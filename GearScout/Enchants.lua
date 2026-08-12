-- GearScout / Enchants.lua
-- The enchanting guide. For every slot that can carry a permanent enchant:
-- which one this character actually wants, and what stands between them and
-- having it on.
--
-- The question this answers is the one an enchanter asks. "I am 225 skill and
-- I can enchant myself, so what should I be putting on, what can I make right
-- now, and what do I have to learn or buy." Every option lands in exactly one
-- of three buckets, because those three cost completely different things:
--
--   1. You know the recipe. It costs you materials and nothing else, so the
--      row names the materials.
--   2. You do not know the recipe yet. The row says so and points at where a
--      recipe comes from, when the shipped data knows.
--   3. You cannot apply it at all. Then it is a "buy the materials and find
--      somebody" job, and the row says who has to do it.
--
-- Deliberately NOT gated by ns.ENCHANT_WORTH_IT. That threshold answers
-- "is paying a stranger worth the gold at level 27", which is a different
-- question from "I am an enchanter and the dust is already in my bags". The
-- gear score keeps the threshold, this page never applies it.
--
-- ---------------------------------------------------------------------------
-- WHAT THE SHIPPED DATA ACTUALLY CARRIES, since it decides everything below
-- ---------------------------------------------------------------------------
-- Data/Catalogue.lua's ns.ENCHANT_ITEMS carries exactly two fields per
-- enchant, an id and a name, for 191 enchants across 9 slot categories. It
-- carries NO required skill level and NO reagent list. That is not an
-- oversight downstream: the generator strips the skill annotation from its
-- own source on the way in, see cleanComment in
-- tools/extract-atlasloot-catalogue.mjs, which removes the trailing " / NNN"
-- the source appends to enchant comments.
--
-- So this file invents neither. It reads them from places that genuinely know:
--
--   materials       from the player's own enchanting window, for recipes they
--                   know. The client only hands an addon the reagents of a
--                   learned recipe, so an unknown recipe honestly has no
--                   material list here and says so rather than guessing one.
--   what it gives   from the client's own spell description or spell tooltip,
--                   which is the game's answer, not ours. When the client will
--                   not answer, the enchant's own name is read instead, and a
--                   name that does not say what it does leaves the option
--                   unranked rather than guessed at.
--   required skill  only if the client's tooltip happens to print a
--                   "Requires Enchanting (NNN)" line. Usually it does not, and
--                   then nothing is claimed. This is why the guide leans on
--                   "do you know it" rather than "is your skill high enough":
--                   the first is knowable, the second mostly is not.
--   requirements    the character level an option needs, read from the
--                   client's own required level for the item, or from the
--                   "Requires Level NNN" line of its tooltip when the client
--                   will not answer directly; and the faction standing a
--                   reputation enchant is sold at, which the shipped
--                   reputation data carries per reward. The character's own
--                   standing with that faction is asked of the client too, so
--                   "you are not there yet" is a fact rather than an
--                   assumption. A requirement that could not be read is never
--                   invented: an option is treated as usable until something
--                   readable says otherwise, because hiding a perfectly good
--                   enchant on a suspicion is the worse mistake.
--
-- ---------------------------------------------------------------------------
-- WHY THE LIST IS GROUPED RATHER THAN FILTERED
-- ---------------------------------------------------------------------------
-- A level 27 asking about their head slot is looking at a list where every
-- entry needs level 70 and a faction ground to honored. Showing those first,
-- unmarked, is the bug this grouping exists to fix. Hiding them outright is
-- the other half of the same mistake, because "what should I work toward" is
-- a question this page is supposed to answer.
--
-- So options land in three groups, in this order, each with its own heading
-- that says what the group is waiting on:
--
--   usable now   nothing readable stands in the way. Ranked, best first, and
--                the only group anything is ever called "best" in.
--   soon         a level requirement within LEVEL_SOON levels, or an item
--                level requirement the slot is close to clearing.
--   a long way   a level requirement further out than that, or a reputation
--                off         standing. Capped at MAX_FAR rows with the rest
--                counted in the heading, since twenty level 70 glyphs listed
--                in full at level 27 is noise, and three of them plus "and
--                fourteen more like it" is the same information.
--
-- Reputation is always the far group even when the level is met, which is the
-- same call Upgrades.lua's effort tiers already make and for the same stated
-- reason: a character is not going to farm a faction on the way past, so
-- listing that beside something they could do tonight makes a multi week
-- grind read like an evening's plan.
--
-- Ranking uses Data/StatWeights.lua where that spec has researched weights,
-- and falls back to a plain role preference where it does not, which the page
-- says out loud rather than presenting as research.
--
-- Public API, usable with no UI at all:
--   ns.GetEnchantingSkill()      rank, maxRank, where the number came from
--   ns.KnowsEnchant(id, name)    true plus where that was read from
--   ns.GetEnchantPlan(slotID)    the whole answer for one slot
--   ns.GetEnchantSummary()       the character level picture, for the banner
--   ns.BuildEnchantsPage(page)   the page, called once by CoachUI.lua

local ADDON, ns = ...

local CreateFrame, UIParent = CreateFrame, UIParent
local format, ipairs, pairs, type, tonumber = string.format, ipairs, pairs, type, tonumber
local max, min, sort, wipe, unpack = math.max, math.min, table.sort, wipe, unpack

local T, UI = ns.T, ns.UI
local L = ns.L

-- Enchant names, faction names, standing names and profession names all come
-- from the client or from the extracted catalogue, so they are never
-- translated: they are placed into these sentences exactly as they arrived.

-- Enchanting's own profession spell, used to get the localized profession name
-- rather than comparing against the English word. Scan.lua already resolves the
-- same id for the same reason.
local ENCHANTING_SPELL = 7411
-- Every enchanter has Disenchant. It is the control that proves the spellbook
-- can be read at all on this client, which decides whether "you do not know
-- this recipe" is a fact or a guess.
local DISENCHANT_SPELL = 13262

-- ---------------------------------------------------------------------------
-- the three cases
-- ---------------------------------------------------------------------------
local CASE_SELF  = 1   -- you know it, so it costs materials and nothing else
local CASE_LEARN = 2   -- you could apply it, but you do not know the recipe
local CASE_OTHER = 3   -- somebody else has to apply it, or you buy it outright

local CASE_COLOR = { [CASE_SELF] = "good", [CASE_LEARN] = "warn", [CASE_OTHER] = "accent" }

-- ---------------------------------------------------------------------------
-- what stands between this character and an option
--
-- Separate from the three cases above on purpose. A case answers "who does the
-- work"; a gate answers "can it be done at all yet". An option can be one you
-- know the recipe for and still be forty three levels out of reach.
-- ---------------------------------------------------------------------------
local GATE_NONE = 0   -- nothing readable stands in the way
local GATE_SOON = 1   -- a few levels, or one better item in the slot
local GATE_FAR  = 2   -- a long climb, or a faction to grind

-- How many levels away still counts as soon. Ten is close enough that a
-- character is going to cross it without changing what they are doing, which
-- is the whole difference this number is drawing: soon is something to keep in
-- mind, far is something to plan around.
local LEVEL_SOON = 10

-- Where a slot's permanent bonus comes from. Enchanting does not own all of
-- them, and telling an enchanter to enchant their own legs would be wrong:
-- leg armor is a leatherworker or a tailor, a scope is an engineer, and head
-- and shoulder are bought with reputation by the wearer themselves.
local KIND_ENCHANT = "enchant"
local KIND_REP     = "reputation"
local KIND_LEG     = "legarmor"
local KIND_SCOPE   = "scope"

-- Which ns.ENCHANT_ITEMS category serves each equipment slot. Main hand and
-- off hand resolve at read time, because the right category depends on what is
-- actually worn there.
local CATALOGUE_KEY = {
    [15] = "Cloak",
    [5]  = "Chest",
    [9]  = "Wrist",
    [10] = "Hand",
    [8]  = "Feet",
    [11] = "Ring",
    [12] = "Ring",
}

-- Same order Rules.lua already uses when it decides which missing enchant to
-- complain about first, repeated here so the two screens agree on what matters.
local SLOT_PRIORITY = {
    [16] = 1, [5] = 2, [15] = 3, [8] = 4, [9] = 5, [10] = 6,
    [1] = 7, [3] = 8, [7] = 9, [17] = 10, [11] = 11, [12] = 11, [18] = 12,
}

-- ---------------------------------------------------------------------------
-- reading an enchant's name
--
-- "Enchant Bracer - Superior Strength" is two useful facts in one string: the
-- stat is Strength, and Superior places it on the game's own quality ladder.
-- Both come out of the shipped name, so neither is invented. The ladder only
-- ever decides the ORDER of two enchants that give the same stat; no number is
-- ever quoted to the player from it.
-- ---------------------------------------------------------------------------
local TIER = {
    minor = 1, lesser = 2, advanced = 4, greater = 4, superior = 5,
    mighty = 6, major = 6, exceptional = 7,
}
local TIER_PLAIN = 3

-- Phrase to tag. Scanned in order, so anything that contains a shorter phrase
-- has to sit above it: "restore mana prime" before "mana", "healing power"
-- before "healing", "all stats" before "stats".
local STAT_WORDS = {
    { "all stats",          "allStats" },
    { "stats",              "allStats" },
    { "damage and healing", "spellPower" },
    { "spellpower",         "spellPower" },
    { "spell power",        "spellPower" },
    { "spell damage",       "spellPower" },
    { "spell strike",       "spellHit" },
    { "spellsurge",         "spellPower" },
    { "blasting",           "spellCrit" },
    { "spell penetration",  "spellPen" },
    { "healing power",      "healing" },
    { "healing",            "healing" },
    { "restore mana prime", "manaRegen" },
    { "mana regeneration",  "manaRegen" },
    { "attack power",       "attackPower" },
    { "strength",           "strength" },
    { "agility",            "agility" },
    { "stamina",            "stamina" },
    { "intellect",          "intellect" },
    { "spirit",             "spirit" },
    { "fortitude",          "stamina" },
    { "vitality",           "manaRegen" },
    { "dexterity",          "agility" },
    { "shield block",       "block" },
    { "block",              "block" },
    { "defense",            "defense" },
    { "dodge",              "dodge" },
    { "deflect",            "parry" },
    { "resilience",         "resilience" },
    { "threat",             "tankThreat" },
    { "subtlety",           "threatDown" },
    { "protection",         "armor" },
    { "armor",              "armor" },
    { "health",             "health" },
    { "mana",               "mana" },
    { "resistance",         "resistance" },
    { "absorption",         "situational" },
    { "beastslayer",        "situational" },
    { "elemental slayer",   "situational" },
    { "demonslaying",       "situational" },
    { "striking",           "weaponDamage" },
    { "impact",             "weaponDamage" },
    { "savagery",           "attackPower" },
    { "potency",            "strength" },
    { "assault",            "attackPower" },
    { "brawn",              "strength" },
    { "surefooted",         "hit" },
    { "haste",              "haste" },
    { "speed",              "speed" },
    { "swiftness",          "speed" },
    { "stealth",            "stealth" },
    { "mining",             "profession" },
    { "herbalism",          "profession" },
    { "fishing",            "profession" },
    { "skinning",           "profession" },
    { "riding skill",       "profession" },
}

-- Plain words for a tag, used in the one line that says what an option gives
-- when the client will not describe it itself.
local TAG_WORDS = {
    allStats = "all five stats", spellPower = "spell power", healing = "healing power",
    spellHit = "spell hit", spellCrit = "spell crit", spellPen = "spell penetration",
    manaRegen = "mana regeneration", attackPower = "attack power", strength = "strength",
    agility = "agility", stamina = "stamina", intellect = "intellect", spirit = "spirit",
    block = "block", defense = "defense", dodge = "dodge", parry = "parry",
    resilience = "resilience", tankThreat = "threat", threatDown = "less threat",
    armor = "armor", health = "health", mana = "mana", resistance = "one school of resistance",
    weaponDamage = "weapon damage", haste = "haste", hit = "hit", speed = "movement speed",
    stealth = "stealth", profession = "a gathering profession, not a combat stat",
    situational = "a bonus against one kind of enemy only",
}

