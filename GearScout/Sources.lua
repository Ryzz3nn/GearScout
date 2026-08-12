-- GearScout / Sources.lua
-- Answers "where do I actually get one" from the shipped data tables.
--
-- Two questions, both cheap:
--   which faction sells the enchant for this slot, and at what standing
--   where did this item drop, and what else drops for this slot near my level
--
-- Everything here reads generated data that is already in memory. Nothing
-- calls the network, because an addon cannot, and nothing scans in a refresh
-- path. The one loop that could be expensive is bounded by level and cached.

local ADDON, ns = ...

local ipairs, pairs, type, wipe = ipairs, pairs, type, wipe
local format, sort = string.format, table.sort

-- ---------------------------------------------------------------------------
-- reputation enchants
--
-- Head and shoulder enchants are the two the addon already nags about but
-- could never place. They are recognisable from their names: a head enchant
-- is a Glyph or an Arcanum, a shoulder enchant is an Inscription. Matching on
-- the name rather than a hand written faction list means the mapping comes
-- from the extracted data and stays right if the data is regenerated.
-- ---------------------------------------------------------------------------
local HEAD_SLOT, SHOULDER_SLOT = 1, 3

local STANDING_ORDER = {
    Neutral = 1, Friendly = 2, Honored = 3, Revered = 4, Exalted = 5,
}

local function SlotForRewardName(name)
    if not name then return nil end
    if name:find("Inscription of", 1, true) then return SHOULDER_SLOT end
    if name:find("Glyph of", 1, true) or name:find("Arcanum of", 1, true) then
        return HEAD_SLOT
    end
    return nil
end

local enchantsBySlot   -- built once, on first use
local function BuildEnchantIndex()
    if enchantsBySlot then return enchantsBySlot end
    enchantsBySlot = { [HEAD_SLOT] = {}, [SHOULDER_SLOT] = {} }

    local rep = ns.REP_REWARDS
    if type(rep) ~= "table" then return enchantsBySlot end

    for factionName, faction in pairs(rep) do
        local rewards = type(faction) == "table" and faction.rewards
        if type(rewards) == "table" then
            for _, r in ipairs(rewards) do
                local slot = SlotForRewardName(r and r.name)
                if slot then
                    local list = enchantsBySlot[slot]
                    list[#list + 1] = {
                        name     = r.name,
                        itemID   = r.item,
                        faction  = factionName,
                        standing = r.standing,
                        rank     = STANDING_ORDER[r.standing] or 9,
                    }
                end
            end
        end
    end

    -- Lowest standing first, because the cheapest one to reach is the one
    -- worth telling somebody about.
    for _, list in pairs(enchantsBySlot) do
        sort(list, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            return (a.name or "") < (b.name or "")
        end)
    end
    return enchantsBySlot
end

-- Every reputation enchant that fits this slot, easiest standing first.
function ns.GetEnchantSources(slotID)
    local idx = BuildEnchantIndex()
    return idx[slotID] or {}
end

