-- GearScout / UI.lua
-- Self contained widget kit. No Ace, no LibStub, no Blizzard Backdrop API.
--
-- Performance rules this file follows:
--   * No permanent OnUpdate handlers. The only OnUpdate is a tween that
--     removes its own script when it finishes.
--   * Lists are virtualized. A 40 man roster creates the same 14 row frames as
--     an empty one, and scrolling re-texts those rows instead of building more.
--   * Frames and textures are created once, then shown and hidden. Nothing in
--     a refresh path calls CreateFrame.
--   * Animations use AnimationGroups so the interpolation runs on the C side.

local ADDON, ns = ...

local CreateFrame, UIParent = CreateFrame, UIParent
local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local unpack, select = unpack, select

local T = ns.T
local UI = {}
ns.UI = UI

-- Pull the client font so non Western locales keep working.
local FONT = GameFontNormal:GetFont()
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- ---------------------------------------------------------------------------
-- primitives
-- ---------------------------------------------------------------------------

function UI.Tex(parent, layer, c)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    if c then t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
    return t
end

-- Four hairlines instead of a backdrop. Crisp at any UI scale, zero templates.
function UI.Border(f, c)
    c = c or T.line
    local b = {}
    for i = 1, 4 do
        b[i] = f:CreateTexture(nil, "BORDER")
        b[i]:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end
    b[1]:SetPoint("TOPLEFT");    b[1]:SetPoint("TOPRIGHT");    b[1]:SetHeight(1)
    b[2]:SetPoint("BOTTOMLEFT"); b[2]:SetPoint("BOTTOMRIGHT"); b[2]:SetHeight(1)
    b[3]:SetPoint("TOPLEFT");    b[3]:SetPoint("BOTTOMLEFT");  b[3]:SetWidth(1)
    b[4]:SetPoint("TOPRIGHT");   b[4]:SetPoint("BOTTOMRIGHT"); b[4]:SetWidth(1)
    f.borderTextures = b
    return b
end

function UI.SetBorderColor(f, c)
    if not f.borderTextures then return end
    for i = 1, 4 do
        f.borderTextures[i]:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end
end

-- Set by ns.ApplySkin once the saved variables are loaded. When false every
-- panel keeps the original flat rectangle, which is the fallback skin.
UI.useRounded = false
UI.radius = 10

-- Recolours a panel's fill whichever way it was drawn. Hover states go
-- through this so they work in both skins without branching at the call site.
function UI.SetFill(f, c)
    if f.skin and f.skin.SetFillColor then
        f.skin:SetFillColor(c)
    elseif f.bg then
        f.bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end
end

-- Panels swallow mouse input on purpose. Without this, a click that lands on
-- empty space inside the window falls through to whatever sits behind it,
-- usually the chat frame or an action bar.
function UI.Panel(parent, fill, border, radius)
    local f = CreateFrame("Frame", nil, parent)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)

    if UI.useRounded and ns.Skin and ns.Skin.RoundedPanel then
        -- The skin lives one frame level below its own container so that
        -- anything added to the panel afterwards still draws on top of it.
        local skin = ns.Skin.RoundedPanel(f, radius or UI.radius,
                                          fill or T.panel, border or T.line)
        skin:SetAllPoints(f)
        skin:SetFrameLevel(max(0, f:GetFrameLevel() - 1))
        f.skin = skin
    else
        f.bg = UI.Tex(f, "BACKGROUND", fill or T.panel)
        f.bg:SetAllPoints()
        UI.Border(f, border or T.line)
    end
    return f
end

function UI.Font(parent, size, color, flags, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size or 12, flags or "")
    local c = color or T.text
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    if justify then fs:SetJustifyH(justify) end
    return fs
end

-- ---------------------------------------------------------------------------
-- text measurement
-- Used by lists with variable row heights to size a row before it draws.
-- One hidden FontString per distinct font size, reused for every call, so
-- measuring a whole dataset never creates a new font string object.
-- ---------------------------------------------------------------------------
local measureFrame
local measureCache = {}

