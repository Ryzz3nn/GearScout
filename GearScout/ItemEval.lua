-- GearScout / ItemEval.lua
-- Scores an item against a spec's researched stat weights, compares it to
-- what is currently equipped, and reports where a character stands against
-- the hard caps in Data/StatWeights.lua.
--
-- Writing rule, same as Rules.lua: every explanation says what is true, why
-- it matters, and what to do about it, in plain words a beginner can act on.
--
-- Public API:
--   ns.ScoreItem(itemLinkOrId, specKey)   numeric score, or nil plus a reason
--   ns.CompareToEquipped(itemLinkOrId)    delta plus a plain English explanation
--   ns.GetCapStatus(specKey)              list of caps this character meets or misses
--   ns.ExplainItem(itemLinkOrId, specKey) full per stat breakdown, see below
--   ns.ScoreItemAllSpecs(itemLinkOrId, classFile)  one score per spec of a class
--
-- specKey is optional everywhere it appears. Pass nil to mean "the character
-- currently logged in, in their current talent spec". Pass a table shaped
-- like { class = "PALADIN", tab = 2 } to score for a different spec, for
-- example when a raid lead is checking gear for someone else's class.
--
-- ---------------------------------------------------------------------------
-- ns.ExplainItem, the three tier model
--
-- Pawn's problem is not that its arithmetic is wrong, it is that it never
-- says why, so a wrong recommendation looks exactly as confident as a right
-- one. ExplainItem answers "why" by sorting everything about an item into
-- three tiers, and never lets a lower tier argue its way past a higher one:
--
--   1. Blocking. The item is unusable, full stop, and no stat total changes
--      that: a required level above the character, a weapon type the class
--      cannot equip, or a slot the class cannot fill at all (a shield with
--      no shield proficiency, a relic of the wrong kind). When this tier has
--      an entry the verdict is that entry, and the stat arithmetic is not
--      shown as if it mattered, because it does not.
--   2. Weighted penalty. Real, but not a veto. Right now this is armor
--      weight: a class wearing lighter armor than it could be wearing loses
--      real physical mitigation, but only from the level that class actually
--      gets access to the heavier type, matching the same level 40 gate
--      Scan.lua's own wantArmor already uses. Below that level cloth,
--      leather and mail are all so close in raw armor that the difference is
--      not worth a penalty, never mind a veto, which is exactly why a level
--      27 hunter in cloth boots is not a problem: they have no mail to give
--      up yet. This tier is folded straight into the score, and said in
--      words too, but a big enough stat gap still wins.
--   3. Ordinary stat arithmetic, the researched weights doing their normal
--      job: agility times its weight, stamina times its weight, and so on,
--      each one shown so a player can see exactly what an item is and is
--      not paying them for. A stat with no weight for this spec at all, or
--      a weight so small it barely moves the total, gets its own plain
--      English line instead of silently vanishing into a total, because
--      "plus 7 spell damage does nothing for a hunter" is worth more to a
--      hunter deciding whether to roll than the total ever is on its own.
--
-- ---------------------------------------------------------------------------
-- two different confidences, never mixed
--
-- "How good is GearScout's data for this spec" and "is this even the spec
-- you are playing" are separate questions with separate answers, and folding
-- them into one number would hide the more dangerous of the two. Researched,
-- audited, high confidence weights applied to the wrong talent tree are
-- still the wrong advice.
--   result.confidence      how good the researched data for that spec is,
--                          straight from Data/StatWeights.lua
--   result.specConfidence  how sure ns.GetSpecInfo is that this is the spec
--                          being played: none, low, medium, high, or
--                          explicit when the caller named the spec itself
-- When specConfidence is none or low, result.specUncertain is true, the item
-- is still scored with the deepest talent tree, result.specNote says in
-- plain words why that is a guess, and result.alternatives carries the same
-- item scored for every other spec of the class so a caller can show all of
-- them rather than commit to one. A level 27 hunter with points spread over
-- three trees gets three honest numbers instead of one confident wrong one.
--
-- ExplainItem returns one table (or nil plus a reason when the item itself
-- cannot be identified):
--   itemID, link, name
--   spec        { class, tab, name, confidence, role }    the spec used
--   specConfidence, specUncertain, specNote, alternatives see above
--   noData      true when this spec has no researched weights at all
--   blocking    array of { kind, text }, tier 1, empty when nothing blocks
--   armorPenalty  { fraction, note } or nil, tier 2
--   stats       array of { key, label, amount, weight, contribution, note,
--               dead, nearZero, capGated }, tier 3, dead stats sorted first
--   weapon      { dps, weight, contribution } for a ranged weapon's own DPS,
--               or { note } when the DPS could not be read yet
--   total, equippedTotal, delta, slotID
--   verdict     "blocked" | "no data" | "empty slot" | "upgrade" |
--               "sidegrade" | "downgrade" | "same" | "no slot"
--   verdictText a single plain English sentence matching verdict
--
-- Caps come first, same as everywhere else in this file. Whether a mandatory
-- cap, like a tank's defense skill, is currently met is checked through
-- ns.GetCapStatus before any stat comparison is trusted, because nothing
-- else matters until a missed mandatory cap is fixed.
--
-- A stat that has already passed its cap is worth only a small fraction of
-- its normal weight for the rest of that comparison, not full value and not
-- zero, matching how the caps in Data/StatWeights.lua actually behave.
--
-- Every stat lookup goes through ns.GetStats, the cached wrapper Scan.lua
-- already exposes for the C_Item.GetItemStats shim. Nothing in this file
-- calls GetItemStats or C_Item.GetItemStats directly, and nothing here is
-- wired into a refresh or OnUpdate path. Every per item computation, raw
-- stat contributions, weapon DPS, armor subclass, required level, is cached
-- by item id the first time it is needed and kept from then on, so a
-- tooltip that redraws on every mouse move never recomputes any of it.

local ADDON, ns = ...

local CreateFrame, UIParent = CreateFrame, UIParent
local GetInventoryItemLink = GetInventoryItemLink
local UnitClass, UnitLevel = UnitClass, UnitLevel
local GetItemInfo, GetItemInfoInstant = GetItemInfo, GetItemInfoInstant
local pairs, ipairs, type, tonumber, tostring = pairs, ipairs, type, tonumber, tostring
local format = string.format
local mmin, mfloor = math.min, math.floor

-- How much of a stat's weight survives once the character is already past
-- that stat's cap. Not zero, because a hair over a soft cap should not read
-- identically to wildly over it, but small enough that it never outweighs an
-- uncapped stat of the same size.
local OVERCAP_FACTOR = 0.05

