// GearScout / tools/extract-questie-items.mjs
// Plain Node script, no dependencies. Reads Questie's TBC item database off disk
// and emits GearScout/Data/ItemDB.lua: a single compact, static table mapping
// item id -> item level, required level, class id and subclass id. The shipped
// addon never talks to Questie at runtime; this script is the only place that
// dependency exists, and only at build time. It exists because the addon's own
// live item scan only sees items the player's client happens to have cached,
// so gear comparisons (e.g. "what beats your current head slot") are patchy
// for anything the player has not personally seen. A shipped table fixes that.
//
// Source structure (read from the file below, not guessed):
//   QuestieDB.itemKeys = { ['name'] = 1, ['npcDrops'] = 2, ... } defines the
//   positional order of the per-item array. This script reads that table
//   rather than hardcoding the order, in case a future Questie release
//   reorders it.
//   QuestieDB.itemData = [[return { [id] = {<positional values>}, ... } ]]
//   is a long-bracket Lua string (loaded with loadstring at Questie's own
//   runtime, never executed as code here). Each entry is a Lua array literal;
//   missing values are the bare word `nil`, strings are single quoted with
//   backslash-escaped apostrophes (e.g. 'Recruit\'s Shirt'), and some fields
//   are themselves array literals (e.g. npcDrops = {19994,21382,23324}).
//
// Only Database/TBC/tbcItemDB.lua is read. Database/Classic and Database/Wrath
// hold the same item ids with different era values (different item level,
// required level, etc for items that changed between expansions) and must
// never be substituted here.
//
// Run with: node tools/extract-questie-items.mjs
// Output:   ../GearScout/Data/ItemDB.lua

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT_FILE = path.join(HERE, "..", "GearScout", "Data", "ItemDB.lua");

const SOURCE_FILE = "D:/World of Warcraft/_anniversary_/Interface/AddOns/Questie/Database/TBC/tbcItemDB.lua";

// WoW item class ids (ITEM_CLASS_*). Only these two classes are equippable
// gear; everything else (consumables, containers, gems, reagents, quest
// items, recipes, money, keys, glyphs, ...) is not useful for a gear
// comparison table and is dropped below.
const CLASS_WEAPON = 2;
const CLASS_ARMOR = 4;

// ---------------------------------------------------------------------------
// Minimal quote and brace aware Lua scanning helpers. We do not need a full
// Lua parser: itemData is a flat, regular sequence of array literals, so
// tracking single/double quoted string state (with backslash escapes) while
// counting braces is sufficient to correctly segment it. This is the same
// approach tools/extract-atlasloot.mjs uses, adapted for single quoted
// strings (Questie uses those; AtlasLoot uses double quoted ones).
// ---------------------------------------------------------------------------

function skipString(text, i, quote) {
    const n = text.length;
    i++; // past opening quote
    while (i < n && text[i] !== quote) {
        if (text[i] === "\\") i++;
        i++;
    }
    return i + 1; // past closing quote
}

// Returns the index of the '}' matching the '{' at openIdx, skipping over
// string literals so braces inside them do not affect the depth count.
function findMatchingBrace(text, openIdx) {
    let depth = 0;
    let i = openIdx;
    const n = text.length;
    while (i < n) {
        const c = text[i];
        if (c === "'" || c === '"') {
            i = skipString(text, i, c);
            continue;
        }
        if (c === "{") {
            depth++;
            i++;
            continue;
        }
        if (c === "}") {
            depth--;
            i++;
            if (depth === 0) return i - 1;
            continue;
        }
        i++;
    }
    return -1;
}

// Splits the inner content of an array literal into its top level, comma
// separated fields, ignoring commas nested inside strings or nested tables
// (e.g. the npcDrops = {1,2,3} field).
function splitTopLevel(text) {
    const parts = [];
    let depth = 0;
    let start = 0;
    let i = 0;
    const n = text.length;
    while (i < n) {
        const c = text[i];
        if (c === "'" || c === '"') {
            i = skipString(text, i, c);
            continue;
        }
        if (c === "{") {
            depth++;
            i++;
            continue;
        }
        if (c === "}") {
            depth--;
            i++;
            continue;
        }
        if (c === "," && depth === 0) {
            parts.push(text.slice(start, i));
            i++;
            start = i;
            continue;
        }
        i++;
    }
    if (start < n) parts.push(text.slice(start, n));
    return parts.map((s) => s.trim());
}

