--[[-------------------------------------------------------------------------
  SKTools-ESO by Scotskoogen-Chris
  Skills: both skill bars at once, in the style of the WoW Essentials pane.

  Front bar on the left, back bar on the right. Each bar is three columns of
  two rows:

      [2] [4] [ULT]
      [1] [3] [ 5 ]

  Icons sit flush, framed by thin white lines that neighbours share, the
  outer corners rounded. On cooldown: a dark sweep with the time in the
  middle. Short of the cost: the icon greys and a thin frame in the
  resource's colour fills clockwise from 12 o'clock as you build up to it
  (the ultimate fills as your ultimate builds). The bar you are not on is
  dimmed.
---------------------------------------------------------------------------]]

local SKT = SKT
local D   = SKT.Draw
local WM  = WINDOW_MANAGER
local EM  = EVENT_MANAGER

local NS = "SKToolsESO_Skills"
local S = {}
SKT.Skills = S

-- a game function called safely: its results, or nothing if it isn't there or fails
local function Call(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end
S.timers = {}       -- abilityId -> when its effect ends (GetFrameTimeSeconds)
S.slotTimers = {}   -- "bar:slot" -> { ends, id }: a delayed skill's timer, kept on its slot
S.companions = {}   -- abilityIds that stood in for a delayed skill (Budding Seeds' "bloom now")
local function Key(cat, slot) return tostring(cat) .. ":" .. tostring(slot) end

-- skills that heal (or harm) from the cast up to the moment they bloom: the timer runs from the
-- cast to the bloom. The game's effect events for them are ignored: they arrive at the bloom and
-- would start a second, wrong countdown. secs: used only if the game gives no duration.
-- reuseEnds: using it again while it runs blooms it now (Budding Seeds), so the timer clears.
local DELAYED = {
    ["Healing Seed"]      = { secs = 6 },
    ["Budding Seeds"]     = { secs = 6, reuseEnds = true },
    ["Corrupting Pollen"] = { secs = 6 },
    -- two detonations, 3 s apart: the whole 6 s (the game's duration covers only the first)
    ["Subterranean Assault"] = { secs = 6, fixed = true },
}
-- skills whose effect comes and goes in short pulses (the netches: a stronger effect every 5 s):
-- the timer keeps the skill's whole duration from the cast, never shortened by a pulse
local WHOLE = { ["Betty Netch"] = true, ["Blue Betty"] = true, ["Bull Netch"] = true }
local function Whole(id)
    local ok, name = pcall(GetAbilityName, id)
    return ok and name and WHOLE[zo_strformat("<<1>>", name)] or false
end

local function Delayed(id)
    local ok, name = pcall(GetAbilityName, id)
    if not ok or not name or name == "" then return nil end
    return DELAYED[zo_strformat("<<1>>", name)]
end

local FIRST = (ACTION_BAR_FIRST_NORMAL_SLOT_INDEX or 2) + 1     -- slot of skill 1 (3)
local ULT   = (ACTION_BAR_ULTIMATE_SLOT_INDEX or 7) + 1         -- ultimate slot (8)

-- where each slot sits: column 1..3, row 1 = top, 2 = bottom
local LAYOUT = {
    { slot = FIRST,     col = 1, row = 2 },   -- 1
    { slot = FIRST + 1, col = 1, row = 1 },   -- 2
    { slot = FIRST + 2, col = 2, row = 2 },   -- 3
    { slot = FIRST + 3, col = 2, row = 1 },   -- 4
    { slot = FIRST + 4, col = 3, row = 2 },   -- 5
    { slot = ULT,       col = 3, row = 1 },   -- ultimate
}

local BARS = {
    { cat = HOTBAR_CATEGORY_PRIMARY, label = "Front" },
    { cat = HOTBAR_CATEGORY_BACKUP,  label = "Back" },
}

-- costs, in the order they are checked
local MECH = {
    { COMBAT_MECHANIC_FLAGS_MAGICKA, "magicka" },
    { COMBAT_MECHANIC_FLAGS_STAMINA, "stamina" },
    { COMBAT_MECHANIC_FLAGS_HEALTH,  "health" },
    { COMBAT_MECHANIC_FLAGS_ULTIMATE, "ultimate" },
}
local ULT_COLOR   = { 0.90, 0.62, 0.40 }   -- the WoW focus pastel
local OTHER_COLOR = { 0.75, 0.75, 0.80 }

-- the resource frame: five little bars round the edge, filling clockwise from 12 o'clock
local FRAME_SEGS = {
    { 0.125, "top-right" }, { 0.25, "right" }, { 0.25, "bottom" }, { 0.25, "left" }, { 0.125, "top-left" },
}

local function ResColor(key)
    if key == "ultimate" then return ULT_COLOR end
    if SKT.Resources and SKT.Resources.db then return SKT.Resources:Color(key) or OTHER_COLOR end
    return OTHER_COLOR
end

---------------------------------------------------------------------------
-- An icon
---------------------------------------------------------------------------
local function MakeIcon(parent)
    local f = WM:CreateControl(nil, parent, CT_CONTROL)

    f.bg = D.Tex(f, 1)
    f.bg:SetAnchorFill(f)
    D.Solid(f.bg, 0, 0, 0, 0.6)

    f.tex = WM:CreateControl(nil, f, CT_TEXTURE)
    f.tex:SetAnchorFill(f)
    f.tex:SetTextureCoords(0.08, 0.92, 0.08, 0.92)
    f.tex:SetDrawLevel(2)

    f.cd = WM:CreateControl(nil, f, CT_COOLDOWN)
    f.cd:SetAnchorFill(f)
    f.cd:SetFillColor(0, 0, 0, 0.62)
    f.cd:SetDrawLevel(3)

    -- resource frame segments: a black track and a fill each
    f.segs = {}
    for i, sg in ipairs(FRAME_SEGS) do
        local track = D.Tex(f, 4)
        D.Solid(track, 0, 0, 0, 0.75)
        local fill = D.Tex(f, 5)
        f.segs[i] = { where = sg[2], share = sg[1], track = track, fill = fill }
    end

    f.num = WM:CreateControl(nil, f, CT_LABEL)
    f.num:SetColor(1, 1, 1, 1)
    f.num:SetDrawLevel(7)

    -- the game's tooltip for the skill, while the cursor is over it
    f:SetHandler("OnMouseEnter", function(c)
        if not c.abilityId then return end
        InitializeTooltip(AbilityTooltip, c, BOTTOM, 0, -6, TOP)
        -- scribed skills: the scribing tooltip with its scripts, else the skill it makes
        if c.craftedId and AbilityTooltip.SetCraftedAbility then
            local a, b, d = Call(GetCraftedAbilityActiveScriptIds, c.craftedId)
            if pcall(AbilityTooltip.SetCraftedAbility, AbilityTooltip, c.craftedId, a, b, d) then return end
        end
        AbilityTooltip:SetAbilityId(c.abilityId)
    end)
    f:SetHandler("OnMouseExit", function() ClearTooltip(AbilityTooltip) end)

    -- moving skills: drag one to another slot (or drop one from the skills window), as on ESO's bar
    f:SetHandler("OnDragStart", function(c) S:Pickup(c) end)
    f:SetHandler("OnReceiveDrag", function(c) S:Place(c) end)
    f:SetHandler("OnMouseUp", function(c, button, upInside)
        if upInside and button == MOUSE_BUTTON_INDEX_LEFT and GetCursorContentType
           and GetCursorContentType() ~= MOUSE_CONTENT_EMPTY then
            S:Place(c)
        end
    end)
    return f
end

local function SizeIcon(f, s)
    f:SetDimensions(s, s)
    f.size = s
    local fontSize = math.max(10, math.floor(s * 0.46))
    local font = "$(BOLD_FONT)|" .. fontSize .. "|thick-outline"
    f.num:SetFont(font)
    -- the label sizes itself to the text; its centre is put on the middle of a full s x s icon (not
    -- the icon itself, which may be a pixel narrower at the bar's edge while snapping)
    f.num:ClearAnchors()
    -- the font's line leaves room below the digits, which sit about 0.14 of the font size high:
    -- moved down by that so the digits themselves are centred (measured in game)
    f.num:SetAnchor(CENTER, f, TOPLEFT, s / 2, s / 2 + D.OnPx(fontSize * 0.14))

    local t = D.OnPx(math.max(1.5, s * 2 / 36))
    f.thick = t
    for _, sg in ipairs(f.segs) do
        local tr = sg.track
        tr:ClearAnchors()
        if sg.where == "top-right" then
            tr:SetAnchor(TOPLEFT, f, TOPLEFT, s / 2, 0); tr:SetDimensions(s / 2, t)
        elseif sg.where == "right" then
            tr:SetAnchor(TOPRIGHT, f, TOPRIGHT, 0, 0); tr:SetDimensions(t, s)
        elseif sg.where == "bottom" then
            tr:SetAnchor(BOTTOMLEFT, f, BOTTOMLEFT, 0, 0); tr:SetDimensions(s, t)
        elseif sg.where == "left" then
            tr:SetAnchor(TOPLEFT, f, TOPLEFT, 0, 0); tr:SetDimensions(t, s)
        else
            tr:SetAnchor(TOPLEFT, f, TOPLEFT, 0, 0); tr:SetDimensions(s / 2, t)
        end
    end
end

-- have / cost: each segment covers its share of the cost, filling clockwise from 12 o'clock
local function FillResourceFrame(f, ratio, color)
    local s, t, at = f.size, f.thick, 0
    for _, sg in ipairs(f.segs) do
        local frac = D.Clamp01((ratio - at) / sg.share)
        at = at + sg.share
        local fl = sg.fill
        fl:ClearAnchors()
        if sg.where == "top-right" then          -- left to right from the middle
            fl:SetAnchor(TOPLEFT, f, TOPLEFT, s / 2, 0); fl:SetDimensions(s / 2 * frac, t)
        elseif sg.where == "right" then          -- downwards
            fl:SetAnchor(TOPRIGHT, f, TOPRIGHT, 0, 0); fl:SetDimensions(t, s * frac)
        elseif sg.where == "bottom" then         -- right to left
            fl:SetAnchor(BOTTOMRIGHT, f, BOTTOMRIGHT, 0, 0); fl:SetDimensions(s * frac, t)
        elseif sg.where == "left" then           -- upwards
            fl:SetAnchor(BOTTOMLEFT, f, BOTTOMLEFT, 0, 0); fl:SetDimensions(t, s * frac)
        else                                     -- left to the middle
            fl:SetAnchor(TOPLEFT, f, TOPLEFT, 0, 0); fl:SetDimensions(s / 2 * frac, t)
        end
        D.Solid(fl, color[1], color[2], color[3], 1)
        fl:SetHidden(frac <= 0)
        sg.track:SetHidden(false)
    end
end

local function HideResourceFrame(f)
    for _, sg in ipairs(f.segs) do sg.track:SetHidden(true); sg.fill:SetHidden(true) end
end

---------------------------------------------------------------------------
-- Slot data
---------------------------------------------------------------------------

-- a slot's real ability: scribed (crafted) skills hold a scribing id, turned into the skill it makes
local function SlotAbility(slot, cat)
    local id = Call(GetSlotBoundId, slot, cat)
    if not id or id == 0 then return nil, nil end
    local craftedId
    if ACTION_TYPE_CRAFTED_ABILITY and Call(GetSlotType, slot, cat) == ACTION_TYPE_CRAFTED_ABILITY then
        craftedId = id
        local real = Call(GetAbilityIdForCraftedAbilityId, id)
        if real and real ~= 0 then id = real end
    end
    return id, craftedId
end

-- the ultimate's cost, asked a few ways (the slot, then the ability). For the bar you're not on,
-- the ability's own cost comes first: the game answers the slot question for that bar with the
-- ultimate on the bar you ARE on (a Warden's unsummoned companion ultimate showed the other
-- bar's percentage)
local ULT_SEEN = {}
local function UltCost(slot, cat, abilityId, active)
    local ULT = COMBAT_MECHANIC_FLAGS_ULTIMATE
    -- what it cost while its bar was the one in use, kept by ability: the other bar then shows it
    -- just as it showed there (no cost, no percentage)
    if not active and abilityId then
        local seen = ULT_SEEN[abilityId]
        if seen ~= nil then return seen or nil end
        local own = Call(GetAbilityCost, abilityId, ULT, nil, "player") or Call(GetAbilityCost, abilityId, ULT)
        if type(own) == "number" and own > 0 then return own end
        return nil
    end
    local cost = Call(GetSlotAbilityCost, slot, ULT, cat)
    if type(cost) ~= "number" or cost <= 0 then
        local c2, mech = Call(GetSlotAbilityCost, slot, cat)
        if type(c2) == "number" and c2 > 0 and (mech == nil or mech == ULT) then cost = c2 end
    end
    if (type(cost) ~= "number" or cost <= 0) and abilityId then
        cost = Call(GetAbilityCost, abilityId, ULT, nil, "player") or Call(GetAbilityCost, abilityId, ULT)
    end
    if type(cost) == "number" and cost > 0 then
        if abilityId then ULT_SEEN[abilityId] = cost end
        return cost
    end
    if abilityId then ULT_SEEN[abilityId] = false end
end

local function SlotCost(slot, cat, abilityId, active)
    if slot == ULT then
        local cost = UltCost(slot, cat, abilityId, active ~= false)
        if cost then return cost, COMBAT_MECHANIC_FLAGS_ULTIMATE, "ultimate" end
        return nil
    end
    for _, m in ipairs(MECH) do
        if m[1] then
            local cost = Call(GetSlotAbilityCost, slot, m[1], cat)
            if type(cost) == "number" and cost > 0 then return cost, m[1], m[2] end
        end
    end
end

---------------------------------------------------------------------------
-- The pane
---------------------------------------------------------------------------
function S:Build()
    local db = self.db
    local root = WM:CreateTopLevelWindow(NS)
    root:SetClampedToScreen(true)
    root:SetMouseEnabled(false)
    root:SetMovable(false)
    -- dragged box by box; brought near the top of the resource bars (centred over them, within a
    -- grid box) it sits on them, the two frames sharing a line
    local drag
    SKT.Grid.Draggable(root, {
        start = function()
            local G = SKT.Grid
            local l, _, r, b = G.Rect(root)
            local fullW = (r - l) + G.Trim()
            drag = { x = l + fullW / 2, y = b + G.Trim() }
        end,
        move = function(dx, dy)
            local G = SKT.Grid
            db.x, db.y = drag.x + dx, drag.y + dy
            self:Layout()
        end,
        stop = function()
            local G = SKT.Grid
            local s = D.OnPx(G.Boxes(db.size))
            local fullW = 6 * s + self:Gap()
            db.x = G.SnapOne(db.x - fullW / 2) + fullW / 2
            db.y = G.SnapOne(db.y)
            self:Layout()
        end,
    })
    self.root = root

    local body = WM:CreateControl("$(parent)Body", root, CT_CONTROL)
    body:SetAnchorFill(root)
    self.body = body

    self.groups = {}
    for g, bar in ipairs(BARS) do
        local grp = WM:CreateControl(nil, body, CT_CONTROL)
        grp.cat = bar.cat
        grp.icons = {}
        for i = 1, #LAYOUT do grp.icons[i] = MakeIcon(grp) end
        -- the white lines: the ring round the bar, two lines down between columns, one across between rows
        grp.ring = D.NewRing(grp, 9)
        grp.lines = { D.Tex(grp, 8), D.Tex(grp, 8), D.Tex(grp, 8) }
        self.groups[g] = grp
    end

    -- its name and outline while unlocked
    self.mover = SKT.Grid.Tag(root, "Skill bars")

    self.fragment = ZO_HUDFadeSceneFragment:New(root)
end

function S:Layout()
    if not self.root then return end
    local db = self.db
    local G = SKT.Grid
    local px = D.Px()
    -- while snapping: sizes in whole grid boxes, each bar's right and bottom side a pixel in (their
    -- frame lines on grid lines; with no gap the two bars share the line between them)
    local trim = G.Trim()
    local s = D.OnPx(G.Boxes(db.size))
    local gap = self:Gap()
    local gw, gh = 3 * s - trim, 2 * s - trim
    local fullW = 6 * s + gap

    for g, grp in ipairs(self.groups) do
        grp:ClearAnchors()
        grp:SetAnchor(TOPLEFT, self.body, TOPLEFT, (g - 1) * (3 * s + gap), 0)
        grp:SetDimensions(gw, gh)
        for i, pos in ipairs(LAYOUT) do
            local f = grp.icons[i]
            SizeIcon(f, s)
            f:SetDimensions((pos.col == 3) and (s - trim) or s, (pos.row == 2) and (s - trim) or s)
            f:ClearAnchors()
            f:SetAnchor(TOPLEFT, grp, TOPLEFT, (pos.col - 1) * s, (pos.row - 1) * s)
        end
        -- shared lines on the icons' last pixel: neighbours share one line
        local l = grp.lines
        l[1]:ClearAnchors(); l[1]:SetAnchor(TOPLEFT, grp, TOPLEFT, s - px, 0);     l[1]:SetDimensions(px, gh)
        l[2]:ClearAnchors(); l[2]:SetAnchor(TOPLEFT, grp, TOPLEFT, 2 * s - px, 0); l[2]:SetDimensions(px, gh)
        l[3]:ClearAnchors(); l[3]:SetAnchor(TOPLEFT, grp, TOPLEFT, 0, s - px);     l[3]:SetDimensions(gw, px)
        for _, t in ipairs(l) do D.Solid(t, 1, 1, 1, 1) end
        D.DrawRing(grp.ring, grp, 0, 0, gw, gh, D.White)
    end

    self:LayoutUltMeter(3 * s, gap, gh)
    self.root:SetDimensions(fullW - trim, gh)
    self.root:ClearAnchors()
    local res = SKT.Resources and SKT.Resources.root
    -- placed by its bottom (centred on x), from the middle of the screen; while snapping the left
    -- edge and the bottom frame line on grid lines
    local left = G.SnapOne((db.x or 0) - fullW / 2)
    local bottom = G.SnapOne(db.y or 135) - trim
    self.root:SetAnchor(BOTTOMLEFT, GuiRoot, CENTER, D.OnPx(left), D.OnPx(bottom))
end

-- one icon's look: texture, dimmed, cost, cooldown
function S:PaintIcon(f, slot, cat, activeBar)
    local tex = Call(GetSlotTexture, slot, cat)
    local empty = (tex == nil or tex == "")
    f.abilityId, f.craftedId = nil, nil
    if not empty then f.abilityId, f.craftedId = SlotAbility(slot, cat) end
    f.key = Key(cat, slot)
    f.slot, f.cat = slot, cat
    -- the slot shows another ability while its delayed skill runs (Budding Seeds' "bloom now"):
    -- remember it, so its effects never start a timer of their own
    local st = self.slotTimers[f.key]
    if st and f.abilityId and f.abilityId ~= st.id then self.companions[f.abilityId] = true end
    f.tex:SetTexture(empty and "" or tex)
    f.tex:SetHidden(empty)

    local dim = self.db.dimInactive and not activeBar
    local cost, mech, key
    if not empty then cost, mech, key = SlotCost(slot, cat, f.abilityId, activeBar) end
    local power = mech and GetUnitPower("player", mech) or 0
    local short = cost and power < cost

    f.tex:SetDesaturation((dim or short) and 1 or 0)
    if dim then f.tex:SetColor(0.45, 0.45, 0.45, 1)
    elseif short then f.tex:SetColor(0.7, 0.7, 0.7, 1)
    else f.tex:SetColor(1, 1, 1, 1) end
    f:SetAlpha(dim and 0.75 or 1)

    if short and self.db.showCost then
        FillResourceFrame(f, power / cost, ResColor(key))
    else
        HideResourceFrame(f)
    end

    -- the ultimates: how close you are to the cost, in percent (until it's ready)
    f.ultPct = nil
    if self.db.ultPercent and key == "ultimate" and cost and cost > 0 and power < cost then
        f.ultPct = math.floor(power / cost * 100)
    end

    -- cooldown: the sweep and its number (the global cooldown's number can be switched off)
    local remain, duration, global = Call(GetSlotCooldownInfo, slot, cat)
    remain, duration = remain or 0, duration or 0
    if not empty and remain > 0 and duration > 0 then
        if f.cdEnd == nil or math.abs((GetFrameTimeMilliseconds() + remain) - f.cdEnd) > 100 then
            f.cd:StartCooldown(remain, duration, CD_TYPE_RADIAL, CD_TIME_TYPE_TIME_UNTIL, false)
        end
        -- the sweep's darkness: the global cooldown and real cooldowns each have their own
        local a = (global and self.db.gcdAlpha or self.db.cdAlpha) / 100
        f.cd:SetFillColor(0, 0, 0, a)
        f.cd:SetHidden(a <= 0)
        f.cdEnd = GetFrameTimeMilliseconds() + remain
        f.cdGlobal = global
    else
        f.cd:ResetCooldown()
        f.cd:SetHidden(true)
        f.cdEnd, f.cdGlobal = nil, nil
    end
end

-- is this ability slotted on either bar?
function S:IsSlotted(id)
    if not id or not self.groups then return false end
    for _, grp in ipairs(self.groups) do
        for _, f in ipairs(grp.icons) do
            if f.abilityId == id then return true end
        end
    end
    return false
end

-- a slotted skill by name: some skills' effects carry their own ability id, not the skill's
-- (Cutting Dive's bleed): the effect's name is the skill's, so the timer still finds its slot
function S:SlottedByName(name)
    if not name or name == "" or not self.groups then return nil end
    name = zo_strformat("<<1>>", name)
    for _, grp in ipairs(self.groups) do
        for _, f in ipairs(grp.icons) do
            if f.abilityId and f.abilityId ~= 0 then
                local ok, n = pcall(GetAbilityName, f.abilityId)
                if ok and n and zo_strformat("<<1>>", n) == name then return f.abilityId end
            end
        end
    end
    return nil
end

function S:Refresh()
    if not self.groups then return end
    self:UpdateUltMeter()
    local active = Call(GetActiveHotbarCategory) or HOTBAR_CATEGORY_PRIMARY
    for _, grp in ipairs(self.groups) do
        for i, pos in ipairs(LAYOUT) do
            self:PaintIcon(grp.icons[i], pos.slot, grp.cat, grp.cat == active)
        end
    end
    self:Tick()
end

-- the countdown numbers, a few times a second while anything is cooling down
-- whole seconds from 1 up, tenths below
local function Secs(secs)
    if secs >= 1 then return tostring(math.floor(secs + 0.5)) end
    return string.format("%.1f", secs)
end

function S:Tick()
    local now, any = GetFrameTimeMilliseconds(), false
    local nowS = now / 1000
    local db = self.db
    for _, grp in ipairs(self.groups) do
        for _, f in ipairs(grp.icons) do
            -- first choice: the time left on the skill's own effect
            local effEnd = db.showTimers and f.abilityId and self.timers[f.abilityId] or 0
            local st = db.showTimers and f.key and self.slotTimers[f.key]
            if st and st.ends > effEnd then effEnd = st.ends end
            local effLeft = effEnd - nowS
            local left = f.cdEnd and (f.cdEnd - now) or 0
            if effLeft > 0 then
                any = true
                f.num:SetText(Secs(effLeft))
            elseif left > 0 and db.showNumbers and (not f.cdGlobal or db.gcdNumbers) then
                any = true
                f.num:SetText(Secs(left / 1000))
            elseif f.ultPct then
                f.num:SetText(f.ultPct .. "%")
            else
                f.num:SetText("")
                if left > 0 then any = true end
            end
        end
    end
    if self:TickQuickslot() then any = true end
    -- forget timers that have run out
    for id, t in pairs(self.timers) do if t <= nowS then self.timers[id] = nil end end
    for k, st in pairs(self.slotTimers) do if st.ends <= nowS then self.slotTimers[k] = nil end end
    if any and not self.ticking then
        self.ticking = true
        EM:RegisterForUpdate(NS .. "Tick", 50, function() self:Tick() end)
    elseif not any and self.ticking then
        self.ticking = false
        EM:UnregisterForUpdate(NS .. "Tick")
        self:Refresh()
    end
end

---------------------------------------------------------------------------
-- Visibility
---------------------------------------------------------------------------
function S:UpdateIdle()
    if not self.body then return end
    local db = self.db
    local show = (not db.locked) or (not db.hideOutOfCombat) or IsUnitInCombat("player")
    self.body:SetAlpha(show and 1 or 0)
end

-- the gap between the bars: with the middle column on, exactly one cell, so the whole pane is
-- seven cells wide (the column shares its frame lines with both bars)
local function Box() local G = SKT.Grid; return G.On() and G.Size() or 8 end

function S:Gap()
    local G = SKT.Grid
    if self.db.ultMeter then return D.OnPx(G.Boxes(self.db.size)) end
    return D.OnPx(G.Boxes(self.db.gap, true))
end

---------------------------------------------------------------------------
-- The middle column: the quickslot on top (the item chosen in the quickslot wheel, how many you
-- have, and a potion's cooldown), and the ultimate below (filling from the bottom, with your
-- ultimate in points, up to the most you can hold: 500)
---------------------------------------------------------------------------
local QS_CAT = HOTBAR_CATEGORY_QUICKSLOT_WHEEL

function S:BuildMiddle()
    local m = {}
    local body = self.body
    m.box = WM:CreateControl(nil, body, CT_CONTROL)
    -- the quickslot
    local q = WM:CreateControl(nil, m.box, CT_CONTROL)
    q.bg = D.Tex(q, 1); q.bg:SetAnchorFill(q); D.Solid(q.bg, 0, 0, 0, 0.6)
    q.tex = WM:CreateControl(nil, q, CT_TEXTURE)
    q.tex:SetAnchorFill(q); q.tex:SetTextureCoords(0.08, 0.92, 0.08, 0.92); q.tex:SetDrawLevel(2)
    q.cd = WM:CreateControl(nil, q, CT_COOLDOWN)
    q.cd:SetAnchorFill(q); q.cd:SetFillColor(0, 0, 0, 0.62); q.cd:SetDrawLevel(3)
    q.num = WM:CreateControl(nil, q, CT_LABEL); q.num:SetColor(1, 1, 1, 1); q.num:SetDrawLevel(7)
    q.count = WM:CreateControl(nil, q, CT_LABEL); q.count:SetColor(1, 1, 1, 1); q.count:SetDrawLevel(7)
    q.count:SetHorizontalAlignment(TEXT_ALIGN_CENTER)   -- grows and shrinks from the middle
    q:SetMouseEnabled(true)
    q:SetHandler("OnMouseEnter", function(c)
        local slot = GetCurrentQuickslot and GetCurrentQuickslot()
        if not slot then return end
        InitializeTooltip(ItemTooltip, c, BOTTOM, 0, -6, TOP)
        if ItemTooltip.SetQuickslot then pcall(ItemTooltip.SetQuickslot, ItemTooltip, slot) end
    end)
    q:SetHandler("OnMouseExit", function() ClearTooltip(ItemTooltip) end)
    m.q = q
    -- the ultimate
    local u = WM:CreateControl(nil, m.box, CT_CONTROL)
    u.track = D.Tex(u, 1); u.track:SetAnchorFill(u); D.Solid(u.track, 0, 0, 0, 0.6)
    u.fill = D.Tex(u, 2)
    u.num = WM:CreateControl(nil, u, CT_LABEL); u.num:SetColor(1, 1, 1, 1); u.num:SetDrawLevel(7)
    m.u = u
    m.ring = D.NewRing(m.box, 9)
    m.line = D.Tex(m.box, 8)
    self.middle = m
end

-- placed in the gap: x is where the left bar ends (3 cells), s a cell, h the bars' height
function S:LayoutUltMeter(x, gap, h)
    if not self.middle then self:BuildMiddle() end
    local m = self.middle
    local on = self.db.ultMeter
    m.on = on
    m.box:SetHidden(not on)
    for _, t in ipairs(m.ring.edges) do t:SetHidden(not on) end
    for _, t in ipairs(m.ring.dots) do t:SetHidden(not on) end
    if not on then return end
    local G = SKT.Grid
    local px = D.Px()
    local trim = G.Trim()
    local s = gap
    local w = s - trim
    m.box:ClearAnchors()
    m.box:SetAnchor(TOPLEFT, self.body, TOPLEFT, x, 0)
    m.box:SetDimensions(w, h)
    m.q:ClearAnchors(); m.q:SetAnchor(TOPLEFT, m.box, TOPLEFT, 0, 0); m.q:SetDimensions(w, s)
    m.u:ClearAnchors(); m.u:SetAnchor(TOPLEFT, m.box, TOPLEFT, 0, s); m.u:SetDimensions(w, h - s)
    m.w, m.uh = w, h - s
    -- numbers: as on the skills (centred on the cell, a touch lower for the digits)
    local fontSize = math.max(10, math.floor(s * 0.46))
    local font = "$(BOLD_FONT)|" .. fontSize .. "|thick-outline"
    local down = D.OnPx(fontSize * 0.14)
    m.q.num:SetFont(font)
    -- the cooldown a little above the middle, the count centred at the bottom, clear of each other
    m.q.num:ClearAnchors(); m.q.num:SetAnchor(CENTER, m.q, TOPLEFT, s / 2, s * 0.38 + down)
    m.q.count:SetFont("$(BOLD_FONT)|" .. math.max(9, math.floor(s * 0.30)) .. "|thick-outline")
    m.q.count:ClearAnchors(); m.q.count:SetAnchor(BOTTOM, m.q, TOPLEFT, s / 2, s + D.OnPx(2))
    local uFont = "$(BOLD_FONT)|" .. math.max(9, math.floor(s * 0.36)) .. "|thick-outline"
    m.u.num:SetFont(uFont)
    m.u.num:ClearAnchors(); m.u.num:SetAnchor(CENTER, m.u, TOPLEFT, s / 2, (h - s) / 2 + D.OnPx(s * 0.36 * 0.14))
    -- the frame: round the column and across between the two cells (shared with the bars')
    m.line:ClearAnchors(); m.line:SetAnchor(TOPLEFT, m.box, TOPLEFT, 0, s - px); m.line:SetDimensions(w, px)
    D.Solid(m.line, 1, 1, 1, 1)
    D.DrawRing(m.ring, m.box, 0, 0, w, h, D.White)
    self:UpdateUltMeter()
    self:UpdateQuickslot()
end

function S:UpdateUltMeter()
    local m = self.middle
    if not (m and m.on) then return end
    local cur, max = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_ULTIMATE)
    max = (max and max > 0) and max or 500
    cur = cur or 0
    local f = D.Clamp01(cur / max)
    local u = m.u
    u.fill:ClearAnchors()
    u.fill:SetAnchor(BOTTOMLEFT, u, BOTTOMLEFT, 0, 0)
    u.fill:SetDimensions(m.w, math.max(0.01, m.uh * f))
    u.fill:SetHidden(f <= 0)
    local c = ULT_COLOR
    D.VGrad(u.fill, math.min(1, c[1] * 1.15 + 0.12), math.min(1, c[2] * 1.15 + 0.12), math.min(1, c[3] * 1.15 + 0.12), 1,
        c[1] * 0.55, c[2] * 0.55, c[3] * 0.55, 1)
    u.num:SetText(tostring(cur))
end

function S:UpdateQuickslot()
    local m = self.middle
    if not (m and m.on) then return end
    local q = m.q
    local slot = GetCurrentQuickslot and GetCurrentQuickslot()
    local tex = slot and Call(GetSlotTexture, slot, QS_CAT)
    local empty = not tex or tex == ""
    q.tex:SetHidden(empty)
    if not empty then q.tex:SetTexture(tex) end
    local count = slot and Call(GetSlotItemCount, slot, QS_CAT)
    q.count:SetText((not empty and count and count > 0) and tostring(count) or "")
    -- the cooldown (potions): the sweep, and the seconds in :TickQuickslot
    local remain, duration, global = 0, 0, false
    if slot and not empty then
        local r, d, g = Call(GetSlotCooldownInfo, slot, QS_CAT)
        remain, duration, global = r or 0, d or 0, g
    end
    -- the global cooldown (or anything as short): the sweep only, as on the skills; a potion's
    -- own cooldown: the sweep and the seconds
    local gcd = global or duration <= 1500
    if remain > 0 and duration > 0 then
        local now = GetFrameTimeMilliseconds()
        if q.cdEnd == nil or math.abs((now + remain) - q.cdEnd) > 100 then
            q.cd:StartCooldown(remain, duration, CD_TYPE_RADIAL, CD_TIME_TYPE_TIME_UNTIL, false)
        end
        local a = ((gcd and self.db.gcdAlpha or self.db.cdAlpha) or 62) / 100
        q.cd:SetFillColor(0, 0, 0, a)
        q.cd:SetHidden(a <= 0)
        q.cdEnd = now + remain
        q.cdGlobal = gcd
    else
        q.cdEnd, q.cdGlobal = nil, nil
        q.cd:ResetCooldown()
        q.cd:SetHidden(true)
        q.num:SetText("")
    end
    self:TickQuickslot()
end

function S:TickQuickslot()
    local m = self.middle
    if not (m and m.on) then return false end
    local q = m.q
    local left = q.cdEnd and (q.cdEnd - GetFrameTimeMilliseconds()) or 0
    if left > 0 then
        q.num:SetText(q.cdGlobal and "" or Secs(left / 1000))
        return true
    end
    q.num:SetText("")
    q.cdEnd = nil
    return false
end

-- moving skills: only on the bar you're on, out of combat (as ESO's own bar)
local function BarCheck(c)
    if not c.slot then return false end
    if IsUnitInCombat("player") then return false end
    if AreActionBarsLocked and AreActionBarsLocked() then return false end
    if c.cat ~= (GetActiveHotbarCategory and GetActiveHotbarCategory()) then
        SKT:Print("Swap to that bar to move its skills.")
        return false
    end
    return true
end

local function Protected(fn, ...)
    if CallSecureProtected then
        local ok = pcall(CallSecureProtected, fn, ...)
        if ok then return true end
    end
    local f = _G[fn]
    return f and pcall(f, ...) or false
end

function S:Pickup(c)
    if not c.abilityId or not BarCheck(c) then return end
    ClearTooltip(AbilityTooltip)
    Protected("PickupAction", c.slot)
end

function S:Place(c)
    if not BarCheck(c) then return end
    Protected("PlaceInActionBar", c.slot)
end

function S:ApplyLock()
    local locked = self.db.locked
    self.root:SetMouseEnabled(not locked)
    -- the icons take the mouse (tooltips, moving skills) while locked; unlocked, the pane is dragged
    for _, grp in ipairs(self.groups or {}) do
        for _, f in ipairs(grp.icons) do f:SetMouseEnabled(locked) end
    end
    self.mover:SetHidden(locked)
    self:UpdateIdle()
    SKT.Grid:Update()
end

-- ESO's own action bar (skills, ultimate and quickslot). Its fragment is hidden for our reason, so
-- no scene shows it; keybinds keep working.
function S:ApplyDefaultBar()
    local hide = self.db.enabled and self.db.hideDefault
    if self.defaultHidden == hide then return end
    self.defaultHidden = hide
    local frag = ACTION_BAR_FRAGMENT
    if frag and frag.SetHiddenForReason then
        frag:SetHiddenForReason("SKToolsESO", hide)
    elseif ZO_ActionBar1 then
        ZO_ActionBar1:SetHidden(hide)
    end
end

function S:ApplyEnabled()
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
    self:ApplyDefaultBar()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function S:RegisterEvents()
    local function Full() self:Refresh() end
    local n = 0
    for _, ev in pairs({
        EVENT_ACTION_SLOTS_FULL_UPDATE, EVENT_ACTION_SLOT_UPDATED, EVENT_ACTION_SLOTS_ALL_HOTBARS_UPDATED,
        EVENT_ACTION_SLOTS_ACTIVE_HOTBAR_UPDATED, EVENT_HOTBAR_SLOT_UPDATED, EVENT_ACTIVE_WEAPON_PAIR_CHANGED,
        EVENT_ACTION_UPDATE_COOLDOWNS, EVENT_SKILLS_FULL_UPDATE, EVENT_PLAYER_ACTIVATED,
    }) do
        if ev then
            n = n + 1
            EM:RegisterForEvent(NS .. n, ev, Full)
        end
    end

    -- the quickslot: chosen item, counts, cooldowns
    local qn = 0
    for _, ev in pairs({ EVENT_ACTIVE_QUICKSLOT_CHANGED, EVENT_ACTION_UPDATE_COOLDOWNS, EVENT_INVENTORY_SINGLE_SLOT_UPDATE,
                         EVENT_ACTION_SLOT_UPDATED, EVENT_PLAYER_ACTIVATED }) do
        if ev then qn = qn + 1; EM:RegisterForEvent(NS .. "QS" .. qn, ev, function() self:UpdateQuickslot() end) end
    end

    -- power changes: repaint the cost frames
    EM:RegisterForEvent(NS .. "Power", EVENT_POWER_UPDATE, Full)
    EM:AddFilterForEvent(NS .. "Power", EVENT_POWER_UPDATE, REGISTER_FILTER_UNIT_TAG, "player")

    EM:RegisterForEvent(NS .. "Combat", EVENT_PLAYER_COMBAT_STATE, function() self:UpdateIdle() end)

    -- skill timers: started when you use a slotted skill, from the skill's duration ...
    EM:RegisterForEvent(NS .. "Used", EVENT_ACTION_SLOT_ABILITY_USED, function(_, slot)
        local cat = Call(GetActiveHotbarCategory) or HOTBAR_CATEGORY_PRIMARY
        local id = SlotAbility(slot, cat)
        if not id or id == 0 then return end
        local now = GetFrameTimeSeconds()
        local key = Key(cat, slot)
        local st = self.slotTimers[key]
        -- used again while its delayed skill runs (from the same skill or the ability standing in
        -- for it, e.g. Budding Seeds blooming early): it lands now, so the timer clears
        if st and st.ends > now and (id ~= st.id or (Delayed(id) or {}).reuseEnds) then
            if id ~= st.id then self.companions[id] = true end
            self.slotTimers[key] = nil
            self:Tick()
            return
        end
        local d = Delayed(id)
        if d then
            local ms = Call(GetAbilityDuration, id, nil, "player") or Call(GetAbilityDuration, id)
            local secs = (not d.fixed and type(ms) == "number" and ms > 0) and (ms / 1000) or d.secs
            self.slotTimers[key] = { ends = now + secs, id = id }
            self:Tick()
            return
        end
        local ms = Call(GetAbilityDuration, id, nil, "player") or Call(GetAbilityDuration, id)
        if type(ms) == "number" and ms > 0 then
            self.timers[id] = GetFrameTimeSeconds() + ms / 1000
            self:Tick()
        end
    end)

    -- ... and corrected by the game's own effect times when your effect of the same skill is
    -- applied or refreshed (on you or on a target); a buff on you that ends early clears it
    EM:RegisterForEvent(NS .. "Effect", EVENT_EFFECT_CHANGED, function(_, change, _, effectName, unitTag, _, endTime,
                                                                  _, _, _, _, _, _, _, _, abilityId)
        if self.debugTimers then
            SKT:Print(string.format("%s %s on %s, id %s, ends in %.1f s", change == EFFECT_RESULT_FADED and "faded:" or "effect:",
                zo_strformat("<<1>>", effectName or ""), tostring(unitTag), tostring(abilityId),
                (endTime or 0) - GetFrameTimeSeconds()))
        end
        if not self:IsSlotted(abilityId) then
            abilityId = self:SlottedByName(effectName)    -- the skill's effect under its own id
            if not abilityId then return end
        end
        if Delayed(abilityId) or self.companions[abilityId] then return end
        -- the netches: the timer is the whole duration from the cast; their pulses (including the
        -- last one, which runs past the end) are left out
        if Whole(abilityId) then return end
        if change == EFFECT_RESULT_FADED then
            if unitTag == "player" then self.timers[abilityId] = nil; self:Tick() end
        elseif endTime and endTime > GetFrameTimeSeconds() then
            local cur = self.timers[abilityId]
            if not cur or endTime > cur or change == EFFECT_RESULT_GAINED then
                self.timers[abilityId] = endTime
                self:Tick()
            end
        end
    end)
    EM:AddFilterForEvent(NS .. "Effect", EVENT_EFFECT_CHANGED,
        REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER)
    -- /sktskills: your skills' effects as they happen, to see what a skill's timer could use
    SLASH_COMMANDS["/sktskills"] = function()
        self.debugTimers = not self.debugTimers
        SKT:Print(self.debugTimers and "Skill test on: your effects show in chat. /sktskills again to stop."
            or "Skill test off.")
    end
    EM:RegisterForEvent(NS .. "Scale", EVENT_ALL_GUI_SCREENS_RESIZED, function()
        self:Layout(); self:Refresh()
    end)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
SKT:RegisterModule({
    key   = "Skills",
    title = "Skills",
    order = 20,

    defaults = {
        enabled = true,
        locked  = true,
        x = 0, y = 135,      -- the pane's bottom centre from the middle of the screen
        size = 40,
        gap  = 8,            -- between the front and back bar (one grid box)
        dimInactive = true,
        showNumbers = true,
        showCost    = true,
        hideOutOfCombat = false,
        hideDefault = true,  -- ESO's own action bar hidden
        gcdNumbers  = false, -- countdown numbers on the global cooldown too
        ultPercent  = true,  -- the ultimates: percent of their cost
        ultMeter    = true,  -- the middle column: quickslot over the ultimate
        showTimers  = true,  -- time left on each skill's effect
        gcdAlpha    = 62,    -- sweep darkness (%) on the global cooldown
        cdAlpha     = 62,    -- sweep darkness (%) on real cooldowns
    },

    OnLoad = function(self, db)
        S.db = db
        -- 0.5.1 turned GCD numbers on by default: back off, the skill timers take the middle
        if db.timerVersion ~= 1 then db.gcdNumbers, db.timerVersion = false, 1 end
        local NUM = { x = 0, y = 135, size = 40, gap = 8, gcdAlpha = 62, cdAlpha = 62 }
        for k, v in pairs(NUM) do if type(db[k]) ~= "number" then db[k] = v end end
        -- the pane no longer sits on the resource bars: one that did keeps that place, on its own
        if db.attach ~= false then
            local rdb = SKT.Resources and SKT.Resources.db
            if rdb then db.x, db.y = rdb.x or 0, rdb.y or 136 end
            db.attach = false
        end
        -- always: no GCD numbers, shown in and out of combat, ESO's own action bar hidden
        db.gcdNumbers, db.hideOutOfCombat, db.hideDefault = false, false, true
        S:Build()
        S:RegisterEvents()
        S:Layout()
        S:ApplyLock()
        S:ApplyEnabled()
        S:Refresh()
    end,

    BuildTab = function(self, page, db)
        local L = SKT.UI.Column(page, 16, 268)
        local R = SKT.UI.Column(page, 316, 268)
        local function relayout() S:Layout(); S:Refresh() end
        local function Pct(v) return v <= 0 and "hidden" or (v .. "%") end

        L:Header("Skill bars")
        L:Check("Enable", function() return db.enabled end,
            function(v) db.enabled = v; S:ApplyEnabled() end)
        L:Check("Dim the bar you are not on", function() return db.dimInactive end,
            function(v) db.dimInactive = v; S:Refresh() end)

        L:Header("On the icons")
        L:Check("Skill timers", function() return db.showTimers end,
            function(v) db.showTimers = v; S:Tick() end,
            "Time left on what each skill applied, on both bars.")
        L:Check("Cooldown numbers", function() return db.showNumbers end,
            function(v) db.showNumbers = v; S:Refresh() end)
        L:Check("Resource frame when short of the cost", function() return db.showCost end,
            function(v) db.showCost = v; S:Refresh() end)

        L:Header("Ultimate")
        L:Check("Percent of its cost", function() return db.ultPercent end,
            function(v) db.ultPercent = v; S:Refresh() end)
        L:Check("Quickslot and ultimate column", function() return db.ultMeter end,
            function(v) db.ultMeter = v; relayout() end)

        R:Header("Size")
        R:Slider("Icon size", 24, 64, 1,
            function() return db.size end, function(v) db.size = v; relayout() end, SKT.Grid.Fmt)
        R:Slider("Gap between the bars", 0, 24, 1,
            function() return db.gap end, function(v) db.gap = v; relayout() end, SKT.Grid.Fmt)
        R:Button("Reset position", 180, function() db.x, db.y = 0, 135; relayout() end)

        R:Header("Cooldown sweep")
        R:Slider("Global cooldown", 0, 100, 5,
            function() return db.gcdAlpha end, function(v) db.gcdAlpha = v; S:Refresh() end, Pct)
        R:Slider("Other cooldowns", 0, 100, 5,
            function() return db.cdAlpha end, function(v) db.cdAlpha = v; S:Refresh() end, Pct)
    end,
})
