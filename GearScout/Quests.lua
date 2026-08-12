-- GearScout / Quests.lua
-- Scans the quest log for reward items that would upgrade a slot the player
-- is currently wearing something worse in. The point is not "here is an item
-- level number", it is "you already did the work for this, go turn it in".
--
-- Writing rule, same as Rules.lua: say what is wrong, why it matters, and
-- what to do about it, in plain words.
--
-- ---------------------------------------------------------------------------
-- quest log API shim
-- This client reports interface 20506 but runs on the current engine, where
-- GetNumQuestLogEntries, GetQuestLogTitle and GetQuestLogChoiceInfo (and
-- their guaranteed reward equivalents) may only exist under C_QuestLog
-- rather than as plain globals. Every quest log read goes through the four
-- functions below, each of which tries the C_QuestLog path first and falls
-- back to the old global, so the rest of the file never has to guard for a
-- missing function itself.
-- ---------------------------------------------------------------------------

local ADDON, ns = ...

local format, ipairs, pairs, type = string.format, ipairs, pairs, type
local huge = math.huge
local GetItemInfo, GetItemInfoInstant = GetItemInfo, GetItemInfoInstant

local function NumQuestLogEntries()
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
        if ok and type(n) == "number" then return n end
    end
    if _G.GetNumQuestLogEntries then
        local ok, n = pcall(_G.GetNumQuestLogEntries)
        if ok and type(n) == "number" then return n end
    end
    return 0
end

-- Returns title, level, isHeader, questID for a quest log index. Header rows
-- (zone dividers) are skipped by the caller.
local function QuestLogTitle(index)
    if C_QuestLog and C_QuestLog.GetInfo then
        local ok, info = pcall(C_QuestLog.GetInfo, index)
        if ok and type(info) == "table" then
            return info.title, info.level, info.isHeader, info.questID
        end
    end
    if _G.GetQuestLogTitle then
        -- classic shape: title, level, tag, suggestedGroup, isHeader,
        -- isCollapsed, isComplete, isDaily, questID
        local ok, title, level, _, _, isHeader, _, _, _, questID =
            pcall(_G.GetQuestLogTitle, index)
        if ok and title then return title, level, isHeader, questID end
    end
    return nil
end

local function NumQuestChoices(questID)
    if C_QuestLog and C_QuestLog.GetNumQuestLogChoices then
        local ok, n = pcall(C_QuestLog.GetNumQuestLogChoices, questID)
        if ok and type(n) == "number" then return n end
    end
    if _G.GetNumQuestLogChoices then
        local ok, n = pcall(_G.GetNumQuestLogChoices, questID)
        if ok and type(n) == "number" then return n end
    end
    return 0
end

-- One of these is picked by the player, so each is a separate upgrade
-- candidate. Returns an item id, or nil.
local function QuestChoiceItemID(choiceIndex, questID)
    if C_QuestLog and C_QuestLog.GetQuestLogChoiceInfo then
        local ok, info = pcall(C_QuestLog.GetQuestLogChoiceInfo, choiceIndex, questID)
        if ok and type(info) == "table" then return info.itemID end
    end
    if _G.GetQuestLogChoiceInfo then
        local ok, name, _, _, _, _, itemID = pcall(_G.GetQuestLogChoiceInfo, choiceIndex, questID)
        if ok and name then return itemID end
    end
    return nil
end

local function NumQuestRewards(questID)
    if C_QuestLog and C_QuestLog.GetNumQuestLogRewards then
        local ok, n = pcall(C_QuestLog.GetNumQuestLogRewards, questID)
        if ok and type(n) == "number" then return n end
    end
    if _G.GetNumQuestLogRewards then
        local ok, n = pcall(_G.GetNumQuestLogRewards, questID)
        if ok and type(n) == "number" then return n end
    end
    return 0
end

