-- GearScout / Profiles.lua
-- What each spec is supposed to be pressing in Burning Crusade.
--
-- Spell ids here exist for one reason: to resolve the localized spell NAME at
-- runtime through GetSpellInfo. Tracking then matches on name, which means
-- every rank of a spell counts as the same button and the addon works in every
-- client locale. An id that fails to resolve is dropped quietly rather than
-- breaking the profile.
--
-- kind:
--   dot   maintain on the target, dur is the debuff length, uptime is measured
--   buff  maintain on yourself, dur is the buff length, uptime is measured
--   cd    used on cooldown, cd is the recharge, missed casts are counted
--   core  the bread and butter button, counted only
--   proc  reactive and situational, counted only, never judged

local ADDON, ns = ...

-- ---------------------------------------------------------------------------
-- aura groups
--
-- Some things must be up, but which one is the player's choice. A paladin
-- runs exactly one seal at a time, so checking for a specific seal would
-- report "never up" for every seal they did not pick. A group counts as up
-- when ANY member of it is up, which turns a false accusation into the check
-- that actually matters: a paladin with no seal at all is barely playing.
--
-- ids only exist to resolve localized names, same as everywhere else here.
-- ---------------------------------------------------------------------------
local SEAL_GROUP = {
    group = "seal", kind = "buff", label = "a Seal", dur = 30,
    ids = {
        21084, -- Seal of Righteousness
        20375, -- Seal of Command
        31892, -- Seal of Blood
        31801, -- Seal of Vengeance
        21082, -- Seal of the Crusader
        20165, -- Seal of Light
        20166, -- Seal of Wisdom
        20164, -- Seal of Justice
    },
}

local ASPECT_GROUP = {
    group = "aspect", kind = "buff", label = "an Aspect", dur = 1800,
    ids = {
        13165, -- Aspect of the Hawk
        5118,  -- Aspect of the Cheetah
        13163, -- Aspect of the Monkey
        34074, -- Aspect of the Viper
        13159, -- Aspect of the Pack
    },
}

local MAGE_ARMOR_GROUP = {
    group = "armor", kind = "buff", label = "an Armor spell", dur = 1800,
    ids = {
        168,   -- Frost Armor
        7302,  -- Ice Armor
        6117,  -- Mage Armor
        30482, -- Molten Armor
    },
}

