# GearScout data map

Every source of data the addon uses, where it comes from, how much of it there is, and how far
it can be trusted. Written to be read cold.

Last updated during the overnight research run.

---

## The one constraint that shapes everything

**A WoW addon cannot make network requests.** There is no HTTP in the Lua sandbox. Nothing can
be fetched from a database, an API or a website while the game is running, ever.

So there are exactly three ways data can reach the addon:

1. **Ask the game client.** It already knows every item's stats, every spell's name, every aura
   on you. This is live, always current, and needs no shipping.
2. **Ship it inside the addon.** A generated Lua file, produced here at build time. Users get
   new data when they update the addon, not instantly.
3. **Read another addon in process.** If Details or TSM happen to be loaded, their data is
   reachable. Optional, never required.

Anything that sounds like "the addon pulls from Turso" is impossible. The Turso loop works, it
just runs the other way round: your client observes, a Node script uploads, a build step pulls
it back down and bakes it into a shipped Lua file.

```
your client observes  ->  SavedVariables
      ->  tools/export-session.mjs  ->  Turso
      ->  build step  ->  generated Lua  ->  shipped in the addon
```

---

## Live, from the game client

No shipping, no staleness, works for every item that will ever exist. This is the backbone and
it is why a complete item database is not actually needed.

| What | How | Notes |
|---|---|---|
| Item stats | `ns.GetStats(link)` in `Scan.lua` | Wraps `GetItemStats`, which on this client may only exist as `C_Item.GetItemStats`. Handles both. |
| Item level, quality, slot, required level | `ns.GetItemMeta` in `Core.lua` | Resolves uncached items asynchronously and re-fires when they arrive. |
| Sockets | `ns.CountSockets` in `Scan.lua` | Reads the base item so inserted gems cannot hide the socket count. Falls back to tooltip scanning. |
| Enchants and gems on an item | itemString fields 2 and 3 to 6 | Parsed in `ns.ParseLink`. |
| Auras on you and your target | `ns.GetAuraName` in `Core.lua` | `C_UnitAuras` with a `UnitAura` fallback. Sampled 4 times a second in combat. |
| Spell names and known spells | `ns.SpellName`, `ns.SpellKnown` | Handles the modern `C_Spell` and `C_SpellBook` paths. |
| Talent spec | `ns.GetSpec` in `Core.lua` | Identifies returns by type, because this client uses the retail `GetTalentTabInfo` signature. |
| Bags and bank | `Bags.lua` | `C_Container` with a global fallback. |
| Quest log rewards | `Quests.lua` | `C_QuestLog` with a global fallback. |
| Group composition | `Buffs.lua` | Class and level of everyone present, to work out which buffs you are missing. |

### A client quirk that caused three separate bugs

This client reports interface `20506`, which says Burning Crusade, but runs on the **current
engine**. Old globals are gone or changed shape. Three real failures came from assuming
otherwise:

- `GetSpellBookItemName` and `BOOKTYPE_SPELL` do not exist. Scanning the spellbook threw, which
  killed profile building for every class.
- `GetTalentTabInfo` returns the retail signature `(id, name, description, icon, pointsSpent)`.
  Reading position three as the point count returned a description string and threw on compare.
- `GetItemStats` may only exist as `C_Item.GetItemStats`.

**Rule for anything added later: never assume a global exists.** Guard it or shim it.

---

## Shipped data, generated here

### Data/DungeonLoot.lua

| | |
|---|---|
| Source | AtlasLoot Classic's own data files, on disk |
| Generator | `tools/extract-atlasloot.mjs` |
| Contents | **3570 gear items across 59 instances**, 26 Burning Crusade and 33 classic |
| Verified | Yes, structurally. 0 malformed entries, every item resolves to a known instance, every level range sane |
| Confidence | High |

Shape is `ns.DUNGEON_LOOT[itemId] = { d = "instance", b = "boss" }` plus
`ns.DUNGEON_INFO["instance"] = { min, max }`.

