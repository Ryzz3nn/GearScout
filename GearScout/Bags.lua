-- GearScout / Bags.lua
-- Looks through bags, and through the bank when it happens to be open, for
-- items that would beat what is currently equipped in that slot. Item level
-- is the main signal, but nothing is suggested unless the character could
-- actually wear or wield it right now: right slot, right armor weight, right
-- weapon type, and a level requirement the character has already reached.
-- When any of that cannot be worked out, the item is left out. A missed
-- upgrade costs nothing. A wrong one wastes the player's time and trust.

local ADDON, ns = ...

local ipairs, type = ipairs, type
local format = string.format
local GetItemInfo = GetItemInfo
local GetItemInfoInstant = GetItemInfoInstant

-- ---------------------------------------------------------------------------
-- container API shim
-- This client reports interface 20506 but runs on the current engine, where
-- the bag reading functions may only exist under C_Container. Both paths are
-- tried once here so nothing else in the file has to guard for it again.
-- ---------------------------------------------------------------------------
local RawContainerNumSlots = (C_Container and C_Container.GetContainerNumSlots) or _G.GetContainerNumSlots
local RawContainerItemLink = (C_Container and C_Container.GetContainerItemLink) or _G.GetContainerItemLink

ns.hasContainerAPI = RawContainerNumSlots ~= nil and RawContainerItemLink ~= nil

local function BagSlotCount(bag)
    if not RawContainerNumSlots then return 0 end
    local ok, n = pcall(RawContainerNumSlots, bag)
    if ok and type(n) == "number" then return n end
    return 0
end

local function BagItemLink(bag, slot)
    if not RawContainerItemLink then return nil end
    local ok, link = pcall(RawContainerItemLink, bag, slot)
    if ok then return link end
    return nil
end

-- ---------------------------------------------------------------------------
-- bank state
-- Bank slots read back stale or empty data while the bank window is closed,
-- so they are left out of the scan entirely rather than reported on.
-- ---------------------------------------------------------------------------
local function BankIsOpen()
    local frame = _G.BankFrame
    if not frame or type(frame.IsShown) ~= "function" then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
end

local NUM_BAG_SLOTS = _G.NUM_BAG_SLOTS or 4
local NUM_BANKBAGSLOTS = _G.NUM_BANKBAGSLOTS or 6
local BANK_CONTAINER = _G.BANK_CONTAINER or -1