ns.PROFILES = {

    WARRIOR = {
        [1] = { name = "Arms", role = "melee", track = {
            { id = 772,   kind = "dot",  dur = 21 },   -- Rend
            { id = 12294, kind = "cd",   cd = 6 },     -- Mortal Strike
            { id = 1680,  kind = "cd",   cd = 10 },    -- Whirlwind
            { id = 7384,  kind = "proc" },             -- Overpower
            { id = 5308,  kind = "proc" },             -- Execute
            { id = 1464,  kind = "core" },             -- Slam
            { id = 78,    kind = "core" },             -- Heroic Strike
            { id = 12292, kind = "cd",   cd = 180 },   -- Death Wish
            { id = 6673,  kind = "buff", dur = 120 },  -- Battle Shout
        }},
        [2] = { name = "Fury", role = "melee", track = {
            { id = 23881, kind = "cd",   cd = 6 },     -- Bloodthirst
            { id = 1680,  kind = "cd",   cd = 10 },    -- Whirlwind
            { id = 78,    kind = "core" },             -- Heroic Strike
            { id = 5308,  kind = "proc" },             -- Execute
            { id = 12292, kind = "cd",   cd = 180 },   -- Death Wish
            { id = 6673,  kind = "buff", dur = 120 },  -- Battle Shout
        }},
        [3] = { name = "Protection", role = "tank", track = {
            { id = 23922, kind = "cd",   cd = 6 },     -- Shield Slam
            { id = 6572,  kind = "cd",   cd = 5 },     -- Revenge
            { id = 20243, kind = "core" },             -- Devastate
            { id = 6343,  kind = "cd",   cd = 4 },     -- Thunder Clap
            { id = 1160,  kind = "buff", dur = 30 },   -- Demoralizing Shout
            { id = 469,   kind = "buff", dur = 120 },  -- Commanding Shout
        }},
    },

    -- Paladin is the most carefully modelled class here, because almost
    -- everything that separates a good one from a bad one is a thing that is
    -- either up or not up, which is exactly what this addon can measure.
    PALADIN = {
        [1] = { name = "Holy", role = "healer", track = {
            SEAL_GROUP,
            { id = 20473, kind = "cd",   cd = 15 },    -- Holy Shock
            { id = 20271, kind = "cd",   cd = 10 },    -- Judgement, for Wisdom or Light on the target
            { id = 19750, kind = "core" },             -- Flash of Light
            { id = 635,   kind = "core" },             -- Holy Light
            { id = 20216, kind = "cd",   cd = 120 },   -- Divine Favor
            { id = 19742, kind = "buff", dur = 600 },  -- Blessing of Wisdom
        }},
        [2] = { name = "Protection", role = "tank", track = {
            { id = 25780, kind = "buff", dur = 1800 }, -- Righteous Fury, the single biggest tanking mistake
            { id = 20925, kind = "buff", dur = 10 },   -- Holy Shield
            SEAL_GROUP,
            { id = 26573, kind = "cd",   cd = 8 },     -- Consecration
            { id = 20271, kind = "cd",   cd = 10 },    -- Judgement
            { id = 31935, kind = "cd",   cd = 30 },    -- Avenger's Shield
            { id = 20911, kind = "buff", dur = 600 },  -- Blessing of Sanctuary
        }},
        [3] = { name = "Retribution", role = "melee", track = {
            SEAL_GROUP,
            { id = 20271, kind = "cd",   cd = 10 },    -- Judgement
            { id = 35395, kind = "cd",   cd = 6 },     -- Crusader Strike
            { id = 26573, kind = "cd",   cd = 8 },     -- Consecration
            { id = 879,   kind = "cd",   cd = 15 },    -- Exorcism
            { id = 31884, kind = "cd",   cd = 180 },   -- Avenging Wrath
            { id = 19740, kind = "buff", dur = 600 },  -- Blessing of Might
        }},
    },

    HUNTER = {
        [1] = { name = "Beast Mastery", role = "ranged", track = {
            { id = 34120, kind = "core" },             -- Steady Shot
            { id = 1978,  kind = "dot",  dur = 15 },   -- Serpent Sting
            { id = 19574, kind = "cd",   cd = 120 },   -- Bestial Wrath
            { id = 3045,  kind = "cd",   cd = 300 },   -- Rapid Fire
            { id = 2643,  kind = "cd",   cd = 10 },    -- Multi-Shot
            { id = 1130,  kind = "buff", dur = 120 },  -- Hunter's Mark
            { id = 34026, kind = "core" },             -- Kill Command
        }},
        [2] = { name = "Marksmanship", role = "ranged", track = {
            { id = 34120, kind = "core" },             -- Steady Shot
            { id = 19434, kind = "cd",   cd = 6 },     -- Aimed Shot
            { id = 3044,  kind = "cd",   cd = 6 },     -- Arcane Shot
            { id = 2643,  kind = "cd",   cd = 10 },    -- Multi-Shot
            { id = 1978,  kind = "dot",  dur = 15 },   -- Serpent Sting
            { id = 3045,  kind = "cd",   cd = 300 },   -- Rapid Fire
            { id = 1130,  kind = "buff", dur = 120 },  -- Hunter's Mark
            ASPECT_GROUP,
        }},
        [3] = { name = "Survival", role = "ranged", track = {
            { id = 34120, kind = "core" },             -- Steady Shot
            { id = 3044,  kind = "cd",   cd = 6 },     -- Arcane Shot
            { id = 1978,  kind = "dot",  dur = 15 },   -- Serpent Sting
            { id = 2643,  kind = "cd",   cd = 10 },    -- Multi-Shot
            { id = 3045,  kind = "cd",   cd = 300 },   -- Rapid Fire
            { id = 1130,  kind = "buff", dur = 120 },  -- Hunter's Mark
            ASPECT_GROUP,
        }},
    },

    ROGUE = {
        [1] = { name = "Assassination", role = "melee", track = {
            { id = 1329,  kind = "core" },             -- Mutilate
            { id = 5171,  kind = "buff", dur = 15 },   -- Slice and Dice
            { id = 1943,  kind = "dot",  dur = 16 },   -- Rupture
            { id = 32645, kind = "core" },             -- Envenom
            { id = 14177, kind = "cd",   cd = 180 },   -- Cold Blood
        }},
        [2] = { name = "Combat", role = "melee", track = {
            { id = 1752,  kind = "core" },             -- Sinister Strike
            { id = 5171,  kind = "buff", dur = 15 },   -- Slice and Dice
            { id = 2098,  kind = "core" },             -- Eviscerate
            { id = 1943,  kind = "dot",  dur = 16 },   -- Rupture
            { id = 13750, kind = "cd",   cd = 300 },   -- Adrenaline Rush
            { id = 13877, kind = "cd",   cd = 120 },   -- Blade Flurry
        }},
        [3] = { name = "Subtlety", role = "melee", track = {
            { id = 16511, kind = "core" },             -- Hemorrhage
            { id = 53,    kind = "core" },             -- Backstab
            { id = 5171,  kind = "buff", dur = 15 },   -- Slice and Dice
            { id = 1943,  kind = "dot",  dur = 16 },   -- Rupture
            { id = 36554, kind = "cd",   cd = 30 },    -- Shadowstep
        }},
    },

    PRIEST = {
        [1] = { name = "Discipline", role = "healer", track = {
            { id = 17,    kind = "buff", dur = 30 },   -- Power Word: Shield
            { id = 33076, kind = "cd",   cd = 10 },    -- Prayer of Mending
            { id = 2061,  kind = "core" },             -- Flash Heal
            { id = 2060,  kind = "core" },             -- Greater Heal
            { id = 14751, kind = "cd",   cd = 180 },   -- Inner Focus
        }},
        [2] = { name = "Holy", role = "healer", track = {
            { id = 34861, kind = "cd",   cd = 6 },     -- Circle of Healing
            { id = 33076, kind = "cd",   cd = 10 },    -- Prayer of Mending
            { id = 139,   kind = "dot",  dur = 15 },   -- Renew
            { id = 2061,  kind = "core" },             -- Flash Heal
            { id = 2060,  kind = "core" },             -- Greater Heal
            { id = 596,   kind = "core" },             -- Prayer of Healing
        }},
        [3] = { name = "Shadow", role = "caster", track = {
            { id = 589,   kind = "dot",  dur = 24 },   -- Shadow Word: Pain
            { id = 34914, kind = "dot",  dur = 15 },   -- Vampiric Touch
            { id = 8092,  kind = "cd",   cd = 8 },     -- Mind Blast
            { id = 15407, kind = "core" },             -- Mind Flay
            { id = 32379, kind = "cd",   cd = 12 },    -- Shadow Word: Death
            { id = 15286, kind = "buff", dur = 60 },   -- Vampiric Embrace
            { id = 34433, kind = "cd",   cd = 300 },   -- Shadowfiend
        }},
    },

    SHAMAN = {
        [1] = { name = "Elemental", role = "caster", track = {
            { id = 403,   kind = "core" },             -- Lightning Bolt
            { id = 421,   kind = "cd",   cd = 6 },     -- Chain Lightning
            { id = 8050,  kind = "dot",  dur = 12 },   -- Flame Shock
            { id = 16166, kind = "cd",   cd = 180 },   -- Elemental Mastery
            { id = 30706, kind = "buff", dur = 120 },  -- Totem of Wrath
        }},
        [2] = { name = "Enhancement", role = "melee", track = {
            { id = 17364, kind = "cd",   cd = 10 },    -- Stormstrike
            { id = 8042,  kind = "cd",   cd = 6 },     -- Earth Shock
            { id = 8050,  kind = "dot",  dur = 12 },   -- Flame Shock
            { id = 30823, kind = "cd",   cd = 120 },   -- Shamanistic Rage
            { id = 8190,  kind = "core" },             -- Magma Totem
        }},
        [3] = { name = "Restoration", role = "healer", track = {
            { id = 1064,  kind = "core" },             -- Chain Heal
            { id = 8004,  kind = "core" },             -- Lesser Healing Wave
            { id = 331,   kind = "core" },             -- Healing Wave
            { id = 974,   kind = "buff", dur = 600 },  -- Earth Shield
            { id = 24398, kind = "buff", dur = 600 },  -- Water Shield
            { id = 16190, kind = "cd",   cd = 300 },   -- Mana Tide Totem
        }},
    },

    MAGE = {
        [1] = { name = "Arcane", role = "caster", track = {
            { id = 30451, kind = "core" },             -- Arcane Blast
            { id = 116,   kind = "core" },             -- Frostbolt
            { id = 5143,  kind = "core" },             -- Arcane Missiles
            { id = 12042, kind = "cd",   cd = 180 },   -- Arcane Power
            { id = 12043, kind = "cd",   cd = 180 },   -- Presence of Mind
            { id = 12051, kind = "cd",   cd = 480 },   -- Evocation
            MAGE_ARMOR_GROUP,
        }},
        [2] = { name = "Fire", role = "caster", track = {
            { id = 133,   kind = "core" },             -- Fireball
            { id = 2948,  kind = "core" },             -- Scorch
            { id = 2136,  kind = "cd",   cd = 8 },     -- Fire Blast
            { id = 11129, kind = "cd",   cd = 180 },   -- Combustion
            { id = 12051, kind = "cd",   cd = 480 },   -- Evocation
            MAGE_ARMOR_GROUP,
        }},
        [3] = { name = "Frost", role = "caster", track = {
            { id = 116,   kind = "core" },             -- Frostbolt
            { id = 30455, kind = "core" },             -- Ice Lance
            { id = 12472, kind = "cd",   cd = 180 },   -- Icy Veins
            { id = 11958, kind = "cd",   cd = 480 },   -- Cold Snap
            { id = 31687, kind = "cd",   cd = 180 },   -- Summon Water Elemental
            { id = 12051, kind = "cd",   cd = 480 },   -- Evocation
            MAGE_ARMOR_GROUP,
        }},
    },

    WARLOCK = {
        [1] = { name = "Affliction", role = "caster", track = {
            { id = 172,   kind = "dot",  dur = 18 },   -- Corruption
            { id = 980,   kind = "dot",  dur = 24 },   -- Curse of Agony
            { id = 30108, kind = "dot",  dur = 18 },   -- Unstable Affliction
            { id = 18265, kind = "dot",  dur = 30 },   -- Siphon Life
            { id = 686,   kind = "core" },             -- Shadow Bolt
            { id = 1454,  kind = "core" },             -- Life Tap
        }},
        [2] = { name = "Demonology", role = "caster", track = {
            { id = 686,   kind = "core" },             -- Shadow Bolt
            { id = 172,   kind = "dot",  dur = 18 },   -- Corruption
            { id = 348,   kind = "dot",  dur = 15 },   -- Immolate
            { id = 980,   kind = "dot",  dur = 24 },   -- Curse of Agony
            { id = 1454,  kind = "core" },             -- Life Tap
        }},
        [3] = { name = "Destruction", role = "caster", track = {
            { id = 348,   kind = "dot",  dur = 15 },   -- Immolate
            { id = 29722, kind = "core" },             -- Incinerate
            { id = 17962, kind = "cd",   cd = 10 },    -- Conflagrate
            { id = 686,   kind = "core" },             -- Shadow Bolt
            { id = 172,   kind = "dot",  dur = 18 },   -- Corruption
            { id = 17877, kind = "cd",   cd = 15 },    -- Shadowburn
            { id = 1454,  kind = "core" },             -- Life Tap
        }},
    },

    DRUID = {
        [1] = { name = "Balance", role = "caster", track = {
            { id = 8921,  kind = "dot",  dur = 12 },   -- Moonfire
            { id = 5570,  kind = "dot",  dur = 12 },   -- Insect Swarm
            { id = 2912,  kind = "core" },             -- Starfire
            { id = 5176,  kind = "core" },             -- Wrath
            { id = 770,   kind = "dot",  dur = 40 },   -- Faerie Fire
            { id = 33831, kind = "cd",   cd = 180 },   -- Force of Nature
            { id = 29166, kind = "cd",   cd = 360 },   -- Innervate
        }},
        [2] = { name = "Feral Combat", role = "melee", track = {
            { id = 33876, kind = "core" },             -- Mangle (Cat)
            { id = 5221,  kind = "core" },             -- Shred
            { id = 1079,  kind = "dot",  dur = 12 },   -- Rip
            { id = 1822,  kind = "dot",  dur = 9 },    -- Rake
            { id = 22568, kind = "core" },             -- Ferocious Bite
            { id = 5217,  kind = "cd",   cd = 30 },    -- Tiger's Fury
            { id = 33878, kind = "cd",   cd = 6 },     -- Mangle (Bear)
            { id = 33745, kind = "dot",  dur = 15 },   -- Lacerate
            { id = 6807,  kind = "core" },             -- Maul
            { id = 16857, kind = "dot",  dur = 40 },   -- Faerie Fire (Feral)
            { id = 99,    kind = "dot",  dur = 30 },   -- Demoralizing Roar
        }},
        [3] = { name = "Restoration", role = "healer", track = {
            { id = 33763, kind = "buff", dur = 7 },    -- Lifebloom
            { id = 774,   kind = "dot",  dur = 12 },   -- Rejuvenation
            { id = 8936,  kind = "dot",  dur = 21 },   -- Regrowth
            { id = 18562, kind = "cd",   cd = 15 },    -- Swiftmend
            { id = 5185,  kind = "core" },             -- Healing Touch
            { id = 29166, kind = "cd",   cd = 360 },   -- Innervate
        }},
    },
}

