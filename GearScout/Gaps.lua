-- GearScout / Gaps.lua
-- Readiness gaps that have nothing to do with item level, but still cost a
-- levelling character a great deal: unspent talent points, ammo, quivers and
-- ammo pouches, riding skill, an empty ranged slot on a melee class, missing
-- weapon buffs, and starving on bag space.
--
-- Writing rule, matched from Rules.lua: every message says three things in
-- plain words. What is wrong, why it costs you, and exactly what to do about
-- it. No jargon, no shorthand, no assumed knowledge.
--
-- Conservative on purpose throughout this file. Several of the checks below
-- lean on APIs this file cannot verify against a live client, so each one is
-- written to skip quietly rather than guess when it is not sure. A missing
-- warning is a smaller mistake than a wrong one.

local ADDON, ns = ...

local SEV = ns.SEVERITY
local ipairs, pairs, format, type = ipairs, pairs, string.format, type
local GetInventoryItemLink = GetInventoryItemLink
local GetInventoryItemCount = GetInventoryItemCount
local GetItemInfo = GetItemInfo

-- ---------------------------------------------------------------------------
-- score weights
-- Independent of Rules.lua's own weights. These issues are not gear quality,
-- so they are not mixed into that score.
-- ---------------------------------------------------------------------------
local W = {
    talentPoints = 6,
    noAmmo       = 15,
    oldAmmo      = 5,
    lowAmmo      = 4,
    noQuiver     = 6,
    noRiding     = 8,
    emptyRanged  = 6,
    noWeaponBuff = 3,
    starterBag   = 8,
    bagsFull     = 10,
}

-- ---------------------------------------------------------------------------
-- issue helper, same shape Rules.lua uses
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

-- ---------------------------------------------------------------------------
-- talent points
-- GetUnspentTalentPoints is the classic global for this. It is guarded rather
-- than trusted, since this client's talent API already changed shape once
-- (GetTalentTabInfo, handled in Core.lua) and there is no way to confirm this
-- one still returns a plain number without a live client.
-- ---------------------------------------------------------------------------
local function CheckTalentPoints(issues)
    if not _G.GetUnspentTalentPoints then return end
    local ok, pts = pcall(_G.GetUnspentTalentPoints)
    if not ok or type(pts) ~= "number" or pts <= 0 then return end

    Add(issues, SEV.WARN, nil,
        format("You have %d unspent talent point%s", pts, pts == 1 and "" or "s"),
        "Talent points make your character permanently stronger and cost nothing to spend. Right now they are sitting unused and doing nothing for you.",
        "Open your talents from the main menu, or press the default key N, and click a point into any tree you like. You can move points around again later for a fee.",
        W.talentPoints)
end

-- ---------------------------------------------------------------------------
-- ammo
-- Slot 0 is Ammo, and it is not one of the 17 slots Scan.lua reads, so this
-- file reads the equipped ranged weapon and the ammo slot directly.
-- Bows and Crossbows use arrows, Guns use bullets, Thrown weapons and Wands
-- use neither. The three numeric weapon subclass ids below (2, 3, 18) are the
-- same ones already trusted elsewhere in this addon for scope eligibility.
-- ---------------------------------------------------------------------------
local RANGED_AMMO_KIND = {
    [2]  = "quiver", -- Bows
    [18] = "quiver", -- Crossbows
    [3]  = "pouch",  -- Guns
}

local function GetRangedWeaponInfo()
    local link = GetInventoryItemLink("player", 18)
    if not link then return nil end

    local itemID = tonumber(link:match("item:(%d+)"))
    local subClassID
    if _G.GetItemInfoInstant and itemID then
        local ok, _, _, _, _, _, _, subClass = pcall(_G.GetItemInfoInstant, itemID)
        if ok then subClassID = subClass end
    end
    return { link = link, itemID = itemID, subClassID = subClassID }
end

