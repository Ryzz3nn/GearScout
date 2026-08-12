-- GearScout / Core.lua
-- Namespace, theme, event bus, scheduling helpers, item cache, saved variables.
-- No external libraries. Everything here is upvalued and allocation free on hot paths.

local ADDON, ns = ...

-- ---------------------------------------------------------------------------
-- upvalues
-- ---------------------------------------------------------------------------
local CreateFrame, UIParent = CreateFrame, UIParent
local C_Timer = C_Timer
local GetItemInfo, GetTime = GetItemInfo, GetTime
local UnitClass, UnitGUID, UnitLevel = UnitClass, UnitGUID, UnitLevel
local type, pairs, ipairs, select = type, pairs, ipairs, select
local floor, max, min = math.floor, math.max, math.min

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

ns.ADDON   = ADDON
ns.VERSION = (GetMeta and GetMeta(ADDON, "Version")) or "1.0.0"
ns.PREFIX  = "GearScout"          -- addon message prefix, 9 chars, limit is 16

-- ---------------------------------------------------------------------------
-- theme
-- Flat panels with hairline borders. Deliberately avoids the Backdrop API,
-- which has changed shape between clients and drags a template dependency in.
-- ---------------------------------------------------------------------------
ns.T = {
    bg       = { 0.043, 0.051, 0.063, 0.97 },
    panel    = { 0.078, 0.090, 0.110, 1 },
    raised   = { 0.118, 0.133, 0.157, 1 },
    hover    = { 0.165, 0.184, 0.216, 1 },
    line     = { 1, 1, 1, 0.06 },
    lineHard = { 1, 1, 1, 0.14 },
    text     = { 0.902, 0.918, 0.949, 1 },
    dim      = { 0.541, 0.580, 0.651, 1 },
    accent   = { 0.302, 0.639, 1.000, 1 },
    good     = { 0.278, 0.816, 0.416, 1 },
    warn     = { 1.000, 0.741, 0.180, 1 },
    bad      = { 1.000, 0.373, 0.341, 1 },
}

ns.SEVERITY = { CRITICAL = 1, WARN = 2, INFO = 3 }
ns.SEV_COLOR = { ns.T.bad, ns.T.warn, ns.T.accent }
ns.SEV_LABEL = { "Critical", "Warning", "Note" }

-- ---------------------------------------------------------------------------
-- output
-- ---------------------------------------------------------------------------
local TAG = "|cff4da3ffGearScout|r: "
function ns.Print(...)
    print(TAG .. strjoin(" ", tostringall(...)))
end

function ns.Color(c, text)
    return format("|cff%02x%02x%02x%s|r", c[1] * 255, c[2] * 255, c[3] * 255, text)
end

-- ---------------------------------------------------------------------------
-- event bus
-- One frame for the whole addon. Unit filtered events go through
-- RegisterUnitEvent so the client drops other units before Lua ever runs.
-- ---------------------------------------------------------------------------
local bus = CreateFrame("Frame")
local handlers = {}

bus:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        list[i](...)
    end
end)