-- ---------------------------------------------------------------------------
-- levelling baselines
--
-- The spec tables above describe a finished level 70 character. A level 26
-- hunter has learned three of those seven spells, which leaves almost nothing
-- to coach. These are the buttons that every spec of a class uses on the way
-- up, and they are merged in only when the spec list turns out to be mostly
-- unlearned, so an endgame profile is never polluted by them.
--
-- Anything that is right for one spec but wrong for another is marked proc,
-- which counts casts without ever judging them.
-- ---------------------------------------------------------------------------
ns.BASE_TRACK = {
    WARRIOR = {
        { id = 6673,  kind = "buff", dur = 120 }, -- Battle Shout
        { id = 772,   kind = "dot",  dur = 21 },  -- Rend
        { id = 6343,  kind = "cd",   cd = 4 },    -- Thunder Clap
        { id = 78,    kind = "proc" },            -- Heroic Strike
    },
    PALADIN = {
        { id = 21084, kind = "buff", dur = 30 },  -- Seal of Righteousness
        { id = 20271, kind = "cd",   cd = 10 },   -- Judgement
        { id = 19740, kind = "buff", dur = 600 }, -- Blessing of Might
    },
    HUNTER = {
        { id = 1130,  kind = "buff", dur = 120 }, -- Hunter's Mark
        { id = 1978,  kind = "dot",  dur = 15 },  -- Serpent Sting
        { id = 3044,  kind = "cd",   cd = 6 },    -- Arcane Shot
        { id = 2643,  kind = "cd",   cd = 10 },   -- Multi-Shot
        ASPECT_GROUP,                             -- any Aspect counts as up
    },
    ROGUE = {
        { id = 5171,  kind = "buff", dur = 15 },  -- Slice and Dice
        { id = 1752,  kind = "proc" },            -- Sinister Strike
        { id = 2098,  kind = "proc" },            -- Eviscerate
    },
    PRIEST = {
        { id = 589,   kind = "dot",  dur = 24 },  -- Shadow Word: Pain
        { id = 17,    kind = "buff", dur = 30 },  -- Power Word: Shield
        { id = 139,   kind = "proc" },            -- Renew
        { id = 585,   kind = "proc" },            -- Smite
    },
    SHAMAN = {
        { id = 324,   kind = "buff", dur = 600 }, -- Lightning Shield
        { id = 8050,  kind = "dot",  dur = 12 },  -- Flame Shock
        { id = 8042,  kind = "cd",   cd = 6 },    -- Earth Shock
        { id = 403,   kind = "proc" },            -- Lightning Bolt
    },
    MAGE = {
        { id = 2136,  kind = "cd",   cd = 8 },    -- Fire Blast
        { id = 116,   kind = "proc" },            -- Frostbolt
        { id = 133,   kind = "proc" },            -- Fireball
        { id = 5143,  kind = "proc" },            -- Arcane Missiles
    },
    WARLOCK = {
        { id = 172,   kind = "dot",  dur = 18 },  -- Corruption
        { id = 980,   kind = "dot",  dur = 24 },  -- Curse of Agony
        { id = 348,   kind = "dot",  dur = 15 },  -- Immolate
        { id = 686,   kind = "proc" },            -- Shadow Bolt
        { id = 1454,  kind = "proc" },            -- Life Tap
    },
    DRUID = {
        { id = 8921,  kind = "dot",  dur = 12 },  -- Moonfire
        { id = 770,   kind = "dot",  dur = 40 },  -- Faerie Fire
        { id = 5176,  kind = "proc" },            -- Wrath
        { id = 774,   kind = "proc" },            -- Rejuvenation
        { id = 1082,  kind = "proc" },            -- Claw
        { id = 6807,  kind = "proc" },            -- Maul
    },
}

