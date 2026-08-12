// GearScout / tools/extract-droprates.mjs
// Plain Node script, no dependencies (built-in fetch + zlib). Emits
// GearScout/Data/DropRates.lua: real drop chance percentages per item id,
// naming the creature, for items already tracked in GearScout/Data/
// DungeonLoot.lua (produced by tools/extract-atlasloot.mjs).
//
// Two independent sources, used in this priority order per item:
//
// SOURCE A (preferred): AtlasLoot Classic's own droprate.lua, read straight
// off disk from the same installed addon extract-atlasloot.mjs already
// reads. Its DropRateData table is keyed [npcId][itemId] = percent (see
// AtlasLootClassic/Data/Droprate.lua's own comment: "--[npcID] = { itemID =
// dropRate }"), and its values are Wowhead's own crowd sourced, empirically
// observed drop percentages, not a database's nominal weight. Item -> npcId
// comes from the npcID field already present on each boss entry in
// data.lua / data-tbc.lua (the same files extract-atlasloot.mjs reads),
// cross joined against droprate.lua by item id. Verified for one entry
// against a live in game tooltip during this extraction (Sneed, item 5195,
// 67.32%, matched exactly) and against creature_template in the source
// below (Sneed = npc id 643 in both, independently).
//
// LIMITATION (checked, not assumed): droprate.lua only covers Classic
// dungeon and raid bosses. Its 295 outer npc ids have zero overlap with the
// ~200 distinct npc ids referenced by TBC boss entries in data-tbc.lua, so
// it contributes nothing for actual Burning Crusade content. This is the
// single biggest gap in this file; see the extraction report for why a
// second, TBC covering source could not be added safely (grouped loot, below).
//
// SOURCE B (fallback, items source A has nothing for): the CMaNGOS tbc-db
// content database (github.com/cmangos/tbc-db), tables `creature_loot_template`
// and `creature_template`. Only rows where `groupid` = 0 are used: reading
// mangos-tbc's own LootMgr.cpp (LootTemplate::LootGroup::Roll) shows that
// for groupid != 0 rows, ChanceOrQuestChance is a weight in a single
// weighted pick among that group's items (exactly one group member can win
// a given loot roll), not an independent percentage, and a spot check
// against source A disagreed sharply for a grouped item (Buzzer Blade,
// item 2169: 90 in the grouped DB row vs 52.23%% empirically in droprate.lua)
// while groupid = 0 rows are plain independent percentages with no such
// transform. Since most named boss loot in this database is grouped,
// keeping only groupid = 0 rows means source B mostly contributes trash
// and reagent drops, not boss gear; see the report for the exact TBC
// coverage number this leaves.
//
// creature_loot_template columns (read from its own CREATE TABLE, not
// assumed): entry(0), item(1), ChanceOrQuestChance(2), groupid(3),
// mincountOrRef(4), maxcount(5), condition_id(6), comments(7).
// creature_template columns (relevant ones): Entry(0), Name(1), ...
// LootId(68). A creature's own loot table is keyed by LootId, which for
// 6112 of 6132 creatures with any loot equals their own Entry; the 20 that
// borrow another creature's loot table are not resolved to a name here, so
// this script matches creature_loot_template.entry directly against
// creature_template.Entry rather than walking the LootId indirection.
//
// Run with: node tools/extract-droprates.mjs [path-to-local-sql-or-gz]
// The optional argument points at an already downloaded copy of the
// cmangos dump (.sql or .sql.gz) for fast repeated runs while developing;
// with no argument the script fetches the current file from GitHub.
// Output: ../GearScout/Data/DropRates.lua

import { createReadStream, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createGunzip } from "node:zlib";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { Readable } from "node:stream";
import path from "node:path";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DUNGEON_LOOT_FILE = path.join(HERE, "..", "GearScout", "Data", "DungeonLoot.lua");
const OUT_FILE = path.join(HERE, "..", "GearScout", "Data", "DropRates.lua");

