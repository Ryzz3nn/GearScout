-- GearScout / Deaths.lua
-- Keeps a short rolling record of damage taken, then on death turns it into
-- one useful sentence: what killed you, how much of your health the last few
-- hits took, and how long the fight lasted. A capped history of past deaths
-- is kept in the per character saved variable so patterns show up over time.
--
-- Writing rule, same as Rules.lua: say what happened, why it matters, and
-- what to actually do about it. A log dump is not advice.
--
-- IMPORTANT: this file does not register COMBAT_LOG_EVENT_UNFILTERED itself.
-- Rotation.lua already runs the one and only combat log listener during
-- combat, so a second registration would double the per event cost in a
-- raid. Instead this file exposes ns.Deaths.HandleCombatLog(subevent,
-- sourceName, spellName, amount, destGUID, environmentalType), which the
-- existing listener calls for every damage subevent. See the bottom of this
-- file for the exact contract.

local ADDON, ns = ...

local GetTime, time = GetTime, time
local UnitGUID, UnitHealthMax = UnitGUID, UnitHealthMax
local GetRealZoneText = GetRealZoneText
local format, ipairs, pairs = string.format, ipairs, pairs
local max, min, floor = math.max, math.min, math.floor
local tinsert, wipe = table.insert, wipe

local SEV = ns.SEVERITY

local Deaths = {}
ns.Deaths = Deaths

-- ---------------------------------------------------------------------------
-- rolling hit history
-- A small ring buffer of recent damage taken, same shape as the cast history
-- in Rotation.lua: an absolute write counter mapped into a fixed size array,
-- so nothing ever grows or gets reallocated.
-- ---------------------------------------------------------------------------
local CAP = 40
local hitTime, hitSource, hitSpell, hitAmount, hitPct = {}, {}, {}, {}, {}
local writeIdx = 0

local STREAK_GAP = 20   -- seconds. A gap this long starts a new fight for timing purposes.

local function RecordHit(source, spellName, amount, pct)
    writeIdx = writeIdx + 1
    local slot = (writeIdx - 1) % CAP + 1
    hitTime[slot]   = GetTime()
    hitSource[slot] = source
    hitSpell[slot]  = spellName
    hitAmount[slot] = amount
    hitPct[slot]    = pct
end

-- Up to the last n recorded hits, oldest first.
local function GetRecentHits(n)
    local out = {}
    if writeIdx == 0 then return out end
    local first = max(1, writeIdx - CAP + 1)
    local from = max(first, writeIdx - n + 1)
    for i = from, writeIdx do
        local slot = (i - 1) % CAP + 1
        if hitTime[slot] then
            out[#out + 1] = {
                source = hitSource[slot], spell = hitSpell[slot],
                amount = hitAmount[slot], pct = hitPct[slot], t = hitTime[slot],
            }
        end
    end
    return out
end

-- Walks backward from the most recent hit as long as consecutive hits are no
-- more than STREAK_GAP apart, and returns how long ago the earliest hit in
-- that run happened. This is what "how long did you survive" actually means
-- for both a drawn out fight and a single instant fall.
local function ComputeSurvived(deathTime)
    if writeIdx == 0 then return nil end
    local first = max(1, writeIdx - CAP + 1)
    local earliest, prevTime = nil, nil
    for i = writeIdx, first, -1 do
        local slot = (i - 1) % CAP + 1
        local t = hitTime[slot]
        if not t then break end
        if prevTime and (prevTime - t) > STREAK_GAP then break end
        earliest = t
        prevTime = t
    end
    if not earliest then return nil end
    return max(0, deathTime - earliest)
end

-- ---------------------------------------------------------------------------
-- environmental damage labels
-- These type strings come straight from the combat log and never localise,
-- so they are safe to match on directly.
-- ---------------------------------------------------------------------------
local ENV_LABEL = {
    FALLING  = "Fall damage",
    DROWNING = "Drowning",
    FATIGUE  = "Exhaustion",
    FIRE     = "Fire",
    LAVA     = "Lava",
    SLIME    = "Slime",
}

local DAMAGE_SUBEVENTS = {
    SWING_DAMAGE = true, SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true,
    RANGE_DAMAGE = true, DAMAGE_SPLIT = true, ENVIRONMENTAL_DAMAGE = true,
}