Filtered out: 217 recipes, 28 keys, 137 curated junk ids, and 890 duplicate item ids.

Known simplifications: the junk filter is text heuristic because the source carries no item type
field, so some currency or quest items may slip through. Scarlet Monastery's four wings share one
trash pool, attributed to whichever wing appears first.

Regenerate with `node tools/extract-atlasloot.mjs`.

### Data/Rotations.lua

| | |
|---|---|
| Source | Research workflow, 9 class agents plus an adversarial auditor |
| Contents | **27 specs, 302 tracked spells, 6 aura groups, 134 spec tips** |
| Verified | Spell ids fetched individually against Wowhead's TBC database |
| Confidence | Medium to high, with known exceptions below |

Every spell id was confirmed by fetching its Wowhead TBC page and matching the name, rather than
trusted from recall. The auditor then found and the assembler removed:

- Circle of Healing, wrong cooldown, dropped
- Shadowstep, wrong cooldown, dropped
- Slice and Dice and Rupture, durations that assumed maximum combo points, downgraded so they
  are counted but never judged

Two further faults were caught here afterwards by structural verification, not by the workflow:

- Rapid Fire was tagged as a cooldown with no cooldown number, in three hunter specs and the
  levelling list. The analyzer divides by that, so this would have thrown mid fight. Set to 300s.
- Eleven entries carry no duration. Harmless: uptime is measured by sampling real auras, so
  nothing divides by it.

**Switchable.** `/gearscout data builtin` reverts to the hand written tables in `Profiles.lua`,
`/gearscout data research` returns to this set. `/gearscout rot` reports which is live.

### Data/ItemDB.lua

| | |
|---|---|
| Source | Questie's `Database/TBC/tbcItemDB.lua`, on disk |
| Generator | `tools/extract-questie-items.mjs` |
| Contents | **14,949 items**: 2,826 weapons, 12,123 armor. Item level, required level, class, subclass |
| Size | 0.63 MB |
| Verified | 0 malformed, 0 missing item level. Thunderfury spot checked at item level 80, required 60, one hand sword |
| Confidence | High |

Names are deliberately excluded. Including them grew the file from 641 KB to 1042 KB, and every
caller already has the name from the live client. Sixty three percent more size for nothing.

Also excluded: 1,405 items with no item level, and 8,656 that are neither weapon nor armor.
Neither can take part in a gear comparison.

**Coverage of the dungeon loot table is 85.6 percent, not the 99.1 percent originally measured.**
The two numbers count different things. The earlier figure was Questie's coverage of all loot
ids; this one is what survives after filtering to weapons and armor. The 515 loot ids not
present are gems, patterns and formulae that the AtlasLoot filter did not catch, which are not
gear and were never wanted here.

#### What it does and does not solve

ItemDB carries no equip location, so it cannot name a slot by itself. What it can do is reject
the overwhelming majority of candidates before the client is troubled: wrong item level, wrong
armor type for the class, level requirement too high. Only the survivors get looked up, and
looking one up caches it, so the answer improves every time it runs.

`FindSlotUpgrades` now reports how many candidates are still loading rather than presenting a
partial list as if it were complete.

Regenerate with `node tools/extract-questie-items.mjs`.

### Data/Catalogue.lua

| | |
|---|---|
| Source | AtlasLoot's Factions and Crafting modules, on disk |
| Generator | `tools/extract-atlasloot-catalogue.mjs` |
| Contents | **29 factions with 781 reward rows, 118 gems, 14 meta gems, 191 enchants across 9 slots, 8 leg armors, 9 weapon scopes** |
| Verified | Yes, structurally. Every reputation reward carries an item id, zero gaps |
| Confidence | High |

This is the file that fills the addon's biggest advice gap. It already told players to get a head
or shoulder enchant but could not say where from. Now it can.

