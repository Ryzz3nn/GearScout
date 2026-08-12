-- GearScout / Collector.lua
-- Records game facts the player's session observes: which creature drops
-- which item and where, an item's resolved level/quality/slot/required
-- level, which items a quest can reward, and vendor prices seen while a
-- merchant window is open. Everything recorded is a fact about the game
-- world. See the privacy note above the event handlers below.
--
-- This never talks to the network. WoW addons cannot make HTTP requests, so
-- the only path this data takes out of the game is:
--   this file writes to GearScoutData (a SavedVariables table)
--   -> tools/export-session.mjs reads that file after the session ends
--   -> uploads it to Turso
--   -> a later build step turns the database back into a Lua data file
--   -> that file ships inside the addon on the next update
-- Nothing here should be written as though a live lookup were possible.

local ADDON, ns = ...

local GetNumLootItems, GetLootSlotLink = GetNumLootItems, GetLootSlotLink
local GetLootSourceInfo = _G.GetLootSourceInfo
local GetItemInfo = GetItemInfo
local GetQuestID = _G.GetQuestID
local GetNumQuestChoices, GetNumQuestRewards = _G.GetNumQuestChoices, _G.GetNumQuestRewards
local GetQuestItemLink = _G.GetQuestItemLink
local GetMerchantNumItems, GetMerchantItemInfo, GetMerchantItemLink =
    _G.GetMerchantNumItems, _G.GetMerchantItemInfo, _G.GetMerchantItemLink
local UnitGUID, GetZoneText = UnitGUID, GetZoneText
local C_Map = _G.C_Map
local strsplit, tonumber, pairs, type, time, wipe, format =
    strsplit, tonumber, pairs, type, time, wipe, format
local floor = math.floor

-- ---------------------------------------------------------------------------
-- caps
-- Each table below counts distinct rows, matching the natural key it becomes
-- in SQL. Once a cap is hit, brand new rows stop being added, but a row
-- already known is still refreshed in place, so a long session cannot bloat
-- the saved variables file without bound and a zone explored early is not
-- penalised for having been seen first.
-- ---------------------------------------------------------------------------
local MAX_DROPS         = 5000 -- distinct (item, creature) pairs
local MAX_ITEMS         = 5000 -- distinct items with resolved metadata
local MAX_QUEST_REWARDS = 2000 -- distinct (quest, item) pairs
local MAX_VENDOR_PRICES = 3000 -- distinct (item, vendor) pairs
local MAX_TRAINER       = 4000 -- distinct (class, spell, rank) triples

-- ---------------------------------------------------------------------------
-- saved variable shape
-- GearScoutData = {
--   v = 1,
--   drops         = { [itemID] = { [creatureID] = { zone, zoneName, t } } },
--   items         = { [itemID] = { ilvl, quality, equipLoc, reqLevel, t } },
--   questRewards  = { [questID] = { [itemID] = t } },
--   vendorPrices  = { [itemID] = { [vendorID] = { price, t } } },
--   trainerSpells = { [classFile] = { [spellName] = { [rank] = { level, t } } } },
--   counts        = { drops, items, questRewards, vendorPrices, trainerSpells },
-- }
-- ---------------------------------------------------------------------------
local function EnsureTable(t, key)
    if type(t[key]) ~= "table" then t[key] = {} end
    return t[key]
end

ns:On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    GearScoutData = GearScoutData or {}
    GearScoutData.v = 1
    -- Spell and item names are localized, so the upload has to know which
    -- language produced them or two clients would overwrite each other.
    GearScoutData.locale = (_G.GetLocale and GetLocale()) or "enUS"
    EnsureTable(GearScoutData, "drops")
    EnsureTable(GearScoutData, "items")
    EnsureTable(GearScoutData, "questRewards")
    EnsureTable(GearScoutData, "vendorPrices")
    EnsureTable(GearScoutData, "trainerSpells")
    local counts = EnsureTable(GearScoutData, "counts")
    counts.drops        = counts.drops or 0
    counts.items         = counts.items or 0
    counts.questRewards  = counts.questRewards or 0
    counts.vendorPrices  = counts.vendorPrices or 0
    counts.trainerSpells = counts.trainerSpells or 0
end)

-- ---------------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------------

-- Reads the numeric item id out of an item link or itemString.
local function ExtractItemID(link)
    if not link then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

-- A creature or vehicle GUID only. A player GUID (or anything else) returns
-- nil here, which is the enforcement point for the privacy boundary: nothing
-- downstream of this function can ever end up with a person's identity,
-- because a player's GUID never survives the type check.
local function CreatureIDFromGUID(guid)
    if not guid then return nil end
    local kind, _, _, _, _, npcID = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(npcID)
end

local function ResolveZone()
    local id, name
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and mapID then
            id = mapID
            if C_Map.GetMapInfo then
                local ok2, info = pcall(C_Map.GetMapInfo, mapID)
                if ok2 and info then name = info.name end
            end
        end
    end
    if not name and GetZoneText then name = GetZoneText() end
    return id, name
