-- GearScout / Data/StatWeights.lua
-- Generated from an external stat weight research pass for World of Warcraft:
-- The Burning Crusade, patch 2.4.3, level 70, as played on the Anniversary
-- realms. A follow up audit checked the research for wrong and suspect
-- numbers before this file was written, and every finding below is already
-- applied.
--
-- DO NOT HAND EDIT THIS FILE. It is regenerated from research data and any
-- direct edits will be overwritten the next time that happens. Fix problems
-- upstream, in the research or audit pass, not here.
--
-- Audit findings applied in this file:
--   1. Melee hit rating conversion was listed at 10.2 rating per 1 percent,
--      a Wrath value. Corrected to 15.77, the TBC 2.4.3 value. This also
--      matches the math the hunter and retribution paladin cap notes were
--      already using (142 rating divided by 9 percent equals 15.77).
--   2. WITHDRAWN. The audit claimed the defense cap of 490 defense skill was
--      a Wrath number and that 415 was correct for TBC. The audit was wrong,
--      and its "correction" was applied to this file before being checked.
--      It has now been reverted by hand.
--      Verified against warcraft.wiki.gg: base defense is 5 times level, so
--      350 at level 70. Immunity to critical hits from a mob three levels
--      higher needs 5.6 percent removed at 0.04 percent per defense point,
--      which is 140 further points. 350 plus 140 is 490. The page states it
--      outright: "Critical Hit immunity for a level 70 player against a raid
--      boss occurs at 490 Defense". The conversion is 2.36 defense rating per
--      point of defense skill at level 70, so 140 skill is about 331 rating
--      from gear, which is close to the 332 the research originally gave.
--      This was the most dangerous error in the whole dataset and it came
--      from the auditor rather than the researcher. A tank following 415
--      would have believed they were crit immune while 75 defense skill
--      short, and would have taken unmitigated critical hits.
--      Lesson worth keeping: an auditor instructed to find faults will
--      sometimes manufacture one, so a safety critical number needs its own
--      verification and not just a second opinion.
--   3. "Ranged Weapon DPS" was listed as a per point ITEM_MOD_* stat weight
--      (2.4) on all three hunter specs. It is not a stat key the game hands
--      out per point the way Agility or hit rating are. A weapon's damage
--      per second is a property of the whole weapon, not something you sum
--      across an item's stat list. It has been removed from the weights
--      table. The dominance the research was trying to express is kept as
--      weaponDPSWeight, a separate plain named field. ItemEval.lua reads
--      that field to score a hunter's ranged weapon by its own damage per
--      second, on top of, not folded into, the normal stat weight sum.
--   4. ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT was present as a real stat,
--      14 rating per 1 percent, and weighted 0.09 on Retribution Paladin,
--      even though the hunter hard rules correctly say armor penetration
--      did not exist until Wrath 3.0. Removed from the conversion table and
--      from every spec that carried it. A Retribution Paladin hard rule
--      that discussed armor penetration as if it were itemizable in TBC was
--      dropped for the same reason.
--   5. Warrior (Arms, Fury, Protection) and Druid (Balance, Feral Cat,
--      Feral Bear, Restoration) had no usable research, only placeholder
--      text. They are left out of this file entirely instead of being
--      shipped as empty or guessed entries. See EXCLUDED below. Code that
--      reads this table must treat a missing class or tab as "no data", not
--      as a zero score.
--   6. Paladin Protection also carried ITEM_MOD_ARMOR as a weighted stat.
--      ITEM_MOD_ARMOR is not one of the confirmed stat keys this addon was
--      given to read (see the ITEM_MOD_* list in the research brief), so it
--      was pulled out of the numeric weight table and kept only as a plain
--      English note under hardRules. Do not add it back as a weight until a
--      real stat key for it is confirmed against ns.GetStats output.
--   7. Hunter hit cap wording was uniform ("below 142 rating, shots miss")
--      and ignored the common raid buffed case. Reworded below to state the
--      unbuffed number and the buffed number (79 rating with Improved
--      Faerie Fire and Heroic Presence) side by side.
--
-- Confidence markers were left exactly as the research pass reported them,
-- with one exception: Paladin Protection was reported "high" but carried
-- the crit immunity error above, which the audit graded a safety hazard.
-- It is marked "medium" here until an independent pass re-checks the
-- corrected cap. The four specs the audit named as trustworthy after fixes,
-- Shadow Priest, Hunter Survival, Retribution Paladin and Holy Paladin,
-- keep the confidence the research reported.
--
-- The discrepancy previously flagged here is resolved. It existed only
-- because the audit's false 415 figure disagreed with its own worked rating
-- number. With the real threshold restored the arithmetic is consistent:
-- 490 total defense skill, 350 of it free from being level 70, so 140 skill
-- from gear, at 2.36 defense rating per skill point, is about 331 defense
-- rating on your gear.
--
-- Weight numbers are per one point of the raw stat as it appears in the
-- item's stat table (the same convention tools like Pawn use): multiply the
-- item's stat value by the weight and add it to the running score. Every
-- spec below is already normalised so its single most valuable primary
-- stat weighs 1.0, which is what lets ItemEval.lua compare items across
-- specs without any extra tuning.

local ADDON, ns = ...

ns.STAT_WEIGHTS = {}
local SW = ns.STAT_WEIGHTS

