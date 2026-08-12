-- GearScout / Rules.lua
-- Turns a scan into a ranked list of things worth fixing, plus a 0 to 100 score.
--
-- Writing rule: every message says three things in plain words. What is wrong,
-- why it costs you, and exactly what to do about it. No jargon, no shorthand,
-- no assumed knowledge.

local ADDON, ns = ...

local SEV = ns.SEVERITY
local L = ns.L
local ipairs, pairs, format, max, min = ipairs, pairs, string.format, math.max, math.min

-- Every sentence below is written in English and looked up through L at the
-- moment it is built, never when the table holding it is defined, because the
-- tables here are built once at load and the player can change language at
-- any point after that.
--
-- Equipment slot names, class names, stat names and armor weights stay in
-- English in every language. Swedish players say head, cloak, main hand,
-- warrior, agility and plate, and translating them would also drag gender
-- agreement into every generated sentence that names one.

-- ---------------------------------------------------------------------------
-- score weights
-- ---------------------------------------------------------------------------
local W = {
    emptySlot    = 12,
    missingEnch  = 4,
    emptySocket  = 3,
    wrongArmor   = 6,
    lowQuality   = 5,
    weakLink     = 4,
    outdated     = 4,
    junkStats    = 2,
    broken       = 3,
}

-- ---------------------------------------------------------------------------
-- how to actually get each enchant, said simply
-- ---------------------------------------------------------------------------
local ENCHANT_SOURCE = {
    [1]  = "Head enchants are bought once from a reputation vendor and last forever. Ask in guild chat which one suits your class.",
    [3]  = "Shoulder enchants are sold by the Aldor or the Scryers in Shattrath once you have earned enough standing with them.",
    [15] = "Any enchanter can enchant a cloak. It is cheap, it is permanent, and you only pay once.",
    [5]  = "Ask any enchanter for plus six to all stats on your chest. It is one of the cheapest upgrades in the whole game.",
    [9]  = "Any enchanter can add stats to bracers for very little gold.",
    [10] = "Any enchanter can enchant gloves. If you are an engineer you can also fit a glove gadget instead.",
    [7]  = "Leg armor comes from a tailor as spellthread, or from a leatherworker as an armor kit. One of them lasts forever.",
    [8]  = "Boots can take extra movement speed or extra stats from an enchanter. Movement speed is never wasted.",
    [16] = "A weapon enchant is the single largest enchant in the game. Get one from an enchanter as soon as you can afford it.",
    [17] = "Your off hand can take a weapon enchant, or a shield enchant, from an enchanter.",
    [18] = "An engineer can fit a scope to a bow, gun or crossbow. It adds flat damage to every single shot you fire.",
    [11] = "You are an enchanter, and only enchanters may enchant their own rings. Both of yours are bare.",
    [12] = "You are an enchanter, and only enchanters may enchant their own rings. Both of yours are bare.",
}

-- ---------------------------------------------------------------------------
-- when several slots are missing an enchant at once, this decides which ones
-- to tell the player to do first. Lower number means do it sooner.
-- ---------------------------------------------------------------------------
local ENCHANT_PRIORITY = {
    [16] = 1,  -- main weapon, the single biggest enchant in the game
    [5]  = 2,  -- chest
    [15] = 3,  -- cloak
    [8]  = 4,  -- boots
    [9]  = 5,  -- bracers
    [10] = 6,  -- gloves
    [1]  = 7,  -- head
    [3]  = 8,  -- shoulder
    [7]  = 9,  -- legs
    [17] = 10, -- off hand
    [11] = 11, [12] = 11, -- rings, only the player themself can enchant these
    [18] = 12, -- ranged weapon scope
}