-- Below this many learned spec spells, the baseline list is merged in.
local THIN_PROFILE = 5

-- ---------------------------------------------------------------------------
-- coaching tips
--
-- These are not measurements. They are the handful of things that separate
-- someone who is playing the class from someone who is pressing buttons, and
-- they are worth saying even when nothing is technically wrong. Written for a
-- person who has never read a guide.
-- ---------------------------------------------------------------------------
ns.CLASS_TIPS = {
    HUNTER = {
        "Send your pet in first and let it land a hit or two before you attack. It builds threat and takes the hits for you, which is exactly right. GearScout measures your rotation from your first shot, not from the pull, so opening this way is never counted against you.",
        "Keep an Aspect up at all times. Aspect of the Hawk is the damage one and it costs nothing to maintain.",
        "Hunter's Mark before the pull is free and makes every single shot hit harder.",
        "Stay at range. If something reaches you, your shots get much weaker, so use the space your pet is buying you.",
    },
    PALADIN = {
        "A Seal must be up at all times. Without one your swings are ordinary weapon hits and you lose a large slice of everything you do.",
        "Judgement uses up your Seal, so put the Seal straight back on afterwards. Seal, Judgement, Seal again is the rhythm.",
        "Keep a Blessing on yourself. There is never a good reason to stand there without one.",
    },
    WARLOCK = {
        "Your demon is a real part of your damage. Summon one before you pull and keep it alive.",
        "Life Tap turns health into mana. Using it while at full health wastes nothing and keeps you casting.",
    },
    WARRIOR = {
        "Rage only builds while you are being hit or hitting something. Standing still doing nothing loses it.",
    },
}