-- ---------------------------------------------------------------------------
-- plain English labels
-- Shared by the per stat breakdown, the armor tier penalty note and the
-- blocking problem text, so the same stat or class is never worded two
-- different ways in the same tooltip.
-- ---------------------------------------------------------------------------
local CLASS_LOWER = {
    WARRIOR = "warrior", PALADIN = "paladin", HUNTER = "hunter", ROGUE = "rogue",
    PRIEST = "priest", SHAMAN = "shaman", MAGE = "mage", WARLOCK = "warlock",
    DRUID = "druid",
}

local CLASS_PLURAL = {
    WARRIOR = "Warriors", PALADIN = "Paladins", HUNTER = "Hunters", ROGUE = "Rogues",
    PRIEST = "Priests", SHAMAN = "Shamans", MAGE = "Mages", WARLOCK = "Warlocks",
    DRUID = "Druids",
}

local STAT_LABEL = {
    ITEM_MOD_STRENGTH_SHORT = "Strength",
    ITEM_MOD_AGILITY_SHORT = "Agility",
    ITEM_MOD_STAMINA_SHORT = "Stamina",
    ITEM_MOD_INTELLECT_SHORT = "Intellect",
    ITEM_MOD_SPIRIT_SHORT = "Spirit",
    ITEM_MOD_HIT_RATING_SHORT = "Hit Rating",
    ITEM_MOD_HIT_SPELL_RATING_SHORT = "Spell Hit Rating",
    ITEM_MOD_HIT_MELEE_RATING_SHORT = "Melee Hit Rating",
    ITEM_MOD_CRIT_RATING_SHORT = "Critical Strike Rating",
    ITEM_MOD_CRIT_SPELL_RATING_SHORT = "Spell Critical Strike Rating",
    ITEM_MOD_HASTE_RATING_SHORT = "Haste Rating",
    ITEM_MOD_HASTE_SPELL_RATING_SHORT = "Spell Haste Rating",
    ITEM_MOD_EXPERTISE_RATING_SHORT = "Expertise Rating",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "Defense Rating",
    ITEM_MOD_DODGE_RATING_SHORT = "Dodge Rating",
    ITEM_MOD_PARRY_RATING_SHORT = "Parry Rating",
    ITEM_MOD_BLOCK_RATING_SHORT = "Block Rating",
    ITEM_MOD_BLOCK_VALUE_SHORT = "Block Value",
    ITEM_MOD_RESILIENCE_RATING_SHORT = "Resilience Rating",
    ITEM_MOD_ATTACK_POWER_SHORT = "Attack Power",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "Ranged Attack Power",
    ITEM_MOD_SPELL_POWER_SHORT = "Spell Power",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "Spell Damage",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "Healing Power",
    ITEM_MOD_MANA_REGENERATION_SHORT = "Mana Regeneration",
}

-- Whichever of the character's own gear or the game's own level check is
-- available. Both CompareToEquipped and ExplainItem judge a hypothetical
-- other class's item using the currently logged in character's own level,
-- the same assumption SumEquippedStat already makes about equipped gear, so
-- this is not a new limitation, only a shared one made explicit here.
local function CurrentLevel()
    return (ns.lastScan and ns.lastScan.level) or (UnitLevel and UnitLevel("player")) or 0
end

-- Formats a stat amount without a pile of decimal places for the common
-- whole number case, but still shows one decimal for a fractional value
-- rather than silently rounding it away.
local function AmountText(v)
    if v == mfloor(v) then return format("%d", v) end
    return format("%.1f", v)
end

-- ---------------------------------------------------------------------------
-- spec resolution
-- ---------------------------------------------------------------------------

-- Looks up the researched weight table for a class and talent tab. Returns
-- nil when nothing has been researched for that class or tab, which callers
-- must treat as "cannot score", not as "score zero".
local function GetSpecData(classFile, tab)
    if not classFile or not tab then return nil end
    local classData = ns.STAT_WEIGHTS and ns.STAT_WEIGHTS[classFile]
    if not classData then return nil end
    return classData[tab]
end

-- Turns whatever the caller passed as specKey into a classFile and a tab
-- index. Falls back to the character currently logged in and their current
-- talent spec when nothing usable was passed in.
--
-- The third return is how sure GearScout is that the tab really is the spec
-- being played, straight from ns.GetSpecInfo: "none", "low", "medium" or
-- "high", or "explicit" when the caller named the spec itself and there is
-- nothing to be unsure about. The fourth is the role, which is settled
-- earlier than the tree name and is often the only part worth acting on for
-- a character who has barely spent a point. Nothing here refuses to score on
-- a low confidence; it scores with the deepest tree and says so, which is
-- more useful than silence and more honest than a confident wrong answer.
local function ResolveSpecKey(specKey)
    if type(specKey) == "table" and specKey.class then
        return specKey.class, tonumber(specKey.tab) or 1, "explicit", nil
    end
    if type(specKey) == "string" then
        local classFile, tab = specKey:match("^(%u+):(%d+)$")
        if classFile then return classFile, tonumber(tab), "explicit", nil end
    end

    local classFile = ns.playerClass or select(2, UnitClass("player"))
    local tab, confidence, role = 1, "none", nil
    if ns.GetSpecInfo then
        local info = ns.GetSpecInfo()
        tab        = info.tab or 1
        confidence = info.confidence or "none"
        role       = info.role
    elseif ns.GetSpec then
        local _, bestIdx = ns.GetSpec()
        tab = bestIdx or 1
    end
    return classFile, tab, confidence, role
end

-- Confidences a caller must not commit to one spec on. "explicit" is not in
-- here on purpose: a caller that named the spec itself is never second
-- guessed about it.
local UNCERTAIN_CONFIDENCE = { none = true, low = true }

local function SpecIsUncertain(confidence)
    return UNCERTAIN_CONFIDENCE[confidence or "none"] == true
end

-- Plain words for a role, for the one sentence that tells a player what
-- GearScout is treating them as.
local ROLE_WORDS = {
    tank   = "a tank",
    healer = "a healer",
    melee  = "a melee damage dealer",
    ranged = "a ranged damage dealer",
    caster = "a caster",
}

