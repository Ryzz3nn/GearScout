// GearScout / tools/extract-cmangos-itemmeta.mjs
// Plain Node script, no dependencies (built-in fetch + zlib). Streams the
// CMaNGOS tbc-db content database (a full mangos-tbc server database, patch
// 2.4.3) and emits GearScout/Data/ItemMeta.lua: item quality and equip
// location for every item already tracked in GearScout/Data/ItemDB.lua.
// That file (produced by tools/extract-questie-items.mjs from Questie) has
// no quality or equip location field at all, because Questie's own source
// data does not carry either; this script fills exactly that gap from a
// different, independent source.
//
// Source: https://github.com/cmangos/tbc-db, table `item_template`, file
//   Full_DB/TBCDB_1.11.0_Vengeance_One_A_Cmangos_Story.sql.gz (a single
//   mysqldump, ~17 MB gzipped / ~101 MB decompressed as of writing). The
//   file is fetched fresh over HTTPS and decompressed and parsed as a
//   stream, one INSERT line at a time; the fully decompressed dump is never
//   held in memory at once, only whichever single INSERT statement line is
//   being read (each table's data is one very long line).
//
// item_template column order (read from its own CREATE TABLE statement in
// the dump, not assumed): entry(0), class(1), subclass(2), unk0(3), name(4),
// displayid(5), Quality(6), Flags(7), BuyCount(8), BuyPrice(9),
// SellPrice(10), InventoryType(11), ... Only columns 0, 6 and 11 are used
// here. InventoryType uses the same numeric slot ids as the client's own
// item data (id 10 = Hands, 21 = Main Hand, ...); this was cross checked
// against the Wowhead XML endpoint for several items (see extraction
// report) and matched exactly, so the raw number is kept as-is rather than
// translated to a name, matching how ItemDB.lua keeps class/subclass as
// raw numeric ids instead of strings.
//
// Domain: only item ids already present in ns.ITEM_DB (GearScout/Data/
// ItemDB.lua), which is itself already filtered to equippable weapons and
// armor (class 2 or 4) that carry an item level. Within that set, rows
// whose InventoryType is 0 (not equippable in any slot, e.g. quivers/ammo
// pouches that Questie's own class filter let through) are dropped too, so
// this file only ever describes items that occupy a real equipment slot.
//
// Run with: node tools/extract-cmangos-itemmeta.mjs [path-to-local-sql-or-gz]
// The optional argument points at an already downloaded copy of the dump
// (.sql or .sql.gz) for fast repeated runs while developing; with no
// argument the script fetches the current file from GitHub every run.
// Output: ../GearScout/Data/ItemMeta.lua

import { createReadStream, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createGunzip } from "node:zlib";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { Readable } from "node:stream";
import path from "node:path";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ITEM_DB_FILE = path.join(HERE, "..", "GearScout", "Data", "ItemDB.lua");
const OUT_FILE = path.join(HERE, "..", "GearScout", "Data", "ItemMeta.lua");

const CMANGOS_SQL_GZ_URL =
    "https://raw.githubusercontent.com/cmangos/tbc-db/master/Full_DB/TBCDB_1.11.0_Vengeance_One_A_Cmangos_Story.sql.gz";

const LOCAL_SOURCE = process.argv[2] || null;

// ---------------------------------------------------------------------------
// Step 1: the target item id set, read from the already generated ItemDB.lua.
// ---------------------------------------------------------------------------
function loadTargetItemIds() {
    const text = readFileSync(ITEM_DB_FILE, "utf8");
    const ids = new Set();
    const re = /^\[(\d+)\] = /gm;
    let m;
    while ((m = re.exec(text))) ids.add(parseInt(m[1], 10));
    return ids;
}

// ---------------------------------------------------------------------------
// Step 2: a small paren/quote aware scanner for mysqldump "INSERT INTO
// `table` VALUES (...),(...),...;" lines. mysqldump escapes with backslash
// and doubles nothing, so this only has to track single quoted strings and
// backslash escapes inside them.
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

async function openSource() {
    if (LOCAL_SOURCE) {
        console.log(`Reading local source: ${LOCAL_SOURCE}`);
        const raw = createReadStream(LOCAL_SOURCE);
        return LOCAL_SOURCE.endsWith(".gz") ? raw.pipe(createGunzip()) : raw;
    }
    console.log(`Fetching ${CMANGOS_SQL_GZ_URL}`);
    const res = await fetch(CMANGOS_SQL_GZ_URL);
    if (!res.ok || !res.body) {
        throw new Error(`Fetch failed: ${res.status} ${res.statusText}`);
    }
    const nodeStream = Readable.fromWeb(res.body);
    return nodeStream.pipe(createGunzip());
}

