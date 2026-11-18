--[[-------------------------------------------------------------------------
  SKTools-ESO by Scotskoogen-Chris
  Snap to grid, as in SKTools for WoW Forever.

  While any element is unlocked a faint grid covers the screen, its bright
  lines crossing at the middle of the screen. A dropped element's place is
  rounded to the nearest grid point (measured from the middle of the
  screen), and its sizes are taken in whole grid boxes. Its far frame lines
  are a pixel in, so every frame line lands on a grid line.
---------------------------------------------------------------------------]]

local SKT = SKT
local D   = SKT.Draw
local WM  = WINDOW_MANAGER
local G = {}
SKT.Grid = G

function G.On()   return SKT.db ~= nil and SKT.db.snap ~= false end
function G.Size() return math.max(2, (SKT.db and SKT.db.grid) or 8) end

-- an offset from the middle of the screen, put on the nearest grid line
function G.SnapOne(v)
    if not G.On() then return v end
    local g = G.Size()
    return zo_round(v / g) * g
end

-- a size in whole grid boxes (at least one, unless zero is allowed)
function G.Boxes(v, allowZero)
    if not G.On() then return v end
    local g = G.Size()
    local n = zo_round(v / g)
    if not allowZero then n = math.max(1, n) end
    return n * g
end

-- the pixel taken off an element's far sides while snapping, so its far frame lines land on grid lines
function G.Trim() return G.On() and D.Px() or 0 end

-- slider text: the size actually used
function G.Fmt(v)
    if G.On() then return G.Boxes(v, true) .. " px (" .. zo_round(G.Boxes(v, true) / G.Size()) .. " boxes)" end
    return v .. " px"
end

local function AnyUnlocked()
    for _, m in ipairs({ SKT.Resources, SKT.Skills }) do
        if m and m.db and m.db.enabled and not m.db.locked then return true end
    end
    return false
end

-- (re)draw the grid lines; each line a screen pixel wide, ending at its grid position, where a frame
-- line just outside an element's edge falls
local function Draw(self)
    local g, px = G.Size(), D.Px()
    local W, H = GuiRoot:GetWidth(), GuiRoot:GetHeight()
    if self.size == g and self.px == px and self.w == W and self.h == H then return end
    self.size, self.px, self.w, self.h = g, px, W, H

    local n = 0
    local function Line(vertical, off)
        n = n + 1
        local t = self.lines[n]
        if not t then t = D.Tex(self.win, 1); self.lines[n] = t end
        t:ClearAnchors()
        local centre = math.abs(off) < 0.5
        local major = (zo_round(off / g) % 8 == 0)
        if centre then D.Solid(t, 1, 0.85, 0.3, 0.5)
        else D.Solid(t, 0.6, 0.8, 1, major and 0.22 or 0.09) end
        if vertical then
            t:SetAnchor(TOPLEFT, self.win, TOP, off - px, 0); t:SetDimensions(px, H)
        else
            t:SetAnchor(TOPLEFT, self.win, LEFT, 0, off - px); t:SetDimensions(W, px)
        end
        t:SetHidden(false)
    end
    for x = 0, W / 2, g do Line(true, x); if x > 0 then Line(true, -x) end end
    for y = 0, H / 2, g do Line(false, y); if y > 0 then Line(false, -y) end end
    for i = n + 1, #self.lines do self.lines[i]:SetHidden(true) end
end

function G:Update(force)
    local show = G.On() and AnyUnlocked()
    if not show then
        if self.win then self.win:SetHidden(true) end
        return
    end
    if not self.win then
        self.win = WM:CreateTopLevelWindow("SKToolsESO_Grid")
        self.win:SetAnchorFill(GuiRoot)
        self.win:SetDrawLayer(DL_BACKGROUND)
        self.win:SetDrawTier(DT_LOW)
        self.win:SetMouseEnabled(false)
        self.lines = {}
        EVENT_MANAGER:RegisterForEvent("SKToolsESO_Grid", EVENT_ALL_GUI_SCREENS_RESIZED, function()
            if not self.win:IsHidden() then self.size = nil; Draw(self) end
        end)
    end
    if force then self.size = nil end
    Draw(self)
    self.win:SetHidden(false)
end

-- Drag an element box by box, as in WoW: it follows the cursor in grid steps, so where it shows while
-- dragging is where it stays. opts.start() (once, at mouse down), opts.move(dx, dy) (cursor offset from
-- where the drag began, every frame), opts.stop() (at mouse up).
function G.Draggable(ctrl, opts)
    ctrl:SetHandler("OnMouseDown", function(c, button)
        if button ~= MOUSE_BUTTON_INDEX_LEFT then return end
        local mx, my = GetUIMousePosition()
        if opts.start then opts.start() end
        c:SetHandler("OnUpdate", function()
            local x, y = GetUIMousePosition()
            opts.move(x - mx, y - my)
        end)
    end)
    ctrl:SetHandler("OnMouseUp", function(c, button)
        if button ~= MOUSE_BUTTON_INDEX_LEFT then return end
        c:SetHandler("OnUpdate", nil)
        if opts.stop then opts.stop() end
    end)
end

-- an element's place from the middle of the screen: left, top, right, bottom
function G.Rect(ctrl)
    local cx, cy = GuiRoot:GetWidth() / 2, GuiRoot:GetHeight() / 2
    return ctrl:GetLeft() - cx, ctrl:GetTop() - cy, ctrl:GetRight() - cx, ctrl:GetBottom() - cy
end