-- ns:On("UNIT_SPELLCAST_SUCCEEDED", fn, "player") registers a C side unit filter.
function ns:On(event, fn, unit1, unit2)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        if unit1 and bus.RegisterUnitEvent then
            bus:RegisterUnitEvent(event, unit1, unit2)
        else
            bus:RegisterEvent(event)
        end
    end
    list[#list + 1] = fn
end

-- internal pub/sub, used so UI files never poll for state changes
local subs = {}
function ns:Sub(msg, fn)
    local list = subs[msg]
    if not list then list = {}; subs[msg] = list end
    list[#list + 1] = fn
end

function ns:Emit(msg, ...)
    local list = subs[msg]
    if not list then return end
    for i = 1, #list do
        list[i](...)
    end
end

-- ---------------------------------------------------------------------------
-- scheduling
-- ---------------------------------------------------------------------------

-- Trailing edge debounce. Equipment change events fire once per swapped slot,
-- so a full re-scan per event would run up to 17 times for one gear set change.
function ns.Debounce(delay, fn)
    local scheduled = false
    return function()
        if scheduled then return end
        scheduled = true
        C_Timer.After(delay, function()
            scheduled = false
            fn()
        end)
    end
end

-- Defer work out of combat. Anything cosmetic can wait for the pull to end.
local deferred = {}
function ns.RunSafe(fn)
    if InCombatLockdown() then
        deferred[#deferred + 1] = fn
    else
        fn()
    end
end

ns:On("PLAYER_REGEN_ENABLED", function()
    if #deferred == 0 then return end
    for i = 1, #deferred do deferred[i]() end
    wipe(deferred)
end)

-- ---------------------------------------------------------------------------
-- saved variables
-- ---------------------------------------------------------------------------
ns.defaults = {
    skin           = "obsidian", -- obsidian | slate, slate is the original flat look
    dataSource     = "research", -- research | builtin, builtin is the hand written fallback
    tooltip        = true,       -- add drop source and score lines to item tooltips
    respondTo      = "leaders",  -- leaders | guild | anyone | nobody
    shareRotation  = true,
    autoScan       = true,
    showMinimap    = true,
    minimapAngle   = 202,
    ilvlSlack      = 12,         -- an item this far under your median is flagged
    rotationFights = 10,         -- how many fights to keep
    window         = {},
}

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Swaps the colour palette and tells the widget kit whether to draw rounded
-- corners. The table is mutated in place rather than replaced, because every
-- file captured `local T = ns.T` when it loaded and replacing the table would
-- leave all of them pointing at the old colours.
function ns.ApplySkin(name)
    local pal
    if name == "obsidian" and ns.Skin and ns.Skin.OBSIDIAN then
        pal = ns.Skin.OBSIDIAN
    else
        pal = ns.SLATE
        name = "slate"
    end
    if pal then
        for k, v in pairs(pal) do ns.T[k] = v end
    end
    if ns.UI then
        ns.UI.useRounded = (name == "obsidian") and (ns.Skin ~= nil)
    end
    ns.activeSkin = name
end

ns:On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    GearScoutDB = GearScoutDB or {}
    GearScoutCharDB = GearScoutCharDB or {}
    CopyDefaults(ns.defaults, GearScoutDB)
    ns.db = GearScoutDB
    ns.cdb = GearScoutCharDB

    -- Snapshot the original flat palette first so the skin can be reverted.
    if not ns.SLATE then
        ns.SLATE = {}
        for k, v in pairs(ns.T) do ns.SLATE[k] = v end
    end
    ns.ApplySkin(ns.db.skin)

    ns:Emit("DB_READY")
end)

-- ---------------------------------------------------------------------------
-- player identity
-- ---------------------------------------------------------------------------
function ns.RefreshPlayer()
    local _, classFile = UnitClass("player")
    ns.playerClass = classFile
    ns.playerGUID  = UnitGUID("player")
    ns.playerLevel = UnitLevel("player")
    local name, realm = UnitFullName("player")
    ns.playerName = name
    ns.playerRealm = (realm and realm ~= "") and realm or GetRealmName()
    ns.playerFull = ns.playerName .. "-" .. (ns.playerRealm or ""):gsub("%s+", "")
end

-- Last resort: add up the ranks actually spent in a tab.
local function CountTabRanks(tab)
    if not _G.GetNumTalents or not _G.GetTalentInfo then return nil end
    local okN, num = pcall(_G.GetNumTalents, tab)
    if not okN or type(num) ~= "number" then return nil end
    local total = 0
    for i = 1, num do
        -- classic: name, icon, tier, column, rank, maxRank
        local ok, a, _, _, _, rank = pcall(_G.GetTalentInfo, tab, i)
        if ok and type(a) == "string" and type(rank) == "number" then
            total = total + rank
        end
    end
    return total
end

-- Talent tab with the most points. Locale safe, works without any spec API.
--
-- GetTalentTabInfo comes in two shapes and the Anniversary client uses the
-- newer one, so the returns are identified by type rather than by position:
--   classic: name, iconTexture, pointsSpent, fileName
--   current: id, name, description, iconTexture, pointsSpent, ...
-- Reading position three blindly hands you the description string, which is
-- what broke spec detection for every class.
function ns.GetSpec()
    local bestName, bestPts, bestIdx = nil, -1, 1

    local numTabs = 3
    if _G.GetNumTalentTabs then
        local ok, n = pcall(_G.GetNumTalentTabs)
        if ok and type(n) == "number" and n > 0 then numTabs = n end
    end

    if _G.GetTalentTabInfo then
        for i = 1, numTabs do
            local ok, a, b, c, d, e = pcall(_G.GetTalentTabInfo, i)
            if ok then
                local name, pts
                if type(a) == "string" then
                    name, pts = a, c
                elseif type(a) == "number" then
                    name, pts = b, e
                end
                if type(pts) ~= "number" then
                    pts = CountTabRanks(i)
                end
                if type(pts) == "number" and pts > bestPts then
                    bestName, bestPts, bestIdx = name, pts, i
                end
            end
        end
    end

    return bestName, bestIdx, (bestPts >= 0 and bestPts or 0)
end

-- ---------------------------------------------------------------------------
-- item metadata cache
-- GetItemInfo returns nil for anything the client has not cached yet. Equipped
-- items are always cached, but items seen through the lead console may not be,
-- so misses are queued and resolved on GET_ITEM_INFO_RECEIVED.
-- ---------------------------------------------------------------------------
local itemCache = {}
local itemPending = {}
ns.itemCache = itemCache

function ns.GetItemMeta(key)
    if not key then return nil end
    local cached = itemCache[key]
    if cached then return cached end

    local name, link, quality, ilvl, _, _, subType, _, equipLoc, icon = GetItemInfo(key)
    if not name then
        if type(key) == "number" then itemPending[key] = true end
        return nil
    end

    local meta = {
        name     = name,
        link     = link,
        quality  = quality,
        ilvl     = ilvl,
        subType  = subType,
        equipLoc = equipLoc,
        icon     = icon,
    }
    itemCache[key] = meta
    return meta
end

ns:On("GET_ITEM_INFO_RECEIVED", function(itemID)
    if not itemID or not itemPending[itemID] then return end
    itemPending[itemID] = nil
    ns.GetItemMeta(itemID)
    ns:Emit("ITEM_CACHE_UPDATED", itemID)
end)

-- ---------------------------------------------------------------------------
-- spell API shims
--
-- The Anniversary client reports interface 20506 but runs on the current
-- engine, where the spell functions moved under C_Spell and C_SpellBook and
-- several globals (GetSpellBookItemName, BOOKTYPE_SPELL) no longer exist.
-- Everything spell related goes through these two helpers so a missing global
-- degrades instead of throwing.
-- ---------------------------------------------------------------------------
local spellNameCache = {}
local spellIconCache = {}

function ns.SpellName(id)
    if not id then return nil end
    local cached = spellNameCache[id]
    if cached ~= nil then
        if cached == false then return nil end
        return cached, spellIconCache[id]
    end

    local name, icon
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" then
            name, icon = info.name, info.iconID
        end
    end
    if not name and _G.GetSpellInfo then
        local ok, n, _, ic = pcall(_G.GetSpellInfo, id)
        if ok and n then name, icon = n, ic end
    end

    spellNameCache[id] = name or false
    spellIconCache[id] = icon
    return name, icon
end

function ns.SpellKnown(id)
    if not id then return false end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
        if ok and known then return true end
    end
    if _G.IsSpellKnown then
        local ok, known = pcall(_G.IsSpellKnown, id)
        if ok and known then return true end
    end
    if _G.IsPlayerSpell then
        local ok, known = pcall(_G.IsPlayerSpell, id)
        if ok and known then return true end
    end
    return false
end

-- Aura lookup. C_UnitAuras is present on this client and UnitAura is on its
-- way out, so the new path is tried first. The PLAYER filter makes the client
-- return only auras this character applied, which is exactly what uptime
-- coaching needs.
local GetAuraByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex

function ns.GetAuraName(unit, index, filter)
    if GetAuraByIndex then
        local data = GetAuraByIndex(unit, index, filter)
        if not data then return nil end
        return data.name
    end
    if _G.UnitAura then
        return (_G.UnitAura(unit, index, filter))
    end
    return nil
end

ns.hasAuraAPI = (GetAuraByIndex ~= nil) or (_G.UnitAura ~= nil)

-- Which path is actually live, for the diagnostic command.
function ns.SpellAPIReport()
    return format("C_Spell.GetSpellInfo:%s GetSpellInfo:%s C_SpellBook.IsSpellKnown:%s IsSpellKnown:%s IsPlayerSpell:%s",
        (C_Spell and C_Spell.GetSpellInfo) and "yes" or "no",
        _G.GetSpellInfo and "yes" or "no",
        (C_SpellBook and C_SpellBook.IsSpellKnown) and "yes" or "no",
        _G.IsSpellKnown and "yes" or "no",
        _G.IsPlayerSpell and "yes" or "no")
end

-- ---------------------------------------------------------------------------
-- small shared helpers
-- ---------------------------------------------------------------------------
function ns.Clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

function ns.Round(v)
    return floor(v + 0.5)
end

function ns.FmtTime(sec)
    if sec < 60 then return format("%.0fs", sec) end
    return format("%d:%02d", floor(sec / 60), floor(sec % 60))
end

function ns.ClassColor(classFile)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return ns.T.text[1], ns.T.text[2], ns.T.text[3]
end

function ns.Grade(score)
    if score >= 90 then return "A", ns.T.good end
    if score >= 80 then return "B", ns.T.good end
    if score >= 70 then return "C", ns.T.warn end
    if score >= 55 then return "D", ns.T.warn end
    return "F", ns.T.bad
end

ns:On("PLAYER_LOGIN", ns.RefreshPlayer)
ns:On("PLAYER_LEVEL_UP", function(level)
    ns.playerLevel = level or UnitLevel("player")
end)

-- Public handle. GearScout_Lead reaches the shared code through this table and
-- through nothing else, which keeps the two addons independently installable.
_G.GearScout = ns