-- ---------------------------------------------------------------------------
-- rating conversions, level 70, TBC 2.4.3
-- perPercent is how much of that rating a level 70 character needs for 1
-- percent of the effect. Armor penetration is deliberately absent: it is a
-- Wrath 3.0 stat and does not exist on this client.
-- ---------------------------------------------------------------------------
SW.RATING_CONVERSIONS = {
    ITEM_MOD_HIT_RATING_SHORT = {
        perPercent = 15.77,
        note = "Melee and ranged hit rating at level 70. Corrected from an audit finding of 10.2, which is the Wrath value.",
    },
    ITEM_MOD_HIT_SPELL_RATING_SHORT = {
        perPercent = 12.6,
        note = "Spell hit rating at level 70.",
    },
    ITEM_MOD_CRIT_RATING_SHORT = {
        perPercent = 14.3,
        note = "Melee crit rating at level 70.",
    },
    ITEM_MOD_CRIT_SPELL_RATING_SHORT = {
        perPercent = 14.3,
        note = "Spell crit rating at level 70.",
    },
    ITEM_MOD_HASTE_RATING_SHORT = {
        perPercent = 10,
        note = "Melee haste rating at level 70.",
    },
    ITEM_MOD_HASTE_SPELL_RATING_SHORT = {
        perPercent = 10,
        note = "Spell haste rating at level 70.",
    },
    ITEM_MOD_EXPERTISE_RATING_SHORT = {
        perPercent = 3.9,
        note = "3.9 rating buys 1 full expertise point. Each expertise point removes 0.25 percent chance the boss dodges or parries you.",
    },
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = {
        perPercent = 1.5,
        note = "2.36 rating buys 1 defense skill point at level 70.",
    },
    ITEM_MOD_DODGE_RATING_SHORT = {
        perPercent = 12,
        note = "Dodge rating at level 70.",
    },
    ITEM_MOD_PARRY_RATING_SHORT = {
        perPercent = 12,
        note = "Parry rating at level 70.",
    },
    ITEM_MOD_BLOCK_RATING_SHORT = {
        perPercent = 12,
        note = "Block rating at level 70.",
    },
    ITEM_MOD_RESILIENCE_RATING_SHORT = {
        perPercent = 2.4,
        note = "Resilience rating at level 70. Reduces damage taken in PvP only, worth nothing in a PvE raid.",
    },
}

-- ---------------------------------------------------------------------------
-- boss assumptions, level 73 raid boss, TBC 2.4.3
-- ---------------------------------------------------------------------------
SW.BOSS_ASSUMPTIONS = {
    { name = "Boss Level", value = "73",
      note = "Raid bosses in TBC dungeons and raids are level 73, three levels above the level 70 player cap." },
    { name = "Melee Miss Chance", value = "9 percent",
      note = "Base 5 percent miss plus 4 percent from the boss being 3 levels higher." },
    { name = "Spell Miss Chance", value = "16 percent",
      note = "Base miss chance for spells against a level 73 boss with no talents or buffs." },
    { name = "Dodge Removal", value = "26 expertise points, about 104 expertise rating",
      note = "Expertise removes dodge chance from raid bosses. About 26 expertise points removes all dodgeable attacks." },
    { name = "Crit Immunity Defense", value = "490 defense skill",
      note = "Defense skill of 490 makes you immune to critical hits from a level 73 raid boss. That is 350 free from being level 70, plus 140 more from your gear, which is about 331 defense rating at 2.36 rating per skill point. Verified directly against warcraft.wiki.gg after an audit wrongly claimed the number was 415." },
}

-- ---------------------------------------------------------------------------
-- armor types
-- Scan.lua already encodes and uses this exact relationship in its own
-- ARMOR_TARGET table (mail before level 40, then the class's best armor
-- from level 40 on), so it is repeated here in the same shape rather than
-- copied from the raw research JSON, whose fromLevel values were reversed
-- relative to how the addon's own scan logic already works.
-- ---------------------------------------------------------------------------
SW.ARMOR_TYPES = {
    WARRIOR = { early = "Mail",    upgraded = "Plate",   upgradeLevel = 40 },
    PALADIN = { early = "Mail",    upgraded = "Plate",   upgradeLevel = 40 },
    HUNTER  = { early = "Leather", upgraded = "Mail",     upgradeLevel = 40 },
    SHAMAN  = { early = "Leather", upgraded = "Mail",     upgradeLevel = 40 },
    ROGUE   = { early = "Leather", upgraded = "Leather", upgradeLevel = 40 },
    DRUID   = { early = "Leather", upgraded = "Leather", upgradeLevel = 40 },
    MAGE    = { early = "Cloth",   upgraded = "Cloth",   upgradeLevel = 40 },
    PRIEST  = { early = "Cloth",   upgraded = "Cloth",   upgradeLevel = 40 },
    WARLOCK = { early = "Cloth",   upgraded = "Cloth",   upgradeLevel = 40 },
}

