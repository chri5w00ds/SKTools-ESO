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
}
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
    -- the number fills the icon and is centred both ways within it
    f.num:SetColor(1, 1, 1, 1)
    f.num:SetDrawLevel(7)
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
local function Call(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

local function SlotCost(slot, cat)
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
            local x, y = drag.x + dx, drag.y + dy
            local attach = false
            local res = SKT.Resources and SKT.Resources.root
            if res and SKT.Resources.db.enabled then
                local rl, rt, rr = G.Rect(res)
                local rcx = rl + ((rr - rl) + G.Trim()) / 2
                local near = math.max(4, G.Size())
                attach = math.abs(x - rcx) <= near and math.abs(y - rt) <= near
            end
            db.attach = attach
            db.x, db.y = x, y
            self:Layout()
        end,
        stop = function()
            local G = SKT.Grid
            if not db.attach then
                local s = D.OnPx(G.Boxes(db.size))
                local fullW = 6 * s + D.OnPx(G.Boxes(db.gap, true))
                db.x = G.SnapOne(db.x - fullW / 2) + fullW / 2
                db.y = G.SnapOne(db.y)
            end
            self:Layout()
            if self.attachBox then ZO_CheckButton_SetCheckState(self.attachBox, db.attach) end
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

    local mover = WM:CreateControl("$(parent)Mover", root, CT_BACKDROP)
    mover:SetCenterColor(0.16, 0.22, 0.38, 0.35)
    mover:SetEdgeColor(SKT.col(SKT.colors.title))
    mover:SetEdgeTexture("", 1, 1, 1, 0)
    mover:SetAnchor(TOPLEFT, root, TOPLEFT, -6, -22)
    mover:SetAnchor(BOTTOMRIGHT, root, BOTTOMRIGHT, 6, 6)
    mover:SetDrawLevel(10)
    local mt = SKT.MakeLabel("$(parent)Text", mover, "SKTools: skills (front | back)", "ZoFontGameSmall",
        SKT.colors.title)
    mt:SetAnchor(TOP, mover, TOP, 0, 3)
    self.mover = mover

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
    local gap = D.OnPx(G.Boxes(db.gap, true))
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

    self.root:SetDimensions(fullW - trim, gh)
    self.root:ClearAnchors()
    local res = SKT.Resources and SKT.Resources.root
    if db.attach and res then
        -- a pixel above the resource bars: their frames share a line
        self.root:SetAnchor(BOTTOM, res, TOP, 0, -px)
    else
        -- placed by its bottom (centred on x), from the middle of the screen; while snapping the left
        -- edge and the bottom frame line on grid lines
        local left = G.SnapOne((db.x or 0) - fullW / 2)
        local bottom = G.SnapOne(db.y or 135) - trim
        self.root:SetAnchor(BOTTOMLEFT, GuiRoot, CENTER, D.OnPx(left), D.OnPx(bottom))
    end
end

-- one icon's look: texture, dimmed, cost, cooldown
function S:PaintIcon(f, slot, cat, activeBar)
    local tex = Call(GetSlotTexture, slot, cat)
    local empty = (tex == nil or tex == "")
    f.abilityId = (not empty) and Call(GetSlotBoundId, slot, cat) or nil
    f.key = Key(cat, slot)
    -- the slot shows another ability while its delayed skill runs (Budding Seeds' "bloom now"):
    -- remember it, so its effects never start a timer of their own
    local st = self.slotTimers[f.key]
    if st and f.abilityId and f.abilityId ~= st.id then self.companions[f.abilityId] = true end
    f.tex:SetTexture(empty and "" or tex)
    f.tex:SetHidden(empty)

    local dim = self.db.dimInactive and not activeBar
    local cost, mech, key
    if not empty then cost, mech, key = SlotCost(slot, cat) end
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

function S:Refresh()
    if not self.groups then return end
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
            else
                f.num:SetText("")
                if left > 0 then any = true end
            end
        end
    end
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

function S:ApplyLock()
    local locked = self.db.locked
    self.root:SetMouseEnabled(not locked)
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
    for _, ev in ipairs({
        EVENT_ACTION_SLOTS_FULL_UPDATE, EVENT_ACTION_SLOT_UPDATED, EVENT_ACTION_SLOTS_ALL_HOTBARS_UPDATED,
        EVENT_ACTION_SLOTS_ACTIVE_HOTBAR_UPDATED, EVENT_HOTBAR_SLOT_UPDATED, EVENT_ACTIVE_WEAPON_PAIR_CHANGED,
        EVENT_ACTION_UPDATE_COOLDOWNS, EVENT_SKILLS_FULL_UPDATE, EVENT_PLAYER_ACTIVATED,
    }) do
        if ev then
            n = n + 1
            EM:RegisterForEvent(NS .. n, ev, Full)
        end
    end

    -- power changes: repaint the cost frames
    EM:RegisterForEvent(NS .. "Power", EVENT_POWER_UPDATE, Full)
    EM:AddFilterForEvent(NS .. "Power", EVENT_POWER_UPDATE, REGISTER_FILTER_UNIT_TAG, "player")

    EM:RegisterForEvent(NS .. "Combat", EVENT_PLAYER_COMBAT_STATE, function() self:UpdateIdle() end)

    -- skill timers: started when you use a slotted skill, from the skill's duration ...
    EM:RegisterForEvent(NS .. "Used", EVENT_ACTION_SLOT_ABILITY_USED, function(_, slot)
        local cat = Call(GetActiveHotbarCategory) or HOTBAR_CATEGORY_PRIMARY
        local id = Call(GetSlotBoundId, slot, cat)
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
            local secs = (type(ms) == "number" and ms > 0) and (ms / 1000) or d.secs
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
    EM:RegisterForEvent(NS .. "Effect", EVENT_EFFECT_CHANGED, function(_, change, _, _, unitTag, _, endTime,
                                                                  _, _, _, _, _, _, _, _, abilityId)
        if not self:IsSlotted(abilityId) or Delayed(abilityId) or self.companions[abilityId] then return end
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
        attach  = true,      -- sit on top of the resource bars, sharing their frame line
        x = 0, y = 135,      -- when not attached: the pane's bottom centre from the middle of the screen
        size = 40,
        gap  = 8,            -- between the front and back bar (one grid box)
        dimInactive = true,
        showNumbers = true,
        showCost    = true,
        hideOutOfCombat = false,
        hideDefault = true,  -- ESO's own action bar hidden
        gcdNumbers  = false, -- countdown numbers on the global cooldown too
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
        S:Build()
        S:RegisterEvents()
        S:Layout()
        S:ApplyLock()
        S:ApplyEnabled()
        S:Refresh()
    end,

    BuildTab = function(self, page, db)
        local UI = SKT.UI
        local L, RX, CW = 16, 316, 260
        local function relayout() S:Layout(); S:Refresh() end

        UI.Header(page, "Head", L, 12, "Skill bars")
        UI.Text(page, "Intro", L, 44,
            "Front bar on the left, back bar on the right.\n" ..
            "Each bar: top row 2, 4, Ultimate. Bottom row 1, 3, 5.", 560)

        UI.Checkbox(page, "Enabled", L, 116, "Enable",
            function() return db.enabled end,
            function(v) db.enabled = v; S:ApplyEnabled() end)
        UI.Checkbox(page, "Locked", L, 142, "Lock position",
            function() return db.locked end,
            function(v) db.locked = v; S:ApplyLock() end)
        S.attachBox = UI.Checkbox(page, "Attach", L, 168, "Sit on top of the resource bars",
            function() return db.attach end,
            function(v) db.attach = v; relayout() end,
            "Placed a pixel above the resource bars so the two frames share a line.\nDragging the pane near the top of the bars sets this; dragging it away clears it.")
        UI.Checkbox(page, "Dim", L, 194, "Dim the bar you are not on",
            function() return db.dimInactive end,
            function(v) db.dimInactive = v; S:Refresh() end)
        UI.Checkbox(page, "Timers", L, 324, "Skill timers",
            function() return db.showTimers end,
            function(v) db.showTimers = v; S:Tick() end,
            "The time left on the buff, damage or heal over time each skill applied,\non both bars, so you can see when to recast. Shown in the middle of the icon.")
        UI.Checkbox(page, "Numbers", L, 220, "Cooldown numbers",
            function() return db.showNumbers end,
            function(v) db.showNumbers = v; S:Refresh() end)
        UI.Checkbox(page, "GcdNumbers", L + 170, 220, "GCD too",
            function() return db.gcdNumbers end,
            function(v) db.gcdNumbers = v; S:Refresh() end)
        UI.Checkbox(page, "Cost", L, 246, "Resource frame when short of the cost",
            function() return db.showCost end,
            function(v) db.showCost = v; S:Refresh() end,
            "The icon greys and a thin frame in the resource's colour fills clockwise\nfrom 12 o'clock as you build up to the cost (ultimate too).")
        UI.Checkbox(page, "Combat", L, 272, "Hide out of combat",
            function() return db.hideOutOfCombat end,
            function(v) db.hideOutOfCombat = v; S:UpdateIdle() end)
        UI.Checkbox(page, "HideDefault", L, 298, "Hide ESO's own action bar",
            function() return db.hideDefault end,
            function(v) db.hideDefault = v; S:ApplyDefaultBar() end,
            "Hides the built-in action bar (skills, ultimate and quickslot).\nYour keybinds keep working.")

        UI.Slider(page, "Size", RX, 116, CW, "Icon size", 24, 64, 1,
            function() return db.size end, function(v) db.size = v; relayout() end, SKT.Grid.Fmt)
        UI.Slider(page, "Gap", RX, 160, CW, "Gap between front and back bar", 0, 24, 1,
            function() return db.gap end, function(v) db.gap = v; relayout() end, SKT.Grid.Fmt)
        local function Pct(v) return v <= 0 and "hidden" or (v .. "%") end
        UI.Slider(page, "GcdAlpha", RX, 260, CW, "GCD sweep opacity", 0, 100, 5,
            function() return db.gcdAlpha end, function(v) db.gcdAlpha = v; S:Refresh() end, Pct)
        UI.Slider(page, "CdAlpha", RX, 304, CW, "Cooldown sweep opacity", 0, 100, 5,
            function() return db.cdAlpha end, function(v) db.cdAlpha = v; S:Refresh() end, Pct)

        UI.Button(page, "ResetPos", RX, 212, "Reset position", 180, function()
            db.x, db.y, db.attach = 0, 135, true
            if S.attachBox then ZO_CheckButton_SetCheckState(S.attachBox, true) end
            relayout()
        end)
    end,
})
