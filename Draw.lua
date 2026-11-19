-- SKTools-ESO by Scotskoogen-Chris
-- Draw: shared drawing helpers (no image files; everything is drawn with vertex colours).

local SKT = SKT
local WM = WINDOW_MANAGER
local D = {}
SKT.Draw = D

function D.Clamp01(v) return math.max(0, math.min(1, v)) end

-- one screen pixel in UI units, and a value put on whole pixels
function D.Px()
    local s = (GetUIGlobalScale and GetUIGlobalScale()) or 1
    return (s > 0) and (1 / s) or 1
end
function D.OnPx(v)
    local px = D.Px()
    return zo_round(v / px) * px
end

function D.Tex(parent, level)
    local t = WM:CreateControl(nil, parent, CT_TEXTURE)
    t:SetColor(1, 1, 1, 1)
    t:SetDrawLevel(level or 1)
    return t
end

function D.VGrad(t, r1, g1, b1, a1, r2, g2, b2, a2)
    t:SetVertexColors(VERTEX_POINTS_TOPLEFT,     r1, g1, b1, a1)
    t:SetVertexColors(VERTEX_POINTS_TOPRIGHT,    r1, g1, b1, a1)
    t:SetVertexColors(VERTEX_POINTS_BOTTOMLEFT,  r2, g2, b2, a2)
    t:SetVertexColors(VERTEX_POINTS_BOTTOMRIGHT, r2, g2, b2, a2)
end

-- a flat colour held by the control's own colour (white vertices), for fills whose opacity is a
-- setting: it keeps through the HUD's scene changes
function D.Fill(t, r, g, b, a)
    D.VGrad(t, 1, 1, 1, 1, 1, 1, 1, 1)
    t:SetColor(r, g, b, a or 1)
end

function D.Solid(t, r, g, b, a)
    D.VGrad(t, r, g, b, a or 1, r, g, b, a or 1)
end

-- a thin frame round a box, a pixel outside it, rounded corners (one pixel set in on the diagonal).
-- colorAt(f) gives r, g, b for f = 0 (top) .. 1 (bottom).
function D.NewRing(parent, level)
    local r = { edges = {}, dots = {} }
    for i = 1, 4 do r.edges[i] = D.Tex(parent, level) end
    for i = 1, 4 do r.dots[i] = D.Tex(parent, level) end
    return r
end

function D.DrawRing(ring, anchor, x, y, w, h, colorAt)
    local t = D.Px()
    local X0, Y0 = x - t, y - t
    local W, H = w + 2 * t, h + 2 * t
    local function At(yy) return colorAt(H > 0 and D.Clamp01((yy - Y0) / H) or 0) end
    local C = 2 * t
    local e, d = ring.edges, ring.dots

    local function Place(tex, px, py, tw, th)
        tex:ClearAnchors()
        tex:SetAnchor(TOPLEFT, anchor, TOPLEFT, px, py)
        tex:SetDimensions(math.max(0.01, tw), math.max(0.01, th))
        tex:SetHidden(false)
    end

    Place(e[1], X0 + C, Y0, W - 2 * C, t)
    D.Solid(e[1], At(Y0))
    Place(e[2], X0 + C, Y0 + H - t, W - 2 * C, t)
    D.Solid(e[2], At(Y0 + H))
    local r0, g0, b0 = At(Y0 + C)
    local r1, g1, b1 = At(Y0 + H - C)
    Place(e[3], X0, Y0 + C, t, H - 2 * C)
    D.VGrad(e[3], r0, g0, b0, 1, r1, g1, b1, 1)
    Place(e[4], X0 + W - t, Y0 + C, t, H - 2 * C)
    D.VGrad(e[4], r0, g0, b0, 1, r1, g1, b1, 1)
    local spots = {
        { X0 + t, Y0 + t }, { X0 + W - 2 * t, Y0 + t },
        { X0 + t, Y0 + H - 2 * t }, { X0 + W - 2 * t, Y0 + H - 2 * t },
    }
    for i, s in ipairs(spots) do
        Place(d[i], s[1], s[2], t, t)
        D.Solid(d[i], At(s[2]))
    end
end

function D.White() return 1, 1, 1 end