local function ContainerList()
    local list = {}
    for i = 0, NUM_BAG_SLOTS do list[#list + 1] = i end
    if BankIsOpen() then
        list[#list + 1] = BANK_CONTAINER
        for i = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do
            list[#list + 1] = i
        end
    end
    return list
end

-- ---------------------------------------------------------------------------
-- extended item metadata, cached by item id
-- ns.GetItemMeta already caches name, link, quality, item level, subType,
-- equip location and icon. The required level and the two numeric class ids
-- it does not carry are cached here the same way, so a bag scan never asks
-- the item API for the same item twice.
-- ---------------------------------------------------------------------------
local extraCache = {}
local function GetExtraMeta(itemID)
    if not itemID then return nil end
    local cached = extraCache[itemID]
    if cached then return cached end

    local name, _, _, _, reqLevel = GetItemInfo(itemID)
    if not name then return nil end

    local classID, subClassID
    if GetItemInfoInstant then
        local ok, _, _, _, _, _, cID, sID = pcall(GetItemInfoInstant, itemID)
        if ok then classID, subClassID = cID, sID end
    end

    local meta = { reqLevel = reqLevel or 0, classID = classID, subClassID = subClassID }
    extraCache[itemID] = meta
    return meta
end

-- ---------------------------------------------------------------------------
-- what each class can actually wear or wield
-- Armor weight reuses scan.wantArmor, the heaviest armor class the current
-- equipment scan already worked out for this character and level, so the
-- level 40 rule is not duplicated here.
--
-- Weapon proficiency is fixed game design, not something any API reports, so
-- it is written out by hand below. Every playable class is listed. A weapon
-- subclass missing from a class's list is treated as not usable. That is the
-- safe direction: a real upgrade left off the list costs nothing, one that
-- cannot be equipped wastes the player's time.
-- ---------------------------------------------------------------------------
local AXE1H, AXE2H, BOW, GUN, MACE1H, MACE2H, POLEARM, SWORD1H, SWORD2H =
      0, 1, 2, 3, 4, 5, 6, 7, 8
local STAFF, FIST, DAGGER, THROWN, CROSSBOW, WAND =
      10, 13, 15, 16, 18, 19

local WEAPON_ALLOWED = {
    WARRIOR = { [AXE1H]=1, [AXE2H]=1, [BOW]=1, [GUN]=1, [MACE1H]=1, [MACE2H]=1, [POLEARM]=1,
                [SWORD1H]=1, [SWORD2H]=1, [STAFF]=1, [FIST]=1, [DAGGER]=1, [THROWN]=1, [CROSSBOW]=1 },
    PALADIN = { [AXE1H]=1, [AXE2H]=1, [MACE1H]=1, [MACE2H]=1, [POLEARM]=1,
                [SWORD1H]=1, [SWORD2H]=1, [STAFF]=1, [FIST]=1, [DAGGER]=1 },
    HUNTER  = { [AXE1H]=1, [AXE2H]=1, [BOW]=1, [GUN]=1, [POLEARM]=1,
                [SWORD1H]=1, [SWORD2H]=1, [STAFF]=1, [FIST]=1, [DAGGER]=1, [THROWN]=1, [CROSSBOW]=1 },
    SHAMAN  = { [AXE1H]=1, [MACE1H]=1, [STAFF]=1, [FIST]=1, [DAGGER]=1 },
    ROGUE   = { [AXE1H]=1, [BOW]=1, [GUN]=1, [MACE1H]=1, [SWORD1H]=1,
                [FIST]=1, [DAGGER]=1, [THROWN]=1, [CROSSBOW]=1 },
    DRUID   = { [MACE1H]=1, [STAFF]=1, [FIST]=1, [DAGGER]=1 },
    MAGE    = { [SWORD1H]=1, [STAFF]=1, [DAGGER]=1, [WAND]=1 },
    PRIEST  = { [MACE1H]=1, [STAFF]=1, [DAGGER]=1, [WAND]=1 },
    WARLOCK = { [SWORD1H]=1, [STAFF]=1, [DAGGER]=1, [WAND]=1 },
}

-- Shields are an armor subclass, not a weapon one, and only these classes can
-- raise one.
local SHIELD_CLASSES = { WARRIOR = true, PALADIN = true, SHAMAN = true }

local function CanUseWeapon(scan, subClassID)
    local allowed = WEAPON_ALLOWED[scan.class]
    if not allowed or not subClassID then return false end
    return allowed[subClassID] == true
end

-- ---------------------------------------------------------------------------
-- equip location to paperdoll slot id, using the same ids ns.SLOTS defines.
-- A value is either one slot id, or a pair for the two slots that come in
-- twos. One handed weapons are not listed here because which hand they can
-- go in depends on what is already equipped, worked out separately below.
-- Relics are left out on purpose: figuring out which class a relic belongs
-- to needs data no available API hands over cleanly, so relics are never
-- suggested rather than risk a wrong one.
-- ---------------------------------------------------------------------------
local SLOT_FOR_EQUIPLOC = {
    INVTYPE_HEAD            = 1,
    INVTYPE_NECK            = 2,
    INVTYPE_SHOULDER        = 3,
    INVTYPE_CLOAK           = 15,
    INVTYPE_CHEST           = 5,
    INVTYPE_ROBE            = 5,
    INVTYPE_WRIST           = 9,
    INVTYPE_HAND            = 10,
    INVTYPE_WAIST           = 6,
    INVTYPE_LEGS            = 7,
    INVTYPE_FEET            = 8,
    INVTYPE_FINGER          = { 11, 12 },
    INVTYPE_TRINKET         = { 13, 14 },
    INVTYPE_WEAPONMAINHAND  = 16,
    INVTYPE_2HWEAPON        = 16,
    INVTYPE_WEAPONOFFHAND   = 17,
    INVTYPE_SHIELD          = 17,
    INVTYPE_HOLDABLE        = 17,
    INVTYPE_RANGED          = 18,
    INVTYPE_RANGEDRIGHT     = 18,
    INVTYPE_THROWN          = 18,
}

-- A one handed weapon can go in either hand. The off hand is only offered as
-- a target when the off hand already holds a weapon, since that is the only
-- way to know dual wielding is available to this character without a second
-- proficiency table for it.
local function WeaponTargetSlots(scan)
    local slots = { 16 }
    local oh = scan.bySlotID[17]
    if not scan.twoHander and oh and not oh.empty
       and (oh.equipLoc == "INVTYPE_WEAPON" or oh.equipLoc == "INVTYPE_WEAPONOFFHAND") then
        slots[#slots + 1] = 17
    end
    return slots
end

-- Whether the character could equip this candidate into this specific slot,
-- ignoring item level entirely. Only the slot's own armor flag from ns.SLOTS
-- and the item's numeric class ids are used, both already read once and
-- cached above.
local function IsUsable(scan, meta, extra, slotID)
    local def = ns.SLOT_BY_ID[slotID]
    if not def then return false end

    if slotID == 17 and scan.twoHander then
        return false -- nothing goes in the off hand while a two hander is equipped
    end

    if meta.equipLoc == "INVTYPE_SHIELD" then
        return SHIELD_CLASSES[scan.class] == true
    end

    if def.armor then
        local sub = extra.subClassID
        if not sub or sub < 1 or sub > 4 then return false end
        return scan.wantArmor ~= nil and sub <= scan.wantArmor
    end

    if extra.classID == 2 then
        return CanUseWeapon(scan, extra.subClassID)
    end

    -- rings, necks, trinkets, cloaks and held off hand items: no weight or
    -- weapon type to check.
    return true
end

-- An upgrade this small is noise. It matches on a loading screen and gets
-- undone the next time the player is bored, so it is not worth the interruption.
local MIN_ILVL_GAIN = 3

-- ---------------------------------------------------------------------------
-- the scan
-- ---------------------------------------------------------------------------
function ns.GetBagUpgrades()
    if not ns.hasContainerAPI then return {} end

    local scan = ns.lastScan or ns.ScanEquipment()
    if not scan then return {} end

    local level = scan.level or 1
    local results = {}
    local bestIndex = {} -- itemID -> index in results, so duplicate stacks collapse to one row

    local containers = ContainerList()
    for _, bag in ipairs(containers) do
        local slotCount = BagSlotCount(bag)
        for slot = 1, slotCount do
            local link = BagItemLink(bag, slot)
            if link then
                local itemID = ns.ParseLink(link)
                local meta = itemID and ns.GetItemMeta(itemID)
                local extra = itemID and GetExtraMeta(itemID)

                if meta and extra and meta.equipLoc and meta.equipLoc ~= ""
                   and not (extra.reqLevel and extra.reqLevel > level) then

                    local targetSlots
                    if meta.equipLoc == "INVTYPE_WEAPON" then
                        targetSlots = WeaponTargetSlots(scan)
                    else
                        local mapped = SLOT_FOR_EQUIPLOC[meta.equipLoc]
                        if type(mapped) == "table" then
                            targetSlots = mapped
                        elseif mapped then
                            targetSlots = { mapped }
                        end
                    end

                    if targetSlots then
                        -- Compare against the weaker of the candidate's usable target
                        -- slots. For rings and trinkets that is the two paired slots;
                        -- for a one handed weapon that already dual wields it is
                        -- whichever hand carries the weaker weapon.
                        local weakestSlot, weakestIlvl
                        for _, sid in ipairs(targetSlots) do
                            if IsUsable(scan, meta, extra, sid) then
                                local rec = scan.bySlotID[sid]
                                local curIlvl = (rec and not rec.empty) and (rec.ilvl or 0) or 0
                                if not weakestIlvl or curIlvl < weakestIlvl then
                                    weakestIlvl, weakestSlot = curIlvl, sid
                                end
                            end
                        end

                        if weakestSlot then
                            local gain = (meta.ilvl or 0) - weakestIlvl
                            if gain >= MIN_ILVL_GAIN then
                                local def = ns.SLOT_BY_ID[weakestSlot]
                                local record = {
                                    bag          = bag,
                                    slot         = slot,
                                    bank         = bag == BANK_CONTAINER or bag > NUM_BAG_SLOTS,
                                    itemID       = itemID,
                                    link         = meta.link or link,
                                    name         = meta.name,
                                    icon         = meta.icon,
                                    quality      = meta.quality,
                                    ilvl         = meta.ilvl or 0,
                                    slotID       = weakestSlot,
                                    slotLabel    = def and def.label or "Unknown",
                                    equippedIlvl = weakestIlvl,
                                    gain         = gain,
                                }

                                local existing = bestIndex[itemID]
                                if not existing then
                                    results[#results + 1] = record
                                    bestIndex[itemID] = #results
                                elseif results[existing].gain < gain then
                                    results[existing] = record
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(results, function(a, b)
        if a.gain ~= b.gain then return a.gain > b.gain end
        local oa = ns.SLOT_BY_ID[a.slotID] and ns.SLOT_BY_ID[a.slotID].order or 99
        local ob = ns.SLOT_BY_ID[b.slotID] and ns.SLOT_BY_ID[b.slotID].order or 99
        return oa < ob
    end)

    ns.lastBagUpgrades = results
    return results
end

-- ---------------------------------------------------------------------------
-- one issue row, shaped exactly like the ones ns.Analyze() in Rules.lua adds
-- ---------------------------------------------------------------------------
function ns.GetBagUpgradeIssue()
    local upgrades = ns.GetBagUpgrades()
    if not upgrades or #upgrades == 0 then return nil end

    local top = upgrades[1]
    local def = ns.SLOT_BY_ID[top.slotID]
    local slotName = (top.slotLabel or "slot"):lower()
    local title, detail, fix

    if #upgrades == 1 then
        title = "You are carrying an upgrade for your " .. slotName .. " in your bags"
        detail = format("%s is item level %d. What you have equipped there is item level %d, so this is a real upgrade sitting unused.",
                         top.name or "This item", top.ilvl, top.equippedIlvl)
        fix = "Open your bags, right click " .. (top.name or "the item") .. ", and put it on."
        if top.bank then
            fix = fix .. " It is in your bank, so you need to be at the bank to reach it."
        end
    else
        local restCount = #upgrades - 1
        title = format("You are carrying %d upgrades in your bags", #upgrades)
        detail = format("The best one is %s, item level %d for your %s, where you currently have item level %d. There %s %d more upgrade%s sitting in your bags.",
                         top.name or "an item", top.ilvl, slotName, top.equippedIlvl,
                         restCount == 1 and "is" or "are", restCount, restCount == 1 and "" or "s")
        fix = format("Start with %s for your %s. Open your bags and right click it to equip it.",
                      top.name or "the best one", slotName)
        for _, it in ipairs(upgrades) do
            if it.bank then
                fix = fix .. " Some of these are in your bank, so you need to be there to reach all of them."
                break
            end
        end
    end

    return {
        sev     = ns.SEVERITY.WARN,
        slotID  = top.slotID,
        order   = def and def.order or 99,
        label   = top.slotLabel,
        link    = top.link,
        icon    = top.icon,
        title   = title,
        detail  = detail,
        fix     = fix,
        penalty = 0,
    }
end

-- ---------------------------------------------------------------------------
-- rescan triggers, debounced
-- Bag events fire once per changed slot and looting a stack can touch several
-- slots at once, so this only ever runs on the trailing edge of a burst of
-- events, never on a timer and never in a loop.
-- ---------------------------------------------------------------------------
local RescanBags = ns.Debounce(0.5, function()
    local upgrades = ns.GetBagUpgrades()
    ns:Emit("BAG_UPGRADES_UPDATED", upgrades)
end)
ns.RequestBagRescan = RescanBags

ns:On("BAG_UPDATE", RescanBags)
ns:On("BAG_UPDATE_DELAYED", RescanBags)
ns:On("PLAYERBANKSLOTS_CHANGED", RescanBags)
ns:On("BANKFRAME_OPENED", RescanBags)
ns:On("BANKFRAME_CLOSED", RescanBags)
ns:Sub("SCAN_UPDATED", RescanBags) -- what counts as an upgrade changes when equipment changes
ns:On("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(3, RescanBags)
end)
