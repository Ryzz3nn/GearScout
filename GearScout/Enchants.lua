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

-- What the game itself says an enchant does, plus anything useful it happens
-- to print alongside. Every field is optional and absent means absent: nothing
-- here fills a gap with an assumption.
local spellInfoCache = {}
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
    end

    -- Nothing came back at all. Ask the client to load the spell and leave the
    -- cache empty so the next look gets a real answer once it arrives.
    if not rec.text then
        if C_Spell and C_Spell.RequestLoadSpellData then
            pcall(C_Spell.RequestLoadSpellData, spellID)
        end
        return nil
    end

    spellInfoCache[spellID] = rec
    return rec
end

-- Same idea for an item, used by the reputation enchants, the leg armors and
-- the scopes, which are all real items rather than spells.
local itemTextCache = {}
local function ItemEnchantText(itemID)
    if not itemID then return nil end
    local cached = itemTextCache[itemID]
    if cached ~= nil then return cached or nil end
    local text = TipText("SetItemByID", itemID)
    local best
    if text then
        -- The line that describes the bonus is the one that mentions a stat.
        -- The item's name, its binding and its level requirement are not it.
        for line in text:gmatch("[^\n]+") do
            local low = line:lower()
            if not low:find("^requires") and not low:find("^binds") and TagFromText(line) then
                best = Tidy(line)
                break
            end
        end
    end
    itemTextCache[itemID] = best or false
    return best
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

-- One enchanting option, fully judged. Every text field is written here rather
-- than in a row update, because rows are pooled and must only ever set text.
local function BuildEnchantOption(id, catName, isEnchanter, wornIlvl)
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
        opt.detail = format("The name says this one gives %s. GearScout could not get the exact numbers from the client.", TAG_WORDS[tag] or tag)
    else
        opt.detail = "GearScout cannot tell what this one gives. The name does not say and the client would not describe it."
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
        opt.action = "You are not an enchanter, so somebody else applies this one. Buy the materials, hand them over with the item, and tip for the work."
    elseif known then
        opt.case = CASE_SELF
        opt.action = format("You can do this one yourself right now. Read from %s.", whereFrom or "your own recipes")
    else
        opt.case = CASE_LEARN
        local readable, readFrom = KnowledgeIsReadable()
        if readable then
            opt.action = format("You do not know this recipe yet, according to %s. Enchanting recipes come from your trainer or from a formula that drops, is sold, or is a reputation reward.", readFrom)
        else
            opt.action = "GearScout could not read which recipes you know. Open your enchanting window once and it will read them, along with what each one costs in materials."
        end
    end

    -- Materials. Only ever the real list from the player's own window.
    local rec = recipes[name:lower()]
    if rec and rec.mats then
        opt.mats = "Materials: " .. rec.mats
    elseif known then
        opt.mats = "Open your enchanting window once so GearScout can read what this one costs in materials."
    elseif isEnchanter then
        opt.mats = "GearScout only gets a material list for recipes you already know, because that is all the client will hand an addon."
    else
        opt.mats = "Ask the enchanter which materials they need. The client only tells GearScout the materials for recipes you know yourself."
    end

    -- Anything the client happened to print that is worth acting on.
    if opt.reqSkill then
        local rank = ns.GetEnchantingSkill()
        if rank and rank >= opt.reqSkill then
            opt.note = format("Needs %d enchanting skill. You have %d.", opt.reqSkill, rank)
        elseif rank then
            opt.note = format("Needs %d enchanting skill and you have %d, so you are %d short.",
                opt.reqSkill, rank, opt.reqSkill - rank)
            opt.trainToward = (opt.reqSkill - rank) <= 25
        else
            opt.note = format("Needs %d enchanting skill.", opt.reqSkill)
        end
    end
    if opt.reqIlvl and wornIlvl and wornIlvl > 0 and wornIlvl < opt.reqIlvl then
        local extra = format("This enchant needs an item of level %d or higher, and the one you are wearing is level %d.",
            opt.reqIlvl, wornIlvl)
        opt.note = opt.note and (opt.note .. " " .. extra) or extra
        opt.blocked = true
    end

    return opt
