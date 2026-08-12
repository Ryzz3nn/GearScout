#!/usr/bin/env node
// GearScout / tools/export-session.mjs
// Plain Node, no dependencies. Reads the GearScoutData table out of the
// player's SavedVariables file, parses that Lua table into JSON, and
// upserts it into Turso over Turso's HTTP pipeline API (a libsql:// URL
// becomes https://<host>/v2/pipeline, POSTed with a Bearer token; verified
// by hand against the real database before this script was written).
//
// Credentials are never hardcoded and never taken as a command line
// argument. They come from the environment as TURSO_URL and TURSO_TOKEN,
// which on this machine are fetched with:
//   node C:\Users\Ryzz3nn\.secrets\get.mjs turso.url
//   node C:\Users\Ryzz3nn\.secrets\get.mjs turso.token
//
// Usage:
//   node export-session.mjs [--dry-run] [--in <path>] [--out <path>]
//
// --dry-run writes the parsed JSON to a local file and uploads nothing.
// It is also the automatic behaviour, with or without the flag, whenever
// TURSO_URL or TURSO_TOKEN is not set in the environment.

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));

const DEFAULT_INPUT =
    "D:\\World of Warcraft\\_anniversary_\\WTF\\Account\\459579675#1\\SavedVariables\\GearScout.lua";
const DEFAULT_OUTPUT = path.join(HERE, "session-export.json");
const SCHEMA_FILE = path.join(HERE, "schema.sql");

// ---------------------------------------------------------------------------
// arguments
// ---------------------------------------------------------------------------
function parseArgs(argv) {
    const args = { dryRun: false, in: DEFAULT_INPUT, out: DEFAULT_OUTPUT };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === "--dry-run") args.dryRun = true;
        else if (a === "--in") args.in = argv[++i];
        else if (a === "--out") args.out = argv[++i];
        else throw new Error(`unknown argument: ${a}`);
    }
    return args;
}

// ---------------------------------------------------------------------------
// a focused Lua table parser
// WoW's SavedVariables writer only ever produces:
//   Name = <value>
// repeated at the top level, where <value> is a string, number, boolean,
// nil, or a table of `[key] = value,` entries (every entry, including the
// last, ends with a comma; keys are always bracketed, never bare words).
// Anything outside that shape is unexpected and raises rather than being
// dropped silently.
// ---------------------------------------------------------------------------
class LuaParseError extends Error {}

function tokenize(src) {
    const tokens = [];
    let i = 0;
    const n = src.length;
    while (i < n) {
        const c = src[i];
        if (c === " " || c === "\t" || c === "\r" || c === "\n") { i++; continue; }
        if (c === "-" && src[i + 1] === "-") {
            while (i < n && src[i] !== "\n") i++;
            continue;
        }
        if (c === "{" || c === "}" || c === "[" || c === "]" || c === "=" || c === ",") {
            tokens.push({ type: c, pos: i });
            i++;
            continue;
        }
        if (c === '"') {
            let j = i + 1;
            let out = "";
            const simple = { n: "\n", t: "\t", r: "\r", '"': '"', "\\": "\\", "'": "'" };
            while (j < n && src[j] !== '"') {
                if (src[j] === "\\") {
                    const esc = src[j + 1];
                    if (esc === undefined) throw new LuaParseError(`unterminated string at ${i}`);
                    if (esc in simple) { out += simple[esc]; j += 2; continue; }
                    if (esc >= "0" && esc <= "9") {
                        let d = "";
                        let k = j + 1;
                        while (k < n && d.length < 3 && src[k] >= "0" && src[k] <= "9") { d += src[k]; k++; }
                        out += String.fromCharCode(parseInt(d, 10));
                        j = k;
                        continue;
                    }
                    throw new LuaParseError(`unknown escape \\${esc} at ${j}`);
                }
                out += src[j];
                j++;
            }
            if (src[j] !== '"') throw new LuaParseError(`unterminated string starting at ${i}`);
            tokens.push({ type: "string", value: out, pos: i });
            i = j + 1;
            continue;
        }
        if (c === "-" || (c >= "0" && c <= "9")) {
            const m = /^-?\d+(\.\d+)?([eE][+-]?\d+)?/.exec(src.slice(i));
            if (!m) throw new LuaParseError(`bad number at ${i}`);
            tokens.push({ type: "number", value: Number(m[0]), pos: i });
            i += m[0].length;
            continue;
        }
        if (/[A-Za-z_]/.test(c)) {
            const m = /^[A-Za-z_][A-Za-z0-9_]*/.exec(src.slice(i));
            tokens.push({ type: "ident", value: m[0], pos: i });
            i += m[0].length;
            continue;
        }
        throw new LuaParseError(`unexpected character ${JSON.stringify(c)} at ${i}`);
    }
    tokens.push({ type: "eof", pos: i });
    return tokens;
}