-- ---------------------------------------------------------------------------
-- healing item check
-- Rather than hardcode item ids for every rank of potion and bandage across
-- seventy levels, this matches on the item name itself once it is cached.
-- Every rank of both consumables contains one of these two words.
-- ---------------------------------------------------------------------------
local function ForEachBagItem(callback)
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or _G.GetContainerNumSlots
    local itemID   = (C_Container and C_Container.GetContainerItemID) or _G.GetContainerItemID
    if not numSlots or not itemID then return end
    for bag = 0, 4 do
        local ok, n = pcall(numSlots, bag)
        if ok and n and n > 0 then
            for slot = 1, n do
                local ok2, id = pcall(itemID, bag, slot)
                if ok2 and id then callback(id) end
            end
        end
    end
end

local function HasHealingItem()
    local found = false
    ForEachBagItem(function(id)
        if found then return end
        local meta = ns.GetItemMeta(id)
        local name = meta and meta.name
        if name then
            local lower = name:lower()
            if lower:find("healing potion", 1, true) or lower:find("bandage", 1, true) then
                found = true
            end
        end
    end)
    return found
end

-- ---------------------------------------------------------------------------
-- defensive cooldown check
-- A small, conservative list per class of an early, well known defensive
-- cooldown. Classes with nothing reliable at low level are left out on
-- purpose rather than guessing, the same call Rules.lua makes for junk stats.
-- ---------------------------------------------------------------------------
local DEFENSIVE_BY_CLASS = {
    WARRIOR = { 871, 12975 },   -- Shield Wall, Last Stand
    PALADIN = { 642, 498 },     -- Divine Shield, Divine Protection
    ROGUE   = { 5277, 31224, 1856 }, -- Evasion, Cloak of Shadows, Vanish
    HUNTER  = { 5384 },         -- Feign Death
    MAGE    = { 45438 },        -- Ice Block
    DRUID   = { 22812 },        -- Barkskin
}

local GCD_THRESHOLD = 1.6   -- a duration this short is the global cooldown, not a real one

local function GetCooldownInfo(id)
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, id)
        if ok and type(info) == "table" then
            return info.startTime, info.duration
        end
    end
    if _G.GetSpellCooldown then
        local ok, start, duration = pcall(_G.GetSpellCooldown, id)
        if ok and start then return start, duration end
    end
    return nil, nil
end

local function IsOffCooldown(id)
    local start, duration = GetCooldownInfo(id)
    if not start or not duration then return false end
    if start == 0 then return true end
    if duration <= GCD_THRESHOLD then return true end
    return false
end

-- Name of the first known, off cooldown defensive for this class, or nil.
local function AvailableDefensive()
    local list = DEFENSIVE_BY_CLASS[ns.playerClass]
    if not list then return nil end
    for _, id in ipairs(list) do
        if ns.SpellKnown(id) and IsOffCooldown(id) then
            return ns.SpellName(id)
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- the combat log entry point
--
-- Call this from Rotation.lua's existing COMBAT_LOG_EVENT_UNFILTERED handler
-- for every damage subevent, in this order:
--
--   ns.Deaths.HandleCombatLog(subevent, sourceName, spellName, amount, destGUID, environmentalType)
--
--   subevent          the combat log subevent string, e.g. "SWING_DAMAGE"
--   sourceName        the attacker's name, nil for ENVIRONMENTAL_DAMAGE
--   spellName         the spell that hit, nil for a melee swing
--   amount            the damage amount, a number
--   destGUID          the GUID of whoever was hit
--   environmentalType the fifth ENVIRONMENTAL_DAMAGE arg ("FALLING", "DROWNING",
--                      "FATIGUE", "FIRE", "LAVA", "SLIME"), nil otherwise
--
-- This function checks destGUID against the player itself, so it is safe to
-- call for every damage event without pre-filtering by unit.
-- ---------------------------------------------------------------------------
function Deaths.HandleCombatLog(subevent, sourceName, spellName, amount, destGUID, environmentalType)
    if not DAMAGE_SUBEVENTS[subevent] then return end
    if type(amount) ~= "number" then return end
    if destGUID ~= UnitGUID("player") then return end

    local label = sourceName
    if subevent == "ENVIRONMENTAL_DAMAGE" then
        label = ENV_LABEL[environmentalType] or "Environmental damage"
    end
    label = label or "Unknown"

    local pct
    local ok, maxHealth = pcall(UnitHealthMax, "player")
    if ok and maxHealth and maxHealth > 0 then
        pct = amount / maxHealth
    end

    RecordHit(label, spellName, amount, pct)
