-- GearScout / DetailsBridge.lua
-- Optional enrichment from the Details damage meter.
--
-- GearScout never requires Details. The rotation tracker works entirely on its
-- own cast log. What Details adds, when it happens to be installed, is the one
-- thing a cast log cannot know: how much damage each button actually did.
--
-- Only functions marked exported in Details' own API.lua are used:
--   Details:GetCurrentCombat()        Details:GetCombat(segmentId)
--   combat:GetCombatTime()            combat:GetCombatName()
--   combat:GetActor(attribute, name)  actor:GetSpellList()  actor:Tempo()
-- Every call is wrapped, and any failure disables the bridge for that fight
-- rather than breaking the report.
--
-- Dodges, parries and full misses are not part of that documented surface
-- (only resisted, blocked, absorbed and glancing hits are, and those are all
-- hits that still did some damage). Rotation.lua's own combat log listener
-- is what supplies that, on report.misses. The melee avoidance finding below
-- combines the two: Details' documented hit counter for what landed, and
-- Rotation.lua's count for what did not.

local ADDON, ns = ...

local GetSpellInfo, pcall, type, pairs = GetSpellInfo, pcall, type, pairs
local format, floor, abs, max = string.format, math.floor, math.abs, math.max

local ATTR_DAMAGE = 1   -- DETAILS_ATTRIBUTE_DAMAGE

local function GetDetails()
    local D = _G.Details
    if type(D) ~= "table" then return nil end
    if type(D.GetCurrentCombat) ~= "function" then return nil end
    return D
end

function ns.DetailsAvailable()
    return GetDetails() ~= nil
end