const WOW_ADDONS = "D:/World of Warcraft/_anniversary_/Interface/AddOns/AtlasLootClassic_DungeonsAndRaids";
const ATLASLOOT_SOURCES = [
    path.join(WOW_ADDONS, "data.lua"),
    path.join(WOW_ADDONS, "data-tbc.lua"),
];
const DROPRATE_FILE = path.join(WOW_ADDONS, "droprate.lua");

const CMANGOS_SQL_GZ_URL =
    "https://raw.githubusercontent.com/cmangos/tbc-db/master/Full_DB/TBCDB_1.11.0_Vengeance_One_A_Cmangos_Story.sql.gz";

const LOCAL_SOURCE = process.argv[2] || null;
const MAX_SOURCES_PER_ITEM = 5;

// ---------------------------------------------------------------------------
// Shared Lua scanning helpers (same approach as tools/extract-atlasloot.mjs;
// duplicated here rather than imported since that script is not to be
// edited and does not export them).
// ---------------------------------------------------------------------------
function findMatchingBrace(text, openIdx) {
    let depth = 0, i = openIdx;
    const n = text.length;
    while (i < n) {
        const c = text[i];
        if (c === '"') { i++; while (i < n && text[i] !== '"') { if (text[i] === "\\") i++; i++; } i++; continue; }
        if (c === "-" && text[i + 1] === "-") { let j = text.indexOf("\n", i); if (j === -1) j = n; i = j; continue; }
        if (c === "{") { depth++; i++; continue; }
        if (c === "}") { depth--; i++; if (depth === 0) return i - 1; continue; }
        i++;
    }
    return -1;
}
// A `--` line comment has no comma of its own, so a comment labelling a
// section inside a table sticks to the front of the entry after it and that
// entry stops looking like a table constructor to the callers below. Same
// fault, same fix as tools/extract-atlasloot.mjs.
function stripLeadingComments(text) {
    let s = text;
    while (s.startsWith("--")) {
        const nl = s.indexOf("\n");
        if (nl === -1) return "";
        s = s.slice(nl + 1).trim();
    }
    return s;
}
function splitTopLevel(text) {
    const parts = [];
    let depth = 0, start = 0, i = 0;
    const n = text.length;
    while (i < n) {
        const c = text[i];
        if (c === '"') { i++; while (i < n && text[i] !== '"') { if (text[i] === "\\") i++; i++; } i++; continue; }
        if (c === "-" && text[i + 1] === "-") { let j = text.indexOf("\n", i); if (j === -1) j = n; i = j; continue; }
        if (c === "{") { depth++; i++; continue; }
        if (c === "}") { depth--; i++; continue; }
        if (c === "," && depth === 0) { parts.push(text.slice(start, i)); i++; start = i; continue; }
        i++;
    }
    if (start < n) parts.push(text.slice(start, n));
    return parts.map((s) => stripLeadingComments(s.trim())).filter((s) => s.length > 0);
}
function findDataBlocks(fileText) {
    const blocks = [];
    const re = /data\[\s*"([^"]+)"\s*\]\s*=\s*\{/g;
    let m;
    while ((m = re.exec(fileText))) {
        const braceStart = fileText.indexOf("{", m.index);
        const braceEnd = findMatchingBrace(fileText, braceStart);
        if (braceEnd === -1) continue;
        blocks.push({ body: fileText.slice(braceStart + 1, braceEnd) });
    }
    return blocks;
}
function extractItemsBody(body) {
    const idx = body.search(/items\s*=\s*\{/);
    if (idx === -1) return null;
    const braceStart = body.indexOf("{", idx);
    const braceEnd = findMatchingBrace(body, braceStart);
    if (braceEnd === -1) return null;
    return body.slice(braceStart + 1, braceEnd);
}
const ITEM_ROW_RE = /^[ \t]*\{\s*-?\d+\s*,\s*(\d+)\s*[^{}]*\}[ \t]*,?[ \t]*(?:--[ \t]*(.*))?$/gm;

// ---------------------------------------------------------------------------
// Step 1: target item id domain = whatever DungeonLoot.lua already ships.
// ---------------------------------------------------------------------------
function loadTargetItemIds() {
    const text = readFileSync(DUNGEON_LOOT_FILE, "utf8");
    const ids = new Set();
    const re = /^\[(\d+)\] = /gm;
    let m;
    while ((m = re.exec(text))) ids.add(parseInt(m[1], 10));
    return ids;
}

// ---------------------------------------------------------------------------
// Step 2: item id -> [{ npcIds, boss }] from data.lua / data-tbc.lua. Every
// boss entry that carries an npcID field (single number or an array of
// several, one per difficulty/faction variant of the same boss) is kept
// alongside the item ids inside that entry.
// ---------------------------------------------------------------------------
function loadItemToNpcBoss() {
    const itemToNpcBoss = new Map();
    for (const file of ATLASLOOT_SOURCES) {
        const fileText = readFileSync(file, "utf8");
        for (const { body } of findDataBlocks(fileText)) {
            const itemsBody = extractItemsBody(body);
            if (!itemsBody) continue;
            for (const segment of splitTopLevel(itemsBody)) {
                if (!segment.startsWith("{")) continue;
                const nameMatch = segment.match(/name\s*=\s*AL\[\s*"([^"]*)"\s*\]/);
                const bossName = nameMatch ? nameMatch[1] : null;
                if (!bossName) continue;
                const npcMatch = segment.match(/npcID\s*=\s*(\{[^}]*\}|\d+)/);
                if (!npcMatch) continue;
                const npcIds = npcMatch[1].startsWith("{")
                    ? npcMatch[1].slice(1, -1).split(",").map((s) => parseInt(s.trim(), 10)).filter((n) => !Number.isNaN(n))
                    : [parseInt(npcMatch[1], 10)];
                ITEM_ROW_RE.lastIndex = 0;
                let rowMatch;
                while ((rowMatch = ITEM_ROW_RE.exec(segment))) {
                    const itemId = parseInt(rowMatch[1], 10);
                    if (!itemToNpcBoss.has(itemId)) itemToNpcBoss.set(itemId, []);
                    itemToNpcBoss.get(itemId).push({ npcIds, boss: bossName });
                }
            }
        }
    }
    return itemToNpcBoss;
}