ns.SPEC_TIPS = {
    PALADIN = {
        [1] = { -- Holy
            "Flash of Light is your small fast heal and Holy Light is the big slow one. Leaning on the big one empties your mana in under a minute, so use the small one for topping people up.",
            "Judgement of Wisdom on whatever the group is fighting gives mana back to everyone hitting it. It is one of the most valuable things you bring and it needs refreshing.",
            "Holy Shock is instant, so it is what you use while moving. Do not let it sit unused.",
        },
        [2] = { -- Protection
            "Righteous Fury must be on whenever you are tanking. Without it you make far less threat and things will run past you to the healer. This is the single most common paladin tanking mistake.",
            "Holy Shield is both your damage blocking and a large part of your threat. Keep it refreshed, it is short.",
            "Consecration is what holds a group of enemies on you. Drop it as soon as you pull, before anyone else does damage.",
        },
        [3] = { -- Retribution
            "The loop is Judgement, then Crusader Strike, then re-apply your Seal, with Consecration and Exorcism when they are ready.",
            "Seal of Command is the standard damage seal. Alliance paladins without Seal of Blood should be using it.",
            "Avenging Wrath is a big damage window on a long cooldown. Press it early in a fight rather than saving it for a moment that never comes.",
        },
    },
    HUNTER = {
        [1] = { -- Beast Mastery
            "Bestial Wrath is your biggest button. Use it every time it is ready, do not hold it.",
            "Your pet is a much larger share of your damage as Beast Mastery than other hunters. Feed it, keep it alive, and make sure its abilities are set to autocast in the pet spellbook.",
        },
        [2] = { -- Marksmanship
            "Aimed Shot and Arcane Shot share your attention with Steady Shot. Fire the ones on cooldown first and use Steady Shot to fill the gaps.",
        },
        [3] = { -- Survival
            "Your traps are part of your damage, not just an escape. Drop one before the pull when you can.",
        },
    },
}