// ---------------------------------------------------------------------------
// Step 3: stream item_template, keep only rows in the target id set with a
// non zero InventoryType.
// ---------------------------------------------------------------------------
const targetIds = loadTargetItemIds();
console.log(`Target item ids from ItemDB.lua: ${targetIds.size}`);

const meta = new Map(); // itemId -> { q, e }
const stats = { totalRows: 0, matched: 0, invTypeZero: 0 };

const stream = await openSource();
const rl = createInterface({ input: stream, crlfDelay: Infinity });
const prefix = "INSERT INTO `item_template`";
for await (const line of rl) {
    if (!line.startsWith(prefix)) continue;
    const rows = parseInsertRows(line);
    for (const row of rows) {
        stats.totalRows++;
        const entry = parseInt(row[0], 10);
        if (!targetIds.has(entry)) continue;
        const invType = parseInt(row[11], 10);
        if (invType === 0) { stats.invTypeZero++; continue; }
        const quality = parseInt(row[6], 10);
        meta.set(entry, { q: quality, e: invType });
        stats.matched++;
    }
}

console.log("--- stats ---");
console.log(JSON.stringify(stats, null, 2));
console.log(`Missing from item_template entirely: ${targetIds.size - stats.matched - stats.invTypeZero}`);

// ---------------------------------------------------------------------------
// Emit GearScout/Data/ItemMeta.lua
// ---------------------------------------------------------------------------
const sortedIds = Array.from(meta.keys()).sort((a, b) => a - b);

const lines = [];
lines.push("-- GearScout / Data/ItemMeta.lua");
lines.push("-- GENERATED FILE. Do not hand edit, changes will be overwritten.");
lines.push("-- Produced by tools/extract-cmangos-itemmeta.mjs from the CMaNGOS tbc-db");
lines.push("-- content database (github.com/cmangos/tbc-db), table item_template.");
lines.push("-- Regenerate with: node tools/extract-cmangos-itemmeta.mjs");
lines.push("--");
lines.push("-- Shape:");
lines.push('--   ns.ITEM_META[itemId] = { q = <quality 0-7>, e = <equip location id> }');
lines.push("--");
lines.push("-- q matches Blizzard's item quality enum (0 poor, 1 common, 2 uncommon,");
lines.push("-- 3 rare, 4 epic, 5 legendary, 6 artifact, 7 heirloom).");
lines.push("-- e matches the client's own inventory type numbering used in item data");
lines.push("-- (1 head, 3 shoulder, 5 chest, 6 waist, 7 legs, 8 feet, 9 wrist, 10 hands,");
lines.push("-- 11 finger, 12 trinket, 13 one-hand weapon, 14 shield, 15 ranged (bow),");
lines.push("-- 16 cloak, 17 two-hand weapon, 20 relic-slot robe, 21 main hand,");
lines.push("-- 22 off hand, 23 holdable, 24 ammo, 26 ranged (gun/thrown), 28 relic);");
lines.push("-- it was cross checked against the Wowhead XML endpoint's inventorySlot");
lines.push("-- id attribute for several items and matched exactly, so the raw number");
lines.push("-- is kept as-is instead of a name string, same choice ItemDB.lua makes");
lines.push("-- for class/subclass.");
lines.push("--");
lines.push("-- Domain is exactly the item ids in ns.ITEM_DB (Data/ItemDB.lua) that also");
lines.push("-- have a non zero InventoryType in item_template, so this file is a direct");
lines.push("-- companion lookup keyed the same way; join on item id, no separate index.");
lines.push("");
lines.push("local ADDON, ns = ...");
lines.push("");
lines.push("ns.ITEM_META = {");
for (const id of sortedIds) {
    const e = meta.get(id);
    lines.push(`[${id}] = { q = ${e.q}, e = ${e.e} },`);
}
lines.push("}");
lines.push("");

mkdirSync(path.dirname(OUT_FILE), { recursive: true });
writeFileSync(OUT_FILE, lines.join("\n"), "utf8");

console.log(`Wrote ${OUT_FILE}`);
console.log(`Items with quality + equip location: ${meta.size}`);
