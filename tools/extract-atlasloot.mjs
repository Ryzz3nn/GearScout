// GearScout / tools/extract-atlasloot.mjs
// Plain Node script, no dependencies. Reads AtlasLoot Classic's own dungeon and
// raid loot tables off disk and emits GearScout/Data/DungeonLoot.lua: a single
// compact, static table mapping item id -> where it drops, plus a per instance
// level range summary. The shipped addon never talks to AtlasLoot at runtime;
// this script is the only place that dependency exists, and only at build time.
//
// Source structure (read from the files below, not guessed):
//   Each file assigns data["SomeKey"] = { MapID=, InstanceID=, LevelRange=,
//   items = { <bossOrCategory>, <bossOrCategory>, ... } }.
//   Every bossOrCategory is either:
//     - a literal table  { name = AL["Boss Name"], [SOME_DIFF] = { <items> }, ... }
//     - a bare identifier referring to a table declared earlier in the file
//       (e.g. KEYS, T4_SET) that is reused across several instances. These are
//       not tied to a specific boss in this data and are skipped.
//   Item rows inside a difficulty array look like { 7, 30637 }, -- Item Name
//   or occasionally { 7, 30637, [ATLASLOOT_IT_ALLIANCE] = 30622 }, -- Item Name.
//   Menu header/separator rows reuse the same shape but put a texture string
//   in the item id slot, e.g. { 1, "INV_Box_01", nil, AL["Normal"], nil } -
//   these are rejected structurally because the id slot is not numeric.
//   AtlasLoot has no enUS locale file (English is the default), so the literal
//   text inside AL["..."] calls IS the English string; no locale file needed.
//   Neither file carries a human readable instance display name or (for
//   raids) a level range, so both are hardcoded below in INSTANCE_META.
//
// Run with: node tools/extract-atlasloot.mjs
// Output:   ../GearScout/Data/DungeonLoot.lua

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT_FILE = path.join(HERE, "..", "GearScout", "Data", "DungeonLoot.lua");

const WOW_ADDONS = "D:/World of Warcraft/_anniversary_/Interface/AddOns/AtlasLootClassic_DungeonsAndRaids";
const SOURCES = [
    { file: path.join(WOW_ADDONS, "data.lua"), label: "data.lua (classic dungeons and raids)" },
    { file: path.join(WOW_ADDONS, "data-tbc.lua"), label: "data-tbc.lua (Burning Crusade dungeons and raids)" },
];