-- ---------------------------------------------------------------------------
-- stats that do nothing for a class
-- Conservative on purpose. Accusing someone wrongly is worse than staying quiet.
-- ---------------------------------------------------------------------------
local JUNK = {
    WARRIOR = { ITEM_MOD_INTELLECT_SHORT = 1, ITEM_MOD_SPIRIT_SHORT = 1,
                ITEM_MOD_SPELL_POWER_SHORT = 1, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 1,
                ITEM_MOD_SPELL_HEALING_DONE_SHORT = 1, ITEM_MOD_MANA_REGENERATION_SHORT = 1 },
    ROGUE   = { ITEM_MOD_INTELLECT_SHORT = 1, ITEM_MOD_SPIRIT_SHORT = 1,
                ITEM_MOD_SPELL_POWER_SHORT = 1, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 1,
                ITEM_MOD_SPELL_HEALING_DONE_SHORT = 1, ITEM_MOD_MANA_REGENERATION_SHORT = 1 },
    HUNTER  = { ITEM_MOD_SPIRIT_SHORT = 1, ITEM_MOD_SPELL_POWER_SHORT = 1,
                ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 1, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 1,
                ITEM_MOD_STRENGTH_SHORT = 1 },
    MAGE    = { ITEM_MOD_STRENGTH_SHORT = 1, ITEM_MOD_AGILITY_SHORT = 1,
                ITEM_MOD_ATTACK_POWER_SHORT = 1 },
    WARLOCK = { ITEM_MOD_STRENGTH_SHORT = 1, ITEM_MOD_AGILITY_SHORT = 1,
                ITEM_MOD_ATTACK_POWER_SHORT = 1 },
    PRIEST  = { ITEM_MOD_STRENGTH_SHORT = 1, ITEM_MOD_AGILITY_SHORT = 1,
                ITEM_MOD_ATTACK_POWER_SHORT = 1 },
    -- Paladin, Shaman and Druid are left out on purpose. What is useful to them
    -- swings so hard on their talents that a blanket rule would lie.
}

local STAT_LABEL = {
    ITEM_MOD_STRENGTH_SHORT = "Strength",
    ITEM_MOD_AGILITY_SHORT = "Agility",
    ITEM_MOD_INTELLECT_SHORT = "Intellect",
    ITEM_MOD_SPIRIT_SHORT = "Spirit",
    ITEM_MOD_ATTACK_POWER_SHORT = "Attack Power",
    ITEM_MOD_SPELL_POWER_SHORT = "Spell Power",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "Spell Damage",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "Healing",
    ITEM_MOD_MANA_REGENERATION_SHORT = "Mana Regeneration",
}

-- what each class actually wants to see instead
local WANT_INSTEAD = {
    WARRIOR = "Strength, Stamina and Critical Strike",
    ROGUE   = "Agility, Attack Power and Stamina",
    HUNTER  = "Agility, Attack Power and Stamina",
    MAGE    = "Intellect, Spell Damage and Stamina",
    WARLOCK = "Intellect, Spell Damage and Stamina",
    PRIEST  = "Intellect, Spirit and Spell Power",
}

local CLASS_NAME = {
    WARRIOR = "warrior", PALADIN = "paladin", HUNTER = "hunter", ROGUE = "rogue",
    PRIEST = "priest", SHAMAN = "shaman", MAGE = "mage", WARLOCK = "warlock",
    DRUID = "druid",
}

-- ---------------------------------------------------------------------------
-- level tiers
--
-- Advice has to match where the character actually is. Head and shoulder
-- enchants do not exist below the level cap, and telling someone at level 27
-- to visit the Aldor is noise dressed up as help. Below the enchant threshold
-- the addon says so once and then points at what genuinely helps instead.
-- ---------------------------------------------------------------------------
local ENCHANT_WORTH_IT = 58   -- Outland gear survives long enough to enchant
-- Shared so the UI can colour and word things the same way this file scores
-- them, rather than each deciding separately and disagreeing on screen.
ns.ENCHANT_WORTH_IT = ENCHANT_WORTH_IT
local SOCKETS_EXIST    = 58   -- nothing before Outland has a gem socket

