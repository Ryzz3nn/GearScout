-- GearScout / Scan.lua
-- Reads the 17 real equipment slots and turns them into a plain data table.
-- Everything expensive is cached by item id, because socket layout and armor
-- class never change for a given item.

local ADDON, ns = ...

local GetInventoryItemLink = GetInventoryItemLink
local GetInventoryItemDurability = GetInventoryItemDurability
local GetItemInfo, GetItemStats = GetItemInfo, GetItemStats
local GetItemInfoInstant = GetItemInfoInstant
local strsplit, tonumber, pairs, ipairs = strsplit, tonumber, pairs, ipairs
local wipe, floor = wipe, math.floor

-- ---------------------------------------------------------------------------
-- slot table, in paperdoll reading order
-- ench: true, false, or a keyword resolved per character
-- ---------------------------------------------------------------------------
ns.SLOTS = {
    { id = 1,  label = "Head",      armor = true,  ench = true },
    { id = 2,  label = "Neck",      armor = false, ench = false },
    { id = 3,  label = "Shoulder",  armor = true,  ench = true },
    { id = 15, label = "Back",      armor = false, ench = true },
    { id = 5,  label = "Chest",     armor = true,  ench = true },
    { id = 9,  label = "Wrist",     armor = true,  ench = true },
    { id = 10, label = "Hands",     armor = true,  ench = true },
    { id = 6,  label = "Waist",     armor = true,  ench = false },
    { id = 7,  label = "Legs",      armor = true,  ench = true },
    { id = 8,  label = "Feet",      armor = true,  ench = true },
    { id = 11, label = "Ring 1",    armor = false, ench = "enchanter" },
    { id = 12, label = "Ring 2",    armor = false, ench = "enchanter" },
    { id = 13, label = "Trinket 1", armor = false, ench = false },
    { id = 14, label = "Trinket 2", armor = false, ench = false },
    { id = 16, label = "Main Hand", armor = false, ench = true },
    { id = 17, label = "Off Hand",  armor = false, ench = "offhand" },
    { id = 18, label = "Ranged",    armor = false, ench = "ranged" },
}

ns.SLOT_BY_ID = {}
for i, def in ipairs(ns.SLOTS) do
    def.order = i
    ns.SLOT_BY_ID[def.id] = def
end

-- Which inventory slot an item's equip location belongs to. The two position
-- slots resolve to their first position, so a ring maps to Ring 1 and a caller
-- comparing against what is worn has to consider both itself.
ns.SLOT_FOR_EQUIPLOC = {
    INVTYPE_HEAD            = 1,
    INVTYPE_NECK            = 2,
    INVTYPE_SHOULDER        = 3,
    INVTYPE_CLOAK           = 15,
    INVTYPE_CHEST           = 5,
    INVTYPE_ROBE            = 5,
    INVTYPE_WAIST           = 6,
    INVTYPE_LEGS            = 7,
    INVTYPE_FEET            = 8,
    INVTYPE_WRIST           = 9,
    INVTYPE_HAND            = 10,
    INVTYPE_FINGER          = 11,
    INVTYPE_TRINKET         = 13,
    INVTYPE_WEAPON          = 16,
    INVTYPE_2HWEAPON        = 16,
    INVTYPE_WEAPONMAINHAND  = 16,
    INVTYPE_WEAPONOFFHAND   = 17,
    INVTYPE_SHIELD          = 17,
    INVTYPE_HOLDABLE        = 17,
    INVTYPE_RANGED          = 18,
    INVTYPE_RANGEDRIGHT     = 18,
    INVTYPE_THROWN          = 18,
    INVTYPE_RELIC           = 18,
}

-- Armor subclass ids. Numeric so the check survives every locale.
local ARMOR_CLOTH, ARMOR_LEATHER, ARMOR_MAIL, ARMOR_PLATE = 1, 2, 3, 4
ns.ARMOR_NAMES = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }

-- Best armor class the character should be wearing, before and after level 40.
local ARMOR_TARGET = {
    WARRIOR = { ARMOR_PLATE,   ARMOR_MAIL },
    PALADIN = { ARMOR_PLATE,   ARMOR_MAIL },
    HUNTER  = { ARMOR_MAIL,    ARMOR_LEATHER },
    SHAMAN  = { ARMOR_MAIL,    ARMOR_LEATHER },
    ROGUE   = { ARMOR_LEATHER, ARMOR_LEATHER },
    DRUID   = { ARMOR_LEATHER, ARMOR_LEATHER },
    MAGE    = { ARMOR_CLOTH,   ARMOR_CLOTH },
    PRIEST  = { ARMOR_CLOTH,   ARMOR_CLOTH },
    WARLOCK = { ARMOR_CLOTH,   ARMOR_CLOTH },
}

-- Weapon subclasses that can take a scope.
local SCOPEABLE = { [2] = true, [3] = true, [18] = true } -- bow, gun, crossbow

