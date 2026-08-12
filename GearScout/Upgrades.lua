-- GearScout / Upgrades.lua
-- The upgrade finder. For each gear slot: what could this character
-- realistically get that genuinely beats what is worn there right now.
--
-- Two groups, on purpose, because they cost different things and must never
-- be mixed together:
--
--   EARNED   drops, quest rewards, reputation rewards. Things you go and get.
--            Already owned items (sitting in the bags or bank) are the
--            cheapest earned upgrade of all, so they always sort first.
--   BOUGHT   auction house listings, which cost gold. Shown only when an
--            auction house addon (TradeSkillMaster or Auctionator) is
--            actually installed, and never merged into the earned list.
--
-- "Genuinely better" means it actually scores higher for this character's
-- spec, not merely a higher item level. ns.ExplainItem (or, if that has not
-- loaded yet, ns.CompareToEquipped) does that scoring and already applies the
-- three tier model: a required level, weapon type or slot the character
-- cannot use at all is a hard block and the item is left out entirely; armor
-- weight is a soft penalty folded into the score, never a reason to hide an
-- item outright. When neither function can score an item, because this spec
-- has no researched stat weights yet, that is said in plain words rather
-- than silently falling back to a bare item level sort.
--
-- Every source this reads from is already bounded and mostly already cached
-- by the file that owns it:
--   ns.GetBagUpgrades()        Bags.lua,    scans the bags and open bank
--   ns.GetQuestUpgrades()      Quests.lua,  scans the quest log
--   ns.FindSlotUpgrades()      Sources.lua, scans dungeon and raid loot,
--                              already narrowed to instances near this
--                              character's level before any item is asked
--                              about
--   ns.REP_REWARDS             Data/Catalogue.lua, 781 reputation rewards
--                              total, searched here the same way
--                              Sources.lua's own enchant index is built: a
--                              cheap one time pass, cached, filtered by
--                              ns.ITEM_DB where that data exists before the
--                              client is ever asked about an item.
-- Everything this file computes for a slot is itself cached by slot id and
-- only thrown away when the equipment, bags, quest log or item cache
-- actually change, never on a timer and never inside a redraw.
--
-- Public API:
--   ns.GetSlotUpgrades(slotID)   the data, usable with no UI at all
--   ns.BuildUpgradesPage(page)   the page, called once by CoachUI.lua the
--                                same way it calls ns.BuildRotationPage

local ADDON, ns = ...

local CreateFrame, UIParent, UnitLevel = CreateFrame, UIParent, UnitLevel
local GetItemInfo, GetItemInfoInstant = GetItemInfo, GetItemInfoInstant
local format, ipairs, pairs, type, wipe = string.format, ipairs, pairs, type, wipe
local floor, unpack = math.floor, unpack

-- ---------------------------------------------------------------------------
-- equip slot mapping
-- Same shape as the one Quests.lua and ItemEval.lua already carry, repeated
-- here rather than reached into, since it is small, static WoW game data
-- rather than anything private to either of those files.
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

local STANDING_ORDER = {
    Neutral = 1, Friendly = 2, Honored = 3, Revered = 4, Exalted = 5,
}

local SOURCE_LABEL = {
    bag        = "IN YOUR BAGS",
    quest      = "QUEST REWARD",
    boss       = "DROPS",
    reputation = "REPUTATION",
}

-- Grouped by what it costs the player, not by whether gold changes hands.
-- Reputation gets its own group because it is a different order of
-- commitment: a level 30 is not going to farm a faction to revered, and
-- listing that beside a boss they could kill tonight makes a multi week
-- grind read like an evening's plan.
local EFFORT_TIER = {
    bag        = 1,
    quest      = 2,
    boss       = 3,
    reputation = 4,
}

local TIER_HEADING = {
    [1] = "ALREADY YOURS, no effort at all",
    [2] = "QUEST REWARDS, already in your log",
    [3] = "DROPS, one run at your level",
    [4] = "REPUTATION, a grind worth planning before you start",
}

