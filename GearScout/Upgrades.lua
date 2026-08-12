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
--            actually installed, only for items that can genuinely change
--            hands, and only when the price itself is believable for an
--            item of that level. An item belongs to exactly one of these
--            two groups and is never copied into both, so no row can say
--            "go and earn this" and "here is what it costs" at once.
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
local floor, max, unpack, select = math.floor, math.max, unpack, select

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

-- Which of those tiers can ever put an item on the auction house at all.
-- This is the same grouping as above, read for a different question, rather
-- than a second source of truth invented for pricing:
--   bag         already owned, so there is nothing to buy
--   quest       handed over by the quest, and quest rewards are soulbound
--   reputation  bought from a quartermaster with standing, not with gold on
--               the auction house, and the rewards are soulbound
--   boss        the only tier that can also be sitting on the auction house,
--               and only when the drop itself is not soulbound, which is the
--               separate bind check below
-- Whitelisted rather than blacklisted on purpose: a tier added later gets no
-- price until somebody decides it should have one.
local TRADEABLE_TIER = {
    boss = true,
}

-- Split into a short name and the qualifier that follows it, so the list can
-- draw the name loud and the qualifier quiet instead of running both together
-- in one long line. A tier with no entry here still gets a usable heading.
local TIER_HEADING = {
    [1] = { title = "ALREADY YOURS", note = "no effort at all" },
    [2] = { title = "QUEST REWARDS", note = "already in your log" },
    [3] = { title = "DROPS",         note = "one run at your level" },
    [4] = { title = "REPUTATION",    note = "a grind worth planning before you start" },
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

-- ---------------------------------------------------------------------------
-- can this item actually be bought
-- Two independent questions, both of which have to answer yes.
--
-- First the tier, above: a bag item is already owned, a quest reward is handed
-- over by the quest and a reputation reward is bought with standing at a
-- quartermaster. None of those three is ever an auction house listing, whatever
-- an auction house addon happens to say when asked about the item id.
--
-- Then the bind type, which is the client's own answer and the same call this
-- file already makes for required level in CanEquip. A soulbound drop cannot
-- change hands, so a price on it is a straightforward lie: this is exactly the
-- case that produced a row reading "Drops in Razorfen Kraul" directly above
-- "Auction house price: 196 gold".
--
-- Enum.ItemBind, as this client reports it: 0 none, 1 on pickup, 2 on equip,
-- 3 on use, 4 quest item. Tradeable values are whitelisted rather than the
-- untradeable ones blacklisted, so a bind type this addon has never heard of
-- is treated as unsellable rather than guessed at.
-- ---------------------------------------------------------------------------
local TRADEABLE_BIND = {
    [0] = true,   -- no binding at all
    [2] = true,   -- binds on equip, so it is sellable until somebody wears it
    [3] = true,   -- binds on use
}

-- Reads one value out of a pcall's returns without packing them into a table,
-- so this can be called once per candidate item without churning garbage.
-- bindType is the fourteenth value GetItemInfo returns, after the ok flag.
local function BindTypeFrom(ok, ...)
    if not ok then return nil end
    local bindType = select(14, ...)
    if type(bindType) == "number" then return bindType end
    return nil
end

local tradeableCache = {}
local function IsTradeable(itemID)
    local cached = tradeableCache[itemID]
    if cached ~= nil then return cached end

    local bindType = BindTypeFrom(pcall(GetItemInfo, itemID))

    -- No answer means the client has not cached this item yet, or is old enough
    -- not to report bind type at all. Either way there is no evidence the item
    -- can be traded, and this file would rather say nothing than state a price
    -- for something nobody can sell. Nothing is cached in that case, so the
    -- item gets asked again once ITEM_CACHE_UPDATED rebuilds the slot.
    if bindType == nil then return false end

    local tradeable = TRADEABLE_BIND[bindType] == true
    tradeableCache[itemID] = tradeable
    return tradeable
end

-- ---------------------------------------------------------------------------
-- is this price believable for an item of this level
-- A wrong price is worse than no price, because nothing on the row tells the
-- reader it is wrong. Auction house addons hand back whatever their local
-- database holds, and on a young realm that is regularly one troll listing, a
-- long dead scan, or a market with a single seller in it.
--
-- Item value in this game climbs faster than item level does, roughly with the
-- square of it, so the ceiling is quadratic rather than linear. ilvl squared,
-- divided by ten, in gold:
--   item level  29   ->     84 gold   (the level 29 ring quoted at 196 is out)
--   item level  60   ->    360 gold
--   item level  70   ->    490 gold
--   item level 115   ->  1,322 gold
--   item level 141   ->  1,988 gold   (about what the best crafted epics went
--                                      for, so real prices are not clipped)
-- Every one of those is well above what the item really trades at, which is the
-- point: this rejects readings that are wrong by an order of magnitude, not
-- ones that are merely expensive.
--
-- The floor stops very low item level pieces from being pinned to a few silver.
-- It does mean a genuine twink price on a low level piece is hidden rather than
-- shown, which is the right side to err on when the alternative is stating a
-- wrong number as a fact.
-- ---------------------------------------------------------------------------
local COPPER_PER_GOLD  = 10000
local PRICE_CEILING_MIN = 50 * COPPER_PER_GOLD

local function BelievablePrice(price, ilvl)
    if not price or price <= 0 then return nil end
    local lvl = ilvl or 0
    local ceiling = max(PRICE_CEILING_MIN, (lvl * lvl / 10) * COPPER_PER_GOLD)
    if price > ceiling then return nil end
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
                    -- What this would replace, carried on the row itself so
                    -- the list can draw the worn icon beside the new one
                    -- without reaching back into the scan while it scrolls.
                    slotID      = slotID,
                    wornIcon    = result.worn and result.worn.icon or nil,
                    wornName    = result.worn and result.worn.name or nil,
                    wornQuality = result.worn and result.worn.quality or nil,
                    wornIlvl   = wornIlvl,
                    gain       = meta.ilvl - wornIlvl,
                    delta      = scored.delta,
                    noSpecData = scored.noSpecData,
                    verdictText = scored.verdictText or scored.specReason,
                    source     = cand,
                }

                -- One row object, appended to exactly one list. The bought
                -- list used to be a shallow copy of the earned row with a
                -- price stapled on, which is how a single item ended up
                -- claiming to be both a dungeon drop to go and earn and a
                -- purchase to go and make. Routing the one table means the two
                -- groups cannot disagree about an item, because only one of
                -- them is ever holding it.
                local placed = false
                if result.ahSource and TRADEABLE_TIER[cand.kind] and IsTradeable(cand.itemID) then
                    local price = BelievablePrice(GetAHPrice(cand.itemID), meta.ilvl)
                    if price then
                        row.buyable   = true
                        row.price     = price
                        row.priceText = MoneyText(price)
                        result.bought[#result.bought + 1] = row
                        placed = true
                    end
                end
                if not placed then
                    result.earned[#result.earned + 1] = row
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
    -- Counted up front so a heading can say how many rows sit under it, which
    -- is the one thing a collapsed reading of this list cannot work out for
    -- itself once the group runs off the bottom of the visible area.
    local perTier = {}
    for _, row in ipairs(result.earned) do
        local tier = EFFORT_TIER[row.source and row.source.kind] or 9
        perTier[tier] = (perTier[tier] or 0) + 1
    end

    local grouped, lastTier = {}, nil
    for _, row in ipairs(result.earned) do
        local tier = EFFORT_TIER[row.source and row.source.kind] or 9
        if tier ~= lastTier then
            local heading = TIER_HEADING[tier]
            local n = perTier[tier] or 0
            grouped[#grouped + 1] = {
                isHeader  = true,
                label     = heading and heading.title or "OTHER",
                note      = heading and heading.note or nil,
                count     = n,
                countText = format(n == 1 and "%d upgrade" or "%d upgrades", n),
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
local wornIcon, wornIconEdge, wornSlotLine, wornLine
local caveatLine, pendingLine
local earnedHeader, earnedEmpty
local boughtDivider, boughtHeader, boughtList2Empty
local selectedSlotID = 1
local ShowSlot

-- Paperdoll art for a slot, used as the placeholder whenever there is no real
-- item icon to draw: an empty slot, or an item the client has not cached yet.
-- CoachUI.lua owns the table and loads after this file, so it is read through
-- ns at call time rather than copied at load time. A build that renames one of
-- those assets renders nothing rather than erroring, which is why a missing
-- entry here is simply "no texture" and never a special case.
local function SlotArt(slotID)
    return slotID and ns.SLOT_ART and ns.SLOT_ART[slotID] or nil
end

-- Item quality drives the ring around an icon and the colour of an item name,
-- which is the fastest read in the whole list: green, blue and purple are
-- already a language every player of this game knows.
local function QualityColor(quality)
    local q = _G.ITEM_QUALITY_COLORS
    local c = quality and type(q) == "table" and q[quality]
    if type(c) == "table" and type(c.r) == "number" then
        return c.r, c.g, c.b
    end
    return T.text[1], T.text[2], T.text[3]
end

-- Points an already created icon texture and its already created ring at an
-- item, or at the paperdoll art for the slot when there is no item. Creates
-- nothing: both textures come from the row builder, this only re-textures and
-- re-colours them, so it is safe to call from a pooled row's update path.
local function PaintIcon(icon, edge, texture, quality, slotID)
    local art = texture or SlotArt(slotID)
    if not art then
        icon:Hide()
        edge:Hide()
        return false
    end
    icon:SetTexture(art)
    icon:Show()
    if texture then
        edge:SetColorTexture(QualityColor(quality))
    else
        -- Placeholder art gets the theme's own hairline, never a quality
        -- colour it has not earned.
        edge:SetColorTexture(T.lineHard[1], T.lineHard[2], T.lineHard[3], T.lineHard[4] or 1)
    end
    edge:Show()
    return true
end

-- Long item and slot names must clip rather than wrap in the fixed height slot
-- list, or a two line name pushes the row's own text out of its box.
local function NoWrap(fs)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
end

-- ---------------------------------------------------------------------------
-- left hand slot list
-- Every row carries the icon of whatever is actually worn in that slot, with
-- the paperdoll art standing in for an empty one, so the list reads as the
-- character's own gear rather than as seventeen words.
-- ---------------------------------------------------------------------------
local SLOT_ROW_HEIGHT = 38

local function CreateSlotRow(list)
    local row = CreateFrame("Button", nil, list)

    row.hl = UI.Tex(row, "BACKGROUND", T.hover)
    row.hl:SetPoint("TOPLEFT", 0, -1)
    row.hl:SetPoint("BOTTOMRIGHT", 0, 1)
    row.hl:Hide()

    -- The selected row gets a filled band as well as the accent bar. The bar
    -- alone is easy to lose against a list this dense.
    row.selBg = UI.Tex(row, "BACKGROUND", { T.accent[1], T.accent[2], T.accent[3], 0.10 })
    row.selBg:SetPoint("TOPLEFT", 0, -1)
    row.selBg:SetPoint("BOTTOMRIGHT", 0, 1)
    row.selBg:Hide()

    row.sel = UI.Tex(row, "ARTWORK", T.accent)
    row.sel:SetPoint("TOPLEFT", 0, -1)
    row.sel:SetPoint("BOTTOMLEFT", 0, 1)
    row.sel:SetWidth(2)
    row.sel:Hide()

    -- Created once here, only ever re-textured and re-coloured in
    -- UpdateSlotRow. This list is pooled and scrolled, so a texture created in
    -- the update path would leak one object per scroll event.
    row.iconEdge = UI.Tex(row, "BACKGROUND", T.line)
    row.iconEdge:SetSize(28, 28)
    row.iconEdge:SetPoint("LEFT", 8, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("CENTER", row.iconEdge, "CENTER")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = NoWrap(UI.Font(row, 12, T.text, nil, "LEFT"))
    row.name:SetPoint("TOPLEFT", 44, -5)
    row.name:SetPoint("RIGHT", -46, 0)

    row.sub = NoWrap(UI.Font(row, 10, T.dim, nil, "LEFT"))
    row.sub:SetPoint("TOPLEFT", 44, -21)
    row.sub:SetPoint("RIGHT", -46, 0)

    -- The item level of what is worn, right aligned so the column can be read
    -- straight down without reading any of the names.
    row.ilvl = UI.Font(row, 12, T.dim, nil, "RIGHT")
    row.ilvl:SetPoint("RIGHT", -10, 0)
    row.ilvl:SetWidth(34)

    -- Set once. The row is pooled, so building this closure per update would
    -- churn a table every scroll event for no gain; the slot it points at
    -- lives on the row instead.
    row:SetScript("OnEnter", function(self)
        self.hl:Show()
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
        if self.slotID and ShowSlot then ShowSlot(self.slotID) end
    end)
    return row
end

local function UpdateSlotRow(row, def)
    row.slotID = def.id
    row.name:SetText(def.label)

    local scan = ns.Subject().scan
    local rec = scan and scan.bySlotID[def.id]

    -- Every branch writes every field. A pooled row must never keep the faded
    -- icon, the red ring or the empty item level of whichever slot it drew
    -- before it was scrolled and reused.
    if rec and not rec.empty then
        row.link = rec.link
        row.sub:SetText(rec.name or "Equipped item")
        row.sub:SetTextColor(QualityColor(rec.quality))
        row.ilvl:SetText(tostring(rec.ilvl or 0))
        row.ilvl:SetTextColor(unpack(T.text))
        PaintIcon(row.icon, row.iconEdge, rec.icon, rec.quality, def.id)
        row.icon:SetAlpha(1)
    elseif rec and rec.expectedEmpty then
        row.link = nil
        row.sub:SetText("Not used with your two hander.")
        row.sub:SetTextColor(unpack(T.dim))
        row.ilvl:SetText("")
        PaintIcon(row.icon, row.iconEdge, nil, nil, def.id)
        row.icon:SetAlpha(0.35)
    else
        row.link = nil
        row.sub:SetText("Nothing equipped.")
        row.sub:SetTextColor(unpack(T.bad))
        row.ilvl:SetText("")
        PaintIcon(row.icon, row.iconEdge, nil, nil, def.id)
        row.icon:SetAlpha(0.5)
        row.iconEdge:SetColorTexture(T.bad[1], T.bad[2], T.bad[3], 0.5)
    end

    local on = (def.id == selectedSlotID)
    row.sel:SetShown(on)
    row.selBg:SetShown(on)
    row.name:SetTextColor(unpack(on and T.accent or T.text))
end

-- ---------------------------------------------------------------------------
-- upgrade rows
--
-- Layout, left to right:
--   a 2px stripe carrying the verdict colour
--   what is worn now, faded, then an arrow, then the item being offered
--   the size of the improvement, under those icons, because that is what the
--     two icons are actually saying
--   the item name, then one line of numbers, then the sentence explaining
--     where it comes from, then the price when there is one
--
-- Rows are variable height so the explaining sentence can be two or three
-- lines without being cut off, which is what the old fixed 28px detail box was
-- doing to every drop with a real source description.
-- ---------------------------------------------------------------------------
local UPG_TEXT_LEFT  = 76   -- where the text column starts
local UPG_TEXT_RIGHT = 12   -- how far short of the right edge body text stops
local UPG_TAG_ROOM   = 78   -- reserved top right for the source label
local UPG_ICON_BLOCK = 64   -- the icons plus the improvement figure under them
local UPG_HEADER_H   = 32

-- How much of the panel's bottom the auction house block claims when there is
-- an auction house addon to read prices from: its divider, its heading and its
-- list. One constant, used both to pin that block and to stop the earned list
-- above it, so the two can never drift apart.
local BOUGHT_BLOCK_H = 230

-- A small right pointing arrow that ships with every client. If a build ever
-- renames it the texture simply does not draw, exactly like the paperdoll art
-- above, and the two icons still read as a before and after pair.
local ARROW_ART = "Interface\\CHATFRAME\\ChatFrameExpandArrow"

-- Built by both the measuring pass and the drawing pass, so a row is always
-- measured for the very text it is about to show.
local function UpgradeTitleText(item)
    return item.name or "Unknown item"
end

local function UpgradeMetaText(item)
    if (item.wornIlvl or 0) > 0 then
        return format("Item level %d, up from %d.", item.ilvl or 0, item.wornIlvl or 0)
    end
    return format("Item level %d, and that slot is empty right now.", item.ilvl or 0)
end

-- A bought row still names where the item comes from, because that is useful:
-- the choice is farm it or buy it. Saying out loud why both are possible is
-- what stops "drops in a dungeon" and "costs this much gold" reading as two
-- contradictory claims about the same item. Only rows that passed both the
-- tier check and the bind check ever carry this.
local BUYABLE_NOTE = "It is not soulbound, so you can buy it instead of farming it."

local function UpgradeDetailText(item)
    local detail = (item.source and item.source.detail) or ""
    if item.buyable then
        detail = detail .. " " .. BUYABLE_NOTE
    end
    if item.noSpecData then
        detail = detail .. " " .. (item.verdictText
            or "GearScout has no researched stat weights for your spec yet.")
    elseif item.verdictText then
        detail = detail .. " " .. item.verdictText
    end
    return (detail:gsub("^%s+", ""))
end

local function UpgradePriceText(item)
    return "Auction house price: " .. (item.priceText or "not known")
end

-- The one number the eye should land on first. A researched spec gets a real
-- score difference; a spec with no weights yet gets the item level difference
-- instead, coloured like the caveat at the top of the panel so the two read as
-- the same statement rather than as two unrelated warnings.
local function UpgradeGain(item)
    if not item.noSpecData and item.delta then
        local d = item.delta
        d = floor(d + (d >= 0 and 0.5 or -0.5))
        local c = T.dim
        if d > 0 then c = T.good elseif d < 0 then c = T.bad end
        return format("%+d", d), "SCORE", c
    end
    local g = floor((item.gain or 0) + 0.5)
    return format("%+d", g), "ITEM LEVEL", g > 0 and T.warn or T.dim
end

local function CreateUpgradeRow(list)
    local row = CreateFrame("Button", nil, list)

    row.hl = UI.Tex(row, "BACKGROUND", { 1, 1, 1, 0.03 })
    row.hl:SetPoint("TOPLEFT", 0, -1)
    row.hl:SetPoint("BOTTOMRIGHT", 0, 3)
    row.hl:Hide()

    row.stripe = UI.Tex(row, "ARTWORK", T.good)
    row.stripe:SetPoint("TOPLEFT", 0, -2)
    row.stripe:SetPoint("BOTTOMLEFT", 0, 4)
    row.stripe:SetWidth(2)

    -- Section headings get their own widgets rather than borrowing the item
    -- ones. A pooled row that reuses a font string across two very different
    -- looks has to remember to undo every property it changed; separate
    -- widgets mean the reset is simply "clear the other set".
    row.headTitle = UI.Font(row, 11, T.accent, nil, "LEFT")
    row.headTitle:SetPoint("TOPLEFT", 10, -10)

    row.headNote = UI.Font(row, 10, T.dim, nil, "LEFT")
    row.headNote:SetPoint("LEFT", row.headTitle, "RIGHT", 8, 0)

    row.headCount = UI.Font(row, 10, T.dim, nil, "RIGHT")
    row.headCount:SetPoint("TOPRIGHT", -12, -10)

    row.headRule = UI.Tex(row, "ARTWORK", T.line)
    row.headRule:SetPoint("BOTTOMLEFT", 10, 5)
    row.headRule:SetPoint("BOTTOMRIGHT", -10, 5)
    row.headRule:SetHeight(1)
    row.headRule:Hide()

    -- All four icon textures are created once here and only ever re-textured
    -- in FillUpgradeRow. Both lists are pooled and scrolled, so a texture
    -- created inside an update would leak one object per scroll event.
    row.wornEdge = UI.Tex(row, "BACKGROUND", T.line)
    row.wornEdge:SetSize(22, 22)
    row.wornEdge:SetPoint("TOPLEFT", 8, -8)

    row.wornIcon = row:CreateTexture(nil, "ARTWORK")
    row.wornIcon:SetSize(18, 18)
    row.wornIcon:SetPoint("CENTER", row.wornEdge, "CENTER")
    row.wornIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- Held back on purpose. This is the thing being replaced, so it should
    -- never compete with the thing replacing it.
    row.wornIcon:SetAlpha(0.55)

    row.arrow = row:CreateTexture(nil, "ARTWORK")
    row.arrow:SetTexture(ARROW_ART)
    row.arrow:SetSize(10, 10)
    row.arrow:SetPoint("LEFT", row.wornEdge, "RIGHT", 2, 0)
    row.arrow:SetVertexColor(T.dim[1], T.dim[2], T.dim[3], 1)

    row.newEdge = UI.Tex(row, "BACKGROUND", T.line)
    row.newEdge:SetSize(30, 30)
    row.newEdge:SetPoint("TOPLEFT", 42, -6)

    row.newIcon = row:CreateTexture(nil, "ARTWORK")
    row.newIcon:SetSize(26, 26)
    row.newIcon:SetPoint("CENTER", row.newEdge, "CENTER")
    row.newIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.gain = UI.Font(row, 13, T.good, nil, "CENTER")
    row.gain:SetPoint("TOPLEFT", 6, -40)
    row.gain:SetWidth(66)

    row.gainUnit = NoWrap(UI.Font(row, 9, T.dim, nil, "CENTER"))
    row.gainUnit:SetPoint("TOPLEFT", 6, -55)
    row.gainUnit:SetWidth(66)

    -- Left wrapping on purpose, unlike the fixed height slot list. These rows
    -- size themselves, and the measuring pass wraps this same text at this
    -- same width, so a long item name grows the row instead of being cut off.
    row.title = UI.Font(row, 12, T.text, nil, "LEFT")
    row.title:SetPoint("TOPLEFT", UPG_TEXT_LEFT, -8)
    row.title:SetPoint("RIGHT", -UPG_TAG_ROOM, 0)

    row.tag = UI.Font(row, 9, T.dim, nil, "RIGHT")
    row.tag:SetPoint("TOPRIGHT", -UPG_TEXT_RIGHT, -9)

    -- Each line hangs off the bottom of the one above it and carries no fixed
    -- height, so a font string sizes itself to however many lines its text
    -- actually wraps to, and an empty one collapses to nothing. This is what
    -- lets the measuring pass and the drawn row agree.
    row.meta = UI.Font(row, 11, T.text, nil, "LEFT")
    row.meta:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
    row.meta:SetPoint("RIGHT", -UPG_TEXT_RIGHT, 0)
    row.meta:SetJustifyV("TOP")

    row.detail = UI.Font(row, 11, T.dim, nil, "LEFT")
    row.detail:SetPoint("TOPLEFT", row.meta, "BOTTOMLEFT", 0, -3)
    row.detail:SetPoint("RIGHT", -UPG_TEXT_RIGHT, 0)
    row.detail:SetJustifyV("TOP")

    row.price = UI.Font(row, 11, T.accent, nil, "LEFT")
    row.price:SetPoint("TOPLEFT", row.detail, "BOTTOMLEFT", 0, -3)
    row.price:SetPoint("RIGHT", -UPG_TEXT_RIGHT, 0)
    row.price:SetJustifyV("TOP")

    -- Set once, reading the row's own item. A heading has nothing to show.
    row:SetScript("OnEnter", function(self)
        local it = self.item
        if not it or it.isHeader then return end
        self.hl:Show()
        if not it.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetHyperlink(it.link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip:Hide()
    end)

    return row
end

-- Measured against the same insets the row is drawn at. The two have to agree
-- or rows get sized for a width they are never drawn at.
local function MeasureUpgradeRow(item, width, withPrice)
    if item.isHeader then return UPG_HEADER_H end

    local wTitle = max(1, (width or 0) - UPG_TEXT_LEFT - UPG_TAG_ROOM)
    local wBody  = max(1, (width or 0) - UPG_TEXT_LEFT - UPG_TEXT_RIGHT)

    local h = 8 + UI.MeasureText(12, wTitle, UpgradeTitleText(item))
    h = h + 2 + UI.MeasureText(11, wBody, UpgradeMetaText(item))
    h = h + 3 + UI.MeasureText(11, wBody, UpgradeDetailText(item))
    if withPrice then
        h = h + 3 + UI.MeasureText(11, wBody, UpgradePriceText(item))
    end

    -- Never shorter than the icon column, so the improvement figure under the
    -- icons always has somewhere to sit.
    return max(UPG_ICON_BLOCK + 6, h + 9)
end

local function MeasureEarnedRow(item, width)
    return MeasureUpgradeRow(item, width, false)
end

local function MeasureBoughtRow(item, width)
    return MeasureUpgradeRow(item, width, true)
end

-- Pooled rows are reused across both looks, so every widget is written on
-- every pass. Nothing is left carrying text or a colour from whichever item,
-- or heading, this row happened to draw before it scrolled.
local function FillUpgradeRow(row, item)
    row.item = item

    if item.isHeader then
        row.headTitle:SetText(item.label or "")
        row.headNote:SetText(item.note or "")
        row.headCount:SetText(item.countText or "")
        row.headRule:Show()

        row.stripe:Hide()
        row.hl:Hide()
        row.wornIcon:Hide()
        row.wornEdge:Hide()
        row.arrow:Hide()
        row.newIcon:Hide()
        row.newEdge:Hide()
        row.gain:SetText("")
        row.gainUnit:SetText("")
        row.title:SetText("")
        row.tag:SetText("")
        row.meta:SetText("")
        row.detail:SetText("")
        row.price:SetText("")
        return
    end

    row.headTitle:SetText("")
    row.headNote:SetText("")
    row.headCount:SetText("")
    row.headRule:Hide()

    local gainText, gainUnit, gainColor = UpgradeGain(item)
    row.stripe:SetColorTexture(gainColor[1], gainColor[2], gainColor[3], 1)
    row.stripe:Show()

    -- What is worn there now, then what is on offer. When the client has not
    -- cached an item's icon yet the paperdoll art for the slot stands in, and
    -- ITEM_CACHE_UPDATED already triggers a ShowSlot() refresh that redraws
    -- this row properly once the icon resolves.
    local shownWorn = PaintIcon(row.wornIcon, row.wornEdge, item.wornIcon,
                                item.wornQuality, item.slotID)
    row.arrow:SetShown(shownWorn)
    PaintIcon(row.newIcon, row.newEdge, item.icon, item.quality, item.slotID)

    row.gain:SetText(gainText)
    row.gain:SetTextColor(gainColor[1], gainColor[2], gainColor[3], 1)
    row.gainUnit:SetText(gainUnit)

    row.title:SetText(UpgradeTitleText(item))
    row.title:SetTextColor(QualityColor(item.quality))
    row.tag:SetText(SOURCE_LABEL[item.source and item.source.kind] or "")
    row.meta:SetText(UpgradeMetaText(item))
    row.detail:SetText(UpgradeDetailText(item))
end

local function UpdateEarnedRow(row, item)
    FillUpgradeRow(row, item)
    if not item.isHeader then row.price:SetText("") end
end

local function UpdateBoughtRow(row, item)
    FillUpgradeRow(row, item)
    if not item.isHeader then row.price:SetText(UpgradePriceText(item)) end
end

-- Both lists, because an item now lives in one or the other rather than in
-- both, so a spec with no weights can show up only under the bought heading.
local function AnyNoSpecData(result)
    for _, row in ipairs(result.earned) do
        if row.noSpecData then return true end
    end
    for _, row in ipairs(result.bought) do
        if row.noSpecData then return true end
    end
    return false
end

-- The caveat and the loading note both come and go, so the list below them
-- cannot sit at a fixed offset without leaving a hole whenever one of them is
-- absent. This stacks whatever is actually showing and hands back where the
-- earned list should start. It re-anchors existing widgets and creates
-- nothing, and it runs once per slot selection, never per row.
local function LayoutPanel(showCaveat, showPending, showBought)
    -- Both notices wrap, so how much room each one needs is measured rather
    -- than assumed. UI.MeasureText reuses one hidden font string per size, so
    -- this allocates nothing. The width falls back to a sane figure for the
    -- very first call, before the page has been given its real size.
    local panelW = rightPanel:GetWidth() or 0
    if panelW <= 1 then panelW = 500 end
    local textW = max(1, panelW - 28)

    local y = 62

    caveatLine:ClearAllPoints()
    caveatLine:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 14, -y)
    caveatLine:SetPoint("RIGHT", rightPanel, "RIGHT", -14, 0)
    caveatLine:SetShown(showCaveat)
    if showCaveat then
        y = y + max(16, UI.MeasureText(10, textW, caveatLine:GetText() or "")) + 8
    end

    pendingLine:ClearAllPoints()
    pendingLine:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 14, -y)
    pendingLine:SetPoint("RIGHT", rightPanel, "RIGHT", -14, 0)
    pendingLine:SetShown(showPending)
    if showPending then
        y = y + max(14, UI.MeasureText(10, textW, pendingLine:GetText() or "")) + 6
    end

    earnedHeader:ClearAllPoints()
    earnedHeader:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 14, -y)
    y = y + 16

    boughtDivider:SetShown(showBought)
    boughtHeader:SetShown(showBought)
    boughtList:SetShown(showBought)
    boughtList2Empty:SetShown(false)

    -- Two points only, a top left and a bottom right. Adding a third that
    -- carries a centre line as well would leave the height over specified and
    -- the list at the mercy of which anchor the client resolves last.
    earnedList:ClearAllPoints()
    earnedList:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 8, -y)
    if showBought then
        earnedList:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -6, BOUGHT_BLOCK_H + 8)
    else
        earnedList:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -6, 8)
    end