Reached this way only after web research failed twice. Wowhead's listing pages are JavaScript
rendered, so fetching returns the filter interface rather than results. The data was on the disk
the whole time.

Not extracted, and correctly so: vanilla gems, because Jewelcrafting did not exist before TBC;
vanilla leg armor, because Leatherworking had only generic armor kits usable on any leather
slot rather than leg specific items.

Regenerate with `node tools/extract-atlasloot-catalogue.mjs`.

### Data/CatalogueResearch.lua

| | |
|---|---|
| Source | Research workflow plus an adversarial audit. **Not regenerable** |
| Contents | 8 professions, and rank data for 41 spells across 9 classes, with 11 still empty |
| Confidence | Mixed and recorded per entry: verified, suspect, or unverified |

Rogue, Priest and Shaman rank data is missing because the research could not source it and
correctly declined to guess. Those gaps fill from real play via `trainer_spells`.

**This file exists because of a mistake worth recording.** It previously shared `Catalogue.lua`
with generated output. I briefed an extraction agent that the file was a near empty stub, which
was wrong, and the agent overwrote it exactly as instructed, destroying research from an earlier
workflow. It had made a backup, so nothing was lost.

The durable fix is the split: generated data and researched data now never share a filename, so
a build script rerunning can only ever clobber its own output.

### Data/StatWeights.lua and ItemEval.lua

| | |
|---|---|
| Source | Research workflow, 12 agents, then an adversarial audit |
| Contents | Stat weights, caps and gearing rules for **16 of 27 specs**, plus a scoring engine |
| Confidence | Roughly 70 percent by its own audit. Warrior and Druid have **no data at all** |

This is the layer that lets an item be judged properly rather than by item level. It works on
any item that will ever exist, because the client supplies the stats and this supplies the
meaning.

Warrior and Druid were deliberately excluded rather than shipped as guesses. Code reading this
table must treat a missing class as "no data", never as a zero score. `ItemEval` already does:
it returns nil with a plain English reason and a low confidence marker.

**Reachable but not yet automatic.** `/gearscout score [item]` and `/gearscout caps` use it.
The gear tab still judges by item level, because 70 percent confidence is not enough to silently
change the advice a player acts on.

#### The defense cap incident, worth reading before trusting any audit

The audit reported that the tank crit immunity threshold of **490 defense skill was a Wrath era
number** and that the correct TBC figure was 415. The assembler believed it and wrote 415 into
the shipped file, in six places, describing the old value as a safety hazard.

The audit was wrong. Verified directly against warcraft.wiki.gg: base defense is five times
level, so 350 at level 70. Removing 5.6 percent crit at 0.04 percent per point needs 140 more
points. 350 plus 140 is **490**, and the page says so outright. The conversion is 2.36 defense
rating per skill point, so 140 skill is about 331 rating from gear.

A tank following 415 would have believed they were crit immune while 75 defense skill short.
That is precisely the hazard the audit named, inverted and introduced by the audit itself.

Reverted by hand, with the reasoning kept in the file header.

The audit was not useless: its melee hit correction, 10.2 rating to 15.77 per percent, was right,
as was removing armor penetration, which did not exist in TBC. **The lesson is narrower and more
useful than "audits are unreliable": an auditor told to find faults will sometimes manufacture
one, so a safety critical number needs independent verification rather than a second opinion.**

### Sources.lua, turning data into answers

The shipped tables are only worth having if something asks them questions. This file does.

| Function | Answers |
|---|---|
| `ns.DescribeEnchantSource(slotID)` | Which faction sells the head or shoulder enchant, and at what standing. Now feeds the gear advice directly |
| `ns.GetItemSource(itemID)` | Which instance and boss drops an item. O(1) lookup |
| `ns.FindSlotUpgrades(slotID, minIlvl)` | What drops near your level that beats what you wear in that slot |