-- Guaranteed rewards, everyone gets all of these on top of whichever choice
-- reward is picked. Returns an item id, or nil.
local function QuestRewardItemID(rewardIndex, questID)
    if C_QuestLog and C_QuestLog.GetQuestLogRewardInfo then
        local ok, info = pcall(C_QuestLog.GetQuestLogRewardInfo, rewardIndex, questID)
        if ok and type(info) == "table" then return info.itemID end
    end
    if _G.GetQuestLogRewardInfo then
        local ok, name, _, _, _, _, itemID = pcall(_G.GetQuestLogRewardInfo, rewardIndex, questID)
        if ok and name then return itemID end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- equip slot mapping
-- Scan.lua's slot ids, by equipLoc. Rings, trinkets and one handed weapons
-- can go in either of two slots, so those map to both and the worse of the
-- two equipped items is the one compared against.
-- ---------------------------------------------------------------------------
local EQUIP_SLOT_MAP = {
    INVTYPE_HEAD           = { 1 },
    INVTYPE_NECK           = { 2 },
    INVTYPE_SHOULDER       = { 3 },
    INVTYPE_CLOAK          = { 15 },
    INVTYPE_CHEST          = { 5 },
    INVTYPE_ROBE           = { 5 },
    INVTYPE_WRIST          = { 9 },
    INVTYPE_HAND           = { 10 },
    INVTYPE_WAIST          = { 6 },
    INVTYPE_LEGS           = { 7 },
    INVTYPE_FEET           = { 8 },
    INVTYPE_FINGER         = { 11, 12 },
    INVTYPE_TRINKET        = { 13, 14 },
    INVTYPE_WEAPON         = { 16, 17 },
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_2HWEAPON       = { 16 },
    INVTYPE_WEAPONOFFHAND  = { 17 },
    INVTYPE_SHIELD         = { 17 },
    INVTYPE_HOLDABLE       = { 17 },
    INVTYPE_RANGED         = { 18 },
    INVTYPE_RANGEDRIGHT    = { 18 },
    INVTYPE_THROWN         = { 18 },
    INVTYPE_RELIC          = { 18 },
}

-- The worse equipped item across a group of candidate slots (an empty slot
-- counts as item level 0). Returns the equipped record and its item level.
local function WorstEquipped(equipLoc, scan)
    local slots = EQUIP_SLOT_MAP[equipLoc]
    if not slots then return nil, nil end
    local worstRec, worstIlvl = nil, huge
    for _, slotID in ipairs(slots) do
        local rec = scan.bySlotID[slotID]
        if rec then
            local ilvl = rec.empty and 0 or (rec.ilvl or 0)
            if ilvl < worstIlvl then
                worstRec, worstIlvl = rec, ilvl
            end
        end
    end
    return worstRec, (worstRec and worstIlvl or nil)
end

-- ---------------------------------------------------------------------------
-- can the character actually use this item
-- IsEquippableItem checks class and armor or weapon proficiency in one call
-- and is the authoritative answer when it exists. Without it, only armor
-- pieces can be judged, using the same level graduated armor target the gear
-- rules already compute in Scan.lua. A weapon with no known restriction is
-- allowed through rather than silently hidden.
-- ---------------------------------------------------------------------------
local function CanUse(link, itemID, classID, subClassID, scan)
    if _G.IsEquippableItem then
        local ok, usable = pcall(_G.IsEquippableItem, link or itemID)
        if ok and type(usable) == "boolean" then return usable end
    end
    if classID == 4 and subClassID and scan.wantArmor then
        return subClassID <= scan.wantArmor
    end
    return true
end

-- ---------------------------------------------------------------------------
-- building the candidate list
-- ---------------------------------------------------------------------------
local function AddCandidate(out, scan, playerLevel, questTitle, questID, itemID, isChoice)
    if not itemID then return end

    -- Not cached yet. ns.GetItemMeta queues it and fires ITEM_CACHE_UPDATED
    -- once it resolves, which triggers a rescan below.
    local meta = ns.GetItemMeta(itemID)
    if not meta then return end

    local slotRec, equippedIlvl = WorstEquipped(meta.equipLoc, scan)
    if not slotRec then return end   -- not an equippable slot GearScout tracks

    local itemIlvl = meta.ilvl or 0
    if itemIlvl <= equippedIlvl then return end   -- not an upgrade

    local minLevel
    local okInfo, _, _, _, _, ml = pcall(GetItemInfo, itemID)
    if okInfo then minLevel = ml end
    if minLevel and minLevel > playerLevel then return end

    local classID, subClassID
    if GetItemInfoInstant then
        local ok, _, _, _, _, _, cID, subID = pcall(GetItemInfoInstant, itemID)
        if ok then classID, subClassID = cID, subID end
    end
    if not CanUse(meta.link, itemID, classID, subClassID, scan) then return end

    out[#out + 1] = {
        questTitle   = questTitle,
        questID      = questID,
        itemID       = itemID,
        itemLink     = meta.link,
        itemName     = meta.name,
        itemIlvl     = itemIlvl,
        equippedIlvl = equippedIlvl,
        slotLabel    = slotRec.label,
        slotID       = slotRec.slotID,
        isChoice     = isChoice,
    }
