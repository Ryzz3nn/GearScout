-- GearScout / Data/Rotations.lua
-- Generated from an external spell research pass for World of Warcraft: The
-- Burning Crusade, patch 2.4.3, as played on the Anniversary realms. No build
-- date is recorded here because none was supplied by the research pass.
--
-- DO NOT HAND EDIT THIS FILE. It is regenerated from research data and any
-- direct edits will be overwritten the next time that happens. Fix problems
-- upstream, in the research or audit pass, not here.
--
-- Every spell id below carried a verifiedUrl and verifiedName from a live
-- Wowhead TBC spell page in the research pass. A follow-up audit reviewed the
-- research for wrong and suspect values, and its findings are already applied
-- in this file:
--   - Circle of Healing (id 34861, Priest Holy): dropped. The audit found it
--     listed with a 6 second cooldown that does not exist in TBC.
--   - Shadowstep (id 36554, Rogue Subtlety): dropped. The audit found it
--     listed with a 10 second cooldown; the real TBC cooldown is 30 seconds.
--   - Slice and Dice (id 6774, all Rogue specs) and Rupture (id 1943, all
--     Rogue specs): downgraded from a judged kind to kind = "core". The
--     research listed a flat duration that assumes permanent maximum combo
--     points, which is not how either buff behaves, so the duration was
--     dropped rather than guessed at here.
-- The item catalogue (enchants, ammo, consumables) came back empty. The
-- research pass exhausted its search budget and Wowhead's item database did
-- not return usable data, so nothing unverified was written rather than
-- guessing at item ids. See ENCHANTS / AMMO / CONSUMABLES below.
--
-- This file is pure data. It defines ns.RESEARCH for an integrator to merge
-- deliberately into ns.PROFILES, ns.BASE_TRACK, ns.CLASS_TIPS, ns.SPEC_TIPS
-- and the aura group tables in Profiles.lua. It does not assign those tables
-- directly and it has no side effects.
--
-- kind vocabulary matches Profiles.lua:
--   dot   maintain on the target, dur is the debuff length
--   buff  maintain on yourself, dur is the buff length
--   cd    used on cooldown, cd is the recharge in seconds
--   core  the bread and butter button, counted only
--   proc  reactive, situational, or downgraded by audit; counted, never judged

local ADDON, ns = ...

-- ---------------------------------------------------------------------------
-- aura groups
-- Same shape used by Profiles.lua: group, kind, label, dur (when the research
-- gave one), ids. Declared as locals so the same table can sit inside a
-- spec's track list below and inside the flat AURA_GROUPS catalogue.
-- ---------------------------------------------------------------------------
local PALADIN_WISDOM_SEAL_GROUP = {
    group = "seals", kind = "buff", label = "Active Seal", dur = 30,
    ids = { 20166 }, -- Seal of Wisdom
}
local PALADIN_RET_SEAL_GROUP = {
    group = "seals", kind = "buff", label = "Active Seal", dur = 30,
    ids = { 31892, 31801 }, -- Seal of Blood, Seal of Vengeance
}
local HUNTER_ASPECT_GROUP = {
    group = "Aspects", kind = "buff", label = "Active Aspect",
    ids = { 27044, 34074 }, -- Aspect of the Hawk, Aspect of the Viper
}
local ROGUE_POISON_GROUP = {
    group = "poisons", kind = "buff", label = "Weapon Poison",
    ids = { 2835, 26967, 27186 }, -- Deadly Poison, Deadly Poison VI, Deadly Poison VII
}
local MAGE_ARMOR_GROUP = {
    group = "Mage Armor", kind = "buff", label = "Maintain one active armor for passive benefits", dur = 1800,
    ids = { 30482, 27125 }, -- Molten Armor, Mage Armor
}
local WARLOCK_CURSE_GROUP = {
    group = "Curse", kind = "buff", label = "Warlock Curse",
    ids = { 30910, 27218, 27228, 27226 }, -- Curse of Doom, Curse of Agony, Curse of the Elements, Curse of Recklessness
}

