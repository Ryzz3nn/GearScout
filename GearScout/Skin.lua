-- GearScout / Skin.lua
-- "Obsidian" rounded panel skin, built on top of media/roundrect.tga (see
-- tools/gen-corner-texture.mjs). Nine-slices that single texture into a
-- rounded panel: four fixed size corners, four stretched edges, one solid
-- centre. Nothing here is wired into the addon. UI.lua keeps using its own
-- flat UI.Panel / UI.Border until another pass adopts this.
--
-- Every texture a panel needs is created once, in the constructor. Recolour
-- methods only call SetVertexColor / SetColorTexture on those cached
-- references, so nothing in a refresh path calls CreateFrame or
-- CreateTexture.
--
-- If the texture file cannot be loaded (missing from the install, or an
-- older client that never signals load failure, see the comment on
-- TextureUsable below) every constructor falls back to the same flat
-- rectangle plus hairline border UI.Panel/UI.Border already use, so a panel
-- never renders as nothing.

local ADDON, ns = ...

local CreateFrame = CreateFrame

local Skin = {}
ns.Skin = Skin

-- ---------------------------------------------------------------------------
-- palette
-- Same key names as ns.T in Core.lua, so this table can replace it wholesale
-- once the integration pass is ready. Darker and a little softer than the
-- current flat palette; rounded corners read better against more depth.
-- ---------------------------------------------------------------------------
Skin.OBSIDIAN = {
    bg       = { 0.027, 0.031, 0.039, 0.97 },
    panel    = { 0.047, 0.055, 0.067, 1 },
    raised   = { 0.078, 0.090, 0.110, 1 },
    hover    = { 0.114, 0.129, 0.157, 1 },
    line     = { 1, 1, 1, 0.05 },
    lineHard = { 1, 1, 1, 0.11 },
    text     = { 0.902, 0.918, 0.949, 1 },
    dim      = { 0.510, 0.545, 0.612, 1 },
    accent   = { 0.278, 0.596, 0.965, 1 },
    good     = { 0.243, 0.769, 0.388, 1 },
    warn     = { 0.965, 0.694, 0.169, 1 },
    bad      = { 0.937, 0.345, 0.318, 1 },
}

-- ---------------------------------------------------------------------------
-- texture atlas
-- Source art is a 64x64 white rounded rectangle, corner radius 16, shape
-- carried entirely in alpha (see tools/gen-corner-texture.mjs). Slicing it
-- into nine texture coordinate rectangles lets a frame of any size reuse it:
-- fixed size corners, edges stretched between them, a solid centre.
-- ---------------------------------------------------------------------------
local TEXTURE_PATH = "Interface\\AddOns\\" .. ADDON .. "\\media\\roundrect.tga"
Skin.TexturePath = TEXTURE_PATH

local ATLAS  = 64  -- source texture width and height, px
local CORNER = 16  -- corner slice baked into the art, px, matches the radius
local FRAC   = CORNER / ATLAS

-- A single texel pulled from deep inside the flat middle of the source
-- image. That region is fully opaque everywhere, so stretching a texel from
-- it produces a clean, uniform edge or centre fill with no artifacts.
local MID_LO = 0.5 - 0.5 / ATLAS
local MID_HI = 0.5 + 0.5 / ATLAS

local COORD = {
    topLeft     = { 0,        FRAC, 0,        FRAC },
    topRight    = { 1 - FRAC, 1,    0,        FRAC },
    bottomLeft  = { 0,        FRAC, 1 - FRAC, 1    },
    bottomRight = { 1 - FRAC, 1,    1 - FRAC, 1    },
    top         = { MID_LO,   MID_HI, 0,        FRAC },
    bottom      = { MID_LO,   MID_HI, 1 - FRAC, 1    },
    left        = { 0,        FRAC,   MID_LO,   MID_HI },
    right       = { 1 - FRAC, 1,      MID_LO,   MID_HI },
    center      = { MID_LO,   MID_HI, MID_LO,   MID_HI },
}