end

local function ComputeQuestUpgrades()
    local out = {}
    local scan = ns.lastScan
    if not scan then return out end   -- no equipped gear read yet, nothing to compare against

    local playerLevel = ns.playerLevel or UnitLevel("player")
    local total = NumQuestLogEntries()

    for index = 1, total do
        local title, _, isHeader, questID = QuestLogTitle(index)
        if title and not isHeader and questID and questID > 0 then
            local numChoices = NumQuestChoices(questID)
            for c = 1, numChoices do
                AddCandidate(out, scan, playerLevel, title, questID, QuestChoiceItemID(c, questID), true)
            end
            local numRewards = NumQuestRewards(questID)
            for r = 1, numRewards do
                AddCandidate(out, scan, playerLevel, title, questID, QuestRewardItemID(r, questID), false)
            end
        end
    end

    table.sort(out, function(a, b)
        return (a.itemIlvl - a.equippedIlvl) > (b.itemIlvl - b.equippedIlvl)
    end)
    return out
end

-- ---------------------------------------------------------------------------
-- cache and refresh triggers
-- Rescanning walks the whole quest log and resolves item data, so it is
-- debounced the same way Scan.lua debounces equipment changes: quest log
-- updates and item cache fills can both arrive several times in a row for
-- one actual change.
-- ---------------------------------------------------------------------------
local cachedUpgrades = nil

local Rescan = ns.Debounce(0.5, function()
    cachedUpgrades = ComputeQuestUpgrades()
    ns:Emit("QUEST_UPGRADES_UPDATED", cachedUpgrades)
end)

ns:On("QUEST_LOG_UPDATE", Rescan)
ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, Rescan) end)
ns:Sub("ITEM_CACHE_UPDATED", Rescan)
ns:Sub("SCAN_UPDATED", Rescan)

-- ---------------------------------------------------------------------------
-- public reads
-- ---------------------------------------------------------------------------

-- Every quest reward currently in the log that beats the equipped item level
-- for the slot it goes in, best upgrade first. Never includes an item the
-- character cannot use or is not yet the level for.
function ns.GetQuestUpgrades()
    if not cachedUpgrades then
        cachedUpgrades = ComputeQuestUpgrades()
    end
    return cachedUpgrades
end

-- One issue style summary (sev, title, detail, fix), or nil when nothing in
-- the log is worth turning in early for gear.
function ns.GetQuestUpgradeIssue()
    local list = ns.GetQuestUpgrades()
    if not list or #list == 0 then return nil end

    local top = list[1]
    local extra = #list - 1

    local detail = format(
        "%s is already in your quest log, so you have done the work for it. Its %s reward is item level %d, better than the item level %d you have equipped there now.",
        top.questTitle, top.slotLabel:lower(), top.itemIlvl, top.equippedIlvl)
    if extra > 0 then
        detail = detail .. format(" There %s %d more quest reward%s in your log that would also be an upgrade.",
            extra == 1 and "is" or "are", extra, extra == 1 and "" or "s")
    end

    return {
        sev    = ns.SEVERITY.INFO,
        title  = format("Turn in %s for a better %s", top.questTitle, top.slotLabel:lower()),
        detail = detail,
        fix    = format("Hand in %s. The reward is a straight upgrade over what you have equipped, and you already finished the quest.", top.questTitle),
    }
end
