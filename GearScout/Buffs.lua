-- GearScout / Buffs.lua
-- Works out which group buffs you are missing that somebody standing next to
-- you could actually give you.
--
-- The logic is deliberately conservative. It only lists a buff when a class
-- that gets it for free, with no talent required, is in your group and is high
-- enough level to have learned it. Suggesting a buff nobody present can cast
-- is worse than saying nothing, and so is nagging a warrior about mana.

local ADDON, ns = ...

local UnitClass, UnitLevel, UnitName, UnitExists = UnitClass, UnitLevel, UnitName, UnitExists
local IsInRaid, IsInGroup = IsInRaid, IsInGroup
local GetNumGroupMembers, GetNumSubgroupMembers = GetNumGroupMembers, GetNumSubgroupMembers
local ipairs, pairs, wipe = ipairs, pairs, wipe

-- usefulFor: all, mana, physical
-- ids: every spell that produces this buff, single target and group version,
--      because the group version has a different name in every language.
local BUFF_SOURCES = {
    PRIEST = {
        { key = "fort",   minLevel = 1,  usefulFor = "all",
          ids = { 1243, 21562 },
          why = "Extra health. There is no reason to fight without it." },
        { key = "spirit", minLevel = 30, usefulFor = "mana",
          ids = { 14752, 27681 },
          why = "Regenerates your mana faster between casts." },
    },
    MAGE = {
        { key = "int", minLevel = 1, usefulFor = "mana",
          ids = { 1459, 23028 },
          why = "More mana, and more chance to land a critical spell." },
    },
    DRUID = {
        { key = "motw", minLevel = 1, usefulFor = "all",
          ids = { 1126, 21849 },
          why = "Raises every one of your stats and your resistances at once." },
    },
    PALADIN = {
        { key = "might",  minLevel = 4,  usefulFor = "physical",
          ids = { 19740, 25782 },
          why = "Straight attack power, so every hit lands harder." },
        { key = "wisdom", minLevel = 14, usefulFor = "mana",
          ids = { 19742, 25894 },
          why = "Gives mana back steadily, even while you are casting." },
    },
    WARRIOR = {
        { key = "bshout", minLevel = 1, usefulFor = "physical",
          ids = { 6673 },
          why = "Attack power for everyone standing near the warrior." },
    },
    WARLOCK = {
        { key = "bloodpact", minLevel = 10, usefulFor = "all",
          ids = { 6307 },
          why = "Extra health from the warlock's imp, as long as the imp is out." },
    },
}

local CLASS_LABEL = {
    WARRIOR = "warrior", PALADIN = "paladin", HUNTER = "hunter", ROGUE = "rogue",
    PRIEST = "priest", SHAMAN = "shaman", MAGE = "mage", WARLOCK = "warlock",
    DRUID = "druid",
}

-- Classes with no mana bar at all. Never suggest a mana buff to them.
local NO_MANA = { WARRIOR = true, ROGUE = true }
-- Classes that gain nothing worth mentioning from attack power.
local NO_PHYSICAL = { MAGE = true, WARLOCK = true, PRIEST = true }

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function GroupUnits(out)
    wipe(out)
    out[1] = "player"
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid" .. i
            if UnitExists(u) then out[#out + 1] = u end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local u = "party" .. i
            if UnitExists(u) then out[#out + 1] = u end
        end
    end
    return out
end

-- Everything currently on the player, by name. No PLAYER filter here, because
-- the whole point is to find buffs other people gave you.
local function PlayerBuffNames(out)
    wipe(out)
    for i = 1, 40 do
        local name = ns.GetAuraName("player", i, "HELPFUL")
        if not name then break end
        out[name] = true
    end
    return out
end

local unitScratch, buffScratch = {}, {}

-- ---------------------------------------------------------------------------
-- the check
-- Returns a list of { label, why, from } describing buffs you could have.
-- ---------------------------------------------------------------------------
function ns.GetMissingGroupBuffs()
    local missing = {}
    if not IsInGroup() and not IsInRaid() then return missing end

    local myClass = ns.playerClass
    local have = PlayerBuffNames(buffScratch)
    local units = GroupUnits(unitScratch)

    -- who is here, and what is the highest level of each class present
    local present = {}
    for _, unit in ipairs(units) do
        local _, classFile = UnitClass(unit)
        if classFile and BUFF_SOURCES[classFile] then
            local lvl = UnitLevel(unit) or 0
            local entry = present[classFile]
            if not entry or lvl > entry.level then
                present[classFile] = { level = lvl, name = UnitName(unit), unit = unit }
            end
        end
    end

    for classFile, who in pairs(present) do
        for _, def in ipairs(BUFF_SOURCES[classFile]) do
            local relevant = true
            if def.usefulFor == "mana" and NO_MANA[myClass] then relevant = false end
            if def.usefulFor == "physical" and NO_PHYSICAL[myClass] then relevant = false end

            if relevant and who.level >= def.minLevel then
                -- resolve every name this buff can appear under
                local label, found = nil, false
                for _, id in ipairs(def.ids) do
                    local n = ns.SpellName(id)
                    if n then
                        label = label or n
                        if have[n] then found = true break end
                    end
                end
                if label and not found then
                    missing[#missing + 1] = {
                        label = label,
                        why   = def.why,
                        from  = who.name,
                        fromClass = CLASS_LABEL[classFile] or classFile:lower(),
                    }
                end
            end
        end
    end

    table.sort(missing, function(a, b) return a.label < b.label end)
    return missing
end

-- Formats the result as a single issue suitable for either the gear list or a
-- fight report. Returns nil when there is nothing to say.
function ns.GetBuffIssue()
    local missing = ns.GetMissingGroupBuffs()
    if #missing == 0 then return nil end

    local names, sources = {}, {}
    for _, m in ipairs(missing) do
        names[#names + 1] = m.label
        sources[m.from] = true
    end

    local people = {}
    for n in pairs(sources) do people[#people + 1] = n end
    table.sort(people)

    local detail
    if #missing == 1 then
        detail = string.format("%s is in your group and can give you %s. %s",
            people[1], names[1], missing[1].why)
    else
        detail = string.format("Your group can give you %d buffs you do not have: %s.",
            #missing, table.concat(names, ", "))
    end

    return {
        sev    = ns.SEVERITY.WARN,
        title  = string.format("You are missing %d group buff%s",
                               #missing, #missing == 1 and "" or "s"),
        detail = detail,
        fix    = string.format("Ask %s for them. Buffs are free, they last a long time, and they are the cheapest power you will ever get.",
                               table.concat(people, " and ")),
        count  = #missing,
        buffs  = missing,
    }
end
