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

local function Gradient(t, c)
    D.VGrad(t,
        math.min(1, c[1] * 1.15 + 0.12), math.min(1, c[2] * 1.15 + 0.12), math.min(1, c[3] * 1.15 + 0.12), 1,
        c[1] * 0.55, c[2] * 0.55, c[3] * 0.55, 1)
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
        local ok, u = pcall(lib.GetUnitULT, lib, tag)
        if ok and type(u) == "table" then
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
function Sh:DpsRows()
    local lib = self:Lib()
    local rows, boss = {}, false
    if not lib then return rows end
    for _, tag in ipairs(Members()) do
        local ok, d = pcall(lib.GetUnitDPS, lib, tag)
        if ok and type(d) == "table" and (d.dps or 0) > 0 then
            if d.dmgType == 2 then boss = true end
            rows[#rows + 1] = { name = Name(tag), value = d.dps, me = IsMe(tag) }
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
    r.name:SetAnchor(LEFT, r, LEFT, 5, 0)
    r.name:SetDrawLevel(5)
    r.name:SetMaxLineCount(1)
    r.name:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    r.value = WM:CreateControl(nil, r, CT_LABEL)
    r.value:SetAnchor(RIGHT, r, RIGHT, -5, 0)
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

local function Short(n)
    -- DPS arrives in thousands
    if n >= 1000 then return string.format("%.2fm", n / 1000) end
    return string.format("%.1fk", n)
end

local function Clock(secs)
    secs = math.max(0, math.floor(secs))
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

function Sh:Render(p)
    local db, G = self.db, SKT.Grid
    local key = p.key
    local on = db.enabled and db.show[key] and self:Lib()
    local rows, boss = {}, false
    if on then
        if key == "horn" then rows = self:HornRows() else rows, boss = self:DpsRows() end
        if key == "dps" and db.dpsCombatOnly and db.locked and not IsUnitInCombat("player") then
            rows = {}
        end
    end
    -- unlocked with nothing to show: sample rows, to place and size it
    if on and #rows == 0 and not db.locked then
        rows = { { name = "Example", value = key == "horn" and 0.72 or 120.4 },
                 { name = "Example", value = key == "horn" and 0.35 or 88.1 } }
    end
    if not on or #rows == 0 then
        p.root:SetHidden(true)
        p.shown = false
        return
    end

    local trim = G.Trim()
    local px = D.Px()
    local w = D.OnPx(G.Boxes(db.width)) - trim
    local h = D.OnPx(G.Boxes(db.rowHeight))
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
        D.VGrad(r.track, bg[1] + 0.12, bg[2] + 0.12, bg[3] + 0.14, 0.92, bg[1], bg[2], bg[3], 0.92)
        local f, c, text
        if key == "horn" then
            f = math.min(1, data.value)
            c = (data.value >= 1) and COLORS.ready or COLORS.horn
            text = (data.value >= 1) and "READY" or (math.floor(data.value * 100) .. "%")
        else
            f = (top > 0) and (data.value / top) or 0
            c = data.me and COLORS.me or COLORS.dps
            text = Short(data.value)
        end
        r.fill:SetWidth(math.max(0.01, w * f))
        r.fill:SetHidden(f <= 0)
        Gradient(r.fill, c)
        r.name:SetFont(font); r.value:SetFont(font)
        r.name:SetText(data.name)
        r.name:SetWidth(w * 0.68)
        r.value:SetText(text)
        r.name:SetColor(1, 1, 1, 1); r.value:SetColor(1, 1, 1, 1)
        r:SetHidden(false)
        -- a fine dark seam above every row but the first
        local s = p.seams[i]
        if not s then s = D.Tex(p.root, 8); p.seams[i] = s end
        s:ClearAnchors()
        s:SetAnchor(TOPLEFT, p.root, TOPLEFT, 0, (i - 1) * h)
        s:SetDimensions(w, px)
        D.Solid(s, 0, 0, 0, 0.6)
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
        for _, data in ipairs(rows) do total = total + data.value end
        local secs = self.fightStart and ((self.fightEnd or GetFrameTimeSeconds()) - self.fightStart) or 0
        p.head:SetFont("$(BOLD_FONT)|" .. math.max(11, math.floor(h * 0.62)) .. "|soft-shadow-thick")
        p.head:SetText((boss and "Boss  " or "Group  ") .. Short(total) .. "     " .. Clock(secs))
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
        for _, ev in pairs({ LibGroupCombatStats.EVENT_GROUP_ULT_UPDATE, LibGroupCombatStats.EVENT_PLAYER_ULT_UPDATE,
                             LibGroupCombatStats.EVENT_GROUP_DPS_UPDATE, LibGroupCombatStats.EVENT_PLAYER_DPS_UPDATE }) do
            if ev then pcall(lib.RegisterForEvent, lib, ev, Q) end
        end
    end
    -- the fight's time: from entering combat to leaving it (kept on screen until the next fight)
    EM:RegisterForEvent(NS .. "Combat", EVENT_PLAYER_COMBAT_STATE, function(_, inCombat)
        if inCombat then
            self.fightStart, self.fightEnd = GetFrameTimeSeconds(), nil
        else
            self.fightEnd = GetFrameTimeSeconds()
        end
        self:Queue()
    end)
    local n = 0
    for _, ev in pairs({ EVENT_GROUP_MEMBER_JOINED, EVENT_GROUP_MEMBER_LEFT, EVENT_GROUP_UPDATE, EVENT_PLAYER_ACTIVATED }) do
        if ev then n = n + 1; EM:RegisterForEvent(NS .. n, ev, function() self:Queue() end) end
    end
    -- the fight clock ticks
    EM:RegisterForUpdate(NS .. "Tick", 1000, function()
        if IsUnitInCombat("player") then self:Queue() end
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
        show = { horn = true, dps = true },
        dpsHeader = true,
        dpsCombatOnly = false,
        width = 200,
        rowHeight = 20,
        pos = {
            horn = { x = 480, y = -120 },
            dps  = { x = 480, y = 80 },
        },
    },

    OnLoad = function(self, db)
        Sh.db = db
        for k, v in pairs({ horn = { 480, -120 }, dps = { 480, 80 } }) do
            if type(db.pos[k]) ~= "table" then db.pos[k] = { x = v[1], y = v[2] } end
        end
        Sh.panels = { Sh:BuildPanel("horn", "Horn"), Sh:BuildPanel("dps", "DPS") }
        Sh:RegisterEvents()
        Sh:ApplyEnabled()
    end,

    BuildTab = function(self, page, db)
        local L = SKT.UI.Column(page, 16, 268)
        local R = SKT.UI.Column(page, 316, 268)
        local function render() Sh:RenderAll() end

        L:Header("Horn and DPS")
        L:Check("Enable", function() return db.enabled end, function(v) db.enabled = v; Sh:ApplyEnabled() end)
        L:Check("Horn tracker", function() return db.show.horn end,
            function(v) db.show.horn = v; Sh:ApplyEnabled() end)
        L:Check("DPS meter", function() return db.show.dps end,
            function(v) db.show.dps = v; Sh:ApplyEnabled() end)
        L:Check("Group total and fight time", function() return db.dpsHeader end,
            function(v) db.dpsHeader = v; render() end)
        L:Check("DPS only in combat", function() return db.dpsCombatOnly end,
            function(v) db.dpsCombatOnly = v; render() end)
        if not Sh:Lib() then
            L:Space(8)
            L:Text("|cE07070Needs LibGroupCombatStats, LibGroupBroadcast and LibCombat (the libraries Hodor Reflexes uses).|r")
        end

        R:Header("Size")
        R:Slider("Width", 120, 400, 8,
            function() return db.width end, function(v) db.width = v; render() end, SKT.Grid.Fmt)
        R:Slider("Row height", 12, 40, 1,
            function() return db.rowHeight end, function(v) db.rowHeight = v; render() end, SKT.Grid.Fmt)
    end,
})
