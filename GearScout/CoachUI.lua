-- GearScout / CoachUI.lua
-- The window every player sees. Gear audit, rotation report, settings.
-- This addon never displays another player's gear. That code lives only in
-- GearScout_Lead, which raid leads install separately.

local ADDON, ns = ...

local UI, T, SEV = ns.UI, ns.T, ns.SEVERITY
local format, ipairs, unpack = string.format, ipairs, unpack

local win, pages, tabBar
local gearPage, upgradesPage, enchantsPage, rotationPage, settingsPage
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

-- Row geometry, in one place, because MeasureIssueRow below has to reproduce
-- the exact same insets and gaps. Text is laid out in two columns, not one:
-- the title clears the icon, and the two body lines start from the icon's own
-- left edge. The icon only ever occupies the first line, so indenting the
-- sentences underneath it threw away 22px of wrapping width on every one of
-- them, which is what made the list so tall.
local ROW_PAD_TOP    = 5    -- row top to the first line of text
local ROW_PAD_BOTTOM = 5    -- last line of text to the separator hairline
local ROW_GAP_DETAIL = 1    -- title to detail: they read as one block
local ROW_GAP_FIX    = 3    -- detail to fix: the action is set slightly apart
local ROW_TEXT_LEFT  = 8    -- body text and the icon share this left edge
local ROW_TEXT_RIGHT = 8
local ROW_ICON       = 16
local ROW_TITLE_LEFT = ROW_TEXT_LEFT + ROW_ICON + 6   -- title clears the icon
local ROW_BODY_DX    = ROW_TEXT_LEFT - ROW_TITLE_LEFT -- body hangs left of it
-- Only stops a single line issue from looking like an accident. Nothing is
-- ever clipped to it, see MeasureIssueRow.
local ROW_MIN_HEIGHT = 44

local function CreateIssueRow(list)
    local row = CreateFrame("Button", nil, list)

    -- Same hover fill the slot rows use, so the two lists feel like one UI.
    -- Stops 1px short of the bottom to leave the separator visible.
    row.hl = UI.Tex(row, "BACKGROUND", T.hover)
    row.hl:SetPoint("TOPLEFT", 0, 0)
    row.hl:SetPoint("BOTTOMRIGHT", 0, 1)
    row.hl:Hide()

    row.stripe = UI.Tex(row, "ARTWORK", T.bad)
    row.stripe:SetPoint("TOPLEFT", 0, -2)
    row.stripe:SetPoint("BOTTOMLEFT", 0, 3)
    row.stripe:SetWidth(3)

    -- One hairline per row instead of a band of empty space. Rows can then sit
    -- close together without running into each other, which is what lets the
    -- padding above be this tight and still read cleanly.
    row.sep = UI.Tex(row, "ARTWORK", T.line)
    row.sep:SetPoint("BOTTOMLEFT", ROW_TEXT_LEFT, 0)
    row.sep:SetPoint("BOTTOMRIGHT", -ROW_TEXT_RIGHT, 0)
    row.sep:SetHeight(1)

    -- Created once here, only ever re-textured in UpdateIssueRow. This list is
    -- pooled and scrolled, so a texture created per update would leak one per
    -- scroll event.
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_ICON, ROW_ICON)
    row.icon:SetPoint("TOPLEFT", ROW_TEXT_LEFT, -ROW_PAD_TOP)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- The title always starts past the icon column whether or not this
    -- particular row ends up showing an icon, so rows never jump around as the
    -- list scrolls.
    --
    -- TOPLEFT plus TOPRIGHT, never a bare RIGHT: two anchors on the top edge
    -- fix the width and leave the height intrinsic, which is what lets a font
    -- string grow to however many lines its text wraps to.
    row.title = UI.Font(row, 12, T.text, nil, "LEFT")
    row.title:SetPoint("TOPLEFT", ROW_TITLE_LEFT, -ROW_PAD_TOP)
    row.title:SetPoint("TOPRIGHT", -ROW_TEXT_RIGHT, -ROW_PAD_TOP)
    row.title:SetJustifyV("TOP")

    -- what is actually true, in numbers. Dim on purpose: it is the background
    -- to the problem, not the thing to act on.
    --
    -- Each line hangs off the bottom of the one above it and carries no fixed
    -- height. The previous version pinned these to fixed offsets with fixed
    -- heights, which silently truncated any detail longer than one line: the
    -- bag upgrade summary was being cut off mid sentence.
    row.detail = UI.Font(row, 11, T.dim, nil, "LEFT")
    row.detail:SetPoint("TOPLEFT",  row.title, "BOTTOMLEFT",  ROW_BODY_DX, -ROW_GAP_DETAIL)
    row.detail:SetPoint("TOPRIGHT", row.title, "BOTTOMRIGHT", 0,           -ROW_GAP_DETAIL)
    row.detail:SetJustifyV("TOP")

    -- what to do about it. Accent coloured and set a little further down, so
    -- the eye lands on the action rather than on the explanation above it.
    row.fix = UI.Font(row, 11, T.accent, nil, "LEFT")
    row.fix:SetPoint("TOPLEFT",  row.detail, "BOTTOMLEFT",  0, -ROW_GAP_FIX)
    row.fix:SetPoint("TOPRIGHT", row.detail, "BOTTOMRIGHT", 0, -ROW_GAP_FIX)
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

