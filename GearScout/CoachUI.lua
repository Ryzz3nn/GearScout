-- GearScout / CoachUI.lua
-- The window every player sees. Gear audit, rotation report, settings.
-- This addon never displays another player's gear. That code lives only in
-- GearScout_Lead, which raid leads install separately.

local ADDON, ns = ...

local UI, T, SEV = ns.UI, ns.T, ns.SEVERITY
local format, ipairs, unpack = string.format, ipairs, unpack

local win, pages, tabBar
local gearPage, upgradesPage, rotationPage, settingsPage
local scoreGrade, scoreValue, scoreBar, scoreSub
local chips = {}
local slotList, issueList, issueEmpty, issueCount
local footerInfo

local CHIP_DEFS = {
    { key = "avgIlvl",         label = "Average item level" },
    { key = "missingEnchants", label = "Missing enchants" },
    { key = "emptySockets",    label = "Empty sockets" },
    { key = "emptySlots",      label = "Empty slots" },
}

-- ---------------------------------------------------------------------------
-- score card
-- ---------------------------------------------------------------------------
local function BuildScoreCard(parent)
    local card = UI.Panel(parent, T.raised)
    card:SetPoint("TOPLEFT", 10, -10)
    card:SetPoint("TOPRIGHT", -10, -10)
    card:SetHeight(96)

    scoreGrade = UI.Font(card, 40, T.good, "OUTLINE")
    scoreGrade:SetPoint("TOPLEFT", 14, -10)
    scoreGrade:SetText("-")

    scoreValue = UI.Font(card, 20, T.text)
    scoreValue:SetPoint("BOTTOMLEFT", scoreGrade, "BOTTOMRIGHT", 10, 4)
    scoreValue:SetText("0")

    local outOf = UI.Font(card, 11, T.dim)
    outOf:SetPoint("BOTTOMLEFT", scoreValue, "BOTTOMRIGHT", 3, 2)
    outOf:SetText("/ 100")

    local caption = UI.Font(card, 10, T.dim)
    caption:SetPoint("TOPLEFT", scoreValue, "TOPLEFT", 0, 14)
    caption:SetText("GEAR SCORE")

    scoreBar = UI.Bar(card, T.good)
    scoreBar:SetPoint("BOTTOMLEFT", 14, 26)
    scoreBar:SetPoint("BOTTOMRIGHT", -14, 26)
    scoreBar:SetHeight(5)

    scoreSub = UI.Font(card, 11, T.dim, nil, "LEFT")
    scoreSub:SetPoint("BOTTOMLEFT", 14, 9)
    scoreSub:SetPoint("BOTTOMRIGHT", -14, 9)
    scoreSub:SetText("Not scanned yet")

    UI.HookTooltip(card, function(_, tip)
        tip:SetText("Gear score", 1, 1, 1)
        tip:AddLine("One number out of 100 for how well put together your gear is.", 0.8, 0.84, 0.9, true)
        tip:AddLine(" ")
        tip:AddLine("It starts at 100 and loses points for empty slots, missing enchants, empty gem holes, wearing the wrong type of armor, and pieces that are far behind the rest of your set.", 0.8, 0.84, 0.9, true)
        tip:AddLine(" ")
        tip:AddLine("It does not measure how rare your items are. It measures how much free power you are leaving on the table.", 0.3, 0.64, 1, true)
    end)

    return card
end

local function BuildChips(parent, anchor)
    local grid = CreateFrame("Frame", nil, parent)
    grid:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
    grid:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -8)
    grid:SetHeight(78)

    for i, def in ipairs(CHIP_DEFS) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local chip = UI.Panel(grid, T.panel)
        chip:SetPoint("TOPLEFT", col * 0.5 * 266 + col * 4, -row * 39)
        chip:SetSize(129, 35)

        chip.value = UI.Font(chip, 15, T.text, nil, "LEFT")
        chip.value:SetPoint("TOPLEFT", 8, -5)
        chip.value:SetText("0")

        chip.label = UI.Font(chip, 9, T.dim, nil, "LEFT")
        chip.label:SetPoint("BOTTOMLEFT", 8, 5)
        chip.label:SetPoint("BOTTOMRIGHT", -6, 5)
        chip.label:SetText(def.label:upper())

        chips[def.key] = chip
    end
    return grid