end

-- Adds or refreshes root[key1][key2] = value. Refreshing an existing row is
-- always allowed regardless of the cap; only a brand new row is rejected
-- once counts[counterKey] reaches max, and rejecting one never creates a
-- dangling empty table so the row count stays an honest measure of size.
local function SetNested(root, key1, key2, value, counts, counterKey, max)
    local level1 = root[key1]
    local isNew = not level1 or level1[key2] == nil
    if isNew then
        if counts[counterKey] >= max then return end
        if not level1 then
            level1 = {}
            root[key1] = level1
        end
        counts[counterKey] = counts[counterKey] + 1
    end
    level1[key2] = value
end

-- ---------------------------------------------------------------------------
-- item metadata
-- GetItemInfo misses on anything the client has not cached yet, so a miss is
-- queued and resolved the moment the client fills it in.
-- ---------------------------------------------------------------------------
local pendingItems = {}

local function RecordItemMeta(itemID, ilvl, quality, equipLoc, reqLevel)
    local items, counts = GearScoutData.items, GearScoutData.counts
    if items[itemID] == nil then
        if counts.items >= MAX_ITEMS then return end
        counts.items = counts.items + 1
    end
    items[itemID] = {
        ilvl     = ilvl or 0,
        quality  = quality or 0,
        equipLoc = equipLoc or "",
        reqLevel = reqLevel or 0,
        t        = time(),
    }
end

local function ResolveItemMeta(itemID)
    if not itemID or not GearScoutData then return end
    local name, _, quality, ilvl, reqLevel, _, _, _, equipLoc = GetItemInfo(itemID)
    if not name then
        pendingItems[itemID] = true
        return
    end
    RecordItemMeta(itemID, ilvl, quality, equipLoc, reqLevel)
end

ns:On("GET_ITEM_INFO_RECEIVED", function(itemID)
    if itemID and pendingItems[itemID] then
        pendingItems[itemID] = nil
        ResolveItemMeta(itemID)
    end
end)

-- ---------------------------------------------------------------------------
-- drops
-- LOOT_OPENED fires once per loot window, with no combat log involved.
-- GetLootSourceInfo hands back the corpse's own GUID, which is where the
-- creature id comes from, never from who is standing nearby or who looted.
-- ---------------------------------------------------------------------------
local function RecordDrop(itemID, creatureID, zoneID, zoneName)
    SetNested(GearScoutData.drops, itemID, creatureID,
        { zone = zoneID, zoneName = zoneName, t = time() },
        GearScoutData.counts, "drops", MAX_DROPS)
end