// ---------------------------------------------------------------------------
// Hardcoded instance metadata: display name, and a fallback level range used
// only when the source file itself has no LevelRange field (true for every
// raid and world boss entry in both files; dungeons carry their own
// LevelRange and that value is preferred whenever present).
// ---------------------------------------------------------------------------
const INSTANCE_META = {
    // Classic dungeons
    Ragefire: { name: "Ragefire Chasm", level: [8, 16] },
    WailingCaverns: { name: "Wailing Caverns", level: [10, 21] },
    TheDeadmines: { name: "The Deadmines", level: [10, 22] },
    ShadowfangKeep: { name: "Shadowfang Keep", level: [14, 21] },
    BlackfathomDeeps: { name: "Blackfathom Deeps", level: [19, 24] },
    TheStockade: { name: "The Stockade", level: [15, 29] },
    Gnomeregan: { name: "Gnomeregan", level: [15, 28] },
    RazorfenKraul: { name: "Razorfen Kraul", level: [17, 27] },
    ScarletMonasteryGraveyard: { name: "Scarlet Monastery: Graveyard", level: [20, 32] },
    ScarletMonasteryLibrary: { name: "Scarlet Monastery: Library", level: [20, 35] },
    ScarletMonasteryArmory: { name: "Scarlet Monastery: Armory", level: [20, 37] },
    ScarletMonasteryCathedral: { name: "Scarlet Monastery: Cathedral", level: [20, 40] },
    RazorfenDowns: { name: "Razorfen Downs", level: [25, 37] },
    Uldaman: { name: "Uldaman", level: [30, 40] },
    "Zul'Farrak": { name: "Zul'Farrak", level: [35, 46] },
    Maraudon: { name: "Maraudon", level: [30, 48] },
    "TheTempleOfAtal'Hakkar": { name: "The Sunken Temple", level: [35, 50] },
    BlackrockDepths: { name: "Blackrock Depths", level: [40, 56] },
    LowerBlackrockSpire: { name: "Lower Blackrock Spire", level: [45, 60] },
    UpperBlackrockSpire: { name: "Upper Blackrock Spire", level: [45, 60] },
    DireMaulEast: { name: "Dire Maul: East", level: [31, 60] },
    DireMaulWest: { name: "Dire Maul: West", level: [31, 60] },
    DireMaulNorth: { name: "Dire Maul: North", level: [31, 60] },
    Scholomance: { name: "Scholomance", level: [45, 60] },
    Stratholme: { name: "Stratholme", level: [45, 60] },
    WorldBosses: { name: "Classic World Bosses", level: [60, 60] },
    MoltenCore: { name: "Molten Core", level: [60, 60] },
    Onyxia: { name: "Onyxia's Lair", level: [60, 60] },
    "Zul'Gurub": { name: "Zul'Gurub", level: [60, 60] },
    BlackwingLair: { name: "Blackwing Lair", level: [60, 60] },
    TheRuinsofAhnQiraj: { name: "Ruins of Ahn'Qiraj", level: [60, 60] },
    TheTempleofAhnQiraj: { name: "Temple of Ahn'Qiraj", level: [60, 60] },
    Naxxramas: { name: "Naxxramas", level: [60, 60] },

    // Burning Crusade dungeons
    HellfireRamparts: { name: "Hellfire Ramparts", level: [59, 65] },
    TheBloodFurnace: { name: "The Blood Furnace", level: [60, 66] },
    TheShatteredHalls: { name: "The Shattered Halls", level: [70, 70] },
    "Mana-Tombs": { name: "Mana-Tombs", level: [64, 70] },
    AuchenaiCrypts: { name: "Auchenai Crypts", level: [65, 70] },
    SethekkHalls: { name: "Sethekk Halls", level: [67, 70] },
    ShadowLabyrinth: { name: "Shadow Labyrinth", level: [70, 70] },
    TheSlavePens: { name: "The Slave Pens", level: [62, 68] },
    TheUnderbog: { name: "The Underbog", level: [64, 70] },
    TheSteamvault: { name: "The Steamvault", level: [70, 70] },
    OldHillsbradFoothills: { name: "Old Hillsbrad Foothills", level: [67, 70] },
    TheBlackMorass: { name: "The Black Morass", level: [70, 70] },
    TheArcatraz: { name: "The Arcatraz", level: [70, 70] },
    TheBotanica: { name: "The Botanica", level: [70, 70] },
    TheMechanar: { name: "The Mechanar", level: [70, 70] },
    MagistersTerrace: { name: "Magisters' Terrace", level: [70, 70] },

    // Burning Crusade raids and world bosses
    Karazhan: { name: "Karazhan", level: [70, 70] },
    ZulAman: { name: "Zul'Aman", level: [70, 70] },
    WorldBossesBC: { name: "Outland World Bosses", level: [70, 70] },
    MagtheridonsLair: { name: "Magtheridon's Lair", level: [70, 70] },
    GruulsLair: { name: "Gruul's Lair", level: [70, 70] },
    SerpentshrineCavern: { name: "Serpentshrine Cavern", level: [70, 70] },
    TempestKeep: { name: "The Eye", level: [70, 70] },
    HyjalSummit: { name: "Battle for Mount Hyjal", level: [70, 70] },
    BlackTemple: { name: "Black Temple", level: [70, 70] },
    SunwellPlateau: { name: "Sunwell Plateau", level: [70, 70] },
};

// Whole bossOrCategory blocks to drop outright: key rings and the recipe
// (pattern/design/schematic/plans) browse-by-profession menu.
const SKIP_CATEGORY_NAMES = new Set(["Keys", "Patterns"]);

// Item name prefixes that mean "this teaches a recipe", not "this is gear".
const RECIPE_RE = /^(Pattern|Design|Schematic|Plans?|Formula|Recipe|Manual|Technique):/i;

