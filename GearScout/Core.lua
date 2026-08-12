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
--
-- Registration is guarded. This client carries events from two different eras
-- and an event name a given build does not know throws out of RegisterEvent,
-- which would stop the rest of the file loading. A name that does not exist
-- here just means that handler never fires, and the caller gets false back so
-- it can register something else instead.
function ns:On(event, fn, unit1, unit2)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        local ok
        if unit1 and bus.RegisterUnitEvent then
            ok = pcall(bus.RegisterUnitEvent, bus, event, unit1, unit2)
        else
            ok = pcall(bus.RegisterEvent, bus, event)
        end
        if not ok then
            handlers[event] = nil
            return false
        end
    end
    list[#list + 1] = fn
    return true
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
    locale         = "enUS",     -- enUS | svSE, translates GearScout's own text only
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
    ns.InvalidateSpec()
end

-- ---------------------------------------------------------------------------
-- talent spec detection
--
-- Spec decides which stat weights judge a piece of gear and which rotation
-- profile is loaded, and the cost of getting it wrong is high: a protection
-- paladin judged as a retribution paladin is told to throw away every piece
-- of tanking gear they own. So this never just names the tab with the most
-- points, it also says how sure it is, and a caller that cannot act on a
-- guess can ask for the role instead, or list every tree, rather than
-- committing to a wrong answer.
--
-- The thresholds, and why these numbers:
--   Talents start at level 10 and pay one point per level, so a character has
--   their level minus 9 to spend, 61 of them at level 70. Every tree gates
--   its rows 5 points apart: row two opens at 5 points in that tree, row
--   three at 10, and so on up to the 41 point talent on row nine.
--   * 10 points is three rows deep. Nobody reaches that by picking up filler
--     talents on the way to somewhere else, so it is the first depth that
--     honestly means "this is the tree I am building".
--   * 21 points is past the row carrying a tree's defining talent, which is
--     as committed as a build gets before max level.
--   * A lead of 5 over the next tree is one full row of separation, enough
--     that the runner up is not one level away from taking the lead.
--   Roles are judged on a lower bar, 5 points and a lead of 3, because the
--   question is coarser and the error is more expensive. Five points in
--   Protection is a deliberate choice no damage build makes on its way
--   anywhere else, and calling a tank a damage dealer ruins every piece of
--   advice that comes after it, while confusing Marksmanship for Survival
--   changes little. Classes whose three trees all play the same role, a
--   hunter or a rogue, have their role settled by the class alone and need
--   no talent point at all.
-- ---------------------------------------------------------------------------
local SPEC_MIN_POINTS    = 10  -- three rows into one tree, the first honest commitment
local SPEC_MIN_LEAD      = 5   -- one full row clear of the runner up
local SPEC_STRONG_POINTS = 21  -- past the row that carries the tree's defining talent
local SPEC_STRONG_LEAD   = 10  -- two full rows clear of the runner up
local ROLE_MIN_POINTS    = 5   -- one full row, and no damage build spends it in a tank tree
local ROLE_MIN_LEAD      = 3

-- Seconds to wait before asking the talent API again after it answered with
-- nothing usable. Only reached during a loading screen or the first frames of
-- a login, and it stops a draw path from re-asking a broken API every frame.
local SPEC_RETRY = 1

-- Which role each talent tab plays, in the tab order the client reports,
-- which is the same order Profiles.lua and Data/Rotations.lua use. Druid tab
-- 2 covers both cat and bear; it is called melee here to match the single
-- role name Profiles.lua already gives it rather than invent a second one.
local TAB_ROLE = {
    WARRIOR = { "melee",  "melee", "tank"   },  -- Arms, Fury, Protection
    PALADIN = { "healer", "tank",  "melee"  },  -- Holy, Protection, Retribution
    HUNTER  = { "ranged", "ranged", "ranged" }, -- Beast Mastery, Marksmanship, Survival
    ROGUE   = { "melee",  "melee", "melee"  },  -- Assassination, Combat, Subtlety
    PRIEST  = { "healer", "healer", "caster" }, -- Discipline, Holy, Shadow
    SHAMAN  = { "caster", "melee", "healer" },  -- Elemental, Enhancement, Restoration
    MAGE    = { "caster", "caster", "caster" }, -- Arcane, Fire, Frost
    WARLOCK = { "caster", "caster", "caster" }, -- Affliction, Demonology, Destruction
    DRUID   = { "caster", "melee", "healer" },  -- Balance, Feral Combat, Restoration
}

-- Last resort: add up the ranks actually spent in a tab. Returns nil, not
-- zero, when not a single talent could be read, so the caller can tell "no
-- points spent" apart from "the API told me nothing".
local function CountTabRanks(tab)
    if not _G.GetNumTalents or not _G.GetTalentInfo then return nil end
    local okN, num = pcall(_G.GetNumTalents, tab)
    if not okN or type(num) ~= "number" then return nil end
    local total, read = 0, false
    for i = 1, num do
        -- classic: name, icon, tier, column, rank, maxRank
        local ok, a, _, _, _, rank = pcall(_G.GetTalentInfo, tab, i)
        if ok and type(a) == "string" and type(rank) == "number" then
            total = total + rank
            read = true
        end
    end
    if not read then return nil end
    return total
end

-- One talent tab as a name plus points spent, from either shape of
-- GetTalentTabInfo. The returns are identified by type rather than by
-- position, because the Anniversary client uses the newer shape:
--   classic: name, iconTexture, pointsSpent, fileName
--   current: id, name, description, iconTexture, pointsSpent, ...
-- Reading position three blindly hands you the description string, which is
-- what broke spec detection for every class. Points come back nil, never
-- zero, when nothing usable was returned.
local function ReadTabInfo(i)
    if not _G.GetTalentTabInfo then return nil, nil end
    local ok, a, b, c, d, e = pcall(_G.GetTalentTabInfo, i)
    if not ok then return nil, nil end
    local name, pts
    if type(a) == "string" then
        name, pts = a, c
    elseif type(a) == "number" then
        name, pts = b, e
    end
    if type(name) ~= "string" then name = nil end
    if type(pts) ~= "number" then pts = nil end
    return name, pts
end

-- How many points this character should have spent, from their own unspent
-- point count. Used only as a cross check: when the tab summary claims
-- nothing is spent and this says otherwise, the tab summary is not to be
-- trusted and the ranks get counted talent by talent instead. Returns nil
-- when the client cannot answer, which means "no opinion", not "zero".
local function ExpectedSpentPoints()
    local level = ns.playerLevel or (UnitLevel and UnitLevel("player")) or 0
    if type(level) ~= "number" or level < 10 then return 0 end
    if not _G.UnitCharacterPoints then return nil end
    local ok, unspent = pcall(_G.UnitCharacterPoints, "player")
    if not ok or type(unspent) ~= "number" then return nil end
    local spent = (level - 9) - unspent
    if spent < 0 then return nil end
    return spent
end

-- The cached answer. One table, reused, because this is read from draw paths
-- and from row fill functions that run while a list is scrolling.
local specInfo = {
    tabs = {},          -- [tabIndex] = { name, points }
    tab = 1,            -- deepest tab, 1 when nothing is known
    name = nil,
    points = 0,         -- points in that tab
    total = 0,          -- points spent across every tab
    lead = 0,           -- how far ahead of the runner up
    confidence = "none",-- none | low | medium | high
    role = nil,
    roleConfidence = "none",
    rolePoints = 0,
    roleFromClass = false, -- true when the class settles the role on its own
    numTabs = 0,
}
local specDirty, specRetryAt, specTabCount = true, 0, 0
local roleOrder, rolePoints = {}, {}

local function ComputeSpec()
    local info = specInfo
    local tabs = info.tabs

    local classFile = ns.playerClass
    if not classFile and UnitClass then
        classFile = select(2, UnitClass("player"))
    end
    info.class = classFile

    local numTabs = 3
    if _G.GetNumTalentTabs then
        local ok, n = pcall(_G.GetNumTalentTabs)
        if ok and type(n) == "number" and n > 0 then numTabs = n end
    end

    local readable, total = false, 0
    for i = 1, numTabs do
        local rec = tabs[i]
        if not rec then rec = {}; tabs[i] = rec end
        local name, pts = ReadTabInfo(i)
        if not pts then pts = CountTabRanks(i) end
        rec.name = name
        rec.points = pts or 0
        if pts then readable = true end
        total = total + rec.points
    end
    for i = numTabs + 1, specTabCount do tabs[i] = nil end
    specTabCount = numTabs
    info.numTabs = numTabs

    -- Cross check. The tab summary can come back all zeroes on this hybrid
    -- client while points really are spent, and "no talents" is exactly the
    -- answer that would send every caller down the wrong path, so it is the
    -- one answer worth paying to verify.
    if total == 0 then
        local spent = ExpectedSpentPoints()
        if spent and spent > 0 then
            local recount = 0
            for i = 1, numTabs do
                local p = CountTabRanks(i)
                if p then tabs[i].points = p; recount = recount + p end
            end
            if recount > 0 then total, readable = recount, true end
        end
    end

    -- Deepest tab and the runner up. A tie leaves the earlier tab in front,
    -- which keeps the answer stable between calls, and the lead of zero it
    -- produces is what stops anything committing to it.
    local bestIdx, bestPts, secondPts = 1, -1, -1
    for i = 1, numTabs do
        local p = tabs[i].points
        if p > bestPts then
            secondPts = bestPts
            bestPts, bestIdx = p, i
        elseif p > secondPts then
            secondPts = p
        end
    end
    if bestPts < 0 then bestPts = 0 end
    if secondPts < 0 then secondPts = 0 end

    local lead = bestPts - secondPts
    info.tab    = bestIdx
    info.name   = tabs[bestIdx] and tabs[bestIdx].name or nil
    info.points = bestPts
    info.total  = total
    info.lead   = lead

    if total <= 0 then
        info.confidence = "none"
    elseif bestPts >= SPEC_STRONG_POINTS and lead >= SPEC_STRONG_LEAD then
        info.confidence = "high"
    elseif bestPts >= SPEC_MIN_POINTS and lead >= SPEC_MIN_LEAD then
        info.confidence = "medium"
    else
        info.confidence = "low"
    end

    -- Role. Answered separately, and on the lower bar above, because a
    -- caller that only needs tank from healer from damage can act on it far
    -- earlier than anything can act on a tree name.
    info.role, info.roleConfidence, info.rolePoints = nil, "none", 0
    info.roleFromClass = false
    local roleMap = TAB_ROLE[classFile or ""]
    if roleMap then
        local uniform = roleMap[1] ~= nil
        for i = 2, numTabs do
            if roleMap[i] ~= roleMap[1] then uniform = false; break end
        end
        if uniform then
            -- Every tree of this class plays the same role, so the class
            -- alone settles it and no talent point is needed. roleFromClass
            -- says so, because "your class decides this" and "your talents
            -- decided this" are worth wording differently to a player.
            info.role, info.roleConfidence, info.rolePoints = roleMap[1], "high", total
            info.roleFromClass = true
        elseif total > 0 then
            wipe(rolePoints)
            wipe(roleOrder)
            for i = 1, numTabs do
                local r = roleMap[i]
                if r then
                    if rolePoints[r] == nil then
                        roleOrder[#roleOrder + 1] = r
                        rolePoints[r] = 0
                    end
                    rolePoints[r] = rolePoints[r] + tabs[i].points
                end
            end

            -- Walked in tab order rather than with pairs, so a tie always
            -- resolves the same way instead of following table order.
            local bestRole, bestRolePts, secondRolePts = nil, -1, -1
            for i = 1, #roleOrder do
                local p = rolePoints[roleOrder[i]]
                if p > bestRolePts then
                    secondRolePts = bestRolePts
                    bestRole, bestRolePts = roleOrder[i], p
                elseif p > secondRolePts then
                    secondRolePts = p
                end
            end
            if bestRolePts < 0 then bestRolePts = 0 end
            if secondRolePts < 0 then secondRolePts = 0 end

            local roleLead = bestRolePts - secondRolePts
            info.role = bestRole
            info.rolePoints = bestRolePts
            if bestRolePts >= SPEC_MIN_POINTS and roleLead >= SPEC_MIN_LEAD then
                info.roleConfidence = "high"
            elseif bestRolePts >= ROLE_MIN_POINTS and roleLead >= ROLE_MIN_LEAD then
                info.roleConfidence = "medium"
            else
                info.roleConfidence = "low"
            end
        end
    end

    return readable
end

-- The whole picture, cached until something actually changes it. The table
-- is reused between calls, so read it and move on; do not hold a reference
-- and do not write to it.
--
-- Fields: tab, name, points, total, lead, confidence, role, roleConfidence,
-- rolePoints, numTabs, class, and tabs[i] = { name, points } for every tab,
-- which is what a caller shows when confidence is too low to pick one.
function ns.GetSpecInfo()
    if specDirty then
        local now = (GetTime and GetTime()) or 0
        if now >= specRetryAt then
            if ComputeSpec() then
                specDirty = false
            else
                -- Nothing usable came back, so the answer is still pending
                -- rather than settled. Try again shortly, not next frame.
                specRetryAt = now + SPEC_RETRY
            end
        end
    end
    return specInfo
end

-- Throw the cached answer away. Called on the events that can change it, and
-- safe to call from anywhere: the work happens on the next read, not here.
function ns.InvalidateSpec()
    specDirty, specRetryAt = true, 0
end

-- Talent tab with the most points. The first three returns are unchanged
-- from before confidence existed, so older callers keep working; confidence
-- and role are added on the end for callers that would rather show every
-- tree than commit to a wrong one.
function ns.GetSpec()
    local info = ns.GetSpecInfo()
    return info.name, info.tab, info.points, info.confidence, info.role
end

-- Role first, for anything that only needs tank from healer from damage.
-- This is settled earlier, and stays right longer, than the tree name.
function ns.GetSpecRole()
    local info = ns.GetSpecInfo()
    return info.role, info.roleConfidence
end

-- True when enough points are spent to name one tree and mean it. A caller
-- getting false should show every spec, or fall back to the role, instead of
-- presenting one tree as the answer.
function ns.SpecIsCertain()
    local c = ns.GetSpecInfo().confidence
    return c == "medium" or c == "high"
end

ns:On("CHARACTER_POINTS_CHANGED", ns.InvalidateSpec)
ns:On("PLAYER_ENTERING_WORLD", ns.InvalidateSpec)
-- Present on the newer engine this client is really running on, absent on
-- some builds. ns:On swallows an unknown event name, so trying costs nothing.
ns:On("PLAYER_TALENT_UPDATE", ns.InvalidateSpec)
ns:On("ACTIVE_TALENT_GROUP_CHANGED", ns.InvalidateSpec)

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
    -- A new level is a new talent point, which moves both the spent point
    -- total and the bar the confidence check is measured against.
    ns.InvalidateSpec()
end)

-- ---------------------------------------------------------------------------
-- subject
-- Whose data the window is drawing. Normally the player's own, but the officer
-- console can point it at a decoded report from someone else. Every drawing
-- path reads through here, so there is exactly one place that decides this and
-- no screen can end up half showing two different people.
--
-- The self case reuses one table rather than building a fresh one, because
-- this is called from row fill functions that run while a list is scrolling.
-- ---------------------------------------------------------------------------
local selfSubject = { isSelf = true }

ns.subject = nil   -- nil means the player themselves

function ns.Subject()
    if ns.subject then return ns.subject end
    selfSubject.name   = ns.playerName
    selfSubject.class  = ns.playerClass
    selfSubject.level  = ns.playerLevel
    selfSubject.report = ns.lastReport
    selfSubject.scan   = ns.lastScan
    selfSubject.fights = ns.GetFights and ns.GetFights() or nil
    return selfSubject
end

-- Passing nil hands the window back to the player. The officer console calls
-- that on close, so nobody is left staring at a stale roster entry.
function ns.SetSubject(s)
    ns.subject = s
    ns:Emit("SUBJECT_CHANGED")
end

function ns.SubjectIsSelf()
    return ns.subject == nil
end

-- Public handle. GearScout_Lead reaches the shared code through this table and
-- through nothing else, which keeps the two addons independently installable.
_G.GearScout = ns