The enchant mapping is derived from the reward names in the extracted data rather than a hand
written faction list, so regenerating the catalogue keeps it correct. Head enchants are Glyphs
and Arcanums, shoulder enchants are Inscriptions. It reports the easiest standing that has one,
since that is the one worth telling somebody about.

`FindSlotUpgrades` is bounded on purpose: only instances suiting the character's level, and the
shipped `ItemDB` rejects wrong item level, wrong armor type and too high a level requirement
before the client is asked about anything. Only the survivors are looked up, and looking one up
caches it, so the answer sharpens each run. It reports how many are still loading rather than
presenting a partial list as final.

### Where the player actually sees this

Data nobody encounters may as well not exist, so:

| Surface | Shows |
|---|---|
| Weak link row in the gear tab | The real boss and instance that drops a replacement, not just "go upgrade it" |
| Bag and quest reward rows | Where that item drops, added once in the provider wrapper rather than in each module |
| Item tooltips | Drop source, and whether it beats what you wear, when the spec has trusted weights |

The tooltip hook supports both the current `TooltipDataProcessor` path and the older
`OnTooltipSetItem` path, since this client straddles them. It is wrapped and **disables itself
after three failures**: a tooltip handler runs on every mouse move, so one that throws would
bury the player in red text, which is far worse than the feature quietly not appearing.

---

## Optional, from other addons

Never required. Each is detected at runtime and ignored when absent.

| Addon | What it adds | Access |
|---|---|---|
| **Details** | Damage per spell, damage per second, activity time, pet damage | Only functions marked exported in its own `API.lua`, every call wrapped |
| **TSM** | Real auction prices, via `TSM_API.GetCustomPriceValue` | Not yet wired in |
| **Auctionator** | Price fallback | Not yet wired in |

Details cannot supply miss data. Its exported spell table only carries outcomes that still land
damage: resisted, blocked, absorbed, glancing. A full dodge, parry or miss never generates a
damage line. So misses come from the combat log instead.

---

## Collected from play, uploaded to Turso

`Collector.lua` records **game facts only**, into `GearScoutData`.

| Table | Fields |
|---|---|
| drops | item id, creature id, zone id, zone name, first seen |
| item_meta | item id, item level, quality, equip location, required level |
| quest_rewards | quest id, item id |
| vendor_prices | item id, vendor id, price in copper |
| trainer_spells | class, spell name, rank, level required, client locale |

### Why trainer_spells exists

Spell rank data cannot be obtained any other way. AtlasLoot ships no spell data, and Wowhead's
rank tables are JavaScript rendered so they cannot be fetched. Two research agents tried and
both correctly refused to invent it.

But a class trainer window hands the client every spell it offers along with the level it
unlocks at, which is exactly the rank to level mapping wanted. So it gets read for free whenever
a player happens to open a trainer, and flows back out through the same pipeline.

This is the first thing in the project that genuinely needs the Turso loop rather than merely
being able to use it. One player cannot visit every class trainer. Many players collectively can.

Profession trainers offer recipes rather than ranked spells, so requiring both a rank number and
a level requirement naturally selects class spells and leaves recipes alone. The trainer's filter
settings are read and never written, since changing them would rearrange the player's own UI.

Spell names are localized, so every row carries the client locale to stop two languages
overwriting each other.

Verified with a fixture end to end: five hunter rank rows parsed, shaped and staged for upload
correctly.

**Nothing recorded identifies a person.** No player names, no loot recipients, no group rosters.
The GUID helper only accepts Creature and Vehicle kinds, so a player GUID is rejected outright.
This is deliberate: the addon makes an explicit promise to its users about what leaves their
machine, and a collector that quietly contradicted it would make that settings screen a lie.

Event driven, no timers, no combat log, deduplicated on write, and each table capped so a long
session cannot bloat the saved variables file.

**The pipeline is proven, not theoretical.** The schema was applied to the real database, rows
were upserted and read back, re-running the same session left counts unchanged, and the test
rows were then deleted leaving the schema in place.