end

-- The equipped item card at the top of the panel. This is the same answer the
-- slot list on the left gives, restated for the slot actually being looked at,
-- so the question "better than what?" is always on screen next to the list of
-- things claiming to be better.
local function ShowWorn(result)
    if not result then
        wornSlotLine:SetText("")
        wornLine:SetText("")
        wornLine:SetTextColor(unpack(T.dim))
        PaintIcon(wornIcon, wornIconEdge, nil, nil, nil)
        return
    end

    wornSlotLine:SetText(result.label or "Slot")

    if result.worn then
        wornLine:SetText(format("%s, item level %d",
            result.worn.name or "Unknown item", result.worn.ilvl or 0))
        wornLine:SetTextColor(QualityColor(result.worn.quality))
        PaintIcon(wornIcon, wornIconEdge, result.worn.icon, result.worn.quality, result.slotID)
        wornIcon:SetAlpha(1)
    else
        wornLine:SetText("Nothing equipped here right now.")
        wornLine:SetTextColor(unpack(T.dim))
        PaintIcon(wornIcon, wornIconEdge, nil, nil, result.slotID)
        wornIcon:SetAlpha(0.5)
    end
end

ShowSlot = function(slotID)
    selectedSlotID = slotID
    local result = ns.GetSlotUpgrades(slotID)

    if not result then
        ShowWorn(nil)
        LayoutPanel(false, false, false)
        earnedList:SetData({})
        boughtList:SetData({})
        earnedEmpty:Hide()
        slotList:Refresh()
        return
    end

    ShowWorn(result)

    local showCaveat = true
    if result.note then
        caveatLine:SetText(result.note)
    elseif AnyNoSpecData(result) then
        caveatLine:SetText("GearScout has no researched stat weights for your spec yet. Anything below showing an item level figure instead of a score is ranked by item level only, not by how much it actually helps.")
    else
        showCaveat = false
    end

    local showPending = (result.pending or 0) > 0
    if showPending then
        pendingLine:SetText(format("%d more item%s still loading from the server. Reopen this tab in a moment to see them.",
            result.pending, result.pending == 1 and " is" or "s are"))
    end

    LayoutPanel(showCaveat, showPending, result.ahSource ~= nil)

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
        -- This block is empty far more often now that soulbound drops, quest
        -- rewards and reputation rewards no longer get a price stapled to
        -- them, so it says why rather than sitting there blank.
        if #result.bought == 0 then
            boughtList2Empty:SetText("Nothing for this slot can be bought. Quest and reputation rewards are soulbound, and so is everything above that a boss has to drop for you personally.")
        end
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
    -- Wider than it was, because each row now carries an icon, the slot name,
    -- the name of what is worn there and its item level without any of the
    -- four crowding the others.
    left:SetWidth(246)

    local lh = UI.Font(left, 10, T.dim, nil, "LEFT")
    lh:SetPoint("TOPLEFT", 12, -10)
    lh:SetText("GEAR SLOTS")

    local lhRight = UI.Font(left, 9, T.dim, nil, "RIGHT")
    lhRight:SetPoint("TOPRIGHT", -12, -10)
    lhRight:SetText("EQUIPPED")

    local sep = UI.Divider(left)
    sep:SetPoint("TOPLEFT", 10, -26)
    sep:SetPoint("TOPRIGHT", -10, -26)

    slotList = UI.List(left, SLOT_ROW_HEIGHT, CreateSlotRow, UpdateSlotRow)
    slotList:SetPoint("TOPLEFT", 4, -32)
    slotList:SetPoint("BOTTOMRIGHT", -6, 8)

    rightPanel = UI.Panel(page, T.panel)
    rightPanel:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", -12, 8)

    -- The equipped item card. Created once here, only ever re-textured by
    -- ShowWorn, which runs once per slot selection rather than per row.
    wornIconEdge = UI.Tex(rightPanel, "BACKGROUND", T.line)
    wornIconEdge:SetSize(38, 38)
    wornIconEdge:SetPoint("TOPLEFT", 14, -12)

    wornIcon = rightPanel:CreateTexture(nil, "ARTWORK")
    wornIcon:SetSize(34, 34)
    wornIcon:SetPoint("CENTER", wornIconEdge, "CENTER")
    wornIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Stops well short of the right edge so it can never run under the label
    -- sitting in that corner.
    wornSlotLine = NoWrap(UI.Font(rightPanel, 13, T.text, nil, "LEFT"))
    wornSlotLine:SetPoint("TOPLEFT", 60, -14)
    wornSlotLine:SetPoint("RIGHT", -100, 0)

    wornLine = NoWrap(UI.Font(rightPanel, 11, T.dim, nil, "LEFT"))
    wornLine:SetPoint("TOPLEFT", 60, -32)
    wornLine:SetPoint("RIGHT", -14, 0)

    local wornTag = UI.Font(rightPanel, 9, T.dim, nil, "RIGHT")
    wornTag:SetPoint("TOPRIGHT", -14, -14)
    wornTag:SetText("EQUIPPED NOW")

    local sep2 = UI.Divider(rightPanel)
    sep2:SetPoint("TOPLEFT", 10, -56)
    sep2:SetPoint("TOPRIGHT", -10, -56)

    -- Both of these are re-anchored by LayoutPanel every time a slot is
    -- selected, so the offsets here only matter until the first ShowSlot.
    -- No fixed height on either: they size themselves to however many lines
    -- their text wraps to, and LayoutPanel measures the same text to decide
    -- what sits below them. The old fixed 24px box silently cut the caveat off.
    caveatLine = UI.Font(rightPanel, 10, T.warn, nil, "LEFT")
    caveatLine:SetPoint("TOPLEFT", 14, -62)
    caveatLine:SetPoint("RIGHT", -14, 0)
    caveatLine:SetJustifyV("TOP")
    caveatLine:Hide()

    pendingLine = UI.Font(rightPanel, 10, T.dim, nil, "LEFT")
    pendingLine:SetPoint("TOPLEFT", 14, -62)
    pendingLine:SetPoint("RIGHT", -14, 0)
    pendingLine:SetJustifyV("TOP")
    pendingLine:Hide()

    earnedHeader = UI.Font(rightPanel, 10, T.dim, nil, "LEFT")
    earnedHeader:SetPoint("TOPLEFT", 14, -62)
    earnedHeader:SetText("EARNED, THINGS YOU GO AND GET")

    -- Variable height rows. 70 is the shortest a row can be, which is the icon
    -- column plus its padding, and it is only used to size the row pool; the
    -- real height of each row comes from the measure function, so a drop with
    -- a three line source description is no longer cut off mid sentence.
    earnedList = UI.List(rightPanel, 70, CreateUpgradeRow, UpdateEarnedRow, MeasureEarnedRow)
    earnedList:SetPoint("TOPLEFT", 8, -78)
    earnedList:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -6, 8)

    earnedEmpty = UI.Font(rightPanel, 11, T.dim, nil, "CENTER")
    earnedEmpty:SetPoint("TOP", earnedList, "TOP", 0, -24)
    earnedEmpty:SetWidth(380)
    earnedEmpty:Hide()

    -- The auction house block is pinned to the bottom of the panel by one
    -- constant, and the earned list above it grows into whatever is left,
    -- rather than the earned list carrying a fixed height that stops matching
    -- as soon as the caveat or the loading note appears above it.
    boughtDivider = UI.Divider(rightPanel)
    boughtDivider:SetPoint("BOTTOMLEFT", rightPanel, "BOTTOMLEFT", 10, BOUGHT_BLOCK_H)
    boughtDivider:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -8, BOUGHT_BLOCK_H)

    boughtHeader = UI.Font(rightPanel, 10, T.dim, nil, "LEFT")
    boughtHeader:SetPoint("TOPLEFT", boughtDivider, "BOTTOMLEFT", 4, -8)
    boughtHeader:SetText("BOUGHT, FROM THE AUCTION HOUSE")

    boughtList = UI.List(rightPanel, 70, CreateUpgradeRow, UpdateBoughtRow, MeasureBoughtRow)
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