end

-- Reputation enchants, leg armor and scopes are all real items rather than
-- recipes, so they share one builder and differ only in who applies them.
local function BuildItemOption(itemID, name, kind, extra)
    local meta = ns.GetItemMeta and ns.GetItemMeta(itemID) or nil
    local shown = (meta and meta.name) or name or "Unknown item"
    local detail = ItemEnchantText(itemID)
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
        opt.detail = "GearScout could not read what this one gives. Hover it to see the game's own tooltip."
    else
        opt.detail = "Still loading from the server. Reopen this tab in a moment."
    end

    if kind == KIND_REP then
        opt.action = format("Bought once from the %s quartermaster at %s standing. You apply it yourself, no enchanter involved.",
            extra and extra.faction or "faction", (extra and extra.standing or "the required"):lower())
        opt.mats = "Costs reputation and a little gold, and it never wears off."
        opt.standing = extra and extra.standing
        opt.rank = extra and extra.rank or 9
    elseif kind == KIND_LEG then
        opt.action = format("A %s makes this. It is an item, so you can buy one off the auction house and apply it yourself.",
            (extra and extra.profession or "crafter"):lower())
        opt.mats = "Buy the finished item, or bring the materials to a crafter. This one is not an enchanting job."
    elseif kind == KIND_SCOPE then
        opt.action = "An engineer makes this. It is an item, so you can buy one and attach it yourself."
        opt.mats = "Buy the finished scope, or ask an engineer. This one is not an enchanting job."
    end

    return opt
end

-- ---------------------------------------------------------------------------
-- the plan for one slot
-- ---------------------------------------------------------------------------
local MAX_RANKED   = 6
local MAX_UNRANKED = 6

local function ByValue(a, b)
    if a.blocked ~= b.blocked then return not a.blocked end
    if a.value ~= b.value then return a.value > b.value end
    if a.tier ~= b.tier then return a.tier > b.tier end
    return (a.spellID or a.itemID or 0) > (b.spellID or b.itemID or 0)
end