// Item ids confirmed by reading the source comments to be currency, quest
// turn-in fodder, mounts or trade good reagents rather than equippable gear.
// This list cannot be exhaustive from text alone (the source files carry no
// item-type field), so it only contains items positively identified while
// writing this script; see the report for the same caveat in writing.
const JUNK_ITEM_IDS = new Set([
    29434, // Badge of Justice (TBC heroic currency)
    32897, // Mark of the Illidari (Black Temple currency)
    34664, // Sunmote (Sunwell Plateau trash reagent)
    35273, // Study of Advanced Smelting (recipe, no "Pattern:" prefix)
    33993, // Mojo (Zul'Aman currency)
    33809, // Amani War Bear (mount, not gear)
    32227, 32228, 32229, 32230, 32231, 32249, // Sunwell trash raw gems
    19698, 19699, 19700, 19701, 19702, 19703, 19704, 19705, 19706, // Zul'Gurub bijou coins
    18422, 18423, // Head of Onyxia (quest turn-in, Horde/Alliance)
    19002, 19003, // Head of Nefarian (quest turn-in, Horde/Alliance)
    20383, // Head of the Broodlord Lashlayer (quest turn-in)
    13250, // Head of Balnazzar (quest turn-in)
    22733, // Staff Head of Atiesh (legendary quest component)
    22726, 22727, // Splinter/Frame of Atiesh (legendary quest components, Naxxramas)
    20931, // Skin of the Great Sandworm (AQ40 quest item)
    22732, // Mark of C'Thun (AQ40 quest item)
    21670, // Badge of the Swarmguard (AQ40 currency)
    2262,  // Mark of Kern (Blackfathom Deeps quest item)
    10780, // Mark of Hakkar (Zul'Gurub quest item)
    11938, 17962, // Sack of Gems / Blue Sack of Gems (reward bags, not gear)
    18704, // Mature Blue Dragon Sinew (tailoring reagent)
]);

// ---------------------------------------------------------------------------
// Minimal brace/string/comment aware Lua scanning helpers. We do not need a
// full Lua parser: the source is regular enough that tracking string and
// comment state while counting braces is sufficient to correctly segment it.
// ---------------------------------------------------------------------------

// Returns the index of the '}' matching the '{' at openIdx, skipping over
// string literals and `--` line comments so braces inside them do not
// affect the depth count.
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

// Removes any `--` line comments sitting in front of an entry. AtlasLoot
// labels sections inside an items table with bare comments, e.g.
// `-- Graveyard` immediately before the first boss of Scarlet Monastery's
// graveyard wing. A comment carries no comma of its own, so it arrives glued
// to the front of the entry that follows it, and that entry then no longer
// starts with `{` and gets discarded as if it were a bare table reference.
// That silently cost eleven bosses, one per commented section.
function stripLeadingComments(text) {
    let s = text;
    while (s.startsWith("--")) {
        const nl = s.indexOf("\n");
        if (nl === -1) return "";
        s = s.slice(nl + 1).trim();
    }
    return s;
}

// Splits the inner content of a table constructor into its top level,
// comma separated entries, ignoring commas nested inside strings, comments
// or deeper braces.
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

function parseLevelRange(body) {
    let m = body.match(/LevelRange\s*=\s*GetForVersion\(\s*\{([^}]*)\}\s*(?:,\s*\{([^}]*)\})?/);
    if (m) {
        // ReturnForGameVersion(classic, bcc, wrath): on a Burning Crusade
        // realm the second (bcc) array applies, falling back to the first.
        const raw = m[2] !== undefined ? m[2] : m[1];
        const nums = raw.split(",").map((s) => parseInt(s.trim(), 10)).filter((n) => !Number.isNaN(n));
        if (nums.length >= 2) return { min: nums[0], max: nums[nums.length - 1] };
    }
    m = body.match(/LevelRange\s*=\s*\{([^}]*)\}/);
    if (m) {
        const nums = m[1].split(",").map((s) => parseInt(s.trim(), 10)).filter((n) => !Number.isNaN(n));
        if (nums.length >= 2) return { min: nums[0], max: nums[nums.length - 1] };
    }
    return null;
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

const stats = {
    instances: 0,
    bossesOrCategories: 0,
    skippedCategoryBlocks: 0,
    skippedBareRefs: 0,
    itemRowsSeen: 0,
    itemsKeptRecipe: 0,
    itemsKeptKeyish: 0,
    itemsKeptJunkId: 0,
    itemsKept: 0,
    duplicateItemIds: 0,
};

const loot = new Map(); // itemId -> { d, b }
const instanceInfo = new Map(); // display name -> { min, max }