-- ---------------------------------------------------------------------------
-- socket counting
-- ---------------------------------------------------------------------------
local SOCKET_STAT_KEYS = {
    EMPTY_SOCKET_RED = true,
    EMPTY_SOCKET_YELLOW = true,
    EMPTY_SOCKET_BLUE = true,
    EMPTY_SOCKET_META = true,
    EMPTY_SOCKET_PRISMATIC = true,
}

-- Localized tooltip line text for each socket colour, for the fallback path.
local SOCKET_LINE_TEXT = {}
for key in pairs(SOCKET_STAT_KEYS) do
    local s = _G[key]
    if s then SOCKET_LINE_TEXT[s] = true end
end

local scanTip
local function ScanTooltipSockets(link)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "GearScoutScanTooltip", nil, "GameTooltipTemplate")
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    scanTip:ClearLines()
    local ok = pcall(scanTip.SetHyperlink, scanTip, link)
    if not ok then return 0 end
    local n = 0
    for i = 1, scanTip:NumLines() do
        local fs = _G["GearScoutScanTooltipTextLeft" .. i]
        local txt = fs and fs:GetText()
        if txt and SOCKET_LINE_TEXT[txt] then n = n + 1 end
    end
    return n
end

-- ---------------------------------------------------------------------------
-- item stats, cached per link
-- The global GetItemStats was replaced by C_Item.GetItemStats on the current
-- engine, and the new one returns a fresh table instead of filling one you
-- pass in. Both shapes are handled, and a client with neither simply skips
-- the rules that depend on stats.
-- ---------------------------------------------------------------------------
local RawGetItemStats = _G.GetItemStats or (C_Item and C_Item.GetItemStats)
ns.hasItemStats = RawGetItemStats ~= nil

local statsCache = {}
function ns.GetStats(link)
    if not link or not RawGetItemStats then return nil end
    local cached = statsCache[link]
    if cached ~= nil then return cached or nil end

    local t
    local ok, res = pcall(RawGetItemStats, link, {})
    if ok and type(res) == "table" then
        t = res
    else
        local ok2, res2 = pcall(RawGetItemStats, link)
        if ok2 and type(res2) == "table" then t = res2 end
    end

    statsCache[link] = t or false
    return t
end

-- ---------------------------------------------------------------------------
-- socket counting
-- The stat table describes the unmodified item, so inserted gems never hide
-- the socket count. Tooltip scanning covers clients where stats are gone.
-- ---------------------------------------------------------------------------
local socketCache = {}

function ns.CountSockets(itemID)
    if not itemID then return 0 end
    local cached = socketCache[itemID]
    if cached then return cached end

    local baseLink = "item:" .. itemID
    local n = 0
    local stats = ns.GetStats(baseLink)
    if stats then
        for k, v in pairs(stats) do
            if SOCKET_STAT_KEYS[k] then n = n + (v or 0) end
        end
    end
    if n == 0 then
        n = ScanTooltipSockets(baseLink)
    end
    socketCache[itemID] = n
    return n
end

-- ---------------------------------------------------------------------------
-- link parsing
-- itemString is item:id:enchant:gem1:gem2:gem3:gem4:suffix:unique:...
-- ---------------------------------------------------------------------------
function ns.ParseLink(link)
    if not link then return nil end
    local body = link:match("item:([%-%d:]+)")
    if not body then return nil end
    local id, ench, g1, g2, g3, g4, suffix = strsplit(":", body)
    return tonumber(id), tonumber(ench) or 0,
           tonumber(g1) or 0, tonumber(g2) or 0, tonumber(g3) or 0, tonumber(g4) or 0,
           tonumber(suffix) or 0
end

-- ---------------------------------------------------------------------------
-- character facts
-- ---------------------------------------------------------------------------
local isEnchanter
function ns.IsEnchanter(recheck)
    if isEnchanter ~= nil and not recheck then return isEnchanter end

    -- Every enchanter knows Disenchant, so one spell check settles it.
    isEnchanter = ns.SpellKnown(13262)

    -- Older clients that still expose the skill list get a second look.
    if not isEnchanter and _G.GetNumSkillLines and _G.GetSkillLineInfo then
        local encName = ns.SpellName(7411)
        if encName then
            pcall(function()
                for i = 1, GetNumSkillLines() do
                    if GetSkillLineInfo(i) == encName then
                        isEnchanter = true
                        return
                    end
                end
            end)
        end
    end
    return isEnchanter
end

-- ---------------------------------------------------------------------------
-- the scan
-- ---------------------------------------------------------------------------

-- Resolves whether a given slot can actually hold a permanent enchant for
-- this character and this equipped item.
local function ResolveEnchantable(def, rec)
    local rule = def.ench
    if rule == true then
        -- A two handed weapon in the main hand is enchantable, a relic is not.
        if def.id == 16 and rec.equipLoc == "INVTYPE_RELIC" then return false end
        return true
    end
    if rule == false or rule == nil then return false end
    if rule == "enchanter" then return ns.IsEnchanter() end
    if rule == "offhand" then
        return rec.equipLoc == "INVTYPE_WEAPONOFFHAND"
            or rec.equipLoc == "INVTYPE_WEAPON"
            or rec.equipLoc == "INVTYPE_SHIELD"
    end
    if rule == "ranged" then
        return SCOPEABLE[rec.subClassID or -1] == true
    end
    return false