-- Everything this file learned about ammo, in one place, so the UI can show
-- it later without re-deriving any of it.
local function BuildAmmoInfo()
    local info = {
        equipped  = false, -- something is in the ranged slot at all
        needsAmmo = false, -- that something is a bow, crossbow or gun
        ammoKind  = nil,   -- "quiver" or "pouch"
        ammoLink  = nil,
        ammoName  = nil,
        count     = 0,
        minLevel  = nil,
    }

    local ranged = GetRangedWeaponInfo()
    if not ranged then return info end
    info.equipped = true

    local kind = RANGED_AMMO_KIND[ranged.subClassID]
    if not kind then return info end
    info.needsAmmo = true
    info.ammoKind = kind

    -- The ammo slot is inventory id 0, but reading it with a single call is
    -- unreliable on this client, the same way the bag slots were. Several
    -- signals are tried and any one of them proving ammo exists is enough.
    -- If every one of them comes back empty, that is treated as "cannot tell"
    -- rather than "no ammo", because falsely telling a hunter their quiver is
    -- empty is worse than saying nothing.
    local AMMO_SLOT = 0
    local ammoLink = GetInventoryItemLink("player", AMMO_SLOT)
    local ammoID = _G.GetInventoryItemID and GetInventoryItemID("player", AMMO_SLOT) or nil
    local ammoTex = _G.GetInventoryItemTexture and GetInventoryItemTexture("player", AMMO_SLOT) or nil
    local count = GetInventoryItemCount and (GetInventoryItemCount("player", AMMO_SLOT) or 0) or 0

    info.ammoLink = ammoLink
    info.count = count

    local anySignal = ammoLink or ammoID or ammoTex or (count > 0)
    if not anySignal then
        -- Nothing answered. Distinguish an empty slot from an API that does
        -- not report this slot at all: if the ranged weapon reads fine but
        -- every ammo probe is silent, the probes are the problem.
        info.unknown = true
        return info
    end

    if not ammoLink then
        -- Something is loaded, we just could not get a link for it. That is
        -- enough to stay quiet about an empty slot.
        info.present = true
        return info
    end
    info.present = true

    local meta = ns.GetItemMeta(ammoLink)
    if meta then info.ammoName = meta.name end

    if GetItemInfo then
        local _, _, _, _, minLevel = GetItemInfo(ammoLink)
        if type(minLevel) == "number" then info.minLevel = minLevel end
    end

    return info
end

local function CheckAmmo(issues, info)
    if not info.needsAmmo then return end
    local rec = { slotID = 0, label = "Ammo" }

    -- Only accuse when the client actually said the slot is empty. When it
    -- said nothing at all, stay silent: a hunter who can see their own ammo
    -- being told they have none destroys trust in every other line here.
    if info.unknown then return end

    if not info.present then
        Add(issues, SEV.CRITICAL, rec,
            "You have no ammo loaded",
            "Your bow, crossbow or gun needs arrows or bullets sitting in your ammo slot to fire at all. That slot is empty right now, so you cannot attack at range.",
            "Buy arrows or bullets from any vendor that sells weapons, whichever your weapon uses, then right click the stack to load it into your ammo slot.",
            W.noAmmo)
        return
    end

    -- A large gap on purpose. Ammo item level tracks roughly with the level
    -- it was sold at, so only flag ammo that is unmistakably left over from
    -- many levels ago, not ammo that is merely a tier or two behind.
    local level = ns.playerLevel or 0
    if info.minLevel and info.minLevel > 0 and (level - info.minLevel) > 20 then
        Add(issues, SEV.WARN, rec,
            "Your ammo is far below your level",
            format("%s is old ammo, meant for characters level %d and under. Ammo damage scales with the ammo itself, so this is doing noticeably less damage than ammo made for where you are now.",
                   info.ammoName or "Your current ammo", info.minLevel),
            "Buy the newest arrows or bullets a weapons vendor near your level sells, and load those instead.",
            W.oldAmmo)
    end

    -- A count of zero here means the client would not tell us, not that the
    -- quiver is empty, because an actually empty slot was already handled
    -- above. Warning that someone has "0 left" while they can see a full
    -- quiver is the same false accusation as the one this file just fixed.
    if info.count > 0 and info.count < 50 then
        Add(issues, SEV.WARN, rec,
            format("You are low on ammo: %d left", info.count),
            "Ammo is used up on every shot. Running out in the middle of a fight leaves you with no ranged attack at all until you restock.",
            "Buy a full stack from any vendor that sells ammo before you head back out to quest.",
            W.lowAmmo)
    end
end

-- ---------------------------------------------------------------------------
-- quiver or ammo pouch
-- Both share the same equip location on this client, INVTYPE_QUIVER, so a
-- Quiver and an Ammo Pouch cannot be told apart from that alone. That is
-- fine here: either one means "you own something that speeds up your shooting",
-- which is all this check needs to know. Bag slots are inventory ids 20-23.
-- ---------------------------------------------------------------------------
-- Bag slots were read as hardcoded inventory ids 20 to 23, which returned
-- nothing on this client and made a character with three bags and a quiver
-- look like they had neither. Ask the container API for the inventory id
-- instead of assuming it, and identify a quiver by its item class rather than
-- its equip location, since a quiver does not reliably report INVTYPE_QUIVER.
local BagInvID = (C_Container and C_Container.ContainerIDToInventoryID)
                 or _G.ContainerIDToInventoryID