-- ---------------------------------------------------------------------------
-- tier 1, can this character equip it at all
-- Required level is checked directly, since IsEquippableItem does not judge
-- that. Everything else, armor proficiency, weapon proficiency, shield
-- proficiency, class restrictions, is handed to the client's own
-- IsEquippableItem, the same authoritative check Quests.lua's CanUse already
-- trusts, so none of it is guessed at by hand here. A client old enough not
-- to have that function falls back to the graduated armor rule Scan.lua
-- already computes; weapon proficiency is left unchecked in that fallback
-- rather than risking a wrong call, matching Bags.lua's own documented
-- caution for exactly this situation.
--
-- Armor weight itself is never a reason to say no here. A lighter armor
-- type than the class could be wearing is real, but it is a penalty folded
-- into the score, not a block, and below the level a class actually unlocks
-- its heavier armor there is nothing to be penalised against at all.
-- ---------------------------------------------------------------------------
local function CanEquip(link, itemID)
    local scan = ns.Subject().scan
    local level = (scan and scan.level) or (UnitLevel and UnitLevel("player")) or 0

    local okInfo, _, _, _, _, reqLevel = pcall(GetItemInfo, itemID)
    if okInfo and type(reqLevel) == "number" and reqLevel > 0 and reqLevel > level then
        return false
    end

    if _G.IsEquippableItem then
        local ok, usable = pcall(_G.IsEquippableItem, link or itemID)
        if ok and type(usable) == "boolean" and not usable then
            return false
        end
    elseif scan then
        local classID, subClassID
        if GetItemInfoInstant then
            local ok2, _, _, _, _, _, cID, sID = pcall(GetItemInfoInstant, itemID)
            if ok2 then classID, subClassID = cID, sID end
        end
        if classID == 4 and subClassID and scan.wantArmor and subClassID > scan.wantArmor then
            return false
        end
    end

    return true
end

-- ---------------------------------------------------------------------------
-- tier 3, is it genuinely better, using ItemEval where it has data
-- Prefers ns.ExplainItem, which is being added to ItemEval.lua at the same
-- time as this file and returns a structured blocking list plus a plain
-- English verdict. Falls back to ns.CompareToEquipped when ExplainItem does
-- not exist yet. Both are called through pcall so a partially loaded or
-- still changing ItemEval.lua degrades this to an item level comparison
-- instead of breaking the page.
--
-- Returns nil when the item is a hard block, meaning tier 1 above missed
-- something ItemEval itself caught, in which case it is left out entirely
-- rather than shown with a wrong number attached. Otherwise returns a table
-- with delta (nil when this spec has no researched weights) and a plain
-- English sentence explaining the verdict.
-- ---------------------------------------------------------------------------
local function EvaluateCandidate(itemID)
    if type(ns.ExplainItem) == "function" then
        local ok, result = pcall(ns.ExplainItem, itemID)
        if ok and type(result) == "table" then
            if result.blocking and #result.blocking > 0 then
                return nil
            end
            if result.noData then
                return { noSpecData = true, specReason = result.reason }
            end
            return { noSpecData = false, delta = result.delta, verdictText = result.verdictText }
        end
    end

    local ok2, delta, explanation = pcall(ns.CompareToEquipped, itemID)
    if ok2 and delta ~= nil then
        return { noSpecData = false, delta = delta, verdictText = explanation }
    end
    if ok2 then
        return { noSpecData = true,
            specReason = explanation or "GearScout could not score this item for your spec yet, comparing by item level only." }
    end

    return { noSpecData = true,
        specReason = "GearScout could not score this item for your spec yet, comparing by item level only." }
end

-- ---------------------------------------------------------------------------
-- reputation reward index, built once and cached
-- Mirrors Sources.lua's own BuildEnchantIndex: one pass over the 781 rewards
-- in ns.REP_REWARDS, pre-filtered by ns.ITEM_DB where that data exists so a
-- recipe, a piece of food or a faction token never reaches the client, then
-- indexed by the equip slot the client says the survivor actually belongs
-- in. An item still loading is counted as pending rather than skipped, so
-- ns.GetSlotUpgrades can say honestly that more results are on the way.
-- ---------------------------------------------------------------------------
local repIndexBySlot, repIndexPending

