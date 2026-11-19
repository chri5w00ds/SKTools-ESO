--[[-------------------------------------------------------------------------
  SKTools-ESO by Scotskoogen-Chris
  Horn and DPS: group members' War Horn ultimate and their damage, shared
  through LibGroupCombatStats, the library Hodor Reflexes uses. Group
  members on Hodor Reflexes (or any addon on that library) and on SKTools
  see each other's numbers.

    Horn   one bar per group member with a horn slotted (War Horn,
           Aggressive Horn, Sturdy Horn): their ultimate as a share of the
           horn's cost, the fullest first; "READY" at 100 %.
    DPS    one bar per group member sharing damage, the highest first,
           bars measured against the top; a line above with the group's
           total and the fight's time.

  Bars in the resource bars' style (SKTools pastels, light at the top and
  dark at the bottom, fine seams, one thin silver frame). Each panel can be
  placed on the grid.

  Needs LibGroupCombatStats (with LibGroupBroadcast and LibCombat). Without
  it the tab says so and the panels stay hidden.
---------------------------------------------------------------------------]]

local SKT = SKT
local D   = SKT.Draw
local WM  = WINDOW_MANAGER
local EM  = EVENT_MANAGER
local NS  = "SKToolsESO_Shared"

local Sh = {}
SKT.Shared = Sh

local HORN_IDS = { 38563, 40223, 40220 }       -- War Horn, Aggressive Horn, Sturdy Horn
local HORN_SET = {}
for _, id in ipairs(HORN_IDS) do HORN_SET[id] = true end

local COLORS = {
    horn  = { 0.86, 0.78, 0.52 },   -- gold
    ready = { 0.48, 0.80, 0.50 },   -- green
    dps   = { 0.84, 0.42, 0.44 },   -- pastel red
    me    = { 0.45, 0.72, 0.92 },   -- your own bar: pastel blue
}
local SILVER_TOP, SILVER_BOTTOM = { 0.94, 0.94, 0.96 }, { 0.58, 0.59, 0.63 }

local function SilverAt(f)
    return SILVER_TOP[1] + (SILVER_BOTTOM[1] - SILVER_TOP[1]) * f,
           SILVER_TOP[2] + (SILVER_BOTTOM[2] - SILVER_TOP[2]) * f,
           SILVER_TOP[3] + (SILVER_BOTTOM[3] - SILVER_TOP[3]) * f
end

local function Gradient(t, c, a)
    a = a or 1
    D.VGrad(t,
        math.min(1, c[1] * 1.15 + 0.12), math.min(1, c[2] * 1.15 + 0.12), math.min(1, c[3] * 1.15 + 0.12), a,
        c[1] * 0.55, c[2] * 0.55, c[3] * 0.55, a)
end

---------------------------------------------------------------------------
-- The library
---------------------------------------------------------------------------
function Sh:Lib()
    if self.lgcs ~= nil then return self.lgcs end
    local L = LibGroupCombatStats
    if L and L.RegisterAddon then
        local ok, obj = pcall(L.RegisterAddon, "SKTools-ESO", { "ULT", "DPS" })
        self.lgcs = ok and obj or false
    else
        self.lgcs = false
    end
    return self.lgcs
end

