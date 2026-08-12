-- GearScout / Tooltip.lua
-- Puts what GearScout knows onto the item tooltip, which is where a player is
-- already looking when the question "is this better" occurs to them.
--
-- Two lines at most, and only when there is something worth saying:
--   where the item drops, an O(1) lookup in the shipped loot table
--   how it scores against what is worn, when the spec has trusted weights
--
-- The hook is deliberately defensive. A tooltip handler runs constantly, and
-- one that throws produces an error every time the mouse moves, which is far
-- worse than the feature simply not appearing. Everything is wrapped, and any
-- failure disables the hook for the rest of the session rather than repeating.

local ADDON, ns = ...

local pcall, type, format = pcall, type, string.format

local disabled = false
local failures = 0

-- Cheap per item memo. Tooltips redraw constantly and the answer for an item
-- cannot change without gear changing, which clears this.
local lineCache = {}

local function BuildLines(itemLink)
    local itemID = ns.ParseLink and ns.ParseLink(itemLink)
    if not itemID then return nil end

    local cached = lineCache[itemID]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    local lines

    local where = ns.DescribeItemSource and ns.DescribeItemSource(itemID)
    if where then
        lines = lines or {}
        lines[#lines + 1] = { text = where, r = 0.55, g = 0.58, b = 0.65 }
    end

    -- Scoring is only offered when the spec actually has weights. A spec with
    -- no data says nothing rather than implying an item is worthless.
    if ns.CompareToEquipped then
        local ok, delta, why = pcall(ns.CompareToEquipped, itemLink)
        if ok and type(delta) == "number" then
            lines = lines or {}
            if delta > 0.5 then
                lines[#lines + 1] = {
                    text = format("GearScout: an upgrade, %+.0f over what you are wearing.", delta),
                    r = 0.28, g = 0.82, b = 0.42,
                }
            elseif delta < -0.5 then
                lines[#lines + 1] = {
                    text = format("GearScout: worse than what you are wearing, %+.0f.", delta),
                    r = 1.00, g = 0.37, b = 0.34,
                }
            else
                lines[#lines + 1] = {
                    text = "GearScout: about the same as what you are wearing.",
                    r = 0.55, g = 0.58, b = 0.65,
                }
            end
        elseif ok and why then
            -- Only surface a reason when it is genuinely informative, not for
            -- every unscoreable trinket in the game.
            if type(why) == "string" and why:find("no stat weight", 1, true) then
                lines = lines or {}
                lines[#lines + 1] = { text = "GearScout: no stat weights for your spec yet.",
                                      r = 0.55, g = 0.58, b = 0.65 }
            end
        end
    end

    lineCache[itemID] = lines or false
    return lines
end

local function Decorate(tooltip)
    if disabled then return end
    if ns.db and ns.db.tooltip == false then return end
    if not tooltip or not tooltip.GetItem then return end

    local ok, err = pcall(function()
        local _, link = tooltip:GetItem()
        if not link then return end
        local lines = BuildLines(link)
        if not lines then return end
        for _, l in ipairs(lines) do
            tooltip:AddLine(l.text, l.r, l.g, l.b, true)
        end
        tooltip:Show()
    end)

    if not ok then
        failures = failures + 1
        -- Three strikes and it stops. A tooltip error repeating on every mouse
        -- move would drown the player in red text.
        if failures >= 3 then
            disabled = true
            ns.Print("Tooltip additions turned off after repeated errors: " .. tostring(err))
        end
    end
end

-- ---------------------------------------------------------------------------
-- hook, whichever way this client supports
-- ---------------------------------------------------------------------------
ns:Sub("DB_READY", function()
    if _G.TooltipDataProcessor and _G.TooltipDataProcessor.AddTooltipPostCall
       and _G.Enum and _G.Enum.TooltipDataType and _G.Enum.TooltipDataType.Item then
        -- Current engine path.
        _G.TooltipDataProcessor.AddTooltipPostCall(_G.Enum.TooltipDataType.Item, Decorate)
        ns.tooltipHook = "TooltipDataProcessor"
    elseif _G.GameTooltip and _G.GameTooltip.HookScript then
        -- Older path, still present on some builds.
        local okHook = pcall(function()
            GameTooltip:HookScript("OnTooltipSetItem", Decorate)
            if _G.ItemRefTooltip then
                ItemRefTooltip:HookScript("OnTooltipSetItem", Decorate)
            end
        end)
        ns.tooltipHook = okHook and "OnTooltipSetItem" or "none"
    else
        ns.tooltipHook = "none"
    end
end)

-- What is worn changed, so every cached verdict is stale.
ns:Sub("SCAN_UPDATED", function() wipe(lineCache) end)