-- ---------------------------------------------------------------------------
-- weapon proficiency
-- Not flagged by the audit, kept as researched.
-- ---------------------------------------------------------------------------
SW.WEAPON_PROFICIENCY = {
    WARRIOR = { weapons = { "Axe", "Sword", "Mace", "Polearm", "Staff" },
                canDualWield = true, canUseShield = true,
                notes = "Dual Wield requires the talent. Two hand weapons and shields are both usable." },
    PALADIN = { weapons = { "Axe", "Sword", "Mace", "Polearm" },
                canDualWield = false, canUseShield = true,
                notes = "Cannot dual wield. Shields are mandatory for Protection." },
    HUNTER  = { weapons = { "Axe", "Sword", "Dagger", "Gun", "Bow", "Crossbow" },
                canDualWield = true, canUseShield = false,
                notes = "Dual Wield requires the talent. A ranged weapon, gun, bow or crossbow, is required to attack at range." },
    SHAMAN  = { weapons = { "Axe", "Mace", "Dagger" },
                canDualWield = true, canUseShield = true,
                notes = "Dual Wield requires the talent. Shields are used by Protection and Restoration builds." },
    ROGUE   = { weapons = { "Sword", "Dagger", "Mace" },
                canDualWield = true, canUseShield = false,
                notes = "Dual Wield is core to the class, no talent required. Cannot use a shield or a ranged weapon." },
    DRUID   = { weapons = { "Mace", "Polearm", "Staff", "Dagger" },
                canDualWield = false, canUseShield = false,
                notes = "Cannot dual wield in any form. Typically a staff for casting." },
    MAGE    = { weapons = { "Sword", "Dagger", "Staff", "Wand" },
                canDualWield = false, canUseShield = false,
                notes = "Cannot dual wield or use a shield. A wand goes in the off hand and is used for filler damage." },
    PRIEST  = { weapons = { "Mace", "Dagger", "Staff", "Wand" },
                canDualWield = false, canUseShield = false,
                notes = "Cannot dual wield or use a shield. A wand goes in the off hand. Maces are favoured for healing off hands." },
    WARLOCK = { weapons = { "Sword", "Dagger", "Staff", "Wand" },
                canDualWield = false, canUseShield = false,
                notes = "Cannot dual wield or use a shield. A wand goes in the off hand and is used for filler damage." },
}

-- ---------------------------------------------------------------------------
-- classes with no usable research yet
-- ItemEval.lua must treat these, and any class or tab not present below at
-- all, as "no data", and must say so plainly rather than guessing a score.
-- ---------------------------------------------------------------------------
SW.EXCLUDED = {
    WARRIOR = "Arms, Fury and Protection have no researched stat weights yet. The research pass ran out of search budget before reaching them.",
    DRUID   = "Balance, Feral Cat, Feral Bear and Restoration have no researched stat weights yet. The research pass could not find sources for them.",
}