local function Members()
    local tags = {}
    local n = GetGroupSize()
    if n and n > 0 then
        for i = 1, n do
            local tag = GetGroupUnitTagByIndex(i)
            if tag and DoesUnitExist(tag) then tags[#tags + 1] = tag end
        end
    else
        tags[1] = "player"
    end
    return tags
end

local function Name(tag) return zo_strformat("<<1>>", GetUnitName(tag) or "") end
local function IsMe(tag) return AreUnitsEqual(tag, "player") end

local function IsHorn(id)
    if not id or id == 0 then return false end
    if HORN_SET[id] then return true end
    local ok, name = pcall(GetAbilityName, id)
    return ok and name and zo_strformat("<<1>>", name):find("Horn") ~= nil
end

-- horn users: { name, pct (0..1+), me }
function Sh:HornRows()
    local lib = self:Lib()
    local rows = {}
    if not lib then return rows end
    for _, tag in ipairs(Members()) do
        -- as Hodor: the data the library's ultimate events brought (yours included), else asked for
        local u = self.ults and self.ults[zo_strformat("<<1>>", GetUnitName(tag))]
        if type(u) ~= "table" then
            local ok, got = pcall(lib.GetUnitULT, lib, tag)
            u = ok and got or nil
        end
        if type(u) == "table" then
            local cost
            if IsHorn(u.ult1ID) then cost = u.ult1Cost
            elseif IsHorn(u.ult2ID) then cost = u.ult2Cost end
            if cost and cost > 0 then
                rows[#rows + 1] = { name = Name(tag), value = (u.ultValue or 0) / cost, me = IsMe(tag) }
            end
        end
    end
    table.sort(rows, function(a, b) return a.value > b.value end)
    return rows
end

-- DPS: { name, dps (thousands), me }, and whether it's boss DPS
-- your damage this fight (to anything that isn't you or your group), and DPS in thousands over the
-- fight's time so far
local DAMAGE_RESULTS = {}
for _, r in pairs({ ACTION_RESULT_DAMAGE, ACTION_RESULT_CRITICAL_DAMAGE, ACTION_RESULT_DOT_TICK,
                    ACTION_RESULT_DOT_TICK_CRITICAL, ACTION_RESULT_BLOCKED_DAMAGE, ACTION_RESULT_DAMAGE_SHIELDED,
                    ACTION_RESULT_PRECISE_DAMAGE, ACTION_RESULT_WRECKING_DAMAGE }) do
    DAMAGE_RESULTS[r] = true
end

-- as Combat Metrics: the fight runs from your first hit to your last, and a new fight starts with
-- the first hit after leaving combat
function Sh:OnMyDamage(result, targetType, hitValue)
    if not DAMAGE_RESULTS[result] or not hitValue or hitValue <= 0 then return end
    if targetType == COMBAT_UNIT_TYPE_PLAYER or targetType == COMBAT_UNIT_TYPE_GROUP then return end
    local now = GetFrameTimeSeconds()
    if self.newFight or not self.firstHit then
        self.newFight = false
        self.firstHit, self.myDamage = now, 0
    end
    self.lastHit = now
    self.myDamage = (self.myDamage or 0) + hitValue
end

-- DPS in thousands, total damage, seconds
function Sh:MyFight()
    if not self.firstHit or not self.myDamage or self.myDamage <= 0 then return 0, 0, 0 end
    local secs = (self.lastHit or self.firstHit) - self.firstHit
    return self.myDamage / math.max(1, secs) / 1000, self.myDamage, secs
end

-- the test group's damage (thousands): by role, moving a little, you as the first damage dealer
function Sh:TestDpsRows()
    local rows, now, meDone = {}, GetFrameTimeSeconds(), false
    for _, tag in ipairs(SKT:TestTags()) do
        local i, role = SKT.TestIndex(tag), SKT.TestRole(tag)
        local base = (role == LFG_ROLE_TANK and 14) or (role == LFG_ROLE_HEAL and 24) or (135 - i * 4)
        local value = base * (1 + 0.06 * math.sin(now * 0.7 + i))
        local me = (role == LFG_ROLE_DPS and not meDone)
        if me then meDone = true end
        local classes = { 1, 6, 2, 3, 4, 5, 117, 2, 3, 1, 117, 6 }
        local dmg = value * 1000 * 75
        rows[#rows + 1] = { name = me and Name("player") or SKT.TestName(tag), value = dmg, me = me,
                            dmg = dmg, dps = value, class = me and GetUnitClassId("player") or classes[i] }
    end
    table.sort(rows, function(a, b) return a.value > b.value end)
    return rows, false
end

function Sh:DpsRows()
    if SKT:TestSize() > 0 then return self:TestDpsRows() end
    local lib = self:Lib()
    local rows, boss = {}, false
    if not lib then return rows end
    for _, tag in ipairs(Members()) do
        local ok, d = pcall(lib.GetUnitDPS, lib, tag)
        if ok and type(d) == "table" and (d.dps or 0) > 0 then
            local row = { name = Name(tag), me = IsMe(tag), class = GetUnitClassId(tag), dps = d.dps }
            if d.dmgType == 2 then
                -- boss fight: the library sends the boss DPS (in hundreds) and the cleave DPS
                boss = true
                row.target = (d.dmg or 0) / 10
                row.value = row.target
            else
                -- the library sends the total damage in tens of thousands
                row.dmg = (d.dmg or 0) * 10000
                row.value = row.dmg
            end
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, function(a, b) return a.value > b.value end)
    return rows, boss
end

---------------------------------------------------------------------------
-- A list panel
---------------------------------------------------------------------------
local function MakeRow(parent)
    local r = WM:CreateControl(nil, parent, CT_CONTROL)
    r.track = D.Tex(r, 1); r.track:SetAnchorFill(r)
    r.fill = D.Tex(r, 2)
    r.fill:SetAnchor(TOPLEFT, r, TOPLEFT, 0, 0)
    r.fill:SetAnchor(BOTTOMLEFT, r, BOTTOMLEFT, 0, 0)
    r.name = WM:CreateControl(nil, r, CT_LABEL)
    r.name:SetAnchor(LEFT, r, LEFT, 3, 0)
    r.name:SetDrawLevel(5)
    r.name:SetMaxLineCount(1)
    r.name:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    r.value = WM:CreateControl(nil, r, CT_LABEL)
    r.value:SetAnchor(RIGHT, r, RIGHT, -3, 0)
    r.value:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    r.value:SetDrawLevel(5)
    return r
end

function Sh:BuildPanel(key, title)
    local p = { key = key }
    local root = WM:CreateTopLevelWindow(NS .. key)
    root:SetClampedToScreen(true)
    root:SetMouseEnabled(false)
    p.root = root
    p.rows = {}
    p.seams = {}
    p.head = WM:CreateControl(nil, root, CT_LABEL)
    p.head:SetAnchor(BOTTOMLEFT, root, TOPLEFT, 0, -3)
    p.head:SetColor(0.95, 0.76, 0.31, 1)
    p.ring = D.NewRing(root, 9)
    p.tag = SKT.Grid.Tag(root, title)

    local db = self.db
    local drag
    SKT.Grid.Draggable(root, {
        start = function() local pos = db.pos[key]; drag = { x = pos.x, y = pos.y } end,
        move = function(dx, dy)
            local pos = db.pos[key]
            pos.x, pos.y = drag.x + dx, drag.y + dy
            self:Render(p)
        end,
        stop = function()
            local G, pos = SKT.Grid, db.pos[key]
            pos.x, pos.y = G.SnapOne(pos.x), G.SnapOne(pos.y)
            self:Render(p)
        end,
    })

    p.fragment = ZO_HUDFadeSceneFragment:New(root)
    p.fragment:RegisterCallback("StateChange", function(_, st)
        if st == SCENE_FRAGMENT_SHOWN then self:Render(p) end
    end)
    return p
end

-- each panel's own size and background opacity (from the old shared width and row height at first)
function Sh:Dim(key)
    local db = self.db
    if type(db.dims) ~= "table" then db.dims = {} end
    local d = db.dims[key]
    if type(d) ~= "table" then
        d = { width = db.width or 200, rowHeight = db.rowHeight or 20, alpha = 92 }
        db.dims[key] = d
    end
    return d
end

-- the DPS bars by class (pastels, as the rest of SKTools)
local CLASS_COLORS = {
    [1]   = { 0.96, 0.62, 0.36 },   -- Dragonknight: orange
    [2]   = { 0.58, 0.60, 0.98 },   -- Sorcerer: violet blue
    [3]   = { 0.90, 0.40, 0.44 },   -- Nightblade: red
    [4]   = { 0.46, 0.85, 0.86 },   -- Warden: teal
    [5]   = { 0.78, 0.60, 0.88 },   -- Necromancer: mauve
    [6]   = { 0.98, 0.88, 0.50 },   -- Templar: yellow
    [117] = { 0.55, 0.88, 0.50 },   -- Arcanist: green
}

-- a bar colour: the one chosen in the settings, else the default
local DEFAULT_COLORS = { dps = COLORS.dps, me = COLORS.me, personal = COLORS.me }
function Sh:Col(key)
    local c = self.db.colors and self.db.colors[key]
    if type(c) == "table" and c[1] then return c end
    return DEFAULT_COLORS[key]
end

local function Short(n)
    -- DPS arrives in thousands
    if n >= 1000 then return string.format("%.2fm", n / 1000) end
    return string.format("%.1fk", n)
end

-- total damage: 12.3k, 4.56m
local function Total(n)
    if n >= 1e6 then return string.format("%.2fm", n / 1e6) end
    return string.format("%.1fk", n / 1000)
end

local function Clock(secs)
    secs = math.max(0, math.floor(secs))
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

function Sh:Render(p)
    local db, G = self.db, SKT.Grid
    local key = p.key
    local on = db.enabled and db.show[key] and (key == "me" or self:Lib() or (key == "dps" and SKT:TestSize() > 0))
    local rows, boss = {}, false
    if on then
        if key == "horn" then rows = self:HornRows()
        elseif key == "me" then
            local dps, dmg, secs = self:MyFight()
            local hide = db.locked and db.meVis == "combat" and not IsUnitInCombat("player")
            if (dps > 0 or not db.locked) and not hide then
                rows = { { name = Name("player"), value = 1, me = true,
                           right = Total(dmg) .. " (" .. Short(dps > 0 and dps or 0) .. ")" } }
            end
        else rows, boss = self:DpsRows() end
        -- the group DPS meter: only in a group, and (if chosen) only in combat; unlocked always
        if key == "dps" and db.locked and (not IsUnitGrouped("player")
            or (db.dpsVis == "combat" and not IsUnitInCombat("player"))) then
            rows = {}
        end
        -- the horn tracker: only in a group, and (if chosen) only in combat; unlocked always
        if key == "horn" and db.locked and (not IsUnitGrouped("player")
            or (db.hornVis == "combat" and not IsUnitInCombat("player"))) then
            rows = {}
        end
    end
    -- unlocked with nothing to show: sample rows, to place and size it
    if on and #rows == 0 and not db.locked then
        if key == "horn" then
            rows = { { name = "Example", value = 0.7 }, { name = "Example", value = 0.7 } }
        else
            rows = { { name = "Example", value = 9.03e6, dmg = 9.03e6, dps = 120.4 },
                     { name = "Example", value = 6.61e6, dmg = 6.61e6, dps = 88.1 } }
        end
    end
    if not on or #rows == 0 then
        p.root:SetHidden(true)
        p.shown = false
        return
    end

    local trim = G.Trim()
    local px = D.Px()
    local dim = self:Dim(key)
    local w = D.OnPx(G.Boxes(dim.width)) - trim
    local h = D.OnPx(G.Boxes(dim.rowHeight))
    local alpha = (dim.alpha or 92) / 100
    local font = "$(MEDIUM_FONT)|" .. math.max(10, math.floor(h * 0.62)) .. "|soft-shadow-thin"
    local top = rows[1].value
    local bg = SKT.colors.bg

    for i, data in ipairs(rows) do
        local r = p.rows[i]
        if not r then r = MakeRow(p.root); p.rows[i] = r end
        local rh = (i == #rows) and (h - trim) or h
        r:ClearAnchors()
        r:SetAnchor(TOPLEFT, p.root, TOPLEFT, 0, (i - 1) * h)
        r:SetDimensions(w, rh)
        D.VGrad(r.track, bg[1] + 0.12, bg[2] + 0.12, bg[3] + 0.14, alpha, bg[1], bg[2], bg[3], alpha)
        local f, c, text
        if key == "horn" then
            f = math.min(1, data.value)
            c = (data.value >= 1) and COLORS.ready or COLORS.horn
            text = (data.value >= 1) and "READY" or (math.floor(data.value * 100) .. "%")
        elseif key == "me" then
            -- unlocked (placing it): filled to 70 %, so the background shows too
            -- your class colour (when class colours are on), else the Personal DPS colour
            local cls = db.classColors ~= false and CLASS_COLORS[GetUnitClassId("player")]
            f, c, text = db.locked and 1 or 0.7, cls or self:Col("personal"), data.right
        else
            f = (top > 0) and (data.value / top) or 0
            c = (db.classColors ~= false and data.class and CLASS_COLORS[data.class])
                or (data.me and self:Col("me") or self:Col("dps"))
            -- total damage (DPS); in a boss fight: target DPS (cleave DPS)
            if data.target then
                text = Short(data.target) .. " (" .. Short(data.dps or 0) .. ")"
            elseif data.dmg then
                text = Total(data.dmg) .. " (" .. Short(data.dps or 0) .. ")"
            else
                text = Short(data.value)
            end
        end
        r.fill:SetWidth(math.max(0.01, w * f))
        r.fill:SetHidden(f <= 0)
        Gradient(r.fill, c, alpha)
        r.name:SetFont(font); r.value:SetFont(font)
        r.name:SetText(data.name)
        r.value:SetText(text)
        -- the name gets what the number leaves (cut short with … if it's longer)
        r.name:SetWidth(math.max(20, w - (r.value:GetTextWidth() or 0) - 14))
        r.name:SetColor(1, 1, 1, alpha); r.value:SetColor(1, 1, 1, alpha)
        r:SetHidden(false)
        -- a fine dark seam above every row but the first
        local s = p.seams[i]
        if not s then s = D.Tex(p.root, 8); p.seams[i] = s end
        s:ClearAnchors()
        s:SetAnchor(TOPLEFT, p.root, TOPLEFT, 0, (i - 1) * h)
        s:SetDimensions(w, px)
        D.Solid(s, 0, 0, 0, 0.6 * alpha)
        s:SetHidden(i == 1)
    end
    for i = #rows + 1, #p.rows do p.rows[i]:SetHidden(true) end
    for i = #rows + 1, #p.seams do p.seams[i]:SetHidden(true) end

    local H = #rows * h - trim
    p.root:SetDimensions(w, H)
    D.DrawRing(p.ring, p.root, 0, 0, w, H, SilverAt)

    -- the DPS panel's line above: the group's total and the fight's time
    if key == "dps" and db.dpsHeader then
        local total = 0
        for _, data in ipairs(rows) do total = total + (data.target or data.dps or 0) end
        local secs = self.fightStart and ((self.fightEnd or GetFrameTimeSeconds()) - self.fightStart) or 0
        p.head:SetFont("$(MEDIUM_FONT)|" .. math.max(11, math.floor(h * 0.62)) .. "|soft-shadow-thin")
        p.head:SetText((boss and "Boss  " or "Group  ") .. Short(total) .. "     " .. Clock(secs))
        p.head:SetColor(1, 1, 1, alpha)
        p.head:SetHidden(false)
    else
        p.head:SetHidden(true)
    end
    p.tag.label:ClearAnchors()
    p.tag.label:SetAnchor(BOTTOMLEFT, p.root, TOPLEFT, 0, (key == "dps" and db.dpsHeader) and -24 or -4)
    p.tag:SetHidden(db.locked)

    local pos = db.pos[key]
    p.root:ClearAnchors()
    p.root:SetAnchor(TOPLEFT, GuiRoot, CENTER, D.OnPx(G.SnapOne(pos.x)), D.OnPx(G.SnapOne(pos.y)))
    p.root:SetMouseEnabled(not db.locked)
    local st = p.fragment:GetState()
    p.root:SetHidden(not (st == SCENE_FRAGMENT_SHOWN or st == SCENE_FRAGMENT_SHOWING))
    p.shown = true
    if key == "horn" then self:LayoutForce(p, w) end
end

---------------------------------------------------------------------------
-- Major Force: a pill under the horn tracker, as the mount's stamina under the resource bars,
-- full when you gain Major Force (from anyone) and draining to its end; the personal DPS colour
---------------------------------------------------------------------------
local CIRCLE = "SKTools-ESO/Media/Circle.dds"

local function NewPill(parent, level)
    local q = {}
    q.l = D.Tex(parent, level); q.l:SetTexture(CIRCLE)
    q.r = D.Tex(parent, level); q.r:SetTexture(CIRCLE)
    q.m = D.Tex(parent, level)
    return q
end

local function PlacePill(q, parent, x, y, w, h, r1, g1, b1, a1, r2, g2, b2, a2)
    w = math.max(w, h)
    q.l:ClearAnchors(); q.l:SetAnchor(TOPLEFT, parent, TOPLEFT, x, y); q.l:SetDimensions(h, h)
    q.r:ClearAnchors(); q.r:SetAnchor(TOPLEFT, parent, TOPLEFT, x + w - h, y); q.r:SetDimensions(h, h)
    q.m:ClearAnchors(); q.m:SetAnchor(TOPLEFT, parent, TOPLEFT, x + h / 2, y)
    q.m:SetDimensions(math.max(0.01, w - h), h)
    q.m:SetHidden(w - h < 0.5)
    for _, t in ipairs({ q.l, q.r, q.m }) do D.VGrad(t, r1, g1, b1, a1, r2, g2, b2, a2) end
end

local function ShowPill(q, on)
    q.l:SetHidden(not on); q.r:SetHidden(not on)
    if not on then q.m:SetHidden(true) end
end

function Sh:LayoutForce(p, panelW)
    local f = p.force
    if not f then
        f = WM:CreateControl(nil, p.root, CT_CONTROL)
        f.frame, f.track, f.fill = NewPill(f, 10), NewPill(f, 11), NewPill(f, 12)
        p.force = f
    end
    local px = D.Px()
    -- one grid box in from each side of the horn tracker
    local box = (SKT.Grid.On() and SKT.Grid.Size()) or 8
    local w = D.OnPx(math.max(16, panelW - 2 * box))
    local h = D.OnPx(8)
    f.w, f.h = w, h
    f:ClearAnchors()
    f:SetAnchor(TOPLEFT, p.root, BOTTOMLEFT, D.OnPx(box), D.OnPx(6))
    f:SetDimensions(w, h)
    PlacePill(f.frame, f, -px, -px, w + 2 * px, h + 2 * px,
        SILVER_TOP[1], SILVER_TOP[2], SILVER_TOP[3], 1, SILVER_BOTTOM[1], SILVER_BOTTOM[2], SILVER_BOTTOM[3], 1)
    local a = ((self:Dim("horn").alpha or 92) / 100)
    f.alpha = a
    PlacePill(f.track, f, 0, 0, w, h, 0.40, 0.40, 0.40, a, 0.07, 0.07, 0.07, a)
    ShowPill(f.frame, true); ShowPill(f.track, true)
    self.forcePanel = p
    self:UpdateForce()
end

function Sh:UpdateForce()
    local p = self.forcePanel
    local f = p and p.force
    if not f or not f.w then return end
    local now = GetFrameTimeSeconds()
    local frac = 0
    if self.forceEnd and self.forceEnd > now then
        frac = (self.forceEnd - now) / math.max(0.1, self.forceEnd - (self.forceStart or now))
    elseif not self.db.locked then
        frac = 0.7                       -- unlocked: a sample, to see it
    end
    frac = math.max(0, math.min(1, frac))
    if frac <= 0 then ShowPill(f.fill, false) return end
    -- the personal DPS bar's colour: your class colour, or the one chosen
    local c = (self.db.classColors ~= false and CLASS_COLORS[GetUnitClassId("player")]) or self:Col("personal")
    PlacePill(f.fill, f, 0, 0, f.w * frac, f.h,
        math.min(1, c[1] * 1.15 + 0.12), math.min(1, c[2] * 1.15 + 0.12), math.min(1, c[3] * 1.15 + 0.12), f.alpha or 1,
        c[1] * 0.55, c[2] * 0.55, c[3] * 0.55, f.alpha or 1)
    ShowPill(f.fill, true)
    f.fill.m:SetHidden(f.w * frac - f.h < 0.5)
end

-- Major Force on you: from its effect, whoever gave it
local function IsForce(name) return zo_strformat("<<1>>", name or "") == "Major Force" end

function Sh:WatchForce()
    local function Set(started, ending)
        self.forceStart, self.forceEnd = started, ending
        if ending and ending > GetFrameTimeSeconds() then
            EM:RegisterForUpdate(NS .. "Force", 33, function()
                self:UpdateForce()
                if not self.forceEnd or self.forceEnd <= GetFrameTimeSeconds() then
                    EM:UnregisterForUpdate(NS .. "Force")
                    self:UpdateForce()
                end
            end)
        end
        self:UpdateForce()
    end
    EM:RegisterForEvent(NS .. "ForceFx", EVENT_EFFECT_CHANGED,
        function(_, change, _, effectName, _, beginTime, endTime)
            if not IsForce(effectName) then return end
            if change == EFFECT_RESULT_FADED then
                Set(nil, nil)
            elseif endTime and endTime > beginTime then
                Set(beginTime, endTime)
            end
        end)
    EM:AddFilterForEvent(NS .. "ForceFx", EVENT_EFFECT_CHANGED, REGISTER_FILTER_UNIT_TAG, "player")
    -- already on you (after a reload)
    for i = 1, GetNumBuffs("player") do
        local name, started, ending = GetUnitBuffInfo("player", i)
        if IsForce(name) and ending and ending > GetFrameTimeSeconds() then Set(started, ending) end
    end
end

function Sh:RenderAll()
    for _, p in ipairs(self.panels or {}) do self:Render(p) end
end

function Sh:Queue()
    if self.queued then return end
    self.queued = true
    zo_callLater(function() self.queued = false; self:RenderAll() end, 200)
end

function Sh:ApplyLock()
    self:RenderAll()
    SKT.Grid:Update()
end

function Sh:ApplyEnabled()
    for _, p in ipairs(self.panels) do
        local on = self.db.enabled and self.db.show[p.key]
        if on and not p.added then
            HUD_SCENE:AddFragment(p.fragment); HUD_UI_SCENE:AddFragment(p.fragment); p.added = true
        elseif not on and p.added then
            HUD_SCENE:RemoveFragment(p.fragment); HUD_UI_SCENE:RemoveFragment(p.fragment); p.added = false
        end
    end
    self:RenderAll()
end

function Sh:RegisterEvents()
    local lib = self:Lib()
    if lib then
        local function Q() self:Queue() end
        for _, ev in pairs({ LibGroupCombatStats.EVENT_GROUP_DPS_UPDATE, LibGroupCombatStats.EVENT_PLAYER_DPS_UPDATE }) do
            if ev then pcall(lib.RegisterForEvent, lib, ev, Q) end
        end
        -- ultimates: kept from the events by name, the way Hodor reads them (the library's lookup
        -- by unit doesn't hold your own)
        self.ults = {}
        local function OnUlt(unitTag, data)
            if not unitTag or type(data) ~= "table" then return end
            local name = zo_strformat("<<1>>", GetUnitName(unitTag))
            self.ults[name] = data
            if self.debugHorn then
                SKT:Print(string.format("%s: ult %s, front %s (%s), back %s (%s)", name, tostring(data.ultValue),
                    tostring(data.ult1ID), tostring(data.ult1Cost), tostring(data.ult2ID), tostring(data.ult2Cost)))
            end
            self:Queue()
        end
        for _, ev in pairs({ LibGroupCombatStats.EVENT_GROUP_ULT_UPDATE, LibGroupCombatStats.EVENT_PLAYER_ULT_UPDATE }) do
            if ev then pcall(lib.RegisterForEvent, lib, ev, OnUlt) end
        end
        -- /skthorn: show the ultimate data as it arrives
        SLASH_COMMANDS["/skthorn"] = function()
            self.debugHorn = not self.debugHorn
            SKT:Print(self.debugHorn and "Horn test on: ultimate data shows in chat. /skthorn again to stop."
                or "Horn test off.")
        end
    end
    -- the fight's time: from entering combat to leaving it (kept on screen until the next fight)
    EM:RegisterForEvent(NS .. "Combat", EVENT_PLAYER_COMBAT_STATE, function(_, inCombat)
        if inCombat then
            self.fightStart, self.fightEnd = GetFrameTimeSeconds(), nil
            self.newFight = true
        else
            self.fightEnd = GetFrameTimeSeconds()
        end
        self:Queue()
    end)
    -- your damage, you and your pets
    for i, unitType in pairs({ COMBAT_UNIT_TYPE_PLAYER, COMBAT_UNIT_TYPE_PLAYER_PET }) do
        local id = NS .. "Damage" .. i
        EM:RegisterForEvent(id, EVENT_COMBAT_EVENT, function(_, result, isError, _, _, _, _, _, _, targetType, hitValue)
            if not isError then self:OnMyDamage(result, targetType, hitValue) end
        end)
        EM:AddFilterForEvent(id, EVENT_COMBAT_EVENT, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, unitType)
    end
    local n = 0
    for _, ev in pairs({ EVENT_GROUP_MEMBER_JOINED, EVENT_GROUP_MEMBER_LEFT, EVENT_GROUP_UPDATE, EVENT_PLAYER_ACTIVATED }) do
        if ev then n = n + 1; EM:RegisterForEvent(NS .. n, ev, function() self:Queue() end) end
    end
    -- the fight clock ticks
    EM:RegisterForUpdate(NS .. "Tick", 1000, function()
        if IsUnitInCombat("player") or SKT:TestSize() > 0 then self:Queue() end
    end)
    EM:RegisterForEvent(NS .. "Scale", EVENT_ALL_GUI_SCREENS_RESIZED, function() self:RenderAll() end)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
SKT:RegisterModule({
    key   = "Shared",
    title = "Horn & DPS",
    order = 24.7,

    defaults = {
        enabled = true,
        locked  = true,
        show = { horn = true, dps = true, me = true },
        dpsHeader = true,
        colors = {},              -- dps, me, personal: { r, g, b }; unset = the default
        dpsVis = "always",
        meVis = "always",         -- the personal DPS meter: "always" or "combat"        -- the group DPS meter in a group: "always" or "combat"
        hornVis = "always",       -- the horn tracker in a group: "always" or "combat"
        classColors = true,       -- the group DPS bars in class colours
        width = 200,
        rowHeight = 20,
        pos = {
            horn = { x = 480, y = -120 },
            dps  = { x = 480, y = 80 },
            me   = { x = 480, y = 240 },
        },
    },

    OnLoad = function(self, db)
        Sh.db = db
        db.enabled = true                               -- each element has its own Off now
        if db.show.me == nil then db.show.me = true end
        if db.dpsCombatOnly ~= nil then                 -- the old tick, as the new choice
            db.dpsVis = db.dpsCombatOnly and "combat" or "always"
            db.dpsCombatOnly = nil
        end
        for k, v in pairs({ horn = { 480, -120 }, dps = { 480, 80 }, me = { 480, 240 } }) do
            if type(db.pos[k]) ~= "table" then db.pos[k] = { x = v[1], y = v[2] } end
        end
        Sh.panels = { Sh:BuildPanel("horn", "Horn"), Sh:BuildPanel("dps", "DPS"),
                      Sh:BuildPanel("me", "Personal DPS") }
        Sh:RegisterEvents()
        Sh:WatchForce()
        Sh:ApplyEnabled()
    end,

    BuildTab = function(self, page, db)
        local L = SKT.UI.Column(page, 16, 268)
        local R = SKT.UI.Column(page, 316, 268)
        local function render() Sh:RenderAll() end
        db.enabled = true

        -- each element: off, only in combat, or always (the group ones only in a group)
        local function Visibility(title, key, visField)
            L:Header(title)
            L:ChoiceRow({ { "off", "Off" }, { "combat", "In combat" }, { "always", "Always" } },
                function()
                    if not db.show[key] then return "off" end
                    return db[visField] == "combat" and "combat" or "always"
                end,
                function(v)
                    db.show[key] = (v ~= "off")
                    if v ~= "off" then db[visField] = v end
                    Sh:ApplyEnabled()
                end)
        end
        Visibility("Personal DPS meter", "me", "meVis")
        Visibility("Group DPS", "dps", "dpsVis")
        Visibility("Horn tracker", "horn", "hornVis")

        -- one set of sliders; the ticks choose which element they change
        L:Header("Size")
        local sel = "me"
        local sliders = {}
        L:ChoiceRow({ { "me", "Personal" }, { "dps", "Group" }, { "horn", "Horn" } },
            function() return sel end, function(v)
                sel = v
                for _, sl in ipairs(sliders) do sl.ctrl:SetValue(sl.get()) end
            end)
        local function Add(label, minV, maxV, step, field, fmt)
            local get = function() return Sh:Dim(sel)[field] or 0 end
            local ctrl = L:Slider(label, minV, maxV, step, get,
                function(v) Sh:Dim(sel)[field] = v; render() end, fmt)
            sliders[#sliders + 1] = { ctrl = ctrl, get = get }
        end
        Add("Width", 120, 400, 8, "width", SKT.Grid.Fmt)
        Add("Row height", 12, 40, 1, "rowHeight", SKT.Grid.Fmt)
        Add("Opacity", 0, 100, 5, "alpha", function(v) return v .. "%" end)

        -- colours: by class, or your own (the swatches below)
        R:Header("Colours")
        if type(db.colors) ~= "table" then db.colors = {} end
        local painters = {}
        R:Choice({ { true, "Class colours" }, { false, "Custom colours" } },
            function() return db.classColors ~= false end,
            function(v)
                db.classColors = v
                render()
                for _, paint in ipairs(painters) do paint() end
            end)
        R:Space(4)
        -- the swatches open the colour picker while Custom colours is chosen
        local function custom() return db.classColors == false end
        for _, row in ipairs({ { "dps", "Group DPS" }, { "me", "You (group DPS)" }, { "personal", "Personal DPS" } }) do
            local k = row[1]
            painters[#painters + 1] = R:Color(row[2], function() return db.colors[k] end,
                function(v) db.colors[k] = v; render() end, DEFAULT_COLORS[k], custom)
        end
        if not Sh:Lib() then
            R:Space(8)
            R:Text("|cE07070Group DPS and the horn tracker need LibGroupCombatStats, LibGroupBroadcast and LibCombat (as Hodor Reflexes).|r")
        end
    end,
})