Credentials live in the machine secrets store as `turso.url` and `turso.token`, never in the
repo. Export with `node tools/export-session.mjs`, which defaults to `--dry-run` when the
environment variables are absent.

---

## Verification tooling

Two scripts, both in the session scratchpad.

**`check.js`** parses every Lua file with luaparse. Catches syntax errors before the game does.

**`verify-data.mjs`** parses the generated data files and evaluates their tables, then checks
what the game will actually load. It validates that every tracked spell carries the number its
own kind requires, that every loot item resolves to a known instance, and that level ranges are
sane.

Worth knowing that this script had a bug of its own: luaparse leaves `value` as null on string
nodes unless an encoding mode is set, so every string became `null` and 3570 perfectly good
entries looked malformed. **A verifier that reports success is only as trustworthy as its own
correctness.**

---

## Honest gaps

| Gap | Status |
|---|---|
| Nothing rendered in game | Syntax and structure are machine checked. Behaviour is not. The first reload is the real test. |
| Gems, meta gem requirements | Being re-researched |
| Reputation rewards, head and shoulder enchant sources | Being re-researched |
| Spell rank tables | Web research failed twice, correctly. Now gathered from real play via `trainer_spells`, which needs players to visit trainers before it fills up |
| Enchants, ammo, consumables | Returned empty from the first workflow |
| Stat weights and item evaluation | Workflow still running |
| Weapon proficiency table in `Bags.lua` | Hand authored, not verified. Errs toward refusing rather than recommending. |
| Complete item database | Investigated properly, see below |
| Warrior and Druid stat weights | No usable research. Excluded rather than guessed |
| Item scoring in the gear tab | Engine loaded and testable by slash command, not yet automatic |

---

## Is there a complete item database on this machine?

Investigated thoroughly. The honest answer is **no, but two thirds of one exists**, and nothing
on disk carries item stats at all.

| Field | Best source on disk | Coverage of our 3570 loot ids |
|---|---|---|
| id, name, item level, required level, class, subclass | **Questie** `Database/TBC/tbcItemDB.lua` | **99.1 percent** |
| quality, equip slot | TSM runtime cache | 11.9 percent |
| stats | nothing | 0 percent |

**Questie is the find worth acting on.** 3.29 MB of plain Lua, 25,010 items of which 16,071 are
weapons or armor, trivially parseable. Its accuracy was not assumed: cross checking the 8,640
items that also appear in TSM's cache gave 100 percent agreement on item level, required level,
class and subclass, and 99.8 percent on name. It is reproducible on any machine with Questie.

TSM ships no static item database. Its runtime cache does carry quality and equip slot, and was
successfully decoded, but it covers only what that account happened to see, misses essentially
all raid epics, and would not reproduce on another machine. Not a build input.

Auctionator, AtlasLoot and Pawn carry nothing extra. The client no longer writes an
`itemcache.wdb`, so that classic route is dead.

The only complete source is the CASC store in `D:\World of Warcraft\Data`, where `ItemSparse.db2`
holds everything including stats. That is an extraction project needing a CASC reader, a DB2
reader and build specific column definitions, realistically several days and fragile across
client patches. Not promised, not started.

**Recommended shape: hybrid.** Take Questie at build time for the bulk fields, keep reading
stats live from the client, which is where they were always going to come from anyway.

---

## Switches

| Command | Effect |
|---|---|
| `/gearscout` | Open the window |
| `/gearscout rot` | Spell and profile diagnostic, including which data set is live |
| `/gearscout where` | Dungeon drops near your level that beat your weakest slot |
| `/gearscout score [item]` | Score a shift clicked item against what you wear, using stat weights |
| `/gearscout caps` | Which stat caps your spec has and whether you meet them |
| `/gearscout data research` or `builtin` | Swap rotation data source |
| `/gearscout skin obsidian` or `slate` | Swap the visual theme, slate is the original flat look |
| `/gsl` | Officer console |