local BagNumSlots = (C_Container and C_Container.GetContainerNumSlots)
                    or _G.GetContainerNumSlots

local ITEM_CLASS_QUIVER = 11   -- subclass 2 is Quiver, 3 is Ammo Pouch

-- The link of whatever is equipped in bag slot 1 to 4, or nil.
local function EquippedBagLink(bag)
    if not BagInvID then return nil end
    local ok, invID = pcall(BagInvID, bag)
    if not ok or not invID then return nil end
    return GetInventoryItemLink("player", invID)
end

local function CheckQuiver(issues, ammoInfo)
    if not ammoInfo.needsAmmo then return end

    local hasOne = false
    for bag = 1, (_G.NUM_BAG_SLOTS or 4) do
        local link = EquippedBagLink(bag)
        if link and GetItemInfoInstant then
            local _, _, _, _, _, classID = GetItemInfoInstant(link)
            if classID == ITEM_CLASS_QUIVER then
                hasOne = true
                break
            end
        end
    end
    if hasOne then return end

    local label = ammoInfo.ammoKind == "pouch" and "ammo pouch" or "quiver"
    Add(issues, SEV.WARN, nil,
        format("You do not have %s %s", label == "ammo pouch" and "an" or "a", label),
        format("A %s holds your ammo and makes you shoot noticeably faster. Without one, your shooting speed is stuck at its slowest for no reason.",
               label),
        format("Buy a %s from a leatherworker, the auction house, or a vendor near your class trainer, then drag it onto any empty bag slot. It works from there without doing anything else.",
               label),
        W.noQuiver)
end

-- ---------------------------------------------------------------------------
-- riding skill
-- Checked by spell id, the same way Core.lua checks for the Enchanting
-- profession, since that is the only reliable "do you know this" signal this
-- addon has. The ids below are the standard Journeyman, Expert and Artisan
-- riding spells. Before trusting any of them, the resolved spell name is
-- checked for the word "rid" so a wrong id on this client is skipped instead
-- of producing a message about the wrong thing.
-- ---------------------------------------------------------------------------
local RIDE_SPELL = { journeyman = 33391, expert = 34090, artisan = 34091 }

local function KnowsRideRank(id)
    local name = ns.SpellName(id)
    if not name or not name:lower():find("rid", 1, true) then
        return nil -- cannot confirm this id means riding on this client, skip
    end
    return ns.SpellKnown(id)
end

local function CheckRiding(issues)
    local level = ns.playerLevel or 0

    if level >= 40 then
        local j, e, a = KnowsRideRank(RIDE_SPELL.journeyman), KnowsRideRank(RIDE_SPELL.expert), KnowsRideRank(RIDE_SPELL.artisan)
        if j ~= nil and e ~= nil and a ~= nil and not (j or e or a) then
            Add(issues, SEV.WARN, nil,
                "You can learn to ride but have not",
                "From level 40 you can train riding, which lets you buy a mount. A mount moves much faster than running everywhere on foot.",
                "Find a riding trainer in any major city, pay for riding training, then buy a mount from the stable master standing nearby.",
                W.noRiding)
        end
    end

    if level >= 60 then
        local e, a = KnowsRideRank(RIDE_SPELL.expert), KnowsRideRank(RIDE_SPELL.artisan)
        if e ~= nil and a ~= nil and not (e or a) then
            Add(issues, SEV.WARN, nil,
                "You can learn expert riding but have not",
                "From level 60 you can train expert riding, which is what allows you to fly once you reach Outland.",
                "Find a riding trainer, pay for expert riding training, then buy a flying mount once you are in Outland.",
                W.noRiding)
        end
    end
end

-- ---------------------------------------------------------------------------
-- empty ranged or thrown slot on a melee class
-- Restricted to classes with no attack spell to open a fight from range.
-- ---------------------------------------------------------------------------
local PURE_MELEE = { WARRIOR = true, ROGUE = true, PALADIN = true }

local function CheckEmptyRangedForMelee(issues, ammoInfo)
    local level = ns.playerLevel or 0
    if level < 5 then return end
    if not PURE_MELEE[ns.playerClass] then return end
    if ammoInfo.equipped then return end

    Add(issues, SEV.WARN, { slotID = 18, label = "Ranged" },
        "Your ranged slot is empty",
        "A cheap thrown weapon or a bow in that slot lets you damage an enemy before it reaches you, which is how most players start a fight on their own terms instead of the enemy's.",
        "Buy a throwing weapon or a bow from any vendor that sells weapons and equip it in your ranged slot. It does not need to be good, it only needs to be there.",
        W.emptyRanged)
