-- GearScout / API.lua
-- A small, stable, read only surface for other addons and for WeakAuras.
--
-- Everything here returns plain numbers, strings and fresh tables. Nothing
-- returns an internal table, so a badly written WeakAura cannot corrupt the
-- addon's own state by editing what it was handed.
--
-- WeakAuras cannot see addon locals, only globals, so the entry point is the
-- global GearScout table. A custom trigger looks like this:
--
--   function()
--       local api = GearScout and GearScout.API
--       if not api then return false end
--       return api.GetMissingBuffCount() > 0
--   end
--
-- and a custom text display like this:
--
--   function()
--       local api = GearScout and GearScout.API
--       if not api then return "" end
--       local score, grade = api.GetScore()
--       return grade .. "  " .. score
--   end

local ADDON, ns = ...

local API = {}
ns.API = API

API.VERSION = 1   -- bump only on a breaking change to a signature below

function API.GetAddonVersion()
    return ns.VERSION
end

-- ---------------------------------------------------------------------------
-- gear
-- ---------------------------------------------------------------------------

-- score (0 to 100), grade letter
function API.GetScore()
    local r = ns.lastReport
    if not r then return 0, "-" end
    return r.score or 0, r.grade or "-"
end

-- { missingEnchants, emptySockets, emptySlots, avgIlvl }
function API.GetGearCounts()
    local r = ns.lastReport
    if not r then return { missingEnchants = 0, emptySockets = 0, emptySlots = 0, avgIlvl = 0 } end
    local c = r.counts or {}
    return {
        missingEnchants = c.missingEnchants or 0,
        emptySockets    = c.emptySockets or 0,
        emptySlots      = c.emptySlots or 0,
        avgIlvl         = r.avgIlvl or 0,
    }
end

-- Up to `limit` issues, most severe first, as flat tables.
function API.GetIssues(limit)
    local out = {}
    local r = ns.lastReport
    if not r or not r.issues then return out end
    limit = limit or #r.issues
    for i = 1, math.min(limit, #r.issues) do
        local it = r.issues[i]
        out[i] = {
            severity = it.sev,       -- 1 critical, 2 warning, 3 note
            title    = it.title,
            detail   = it.detail,
            fix      = it.fix,
            slot     = it.label,
        }
    end
    return out
end

function API.GetCriticalCount()
    local r = ns.lastReport
    if not r or not r.issues then return 0 end
    local n = 0
    for _, it in ipairs(r.issues) do
        if it.sev == ns.SEVERITY.CRITICAL then n = n + 1 end
    end
    return n
end

-- ---------------------------------------------------------------------------
-- rotation
-- ---------------------------------------------------------------------------

-- Flat summary of the most recent recorded fight, or nil if there is none.
function API.GetLastFight()
    local fights = ns.GetFights and ns.GetFights()
    local f = fights and fights[1]
    if not f then return nil end

    local crit = 0
    for _, x in ipairs(f.findings or {}) do
        if x.sev == ns.SEVERITY.CRITICAL then crit = crit + 1 end
    end

    return {
        duration      = f.dur or 0,
        target        = f.target,
        spec          = f.spec,
        casts         = f.casts or 0,
        castsPerMin   = f.cpm or 0,
        idleFraction  = f.deadPct or 0,
        petUptime     = f.petUptime,
        damagePerSec  = f.dps,
        problemCount  = #(f.findings or {}),
        criticalCount = crit,
    }
end

-- Problems from the last fight, as flat tables.
function API.GetLastFightIssues(limit)
    local out = {}
    local fights = ns.GetFights and ns.GetFights()
    local f = fights and fights[1]
    if not f or not f.findings then return out end
    limit = limit or #f.findings
    for i = 1, math.min(limit, #f.findings) do
        local x = f.findings[i]
        out[i] = {
            severity = x.sev,
            title    = x.title,
            detail   = x.detail,
            fix      = x.fix,
            fraction = x.pct,
        }
    end
    return out
end

function API.GetSpec()
    local p = ns.activeProfile
    if not p then return nil end
    return p.name, p.role
end

-- ---------------------------------------------------------------------------
-- group buffs
-- ---------------------------------------------------------------------------

function API.GetMissingBuffCount()
    if not ns.GetMissingGroupBuffs then return 0 end
    return #ns.GetMissingGroupBuffs()
end

-- Array of { label, why, from }
function API.GetMissingBuffs()
    local out = {}
    if not ns.GetMissingGroupBuffs then return out end
    for i, b in ipairs(ns.GetMissingGroupBuffs()) do
        out[i] = { label = b.label, why = b.why, from = b.from }
    end
    return out
end

-- ---------------------------------------------------------------------------
-- coaching tips for the current class and spec
-- ---------------------------------------------------------------------------
function API.GetTips()
    if not ns.GetTips then return {} end
    local src = ns.GetTips()
    local out = {}
    for i = 1, #src do out[i] = src[i] end
    return out
end

-- ---------------------------------------------------------------------------
-- events, so a WeakAura can react instead of polling every frame
--
--   GEARSCOUT_GEAR_UPDATED       fires after a gear scan is analysed
--   GEARSCOUT_FIGHT_RECORDED     fires when a fight report is finished
--
-- Trigger on the custom event of the same name in WeakAuras.
-- ---------------------------------------------------------------------------
ns:Sub("SCAN_UPDATED", function()
    if _G.WeakAuras and _G.WeakAuras.ScanEvents then
        _G.WeakAuras.ScanEvents("GEARSCOUT_GEAR_UPDATED", true)
    end
end)

ns:Sub("ROTATION_UPDATED", function()
    if _G.WeakAuras and _G.WeakAuras.ScanEvents then
        _G.WeakAuras.ScanEvents("GEARSCOUT_FIGHT_RECORDED", true)
    end
end)