-- ---------------------------------------------------------------------------
-- Hunter
-- Tab order matches Profiles.lua: 1 Beast Mastery, 2 Marksmanship, 3 Survival.
-- ---------------------------------------------------------------------------
SW.HUNTER = {
    [1] = {
        name = "Beast Mastery",
        confidence = "medium",
        playstyle = "Sustained damage output where pet damage scales with hunter gear. Kill Command usage is tied to your own crits.",
        weights = {
            ITEM_MOD_AGILITY_SHORT = 1,
            ITEM_MOD_HIT_RATING_SHORT = 1,
            ITEM_MOD_ATTACK_POWER_SHORT = 0.43,
            ITEM_MOD_CRIT_RATING_SHORT = 0.8,
            ITEM_MOD_HASTE_RATING_SHORT = 0.5,
            ITEM_MOD_STAMINA_SHORT = 0.1,
            ITEM_MOD_INTELLECT_SHORT = 0.05,
        },
        -- Not a stat key. ItemEval.lua multiplies a ranged weapon's own
        -- damage per second by this number, on top of the weights above,
        -- because ranged weapon DPS dominates a hunter's damage far more
        -- than any per point stat weight can express. See audit finding 3.
        weaponDPSWeight = 2.4,
        avoidStats = { ITEM_MOD_STRENGTH_SHORT = true },
        caps = {
            {
                name = "Ranged Hit Rating, Level 73 Raid Boss",
                kind = "must reach",
                statKey = "ITEM_MOD_HIT_RATING_SHORT",
                ratingValue = 142,
                percentValue = 9,
                explanation = "With no raid buffs you need 142 hit rating, 9 percent, before every shot lands on a level 73 raid boss. With Improved Faerie Fire and a Draenei's Heroic Presence both up, that drops to 79 rating, 5 percent. Below whichever number applies to your raid, some of your shots simply miss and deal no damage.",
            },
            {
                name = "Ranged Hit Rating Soft Cap",
                kind = "soft cap",
                statKey = "ITEM_MOD_HIT_RATING_SHORT",
                ratingValue = 142,
                percentValue = 9,
                explanation = "Once you are past 142 rating, extra hit rating does nothing for your damage. Put further gear priority into Agility, crit and haste instead.",
            },
        },
        hardRules = {
            "Ranged weapon DPS dominates all stat weights. A 50 DPS weapon upgrade is worth roughly 400 to 500 rating in secondary stats. Slow weapons, 3.0 speed or higher, scale far better with attack power than fast weapons.",
            "Pet damage is 25 to 30 percent of total Beast Mastery damage output. The pet scales at 22 percent of your ranged attack power and 30 percent of your stamina. This makes attack power worth more to this spec than pure personal DPS math suggests.",
            "Kill Command only executes after a critical strike. Zero crit means dead global cooldowns. Crit is mandatory for keeping the rotation moving.",
            "Armor penetration does not exist as a stat in TBC 2.4.3. Only pet abilities such as Acid Spit provide anything like it.",
            "Intellect and mana are not DPS factors. Aspect of the Viper handles mana regeneration when it is needed.",
        },
        weaponRules = "Weapon speed and base damage dominate ranged weapon selection completely. Attack power adds roughly 1 DPS per 14 attack power, a 0.071 coefficient. Slower weapons, 3.0 speed or higher, gain substantially more per shot damage from attack power than fast weapons do. Ammo contributes base damage and also scales with attack power.",
        sources = {
            "https://www.icy-veins.com/tbc-classic/beast-mastery-hunter-dps-pve-stat-priority",
            "https://www.icy-veins.com/tbc-classic/beast-mastery-hunter-dps-pets-guide",
            "https://www.wowhead.com/tbc/guide/classes/hunter/dps-stat-priority-attributes-pve",
            "https://lifevor.com/en/tools/tbc-hit-rating-2h-calculator",
        },
    },
    [2] = {
        name = "Marksmanship",
        confidence = "medium",
        playstyle = "Burst and sustained ranged damage without depending on pet damage. Built around executing focused shots.",
        weights = {
            ITEM_MOD_AGILITY_SHORT = 1,
            ITEM_MOD_HIT_RATING_SHORT = 1,
            ITEM_MOD_CRIT_RATING_SHORT = 0.85,
            ITEM_MOD_ATTACK_POWER_SHORT = 0.5,
            ITEM_MOD_HASTE_RATING_SHORT = 0.55,
            ITEM_MOD_STAMINA_SHORT = 0.1,
            ITEM_MOD_INTELLECT_SHORT = 0.05,
        },
        weaponDPSWeight = 2.4,
        avoidStats = { ITEM_MOD_STRENGTH_SHORT = true },
        caps = {
            {
                name = "Ranged Hit Rating, Level 73 Raid Boss",
                kind = "must reach",
                statKey = "ITEM_MOD_HIT_RATING_SHORT",
                ratingValue = 142,
                percentValue = 9,
                explanation = "With no raid buffs you need 142 hit rating, 9 percent, before every shot lands on a level 73 raid boss. With Improved Faerie Fire and a Draenei's Heroic Presence both up, that drops to 79 rating, 5 percent. Below whichever number applies to your raid, some of your shots simply miss and deal no damage.",
            },
            {
                name = "Ranged Hit Rating Soft Cap",
                kind = "soft cap",
                statKey = "ITEM_MOD_HIT_RATING_SHORT",
                ratingValue = 142,
                percentValue = 9,
                explanation = "Once you are past 142 rating, extra hit rating does nothing for your damage. Move gear priority to Agility, crit and haste instead.",
            },
        },
        hardRules = {
            "Ranged weapon DPS dominates all stat weights. A 50 DPS weapon upgrade beats roughly 400 to 500 rating in secondary stats. Slow weapons, 3.0 speed or higher, are the ones worth chasing.",
            "Marksmanship has no pet damage multiplier, so attack power is a lower priority than it is for Beast Mastery. It only scales your own damage, at roughly 1 DPS per 14 attack power.",
            "Armor penetration does not exist as a stat in TBC 2.4.3.",
            "Intellect and mana are not DPS factors. Aspect of the Viper handles mana regeneration when it is needed.",
        },
        weaponRules = "Weapon speed and base damage dominate ranged weapon selection completely. Attack power adds roughly 1 DPS per 14 attack power, a 0.071 coefficient. Slower weapons, 3.0 speed or higher, gain substantially more per shot damage from attack power than fast weapons do. Ammo contributes base damage and also scales with attack power.",
        sources = {
            "https://www.icy-veins.com/tbc-classic/marksmanship-hunter-dps-pve-stat-priority",
            "https://www.wowhead.com/tbc/guide/classes/hunter/dps-stat-priority-attributes-pve",
            "https://lifevor.com/en/tools/tbc-hit-rating-2h-calculator",
        },
    },
    [3] = {
        name = "Survival",
        confidence = "medium",
        playstyle = "A raid buff spec built around Expose Weakness. Agility stacking here is mostly about raid group DPS, not your own personal DPS.",
        weights = {
            ITEM_MOD_AGILITY_SHORT = 1,
            ITEM_MOD_CRIT_RATING_SHORT = 0.75,
            ITEM_MOD_ATTACK_POWER_SHORT = 0.55,
            ITEM_MOD_HASTE_RATING_SHORT = 0.4,
            ITEM_MOD_STAMINA_SHORT = 0.1,
            ITEM_MOD_INTELLECT_SHORT = 0.05,
            ITEM_MOD_HIT_RATING_SHORT = 0.2,
        },
        weaponDPSWeight = 2.4,
        avoidStats = { ITEM_MOD_STRENGTH_SHORT = true },
        caps = {
            {
                name = "Hit Rating with Surefooted",
                kind = "must reach",
                statKey = "ITEM_MOD_HIT_RATING_SHORT",
                ratingValue = 32,
                percentValue = 2,
                explanation = "The Surefooted talent grants 3 percent hit automatically, so you only need 2 percent more from gear, 32 rating, to reach the 5 percent effective hit cap. That is far lower than the other two hunter specs need.",
            },
            {
                name = "Hit Rating Soft Cap for Survival",
                kind = "soft cap",
                statKey = "ITEM_MOD_HIT_RATING_SHORT",
                ratingValue = 32,
                percentValue = 2,
                explanation = "Past 32 rating, extra hit does nothing for your damage. Ignore hit on gear entirely once you are there and prioritise Agility and crit.",
            },
        },
        hardRules = {
            "Survival is a raid buff spec. Expose Weakness lowers the target's armor and scales with your Agility, so your main value is raid group damage, not your own personal DPS.",
            "Expose Weakness only triggers on crits. Missing crits means missing debuff uptime for the whole raid.",
            "Ranged weapon DPS dominates all stat weights. Slow weapons, 3.0 speed or higher, are mandatory. A 50 DPS weapon upgrade beats roughly 400 to 500 rating in secondary stats.",
            "Surefooted provides 3 percent hit automatically. Only chase 32 rating, 2 percent, from gear, then stop caring about hit entirely.",
            "Armor penetration does not exist as a stat in TBC 2.4.3.",
            "Intellect and mana are not DPS factors. Aspect of the Viper handles mana regeneration when it is needed.",
        },
        weaponRules = "Weapon speed and base damage dominate ranged weapon selection completely. Attack power adds roughly 1 DPS per 14 attack power, a 0.071 coefficient. Slower weapons, 3.0 speed or higher, gain substantially more per shot damage from attack power than fast weapons do. Ammo contributes base damage and also scales with attack power.",
        sources = {
            "https://www.icy-veins.com/tbc-classic/survival-hunter-dps-pve-stat-priority",
            "https://www.icy-veins.com/tbc-classic/survival-hunter-dps-pets-guide",
            "https://www.wowhead.com/tbc/guide/classes/hunter/dps-stat-priority-attributes-pve",
            "https://lifevor.com/en/tools/tbc-hit-rating-2h-calculator",
        },
    },
}