end

-- ---------------------------------------------------------------------------
-- temporary weapon buffs
-- GetWeaponEnchantInfo is already trusted unguarded elsewhere in this addon
-- (Scan.lua calls it the same way), so it is called the same way here.
-- Limited to the two classes where a temporary weapon buff is genuinely
-- standard practice rather than optional: a poison for a rogue, and a
-- sharpening stone or weightstone for a warrior.
-- ---------------------------------------------------------------------------
local WEAPON_BUFF_LABEL = {
    ROGUE   = "a poison",
    WARRIOR = "a sharpening stone or weightstone",
}

local function CheckWeaponBuff(issues)
    local level = ns.playerLevel or 0
    if level < 10 then return end

    local label = WEAPON_BUFF_LABEL[ns.playerClass]
    if not label then return end

    local mainLink = GetInventoryItemLink("player", 16)
    if not mainLink then return end

    local hasMH = GetWeaponEnchantInfo()
    if hasMH then return end

    Add(issues, SEV.INFO, { slotID = 16, label = "Main Hand" },
        "No temporary buff on your main hand weapon",
        format("%s applied to your weapon adds real damage for a while, and keeping one active is standard practice for a %s.",
               label:sub(1, 1):upper() .. label:sub(2), ns.playerClass == "ROGUE" and "rogue" or "warrior"),
        format("Buy %s from a vendor or the auction house, right click it, then click your main hand weapon to apply it.", label),
        W.noWeaponBuff)
end

-- ---------------------------------------------------------------------------
-- bags
-- GetContainerNumFreeSlots moved under C_Container on this client, matching
-- the container API relocation already documented in Scan.lua for item
-- stats. Bag slots are inventory ids 20-23; if all four are empty the
-- character still owns nothing but the starting backpack.
-- ---------------------------------------------------------------------------
local GetFreeSlots = (C_Container and C_Container.GetContainerNumFreeSlots) or _G.GetContainerNumFreeSlots

local function CheckBags(issues)
    -- A bag slot with any capacity has a bag in it. This is more reliable than
    -- reading a hardcoded inventory id, which is what previously reported a
    -- character carrying three bags and a quiver as having none.
    local hasExtraBag = false
    for bag = 1, (_G.NUM_BAG_SLOTS or 4) do
        local slots = 0
        if BagNumSlots then
            local ok, n = pcall(BagNumSlots, bag)
            if ok and type(n) == "number" then slots = n end
        end
        if slots > 0 or EquippedBagLink(bag) then
            hasExtraBag = true
            break
        end
    end

    if not hasExtraBag then
        Add(issues, SEV.WARN, nil,
            "You are still using only your starting backpack",
            "With no extra bags equipped you have very little room to carry quest items, gear you pick up, or anything worth selling, so you have to stop and empty your bags far more often than you need to.",
            "Buy any bag from a vendor, even a small cheap one, and drag it onto an empty slot in your backpack. Every extra bag helps.",
            W.starterBag)
    end

    if GetFreeSlots then
        local totalFree = 0
        local numBagSlots = _G.NUM_BAG_SLOTS or 4
        for bag = 0, numBagSlots do
            local ok, free = pcall(GetFreeSlots, bag)
            if ok and type(free) == "number" then totalFree = totalFree + free end
        end
        if totalFree <= 0 then
            Add(issues, SEV.CRITICAL, nil,
                "Your bags are completely full",
                "With zero free slots you cannot pick up quest items, loot, or anything else until you make room.",
                "Sell or delete anything you do not need at a vendor, or mail items to another character, before you keep playing.",
                W.bagsFull)
        end
    end
end

-- ---------------------------------------------------------------------------
-- public
-- ---------------------------------------------------------------------------

-- What this file learned about ammo, exposed on its own so the UI can show
-- it separately from the issue list.
function ns.GetAmmoInfo()
    return BuildAmmoInfo()
end

-- Every readiness gap found right now, most severe first. Empty table when
-- there is nothing to report.
function ns.GetReadinessIssues()
    local issues = {}
    local ammoInfo = BuildAmmoInfo()

    CheckTalentPoints(issues)
    CheckAmmo(issues, ammoInfo)
    CheckQuiver(issues, ammoInfo)
    CheckRiding(issues)
    CheckEmptyRangedForMelee(issues, ammoInfo)
    CheckWeaponBuff(issues)
    CheckBags(issues)

    table.sort(issues, function(a, b)
        if a.sev ~= b.sev then return a.sev < b.sev end
        return a.penalty > b.penalty
    end)

    return issues
end
