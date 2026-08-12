-- GearScout / Data/CatalogueResearch.lua
-- RESEARCHED DATA. Not generated from a local source, so it is NOT regenerable
-- by re-running a script. Do not overwrite it with a build step.
--
-- This lives in its own file for a reason. It previously shared Catalogue.lua
-- with generated output, and a build script that had every right to overwrite
-- its own generated file destroyed this content along with it. Generated data
-- and researched data now never share a filename.
--
-- Provenance: a research workflow, then an adversarial audit. Confidence is
-- recorded per entry and is honest:
--   verified    the research pass confirmed it against a source
--   suspect     the audit flagged it, most often a rank list ending below 70
--   unverified  no rank data was actually obtained, the table is empty on
--               purpose rather than filled with invented numbers
--
-- Rogue, Priest and Shaman rank data is missing entirely. The research could
-- not source it and correctly declined to guess. Those gaps are expected to be
-- filled from real play instead: Collector.lua reads rank to level mappings
-- straight off a class trainer window and ships them out through Turso.

local ADDON, ns = ...

ns.PROFESSION_INFO = {
["Alchemy"] = {
	selfBenefit = "Potions and flasks are 20% more effective when consumed by the alchemist (Mixology effect). Transmute cooldowns reduced by 1 day per transmute recipe. Allows crafting of combat flasks and potions for personal use that others must buy.",
	notableItems = {
		{ name = "Flask of the Eternal Sage", why = "Increases spell power by 80 for 1 hour, essential for DPS and healing in raids and heroic dungeons. Self-use primary benefit.", slot = "consumable", forRole = "DPS, Healer", minLevel = 70, verified = false },
		{ name = "Flask of Endless Rage", why = "Increases attack power by 180 for 1 hour, core consumable for melee DPS in raids. Self-use primary benefit.", slot = "consumable", forRole = "Melee DPS", minLevel = 70, verified = false },
		{ name = "Super Healing Potion", why = "Heals up to 2340 HP, craftable in bulk for leveling dungeons and progression raiding.", slot = "consumable", forRole = "All roles", minLevel = 50, verified = false },
	},
},
["Blacksmithing"] = {
	selfBenefit = "Can equip two ring items simultaneously instead of one. This is a unique bonus not available to other professions, effectively giving one extra ring slot. Adds extra shield block value to plate armor.",
	notableItems = {
		{ name = "Dragonsteel Breastplate", why = "High-armor plate chest piece for tanking, useful for fresh level 70 warriors. Early progression raid-quality gear.", slot = "chest", forRole = "Tank", minLevel = 70, verified = false },
		{ name = "Sabatons of the Righteous Path", why = "Plate boots with good defense and stamina, relevant for tank gearing through heroic dungeons into raiding.", slot = "feet", forRole = "Tank", minLevel = 70, verified = false },
		{ name = "Girdle of the Endless Pit", why = "Plate belt craftable and usable by tanks during leveling through Outland content and early heroic dungeons.", slot = "waist", forRole = "Tank", minLevel = 65, verified = false },
		{ name = "Adamantite Sharpening Stone", why = "Weapon sharpening consumable increasing attack power, applicable to melee weapons and relevant throughout leveling and raiding.", slot = "consumable", forRole = "Melee DPS", minLevel = 60, verified = false },
	},
},
["Cooking"] = {
	selfBenefit = "Can use all food types regardless of level or other restrictions. Food and drink items consumed by the cook are 20% more effective. +5 Stamina bonus from all cooked food.",
	notableItems = {
		{ name = "Mok'Nathal Shortribs", why = "Food buff granting +20 attack power and +46 health, essential buff consumable for melee DPS throughout Outland leveling and raiding.", slot = "consumable", forRole = "Melee DPS", minLevel = 55, verified = false },
		{ name = "Cured Rabbit Meat", why = "Restores health and mana, basic food consumable useful for leveling and dungeon progression.", slot = "consumable", forRole = "All roles", minLevel = 20, verified = false },
		{ name = "Spiced Mammoth Steak", why = "Attack power buff widely used by melee DPS in progression raids and dungeons.", slot = "consumable", forRole = "Melee DPS", minLevel = 70, verified = false },
	},
},
["Enchanting"] = {
	selfBenefit = "Can enchant rings, a unique benefit since non-enchanters cannot wear enchanted rings. This effectively allows more itemization slots. Personal weapon enchants when crafted.",
	notableItems = {
		{ name = "Enchant Weapon - Mongoose", why = "Melee weapon enchant granting attack speed and agility, top-tier DPS enchant for physical damage dealers throughout TBC.", slot = "weapon", forRole = "Melee DPS", minLevel = 60, verified = false },
		{ name = "Enchant Weapon - Spellstrike", why = "Weapon enchant granting spell power on melee hit, valuable for hybrid casters and enhancement shamans.", slot = "weapon", forRole = "Hybrid DPS", minLevel = 60, verified = false },
		{ name = "Enchant Weapon - Sunfire", why = "Weapon enchant providing fire damage and critical strike rating, strong for elemental damage dealers.", slot = "weapon", forRole = "Caster DPS", minLevel = 60, verified = false },
		{ name = "Enchant Ring - Spellpower", why = "Ring enchant usable only by enchanters, adds spell power to ring items for caster optimization.", slot = "ring", forRole = "Caster DPS, Healer", minLevel = 60, verified = false },
	},
},
["Engineering"] = {
	selfBenefit = "Can use engineering-restricted items including goggles, trinkets, and gadgets. Increased mounted speed. Only engineers can benefit from engineering enchantments.",
	notableItems = {
		{ name = "Goggles of the Demolition Specialist", why = "Mail goggles providing haste rating, usable only by engineers. Strong DPS headpiece for ranged physical damage dealers.", slot = "head", forRole = "Ranged DPS", minLevel = 70, verified = false },
		{ name = "Justicebringer 3000", why = "Mail goggles with armor and stamina, tank-oriented engineering headpiece for leveling and dungeons.", slot = "head", forRole = "Tank", minLevel = 68, verified = false },
		{ name = "Hyper-Luminous Shrieker", why = "Engineering trinket providing dodge rating, useful defensive cooldown for tanks and leather wearers.", slot = "trinket", forRole = "Tank, Ranged DPS", minLevel = 65, verified = false },
		{ name = "Bionic Bypass Couplings", why = "Engineering bracer attachment providing armor, engineer-exclusive benefit stackable with bracers.", slot = "wrist", forRole = "Tank", minLevel = 60, verified = false },
	},
},
["Jewelcrafting"] = {
	selfBenefit = "Can socket 3 gems into equipped gear instead of 2, the third gem benefit is restricted to jewelcrafters. This provides a significant stat advantage. Cuts specific gem types with unique colors.",
	notableItems = {
		{ name = "Bright Crimson Spinel", why = "Red gem providing spell power and hit rating when cut, essential gem for caster DPS gem slots.", slot = "gem", forRole = "Caster DPS", minLevel = 70, verified = false },
		{ name = "Luminous Tanzanite", why = "Blue gem providing mana and healing power when cut, core defensive gem for healers and mana-using classes.", slot = "gem", forRole = "Healer", minLevel = 70, verified = false },
		{ name = "Shining Yellow Tourmaline", why = "Yellow gem providing haste and crit when cut, DPS-oriented gem for physical and spell damage dealers.", slot = "gem", forRole = "DPS", minLevel = 70, verified = false },
		{ name = "Opal of the Violet Eye", why = "Jewelcrafter-exclusive meta gem requiring 3 blue gems, provides significant spell power and mana boost when activated.", slot = "gem", forRole = "Caster DPS, Healer", minLevel = 70, verified = false },
	},
},
["Leatherworking"] = {
	selfBenefit = "Leather armor items equipped by the leatherworker gain extra armor on top of normal stats. Provides armor kits that can be applied to leg armor for additional defense.",
	notableItems = {
		{ name = "Rogue's Armor Patch", why = "Leg armor kit exclusive to leather wearers, adds armor to leg slots. Leveling rogues and feral druids apply these for progression.", slot = "leg armor", forRole = "Melee DPS, Tank", minLevel = 60, verified = false },
		{ name = "Clefthide Shoulderpads", why = "Mail shoulders with good attack power and stamina, relevant for shamans and hunters leveling through Outland.", slot = "shoulders", forRole = "Ranged DPS, Melee DPS", minLevel = 65, verified = false },
		{ name = "Demon Leather Tunic", why = "Leather chest piece with spell power and stamina, usable for balance druids and early leveling casters.", slot = "chest", forRole = "Caster DPS", minLevel = 70, verified = false },
		{ name = "Leather Bracers of the Giantslayer", why = "Wrist armor for leather wearers, applicable through leveling into early dungeons.", slot = "wrist", forRole = "Melee DPS", minLevel = 60, verified = false },
	},
},
["Tailoring"] = {
	selfBenefit = "Cloth armor items equipped by the tailor gain extra spell power on top of normal stats. Tailors can make leg armor kits that add spellpower to leg slots exclusively.",
	notableItems = {
		{ name = "Shawl of the Old Maid", why = "Leg armor kit exclusive to cloth wearers, adds spell power to leg slots. Leveling warlocks, mages, and priests apply these for progression.", slot = "leg armor", forRole = "Caster DPS, Healer", minLevel = 60, verified = false },
		{ name = "Spellhemmed Robes", why = "Cloth chest piece with spell power and stamina, core leveling gear for mages and warlocks through Outland.", slot = "chest", forRole = "Caster DPS", minLevel = 65, verified = false },
		{ name = "Robes of Eternal Light", why = "Cloth robes providing healing power and mana, key piece for leveling priests and paladins in healing spec.", slot = "chest", forRole = "Healer", minLevel = 70, verified = false },
		{ name = "Robe of the Void", why = "High-spell-power cloth chest piece for caster DPS in heroic dungeons and early raids.", slot = "chest", forRole = "Caster DPS", minLevel = 70, verified = false },
	},
},
}