-- The sentence a player gets when their talents are too thin to name a spec
-- from. Says which tree is being used and why that is a guess, and, when the
-- role is settled even though the tree is not, says the part that is
-- actually known, because "you are a tank" is worth more to a low level
-- paladin than any stat total is.
local function SpecUncertaintyNote(specData, tab, classFile)
    local info = ns.GetSpecInfo and ns.GetSpecInfo()
    local total  = (info and info.total) or 0
    local points = (info and info.points) or 0
    local specName = (specData and specData.name) or (info and info.name) or format("talent tree %s", tostring(tab))

    local sentence
    if total <= 0 then
        sentence = format("You have not spent a talent point yet, so this is scored as %s until you do.", specName)
    else
        sentence = format(
            "Only %d of your %d talent points are in %s, too few to call that your spec, so this is a guide rather than an answer.",
            points, total, specName)
    end

    -- The role can be settled while the tree is not, which is the whole
    -- point of tracking the two apart, and for a hybrid class it is the part
    -- that actually changes what gear to want.
    if info and info.role and (info.roleConfidence == "high" or info.roleConfidence == "medium") then
        local word = ROLE_WORDS[info.role]
        if word and info.roleFromClass then
            sentence = sentence .. format(" Every %s build plays the same role, so you are scored as %s either way.",
                CLASS_LOWER[classFile] or "class", word)
        elseif word then
            sentence = sentence .. format(" Your points do say you are %s, and that much is taken as read.", word)
        end
    end

    return sentence
end

-- Plain English reason a spec has no usable data, for messages shown to the
-- player. Falls back to a generic line for anything not explicitly excluded.
local function NoDataReason(classFile, tab)
    local excluded = ns.STAT_WEIGHTS and ns.STAT_WEIGHTS.EXCLUDED and ns.STAT_WEIGHTS.EXCLUDED[classFile]
    if excluded then return excluded end
    return format("GearScout has no researched stat weights for %s, spec %s, yet.", tostring(classFile), tostring(tab))
end

-- ---------------------------------------------------------------------------
-- item identity
-- Accepts a full item link, a bare "item:" string, or a plain numeric item
-- id, and always hands back a usable "item:<id>" link plus the numeric id.
-- Using the bare item link, the same thing Scan.lua's socket counting uses,
-- means the score reflects the item itself and is stable no matter which
-- specific enchant or gems a particular copy carries, which is what makes
-- caching by item id correct.
-- ---------------------------------------------------------------------------
local function NormalizeItem(itemLinkOrId)
    local itemID
    if type(itemLinkOrId) == "number" then
        itemID = itemLinkOrId
    elseif type(itemLinkOrId) == "string" then
        itemID = ns.ParseLink(itemLinkOrId)
    end
    if not itemID then return nil, nil end
    return "item:" .. itemID, itemID
end

-- ---------------------------------------------------------------------------
-- cap lookup, memoised per spec table
-- ---------------------------------------------------------------------------
local capLookupCache = setmetatable({}, { __mode = "k" })

-- statKey -> the rating value beyond which that stat stops paying full
-- weight for this spec. When two caps name the same stat, the lower number
-- wins, which is the safer number to diminish returns after.
local function GetCapLookup(specData)
    local cached = capLookupCache[specData]
    if cached then return cached end

    local lookup = {}
    for _, cap in ipairs(specData.caps or {}) do
        if cap.statKey and cap.ratingValue then
            if not lookup[cap.statKey] or cap.ratingValue < lookup[cap.statKey] then
                lookup[cap.statKey] = cap.ratingValue
            end
        end
    end
    capLookupCache[specData] = lookup
    return lookup
end

-- The cap entry itself for a given stat, when this spec's data table names
-- one. Used to tell "this stat is weighted at zero because it does nothing"
-- apart from "this stat is weighted at zero because it is judged entirely by
-- a cap instead", which are very different things to tell a player.
local function FindCapForStat(specData, statKey)
    for _, cap in ipairs(specData.caps or {}) do
        if cap.statKey == statKey then return cap end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- how much of the character's current gear already carries a given stat
-- Reads ns.lastScan, the equipment snapshot Scan.lua already keeps, and each
-- slot's stats through ns.GetStats, which is cached by link. This never
-- triggers a fresh scan and never calls the stat API directly.
-- ---------------------------------------------------------------------------
local function SumEquippedStat(statKey, excludeSlotID)
    local scan = ns.lastScan
    if not scan or not scan.slots then return 0 end

    local total = 0
    for i = 1, #scan.slots do
        local rec = scan.slots[i]
        if not rec.empty and rec.link and rec.slotID ~= excludeSlotID then
            local stats = ns.GetStats(rec.link)
            local v = stats and stats[statKey]
            if type(v) == "number" then
                total = total + v
            end
        end
    end
    return total
end

-- Reduces value to reflect how much of it lands under currentTotal's
-- distance from capValue. The portion under the cap keeps full value, the
-- portion past it is worth only OVERCAP_FACTOR of its face value.
local function AdjustForCap(value, currentTotal, capValue)
    if not capValue then return value end
    local remaining = capValue - currentTotal
    if remaining <= 0 then
        return value * OVERCAP_FACTOR
    end
    if value <= remaining then
        return value
    end
    return remaining + (value - remaining) * OVERCAP_FACTOR
end

-- ---------------------------------------------------------------------------
-- tier 2, armor weight
-- Lighter armor than the class could be wearing is a real cost, but only
-- from the level that class actually has access to the heavier type. Below
-- that level every armor type carries so little that the difference is not
-- worth a penalty. This mirrors the exact level >= 40 gate Rules.lua's own
-- gear report already uses for the same check, and the exact wantArmor
-- relationship Scan.lua's own scan already computes, so a level 27 hunter in
-- cloth is correctly never penalised here at all.
-- ---------------------------------------------------------------------------
local ARMOR_NAME_TO_ID = { Cloth = 1, Leather = 2, Mail = 3, Plate = 4 }

local ARMOR_TIER_PENALTY_PER_TIER = 0.10 -- fraction of the item's score removed per tier of gap
local ARMOR_TIER_PENALTY_MAX = 0.35      -- never treat armor weight alone as more than this much of the score

local classInfoCache = {}
local function GetItemClassInfo(itemID)
    local cached = classInfoCache[itemID]
    if cached then return cached[1], cached[2] end
    local classID, subClassID
    if GetItemInfoInstant then
        local ok, _, _, _, _, _, c, s = pcall(GetItemInfoInstant, itemID)
        if ok then classID, subClassID = c, s end
    end
    classInfoCache[itemID] = { classID, subClassID }
    return classID, subClassID
end

-- The heaviest armor type classFile can currently be wearing, or nil when
-- that class has not reached the level its heavier armor type unlocks yet,
-- in which case there is nothing to compare against and no penalty applies.
local function GetWantArmorForClass(classFile, level)
    local types = ns.STAT_WEIGHTS and ns.STAT_WEIGHTS.ARMOR_TYPES
    local at = types and types[classFile]
    if not at then return nil, nil end
    local upgradeLevel = at.upgradeLevel or 40
    if level and level >= upgradeLevel then
        return ARMOR_NAME_TO_ID[at.upgraded], upgradeLevel
    end
    return nil, upgradeLevel