-- Reputation options sort by how cheap the standing is to reach, since the
-- easiest one is the one worth telling somebody about first. Same rule
-- Sources.lua already applies to the same data.
local function ByStanding(a, b)
    local ra, rb = a.rank or 9, b.rank or 9
    if ra ~= rb then return ra < rb end
    return (a.name or "") < (b.name or "")
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

    local plan = {
        slotID      = slotID,
        label       = def.label,
        worn        = rec,
        enchantable = rec and rec.enchantable or false,
        enchanted   = rec and rec.enchanted or false,
        priority    = SLOT_PRIORITY[slotID] or 99,
        options     = {},
        unranked    = {},
    }

    if not rec or rec.empty then
        plan.note = "Nothing is equipped here, so there is nothing to enchant yet."
        planCache[slotID] = plan
        return plan
    end
    if not plan.enchantable then
        if def.ench == "enchanter" then
            plan.note = "Only an enchanter can enchant a ring, and this character is not one. It is the one enchant nobody can do for you."
        elseif def.ench == "ranged" then
            plan.note = "A scope only fits a bow, a gun or a crossbow. What is in this slot cannot take one."
        else
            plan.note = "This slot does not take a permanent enchant in this version of the game."
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
            Push(BuildItemOption(e.itemID, e.name, KIND_REP, e))
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
            Push(BuildItemOption(e.id, e.name, KIND_LEG, e))
        end
        sort(ranked, ByValue)

    elseif slotID == 18 then
        plan.kind = KIND_SCOPE
        local list = ns.WEAPON_SCOPES or {}
        for i = 1, #list do
            local e = list[i]
            Push(BuildItemOption(e.id, e.name, KIND_SCOPE, e))
        end
        sort(ranked, ByValue)

    else
        plan.kind = KIND_ENCHANT
        local key = CATALOGUE_KEY[slotID] or WeaponCategory(rec, slotID)
        local list = (ns.ENCHANT_ITEMS and ns.ENCHANT_ITEMS[key]) or {}
        plan.category = key
        for i = 1, #list do
            local e = list[i]
            Push(BuildEnchantOption(e.id, e.name, isEnchanter, wornIlvl))
        end
        sort(ranked, ByValue)
        sort(unranked, ByValue)

        -- A two hander can also take any of the one hand weapon enchants in
        -- this era, so the shorter list is not the whole answer. Saying which
        -- category was read stops that looking like missing data.
        if key == "2H Weapon" then
            plan.categoryNote = "You are holding a two hander, so these are the two hand weapon enchants."
        end
    end

    -- The best one for this character, and separately the best one they can
    -- actually put on today. Those are often not the same enchant, and the
    -- difference between them is the whole point of the page.
    --
    -- Not done for a reputation slot. That list is ordered by which standing is
    -- cheapest to reach rather than by which enchant is strongest, so calling
    -- the top of it "best for you" would be a claim the ordering never made.
    if plan.kind ~= KIND_REP then
        for i = 1, #ranked do
            local o = ranked[i]
            if not plan.best and not o.blocked then plan.best = o end
            if not plan.bestNow and o.case == CASE_SELF and not o.blocked then plan.bestNow = o end
        end

        if plan.best then plan.best.isBest = true end
        if plan.bestNow and plan.bestNow ~= plan.best then plan.bestNow.isBestNow = true end
    end

    for i = 1, min(#ranked, MAX_RANKED) do plan.options[#plan.options + 1] = ranked[i] end
    -- The best one you can do now always earns its place on screen even when
    -- the ranking would have pushed it off the end of the list.
    if plan.bestNow and plan.bestNow ~= plan.best then
        local shown = false
        for i = 1, #plan.options do
            if plan.options[i] == plan.bestNow then shown = true; break end
        end
        if not shown then plan.options[#plan.options + 1] = plan.bestNow end
    end

    for i = 1, min(#unranked, MAX_UNRANKED) do plan.unranked[#plan.unranked + 1] = unranked[i] end
    plan.unrankedTotal = #unranked

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
    }
    sum.rank, sum.maxRank, sum.rankSource = ns.GetEnchantingSkill()

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
ns:On("SPELL_DATA_LOAD_RESULT", function(spellID)
    if spellID then spellInfoCache[spellID] = nil end
    NotifyChanged()
end)

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
    if not rec or rec.empty then return "Nothing equipped", T.dim end
    if not rec.enchantable then return "Takes no enchant", T.dim end
    if rec.enchanted then return "Already enchanted", T.good end

    local plan = ns.PeekEnchantPlan(slotID)
    if plan and plan.bestNow then return "You can do this one now", T.good end
    if plan and plan.kind == KIND_REP then return "Bought with reputation", T.accent end
    if plan and plan.kind == KIND_LEG then return "Leatherworker or tailor", T.accent end
    if plan and plan.kind == KIND_SCOPE then return "Engineer fits a scope", T.accent end
    if plan and plan.best then return "Bare, recipe not known", T.warn end
    return "Bare", T.warn
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
-- Four wrapping lines, none of them with a fixed height. Every one of them
-- hangs off the bottom of the line above, and the measure function below adds
-- up the same four so a long sentence gets the room it needs instead of being
-- cut off. Fixed heights on wrapping text are what caused the truncation bugs
-- this codebase already had once.
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

    -- The one word that says why this row is at the top of the list. Never
    -- wraps, so it can never push the row's own layout around.
    row.flag = NoWrap(UI.Font(row, 9, T.good, nil, "RIGHT"))
    row.flag:SetPoint("TOPRIGHT", -OPT_TEXT_RIGHT, -OPT_PAD_TOP - 1)
    row.flag:SetWidth(OPT_FLAG_W)

    row.detail = UI.Font(row, 11, T.dim, nil, "LEFT")
    row.detail:SetPoint("TOPLEFT",  row.title, "BOTTOMLEFT",  OPT_BODY_DX, -OPT_GAP)
    row.detail:SetPoint("TOPRIGHT", row.title, "BOTTOMRIGHT", OPT_FLAG_W + 6, -OPT_GAP)
    row.detail:SetJustifyV("TOP")

    row.action = UI.Font(row, 11, T.accent, nil, "LEFT")
    row.action:SetPoint("TOPLEFT",  row.detail, "BOTTOMLEFT",  0, -OPT_GAP_ACTION)
    row.action:SetPoint("TOPRIGHT", row.detail, "BOTTOMRIGHT", 0, -OPT_GAP_ACTION)
    row.action:SetJustifyV("TOP")

    row.mats = UI.Font(row, 11, T.dim, nil, "LEFT")
    row.mats:SetPoint("TOPLEFT",  row.action, "BOTTOMLEFT",  0, -OPT_GAP)
    row.mats:SetPoint("TOPRIGHT", row.action, "BOTTOMRIGHT", 0, -OPT_GAP)
    row.mats:SetJustifyV("TOP")

    row:SetScript("OnEnter", function(self)
        self.hl:Show()
        local opt = self.opt
        if not opt then return end
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
-- the flag in the corner; the three body lines run the full width of the row,
-- since the flag only ever occupies the first line.
local OPT_TITLE_INSET = OPT_TITLE_LEFT + OPT_TEXT_RIGHT + OPT_FLAG_W + 6
local OPT_BODY_INSET  = OPT_TEXT_LEFT + OPT_TEXT_RIGHT

local function MeasureOptionRow(opt, width)
    width = width or 0
    local tw = max(1, width - OPT_TITLE_INSET)
    local bw = max(1, width - OPT_BODY_INSET)
    local h = OPT_PAD_TOP + UI.MeasureText(12, tw, opt.name or "")
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

local function UpdateOptionRow(row, opt)
    row.opt = opt

    local c = T[CASE_COLOR[opt.case or CASE_OTHER] or "accent"] or T.accent
    row.stripe:SetColorTexture(c[1], c[2], c[3], 1)

    row.icon:SetTexture(opt.icon or FALLBACK_ICON)
    row.title:SetText(opt.name or "")
    row.detail:SetText(opt.detail or "")
    row.action:SetText(opt.action or "")
    row.action:SetTextColor(c[1], c[2], c[3], 1)
    row.mats:SetText(opt.matsText or opt.mats or "")

    if opt.isBest then
        row.flag:SetText("BEST FOR YOU")
        row.flag:SetTextColor(unpack(T.accent))
    elseif opt.isBestNow then
        row.flag:SetText("BEST YOU CAN DO NOW")
        row.flag:SetTextColor(unpack(T.good))
    elseif opt.trainToward then
        row.flag:SetText("WORTH TRAINING FOR")
        row.flag:SetTextColor(unpack(T.warn))
    elseif opt.blocked then
        row.flag:SetText("ITEM TOO LOW")
        row.flag:SetTextColor(unpack(T.dim))
    else
        row.flag:SetText("")
    end
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
        wornLine:SetText(format("%s, item level %d", rec.name or "Unknown item", rec.ilvl or 0))
        wornLine:SetTextColor(QualityColor(rec.quality))
        wornIcon:SetTexture(rec.icon or SlotArt(plan.slotID))
        wornIcon:SetAlpha(1)
        wornIconEdge:SetColorTexture(QualityColor(rec.quality))
    else
        wornLine:SetText("Nothing equipped here right now.")
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

    if HaveResearchedWeights() and (confidence == "high" or confidence == "medium") then
        return format("Ranked with GearScout's researched stat weights for %s.", specName or "your spec")
    end
    if HaveResearchedWeights() then
        return format("Your talents are too thin to name a spec, so this is ranked with the weights for %s and is a guide rather than an answer. Every option for this slot is listed below, not just the top one.",
            specName or "the tree you have most points in")
    end
    if role and (roleConfidence == "high" or roleConfidence == "medium") then
        return format("GearScout has no researched stat weights for your spec, so this is ranked by what a %s generally wants. That is a preference, not research.", role)
    end
    return "GearScout has neither researched stat weights for your spec nor a confident read on your role, so this ordering is a rough one. Read the options rather than trusting the order."
end

ShowSlot = function(slotID)
    selectedSlotID = slotID
    local plan = ns.GetEnchantPlan(slotID)

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
    -- much it changes what the player should do.
    local note = plan.note
    if not note and plan.kind == KIND_REP and plan.sourceLine then
        note = plan.sourceLine
    elseif not note and plan.categoryNote then
        note = plan.categoryNote
    elseif not note and plan.enchanted then
        note = "There is already an enchant on this one. GearScout cannot read which enchant it is, only that something is on there, so check the item tooltip before paying for a replacement."
    end

    local showNote = note ~= nil and note ~= ""
    if showNote then noteLine:SetText(note) end

    local showBasis = #plan.options > 0
    if showBasis then basisLine:SetText(BasisText()) end

    LayoutPanel(showNote, showBasis)

    -- Ranked options first, then the ones that cannot honestly be ranked, with
    -- a divider row's worth of explanation carried on the first of them.
    local rows = {}
    for i = 1, #plan.options do rows[#rows + 1] = plan.options[i] end
    for i = 1, #plan.unranked do rows[#rows + 1] = plan.unranked[i] end

    -- The unranked group needs one sentence saying why it is separate, and it
    -- rides on the first of them rather than costing the list a header row it
    -- would have to size and pool separately. Not shown for a reputation slot,
    -- where nothing was stat ranked in the first place.
    if #plan.unranked > 0 and plan.kind ~= KIND_REP then
        local first = plan.unranked[1]
        first.matsText = format("%s  |  This one and the %d below it have names that do not say what they do, so GearScout will not pretend to rank them.",
            first.mats or "", max(0, #plan.unranked - 1))
    end

    optionHeader:SetText(plan.kind == KIND_ENCHANT and "WHAT TO PUT ON THIS SLOT, BEST FIRST"
        or "WHAT GOES ON THIS SLOT")

    optionList:SetData(rows)
    optionEmpty:SetShown(#rows == 0)
    if #rows == 0 then
        optionEmpty:SetText(plan.note
            and "Nothing to choose here."
            or "GearScout has no enchant data for this slot.")
    end

    slotList:Refresh()
end

RefreshBanner = function()
    if not banner then return end
    local sum = ns.GetEnchantSummary()

    local parts = {}
    if sum.isEnchanter then
        if sum.rank then
            parts[#parts + 1] = format("Enchanting %d%s, read from %s.",
                sum.rank,
                sum.maxRank and format(" of %d", sum.maxRank) or "",
                sum.rankSource or "the client")
        else
            parts[#parts + 1] = "You are an enchanter. GearScout could not read your skill number on this client, so it will not guess one."
        end
        if sum.recipesSeen then
            parts[#parts + 1] = format("It knows %d of your recipes and what they cost, read from your enchanting window.", sum.recipeCount)
        else
            parts[#parts + 1] = "Open your enchanting window once and GearScout will read which recipes you know and what each one costs in materials."
        end
    else
        parts[#parts + 1] = "You are not an enchanter, so every enchant here is somebody else's work. What you can do is buy the materials and hand them over with the item."
    end

    if sum.bare > 0 then
        if sum.canDoNow > 0 then
            parts[#parts + 1] = format("%d of your %d bare slot%s ha%s an enchant you already know how to apply.",
                sum.canDoNow, sum.bare, sum.bare == 1 and "" or "s", sum.canDoNow == 1 and "s" or "ve")
        else
            parts[#parts + 1] = format("%d slot%s carrying no enchant.", sum.bare, sum.bare == 1 and " is" or "s are")
        end
    else
        parts[#parts + 1] = "Every slot that can take an enchant already has one."
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
    bannerTitle:SetText("YOUR ENCHANTING")

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
    lh:SetText("GEAR SLOTS")

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
    optionHeader:SetText("WHAT TO PUT ON THIS SLOT, BEST FIRST")

    -- Variable height rows. OPT_MIN_HEIGHT is only the shortest a row can be,
    -- used to size the row pool; every row's real height comes from
    -- MeasureOptionRow.
    optionList = UI.List(rightPanel, OPT_MIN_HEIGHT, CreateOptionRow, UpdateOptionRow, MeasureOptionRow)
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