end

-- ---------------------------------------------------------------------------
-- equipped slot list
-- ---------------------------------------------------------------------------
local function CreateSlotRow(list)
    local row = CreateFrame("Button", nil, list)

    row.hl = UI.Tex(row, "BACKGROUND", T.hover)
    row.hl:SetAllPoints()
    row.hl:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.label = UI.Font(row, 11, T.dim, nil, "LEFT")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetWidth(86)

    row.ilvl = UI.Font(row, 11, T.text, nil, "RIGHT")
    row.ilvl:SetPoint("RIGHT", -42, 0)
    row.ilvl:SetWidth(34)

    row.enchDot = UI.Dot(row, 9)
    row.enchDot:SetPoint("RIGHT", -22, 0)

    row.gemDot = UI.Dot(row, 9)
    row.gemDot:SetPoint("RIGHT", -6, 0)

    row:SetScript("OnEnter", function(self)
        self.hl:Show()
        local rec = self.rec
        if not rec then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if rec.link then
            GameTooltip:SetHyperlink(rec.link)
            GameTooltip:AddLine(" ")
        else
            GameTooltip:SetText(rec.label, 1, 1, 1)
            GameTooltip:AddLine("Nothing equipped here.", 1, 0.37, 0.34, true)
        end
        -- explain the two dots, because nobody guesses what they mean
        if rec.link then
            if not rec.enchantable then
                GameTooltip:AddLine("Enchant: this slot cannot take one.", 0.55, 0.58, 0.65)
            elseif rec.enchanted then
                GameTooltip:AddLine("Enchant: yes, this item is enchanted.", 0.28, 0.82, 0.42)
            elseif (ns.playerLevel or 0) < (ns.ENCHANT_WORTH_IT or 58) then
                -- Missing, but deliberately not counted against you yet. Saying
                -- so here keeps this tooltip agreeing with the summary chip
                -- above it instead of contradicting it.
                GameTooltip:AddLine(format("Enchant: missing, and that is fine for now. Enchants start being worth the gold at level %d.",
                    ns.ENCHANT_WORTH_IT or 58), 0.55, 0.58, 0.65)
            else
                GameTooltip:AddLine("Enchant: missing. Free stats you are not getting.", 1, 0.37, 0.34)
            end
            if (rec.sockets or 0) == 0 then
                GameTooltip:AddLine("Gems: this item has no gem holes.", 0.55, 0.58, 0.65)
            else
                GameTooltip:AddLine(format("Gems: %d of %d holes filled.",
                    rec.gemsFilled or 0, rec.sockets),
                    (rec.emptySockets or 0) == 0 and 0.28 or 1,
                    (rec.emptySockets or 0) == 0 and 0.82 or 0.74,
                    (rec.emptySockets or 0) == 0 and 0.42 or 0.18)
            end
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip:Hide()
    end)
    return row
end