function UI.MeasureText(size, width, text, flags)
    if not measureFrame then
        measureFrame = CreateFrame("Frame", nil, UIParent)
        measureFrame:Hide()
    end
    size = size or 12
    local fs = measureCache[size]
    if not fs then
        fs = measureFrame:CreateFontString(nil, "OVERLAY")
        measureCache[size] = fs
    end
    fs:SetFont(FONT, size, flags or "")
    fs:SetWidth(max(1, width or 1))
    fs:SetText(text or "")
    return fs:GetStringHeight()
end

function UI.Divider(parent, horizontal)
    local t = UI.Tex(parent, "ARTWORK", T.line)
    if horizontal == false then t:SetWidth(1) else t:SetHeight(1) end
    return t
end

-- Small filled circle used for status. Uses a ring texture that ships with the
-- client so there is no art to bundle.
function UI.Dot(parent, size, c)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\COMMON\\Indicator-Gray")
    t:SetSize(size or 10, size or 10)
    if c then t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
    return t
end

-- ---------------------------------------------------------------------------
-- tween
-- A single self cancelling OnUpdate. Used for the score bar so numbers glide
-- instead of snapping. Nothing else in the addon polls.
-- ---------------------------------------------------------------------------
function UI.Tween(frame, duration, apply)
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local p = elapsed / duration
        if p >= 1 then
            apply(1)
            self:SetScript("OnUpdate", nil)
            return
        end
        -- ease out cubic
        local e = 1 - (1 - p) ^ 3
        apply(e)
    end)
end

-- ---------------------------------------------------------------------------
-- progress bar
-- ---------------------------------------------------------------------------
function UI.Bar(parent, c)
    local bar = CreateFrame("Frame", nil, parent)
    bar.track = UI.Tex(bar, "BACKGROUND", { 1, 1, 1, 0.06 })
    bar.track:SetAllPoints()
    bar.fill = UI.Tex(bar, "ARTWORK", c or T.accent)
    bar.fill:SetPoint("TOPLEFT")
    bar.fill:SetPoint("BOTTOMLEFT")
    bar.fill:SetWidth(1)
    bar.value = 0

    local function Apply(self)
        local w = self:GetWidth()
        if not w or w <= 0 then return end
        self.fill:SetWidth(max(1, w * self.value))
    end

    function bar:SetColor(col)
        self.fill:SetColorTexture(col[1], col[2], col[3], col[4] or 1)
    end

    function bar:SetValue(v, animate)
        v = ns.Clamp(v or 0, 0, 1)
        if animate then
            local from = self.value
            UI.Tween(self, 0.35, function(p)
                self.value = from + (v - from) * p
                Apply(self)
            end)
        else
            self.value = v
            Apply(self)
        end
    end

    bar:SetScript("OnSizeChanged", function(self) Apply(self) end)
    return bar
end