-- ---------------------------------------------------------------------------
-- texture load guard
--
-- Modern clients have SetTexture report success as a second return value; on
-- those, a missing file is detected directly. Older clients never signal a
-- load failure at all, a texture just renders blank, so on those a missing
-- file cannot be detected from Lua and is treated as usable. That gap is a
-- known limit of this guard, see the report for a live game test.
-- ---------------------------------------------------------------------------
local textureUsable
function Skin.TextureUsable()
    if textureUsable ~= nil then return textureUsable end
    local probe = UIParent:CreateTexture(nil, "BACKGROUND")
    local ok, worked = pcall(probe.SetTexture, probe, TEXTURE_PATH)
    probe:SetTexture(nil)
    probe:Hide()
    textureUsable = ok and worked ~= false
    return textureUsable
end

-- ---------------------------------------------------------------------------
-- nine slice building blocks
-- ---------------------------------------------------------------------------
local function Slice(owner, layer, coord)
    local t = owner:CreateTexture(nil, layer)
    t:SetTexture(TEXTURE_PATH)
    t:SetTexCoord(coord[1], coord[2], coord[3], coord[4])
    return t
end

-- Builds the nine slice pieces so they cover `owner` edge to edge: four
-- fixed size corners pinned to owner's corners, four edges anchored between
-- them (their length comes from those anchors, so they stretch with owner),
-- and an optional centre. withCenter = false leaves the middle untouched,
-- which is what the outline only variant needs.
local function BuildShape(owner, radius, layer, withCenter)
    radius = radius or CORNER
    local s = {}

    s.tl = Slice(owner, layer, COORD.topLeft)
    s.tr = Slice(owner, layer, COORD.topRight)
    s.bl = Slice(owner, layer, COORD.bottomLeft)
    s.br = Slice(owner, layer, COORD.bottomRight)
    s.tl:SetSize(radius, radius); s.tl:SetPoint("TOPLEFT")
    s.tr:SetSize(radius, radius); s.tr:SetPoint("TOPRIGHT")
    s.bl:SetSize(radius, radius); s.bl:SetPoint("BOTTOMLEFT")
    s.br:SetSize(radius, radius); s.br:SetPoint("BOTTOMRIGHT")

    s.top = Slice(owner, layer, COORD.top)
    s.top:SetHeight(radius)
    s.top:SetPoint("TOPLEFT", s.tl, "TOPRIGHT")
    s.top:SetPoint("TOPRIGHT", s.tr, "TOPLEFT")

    s.bottom = Slice(owner, layer, COORD.bottom)
    s.bottom:SetHeight(radius)
    s.bottom:SetPoint("BOTTOMLEFT", s.bl, "BOTTOMRIGHT")
    s.bottom:SetPoint("BOTTOMRIGHT", s.br, "BOTTOMLEFT")

    s.left = Slice(owner, layer, COORD.left)
    s.left:SetWidth(radius)
    s.left:SetPoint("TOPLEFT", s.tl, "BOTTOMLEFT")
    s.left:SetPoint("BOTTOMLEFT", s.bl, "TOPLEFT")

    s.right = Slice(owner, layer, COORD.right)
    s.right:SetWidth(radius)
    s.right:SetPoint("TOPRIGHT", s.tr, "BOTTOMRIGHT")
    s.right:SetPoint("BOTTOMRIGHT", s.br, "TOPRIGHT")

    if withCenter then
        s.center = Slice(owner, layer, COORD.center)
        s.center:SetPoint("TOPLEFT", s.left, "TOPRIGHT")
        s.center:SetPoint("BOTTOMRIGHT", s.right, "BOTTOMLEFT")
    end

    return s
end

-- Recolour only. No texture is created or destroyed here, safe to call from
-- any refresh path.
local function TintShape(s, c)
    c = c or { 1, 1, 1, 1 }
    for _, tex in pairs(s) do
        tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    end
end

-- Flat rectangle plus four hairlines, the same shape UI.Panel/UI.Border
-- build. Used whenever the rounded texture is not usable.
local function BuildFlatFallback(f, fill, border)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)

    local b = {}
    for i = 1, 4 do
        b[i] = f:CreateTexture(nil, "BORDER")
        b[i]:SetColorTexture(border[1], border[2], border[3], border[4] or 1)
    end
    b[1]:SetPoint("TOPLEFT");    b[1]:SetPoint("TOPRIGHT");    b[1]:SetHeight(1)
    b[2]:SetPoint("BOTTOMLEFT"); b[2]:SetPoint("BOTTOMRIGHT"); b[2]:SetHeight(1)
    b[3]:SetPoint("TOPLEFT");    b[3]:SetPoint("BOTTOMLEFT");  b[3]:SetWidth(1)
    b[4]:SetPoint("TOPRIGHT");   b[4]:SetPoint("BOTTOMRIGHT"); b[4]:SetWidth(1)
    f.borderLines = b