-- Pick the segment that matches the fight we just recorded. Details may have
-- already rolled to a fresh segment by the time this runs, so the closed
-- segment is preferred and the length is sanity checked before it is trusted.
local function PickCombat(D, expectedDur)
    local candidates = {}
    if type(D.GetCombat) == "function" then
        local ok, c = pcall(D.GetCombat, D, 1)
        if ok and c then candidates[#candidates + 1] = c end
    end
    local ok2, cur = pcall(D.GetCurrentCombat, D)
    if ok2 and cur then candidates[#candidates + 1] = cur end

    for _, combat in ipairs(candidates) do
        local okT, ctime = pcall(combat.GetCombatTime, combat)
        if okT and ctime and ctime > 0 then
            -- reject a segment that is clearly a different fight
            if abs(ctime - expectedDur) <= max(10, expectedDur * 0.5) then
                return combat, ctime
            end
        end
    end
    return nil
end

local function GetPlayerActor(combat)
    local names = { ns.playerName, ns.playerFull }
    for _, n in ipairs(names) do
        if n then
            local ok, actor = pcall(combat.GetActor, combat, ATTR_DAMAGE, n)
            if ok and actor then return actor end
        end
    end
    return nil
end

-- Adds damage numbers to a finished rotation report. Returns true if anything
-- was actually attached.
function ns.ApplyDetailsData(report)
    if not report then return false end
    local D = GetDetails()
    if not D then return false end

    local ok, changed = pcall(function()
        local combat, ctime = PickCombat(D, report.dur or 0)
        if not combat then return false end

        local actor = GetPlayerActor(combat)
        if not actor then return false end

        local total = tonumber(actor.total) or 0
        if total <= 0 then return false end

        report.damage = total
        report.dps = total / ctime
        report.detailsTime = ctime

        -- Activity time is how long Details thinks you were actually doing
        -- something. It is a better idle measure than counting gaps between
        -- casts, so it replaces the estimate when it is available.
        if type(actor.Tempo) == "function" then
            local okA, active = pcall(actor.Tempo, actor)
            if okA and active and active > 0 and active <= ctime then
                report.activePct = active / ctime
                report.deadPct = 1 - report.activePct
                report.deadSource = "Details"
            end
        end

        -- damage share per spell
        if type(actor.GetSpellList) == "function" then
            local okS, spells = pcall(actor.GetSpellList, actor)
            if okS and type(spells) == "table" then
                local list = {}
                for spellID, spellTable in pairs(spells) do
                    local dmg = tonumber(spellTable and spellTable.total) or 0
                    if dmg > 0 then
                        local name = ns.SpellName(spellID) or ("Spell " .. tostring(spellID))
                        local existing = list[name]
                        if existing then
                            existing.dmg = existing.dmg + dmg
                            existing.hits = existing.hits + (tonumber(spellTable.counter) or 0)
                        else
                            list[name] = {
                                name = name,
                                dmg = dmg,
                                hits = tonumber(spellTable.counter) or 0,
                            }
                        end
                    end
                end
                local arr = {}
                for _, v in pairs(list) do
                    v.pct = v.dmg / total
                    arr[#arr + 1] = v
                end
                table.sort(arr, function(a, b) return a.dmg > b.dmg end)
                for i = #arr, 9, -1 do arr[i] = nil end
                report.spellDamage = arr
            end
        end

        -- Pet damage, summed from any pet actor whose owner is this character.
        -- Reported as an absolute number rather than a share, because whether
        -- the owner's own total already folds pets in is a Details display
        -- setting and guessing wrong would print a confidently wrong figure.
        if type(combat.GetActorList) == "function" then
            local okL, actors = pcall(combat.GetActorList, combat, ATTR_DAMAGE)
            if okL and type(actors) == "table" then
                local petTotal = 0
                for _, a in ipairs(actors) do
                    if type(a) == "table" and type(a.IsPetOrGuardian) == "function" then
                        local okP, isPet = pcall(a.IsPetOrGuardian, a)
                        if okP and isPet and type(a.owner) == "table" then
                            local ownerName = a.owner.nome or a.owner.name
                            if ownerName == ns.playerName or ownerName == ns.playerFull then
                                petTotal = petTotal + (tonumber(a.total) or 0)
                            end
                        end
                    end
                end
                if petTotal > 0 then report.petDamage = petTotal end
            end
        end

        local okN, cname = pcall(combat.GetCombatName, combat, true)
        if okN and cname and cname ~= "" then report.target = cname end

        report.source = "Details"
        return true
    end)

    return (ok and changed) or false
end

-- ---------------------------------------------------------------------------
-- extra findings that only damage data can support
-- ---------------------------------------------------------------------------
local SEV = ns.SEVERITY

function ns.AddDamageFindings(report)
    if not report or not report.spellDamage or not report.damage then return end
    local profile = ns.activeProfile
    if not profile then return end

    local byName = {}
    for _, s in ipairs(report.spellDamage) do byName[s.name] = s end

    -- A maintenance or cooldown button you own that produced no damage at all
    -- is much stronger evidence than a missing cast count on its own.
    for _, entry in ipairs(profile.list) do
        if entry.known and (entry.kind == "dot" or entry.kind == "cd") then
            if not byName[entry.name] then
                local already = false
                for _, f in ipairs(report.findings) do
                    if f.title:find(entry.name, 1, true) then already = true break end
                end
                if not already then
                    report.findings[#report.findings + 1] = {
                        sev = SEV.WARN,
                        title = entry.name .. " did no damage at all",
                        detail = "Details recorded zero damage from this spell during the fight, so it was either never cast or never landed.",
                        fix = "This is one of the buttons your spec is built around. Get it onto your bars and use it.",
                        pct = 0,
                    }
                end
            end
        end
    end

    -- A pet that was out all fight and dealt nothing is doing nothing useful.
    if (report.petUptime or 0) > 0.7 and not report.petDamage
       and (ns.playerClass == "HUNTER" or ns.playerClass == "WARLOCK") then
        report.findings[#report.findings + 1] = {
            sev = SEV.WARN,
            title = "Your pet dealt no damage",
            detail = "It was out for the whole fight but Details recorded nothing from it.",
            fix = "It is probably passive, or it never reached the target. Set it to defensive, and make sure Claw or Bite is on autocast in the pet spellbook.",
            pct = 0,
        }
    end

    -- Melee dodges and parries. Rotation.lua's combat log listener records
    -- how many swings were avoided, but it deliberately never listens to
    -- SWING_DAMAGE, so it has no count of the swings that landed. Details'
    -- documented per-spell counter (how many hits a spell made) fills that
    -- half, so this only ever fires when Details is available.
    local meleeName = ns.SpellName(6603) or "Auto Attack"
    local meleeMiss = report.misses and (report.misses[meleeName] or report.misses["Melee"])
    if meleeMiss and meleeMiss.total then
        local landedSpell = byName[meleeName] or byName["Melee"]
        local landed = (landedSpell and landedSpell.hits) or 0
        local attempts = landed + meleeMiss.total
        if attempts >= 8 and meleeMiss.total >= 2 then
            local avoidPct = meleeMiss.total / attempts
            if avoidPct >= 0.35 then
                report.findings[#report.findings + 1] = {
                    sev = SEV.WARN,
                    title = format("%d percent of your melee swings were avoided", ns.Round(avoidPct * 100)),
                    detail = format("%d of %d swings were dodged, parried or missed outright.",
                                     meleeMiss.total, attempts),
                    fix = "This usually means you are standing in front of the target. Move to its side or back when you can, most enemies cannot dodge or parry an attack from there.",
                    pct = avoidPct,
                }
            end
        end
    end

    -- auto attack carrying the fight is a strong signal for a new player
    local auto = byName[ns.SpellName(6603) or "Auto Attack"] or byName["Auto Attack"]
                 or byName["Melee"] or byName[ns.SpellName(75) or "Auto Shot"]
    if auto and auto.pct and auto.pct > 0.55 and (report.role == "melee" or report.role == "ranged") then
        report.findings[#report.findings + 1] = {
            sev = SEV.CRITICAL,
            title = format("%d percent of your damage was plain auto attack",
                           ns.Round(auto.pct * 100)),
            detail = "Auto attack is the swing that happens by itself when you stand next to something. Everything else on your bars is what you add on top.",
            fix = "You are barely using your abilities. Pick the three or four buttons your spec cares about, put them somewhere easy to reach, and press them whenever they are ready.",
            pct = auto.pct,
        }
    end

    table.sort(report.findings, function(a, b)
        if a.sev ~= b.sev then return a.sev < b.sev end
        return (a.pct or 1) < (b.pct or 1)
    end)
end
