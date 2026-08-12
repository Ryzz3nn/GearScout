// GearScout / tools/extract-atlasloot-catalogue.mjs
// Plain Node script, no dependencies. Reads AtlasLoot Classic's own reputation and
// crafting data files off disk and emits GearScout/Data/Catalogue.lua: static tables
// for faction reputation rewards, jewelcrafting gems, permanent gear enchants, leg
// armor and weapon scopes. The shipped addon never talks to AtlasLoot at runtime;
// this script is the only place that dependency exists, and only at build time.
// Sibling of tools/extract-atlasloot.mjs (dungeon/raid loot); reuses the same
// brace/string/comment aware Lua scanning approach and the same AL[...]/GetForVersion
// findings documented there.
//
// Source structure (read from the files below, not guessed):
//   Both AtlasLootClassic_Factions and AtlasLootClassic_Crafting assign
//   data["SomeKey"] = { ... , items = { <category>, <category>, ... } }, exactly
//   like the dungeon/raid data files. Each <category> is a literal table
//   { name = <label expr>, [NORMAL_DIFF] = { <items> }, ... } (occasionally
//   [ALLIANCE_DIFF]/[HORDE_DIFF] instead of [NORMAL_DIFF] for faction-side-locked
//   rewards; item rows are scanned regardless of which of those wraps them, same
//   as the dungeon extractor does for difficulty-keyed arrays).
//   Item rows look like { 2, 18182 }, -- Chromatic Mantle of the Dawn or
//   { 1, "f529rep8" } for a menu header (texture string in the id slot instead of
//   a number); header rows are rejected structurally, same as the dungeon extractor.
//
//   AtlasLoot has no enUS locale file (English is the default), so AL["..."] calls
//   ARE the English string. ALIL["..."] ("IngameLocales") is different: it is a
//   table whose keys are plain English words (Locales/IngameLocales.lua, read to
//   confirm) mapped to Blizzard's localized globals at runtime, with
//   setmetatable(..., { __index = function(t,k) return rawget(t,k) or k end }), so
//   on an unlocalized build (or read statically, as here) ALIL["Exalted"] resolves
//   to the literal key "Exalted". Both are therefore safe to read as literal text.
//
//   Category "name" fields combine these in a few fixed shapes used by this script:
//     - name = ALIL["Exalted"]                        -> reputation standing label
//     - name = ALIL["Weapon"].." - "..AL["Enhancements"] -> "<Slot> - Enhancements"
//       (permanent gear enchants, keyed by slot; Enchanting module) and, under the
//       Engineering module, the identical "Weapon - Enhancements" label is reused
//       for scopes, so routing is decided by which data[] key the category came
//       from, not by the label text alone.
//     - name = format(GEM_FORMAT1, ALIL["Meta"]) where GEM_FORMAT1 = ALIL["Gems"]..
//       " - %s" -> "Gems - <Color>" (cut gems; Jewelcrafting module, TBC only,
//       vanilla had no Jewelcrafting profession).
//     - name = AL["Enhancements"] (bare, no concatenation) appears both under
//       Leatherworking (mixing real "... Leg Armor" items with unrelated generic
//       Armor Kits and Glove Reinforcements in the same category, so those are
//       filtered by an "Leg Armor" substring check on the item's own comment) and
//       under Tailoring (Spellthread only, tailoring's leg-slot equivalent, no
//       filtering needed) and, misleadingly, under Blacksmithing too (weapon
//       chains/shield spikes/sharpening stones, not leg armor at all) -- routing
//       is therefore gated on the data[] key exactly as above, never on label text
//       alone.
//
//   Neither module carries a human readable faction display name (only a numeric
//   FactionID), so FACTION_META below hardcodes it the same way the dungeon
//   extractor hardcodes INSTANCE_META display names: well known Warcraft faction
//   names, not invented, just not present as a string literal in the source file.
//
// Run with: node tools/extract-atlasloot-catalogue.mjs
// Output:   ../GearScout/Data/Catalogue.lua

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT_FILE = path.join(HERE, "..", "GearScout", "Data", "Catalogue.lua");

const FACTIONS_DIR = "D:/World of Warcraft/_anniversary_/Interface/AddOns/AtlasLootClassic_Factions";
const CRAFTING_DIR = "D:/World of Warcraft/_anniversary_/Interface/AddOns/AtlasLootClassic_Crafting";

