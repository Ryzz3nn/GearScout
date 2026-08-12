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

-- Drop chance, when it is actually known. Coverage is uneven on purpose:
-- the classic dungeons a levelling character runs are well covered, while
-- TBC boss loot mostly is not, because that data is stored as weighted
-- groups whose values did not survive checking against reality. Saying
-- nothing beats printing a percentage that is wrong.
-- An item can drop from several creatures at different rates, so the table
-- holds a list per item. The best chance is the useful one to quote, since
-- that is the kill worth farming.
function ns.GetDropChance(itemID)
    if not itemID or type(ns.DROP_RATES) ~= "table" then return nil end
    local list = ns.DROP_RATES[itemID]
    if type(list) ~= "table" then return nil end

    local bestPct, bestWho
    for _, rec in ipairs(list) do
        local pct = rec and rec.p
        if type(pct) == "number" and (not bestPct or pct > bestPct) then
            bestPct, bestWho = pct, rec.c
        end
    end
    return bestPct, bestWho
end

-- The source data names a category rather than a creature for loot that is
-- not tied to one kill. Both spellings appear in it, so both are recognised
-- here rather than only the common one.
local TRASH_SOURCE = {
    ["Trash"] = true,
    ["Trash Mobs"] = true,
}

function ns.DescribeItemSource(itemID)
    local instance, boss = ns.GetItemSource(itemID)
    if not instance then return nil end

    local chance = ns.GetDropChance(itemID)
    local odds = ""
    if type(chance) == "number" and chance > 0 then
        odds = format(" It drops about %s of the time.",
            chance >= 10 and format("%d percent", ns.Round(chance))
            or format("%.1f percent", chance))
    end

    -- "Trash" is the source data's own name for a wing's shared trash loot
    -- rather than a creature, and "Unknown" is what the extractor writes when
    -- a source block carries no name at all. Neither is something a player can
    -- look up in a boss table. Saying only "Drops in Razorfen Kraul" for a
    -- trash drop reads as a boss drop, which sends people hunting a boss list
    -- that will never contain the item and makes correct data look wrong.
    if TRASH_SOURCE[boss] then
        return format("Drops from trash mobs in %s, not from a boss.%s",
            instance, odds)
    end
    if boss and boss ~= "" and boss ~= "Unknown" then
        return format("Drops from %s in %s.%s", boss, instance, odds)
    end
    return format("Drops somewhere in %s.%s", instance, odds)
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

-- ItemMeta stores the client's own InventoryType number rather than the
-- INVTYPE_ string, so it needs its own mapping to our slot ids. Having this
-- means an upgrade can be matched to a slot from shipped data alone, instead
-- of only working for items the player's client happens to have cached.
local SLOT_FOR_INVTYPE = {
    [1] = 1,    -- head
    [2] = 2,    -- neck
    [3] = 3,    -- shoulder
    [5] = 5,    -- chest
    [6] = 6,    -- waist
    [7] = 7,    -- legs
    [8] = 8,    -- feet
    [9] = 9,    -- wrist
    [10] = 10,  -- hands
    [11] = 11,  -- finger, first position
    [12] = 13,  -- trinket, first position
    [13] = 16,  -- one hand weapon
    [14] = 17,  -- shield
    [15] = 18,  -- ranged, bow
    [16] = 15,  -- back
    [17] = 16,  -- two hand weapon
    [20] = 5,   -- robe counts as chest
    [21] = 16,  -- main hand
    [22] = 17,  -- off hand
    [23] = 17,  -- held in off hand
    [25] = 18,  -- thrown
    [26] = 18,  -- ranged right, gun or crossbow
    [28] = 18,  -- relic
}

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
                -- Shipped data answers the slot question outright now, so an
                -- item the client has never seen can still be matched. The
                -- client is only consulted for the name, and its absence
                -- downgrades the row rather than discarding it.
                local shipped = ns.ITEM_META and ns.ITEM_META[itemID]
                local shippedSlot = shipped and SLOT_FOR_INVTYPE[shipped.e or -1]

                if shippedSlot and shippedSlot ~= slotID then
                    -- Definitely the wrong slot. Costs nothing and asks nothing.
                elseif shippedSlot == slotID and dbIlvl then
                    local meta = ns.GetItemMeta(itemID)
                    if not meta then pending = pending + 1 end
                    found[#found + 1] = {
                        itemID   = itemID,
                        name     = meta and meta.name,
                        ilvl     = dbIlvl,
                        quality  = shipped.q,
                        instance = rec.d,
                        boss     = rec.b,
                        chance   = ns.GetDropChance(itemID),
                    }
                else
                    -- No shipped answer for this item, fall back to the client.
                    local meta = ns.GetItemMeta(itemID)
                    if not meta then
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
                                chance   = ns.GetDropChance(itemID),
                            }
                        end
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
