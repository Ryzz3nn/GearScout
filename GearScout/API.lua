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
--
-- What your group could give you that you do not have. Three filters have
-- already been applied by the time it reaches here: the class has to actually
-- be in the group, that person has to be high enough level to have learned
-- the spell, and your current spec has to have a real use for it. A Beast
-- Mastery hunter is told about Blessing of Might and is never told about
-- Blessing of Wisdom. A Holy paladin gets the opposite answer.
--
-- Burning Crusade rules are respected, so the list stays honest: one blessing
-- per paladin, one totem per element, and totems, shouts, paladin auras and
-- the imp's Blood Pact only count when the caster is in your own subgroup.
--
-- GetBuffReport() returns a freshly built table. Nothing in it is shared with
-- the addon, so it is safe to keep and safe to edit.
--
--   {
--       inGroup  = true,            -- false when you are on your own, both lists empty
--       stamp    = 7,               -- only changes when the answer changes
--       spec     = "Beast Mastery", -- nil until the spec profile has been built
--       role     = "ranged",        -- melee, ranged, tank, healer, caster, unknown
--       count    = 2,               -- #missing, the same number GetMissingBuffCount returns
--       missing  = { entry, ... },  -- ask for these, most wanted first
--       optional = { entry, ... },  -- talent gated or fight dependent, most wanted first
--   }
--
--   entry = {
--       key         = "might",              -- stable, never localized, safe to switch on
--       label       = "Blessing of Might",  -- localized spell name, safe to print
--       spellID     = 19740,                -- the spell the label came from
--       icon        = 135906,               -- texture id, can be nil
--       why         = "Straight attack power, so every hit lands harder.",
--       from        = "Bob",                -- who in the group can cast it
--       fromClass   = "paladin",            -- lower case, reads well in a sentence
--       classFile   = "PALADIN",            -- upper case, for RAID_CLASS_COLORS
--       scope       = "raid",               -- "party" means only your own subgroup counts
--       slot        = "blessing",           -- nil, or a slot the caster can only fill once
--       talent      = false,                -- true when the caster needs a talent for it
--       situational = false,                -- true when it is only right on some fights
--       score       = 0.87,                 -- 0 to 1, how much your spec wants it
--       isSelf      = false,                -- true when you are the one who can cast it
--   }
--
-- Everything on the optional list has talent or situational set. Kings and
-- Sanctuary sit there because there is no way to tell from outside whether
-- the paladin ever spent the point. Salvation, Thorns, Shadow Protection and
-- the paladin aura check sit there because they are right on some fights and
-- wrong on others.
--
-- Two finished auras, as WeakAuras import strings, plus a step by step recipe
-- for building them by hand, live in WEAKAURA.md at the root of this project.
-- In game, /gearscout wa points at it. What follows is the short version.
--
-- A WeakAura that shows one icon per missing buff. Trigger type Custom,
-- Trigger State Updater, custom trigger event GEARSCOUT_BUFFS_UPDATED, with
-- Check On Every Frame left off so nothing polls:
--
--   function(allstates, event)
--       local api = GearScout and GearScout.API
--       if not api or not api.GetBuffReport then return false end
--       for _, state in pairs(allstates) do
--           state.show = false
--           state.changed = true
--       end
--       for _, b in ipairs(api.GetBuffReport().missing) do
--           allstates[b.key] = {
--               show = true, changed = true,
--               name = b.label, icon = b.icon,
--               caster = b.from, index = b.score,
--           }
--       end
--       return true
--   end
--
-- If a plain status trigger is easier, GetMissingBuffCount() allocates
-- nothing and is safe to check often:
--
--   function()
--       local api = GearScout and GearScout.API
--       return api ~= nil and api.GetMissingBuffCount() > 0
--   end
--
-- And to only rebuild a display when the answer has really moved, watch
-- GetBuffStamp(). It is one number and it only ever counts up:
--
--   function()
--       local api = GearScout and GearScout.API
--       return api and api.GetBuffStamp() or 0
--   end
-- ---------------------------------------------------------------------------

local function CopyBuff(b)
    return {
        key         = b.key,
        label       = b.label,
        spellID     = b.spellID,
        icon        = b.icon,
        why         = b.why,
        from        = b.from,
        fromClass   = b.fromClass,
        classFile   = b.classFile,
        scope       = b.scope,
        slot        = b.slot,
        talent      = b.talent or false,
        situational = b.situational or false,
        score       = b.score or 0,
        isSelf      = b.isSelf or false,
    }
end

local function CopyBuffList(src)
    local out = {}
    if not src then return out end
    for i = 1, #src do out[i] = CopyBuff(src[i]) end
    return out
end

-- Cheapest call in this section. Returns a number and allocates nothing.
function API.GetMissingBuffCount()
    if not ns.GetMissingGroupBuffs then return 0 end
    return #(ns.GetMissingGroupBuffs())
end

-- A number that changes only when the set of missing buffs changes. Poll this
-- instead of rebuilding a display, or trigger on GEARSCOUT_BUFFS_UPDATED and
-- do not poll at all.
function API.GetBuffStamp()
    if not ns.GetBuffStamp then return 0 end
    return ns.GetBuffStamp()
end

-- Array of entries, shape documented above. Most wanted first.
function API.GetMissingBuffs()
    if not ns.GetMissingGroupBuffs then return {} end
    local missing = ns.GetMissingGroupBuffs()
    return CopyBuffList(missing)
end

-- The talent gated and fight dependent ones, same entry shape.
function API.GetOptionalBuffs()
    if not ns.GetMissingGroupBuffs then return {} end
    local _, optional = ns.GetMissingGroupBuffs()
    return CopyBuffList(optional)
end

-- Everything in one table, shape documented above.
function API.GetBuffReport()
    local p = ns.activeProfile
    local report = {
        inGroup  = (IsInGroup() or IsInRaid()) and true or false,
        stamp    = API.GetBuffStamp(),
        spec     = p and p.name or nil,
        role     = p and p.role or nil,
        count    = 0,
        missing  = {},
        optional = {},
    }
    if not ns.GetMissingGroupBuffs then return report end

    local missing, optional = ns.GetMissingGroupBuffs()
    report.missing  = CopyBuffList(missing)
    report.optional = CopyBuffList(optional)
    report.count    = #report.missing
    return report
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
--   GEARSCOUT_BUFFS_UPDATED      fires when the set of missing group buffs
--                                changes, and only then. Gaining a buff,
--                                losing one, somebody joining or leaving, and
--                                respeccing all reach it. It is quiet the
--                                rest of the time, including through a whole
--                                fight where nothing about your buffs moved.
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

ns:Sub("BUFFS_UPDATED", function()
    if _G.WeakAuras and _G.WeakAuras.ScanEvents then
        _G.WeakAuras.ScanEvents("GEARSCOUT_BUFFS_UPDATED", true)
    end
end)