-- Two wrapping widths, because the row draws in two columns: the title is
-- inset past the icon, the detail and the fix run the full width of the row.
-- Both are derived from the same constants CreateIssueRow anchors against,
-- because the two have to agree or rows will be sized for a width they are not
-- actually drawn at.
local ISSUE_TITLE_INSET = ROW_TITLE_LEFT + ROW_TEXT_RIGHT
local ISSUE_BODY_INSET  = ROW_TEXT_LEFT + ROW_TEXT_RIGHT

local function MeasureIssueRow(issue, width)
    width = width or 0
    local tw = math.max(1, width - ISSUE_TITLE_INSET)
    local bw = math.max(1, width - ISSUE_BODY_INSET)
    local h = ROW_PAD_TOP + UI.MeasureText(12, tw, issue.title or "")
    h = h + ROW_GAP_DETAIL + UI.MeasureText(11, bw, issue.detail or "")
    if issue.fix and issue.fix ~= "" then
        h = h + ROW_GAP_FIX + UI.MeasureText(11, bw, issue.fix)
    end
    -- The floor is a floor, never a ceiling: the measured height wins whenever
    -- it is larger, so a long issue still gets every line it needs. The extra
    -- pixel is the separator hairline at the bottom of the row.
    return math.max(ROW_MIN_HEIGHT, h + ROW_PAD_BOTTOM + 1)
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

    -- 6 is the list's own left inset below, so this header sits exactly above
    -- the column the row text starts in rather than near it.
    local rh = UI.Font(right, 10, T.dim, nil, "LEFT")
    rh:SetPoint("TOPLEFT", 6 + ROW_TEXT_LEFT, -9)
    rh:SetText("WHAT TO FIX, HIGHEST IMPACT FIRST")

    issueCount = UI.Font(right, 10, T.dim, nil, "RIGHT")
    issueCount:SetPoint("TOPRIGHT", -12, -9)

    local sep = UI.Divider(right)
    sep:SetPoint("TOPLEFT", 10, -24)
    sep:SetPoint("TOPRIGHT", -10, -24)

    -- The height passed here is only the MINIMUM, used to size the row pool.
    -- It has to be the same floor MeasureIssueRow returns, or the pool comes up
    -- short of the number of rows that actually fit on screen. Every row's real
    -- height still comes from MeasureIssueRow, which is what keeps long advice
    -- fully visible instead of clipped.
    issueList = UI.List(right, ROW_MIN_HEIGHT, CreateIssueRow, UpdateIssueRow, MeasureIssueRow)
    -- Tight against the panel edges. Every pixel here becomes wrapping width for
    -- the sentences inside the rows, which is the cheapest way to make the list
    -- shorter without shrinking any text.
    issueList:SetPoint("TOPLEFT", 6, -28)
    issueList:SetPoint("BOTTOMRIGHT", -4, 6)

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

-- Enchants.lua owns its own page too. It sits next to Upgrades because both
-- answer "what do I do about this", and because an enchant is the one upgrade
-- a player can act on without waiting for a drop.
local function BuildEnchantsPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()

    if ns.BuildEnchantsPage then
        ns.BuildEnchantsPage(page)
        return page
    end

    local msg = UI.Font(page, 12, T.dim, nil, "CENTER")
    msg:SetPoint("CENTER")
    msg:SetWidth(420)
    msg:SetText("The enchanting guide is not loaded in this build.")
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
-- Who the two lists currently hold. The window normally draws the player, but
-- the officer console can point it at a decoded report from someone else, so
-- "is it still the same person" takes both halves of that: whether the subject
-- is the player at all, and, when it is not, which player it is. Recorded only
-- once a refresh actually reaches the drawing below, so a refresh that bailed
-- out early can never make the next one look like a routine redraw.
local shownIsSelf, shownName

local function Refresh()
    if not win or not win:IsShown() then return end
    local subject = ns.Subject()
    local report, scan = subject.report, subject.scan
    if not report or not scan then return end

    -- A rebuild for the person already on screen must not move the view. This
    -- runs on every scan, at the end of every fight and on every rescan, and
    -- each one of those used to throw the issue list back to the top under
    -- whoever was reading it. A genuine change of subject is the one case that
    -- should start at the top, because it is different content.
    local isSelf = ns.SubjectIsSelf()
    local sameSubject = (isSelf == shownIsSelf) and (subject.name == shownName)
    shownIsSelf, shownName = isSelf, subject.name

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

    slotList:SetData(scan.slots, sameSubject)
    issueList:SetData(report.issues, sameSubject)
    issueEmpty:SetShown(n == 0)
    issueCount:SetText(n .. (n == 1 and " ISSUE" or " ISSUES"))

    if footerInfo then
        footerInfo:SetText(format("Level %d %s  |  GearScout %s",
            report.level or 0, (report.class or ""):lower(), ns.VERSION))
    end
