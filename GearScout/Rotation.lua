-- GearScout / Rotation.lua
-- Records what you actually press, then compares it to what your spec should
-- be pressing.
--
-- Two separate sources of truth, because they answer different questions:
--
--   Cast events  answer "how many times did you press this". Recorded
--                continuously, never only during combat, because Hunter's
--                Mark and the opening shot both happen before the client
--                considers you to be in combat. Anything cast in the twelve
--                seconds before the pull counts towards the pull.
--
--   Aura samples answer "was it actually up". Four times a second during
--                combat the addon asks the client which of your auras are on
--                you and on your target. This is the only honest way to
--                measure uptime: it sees buffs applied before the pull, it
--                survives dispels and target swaps, and it never has to guess
--                a duration. The earlier version reconstructed uptime from
--                cast times, which is what reported a pre-pull Hunter's Mark
--                as never applied. The same sampler also reads the player's
--                primary resource, so a fight spent unable to cast because
--                the bar was empty is measured directly instead of guessed.
--
-- Uptime is judged from the player's first cast at or after the pull, not
-- from the pull itself. A hunter who lets the pet open a fight for a couple
-- of seconds has not failed to keep a debuff up during a window where they
-- had not pressed anything yet.
--
-- Cast events are unit filtered to the player and pet by the client, so no
-- combat log listener is needed for them. One is used for a single narrow
-- job: telling a dodge, parry, resist, block or immune apart from a spell
-- that was simply never cast. It is registered only while the player is in
-- combat, and bails on the very first line unless the source is the player
-- or the player's pet. Details is installed on this account, but its
-- documented API (see DetailsBridge.lua) never exports that data, so this is
-- the only source for it.

local ADDON, ns = ...

local GetTime, time = GetTime, time
local UnitName, UnitExists, UnitIsEnemy = UnitName, UnitExists, UnitIsEnemy
local UnitCanAttack, UnitIsDead = UnitCanAttack, UnitIsDead
local UnitPowerType, UnitPower, UnitPowerMax = UnitPowerType, UnitPower, UnitPowerMax
local UnitGUID = UnitGUID
local CombatLogGetCurrentEventInfo, select = CombatLogGetCurrentEventInfo, select
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local format, ipairs, pairs, wipe, type = string.format, ipairs, pairs, wipe, type

local SEV = ns.SEVERITY

-- ---------------------------------------------------------------------------
-- continuous cast recorder
-- ---------------------------------------------------------------------------
local CAP = 2048
local castTime, castName, castPet = {}, {}, {}
local writeIdx = 0

local PREPULL = 12        -- seconds before a pull that still count towards it

local function Record(name, isPet)
    writeIdx = writeIdx + 1
    local slot = (writeIdx - 1) % CAP + 1
    castTime[slot] = GetTime()
    castName[slot] = name
    castPet[slot] = isPet or false
end

-- Unit filtered by the client, so other players' casts never reach Lua.
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, arg2, arg3)
    local name
    if type(arg3) == "number" then
        name = ns.SpellName(arg3)
    elseif type(arg2) == "string" then
        name = arg2
    end
    if not name then return end
    Record(name, unit == "pet")
end, "player", "pet")

ns:On("PLAYER_TARGET_CHANGED", function()
    if UnitExists("target") and UnitIsEnemy("player", "target") then
        ns.lastHostileTarget = UnitName("target")
    end
end)

-- ---------------------------------------------------------------------------
-- miss and mitigation tracker
--
-- Details is installed, but its documented surface (API.lua) only exposes
-- outcomes that still did some damage: spell.r_amt (resisted), spell.b_amt
-- (blocked), spell.a_amt (absorbed), spell.g_amt (glancing). A full dodge,
-- parry, miss, resist or immune produces no damage line at all, and while
-- Details keeps internal DODGE / PARRY / MISS counters on its spell tables
-- (classes/class_spelltable.lua), API.lua never documents or exports them.
-- Reading them anyway would mean depending on internal shape Details never
-- promised to keep, so this section is the one and only source for that data
-- instead, built directly from the combat log.
--
-- Registered only while in combat (see the PLAYER_REGEN_DISABLED and
-- PLAYER_REGEN_ENABLED handlers below), and every event bails on the first
-- line unless it came from the player or the player's pet, so it costs
-- nothing outside a fight and very little inside one.
-- ---------------------------------------------------------------------------
local MISS_LABEL = {
    MISS    = "missed",
    DODGE   = "dodged",
    PARRY   = "parried",
    BLOCK   = "blocked",
    RESIST  = "resisted",
    IMMUNE  = "resisted",   -- an immune target did not take the effect, in plain terms that is a resist
    DEFLECT = "deflected",
    EVADE   = "evaded",
    REFLECT = "reflected",
    ABSORB  = "absorbed",
}
local MISS_ORDER = { "RESIST", "DODGE", "PARRY", "BLOCK", "MISS", "IMMUNE", "DEFLECT", "EVADE", "REFLECT", "ABSORB" }

local missCount = {}          -- [name] = { total = n, [missType] = n }
local playerGUID, petGUID

local function RecordMiss(name, missType)
    if not name or not missType then return end
    local rec = missCount[name]
    if not rec then
        rec = { total = 0 }
        missCount[name] = rec
    end
    rec.total = rec.total + 1
    rec[missType] = (rec[missType] or 0) + 1
end

local function CountWord(n)
    if n == 1 then return "once" end
    if n == 2 then return "twice" end
    return n .. " times"
end