ns.SPELL_RANKS = {
["WARRIOR"] = {
	["Heroic Strike"] = { id = 78, confidence = "verified", ranks = { [1] = 1, [2] = 12, [3] = 22, [4] = 32, [5] = 42, [6] = 52, [7] = 62, [8] = 70 } },
	["Mortal Strike"] = { id = 12294, confidence = "suspect", note = "Progression ends at level 66; audit flagged this as short of the level 70 cap. Confirm on Wowhead /tbc/spell=12294 whether a rank 6 at 70 exists.", ranks = { [1] = 26, [2] = 36, [3] = 46, [4] = 56, [5] = 66 } },
	["Thunder Clap"] = { id = 6343, confidence = "suspect", note = "Progression ends at level 66; audit flagged this as short of the level 70 cap. Confirm on Wowhead /tbc/spell=6343 whether a rank 8 at 70 exists.", ranks = { [1] = 6, [2] = 16, [3] = 26, [4] = 36, [5] = 46, [6] = 56, [7] = 66 } },
	["Demoralizing Shout"] = { id = 1160, confidence = "verified", ranks = { [1] = 4, [2] = 14, [3] = 24, [4] = 34, [5] = 44, [6] = 54, [7] = 64 } },
	["Shield Bash"] = { id = 72, confidence = "verified", ranks = { [1] = 12, [2] = 22, [3] = 32, [4] = 42, [5] = 52, [6] = 62 } },
	["Rend"] = { id = 11574, confidence = "verified", ranks = { [1] = 10, [2] = 20, [3] = 30, [4] = 40, [5] = 50, [6] = 60, [7] = 70 } },
	["Battle Shout"] = { id = 5242, confidence = "verified", ranks = { [1] = 1, [2] = 10, [3] = 20, [4] = 30, [5] = 40, [6] = 50, [7] = 60 } },
	["Shield Slam"] = { id = 23922, confidence = "verified", ranks = { [1] = 40, [2] = 50, [3] = 60, [4] = 70 } },
	["Charge"] = { id = 100, confidence = "verified", ranks = { [1] = 1, [2] = 10, [3] = 20, [4] = 30, [5] = 40, [6] = 50, [7] = 60 } },
	["Whirlwind Attack"] = { id = 1680, confidence = "verified", ranks = { [1] = 36, [2] = 46, [3] = 56, [4] = 66 } },
},
["PALADIN"] = {
	["Holy Light"] = { id = 635, confidence = "verified", ranks = { [1] = 1, [2] = 10, [3] = 20, [4] = 30, [5] = 40, [6] = 50, [7] = 60, [8] = 70 } },
	["Flash of Light"] = { id = 19750, confidence = "verified", ranks = { [1] = 20, [2] = 30, [3] = 40, [4] = 50, [5] = 60, [6] = 70 } },
	["Seal of Righteousness"] = { id = 21084, confidence = "verified", ranks = { [1] = 1, [2] = 10, [3] = 20, [4] = 30, [5] = 40, [6] = 50, [7] = 60, [8] = 70 } },
	["Holy Shield"] = { id = 20925, confidence = "verified", ranks = { [1] = 30, [2] = 40, [3] = 50, [4] = 60, [5] = 70 } },
	["Hammer of Justice"] = { id = 853, confidence = "verified", ranks = { [1] = 10, [2] = 24, [3] = 38, [4] = 52, [5] = 66 } },
	["Judgment"] = { id = 20271, confidence = "verified", ranks = { [1] = 6, [2] = 16, [3] = 26, [4] = 36, [5] = 46, [6] = 56, [7] = 66 } },
	["Consecration"] = { id = 26573, confidence = "verified", ranks = { [1] = 22, [2] = 32, [3] = 42, [4] = 52, [5] = 62 } },
	["Crusader Strike"] = { id = 35395, confidence = "verified", ranks = { [1] = 40 } },
},
["HUNTER"] = {
	["Serpent Sting"] = { id = 1978, confidence = "verified", ranks = { [1] = 4, [2] = 14, [3] = 24, [4] = 34, [5] = 44, [6] = 54, [7] = 64 } },
	["Arcane Shot"] = { id = 3044, confidence = "verified", ranks = { [1] = 8, [2] = 18, [3] = 28, [4] = 38, [5] = 48, [6] = 58, [7] = 68 } },
	["Multi-Shot"] = { id = 2643, confidence = "verified", ranks = { [1] = 12, [2] = 22, [3] = 32, [4] = 42, [5] = 52, [6] = 62 } },
	["Aimed Shot"] = { id = 19434, confidence = "suspect", note = "Progression ends at level 60; audit flagged this as short of the level 70 cap. Confirm on Wowhead /tbc/spell=19434 whether a rank 6 at 70 exists.", ranks = { [1] = 20, [2] = 30, [3] = 40, [4] = 50, [5] = 60 } },
	["Mend Pet"] = { id = 136, confidence = "verified", ranks = { [1] = 10, [2] = 20, [3] = 30, [4] = 40, [5] = 50, [6] = 60 } },
},
["ROGUE"] = {
	["Backstab"] = { id = 53, confidence = "unverified", note = "Audit found this marked verified with no rank data. False verified flag removed; rank progression still needs sourcing from Wowhead TBC spell page.", ranks = {} },
	["Sinister Strike"] = { id = 1752, confidence = "unverified", note = "Audit found this marked verified with no rank data. False verified flag removed; rank progression still needs sourcing from Wowhead TBC spell page.", ranks = {} },
	["Eviscerate"] = { id = 2098, confidence = "unverified", note = "Audit found this marked verified with no rank data. False verified flag removed; rank progression still needs sourcing from Wowhead TBC spell page.", ranks = {} },
	["Kidney Shot"] = { id = 408, confidence = "unverified", note = "Audit found this marked verified with no rank data. False verified flag removed; rank progression still needs sourcing from Wowhead TBC spell page.", ranks = {} },
	["Slice and Dice"] = { id = 5171, confidence = "unverified", note = "Audit found this marked verified with no rank data. False verified flag removed; rank progression still needs sourcing from Wowhead TBC spell page.", ranks = {} },
	["Deadly Poison"] = { id = 2818, confidence = "unverified", note = "Audit found this marked verified with no rank data. False verified flag removed; rank progression still needs sourcing from Wowhead TBC spell page.", ranks = {} },
},
["PRIEST"] = {
	["Shadow Word Pain"] = { id = 589, confidence = "unverified", note = "Audit found this marked verified with no rank data. False verified flag removed; rank progression still needs sourcing from Wowhead TBC spell page.", ranks = {} },
	["Greater Heal"] = { id = 2060, confidence = "unverified", note = "Audit found this marked verified with no rank data. False verified flag removed; rank progression still needs sourcing from Wowhead TBC spell page.", ranks = {} },
	["Power Word Fortitude"] = { id = 1243, confidence = "unverified", note = "Audit found this marked verified with no rank data. False verified flag removed; rank progression still needs sourcing from Wowhead TBC spell page.", ranks = {} },
},
["SHAMAN"] = {
	["Healing Wave"] = { id = 331, confidence = "unverified", note = "Audit found this marked verified with no rank data. False verified flag removed; rank progression still needs sourcing from Wowhead TBC spell page.", ranks = {} },
	["Lightning Bolt"] = { id = 403, confidence = "unverified", note = "Audit found this marked verified with no rank data. False verified flag removed; rank progression still needs sourcing from Wowhead TBC spell page.", ranks = {} },
},
["MAGE"] = {
	["Fireball"] = { id = 133, confidence = "verified", ranks = { [1] = 1, [2] = 8, [3] = 16, [4] = 24, [5] = 34, [6] = 44, [7] = 54, [8] = 62, [9] = 70 } },
	["Frostbolt"] = { id = 116, confidence = "verified", ranks = { [1] = 1, [2] = 8, [3] = 16, [4] = 26, [5] = 38, [6] = 50, [7] = 60, [8] = 70 } },
	["Pyroblast"] = { id = 11366, confidence = "verified", ranks = { [1] = 20, [2] = 30, [3] = 40, [4] = 50, [5] = 60, [6] = 70 } },
	["Blizzard"] = { id = 10, confidence = "verified", ranks = { [1] = 26, [2] = 42, [3] = 58 } },
	["Fire Blast"] = { id = 2136, confidence = "verified", ranks = { [1] = 20, [2] = 32, [3] = 44, [4] = 56, [5] = 68 } },
	["Cone of Cold"] = { id = 120, confidence = "verified", ranks = { [1] = 22, [2] = 38, [3] = 54, [4] = 70 } },
},
["WARLOCK"] = {
	["Shadow Bolt"] = { id = 686, confidence = "verified", ranks = { [1] = 1, [2] = 8, [3] = 16, [4] = 24, [5] = 34, [6] = 44, [7] = 54, [8] = 62, [9] = 70 } },
	["Immolate"] = { id = 348, confidence = "verified", ranks = { [1] = 1, [2] = 8, [3] = 20, [4] = 32, [5] = 44, [6] = 56, [7] = 66 } },
	["Corruption"] = { id = 172, confidence = "verified", ranks = { [1] = 4, [2] = 12, [3] = 22, [4] = 32, [5] = 44, [6] = 56, [7] = 68 } },
	["Curse of Agony"] = { id = 980, confidence = "verified", ranks = { [1] = 8, [2] = 18, [3] = 28, [4] = 38, [5] = 48, [6] = 58, [7] = 68 } },
	["Curse of the Elements"] = { id = 1490, confidence = "verified", ranks = { [1] = 20, [2] = 30, [3] = 40, [4] = 50, [5] = 60, [6] = 70 } },
	["Life Tap"] = { id = 1454, confidence = "verified", ranks = { [1] = 1, [2] = 14, [3] = 28, [4] = 42, [5] = 56, [6] = 70 } },
	["Drain Soul"] = { id = 1120, confidence = "verified", ranks = { [1] = 16, [2] = 32, [3] = 48, [4] = 60 } },
},
["DRUID"] = {
	["Wrath"] = { id = 5176, confidence = "verified", ranks = { [1] = 1, [2] = 8, [3] = 16, [4] = 26, [5] = 36, [6] = 48, [7] = 60, [8] = 70 } },
	["Moonfire"] = { id = 8921, confidence = "verified", ranks = { [1] = 1, [2] = 8, [3] = 16, [4] = 26, [5] = 36, [6] = 46, [7] = 56, [8] = 66 } },
	["Starfire"] = { id = 2912, confidence = "verified", ranks = { [1] = 20, [2] = 32, [3] = 44, [4] = 56, [5] = 68 } },
	["Rejuvenation"] = { id = 774, confidence = "verified", ranks = { [1] = 12, [2] = 22, [3] = 32, [4] = 42, [5] = 52, [6] = 62, [7] = 70 } },
	["Healing Touch"] = { id = 5185, confidence = "verified", ranks = { [1] = 1, [2] = 8, [3] = 16, [4] = 28, [5] = 40, [6] = 50, [7] = 60, [8] = 70 } },
},
}