-- One plain English sentence naming who sells the enchant for this slot.
-- Returns nil when the data has nothing, so the caller keeps its old wording.
function ns.DescribeEnchantSource(slotID)
    local list = ns.GetEnchantSources(slotID)
    if #list == 0 then return nil end

    -- Collect the distinct factions at the easiest standing that has any.
    local best = list[1].rank
    local seen, names = {}, {}
    for _, e in ipairs(list) do
        if e.rank == best and not seen[e.faction] then
            seen[e.faction] = true
            names[#names + 1] = e.faction
        end
    end
    sort(names)

    local who
    if #names == 1 then
        who = names[1]
    elseif #names == 2 then
        who = names[1] .. " or " .. names[2]
    else
        who = format("%s, %s, or one of %d other factions",
            names[1], names[2], #names - 2)
    end

    local slotWord = (slotID == HEAD_SLOT) and "head" or "shoulder"
    return format(
        "Reach %s standing with %s and buy the %s enchant from their quartermaster. You pay once and it never wears off. GearScout knows of %d different ones for this slot.",
        (list[1].standing or "the required"):lower(), who, slotWord, #list)
end

-- ---------------------------------------------------------------------------
-- where an item came from
-- ---------------------------------------------------------------------------

-- O(1). Returns instance and boss, or nil when the item is not dungeon loot.
function ns.GetItemSource(itemID)
    if not itemID or type(ns.DUNGEON_LOOT) ~= "table" then return nil end
    local rec = ns.DUNGEON_LOOT[itemID]
    if not rec then return nil end
    return rec.d, rec.b
end

function ns.DescribeItemSource(itemID)
    local instance, boss = ns.GetItemSource(itemID)
    if not instance then return nil end
    if boss and boss ~= "" and boss ~= "Trash" then
        return format("Drops from %s in %s.", boss, instance)
    end
    return format("Drops in %s.", instance)
end

-- ---------------------------------------------------------------------------
-- what could replace this slot
--
-- Bounded deliberately. Only instances whose level range suits the character
-- are considered, and only items the client has already cached are inspected,
-- because asking the server about thousands of uncached items to answer a
-- cosmetic question would be rude to both the client and the player.
-- ---------------------------------------------------------------------------
local upgradeCache = {}

local function InstancesForLevel(level)
    local out = {}
    if type(ns.DUNGEON_INFO) ~= "table" then return out end
    for name, range in pairs(ns.DUNGEON_INFO) do
        local min = range and (range.min or range[1])
        local max = range and (range.max or range[2])
        if type(min) == "number" and type(max) == "number" then
            -- A little slack below, since a dungeon slightly above the
            -- character is exactly where the upgrades are.
            if level >= (min - 4) and level <= (max + 2) then
                out[name] = true
            end
        end
    end
    return out
end

-- Returns up to `limit` items that beat `minIlvl` in this slot, each with the
-- instance and boss that drops it. Empty when nothing is known, which is a
-- normal answer rather than a failure.
function ns.FindSlotUpgrades(slotID, minIlvl, limit)
    limit = limit or 5
    if type(ns.DUNGEON_LOOT) ~= "table" then return {} end

    local level = ns.playerLevel or UnitLevel("player") or 1
    local key = format("%d:%d:%d", slotID or 0, minIlvl or 0, level)
    local cached = upgradeCache[key]
    if cached then return cached end

    local def = ns.SLOT_BY_ID and ns.SLOT_BY_ID[slotID]
    if not def then return {} end

    local wanted = InstancesForLevel(level)
    local found = {}
    local pending = 0

    -- ItemDB ships item level, required level, class and subclass for 14,949
    -- items, but NOT equip location, so it cannot name a slot on its own. What
    -- it can do is reject the overwhelming majority before the client is
    -- troubled: wrong item level, wrong armor type, too high a level
    -- requirement. Only the handful that survive get asked about, and asking
    -- caches them, so the answer improves each time it is run.
    local db = ns.ITEM_DB
    local armorWant = ns.lastScan and ns.lastScan.wantArmor

    for itemID, rec in pairs(ns.DUNGEON_LOOT) do
        if rec and wanted[rec.d] then
            local worthAsking = true
            local dbIlvl

            local d = db and db[itemID]
            if d then
                dbIlvl = d.i
                -- class 2 is weapons, 4 is armor. Anything else cannot fill a
                -- gear slot, whatever else it may be.
                if d.c ~= 2 and d.c ~= 4 then worthAsking = false end
                if worthAsking and dbIlvl and dbIlvl <= (minIlvl or 0) then worthAsking = false end
                if worthAsking and d.r and d.r > level then worthAsking = false end
                -- Do not suggest plate to a mage. Armor subclasses 1 to 4 are
                -- cloth, leather, mail and plate, and the slot table already
                -- knows which one this character should be wearing.
                if worthAsking and d.c == 4 and armorWant and d.s
                   and d.s >= 1 and d.s <= 4 and d.s ~= armorWant
                   and def.armor then
                    worthAsking = false
                end
            end

            if worthAsking then
                local meta = ns.GetItemMeta(itemID)
                if not meta then
                    -- Not cached yet. GetItemMeta has queued it, so it will be
                    -- answerable next time rather than lost.
                    pending = pending + 1
                elseif meta.ilvl and meta.ilvl > (minIlvl or 0)
                       and meta.equipLoc and meta.equipLoc ~= "" then
                    local target = ns.SLOT_FOR_EQUIPLOC and ns.SLOT_FOR_EQUIPLOC[meta.equipLoc]
                    if target == slotID then
                        found[#found + 1] = {
                            itemID   = itemID,
                            name     = meta.name,
                            ilvl     = meta.ilvl,
                            instance = rec.d,
                            boss     = rec.b,
                        }
                    end
                end
            end
        end
    end

    found.pending = pending

    sort(found, function(a, b) return a.ilvl > b.ilvl end)
    for i = #found, limit + 1, -1 do found[i] = nil end

    upgradeCache[key] = found
    return found
end

-- Equipment changes invalidate the "what beats this" answers.
ns:Sub("SCAN_UPDATED", function() wipe(upgradeCache) end)