function parseLuaAssignments(src) {
    const tokens = tokenize(src);
    let p = 0;
    const peek = () => tokens[p];
    const next = () => tokens[p++];
    const expect = (type) => {
        const t = next();
        if (t.type !== type) throw new LuaParseError(`expected '${type}' but got '${t.type}' at ${t.pos}`);
        return t;
    };

    function parseValue() {
        const t = peek();
        if (t.type === "{") return parseTable();
        if (t.type === "string") { next(); return t.value; }
        if (t.type === "number") { next(); return t.value; }
        if (t.type === "ident") {
            next();
            if (t.value === "true") return true;
            if (t.value === "false") return false;
            if (t.value === "nil") return null;
            throw new LuaParseError(`unexpected identifier '${t.value}' at ${t.pos}`);
        }
        throw new LuaParseError(`unexpected token '${t.type}' at ${t.pos}`);
    }

    function parseTable() {
        expect("{");
        const obj = {};
        while (peek().type !== "}") {
            expect("[");
            const keyTok = next();
            let key;
            if (keyTok.type === "string" || keyTok.type === "number") key = keyTok.value;
            else throw new LuaParseError(`bad table key type '${keyTok.type}' at ${keyTok.pos}`);
            expect("]");
            expect("=");
            obj[key] = parseValue();
            if (peek().type === ",") next();
            else if (peek().type !== "}") throw new LuaParseError(`expected ',' or '}' at ${peek().pos}`);
        }
        expect("}");
        return obj;
    }

    const result = {};
    while (peek().type !== "eof") {
        const nameTok = expect("ident");
        expect("=");
        result[nameTok.value] = parseValue();
    }
    return result;
}

// ---------------------------------------------------------------------------
// GearScoutData -> row lists, matching schema.sql exactly. Every field this
// script relies on is checked; anything missing or the wrong type raises
// instead of being coerced or skipped.
// ---------------------------------------------------------------------------
function assertNumber(v, what) {
    if (typeof v !== "number" || Number.isNaN(v)) {
        throw new Error(`expected a number for ${what}, got ${JSON.stringify(v)}`);
    }
    return v;
}

function assertTable(v, what) {
    if (typeof v !== "object" || v === null) {
        throw new Error(`expected a table for ${what}, got ${JSON.stringify(v)}`);
    }
    return v;
}