-- Everything worth telling this character right now.
function ns.GetTips()
    local out = {}
    local cls = ns.playerClass
    if not cls then return out end

    local classTips = ns.CLASS_TIPS[cls]
    if classTips then
        for _, t in ipairs(classTips) do out[#out + 1] = t end
    end

    -- Researched spec tips are preferred where they exist, but the hand
    -- written class tips above stay in either way. The research pass returned
    -- nothing at class level, and those lines are the ones that explain things
    -- like opening with the pet, which is exactly the advice worth keeping.
    local prof = ns.activeProfile
    local research = ((ns.db == nil) or (ns.db.dataSource ~= "builtin")) and ns.RESEARCH or nil
    local specTips = (research and research.SPEC_TIPS and research.SPEC_TIPS[cls])
                     or ns.SPEC_TIPS[cls]
    if specTips and prof and prof.tabIndex then
        local list = specTips[prof.tabIndex]
        if list then
            for _, t in ipairs(list) do out[#out + 1] = t end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- resolution
-- Turns the id based tables above into name keyed lookups for the current
-- character. Runs once at login and again whenever talents or spells change.
-- ---------------------------------------------------------------------------

-- Spell name and known checks go through the Core shims. The Anniversary
-- client no longer has GetSpellBookItemName or BOOKTYPE_SPELL, so scanning the
-- spellbook by index is not an option any more. Asking about a specific spell
-- id works on every client, and it also sidesteps the rank problem: learning
-- rank 1 of a spell is enough for it to count as known.

ns.activeProfile = nil
ns.unresolvedSpells = 0

-- Which table the current profile came from, surfaced by the diagnostic.
local profileSource = "builtin"
function ns.GetProfileSource() return profileSource end

-- Every class and spec always gets a profile. If a spec has no authored spell
-- list, it still gets an empty one so the rotation tab can report cast rate,
-- idle time and top buttons rather than refusing to work.
function ns.BuildProfile()
    -- Never let a talent API surprise take the whole profile down with it.
    local okSpec, specName, tabIndex = pcall(ns.GetSpec)
    if not okSpec then specName, tabIndex = nil, 1 end
    tabIndex = tabIndex or 1

    -- Two sources exist for this data. The tables further up this file were
    -- written from memory. Data/Rotations.lua was researched, had every spell
    -- id fetched and confirmed, and went through an adversarial audit that
    -- caught two wrong cooldowns and two bad durations. The researched set is
    -- preferred, but the hand written one stays as a fallback that can be
    -- switched back to with /gearscout data builtin if the new data misbehaves.
    local useResearch = (ns.db == nil) or (ns.db.dataSource ~= "builtin")
    local research = useResearch and ns.RESEARCH or nil

    local classProfiles = (research and research.PROFILES and research.PROFILES[ns.playerClass or ""])
                          or ns.PROFILES[ns.playerClass or ""]
    profileSource = (research and research.PROFILES and research.PROFILES[ns.playerClass or ""])
                    and "researched" or "builtin"

    local raw = classProfiles and (classProfiles[tabIndex] or classProfiles[1]) or nil

    local profile = {
        name     = (raw and raw.name) or specName or "Unknown spec",
        role     = (raw and raw.role) or "unknown",
        tabIndex = tabIndex,
        generic  = (raw == nil),
        byName   = {},
        list     = {},
    }

    local unresolved = 0
    local knownSpec = 0

    -- Two entries can resolve to the same name. The first wins, which is the
    -- higher priority one in table order, and spec entries are added first.
    local function AddTrack(entry, basic)
        -- An aura group resolves to a list of names. Uptime counts a moment as
        -- covered when any one of them is present, which is the only fair way
        -- to check a paladin seal or a hunter aspect.
        if entry.ids then
            local names, icon, known = {}, nil, false
            for _, id in ipairs(entry.ids) do
                local n, ic = ns.SpellName(id)
                if n then
                    names[#names + 1] = n
                    icon = icon or ic
                    if ns.SpellKnown(id) then known = true end
                end
            end
            if #names == 0 then
                unresolved = unresolved + 1
                return
            end
            local key = "group:" .. tostring(entry.group)
            if profile.byName[key] then return end

            local resolved = {
                group = entry.group,
                name  = entry.label or names[1],
                names = names,
                icon  = icon,
                kind  = entry.kind,
                cd    = entry.cd,
                dur   = entry.dur,
                known = known,
                basic = basic or nil,
            }
            profile.byName[key] = resolved
            profile.list[#profile.list + 1] = resolved
            if known and not basic then knownSpec = knownSpec + 1 end
            return
        end

        local spellName, icon = ns.SpellName(entry.id)
        if not spellName then
            unresolved = unresolved + 1
            return
        end
        if profile.byName[spellName] then return end

        local known = ns.SpellKnown(entry.id)
        local resolved = {
            id    = entry.id,
            name  = spellName,
            icon  = icon,
            kind  = entry.kind,
            cd    = entry.cd,
            dur   = entry.dur,
            known = known,
            basic = basic or nil,
        }
        profile.byName[spellName] = resolved
        profile.list[#profile.list + 1] = resolved
        if known and not basic then knownSpec = knownSpec + 1 end
    end

    if raw then
        for _, entry in ipairs(raw.track) do AddTrack(entry, false) end
    end

    -- A spec list that is mostly unlearned means a levelling character. Fall
    -- back to the class baseline so there is still something worth saying.
    if knownSpec < THIN_PROFILE then
        local base = (research and research.BASE_TRACK and research.BASE_TRACK[ns.playerClass or ""])
                     or ns.BASE_TRACK[ns.playerClass or ""]
        if base then
            profile.usedBaseline = true
            for _, entry in ipairs(base) do AddTrack(entry, true) end
        end
    end

    local knownTotal = 0
    for _, e in ipairs(profile.list) do
        if e.known then knownTotal = knownTotal + 1 end
    end
    profile.knownCount = knownTotal

    ns.unresolvedSpells = unresolved
    ns.activeProfile = profile
    return profile
end

function ns.GetRole()
    return ns.activeProfile and ns.activeProfile.role or nil
end

local RebuildSoon = ns.Debounce(1.0, function()
    ns.BuildProfile()
    ns:Emit("PROFILE_UPDATED", ns.activeProfile)
end)

ns:On("PLAYER_LOGIN", RebuildSoon)
ns:On("SPELLS_CHANGED", RebuildSoon)
ns:On("CHARACTER_POINTS_CHANGED", RebuildSoon)
ns:On("PLAYER_TALENT_UPDATE", RebuildSoon)