-- ---------------------------------------------------------------------------
-- Priest
-- Tab order matches Profiles.lua: 1 Discipline, 2 Holy, 3 Shadow.
-- ---------------------------------------------------------------------------
SW.PRIEST = {
    [1] = {
        name = "Discipline",
        confidence = "medium",
        playstyle = "Reactive shield absorption and proactive bubble healing with Power Word Shield, backed up by instant cast heals. Mana has to last a long fight.",
        weights = {
            ITEM_MOD_SPELL_HEALING_DONE_SHORT = 1,
            ITEM_MOD_HASTE_SPELL_RATING_SHORT = 0.65,
            ITEM_MOD_INTELLECT_SHORT = 0.55,
            ITEM_MOD_SPIRIT_SHORT = 0.4,
            ITEM_MOD_CRIT_SPELL_RATING_SHORT = 0.22,
            ITEM_MOD_MANA_REGENERATION_SHORT = 0.12,
        },
        caps = {
            {
                name = "Haste Soft Cap",
                kind = "soft cap",
                statKey = "ITEM_MOD_HASTE_SPELL_RATING_SHORT",
                ratingValue = 788.5,
                explanation = "50 percent haste removes the global cooldown floor of 1 second. Past this point extra haste shortens your casts but also burns mana faster, so only chase it if your mana regen can keep up.",
            },
            {
                name = "Mana Sustainability Threshold",
                kind = "must reach",
                statKey = "ITEM_MOD_MANA_REGENERATION_SHORT",
                explanation = "You need enough mana regeneration to keep shielding roughly every 12 seconds and to keep healing for the whole fight. GearScout cannot give a single rating number for this because it depends on the fight length, but if you are hitting zero mana before the fight ends your regen is too low, and if you finish with a lot to spare you can trade some regen for healing power instead.",
            },
            {
                name = "Minimum Crit for Inspiration",
                kind = "soft cap",
                statKey = "ITEM_MOD_CRIT_SPELL_RATING_SHORT",
                ratingValue = 220,
                percentValue = 10,
                explanation = "Around 10 percent crit, 220 rating, keeps the Inspiration buff up on your tank almost all the time as long as you keep shielding. Below this, gaps in the buff let more damage through.",
            },
        },
        hardRules = {
            "Healing power and shield absorption share the same stat. A shield scales exactly like a heal does.",
            "Power Word Shield has no cooldown of its own, only the global cooldown, so haste directly speeds up how often you can reapply it.",
            "The Meditation talent means Spirit does double duty, mana regen and healing power, so Spirit is never a wasted stat for this spec.",
            "Shields cannot crit in TBC. All crit value comes from bonus healing on spells such as Heal and Greater Heal.",
        },
        sources = {
            "https://www.warcrafttavern.com/tbc/guides/pve-discipline-healing-priest-stat-priority/",
            "https://www.wowhead.com/tbc/guide/classes/priest/healer-stat-priority-attributes-pve",
            "https://dwarfpriest.wordpress.com/2008/11/07/weighing-priest-healing-stats/",
        },
    },
    [2] = {
        name = "Holy",
        confidence = "medium",
        playstyle = "Sustained throughput healing with Heal, Greater Heal, Renew and Flash Heal, balancing heavy casting against your mana pool so you do not run dry.",
        weights = {
            ITEM_MOD_SPELL_HEALING_DONE_SHORT = 1,
            ITEM_MOD_HASTE_SPELL_RATING_SHORT = 0.64,
            ITEM_MOD_SPIRIT_SHORT = 0.54,
            ITEM_MOD_INTELLECT_SHORT = 0.52,
            ITEM_MOD_CRIT_SPELL_RATING_SHORT = 0.25,
            ITEM_MOD_MANA_REGENERATION_SHORT = 0.15,
        },
        caps = {
            {
                name = "Haste Soft Cap",
                kind = "soft cap",
                statKey = "ITEM_MOD_HASTE_SPELL_RATING_SHORT",
                ratingValue = 788.5,
                explanation = "50 percent haste removes the global cooldown floor of 1 second. Holy priests rarely reach this in normal progression gear, and value past it depends on the fight and whether your mana regen keeps up.",
            },
            {
                name = "Inspiration Uptime Threshold",
                kind = "soft cap",
                statKey = "ITEM_MOD_CRIT_SPELL_RATING_SHORT",
                ratingValue = 220,
                percentValue = 10,
                explanation = "Around 10 percent crit, 220 rating, keeps the Inspiration buff up on your tank most of the time. Past this the returns fade quickly, so do not chase crit beyond it.",
            },
            {
                name = "Mana Sufficiency Target",
                kind = "must reach",
                statKey = "ITEM_MOD_MANA_REGENERATION_SHORT",
                explanation = "You need enough mana regeneration to keep casting for the whole fight. A rough target is finishing a 5 minute raid encounter with 5 to 10 percent of your mana left. If you hit zero mana before the fight ends, regen is under geared. If you finish with much more than 10 percent left, you were over geared for regen and could trade some Spirit or Intellect for healing power instead.",
            },
        },
        hardRules = {
            "Spirit is worth more than plain mana per five in TBC because of the Meditation talent, which keeps 25 to 50 percent of your regen while casting, and Spiritual Guidance, which turns Spirit directly into healing power.",
            "Intellect scales the Spirit regen formula, so each point of Intellect makes your Spirit regen more, not just your mana pool bigger. Intellect is not a luxury stat for this spec.",
            "The five second rule cuts Spirit regen by 60 percent while you are actively casting. Meditation and any downtime between casts are the only ways to get full value from Spirit during heavy healing.",
            "Renew can be kept up on the tank between other casts without extra mana cost, since it was already paid for when cast. Maintaining its uptime is a rotation habit, not a gearing decision.",
        },
        sources = {
            "https://www.icy-veins.com/tbc-classic/holy-priest-healer-pve-stat-priority",
            "https://www.wowhead.com/tbc/guide/classes/priest/healer-stat-priority-attributes-pve",
            "https://dwarfpriest.wordpress.com/2008/11/07/weighing-priest-healing-stats/",
            "https://www.lootxphub.com/priest-healing-stat-priority-and-attribute-guide-for-tbc-classic-phase-1/",
        },
    },
    [3] = {
        name = "Shadow",
        confidence = "high",
        playstyle = "Sustained DPS built on Shadow Word: Pain, Shadow Word: Death, Mind Blast and Mind Flay. Spell hit is not optional, boss resistances make missing spells real.",
        weights = {
            ITEM_MOD_SPELL_POWER_SHORT = 1,
            ITEM_MOD_HASTE_SPELL_RATING_SHORT = 0.4,
            ITEM_MOD_CRIT_SPELL_RATING_SHORT = 0.3,
            -- Weighted at zero on purpose. This stat is judged entirely by
            -- the Spell Hit Cap rule below: worth everything until you reach
            -- it, worth nothing after. See GetCapStatus in ItemEval.lua.
            ITEM_MOD_HIT_SPELL_RATING_SHORT = 0,
        },
        caps = {
            {
                name = "Spell Hit Cap",
                kind = "must reach",
                statKey = "ITEM_MOD_HIT_SPELL_RATING_SHORT",
                ratingValue = 76,
                percentValue = 6,
                explanation = "Shadow Focus grants 10 percent spell hit on its own. Against a level 73 boss you need 6 percent more from gear, 76 rating, to stop missing spells. With a Draenei's Heroic Presence in the raid that drops to 63 rating. Any hit rating past whichever number applies to you is wasted, so gear to the exact number your raid gives you, not past it.",
            },
            {
                name = "Diminishing Haste Return",
                kind = "worthless past",
                statKey = "ITEM_MOD_HASTE_SPELL_RATING_SHORT",
                ratingValue = 788.5,
                explanation = "Past 50 percent haste, 788.5 rating, you have hit the 1 second global cooldown floor and extra haste gives far less back. Shadow does not depend on hitting this floor the way healers do, so it is a low priority target, not a mandatory one.",
            },
        },
        hardRules = {
            "Spell hit to the cap is mandatory. Every missed spell is lost damage, and every point of hit rating past the cap is wasted. Confirm your hit cap is covered before optimising anything else.",
            "Spell Power, not Attack Power and not Ranged Attack Power, is the only damage stat that scales Shadow spells.",
        },
        sources = {
            "https://www.wowhead.com/tbc/guide/classes/priest/shadow/dps-stat-priority-attributes-pve",
            "https://www.warcrafttavern.com/tbc/guides/pve-shadow-priest-stat-priority/",
            "https://www.icy-veins.com/tbc-classic/shadow-priest-dps-pve-stat-priority",
            "https://www.lootxphub.com/tbc-shadow-priest-stat-priority-guide-optimal-attributes-for-burning-crusade-classic/",
        },
    },
}