function buildRows(data) {
    const drops = [];
    const dropsTable = data.drops === undefined ? {} : assertTable(data.drops, "GearScoutData.drops");
    for (const [itemKey, byCreature] of Object.entries(dropsTable)) {
        const itemID = assertNumber(Number(itemKey), `drops key '${itemKey}'`);
        const creatures = assertTable(byCreature, `drops[${itemKey}]`);
        for (const [creatureKey, rec] of Object.entries(creatures)) {
            const npcID = assertNumber(Number(creatureKey), `drops[${itemKey}] creature key '${creatureKey}'`);
            const r = assertTable(rec, `drops[${itemKey}][${creatureKey}]`);
            if (r.t === undefined) throw new Error(`drops[${itemKey}][${creatureKey}] is missing 't'`);
            drops.push({
                item_id: itemID,
                npc_id: npcID,
                zone_id: r.zone === undefined ? null : assertNumber(r.zone, `drops[${itemKey}][${creatureKey}].zone`),
                zone_name: r.zoneName === undefined ? null : String(r.zoneName),
                seen_at: assertNumber(r.t, `drops[${itemKey}][${creatureKey}].t`),
            });
        }
    }

    const items = [];
    const itemsTable = data.items === undefined ? {} : assertTable(data.items, "GearScoutData.items");
    for (const [itemKey, rec] of Object.entries(itemsTable)) {
        const itemID = assertNumber(Number(itemKey), `items key '${itemKey}'`);
        const r = assertTable(rec, `items[${itemKey}]`);
        if (r.t === undefined) throw new Error(`items[${itemKey}] is missing 't'`);
        items.push({
            item_id: itemID,
            ilvl: r.ilvl === undefined ? null : assertNumber(r.ilvl, `items[${itemKey}].ilvl`),
            quality: r.quality === undefined ? null : assertNumber(r.quality, `items[${itemKey}].quality`),
            equip_loc: r.equipLoc === undefined ? null : String(r.equipLoc),
            req_level: r.reqLevel === undefined ? null : assertNumber(r.reqLevel, `items[${itemKey}].reqLevel`),
            seen_at: assertNumber(r.t, `items[${itemKey}].t`),
        });
    }

    const questRewards = [];
    const questTable = data.questRewards === undefined ? {} : assertTable(data.questRewards, "GearScoutData.questRewards");
    for (const [questKey, byItem] of Object.entries(questTable)) {
        const questID = assertNumber(Number(questKey), `questRewards key '${questKey}'`);
        const itemsForQuest = assertTable(byItem, `questRewards[${questKey}]`);
        for (const [itemKey, t] of Object.entries(itemsForQuest)) {
            const itemID = assertNumber(Number(itemKey), `questRewards[${questKey}] item key '${itemKey}'`);
            questRewards.push({
                quest_id: questID,
                item_id: itemID,
                seen_at: assertNumber(t, `questRewards[${questKey}][${itemKey}]`),
            });
        }
    }

    const vendorPrices = [];
    const vendorTable = data.vendorPrices === undefined ? {} : assertTable(data.vendorPrices, "GearScoutData.vendorPrices");
    for (const [itemKey, byVendor] of Object.entries(vendorTable)) {
        const itemID = assertNumber(Number(itemKey), `vendorPrices key '${itemKey}'`);
        const vendors = assertTable(byVendor, `vendorPrices[${itemKey}]`);
        for (const [vendorKey, rec] of Object.entries(vendors)) {
            const npcID = assertNumber(Number(vendorKey), `vendorPrices[${itemKey}] vendor key '${vendorKey}'`);
            const r = assertTable(rec, `vendorPrices[${itemKey}][${vendorKey}]`);
            if (r.price === undefined || r.t === undefined) {
                throw new Error(`vendorPrices[${itemKey}][${vendorKey}] is missing 'price' or 't'`);
            }
            vendorPrices.push({
                item_id: itemID,
                npc_id: npcID,
                price_copper: assertNumber(r.price, `vendorPrices[${itemKey}][${vendorKey}].price`),
                seen_at: assertNumber(r.t, `vendorPrices[${itemKey}][${vendorKey}].t`),
            });
        }
    }

    // Trainer spell ranks. Nested three deep: class, then spell name, then
    // rank. Spell names are localized, so the client's locale is carried on
    // every row to stop two languages overwriting each other.
    const locale = typeof data.locale === "string" && data.locale ? data.locale : "enUS";
    const trainerSpells = [];
    const trainerTable = data.trainerSpells === undefined
        ? {} : assertTable(data.trainerSpells, "GearScoutData.trainerSpells");
    for (const [classFile, bySpell] of Object.entries(trainerTable)) {
        const spells = assertTable(bySpell, `trainerSpells[${classFile}]`);
        for (const [spellName, byRank] of Object.entries(spells)) {
            const ranks = assertTable(byRank, `trainerSpells[${classFile}][${spellName}]`);
            for (const [rankKey, rec] of Object.entries(ranks)) {
                const where = `trainerSpells[${classFile}][${spellName}][${rankKey}]`;
                const r = assertTable(rec, where);
                if (r.level === undefined || r.t === undefined) {
                    throw new Error(`${where} is missing 'level' or 't'`);
                }
                trainerSpells.push({
                    class_file: classFile,
                    spell_name: spellName,
                    rank: assertNumber(Number(rankKey), `${where} rank key`),
                    level_req: assertNumber(r.level, `${where}.level`),
                    client_locale: locale,
                    seen_at: assertNumber(r.t, `${where}.t`),
                });
            }
        }
    }

    return { drops, items, questRewards, vendorPrices, trainerSpells };
}