end

-- ---------------------------------------------------------------------------
-- death handling
-- ---------------------------------------------------------------------------
local DEATH_CAP = 20

ns:On("PLAYER_DEAD", function()
    local deathTime = GetTime()
    local hits = GetRecentHits(5)
    local lastHit = hits[#hits]

    local pctSum = 0
    for _, h in ipairs(hits) do
        if h.pct then pctSum = pctSum + h.pct end
    end

    local zone = "an unknown zone"
    local okZone, z = pcall(GetRealZoneText)
    if okZone and z and z ~= "" then zone = z end

    local record = {
        when               = time(),
        zone               = zone,
        killer             = lastHit and lastHit.source or "Unknown",
        killerSpell        = lastHit and lastHit.spell or nil,
        survived           = ComputeSurvived(deathTime),
        hitsCount          = #hits,
        hitsPct            = pctSum,
        hadHealingItem     = HasHealingItem(),
        defensiveAvailable = AvailableDefensive(),
    }

    local store = ns.cdb
    if not store then return end
    store.deaths = store.deaths or {}
    tinsert(store.deaths, 1, record)
    for i = #store.deaths, DEATH_CAP + 1, -1 do
        store.deaths[i] = nil
    end

    ns:Emit("DEATH_RECORDED", record)
end)

-- ---------------------------------------------------------------------------
-- public reads
-- ---------------------------------------------------------------------------

-- Most recent death first.
function ns.GetDeaths()
    return (ns.cdb and ns.cdb.deaths) or {}
end

-- One issue style summary (sev, title, detail, fix), or nil when there is
-- nothing worth saying yet. Picks the single most useful observation rather
-- than listing every death: a repeated killer first, then an unused healing
-- item, then an available defensive cooldown, and only then a plain report
-- of the last death.
function ns.GetDeathIssue()
    local deaths = ns.GetDeaths()
    if #deaths == 0 then return nil end
    local last = deaths[1]
    local lookback = min(#deaths, 10)

    local counts = {}
    for i = 1, lookback do
        local k = deaths[i].killer
        if k and k ~= "Unknown" then
            counts[k] = (counts[k] or 0) + 1
        end
    end
    local repeatKiller, repeatCount = nil, 0
    for k, c in pairs(counts) do
        if c > repeatCount then repeatKiller, repeatCount = k, c end
    end

    if repeatKiller and repeatCount >= 2 then
        return {
            sev    = SEV.WARN,
            title  = format("You have died to %s %d times", repeatKiller, repeatCount),
            detail = format("Out of your last %d deaths, %s alone accounts for %d of them. That is a pattern, not bad luck.",
                             lookback, repeatKiller, repeatCount),
            fix    = "Before you fight it again, bring more health consumables, ask for help, or look up what makes that particular enemy dangerous.",
        }
    end

    if last.hadHealingItem then
        return {
            sev    = SEV.WARN,
            title  = "You died with a healing item still in your bags",
            detail = format("When %s killed you, you still had a healing potion or bandage on you. It was never used.", last.killer),
            fix    = "Keybind your healing potion or bandage and use it around half health, not after the fight has already gone wrong.",
        }
    end

    if last.defensiveAvailable then
        return {
            sev    = SEV.WARN,
            title  = format("%s was available when you died", last.defensiveAvailable),
            detail = format("Your %s was off cooldown when %s killed you, so it was ready to be used.", last.defensiveAvailable, last.killer),
            fix    = "Use a defensive cooldown earlier, around half health, rather than waiting to see if you will need it.",
        }
    end

    local survivedText = last.survived and format(" You lasted about %s.", ns.FmtTime(last.survived)) or ""
    local pctText = ""
    if last.hitsPct and last.hitsPct > 0 and last.hitsCount and last.hitsCount > 0 then
        pctText = format(" Your last %d hit%s took roughly %d percent of your health.",
            last.hitsCount, last.hitsCount == 1 and "" or "s",
            ns.Round(ns.Clamp(last.hitsPct, 0, 1) * 100))
    end

    return {
        sev    = SEV.INFO,
        title  = format("You last died to %s", last.killer),
        detail = format("This happened in %s.%s%s", last.zone or "an unknown zone", survivedText, pctText),
        fix    = "Nothing to fix yet. GearScout will start pointing out patterns once it has seen a few more deaths.",
    }
end