// Decodes a single field value: nil, a number, a single/double quoted Lua
// string, or a nested table literal (returned as the raw source text since
// none of the fields this script keeps are tables).
function decodeScalar(raw) {
    if (raw === "nil" || raw === "") return undefined;
    if (raw[0] === "'" || raw[0] === '"') {
        const quote = raw[0];
        const inner = raw.slice(1, -1);
        const chars = [];
        for (let i = 0; i < inner.length; i++) {
            if (inner[i] === "\\" && i + 1 < inner.length) {
                i++;
                chars.push(inner[i]);
            } else {
                chars.push(inner[i]);
            }
        }
        return chars.join("");
    }
    const num = Number(raw);
    return Number.isNaN(num) ? undefined : num;
}

// ---------------------------------------------------------------------------
// Read source, locate the itemKeys and itemData tables.
// ---------------------------------------------------------------------------

const src = readFileSync(SOURCE_FILE, "utf8");

const keysMarker = "QuestieDB.itemKeys = {";
const keysStart = src.indexOf(keysMarker);
if (keysStart === -1) throw new Error("QuestieDB.itemKeys not found in source");
const keysBraceStart = keysStart + keysMarker.length - 1;
const keysBraceEnd = findMatchingBrace(src, keysBraceStart);
if (keysBraceEnd === -1) throw new Error("unbalanced braces in QuestieDB.itemKeys");
const keysBody = src.slice(keysBraceStart + 1, keysBraceEnd);

// itemKeys is read from the source, not assumed: build fieldName -> 1-based
// position from the actual ['name'] = N, entries.
const keyIndex = {};
const keyEntryRe = /\[\s*'([^']+)'\s*\]\s*=\s*(\d+)/g;
let km;
while ((km = keyEntryRe.exec(keysBody))) {
    keyIndex[km[1]] = parseInt(km[2], 10);
}
const requiredKeys = ["name", "itemLevel", "requiredLevel", "class", "subClass"];
for (const k of requiredKeys) {
    if (!(k in keyIndex)) throw new Error(`QuestieDB.itemKeys is missing expected key "${k}"`);
}
console.log("itemKeys order read from source:", JSON.stringify(keyIndex));

const dataMarker = "QuestieDB.itemData = [[return {";
const dataStart = src.indexOf(dataMarker);
if (dataStart === -1) throw new Error("QuestieDB.itemData not found in source");
const bodyStart = dataStart + dataMarker.length; // just past the opening '{'
const closeMarker = "}]]";
const bodyEndOuterBrace = src.lastIndexOf(closeMarker);
if (bodyEndOuterBrace === -1) throw new Error("closing }]] of QuestieDB.itemData not found");
const dataBody = src.slice(bodyStart, bodyEndOuterBrace);

// ---------------------------------------------------------------------------
// Walk every [id] = {...} entry.
// ---------------------------------------------------------------------------

const stats = {
    itemsSeen: 0,
    droppedNoItemLevel: 0,
    droppedNotWeaponOrArmor: 0,
    kept: 0,
};

const kept = new Map(); // itemId -> { i, r, c, s, n }

const entryRe = /\[(\d+)\]\s*=\s*\{/g;
let em;
while ((em = entryRe.exec(dataBody))) {
    stats.itemsSeen++;
    const itemId = parseInt(em[1], 10);
    const braceStart = em.index + em[0].length - 1;
    const braceEnd = findMatchingBrace(dataBody, braceStart);
    if (braceEnd === -1) {
        console.warn(`[warn] unbalanced braces for item ${itemId}`);
        continue;
    }
    const rowText = dataBody.slice(braceStart + 1, braceEnd);
    entryRe.lastIndex = braceEnd + 1;

    const fields = splitTopLevel(rowText);
    const get = (key) => decodeScalar(fields[keyIndex[key] - 1]);

    const itemLevel = get("itemLevel");
    const requiredLevel = get("requiredLevel");
    const classId = get("class");
    const subClassId = get("subClass");
    const name = get("name");

    if (!itemLevel || itemLevel <= 0) {
        stats.droppedNoItemLevel++;
        continue;
    }
    if (classId !== CLASS_WEAPON && classId !== CLASS_ARMOR) {
        stats.droppedNotWeaponOrArmor++;
        continue;
    }

    kept.set(itemId, {
        i: itemLevel,
        r: requiredLevel || 0,
        c: classId,
        s: subClassId || 0,
        n: name,
    });
    stats.kept++;
}

// ---------------------------------------------------------------------------
// Emit GearScout/Data/ItemDB.lua
// ---------------------------------------------------------------------------

function luaString(s) {
    // House style bans em/en dashes everywhere, including generated data;
    // strip them defensively even though no source item name is expected
    // to carry one.
    return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/[\u2013\u2014]/g, "-") + '"';
}