-- Which stat weight keys speak for each tag. Best of them wins, never the sum.
-- Same approach and the same key spellings Buffs.lua already uses, because
-- Data/StatWeights.lua is not consistent about them between specs: melee hit
-- is ITEM_MOD_HIT_RATING_SHORT on a hunter and ITEM_MOD_HIT_MELEE_RATING_SHORT
-- on a retribution paladin, so both have to be tried.
local WEIGHT_KEYS = {
    strength    = { "ITEM_MOD_STRENGTH_SHORT" },
    agility     = { "ITEM_MOD_AGILITY_SHORT" },
    stamina     = { "ITEM_MOD_STAMINA_SHORT" },
    intellect   = { "ITEM_MOD_INTELLECT_SHORT" },
    spirit      = { "ITEM_MOD_SPIRIT_SHORT" },
    attackPower = { "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT" },
    spellPower  = { "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" },
    healing     = { "ITEM_MOD_SPELL_HEALING_DONE_SHORT" },
    manaRegen   = { "ITEM_MOD_MANA_REGENERATION_SHORT" },
    hit         = { "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_MELEE_RATING_SHORT" },
    crit        = { "ITEM_MOD_CRIT_RATING_SHORT" },
    haste       = { "ITEM_MOD_HASTE_RATING_SHORT" },
    spellHit    = { "ITEM_MOD_HIT_SPELL_RATING_SHORT" },
    spellCrit   = { "ITEM_MOD_CRIT_SPELL_RATING_SHORT" },
    defense     = { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" },
    dodge       = { "ITEM_MOD_DODGE_RATING_SHORT" },
    parry       = { "ITEM_MOD_PARRY_RATING_SHORT" },
    block       = { "ITEM_MOD_BLOCK_RATING_SHORT" },
    resilience  = { "ITEM_MOD_RESILIENCE_RATING_SHORT" },
    allStats    = { "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
                    "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT" },
    -- armor, health, mana, weapon damage, movement speed, threat, stealth,
    -- resistance and the gathering enchants have no honest stat weight key on
    -- this client. They are decided by role alone, and the page says so.
}

-- Role preference. This is judgement, not research, which is why the page
-- prints a line saying so whenever it is the basis for an answer. It only ever
-- comes into play for a tag with no researched weight, or for a spec
-- StatWeights.lua has not covered yet.
local ROLE_WANTS = {
    melee = {
        strength = 1, agility = 0.85, attackPower = 0.9, stamina = 0.55, hit = 0.9,
        crit = 0.7, haste = 0.5, allStats = 0.9, weaponDamage = 0.85, armor = 0.2,
        defense = 0.1, dodge = 0.15, parry = 0.15, block = 0, health = 0.3,
        speed = 0.5, threatDown = 0.4, tankThreat = 0, stealth = 0.1,
        resistance = 0.2, situational = 0.15, profession = 0, intellect = 0.05,
        spirit = 0.05, mana = 0.05, manaRegen = 0.05, spellPower = 0,
        healing = 0, spellHit = 0, spellCrit = 0, spellPen = 0, resilience = 0.1,
    },
    ranged = {
        agility = 1, attackPower = 0.9, strength = 0.05, stamina = 0.5, hit = 0.9,
        crit = 0.7, haste = 0.5, allStats = 0.9, weaponDamage = 0.4, armor = 0.15,
        defense = 0.05, dodge = 0.1, parry = 0, block = 0, health = 0.25,
        speed = 0.5, threatDown = 0.4, tankThreat = 0, stealth = 0.1,
        resistance = 0.2, situational = 0.15, profession = 0, intellect = 0.2,
        spirit = 0.05, mana = 0.1, manaRegen = 0.15, spellPower = 0,
        healing = 0, spellHit = 0, spellCrit = 0, spellPen = 0, resilience = 0.1,
    },
    tank = {
        stamina = 1, defense = 0.95, dodge = 0.8, parry = 0.7, block = 0.7,
        armor = 0.8, health = 0.7, strength = 0.5, agility = 0.5, attackPower = 0.4,
        hit = 0.5, crit = 0.3, haste = 0.2, allStats = 0.9, weaponDamage = 0.5,
        speed = 0.3, threatDown = 0, tankThreat = 0.8, stealth = 0,
        resistance = 0.4, situational = 0.1, profession = 0, intellect = 0.25,
        spirit = 0.1, mana = 0.15, manaRegen = 0.35, spellPower = 0.2,
        healing = 0, spellHit = 0.1, spellCrit = 0.1, spellPen = 0, resilience = 0.1,
    },
    healer = {
        healing = 1, spellPower = 0.85, manaRegen = 0.9, intellect = 0.8, spirit = 0.75,
        allStats = 0.85, stamina = 0.4, mana = 0.4, spellCrit = 0.45, haste = 0.4,
        spellHit = 0.05, spellPen = 0, armor = 0.15, health = 0.2, defense = 0.05,
        dodge = 0.05, parry = 0, block = 0, strength = 0, agility = 0.05,
        attackPower = 0, hit = 0, crit = 0.05, weaponDamage = 0, speed = 0.5,
        threatDown = 0.5, tankThreat = 0, stealth = 0, resistance = 0.25,
        situational = 0.05, profession = 0, resilience = 0.1,
    },
    caster = {
        spellPower = 1, spellHit = 0.9, spellCrit = 0.65, intellect = 0.6, haste = 0.5,
        manaRegen = 0.5, spirit = 0.35, allStats = 0.8, stamina = 0.4, mana = 0.3,
        healing = 0, spellPen = 0.25, armor = 0.15, health = 0.2, defense = 0.05,
        dodge = 0.05, parry = 0, block = 0, strength = 0, agility = 0.05,
        attackPower = 0, hit = 0, crit = 0.05, weaponDamage = 0, speed = 0.5,
        threatDown = 0.5, tankThreat = 0, stealth = 0, resistance = 0.25,
        situational = 0.05, profession = 0, resilience = 0.1,
    },
}

-- Nothing is known about the role at all. Everything scores the same so the
-- list at least stays in a sensible ladder order instead of collapsing to zero.
local UNKNOWN_WANT = 0.5

-- ---------------------------------------------------------------------------
-- reading the client
--
-- Everything here is guarded, because this client reports interface 20506 and
-- runs a much newer engine, so a function that exists on one of those two eras
-- may simply be missing. A missing function must degrade the answer, never
-- stop the file.
-- ---------------------------------------------------------------------------
local infoTip
local function EnsureTip()
    if infoTip ~= nil then return infoTip or nil end
    local ok = pcall(function()
        infoTip = CreateFrame("GameTooltip", "GearScoutEnchantTooltip", nil, "GameTooltipTemplate")
        infoTip:SetOwner(UIParent, "ANCHOR_NONE")
    end)
    if not ok or not infoTip then infoTip = false end
    return infoTip or nil
end

-- Whole tooltip as one string, or nil. Used for spells and for items alike,
-- so the setter is named rather than hard coded.
local function TipText(setterName, arg)
    local tip = EnsureTip()
    if not tip then return nil end
    local setter = tip[setterName]
    if type(setter) ~= "function" then return nil end
    tip:ClearLines()
    if not pcall(setter, tip, arg) then return nil end
    local out
    local okN, n = pcall(tip.NumLines, tip)
    if not okN or type(n) ~= "number" then return nil end
    for i = 1, n do
        local fs = _G["GearScoutEnchantTooltipTextLeft" .. i]
        local txt = fs and fs:GetText()
        if txt and txt ~= "" then
            out = out and (out .. "\n" .. txt) or txt
        end
    end
    return out
end

local function Tidy(text)
    if not text then return nil end
    text = text:gsub("\n", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    return text
end

local function TagFromText(text)
    if not text then return nil end
    local low = text:lower()
    for i = 1, #STAT_WORDS do
        if low:find(STAT_WORDS[i][1], 1, true) then return STAT_WORDS[i][2] end
    end
    return nil
end

-- "Requires Level 70". Built from the client's own format string where it has
-- one, so this keeps reading on a client that is not in English, and falls
-- back to the English wording rather than to nothing when it does not.
local function LevelPattern()
    local g = _G.ITEM_MIN_LEVEL
    if type(g) == "string" and g:find("%%d") then
        -- Escape everything the pattern engine would otherwise read as syntax,
        -- then turn the one placeholder into a capture.
        local p = g:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
        return (p:gsub("%%d", "(%%d+)"))
    end
    return "Requires Level (%d+)"
end
local LEVEL_PATTERN = LevelPattern()

-- The character's own level. Nil when nothing will say, which is a real answer:
-- with no level to compare against, no option is ever called out of reach.
local function PlayerLevel()
    local scan = ns.lastScan
    local lvl = (scan and scan.level) or ns.playerLevel
    if type(lvl) ~= "number" or lvl <= 0 then
        local ok, l = pcall(_G.UnitLevel, "player")
        if ok and type(l) == "number" then lvl = l end
    end
    if type(lvl) == "number" and lvl > 0 then return lvl end
    return nil
end

-- What the game itself says an enchant does, plus anything useful it happens
-- to print alongside. Every field is optional and absent means absent: nothing
-- here fills a gap with an assumption.
local spellInfoCache = {}
-- Which spells have already been asked to load. A spell the server has nothing
-- to say about would otherwise be requested again on every rebuild, and each
-- request answers with SPELL_DATA_LOAD_RESULT, which triggers the next rebuild:
-- a loop that never settles and rebuilds the list under the player's cursor
-- forever. Asking once ends it.
local spellRequested = {}
local function SpellEnchantInfo(spellID)
    if not spellID then return nil end
    local rec = spellInfoCache[spellID]
    if rec then return rec end

    local text
    if C_Spell and C_Spell.GetSpellDescription then
        local ok, d = pcall(C_Spell.GetSpellDescription, spellID)
        if ok and type(d) == "string" and d ~= "" then text = d end
    end
    if not text and _G.GetSpellDescription then
        local ok, d = pcall(_G.GetSpellDescription, spellID)
        if ok and type(d) == "string" and d ~= "" then text = d end
    end

    -- The tooltip is the fallback and also the only place a required skill
    -- line ever shows up, so it is read even when a description was found.
    local tipText = TipText("SetSpellByID", spellID)
    if not text and tipText then
        -- Line one is the spell's own name, which the row already prints.
        text = tipText:match("^[^\n]*\n(.+)$")
    end

    rec = {}
    rec.text = Tidy(text)
    -- "Permanently enchant bracers to increase Strength by 9." The first
    -- number after a "by" is the size of the effect. An enchant that grants
    -- two stats has two of them and only the first is read, which is why the
    -- amount is treated as a tie breaker rather than as the whole answer.
    if rec.text then
        rec.amount = tonumber(rec.text:match("by (%d+)"))
        rec.tag = TagFromText(rec.text)
        rec.itemLevel = tonumber(rec.text:match("level (%d+) or higher item"))
    end
    if tipText then
        rec.skill = tonumber(tipText:match("%((%d+)%)"))
        if rec.skill and not tipText:lower():find("enchanting", 1, true) then
            -- A number in brackets that is not next to the profession name is
            -- not a skill requirement, so it is thrown away rather than shown.
            rec.skill = nil
        end
        rec.itemLevel = rec.itemLevel or tonumber(tipText:match("level (%d+) or higher item"))
        -- A character level requirement, when the tooltip prints one. Most
        -- enchant spells do not, and then nothing is claimed.
        rec.level = tonumber(tipText:match(LEVEL_PATTERN))
    end

    -- Nothing came back at all. Ask the client to load the spell, once, and
    -- leave the cache empty so the next look gets a real answer once it
    -- arrives.
    if not rec.text then
        if not spellRequested[spellID] then
            spellRequested[spellID] = true
            if C_Spell and C_Spell.RequestLoadSpellData then
                pcall(C_Spell.RequestLoadSpellData, spellID)
            end
        end
        return nil
    end

    spellInfoCache[spellID] = rec
    return rec
end

-- Same idea for an item, used by the reputation enchants, the leg armors and
-- the scopes, which are all real items rather than spells. One pass over the
-- tooltip answers both questions it can answer, what the thing gives and what
-- the game demands before it can be used, rather than building the same
-- tooltip twice for two readers.
local itemFactsCache = {}
local function ItemFacts(itemID)
    if not itemID then return nil end
    local cached = itemFactsCache[itemID]
    if cached then return cached end

    local facts = {}
    local text = TipText("SetItemByID", itemID)
    if text then
        for line in text:gmatch("[^\n]+") do
            local low = line:lower()
            local lvl = tonumber(line:match(LEVEL_PATTERN))
            if lvl then
                facts.level = facts.level or lvl
            elseif not facts.detail and not low:find("^requires") and not low:find("^binds")
                   and TagFromText(line) then
                -- The line that describes the bonus is the one that mentions a
                -- stat. The item's name, its binding and its requirements are
                -- not it.
                facts.detail = Tidy(line)
            end
        end
    end

    -- The client's own item record is the surer answer for a required level,
    -- and it is not written in any one language, so it wins over the tooltip
    -- line whenever it has something to say. Zero and one both mean "no
    -- requirement" here, which is why neither is stored.
    local okInfo, _, _, _, _, minLevel = pcall(GetItemInfo, itemID)
    if okInfo and type(minLevel) == "number" and minLevel > 1 then
        facts.level = minLevel
    end

    -- The client has not cached this item yet. Remembering that would freeze a
    -- blank answer in place, so the miss is not stored and the next look, after
    -- ITEM_CACHE_UPDATED, gets the real one.
    if not text and not facts.level then return nil end

    itemFactsCache[itemID] = facts
    return facts
end

-- ---------------------------------------------------------------------------
-- faction standing
--
-- The shipped reputation data names the faction a reward is sold by and the
-- standing it is sold at, and carries the client's own faction id alongside.
-- That id is what turns "you are not there yet" into a fact: the client is
-- asked what this character actually stands at, and when it will not say,
-- nothing at all is claimed about the character and the row states only what
-- the reward costs.
-- ---------------------------------------------------------------------------

-- The client numbers standings from Hated at 1, so its Neutral is 4, while the
-- shipped data's own ladder starts at Neutral. Three is the gap between them.
local STANDING_BASE = 3

local factionIDs
local function FactionID(name)
    if not factionIDs then
        factionIDs = {}
        local rep = ns.REP_REWARDS
        if type(rep) == "table" then
            for factionName, faction in pairs(rep) do
                local id = type(faction) == "table" and faction.factionId
                if type(id) == "number" then factionIDs[factionName] = id end
            end
        end
    end
    return name and factionIDs[name] or nil
end

-- The client's standing number for a faction, or nil when it will not say. A
-- faction this character has never met usually answers nothing at all, and nil
-- is the honest way to carry that rather than a zero that would read as
-- "hated".
local function ReadStanding(factionName)
    local id = FactionID(factionName)
    if not id then return nil end

    if C_Reputation and C_Reputation.GetFactionDataByID then
        local ok, data = pcall(C_Reputation.GetFactionDataByID, id)
        if ok and type(data) == "table" and type(data.reaction) == "number" and data.reaction > 0 then
            return data.reaction
        end
    end
    if _G.GetFactionInfoByID then
        local ok, _, _, standingID = pcall(_G.GetFactionInfoByID, id)
        if ok and type(standingID) == "number" and standingID > 0 then
            return standingID
        end
    end
    return nil
end

-- Same answer plus the standing's name in the client's own words, remembered so
-- a slot full of rewards from one faction asks about it once.
local standingCache = {}
local function Standing(factionName)
    if not factionName then return nil end
    local cached = standingCache[factionName]
    if cached ~= nil then
        if cached == false then return nil end
        return cached.id, cached.name
    end

    local reaction = ReadStanding(factionName)
    if not reaction then
        standingCache[factionName] = false
        return nil
    end

    local label = _G["FACTION_STANDING_LABEL" .. reaction]
    local rec = { id = reaction, name = type(label) == "string" and label or nil }
    standingCache[factionName] = rec
    return rec.id, rec.name
end

-- ---------------------------------------------------------------------------
-- what this character wants
-- ---------------------------------------------------------------------------

-- Researched weight for a tag, or nil when this spec has no researched data.
-- A weight of exactly zero is a real answer in StatWeights.lua and means "this
-- is a cap, judged elsewhere, not a stat to optimise", so it is returned as
-- zero and the role preference is allowed to speak over it below rather than
-- letting a hit enchant sink to the bottom of a list on a technicality.
local function ResearchedWeight(tag)
    local info = ns.GetSpecInfo and ns.GetSpecInfo()
    local classFile = (info and info.class) or ns.playerClass
    local sw = ns.STAT_WEIGHTS
    if not classFile or not sw then return nil end
    local classData = sw[classFile]
    if not classData then return nil end
    local spec = classData[(info and info.tab) or 1]
    local weights = spec and spec.weights
    if not weights then return nil end
    local keys = WEIGHT_KEYS[tag]
    if not keys then return nil end
    local best
    for i = 1, #keys do
        local w = weights[keys[i]]
        if type(w) == "number" and (not best or w > best) then best = w end
    end
    return best
end

local function RoleWeight(tag)
    local role = ns.GetSpecRole and select(1, ns.GetSpecRole())
    local t = role and ROLE_WANTS[role]
    if not t then return UNKNOWN_WANT end
    return t[tag] or 0
end

-- How much this character wants a tag, 0 to 1. Best of the researched answer
-- and the role answer, the same rule Buffs.lua settled on, so a cap stat left
-- at zero on purpose still ranks like the role expects.
local function TagWant(tag)
    if not tag then return 0 end
    local a = ResearchedWeight(tag)
    local b = RoleWeight(tag)
    if a and a > b then return a end
    return b
end

-- True when the ranking on screen is backed by researched weights rather than
-- by the role table, so the page can say which one it used.
local function HaveResearchedWeights()
    local info = ns.GetSpecInfo and ns.GetSpecInfo()
    local classFile = (info and info.class) or ns.playerClass
    local sw = ns.STAT_WEIGHTS
    if not classFile or not sw or not sw[classFile] then return false end
    local spec = sw[classFile][(info and info.tab) or 1]
    return (spec and spec.weights) ~= nil
end

-- ---------------------------------------------------------------------------
-- enchanting skill
--
-- Three places this number can live on this client, and none of them is
-- guaranteed. Each is tried in turn and the first that answers wins, with the
-- source carried alongside so the page can say where the number came from
-- instead of presenting a remembered number as a live one.
-- ---------------------------------------------------------------------------
local skill = { rank = nil, maxRank = nil, source = nil }
local skillDirty = true

local function EnchantingName()
    return ns.SpellName(ENCHANTING_SPELL)
end

local function ProfessionRank(idx, encName)
    if type(idx) ~= "number" then return nil end
    local ok, name, _, rank, maxRank = pcall(_G.GetProfessionInfo, idx)
    if ok and name == encName and type(rank) == "number" and rank > 0 then
        return rank, (type(maxRank) == "number" and maxRank or nil)
    end
    return nil
end

-- Written out rather than looped over a temporary table, because GetProfessions
-- returns nils in the middle of its return list and ipairs would stop at the
-- first of them.
local function SkillFromProfessions(encName)
    if not encName or not _G.GetProfessions or not _G.GetProfessionInfo then return nil end
    local ok, p1, p2 = pcall(_G.GetProfessions)
    if not ok then return nil end
    local r, m = ProfessionRank(p1, encName)
    if r then return r, m end
    return ProfessionRank(p2, encName)
end

local function SkillFromSkillLines(encName)
    if not encName or not _G.GetNumSkillLines or not _G.GetSkillLineInfo then return nil end
    local okN, num = pcall(_G.GetNumSkillLines)
    if not okN or type(num) ~= "number" then return nil end
    for i = 1, num do
        -- name, isHeader, isExpanded, rank, tempPoints, modifier, maxRank, ...
        local ok, a, b, _, d, _, _, g = pcall(_G.GetSkillLineInfo, i)
        if ok and a == encName and not b and type(d) == "number" and d > 0 then
            return d, (type(g) == "number" and g or nil)
        end
    end
    return nil
end

-- Set by the trade skill scan while the enchanting window is open, which is
-- the most trustworthy source of the three because the window is the thing
-- being read rather than a list that may be collapsed.
local liveRank, liveMax

local function ComputeSkill()
    local encName = EnchantingName()

    if liveRank then
        skill.rank, skill.maxRank, skill.source = liveRank, liveMax, "your enchanting window"
        return
    end

    local r, m = SkillFromProfessions(encName)
    if r then
        skill.rank, skill.maxRank, skill.source = r, m, "your profession list"
        return
    end

    r, m = SkillFromSkillLines(encName)
    if r then
        skill.rank, skill.maxRank, skill.source = r, m, "your skill list"
        return
    end

    local saved = ns.cdb and ns.cdb.enchanting
    if saved and type(saved.rank) == "number" and saved.rank > 0 then
        skill.rank, skill.maxRank, skill.source = saved.rank, saved.maxRank,
            "remembered from the last time GearScout saw it"
        return
    end

    skill.rank, skill.maxRank, skill.source = nil, nil, nil
end

-- rank, maxRank, source. All three are nil when the client will not say, which
-- is a real answer and never a zero.
function ns.GetEnchantingSkill()
    if skillDirty then
        ComputeSkill()
        skillDirty = false
    end
    return skill.rank, skill.maxRank, skill.source
end

local function InvalidateSkill()
    skillDirty = true
end

-- ---------------------------------------------------------------------------
-- recipes and their materials
--
-- The client only hands an addon the reagents of a recipe the player has
-- already learned, and only while the trade skill window is open. So this
-- reads the window whenever it is open, keeps what it learned in the character
-- saved variables, and says plainly when it has never had the chance.
--
-- The list in that window can be filtered by a search box or by a "have
-- materials" tick, which would make a scan see a subset of what is really
-- known. Entries are therefore merged and never deleted: a recipe once seen
-- stays known, because a filtered view is not evidence that it was forgotten.
-- ---------------------------------------------------------------------------
local recipes = {}          -- [lowercased recipe name] = { mats = "...", spellID = n }
local recipesSeen = false   -- has the window ever been read successfully
local recipeCount = 0

local function StoreRecipes()
    if not ns.cdb then return end
    local e = ns.cdb.enchanting
    if type(e) ~= "table" then e = {}; ns.cdb.enchanting = e end
    e.recipes = recipes
    e.count   = recipeCount
    e.rank    = liveRank or e.rank
    e.maxRank = liveMax or e.maxRank
    e.seen    = recipesSeen
end

local function LoadRecipes()
    local e = ns.cdb and ns.cdb.enchanting
    if type(e) ~= "table" then return end
    if type(e.recipes) == "table" then
        recipes = e.recipes
        recipeCount = 0
        for _ in pairs(recipes) do recipeCount = recipeCount + 1 end
        recipesSeen = e.seen == true and recipeCount > 0
    end
end

local function JoinMats(list)
    if not list or #list == 0 then return nil end
    return table.concat(list, ", ")
end

local function ReagentsModern(recipeID)
    local api = C_TradeSkillUI
    if not api or not api.GetRecipeNumReagents or not api.GetRecipeReagentInfo then return nil end
    local okN, n = pcall(api.GetRecipeNumReagents, recipeID)
    if not okN or type(n) ~= "number" or n <= 0 then return nil end
    local out = {}
    for j = 1, n do
        local ok, name, _, count = pcall(api.GetRecipeReagentInfo, recipeID, j)
        if ok and type(name) == "string" and name ~= "" then
            out[#out + 1] = format("%d %s", tonumber(count) or 1, name)
        end
    end
    return JoinMats(out)
end

local function ReagentsClassic(index)
    if not _G.GetTradeSkillNumReagents or not _G.GetTradeSkillReagentInfo then return nil end
    local okN, n = pcall(_G.GetTradeSkillNumReagents, index)
    if not okN or type(n) ~= "number" or n <= 0 then return nil end
    local out = {}
    for j = 1, n do
        local ok, name, _, count = pcall(_G.GetTradeSkillReagentInfo, index, j)
        if ok and type(name) == "string" and name ~= "" then
            out[#out + 1] = format("%d %s", tonumber(count) or 1, name)
        end
    end
    return JoinMats(out)
end

-- Which profession the open window belongs to, and the rank it reports.
local function OpenTradeSkillLine()
    local api = C_TradeSkillUI
    if api and api.GetTradeSkillLine then
        local ok, a, b, c, d = pcall(api.GetTradeSkillLine)
        if ok then
            -- Two shapes exist. Older builds return the name first, the
            -- current engine returns a numeric skill line id first.
            if type(a) == "string" then return a, b, c end
            if type(a) == "number" and type(b) == "string" then return b, c, d end
        end
    end
    if _G.GetTradeSkillLine then
        local ok, a, b, c = pcall(_G.GetTradeSkillLine)
        if ok and type(a) == "string" then return a, b, c end
    end
    return nil
end

local function ScanTradeSkill()
    local lineName, rank, maxRank = OpenTradeSkillLine()
    if not lineName then return false end

    local encName = EnchantingName()
    if encName then
        if lineName ~= encName then return false end
    elseif lineName ~= "Enchanting" then
        -- No localized name to compare against, so only the English one is
        -- accepted rather than reading somebody's tailoring window as if it
        -- were enchanting.
        return false
    end

    if type(rank) == "number" and rank > 0 then
        liveRank = rank
        liveMax  = (type(maxRank) == "number" and maxRank > 0) and maxRank or nil
        InvalidateSkill()
    end

    local added = 0
    local api = C_TradeSkillUI
    if api and api.GetAllRecipeIDs and api.GetRecipeInfo then
        local ok, ids = pcall(api.GetAllRecipeIDs)
        if ok and type(ids) == "table" then
            for _, rid in ipairs(ids) do
                local ok2, info = pcall(api.GetRecipeInfo, rid)
                if ok2 and type(info) == "table" and type(info.name) == "string"
                   and info.name ~= "" and info.learned ~= false then
                    local key = info.name:lower()
                    if not recipes[key] then added = added + 1 end
                    recipes[key] = {
                        mats    = ReagentsModern(rid) or (recipes[key] and recipes[key].mats),
                        spellID = rid,
                    }
                end
            end
        end
    end

    if added == 0 and _G.GetNumTradeSkills and _G.GetTradeSkillInfo then
        local okN, num = pcall(_G.GetNumTradeSkills)
        if okN and type(num) == "number" then
            for i = 1, num do
                local ok, name, skillType = pcall(_G.GetTradeSkillInfo, i)
                if ok and type(name) == "string" and name ~= ""
                   and skillType ~= "header" and skillType ~= "subheader" then
                    local key = name:lower()
                    if not recipes[key] then added = added + 1 end
                    recipes[key] = {
                        mats       = ReagentsClassic(i) or (recipes[key] and recipes[key].mats),
                        difficulty = skillType,
                    }
                end
            end
        end
    end

    recipeCount = 0
    for _ in pairs(recipes) do recipeCount = recipeCount + 1 end
    if recipeCount > 0 then recipesSeen = true end

    StoreRecipes()
    return recipeCount > 0
end

-- ---------------------------------------------------------------------------
-- do you know this one
-- ---------------------------------------------------------------------------

-- True when a "no, you do not know that" answer can be trusted. The spellbook
-- is trustworthy only if it can be read at all, and Disenchant is the control
-- for that: every enchanter has it, so a spellbook that denies Disenchant is a
-- spellbook this addon cannot read.
local function KnowledgeIsReadable()
    if recipesSeen then return true, "your enchanting window" end
    if ns.SpellKnown(DISENCHANT_SPELL) then return true, "your spellbook" end
    return false
end

-- true plus where it was read from, or false. The name is matched as well as
-- the id, because the enchanting window answers by name and the catalogue's
-- ids are only usable once the client confirms they name the same spell.
function ns.KnowsEnchant(spellID, name)
    if name then
        local rec = recipes[name:lower()]
        if rec then return true, "your enchanting window" end
    end
    if spellID and ns.SpellKnown(spellID) then return true, "your spellbook" end
    return false
end

-- ---------------------------------------------------------------------------
-- building one option
-- ---------------------------------------------------------------------------

-- The catalogue calls its ids item ids in its own header, but an enchant has
-- no crafted item, so what the source really carries for these rows is the
-- recipe's spell id. That is checked rather than assumed: the id is only used
-- for anything if the client agrees it names this exact spell.
local spellIdCache = {}
local function ResolveSpell(id, catName)
    local cached = spellIdCache[id]
    if cached ~= nil then
        if cached == false then return nil, nil end
        return cached.id, cached.icon
    end
    local name, icon = ns.SpellName(id)
    if name and catName and name == catName then
        spellIdCache[id] = { id = id, icon = icon }
        return id, icon
    end
    spellIdCache[id] = false
    return nil, icon
end

local FALLBACK_ICON = "Interface\\Icons\\Trade_Engraving"

local function ParseEnchantName(name)
    local effect = name:match("%-%s*(.+)$") or name
    effect = effect:gsub("^%s+", ""):gsub("%s+$", "")
    local firstWord = effect:match("^(%a+)")
    local tier = firstWord and TIER[firstWord:lower()] or nil
    return effect, tier or TIER_PLAIN
end

-- ---------------------------------------------------------------------------
-- gates
--
-- Each of these takes a requirement that was READ from somewhere and, only if
-- the character does not meet it, records how far out of reach that puts the
-- option and one plain sentence saying why. Nothing here ever infers a
-- requirement from a name, an id or an era: no readable requirement means no
-- gate, and the option stays in the usable group where it has always been.
-- ---------------------------------------------------------------------------
local function AddGate(opt, level, text)
    if (opt.gate or GATE_NONE) < level then opt.gate = level end
    opt.gateText = opt.gateText and (opt.gateText .. " " .. text) or text
end

local function LevelGate(opt, reqLevel, level)
    if type(reqLevel) ~= "number" or reqLevel <= 1 then return end
    opt.reqLevel = reqLevel
    if not level or reqLevel <= level then return end
    local gap = reqLevel - level
    AddGate(opt, gap <= LEVEL_SOON and GATE_SOON or GATE_FAR,
        gap == 1
            and format(L["Needs level %d and you are %d, so it is 1 level away."], reqLevel, level)
            or format(L["Needs level %d and you are %d, so it is %d levels away."], reqLevel, level, gap))
end

-- Reputation is a gate even when the standing is only a few thousand points
-- off, and it is always the far group rather than the near one. That is the
-- same call Upgrades.lua makes about reputation rewards, for the reason stated
-- there: a character is not going to farm a faction in passing, so it belongs
-- beside the other multi week jobs and not beside tonight's.
local function RepGate(opt, faction, standing, rank)
    if not faction or not standing then return end
    opt.repFaction, opt.repStanding = faction, standing

    local have, haveName = Standing(faction)
    if have and have >= (rank or 9) + STANDING_BASE then
        opt.repMet = true
        opt.repMetText = haveName
            and format(L["You are already %s with %s."], haveName, faction)
            or format(L["You already have the standing with %s."], faction)
        return
    end

    opt.repGate = true
    if haveName then
        AddGate(opt, GATE_FAR, format(L["Costs %s standing with %s and you are %s with them."],
            standing, faction, haveName))
    else
        AddGate(opt, GATE_FAR, format(L["Costs %s standing with %s, which has to be earned before any of it is for sale."],
            standing, faction))
    end
end

-- The item in the slot is too weak to carry this enchant. Which group that
-- puts it in is a judgement, and this is the one place the file makes it:
-- through the sixties an item's level tracks the character wearing it closely
-- enough that a "level 60 or higher item" requirement is really a level 60
-- character requirement, so the same LEVEL_SOON distance decides near from far.
-- The sentence the player reads claims none of that. It states only the two
-- numbers the client gave: what the enchant needs and what the item is.
local function ItemLevelGate(opt, reqIlvl, wornIlvl, level)
    if not reqIlvl or not wornIlvl or wornIlvl <= 0 or wornIlvl >= reqIlvl then return end
    opt.itemGate = true
    local far = level and (reqIlvl - level) > LEVEL_SOON
    AddGate(opt, far and GATE_FAR or GATE_SOON,
        format(L["Only goes on an item of level %d or higher, and the one you are wearing is level %d."],
            reqIlvl, wornIlvl))
end

-- One enchanting option, fully judged. Every text field is written here rather
-- than in a row update, because rows are pooled and must only ever set text.
local function BuildEnchantOption(id, catName, isEnchanter, wornIlvl, level)
    local spellID, icon = ResolveSpell(id, catName)
    local name = catName or (spellID and ns.SpellName(spellID)) or "Unknown enchant"
    local effect, tier = ParseEnchantName(name)

    local info = spellID and SpellEnchantInfo(spellID) or nil
    -- The client's own words win over our reading of the name, always.
    local tag = (info and info.tag) or TagFromText(effect)
    local want = TagWant(tag)

    local opt = {
        kind      = KIND_ENCHANT,
        spellID   = spellID,
        name      = name,
        icon      = icon or FALLBACK_ICON,
        tag       = tag,
        tier      = tier,
        amount    = info and info.amount or nil,
        reqSkill  = info and info.skill or nil,
        reqIlvl   = info and info.itemLevel or nil,
        want      = want,
    }

    -- What it gives. The game's sentence first, our reading of the name only
    -- when the game will not say, and an honest blank when neither can.
    if info and info.text then
        opt.detail = info.text
    elseif tag then
        -- TAG_WORDS names a stat, so it is translated only where it is not one:
        -- "a gathering profession, not a combat stat" is GearScout's own prose.
        opt.detail = format(L["The name says this one gives %s. GearScout could not get the exact numbers from the client."], L[TAG_WORDS[tag]] or tag)
    else
        opt.detail = L["GearScout cannot tell what this one gives. The name does not say and the client would not describe it."]
    end

    -- Value used for the ranking. The amount only ever refines an order the
    -- stat has already decided, so an option with no readable amount is never
    -- pushed below one that simply happens to print a number.
    opt.value = want * (opt.amount and (1 + min(opt.amount, 200) / 400) or 1)
    opt.ranked = tag ~= nil

    -- The three cases.
    local known, whereFrom = ns.KnowsEnchant(spellID, name)
    opt.known = known

    if not isEnchanter then
        opt.case = CASE_OTHER
        opt.action = L["You are not an enchanter, so somebody else applies this one. Buy the materials, hand them over with the item, and tip for the work."]
    elseif known then
        opt.case = CASE_SELF
        opt.action = format(L["You can do this one yourself right now. Read from %s."], L[whereFrom] or L["your own recipes"])
    else
        opt.case = CASE_LEARN
        local readable, readFrom = KnowledgeIsReadable()
        if readable then
            opt.action = format(L["You do not know this recipe yet, according to %s. Enchanting recipes come from your trainer or from a formula that drops, is sold, or is a reputation reward."], L[readFrom])
        else
            opt.action = L["GearScout could not read which recipes you know. Open your enchanting window once and it will read them, along with what each one costs in materials."]
        end
    end

    -- Materials. Only ever the real list from the player's own window, and it
    -- is the client's own reagent names, so only the label around it moves.
    local rec = recipes[name:lower()]
    if rec and rec.mats then
        opt.mats = format(L["Materials: %s"], rec.mats)
    elseif known then
        opt.mats = L["Open your enchanting window once so GearScout can read what this one costs in materials."]
    elseif isEnchanter then
        opt.mats = L["GearScout only gets a material list for recipes you already know, because that is all the client will hand an addon."]
    else
        opt.mats = L["Ask the enchanter which materials they need. The client only tells GearScout the materials for recipes you know yourself."]
    end

    -- Anything the client happened to print that is worth acting on.
    if opt.reqSkill then
        local rank = ns.GetEnchantingSkill()
        if rank and rank >= opt.reqSkill then
            opt.note = format(L["Needs %d enchanting skill. You have %d."], opt.reqSkill, rank)
        elseif rank then
            opt.note = format(L["Needs %d enchanting skill and you have %d, so you are %d short."],
                opt.reqSkill, rank, opt.reqSkill - rank)
            opt.trainToward = (opt.reqSkill - rank) <= 25
        else
            opt.note = format(L["Needs %d enchanting skill."], opt.reqSkill)
        end
    end
    -- What actually stands in the way. A spell tooltip rarely prints a
    -- character level for an enchant, but when it does it is read like any
    -- other requirement rather than assumed absent.
    LevelGate(opt, info and info.level, level)
    ItemLevelGate(opt, opt.reqIlvl, wornIlvl, level)

    return opt
end

-- Reputation enchants, leg armor and scopes are all real items rather than
-- recipes, so they share one builder and differ only in who applies them.
local function BuildItemOption(itemID, name, kind, extra, level)
    local meta = ns.GetItemMeta and ns.GetItemMeta(itemID) or nil
    local shown = (meta and meta.name) or name or L["Unknown item"]
    local facts = ItemFacts(itemID)
    local detail = facts and facts.detail or nil
    local tag = TagFromText(detail or shown)

    local opt = {
        kind    = kind,
        itemID  = itemID,
        link    = meta and meta.link or nil,
        name    = shown,
        icon    = (meta and meta.icon) or FALLBACK_ICON,
        tag     = tag,
        tier    = TIER_PLAIN,
        want    = TagWant(tag),
        case    = CASE_OTHER,
        ranked  = tag ~= nil,
        pending = meta == nil,
    }
    opt.value = opt.want

    if detail then
        opt.detail = detail
    elseif meta then
        opt.detail = L["GearScout could not read what this one gives. Hover it to see the game's own tooltip."]
    else
        opt.detail = L["Still loading from the server. Reopen this tab in a moment."]
    end

    -- The level on the item itself, which is the requirement the head and
    -- shoulder glyphs of this era carry and the one that made a level 70
    -- reward read like a suggestion for a level 27. Read before the branch
    -- below so the sentence a player meets first is the biggest wall.
    LevelGate(opt, facts and facts.level, level)

    if kind == KIND_REP then
        local who = (extra and extra.faction) or L["the faction"]
        -- Several faction names carry their own article, and a blind prefix
        -- turns those into "the The Sha'tar quartermaster". The article is
        -- English grammar, so it is part of the translated sentence and any
        -- language that has no equivalent simply leaves it out.
        local article = who:find("^The ") and "" or L["the "]
        opt.action = format(L["Bought once from %s%s quartermaster at %s standing. You apply it yourself, no enchanter involved."],
            article, who, (extra and extra.standing or L["the required"]):lower())
        opt.mats = L["Costs reputation and a little gold, and it never wears off."]
        opt.standing = extra and extra.standing
        opt.rank = extra and extra.rank or 9
        RepGate(opt, extra and extra.faction, extra and extra.standing, opt.rank)
        -- Standing already earned is worth saying first, because it turns the
        -- whole row from a plan into an errand.
        if opt.repMetText then
            opt.action = opt.repMetText .. " " .. opt.action
        end
    elseif kind == KIND_LEG then
        -- The profession name comes from the data, so it goes in as it is.
        opt.action = format(L["A %s makes this. It is an item, so you can buy one off the auction house and apply it yourself."],
            (extra and extra.profession or L["crafter"]):lower())
        opt.mats = L["Buy the finished item, or bring the materials to a crafter. This one is not an enchanting job."]
    elseif kind == KIND_SCOPE then
        opt.action = L["An engineer makes this. It is an item, so you can buy one and attach it yourself."]
        opt.mats = L["Buy the finished scope, or ask an engineer. This one is not an enchanting job."]
    end

    return opt
end

-- ---------------------------------------------------------------------------
-- the plan for one slot
-- ---------------------------------------------------------------------------
local MAX_RANKED   = 6
local MAX_UNRANKED = 6
-- How many out of reach options are worth printing in full. Enough to see what
-- the slot eventually offers and what it costs, not enough to bury the one
-- thing that can be done today. Whatever is cut is counted in the heading, so
-- nothing disappears silently.
local MAX_SOON     = 4
local MAX_FAR      = 3

local function ByValue(a, b)
    local ga, gb = a.gate or GATE_NONE, b.gate or GATE_NONE
    if ga ~= gb then return ga < gb end
    if a.value ~= b.value then return a.value > b.value end
    if a.tier ~= b.tier then return a.tier > b.tier end
    return (a.spellID or a.itemID or 0) > (b.spellID or b.itemID or 0)
end

-- Reputation options sort by how cheap the standing is to reach, since the
-- easiest one is the one worth telling somebody about first. Same rule
-- Sources.lua already applies to the same data.
local function ByStanding(a, b)
    local ga, gb = a.gate or GATE_NONE, b.gate or GATE_NONE
    if ga ~= gb then return ga < gb end
    local ra, rb = a.rank or 9, b.rank or 9
    if ra ~= rb then return ra < rb end
    return (a.name or "") < (b.name or "")
end

-- One sentence describing what a whole group is waiting on, built from what
-- was read about the rows in it rather than from what era they belong to. Used
-- as the note under a group heading, so the player never has to open three
-- rows to find out what the heading means.
local function GateSummary(rows, level)
    local n = #rows
    if n == 0 then return nil end

    local minLevel, levelRows, repRows, itemRows = nil, 0, 0, 0
    for i = 1, n do
        local o = rows[i]
        if o.reqLevel then
            levelRows = levelRows + 1
            if not minLevel or o.reqLevel < minLevel then minLevel = o.reqLevel end
        end
        if o.repGate then repRows = repRows + 1 end
        if o.itemGate then itemRows = itemRows + 1 end
    end

    local parts = {}
    if minLevel then
        local who = (levelRows == n) and L["Every one of these needs"] or format(L["%d of these need"], levelRows)
        parts[#parts + 1] = level
            and format(L["%s level %d or higher, and you are %d."], who, minLevel, level)
            or format(L["%s level %d or higher."], who, minLevel)
    end
    if repRows > 0 then
        parts[#parts + 1] = (repRows == n)
            and L["They are bought with faction standing, which is a grind worth planning before you start rather than something you pick up on the way past."]
            or format(L["%d of them are bought with faction standing."], repRows)
    end
    if itemRows > 0 then
        -- "also" only earns its place when there is a sentence before it.
        local also = (#parts > 0) and L["also "] or ""
        parts[#parts + 1] = (itemRows == n)
            and format(L["They %swant a better item in this slot than the one you are wearing."], also)
            or format(L["%d of them %swant a better item in this slot than the one you are wearing."], itemRows, also)
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " ")
end

-- Which catalogue category serves a weapon slot depends on what is in it.
local function WeaponCategory(rec, slotID)
    if slotID == 16 then
        if rec and rec.equipLoc == "INVTYPE_2HWEAPON" then return "2H Weapon" end
        return "Weapon"
    end
    if rec and rec.equipLoc == "INVTYPE_SHIELD" then return "Shield" end
    return "Weapon"
end

local planCache = {}

function ns.GetEnchantPlan(slotID)
    if not slotID then return nil end
    local cached = planCache[slotID]
    if cached then return cached end

    local def = ns.SLOT_BY_ID and ns.SLOT_BY_ID[slotID]
    if not def then return nil end

    local scan = ns.lastScan
    local rec = scan and scan.bySlotID and scan.bySlotID[slotID]
    local isEnchanter = ns.IsEnchanter and ns.IsEnchanter() or false
    local level = PlayerLevel()

    local plan = {
        slotID      = slotID,
        label       = def.label,
        worn        = rec,
        enchantable = rec and rec.enchantable or false,
        enchanted   = rec and rec.enchanted or false,
        priority    = SLOT_PRIORITY[slotID] or 99,
        level       = level,
        options     = {},
        unranked    = {},
        soon        = {},
        far         = {},
    }

    if not rec or rec.empty then
        plan.note = L["Nothing is equipped here, so there is nothing to enchant yet."]
        planCache[slotID] = plan
        return plan
    end
    if not plan.enchantable then
        if def.ench == "enchanter" then
            plan.note = L["Only an enchanter can enchant a ring, and this character is not one. It is the one enchant nobody can do for you."]
        elseif def.ench == "ranged" then
            plan.note = L["A scope only fits a bow, a gun or a crossbow. What is in this slot cannot take one."]
        else
            plan.note = L["This slot does not take a permanent enchant in this version of the game."]
        end
        planCache[slotID] = plan
        return plan
    end

    local wornIlvl = rec.ilvl or 0
    local ranked, unranked = {}, {}

    local function Push(opt)
        if not opt then return end
        if opt.ranked then ranked[#ranked + 1] = opt else unranked[#unranked + 1] = opt end
    end

    if slotID == 1 or slotID == 3 then
        -- Head and shoulder are bought with reputation in this era. There is
        -- no craftable recipe for either, which is why Data/Catalogue.lua has
        -- no Shoulder key at all, so the source is a faction and the wearer
        -- buys it themselves.
        plan.kind = KIND_REP
        plan.sourceLine = ns.DescribeEnchantSource and ns.DescribeEnchantSource(slotID) or nil
        local list = ns.GetEnchantSources and ns.GetEnchantSources(slotID) or {}
        for i = 1, #list do
            local e = list[i]
            Push(BuildItemOption(e.itemID, e.name, KIND_REP, e, level))
        end
        sort(ranked, ByStanding)
        sort(unranked, ByStanding)

    elseif slotID == 7 then
        -- Legs take leg armor or spellthread, which is leatherworking and
        -- tailoring, not enchanting.
        plan.kind = KIND_LEG
        local list = ns.LEG_ARMOR or {}
        for i = 1, #list do
            local e = list[i]
            Push(BuildItemOption(e.id, e.name, KIND_LEG, e, level))
        end
        sort(ranked, ByValue)

    elseif slotID == 18 then
        plan.kind = KIND_SCOPE
        local list = ns.WEAPON_SCOPES or {}
        for i = 1, #list do
            local e = list[i]
            Push(BuildItemOption(e.id, e.name, KIND_SCOPE, e, level))
        end
        sort(ranked, ByValue)

    else
        plan.kind = KIND_ENCHANT
        local key = CATALOGUE_KEY[slotID] or WeaponCategory(rec, slotID)
        local list = (ns.ENCHANT_ITEMS and ns.ENCHANT_ITEMS[key]) or {}
        plan.category = key
        for i = 1, #list do
            local e = list[i]
            Push(BuildEnchantOption(e.id, e.name, isEnchanter, wornIlvl, level))
        end
        sort(ranked, ByValue)
        sort(unranked, ByValue)

        -- A two hander can also take any of the one hand weapon enchants in
        -- this era, so the shorter list is not the whole answer. Saying which
        -- category was read stops that looking like missing data.
        if key == "2H Weapon" then
            plan.categoryNote = L["You are holding a two hander, so these are the two hand weapon enchants."]
        end
    end

    -- Split by what stands in the way BEFORE anything is capped. Cutting the
    -- list to six first and then splitting would let thirty glyphs that need
    -- level 70 push the one enchant a level 27 can actually buy off the end of
    -- the page, which is the bug this whole section exists to stop.
    local usable, usableUnranked, soon, far = {}, {}, {}, {}
    local function Bucket(o, plain)
        local g = o.gate or GATE_NONE
        if g == GATE_NONE then
            if plain then usableUnranked[#usableUnranked + 1] = o
            else usable[#usable + 1] = o end
        elseif g == GATE_SOON then
            soon[#soon + 1] = o
        else
            far[#far + 1] = o
        end
    end
    for i = 1, #ranked do Bucket(ranked[i], false) end
    -- An option whose name never said what it does is still worth listing when
    -- it is usable, and is not worth a second unrankable group once it is out
    -- of reach as well, so out of reach ones join the group that describes what
    -- is actually keeping them off the character.
    for i = 1, #unranked do Bucket(unranked[i], true) end

    local GateOrder = (plan.kind == KIND_REP) and ByStanding or ByValue
    sort(soon, GateOrder)
    sort(far, GateOrder)

    -- The best one for this character, and separately the best one they can
    -- actually put on today. Those are often not the same enchant, and the
    -- difference between them is the whole point of the page.
    --
    -- Only ever chosen from the usable group. Calling an enchant forty three
    -- levels away "best for you" is exactly the advice this page was giving
    -- before, and it is not advice, it is a distraction.
    --
    -- Not done for a reputation slot. That list is ordered by which standing is
    -- cheapest to reach rather than by which enchant is strongest, so calling
    -- the top of it "best for you" would be a claim the ordering never made.
    if plan.kind ~= KIND_REP then
        for i = 1, #usable do
            local o = usable[i]
            if not plan.best then plan.best = o end
            if not plan.bestNow and o.case == CASE_SELF then plan.bestNow = o end
        end

        if plan.best then plan.best.isBest = true end
        if plan.bestNow and plan.bestNow ~= plan.best then plan.bestNow.isBestNow = true end
    end

    for i = 1, min(#usable, MAX_RANKED) do plan.options[#plan.options + 1] = usable[i] end
    -- The best one you can do now always earns its place on screen even when
    -- the ranking would have pushed it off the end of the list.
    if plan.bestNow and plan.bestNow ~= plan.best then
        local shown = false
        for i = 1, #plan.options do
            if plan.options[i] == plan.bestNow then shown = true; break end
        end
        if not shown then plan.options[#plan.options + 1] = plan.bestNow end
    end

    for i = 1, min(#usableUnranked, MAX_UNRANKED) do plan.unranked[#plan.unranked + 1] = usableUnranked[i] end
    plan.unrankedTotal = #usableUnranked

    for i = 1, min(#soon, MAX_SOON) do plan.soon[#plan.soon + 1] = soon[i] end
    for i = 1, min(#far, MAX_FAR) do plan.far[#plan.far + 1] = far[i] end
    plan.soonTotal  = #soon
    plan.farTotal   = #far
    plan.soonNote   = GateSummary(soon, level)
    plan.farNote    = GateSummary(far, level)
    plan.usableTotal = #usable + #usableUnranked
    plan.gatedTotal  = #soon + #far

    -- Nothing at all for this character yet. Said once, at the top of the
    -- panel, rather than left for the player to work out from three headings.
    if plan.usableTotal == 0 and plan.gatedTotal > 0 then
        plan.gateNote = level
            and format(L["Nothing on this list is usable at level %d yet. Everything below says what it is waiting on."], level)
            or L["Nothing on this list is usable yet. Everything below says what it is waiting on."]
    end

    planCache[slotID] = plan
    return plan
end

local function InvalidatePlans()
    wipe(planCache)
end

-- The plan only if it has already been worked out. Row update functions use
-- this and never ns.GetEnchantPlan, because building a plan reads spell
-- tooltips and that must never happen while a list is being scrolled.
function ns.PeekEnchantPlan(slotID)
    return slotID and planCache[slotID] or nil
end

-- ---------------------------------------------------------------------------
-- the character level picture
--
-- Also the one place every slot's plan gets built, deliberately: it runs from
-- the banner refresh, which is not a drawing path, so the row updates below it
-- only ever read a plan that is already sitting in the cache.
-- ---------------------------------------------------------------------------
function ns.GetEnchantSummary()
    local sum = {
        isEnchanter  = ns.IsEnchanter and ns.IsEnchanter() or false,
        recipesSeen  = recipesSeen,
        recipeCount  = recipeCount,
        canDoNow     = 0,      -- slots with an enchant you know and have not applied
        bare         = 0,      -- enchantable slots with nothing on them
        needSomebody = 0,      -- bare slots where somebody else has to do the work
        locked       = 0,      -- bare slots where nothing on the list is in reach yet
    }
    sum.rank, sum.maxRank, sum.rankSource = ns.GetEnchantingSkill()
    sum.level = PlayerLevel()

    local scan = ns.lastScan
    if not scan or not scan.slots then return sum end

    for i = 1, #scan.slots do
        local rec = scan.slots[i]
        if rec and rec.enchantable then
            local plan = ns.GetEnchantPlan(rec.slotID)
            if not rec.enchanted then
                sum.bare = sum.bare + 1
                if plan and plan.bestNow then
                    sum.canDoNow = sum.canDoNow + 1
                elseif not sum.isEnchanter or (plan and plan.kind ~= KIND_ENCHANT) then
                    sum.needSomebody = sum.needSomebody + 1
                end
                -- Counted separately from needSomebody, because "somebody else
                -- has to do this" and "nobody can do this for you yet" are
                -- different answers and only one of them is worth waiting for.
                if plan and plan.usableTotal == 0 and (plan.gatedTotal or 0) > 0 then
                    sum.locked = sum.locked + 1
                end
            end
        end
    end
    return sum
end

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------
-- Every path that changes an answer funnels through one debounced notify. A
-- login can fire hundreds of these between the spell data loading and the bags
-- settling, and rebuilding the page for each one would be pointless work while
-- nobody is even looking at it yet.
local NotifyChanged = ns.Debounce(0.5, function()
    InvalidatePlans()
    ns:Emit("ENCHANT_DATA_UPDATED")
end)

local Rescan = ns.Debounce(0.4, function()
    if ScanTradeSkill() then
        NotifyChanged()
    end
end)

ns:On("TRADE_SKILL_SHOW", Rescan)
ns:On("TRADE_SKILL_UPDATE", Rescan)
ns:On("TRADE_SKILL_LIST_UPDATE", Rescan)
ns:On("TRADE_SKILL_DATA_SOURCE_CHANGED", Rescan)

ns:On("SKILL_LINES_CHANGED", function()
    InvalidateSkill()
    InvalidatePlans()
end)
ns:On("CHAT_MSG_SKILL", function()
    InvalidateSkill()
end)
ns:On("LEARNED_SPELL_IN_TAB", function()
    NotifyChanged()
end)

-- A spell that had no description when it was first asked about now has one,
-- so the cached miss is dropped and the page redrawn.
--
-- Only for spells this file actually asked about. The event fires for whatever
-- the client and every other addon happens to load, and treating all of that as
-- a reason to rebuild the enchant page was rebuilding it under the player's
-- cursor for reasons that had nothing to do with enchanting.
ns:On("SPELL_DATA_LOAD_RESULT", function(spellID)
    if not spellID or not spellRequested[spellID] then return end
    spellInfoCache[spellID] = nil
    NotifyChanged()
end)

-- This fires for every point of reputation, and a point of reputation changes
-- no answer on this page: only crossing into a new standing does. So the
-- standings already read are re-read and compared, which is a handful of
-- lookups over the few factions this slot's rewards come from, and the page is
-- only rebuilt when one of them has actually moved.
ns:On("UPDATE_FACTION", function()
    local moved = false
    for name, rec in pairs(standingCache) do
        local was = (type(rec) == "table") and rec.id or nil
        if ReadStanding(name) ~= was then moved = true; break end
    end
    if not moved then return end
    wipe(standingCache)
    NotifyChanged()
end)

-- Levelling changes what is in reach, which is the whole point of the grouping,
-- so it is worth a redraw of its own.
ns:On("PLAYER_LEVEL_UP", NotifyChanged)

-- Equipment changing invalidates immediately rather than on the debounce,
-- because the page redraw that follows it must not read a plan built for the
-- item that was just taken off.
ns:Sub("SCAN_UPDATED", InvalidatePlans)
ns:Sub("ITEM_CACHE_UPDATED", NotifyChanged)
ns:Sub("DB_READY", function()
    LoadRecipes()
    InvalidateSkill()
    InvalidatePlans()
end)

-- ---------------------------------------------------------------------------
-- the page
--
-- Same two panel shape the upgrades page uses, because it answers the same
-- kind of question and the two should not feel like different addons. Left is
-- every slot with a status colour, right is the whole answer for the one that
-- is selected.
-- ---------------------------------------------------------------------------
local enchPage, banner, bannerTitle, bannerLine
local slotList, optionList
local wornIcon, wornIconEdge, wornSlotLine, wornLine, wornTag
local noteLine, basisLine, optionHeader, optionEmpty
local selectedSlotID = 15
local ShowSlot, RefreshBanner

local SLOT_ROW_HEIGHT = 36

local function SlotArt(slotID)
    return slotID and ns.SLOT_ART and ns.SLOT_ART[slotID] or nil
end

local function QualityColor(quality)
    local q = _G.ITEM_QUALITY_COLORS
    local c = quality and type(q) == "table" and q[quality]
    if type(c) == "table" and type(c.r) == "number" then
        return c.r, c.g, c.b
    end
    return T.text[1], T.text[2], T.text[3]
end

local function NoWrap(fs)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
end

-- One line saying where this slot stands, and the colour that goes with it.
-- Written here so the left list and the right panel never disagree.
--
-- Reads the plan cache and never builds one, because this is called from a
-- pooled row's update function. ns.GetEnchantSummary has already built every
-- slot's plan by the time any row draws, so the fallback wording below is only
-- ever seen for the handful of frames before that happens.
local function SlotStatus(slotID)
    local scan = ns.lastScan
    local rec = scan and scan.bySlotID and scan.bySlotID[slotID]
    if not rec or rec.empty then return L["Nothing equipped"], T.dim end
    if not rec.enchantable then return L["Takes no enchant"], T.dim end
    if rec.enchanted then return L["Already enchanted"], T.good end

    local plan = ns.PeekEnchantPlan(slotID)
    if plan and plan.bestNow then return L["You can do this one now"], T.good end
    -- Everything this slot offers is out of reach. Said before the source lines
    -- below, because "bought with reputation" reads as a plan and this is not
    -- one yet.
    if plan and plan.usableTotal == 0 and (plan.gatedTotal or 0) > 0 then
        return L["Nothing in reach yet"], T.dim
    end
    if plan and plan.kind == KIND_REP then return L["Bought with reputation"], T.accent end
    if plan and plan.kind == KIND_LEG then return L["Leatherworker or tailor"], T.accent end
    if plan and plan.kind == KIND_SCOPE then return L["Engineer fits a scope"], T.accent end
    if plan and plan.best then return L["Bare, recipe not known"], T.warn end
    return L["Bare"], T.warn
end

-- ---------------------------------------------------------------------------
-- left hand slot list
-- ---------------------------------------------------------------------------
local function CreateSlotRow(list)
    local row = CreateFrame("Button", nil, list)

    row.hl = UI.Tex(row, "BACKGROUND", T.hover)
    row.hl:SetPoint("TOPLEFT", 0, -1)
    row.hl:SetPoint("BOTTOMRIGHT", 0, 1)
    row.hl:Hide()

    row.selBg = UI.Tex(row, "BACKGROUND", { T.accent[1], T.accent[2], T.accent[3], 0.10 })
    row.selBg:SetPoint("TOPLEFT", 0, -1)
    row.selBg:SetPoint("BOTTOMRIGHT", 0, 1)
    row.selBg:Hide()

    row.sel = UI.Tex(row, "ARTWORK", T.accent)
    row.sel:SetPoint("TOPLEFT", 0, -1)
    row.sel:SetPoint("BOTTOMLEFT", 0, 1)
    row.sel:SetWidth(2)
    row.sel:Hide()

    -- Created once. This list is pooled and scrolled, so anything created in
    -- the update path would leak one object per scroll event.
    row.iconEdge = UI.Tex(row, "BACKGROUND", T.line)
    row.iconEdge:SetSize(26, 26)
    row.iconEdge:SetPoint("LEFT", 8, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("CENTER", row.iconEdge, "CENTER")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = NoWrap(UI.Font(row, 12, T.text, nil, "LEFT"))
    row.name:SetPoint("TOPLEFT", 42, -4)
    row.name:SetPoint("RIGHT", -8, 0)

    row.sub = NoWrap(UI.Font(row, 10, T.dim, nil, "LEFT"))
    row.sub:SetPoint("TOPLEFT", 42, -19)
    row.sub:SetPoint("RIGHT", -8, 0)

    row:SetScript("OnEnter", function(self)
        self.hl:Show()
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
        if self.slotID and ShowSlot then ShowSlot(self.slotID) end
    end)
    return row
end

local function UpdateSlotRow(row, def)
    row.slotID = def.id
    row.name:SetText(def.label)

    local scan = ns.lastScan
    local rec = scan and scan.bySlotID and scan.bySlotID[def.id]
    row.link = rec and rec.link or nil

    -- Every branch writes every field. A pooled row must never keep the icon
    -- or the colour of whichever slot it drew before it was reused.
    local art = (rec and not rec.empty and rec.icon) or SlotArt(def.id)
    if art then
        row.icon:SetTexture(art)
        row.icon:Show()
        row.iconEdge:Show()
        row.icon:SetAlpha((rec and not rec.empty) and 1 or 0.5)
        if rec and not rec.empty then
            row.iconEdge:SetColorTexture(QualityColor(rec.quality))
        else
            row.iconEdge:SetColorTexture(T.lineHard[1], T.lineHard[2], T.lineHard[3], T.lineHard[4] or 1)
        end
    else
        row.icon:Hide()
        row.iconEdge:Hide()
    end

    local text, color = SlotStatus(def.id)
    row.sub:SetText(text)
    row.sub:SetTextColor(color[1], color[2], color[3], color[4] or 1)

    local on = (def.id == selectedSlotID)
    row.sel:SetShown(on)
    row.selBg:SetShown(on)
    row.name:SetTextColor(unpack(on and T.accent or T.text))
end

-- ---------------------------------------------------------------------------
-- option rows
--
-- Five wrapping lines, none of them with a fixed height. Every one of them
-- hangs off the bottom of the line above, and the measure function below adds
-- up the same five so a long sentence gets the room it needs instead of being
-- cut off. Fixed heights on wrapping text are what caused the truncation bugs
-- this codebase already had once.
--
-- Section headings share the row and the pool rather than being a second
-- widget type, the same way the upgrades list does it, but with their own font
-- strings: a pooled row that reuses one font string across two very different
-- looks has to remember to undo every property it changed, while two sets only
-- have to be blanked.
-- ---------------------------------------------------------------------------
local OPT_PAD_TOP    = 6
local OPT_PAD_BOTTOM = 6
local OPT_TEXT_LEFT  = 10
local OPT_TEXT_RIGHT = 10
local OPT_ICON       = 18
local OPT_TITLE_LEFT = OPT_TEXT_LEFT + OPT_ICON + 6
local OPT_BODY_DX    = OPT_TEXT_LEFT - OPT_TITLE_LEFT
local OPT_FLAG_W     = 130
local OPT_GAP        = 2
local OPT_GAP_ACTION = 4
local OPT_MIN_HEIGHT = 54

local OPT_HEAD_TOP    = 10
local OPT_HEAD_BOTTOM = 8
-- The shortest row this list can ever produce, which is a heading with a one
-- line note under it. UI.List sizes its row pool from the height it is given,
-- so that number has to be the true minimum across BOTH row shapes: hand it
-- the option minimum instead and a panel full of short headings runs out of
-- pooled rows before it reaches its own bottom edge.
local OPT_ROW_MIN    = 34

local function CreateOptionRow(list)
    local row = CreateFrame("Button", nil, list)

    row.hl = UI.Tex(row, "BACKGROUND", T.hover)
    row.hl:SetPoint("TOPLEFT", 0, 0)
    row.hl:SetPoint("BOTTOMRIGHT", 0, 1)
    row.hl:Hide()

    row.stripe = UI.Tex(row, "ARTWORK", T.accent)
    row.stripe:SetPoint("TOPLEFT", 0, -2)
    row.stripe:SetPoint("BOTTOMLEFT", 0, 3)
    row.stripe:SetWidth(3)

    row.sep = UI.Tex(row, "ARTWORK", T.line)
    row.sep:SetPoint("BOTTOMLEFT", OPT_TEXT_LEFT, 0)
    row.sep:SetPoint("BOTTOMRIGHT", -OPT_TEXT_RIGHT, 0)
    row.sep:SetHeight(1)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(OPT_ICON, OPT_ICON)
    row.icon:SetPoint("TOPLEFT", OPT_TEXT_LEFT, -OPT_PAD_TOP)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Two anchors on the top edge fix the width and leave the height
    -- intrinsic, which is what lets a font string grow to as many lines as its
    -- text wraps to.
    row.title = UI.Font(row, 12, T.text, nil, "LEFT")
    row.title:SetPoint("TOPLEFT", OPT_TITLE_LEFT, -OPT_PAD_TOP)
    row.title:SetPoint("TOPRIGHT", -(OPT_TEXT_RIGHT + OPT_FLAG_W + 6), -OPT_PAD_TOP)
    row.title:SetJustifyV("TOP")

    -- The one word that says why this row is at the top of the list, or what is
    -- keeping it off the character. Never wraps, so it can never push the row's
    -- own layout around.
    row.flag = NoWrap(UI.Font(row, 9, T.good, nil, "RIGHT"))
    row.flag:SetPoint("TOPRIGHT", -OPT_TEXT_RIGHT, -OPT_PAD_TOP - 1)
    row.flag:SetWidth(OPT_FLAG_W)

    -- What stands in the way, directly under the name, because for a row the
    -- character cannot use that is the only thing worth reading first. Empty
    -- for anything usable, and an empty font string collapses to nothing, which
    -- is why the measure below can add its gap unconditionally.
    row.gate = UI.Font(row, 11, T.warn, nil, "LEFT")
    row.gate:SetPoint("TOPLEFT",  row.title, "BOTTOMLEFT",  OPT_BODY_DX, -OPT_GAP)
    row.gate:SetPoint("TOPRIGHT", row.title, "BOTTOMRIGHT", OPT_FLAG_W + 6, -OPT_GAP)
    row.gate:SetJustifyV("TOP")

    row.detail = UI.Font(row, 11, T.dim, nil, "LEFT")
    row.detail:SetPoint("TOPLEFT",  row.gate, "BOTTOMLEFT",  0, -OPT_GAP)
    row.detail:SetPoint("TOPRIGHT", row.gate, "BOTTOMRIGHT", 0, -OPT_GAP)
    row.detail:SetJustifyV("TOP")

    row.action = UI.Font(row, 11, T.accent, nil, "LEFT")
    row.action:SetPoint("TOPLEFT",  row.detail, "BOTTOMLEFT",  0, -OPT_GAP_ACTION)
    row.action:SetPoint("TOPRIGHT", row.detail, "BOTTOMRIGHT", 0, -OPT_GAP_ACTION)
    row.action:SetJustifyV("TOP")

    row.mats = UI.Font(row, 11, T.dim, nil, "LEFT")
    row.mats:SetPoint("TOPLEFT",  row.action, "BOTTOMLEFT",  0, -OPT_GAP)
    row.mats:SetPoint("TOPRIGHT", row.action, "BOTTOMRIGHT", 0, -OPT_GAP)
    row.mats:SetJustifyV("TOP")

    -- Heading widgets. Created once with the rest of the row, never in an
    -- update, and simply blanked on every row that is not a heading.
    row.headTitle = NoWrap(UI.Font(row, 11, T.accent, nil, "LEFT"))
    row.headTitle:SetPoint("TOPLEFT", OPT_TEXT_LEFT, -OPT_HEAD_TOP)
    row.headTitle:SetPoint("TOPRIGHT", -(OPT_TEXT_RIGHT + OPT_FLAG_W + 6), -OPT_HEAD_TOP)

    row.headCount = NoWrap(UI.Font(row, 9, T.dim, nil, "RIGHT"))
    row.headCount:SetPoint("TOPRIGHT", -OPT_TEXT_RIGHT, -OPT_HEAD_TOP - 1)
    row.headCount:SetWidth(OPT_FLAG_W)

    -- Wraps, and carries no height of its own, because what a group is waiting
    -- on is a sentence and not a label.
    row.headNote = UI.Font(row, 10, T.dim, nil, "LEFT")
    row.headNote:SetPoint("TOPLEFT",  row.headTitle, "BOTTOMLEFT",  0, -OPT_GAP)
    row.headNote:SetPoint("TOPRIGHT", row.headTitle, "BOTTOMRIGHT", OPT_FLAG_W + 6, -OPT_GAP)
    row.headNote:SetJustifyV("TOP")

    row:SetScript("OnEnter", function(self)
        local opt = self.opt
        -- A heading is not an option, so it neither highlights nor has a
        -- tooltip to show.
        if not opt or opt.isHeader then return end
        self.hl:Show()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if opt.link then
            GameTooltip:SetHyperlink(opt.link)
        elseif opt.itemID then
            GameTooltip:SetItemByID(opt.itemID)
        elseif opt.spellID and GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(opt.spellID)
        else
            return
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip:Hide()
    end)
    return row
end

-- The same insets the row above anchors against, because the two have to agree
-- or rows get sized for a width they are not drawn at. The title stops short of
-- the flag in the corner; the four body lines run the full width of the row,
-- since the flag only ever occupies the first line. A heading's own title stops
-- short of its count in the same corner, but it starts at the body inset rather
-- than the title one, because a heading carries no icon.
local OPT_TITLE_INSET = OPT_TITLE_LEFT + OPT_TEXT_RIGHT + OPT_FLAG_W + 6
local OPT_BODY_INSET  = OPT_TEXT_LEFT + OPT_TEXT_RIGHT
local OPT_HEAD_INSET  = OPT_TEXT_LEFT + OPT_TEXT_RIGHT + OPT_FLAG_W + 6

local function MeasureOptionRow(opt, width)
    width = width or 0
    local bw = max(1, width - OPT_BODY_INSET)

    if opt.isHeader then
        local hw = max(1, width - OPT_HEAD_INSET)
        local h = OPT_HEAD_TOP + UI.MeasureText(11, hw, opt.label or "")
        h = h + OPT_GAP + UI.MeasureText(10, bw, opt.headNote or "")
        -- Never shorter than the height the row pool was sized from, so a list
        -- of nothing but headings still has a row for every visible slot.
        return max(OPT_ROW_MIN, h + OPT_HEAD_BOTTOM + 1)
    end

    local tw = max(1, width - OPT_TITLE_INSET)
    local h = OPT_PAD_TOP + UI.MeasureText(12, tw, opt.name or "")
    h = h + OPT_GAP + UI.MeasureText(11, bw, opt.gateText or "")
    h = h + OPT_GAP + UI.MeasureText(11, bw, opt.detail or "")
    h = h + OPT_GAP_ACTION + UI.MeasureText(11, bw, opt.action or "")
    local mats = opt.matsText or opt.mats
    if mats and mats ~= "" then
        h = h + OPT_GAP + UI.MeasureText(11, bw, mats)
    end
    -- A floor, never a ceiling. The measured height always wins when it is
    -- larger. The extra pixel is the separator at the bottom of the row.
    return max(OPT_MIN_HEIGHT, h + OPT_PAD_BOTTOM + 1)
end

-- Which corner label a row earns. A row nothing is in the way of gets the one
-- that says why it is near the top; a row that is out of reach gets the one
-- naming what is holding it there, since at that point nothing else about the
-- row matters as much.
local function FlagFor(opt)
    if (opt.gate or GATE_NONE) ~= GATE_NONE then
        if opt.reqLevel then return format("AT LEVEL %d", opt.reqLevel), T.dim end
        if opt.repGate then return "COSTS REPUTATION", T.dim end
        if opt.itemGate then return "NEEDS A BETTER ITEM", T.dim end
        return "NOT YET", T.dim
    end
    if opt.isBest then return "BEST FOR YOU", T.accent end
    if opt.isBestNow then return "BEST YOU CAN DO NOW", T.good end
    if opt.trainToward then return "WORTH TRAINING FOR", T.warn end
    return "", T.dim
end

local function UpdateOptionRow(row, opt)
    row.opt = opt

    -- Every branch writes every widget. A pooled row must never keep the
    -- heading, the stripe or the flag of whichever row it drew before it was
    -- scrolled and reused.
    if opt.isHeader then
        local hc = T[opt.color or "accent"] or T.accent
        row.headTitle:SetText(opt.label or "")
        row.headTitle:SetTextColor(hc[1], hc[2], hc[3], hc[4] or 1)
        row.headNote:SetText(opt.headNote or "")
        row.headCount:SetText(opt.countText or "")

        row.hl:Hide()
        row.stripe:Hide()
        row.icon:Hide()
        row.title:SetText("")
        row.gate:SetText("")
        row.detail:SetText("")
        row.action:SetText("")
        row.mats:SetText("")
        row.flag:SetText("")
        return
    end

    row.headTitle:SetText("")
    row.headNote:SetText("")
    row.headCount:SetText("")

    local c = T[CASE_COLOR[opt.case or CASE_OTHER] or "accent"] or T.accent
    row.stripe:SetColorTexture(c[1], c[2], c[3], 1)
    row.stripe:Show()

    row.icon:SetTexture(opt.icon or FALLBACK_ICON)
    row.icon:Show()
    row.title:SetText(opt.name or "")

    -- Out of reach reads quieter the further out it is, so a group of level 70
    -- rewards never shouts louder than the enchant sitting above them that the
    -- character could put on tonight.
    row.gate:SetText(opt.gateText or "")
    local gc = ((opt.gate or GATE_NONE) == GATE_SOON) and T.warn or T.dim
    row.gate:SetTextColor(gc[1], gc[2], gc[3], gc[4] or 1)

    row.detail:SetText(opt.detail or "")
    row.action:SetText(opt.action or "")
    row.action:SetTextColor(c[1], c[2], c[3], 1)
    row.mats:SetText(opt.matsText or opt.mats or "")

    local flag, fc = FlagFor(opt)
    row.flag:SetText(flag)
    row.flag:SetTextColor(fc[1], fc[2], fc[3], fc[4] or 1)
end

-- ---------------------------------------------------------------------------
-- the right hand panel
-- ---------------------------------------------------------------------------
local rightPanel

-- Both notices wrap, so how much room each needs is measured rather than
-- assumed, and the list below them grows into whatever is left. Runs once per
-- slot selection, never per row, and creates nothing.
local function LayoutPanel(showNote, showBasis)
    local panelW = rightPanel:GetWidth() or 0
    if panelW <= 1 then panelW = 460 end
    local textW = max(1, panelW - 28)

    local y = 62

    noteLine:ClearAllPoints()
    noteLine:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 14, -y)
    noteLine:SetPoint("RIGHT", rightPanel, "RIGHT", -14, 0)
    noteLine:SetShown(showNote)
    if showNote then
        y = y + max(14, UI.MeasureText(11, textW, noteLine:GetText() or "")) + 7
    end

    basisLine:ClearAllPoints()
    basisLine:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 14, -y)
    basisLine:SetPoint("RIGHT", rightPanel, "RIGHT", -14, 0)
    basisLine:SetShown(showBasis)
    if showBasis then
        y = y + max(12, UI.MeasureText(10, textW, basisLine:GetText() or "")) + 6
    end

    optionHeader:ClearAllPoints()
    optionHeader:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 14, -y)
    y = y + 16

    optionList:ClearAllPoints()
    optionList:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 8, -y)
    optionList:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -6, 8)
end

-- The item this slot is actually wearing, restated next to the advice, so
-- "best for what" is always on screen beside the list claiming to answer it.
local function ShowWorn(plan)
    local rec = plan and plan.worn
    wornSlotLine:SetText((plan and plan.label) or "Slot")

    if rec and not rec.empty then
        wornLine:SetText(format(L["%s, item level %d"], rec.name or L["Unknown item"], rec.ilvl or 0))
        wornLine:SetTextColor(QualityColor(rec.quality))
        wornIcon:SetTexture(rec.icon or SlotArt(plan.slotID))
        wornIcon:SetAlpha(1)
        wornIconEdge:SetColorTexture(QualityColor(rec.quality))
    else
        wornLine:SetText(L["Nothing equipped here right now."])
        wornLine:SetTextColor(unpack(T.dim))
        wornIcon:SetTexture(SlotArt(plan and plan.slotID))
        wornIcon:SetAlpha(0.5)
        wornIconEdge:SetColorTexture(T.lineHard[1], T.lineHard[2], T.lineHard[3], T.lineHard[4] or 1)
    end

    local text, color = SlotStatus(plan and plan.slotID or 0)
    wornTag:SetText(text:upper())
    wornTag:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

-- One sentence saying what the ranking is actually based on, because a role
-- guess and a researched weight table are not the same thing and the player
-- deserves to know which one they are looking at.
local function BasisText()
    local info = ns.GetSpecInfo and ns.GetSpecInfo()
    local specName = info and info.name
    local confidence = (info and info.confidence) or "none"
    local role, roleConfidence = nil, "none"
    if ns.GetSpecRole then role, roleConfidence = ns.GetSpecRole() end

    -- The spec name is the client's own talent tab name, so it goes in
    -- untouched. The role word is one of tank, healer, melee, ranged or
    -- caster, which Swedish players say in English too.
    if HaveResearchedWeights() and (confidence == "high" or confidence == "medium") then
        return format(L["Ranked with GearScout's researched stat weights for %s."], specName or L["your spec"])
    end
    if HaveResearchedWeights() then
        return format(L["Your talents are too thin to name a spec, so this is ranked with the weights for %s and is a guide rather than an answer. Every option for this slot is listed below, not just the top one."],
            specName or L["the tree you have most points in"])
    end
    if role and (roleConfidence == "high" or roleConfidence == "medium") then
        return format(L["GearScout has no researched stat weights for your spec, so this is ranked by what a %s generally wants. That is a preference, not research."], role)
    end
    return L["GearScout has neither researched stat weights for your spec nor a confident read on your role, so this ordering is a rough one. Read the options rather than trusting the order."]
end

-- One heading row. Built here rather than in the plan because it is a piece of
-- the list's layout and not a piece of the answer, though every word in it
-- comes from the plan. The field is headNote rather than note because an option
-- row already carries a note of its own meaning something else entirely, and
-- the two share a row.
local function HeaderRow(label, headNote, color, shown, total)
    local countText
    if total and total > 0 then
        countText = (shown < total)
            and format("SHOWING %d OF %d", shown, total)
            or format(total == 1 and "%d OPTION" or "%d OPTIONS", total)
    end
    return { isHeader = true, label = label, headNote = headNote, color = color, countText = countText }
end

-- Which slot the option list currently holds. The difference between "the
-- player clicked a different slot" and "the same slot was rebuilt underneath
-- them" is the difference between resetting the scroll and keeping it, and this
-- is the only thing that can tell the two apart.
local shownSlotID

ShowSlot = function(slotID)
    selectedSlotID = slotID
    local plan = ns.GetEnchantPlan(slotID)

    -- A rebuild of the slot already on screen must not move the view. This page
    -- redraws itself whenever an item finishes loading, a spell description
    -- arrives or the bags settle, which during a login is a steady stream, and
    -- every one of those redraws used to yank the list back to the top under
    -- whoever was reading it.
    local sameSlot = (slotID == shownSlotID)
    shownSlotID = slotID

    if not plan then
        ShowWorn(nil)
        noteLine:SetText("")
        LayoutPanel(false, false)
        optionList:SetData({})
        optionEmpty:Hide()
        slotList:Refresh()
        return
    end

    ShowWorn(plan)

    -- The note is whatever this slot most needs said about it, in order of how
    -- much it changes what the player should do. "Nothing here is in reach yet"
    -- outranks everything except the slot being unusable outright, because it
    -- changes whether the rest of the panel is worth reading at all.
    local note = plan.note
    if not note then
        local parts = {}
        if plan.gateNote then parts[#parts + 1] = plan.gateNote end
        if plan.kind == KIND_REP and plan.sourceLine then
            parts[#parts + 1] = plan.sourceLine
        elseif plan.categoryNote then
            parts[#parts + 1] = plan.categoryNote
        elseif plan.enchanted then
            parts[#parts + 1] = L["There is already an enchant on this one. GearScout cannot read which enchant it is, only that something is on there, so check the item tooltip before paying for a replacement."]
        end
        if #parts > 0 then note = table.concat(parts, " ") end
    end

    local showNote = note ~= nil and note ~= ""
    if showNote then noteLine:SetText(note) end

    local showBasis = #plan.options > 0
    if showBasis then basisLine:SetText(BasisText()) end

    LayoutPanel(showNote, showBasis)

    -- Usable options first, then the ones that cannot honestly be ranked, then
    -- what is out of reach, each group behind a heading that says what it is.
    -- Headings only appear when there is something to separate: a slot where
    -- everything is usable is the plain list it always was.
    local rows = {}
    local grouped = (#plan.soon > 0 or #plan.far > 0)
    local usableShown = #plan.options + #plan.unranked

    if grouped and usableShown > 0 then
        rows[#rows + 1] = HeaderRow(L["YOU CAN USE THESE NOW"],
            L["Nothing readable stands between you and any of these."], "good",
            usableShown, plan.usableTotal)
    end
    for i = 1, #plan.options do rows[#rows + 1] = plan.options[i] end
    for i = 1, #plan.unranked do rows[#rows + 1] = plan.unranked[i] end

    -- The unranked group needs one sentence saying why it is separate, and it
    -- rides on the first of them rather than costing the list a header row it
    -- would have to size and pool separately. Not shown for a reputation slot,
    -- where nothing was stat ranked in the first place.
    if #plan.unranked > 0 and plan.kind ~= KIND_REP then
        local first = plan.unranked[1]
        first.matsText = format(L["%s  |  This one and the %d below it have names that do not say what they do, so GearScout will not pretend to rank them."],
            first.mats or "", max(0, #plan.unranked - 1))
    end

    if #plan.soon > 0 then
        rows[#rows + 1] = HeaderRow(L["NOT YET, BUT CLOSE"],
            plan.soonNote or L["A little more character or a little more gear and these open up."],
            "warn", #plan.soon, plan.soonTotal)
        for i = 1, #plan.soon do rows[#rows + 1] = plan.soon[i] end
    end

    if #plan.far > 0 then
        rows[#rows + 1] = HeaderRow(L["A LONG WAY OFF"],
            plan.farNote or L["These are here so you know they exist, not because they are worth planning around today."],
            "dim", #plan.far, plan.farTotal)
        for i = 1, #plan.far do rows[#rows + 1] = plan.far[i] end
    end

    if plan.kind ~= KIND_ENCHANT then
        optionHeader:SetText(L["WHAT GOES ON THIS SLOT"])
    else
        optionHeader:SetText(grouped and L["WHAT TO PUT ON THIS SLOT, WHAT YOU CAN USE FIRST"]
            or L["WHAT TO PUT ON THIS SLOT, BEST FIRST"])
    end

    optionList:SetData(rows, sameSlot)
    optionEmpty:SetShown(#rows == 0)
    if #rows == 0 then
        optionEmpty:SetText(plan.note
            and L["Nothing to choose here."]
            or L["GearScout has no enchant data for this slot."])
    end

    slotList:Refresh()
end

RefreshBanner = function()
    if not banner then return end
    local sum = ns.GetEnchantSummary()

    -- Every count gets a whole sentence of its own rather than a stem with an
    -- "s" or a "ve" bolted onto it. That trick is English grammar and it does
    -- not survive translation into anything.
    local parts = {}
    if sum.isEnchanter then
        if sum.rank then
            parts[#parts + 1] = sum.maxRank
                and format(L["Enchanting %d of %d, read from %s."],
                    sum.rank, sum.maxRank, L[sum.rankSource] or L["the client"])
                or format(L["Enchanting %d, read from %s."],
                    sum.rank, L[sum.rankSource] or L["the client"])
        else
            parts[#parts + 1] = L["You are an enchanter. GearScout could not read your skill number on this client, so it will not guess one."]
        end
        if sum.recipesSeen then
            parts[#parts + 1] = format(L["It knows %d of your recipes and what they cost, read from your enchanting window."], sum.recipeCount)
        else
            parts[#parts + 1] = L["Open your enchanting window once and GearScout will read which recipes you know and what each one costs in materials."]
        end
    else
        parts[#parts + 1] = L["You are not an enchanter, so every enchant here is somebody else's work. What you can do is buy the materials and hand them over with the item."]
    end

    if sum.bare > 0 then
        if sum.canDoNow > 0 then
            parts[#parts + 1] = sum.bare == 1
                and format(L["%d of your 1 bare slot has an enchant you already know how to apply."], sum.canDoNow)
                or format(L["%d of your %d bare slots have an enchant you already know how to apply."], sum.canDoNow, sum.bare)
        else
            parts[#parts + 1] = sum.bare == 1
                and L["1 slot is carrying no enchant."]
                or format(L["%d slots are carrying no enchant."], sum.bare)
        end
        -- Said out loud so an empty looking slot list is not read as missing
        -- data. Head and shoulder are reputation bought at level 70 in this
        -- era, so a levelling character genuinely has nothing to do about them.
        if sum.locked > 0 then
            parts[#parts + 1] = sum.level
                and format(L["%d of those have nothing in reach at level %d, and each one says what it is waiting on."],
                    sum.locked, sum.level)
                or format(L["%d of those have nothing in reach yet, and each one says what it is waiting on."],
                    sum.locked)
        end
    else
        parts[#parts + 1] = L["Every slot that can take an enchant already has one."]
    end

    bannerLine:SetText(table.concat(parts, " "))

    local w = banner:GetWidth() or 0
    if w <= 1 then w = 700 end
    local h = UI.MeasureText(11, max(1, w - 28), bannerLine:GetText() or "")
    banner:SetHeight(max(46, 24 + h + 10))
end

function ns.BuildEnchantsPage(page)
    enchPage = page

    -- The banner is the only part of this page that is about the character
    -- rather than about one slot, so it sits across the top and the two panels
    -- below it grow into what is left.
    banner = UI.Panel(page, T.raised)
    banner:SetPoint("TOPLEFT", 12, -8)
    banner:SetPoint("TOPRIGHT", -12, -8)
    banner:SetHeight(46)

    bannerTitle = UI.Font(banner, 10, T.dim, nil, "LEFT")
    bannerTitle:SetPoint("TOPLEFT", 14, -8)

    -- No fixed height. RefreshBanner measures the same text to size the panel
    -- around it, so a long sentence is never clipped.
    bannerLine = UI.Font(banner, 11, T.text, nil, "LEFT")
    bannerLine:SetPoint("TOPLEFT", 14, -22)
    bannerLine:SetPoint("RIGHT", banner, "RIGHT", -14, 0)
    bannerLine:SetJustifyV("TOP")

    local left = UI.Panel(page, T.panel)
    left:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 0, -8)
    left:SetPoint("BOTTOMLEFT", 12, 8)
    left:SetWidth(232)

    local lh = UI.Font(left, 10, T.dim, nil, "LEFT")
    lh:SetPoint("TOPLEFT", 12, -10)

    local sep = UI.Divider(left)
    sep:SetPoint("TOPLEFT", 10, -26)
    sep:SetPoint("TOPRIGHT", -10, -26)

    slotList = UI.List(left, SLOT_ROW_HEIGHT, CreateSlotRow, UpdateSlotRow)
    slotList:SetPoint("TOPLEFT", 4, -32)
    slotList:SetPoint("BOTTOMRIGHT", -6, 8)

    rightPanel = UI.Panel(page, T.panel)
    rightPanel:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", -12, 8)

    wornIconEdge = UI.Tex(rightPanel, "BACKGROUND", T.line)
    wornIconEdge:SetSize(38, 38)
    wornIconEdge:SetPoint("TOPLEFT", 14, -12)

    wornIcon = rightPanel:CreateTexture(nil, "ARTWORK")
    wornIcon:SetSize(34, 34)
    wornIcon:SetPoint("CENTER", wornIconEdge, "CENTER")
    wornIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    wornSlotLine = NoWrap(UI.Font(rightPanel, 13, T.text, nil, "LEFT"))
    wornSlotLine:SetPoint("TOPLEFT", 60, -14)
    wornSlotLine:SetPoint("RIGHT", -160, 0)

    wornLine = NoWrap(UI.Font(rightPanel, 11, T.dim, nil, "LEFT"))
    wornLine:SetPoint("TOPLEFT", 60, -32)
    wornLine:SetPoint("RIGHT", -14, 0)

    wornTag = NoWrap(UI.Font(rightPanel, 9, T.dim, nil, "RIGHT"))
    wornTag:SetPoint("TOPRIGHT", -14, -14)
    wornTag:SetWidth(140)

    local sep2 = UI.Divider(rightPanel)
    sep2:SetPoint("TOPLEFT", 10, -56)
    sep2:SetPoint("TOPRIGHT", -10, -56)

    -- Re-anchored by LayoutPanel on every slot selection, so these offsets
    -- only matter until the first ShowSlot. Neither carries a fixed height.
    noteLine = UI.Font(rightPanel, 11, T.warn, nil, "LEFT")
    noteLine:SetPoint("TOPLEFT", 14, -62)
    noteLine:SetPoint("RIGHT", -14, 0)
    noteLine:SetJustifyV("TOP")
    noteLine:Hide()

    basisLine = UI.Font(rightPanel, 10, T.dim, nil, "LEFT")
    basisLine:SetPoint("TOPLEFT", 14, -62)
    basisLine:SetPoint("RIGHT", -14, 0)
    basisLine:SetJustifyV("TOP")
    basisLine:Hide()

    optionHeader = UI.Font(rightPanel, 10, T.dim, nil, "LEFT")
    optionHeader:SetPoint("TOPLEFT", 14, -62)

    -- The fixed headings on this page. ShowSlot rewrites optionHeader from the
    -- slot it is drawing, so it only needs a starting value here.
    local function ApplyLocale()
        bannerTitle:SetText(L["YOUR ENCHANTING"])
        lh:SetText(L["GEAR SLOTS"])
        optionHeader:SetText(L["WHAT TO PUT ON THIS SLOT, BEST FIRST"])
    end
    ApplyLocale()

    -- Variable height rows. OPT_ROW_MIN is only the shortest a row can be,
    -- which is a section heading rather than an option, and it is used purely
    -- to size the row pool; every row's real height comes from
    -- MeasureOptionRow.
    optionList = UI.List(rightPanel, OPT_ROW_MIN, CreateOptionRow, UpdateOptionRow, MeasureOptionRow)
    optionList:SetPoint("TOPLEFT", 8, -78)
    optionList:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -6, 8)

    optionEmpty = UI.Font(rightPanel, 11, T.dim, nil, "CENTER")
    optionEmpty:SetPoint("TOP", optionList, "TOP", 0, -24)
    optionEmpty:SetWidth(360)
    optionEmpty:Hide()

    local function Redraw()
        if not enchPage then return end
        RefreshBanner()
        ShowSlot(selectedSlotID)
    end

    ns:Sub("LOCALE_CHANGED", function()
        if not enchPage then return end
        ApplyLocale()
        -- Every plan holds sentences built in the old language, so they are
        -- thrown away and rebuilt rather than merely redrawn.
        InvalidatePlans()
        Redraw()
        slotList:Refresh()
    end)

    -- ITEM_CACHE_UPDATED is deliberately not subscribed here. It already
    -- reaches this page through the debounced ENCHANT_DATA_UPDATED above, and
    -- subscribing to both would redraw the whole page once per item the server
    -- hands back during a login.
    ns:Sub("SCAN_UPDATED", Redraw)
    ns:Sub("ENCHANT_DATA_UPDATED", Redraw)

    slotList:SetData(ns.SLOTS or {})

    -- Open on the first slot that is actually missing an enchant, since that is
    -- the one the player came here about. Falls back to the cloak, which is the
    -- cheapest enchant in the game and never a wasted answer.
    local firstBare
    local scan = ns.lastScan
    if scan and scan.slots then
        local bestPriority = 99
        for i = 1, #scan.slots do
            local rec = scan.slots[i]
            if rec and rec.enchantable and not rec.enchanted then
                local p = SLOT_PRIORITY[rec.slotID] or 99
                if p < bestPriority then bestPriority, firstBare = p, rec.slotID end
            end
        end
    end
    selectedSlotID = firstBare or 15

    RefreshBanner()
    ShowSlot(selectedSlotID)
end