end

-- Returns the fraction of an armor item's score to remove for being a
-- lighter type than the class could be wearing, plus a plain English note,
-- or nil, nil when nothing applies: the item is not armor, it is already the
-- right weight or heavier, or the character has not reached the level where
-- the heavier type exists yet.
local function GetArmorTierPenalty(itemID, classFile, level)
    local classID, subClassID = GetItemClassInfo(itemID)
    if classID ~= 4 or not subClassID or subClassID < 1 or subClassID > 4 then
        return nil, nil
    end
    local wantArmor, upgradeLevel = GetWantArmorForClass(classFile, level)
    if not wantArmor or subClassID >= wantArmor then
        return nil, nil
    end

    local tierGap = wantArmor - subClassID
    local fraction = mmin(ARMOR_TIER_PENALTY_PER_TIER * tierGap, ARMOR_TIER_PENALTY_MAX)
    local note = format(
        "This is %s armor. From level %d a %s can wear %s instead, which carries meaningfully more armor. " ..
        "That is worth about %d percent of this item's score here, weighed in below, not a reason to rule the item out by itself.",
        ns.ARMOR_NAMES[subClassID] or "lighter", upgradeLevel, CLASS_LOWER[classFile] or tostring(classFile),
        ns.ARMOR_NAMES[wantArmor] or "heavier armor", ns.Round(fraction * 100))
    return fraction, note
end

-- ---------------------------------------------------------------------------
-- tier 1, blocking problems
-- Whether an item can be equipped at all does not care about stat weights,
-- so this is checked with only the game's own item and class data, never
-- with specData. Conservative on purpose: a weapon subtype or relic type
-- GearScout does not recognise is skipped rather than guessed at, because a
-- wrongly confident "you cannot use this" is worse than saying nothing.
-- ---------------------------------------------------------------------------
local reqLevelCache = {}
local function GetRequiredLevel(itemID)
    local cached = reqLevelCache[itemID]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local reqLevel
    if GetItemInfo then
        local ok, _, _, _, _, r = pcall(GetItemInfo, "item:" .. itemID)
        if ok and type(r) == "number" and r > 0 then reqLevel = r end
    end
    reqLevelCache[itemID] = reqLevel or false
    return reqLevel
end

-- Maps the localized weapon subtype tooltip text back to the generic name
-- Data/StatWeights.lua's WEAPON_PROFICIENCY table uses. Anything not listed
-- here, fist weapons, thrown, fishing poles, is left unchecked rather than
-- risking a wrong call.
local WEAPON_SUBTYPE_ALIASES = {
    ["One-Handed Axes"] = "Axe", ["Two-Handed Axes"] = "Axe",
    ["One-Handed Swords"] = "Sword", ["Two-Handed Swords"] = "Sword",
    ["One-Handed Maces"] = "Mace", ["Two-Handed Maces"] = "Mace",
    ["Daggers"] = "Dagger",
    ["Polearms"] = "Polearm",
    ["Staves"] = "Staff",
    ["Bows"] = "Bow",
    ["Guns"] = "Gun",
    ["Crossbows"] = "Crossbow",
    ["Wands"] = "Wand",
}

-- Which relic subtype each relic using class actually takes. A class not
-- listed here cannot equip any relic at all, the slot simply stays empty
-- for them.
local RELIC_TYPE_FOR_CLASS = {
    PALADIN = "Libram",
    DRUID   = "Idol",
    SHAMAN  = "Totem",
}

local function GetBlockingProblems(itemID, classFile, level, meta)
    local problems = {}

    local reqLevel = GetRequiredLevel(itemID)
    if reqLevel and level and level > 0 and reqLevel > level then
        problems[#problems + 1] = { kind = "required_level", text = format(
            "Requires level %d and you are level %d, so you cannot equip this yet.", reqLevel, level) }
    end

    local prof = ns.STAT_WEIGHTS and ns.STAT_WEIGHTS.WEAPON_PROFICIENCY and ns.STAT_WEIGHTS.WEAPON_PROFICIENCY[classFile]
    local subType = meta and meta.subType
    local equipLoc = meta and meta.equipLoc

    if prof then
        local classID = GetItemClassInfo(itemID)
        if classID == 2 and subType and subType ~= "" then
            local generic = WEAPON_SUBTYPE_ALIASES[subType]
            if generic then
                local allowed = false
                for _, w in ipairs(prof.weapons) do
                    if w == generic then allowed = true break end
                end
                if not allowed then
                    problems[#problems + 1] = { kind = "weapon_type", text = format(
                        "A %s cannot equip a %s.", CLASS_LOWER[classFile] or tostring(classFile), subType) }
                end
            end
        end

        if equipLoc == "INVTYPE_SHIELD" and prof.canUseShield == false then
            problems[#problems + 1] = { kind = "cannot_fill_slot", text = format(
                "A %s cannot equip a shield at all.", CLASS_LOWER[classFile] or tostring(classFile)) }
        end
    end

    if equipLoc == "INVTYPE_RELIC" and subType and subType ~= "" then
        local wanted = RELIC_TYPE_FOR_CLASS[classFile]
        if not wanted then
            problems[#problems + 1] = { kind = "cannot_fill_slot", text = format(
                "A %s cannot equip relics at all, that slot stays empty for your class.",
                CLASS_LOWER[classFile] or tostring(classFile)) }
        elseif subType ~= wanted then
            problems[#problems + 1] = { kind = "cannot_fill_slot", text = format(
                "This is a %s. A %s can only use a %s in that slot.",
                subType, CLASS_LOWER[classFile] or tostring(classFile), wanted) }
        end
    end

    return problems
end

-- ---------------------------------------------------------------------------
-- per item id caches
-- rawStatCache holds the item's own weighted stat contributions, uncapped,
-- for a given spec. It never changes for a given item id and spec, so it is
-- computed once. Cap adjustment happens afterwards, live, against the
-- character's current gear, which does change as the character re-gears.
-- weaponDPSCache holds a ranged weapon's damage per second, read once from
-- its tooltip, the same technique Scan.lua uses for reading gem sockets.
-- ---------------------------------------------------------------------------
local rawStatCache = {}
local weaponDPSCache = {}

local function SpecCacheKey(classFile, tab)
    return (classFile or "?") .. ":" .. tostring(tab or "?")
end