-- Turns whatever this spell name has recorded into a plain sentence fragment,
-- for example "resisted twice and dodged once". Returns nil when there is
-- nothing recorded. This states a fact rather than a rate, so it is safe to
-- use even for a single event.
local function MissPhrase(name)
    local mc = missCount[name]
    if not mc or mc.total == 0 then return nil, 0 end
    local parts = {}
    for i = 1, #MISS_ORDER do
        local mtype = MISS_ORDER[i]
        local cnt = mc[mtype]
        if cnt and cnt > 0 then
            parts[#parts + 1] = format("%s %s", MISS_LABEL[mtype] or mtype:lower(), CountWord(cnt))
        end
    end
    if #parts == 0 then return nil, 0 end
    return table.concat(parts, " and "), mc.total
end

-- Details labels a melee swing this way in its own spell list, so the same
-- name is used here to key melee misses. See DetailsBridge.lua.
local MELEE_NAME = ns.SpellName(6603) or "Auto Attack"

-- Where the damage payload starts differs per subevent, so each shape is
-- unpacked separately rather than guessed at.
local INCOMING = {
    SWING_DAMAGE = 1,
    SPELL_DAMAGE = 2,
    SPELL_PERIODIC_DAMAGE = 2,
    RANGE_DAMAGE = 2,
    ENVIRONMENTAL_DAMAGE = 3,
}

-- One combat log listener for the whole addon. Misses need events the player
-- caused, the death log needs events aimed AT the player, so the source filter
-- cannot sit at the top of the function or deaths would never be seen.
local function OnCombatLogEvent()
    local _, subevent, _, sourceGUID, sourceName, _, _, destGUID = CombatLogGetCurrentEventInfo()

    if sourceGUID == playerGUID or sourceGUID == petGUID then
        if subevent == "SWING_MISSED" then
            local missType = select(12, CombatLogGetCurrentEventInfo())
            RecordMiss(MELEE_NAME, missType)
        elseif subevent == "SPELL_MISSED" or subevent == "RANGE_MISSED" then
            local spellId, spellName, _, missType = select(12, CombatLogGetCurrentEventInfo())
            RecordMiss(spellName or ns.SpellName(spellId), missType)
        end
    end

    -- Deaths.lua re-checks destGUID itself, but comparing here first keeps the
    -- payload unpacking off the path every unrelated event takes.
    if destGUID == playerGUID and ns.Deaths and ns.Deaths.HandleCombatLog then
        local shape = INCOMING[subevent]
        if shape == 1 then
            local amount = select(12, CombatLogGetCurrentEventInfo())
            ns.Deaths.HandleCombatLog(subevent, sourceName, MELEE_NAME, amount, destGUID)
        elseif shape == 2 then
            local spellId, spellName, _, amount = select(12, CombatLogGetCurrentEventInfo())
            ns.Deaths.HandleCombatLog(subevent, sourceName,
                spellName or ns.SpellName(spellId), amount, destGUID)
        elseif shape == 3 then
            local envType, amount = select(12, CombatLogGetCurrentEventInfo())
            ns.Deaths.HandleCombatLog(subevent, sourceName, envType, amount, destGUID, envType)
        end
    end
end

local missFrame = CreateFrame("Frame")
missFrame:SetScript("OnEvent", OnCombatLogEvent)

-- ---------------------------------------------------------------------------
-- resource tracker
--
-- Low mana at the pull, or running dry mid fight, looks identical to
-- forgetting to press buttons unless it is measured directly. Rage and
-- energy start near empty by design, so only mana and focus ever produce a
-- finding here; a warrior opening at zero rage is normal and is never read
-- as a resource problem.
-- ---------------------------------------------------------------------------
local RESOURCE_EMPTY = 0.05    -- at or below this, the bar could not pay for much of anything

local function ReadPowerRaw()
    local powerType, token = UnitPowerType("player")
    local cur = UnitPower("player", powerType)
    local maxPower = UnitPowerMax("player", powerType)
    return token, cur, maxPower
end

-- Guarded like everything else client facing: this addon never assumes a
-- global behaves the way an older client would.
local function ReadPower()
    local ok, token, cur, maxPower = pcall(ReadPowerRaw)
    if not ok or not token or not cur or not maxPower or maxPower <= 0 then return nil, nil end
    return token, cur / maxPower
end

local startResourceToken, startResourcePct
local resourceSamples, resourceEmptySamples = 0, 0

-- ---------------------------------------------------------------------------
-- aura sampler
-- ---------------------------------------------------------------------------
local SAMPLE_RATE = 0.25
local sampleTime = {}      -- ascending GetTime() of every sample taken this fight
local auraPresentAt = {}   -- [spell name] = ascending sample times it was present
local sampleCount = 0
local petSamples = 0
local auraTicker
local seen = {}

local function SampleUnit(unit, filter)
    for i = 1, 40 do
        local name = ns.GetAuraName(unit, i, filter)
        if not name then return end
        seen[name] = true
    end
end

local fightActive = false

local function Sample()
    if not fightActive then return end

    wipe(seen)
    SampleUnit("player", "HELPFUL|PLAYER")
    if UnitExists("target") and UnitCanAttack("player", "target") then
        SampleUnit("target", "HARMFUL|PLAYER")
    end

    local now = GetTime()
    sampleCount = sampleCount + 1
    sampleTime[sampleCount] = now
    if UnitExists("pet") and not UnitIsDead("pet") then
        petSamples = petSamples + 1
    end

    if startResourceToken == "MANA" or startResourceToken == "FOCUS" then
        local _, pct = ReadPower()
        if pct then
            resourceSamples = resourceSamples + 1
            if pct <= RESOURCE_EMPTY then
                resourceEmptySamples = resourceEmptySamples + 1
            end
        end
    end

    local prof = ns.activeProfile
    if not prof then return end
    local list = prof.list
    for i = 1, #list do
        local e = list[i]
        if e.kind == "dot" or e.kind == "buff" then
            -- An aura group counts as up when ANY member of it is up. A
            -- paladin runs one seal out of eight, so asking about a specific
            -- seal would report the other seven as never applied.
            local up = false
            if e.names then
                for j = 1, #e.names do
                    if seen[e.names[j]] then up = true break end
                end
            else
                up = seen[e.name] and true or false
            end

            if up then
                local arr = auraPresentAt[e.name]
                if not arr then
                    arr = {}
                    auraPresentAt[e.name] = arr
                end
                arr[#arr + 1] = now
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- analysis
-- ---------------------------------------------------------------------------
local MIN_FIGHT = 5
local MIN_CASTS = 3
local LIVE_MIN  = 3
local DEAD_GAP  = 3.0

local MISS_MIN_SAMPLE    = 8      -- need at least this many in combat casts before a miss rate means anything
local MISS_MIN_COUNT     = 2      -- and at least this many misses; a single dodge in four swings is noise
local RESOURCE_LOW_START = 0.30   -- entering a fight under this is worth a heads up
local RESOURCE_STARVED   = 0.25   -- share of the fight spent empty before it excuses missed buttons

local fightStart, fightTarget, truncated = 0, nil, false
local tally = {}

-- Count casts inside a time window, keeping player and pet separate.
local function Tally(from, to)
    for _, t in pairs(tally) do
        wipe(t.times)
        t.n = 0
    end
    local petCasts = 0
    local first = max(1, writeIdx - CAP + 1)
    for i = first, writeIdx do
        local slot = (i - 1) % CAP + 1
        local t = castTime[slot]
        if t and t >= from and t <= to then
            if castPet[slot] then
                petCasts = petCasts + 1
            else
                local name = castName[slot]
                local rec = tally[name]
                if not rec then
                    rec = { n = 0, times = {} }
                    tally[name] = rec
                end
                rec.n = rec.n + 1
                rec.times[rec.n] = t
            end
        end
    end
    return petCasts
end

-- Both sampleTime and every auraPresentAt[name] are ascending, since samples
-- and casts are recorded in the order they happen. Counting how many fall at
-- or after a cutoff is a reverse scan that stops the moment it walks past it.
local function CountSince(list, from)
    local n = list and #list or 0
    local c = 0
    for i = n, 1, -1 do
        if list[i] < from then break end
        c = c + 1
    end
    return c
end

-- The player's own first cast at or after "from". Pet casts never count,
-- since the whole point is to find the moment the player actually started
-- attacking, which can be a couple of seconds after the pull.
local function FirstPlayerCastAtOrAfter(from)
    local best
    for _, t in pairs(tally) do
        for i = 1, t.n do
            local ct = t.times[i]
            if ct >= from and (not best or ct < best) then best = ct end
        end
    end
    return best
end

-- How many of this spell's casts happened once combat was underway. This is
-- the honest denominator for a miss rate: a cast that missed still landed in
-- the ring buffer as a completed cast, so it is a real attempt either way.
local function CastsInCombat(name)
    local t = tally[name]
    if not t then return 0 end
    local c = 0
    for i = 1, t.n do
        if t.times[i] >= fightStart then c = c + 1 end
    end
    return c
end

local function AnalyzeFight(fightEnd, live)
    local dur = fightEnd - fightStart
    local from = fightStart - PREPULL

    local petCasts = Tally(from, fightEnd)

    local playerCasts = 0
    for _, t in pairs(tally) do playerCasts = playerCasts + t.n end

    if live then
        if dur < LIVE_MIN then return nil end
    elseif dur < MIN_FIGHT or playerCasts < MIN_CASTS then
        return nil
    end

    local profile = ns.activeProfile
    if not profile then return nil end

    local findings = {}
    -- icon is optional: only findings tied to one specific spell (matched to
    -- its profile entry below) carry one. The fight-wide findings further
    -- down, resource state, pet uptime, dead time, are not about a single
    -- spell and are never given one.
    local function Add(sev, title, detail, fix, pct, icon)
        findings[#findings + 1] = {
            sev = sev, title = title, detail = detail, fix = fix, pct = pct, icon = icon,
        }
    end

    local judge = (not live) or dur >= 10
    local haveSamples = sampleCount > 0

    -- The uptime window starts at the player's own first cast, not the pull,
    -- so an intentional slow open (a hunter letting the pet establish threat,
    -- for example) is never counted as a debuff failing to go up. A fight
    -- with no qualifying player cast yet just falls back to the pull itself.
    local upStart = FirstPlayerCastAtOrAfter(fightStart) or fightStart
    local windowDur = max(0, fightEnd - upStart)
    local windowSamples = CountSince(sampleTime, upStart)

    -- Resource state. Only mana and focus ever excuse a missed button; rage
    -- and energy legitimately start near empty and say nothing about play.
    local resourceRelevant = startResourceToken == "MANA" or startResourceToken == "FOCUS"
    local resourceLabel = (startResourceToken == "FOCUS") and "focus" or "mana"
    local emptyPct = (resourceRelevant and resourceSamples > 0)
        and (resourceEmptySamples / resourceSamples) or 0
    local resourceStarved = resourceRelevant and emptyPct >= RESOURCE_STARVED

    for _, entry in ipairs(profile.list) do
        if entry.known and judge then
            local t = tally[entry.name]
            local n = t and t.n or 0

            if entry.kind == "dot" or entry.kind == "buff" then
                if windowSamples > 0 then
                    local present = auraPresentAt[entry.name]
                    local pct = present and (CountSince(present, upStart) / windowSamples) or 0
                    local where = (entry.kind == "buff") and "on you" or "on your target"
                    local attempts = CastsInCombat(entry.name)
                    local missPhrase, missTotal = MissPhrase(entry.name)

                    if pct < 0.05 then
                        if attempts == 0 then
                            Add(SEV.CRITICAL,
                                entry.name .. " was never up",
                                format("It was not %s at any point after you started attacking (%s).",
                                       where, ns.FmtTime(windowDur)),
                                "This is a keep it up button. Apply it at the start and refresh it when it drops.",
                                0, entry.icon)
                        else
                            -- It was cast, it just never stuck. That is a very
                            -- different, much fairer story than "never up".
                            Add(SEV.CRITICAL,
                                entry.name .. " did not stick",
                                missPhrase
                                    and format("You cast it %d time%s, but it %s, so it had little chance to be up.",
                                               attempts, attempts == 1 and "" or "s", missPhrase)
                                    or format("You cast it %d time%s but it was not %s for long.",
                                               attempts, attempts == 1 and "" or "s", where),
                                "Check you are not overwriting it with a weaker application, or refresh it the moment it drops.",
                                0, entry.icon)
                        end
                    elseif pct < 0.60 then
                        local detail = format("Present %s for roughly %s of the %s since you started attacking.",
                                               where, ns.FmtTime(pct * windowDur), ns.FmtTime(windowDur))
                        if missTotal >= MISS_MIN_COUNT and attempts >= MISS_MIN_SAMPLE then
                            detail = detail .. format(" %d of %d casts were %s, not missed presses.",
                                                       missTotal, attempts, missPhrase)
                        end
                        Add(SEV.CRITICAL,
                            format("%s up only %d percent of the time", entry.name, ns.Round(pct * 100)),
                            detail,
                            "Refresh it as soon as it falls off. Every second it is missing is damage you simply do not do.",
                            pct, entry.icon)
                    elseif pct < 0.85 then
                        Add(SEV.WARN,
                            format("%s up %d percent of the time", entry.name, ns.Round(pct * 100)),
                            format("Close, but it dropped %s during the fight.", where),
                            "Refresh a moment earlier and this becomes full uptime.",
                            pct, entry.icon)
                    end
                end

            -- A cd entry with no cooldown number is a data fault, and dividing
            -- by it would throw mid fight. Skipping it costs one check and
            -- turns a crash into a silently missing line.
            elseif entry.kind == "cd" and type(entry.cd) == "number" and entry.cd > 0 then
                local expected = floor(dur / entry.cd) + 1
                local pct = expected > 0 and (n / expected) or 1
                local missed = expected - n
                if n == 0 and entry.cd >= 60 and not live then
                    Add(SEV.WARN,
                        entry.name .. " was never used",
                        "It was available the whole fight and never pressed.",
                        "That is free damage or healing sitting unused on your bars.",
                        0, entry.icon)
                elseif missed >= 2 and pct < 0.70 then
                    local detail = format("A %d second cooldown across %s allows roughly %d casts.",
                                           entry.cd, ns.FmtTime(dur), expected)
                    if resourceStarved then
                        detail = detail .. format(" You also spent about %d percent of the fight without %s to cast.",
                                                   ns.Round(emptyPct * 100), resourceLabel)
                    end
                    Add(entry.cd <= 30 and SEV.CRITICAL or SEV.WARN,
                        format("%s used %d of about %d times", entry.name, n, expected),
                        detail,
                        "Press it again as soon as it comes back up.",
                        pct, entry.icon)
                end

            elseif entry.kind == "core" then
                -- A resource starved fight already gets its own finding below,
                -- so a spender that never fired here is not blamed twice.
                if n == 0 and not resourceStarved then
                    Add(SEV.WARN,
                        entry.name .. " was never pressed",
                        "Your spec treats this as a main button and it saw zero casts.",
                        "Check your action bars and your keybinds.",
                        0, entry.icon)
                end
            end
        end
    end

    -- resource state, mana and focus only
    if judge and resourceRelevant then
        if startResourcePct and startResourcePct < RESOURCE_LOW_START then
            Add(SEV.WARN,
                format("Started the fight at %d percent %s", ns.Round(startResourcePct * 100), resourceLabel),
                "Starting a fight low on this means running dry partway through it.",
                "Drink or eat before you pull. A few seconds spent topping up costs far less than the fight does.",
                startResourcePct)
        end
        if resourceStarved then
            Add(SEV.WARN,
                format("Out of %s for about %d percent of the fight", resourceLabel, ns.Round(emptyPct * 100)),
                "The bar was at or near empty for a real share of the fight, time you physically could not cast.",
                "This is a resource problem, not a rotation problem. A fuller bar at the pull and a lighter rotation once it gets low both help.",
                emptyPct)
        end
    end

    -- pet, for the classes that live and die by it
    local petUptime = haveSamples and (petSamples / sampleCount) or nil
    local cls = ns.playerClass
    if judge and petUptime and (cls == "HUNTER" or cls == "WARLOCK") then
        if petUptime < 0.10 then
            Add(SEV.CRITICAL,
                "You fought without a pet",
                format("Your pet was out for %d percent of the fight.", ns.Round(petUptime * 100)),
                cls == "HUNTER"
                    and "A hunter pet is a large slice of your damage and it holds things off you. Call it before you pull, and revive it when it dies."
                    or "Your demon is a large slice of your damage. Summon one before you pull.",
                petUptime)
        elseif petUptime < 0.80 then
            Add(SEV.WARN,
                format("Your pet was only out %d percent of the fight", ns.Round(petUptime * 100)),
                "It either died partway through or was called late.",
                "Keep it alive and keep it on the target. Mend Pet while it is tanking.",
                petUptime)
        elseif petCasts == 0 and cls == "HUNTER" then
            Add(SEV.WARN,
                "Your pet never used an ability",
                "It was out the whole fight but never cast anything of its own.",
                "Open the pet spellbook and set Claw or Bite to autocast. Free damage that costs you nothing.",
                0)
        end
    end

    -- A hunter who let the pet open the fight is not stalling, that pet is
    -- doing exactly what it should. Say so, rather than only softening the
    -- uptime findings above and leaving the good habit unmentioned.
    if judge and cls == "HUNTER" and petUptime and petUptime > 0.3 then
        local openDelay = upStart - fightStart
        if openDelay >= 1.5 then
            Add(SEV.INFO,
                "You let your pet open the fight",
                format("Your pet was already in combat for %s before your first cast.", ns.FmtTime(openDelay)),
                "That is good play. It gives your pet time to build threat and take the hit instead of you.",
                nil)
        end
    end

    -- dead time, measured inside the fight only
    local dead, gaps, prev = 0, 0, nil
    local firstIdx = max(1, writeIdx - CAP + 1)
    for i = firstIdx, writeIdx do
        local slot = (i - 1) % CAP + 1
        local t = castTime[slot]
        if t and t >= fightStart and t <= fightEnd and not castPet[slot] then
            if prev then
                local gap = t - prev
                if gap > DEAD_GAP then dead = dead + gap gaps = gaps + 1 end
            else
                local lead = t - fightStart
                if lead > DEAD_GAP then dead = dead + lead gaps = gaps + 1 end
            end
            prev = t
        end
    end

    local deadPct = dur > 0 and (dead / dur) or 0
    if deadPct > 0.20 then
        Add(SEV.CRITICAL,
            format("%d percent of the fight with nothing cast", ns.Round(deadPct * 100)),
            format("%d gaps longer than %.0f seconds, %s in total.", gaps, DEAD_GAP, ns.FmtTime(dead)),
            "Moving, swapping targets and running dry all land here. Something instant is almost always better than standing still.",
            deadPct)
    elseif deadPct > 0.10 then
        Add(SEV.WARN,
            format("%d percent idle time", ns.Round(deadPct * 100)),
            format("%d gaps longer than %.0f seconds.", gaps, DEAD_GAP),
            "Some of this cannot be helped. The rest is free damage.",
            deadPct)
    end

    if truncated then
        Add(SEV.INFO, "Long fight, log truncated",
            format("Only the most recent %d casts were kept.", CAP),
            "The percentages above still describe the recorded part.", nil)
    end

    table.sort(findings, function(a, b)
        if a.sev ~= b.sev then return a.sev < b.sev end
        return (a.pct or 1) < (b.pct or 1)
    end)

    local top = {}
    for name, t in pairs(tally) do
        if t.n > 0 then top[#top + 1] = { name = name, n = t.n } end
    end
    table.sort(top, function(a, b) return a.n > b.n end)
    for i = #top, 7, -1 do top[i] = nil end

    -- Snapshot the miss table onto the report itself. missCount gets wiped at
    -- the start of the next fight, but DetailsBridge.lua enriches this same
    -- report a second or two after it is built, so it needs its own copy.
    local missSnapshot
    for name, rec in pairs(missCount) do
        missSnapshot = missSnapshot or {}
        local copy = {}
        for k, v in pairs(rec) do copy[k] = v end
        missSnapshot[name] = copy
    end

    return {
        live      = live or nil,
        when      = time(),
        dur       = dur,
        target    = fightTarget or "Combat",
        zone      = GetRealZoneText() or "",
        casts     = playerCasts,
        petCasts  = petCasts,
        petUptime = petUptime,
        cpm       = dur > 0 and (playerCasts / (dur / 60)) or 0,
        spec      = profile.name,
        role      = profile.role,
        deadPct   = deadPct,
        findings  = findings,
        top       = top,
        misses    = missSnapshot,
        resource  = resourceRelevant
            and { token = startResourceToken, startPct = startResourcePct, emptyPct = emptyPct }
            or nil,
    }
end

-- ---------------------------------------------------------------------------
-- combat segmentation
-- ---------------------------------------------------------------------------
local StartLive, StopLive

ns:On("PLAYER_REGEN_DISABLED", function()
    -- Read before anything else in this handler: the resource bar the fight
    -- was actually pulled with, before any regen tick or GCD touches it.
    startResourceToken, startResourcePct = ReadPower()

    truncated = false
    fightStart = GetTime()
    fightActive = true
    fightTarget = nil

    wipe(sampleTime)
    wipe(auraPresentAt)
    sampleCount = 0
    petSamples = 0
    resourceSamples = 0
    resourceEmptySamples = 0
    if not auraTicker then
        auraTicker = C_Timer.NewTicker(SAMPLE_RATE, Sample)
    end
    Sample()   -- one immediate sample so a pre-pull buff is caught at once

    wipe(missCount)
    playerGUID = ns.playerGUID
    petGUID = UnitGUID("pet")
    missFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

    if UnitExists("target") and UnitIsEnemy("player", "target") then
        fightTarget = UnitName("target")
    else
        fightTarget = ns.lastHostileTarget
    end

    ns:Emit("ROTATION_RECORDING", true)
    if StartLive then StartLive() end
end)

ns:On("PLAYER_REGEN_ENABLED", function()
    if not fightActive then return end
    fightActive = false
    missFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    if auraTicker then auraTicker:Cancel() auraTicker = nil end
    if StopLive then StopLive() end

    local report = AnalyzeFight(GetTime())
    ns:Emit("ROTATION_RECORDING", false)
    if not report then return end

    local store = ns.cdb
    if not store then return end
    store.fights = store.fights or {}
    table.insert(store.fights, 1, report)
    local keep = (ns.db and ns.db.rotationFights) or 10
    for i = #store.fights, keep + 1, -1 do
        store.fights[i] = nil
    end
    ns:Emit("ROTATION_UPDATED", report)

    if ns.DetailsAvailable and ns.DetailsAvailable() then
        C_Timer.After(1.5, function()
            if ns.ApplyDetailsData(report) then
                if ns.AddDamageFindings then ns.AddDamageFindings(report) end
                ns:Emit("ROTATION_UPDATED", report)
            end
        end)
    end
end)

function ns.GetFights()
    return (ns.cdb and ns.cdb.fights) or {}
end

-- ---------------------------------------------------------------------------
-- rotation page
-- ---------------------------------------------------------------------------
local UI, T = ns.UI, ns.T
local fightList, findingList, summaryLine, specLine, emptyMsg, recDot, cpmText, deadBar, deadText
local dpsBox, dpsText, deadLabel
local rotPage, RefreshList
local liveReport, liveTicker
local displayList = {}
local selectedIndex = 1

local function ShortNum(v)
    v = v or 0
    if v >= 1000000 then return format("%.1fm", v / 1000000) end
    if v >= 1000 then return format("%.1fk", v / 1000) end
    return format("%.0f", v)
end

local function CreateFightRow(list)
    local row = CreateFrame("Button", nil, list)
    row.hl = UI.Tex(row, "BACKGROUND", T.hover)
    row.hl:SetAllPoints()
    row.hl:Hide()

    row.sel = UI.Tex(row, "BACKGROUND", T.accent)
    row.sel:SetPoint("TOPLEFT")
    row.sel:SetPoint("BOTTOMLEFT")
    row.sel:SetWidth(2)
    row.sel:Hide()

    row.name = UI.Font(row, 12, T.text, nil, "LEFT")
    row.name:SetPoint("TOPLEFT", 10, -5)
    row.name:SetPoint("RIGHT", -8, 0)

    row.sub = UI.Font(row, 10, T.dim, nil, "LEFT")
    row.sub:SetPoint("TOPLEFT", 10, -20)
    row.sub:SetPoint("RIGHT", -8, 0)

    row.badge = UI.Font(row, 11, T.dim, nil, "RIGHT")
    row.badge:SetPoint("RIGHT", -8, 4)

    row:SetScript("OnEnter", function(self) self.hl:Show() end)
    row:SetScript("OnLeave", function(self) self.hl:Hide() end)
    return row
end

local ShowFight

local function UpdateFightRow(row, fight, index)
    if fight.live then
        row.name:SetText("Current fight")
        row.name:SetTextColor(unpack(T.accent))
        row.sub:SetText(format("%s  |  %d casts  |  happening now",
            ns.FmtTime(fight.dur), fight.casts))
        row.badge:SetText("live")
        row.badge:SetTextColor(unpack(T.bad))
    else
        row.name:SetText(fight.target)
        row.name:SetTextColor(unpack(T.text))
        row.sub:SetText(format("%s  |  %d casts  |  %s",
            ns.FmtTime(fight.dur), fight.casts, date("%H:%M", fight.when)))

        local crit = 0
        for _, f in ipairs(fight.findings) do
            if f.sev == SEV.CRITICAL then crit = crit + 1 end
        end
        if crit > 0 then
            row.badge:SetText(crit)
            row.badge:SetTextColor(unpack(T.bad))
        else
            row.badge:SetText("ok")
            row.badge:SetTextColor(unpack(T.good))
        end
    end

    row.sel:SetShown(index == selectedIndex)
    row:SetScript("OnClick", function()
        selectedIndex = index
        ShowFight(fight)
        fightList:Draw()
    end)
end

local function CreateFindingRow(list)
    local row = CreateFrame("Frame", nil, list)
    row.stripe = UI.Tex(row, "ARTWORK", T.bad)
    row.stripe:SetPoint("TOPLEFT", 0, -2)
    row.stripe:SetPoint("BOTTOMLEFT", 0, 4)
    row.stripe:SetWidth(2)

    -- Created once, only ever re-textured in UpdateFindingRow. This list is
    -- pooled the same way CoachUI's slot list is, so a texture created inside
    -- the update path would leak one per scroll event.
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("TOPLEFT", 6, -5)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Text always starts 24px in (18px icon plus a 6px gap, matching
    -- CoachUI's slot rows), whether or not a given finding has a spell icon
    -- to show, so rows do not shift as the list scrolls.
    row.title = UI.Font(row, 12, T.text, nil, "LEFT")
    row.title:SetPoint("TOPLEFT", 30, -6)
    row.title:SetPoint("RIGHT", -8, 0)

    -- Each line hangs off the one above it with no fixed height, so a font
    -- string grows to however many lines its text wraps to. Fixed heights here
    -- truncated any finding whose wording ran long, mid sentence.
    row.detail = UI.Font(row, 11, T.dim, nil, "LEFT")
    row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
    row.detail:SetPoint("RIGHT", -8, 0)
    row.detail:SetJustifyV("TOP")

    row.fix = UI.Font(row, 11, T.accent, nil, "LEFT")
    row.fix:SetPoint("TOPLEFT", row.detail, "BOTTOMLEFT", 0, -4)
    row.fix:SetPoint("RIGHT", -8, 0)
    row.fix:SetJustifyV("TOP")
    return row
end

-- Text starts 30px in and stops 8px short of the right edge. This has to match
-- CreateFindingRow or rows get sized for a width they are not drawn at.
local FINDING_TEXT_INSET = 30 + 8

local function MeasureFindingRow(f, width)
    local w = max(1, (width or 0) - FINDING_TEXT_INSET)
    local h = 6 + UI.MeasureText(12, w, f.title or "")
    h = h + 4 + UI.MeasureText(11, w, f.detail or "")
    if f.fix and f.fix ~= "" then
        h = h + 4 + UI.MeasureText(11, w, f.fix)
    end
    return max(76, h + 8)
end

local function UpdateFindingRow(row, f)
    local c = ns.SEV_COLOR[f.sev] or T.dim
    row.stripe:SetColorTexture(c[1], c[2], c[3], 1)
    row.title:SetText(f.title)
    row.detail:SetText(f.detail or "")
    row.fix:SetText(f.fix or "")

    -- Only findings matched to one specific spell carry an icon (see Add() in
    -- AnalyzeFight above). A spell whose icon has not resolved yet, or a
    -- fight-wide finding like idle time or resource state, shows nothing
    -- rather than a placeholder.
    if f.icon then
        row.icon:SetTexture(f.icon)
        row.icon:Show()
    else
        row.icon:Hide()
    end
end

function ShowFight(fight)
    if not fight then
        summaryLine:SetText("")
        specLine:SetText("")
        cpmText:SetText("-")
        deadBar:SetValue(0)
        deadText:SetText("-")
        if dpsBox then dpsBox:Hide() end
        findingList:SetData({})
        emptyMsg:Show()
        return
    end

    emptyMsg:Hide()
    specLine:SetText(format("%s  |  %s", fight.spec or "?",
        fight.live and "fight in progress" or fight.target))

    local petBit = ""
    if fight.petUptime then
        petBit = format("  |  pet out %d%%", ns.Round(fight.petUptime * 100))
    end
    summaryLine:SetText(format("%d casts in %s%s  |  %s",
        fight.casts, ns.FmtTime(fight.dur), petBit, fight.zone or ""))

    cpmText:SetText(format("%.0f", fight.cpm or 0))
    deadBar:SetValue(ns.Clamp(fight.deadPct or 0, 0, 1), true)
    deadBar:SetColor((fight.deadPct or 0) > 0.20 and T.bad
        or ((fight.deadPct or 0) > 0.10 and T.warn or T.good))
    deadText:SetText(format("%d%%", ns.Round((fight.deadPct or 0) * 100)))
    deadLabel:SetText(fight.deadSource == "Details" and "IDLE (DETAILS)" or "IDLE TIME")

    if fight.dps then
        dpsBox:Show()
        dpsText:SetText(ShortNum(fight.dps))
    else
        dpsBox:Hide()
    end

    findingList:SetData(fight.findings, fight.live)
    if #fight.findings == 0 then
        emptyMsg:SetText(fight.live
            and "Nothing wrong so far. Keep going."
            or "Clean fight. Nothing stood out.")
        emptyMsg:Show()
    end
end

function ns.BuildRotationPage(page)
    rotPage = page

    local left = UI.Panel(page, T.panel)
    left:SetPoint("TOPLEFT", 12, -8)
    left:SetPoint("BOTTOMLEFT", 12, 8)
    left:SetWidth(230)

    local lh = UI.Font(left, 10, T.dim, nil, "LEFT")
    lh:SetPoint("TOPLEFT", 12, -10)
    lh:SetText("RECENT FIGHTS")

    recDot = UI.Dot(left, 8, T.dim)
    recDot:SetPoint("TOPRIGHT", -12, -11)

    local sep = UI.Divider(left)
    sep:SetPoint("TOPLEFT", 10, -26)
    sep:SetPoint("TOPRIGHT", -10, -26)

    fightList = UI.List(left, 38, CreateFightRow, UpdateFightRow)
    fightList:SetPoint("TOPLEFT", 4, -32)
    fightList:SetPoint("BOTTOMRIGHT", -6, 8)

    local right = UI.Panel(page, T.panel)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT", -12, 8)

    specLine = UI.Font(right, 13, T.text, nil, "LEFT")
    specLine:SetPoint("TOPLEFT", 14, -12)

    summaryLine = UI.Font(right, 11, T.dim, nil, "LEFT")
    summaryLine:SetPoint("TOPLEFT", 14, -30)

    local cpmBox = UI.Panel(right, T.raised)
    cpmBox:SetPoint("TOPRIGHT", -14, -10)
    cpmBox:SetSize(78, 40)
    cpmText = UI.Font(cpmBox, 17, T.text, nil, "CENTER")
    cpmText:SetPoint("TOP", 0, -4)
    cpmText:SetPoint("LEFT")
    cpmText:SetPoint("RIGHT")
    local cpmLabel = UI.Font(cpmBox, 9, T.dim, nil, "CENTER")
    cpmLabel:SetPoint("BOTTOM", 0, 5)
    cpmLabel:SetPoint("LEFT")
    cpmLabel:SetPoint("RIGHT")
    cpmLabel:SetText("CASTS / MIN")

    local deadBox = UI.Panel(right, T.raised)
    deadBox:SetPoint("TOPRIGHT", cpmBox, "TOPLEFT", -6, 0)
    deadBox:SetSize(96, 40)
    deadText = UI.Font(deadBox, 17, T.text, nil, "CENTER")
    deadText:SetPoint("TOP", 0, -4)
    deadText:SetPoint("LEFT")
    deadText:SetPoint("RIGHT")
    deadLabel = UI.Font(deadBox, 9, T.dim, nil, "CENTER")
    deadLabel:SetPoint("BOTTOM", 0, 5)
    deadLabel:SetPoint("LEFT")
    deadLabel:SetPoint("RIGHT")
    deadLabel:SetText("IDLE TIME")
    deadBar = UI.Bar(deadBox, T.good)
    deadBar:SetPoint("BOTTOMLEFT", 6, 16)
    deadBar:SetPoint("BOTTOMRIGHT", -6, 16)
    deadBar:SetHeight(3)

    dpsBox = UI.Panel(right, T.raised)
    dpsBox:SetPoint("TOPRIGHT", deadBox, "TOPLEFT", -6, 0)
    dpsBox:SetSize(86, 40)
    dpsText = UI.Font(dpsBox, 17, T.text, nil, "CENTER")
    dpsText:SetPoint("TOP", 0, -4)
    dpsText:SetPoint("LEFT")
    dpsText:SetPoint("RIGHT")
    local dpsLabel = UI.Font(dpsBox, 9, T.dim, nil, "CENTER")
    dpsLabel:SetPoint("BOTTOM", 0, 5)
    dpsLabel:SetPoint("LEFT")
    dpsLabel:SetPoint("RIGHT")
    dpsLabel:SetText("DAMAGE / SEC")
    dpsBox:Hide()

    -- Right anchored to dpsBox, the leftmost of the three stat boxes, so the
    -- text is clipped or wrapped before it reaches them. dpsBox keeps this
    -- same position whether or not Details supplied any damage, since Hide()
    -- does not change a frame's anchors, so the reserved space is correct
    -- either way.
    specLine:SetPoint("RIGHT", dpsBox, "LEFT", -10, 0)
    summaryLine:SetPoint("RIGHT", dpsBox, "LEFT", -10, 0)

    local sep2 = UI.Divider(right)
    sep2:SetPoint("TOPLEFT", 10, -56)
    sep2:SetPoint("TOPRIGHT", -10, -56)

    findingList = UI.List(right, 76, CreateFindingRow, UpdateFindingRow, MeasureFindingRow)
    findingList:SetPoint("TOPLEFT", 8, -62)
    findingList:SetPoint("BOTTOMRIGHT", -6, 8)

    emptyMsg = UI.Font(right, 12, T.dim, nil, "CENTER")
    emptyMsg:SetPoint("CENTER", 0, -10)
    emptyMsg:SetWidth(380)
    emptyMsg:SetText("No fights recorded yet. Pull something for at least five seconds and it will show up here.")

    RefreshList = function(liveTick)
        local subject = ns.Subject()
        local fights = subject.fights or {}
        wipe(displayList)
        -- The live row is this player's own fight in progress. It means
        -- nothing while the window is pointed at someone else, and showing it
        -- there would quietly mix two people's data in one list.
        if liveReport and subject.isSelf then displayList[1] = liveReport end
        for i = 1, #fights do
            displayList[#displayList + 1] = fights[i]
        end

        emptyMsg:SetText(subject.isSelf
            and "No fights recorded yet. Pull something for at least five seconds and it will show up here."
            or format("%s has not shared any fights yet. They need to fight something with rotation sharing turned on.",
                      subject.name or "This player"))

        fightList:SetData(displayList, liveTick)
        if #displayList == 0 then ShowFight(nil) return end

        selectedIndex = ns.Clamp(selectedIndex, 1, #displayList)
        if liveTick and selectedIndex ~= 1 then return end
        ShowFight(displayList[selectedIndex])
    end

    ns:Sub("ROTATION_UPDATED", function()
        selectedIndex = 1
        RefreshList()
    end)
    ns:Sub("ROTATION_RECORDING", function(on)
        if recDot then
            recDot:SetVertexColor(unpack(on and T.bad or T.dim))
        end
    end)

    RefreshList()
end

-- ---------------------------------------------------------------------------
-- live updating
-- ---------------------------------------------------------------------------
StartLive = function()
    if liveTicker then return end
    selectedIndex = 1
    liveTicker = C_Timer.NewTicker(0.75, function()
        if not fightActive then
            if StopLive then StopLive() end
            return
        end
        if not rotPage or not rotPage:IsVisible() then return end
        liveReport = AnalyzeFight(GetTime(), true)
        if RefreshList then RefreshList(true) end
    end)
end

StopLive = function()
    if liveTicker then
        liveTicker:Cancel()
        liveTicker = nil
    end
    liveReport = nil
    if RefreshList then RefreshList(true) end
end

-- ---------------------------------------------------------------------------
-- diagnostics
-- ---------------------------------------------------------------------------
function ns.PrintRotationDebug()
    local okSpec, specName, tabIndex, points = pcall(ns.GetSpec)
    if not okSpec then
        ns.Print("Spec detection failed: " .. tostring(specName))
        specName, tabIndex, points = nil, nil, nil
    end
    ns.Print(format("class=%s  spec tab=%s (%s, %s points)",
        tostring(ns.playerClass), tostring(tabIndex),
        tostring(specName), tostring(points)))
    ns.Print(ns.SpellAPIReport())
    ns.Print(format("aura API: %s   casts recorded: %d   samples last fight: %d",
        ns.hasAuraAPI and "yes" or "NO", writeIdx, sampleCount))

    local p = ns.activeProfile
    if not p then
        ns.Print("Profile has not been built yet. Try /reload.")
        return
    end
    if p.generic then
        ns.Print(format("No authored spell list for %s, running in generic mode.", p.name))
        return
    end
    ns.Print(format("Profile %s, %d tracked spells, %d known, %d spell ids failed to resolve. Data: %s.",
        p.name, #p.list, p.knownCount or 0, ns.unresolvedSpells or 0,
        ns.GetProfileSource and ns.GetProfileSource() or "?"))
    if p.usedBaseline then
        ns.Print("Most of this spec's endgame spells are not learned yet, so the class levelling baseline was added too.")
    end
    for _, e in ipairs(p.list) do
        ns.Print(format("  %s  [%s]%s  %s", e.name, e.kind,
            e.basic and " basic" or "",
            e.known and "known" or "not learned yet"))
    end
end

-- RefreshList is a file local assigned during page construction, so this only
-- does anything once the rotation page has actually been built.
ns:Sub("SUBJECT_CHANGED", function()
    if RefreshList then
        selectedIndex = 1
        RefreshList()
    end
end)