-- Where the upgrades actually are, by level bracket.
local UPGRADE_SOURCES = {
    { 1,  14, "Quest rewards. At this level they beat anything you can buy, and you get them for free just by questing." },
    { 15, 21, "Quest rewards, plus your first dungeons: Ragefire Chasm, Wailing Caverns, Deadmines and Shadowfang Keep." },
    { 22, 27, "Blackfathom Deeps, the Stockade and Razorfen Kraul. Every blue that drops there is a big jump at your level." },
    { 28, 33, "Gnomeregan and Scarlet Monastery. The Monastery wings are the best gear per hour in this bracket by a wide margin." },
    { 34, 40, "Scarlet Monastery Cathedral, Razorfen Downs and Uldaman." },
    { 41, 46, "Zul'Farrak and Maraudon. Also worth buying a few crafted blues from the auction house around now." },
    { 47, 52, "Sunken Temple and the upper parts of Blackrock Depths." },
    { 53, 57, "Blackrock Depths, Lower Blackrock Spire, Stratholme and Scholomance." },
    { 58, 63, "Head to Outland. The first green quest rewards in Hellfire Peninsula beat level 60 raid gear, so replace everything fast." },
    { 64, 69, "Auchenai Crypts, Sethekk Halls, Mana-Tombs and the Steamvault. Do the quests inside them for the rewards too." },
    { 70, 70, "Heroic dungeons for badges, Karazhan, reputation rewards and crafted epics. Now is the point where enchants and gems are worth real gold." },
}

function ns.UpgradeAdvice(level)
    for _, row in ipairs(UPGRADE_SOURCES) do
        -- Dungeon and zone names inside these lines are left as they are: the
        -- client names them, and a player looking for Scarlet Monastery on
        -- their own map needs to read the same words GearScout used.
        if level >= row[1] and level <= row[2] then return L[row[3]] end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function Add(issues, sev, rec, title, detail, fix, penalty)
    issues[#issues + 1] = {
        sev     = sev,
        slotID  = rec and rec.slotID or 0,
        order   = rec and rec.order or 99,
        label   = rec and rec.label or "Character",
        link    = rec and rec.link or nil,
        icon    = rec and rec.icon or nil,
        title   = title,
        detail  = detail,
        fix     = fix,
        penalty = penalty or 0,
    }
end