// ---------------------------------------------------------------------------
// Step 3: droprate.lua -> Map(npcId -> Map(itemId -> percent)).
// ---------------------------------------------------------------------------
function loadDropRateData() {
    const text = readFileSync(DROPRATE_FILE, "utf8");
    const startIdx = text.indexOf("local DropRateData = {");
    if (startIdx === -1) throw new Error("droprate.lua: could not find 'local DropRateData = {'");
    const braceStart = text.indexOf("{", startIdx);
    const braceEnd = findMatchingBrace(text, braceStart);
    const body = text.slice(braceStart + 1, braceEnd);
    const data = new Map();
    for (const entrySeg of splitTopLevel(body)) {
        const km = entrySeg.match(/^\[(\d+)\]\s*=\s*\{/);
        if (!km) continue;
        const npcId = parseInt(km[1], 10);
        const innerStart = entrySeg.indexOf("{");
        const innerEnd = findMatchingBrace(entrySeg, innerStart);
        const innerBody = entrySeg.slice(innerStart + 1, innerEnd);
        const inner = new Map();
        for (const pairSeg of splitTopLevel(innerBody)) {
            const pm = pairSeg.match(/^\[(\d+)\]\s*=\s*([\d.]+)/);
            if (pm) inner.set(parseInt(pm[1], 10), parseFloat(pm[2]));
        }
        data.set(npcId, inner);
    }
    return data;
}

// ---------------------------------------------------------------------------
// SQL streaming helpers for the cmangos fallback.
// ---------------------------------------------------------------------------
function parseInsertRows(line) {
    const valuesIdx = line.indexOf("VALUES ");
    const s = line.slice(valuesIdx + 7);
    const rows = [];
    let i = 0;
    const n = s.length;
    while (i < n) {
        while (i < n && s[i] !== "(") i++;
        if (i >= n) break;
        i++;
        const row = [];
        let field = "";
        let inStr = false;
        while (i < n) {
            const c = s[i];
            if (inStr) {
                if (c === "\\") { field += c + s[i + 1]; i += 2; continue; }
                if (c === "'") { inStr = false; field += c; i++; continue; }
                field += c; i++; continue;
            }
            if (c === "'") { inStr = true; field += c; i++; continue; }
            if (c === ",") { row.push(field); field = ""; i++; continue; }
            if (c === ")") { row.push(field); i++; break; }
            field += c; i++;
        }
        rows.push(row);
        while (i < n && s[i] !== "(" && s[i] !== ";") i++;
    }
    return rows;
}
function unquote(f) {
    f = f.trim();
    if (f.startsWith("'") && f.endsWith("'")) return f.slice(1, -1).replace(/\\'/g, "'").replace(/\\\\/g, "\\");
    return f;
}
async function openSource() {
    if (LOCAL_SOURCE) {
        console.log(`Reading local source: ${LOCAL_SOURCE}`);
        const raw = createReadStream(LOCAL_SOURCE);
        return LOCAL_SOURCE.endsWith(".gz") ? raw.pipe(createGunzip()) : raw;
    }
    console.log(`Fetching ${CMANGOS_SQL_GZ_URL}`);
    const res = await fetch(CMANGOS_SQL_GZ_URL);
    if (!res.ok || !res.body) throw new Error(`Fetch failed: ${res.status} ${res.statusText}`);
    return Readable.fromWeb(res.body).pipe(createGunzip());
}

// ---------------------------------------------------------------------------
// Build source A hits.
// ---------------------------------------------------------------------------
const targetIds = loadTargetItemIds();
console.log(`Target item ids from DungeonLoot.lua: ${targetIds.size}`);

const itemToNpcBoss = loadItemToNpcBoss();
const dropRateData = loadDropRateData();
console.log(`droprate.lua npc entries: ${dropRateData.size}`);

const hits = new Map(); // itemId -> [{ creature, chance }]
let atlasRows = 0;
for (const itemId of targetIds) {
    const bossEntries = itemToNpcBoss.get(itemId);
    if (!bossEntries) continue;
    for (const { npcIds, boss } of bossEntries) {
        for (const npcId of npcIds) {
            const perItem = dropRateData.get(npcId);
            if (perItem && perItem.has(itemId)) {
                if (!hits.has(itemId)) hits.set(itemId, []);
                hits.get(itemId).push({ creature: boss, chance: perItem.get(itemId) });
                atlasRows++;
            }
        }
    }
}
console.log(`Source A (AtlasLoot droprate.lua) hits: ${hits.size} items, ${atlasRows} rows`);

// ---------------------------------------------------------------------------
// Build source B hits (cmangos, groupid = 0 only) for items source A missed.
// ---------------------------------------------------------------------------
const remainingIds = new Set([...targetIds].filter((id) => !hits.has(id)));
console.log(`Remaining ids for cmangos fallback: ${remainingIds.size}`);

const creatureNameByEntry = new Map();
let stream = await openSource();
let rl = createInterface({ input: stream, crlfDelay: Infinity });
for await (const line of rl) {
    if (!line.startsWith("INSERT INTO `creature_template`")) continue;
    for (const row of parseInsertRows(line)) creatureNameByEntry.set(parseInt(row[0], 10), unquote(row[1]));
}
console.log(`creature_template names loaded: ${creatureNameByEntry.size}`);

const cmangosStats = { rowsSeen: 0, grouped: 0, noName: 0, kept: 0 };
stream = await openSource();
rl = createInterface({ input: stream, crlfDelay: Infinity });
for await (const line of rl) {
    if (!line.startsWith("INSERT INTO `creature_loot_template`")) continue;
    for (const row of parseInsertRows(line)) {
        const itemId = parseInt(row[1], 10);
        if (!remainingIds.has(itemId)) continue;
        cmangosStats.rowsSeen++;
        const groupid = parseInt(row[3], 10);
        if (groupid !== 0) { cmangosStats.grouped++; continue; }
        const entry = parseInt(row[0], 10);
        const name = creatureNameByEntry.get(entry);
        if (!name) { cmangosStats.noName++; continue; }
        const chance = parseFloat(row[2]);
        if (!hits.has(itemId)) hits.set(itemId, []);
        hits.get(itemId).push({ creature: name, chance });
        cmangosStats.kept++;
    }
}
console.log("Source B (cmangos, groupid = 0) stats:", JSON.stringify(cmangosStats));
console.log(`Total items covered: ${hits.size} of ${targetIds.size} (${(hits.size / targetIds.size * 100).toFixed(1)}%)`);

// ---------------------------------------------------------------------------
// Cap and sort each item's source list, highest chance first.
// ---------------------------------------------------------------------------
let totalRows = 0;
for (const [itemId, arr] of hits) {
    arr.sort((a, b) => b.chance - a.chance);
    if (arr.length > MAX_SOURCES_PER_ITEM) arr.length = MAX_SOURCES_PER_ITEM;
    totalRows += arr.length;
}
console.log(`Total output rows after cap (${MAX_SOURCES_PER_ITEM}/item): ${totalRows}`);

// ---------------------------------------------------------------------------
// Emit GearScout/Data/DropRates.lua
// ---------------------------------------------------------------------------
function luaString(s) {
    return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/[\u2013\u2014]/g, "-") + '"';
}

const sortedIds = Array.from(hits.keys()).sort((a, b) => a - b);

const lines = [];
lines.push("-- GearScout / Data/DropRates.lua");
lines.push("-- GENERATED FILE. Do not hand edit, changes will be overwritten.");
lines.push("-- Produced by tools/extract-droprates.mjs from two sources:");
lines.push("--   A. AtlasLoot Classic's droprate.lua (AtlasLootClassic_DungeonsAndRaids),");
lines.push("--      Wowhead's own crowd sourced drop percentages, Classic content only.");
lines.push("--   B. CMaNGOS tbc-db (github.com/cmangos/tbc-db), creature_loot_template");
lines.push("--      rows with groupid = 0 only (see script header for why grouped rows");
lines.push("--      are excluded); used only for items source A has nothing for.");
lines.push("-- Regenerate with: node tools/extract-droprates.mjs");
lines.push("--");
lines.push("-- Shape:");
lines.push('--   ns.DROP_RATES[itemId] = { { c = "<creature name>", p = <percent> }, ... }');
lines.push("--");
lines.push("-- Sorted highest chance first, capped at " + MAX_SOURCES_PER_ITEM + " sources per item.");
lines.push("-- Coverage is partial: only " + sortedIds.length + " of the " + targetIds.size +
    " item ids in Data/DungeonLoot.lua have a real percentage available from either");
lines.push("-- source; see the extraction report for the exact Classic/TBC coverage split");
lines.push("-- and why most Burning Crusade boss loot could not be included.");
lines.push("");
lines.push("local ADDON, ns = ...");
lines.push("");
lines.push("ns.DROP_RATES = {");
for (const id of sortedIds) {
    const arr = hits.get(id);
    const parts = arr.map((e) => `{ c = ${luaString(e.creature)}, p = ${e.chance} }`);
    lines.push(`[${id}] = { ${parts.join(", ")} },`);
}
lines.push("}");
lines.push("");

mkdirSync(path.dirname(OUT_FILE), { recursive: true });
writeFileSync(OUT_FILE, lines.join("\n"), "utf8");

console.log(`Wrote ${OUT_FILE}`);