const sortedIds = Array.from(kept.keys()).sort((a, b) => a - b);

// Names roughly double the file size (see report), and every caller already
// has the item id plus, for anything currently in a player's bags/gear, the
// live client's own GetItemInfo name. The one caller that does not have a
// name handy is a dungeon loot lookup, and DungeonLoot.lua already ships its
// own item ids with no name either, so names are left out here too.
const INCLUDE_NAMES = false;

function buildLines(includeNames) {
    const lines = [];
    lines.push("-- GearScout / Data/ItemDB.lua");
    lines.push("-- GENERATED FILE. Do not hand edit, changes will be overwritten.");
    lines.push("-- Produced by tools/extract-questie-items.mjs from Questie's TBC item database");
    lines.push("-- (Questie/Database/TBC/tbcItemDB.lua), so gear comparisons work for items the");
    lines.push("-- player's own client has never cached.");
    lines.push("-- Regenerate with: node tools/extract-questie-items.mjs");
    lines.push("--");
    lines.push("-- Shape:");
    if (includeNames) {
        lines.push('--   ns.ITEM_DB[itemId] = { i = <item level>, r = <required level>, c = <class id>,');
        lines.push('--                          s = <subclass id>, n = "<item name>" }');
    } else {
        lines.push('--   ns.ITEM_DB[itemId] = { i = <item level>, r = <required level>, c = <class id>,');
        lines.push("--                          s = <subclass id> }");
    }
    lines.push("--");
    lines.push("-- Only equippable gear is included (class id 2 = weapon, 4 = armor) and only");
    lines.push("-- items that carry an item level; everything else (consumables, quest items,");
    lines.push("-- reagents, recipes, containers, ...) is useless for a gear comparison table");
    lines.push("-- and would only add dead weight to every user's download. Item quality and");
    lines.push("-- equip location are not in the source data and are not invented here; the");
    lines.push("-- addon reads those live from the client for anything it evaluates.");
    lines.push("--");
    lines.push("-- Field names are single letters to keep the file small, matching DungeonLoot.lua.");
    lines.push("");
    lines.push("local ADDON, ns = ...");
    lines.push("");
    lines.push("ns.ITEM_DB = {");
    for (const id of sortedIds) {
        const e = kept.get(id);
        if (includeNames) {
            lines.push(`[${id}] = { i = ${e.i}, r = ${e.r}, c = ${e.c}, s = ${e.s}, n = ${luaString(e.n)} },`);
        } else {
            lines.push(`[${id}] = { i = ${e.i}, r = ${e.r}, c = ${e.c}, s = ${e.s} },`);
        }
    }
    lines.push("}");
    lines.push("");
    return lines.join("\n");
}

const withNames = buildLines(true);
const withoutNames = buildLines(false);
console.log(`Size with names:    ${(Buffer.byteLength(withNames, "utf8") / 1024).toFixed(1)} KB`);
console.log(`Size without names: ${(Buffer.byteLength(withoutNames, "utf8") / 1024).toFixed(1)} KB`);

const output = INCLUDE_NAMES ? withNames : withoutNames;

mkdirSync(path.dirname(OUT_FILE), { recursive: true });
writeFileSync(OUT_FILE, output, "utf8");

console.log(`Wrote ${OUT_FILE} (names ${INCLUDE_NAMES ? "included" : "excluded"})`);
console.log(`Final size: ${(Buffer.byteLength(output, "utf8") / 1024).toFixed(1)} KB`);
console.log("--- stats ---");
console.log(JSON.stringify(stats, null, 2));