local function BuildRepIndex()
    if repIndexBySlot then return repIndexBySlot, repIndexPending end
    repIndexBySlot, repIndexPending = {}, 0

    local rep = ns.REP_REWARDS
    if type(rep) ~= "table" then return repIndexBySlot, repIndexPending end

    for factionName, faction in pairs(rep) do
        local rewards = type(faction) == "table" and faction.rewards
        if type(rewards) == "table" then
            for _, r in ipairs(rewards) do
                local itemID = r and r.item
                if itemID then
                    local d = ns.ITEM_DB and ns.ITEM_DB[itemID]
                    local worthAsking = not (d and d.c ~= 2 and d.c ~= 4)

                    if worthAsking then
                        local meta = ns.GetItemMeta(itemID)
                        if not meta then
                            repIndexPending = repIndexPending + 1
                        elseif meta.equipLoc and meta.equipLoc ~= "" then
                            local slots = EQUIP_SLOT_MAP[meta.equipLoc]
                            if slots then
                                for _, sid in ipairs(slots) do
                                    local list = repIndexBySlot[sid]
                                    if not list then
                                        list = {}
                                        repIndexBySlot[sid] = list
                                    end
                                    list[#list + 1] = {
                                        itemID   = itemID,
                                        faction  = factionName,
                                        standing = r.standing,
                                        rank     = STANDING_ORDER[r.standing] or 9,
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return repIndexBySlot, repIndexPending
end

-- ---------------------------------------------------------------------------
-- candidate gathering
-- One list per slot, item ids deduplicated. Bag items are added first and
-- always keep that slot even if the same item also drops somewhere, since
-- an item already owned is the cheapest possible source and the task this
-- file exists for says so explicitly. Everything here is either already
-- bounded and cached by the file that owns it, or, for reputation, bounded
-- to at most 781 rows and cached above.
-- ---------------------------------------------------------------------------
local function GatherCandidates(slotID, wornIlvl)
    local out, seen = {}, {}
    local pending = 0

    local function Add(itemID, kind, detail)
        if not itemID or seen[itemID] then return end
        seen[itemID] = true
        out[#out + 1] = { itemID = itemID, kind = kind, detail = detail }
    end

    local bagUp = ns.GetBagUpgrades and ns.GetBagUpgrades() or {}
    for _, it in ipairs(bagUp) do
        if it.slotID == slotID then
            Add(it.itemID, "bag", it.bank and "Already sitting in your bank." or "Already sitting in your bags.")
        end
    end

    local questUp = ns.GetQuestUpgrades and ns.GetQuestUpgrades() or {}
    for _, it in ipairs(questUp) do
        if it.slotID == slotID then
            local suffix = it.isChoice and " (one of the reward choices)." or "."
            Add(it.itemID, "quest", format("Quest reward from %s%s", it.questTitle or "a quest", suffix))
        end
    end

    if ns.FindSlotUpgrades then
        local drops = ns.FindSlotUpgrades(slotID, wornIlvl, 10)
        for _, it in ipairs(drops) do
            Add(it.itemID, "boss",
                (ns.DescribeItemSource and ns.DescribeItemSource(it.itemID))
                    or format("Drops in %s.", it.instance or "a dungeon"))
        end
        pending = pending + (drops.pending or 0)
    end

    local repBySlot, repPending = BuildRepIndex()
    local repList = repBySlot[slotID]
    if repList then
        for _, it in ipairs(repList) do
            Add(it.itemID, "reputation",
                format("Reputation reward. Reach %s standing with %s and buy it from their quartermaster.",
                    (it.standing or "the required"):lower(), it.faction or "the faction"))
        end
    end
    pending = pending + repPending

    return out, pending
end

-- ---------------------------------------------------------------------------
-- auction house pricing, optional, guarded everywhere
-- TradeSkillMaster is tried first since it is the addon this machine has
-- installed. Auctionator is tried only when TSM has nothing to say about a
-- given item. Neither call ever touches the network, both addons already
-- keep their own local price database, so this is cheap and safe to call
-- once per candidate item.
-- ---------------------------------------------------------------------------
local function DetectAHSource()
    local tsm = _G.TSM_API
    if type(tsm) == "table" and type(tsm.GetCustomPriceValue) == "function" then
        return "tsm"
    end
    local atr = _G.Auctionator
    if type(atr) == "table" and type(atr.API) == "table" and type(atr.API.v1) == "table"
       and type(atr.API.v1.GetAuctionPriceByItemID) == "function" then
        return "auctionator"
    end
    return nil
end

local ahPriceCache = {}
local function GetAHPrice(itemID)
    local cached = ahPriceCache[itemID]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    local price

    local tsm = _G.TSM_API
    if type(tsm) == "table" and type(tsm.GetCustomPriceValue) == "function" then
        local itemString
        if type(tsm.ToItemString) == "function" then
            local ok, s = pcall(tsm.ToItemString, "item:" .. itemID)
            if ok and type(s) == "string" then itemString = s end
        end
        itemString = itemString or ("i:" .. itemID)
        local ok, value = pcall(tsm.GetCustomPriceValue, "dbmarket", itemString)
        if ok and type(value) == "number" and value > 0 then
            price = value
        end
    end

    if not price then
        local atr = _G.Auctionator
        if type(atr) == "table" and type(atr.API) == "table" and type(atr.API.v1) == "table"
           and type(atr.API.v1.GetAuctionPriceByItemID) == "function" then
            local ok, value = pcall(atr.API.v1.GetAuctionPriceByItemID, ns.ADDON or "GearScout", itemID)
            if ok and type(value) == "number" and value > 0 then
                price = value
            end
        end
    end

    ahPriceCache[itemID] = price or false
    return price
end

-- Plain words, no symbols, matching the rest of this addon's writing rule.
local function MoneyText(copper)
    copper = floor((copper or 0) + 0.5)
    if copper < 0 then copper = 0 end
    local gold = floor(copper / 10000)
    local silver = floor((copper % 10000) / 100)
    local cop = copper % 100

    local parts = {}
    if gold > 0 then parts[#parts + 1] = format("%d gold", gold) end
    if silver > 0 then parts[#parts + 1] = format("%d silver", silver) end
    if cop > 0 or #parts == 0 then parts[#parts + 1] = format("%d copper", cop) end

    if #parts == 1 then return parts[1] end
    if #parts == 2 then return parts[1] .. " and " .. parts[2] end
    return parts[1] .. ", " .. parts[2] .. " and " .. parts[3]
end

-- ---------------------------------------------------------------------------
-- ns.GetSlotUpgrades(slotID)
-- The data, with no UI attached, the way Sources.lua's own functions work.
-- Cached per slot until the equipment, bags, quest log or item cache change.
-- ---------------------------------------------------------------------------
local function EvaluateSlot(slotID)
    local def = ns.SLOT_BY_ID and ns.SLOT_BY_ID[slotID]
    local scan = ns.Subject().scan

    local result = {
        slotID = slotID,
        label  = def and def.label or "Slot",
        earned = {},
        bought = {},
        pending = 0,
        ahSource = DetectAHSource(),
    }

    if not scan then
        result.note = "Your gear has not been scanned yet. Open the Gear tab once so GearScout can read what you have equipped, then come back here."
        return result
    end

    local wornRec = scan.bySlotID[slotID]
    local wornEmpty = not wornRec or wornRec.empty
    local wornIlvl = wornEmpty and 0 or (wornRec.ilvl or 0)

    if not wornEmpty then
        result.worn = {
            name = wornRec.name, link = wornRec.link, ilvl = wornRec.ilvl,
            icon = wornRec.icon, quality = wornRec.quality,
        }
    end

    if slotID == 17 and scan.twoHander then
        result.note = "You have a two handed weapon equipped, so nothing goes in your off hand right now."
        return result
    end

    local candidates, pending = GatherCandidates(slotID, wornIlvl)
    result.pending = pending

    for _, cand in ipairs(candidates) do
        local meta = ns.GetItemMeta(cand.itemID)
        if not meta then
            result.pending = result.pending + 1
        elseif meta.ilvl and meta.ilvl > wornIlvl and CanEquip(meta.link, cand.itemID) then
            local scored = EvaluateCandidate(cand.itemID)
            if scored then
                local row = {
                    itemID     = cand.itemID,
                    link       = meta.link,
                    name       = meta.name,
                    icon       = meta.icon,
                    ilvl       = meta.ilvl,
                    quality    = meta.quality,
                    wornIlvl   = wornIlvl,
                    gain       = meta.ilvl - wornIlvl,
                    delta      = scored.delta,
                    noSpecData = scored.noSpecData,
                    verdictText = scored.verdictText or scored.specReason,
                    source     = cand,
                }
                result.earned[#result.earned + 1] = row

                if result.ahSource and cand.kind ~= "bag" then
                    local price = GetAHPrice(cand.itemID)
                    if price then
                        local brow = {}
                        for k, v in pairs(row) do brow[k] = v end
                        brow.price = price
                        brow.priceText = MoneyText(price)
                        result.bought[#result.bought + 1] = brow
                    end
                end
            end
        end
    end

    -- Bag items surface first, since they cost nothing more to get. Inside
    -- each group, the biggest genuine improvement sorts first, not the
    -- biggest item level number, matching the rest of the task's rules.
    -- Cheapest effort first, so the top of the list is always the thing they
    -- could do soonest. Within a tier, the biggest genuine improvement wins,
    -- not the biggest item level number.
    table.sort(result.earned, function(a, b)
        local aTier = EFFORT_TIER[a.source and a.source.kind] or 9
        local bTier = EFFORT_TIER[b.source and b.source.kind] or 9
        if aTier ~= bTier then return aTier < bTier end
        return (a.delta or a.gain or 0) > (b.delta or b.gain or 0)
    end)

    -- Section headers are inserted as ordinary rows. The list is pooled and
    -- fixed height, so a header is just a row drawn differently rather than a
    -- second widget type, and an empty tier simply never gets a heading.
    local grouped, lastTier = {}, nil
    for _, row in ipairs(result.earned) do
        local tier = EFFORT_TIER[row.source and row.source.kind] or 9
        if tier ~= lastTier then
            grouped[#grouped + 1] = {
                isHeader = true,
                label = TIER_HEADING[tier] or "OTHER",
            }
            lastTier = tier
        end
        grouped[#grouped + 1] = row
    end
    result.earned = grouped
    table.sort(result.bought, function(a, b)
        return (a.delta or a.gain or 0) > (b.delta or b.gain or 0)
    end)

    return result
end

local slotCache = {}

function ns.GetSlotUpgrades(slotID)
    if not slotID or not (ns.SLOT_BY_ID and ns.SLOT_BY_ID[slotID]) then return nil end
    local cached = slotCache[slotID]
    if cached then return cached end
    local result = EvaluateSlot(slotID)
    slotCache[slotID] = result
    return result
end

local function InvalidateSlotCache()
    wipe(slotCache)
    repIndexBySlot, repIndexPending = nil, nil
end

ns:Sub("SCAN_UPDATED", InvalidateSlotCache)
ns:Sub("BAG_UPGRADES_UPDATED", InvalidateSlotCache)
ns:Sub("QUEST_UPGRADES_UPDATED", InvalidateSlotCache)
ns:Sub("ITEM_CACHE_UPDATED", InvalidateSlotCache)

-- ---------------------------------------------------------------------------
-- upgrades page
-- Same widget kit and layout idiom as Rotation.lua: a left hand list that
-- selects, a right hand panel that explains. The left list only ever shows
-- what is already free to know, the slot name and what is currently worn
-- there, straight from the subject scan. Working out how many upgrades exist is
-- real work, so it only happens for the slot actually selected, never for
-- all seventeen slots on every redraw.
-- ---------------------------------------------------------------------------
local UI, T = ns.UI, ns.T
local upgPage, rightPanel
local slotList, earnedList, boughtList
local wornLine, caveatLine, pendingLine
local earnedHeader, earnedEmpty
local boughtDivider, boughtHeader, boughtList2Empty
local selectedSlotID = 1
local ShowSlot

local function CreateSlotRow(list)
    local row = CreateFrame("Button", nil, list)
    row.hl = UI.Tex(row, "BACKGROUND", T.hover)
    row.hl:SetAllPoints()
    row.hl:Hide()

    row.sel = UI.Tex(row, "BACKGROUND", T.accent)
    row.sel:SetPoint("TOPLEFT")
    row.sel:SetPoint("BOTTOMLEFT")
    row.sel:SetWidth(2)
    row.sel:Hide()

    row.dot = UI.Dot(row, 7, T.dim)
    row.dot:SetPoint("LEFT", 10, -1)

    row.name = UI.Font(row, 12, T.text, nil, "LEFT")
    row.name:SetPoint("TOPLEFT", 22, -5)
    row.name:SetPoint("RIGHT", -8, 0)

    row.sub = UI.Font(row, 10, T.dim, nil, "LEFT")
    row.sub:SetPoint("TOPLEFT", 22, -20)
    row.sub:SetPoint("RIGHT", -8, 0)

    row:SetScript("OnEnter", function(self) self.hl:Show() end)
    row:SetScript("OnLeave", function(self) self.hl:Hide() end)
    return row
end

local function UpdateSlotRow(row, def)
    row.name:SetText(def.label)

    local scan = ns.Subject().scan
    local rec = scan and scan.bySlotID[def.id]
    if rec and not rec.empty then
        row.sub:SetText(format("%s, item level %d", rec.name or "Equipped item", rec.ilvl or 0))
        row.dot:SetVertexColor(unpack(T.good))
    elseif rec and rec.expectedEmpty then
        row.sub:SetText("Not used with your two handed weapon.")
        row.dot:SetVertexColor(unpack(T.dim))
    else
        row.sub:SetText("Nothing equipped.")
        row.dot:SetVertexColor(unpack(T.bad))
    end

    row.sel:SetShown(def.id == selectedSlotID)
    row:SetScript("OnClick", function()
        if ShowSlot then ShowSlot(def.id) end
        slotList:Draw()
    end)
end

local function CreateUpgradeRow(list)
    local row = CreateFrame("Frame", nil, list)
    row.stripe = UI.Tex(row, "ARTWORK", T.good)
    row.stripe:SetPoint("TOPLEFT", 0, -2)
    row.stripe:SetPoint("BOTTOMLEFT", 0, 4)
    row.stripe:SetWidth(2)

    -- Created once, only ever re-textured in FillUpgradeRowText. Both the
    -- earned and bought lists are pooled the same way CoachUI's slot list is,
    -- so a texture created inside the update path would leak one per scroll.
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("TOPLEFT", 6, -4)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Text starts 24px in (18px icon plus the same 6px gap CreateSlotRow
    -- uses) instead of the old 12px, whether or not the item's icon has
    -- resolved yet, so rows do not shift as the list scrolls.
    row.title = UI.Font(row, 12, T.text, nil, "LEFT")
    row.title:SetPoint("TOPLEFT", 30, -5)
    row.title:SetPoint("RIGHT", -80, 0)

    row.tag = UI.Font(row, 9, T.dim, nil, "RIGHT")
    row.tag:SetPoint("TOPRIGHT", -8, -6)

    row.detail = UI.Font(row, 11, T.dim, nil, "LEFT")
    row.detail:SetPoint("TOPLEFT", 30, -21)
    row.detail:SetPoint("RIGHT", -8, 0)
    row.detail:SetHeight(28)
    row.detail:SetJustifyV("TOP")

    row.price = UI.Font(row, 11, T.accent, nil, "LEFT")
    row.price:SetPoint("TOPLEFT", 30, -49)
    row.price:SetPoint("RIGHT", -8, 0)
    row.price:Hide()

    return row
end

local function FillUpgradeRowText(row, item)
    -- A section heading is the same pooled row, drawn plainly. Everything that
    -- belongs to an item is hidden rather than left showing stale text from
    -- whichever item this row displayed before it scrolled.
    if item.isHeader then
        row.stripe:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
        row.title:SetText(item.label or "")
        row.title:SetTextColor(unpack(T.accent))
        row.tag:SetText("")
        row.detail:SetText("")
        row.icon:Hide()
        row.isHeader = true
        return
    end

    if row.isHeader then
        -- Coming back from being a heading, restore the normal title colour.
        row.title:SetTextColor(unpack(T.text))
        row.isHeader = false
    end

    local c = ((item.delta and item.delta > 0) or (not item.delta and (item.gain or 0) > 0)) and T.good or T.dim
    row.stripe:SetColorTexture(c[1], c[2], c[3], 1)
    row.title:SetText(format("%s, item level %d", item.name or "Unknown item", item.ilvl or 0))
    row.tag:SetText(SOURCE_LABEL[item.source and item.source.kind] or "")

    -- Every row here is an item, so every row gets one. When the client has
    -- not cached this item's icon yet, ITEM_CACHE_UPDATED already triggers a
    -- ShowSlot() refresh (see below), which rebuilds this row with the icon
    -- once it resolves.
    if item.icon then
        row.icon:SetTexture(item.icon)
        row.icon:Show()
    else
        row.icon:Hide()
    end

    local detail = (item.source and item.source.detail) or ""
    if item.noSpecData then
        detail = detail .. format(" %s Item level %d here versus %d equipped now.",
            item.verdictText or "GearScout has no researched stat weights for your spec yet.",
            item.ilvl or 0, item.wornIlvl or 0)
    elseif item.verdictText then
        detail = detail .. " " .. item.verdictText
    end
    row.detail:SetText(detail)
end

local function UpdateEarnedRow(row, item)
    FillUpgradeRowText(row, item)
    row.price:Hide()
end

local function UpdateBoughtRow(row, item)
    FillUpgradeRowText(row, item)
    row.price:SetText("Auction house price: " .. (item.priceText or "not known"))
    row.price:Show()
end

local function AnyNoSpecData(result)
    for _, row in ipairs(result.earned) do
        if row.noSpecData then return true end
    end
    return false
end

local function LayoutForAH(showBought)
    boughtDivider:SetShown(showBought)
    boughtHeader:SetShown(showBought)
    boughtList:SetShown(showBought)
    boughtList2Empty:SetShown(false)

    earnedList:ClearAllPoints()
    earnedList:SetPoint("TOPLEFT", 8, -80)
    earnedList:SetPoint("RIGHT", -6, 0)
    if showBought then
        earnedList:SetHeight(230)
    else
        earnedList:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -6, 8)
    end
end

ShowSlot = function(slotID)
    selectedSlotID = slotID
    local result = ns.GetSlotUpgrades(slotID)

    if not result then
        wornLine:SetText("")
        caveatLine:Hide()
        pendingLine:Hide()
        LayoutForAH(false)
        earnedList:SetData({})
        boughtList:SetData({})
        return
    end

    if result.worn then
        wornLine:SetText(format("%s. Currently equipped: %s, item level %d.",
            result.label, result.worn.name or "Unknown item", result.worn.ilvl or 0))
    else
        wornLine:SetText(format("%s. Nothing equipped in this slot right now.", result.label))
    end

    if result.note then
        caveatLine:SetText(result.note)
        caveatLine:Show()
    elseif AnyNoSpecData(result) then
        caveatLine:SetText("GearScout has no researched stat weights for your spec yet. Upgrades below marked with that are ranked by item level only, not by how much they actually help.")
        caveatLine:Show()
    else
        caveatLine:Hide()
    end

    if result.pending and result.pending > 0 then
        pendingLine:SetText(format("%d more item%s still loading from the server. Reopen this tab in a moment to see them.",
            result.pending, result.pending == 1 and " is" or "s are"))
        pendingLine:Show()
    else
        pendingLine:Hide()
    end

    LayoutForAH(result.ahSource ~= nil)

    earnedList:SetData(result.earned)
    earnedEmpty:SetShown(#result.earned == 0 and not result.note)
    if #result.earned == 0 then
        earnedEmpty:SetText(result.worn
            and "Nothing found yet that beats what you have equipped there."
            or "Nothing found yet for this empty slot.")
    end

    if result.ahSource then
        boughtList:SetData(result.bought)
        boughtList2Empty:SetShown(#result.bought == 0)
    else
        boughtList:SetData({})
    end

    slotList:Refresh()
end

function ns.BuildUpgradesPage(page)
    upgPage = page

    local left = UI.Panel(page, T.panel)
    left:SetPoint("TOPLEFT", 12, -8)
    left:SetPoint("BOTTOMLEFT", 12, 8)
    left:SetWidth(230)

    local lh = UI.Font(left, 10, T.dim, nil, "LEFT")
    lh:SetPoint("TOPLEFT", 12, -10)
    lh:SetText("GEAR SLOTS")

    local sep = UI.Divider(left)
    sep:SetPoint("TOPLEFT", 10, -26)
    sep:SetPoint("TOPRIGHT", -10, -26)

    slotList = UI.List(left, 34, CreateSlotRow, UpdateSlotRow)
    slotList:SetPoint("TOPLEFT", 4, -32)
    slotList:SetPoint("BOTTOMRIGHT", -6, 8)

    rightPanel = UI.Panel(page, T.panel)
    rightPanel:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", -12, 8)

    wornLine = UI.Font(rightPanel, 13, T.text, nil, "LEFT")
    wornLine:SetPoint("TOPLEFT", 14, -12)
    wornLine:SetPoint("RIGHT", -14, 0)

    caveatLine = UI.Font(rightPanel, 10, T.warn, nil, "LEFT")
    caveatLine:SetPoint("TOPLEFT", 14, -30)
    caveatLine:SetPoint("RIGHT", -14, 0)
    caveatLine:SetHeight(24)
    caveatLine:SetJustifyV("TOP")
    caveatLine:Hide()

    pendingLine = UI.Font(rightPanel, 10, T.dim, nil, "LEFT")
    pendingLine:SetPoint("TOPLEFT", 14, -46)
    pendingLine:SetPoint("RIGHT", -14, 0)
    pendingLine:Hide()

    local sep2 = UI.Divider(rightPanel)
    sep2:SetPoint("TOPLEFT", 10, -62)
    sep2:SetPoint("TOPRIGHT", -10, -62)

    earnedHeader = UI.Font(rightPanel, 10, T.dim, nil, "LEFT")
    earnedHeader:SetPoint("TOPLEFT", 14, -68)
    earnedHeader:SetText("EARNED, THINGS YOU GO AND GET")

    earnedList = UI.List(rightPanel, 58, CreateUpgradeRow, UpdateEarnedRow)
    earnedList:SetPoint("TOPLEFT", 8, -82)
    earnedList:SetPoint("RIGHT", -6, 0)
    earnedList:SetHeight(230)

    earnedEmpty = UI.Font(rightPanel, 11, T.dim, nil, "CENTER")
    earnedEmpty:SetPoint("TOP", earnedList, "TOP", 0, -24)
    earnedEmpty:SetWidth(380)
    earnedEmpty:Hide()

    boughtDivider = UI.Divider(rightPanel)
    boughtDivider:SetPoint("TOPLEFT", earnedList, "BOTTOMLEFT", 2, -8)
    boughtDivider:SetPoint("TOPRIGHT", earnedList, "BOTTOMRIGHT", -2, -8)

    boughtHeader = UI.Font(rightPanel, 10, T.dim, nil, "LEFT")
    boughtHeader:SetPoint("TOPLEFT", boughtDivider, "BOTTOMLEFT", 4, -8)
    boughtHeader:SetText("BOUGHT, FROM THE AUCTION HOUSE")

    boughtList = UI.List(rightPanel, 74, CreateUpgradeRow, UpdateBoughtRow)
    boughtList:SetPoint("TOPLEFT", boughtHeader, "BOTTOMLEFT", -4, -6)
    boughtList:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -6, 8)

    boughtList2Empty = UI.Font(rightPanel, 11, T.dim, nil, "CENTER")
    boughtList2Empty:SetPoint("TOP", boughtList, "TOP", 0, -24)
    boughtList2Empty:SetWidth(380)
    boughtList2Empty:Hide()

    ns:Sub("SCAN_UPDATED", function()
        if not upgPage then return end
        if selectedSlotID then ShowSlot(selectedSlotID) end
    end)
    ns:Sub("BAG_UPGRADES_UPDATED", function()
        if upgPage and selectedSlotID then ShowSlot(selectedSlotID) end
    end)
    ns:Sub("QUEST_UPGRADES_UPDATED", function()
        if upgPage and selectedSlotID then ShowSlot(selectedSlotID) end
    end)
    ns:Sub("ITEM_CACHE_UPDATED", function()
        if upgPage and selectedSlotID then ShowSlot(selectedSlotID) end
    end)

    slotList:SetData(ns.SLOTS or {})
    ShowSlot((ns.SLOTS and ns.SLOTS[1] and ns.SLOTS[1].id) or 1)
end