end

ns:Sub("SCAN_UPDATED", function() ns.Analyze() Refresh() end)
ns:Sub("ROTATION_UPDATED", Refresh)
-- Redraw only. Analyze would recompute the player's own gear, which is not
-- what is on screen once the window is pointed at someone else.
ns:Sub("SUBJECT_CHANGED", Refresh)

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
    tabBar = UI.TabBar(win.content, { "Gear", "Upgrades", "Enchants", "Rotation", "Settings" }, function(i)
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
    enchantsPage = BuildEnchantsPage(body)
    rotationPage = BuildRotationPage(body)
    settingsPage = BuildSettingsPage(body)
    -- Same order as the tab bar above. The two lists are indexed against each
    -- other, so a tab added to one has to be added to the other in step.
    pages = { gearPage, upgradesPage, enchantsPage, rotationPage, settingsPage }
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

-- Show without toggling. The officer console needs this: clicking a second
-- player while the window is already open must swap whose data is on screen,
-- not close the window the player was reading.
function ns.ShowMain()
    Build()
    -- Closing the window hands it back to the player. Without this, reopening
    -- it later would silently show someone else's gear as if it were yours,
    -- which is the one mistake here that would actually mislead somebody.
    if not win.subjectHooked then
        win.subjectHooked = true
        win:HookScript("OnHide", function()
            if not ns.SubjectIsSelf() then ns.SetSubject(nil) end
        end)
    end
    win:Show()
    if ns.SubjectIsSelf() and not ns.lastReport then ns.Evaluate() end
    Refresh()
end

-- The player's own way in, from the minimap button and from /gearscout. It
-- always shows the player themselves: if the window was last pointed at
-- someone else through the officer console and left that way, opening it from
-- here means "show me", never "show whoever I looked at last".
function ns.ToggleMain()
    Build()
    if not ns.SubjectIsSelf() then ns.SetSubject(nil) end
    if win:IsShown() then
        win:Hide()
    else
        win:Show()
        -- Only ever evaluate the player themselves. Someone else's report
        -- arrived over the wire and cannot be recomputed from this client.
        if ns.SubjectIsSelf() and not ns.lastReport then ns.Evaluate() end
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
            -- Right click opens the officer console, but only for someone who
            -- actually has that addon. Looked up at click time rather than at
            -- load, because the two addons have no guaranteed load order and
            -- a plain member never has it at all. Without it, right click
            -- simply does what left click does instead of doing nothing.
            function(_, button)
                local leadAddon = _G.GearScoutLead
                if button == "RightButton" and leadAddon and leadAddon.Toggle then
                    leadAddon.Toggle()
                    return
                end
                ns.ToggleMain()
            end,
            function(_, tip)
                tip:SetText("GearScout", 1, 1, 1)
                tip:AddLine("Left click to open the gear and rotation coach.", 0.8, 0.84, 0.9)
                -- Checked on every hover, so the line appears the moment the
                -- console is installed and never advertises it to a member
                -- who does not have it.
                if _G.GearScoutLead and _G.GearScoutLead.Toggle then
                    tip:AddLine("Right click to open the officer console.", 0.8, 0.84, 0.9)
                end
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
        local subject = ns.Subject()
        if not ns.FindSlotUpgrades or not subject.report then
            ns.Print("Nothing scanned yet. Try /gearscout scan first.")
            return
        end
        local weakest, weakestIlvl
        for _, rec in ipairs(subject.scan and subject.scan.slots or {}) do
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
    elseif msg == "wa" or msg == "weakaura" or msg == "weakauras" then
        -- Deliberately four lines. The actual snippets are pages of Lua and a
        -- wall of code in chat is unreadable and uncopyable, so this points at
        -- the file that has them and prints the one call worth memorising.
        ns.Print("WeakAuras: ready made import strings and copy paste snippets are in WEAKAURA.md, in the GearScout folder you downloaded.")
        ns.Print("  Fastest way: /wa, click Import, paste the string from the top of that file.")
        ns.Print("  Writing your own: trigger type Custom, event GEARSCOUT_BUFFS_UPDATED, then call GearScout.API.GetBuffReport()")
        local api = ns.API
        if api and api.GetMissingBuffCount then
            local n = api.GetMissingBuffCount()
            ns.Print(format("  Missing group buffs right now: %d%s", n,
                (IsInGroup() or IsInRaid()) and "" or " (you are not in a group, so there is nobody to ask)"))
        end
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