// ---------------------------------------------------------------------------
// Turso upload
// A libsql:// URL's host is the same host the HTTP pipeline API answers on;
// only the scheme changes. Every statement result in the pipeline response
// comes back with HTTP 200 even on failure, so each result's own `type`
// field has to be checked, not just the response status.
// ---------------------------------------------------------------------------
function toArg(value) {
    if (value === null || value === undefined) return { type: "null" };
    if (typeof value === "number") {
        return Number.isInteger(value) ? { type: "integer", value: String(value) } : { type: "float", value };
    }
    if (typeof value === "string") return { type: "text", value };
    throw new Error(`cannot convert value to a Turso argument: ${JSON.stringify(value)}`);
}

async function tursoPipeline(baseUrl, token, statements) {
    const httpUrl = baseUrl.replace(/^libsql:\/\//, "https://") + "/v2/pipeline";
    const requests = statements.map((stmt) => ({ type: "execute", stmt }));
    requests.push({ type: "close" });

    const res = await fetch(httpUrl, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({ requests }),
    });
    if (!res.ok) {
        throw new Error(`Turso HTTP ${res.status}: ${await res.text()}`);
    }
    const body = await res.json();
    for (let i = 0; i < body.results.length - 1; i++) {
        const r = body.results[i];
        if (r.type === "error") {
            throw new Error(`Turso statement ${i} failed: ${r.error.message} (${r.error.code})`);
        }
    }
    return body;
}

async function execBatched(baseUrl, token, statements, chunkSize = 100) {
    for (let i = 0; i < statements.length; i += chunkSize) {
        await tursoPipeline(baseUrl, token, statements.slice(i, i + chunkSize));
    }
}

async function applySchema(baseUrl, token) {
    // Strip line comments before splitting on ';', since a comment is free
    // to contain punctuation (this file's own comments do) and a naive split
    // on the raw text would cut a statement in the wrong place.
    const withoutComments = readFileSync(SCHEMA_FILE, "utf8")
        .split("\n")
        .map((line) => {
            const at = line.indexOf("--");
            return at === -1 ? line : line.slice(0, at);
        })
        .join("\n");
    const statements = withoutComments
        .split(";")
        .map((s) => s.trim())
        .filter(Boolean)
        .map((sql) => ({ sql }));
    await execBatched(baseUrl, token, statements);
}