local function GetRawStatContribution(itemID, specData, specCacheKey)
    local byItem = rawStatCache[itemID]
    if byItem and byItem[specCacheKey] then
        return byItem[specCacheKey]
    end

    local stats = ns.GetStats("item:" .. itemID)
    local perStat, hasWeightedStat = {}, false
    if stats and specData.weights then
        for statKey, value in pairs(stats) do
            local weight = specData.weights[statKey]
            if weight and weight ~= 0 and type(value) == "number" then
                perStat[statKey] = { value = value, weight = weight }
                hasWeightedStat = true
            end
        end
    end

    local result = { perStat = perStat, hasStats = stats ~= nil, hasWeightedStat = hasWeightedStat }
    rawStatCache[itemID] = rawStatCache[itemID] or {}
    rawStatCache[itemID][specCacheKey] = result
    return result
end

-- ---------------------------------------------------------------------------
-- tier 3, the full per stat breakdown, every stat on the item
-- Unlike GetRawStatContribution above, which ScoreItem uses and which only
-- keeps stats this spec actually weighs, this keeps every stat the item has
-- so a stat with no weight at all, the ones actually worth telling a player
-- about, are not silently dropped before they are ever looked at.
-- ---------------------------------------------------------------------------
local SOCKET_LIKE_KEYS = {
    EMPTY_SOCKET_RED = true,
    EMPTY_SOCKET_YELLOW = true,
    EMPTY_SOCKET_BLUE = true,
    EMPTY_SOCKET_META = true,
    EMPTY_SOCKET_PRISMATIC = true,
}