const FACTION_SOURCES = [
    { file: path.join(FACTIONS_DIR, "data.lua"), label: "AtlasLootClassic_Factions/data.lua (classic)" },
    { file: path.join(FACTIONS_DIR, "data-tbc.lua"), label: "AtlasLootClassic_Factions/data-tbc.lua (Burning Crusade)" },
];
const CRAFTING_SOURCES = [
    { file: path.join(CRAFTING_DIR, "data.lua"), label: "AtlasLootClassic_Crafting/data.lua (classic)" },
    { file: path.join(CRAFTING_DIR, "data-tbc.lua"), label: "AtlasLootClassic_Crafting/data-tbc.lua (Burning Crusade)" },
];

// Faction data[] key -> real English faction display name. The source has no name
// string for the faction itself (only FactionID), so this is hardcoded from common
// Warcraft knowledge, exactly like tools/extract-atlasloot.mjs's INSTANCE_META.
const FACTION_META = {
    // Classic
    ArgentDawn: "Argent Dawn",
    Timbermaw: "Timbermaw Hold",
    ThoriumBrotherhood: "Thorium Brotherhood",
    CenarionCircle: "Cenarion Circle",
    ZandalarTribe: "Zandalar Tribe",
    BroodOfNozdormu: "Brood of Nozdormu",
    HydraxianWaterlords: "Hydraxian Waterlords",
    BloodsailBuccaneers: "Bloodsail Buccaneers",
    WintersaberTrainers: "Wintersaber Trainers",
    // Burning Crusade
    TheAldor: "The Aldor",
    TheScryers: "The Scryers",
    TheShatar: "The Sha'tar",
    LowerCity: "Lower City",
    KeepersOfTime: "Keepers of Time",
    TheVioletEye: "The Violet Eye",
    CenarionExpedition: "Cenarion Expedition",
    TheConsortium: "The Consortium",
    AshtongueDeathsworn: "Ashtongue Deathsworn",
    TheScaleOfTheSands: "The Scale of the Sands",
    ShatteredSunOffensive: "Shattered Sun Offensive",
    ShatariSkyguard: "Sha'tari Skyguard",
    Netherwing: "Netherwing",
    Sporeggar: "Sporeggar",
    Ogrila: "Ogri'la",
    Tranquillien: "Tranquillien",
    Thrallmar: "Thrallmar",
    TheMaghar: "The Mag'har",
    HonorHold: "Honor Hold",
    Kurenai: "Kurenai",
};

const STANDING_ORDER = { Neutral: 0, Friendly: 1, Honored: 2, Revered: 3, Exalted: 4 };
const ENCHANT_SLOTS = new Set(["Weapon", "2H Weapon", "Cloak", "Chest", "Feet", "Hand", "Shield", "Wrist", "Ring"]);
const ENCHANT_SLOT_ORDER = ["Weapon", "2H Weapon", "Cloak", "Chest", "Shoulder", "Feet", "Hand", "Shield", "Wrist", "Ring"];
const GEM_COLORS = new Set(["Meta", "Red", "Yellow", "Blue", "Orange", "Green", "Purple"]);

// ---------------------------------------------------------------------------
// Minimal brace/string/comment aware Lua scanning helpers, copied from
// tools/extract-atlasloot.mjs (same proven approach, kept in sync by hand since
// this is a standalone build-time script with no shared runtime dependency).
// ---------------------------------------------------------------------------

function stripLuaLongComments(text) {
    // Removes --[[ ... ]] (and --[=[ ... ]=] style) block comments so commented
    // out data[] entries (e.g. a leftover DUMMY example in the Factions file)
    // never reach the data[] block scanner below.
    return text.replace(/--\[(=*)\[[\s\S]*?\]\1\]/g, "");
}