-- Turns a list of names into plain English: "a and b", "a, b and c", or once
-- there are more than three, "a, b, c and 2 more" so a title never wraps to
-- a second line.
local function JoinList(names)
    local n = #names
    if n == 0 then return "" end
    if n == 1 then return names[1] end
    if n <= 3 then
        local head = {}
        for i = 1, n - 1 do head[#head + 1] = names[i] end
        return table.concat(head, ", ") .. L[" and "] .. names[n]
    end
    return format(L["%s, %s, %s and %d more"], names[1], names[2], names[3], n - 3)
end

-- Slot names for a group of same-rule entries, in equipped slot order so the
-- list reads the way a player would look down their own character.
local function GroupSlotNames(group)
    table.sort(group, function(a, b) return (a.rec and a.rec.order or 99) < (b.rec and b.rec.order or 99) end)
    local names = {}
    for _, it in ipairs(group) do names[#names + 1] = it.slotName end
    return names
end

local function GroupPenalty(group)
    local total = 0
    for _, it in ipairs(group) do total = total + it.penalty end
    return total
end

-- If only one slot triggered this rule, there is nothing to merge: add the
-- row exactly as the single slot loop would have. Returns true when it did,
-- so the caller knows the merged version below is not needed.
local function EmitGroupSingle(issues, group, sev)
    if #group ~= 1 then return false end
    local it = group[1]
    Add(issues, sev, it.rec, it.title, it.detail, it.fix, it.penalty)
    return true
end

-- Roughly what item level a piece should be at a given character level.
local function ExpectedIlvl(level)
    if level >= 70 then return 100 end
    if level >= 58 then return level + 2 end
    if level >= 20 then return level - 6 end
    return 1
end

-- ---------------------------------------------------------------------------
-- the analysis
-- ---------------------------------------------------------------------------
function ns.Analyze(scan)
    scan = scan or ns.lastScan
    if not scan then return nil end

    local issues = {}
    local penalty = 0
    local level = scan.level or 1
    local className = CLASS_NAME[scan.class] or L["character"]
    local junkSet = JUNK[scan.class]
    local expectFloor = ExpectedIlvl(level)
    local slack = (ns.db and ns.db.ilvlSlack) or 12
    local counts = { emptySlots = 0, missingEnchants = 0, emptySockets = 0, weakItems = 0 }

    -- Repetitive per slot rules collect here instead of adding a row straight
    -- away. Once the loop is done, each of these becomes one row if only one
    -- slot triggered it, or a single combined row if several did, so a
    -- character with three empty slots gets one line instead of three.
    local groups = {
        emptySlot   = {},
        missingEnch = {},
        emptySocket = {},
        lowQuality  = {},
        outdated    = {},
        junkStats   = {},
    }

    for i = 1, #scan.slots do
        local rec = scan.slots[i]
        local slotName = (rec.label or "slot"):lower()

        if rec.empty then
            if not rec.expectedEmpty then
                counts.emptySlots = counts.emptySlots + 1
                penalty = penalty + W.emptySlot
                groups.emptySlot[#groups.emptySlot + 1] = {
                    rec = rec, slotName = slotName, penalty = W.emptySlot,
                    title  = format(L["You are wearing nothing on your %s"], slotName),
                    detail = L["This slot is completely empty, so it gives you no armor and no stats at all."],
                    fix    = level < 40
                        and L["Put anything in it. Look in your bags first, then any town vendor. At your level a plain green costs silver, not gold."]
                        or L["Put anything in it. Even a cheap auction house item beats an empty slot. Check your bags first, you may already own something."],
                }
            end
        else
            -- The COUNT is always the truth. Only the advice and the score are
            -- level gated. Counting only above the threshold made the summary
            -- read "0 missing enchants" for a level 27 character who was in
            -- fact missing eight of them, while the slot tooltip right next to
            -- it said the enchant was missing. A panel that contradicts itself
            -- is worse than one that says nothing.
            local enchantMissing = rec.enchantable and not rec.enchanted
            if enchantMissing then
                counts.missingEnchants = counts.missingEnchants + 1
            end

            if enchantMissing and level >= ENCHANT_WORTH_IT then
                penalty = penalty + W.missingEnch
                groups.missingEnch[#groups.missingEnch + 1] = {
                    rec = rec, slotName = slotName, penalty = W.missingEnch,
                    title  = format(L["No enchant on your %s"], slotName),
                    detail = L["An enchant is a permanent bonus added on top of an item. This one has none, so you are missing free stats."],
                    -- Head and shoulder enchants come from reputation, and the
                    -- extracted catalogue knows exactly which factions sell
                    -- them and at what standing. Where it can answer, its
                    -- specific line replaces the vague one below. That answer
                    -- names a faction and a standing the client supplies, so
                    -- it is left in the client's own words.
                    fix    = (ns.DescribeEnchantSource and ns.DescribeEnchantSource(rec.slotID))
                             or L[ENCHANT_SOURCE[rec.slotID]]
                             or L["Ask an enchanter to add a permanent enchant to this slot."],
                }
            end

            -- empty gem sockets
            if rec.emptySockets and rec.emptySockets > 0 and level >= SOCKETS_EXIST then
                counts.emptySockets = counts.emptySockets + rec.emptySockets
                local p = W.emptySocket * rec.emptySockets
                penalty = penalty + p
                -- One complete sentence per count rather than a stem plus an
                -- "s". English pluralises by suffix, most languages do not.
                local socketTitle
                if rec.emptySockets == 1 then
                    socketTitle = format(L["1 empty gem slot on your %s"], slotName)
                else
                    socketTitle = format(L["%d empty gem slots on your %s"], rec.emptySockets, slotName)
                end
                groups.emptySocket[#groups.emptySocket + 1] = {
                    rec = rec, slotName = slotName, penalty = p,
                    emptySockets = rec.emptySockets, sockets = rec.sockets or 0, gemsFilled = rec.gemsFilled or 0,
                    title  = socketTitle,
                    detail = format(L["This item has %d gem holes and only %d of them have a gem in. Empty holes give you nothing."],
                                     rec.sockets or 0, rec.gemsFilled or 0),
                    fix    = L["Gems drop in dungeons and sell for a few silver at the auction house. Right click a gem, then click the item, and it snaps in. Even the cheapest gem beats an empty hole."],
                }
            end

            -- wrong armor class
            if scan.wantArmor and rec.classID == 4 and rec.subClassID
               and rec.subClassID >= 1 and rec.subClassID <= 4
               and rec.subClassID < scan.wantArmor and level >= 40 then
                penalty = penalty + W.wrongArmor
                Add(issues, SEV.CRITICAL, rec,
                    format(L["Your %s is the wrong kind of armor"], slotName),
                    format(L["You are wearing %s here, but from level 40 a %s can wear %s, which has far more armor on it."],
                           ns.ARMOR_NAMES[rec.subClassID] or L["light armor"],
                           className,
                           ns.ARMOR_NAMES[scan.wantArmor] or L["heavier armor"]),
                    format(L["Look for %s instead. You are giving away a large amount of protection for nothing."],
                           ns.ARMOR_NAMES[scan.wantArmor] or L["your armor type"]),
                    W.wrongArmor)
            end

            -- green or white item at the level cap
            if level >= 68 and rec.quality and rec.quality < 3 then
                penalty = penalty + W.lowQuality
                groups.lowQuality[#groups.lowQuality + 1] = {
                    rec = rec, slotName = slotName, penalty = W.lowQuality,
                    title  = format(L["Your %s is a low quality item"], slotName),
                    detail = format(L["%s is a green or white item and you are level %d. Items are colour coded, and green is the second weakest tier."],
                                     rec.name or L["This item"], level),
                    fix    = L["Blue items from normal and heroic dungeons are a large step up and cost nothing but time. Crafted gear and reputation rewards work too."],
                }

            -- much worse than everything else you own
            elseif scan.medianIlvl and scan.medianIlvl > 0
                   and rec.ilvl and rec.ilvl < (scan.medianIlvl - slack) then
                counts.weakItems = counts.weakItems + 1
                penalty = penalty + W.weakLink
                -- Naming a real drop is worth far more than "go upgrade it".
                -- Bounded and cached, and it only runs for the weak link,
                -- never for every slot.
                local fix = L["Because it is so far behind everything else, replacing this one piece helps you more than upgrading anything else right now."]
                if ns.FindSlotUpgrades then
                    local ok, drops = pcall(ns.FindSlotUpgrades, rec.slotID, rec.ilvl or 0, 2)
                    if ok and drops and #drops > 0 then
                        local first = drops[1]
                        -- Boss, dungeon and item names come from the loot data
                        -- and from the client, so they are placed into the
                        -- sentence untouched.
                        local where = (first.boss and first.boss ~= "" and first.boss ~= "Trash")
                            and format(L["%s in %s"], first.boss, first.instance)
                            or first.instance
                        -- Four templates rather than one with an article
                        -- glued on. "the" in front of an item name is English
                        -- grammar and has no equivalent to paste in elsewhere,
                        -- so each case is a whole sentence of its own.
                        if #drops > 1 then
                            fix = first.name
                                and format(L["%s drops the %s at item level %d, and GearScout knows of %d more for this slot at your level."],
                                    where, first.name, first.ilvl, #drops - 1)
                                or format(L["%s drops an upgrade at item level %d, and GearScout knows of %d more for this slot at your level."],
                                    where, first.ilvl, #drops - 1)
                        else
                            fix = first.name
                                and format(L["%s drops the %s at item level %d, which would replace this."],
                                    where, first.name, first.ilvl)
                                or format(L["%s drops an upgrade at item level %d, which would replace this."],
                                    where, first.ilvl)
                        end
                    end
                end

                Add(issues, SEV.WARN, rec,
                    format(L["Your %s is the weakest thing you are wearing"], slotName),
                    format(L["Item level is a simple power number printed on every item. This one is %d, while the rest of your gear averages %d."],
                           rec.ilvl or 0, ns.Round(scan.medianIlvl)),
                    fix,
                    W.weakLink)

            -- simply too old for your level
            elseif rec.ilvl and rec.ilvl > 0 and rec.ilvl < expectFloor - 8 then
                penalty = penalty + W.outdated
                groups.outdated[#groups.outdated + 1] = {
                    rec = rec, slotName = slotName, penalty = W.outdated, ilvl = rec.ilvl,
                    title  = format(L["Your %s is out of date"], slotName),
                    detail = format(L["It is item level %d. At level %d you should be wearing something around item level %d."],
                                     rec.ilvl, level, expectFloor),
                    fix    = L["Almost any quest reward or dungeon drop in the zone you are questing in right now will be better than this."],
                }
            end

            -- stats the class cannot use, only worth raising once gear matters
            if junkSet and level >= 60 then
                local stats = ns.GetStats(rec.link)
                if stats then
                    local worst, worstVal = nil, 0
                    for key, val in pairs(stats) do
                        if junkSet[key] and val and val > worstVal then
                            worst, worstVal = key, val
                        end
                    end
                    if worst and worstVal >= 5 then
                        penalty = penalty + W.junkStats
                        groups.junkStats[#groups.junkStats + 1] = {
                            rec = rec, slotName = slotName, penalty = W.junkStats,
                            statLabel = STAT_LABEL[worst] or worst,
                            title  = format(L["Your %s has stats a %s cannot use"], slotName, className),
                            detail = format(L["It gives %s %d. A %s gets no benefit at all from %s, so that part of the item is doing nothing for you."],
                                             STAT_LABEL[worst] or worst, worstVal, className,
                                             (STAT_LABEL[worst] or worst):lower()),
                            -- The stat list is a run of client stat names with
                            -- one connective word between them, so the whole
                            -- phrase is translated but every name in it is not.
                            fix    = format(L["Not urgent on its own. It does mean that when you find a piece with %s on it, that piece will be a clear upgrade."],
                                             L[WANT_INSTEAD[scan.class]] or L["your class stats"]),
                        }
                    end
                end
            end

            -- broken gear
            if rec.durability and rec.durability <= 0.05 then
                penalty = penalty + W.broken
                Add(issues, SEV.CRITICAL, rec,
                    format(L["Your %s is broken"], slotName),
                    format(L["Durability is at %d percent. A broken item gives zero armor and zero stats until it is fixed."],
                           ns.Round(rec.durability * 100)),
                    L["Visit any repair vendor, the ones with a small anvil icon on the map, and click the repair all button."],
                    W.broken)
            end

            -- temporary weapon buff hides the real answer
            if rec.tempEnchant then
                Add(issues, SEV.INFO, rec,
                    format(L["Cannot check the enchant on your %s right now"], slotName),
                    L["A temporary buff such as a sharpening stone, an oil or a poison is on this weapon, and it hides the permanent enchant underneath."],
                    L["Nothing to do. GearScout will check this slot again once the temporary buff wears off."],
                    0)
            end
        end
    end

    -- Turn each bucket of repeated per slot rules into one row. A single hit
    -- keeps the exact wording the slot loop would have used. More than one
    -- becomes a single row naming every affected slot, with the penalty
    -- points added together so the score is unchanged either way.
    if #groups.emptySlot > 0 and not EmitGroupSingle(issues, groups.emptySlot, SEV.CRITICAL) then
        local names = GroupSlotNames(groups.emptySlot)
        Add(issues, SEV.CRITICAL, nil,
            format(L["You are wearing nothing on %d slots: %s"], #groups.emptySlot, JoinList(names)),
            L["These slots are completely empty, so together they give you no armor and no stats at all."],
            level < 40
                and L["Put anything in each of them. Look in your bags first, then any town vendor. At your level plain greens cost silver, not gold."]
                or L["Put anything in each of them. Even a cheap auction house item beats an empty slot. Check your bags first, you may already own some of these."],
            GroupPenalty(groups.emptySlot))
    end

    if #groups.missingEnch > 0 and not EmitGroupSingle(issues, groups.missingEnch, SEV.WARN) then
        local names = GroupSlotNames(groups.missingEnch)
        -- Rank the slots by how much an enchant there is actually worth, so
        -- the fix line tells the player where their gold goes furthest.
        local ranked = {}
        for _, it in ipairs(groups.missingEnch) do ranked[#ranked + 1] = it end
        table.sort(ranked, function(a, b)
            local pa = ENCHANT_PRIORITY[a.rec and a.rec.slotID] or 99
            local pb = ENCHANT_PRIORITY[b.rec and b.rec.slotID] or 99
            if pa ~= pb then return pa < pb end
            return (a.rec and a.rec.order or 99) < (b.rec and b.rec.order or 99)
        end)
        local top = ranked[1]
        local restNames = {}
        for i = 2, #ranked do restNames[#restNames + 1] = ranked[i].slotName end
        Add(issues, SEV.WARN, nil,
            format(L["No enchant on %d slots: %s"], #groups.missingEnch, JoinList(names)),
            L["An enchant is a permanent bonus added on top of an item. None of these have one, so you are missing free stats on every one of them."],
            format(L["Start with your %s: %s%s"], top.slotName,
                   (ns.DescribeEnchantSource and top.rec and ns.DescribeEnchantSource(top.rec.slotID))
                   or L[ENCHANT_SOURCE[top.rec and top.rec.slotID]]
                   or L["Ask an enchanter to add a permanent enchant to this slot."],
                   #restNames > 0 and format(L[" Then do the rest when you can afford it: %s."], JoinList(restNames)) or ""),
            GroupPenalty(groups.missingEnch))
    end

    if #groups.emptySocket > 0 and not EmitGroupSingle(issues, groups.emptySocket, SEV.WARN) then
        local names = GroupSlotNames(groups.emptySocket)
        local totalEmpty, totalSockets, totalFilled = 0, 0, 0
        for _, it in ipairs(groups.emptySocket) do
            totalEmpty = totalEmpty + it.emptySockets
            totalSockets = totalSockets + it.sockets
            totalFilled = totalFilled + it.gemsFilled
        end
        Add(issues, SEV.WARN, nil,
            totalEmpty == 1
                and format(L["1 empty gem slot across %d items: %s"], #groups.emptySocket, JoinList(names))
                or format(L["%d empty gem slots across %d items: %s"], totalEmpty, #groups.emptySocket, JoinList(names)),
            format(L["These items have %d gem holes between them and only %d of them have a gem in. Empty holes give you nothing."],
                   totalSockets, totalFilled),
            L["Gems drop in dungeons and sell for a few silver at the auction house. Right click a gem, then click the item, and it snaps in. Even the cheapest gem beats an empty hole."],
            GroupPenalty(groups.emptySocket))
    end

    if #groups.lowQuality > 0 and not EmitGroupSingle(issues, groups.lowQuality, SEV.WARN) then
        local names = GroupSlotNames(groups.lowQuality)
        Add(issues, SEV.WARN, nil,
            format(L["%d of your items are low quality: %s"], #groups.lowQuality, JoinList(names)),
            format(L["These are green or white items and you are level %d. Green is the second weakest quality tier."], level),
            L["Blue items from normal and heroic dungeons are a large step up and cost nothing but time. Crafted gear and reputation rewards work too."],
            GroupPenalty(groups.lowQuality))
    end

    if #groups.outdated > 0 and not EmitGroupSingle(issues, groups.outdated, SEV.WARN) then
        local names = GroupSlotNames(groups.outdated)
        local minIlvl, maxIlvl = nil, nil
        for _, it in ipairs(groups.outdated) do
            if not minIlvl or it.ilvl < minIlvl then minIlvl = it.ilvl end
            if not maxIlvl or it.ilvl > maxIlvl then maxIlvl = it.ilvl end
        end
        Add(issues, SEV.WARN, nil,
            format(L["%d of your items are out of date: %s"], #groups.outdated, JoinList(names)),
            format(L["Their item levels run from %d to %d. At level %d you should be wearing something around item level %d."],
                   minIlvl, maxIlvl, level, expectFloor),
            L["Almost any quest reward or dungeon drop in the zone you are questing in right now will be better than these."],
            GroupPenalty(groups.outdated))
    end

    if #groups.junkStats > 0 and not EmitGroupSingle(issues, groups.junkStats, SEV.INFO) then
        local names = GroupSlotNames(groups.junkStats)
        local statNames, seen = {}, {}
        for _, it in ipairs(groups.junkStats) do
            if not seen[it.statLabel] then
                seen[it.statLabel] = true
                statNames[#statNames + 1] = it.statLabel
            end
        end
        Add(issues, SEV.INFO, nil,
            format(L["%d of your items have stats a %s cannot use: %s"], #groups.junkStats, className, JoinList(names)),
            format(L["Between them these items give %s. A %s gets no benefit from any of that, so that part of each item is doing nothing for you."],
                   JoinList(statNames), className),
            format(L["Not urgent on its own. It does mean that when you find pieces with %s on them, those pieces will be a clear upgrade."],
                   L[WANT_INSTEAD[scan.class]] or L["your class stats"]),
            GroupPenalty(groups.junkStats))
    end

    -- a hunter with no ranged weapon has lost most of their damage
    if scan.class == "HUNTER" then
        local ranged = scan.bySlotID[18]
        if ranged and ranged.empty then
            penalty = penalty + W.emptySlot
            Add(issues, SEV.CRITICAL, ranged,
                L["You have no bow, gun or crossbow"],
                L["A hunter does most of their damage at range. With this slot empty, your auto shot and every shot ability are unusable."],
                L["Equip a ranged weapon right now. Any vendor in a starting town sells a basic one for silver."],
                W.emptySlot)
        end
    end

    -- Level aware guidance. Scores nothing, but it is the part that turns a
    -- list of complaints into something a new player can act on today.
    if level >= 10 and level < ENCHANT_WORTH_IT then
        Add(issues, SEV.INFO, nil,
            L["Enchants and gems are being skipped on purpose"],
            format(L["At level %d your gear gets replaced every few levels, so an enchant bought now is thrown away almost immediately."], level),
            format(L["Spend the gold on bags, riding skill and your class trainer instead. GearScout starts checking enchants at level %d, when Outland gear lasts long enough to deserve one."], ENCHANT_WORTH_IT),
            0)
    end

    local upgrade = ns.UpgradeAdvice(level)
    if upgrade then
        Add(issues, SEV.INFO, nil,
            format(L["Where your next upgrades come from at level %d"], level),
            upgrade,
            L["Item level is the number GearScout compares. Anything with a higher one is an upgrade for that slot."],
            0)
    end

    -- ---------------------------------------------------------------------
    -- other providers
    --
    -- Bags, readiness gaps, quest rewards, group buffs and deaths each produce
    -- issues in this same shape. Every one is optional and every call is
    -- wrapped, so a provider that failed to load, or that throws on some
    -- client quirk, costs its own contribution and nothing else. Losing the
    -- whole gear report because a bag scan tripped would be a bad trade.
    -- ---------------------------------------------------------------------
    local function Accept(it)
        if type(it) ~= "table" or not it.title then return end
        -- These come from outside, so fill in what the sort comparator needs.
        it.order = it.order or 90
        it.penalty = it.penalty or 0
        it.sev = it.sev or SEV.INFO

        -- If the issue is about a specific item and that item is known dungeon
        -- loot, say where it came from. One place to do this beats repeating
        -- it in every provider, and it is an O(1) table lookup. Only applied
        -- to provider issues, never to a slot the player is already wearing,
        -- where naming the drop would be noise.
        if it.link and ns.DescribeItemSource and not it.sourceAdded then
            local itemID = ns.ParseLink and ns.ParseLink(it.link)
            local where = itemID and ns.DescribeItemSource(itemID)
            if where then
                it.detail = (it.detail and (it.detail .. " ") or "") .. where
                it.sourceAdded = true
            end
        end

        issues[#issues + 1] = it
    end

    local function Provide(fn, many)
        if type(fn) ~= "function" then return end
        local ok, result = pcall(fn)
        if not ok or not result then return end
        if many then
            for i = 1, #result do Accept(result[i]) end
        else
            Accept(result)
        end
    end

    Provide(ns.GetReadinessIssues, true)
    Provide(ns.GetBagUpgradeIssue, false)
    Provide(ns.GetQuestUpgradeIssue, false)
    Provide(ns.GetBuffIssue, false)
    Provide(ns.GetDeathIssue, false)

    table.sort(issues, function(a, b)
        if a.sev ~= b.sev then return a.sev < b.sev end
        if a.penalty ~= b.penalty then return a.penalty > b.penalty end
        return (a.order or 90) < (b.order or 90)
    end)

    local score = ns.Clamp(100 - penalty, 0, 100)
    local grade, gradeColor = ns.Grade(score)

    local report = {
        score       = score,
        grade       = grade,
        gradeColor  = gradeColor,
        issues      = issues,
        counts      = counts,
        avgIlvl     = scan.avgIlvl or 0,
        medianIlvl  = scan.medianIlvl or 0,
        level       = level,
        class       = scan.class,
        scannedAt   = scan.scannedAt,
    }

    ns.lastReport = report
    return report
end

function ns.Evaluate()
    local scan = ns.ScanEquipment()
    return ns.Analyze(scan), scan
end