-- ---------------------------------------------------------------------------
-- Paladin
-- Tab order matches Profiles.lua: 1 Holy, 2 Protection, 3 Retribution.
-- ---------------------------------------------------------------------------
SW.PALADIN = {
    [1] = {
        name = "Holy",
        confidence = "high",
        playstyle = "Healing throughput built on Healing Power and Intellect stacking, both single target and group heals.",
        weights = {
            ITEM_MOD_SPELL_HEALING_DONE_SHORT = 1,
            ITEM_MOD_INTELLECT_SHORT = 0.87,
            ITEM_MOD_MANA_REGENERATION_SHORT = 0.65,
            ITEM_MOD_CRIT_SPELL_RATING_SHORT = 0.54,
            ITEM_MOD_SPIRIT_SHORT = 0.18,
            ITEM_MOD_STAMINA_SHORT = 0.12,
            ITEM_MOD_HASTE_SPELL_RATING_SHORT = 0.09,
        },
        caps = {
            {
                name = "Mana Pool Sufficiency",
                kind = "soft cap",
                statKey = "ITEM_MOD_INTELLECT_SHORT",
                ratingValue = 250,
                explanation = "Intellect both grows your mana pool and, through Holy Guidance, adds healing power directly. A rough progression target is a mana pool over 4000, which usually means about 250 rating worth of Intellect from gear on top of your base. Below this, mana per five becomes even more important to avoid running dry.",
            },
            {
                name = "Healing Throughput Floor",
                kind = "soft cap",
                statKey = "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
                ratingValue = 800,
                explanation = "About 800 healing power is the rough minimum for raiding to make your spells worth their mana cost. Below this, healing is inefficient per point of mana spent. The exact number moves with the raid tier.",
            },
        },
        hardRules = {
            "Healing power is the single most valuable stat for throughput. It directly scales every healing spell you cast.",
            "Holy Guidance converts 35 percent of your Intellect into spell power and healing power, which makes Intellect one of the strongest stats a Holy Paladin can wear, on top of the mana pool and crit chance it already gives.",
            "Unlike most healers, Intellect is a primary stat here, not a secondary one, because of Holy Guidance.",
            "Mana per five is essential for raid progression fights that run long. Shorter farm fights can trade some of it for healing power and crit instead.",
            "Spell crit gives free healing through 150 percent crit heals, but can cause wasted overhealing in low pressure fights.",
            "Spirit has only marginal value in TBC for this spec, because most healing rotations stay on the global cooldown to keep the Vengeance buff up, leaving little time to benefit from Spirit's regen.",
        },
        sources = {
            "https://www.icy-veins.com/tbc-classic/holy-paladin-healer-pve-stat-priority",
            "https://www.wowhead.com/tbc/guide/classes/paladin/holy/healer-stat-priority-attributes-pve",
            "https://www.warcrafttavern.com/tbc/guides/pve-holy-paladin-stat-priority/",
        },
    },
    [2] = {
        name = "Protection",
        -- Downgraded from the research pass's own "high" marker. The audit
        -- called the original defense cap number a safety hazard. The
        -- number below is corrected, but this spec has not had an
        -- independent re-check since, so GearScout should not present it
        -- with full confidence yet. See the file header for the details.
        confidence = "medium",
        playstyle = "Tanking. Survival comes from capped defense and crush immunity first, then effective health. Threat comes from holy spell damage, not melee.",
        weights = {
            -- Not weighted. This is a mandatory prerequisite, not a stat to
            -- optimise, and is checked separately through GetCapStatus.
            ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 0,
            ITEM_MOD_STAMINA_SHORT = 1,
            ITEM_MOD_BLOCK_RATING_SHORT = 0.65,
            ITEM_MOD_DODGE_RATING_SHORT = 0.48,
            ITEM_MOD_PARRY_RATING_SHORT = 0.38,
            ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 0.42,
            ITEM_MOD_HIT_SPELL_RATING_SHORT = 0.18,
            ITEM_MOD_STRENGTH_SHORT = 0.12,
            ITEM_MOD_INTELLECT_SHORT = 0.08,
            -- PvP only. Kept at zero on purpose rather than left off, so it
            -- reads as considered and rejected, not forgotten.
            ITEM_MOD_RESILIENCE_RATING_SHORT = 0,
        },
        caps = {
            {
                name = "Defense Skill, Crit Immunity",
                kind = "must reach",
                statKey = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
                ratingValue = 331,
                skillValue = 490,
                explanation = "You need 490 total defense skill before a level 73 raid boss can no longer land a critical hit on you. Being level 70 gives you 350 of that for free, so the remaining 140 has to come off your gear, which is about 331 defense rating. Until you reach it you will take occasional critical hits that healers cannot plan around. There is no partial credit: you are either at 490 or you are not.",
            },
            {
                name = "Crush Immunity Avoidance",
                kind = "must reach",
                statKey = "ITEM_MOD_BLOCK_RATING_SHORT",
                ratingValue = 79,
                percentValue = 102.4,
                explanation = "Your combined avoidance, miss, dodge, parry and block together, needs to reach 102.4 percent while Holy Shield is active. Below this, boss crushing blows, 150 percent damage, land freely. Block is the most rating efficient way to close the gap because Holy Shield already gives 30 percent block chance on its own.",
            },
            {
                name = "Block Value Efficiency",
                kind = "soft cap",
                statKey = "ITEM_MOD_BLOCK_VALUE_SHORT",
                ratingValue = 250,
                percentValue = 6,
                explanation = "Block value scales from Strength at a 20 to 1 ratio in TBC. Early progression only reaches 250 to 400 total block value, which still leaves most of a big hit unblocked. Do not itemize specifically for block value, let it come naturally from Strength and your shield.",
            },
        },
        hardRules = {
            "The defense cap, 490 skill, is mandatory and overrides every other stat. You cannot safely tank raid bosses without it.",
            "The crush cap, 102.4 percent avoidance with Holy Shield up, is mandatory for boss progression. Below it, crushing blows create damage spikes your healers cannot plan around.",
            "Threat gear and survival gear pull against each other: spell damage for threat often sits on low stamina pieces. Cap defense and crush first, then shift toward threat gear.",
            "Holy Shield's built in 30 percent block chance makes block rating the most efficient avoidance stat for reaching the crush cap, ahead of dodge or parry.",
            "Spell damage is a real threat stat for this spec because Protection Paladin threat comes from holy spell scaling, Holy Shield, Consecration, Avenger's Shield and Judgement, not from melee swings.",
            "ITEM_MOD_ARMOR is not a confirmed stat key this addon reads, so it is not scored as a weight. Armor still reduces physical damage through the game's own formula, but block rating is usually the better itemization choice on a given piece.",
            "Strength's 20 to 1 block value ratio in TBC is very different from later expansions. It is a reason not to actively itemize for block value, not a reason to chase Strength.",
            "In early progression, once the caps are met, Stamina becomes the primary long term survival stat. Block and dodge rating beyond what the crush cap needs stop paying off.",
        },
        sources = {
            "https://www.icy-veins.com/tbc-classic/protection-paladin-tank-pve-stat-priority",
            "https://www.wowhead.com/tbc/guide/classes/paladin/tank-overview-pve",
            "https://www.bluetracker.gg/wow/topic/us-en/36573662-combat-ratings-level-70-conversions/",
            "https://hitcap.io/tbc/defense-cap/",
            "https://west-games.com/tbc-defense-calculator/",
            "https://www.warcrafttavern.com/tbc/guides/paladin-seals-judgements/",
        },
    },
    [3] = {
        name = "Retribution",
        confidence = "high",
        playstyle = "Melee DPS built around a hit capped rotation and Strength scaling, using Seal of Blood or Seal of Corruption for sustained output.",
        weights = {
            -- Not weighted. Mandatory prerequisite, checked through
            -- GetCapStatus, not a stat to optimise past the cap.
            ITEM_MOD_HIT_MELEE_RATING_SHORT = 0,
            ITEM_MOD_STRENGTH_SHORT = 1,
            ITEM_MOD_EXPERTISE_RATING_SHORT = 0.64,
            ITEM_MOD_CRIT_RATING_SHORT = 0.52,
            ITEM_MOD_ATTACK_POWER_SHORT = 0.48,
            ITEM_MOD_HASTE_RATING_SHORT = 0.31,
            ITEM_MOD_AGILITY_SHORT = 0.18,
            ITEM_MOD_STAMINA_SHORT = 0.08,
        },
        caps = {
            {
                name = "Hit Chance vs Level 73 Boss",
                kind = "must reach",
                statKey = "ITEM_MOD_HIT_MELEE_RATING_SHORT",
                ratingValue = 142,
                percentValue = 9,
                explanation = "You need 9 percent hit, 142 rating, against a level 73 raid boss with no talents or buffs. With Precision, 3 percent, only 95 rating is needed. With Precision plus a Draenei's Heroic Presence, 79 rating. With Precision, Heroic Presence and a Balance Druid's 3 percent buff all up, 32 rating. Missing this cap means Crusader Strikes miss, which breaks both your Vengeance uptime and your seal application on the boss.",
            },
            {
                name = "Expertise Cap",
                kind = "must reach",
                statKey = "ITEM_MOD_EXPERTISE_RATING_SHORT",
                ratingValue = 103,
                explanation = "Expertise caps at 26 points, 103 rating, to stop bosses from dodging or parrying you, or 21 points, 86 rating, for a human using a sword or mace. Below this cap, dodged and parried swings cost you damage and Vengeance uptime the same way a miss does.",
            },
            {
                name = "Vengeance Uptime Target",
                kind = "soft cap",
                statKey = "ITEM_MOD_CRIT_RATING_SHORT",
                ratingValue = 190,
                percentValue = 30,
                explanation = "About 30 percent crit, 190 rating, is the target for keeping the Vengeance buff up through a fight. Past this the returns drop sharply, because Vengeance does not stack, keeping it up is the goal, not maximising how often it procs.",
            },
        },
        hardRules = {
            "The hit cap, 9 percent or lower with talents and raid buffs, is mandatory. Missing attacks breaks both Vengeance uptime and seal application.",
            "Strength is the primary damage stat because of the Divine Strength talent, 2.2 attack power per point of Strength, and because it scales both physical damage and Seal of Blood or Seal of Corruption procs.",
            "Expertise is mandatory once hit is capped, to stop bosses dodging and parrying your swings.",
            "Agility is meaningfully weaker than Strength here even though both give crit chance, because Strength's attack power scaling dominates through Divine Strength.",
            "30 percent crit is the soft cap for keeping Vengeance up. Stacking more crit past that point has sharply diminishing returns.",
            "Seal of Blood and Seal of Corruption scale with haste through faster proc rates, which is why haste is worth more here than it is for most pure melee DPS specs.",
        },
        sources = {
            "https://www.icy-veins.com/tbc-classic/retribution-paladin-dps-pve-stat-priority",
            "https://www.wowhead.com/tbc/guide/classes/paladin/retribution/leveling-tips",
            "https://www.warcrafttavern.com/tbc/guides/pve-retribution-paladin-stat-priority/",
        },
    },
}
