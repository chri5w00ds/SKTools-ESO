--[[-------------------------------------------------------------------------
  SKTools-ESO by Scotskoogen-Chris
  Resources: the SKTools block, as in the WoW Forever version.

  Top to bottom: Health, Magicka, Stamina, and the cast bar along the bottom
  while channelling (nothing above it moves). The bars sit flush, split by
  fine dark seams, inside one thin silver frame (light at the top, darker at
  the bottom) with rounded corners.

  Each bar: the SKTools pastel, light at the top and dark at the bottom, over
  a dark track. Percent on the left, the value on the right, in a condensed
  font with a drop shadow. Optional gradient (darker on the left) and
  cylinder shading (dark top and bottom edges), as in the WoW options.
---------------------------------------------------------------------------]]

local SKT = SKT
local WM  = WINDOW_MANAGER
local EM  = EVENT_MANAGER

local NS = "SKToolsESO_Resources"
local R = {}
SKT.Resources = R

-- the SKTools pastels (same values as the WoW version)
local COLORS = {
    health  = { 0.84, 0.42, 0.44 },   -- pastel red (WoW's rage pastel)
    magicka = { 0.45, 0.72, 0.92 },   -- WoW's mana
    stamina = { 0.25, 0.62, 0.30 },   -- green (WoW's health)
    cast    = { 0.93, 0.52, 0.72 },   -- pink
    range   = { 0.95, 0.22, 0.20 },   -- used for "Interrupted"
}
local GRADIENT_MAX, CYLINDER_MAX = 0.70, 0.90
local SILVER_TOP, SILVER_BOTTOM = { 0.94, 0.94, 0.96 }, { 0.58, 0.59, 0.63 }

-- the WoW cylinder.tga, sampled down its height (it is symmetric): dark top and bottom edges
local CYL = {
    { 0.0000, 0.824 }, { 0.0625, 0.490 }, { 0.125, 0.322 }, { 0.250, 0.125 }, { 0.375, 0.027 },
    { 0.5000, 0.000 }, { 0.6250, 0.027 }, { 0.750, 0.125 }, { 0.875, 0.322 }, { 0.9375, 0.490 },
    { 1.0000, 0.824 },
}

local BARS = {
    { key = "health",  power = COMBAT_MECHANIC_FLAGS_HEALTH  or POWERTYPE_HEALTH,  size = "health" },
    { key = "magicka", power = COMBAT_MECHANIC_FLAGS_MAGICKA or POWERTYPE_MAGICKA, size = "power" },
    { key = "stamina", power = COMBAT_MECHANIC_FLAGS_STAMINA or POWERTYPE_STAMINA, size = "power" },
}

local function Clamp01(v) return math.max(0, math.min(1, v)) end

-- one screen pixel in UI units, and a value put on whole pixels
local function Px()
    local s = (GetUIGlobalScale and GetUIGlobalScale()) or 1
    return (s > 0) and (1 / s) or 1
end
local function OnPx(v)
    local px = Px()
    return zo_round(v / px) * px
end

---------------------------------------------------------------------------
-- Texture helpers (no image files: everything is drawn with vertex colours)
---------------------------------------------------------------------------
local function Tex(parent, level)
    local t = WM:CreateControl(nil, parent, CT_TEXTURE)
    t:SetColor(1, 1, 1, 1)
    t:SetDrawLevel(level or 1)
    return t
end

local function VGrad(t, r1, g1, b1, a1, r2, g2, b2, a2)       -- top colour, bottom colour
    t:SetVertexColors(VERTEX_POINTS_TOPLEFT,     r1, g1, b1, a1)
    t:SetVertexColors(VERTEX_POINTS_TOPRIGHT,    r1, g1, b1, a1)
    t:SetVertexColors(VERTEX_POINTS_BOTTOMLEFT,  r2, g2, b2, a2)
    t:SetVertexColors(VERTEX_POINTS_BOTTOMRIGHT, r2, g2, b2, a2)
end

local function HGrad(t, r1, g1, b1, a1, r2, g2, b2, a2)       -- left colour, right colour
    t:SetVertexColors(VERTEX_POINTS_TOPLEFT,     r1, g1, b1, a1)
    t:SetVertexColors(VERTEX_POINTS_BOTTOMLEFT,  r1, g1, b1, a1)
    t:SetVertexColors(VERTEX_POINTS_TOPRIGHT,    r2, g2, b2, a2)
    t:SetVertexColors(VERTEX_POINTS_BOTTOMRIGHT, r2, g2, b2, a2)
end

-- the nameplates' bar look: light at the top, dark at the bottom
local function Gradient(t, c, lift, alpha)
    lift, alpha = lift or 1, alpha or 1
    VGrad(t,
        Clamp01(c[1] * 1.15 + 0.12), Clamp01(c[2] * 1.15 + 0.12), Clamp01(c[3] * 1.15 + 0.12), alpha,
        c[1] * 0.55 * lift, c[2] * 0.55 * lift, c[3] * 0.55 * lift, alpha)
end

local function SilverAt(f)
    f = Clamp01(f)
    return SILVER_TOP[1] + (SILVER_BOTTOM[1] - SILVER_TOP[1]) * f,
           SILVER_TOP[2] + (SILVER_BOTTOM[2] - SILVER_TOP[2]) * f,
           SILVER_TOP[3] + (SILVER_BOTTOM[3] - SILVER_TOP[3]) * f
end

---------------------------------------------------------------------------
-- A bar: track, fill, shield segment, gradient shade, cylinder bands, text
---------------------------------------------------------------------------
local function MakeBar(parent)
    local b = WM:CreateControl(nil, parent, CT_CONTROL)

    b.track = Tex(b, 1)
    b.track:SetAnchorFill(b)

    b.fill = Tex(b, 2)
    b.fill:SetAnchor(TOPLEFT, b, TOPLEFT, 0, 0)
    b.fill:SetAnchor(BOTTOMLEFT, b, BOTTOMLEFT, 0, 0)

    -- lighter segment after the fill (ESO's damage shield, drawn like WoW's incoming heal)
    b.extra = Tex(b, 3)
    b.extra:SetAnchor(TOPLEFT, b.fill, TOPRIGHT, 0, 0)
    b.extra:SetAnchor(BOTTOMLEFT, b.fill, BOTTOMRIGHT, 0, 0)
    b.extra:SetHidden(true)

    -- shading follows the fill as it grows and shrinks
    b.shade = Tex(b, 4)
    b.shade:SetAnchorFill(b.fill)

    b.cyl = {}
    for i = 1, #CYL - 1 do b.cyl[i] = Tex(b, 5) end

    b.left = WM:CreateControl(nil, b, CT_LABEL)
    b.left:SetAnchor(LEFT, b, LEFT, 3, 0)
    b.left:SetColor(1, 1, 1, 1)
    b.left:SetDrawLevel(7)

    b.right = WM:CreateControl(nil, b, CT_LABEL)
    b.right:SetAnchor(RIGHT, b, RIGHT, -3, 0)
    b.right:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    b.right:SetColor(1, 1, 1, 1)
    b.right:SetDrawLevel(7)

    b.pct = 0
    return b
end

local function SetBarFill(b, pct)
    b.pct = Clamp01(pct or 0)
    local w = (b.w or 0) * b.pct
    b.fill:SetWidth(math.max(w, 0.01))
    b.fill:SetHidden(w < 0.5)
    -- the shading bands sit on the fill
    for _, t in ipairs(b.cyl) do t:SetWidth(math.max(w, 0.01)) end
end

local function SetBarColor(b, c)
    b.color = c
    Gradient(b.fill, c)
end

-- the resource display's settings: track opacity, gradient and cylinder strength
local function StyleBar(b, db)
    Gradient(b.track, { 0.25, 0.25, 0.25 }, 0.5, Clamp01(db.alpha))   -- the dark track

    local g = math.max(0, math.min(GRADIENT_MAX, db.gradient or 0))
    HGrad(b.shade, 0, 0, 0, g, 0, 0, 0, 0)
    b.shade:SetHidden(g <= 0)

    local c = math.max(0, math.min(CYLINDER_MAX, db.cylinder or 0))
    for i, t in ipairs(b.cyl) do
        local y0, a0 = CYL[i][1], CYL[i][2]
        local y1, a1 = CYL[i + 1][1], CYL[i + 1][2]
        t:ClearAnchors()
        t:SetAnchor(TOPLEFT, b, TOPLEFT, 0, b.h * y0)
        t:SetHeight(math.max(0.01, b.h * (y1 - y0)))
        VGrad(t, 0, 0, 0, a0 * c, 0, 0, 0, a1 * c)
        t:SetHidden(c <= 0)
    end
end

-- condensed numbers with a drop shadow (no outline), sized from the bar
local function BarFonts(b)
    local size = math.max(8, math.floor(b.h * 0.68 + 0.5))
    local font = "$(MEDIUM_FONT)|" .. size .. "|soft-shadow-thin"
    b.left:SetFont(font)
    b.right:SetFont(font)
end

---------------------------------------------------------------------------
-- The block
---------------------------------------------------------------------------
function R:Build()
    local db = self.db

    local root = WM:CreateTopLevelWindow(NS)
    root:SetClampedToScreen(true)
    root:SetMouseEnabled(false)
    root:SetMovable(false)
    -- dragged box by box (Layout puts it on the grid every frame)
    local drag
    SKT.Grid.Draggable(root, {
        start = function() drag = { x = db.x or 0, y = db.y or 136 } end,
        move = function(dx, dy)
            db.x, db.y = drag.x + dx, drag.y + dy
            self:Layout()
            if SKT.Skills and SKT.Skills.root then SKT.Skills:Layout() end
        end,
        stop = function()
            -- keep the place it shows (on the grid)
            local G = SKT.Grid
            local fullW = OnPx(G.Boxes(db.width))
            db.x = G.SnapOne(db.x - fullW / 2) + fullW / 2
            db.y = G.SnapOne(db.y)
            self:Layout()
        end,
    })
    self.root = root

    local body = WM:CreateControl("$(parent)Body", root, CT_CONTROL)
    body:SetAnchorFill(root)
    self.body = body

    self.bars = {}
    for i, def in ipairs(BARS) do
        local b = MakeBar(body)
        b.def = def
        b.cur, b.max = 0, 1
        self.bars[i] = b
        self.bars[def.key] = b
    end
    self.castBar = MakeBar(body)

    -- seams between bars and the silver ring round the block
    self.seams = {}
    for i = 1, 3 do self.seams[i] = Tex(body, 8) end
    self.ring = { edges = {}, dots = {} }
    for i = 1, 4 do self.ring.edges[i] = Tex(body, 9) end
    for i = 1, 4 do self.ring.dots[i] = Tex(body, 9) end

    -- shown while unlocked
    local mover = WM:CreateControl("$(parent)Mover", root, CT_BACKDROP)
    mover:SetCenterColor(0.16, 0.22, 0.38, 0.35)
    mover:SetEdgeColor(SKT.col(SKT.colors.title))
    mover:SetEdgeTexture("", 1, 1, 1, 0)
    mover:SetAnchor(TOPLEFT, root, TOPLEFT, -6, -22)
    mover:SetAnchor(BOTTOMRIGHT, root, BOTTOMRIGHT, 6, 6)
    mover:SetDrawLevel(10)
    local mt = SKT.MakeLabel("$(parent)Text", mover, "SKTools: health, magicka, stamina, cast bar",
        "ZoFontGameSmall", SKT.colors.title)
    mt:SetAnchor(TOP, mover, TOP, 0, 3)
    self.mover = mover

    self.fragment = ZO_HUDFadeSceneFragment:New(root)
end

-- a frame line round the box, a pixel outside it, rounded corners, silver shaded top to bottom
function R:DrawRing(w, h)
    local t = Px()
    local X0, Y0 = -t, -t
    local W, H = w + 2 * t, h + 2 * t
    local function At(y) return SilverAt(H > 0 and (y - Y0) / H or 0) end
    local e, d = self.ring.edges, self.ring.dots
    local C = 2 * t    -- each line stops two pixels short of the corner; one pixel set in diagonally

    local function Place(tex, x, y, tw, th)
        tex:ClearAnchors()
        tex:SetAnchor(TOPLEFT, self.body, TOPLEFT, x, y)
        tex:SetDimensions(math.max(0.01, tw), math.max(0.01, th))
    end

    -- top, bottom
    Place(e[1], X0 + C, Y0, W - 2 * C, t)
    local r, g, b = At(Y0); VGrad(e[1], r, g, b, 1, r, g, b, 1)
    Place(e[2], X0 + C, Y0 + H - t, W - 2 * C, t)
    r, g, b = At(Y0 + H); VGrad(e[2], r, g, b, 1, r, g, b, 1)
    -- left, right: shaded down their length
    local r0, g0, b0 = At(Y0 + C)
    local r1, g1, b1 = At(Y0 + H - C)
    Place(e[3], X0, Y0 + C, t, H - 2 * C)
    VGrad(e[3], r0, g0, b0, 1, r1, g1, b1, 1)
    Place(e[4], X0 + W - t, Y0 + C, t, H - 2 * C)
    VGrad(e[4], r0, g0, b0, 1, r1, g1, b1, 1)
    -- the rounded corners: one pixel on the diagonal
    local spots = {
        { X0 + t, Y0 + t }, { X0 + W - 2 * t, Y0 + t },
        { X0 + t, Y0 + H - 2 * t }, { X0 + W - 2 * t, Y0 + H - 2 * t },
    }
    for i, s in ipairs(spots) do
        Place(d[i], s[1], s[2], t, t)
        local cr, cg, cb = At(s[2])
        VGrad(d[i], cr, cg, cb, 1, cr, cg, cb, 1)
    end
end

function R:Layout()
    if not self.root then return end
    local db = self.db
    local G = SKT.Grid
    local px = Px()
    -- while snapping: sizes in whole grid boxes, the far sides a pixel in (their frame lines on grid lines)
    local trim = G.Trim()
    local fullW = OnPx(G.Boxes(db.width))
    local w = fullW - trim

    -- which strips show: health, magicka, stamina, and the cast bar only while channelling (or unlocked)
    local strips = { self.bars[1], self.bars[2], self.bars[3] }
    local showCast = db.castEnabled and (self.cast.active or not db.locked)
    if showCast then strips[4] = self.castBar end
    self.castBar:SetHidden(not showCast)

    local y = 0
    for i, b in ipairs(strips) do
        local h = OnPx(G.Boxes((b == self.castBar) and db.castHeight or db[b.def.size]))
        if i == #strips then h = h - trim end
        b:ClearAnchors()
        b:SetAnchor(TOPLEFT, self.body, TOPLEFT, 0, y)
        b:SetDimensions(w, h)
        b.w, b.h = w, h
        StyleBar(b, db)
        BarFonts(b)
        SetBarFill(b, b.pct)
        -- a fine dark seam between this bar and the one above
        if i > 1 then
            local s = self.seams[i - 1]
            s:ClearAnchors()
            s:SetAnchor(TOPLEFT, self.body, TOPLEFT, 0, y)
            s:SetDimensions(w, px)
            VGrad(s, 0, 0, 0, 0.6, 0, 0, 0, 0.6)
            s:SetHidden(false)
        end
        y = y + h
    end
    for i = #strips, 3 do self.seams[i]:SetHidden(true) end

    self.root:SetDimensions(w, y)
    self:DrawRing(w, y)

    -- placed by its top (the bars grow down), centred on x; both from the middle of the screen and,
    -- while snapping, on grid lines
    local left = G.SnapOne((db.x or 0) - fullW / 2)
    local top = G.SnapOne(db.y or 136)
    self.root:ClearAnchors()
    self.root:SetAnchor(TOPLEFT, GuiRoot, CENTER, OnPx(left), OnPx(top))
end

function R:Color(key)
    local c = self.db.colors and self.db.colors[key]
    if type(c) == "table" and c.r then return { c.r, c.g, c.b } end
    return COLORS[key]
end

-- full restyle (colours, sizes) and refresh
function R:ApplyLayout()
    if not self.root then return end
    for _, b in ipairs(self.bars) do SetBarColor(b, self:Color(b.def.key)) end
    if not self.cast.interrupted then SetBarColor(self.castBar, self:Color("cast")) end
    self:Layout()
    self:RefreshAll()
end

---------------------------------------------------------------------------
-- Values
---------------------------------------------------------------------------
function R:UpdateBar(b, cur, max)
    b.cur, b.max = cur or 0, (max and max > 0) and max or 1
    SetBarFill(b, b.cur / b.max)
    b.left:SetText(zo_round(b.cur / b.max * 100) .. "%")
    b.right:SetText(tostring(zo_round(b.cur)))
    if b == self.bars.health then self:UpdateShield() end
end

-- damage shield: a lighter segment where the health fill ends, as long as the shield, cut off at the bar's end
function R:UpdateShield()
    local hp = self.bars.health
    local v = self.db.showShield and (self.shield or 0) or 0
    if v <= 0 or not hp.w then hp.extra:SetHidden(true) return end
    local room = math.max(0, hp.max - hp.cur)
    local w = hp.w * math.min(v, room) / hp.max
    if w < 0.5 then hp.extra:SetHidden(true) return end
    local c = hp.color or COLORS.health
    local light = { c[1] * 0.45 + 0.55, c[2] * 0.45 + 0.55, c[3] * 0.45 + 0.55 }
    Gradient(hp.extra, light, 1, 0.75)
    hp.extra:SetWidth(w)
    hp.extra:SetHidden(false)
end

function R:QueryShield()
    local ok, value = pcall(GetUnitAttributeVisualizerEffectInfo, "player",
        ATTRIBUTE_VISUAL_POWER_SHIELDING, STAT_MITIGATION, ATTRIBUTE_HEALTH, BARS[1].power)
    self.shield = (ok and value) or 0
end

function R:RefreshAll()
    if not self.bars then return end
    for _, b in ipairs(self.bars) do
        local cur, max = GetUnitPower("player", b.def.power)
        self:UpdateBar(b, cur, max)
    end
    self:CastPreview()
    self:UpdateIdle()
end

---------------------------------------------------------------------------
-- The cast bar: channels drain, cast times fill (as in WoW)
---------------------------------------------------------------------------
R.cast = { active = false }

function R:CastPreview()
    if self.cast.active or self.db.locked then return end
    SetBarColor(self.castBar, self:Color("cast"))
    self.castBar.left:SetText("Cast bar")
    self.castBar.right:SetText("")
    SetBarFill(self.castBar, 0.6)
end

function R:StartCast(name, duration, isChannel)
    local c = self.cast
    c.active, c.interrupted = true, false
    c.channel = isChannel
    c.start = GetFrameTimeSeconds()
    c.stop = c.start + duration
    c.fadeAt = nil
    SetBarColor(self.castBar, self:Color("cast"))
    self.castBar.left:SetText(zo_strformat("<<1>>", name or ""))
    self:Layout()
    self:CastTick()
    self:UpdateIdle()
    EM:RegisterForUpdate(NS .. "Cast", 0, function() self:CastTick() end)
end

function R:StopCast(interrupted)
    local c = self.cast
    if not c.active then return end
    if interrupted and not c.interrupted then
        c.interrupted = true
        SetBarColor(self.castBar, COLORS.range)
        SetBarFill(self.castBar, 1)
        self.castBar.right:SetText("Interrupted")
        c.fadeAt = GetFrameTimeSeconds() + 0.7
        return
    end
    c.active, c.interrupted, c.fadeAt = false, false, nil
    EM:UnregisterForUpdate(NS .. "Cast")
    SetBarColor(self.castBar, self:Color("cast"))
    self:Layout()
    self:CastPreview()
    self:UpdateIdle()
end

-- worked out afresh every frame (smooth at any frame rate)
function R:CastTick()
    local c = self.cast
    local now = GetFrameTimeSeconds()
    if c.fadeAt then
        if now >= c.fadeAt then self:StopCast(false) end
        return
    end
    if now >= c.stop then self:StopCast(false) return end
    local f = (now - c.start) / (c.stop - c.start)
    if c.channel then f = 1 - f end
    SetBarFill(self.castBar, f)
    self.castBar.right:SetText(string.format("%.1f", math.max(0, c.stop - now)))
end

local function OnCastBegin(_, result, isError, abilityName, _, _, _, _, _, _, hitValue,
                           _, _, _, _, _, abilityId)
    local db = R.db
    if not db.enabled or not db.castEnabled or isError then return end

    local channeled, castTime, channelTime = GetAbilityCastInfo(abilityId)
    local isChannel = (result == ACTION_RESULT_BEGIN_CHANNEL) or channeled
    if not isChannel and not db.castShowCastTime then return end

    local ms = hitValue
    if not ms or ms <= 0 then ms = isChannel and channelTime or castTime end
    if not ms or ms < 250 then return end   -- instants

    local name = (abilityName and abilityName ~= "") and abilityName or GetAbilityName(abilityId)
    R:StartCast(name, ms / 1000, isChannel)
end

local function OnInterrupted()
    if R.cast.active then R:StopCast(true) end
end

---------------------------------------------------------------------------
-- Visibility
---------------------------------------------------------------------------
function R:UpdateIdle()
    if not self.body then return end
    local db = self.db
    if not db.locked or not db.hideWhenIdle then self.body:SetAlpha(1) return end
    local busy = IsUnitInCombat("player") or self.cast.active
    if not busy then
        for _, b in ipairs(self.bars) do
            if b.cur < b.max then busy = true break end
        end
    end
    self.body:SetAlpha(busy and 1 or 0)
end

function R:ApplyLock()
    local locked = self.db.locked
    self.root:SetMouseEnabled(not locked)
    self.mover:SetHidden(locked)
    self:Layout()
    self:CastPreview()
    self:UpdateIdle()
    SKT.Grid:Update()
    if SKT.Skills and SKT.Skills.root then SKT.Skills:Layout() end
end

-- ESO's own attribute bars
function R:ApplyDefaultBars()
    local frag = PLAYER_ATTRIBUTE_BARS_FRAGMENT
    if not frag then return end
    local hide = self.db.enabled and self.db.hideDefault
    if hide and not self.defaultHidden then
        HUD_SCENE:RemoveFragment(frag)
        HUD_UI_SCENE:RemoveFragment(frag)
        if ZO_PlayerAttribute then ZO_PlayerAttribute:SetHidden(true) end
        self.defaultHidden = true
    elseif not hide and self.defaultHidden then
        HUD_SCENE:AddFragment(frag)
        HUD_UI_SCENE:AddFragment(frag)
        if ZO_PlayerAttribute then ZO_PlayerAttribute:SetHidden(false) end
        self.defaultHidden = false
    end
end

function R:ApplyEnabled()
    local on = self.db.enabled
    if on and not self.fragmentAdded then
        HUD_SCENE:AddFragment(self.fragment)
        HUD_UI_SCENE:AddFragment(self.fragment)
        self.fragmentAdded = true
    elseif not on and self.fragmentAdded then
        HUD_SCENE:RemoveFragment(self.fragment)
        HUD_UI_SCENE:RemoveFragment(self.fragment)
        self.fragmentAdded = false
        self.root:SetHidden(true)
    end
    self:ApplyDefaultBars()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function R:RegisterEvents()
    EM:RegisterForEvent(NS, EVENT_POWER_UPDATE, function(_, _, _, powerType, value, max)
        for _, b in ipairs(self.bars) do
            if b.def.power == powerType then self:UpdateBar(b, value, max) break end
        end
        self:UpdateIdle()
    end)
    EM:AddFilterForEvent(NS, EVENT_POWER_UPDATE, REGISTER_FILTER_UNIT_TAG, "player")

    local function OnShield()
        self:QueryShield()
        self:UpdateShield()
    end
    for i, ev in ipairs({ EVENT_UNIT_ATTRIBUTE_VISUAL_ADDED, EVENT_UNIT_ATTRIBUTE_VISUAL_UPDATED,
                          EVENT_UNIT_ATTRIBUTE_VISUAL_REMOVED }) do
        EM:RegisterForEvent(NS .. "Shield" .. i, ev, OnShield)
        EM:AddFilterForEvent(NS .. "Shield" .. i, ev, REGISTER_FILTER_UNIT_TAG, "player")
    end

    EM:RegisterForEvent(NS, EVENT_PLAYER_COMBAT_STATE, function() self:UpdateIdle() end)
    EM:RegisterForEvent(NS, EVENT_PLAYER_ACTIVATED, function()
        self:ApplyDefaultBars()
        self:QueryShield()
        self:ApplyLayout()
    end)
    -- UI scale changes move the pixel grid
    EM:RegisterForEvent(NS, EVENT_ALL_GUI_SCREENS_RESIZED, function() self:ApplyLayout() end)

    for _, result in ipairs({ ACTION_RESULT_BEGIN_CHANNEL, ACTION_RESULT_BEGIN }) do
        local id = NS .. "CastBegin" .. result
        EM:RegisterForEvent(id, EVENT_COMBAT_EVENT, OnCastBegin)
        EM:AddFilterForEvent(id, EVENT_COMBAT_EVENT,
            REGISTER_FILTER_COMBAT_RESULT, result,
            REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER)
    end

    for _, result in ipairs({ ACTION_RESULT_INTERRUPT, ACTION_RESULT_STUNNED, ACTION_RESULT_KNOCKBACK,
                              ACTION_RESULT_FEARED, ACTION_RESULT_STAGGERED }) do
        if result then
            local id = NS .. "CastStop" .. result
            EM:RegisterForEvent(id, EVENT_COMBAT_EVENT, OnInterrupted)
            EM:AddFilterForEvent(id, EVENT_COMBAT_EVENT,
                REGISTER_FILTER_COMBAT_RESULT, result,
                REGISTER_FILTER_TARGET_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER)
        end
    end

    EM:RegisterForEvent(NS, EVENT_ACTIVE_WEAPON_PAIR_CHANGED, function()
        if self.cast.active then self:StopCast(false) end
    end)
end

---------------------------------------------------------------------------
-- Settings tab
---------------------------------------------------------------------------
local COLOR_ROWS = {
    { key = "health",  label = "Health" },
    { key = "magicka", label = "Magicka" },
    { key = "stamina", label = "Stamina" },
    { key = "cast",    label = "Cast bar" },
}

local function NoneOrPercent(v) return v <= 0 and "none" or (v .. "%") end

-- a colour row: label, a swatch previewing the gradient and shading, and a reset button
local function ColorRow(page, db, row, x, y)
    local base = page:GetName() .. "Color" .. row.key
    local label = SKT.MakeLabel(base .. "Label", page, row.label, "ZoFontGame", SKT.colors.text)
    label:SetAnchor(TOPLEFT, page, TOPLEFT, x, y + 2)

    local sw = WM:CreateControl(base, page, CT_CONTROL)
    sw:SetDimensions(110, 16)
    sw:SetAnchor(TOPLEFT, page, TOPLEFT, x + 90, y + 4)
    sw:SetMouseEnabled(true)
    local fill = Tex(sw, 1); fill:SetAnchorFill(sw)
    local shade = Tex(sw, 2); shade:SetAnchorFill(sw)
    local cylA, cylB = Tex(sw, 3), Tex(sw, 3)
    cylA:SetAnchor(TOPLEFT, sw, TOPLEFT, 0, 0); cylA:SetAnchor(BOTTOMRIGHT, sw, RIGHT, 0, 0)
    cylB:SetAnchor(TOPLEFT, sw, LEFT, 0, 0);    cylB:SetAnchor(BOTTOMRIGHT, sw, BOTTOMRIGHT, 0, 0)
    local edge = WM:CreateControl(base .. "Edge", sw, CT_BACKDROP)
    edge:SetAnchorFill(sw)
    edge:SetCenterColor(0, 0, 0, 0)
    edge:SetEdgeColor(SILVER_TOP[1], SILVER_TOP[2], SILVER_TOP[3], 1)
    edge:SetEdgeTexture("", 1, 1, 1, 0)
    edge:SetDrawLevel(4)

    local reset = WM:CreateControlFromVirtual(base .. "Reset", page, "ZO_DefaultButton")
    reset:SetWidth(80)
    reset:SetText("Reset")
    reset:SetAnchor(LEFT, sw, RIGHT, 8, 0)

    local function Paint()
        Gradient(fill, R:Color(row.key))
        local g = math.max(0, math.min(GRADIENT_MAX, db.gradient or 0))
        HGrad(shade, 0, 0, 0, g, 0, 0, 0, 0); shade:SetHidden(g <= 0)
        local c = math.max(0, math.min(CYLINDER_MAX, db.cylinder or 0))
        VGrad(cylA, 0, 0, 0, 0.824 * c, 0, 0, 0, 0)
        VGrad(cylB, 0, 0, 0, 0, 0, 0, 0, 0.824 * c)
        cylA:SetHidden(c <= 0); cylB:SetHidden(c <= 0)
        reset:SetEnabled(db.colors[row.key] ~= nil)
    end

    sw:SetHandler("OnMouseUp", function(_, button, upInside)
        if not upInside or button ~= MOUSE_BUTTON_INDEX_LEFT then return end
        local c = R:Color(row.key)
        COLOR_PICKER:Show(function(r, g, b)
            db.colors[row.key] = { r = r, g = g, b = b }
            R:ApplyLayout(); Paint()
        end, c[1], c[2], c[3], 1, row.label)
    end)
    reset:SetHandler("OnClicked", function()
        db.colors[row.key] = nil
        R:ApplyLayout(); Paint()
    end)

    Paint()
    return Paint
end

SKT:RegisterModule({
    key   = "Resources",
    title = "Resources",
    order = 10,

    defaults = {
        enabled      = true,
        locked       = true,
        hideDefault  = true,      -- ESO's own resource bars off while the block shows
        hideWhenIdle = false,
        showShield   = true,
        castEnabled  = true,
        castShowCastTime = false,
        -- x, y: the block's top centre from the middle of the screen
        x = 0, y = 136,
        width = 224, health = 16, power = 8, castHeight = 16,
        -- the resource display's look (as in WoW)
        alpha = 1, gradient = 0, cylinder = 0,
        colors = {},
    },

    OnLoad = function(self, db)
        R.db = db
        db.colors = db.colors or {}
        -- 0.2.x stored the position as a top-left corner: start from the default place instead
        if db.layoutVersion ~= 3 then db.x, db.y, db.layoutVersion = 0, 136, 3 end
        -- settings saved by older versions in another form (0.2.x had cylinder = true/false)
        local NUM = { x = 0, y = 136, width = 224, health = 16, power = 8, castHeight = 16,
                      alpha = 1, gradient = 0, cylinder = 0 }
        for k, v in pairs(NUM) do
            if type(db[k]) ~= "number" then db[k] = v end
        end
        if type(db.colors) ~= "table" then db.colors = {} end
        R:Build()
        R:RegisterEvents()
        R:ApplyLayout()
        R:ApplyLock()
        R:ApplyEnabled()
    end,

    BuildTab = function(self, page, db)
        local UI = SKT.UI
        local L, RX, CW = 16, 316, 260
        local painters = {}
        local function relayout() R:ApplyLayout() end
        local function repaint() relayout(); for _, p in ipairs(painters) do p() end end

        -- left: the block
        UI.Header(page, "HeadBlock", L, 12, "Resource bars")

        UI.Checkbox(page, "Enabled", L, 48, "Enable",
            function() return db.enabled end,
            function(v) db.enabled = v; R:ApplyEnabled() end)
        UI.Checkbox(page, "Locked", L, 74, "Lock position",
            function() return db.locked end,
            function(v) db.locked = v; R:ApplyLock() end,
            "Untick to drag the block. The cast bar shows while unlocked.")
        UI.Checkbox(page, "HideDefault", L, 100, "Hide ESO's own resource bars",
            function() return db.hideDefault end,
            function(v) db.hideDefault = v; R:ApplyDefaultBars() end)
        UI.Checkbox(page, "Idle", L, 126, "Hide when full and out of combat",
            function() return db.hideWhenIdle end,
            function(v) db.hideWhenIdle = v; R:UpdateIdle() end)
        UI.Checkbox(page, "Shield", L, 152, "Show damage shields",
            function() return db.showShield end,
            function(v) db.showShield = v; R:UpdateShield() end,
            "A lighter segment after the health fill, as long as the shield.")
        UI.Checkbox(page, "Cast", L, 178, "Cast bar for channelled abilities",
            function() return db.castEnabled end,
            function(v) db.castEnabled = v; relayout() end)
        UI.Checkbox(page, "CastTime", L, 204, "Also show cast-time abilities",
            function() return db.castShowCastTime end,
            function(v) db.castShowCastTime = v end,
            "Channels drain, casts fill up.")

        UI.Slider(page, "Width", L, 240, CW, "Width", 120, 480, 4,
            function() return db.width end, function(v) db.width = v; relayout() end,
            SKT.Grid.Fmt)
        UI.Slider(page, "Health", L, 284, CW, "Health height", 6, 40, 1,
            function() return db.health end, function(v) db.health = v; relayout() end,
            SKT.Grid.Fmt)
        UI.Slider(page, "Power", L, 328, CW, "Magicka / stamina height", 4, 30, 1,
            function() return db.power end, function(v) db.power = v; relayout() end,
            SKT.Grid.Fmt)
        UI.Slider(page, "CastH", L, 372, CW, "Cast bar height", 6, 36, 1,
            function() return db.castHeight end, function(v) db.castHeight = v; relayout() end,
            SKT.Grid.Fmt)
        UI.Button(page, "ResetPos", L, 420, "Reset position", 180, function()
            db.x, db.y = 0, 136
            relayout()
        end)

        -- right: the look (same options as WoW's resource display page)
        UI.Header(page, "HeadLook", RX, 12, "Look")
        UI.Slider(page, "Alpha", RX, 48, CW, "Track opacity", 0, 100, 5,
            function() return zo_round((db.alpha or 1) * 100) end,
            function(v) db.alpha = v / 100; relayout() end,
            function(v) return v .. "%" end)
        UI.Slider(page, "Gradient", RX, 92, CW, "Bar gradient (darker on the left)", 0, 100, 5,
            function() return zo_round(math.min((db.gradient or 0) / GRADIENT_MAX, 1) * 100) end,
            function(v) db.gradient = v / 100 * GRADIENT_MAX; repaint() end, NoneOrPercent)
        UI.Slider(page, "Cylinder", RX, 136, CW, "Cylinder shading (top / bottom)", 0, 100, 5,
            function() return zo_round(math.min((db.cylinder or 0) / CYLINDER_MAX, 1) * 100) end,
            function(v) db.cylinder = v / 100 * CYLINDER_MAX; repaint() end, NoneOrPercent)

        UI.Header(page, "HeadColors", RX, 184, "Bar colours")
        for i, row in ipairs(COLOR_ROWS) do
            painters[#painters + 1] = ColorRow(page, db, row, RX, 216 + (i - 1) * 32)
        end
        UI.Text(page, "ColorNote", RX, 216 + #COLOR_ROWS * 32 + 6,
            "Click a colour to change it. The swatch previews the gradient and cylinder shading.", CW)
    end,
})
