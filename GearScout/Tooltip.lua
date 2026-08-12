-- GearScout / Tooltip.lua
-- Puts what GearScout knows onto the item tooltip, which is where a player is
-- already looking when the question "is this better" occurs to them.
--
-- What gets added, and only when there is something worth saying:
--   where the item drops, an O(1) lookup in the shipped loot table
--   a verdict line from ns.ExplainItem: upgrade, downgrade, cannot equip, or
--     no data for this spec yet
--   the one or two stats on the item worth saying out loud: a stat that
--     does nothing for this class at all, or a lighter armor type than the
--     class could be wearing from the level that matters
--
-- A tooltip is not a report. When a tier 1 blocking problem exists, that
-- line is the whole story and nothing else from ns.ExplainItem is shown
-- under it, so the message stays unambiguous instead of getting diluted by
-- stat detail that does not change the answer.
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

-- Colours match ns.T.good, ns.T.warn, ns.T.bad and ns.T.dim, written out
-- directly rather than read from ns.T so a tooltip line never shifts colour
-- when the player changes skin.
local COLOR_GOOD = { r = 0.278, g = 0.816, b = 0.416 }
local COLOR_WARN = { r = 1.000, g = 0.741, b = 0.180 }
local COLOR_BAD  = { r = 1.000, g = 0.373, b = 0.341 }
local COLOR_DIM  = { r = 0.541, g = 0.580, b = 0.651 }

local VERDICT_COLOR = {
    blocked   = COLOR_BAD,
    downgrade = COLOR_BAD,
    upgrade   = COLOR_GOOD,
    ["empty slot"] = COLOR_GOOD,
}

local function AddLine(lines, text, color)
    lines[#lines + 1] = { text = text, r = color.r, g = color.g, b = color.b }
end

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
        AddLine(lines, where, COLOR_DIM)
    end

    -- Scoring is only offered when GearScout can actually say something
    -- about the item. ExplainItem itself decides that; a spec with no
    -- researched weights still gets one honest line saying so, never a
    -- guessed number.
    if ns.ExplainItem then
        local ok, explain = pcall(ns.ExplainItem, itemLink)
        if ok and explain and explain.verdictText then
            lines = lines or {}
            AddLine(lines, "GearScout: " .. explain.verdictText, VERDICT_COLOR[explain.verdict] or COLOR_DIM)

            if explain.verdict == "blocked" then
                -- The blocking problem is the entire answer. Nothing below
                -- it would change that, so nothing below it is shown.
            else
                -- The single most valuable line this feature produces: which
                -- stats on this item do nothing, or next to nothing, for
                -- this class, said in plain words instead of buried in a
                -- total. Dead stats are sorted first by BuildStatBreakdown,
                -- so the first one or two rows are the ones most worth
                -- saying, and at most two are shown to keep this tight.
                local shown = 0
                if explain.stats then
                    for _, s in ipairs(explain.stats) do
                        if shown >= 2 then break end
                        if s.note and (s.dead or s.nearZero) then
                            AddLine(lines, s.note, COLOR_WARN)
                            shown = shown + 1
                        end
                    end
                end

                if explain.armorPenalty and explain.armorPenalty.note then
                    AddLine(lines, explain.armorPenalty.note, COLOR_DIM)
                end
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
            -- The error text itself is left as Lua produced it.
            ns.Print(string.format(ns.L["Tooltip additions turned off after repeated errors: %s"],
                tostring(err)))
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