end

function ns.ScanEquipment()
    local hasMHTemp, _, _, hasOHTemp = GetWeaponEnchantInfo()
    local level = UnitLevel("player")
    local classFile = ns.playerClass or select(2, UnitClass("player"))
    local armorTarget = ARMOR_TARGET[classFile]
    local wantArmor = armorTarget and (level >= 40 and armorTarget[1] or armorTarget[2]) or nil

    local scan = {
        level = level,
        class = classFile,
        wantArmor = wantArmor,
        slots = {},
        bySlotID = {},
        filled = 0,
        emptySlots = 0,
        sumIlvl = 0,
        avgIlvl = 0,
        missingEnchants = 0,
        emptySockets = 0,
        twoHander = false,
        scannedAt = GetTime(),
    }

    local ilvls = {}

    for i = 1, #ns.SLOTS do
        local def = ns.SLOTS[i]
        local rec = {
            slotID = def.id,
            label  = def.label,
            order  = i,
        }

        local link = GetInventoryItemLink("player", def.id)
        if link then
            local itemID, ench, g1, g2, g3, g4, suffix = ns.ParseLink(link)
            rec.link = link
            rec.itemID = itemID
            rec.enchantID = ench
            rec.suffixID = suffix
            rec.gems = { g1, g2, g3, g4 }
            rec.gemsFilled = (g1 ~= 0 and 1 or 0) + (g2 ~= 0 and 1 or 0)
                           + (g3 ~= 0 and 1 or 0) + (g4 ~= 0 and 1 or 0)

            local name, _, quality, ilvl, _, _, _, _, equipLoc, icon = GetItemInfo(link)
            rec.name, rec.quality, rec.ilvl, rec.equipLoc, rec.icon =
                name, quality or 1, ilvl or 0, equipLoc, icon

            if GetItemInfoInstant then
                local _, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemID)
                rec.classID, rec.subClassID = classID, subClassID
            end

            rec.sockets = ns.CountSockets(itemID)
            rec.emptySockets = math.max(0, rec.sockets - rec.gemsFilled)

            local cur, maxDur = GetInventoryItemDurability(def.id)
            if cur and maxDur and maxDur > 0 then
                rec.durability = cur / maxDur
            end

            rec.enchantable = ResolveEnchantable(def, rec)
            rec.enchanted = rec.enchantID ~= 0
            -- A sharpening stone or oil writes into the same field, so a
            -- weapon carrying a temporary buff cannot be judged reliably.
            if def.id == 16 and hasMHTemp then rec.tempEnchant = true end
            if def.id == 17 and hasOHTemp then rec.tempEnchant = true end

            if rec.enchantable and not rec.enchanted then
                scan.missingEnchants = scan.missingEnchants + 1
            end
            scan.emptySockets = scan.emptySockets + rec.emptySockets

            if rec.equipLoc == "INVTYPE_2HWEAPON" then scan.twoHander = true end

            scan.filled = scan.filled + 1
            scan.sumIlvl = scan.sumIlvl + rec.ilvl
            ilvls[#ilvls + 1] = rec.ilvl
        else
            rec.empty = true
            scan.emptySlots = scan.emptySlots + 1
        end

        scan.slots[i] = rec
        scan.bySlotID[def.id] = rec
    end

    -- An empty off hand next to a two hander is correct, not a hole.
    if scan.twoHander then
        local oh = scan.bySlotID[17]
        if oh and oh.empty then
            oh.expectedEmpty = true
            scan.emptySlots = scan.emptySlots - 1
        end
    end

    if scan.filled > 0 then
        scan.avgIlvl = scan.sumIlvl / scan.filled
        table.sort(ilvls)
        local n = #ilvls
        scan.medianIlvl = (n % 2 == 1) and ilvls[(n + 1) / 2]
                          or (ilvls[n / 2] + ilvls[n / 2 + 1]) / 2
    else
        scan.medianIlvl = 0
    end

    ns.lastScan = scan
    return scan
end

-- ---------------------------------------------------------------------------
-- rescan triggers, debounced
-- Swapping a full gear set fires PLAYER_EQUIPMENT_CHANGED once per slot, so a
-- naive handler would run the whole scan up to seventeen times in one frame.
-- ---------------------------------------------------------------------------
local Rescan = ns.Debounce(0.3, function()
    if InCombatLockdown() then return end
    local scan = ns.ScanEquipment()
    ns:Emit("SCAN_UPDATED", scan)
end)
ns.RequestRescan = Rescan

ns:On("PLAYER_EQUIPMENT_CHANGED", Rescan)
ns:On("SOCKET_INFO_UPDATE", Rescan)
ns:On("PLAYER_LEVEL_UP", Rescan)
ns:On("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(3, Rescan)
end)