-- ---------------------------------------------------------------------------
-- button
-- ---------------------------------------------------------------------------
function UI.Button(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 90, h or 22)

    if UI.useRounded and ns.Skin and ns.Skin.RoundedPanel then
        local skin = ns.Skin.RoundedPanel(b, 6, T.raised, T.line)
        skin:SetAllPoints(b)
        skin:SetFrameLevel(max(0, b:GetFrameLevel() - 1))
        b.skin = skin
    else
        b.bg = UI.Tex(b, "BACKGROUND", T.raised)
        b.bg:SetAllPoints()
        UI.Border(b, T.line)
    end

    b.label = UI.Font(b, 12)
    b.label:SetPoint("CENTER")
    b.label:SetText(text)

    b:SetScript("OnEnter", function(self)
        UI.SetFill(self, T.hover)
        self.label:SetTextColor(unpack(T.accent))
        if self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tooltipText, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        UI.SetFill(self, T.raised)
        self.label:SetTextColor(unpack(T.text))
        GameTooltip:Hide()
    end)
    b:SetScript("OnMouseDown", function(self) self.label:SetPoint("CENTER", 0, -1) end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- ---------------------------------------------------------------------------
-- checkbox
-- ---------------------------------------------------------------------------
function UI.CheckBox(parent, text, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(20)

    local box = CreateFrame("Frame", nil, b)
    box:SetSize(14, 14)
    box:SetPoint("LEFT")
    box.bg = UI.Tex(box, "BACKGROUND", T.raised)
    box.bg:SetAllPoints()
    UI.Border(box, T.lineHard)

    local tick = UI.Tex(box, "OVERLAY", T.accent)
    tick:SetPoint("TOPLEFT", 3, -3)
    tick:SetPoint("BOTTOMRIGHT", -3, 3)

    local label = UI.Font(b, 12)
    label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    label:SetText(text)
    b:SetWidth(label:GetStringWidth() + 26)

    function b:Refresh()
        tick:SetShown(get() and true or false)
    end

    b:SetScript("OnClick", function(self)
        set(not get())
        self:Refresh()
        PlaySound(856)
    end)
    b:SetScript("OnEnter", function() label:SetTextColor(unpack(T.accent)) end)
    b:SetScript("OnLeave", function() label:SetTextColor(unpack(T.text)) end)

    b:Refresh()
    return b
end

-- ---------------------------------------------------------------------------
-- select
-- Hand rolled so it never touches UIDropDownMenu, which is a known taint and
-- styling headache.
-- ---------------------------------------------------------------------------
function UI.Select(parent, width, options, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 150, 22)
    if UI.useRounded and ns.Skin and ns.Skin.RoundedPanel then
        local skin = ns.Skin.RoundedPanel(b, 6, T.raised, T.line)
        skin:SetAllPoints(b)
        skin:SetFrameLevel(max(0, b:GetFrameLevel() - 1))
        b.skin = skin
    else
        b.bg = UI.Tex(b, "BACKGROUND", T.raised)
        b.bg:SetAllPoints()
        UI.Border(b, T.line)
    end

    local label = UI.Font(b, 12, T.text, nil, "LEFT")
    label:SetPoint("LEFT", 8, 0)
    label:SetPoint("RIGHT", -18, 0)

    local caret = UI.Font(b, 10, T.dim)
    caret:SetPoint("RIGHT", -7, -1)
    caret:SetText("v")

    local menu = CreateFrame("Frame", nil, b)
    menu:SetFrameStrata("DIALOG")
    menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
    menu:SetWidth(width or 150)
    menu:SetHeight(#options * 20 + 8)
    menu.bg = UI.Tex(menu, "BACKGROUND", T.panel)
    menu.bg:SetAllPoints()
    UI.Border(menu, T.lineHard)
    menu:Hide()

    for i, opt in ipairs(options) do
        local row = CreateFrame("Button", nil, menu)
        row:SetHeight(20)
        row:SetPoint("TOPLEFT", 4, -(i - 1) * 20 - 4)
        row:SetPoint("RIGHT", -4, 0)
        local hl = UI.Tex(row, "BACKGROUND", T.hover)
        hl:SetAllPoints()
        hl:Hide()
        local txt = UI.Font(row, 12, T.text, nil, "LEFT")
        txt:SetPoint("LEFT", 6, 0)
        txt:SetText(opt.text)
        row:SetScript("OnEnter", function() hl:Show() end)
        row:SetScript("OnLeave", function() hl:Hide() end)
        row:SetScript("OnClick", function()
            set(opt.value)
            menu:Hide()
            b:Refresh()
        end)
    end

    function b:Refresh()
        local v = get()
        for _, opt in ipairs(options) do
            if opt.value == v then label:SetText(opt.text) return end
        end
        label:SetText(tostring(v))
    end

    b:SetScript("OnClick", function() menu:SetShown(not menu:IsShown()) end)
    b:SetScript("OnEnter", function(self) UI.SetFill(self, T.hover) end)
    b:SetScript("OnLeave", function(self) UI.SetFill(self, T.raised) end)
    b:Refresh()
    return b
end

-- ---------------------------------------------------------------------------
-- virtualized list
--
-- createRow(list) -> frame, called once per visible slot
-- updateRow(row, item, index), called on scroll and on data change
-- measureRow(item, width) -> pixel height, optional. Leave it out and the
-- list is the plain fixed row height list this always was, byte for byte the
-- same code path. Pass it and rowHeight becomes the MINIMUM row height, used
-- only to size the row pool, while each row's real height comes from
-- measureRow.
-- ---------------------------------------------------------------------------
function UI.List(parent, rowHeight, createRow, updateRow, measureRow)
    local list = CreateFrame("Frame", nil, parent)

    -- Clipping is what lets a partial row sit at the top and bottom edge. With
    -- it, the visible area is always completely filled. Without it, fall back
    -- to whole rows so nothing paints outside the panel.
    local canClip = type(list.SetClipsChildren) == "function"
    if canClip then list:SetClipsChildren(true) end

    list.rowHeight = rowHeight
    list.rows = {}
    list.data = {}
    list.scroll = 0        -- rendered offset, in pixels
    list.target = 0        -- where the scroll is heading
    list.firstIndex = -1
    list.visibleCount = 0
    list.heights = {}      -- per item pixel height, filled only when measureRow is set
    list.offsets = {}      -- absolute top of each item, same condition
    list.totalHeight = 0

    -- Rows live in this child. Scrolling moves one frame by a few pixels
    -- rather than re-anchoring every row every frame.
    local content = CreateFrame("Frame", nil, list)
    content:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
    content:SetHeight(1)
    list.content = content

    local slider = CreateFrame("Slider", nil, list)
    slider:SetOrientation("VERTICAL")
    slider:SetWidth(8)
    slider:SetPoint("TOPRIGHT", 0, -1)
    slider:SetPoint("BOTTOMRIGHT", 0, 1)
    slider:SetMinMaxValues(0, 0)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(false) end
    local track = UI.Tex(slider, "BACKGROUND", { 1, 1, 1, 0.04 })
    track:SetAllPoints()
    slider:SetThumbTexture(WHITE)
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(8, 36)
    thumb:SetColorTexture(1, 1, 1, 0.18)
    slider:Hide()
    list.slider = slider

    local syncing = false

    local function MaxScroll()
        local h = list:GetHeight() or 0
        if measureRow then
            return max(0, list.totalHeight - h)
        end
        return max(0, #list.data * rowHeight - h)
    end

    local function EnsureRows()
        local h = list:GetHeight()
        if not h or h <= 0 then return end
        content:SetWidth(max(1, (list:GetWidth() or 1) - 11))
        -- one extra row so a partial one can cover the bottom edge. rowHeight
        -- is always the shortest possible row, so sizing the pool from it
        -- guarantees enough rows even when every visible item is short.
        local need = canClip and (ceil(h / rowHeight) + 1) or max(1, floor(h / rowHeight))
        for i = #list.rows + 1, need do
            local row = createRow(content)
            row:SetHeight(rowHeight)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * rowHeight)
            row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
            list.rows[i] = row
        end
        list.visibleCount = need
    end

    -- Builds the per item height and cumulative offset arrays. Only runs on
    -- SetData/Refresh, never mid scroll, so calling measureRow for every item
    -- costs once per data change instead of once per frame.
    local function ComputeLayout()
        if not measureRow then return end
        local w = max(1, (list:GetWidth() or 1) - 11)
        local heights, offsets = {}, {}
        local total = 0
        for i, item in ipairs(list.data) do
            local hgt = measureRow(item, w)
            if not hgt or hgt <= 0 then hgt = rowHeight end
            heights[i] = hgt
            offsets[i] = total
            total = total + hgt
        end
        list.heights, list.offsets, list.totalHeight = heights, offsets, total
    end

    -- offsets is sorted ascending by construction. This finds the last item
    -- whose absolute top is at or before scroll, i.e. the item that belongs
    -- in the first visible row slot. A linear scan would cost O(n) every
    -- frame while the list glides, this keeps it O(log n).
    local function FindFirst(scroll, offsets, n)
        local lo, hi = 1, n
        while lo < hi do
            local mid = ceil((lo + hi) / 2)
            if offsets[mid] <= scroll then
                lo = mid
            else
                hi = mid - 1
            end
        end
        return lo
    end

    function list:Draw()
        local first, frac
        if measureRow then
            local n = #self.data
            first = n > 0 and FindFirst(self.scroll, self.offsets, n) or 1
            frac = self.scroll - (self.offsets[first] or 0)
        else
            first = floor(self.scroll / rowHeight)
            frac = self.scroll - first * rowHeight
        end

        -- single anchor move per frame while scrolling
        content:SetPoint("TOPLEFT", self, "TOPLEFT", 0, frac)

        -- rows only get re-texted when the top data index actually changes
        if first ~= self.firstIndex then
            self.firstIndex = first
            if measureRow then
                -- variable heights mean the grid isn't uniform, so every
                -- visible row has to be re-anchored, not just re-texted
                local y = 0
                for i = 1, self.visibleCount do
                    local row = self.rows[i]
                    if row then
                        local idx = first + i - 1
                        local item = self.data[idx]
                        if item then
                            local hgt = self.heights[idx] or rowHeight
                            row:ClearAllPoints()
                            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                            row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                            row:SetHeight(hgt)
                            row:Show()
                            updateRow(row, item, idx)
                            y = y + hgt
                        else
                            row:Hide()
                        end
                    end
                end
            else
                for i = 1, self.visibleCount do
                    local row = self.rows[i]
                    if row then
                        local idx = first + i
                        local item = self.data[idx]
                        if item then
                            row:Show()
                            updateRow(row, item, idx)
                        else
                            row:Hide()
                        end
                    end
                end
            end
            for i = self.visibleCount + 1, #self.rows do
                self.rows[i]:Hide()
            end
        end

        if not syncing then
            syncing = true
            slider:SetValue(self.scroll)
            syncing = false
        end
    end

    -- Runs only while the list is gliding, then removes itself.
    local function Glide(self, dt)
        local diff = self.target - self.scroll
        if abs(diff) < 0.5 then
            self.scroll = self.target
            self:SetScript("OnUpdate", nil)
            self:Draw()
            return
        end
        self.scroll = self.scroll + diff * min(1, dt * 18)
        self:Draw()
    end

    function list:ScrollTo(v, instant)
        local mx = MaxScroll()
        -- the row grid snap only makes sense when every row is the same
        -- height, so skip it in variable height mode
        if not canClip and not measureRow then v = floor(v / rowHeight + 0.5) * rowHeight end
        if v < 0 then v = 0 elseif v > mx then v = mx end
        self.target = v
        if instant then
            self.scroll = v
            self:SetScript("OnUpdate", nil)
            self:Draw()
        else
            self:SetScript("OnUpdate", Glide)
        end
    end

    function list:Refresh()
        ComputeLayout()
        EnsureRows()
        local mx = MaxScroll()
        if self.scroll > mx then self.scroll = mx end
        if self.target > mx then self.target = mx end

        syncing = true
        slider:SetMinMaxValues(0, mx)
        slider:SetValue(self.scroll)
        syncing = false
        slider:SetShown(mx > 0)

        local h = self:GetHeight() or 1
        local totalH = measureRow and self.totalHeight or (#self.data * rowHeight)
        if mx > 0 and totalH > 0 then
            thumb:SetHeight(max(24, h * (h / totalH)))
        end

        self.firstIndex = -1   -- force a re-text
        self:Draw()
    end

    -- keepScroll matters for lists that refresh on a timer. Without it a live
    -- update would yank the view back to the top while the user is reading.
    function list:SetData(t, keepScroll)
        self.data = t or {}
        if not keepScroll then
            self.scroll, self.target = 0, 0
            self:SetScript("OnUpdate", nil)
        end
        self:Refresh()
    end

    slider:SetScript("OnValueChanged", function(_, v)
        if syncing then return end
        list:ScrollTo(v, true)
    end)

    local wheelStep = 3 * min(rowHeight, 30)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        if not slider:IsShown() then return end
        self:ScrollTo(self.target - delta * wheelStep, false)
    end)
    list:SetScript("OnSizeChanged", function(self) self:Refresh() end)

    return list
end

-- ---------------------------------------------------------------------------
-- tab bar
-- ---------------------------------------------------------------------------
function UI.TabBar(parent, tabs, onSelect)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(28)
    bar.buttons = {}
    bar.selected = 1

    local x = 0
    for i, name in ipairs(tabs) do
        local t = CreateFrame("Button", nil, bar)
        t:SetHeight(28)
        t:SetPoint("BOTTOMLEFT", x, 0)

        local label = UI.Font(t, 12)
        label:SetPoint("CENTER", 0, 1)
        label:SetText(name)
        t:SetWidth(max(70, label:GetStringWidth() + 28))
        x = x + t:GetWidth()

        local underline = UI.Tex(t, "OVERLAY", T.accent)
        underline:SetPoint("BOTTOMLEFT", 6, 0)
        underline:SetPoint("BOTTOMRIGHT", -6, 0)
        underline:SetHeight(2)
        underline:Hide()

        t.label, t.underline = label, underline
        t:SetScript("OnClick", function() bar:Select(i) end)
        t:SetScript("OnEnter", function(self)
            if bar.selected ~= i then self.label:SetTextColor(unpack(T.text)) end
        end)
        t:SetScript("OnLeave", function(self)
            if bar.selected ~= i then self.label:SetTextColor(unpack(T.dim)) end
        end)
        bar.buttons[i] = t
    end
    bar:SetWidth(x)

    function bar:Select(i)
        self.selected = i
        for j, t in ipairs(self.buttons) do
            local on = (j == i)
            t.underline:SetShown(on)
            t.label:SetTextColor(unpack(on and T.text or T.dim))
        end
        if onSelect then onSelect(i) end
    end

    bar:Select(1)
    return bar
end

-- ---------------------------------------------------------------------------
-- window
-- ---------------------------------------------------------------------------
function UI.Window(globalName, title, w, h)
    local f = CreateFrame("Frame", globalName, UIParent)
    f:SetSize(w, h)
    -- DIALOG sits above the chat frame and the action bars. On HIGH, a click
    -- near the bottom of the window can still reach the chat behind it.
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:Hide()

    local rounded = UI.useRounded and ns.Skin and ns.Skin.RoundedPanel
    if rounded then
        local skin = ns.Skin.RoundedPanel(f, 12, T.bg, T.lineHard)
        skin:SetAllPoints(f)
        skin:SetFrameLevel(max(0, f:GetFrameLevel() - 1))
        f.skin = skin
    else
        f.bg = UI.Tex(f, "BACKGROUND", T.bg)
        f.bg:SetAllPoints()
        UI.Border(f, T.lineHard)
    end

    -- title bar
    local tb = CreateFrame("Frame", nil, f)
    tb:SetHeight(34)
    tb:SetPoint("TOPLEFT")
    tb:SetPoint("TOPRIGHT")
    -- A square strip across the top would poke its corners out through the
    -- window's rounded ones, so in that skin the window background shows
    -- through and only the divider line separates the title bar.
    if not rounded then
        tb.bg = UI.Tex(tb, "BACKGROUND", T.panel)
        tb.bg:SetAllPoints()
    end
    local tbLine = UI.Tex(tb, "ARTWORK", T.line)
    tbLine:SetPoint("BOTTOMLEFT")
    tbLine:SetPoint("BOTTOMRIGHT")
    tbLine:SetHeight(1)

    local accentDash = UI.Tex(tb, "ARTWORK", T.accent)
    accentDash:SetPoint("LEFT", 12, 0)
    accentDash:SetSize(3, 14)

    f.title = UI.Font(tb, 13, T.text, nil, "LEFT")
    f.title:SetPoint("LEFT", 22, 0)
    f.title:SetText(title)

    f.subtitle = UI.Font(tb, 11, T.dim, nil, "LEFT")
    f.subtitle:SetPoint("LEFT", f.title, "RIGHT", 10, 0)

    tb:EnableMouse(true)
    tb:RegisterForDrag("LeftButton")
    tb:SetScript("OnDragStart", function() f:StartMoving() end)
    tb:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if ns.db then
            local point, _, relPoint, x, y = f:GetPoint()
            ns.db.window[globalName] = { point = point, rel = relPoint, x = x, y = y }
        end
    end)

    local close = CreateFrame("Button", nil, tb)
    close:SetSize(28, 28)
    close:SetPoint("RIGHT", -4, 0)
    local xLabel = UI.Font(close, 14, T.dim)
    xLabel:SetPoint("CENTER")
    xLabel:SetText("X")
    close:SetScript("OnEnter", function() xLabel:SetTextColor(unpack(T.bad)) end)
    close:SetScript("OnLeave", function() xLabel:SetTextColor(unpack(T.dim)) end)
    close:SetScript("OnClick", function() f:Hide() end)
    f.titleBar = tb

    -- content area below the title bar
    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT", 0, -34)
    f.content:SetPoint("BOTTOMRIGHT", 0, 0)

    -- open animation, interpolated on the C side
    local ag = f:CreateAnimationGroup()
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(0.12)
    fade:SetSmoothing("OUT")
    local scale = ag:CreateAnimation("Scale")
    if scale.SetScaleFrom then
        scale:SetScaleFrom(0.98, 0.98)
        scale:SetScaleTo(1, 1)
    elseif scale.SetFromScale then
        scale:SetFromScale(0.98, 0.98)
        scale:SetToScale(1, 1)
    end
    scale:SetOrigin("CENTER", 0, 0)
    scale:SetDuration(0.12)
    scale:SetSmoothing("OUT")
    f:SetScript("OnShow", function(self) ag:Stop() ag:Play() end)

    -- escape closes it
    tinsert(UISpecialFrames, globalName)

    function f:RestorePosition()
        local saved = ns.db and ns.db.window[globalName]
        self:ClearAllPoints()
        if saved and saved.point then
            self:SetPoint(saved.point, UIParent, saved.rel, saved.x, saved.y)
        else
            self:SetPoint("CENTER")
        end
    end

    return f
end

-- ---------------------------------------------------------------------------
-- tooltip helper
-- ---------------------------------------------------------------------------
function UI.HookTooltip(frame, fill)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        fill(self, GameTooltip)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ---------------------------------------------------------------------------
-- minimap button
-- ---------------------------------------------------------------------------
function UI.MinimapButton(globalName, iconPath, onClick, fillTooltip)
    local b = CreateFrame("Button", globalName, Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(iconPath)
    icon:SetSize(19, 19)
    icon:SetPoint("CENTER", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    local function Reposition()
        local angle = (ns.db and ns.db.minimapAngle) or 202
        b:SetPoint("CENTER", Minimap, "CENTER", 80 * cos(angle), 80 * sin(angle))
    end
    b.Reposition = Reposition

    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
        -- OnUpdate exists only while the button is being dragged
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            if ns.db then
                ns.db.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
            end
            Reposition()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnClick", onClick)
    if fillTooltip then
        UI.HookTooltip(b, fillTooltip)
    end

    Reposition()
    return b
end