for (const src of SOURCES) {
    const fileText = readFileSync(src.file, "utf8");
    const blocks = findDataBlocks(fileText);

    for (const { key, body } of blocks) {
        const meta = INSTANCE_META[key];
        if (!meta) {
            console.warn(`[warn] no INSTANCE_META entry for data["${key}"] in ${src.label}, skipping`);
            continue;
        }
        stats.instances++;

        const sourceRange = parseLevelRange(body);
        const range = sourceRange || { min: meta.level[0], max: meta.level[1] };
        instanceInfo.set(meta.name, range);

        const itemsBody = extractItemsBody(body);
        if (!itemsBody) continue;

        for (const segment of splitTopLevel(itemsBody)) {
            if (!segment.startsWith("{")) {
                stats.skippedBareRefs++;
                continue;
            }
            stats.bossesOrCategories++;

            const nameMatch = segment.match(/name\s*=\s*AL\[\s*"([^"]*)"\s*\]/);
            const bossName = nameMatch ? nameMatch[1] : "Unknown";
            if (SKIP_CATEGORY_NAMES.has(bossName)) {
                stats.skippedCategoryBlocks++;
                continue;
            }

            ITEM_ROW_RE.lastIndex = 0;
            let rowMatch;
            while ((rowMatch = ITEM_ROW_RE.exec(segment))) {
                stats.itemRowsSeen++;
                const itemId = parseInt(rowMatch[1], 10);
                const comment = (rowMatch[2] || "").trim();

                if (JUNK_ITEM_IDS.has(itemId)) {
                    stats.itemsKeptJunkId++;
                    continue;
                }
                if (comment && RECIPE_RE.test(comment)) {
                    stats.itemsKeptRecipe++;
                    continue;
                }
                if (comment && /\bKey$/.test(comment)) {
                    stats.itemsKeptKeyish++;
                    continue;
                }

                if (loot.has(itemId)) {
                    stats.duplicateItemIds++;
                    continue;
                }
                loot.set(itemId, { d: meta.name, b: bossName });
                stats.itemsKept++;
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Emit GearScout/Data/DungeonLoot.lua
// ---------------------------------------------------------------------------

function luaString(s) {
    // Source data is plain ASCII/Latin item and boss names; strip anything
    // that could break a double quoted Lua string plus the house style ban
    // on em/en dashes, just in case a name ever carries one.
    return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/[\u2013\u2014]/g, "-") + '"';
}

const sortedItemIds = Array.from(loot.keys()).sort((a, b) => a - b);
const sortedInstanceNames = Array.from(instanceInfo.keys()).sort((a, b) => a.localeCompare(b));

const lines = [];
lines.push("-- GearScout / Data/DungeonLoot.lua");
lines.push("-- GENERATED FILE. Do not hand edit, changes will be overwritten.");
lines.push("-- Produced by tools/extract-atlasloot.mjs from AtlasLoot Classic's dungeon and");
lines.push("-- raid loot tables (AtlasLootClassic_DungeonsAndRaids data.lua and data-tbc.lua).");
lines.push("-- Regenerate with: node tools/extract-atlasloot.mjs");
lines.push("--");
lines.push("-- Shape:");
lines.push('--   ns.DUNGEON_LOOT[itemId] = { d = "<instance name>", b = "<boss or source name>" }');
lines.push('--   ns.DUNGEON_INFO["<instance name>"] = { min = <level>, max = <level> }');
lines.push("--");
lines.push("-- ns.DUNGEON_LOOT is keyed by item id because the addon's hot path is looking");
lines.push("-- up items it already has an id for while scanning gear, which makes this a");
lines.push("-- single O(1) hash lookup with no scan. Field names are single letters to keep");
lines.push("-- the file small. Values are short literal strings rather than indices into a");
lines.push("-- separate name table: Lua interns identical string constants, so repeating");
lines.push('-- "Karazhan" across many entries costs no extra memory at runtime, and it saves');
lines.push("-- a second table lookup per item plus keeps the file readable to diff by hand.");
lines.push("--");
lines.push("-- ns.DUNGEON_INFO is keyed by that same instance name string so the addon can");
lines.push("-- go item -> source -> level range without needing a third join table.");
lines.push("");
lines.push("local ADDON, ns = ...");
lines.push("");
lines.push("ns.DUNGEON_LOOT = {");
for (const id of sortedItemIds) {
    const entry = loot.get(id);
    lines.push(`[${id}] = { d = ${luaString(entry.d)}, b = ${luaString(entry.b)} },`);
}
lines.push("}");
lines.push("");
lines.push("ns.DUNGEON_INFO = {");
for (const name of sortedInstanceNames) {
    const range = instanceInfo.get(name);
    lines.push(`[${luaString(name)}] = { min = ${range.min}, max = ${range.max} },`);
}
lines.push("}");
lines.push("");

mkdirSync(path.dirname(OUT_FILE), { recursive: true });
writeFileSync(OUT_FILE, lines.join("\n"), "utf8");

console.log(`Wrote ${OUT_FILE}`);
console.log(`Instances: ${instanceInfo.size}`);
console.log(`Items kept: ${loot.size}`);
console.log("--- stats ---");
console.log(JSON.stringify(stats, null, 2));