local function UpdateSlotRow(row, rec)
    row.rec = rec
    row.label:SetText(rec.label)

    if rec.empty then
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        row.icon:SetDesaturated(true)
        row.ilvl:SetText(rec.expectedEmpty and "-" or "none")
        row.ilvl:SetTextColor(unpack(rec.expectedEmpty and T.dim or T.bad))
        row.enchDot:SetVertexColor(0.25, 0.27, 0.31, 1)
        row.gemDot:SetVertexColor(0.25, 0.27, 0.31, 1)
        return
    end

    row.icon:SetTexture(rec.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.icon:SetDesaturated(false)
    row.ilvl:SetText(rec.ilvl or 0)
    row.ilvl:SetTextColor(unpack(T.text))

    if not rec.enchantable then
        row.enchDot:SetVertexColor(0.25, 0.27, 0.31, 1)
    elseif rec.enchanted then
        row.enchDot:SetVertexColor(unpack(T.good))
    else
        row.enchDot:SetVertexColor(unpack(T.bad))
    end

    if (rec.sockets or 0) == 0 then
        row.gemDot:SetVertexColor(0.25, 0.27, 0.31, 1)
    elseif (rec.emptySockets or 0) == 0 then
        row.gemDot:SetVertexColor(unpack(T.good))
    else
        row.gemDot:SetVertexColor(unpack(T.warn))
    end
end

-- ---------------------------------------------------------------------------
-- issue list
-- ---------------------------------------------------------------------------
-- Paperdoll art for a slot with nothing worn in it. Standard client asset
-- names; if a client build ever renames one the texture just fails to render,
-- it does not error, so this degrades to no icon rather than breaking the row.
local SLOT_ART = {
    [1]  = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head",
    [2]  = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Neck",
    [3]  = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shoulder",
    [15] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Back",
    [5]  = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest",
    [9]  = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Wrist",
    [10] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Hands",
    [6]  = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Waist",
    [7]  = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Legs",
    [8]  = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Feet",
    [11] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger",
    [12] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger",
    [13] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket",
    [14] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket",
    [16] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand",
    [17] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-SecondaryHand",
    [18] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Ranged",
}
ns.SLOT_ART = SLOT_ART

local function CreateIssueRow(list)
    local row = CreateFrame("Button", nil, list)

    row.hl = UI.Tex(row, "BACKGROUND", { 1, 1, 1, 0.03 })
    row.hl:SetPoint("TOPLEFT", 0, -1)
    row.hl:SetPoint("BOTTOMRIGHT", 0, 3)
    row.hl:Hide()

    row.stripe = UI.Tex(row, "ARTWORK", T.bad)
    row.stripe:SetPoint("TOPLEFT", 0, -2)
    row.stripe:SetPoint("BOTTOMLEFT", 0, 4)
    row.stripe:SetWidth(2)

    -- Created once here, only ever re-textured in UpdateIssueRow. This list is
    -- pooled and scrolled, so a texture created per update would leak one per
    -- scroll event.
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("TOPLEFT", 6, -5)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Text starts 24px in (18px icon plus the same 6px gap CreateSlotRow uses)
    -- instead of the old 12px, whether or not this particular row ends up
    -- showing an icon, so rows never jump around as the list scrolls.
    row.title = UI.Font(row, 12, T.text, nil, "LEFT")
    row.title:SetPoint("TOPLEFT", 30, -6)
    row.title:SetPoint("RIGHT", -10, 0)

    -- what is actually true, in numbers. Merged rows keep this short, so it
    -- only needs room for about one line.
    row.detail = UI.Font(row, 11, T.dim, nil, "LEFT")
    row.detail:SetPoint("TOPLEFT", 30, -19)
    row.detail:SetPoint("RIGHT", -10, 0)
    row.detail:SetHeight(15)
    row.detail:SetJustifyV("TOP")

    -- what to do about it. This is the line most likely to wrap onto a
    -- second line, so it gets most of the row's remaining height.
    row.fix = UI.Font(row, 11, T.accent, nil, "LEFT")
    row.fix:SetPoint("TOPLEFT", 30, -35)
    row.fix:SetPoint("RIGHT", -10, 0)
    row.fix:SetHeight(33)
    row.fix:SetJustifyV("TOP")

    -- The row already prints the title, the facts and the fix, so the tooltip
    -- only earns its place when there is an actual item to show.
    row:SetScript("OnEnter", function(self)
        self.hl:Show()
        local it = self.issue
        if not it or not it.link then return end
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

local function UpdateIssueRow(row, issue)
    row.issue = issue
    local c = ns.SEV_COLOR[issue.sev] or T.dim
    row.stripe:SetColorTexture(c[1], c[2], c[3], 1)
    row.title:SetText(issue.title)
    row.detail:SetText(issue.detail or "")
    row.fix:SetText(issue.fix or "")

    -- A specific item wins first, since that is the more useful picture. An
    -- item not yet cached by the client just shows nothing; SCAN_UPDATED
    -- redraws this list once the scan itself catches the item, and
    -- ITEM_CACHE_UPDATED is not subscribed here because a stale icon on an
    -- issue row is harmless, unlike a missing one.
    if issue.icon then
        row.icon:SetTexture(issue.icon)
        row.icon:Show()
    elseif issue.slotID and SLOT_ART[issue.slotID] then
        row.icon:SetTexture(SLOT_ART[issue.slotID])
        row.icon:Show()
    else
        row.icon:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- gear page
-- ---------------------------------------------------------------------------
local function BuildGearPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()

    local left = UI.Panel(page, T.panel)
    left:SetPoint("TOPLEFT", 12, -8)
    left:SetPoint("BOTTOMLEFT", 12, 8)
    left:SetWidth(286)

    local card = BuildScoreCard(left)
    local grid = BuildChips(left, card)

    local slotHeader = UI.Font(left, 10, T.dim, nil, "LEFT")
    slotHeader:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", 2, -8)
    slotHeader:SetText("EQUIPPED")

    local legend = UI.Font(left, 9, T.dim, nil, "RIGHT")
    legend:SetPoint("TOPRIGHT", grid, "BOTTOMRIGHT", -2, -8)
    legend:SetText("LEVEL  ENCH  GEM")

    slotList = UI.List(left, 22, CreateSlotRow, UpdateSlotRow)
    slotList:SetPoint("TOPLEFT", slotHeader, "BOTTOMLEFT", -2, -4)
    slotList:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -6, 8)

    local right = UI.Panel(page, T.panel)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT", -12, 8)

    local rh = UI.Font(right, 10, T.dim, nil, "LEFT")
    rh:SetPoint("TOPLEFT", 12, -10)
    rh:SetText("WHAT TO FIX, HIGHEST IMPACT FIRST")

    issueCount = UI.Font(right, 10, T.dim, nil, "RIGHT")
    issueCount:SetPoint("TOPRIGHT", -12, -10)

    local sep = UI.Divider(right)
    sep:SetPoint("TOPLEFT", 10, -26)
    sep:SetPoint("TOPRIGHT", -10, -26)

    -- 72 replaces the old fixed 84. The saved padding goes to the fix line
    -- below, which is the one that was getting cut off mid sentence.
    issueList = UI.List(right, 72, CreateIssueRow, UpdateIssueRow)
    issueList:SetPoint("TOPLEFT", 8, -32)
    issueList:SetPoint("BOTTOMRIGHT", -6, 8)

    issueEmpty = UI.Font(right, 13, T.good)
    issueEmpty:SetPoint("CENTER", 0, 10)
    issueEmpty:SetText("Nothing to fix. Gear is clean.")
    issueEmpty:Hide()

    return page
end

-- ---------------------------------------------------------------------------
-- rotation page
-- Rotation.lua fills this in. Until it loads the tab explains itself rather
-- than showing an empty box.
-- ---------------------------------------------------------------------------
-- Upgrades.lua owns its own page, the same way Rotation.lua does, so this is
-- only a holder plus an honest message if that file failed to load.
local function BuildUpgradesPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()

    if ns.BuildUpgradesPage then
        ns.BuildUpgradesPage(page)
        return page
    end

    local msg = UI.Font(page, 12, T.dim, nil, "CENTER")
    msg:SetPoint("CENTER")
    msg:SetWidth(420)
    msg:SetText("The upgrade finder is not loaded in this build.")
    return page
end

local function BuildRotationPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()

    if ns.BuildRotationPage then
        ns.BuildRotationPage(page)
        return page
    end

    local msg = UI.Font(page, 12, T.dim, nil, "CENTER")
    msg:SetPoint("CENTER")
    msg:SetWidth(420)
    msg:SetText("Rotation tracking is not loaded in this build.")
    return page
end

-- ---------------------------------------------------------------------------
-- settings page
-- ---------------------------------------------------------------------------
local function BuildSettingsPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()

    local box = UI.Panel(page, T.panel)
    box:SetPoint("TOPLEFT", 12, -8)
    box:SetPoint("BOTTOMRIGHT", -12, 8)

    local y = -14

    local function Header(text)
        local h = UI.Font(box, 10, T.dim, nil, "LEFT")
        h:SetPoint("TOPLEFT", 14, y)
        h:SetText(text)
        y = y - 22
        return h
    end

    local function Note(text)
        local n = UI.Font(box, 11, T.dim, nil, "LEFT")
        n:SetPoint("TOPLEFT", 14, y)
        n:SetPoint("RIGHT", box, "RIGHT", -14, 0)
        n:SetText(text)
        n:SetHeight(30)
        n:SetJustifyV("TOP")
        y = y - 34
        return n
    end

    Header("PRIVACY")
    Note("GearScout only ever sends your own gear, and only when someone asks for it. You never receive anyone else's gear: the code that displays other players lives in a separate addon that raid leads install.")

    local sel = UI.Select(box, 210, {
        { value = "leaders", text = "Group leader and assistants" },
        { value = "guild",   text = "Anyone in my guild" },
        { value = "anyone",  text = "Anyone who asks" },
        { value = "nobody",  text = "Nobody, decline every request" },
    }, function() return ns.db.respondTo end,
       function(v) ns.db.respondTo = v end)
    sel:SetPoint("TOPLEFT", 14, y)
    local selLabel = UI.Font(box, 11, T.text, nil, "LEFT")
    selLabel:SetPoint("LEFT", sel, "RIGHT", 10, 0)
    selLabel:SetText("Answer gear requests from")
    y = y - 34

    local cbRot = UI.CheckBox(box, "Include a rotation summary in my reply",
        function() return ns.db.shareRotation end,
        function(v) ns.db.shareRotation = v end)
    cbRot:SetPoint("TOPLEFT", 14, y)
    y = y - 26

    y = y - 10
    Header("BEHAVIOUR")

    local cbAuto = UI.CheckBox(box, "Scan automatically when gear changes",
        function() return ns.db.autoScan end,
        function(v) ns.db.autoScan = v end)
    cbAuto:SetPoint("TOPLEFT", 14, y)
    y = y - 26

    local cbTip = UI.CheckBox(box, "Add GearScout lines to item tooltips",
        function() return ns.db.tooltip end,
        function(v) ns.db.tooltip = v end)
    cbTip:SetPoint("TOPLEFT", 14, y)
    y = y - 26

    local cbMap = UI.CheckBox(box, "Show the minimap button",
        function() return ns.db.showMinimap end,
        function(v)
            ns.db.showMinimap = v
            if ns.minimapButton then ns.minimapButton:SetShown(v) end
        end)
    cbMap:SetPoint("TOPLEFT", 14, y)
    y = y - 34

    local slackSel = UI.Select(box, 210, {
        { value = 6,  text = "Strict, 6 item levels" },
        { value = 12, text = "Normal, 12 item levels" },
        { value = 20, text = "Relaxed, 20 item levels" },
    }, function() return ns.db.ilvlSlack end,
       function(v) ns.db.ilvlSlack = v ns.RequestRescan() end)
    slackSel:SetPoint("TOPLEFT", 14, y)
    local slackLabel = UI.Font(box, 11, T.text, nil, "LEFT")
    slackLabel:SetPoint("LEFT", slackSel, "RIGHT", 10, 0)
    slackLabel:SetText("How far under your median counts as a weak link")
    y = y - 40

    -- Ticking "always share with this person" on the request popup writes a
    -- name into ns.db.trustedRequesters, and until now there was no way to
    -- see that list or take a name back out of it. A permission you can grant
    -- but never revoke is not really a permission.
    Header("PEOPLE YOU ALWAYS SHARE WITH")

    local trustedText = UI.Font(box, 11, T.dim, nil, "LEFT")
    trustedText:SetPoint("TOPLEFT", 14, y)
    trustedText:SetPoint("RIGHT", box, "RIGHT", -150, 0)
    trustedText:SetHeight(30)
    trustedText:SetJustifyV("TOP")

    local function TrustedNames()
        local names = {}
        local t = ns.db and ns.db.trustedRequesters
        if type(t) == "table" then
            for name in pairs(t) do names[#names + 1] = name end
        end
        table.sort(names)
        return names
    end

    local forgetBtn

    local function RefreshTrusted()
        local names = TrustedNames()
        if #names == 0 then
            trustedText:SetText("Nobody yet. When someone asks for your gear you can tick the box on that prompt to stop being asked again, and their name will appear here.")
        else
            trustedText:SetText(format("%d name%s: %s. These players get your gear without being asked each time.",
                #names, #names == 1 and "" or "s", table.concat(names, ", ")))
        end
        if forgetBtn then forgetBtn:SetShown(#names > 0) end
    end

    forgetBtn = UI.Button(box, "Forget them all", 120, 22, function()
        if ns.db then ns.db.trustedRequesters = {} end
        RefreshTrusted()
        ns.Print("Cleared. Everyone will be asked again from now on.")
    end)
    forgetBtn:SetPoint("TOPRIGHT", box, "TOPRIGHT", -14, y)
    forgetBtn.tooltipText = "Removes every saved name, so the next request from anyone prompts you again."

    RefreshTrusted()
    box:SetScript("OnShow", RefreshTrusted)

    return page
end

-- ---------------------------------------------------------------------------
-- refresh
-- ---------------------------------------------------------------------------
local function Refresh()
    if not win or not win:IsShown() then return end
    local report = ns.lastReport
    local scan = ns.lastScan
    if not report or not scan then return end

    scoreGrade:SetText(report.grade)
    scoreGrade:SetTextColor(unpack(report.gradeColor))
    scoreValue:SetText(report.score)
    scoreBar:SetColor(report.gradeColor)
    scoreBar:SetValue(report.score / 100, true)

    local n = #report.issues
    scoreSub:SetText(n == 0 and "No problems found"
        or format("%d thing%s worth fixing", n, n == 1 and "" or "s"))

    chips.avgIlvl.value:SetText(format("%.1f", report.avgIlvl or 0))
    -- The number is always the true count. Below the level where enchanting is
    -- worth the gold it is shown in a neutral colour, because it is a fact
    -- about your gear rather than a problem you should act on yet.
    local enchantThreshold = ns.ENCHANT_WORTH_IT or 58
    local enchantsMatter = (report.level or 0) >= enchantThreshold
    chips.missingEnchants.value:SetText(report.counts.missingEnchants)
    if report.counts.missingEnchants == 0 then
        chips.missingEnchants.value:SetTextColor(unpack(T.good))
    elseif enchantsMatter then
        chips.missingEnchants.value:SetTextColor(unpack(T.bad))
    else
        chips.missingEnchants.value:SetTextColor(unpack(T.dim))
    end
    chips.missingEnchants.label:SetText(enchantsMatter and "MISSING ENCHANTS"
        or ("MISSING ENCHANTS, OK UNTIL " .. enchantThreshold))
    chips.emptySockets.value:SetText(report.counts.emptySockets)
    chips.emptySockets.value:SetTextColor(unpack(report.counts.emptySockets > 0 and T.warn or T.good))
    chips.emptySlots.value:SetText(report.counts.emptySlots)
    chips.emptySlots.value:SetTextColor(unpack(report.counts.emptySlots > 0 and T.bad or T.good))

    slotList:SetData(scan.slots)
    issueList:SetData(report.issues)
    issueEmpty:SetShown(n == 0)
    issueCount:SetText(n .. (n == 1 and " ISSUE" or " ISSUES"))

    if footerInfo then
        footerInfo:SetText(format("Level %d %s  |  GearScout %s",
            report.level or 0, (report.class or ""):lower(), ns.VERSION))
    end
end

ns:Sub("SCAN_UPDATED", function() ns.Analyze() Refresh() end)
ns:Sub("ROTATION_UPDATED", Refresh)

-- ---------------------------------------------------------------------------
-- window assembly
-- ---------------------------------------------------------------------------
local function Build()
    if win then return win end

    win = UI.Window("GearScoutFrame", "GearScout", 790, 650)
    win.subtitle:SetText(UnitName("player"))

    -- TabBar selects its first tab while it is being constructed, which happens
    -- before the pages below exist. The guard keeps that first call harmless.
    -- Upgrades sits next to Gear on purpose: the gear tab tells you what is
    -- wrong, and the natural next question is what to do about it.
    tabBar = UI.TabBar(win.content, { "Gear", "Upgrades", "Rotation", "Settings" }, function(i)
        if not pages then return end
        for j, p in ipairs(pages) do p:SetShown(i == j) end
    end)
    tabBar:SetPoint("TOPLEFT", 8, 0)

    local tabLine = UI.Divider(win.content)
    tabLine:SetPoint("TOPLEFT", 0, -28)
    tabLine:SetPoint("TOPRIGHT", 0, -28)

    local body = CreateFrame("Frame", nil, win.content)
    body:EnableMouse(true)
    body:SetPoint("TOPLEFT", 0, -29)
    body:SetPoint("BOTTOMRIGHT", 0, 34)

    gearPage     = BuildGearPage(body)
    upgradesPage = BuildUpgradesPage(body)
    rotationPage = BuildRotationPage(body)
    settingsPage = BuildSettingsPage(body)
    pages = { gearPage, upgradesPage, rotationPage, settingsPage }
    tabBar:Select(1)

    -- footer
    local footer = CreateFrame("Frame", nil, win.content)
    footer:EnableMouse(true)
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(34)
    local fLine = UI.Divider(footer)
    fLine:SetPoint("TOPLEFT")
    fLine:SetPoint("TOPRIGHT")

    local rescan = UI.Button(footer, "Rescan", 88, 22, function()
        ns.Evaluate()
        Refresh()
    end)
    rescan:SetPoint("LEFT", 12, 0)
    rescan.tooltipText = "Read your equipment again right now."

    footerInfo = UI.Font(footer, 11, T.dim, nil, "RIGHT")
    footerInfo:SetPoint("RIGHT", -14, 0)

    win:RestorePosition()
    return win
end

function ns.ToggleMain()
    Build()
    if win:IsShown() then
        win:Hide()
    else
        win:Show()
        if not ns.lastReport then ns.Evaluate() end
        Refresh()
    end
end

-- ---------------------------------------------------------------------------
-- entry points
-- ---------------------------------------------------------------------------
ns:Sub("DB_READY", function()
    if ns.db.showMinimap then
        ns.minimapButton = UI.MinimapButton(
            "GearScoutMinimapButton",
            "Interface\\Icons\\INV_Misc_Gear_01",
            function() ns.ToggleMain() end,
            function(_, tip)
                tip:SetText("GearScout", 1, 1, 1)
                tip:AddLine("Click to open the gear and rotation coach.", 0.8, 0.84, 0.9)
                tip:AddLine("Drag to move this button.", 0.55, 0.58, 0.65)
            end)
    end
end)

SLASH_GEARSCOUT1 = "/gearscout"
SLASH_GEARSCOUT2 = "/gscout"
SlashCmdList.GEARSCOUT = function(msg)
    -- Kept before lowercasing, because an item link is case sensitive and
    -- lowercasing one turns it into unusable text.
    local raw = msg or ""
    msg = raw:lower():match("^%s*(.-)%s*$")
    if msg == "scan" then
        local report = ns.Evaluate()
        ns.Print(format("Score %d (%s), %d issue%s.",
            report.score, report.grade, #report.issues, #report.issues == 1 and "" or "s"))
        Refresh()
    elseif msg == "skin obsidian" or msg == "skin slate" then
        ns.db.skin = msg:match("skin (%a+)")
        ns.Print("Skin set to " .. ns.db.skin .. ". Type /reload to see it.")
    elseif msg == "skin" then
        ns.Print("Current skin: " .. tostring(ns.activeSkin)
            .. ". Use /gearscout skin obsidian or /gearscout skin slate.")
    -- Deliberately manual for now. The stat weight data covers 16 of 27 specs
    -- and its own audit put it at roughly 70 percent trustworthy, so it is
    -- reachable and testable but is not yet allowed to quietly change the
    -- advice the gear tab gives.
    elseif msg == "where" then
        -- Manual for now. It walks the whole dungeon loot table, which is
        -- cheap but pointless to run on every gear change when nobody asked.
        if not ns.FindSlotUpgrades or not ns.lastReport then
            ns.Print("Nothing scanned yet. Try /gearscout scan first.")
            return
        end
        local weakest, weakestIlvl
        for _, rec in ipairs(ns.lastScan and ns.lastScan.slots or {}) do
            if not rec.empty and rec.ilvl and (not weakestIlvl or rec.ilvl < weakestIlvl) then
                weakest, weakestIlvl = rec, rec.ilvl
            end
        end
        if not weakest then ns.Print("No equipped items to compare.") return end
        local list = ns.FindSlotUpgrades(weakest.slotID, weakestIlvl, 5)
        if #list == 0 then
            ns.Print(format("Nothing known that beats your %s at item level %d in dungeons near your level. The loot table only covers dungeons and raids, so quest rewards will not appear here.",
                (weakest.label or "slot"):lower(), weakestIlvl or 0))
        else
            ns.Print(format("Upgrades for your %s, currently item level %d:",
                (weakest.label or "slot"):lower(), weakestIlvl or 0))
            for _, u in ipairs(list) do
                ns.Print(format("  %s (item level %d) from %s in %s",
                    u.name or ("item " .. u.itemID), u.ilvl,
                    (u.boss and u.boss ~= "" and u.boss) or "trash", u.instance))
            end
        end
        -- Items the client had not cached were requested rather than dropped,
        -- so saying so is more honest than presenting a partial list as final.
        if (list.pending or 0) > 0 then
            ns.Print(format("%d more candidate%s still loading from the server. Run this again in a moment for the complete answer.",
                list.pending, list.pending == 1 and " is" or "s are"))
        end
    elseif msg:match("^caps") then
        if not ns.GetCapStatus then ns.Print("Item evaluation is not loaded.") return end
        local caps, confidence = ns.GetCapStatus()
        if not caps then
            ns.Print(tostring(confidence or "No stat weight data for your class and spec yet."))
        else
            ns.Print("Stat caps, data confidence " .. tostring(confidence) .. ":")
            for _, c in ipairs(caps) do
                ns.Print(format("  %s: %s", tostring(c.name),
                    c.met and "met" or ("NOT met, " .. tostring(c.explanation or ""))))
            end
        end
    elseif msg:match("^score ") then
        if not ns.CompareToEquipped then ns.Print("Item evaluation is not loaded.") return end
        -- The raw message is used, not the lowercased one, because an item
        -- link is case sensitive and lowercasing it destroys the link.
        local link = (raw or ""):match("|c%x+|Hitem:.-|h.-|h|r")
        if not link then
            ns.Print("Shift click an item into chat after the command, like /gearscout score [item].")
        else
            local delta, why = ns.CompareToEquipped(link)
            ns.Print(why or (delta and format("Score difference against what you are wearing: %+.1f", delta))
                or "No comparison available.")
        end
    elseif msg == "data research" or msg == "data builtin" then
        ns.db.dataSource = msg:match("data (%a+)")
        if ns.BuildProfile then ns.BuildProfile() end
        ns.Print("Rotation data source set to " .. ns.db.dataSource
            .. ". Run /gearscout rot to see what it resolved.")
    elseif msg == "data" then
        ns.Print("Rotation data source: " .. tostring(ns.db.dataSource or "research")
            .. ", currently using " .. tostring(ns.GetProfileSource and ns.GetProfileSource())
            .. ". Switch with /gearscout data research or /gearscout data builtin.")
    elseif msg == "rot" or msg == "rotation" then
        -- A diagnostic that dies silently is worse than useless, so it always
        -- prints something even when the thing it is diagnosing is broken.
        if ns.PrintRotationDebug then
            local ok, err = pcall(ns.PrintRotationDebug)
            if not ok then ns.Print("Diagnostic failed: " .. tostring(err)) end
        else
            ns.Print("The rotation module did not load at all.")
        end
    else
        ns.ToggleMain()
    end
end