ns.RESEARCH = {

    -- -----------------------------------------------------------------------
    -- level 70 spec profiles
    -- -----------------------------------------------------------------------
    PROFILES = {

        WARRIOR = {
            [1] = { name = "Arms", role = "melee", track = {
                { id = 30330, kind = "cd",   cd = 6 },              -- Mortal Strike
                { id = 25242, kind = "core" },                      -- Slam, no cooldown, cast after auto-attacks
                { id = 1680,  kind = "cd",   cd = 10 },             -- Whirlwind
                { id = 25236, kind = "proc" },                      -- Execute, only below 20 percent health
                { id = 25286, kind = "core" },                      -- Heroic Strike, on next swing, use when rage exceeds 60
                { id = 12328, kind = "cd",   cd = 30,  dur = 10 },  -- Sweeping Strikes
                { id = 25289, kind = "buff", dur = 120 },           -- Battle Shout
                { id = 25203, kind = "dot",  dur = 30 },            -- Demoralizing Shout
                { id = 29859, kind = "proc" },                      -- Blood Frenzy, applied through Rend, passive debuff
                { id = 25231, kind = "core" },                      -- Cleave, multi-target
            }},
            [2] = { name = "Fury", role = "melee", track = {
                { id = 30335, kind = "cd",   cd = 6 },              -- Bloodthirst
                { id = 1680,  kind = "cd",   cd = 10 },             -- Whirlwind
                { id = 25286, kind = "core" },                      -- Heroic Strike, rage dump when capped
                { id = 25236, kind = "proc" },                      -- Execute, only below 20 percent health
                { id = 30033, kind = "buff", dur = 30 },            -- Rampage
                { id = 25289, kind = "buff", dur = 120 },           -- Battle Shout
                { id = 25203, kind = "dot",  dur = 30 },            -- Demoralizing Shout
                { id = 12328, kind = "cd",   cd = 30,  dur = 10 },  -- Sweeping Strikes
                { id = 12292, kind = "cd",   cd = 180, dur = 30 },  -- Death Wish
                { id = 25231, kind = "core" },                      -- Cleave
            }},
            [3] = { name = "Protection", role = "tank", track = {
                { id = 30356, kind = "cd",   cd = 6 },              -- Shield Slam
                { id = 30357, kind = "cd",   cd = 5 },              -- Revenge
                { id = 30022, kind = "core" },                      -- Devastate, applies Sunder Armor, use as filler
                { id = 25225, kind = "dot",  dur = 30 },            -- Sunder Armor
                { id = 2565,  kind = "buff", dur = 5,  cd = 5 },    -- Shield Block
                { id = 25286, kind = "core" },                      -- Heroic Strike, rage dump for threat
                { id = 25203, kind = "dot",  dur = 30 },            -- Demoralizing Shout
                { id = 469,   kind = "buff", dur = 120 },           -- Commanding Shout
                { id = 871,   kind = "cd",   cd = 1800, dur = 10 }, -- Shield Wall
                { id = 12975, kind = "cd",   cd = 480 },            -- Last Stand
            }},
        },

        PALADIN = {
            [1] = { name = "Holy", role = "healer", track = {
                PALADIN_WISDOM_SEAL_GROUP,
                { id = 25292, kind = "core" },                      -- Holy Light
                { id = 27137, kind = "core" },                      -- Flash of Light
                { id = 20473, kind = "cd",   cd = 15 },             -- Holy Shock
                { id = 20216, kind = "cd",   cd = 120 },            -- Divine Favor
                { id = 31884, kind = "cd",   cd = 180, dur = 20 },  -- Avenging Wrath
            }},
            [2] = { name = "Protection", role = "tank", track = {
                PALADIN_WISDOM_SEAL_GROUP,
                { id = 27179, kind = "cd",   cd = 10,  dur = 10 },  -- Holy Shield
                { id = 20271, kind = "cd",   cd = 10 },             -- Judgement
                { id = 26573, kind = "cd",   cd = 8,   dur = 8 },   -- Consecration, zone effect, place where enemies will stand
                { id = 10314, kind = "cd",   cd = 15 },             -- Exorcism
                { id = 31884, kind = "cd",   cd = 180, dur = 20 },  -- Avenging Wrath
            }},
            [3] = { name = "Retribution", role = "melee", track = {
                PALADIN_RET_SEAL_GROUP,
                { id = 35395, kind = "cd",   cd = 6 },              -- Crusader Strike
                { id = 20271, kind = "cd",   cd = 10 },             -- Judgement
                { id = 24275, kind = "cd",   cd = 6 },              -- Hammer of Wrath, only below 20 percent health
                { id = 31884, kind = "cd",   cd = 180, dur = 20 },  -- Avenging Wrath
            }},
        },

        HUNTER = {
            [1] = { name = "Beast Mastery", role = "ranged", track = {
                HUNTER_ASPECT_GROUP,
                { id = 34120, kind = "core" },                      -- Steady Shot
                { id = 34026, kind = "proc" },                      -- Kill Command, off-GCD, only after a critical hit
                { id = 19574, kind = "cd",   cd = 120, dur = 18 },  -- Bestial Wrath
                { id = 27021, kind = "core" },                      -- Multi-Shot, instant, use on stacked targets or on cooldown
                { id = 36828, kind = "cd",   cd = 300 },            -- Rapid Fire, major opener and burst cooldown
                { id = 27016, kind = "dot",  dur = 15 },            -- Serpent Sting
                { id = 1130,  kind = "dot" },                       -- Hunter's Mark, permanent debuff, typically one per fight
            }},
            [2] = { name = "Marksmanship", role = "ranged", track = {
                HUNTER_ASPECT_GROUP,
                { id = 34120, kind = "core" },                      -- Steady Shot
                { id = 27021, kind = "core" },                      -- Multi-Shot, instant alternative filler for grouped targets
                { id = 20904, kind = "cd",   cd = 6,   dur = 10 },  -- Aimed Shot
                { id = 34026, kind = "proc" },                      -- Kill Command, off-GCD, only after a critical hit
                { id = 36828, kind = "cd",   cd = 300 },            -- Rapid Fire
                { id = 27016, kind = "dot",  dur = 15 },            -- Serpent Sting
                { id = 1130,  kind = "dot" },                       -- Hunter's Mark, permanent debuff if assigned to maintain it
            }},
            [3] = { name = "Survival", role = "ranged", track = {
                HUNTER_ASPECT_GROUP,
                { id = 34120, kind = "core" },                      -- Steady Shot
                { id = 34026, kind = "proc" },                      -- Kill Command, off-GCD, only after a critical hit
                { id = 36828, kind = "cd",   cd = 300 },            -- Rapid Fire
                { id = 23989, kind = "cd",   cd = 300 },            -- Readiness, resets cooldowns including Rapid Fire
                { id = 27021, kind = "core" },                      -- Multi-Shot, instant alternative filler
                { id = 14316, kind = "cd",   cd = 60,  dur = 60 },  -- Explosive Trap
                { id = 27016, kind = "dot",  dur = 15 },            -- Serpent Sting
            }},
        },

        ROGUE = {
            [1] = { name = "Assassination", role = "melee", track = {
                ROGUE_POISON_GROUP,
                { id = 34412, kind = "core" },  -- Mutilate, requires both weapons, generates 2 combo points
                { id = 26884, kind = "dot",  dur = 18 },            -- Garrote, silencing DoT, opener, maintained
                { id = 6774,  kind = "core" },  -- Slice and Dice, audit: downgraded from buff, duration assumed max combo points
                { id = 1943,  kind = "core" },  -- Rupture, audit: downgraded from dot, duration assumed max combo points
                { id = 32684, kind = "proc" },  -- Envenom, finisher that consumes deadly poison stacks
                { id = 14177, kind = "cd",   cd = 180 },            -- Cold Blood
                { id = 5938,  kind = "core" },  -- Shiv, applies off-hand poison, generates 1 combo point
            }},
            [2] = { name = "Combat", role = "melee", track = {
                { id = 26862, kind = "core" },                      -- Sinister Strike, primary combo point generator, no cooldown
                { id = 6774,  kind = "core" },  -- Slice and Dice, audit: downgraded from buff, duration assumed max combo points
                { id = 1943,  kind = "core" },  -- Rupture, audit: downgraded from dot, duration assumed max combo points
                { id = 2098,  kind = "core" },  -- Eviscerate, use when target dies before Rupture would, or during Blade Flurry
                { id = 13877, kind = "cd",   cd = 120, dur = 15 },  -- Blade Flurry
                { id = 13750, kind = "cd",   cd = 300, dur = 15 },  -- Adrenaline Rush
                { id = 14177, kind = "cd",   cd = 180 },            -- Cold Blood
                { id = 11198, kind = "proc" },                      -- Expose Armor, utility finisher if assigned
            }},
            [3] = { name = "Subtlety", role = "melee", track = {
                { id = 16511, kind = "core" },                      -- Hemorrhage, primary combo point builder
                { id = 26884, kind = "dot",  dur = 18 },            -- Garrote, opener from stealth, silencing DoT
                { id = 6774,  kind = "core" },  -- Slice and Dice, audit: downgraded from buff, duration assumed max combo points
                { id = 1943,  kind = "core" },  -- Rupture, audit: downgraded from dot, duration assumed max combo points
                -- Shadowstep (id 36554) dropped by audit: listed with a 10 second
                -- cooldown, the real TBC cooldown is 30 seconds.
                { id = 14185, kind = "cd",   cd = 300 },            -- Preparation, resets Vanish, Evasion, Sprint
                { id = 1856,  kind = "cd",   cd = 180 },            -- Vanish
                { id = 1833,  kind = "proc" },                      -- Cheap Shot, opener from stealth, 4 second stun, 2 combo points
            }},
        },

        PRIEST = {
            [1] = { name = "Discipline", role = "healer", track = {
                { id = 17,    kind = "buff", dur = 30 },            -- Power Word: Shield
                { id = 33076, kind = "cd",   cd = 10 },             -- Prayer of Mending
                { id = 2061,  kind = "core" },                      -- Flash Heal
                { id = 2060,  kind = "core" },                      -- Greater Heal
                { id = 14751, kind = "cd",   cd = 180 },            -- Inner Focus
            }},
            [2] = { name = "Holy", role = "healer", track = {
                -- Circle of Healing (id 34861) dropped by audit: listed with a 6
                -- second cooldown that does not exist in TBC.
                { id = 33076, kind = "cd",   cd = 10 },             -- Prayer of Mending
                { id = 139,   kind = "dot",  dur = 15 },            -- Renew
                { id = 2061,  kind = "core" },                      -- Flash Heal
                { id = 2060,  kind = "core" },                      -- Greater Heal
                { id = 596,   kind = "core" },                      -- Prayer of Healing
            }},
            [3] = { name = "Shadow", role = "caster", track = {
                { id = 589,   kind = "dot",  dur = 24 },            -- Shadow Word: Pain
                { id = 34914, kind = "dot",  dur = 15 },            -- Vampiric Touch
                { id = 8092,  kind = "cd",   cd = 8 },              -- Mind Blast
                { id = 15407, kind = "core" },                      -- Mind Flay
                { id = 32379, kind = "cd",   cd = 12 },             -- Shadow Word: Death
                { id = 15286, kind = "buff", dur = 60 },            -- Vampiric Embrace
                { id = 34433, kind = "cd",   cd = 300 },            -- Shadowfiend
            }},
        },

        SHAMAN = {
            [1] = { name = "Elemental", role = "caster", track = {
                { id = 25442, kind = "core" },                      -- Chain Lightning
                { id = 15207, kind = "core" },                      -- Lightning Bolt
                { id = 25457, kind = "dot",  dur = 30 },            -- Flame Shock
                { id = 33736, kind = "buff", dur = 600 },           -- Water Shield
                { id = 30706, kind = "buff", dur = 120 },           -- Totem of Wrath
                { id = 25547, kind = "cd",   cd = 15 },             -- Fire Nova Totem
                { id = 25552, kind = "proc" },                      -- Magma Totem, situational, use when enemies are grouped
                { id = 3738,  kind = "buff", dur = 120 },           -- Wrath of Air Totem
            }},
            [2] = { name = "Enhancement", role = "melee", track = {
                { id = 17364, kind = "cd",   cd = 10 },             -- Stormstrike
                { id = 8042,  kind = "cd",   cd = 6 },              -- Earth Shock, shares cooldown with Flame Shock and Frost Shock
                { id = 8232,  kind = "proc" },                      -- Windfury Weapon, apply to both weapons
                { id = 30823, kind = "cd",   cd = 120 },            -- Shamanistic Rage
                { id = 33736, kind = "buff", dur = 600 },           -- Water Shield
                { id = 25457, kind = "dot",  dur = 30 },            -- Flame Shock, use after Stormstrike for debuff amplification
                { id = 2894,  kind = "cd",   cd = 1200 },           -- Fire Elemental Totem
                { id = 25528, kind = "buff", dur = 120 },           -- Strength of Earth Totem
            }},
            [3] = { name = "Restoration", role = "healer", track = {
                { id = 10396, kind = "core" },                      -- Healing Wave
                { id = 25423, kind = "core" },                      -- Chain Heal
                { id = 25420, kind = "core" },                      -- Lesser Healing Wave
                { id = 32594, kind = "buff", dur = 600 },           -- Earth Shield, 6 charges, cast on tank
                { id = 33736, kind = "buff", dur = 600 },           -- Water Shield
                { id = 16190, kind = "cd",   cd = 300 },            -- Mana Tide Totem
                { id = 16188, kind = "cd",   cd = 180 },            -- Nature's Swiftness
                { id = 25442, kind = "proc" },                      -- Chain Lightning, off-spec damage when safe to cast
            }},
        },

        MAGE = {
            [1] = { name = "Arcane", role = "caster", track = {
                MAGE_ARMOR_GROUP,
                { id = 30451, kind = "core" },                      -- Arcane Blast
                { id = 10180, kind = "core" },                      -- Frostbolt
                { id = 12042, kind = "cd",   cd = 180 },            -- Arcane Power, 15 second duration buff
                { id = 12472, kind = "cd",   cd = 180 },            -- Icy Veins
                { id = 12043, kind = "cd",   cd = 180 },            -- Presence of Mind
                { id = 11958, kind = "cd",   cd = 480 },            -- Cold Snap, resets Arcane Power and Icy Veins
            }},
            [2] = { name = "Fire", role = "caster", track = {
                MAGE_ARMOR_GROUP,
                { id = 10149, kind = "core" },                      -- Fireball
                { id = 27074, kind = "core" },                      -- Scorch, applies Improved Scorch debuff
                { id = 12873, kind = "dot",  dur = 30 },            -- Improved Scorch, debuff, 5 stacks maximum
                { id = 27079, kind = "cd",   cd = 8 },              -- Fire Blast, instant, reduced to 7s with a talent
                { id = 11129, kind = "cd",   cd = 180 },            -- Combustion
                { id = 12472, kind = "cd",   cd = 180 },            -- Icy Veins
                { id = 27086, kind = "core" },                      -- Flamestrike, instant precast for multiple targets
                { id = 33933, kind = "cd",   cd = 30 },             -- Blast Wave
                { id = 33043, kind = "cd",   cd = 20 },             -- Dragon's Breath, execute phase below 20 percent
            }},
            [3] = { name = "Frost", role = "caster", track = {
                MAGE_ARMOR_GROUP,
                { id = 10180, kind = "core" },                      -- Frostbolt, applies Winter's Chill passively
                { id = 28595, kind = "dot",  dur = 15 },            -- Winter's Chill, debuff, 5 stacks maximum
                { id = 30455, kind = "core" },                      -- Ice Lance, high damage follow-up when target is frozen
                { id = 12472, kind = "cd",   cd = 180 },            -- Icy Veins
                { id = 31687, kind = "cd",   cd = 180 },            -- Summon Water Elemental
                { id = 11958, kind = "cd",   cd = 480 },            -- Cold Snap, resets Water Elemental and Icy Veins
                { id = 27088, kind = "cd",   cd = 25 },             -- Frost Nova
                { id = 27085, kind = "core" },                      -- Blizzard, channeled AoE
            }},
        },

        WARLOCK = {
            [1] = { name = "Affliction", role = "caster", track = {
                WARLOCK_CURSE_GROUP,
                { id = 27216, kind = "dot",  dur = 18 },            -- Corruption
                { id = 30405, kind = "dot",  dur = 18 },            -- Unstable Affliction
                { id = 30911, kind = "dot",  dur = 30 },            -- Siphon Life
                { id = 11661, kind = "core" },                      -- Shadow Bolt
                { id = 30910, kind = "cd",   cd = 60,  dur = 60 },  -- Curse of Doom
                { id = 27243, kind = "core" },                      -- Seed of Corruption, primary AoE ability
                { id = 27220, kind = "proc" },                      -- Drain Life, channeled self-heal, use when taking damage
                { id = 27222, kind = "core" },                      -- Life Tap, converts health to mana, triggers global cooldown
                { id = 29858, kind = "cd",   cd = 300 },            -- Soulshatter, threat management tool
            }},
            [2] = { name = "Demonology", role = "caster", track = {
                WARLOCK_CURSE_GROUP,
                { id = 30146, kind = "buff" },                      -- Summon Felguard, capstone pet, primary damage dealer
                { id = 19028, kind = "buff" },                      -- Soul Link, shares damage between you and your pet
                { id = 28189, kind = "buff", dur = 1800 },          -- Fel Armor
                { id = 27216, kind = "dot",  dur = 18 },            -- Corruption
                { id = 27215, kind = "dot",  dur = 18 },            -- Immolate
                { id = 11661, kind = "core" },                      -- Shadow Bolt
                { id = 27223, kind = "cd",   cd = 120 },            -- Death Coil, instant heal your pet or a damage spell
                { id = 29858, kind = "cd",   cd = 300 },            -- Soulshatter
                { id = 27220, kind = "proc" },                      -- Drain Life
            }},
            [3] = { name = "Destruction", role = "caster", track = {
                WARLOCK_CURSE_GROUP,
                { id = 28189, kind = "buff", dur = 1800 },          -- Fel Armor
                { id = 27215, kind = "dot",  dur = 18 },            -- Immolate, foundation of the rotation, maintain constantly
                { id = 11661, kind = "core" },                      -- Shadow Bolt, main filler for Shadow Destruction builds
                { id = 32231, kind = "core" },                      -- Incinerate, main filler for Fire Destruction builds
                { id = 30912, kind = "cd",   cd = 10 },             -- Conflagrate, do not use on cooldown, only when moving
                { id = 30546, kind = "cd",   cd = 15 },             -- Shadowburn, soul shard finisher or movement option
                { id = 30414, kind = "cd",   cd = 20 },             -- Shadowfury, AoE stun for control
                { id = 29858, kind = "cd",   cd = 300 },            -- Soulshatter
                { id = 27222, kind = "core" },                      -- Life Tap, convert health to mana when mana drops
            }},
        },

        DRUID = {
            [1] = { name = "Balance", role = "caster", track = {
                { id = 26986, kind = "core" },                      -- Starfire
                { id = 9834,  kind = "dot",  dur = 12 },            -- Moonfire
                { id = 27013, kind = "dot",  dur = 12 },            -- Insect Swarm
                { id = 26993, kind = "dot",  dur = 40 },            -- Faerie Fire, group-wide benefit with Improved Faerie Fire
                { id = 33831, kind = "cd",   cd = 180 },            -- Force of Nature
                { id = 27012, kind = "cd",   cd = 60 },             -- Hurricane
                { id = 29166, kind = "cd",   cd = 360 },            -- Innervate
                { id = 26984, kind = "core" },                      -- Wrath, faster cast filler when refreshing DoTs or managing mana
            }},
            [2] = { name = "Feral Combat", role = "melee", track = {
                { id = 33983, kind = "dot",  dur = 12 },            -- Mangle (Cat), +30 percent bleed damage debuff, always keep active
                { id = 27002, kind = "core" },                      -- Shred, primary generator when attacking from behind
                { id = 27008, kind = "dot",  dur = 12 },            -- Rip, apply at 4+ combo points if target lives long enough
                { id = 24248, kind = "core" },                      -- Ferocious Bite, apply at 4+ combo points on a dying target
                { id = 9846,  kind = "buff", dur = 6 },             -- Tiger's Fury, only at max energy about to overflow
                { id = 768,   kind = "buff", dur = 0 },             -- Cat Form, primary combat form
                { id = 9913,  kind = "proc" },                      -- Prowl
                { id = 16864, kind = "buff", dur = 1800 },          -- Omen of Clarity, passive proc from talent, next ability free
            }},
            [3] = { name = "Restoration", role = "healer", track = {
                { id = 33763, kind = "buff", dur = 7 },             -- Lifebloom, stacks to 3, keep a full stack on the tank
                { id = 9840,  kind = "dot",  dur = 12 },            -- Rejuvenation
                { id = 9858,  kind = "dot",  dur = 21 },            -- Regrowth, immediate heal plus heal over time
                { id = 9888,  kind = "core" },                      -- Healing Touch, main reactive heal
                { id = 18562, kind = "cd",   cd = 15 },             -- Swiftmend, converts an existing HoT into a burst heal
                { id = 33891, kind = "buff", dur = 0 },             -- Tree of Life, shapeshift form, increases healing output
                { id = 26983, kind = "cd",   cd = 600 },            -- Tranquility, channeled party AoE heal
                { id = 17116, kind = "cd",   cd = 180 },            -- Nature's Swiftness, next healing spell is instant
                { id = 29166, kind = "cd",   cd = 360 },            -- Innervate
            }},
        },
    },

    -- -----------------------------------------------------------------------
    -- levelling baselines
    -- One merged list per class, built from every spec's levelling track with
    -- duplicate spell ids removed. As in Profiles.lua, these are the buttons
    -- every spec of the class uses on the way up.
    -- -----------------------------------------------------------------------
    BASE_TRACK = {
        WARRIOR = {
            { id = 100,   kind = "core" },                      -- Charge
            { id = 12294, kind = "cd",   cd = 6 },              -- Mortal Strike
            { id = 25242, kind = "core" },                      -- Slam
            { id = 25236, kind = "proc" },                      -- Execute
            { id = 25286, kind = "core" },                      -- Heroic Strike
            { id = 1680,  kind = "cd",   cd = 10 },             -- Whirlwind
            { id = 25289, kind = "buff", dur = 120 },           -- Battle Shout
            { id = 30335, kind = "cd",   cd = 6 },              -- Bloodthirst
            { id = 71,    kind = "core" },                      -- Defensive Stance
            { id = 2565,  kind = "buff", dur = 5,  cd = 5 },    -- Shield Block
            { id = 30356, kind = "cd",   cd = 6 },              -- Shield Slam
            { id = 30357, kind = "cd",   cd = 5 },              -- Revenge
            { id = 871,   kind = "cd",   cd = 1800, dur = 10 }, -- Shield Wall
        },
        PALADIN = {
            { id = 25292, kind = "core" },                      -- Holy Light
            { id = 20271, kind = "cd",   cd = 10 },             -- Judgement
            { id = 853,   kind = "cd",   cd = 60,  dur = 3 },   -- Hammer of Justice
            { id = 27137, kind = "core" },                      -- Flash of Light
            { id = 26573, kind = "cd",   cd = 8,   dur = 8 },   -- Consecration
            { id = 35395, kind = "cd",   cd = 6 },              -- Crusader Strike
            { id = 31892, kind = "buff", dur = 30 },            -- Seal of Blood
            { id = 31801, kind = "buff", dur = 30 },            -- Seal of Vengeance
            { id = 27179, kind = "cd",   cd = 10,  dur = 10 },  -- Holy Shield
            { id = 20166, kind = "buff", dur = 30 },            -- Seal of Wisdom
        },
        HUNTER = {
            { id = 27016, kind = "dot",  dur = 15 },            -- Serpent Sting
            { id = 20904, kind = "cd",   cd = 6,   dur = 10 },  -- Aimed Shot
            { id = 34026, kind = "proc" },                      -- Kill Command
            { id = 34120, kind = "core" },                      -- Steady Shot
            { id = 27021, kind = "core" },                      -- Multi-Shot
            { id = 19574, kind = "cd",   cd = 120, dur = 18 },  -- Bestial Wrath
            { id = 36828, kind = "cd",   cd = 300 },            -- Rapid Fire
            { id = 14316, kind = "cd",   cd = 60,  dur = 60 },  -- Explosive Trap
            { id = 23989, kind = "cd",   cd = 300 },            -- Readiness
        },
        ROGUE = {
            { id = 26862, kind = "core" },                      -- Sinister Strike
            { id = 2098,  kind = "core" },                      -- Eviscerate
            { id = 6774,  kind = "core" },  -- Slice and Dice, audit: downgraded, duration assumed max combo points
            { id = 1856,  kind = "cd",   cd = 180 },            -- Vanish
            { id = 26884, kind = "dot",  dur = 18 },            -- Garrote
            { id = 34412, kind = "core" },                      -- Mutilate
            { id = 13877, kind = "cd",   cd = 120, dur = 15 },  -- Blade Flurry
            { id = 13750, kind = "cd",   cd = 300, dur = 15 },  -- Adrenaline Rush
            { id = 26669, kind = "cd",   cd = 300, dur = 15 },  -- Evasion
            { id = 16511, kind = "core" },                      -- Hemorrhage
        },
        PRIEST = {
            { id = 17,    kind = "buff", dur = 30 },            -- Power Word: Shield
            { id = 585,   kind = "proc" },                      -- Smite
            { id = 139,   kind = "proc", dur = 15 },            -- Renew
            { id = 589,   kind = "dot",  dur = 24 },            -- Shadow Word: Pain
        },
        SHAMAN = {
            { id = 15207, kind = "core" },                      -- Lightning Bolt
            { id = 25457, kind = "dot",  dur = 30 },            -- Flame Shock
            { id = 10396, kind = "core" },                      -- Healing Wave
            { id = 33736, kind = "buff", dur = 600 },           -- Water Shield
            { id = 8042,  kind = "cd",   cd = 6 },              -- Earth Shock
            { id = 8232,  kind = "proc" },                      -- Windfury Weapon
            { id = 25420, kind = "core" },                      -- Lesser Healing Wave
            { id = 25423, kind = "core" },                      -- Chain Heal
        },
        MAGE = {
            { id = 10149, kind = "core" },                      -- Fireball
            { id = 10180, kind = "core" },                      -- Frostbolt
            { id = 27079, kind = "cd",   cd = 8 },              -- Fire Blast
            { id = 27082, kind = "core" },                      -- Arcane Explosion
            { id = 12472, kind = "cd",   cd = 180 },            -- Icy Veins
            { id = 27074, kind = "core" },                      -- Scorch
            { id = 27085, kind = "core" },                      -- Blizzard
            { id = 27088, kind = "cd",   cd = 25 },             -- Frost Nova
        },
        WARLOCK = {
            { id = 6215,  kind = "proc" },                      -- Fear
            { id = 27216, kind = "dot",  dur = 18 },            -- Corruption
            { id = 27218, kind = "dot",  dur = 24 },            -- Curse of Agony
            { id = 1120,  kind = "proc" },                      -- Drain Soul
            { id = 27220, kind = "proc" },                      -- Drain Life
            { id = 11661, kind = "core" },                      -- Shadow Bolt
            { id = 27215, kind = "dot",  dur = 18 },            -- Immolate
            { id = 32231, kind = "core" },                      -- Incinerate
        },
        DRUID = {
            { id = 9834,  kind = "dot",  dur = 12 },            -- Moonfire
            { id = 26984, kind = "core" },                      -- Wrath
            { id = 26986, kind = "core" },                      -- Starfire
            { id = 26993, kind = "dot",  dur = 40 },            -- Faerie Fire
            { id = 26990, kind = "buff", dur = 1800 },          -- Mark of the Wild
            { id = 5487,  kind = "buff", dur = 0 },             -- Bear Form
            { id = 768,   kind = "buff", dur = 0 },             -- Cat Form
            { id = 27002, kind = "core" },                      -- Shred
            { id = 27008, kind = "dot",  dur = 12 },            -- Rip
            { id = 24248, kind = "core" },                      -- Ferocious Bite
            { id = 33983, kind = "dot",  dur = 12 },            -- Mangle (Cat)
            { id = 9840,  kind = "dot",  dur = 12 },            -- Rejuvenation
            { id = 9888,  kind = "core" },                      -- Healing Touch
            { id = 9858,  kind = "dot",  dur = 21 },            -- Regrowth
            { id = 17116, kind = "cd",   cd = 180 },            -- Nature's Swiftness
            { id = 18562, kind = "cd",   cd = 15 },             -- Swiftmend
        },
    },

    -- -----------------------------------------------------------------------
    -- class wide tips
    -- The research pass only produced spec level tips, not class wide ones,
    -- so there is nothing to put here that was not invented. Left empty on
    -- purpose; everything the research pass gave us lives in SPEC_TIPS below.
    -- -----------------------------------------------------------------------
    CLASS_TIPS = {},

    -- -----------------------------------------------------------------------
    -- spec tips, keyed by class then tabIndex (1, 2, 3 in talent tree order)
    -- -----------------------------------------------------------------------
    SPEC_TIPS = {
        WARRIOR = {
            [1] = { -- Arms
                "Slam timing is everything. Cast it immediately after your auto-attack lands to maximize damage before your next swing.",
                "Mortal Strike is your main damage button and reduces healing on targets. Never let it sit off cooldown.",
                "Maintain Battle Shout for the entire fight or you will lose significant damage and threat to your group.",
                "Blood Frenzy through Rend is mandatory for raid groups as it increases all physical damage to your targets by 4 percent.",
                "Learn the 20 percent health threshold for Execute. Switching to fast one-handed weapons during this phase is a significant DPS gain.",
            },
            [2] = { -- Fury
                "Bloodthirst is your main damage ability. Do not hold it off cooldown just to pool rage for Whirlwind.",
                "Pool rage for Whirlwind but not at the expense of skipping Bloodthirst. The cooldown priority matters more than perfect rage management.",
                "Rampage stacks must be kept up. Refresh the buff in the last few seconds before it expires to maintain full stacks.",
                "Maintain Battle Shout at all times. Warriors without shout lose damage, health, and threat compared to those with it.",
                "Execute below 20 percent health, then use Whirlwind with the rage you saved. Never waste Execute phase on auto-attacks.",
            },
            [3] = { -- Protection
                "Shield Slam is your main threat button. It must be used on cooldown every 6 seconds for threat generation and to dispel magic buffs.",
                "Shield Block should maintain close to 100 percent uptime against bosses with crushing blows. It is your primary mitigation tool.",
                "Sunder Armor requires 5 stacks to maximize armor reduction on the target. Layer your Devastates to maintain full stacks.",
                "Demoralizing Shout is not just for you. Keeping it up reduces damage the entire group takes from melee enemies.",
                "Shield Wall is an emergency tool with a 30 minute cooldown. Do not waste it on trash, save it for planned boss mechanics.",
            },
        },
        PALADIN = {
            [1] = { -- Holy
                "Flash of Light is your most-cast spell, not Holy Light. Spamming Holy Light depletes mana quickly without comparable healing.",
                "Use lower ranks of Holy Light to maintain the Light's Grace buff without overhealing and wasting mana.",
                "Holy Shock is only for emergencies or movement. It is expensive and should not be part of your regular healing rotation.",
                "Keep your seal active and judge it regularly to unleash its effect and maintain threat on Judgment.",
                "Divine Favor guarantees your next heal will crit. Use it just before expected burst damage intake.",
            },
            [2] = { -- Protection
                "Holy Shield generates both threat and blocking. Keep it rolling on cooldown throughout the fight.",
                "Consecration is your multi-target threat generator. Place it at your feet in AoE pulls.",
                "Seal of Wisdom restores mana on Judgment. Maintain it to keep your mana pool sustainable.",
                "Divine Shield causes Forbearance. You cannot use it again for 12 seconds and cannot use Divine Protection or Intervention during this window.",
                "Use Judgment both as threat generation and to maintain Holy Shield uptime if talented.",
                "Exorcism provides snap threat to run-away targets. Use it to maintain threat on enemies pulled away from the pack.",
            },
            [3] = { -- Retribution
                "Crusader Strike is your filler button. Cast it on cooldown between Judgments.",
                "Your seal is where your damage comes from. Keep Seal of Blood (Horde) or Seal of Vengeance (Alliance) active and reapply after every Judge.",
                "Judge immediately after auto-attacking to maximize weapon damage and seal effect procs.",
                "Hammer of Wrath is for execute phase only. Save it for targets below 20 percent health, do not waste it early.",
                "Avenging Wrath increases all damage by 30 percent. Use it together with cooldowns for burst phases.",
                "You have no mobility tools. Position carefully before engaging and stay in melee range.",
            },
        },
        HUNTER = {
            [1] = { -- Beast Mastery
                "Kill Command only triggers after your own critical hit on the current target. Do not tab between enemies expecting it to be ready on every mob.",
                "Steady Shot is your main filler after level 62. Weave it between Auto Shots without interrupting your ranged weapon's attack sequence, or you will clip damage.",
                "Your pet does 40 to 50 percent of your total damage in Beast Mastery. Keep it attacking constantly between your shots, never pull threat away.",
                "Use Aspect of the Hawk for pure damage output. Only switch to Aspect of the Viper when your mana runs critically low during long fights.",
                "Bestial Wrath lasts 18 seconds and has a 2 minute cooldown. Combine it with Rapid Fire and a damage potion to create your burst phase at key moments.",
            },
            [2] = { -- Marksmanship
                "Aimed Shot has a 3 second cast time. Only use it before combat starts or when you need burst damage, not during sustained rotation with Steady Shot.",
                "Kill Command requires your own critical hit to trigger. On trash with lower health, you may never land a crit and this ability will not fire.",
                "Multi-Shot is instant cast and deals more per use than Steady Shot. Keep it ready for any pack of 2 or more enemies grouped together.",
                "Do not attempt to Steady Shot while moving. You will lose damage by casting it and then being interrupted. Use instant shots instead.",
                "If you are assigned to Hunter's Mark, maintain it on the boss for the entire fight. Never let it fall off as it increases all party damage to that target.",
            },
            [3] = { -- Survival
                "Readiness resets your Rapid Fire cooldown to enable a second cast. This is your entire burst damage toolkit, use it during your opener or key damage phases.",
                "Explosive Trap is instant cast and deals area damage. Place it before trash engages so damage applies immediately, do not waste it on single targets.",
                "Traps are placed effects with a 1 minute duration. Check that your trap is actually on the ground before starting the next one or it will not fire.",
                "You have no survival cooldown like other specs. Position yourself at range and do not stand in area damage effects or melee range.",
                "Survival is the hardest hitting single-target hunter spec but trades group utility. Do not expect to maintain buffs like other hunters do.",
            },
        },
        ROGUE = {
            [1] = { -- Assassination
                "Keep Deadly Poison weapon buff active at all times. Without poison stacks, Envenom becomes a weak finisher. Reapply with Shiv every 30 seconds.",
                "Maintain Slice and Dice constantly for haste. Assassination DPS plummets when this buff drops. Refresh at 2 to 3 combo points rather than letting it expire.",
                "Cold Blood plus Envenom is your biggest damage spike. Cold Blood guarantees a critical strike on your next finisher. Always use this combo as your burst window.",
                "Garrote as an opener generates 1 combo point and applies a silencing DoT. This is superior to Cheap Shot because the silence persists while you build more points.",
                "Do not use Eviscerate in raids. Rupture at 5 combo points deals more damage over time and keeps the DoT rolling. Only Eviscerate trash mobs or when the target will die before Rupture expires.",
            },
            [2] = { -- Combat
                "Stack Blade Flurry and Adrenaline Rush together. This is your biggest burst window. The 2 minute cooldown on Blade Flurry usually means they never sync perfectly again in a raid fight.",
                "Maintain Slice and Dice constantly even though you have many combo point builders. Missing uptime on this haste buff costs more damage than missing a Rupture tick.",
                "Energy pooling is critical in Combat. Do not spend energy immediately when it regenerates. Instead, keep 65 to 85 energy available so you can chain abilities without downtime.",
                "Combat is the most consistent DPS spec and the primary raid choice. Your DPS doesn't spike and crash like Assassination does. You provide steady, reliable damage.",
                "When using Expose Armor in a raid, you lose significant personal DPS. Only use this finisher if your raid specifically assigns you to armor reduction duty.",
            },
            [3] = { -- Subtlety
                "Subtlety is a PvP specialization. While you can raid with Hemorrhage, Combat and Assassination both out-DPS you significantly in Tier 5 and later content. Raid as Subtlety only if you love the playstyle.",
                "Hemorrhage reduces enemy armor when it crits, but do not prioritize Rupture uptime over Hemorrhage hits. Your combo point generation suffers too much without the extra strikes.",
                "Preparation resets all your defensive cooldowns. Use it to Vanish, re-open from stealth, or chain Evasion windows. In raids, this is your survival tool when mechanics force you to bail.",
                "Use Cheap Shot or Garrote as your stealth opener, then build toward Slice and Dice and Rupture before spending your remaining combo points.",
                "Never take Subtlety to a raid unless the content is old tier and overgeared, or unless you are purely specing for survivability. Even then, you will parse lower than your raid's Assassination and Combat rogues.",
            },
        },
        PRIEST = {
            [1] = { -- Discipline
                "Power Word: Shield is your primary defensive tool. Refresh it regularly to keep your shield buff active and prevent damage spikes.",
                "Prayer of Mending is instant-cast, so use it while moving or when you need a quick heal without interrupting your position.",
                "Combine Flash Heal for fast emergency heals and Greater Heal for solid throughput when there is no pressure.",
                "Inner Focus should be used before your biggest heals to reduce their mana cost by 25 percent and increase critical strike chance.",
                "Discipline excels at preventing damage through shields and planning ahead, not reacting to damage already taken.",
            },
            [2] = { -- Holy
                "Renew is best used as preventative healing and upkeep between the heavy damage periods, not as your main button.",
                "Prayer of Healing is your answer to group damage. Cast it when three or more allies need healing in one area.",
                "Holy priests rely more on sustained healing and group coverage than discipline priests, which excel at prevention.",
                "Flash Heal is your fast response for emergency single-target healing when someone drops quickly.",
            },
            [3] = { -- Shadow
                "Mind Blast is your hardest-hitting button on an 8 second cooldown. Press it every time it is ready, do not save it for later.",
                "Shadow Word: Pain and Vampiric Touch are both damage over time effects that need to be kept on the target. Both ticking heals you, so keeping them up is survival, not just damage.",
                "Mind Flay is your main filler button. Channel it to deal damage while other cooldowns recharge.",
                "Shadowfiend is a pet on a 5 minute cooldown that generates mana as it attacks. Summon it at the start of fights, or before long damage phases to maintain your mana pool.",
                "Shadow Word: Death is powerful but costs health if the target survives. Use it on low-health enemies or when you have room in your health pool to take the hit.",
            },
        },
        SHAMAN = {
            [1] = { -- Elemental
                "Totem of Wrath lasts only 2 minutes. Refresh it frequently or your raid loses spell hit and crit bonuses.",
                "Flame Shock should be refreshed when 2 to 3 seconds remain. Letting it fall off wastes a global cooldown and damages your uptime.",
                "Chain Lightning bounces to nearby enemies. Cast it on grouped targets, not single enemies, for multi-target damage.",
                "Wrath of Air Totem increases party spell hit chance. Swap it in when your casters need accuracy over mana.",
                "Move while casting Flame Shock. It is your only instant damage spell for repositioning.",
            },
            [2] = { -- Enhancement
                "Windfury Weapon must be on both weapons. Each weapon procs independently, so both need the buff for double output.",
                "Stormstrike's debuff increases Nature damage taken by 20 percent. Always use it before Earth Shock and Flame Shock to amplify damage.",
                "Shamanistic Rage reduces damage taken by 30 percent. Use it for survival when taking heavy damage, not just mana.",
                "Earth Shock and Flame Shock share a 6 second cooldown. Use Earth Shock for raw damage in that window.",
                "Flame Shock lasts 30 seconds. Refresh it before expiration or lose the DoT ticks.",
                "Totem twisting Windfury and Grace of Air is optional. Only do it if you can maintain buffs without losing melee time.",
            },
            [3] = { -- Restoration
                "Earth Shield on the tank is your most efficient healing. Cast once and let the charges proc without spamming.",
                "Chain Heal bounces between nearby party members. Position yourself where bounces naturally hit your group.",
                "Nature's Swiftness makes your next spell instant. Pair it with Healing Wave for emergency tank saves.",
                "Mana Tide Totem returns mana to your party. Use it proactively when group mana drops, not during panic.",
                "Lesser Healing Wave costs 25 percent less mana than Healing Wave. Use it for steady healing between emergencies.",
                "Water Shield triggers on every spell cast. Maintain it even if not taking damage for consistent mana recovery.",
            },
        },
        MAGE = {
            [1] = { -- Arcane
                "Stack Arcane Blast before switching to Frostbolt filler. The buff increases damage dealt, so maintain stacks while dealing damage.",
                "Align all cooldowns together: Arcane Power, Icy Veins, and Presence of Mind into a single burst window for maximum output.",
                "Frostbolt is essential mana recovery between Arcane Blast phases. Do not skip it or you will run out of mana.",
                "Cold Snap resets your long cooldowns. Use it to enable a second full burst phase when available.",
                "Mage Armor is mandatory for efficient mana regeneration. Maintain it at all times during combat.",
            },
            [2] = { -- Fire
                "Stack Improved Scorch to 5 stacks with Scorch before switching to Fireball spam. The debuff is mandatory for fire damage.",
                "Hold Combustion and Icy Veins for execute phase when the target is below 20 percent health to maximize burst damage.",
                "Flamestrike costs significant mana. Only use it for multiple targets or when you cannot move, not as a regular filler.",
                "Fire Blast is an instant filler for movement and crit procs. Do not weave it between Fireball casts in your main rotation.",
                "Molten Armor provides passive fire damage return. Keep it active at all times for continuous damage contribution.",
            },
            [3] = { -- Frost
                "Frostbolt is your main rotation. Cast it constantly and Winter's Chill maintains itself automatically, do not switch spells unnecessarily.",
                "Ice Lance deals extra damage when the target is frozen. Only use it as a follow-up after Frost Nova or a freeze effect lands.",
                "Summon Water Elemental on cooldown and use Cold Snap to reset it during burst windows for continuous pet damage.",
                "Blizzard is a channeled spell. Ensure you are safe to complete the entire channel without interruption before casting.",
                "Choose between Mage Armor for mana efficiency or Frost Armor for movement control, and maintain your choice at all times.",
            },
        },
        WARLOCK = {
            [1] = { -- Affliction
                "Maintain 100 percent uptime on Curse of the Elements. This buff for the raid's casters must never drop during combat.",
                "Do not clip your damage-over-time effects by refreshing too early. Wait until the final tick is about to happen or you waste damage.",
                "Download an addon or Weak Aura to track your multiple DoT timers so you never let them fall off unexpectedly.",
                "Time your Life Tap casts carefully since they trigger the global cooldown. Avoid tapping when you are about to take a mechanic.",
                "Summon an Imp as your demon to provide party spell damage buffs while you apply sustained DoT pressure.",
            },
            [2] = { -- Demonology
                "Keep your Felguard alive at all times. If your pet dies mid-fight, your damage output drops sharply until it is resummoned.",
                "Soul Link shares damage between you and your pet, so stamina is more valuable for Demonology than other specs.",
                "Position your Felguard correctly and pull it back when it takes too much damage to prevent a total wipe.",
                "Maintain Fel Armor before pulls and ensure your assigned target has a Soulstone ready for combat.",
                "Manage your DoTs on the target and use Shadow Bolt as your primary filler. Your pet does the heavy lifting.",
            },
            [3] = { -- Destruction
                "Watch your threat constantly. You deal burst damage and can easily pull aggro if the tank is not ahead.",
                "Do not use Conflagrate on cooldown. Only cast it when you need to move and do not need to Life Tap for mana.",
                "Maintain Immolate constantly as your foundation. For Fire builds, Incinerate does bonus damage when Immolate is active.",
                "Choose your demon wisely. Use Imp for fire single-target damage, Succubus for AoE or shadow builds.",
                "Balance aggressive damage output with awareness of threat levels to keep your raid alive and not wiping the group.",
            },
        },
        DRUID = {
            [1] = { -- Balance
                "Keep Moonfire on the target at all times, but allow it to expire completely before refreshing. Refreshing early wastes mana and damage.",
                "Maintain Insect Swarm even though it deals less damage than Moonfire, because the -2 percent hit debuff benefits your entire group's melee and ranged attackers.",
                "Your rotation is roughly three Starfire casts followed by refreshing all DoTs, then repeat. This balances maximizing damage while maintaining debuff uptime.",
                "If mana becomes an issue mid-fight, stop casting DoTs entirely and spam only Starfire and Wrath to preserve mana for emergency healing.",
                "Always cast Faerie Fire in raids because other Balance druids share the Improved Faerie Fire talent bonus, making it a group-wide damage buff.",
                "Use Force of Nature on cooldown for consistent additional damage. The treants' attack speed scales with your haste.",
            },
            [2] = { -- Feral Combat
                "Always keep Mangle (Cat)'s debuff active on your target. The 30 percent bleed damage boost applies to your Rips and benefits other bleed users in your group.",
                "Use Rip at 4 or more combo points only against enemies that will survive its full duration. Otherwise the energy spent generating those combo points is wasted.",
                "Powershifting is the critical skill that separates good Feral DPS from bad. Shift out of Cat Form to regain mana, then shift back in to continue attacking.",
                "Always shift at the lowest energy possible, typically right after Shred or Ferocious Bite, to maximize the energy gained from the mana-to-energy conversion.",
                "Tiger's Fury looks tempting but wastes energy in most situations. Only use it when at max energy about to overflow.",
                "When positioning to attack from behind, use Shred for damage. If you cannot stay behind the target, use Mangle (Cat) instead for the same combo generation.",
            },
            [3] = { -- Restoration
                "Keep triple Lifebloom stacks active on the tank at all times. This is the cornerstone of Restoration healing and provides both consistent healing and mana efficiency.",
                "Use proactive healing by applying HoTs before a damage spike happens, not reactive healing after the damage is taken.",
                "Do not rely solely on Healing Touch spam like you might see in other healing classes. Your rotation should be HoT-centric, not cast-centric.",
                "Use Nature's Swiftness with Healing Touch for large emergency heals when you need instant casting without the 3.5 second cast time.",
                "Tree of Life form increases your healing output by 15 percent but limits movement. Enter it during predictable heavy-damage phases where you can stay stationary.",
                "Coordinate Innervate usage with other druids and mana-hungry casters like Arcane Mages. Communicate who gets Innervate priority in your group.",
            },
        },
    },

    -- -----------------------------------------------------------------------
    -- flat catalogue of the aura group tables used above, for an integrator
    -- that wants to inspect or merge them without walking every spec's track.
    -- -----------------------------------------------------------------------
    AURA_GROUPS = {
        PALADIN_WISDOM_SEAL_GROUP,
        PALADIN_RET_SEAL_GROUP,
        HUNTER_ASPECT_GROUP,
        ROGUE_POISON_GROUP,
        MAGE_ARMOR_GROUP,
        WARLOCK_CURSE_GROUP,
    },

    -- -----------------------------------------------------------------------
    -- item catalogue
    -- The research pass could not produce verified item data: its web search
    -- budget was exhausted and Wowhead's item database returned only
    -- navigation structures, not item or enchant stats. Per the verification
    -- rule this task runs under, an unverified id is worse than a missing
    -- entry, so these are left empty rather than guessed at.
    -- -----------------------------------------------------------------------
    ENCHANTS = {},
    AMMO = {},
    CONSUMABLES = {},
}