ns:On("LOOT_OPENED", function()
    if not GearScoutData then return end
    local zoneID, zoneName = ResolveZone()
    local n = GetNumLootItems and GetNumLootItems() or 0
    for slot = 1, n do
        local itemID = ExtractItemID(GetLootSlotLink(slot))
        if itemID then
            local creatureID
            if GetLootSourceInfo then
                local ok, guid = pcall(GetLootSourceInfo, slot)
                if ok and guid then creatureID = CreatureIDFromGUID(guid) end
            end
            if creatureID then
                RecordDrop(itemID, creatureID, zoneID, zoneName)
            end
            ResolveItemMeta(itemID)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- quest rewards
-- QUEST_COMPLETE is the turn in screen showing both choice and guaranteed
-- rewards. Nothing about who the quest giver is gets recorded, only the
-- quest id and the item ids it can hand out.
-- ---------------------------------------------------------------------------
local function RecordQuestReward(questID, itemID)
    SetNested(GearScoutData.questRewards, questID, itemID, time(),
        GearScoutData.counts, "questRewards", MAX_QUEST_REWARDS)
end

ns:On("QUEST_COMPLETE", function()
    if not GearScoutData or not GetQuestID then return end
    local questID = GetQuestID()
    if not questID or questID == 0 then return end

    local nChoices = GetNumQuestChoices and GetNumQuestChoices() or 0
    local nRewards = GetNumQuestRewards and GetNumQuestRewards() or 0

    for i = 1, nChoices do
        local itemID = ExtractItemID(GetQuestItemLink and GetQuestItemLink("choice", i))
        if itemID then
            RecordQuestReward(questID, itemID)
            ResolveItemMeta(itemID)
        end
    end
    for i = 1, nRewards do
        local itemID = ExtractItemID(GetQuestItemLink and GetQuestItemLink("reward", i))
        if itemID then
            RecordQuestReward(questID, itemID)
            ResolveItemMeta(itemID)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- vendor prices
-- MERCHANT_SHOW fires once per open merchant window. Extended cost items
-- (tokens, reputation, etc) are skipped since their price is not a copper
-- amount. vendorID falls back to 0 when the open target is not a resolvable
-- creature GUID, so the row is still useful without inventing an identity.
--
-- GetMerchantItemInfo returns the price of the whole stack it sells, not the
-- price of one item, and the stack size is the fourth return. A vendor
-- selling five of something for 500 copper was being recorded as 500 copper
-- per item rather than 100, so the stack size is divided out here. Every
-- consumer of this table treats the number as one item's price in copper
-- (tools/export-session.mjs writes it to vendor_prices.price_copper), so the
-- unit price is the only value that belongs in it.
-- ---------------------------------------------------------------------------
local function RecordVendorPrice(itemID, vendorID, price)
    SetNested(GearScoutData.vendorPrices, itemID, vendorID or 0,
        { price = price, t = time() },
        GearScoutData.counts, "vendorPrices", MAX_VENDOR_PRICES)
end

ns:On("MERCHANT_SHOW", function()
    if not GearScoutData or not GetMerchantNumItems then return end
    local vendorID = CreatureIDFromGUID(UnitGUID("target"))
    local n = GetMerchantNumItems() or 0
    for i = 1, n do
        local name, _, price, quantity, _, _, extendedCost = GetMerchantItemInfo(i)
        if name and price and price > 0 and not extendedCost then
            local stack = (type(quantity) == "number" and quantity > 0) and quantity or 1
            local unitPrice = floor(price / stack)
            local itemID = ExtractItemID(GetMerchantItemLink and GetMerchantItemLink(i))
            if itemID and unitPrice > 0 then
                RecordVendorPrice(itemID, vendorID, unitPrice)
                ResolveItemMeta(itemID)
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- class trainer spell ranks
--
-- This one exists because the data cannot be obtained any other way. AtlasLoot
-- carries no spell data, and Wowhead is JavaScript rendered so its rank tables
-- cannot be fetched. But a trainer window hands the client every spell it
-- offers along with the level it unlocks at, which is exactly the rank to
-- level mapping wanted, and it costs nothing to read while a player is
-- standing there anyway.
--
-- Profession trainers offer recipes rather than ranked spells, so requiring
-- both a rank number and a level requirement naturally selects class spells
-- and leaves recipes alone.
--
-- The trainer's own filter settings are read, never written. Changing them to
-- see more rows would silently rearrange the player's UI.
-- ---------------------------------------------------------------------------
local function RecordTrainerSpell(classFile, spellName, rank, level)
    local byClass = EnsureTable(GearScoutData.trainerSpells, classFile)
    SetNested(byClass, spellName, rank, { level = level, t = time() },
        GearScoutData.counts, "trainerSpells", MAX_TRAINER)
end

ns:On("TRAINER_SHOW", function()
    if not GearScoutData then return end
    if not _G.GetNumTrainerServices or not _G.GetTrainerServiceInfo then return end

    local classFile = ns.playerClass
    if not classFile then return end

    local okCount, total = pcall(_G.GetNumTrainerServices)
    if not okCount or not total or total < 1 then return end

    for i = 1, total do
        local okInfo, name, subText = pcall(_G.GetTrainerServiceInfo, i)
        if okInfo and name and subText then
            -- subText reads like "Rank 4" in English and the equivalent
            -- elsewhere, so the digits are taken rather than the words.
            local rank = tonumber(subText:match("(%d+)"))
            local level
            if _G.GetTrainerServiceLevelReq then
                local okLvl, req = pcall(_G.GetTrainerServiceLevelReq, i)
                if okLvl then level = tonumber(req) end
            end
            if rank and level and level > 0 then
                RecordTrainerSpell(classFile, name, rank, level)
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- public surface
-- ---------------------------------------------------------------------------
ns.Collector = {}

-- { drops, items, questRewards, vendorPrices, trainerSpells, total }
function ns.Collector.GetCounts()
    local c = GearScoutData and GearScoutData.counts
    if not c then
        return { drops = 0, items = 0, questRewards = 0, vendorPrices = 0,
                 trainerSpells = 0, total = 0 }
    end
    local drops, items, quests, vendor, trainer =
        c.drops or 0, c.items or 0, c.questRewards or 0, c.vendorPrices or 0,
        c.trainerSpells or 0
    return {
        drops         = drops,
        items         = items,
        questRewards  = quests,
        vendorPrices  = vendor,
        trainerSpells = trainer,
        total         = drops + items + quests + vendor + trainer,
    }
end

-- One line summary, for a slash command or debug print elsewhere.
function ns.Collector.Report()
    local c = ns.Collector.GetCounts()
    return format("drops:%d items:%d questRewards:%d vendorPrices:%d trainerSpells:%d (total %d)",
        c.drops, c.items, c.questRewards, c.vendorPrices, c.trainerSpells, c.total)
end

-- Wipes everything gathered this session. Does not touch any other saved
-- variable.
function ns.Collector.Clear()
    if not GearScoutData then return end
    wipe(GearScoutData.drops)
    wipe(GearScoutData.items)
    wipe(GearScoutData.questRewards)
    wipe(GearScoutData.vendorPrices)
    GearScoutData.counts.drops        = 0
    GearScoutData.counts.items        = 0
    GearScoutData.counts.questRewards = 0
    GearScoutData.counts.vendorPrices = 0
end