local allStatCache = {}
local function GetAllStatEntries(itemID, specData, specCacheKey)
    local byItem = allStatCache[itemID]
    if byItem and byItem[specCacheKey] then
        return byItem[specCacheKey]
    end

    local stats = ns.GetStats("item:" .. itemID)
    local entries = {}
    if stats then
        for statKey, value in pairs(stats) do
            -- Sockets are not a stat to judge and ITEM_MOD_ARMOR is not a
            -- confirmed stat key this addon reads for scoring (see the audit
            -- note in Data/StatWeights.lua), and armor always helps physical
            -- mitigation regardless of class, so it is never "junk" either.
            -- Both are left out of the breakdown entirely rather than mislabelled.
            if not SOCKET_LIKE_KEYS[statKey] and statKey ~= "ITEM_MOD_ARMOR" and type(value) == "number" then
                entries[#entries + 1] = { key = statKey, value = value, weight = specData.weights and specData.weights[statKey] }
            end
        end
    end

    allStatCache[itemID] = allStatCache[itemID] or {}
    allStatCache[itemID][specCacheKey] = entries
    return entries
end

local NEAR_ZERO_FRACTION = 0.12 -- a stat weighing less than this fraction of the spec's top stat barely moves the score

local topWeightCache = setmetatable({}, { __mode = "k" })
local function GetTopWeight(specData)
    local cached = topWeightCache[specData]
    if cached then return cached end
    local top = 0
    for _, w in pairs(specData.weights or {}) do
        if w and w > top then top = w end
    end
    topWeightCache[specData] = top
    return top
end

local topStatCache = setmetatable({}, { __mode = "k" })
local function GetTopStatNames(specData, limit)
    local cached = topStatCache[specData]
    if cached then return cached end
    local ranked = {}
    for key, w in pairs(specData.weights or {}) do
        if w and w > 0 then ranked[#ranked + 1] = { key = key, w = w } end
    end
    table.sort(ranked, function(a, b) return a.w > b.w end)
    local names = {}
    for i = 1, mmin(limit or 3, #ranked) do
        names[#names + 1] = STAT_LABEL[ranked[i].key] or ranked[i].key
    end
    topStatCache[specData] = names
    return names
end

-- Builds one row per stat on the item, and the tier 3 subtotal. Rows are
-- returned with dead stats first, then near zero ones, then the stats that
-- actually pay, then cap gated stats last, so a caller that only has room
-- for the first one or two rows shows the ones most worth saying out loud.
local function BuildStatBreakdown(itemID, specData, specCacheKey, excludeSlotID, classFile)
    local entries = GetAllStatEntries(itemID, specData, specCacheKey)
    local capsByStat = GetCapLookup(specData)
    local topWeight = GetTopWeight(specData)
    local className = CLASS_LOWER[classFile] or "your class"

    local out, total = {}, 0
    for _, e in ipairs(entries) do
        local row = { key = e.key, label = STAT_LABEL[e.key] or e.key, amount = e.value, weight = e.weight }

        if e.weight and e.weight ~= 0 then
            local usedValue = e.value
            local capValue = capsByStat[e.key]
            if capValue then
                local currentTotal = SumEquippedStat(e.key, excludeSlotID)
                usedValue = AdjustForCap(usedValue, currentTotal, capValue)
            end
            row.contribution = e.weight * usedValue
            total = total + row.contribution

            if topWeight > 0 and (e.weight / topWeight) < NEAR_ZERO_FRACTION then
                row.nearZero = true
                local top = GetTopStatNames(specData, 3)
                row.note = format("%s %s is close to nothing for a %s. It carries only a token weight next to %s.",
                    row.label, AmountText(e.value), className, table.concat(top, ", "))
            end
        else
            row.contribution = 0
            local cap = FindCapForStat(specData, e.key)
            if cap then
                row.capGated = true
                row.note = format("%s does not add to the score by itself, it is judged entirely by the %s: %s",
                    row.label, cap.name, cap.explanation)
            else
                row.dead = true
                local top = GetTopStatNames(specData, 3)
                local wantText = #top > 0 and table.concat(top, ", ") or "their own class stats"
                row.note = format("%s %s does nothing for a %s. %s look for %s instead.",
                    row.label, AmountText(e.value), className, CLASS_PLURAL[classFile] or "They", wantText)
            end
        end

        out[#out + 1] = row
    end

    table.sort(out, function(a, b)
        local function Rank(r)
            if r.dead then return 1 end
            if r.nearZero then return 2 end
            if r.capGated then return 4 end
            return 3
        end
        local ra, rb = Rank(a), Rank(b)
        if ra ~= rb then return ra < rb end
        return (a.amount or 0) > (b.amount or 0)
    end)

    return out, total
end

-- ---------------------------------------------------------------------------
-- ranged weapon damage per second
-- A hunter's ranged weapon must be judged on its own DPS first, because DPS
-- is not something the item's per point stats can express, per the hard
-- rules in Data/StatWeights.lua. The DPS is read once from the item's own
-- tooltip line and cached by item id from then on, same caching rule as
-- everything else in this file.
-- ---------------------------------------------------------------------------
local RANGED_EQUIP_LOCS = {
    INVTYPE_RANGED = true,
    INVTYPE_RANGEDRIGHT = true,
    INVTYPE_THROWN = true,
}

local evalTip
local function GetWeaponDPS(itemID)
    local cached = weaponDPSCache[itemID]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    if not evalTip then
        evalTip = CreateFrame("GameTooltip", "GearScoutEvalTooltip", nil, "GameTooltipTemplate")
        evalTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    evalTip:ClearLines()

    local dps
    local ok = pcall(evalTip.SetHyperlink, evalTip, "item:" .. itemID)
    if ok then
        for i = 1, evalTip:NumLines() do
            local fs = _G["GearScoutEvalTooltipTextLeft" .. i]
            local txt = fs and fs:GetText()
            if txt then
                -- Matches a line shaped like "(46.7 damage per second)"
                -- without depending on the exact locale wording around the
                -- number, only on it sitting inside parentheses next to the
                -- words "per second".
                local num = txt:match("%(([%d%.,]+)%s*%a[%a%s]-per%s*second%)")
                if num then
                    dps = tonumber((num:gsub(",", "")))
                    if dps then break end
                end
            end
        end
    end

    weaponDPSCache[itemID] = dps or false
    return dps
end

-- ---------------------------------------------------------------------------
-- ns.ScoreItem(itemLinkOrId, specKey)
-- Returns a numeric score, or nil plus a plain English reason it could not
-- be scored. A third return, confidence, is "high", "medium" or "low" and
-- mirrors the confidence marker the audit left on that spec's data, so a
-- caller can decide whether to show the number with a caveat.
--
-- A fourth return says how sure GearScout is that this is even the right
-- spec to be scoring for, which is a different question from how good the
-- data for that spec is. A researched, high confidence weight table applied
-- to the wrong tree is still the wrong answer, so the two are kept apart
-- rather than folded into one number.
-- ---------------------------------------------------------------------------
function ns.ScoreItem(itemLinkOrId, specKey, excludeSlotID)
    local link, itemID = NormalizeItem(itemLinkOrId)
    if not itemID then
        return nil, "That is not a recognisable item.", nil, nil
    end

    local classFile, tab, specConfidence = ResolveSpecKey(specKey)
    local specData = GetSpecData(classFile, tab)
    if not specData then
        return nil, NoDataReason(classFile, tab), "low", specConfidence
    end

    local specCacheKey = SpecCacheKey(classFile, tab)
    local cached = GetRawStatContribution(itemID, specData, specCacheKey)
    local capsByStat = GetCapLookup(specData)

    local score = 0
    for statKey, info in pairs(cached.perStat) do
        local capValue = capsByStat[statKey]
        local usedValue = info.value
        if capValue then
            local currentTotal = SumEquippedStat(statKey, excludeSlotID)
            usedValue = AdjustForCap(usedValue, currentTotal, capValue)
        end
        score = score + info.weight * usedValue
    end

    -- Ranged weapon DPS, when this spec cares about it and this item is a
    -- ranged weapon, dominates the score rather than being folded into the
    -- stat sum above, matching the hard rule that a hunter's weapon is
    -- judged on its damage output first.
    if specData.weaponDPSWeight then
        local meta = ns.GetItemMeta and ns.GetItemMeta(itemID)
        if meta and RANGED_EQUIP_LOCS[meta.equipLoc or ""] then
            local dps = GetWeaponDPS(itemID)
            if dps then
                score = score + dps * specData.weaponDPSWeight
            end
        end
    end

    -- Tier 2: a lighter armor type than the class could be wearing, from the
    -- level that class actually has the heavier type available. See the
    -- GetArmorTierPenalty comment above for why this is folded into the
    -- score itself rather than only mentioned in passing.
    local armorFraction = GetArmorTierPenalty(itemID, classFile, CurrentLevel())
    if armorFraction then
        score = score * (1 - armorFraction)
    end

    return score, nil, specData.confidence, specConfidence
end

-- ---------------------------------------------------------------------------
-- ns.ScoreItemAllSpecs(itemLinkOrId, classFile, excludeSlotID)
-- Every spec of a class scored against the same item, in tab order, for the
-- case ns.GetSpecInfo reports too few talent points to name one. Showing
-- three honest numbers beats showing one confident wrong one.
--
-- Returns an array of { tab, name, score, confidence }, or nil plus a plain
-- English reason when the class has no researched weights at all. Specs with
-- no researched data are left out rather than listed with a zero, and score
-- is nil for a spec whose stats could not be read yet.
-- ---------------------------------------------------------------------------
function ns.ScoreItemAllSpecs(itemLinkOrId, classFile, excludeSlotID)
    local link, itemID = NormalizeItem(itemLinkOrId)
    if not itemID then
        return nil, "That is not a recognisable item."
    end

    classFile = classFile or ns.playerClass or select(2, UnitClass("player"))
    local classData = ns.STAT_WEIGHTS and ns.STAT_WEIGHTS[classFile]
    if not classData then
        local excluded = ns.STAT_WEIGHTS and ns.STAT_WEIGHTS.EXCLUDED and ns.STAT_WEIGHTS.EXCLUDED[classFile]
        return nil, excluded or format("GearScout has no researched stat weights for %s yet.", tostring(classFile))
    end

    local out = {}
    for tab = 1, 3 do
        local specData = classData[tab]
        if specData then
            local score = ns.ScoreItem(link, { class = classFile, tab = tab }, excludeSlotID)
            out[#out + 1] = {
                tab = tab,
                name = specData.name,
                score = score,
                confidence = specData.confidence,
            }
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- equip slot lookup, for CompareToEquipped and ExplainItem
-- Ring, trinket and one hand weapon slots come in pairs. When an item could
-- go in either one, the weaker of the two currently equipped is treated as
-- the one being replaced, since that is the one a player would actually
-- swap out.
-- ---------------------------------------------------------------------------
local EQUIP_SLOTS = {
    INVTYPE_HEAD = { 1 },
    INVTYPE_NECK = { 2 },
    INVTYPE_SHOULDER = { 3 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 },
    INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 },
    INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 },
    INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 },
    INVTYPE_RELIC = { 18 },
}

local function PickReplaceSlot(slotIDs, classFile, tab)
    if #slotIDs == 1 then return slotIDs[1] end

    local scan = ns.lastScan
    local bestSlot, bestScore
    for _, slotID in ipairs(slotIDs) do
        local rec = scan and scan.bySlotID and scan.bySlotID[slotID]
        if not rec or rec.empty then
            return slotID -- an empty slot is always the one to fill first
        end
        local s = ns.ScoreItem(rec.link, { class = classFile, tab = tab })
        s = s or 0
        if not bestScore or s < bestScore then
            bestScore, bestSlot = s, slotID
        end
    end
    return bestSlot or slotIDs[1]
end

local function GetEquippedLink(slotID)
    local scan = ns.lastScan
    local rec = scan and scan.bySlotID and scan.bySlotID[slotID]
    if rec and rec.link then return rec.link end
    if GetInventoryItemLink then
        return GetInventoryItemLink("player", slotID)
    end
    return nil
end

-- One sentence describing how newScore compares to equippedScore, shared by
-- CompareToEquipped's longer explanation and ExplainItem's tight verdict
-- line, so the two never disagree in wording.
local function VerdictSentence(delta, equippedLink, equippedScore)
    if not equippedLink then
        return "empty slot", "That slot is currently empty, so equipping this is a straight upgrade over nothing."
    elseif delta > 0.05 then
        local pct
        if equippedScore > 0 then pct = (delta / equippedScore) * 100 end
        if pct and pct >= 15 then
            return "upgrade", "This is a clear upgrade over what you have equipped there now."
        elseif pct and pct < 5 then
            return "sidegrade", "This is a small upgrade, more of a sidegrade than a real improvement."
        else
            return "upgrade", "This is an upgrade over what you have equipped there now."
        end
    elseif delta < -0.05 then
        return "downgrade", "This is a downgrade from what you already have equipped there."
    else
        return "same", "This is about the same as what you already have equipped there."
    end
end

-- ---------------------------------------------------------------------------
-- ns.GetCapStatus(specKey)
-- Returns a list of caps for the given spec, each entry saying whether the
-- character currently meets it. Entries whose cap has no fixed rating
-- number, because the research only gave a rule of thumb rather than a hard
-- number, come back with measurable = false and no met value; the
-- explanation still tells the player what to look at.
--
-- The third return is how sure GearScout is that this is the right spec at
-- all, separate from the second return's confidence in the spec's data.
-- ---------------------------------------------------------------------------
function ns.GetCapStatus(specKey)
    local classFile, tab, specConfidence = ResolveSpecKey(specKey)
    local specData = GetSpecData(classFile, tab)
    if not specData then
        return nil, NoDataReason(classFile, tab), specConfidence
    end

    local results = {}
    for _, cap in ipairs(specData.caps or {}) do
        local row = {
            name = cap.name,
            kind = cap.kind,
            statKey = cap.statKey,
            percentValue = cap.percentValue,
            explanation = cap.explanation,
        }
        if cap.statKey and cap.ratingValue then
            local current = SumEquippedStat(cap.statKey)
            row.measurable = true
            row.current = current
            row.needed = cap.ratingValue
            row.met = current >= cap.ratingValue
        else
            row.measurable = false
        end
        results[#results + 1] = row
    end
    return results, specData.confidence, specConfidence
end

-- ---------------------------------------------------------------------------
-- ns.CompareToEquipped(itemLinkOrId)
-- Always uses the character currently logged in and their current talent
-- spec. Returns delta, explanation. delta is nil when the item or the
-- character's spec could not be scored at all, or when a tier 1 blocking
-- problem makes the arithmetic beside the point; the explanation says why.
-- ---------------------------------------------------------------------------
function ns.CompareToEquipped(itemLinkOrId)
    local link, itemID = NormalizeItem(itemLinkOrId)
    if not itemID then
        return nil, "That is not a recognisable item, so GearScout cannot compare it to anything."
    end

    local classFile, tab, specConfidence = ResolveSpecKey(nil)
    local level = CurrentLevel()
    local meta = ns.GetItemMeta and ns.GetItemMeta(itemID)

    -- Tier 1 first. None of the arithmetic below is worth showing if the
    -- item cannot be equipped at all, so a blocking problem short circuits
    -- everything else and says so in unambiguous words.
    local blocking = GetBlockingProblems(itemID, classFile, level, meta)
    if #blocking > 0 then
        local texts = {}
        for _, p in ipairs(blocking) do texts[#texts + 1] = p.text end
        return nil, table.concat(texts, " ")
    end

    local specData = GetSpecData(classFile, tab)
    if not specData then
        return nil, NoDataReason(classFile, tab)
    end

    local equipLoc = meta and meta.equipLoc
    local slotIDs = equipLoc and EQUIP_SLOTS[equipLoc]
    if not slotIDs then
        return nil, "GearScout does not know which equipment slot that item goes in yet, so it cannot be compared."
    end

    local slotID = PickReplaceSlot(slotIDs, classFile, tab)
    local equippedLink = GetEquippedLink(slotID)

    local newScore = ns.ScoreItem(link, { class = classFile, tab = tab }, slotID)
    if not newScore then
        return nil, format("GearScout could not read the stats on that item yet. Hover it once in game so the client can cache it, then try again.")
    end

    local equippedScore = 0
    if equippedLink then
        equippedScore = ns.ScoreItem(equippedLink, { class = classFile, tab = tab }, slotID) or 0
    end

    local delta = newScore - equippedScore

    -- Caps come first. A missed mandatory cap gets said before any stat
    -- comparison, because nothing else matters until it is fixed.
    local capLines = {}
    local caps = ns.GetCapStatus({ class = classFile, tab = tab })
    if caps then
        for _, cap in ipairs(caps) do
            if cap.kind == "must reach" and cap.measurable and not cap.met then
                capLines[#capLines + 1] = format(
                    "You have not reached %s yet, %d of %d rating. Fix that before this comparison matters: %s",
                    cap.name, cap.current or 0, cap.needed or 0, cap.explanation)
            end
        end
    end

    local _, verdictSentence = VerdictSentence(delta, equippedLink, equippedScore)
    local pieces = { verdictSentence }

    -- Tier 2, said in words as well as folded into the score above, so a
    -- player sees the armor gap even when the total still comes out ahead.
    local _, armorNote = GetArmorTierPenalty(itemID, classFile, level)
    if armorNote then
        pieces[#pieces + 1] = armorNote
    end

    -- Which spec this was scored for, said out loud whenever the talents are
    -- too thin to be sure of it. Said before the data confidence line below,
    -- because scoring the wrong spec well is a bigger problem than scoring
    -- the right spec from thin data.
    if SpecIsUncertain(specConfidence) then
        pieces[#pieces + 1] = SpecUncertaintyNote(specData, tab, classFile)
    end

    if specData.confidence and specData.confidence ~= "high" then
        pieces[#pieces + 1] = format(
            "GearScout's data for %s is marked %s confidence, so treat this comparison as a rough guide, not a final answer.",
            specData.name or classFile, specData.confidence)
    end

    local explanation
    if #capLines > 0 then
        explanation = table.concat(capLines, " ") .. " " .. table.concat(pieces, " ")
    else
        explanation = table.concat(pieces, " ")
    end

    return delta, explanation
end

-- ---------------------------------------------------------------------------
-- ns.ExplainItem(itemLinkOrId, specKey)
-- See the file header for the full three tier model and the return shape.
-- Always uses the currently logged in character's own equipped gear and
-- level, the same as CompareToEquipped; specKey only changes which spec's
-- weights judge the stats.
-- ---------------------------------------------------------------------------
function ns.ExplainItem(itemLinkOrId, specKey)
    local link, itemID = NormalizeItem(itemLinkOrId)
    if not itemID then
        return nil, "That is not a recognisable item."
    end

    local classFile, tab, specConfidence, specRole = ResolveSpecKey(specKey)
    local level = CurrentLevel()
    local meta = ns.GetItemMeta and ns.GetItemMeta(itemID)

    local result = {
        itemID = itemID,
        link = link,
        name = meta and meta.name,
        -- spec.confidence is how sure GearScout is that this is the spec
        -- being played. result.confidence further down is a different thing
        -- entirely: how good the researched data for that spec is.
        spec = { class = classFile, tab = tab, confidence = specConfidence, role = specRole },
        specConfidence = specConfidence,
        specUncertain = SpecIsUncertain(specConfidence),
    }

    -- Tier 1. Checked before spec data even matters, because whether an item
    -- can be equipped does not depend on whether GearScout has researched
    -- weights for the spec.
    result.blocking = GetBlockingProblems(itemID, classFile, level, meta)

    local specData = GetSpecData(classFile, tab)
    if not specData then
        result.noData = true
        result.reason = NoDataReason(classFile, tab)
        if #result.blocking > 0 then
            local texts = {}
            for _, p in ipairs(result.blocking) do texts[#texts + 1] = p.text end
            result.verdict = "blocked"
            result.verdictText = table.concat(texts, " ")
        else
            result.verdict = "no data"
            result.verdictText = result.reason
        end
        return result
    end

    result.spec.name = specData.name
    result.confidence = specData.confidence

    if #result.blocking > 0 then
        local texts = {}
        for _, p in ipairs(result.blocking) do texts[#texts + 1] = p.text end
        result.verdict = "blocked"
        result.verdictText = table.concat(texts, " ")
    end

    local specCacheKey = SpecCacheKey(classFile, tab)

    -- Which slot this item would replace, exactly the way CompareToEquipped
    -- resolves it, so the cap adjustment below and the equipped comparison
    -- agree with each other.
    local equipLoc = meta and meta.equipLoc
    local slotIDs = equipLoc and EQUIP_SLOTS[equipLoc]
    local slotID = slotIDs and PickReplaceSlot(slotIDs, classFile, tab) or nil
    local equippedLink = slotID and GetEquippedLink(slotID) or nil

    -- Tier 3, every stat on the item.
    local stats, rawTotal = BuildStatBreakdown(itemID, specData, specCacheKey, slotID, classFile)
    result.stats = stats

    local weaponScore = 0
    if specData.weaponDPSWeight and meta and RANGED_EQUIP_LOCS[meta.equipLoc or ""] then
        local dps = GetWeaponDPS(itemID)
        if dps then
            weaponScore = dps * specData.weaponDPSWeight
            result.weapon = { dps = dps, weight = specData.weaponDPSWeight, contribution = weaponScore }
        else
            result.weapon = { note = "GearScout could not read this weapon's damage per second yet. Hover it once in game, then check again." }
        end
    end

    -- Tier 2.
    local armorFraction, armorNote = GetArmorTierPenalty(itemID, classFile, level)
    local total = rawTotal + weaponScore
    if armorFraction then
        total = total * (1 - armorFraction)
        result.armorPenalty = { fraction = armorFraction, note = armorNote }
    end
    result.total = total

    if slotID then
        result.slotID = slotID
        if not equippedLink then
            result.equippedTotal = 0
            result.delta = total
        else
            local equippedTotal = ns.ScoreItem(equippedLink, { class = classFile, tab = tab }, slotID) or 0
            result.equippedTotal = equippedTotal
            result.delta = total - equippedTotal
        end
        if not result.verdict then
            result.verdict, result.verdictText = VerdictSentence(result.delta, equippedLink, result.equippedTotal)
        end
    elseif not result.verdict then
        result.verdict = "no slot"
        result.verdictText = "GearScout does not know which equipment slot that item goes in yet, so it cannot be compared to what you have equipped."
    end

    -- Too few talent points to name a spec from. The item is still scored,
    -- with the deepest tree, because a number with a caveat is more use than
    -- no number, but the caveat travels with it and every other tree of the
    -- class is scored alongside so a caller can show all of them instead of
    -- presenting one guess as the answer.
    --
    -- None of this runs for a character who has actually committed to a
    -- tree, and a blocking problem is the whole answer on its own, so
    -- neither the extra scoring nor the extra sentence happens there.
    if result.specUncertain and result.verdict ~= "blocked" then
        result.specNote = SpecUncertaintyNote(specData, tab, classFile)

        local classData = ns.STAT_WEIGHTS and ns.STAT_WEIGHTS[classFile]
        if classData then
            local alts = {}
            for otherTab = 1, 3 do
                local other = classData[otherTab]
                if other and otherTab ~= tab then
                    local score = ns.ScoreItem(link, { class = classFile, tab = otherTab }, slotID)
                    local entry = { tab = otherTab, name = other.name, total = score, confidence = other.confidence }
                    if score and slotID then
                        local equippedTotal = 0
                        if equippedLink then
                            equippedTotal = ns.ScoreItem(equippedLink, { class = classFile, tab = otherTab }, slotID) or 0
                        end
                        entry.equippedTotal = equippedTotal
                        entry.delta = score - equippedTotal
                        entry.verdict, entry.verdictText = VerdictSentence(entry.delta, equippedLink, equippedTotal)
                    end
                    alts[#alts + 1] = entry
                end
            end
            if #alts > 0 then result.alternatives = alts end
        end

        -- Folded into the verdict line as well, because a caller with room
        -- for one line only, a tooltip, would otherwise show a spec specific
        -- verdict with no hint that the spec was a guess. A caller showing
        -- specNote separately should skip it here to avoid saying it twice.
        if result.verdictText then
            result.verdictText = result.verdictText .. " " .. result.specNote
        end
    end

    if specData.confidence and specData.confidence ~= "high" and result.verdict ~= "blocked" then
        result.confidenceNote = format(
            "GearScout's data for %s is marked %s confidence, so treat this as a rough guide, not a final answer.",
            specData.name or classFile, specData.confidence)
    end

    return result
end