end

-- ---------------------------------------------------------------------------
-- ns.Skin.RoundedPanel
-- A filled rounded panel with a border ring around it, the rounded
-- equivalent of UI.Panel(parent, fill, border). Built from two stacked nine
-- slices: an outer one at the frame's full size tinted borderColor, and an
-- inner one inset by BORDER_WIDTH tinted fillColor, so a border colored ring
-- shows around the fill. Both use the same fixed corner radius, so the ring
-- is exact along straight edges; at the very tip of the curve it can read a
-- touch thicker, see the report.
-- ---------------------------------------------------------------------------
local BORDER_WIDTH = 2 -- px, ring thickness between the outer and inner shape
Skin.BORDER_WIDTH = BORDER_WIDTH

function Skin.RoundedPanel(parent, radius, fillColor, borderColor)
    radius = radius or CORNER
    fillColor = fillColor or Skin.OBSIDIAN.panel
    borderColor = borderColor or Skin.OBSIDIAN.lineHard

    local f = CreateFrame("Frame", nil, parent)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)

    if Skin.TextureUsable() then
        f.borderShape = BuildShape(f, radius, "BACKGROUND", true)
        TintShape(f.borderShape, borderColor)

        f.fillFrame = CreateFrame("Frame", nil, f)
        f.fillFrame:SetPoint("TOPLEFT", BORDER_WIDTH, -BORDER_WIDTH)
        f.fillFrame:SetPoint("BOTTOMRIGHT", -BORDER_WIDTH, BORDER_WIDTH)
        f.fillShape = BuildShape(f.fillFrame, radius, "BORDER", true)
        TintShape(f.fillShape, fillColor)
        f.skinned = true
    else
        BuildFlatFallback(f, fillColor, borderColor)
        f.skinned = false
    end

    function f:SetFillColor(c)
        if self.fillShape then
            TintShape(self.fillShape, c)
        elseif self.bg then
            self.bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        end
    end

    function f:SetBorderColor(c)
        if self.borderShape then
            TintShape(self.borderShape, c)
        elseif self.borderLines then
            for i = 1, 4 do
                self.borderLines[i]:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
            end
        end
    end

    return f
end

-- ---------------------------------------------------------------------------
-- ns.Skin.RoundedBorder
-- Outline only: the eight corner and edge pieces tinted a single colour,
-- centre left out entirely so whatever sits behind the frame still shows
-- through. Ring thickness equals radius. Meant to decorate arbitrary
-- content the way UI.Border decorates a button or a checkbox, not paired
-- with a matching fill.
-- ---------------------------------------------------------------------------
function Skin.RoundedBorder(parent, radius, color)
    radius = radius or CORNER
    color = color or Skin.OBSIDIAN.lineHard

    local f = CreateFrame("Frame", nil, parent)

    if Skin.TextureUsable() then
        f.shape = BuildShape(f, radius, "BORDER", false)
        TintShape(f.shape, color)
        f.skinned = true
    else
        local b = {}
        for i = 1, 4 do
            b[i] = f:CreateTexture(nil, "BORDER")
            b[i]:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        end
        b[1]:SetPoint("TOPLEFT");    b[1]:SetPoint("TOPRIGHT");    b[1]:SetHeight(1)
        b[2]:SetPoint("BOTTOMLEFT"); b[2]:SetPoint("BOTTOMRIGHT"); b[2]:SetHeight(1)
        b[3]:SetPoint("TOPLEFT");    b[3]:SetPoint("BOTTOMLEFT");  b[3]:SetWidth(1)
        b[4]:SetPoint("TOPRIGHT");   b[4]:SetPoint("BOTTOMRIGHT"); b[4]:SetWidth(1)
        f.borderLines = b
        f.skinned = false
    end

    function f:SetColor(c)
        if self.shape then
            TintShape(self.shape, c)
        elseif self.borderLines then
            for i = 1, 4 do
                self.borderLines[i]:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
            end
        end
    end

    return f
end