async function uploadToTurso(baseUrl, token, rows) {
    console.log("applying schema.sql...");
    await applySchema(baseUrl, token);

    const statements = [];
    for (const r of rows.drops) {
        statements.push({
            sql: "INSERT INTO item_drops (item_id, npc_id, zone_id, zone_name, seen_at) VALUES (?1,?2,?3,?4,?5) " +
                "ON CONFLICT(item_id, npc_id) DO UPDATE SET zone_id=excluded.zone_id, zone_name=excluded.zone_name, seen_at=excluded.seen_at",
            args: [toArg(r.item_id), toArg(r.npc_id), toArg(r.zone_id), toArg(r.zone_name), toArg(r.seen_at)],
        });
    }
    for (const r of rows.items) {
        statements.push({
            sql: "INSERT INTO item_meta (item_id, ilvl, quality, equip_loc, req_level, seen_at) VALUES (?1,?2,?3,?4,?5,?6) " +
                "ON CONFLICT(item_id) DO UPDATE SET ilvl=excluded.ilvl, quality=excluded.quality, equip_loc=excluded.equip_loc, req_level=excluded.req_level, seen_at=excluded.seen_at",
            args: [toArg(r.item_id), toArg(r.ilvl), toArg(r.quality), toArg(r.equip_loc), toArg(r.req_level), toArg(r.seen_at)],
        });
    }
    for (const r of rows.questRewards) {
        statements.push({
            sql: "INSERT INTO quest_rewards (quest_id, item_id, seen_at) VALUES (?1,?2,?3) " +
                "ON CONFLICT(quest_id, item_id) DO UPDATE SET seen_at=excluded.seen_at",
            args: [toArg(r.quest_id), toArg(r.item_id), toArg(r.seen_at)],
        });
    }
    for (const r of rows.vendorPrices) {
        statements.push({
            sql: "INSERT INTO vendor_prices (item_id, npc_id, price_copper, seen_at) VALUES (?1,?2,?3,?4) " +
                "ON CONFLICT(item_id, npc_id) DO UPDATE SET price_copper=excluded.price_copper, seen_at=excluded.seen_at",
            args: [toArg(r.item_id), toArg(r.npc_id), toArg(r.price_copper), toArg(r.seen_at)],
        });
    }

    for (const r of rows.trainerSpells || []) {
        statements.push({
            sql: "INSERT INTO trainer_spells (class_file, spell_name, rank, level_req, client_locale, seen_at) VALUES (?1,?2,?3,?4,?5,?6) " +
                "ON CONFLICT(class_file, spell_name, rank, client_locale) DO UPDATE SET level_req=excluded.level_req, seen_at=excluded.seen_at",
            args: [toArg(r.class_file), toArg(r.spell_name), toArg(r.rank),
                   toArg(r.level_req), toArg(r.client_locale), toArg(r.seen_at)],
        });
    }

    if (statements.length === 0) {
        console.log("no rows to upload (schema applied, nothing else to do)");
        return;
    }
    console.log(`uploading ${statements.length} row(s)...`);
    await execBatched(baseUrl, token, statements);
    console.log("upload complete");
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
async function main() {
    const args = parseArgs(process.argv.slice(2));

    const tursoUrl = process.env.TURSO_URL;
    const tursoToken = process.env.TURSO_TOKEN;
    const missingCreds = !tursoUrl || !tursoToken;
    const dryRun = args.dryRun || missingCreds;

    if (!existsSync(args.in)) {
        console.error(`no SavedVariables file at ${args.in}`);
        process.exitCode = 1;
        return;
    }

    const src = readFileSync(args.in, "utf8");
    let parsed;
    try {
        parsed = parseLuaAssignments(src);
    } catch (err) {
        console.error(`failed to parse ${args.in}: ${err.message}`);
        process.exitCode = 1;
        return;
    }

    const data = parsed.GearScoutData;
    if (data === undefined) {
        console.log(`GearScoutData is not present in ${args.in}. Collector.lua has not saved anything yet, nothing to export.`);
        return;
    }
    assertTable(data, "GearScoutData");

    const rows = buildRows(data);
    const counts = {
        drops: rows.drops.length,
        items: rows.items.length,
        questRewards: rows.questRewards.length,
        vendorPrices: rows.vendorPrices.length,
        trainerSpells: rows.trainerSpells.length,
    };
    // Built from the counts object rather than a fixed list, so a table added
    // later shows up here automatically instead of silently going unreported.
    const summary = Object.entries(counts).map(([k, v]) => `${k}=${v}`).join(" ");
    console.log(`parsed ${args.in}: ${summary}`);

    if (dryRun) {
        const payload = { exportedAt: new Date().toISOString(), source: args.in, ...rows };
        writeFileSync(args.out, JSON.stringify(payload, null, 2));
        console.log(`dry run: wrote ${args.out}, uploaded nothing`);
        if (missingCreds) {
            console.log("TURSO_URL / TURSO_TOKEN not set in the environment, dry run is automatic until both are present");
        }
        return;
    }

    await uploadToTurso(tursoUrl, tursoToken, rows);
}

main().catch((err) => {
    console.error(err.stack || err.message);
    process.exitCode = 1;
});
