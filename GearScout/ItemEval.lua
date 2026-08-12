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
--
-- specKey is optional everywhere it appears. Pass nil to mean "the character
-- currently logged in, in their current talent spec". Pass a table shaped
-- like { class = "PALADIN", tab = 2 } to score for a different spec, for
-- example when a raid lead is checking gear for someone else's class.
--
-- Caps come first. Whether a mandatory cap, like a tank's defense skill, is
-- currently met is always checked before any stat comparison is trusted,
-- because nothing else matters until a missed mandatory cap is fixed.
--
-- A stat that has already passed its cap is worth only a small fraction of
-- its normal weight for the rest of that comparison, not full value and not
-- zero, matching how the caps in Data/StatWeights.lua actually behave.
--
-- Every stat lookup goes through ns.GetStats, the cached wrapper Scan.lua
-- already exposes for the C_Item.GetItemStats shim. Nothing in this file
-- calls GetItemStats or C_Item.GetItemStats directly, and nothing here is
-- wired into a refresh or OnUpdate path, so the API is only ever touched
-- once per item id and the result is kept from then on.

local ADDON, ns = ...

local CreateFrame, UIParent = CreateFrame, UIParent
local GetInventoryItemLink = GetInventoryItemLink
local UnitClass = UnitClass
local pairs, ipairs, type, tonumber, tostring = pairs, ipairs, type, tonumber, tostring
local format = string.format

-- How much of a stat's weight survives once the character is already past
-- that stat's cap. Not zero, because a hair over a soft cap should not read
-- identically to wildly over it, but small enough that it never outweighs an
-- uncapped stat of the same size.
local OVERCAP_FACTOR = 0.05

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
local function ResolveSpecKey(specKey)
    if type(specKey) == "table" and specKey.class then
        return specKey.class, tonumber(specKey.tab) or 1
    end
    if type(specKey) == "string" then
        local classFile, tab = specKey:match("^(%u+):(%d+)$")
        if classFile then return classFile, tonumber(tab) end
    end

    local classFile = ns.playerClass or select(2, UnitClass("player"))
    local tab = 1
    if ns.GetSpec then
        local _, bestIdx = ns.GetSpec()
        tab = bestIdx or 1
    end
    return classFile, tab
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
-- ---------------------------------------------------------------------------
function ns.ScoreItem(itemLinkOrId, specKey, excludeSlotID)
    local link, itemID = NormalizeItem(itemLinkOrId)
    if not itemID then
        return nil, "That is not a recognisable item.", nil
    end

    local classFile, tab = ResolveSpecKey(specKey)
    local specData = GetSpecData(classFile, tab)
    if not specData then
        return nil, NoDataReason(classFile, tab), "low"
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

    return score, nil, specData.confidence
end

-- ---------------------------------------------------------------------------
-- equip slot lookup, for CompareToEquipped
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

-- ---------------------------------------------------------------------------
-- ns.GetCapStatus(specKey)
-- Returns a list of caps for the given spec, each entry saying whether the
-- character currently meets it. Entries whose cap has no fixed rating
-- number, because the research only gave a rule of thumb rather than a hard
-- number, come back with measurable = false and no met value; the
-- explanation still tells the player what to look at.
-- ---------------------------------------------------------------------------
function ns.GetCapStatus(specKey)
    local classFile, tab = ResolveSpecKey(specKey)
    local specData = GetSpecData(classFile, tab)
    if not specData then
        return nil, NoDataReason(classFile, tab)
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
    return results, specData.confidence
end

-- ---------------------------------------------------------------------------
-- ns.CompareToEquipped(itemLinkOrId)
-- Always uses the character currently logged in and their current talent
-- spec. Returns delta, explanation. delta is nil when the item or the
-- character's spec could not be scored at all; the explanation says why.
-- ---------------------------------------------------------------------------
function ns.CompareToEquipped(itemLinkOrId)
    local link, itemID = NormalizeItem(itemLinkOrId)
    if not itemID then
        return nil, "That is not a recognisable item, so GearScout cannot compare it to anything."
    end

    local classFile, tab = ResolveSpecKey(nil)
    local specData = GetSpecData(classFile, tab)
    if not specData then
        return nil, NoDataReason(classFile, tab)
    end

    local meta = ns.GetItemMeta and ns.GetItemMeta(itemID)
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

    local pieces = {}
    if not equippedLink then
        pieces[#pieces + 1] = "That slot is currently empty, so equipping this item is a straight upgrade over nothing."
    elseif delta > 0.05 then
        local pct
        if equippedScore > 0 then
            pct = (delta / equippedScore) * 100
        end
        if pct and pct >= 15 then
            pieces[#pieces + 1] = "This is a clear upgrade over what you have equipped there now."
        elseif pct and pct < 5 then
            pieces[#pieces + 1] = "This is a small upgrade, more of a sidegrade than a real improvement."
        else
            pieces[#pieces + 1] = "This is an upgrade over what you have equipped there now."
        end
    elseif delta < -0.05 then
        pieces[#pieces + 1] = "This is a downgrade from what you already have equipped there."
    else
        pieces[#pieces + 1] = "This is about the same as what you already have equipped there."
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