function findMatchingBrace(text, openIdx) {
    let depth = 0;
    let i = openIdx;
    const n = text.length;
    while (i < n) {
        const c = text[i];
        if (c === '"') {
            i++;
            while (i < n && text[i] !== '"') {
                if (text[i] === "\\") i++;
                i++;
            }
            i++;
            continue;
        }
        if (c === "-" && text[i + 1] === "-") {
            let j = text.indexOf("\n", i);
            if (j === -1) j = n;
            i = j;
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

// A `--` line comment carries no comma of its own, so a comment used to label
// a section inside a table arrives glued to the front of the entry that
// follows it. Left in place that entry no longer starts with `{` and the
// callers below throw it away as a bare table reference, losing every item
// under it. Same fault, same fix as tools/extract-atlasloot.mjs.
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
    let depth = 0;
    let start = 0;
    let i = 0;
    const n = text.length;
    while (i < n) {
        const c = text[i];
        if (c === '"') {
            i++;
            while (i < n && text[i] !== '"') {
                if (text[i] === "\\") i++;
                i++;
            }
            i++;
            continue;
        }
        if (c === "-" && text[i + 1] === "-") {
            let j = text.indexOf("\n", i);
            if (j === -1) j = n;
            i = j;
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
    return parts.map((s) => stripLeadingComments(s.trim())).filter((s) => s.length > 0);
}

function findDataBlocks(fileText) {
    const blocks = [];
    const re = /data\[\s*"([^"]+)"\s*\]\s*=\s*\{/g;
    let m;
    while ((m = re.exec(fileText))) {
        const key = m[1];
        const braceStart = fileText.indexOf("{", m.index);
        const braceEnd = findMatchingBrace(fileText, braceStart);
        if (braceEnd === -1) {
            console.warn(`[warn] unbalanced braces for data["${key}"]`);
            continue;
        }
        blocks.push({ key, body: fileText.slice(braceStart + 1, braceEnd) });
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

// Strips the trailing " (NNN)" ilvl and/or " / NNN[ / NNN]" skill-requirement
// annotations AtlasLoot appends to many item comments, keeping the bare name.
function cleanComment(c) {
    return String(c || "")
        .replace(/\s*\(\s*\d+\s*\)\s*$/, "")
        .replace(/\s*(\/\s*\d+\s*)+$/, "")
        .trim();
}

function collectRows(segment, cb) {
    ITEM_ROW_RE.lastIndex = 0;
    let m;
    while ((m = ITEM_ROW_RE.exec(segment))) {
        const itemId = parseInt(m[1], 10);
        cb(itemId, cleanComment(m[2]));
    }
}

// ---------------------------------------------------------------------------
// Pass 1: reputation rewards (AtlasLootClassic_Factions).
// ---------------------------------------------------------------------------

const stats = {
    factionBlocksSeen: 0,
    factionsWithoutMeta: 0,
    factionsKept: 0,
    repRewardRowsSeen: 0,
    repRewardsKept: 0,
    repRewardDupesSkipped: 0,
    craftingCategoriesSeen: 0,
    gemRowsKept: 0,
    metaGemRowsKept: 0,
    enchantRowsKept: 0,
    legArmorRowsSeen: 0,
    legArmorRowsKept: 0,
    weaponScopeRowsKept: 0,
};

// faction display name -> { factionId, rewards: [{standing, item, name}], seen: Set }
const repRewards = new Map();
const unknownFactionKeys = new Set();

for (const src of FACTION_SOURCES) {
    const fileText = stripLuaLongComments(readFileSync(src.file, "utf8"));
    const blocks = findDataBlocks(fileText);

    for (const { key, body } of blocks) {
        stats.factionBlocksSeen++;
        const factionName = FACTION_META[key];
        if (!factionName) {
            stats.factionsWithoutMeta++;
            unknownFactionKeys.add(key);
            continue;
        }
        stats.factionsKept++;

        const idMatch = body.match(/FactionID\s*=\s*(\d+)/);
        const factionId = idMatch ? parseInt(idMatch[1], 10) : null;

        if (!repRewards.has(factionName)) {
            repRewards.set(factionName, { factionId, rewards: [], seen: new Set() });
        }
        const entry = repRewards.get(factionName);
        if (entry.factionId === null) entry.factionId = factionId;

        const itemsBody = extractItemsBody(body);
        if (!itemsBody) continue;

        for (const segment of splitTopLevel(itemsBody)) {
            if (!segment.startsWith("{")) continue;
            const standingMatch = segment.match(/name\s*=\s*ALIL\["([^"]+)"\]/);
            if (!standingMatch) continue;
            const standing = standingMatch[1];

            collectRows(segment, (itemId, name) => {
                stats.repRewardRowsSeen++;
                const dupeKey = `${standing}:${itemId}`;
                if (entry.seen.has(dupeKey)) {
                    stats.repRewardDupesSkipped++;
                    return;
                }
                entry.seen.add(dupeKey);
                entry.rewards.push({ standing, item: itemId, name });
                stats.repRewardsKept++;
            });
        }
    }
}

// ---------------------------------------------------------------------------
// Pass 2: gems, enchants, leg armor, weapon scopes (AtlasLootClassic_Crafting).
// ---------------------------------------------------------------------------

const gems = new Map(); // itemId -> { color, cut }
const metaGems = new Map(); // itemId -> { cut }
const enchantItems = new Map(); // slot -> Map(itemId -> name)
const legArmor = []; // { id, name, profession }
const weaponScopes = new Map(); // itemId -> name

const SLOT_LABEL_RE = /name\s*=\s*(?:ALIL|AL)\["([^"]+)"\]\s*\.\.\s*"\s*-\s*"\s*\.\.\s*(?:ALIL|AL)\["Enhancements"\]/;
const GEM_LABEL_RE = /name\s*=\s*format\(\s*GEM_FORMAT1\s*,\s*ALIL\["([^"]+)"\]\s*\)/;
const BARE_ENHANCEMENTS_RE = /name\s*=\s*AL\["Enhancements"\]/;

for (const src of CRAFTING_SOURCES) {
    const fileText = stripLuaLongComments(readFileSync(src.file, "utf8"));
    const blocks = findDataBlocks(fileText);

    for (const { key, body } of blocks) {
        const itemsBody = extractItemsBody(body);
        if (!itemsBody) continue;

        for (const segment of splitTopLevel(itemsBody)) {
            if (!segment.startsWith("{")) continue;
            stats.craftingCategoriesSeen++;

            if (key === "JewelcraftingBC") {
                const gemMatch = segment.match(GEM_LABEL_RE);
                if (!gemMatch || !GEM_COLORS.has(gemMatch[1])) continue;
                const color = gemMatch[1];
                collectRows(segment, (itemId, name) => {
                    if (color === "Meta") {
                        metaGems.set(itemId, { cut: name });
                        stats.metaGemRowsKept++;
                    } else {
                        gems.set(itemId, { color, cut: name });
                        stats.gemRowsKept++;
                    }
                });
                continue;
            }

            if (key === "Enchanting" || key === "EnchantingBC") {
                const slotMatch = segment.match(SLOT_LABEL_RE);
                if (!slotMatch || !ENCHANT_SLOTS.has(slotMatch[1])) continue;
                const slot = slotMatch[1];
                if (!enchantItems.has(slot)) enchantItems.set(slot, new Map());
                const slotMap = enchantItems.get(slot);
                collectRows(segment, (itemId, name) => {
                    if (!slotMap.has(itemId)) {
                        slotMap.set(itemId, name);
                        stats.enchantRowsKept++;
                    }
                });
                continue;
            }

            if (key === "Engineering" || key === "EngineeringBC") {
                const slotMatch = segment.match(SLOT_LABEL_RE);
                if (!slotMatch || slotMatch[1] !== "Weapon") continue;
                collectRows(segment, (itemId, name) => {
                    if (!weaponScopes.has(itemId)) {
                        weaponScopes.set(itemId, name);
                        stats.weaponScopeRowsKept++;
                    }
                });
                continue;
            }

            if (key === "Leatherworking" || key === "LeatherworkingBC" || key === "Tailoring" || key === "TailoringBC") {
                if (!BARE_ENHANCEMENTS_RE.test(segment)) continue;
                const profession = key.startsWith("Leatherworking") ? "Leatherworking" : "Tailoring";
                collectRows(segment, (itemId, name) => {
                    stats.legArmorRowsSeen++;
                    // Leatherworking's "Enhancements" category also holds generic Armor
                    // Kits and Glove Reinforcements in the same array; only true leg
                    // armor belongs here. Tailoring's equivalent category is pure
                    // Spellthread (the tailor leg-slot enchant), so every row qualifies.
                    if (profession === "Leatherworking" && !/Leg Armor/i.test(name)) return;
                    legArmor.push({ id: itemId, name, profession });
                    stats.legArmorRowsKept++;
                });
                continue;
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Emit GearScout/Data/Catalogue.lua
// ---------------------------------------------------------------------------

function luaString(s) {
    return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/[\u2013\u2014]/g, "-") + '"';
}

const lines = [];
lines.push("-- GearScout / Data/Catalogue.lua");
lines.push("-- GENERATED FILE. Do not hand edit, changes will be overwritten.");
lines.push("-- Produced by tools/extract-atlasloot-catalogue.mjs from AtlasLoot Classic's own");
lines.push("-- reputation and crafting data (AtlasLootClassic_Factions and");
lines.push("-- AtlasLootClassic_Crafting, data.lua and data-tbc.lua in each).");
lines.push("-- Regenerate with: node tools/extract-atlasloot-catalogue.mjs");
lines.push("--");
lines.push("-- Shape:");
lines.push('--   ns.REP_REWARDS["<faction name>"] = { factionId = <id>,');
lines.push('--     rewards = { { standing = "<standing>", item = <itemId>, name = "<name>" }, ... } }');
lines.push('--   ns.GEMS[itemId] = { color = "<Red|Yellow|Blue|Orange|Green|Purple>", cut = "<name>" }');
lines.push('--   ns.META_GEMS[itemId] = { cut = "<name>" }');
lines.push('--   ns.ENCHANT_ITEMS["<slot>"] = { { id = <itemId>, name = "<name>" }, ... }');
lines.push('--   ns.LEG_ARMOR[n] = { id = <itemId>, name = "<name>", profession = "<profession>" }');
lines.push('--   ns.WEAPON_SCOPES[n] = { id = <itemId>, name = "<name>" }');
lines.push("--");
lines.push("-- Item ids are the load-bearing data; the addon resolves id -> name/icon/stats");
lines.push("-- through the game client at runtime. Name fields are carried only to make this");
lines.push("-- file readable and its diffs reviewable by a human.");
lines.push("--");
lines.push("-- Coverage notes from this generation pass:");
lines.push("--   * ns.GEMS and ns.META_GEMS are Burning Crusade only: vanilla AtlasLoot data has");
lines.push("--     no Jewelcrafting module at all (the profession did not exist pre-TBC), so");
lines.push("--     there is no classic cut-gem source to read. This is a genuine source gap, not");
lines.push("--     an extraction failure.");
lines.push("--   * ns.LEG_ARMOR mixes two source professions: Leatherworking's own \"Leg Armor\"");
lines.push("--     items (Burning Crusade only; vanilla Leatherworking never added leg-specific");
lines.push("--     armor, only generic Armor Kits usable on any leather piece, which are not");
lines.push("--     included here) and Tailoring's Spellthread items (Burning Crusade only), the");
lines.push("--     cloth-wearer equivalent of leg armor. Both carry a profession field so the");
lines.push("--     addon can tell them apart.");
lines.push("--   * ns.WEAPON_SCOPES covers Engineering-only gun/bow scopes from both eras.");
lines.push("--   * ns.ENCHANT_ITEMS covers only permanent slot enchants recoverable from a");
lines.push('--     labeled "<Slot> - Enhancements" source category (Weapon, 2H Weapon, Cloak,');
lines.push("--     Chest, Feet, Hand, Shield, Wrist, Ring). Temporary weapon oils, wands, rods");
lines.push("--     and enchanting reagents (the source's own \"Oil\"/\"Wands\"/\"Misc\" categories)");
lines.push("--     are deliberately excluded as not permanent gear enchants. No Shoulder-slot");
lines.push("--     enchant category exists in this AtlasLoot data for classic or TBC (shoulder");
lines.push("--     enchants in this era come from reputation, not a craftable recipe), so");
lines.push("--     ns.ENCHANT_ITEMS has no [\"Shoulder\"] key; a shoulder enchant's source is a");
lines.push("--     faction instead and shows up in ns.REP_REWARDS.");
lines.push("--   * ns.REP_REWARDS lists every reward row AtlasLoot has for a faction (gear,");
lines.push('--     recipes, tokens alike), not just equippable items, because the task calling');
lines.push("--     for this file asked for \"every reward,\" not just gear.");
if (unknownFactionKeys.size > 0) {
    lines.push("--   * Faction data[] keys read from source but skipped (no FACTION_META display");
    lines.push(`--     name mapped): ${Array.from(unknownFactionKeys).sort().join(", ")}.`);
}
lines.push("");
lines.push("local ADDON, ns = ...");
lines.push("");

// -- ns.REP_REWARDS --
lines.push("ns.REP_REWARDS = {");
const factionNames = Array.from(repRewards.keys()).sort((a, b) => a.localeCompare(b));
for (const name of factionNames) {
    const entry = repRewards.get(name);
    entry.rewards.sort((a, b) => {
        const oa = STANDING_ORDER[a.standing] ?? 99;
        const ob = STANDING_ORDER[b.standing] ?? 99;
        if (oa !== ob) return oa - ob;
        return a.item - b.item;
    });
    lines.push(`[${luaString(name)}] = {`);
    lines.push(`\tfactionId = ${entry.factionId ?? "nil"},`);
    lines.push("\trewards = {");
    for (const r of entry.rewards) {
        const nameField = r.name ? `, name = ${luaString(r.name)}` : "";
        lines.push(`\t\t{ standing = ${luaString(r.standing)}, item = ${r.item}${nameField} },`);
    }
    lines.push("\t},");
    lines.push("},");
}
lines.push("}");
lines.push("");

// -- ns.GEMS --
lines.push("ns.GEMS = {");
for (const id of Array.from(gems.keys()).sort((a, b) => a - b)) {
    const g = gems.get(id);
    lines.push(`[${id}] = { color = ${luaString(g.color)}, cut = ${luaString(g.cut)} },`);
}
lines.push("}");
lines.push("");

// -- ns.META_GEMS --
lines.push("ns.META_GEMS = {");
for (const id of Array.from(metaGems.keys()).sort((a, b) => a - b)) {
    const g = metaGems.get(id);
    lines.push(`[${id}] = { cut = ${luaString(g.cut)} },`);
}
lines.push("}");
lines.push("");

// -- ns.ENCHANT_ITEMS --
lines.push("ns.ENCHANT_ITEMS = {");
const slotKeys = Array.from(enchantItems.keys()).sort((a, b) => {
    const ia = ENCHANT_SLOT_ORDER.indexOf(a);
    const ib = ENCHANT_SLOT_ORDER.indexOf(b);
    return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib);
});
for (const slot of slotKeys) {
    lines.push(`[${luaString(slot)}] = {`);
    const slotMap = enchantItems.get(slot);
    for (const id of Array.from(slotMap.keys()).sort((a, b) => a - b)) {
        lines.push(`\t{ id = ${id}, name = ${luaString(slotMap.get(id))} },`);
    }
    lines.push("},");
}
lines.push("}");
lines.push("");

// -- ns.LEG_ARMOR --
legArmor.sort((a, b) => (a.profession === b.profession ? a.id - b.id : a.profession.localeCompare(b.profession)));
lines.push("ns.LEG_ARMOR = {");
for (const la of legArmor) {
    lines.push(`{ id = ${la.id}, name = ${luaString(la.name)}, profession = ${luaString(la.profession)} },`);
}
lines.push("}");
lines.push("");

// -- ns.WEAPON_SCOPES --
lines.push("ns.WEAPON_SCOPES = {");
for (const id of Array.from(weaponScopes.keys()).sort((a, b) => a - b)) {
    lines.push(`{ id = ${id}, name = ${luaString(weaponScopes.get(id))} },`);
}
lines.push("}");
lines.push("");

mkdirSync(path.dirname(OUT_FILE), { recursive: true });
writeFileSync(OUT_FILE, lines.join("\n"), "utf8");

console.log(`Wrote ${OUT_FILE}`);
console.log(`Factions kept: ${repRewards.size}`);
console.log(`Rep reward rows: ${stats.repRewardsKept}`);
console.log(`Gems: ${gems.size}`);
console.log(`Meta gems: ${metaGems.size}`);
console.log(`Enchant slots: ${enchantItems.size}, enchant item rows: ${stats.enchantRowsKept}`);
console.log(`Leg armor items: ${legArmor.length}`);
console.log(`Weapon scopes: ${weaponScopes.size}`);
if (unknownFactionKeys.size > 0) {
    console.log(`Faction keys with no FACTION_META entry (skipped): ${Array.from(unknownFactionKeys).sort().join(", ")}`);
}
console.log("--- stats ---");
console.log(JSON.stringify(stats, null, 2));
