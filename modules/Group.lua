--[[-------------------------------------------------------------------------
  SKTools-ESO by Scotskoogen-Chris
  Group buffs: which group member has which of the effects you watch.

  One row per group member (you included), one column per watched effect.
  The top row holds each effect's icon (its name in a tooltip). A member
  who has the effect gets a cell filled green that sweeps away (the same
  sweep as the skill bars' global cooldown) as the effect runs down,
  leaving the black behind, with the time left in the middle; one who hasn't gets an empty cell with
  a small dash, so the two read apart by shape. Cells sit on black at 40 %.
  Members who are dead or offline are dimmed.

  Effects are watched by name (English names, as the game writes them),
  and the list is yours to edit in the Group tab. An effect's icon is
  learnt the first time anyone in the group has it (until then: a question
  mark).

  Essentials style: flush cells, thin white lines that neighbours share,
  rounded outer corners. Unlock to place it on the grid.
---------------------------------------------------------------------------]]

local SKT = SKT
local D   = SKT.Draw
local WM  = WINDOW_MANAGER
local EM  = EVENT_MANAGER
local NS  = "SKToolsESO_Group"

local Gp = {}
SKT.Group = Gp

local UNKNOWN_ICON = "/esoui/art/icons/icon_missing.dds"
local HAS_GREEN = { 0.48, 0.80, 0.50 }     -- a lighter shade of the SKTools green
local HAS_ALPHA = 0.7
local CELL_BG_ALPHA = 0.4
local DEFAULT_LIST = {
    "Major Courage", "Major Berserk", "Minor Berserk", "Major Slayer",
    "Powerful Assault", "Major Force", "Minor Toughness", "Major Resolve",
}

local function Key(name) return zo_strlower(zo_strformat("<<1>>", name or "")) end

---------------------------------------------------------------------------
-- Who has what
---------------------------------------------------------------------------
local RoleRank
-- a member's role: tank 1, healer 2, damage 3, none chosen 4
local function Role(tag)
    if SKT.IsTestTag(tag) then return SKT.TestRole(tag) end
    return GetGroupMemberSelectedRole and GetGroupMemberSelectedRole(tag) or nil
end
RoleRank = function(tag)
    local r = Role(tag)
    if r == LFG_ROLE_TANK then return 1 end
    if r == LFG_ROLE_HEAL then return 2 end
    if r == LFG_ROLE_DPS then return 3 end
    return 4
end
local function RoleIcon(tag)
    local r = Role(tag)
    if not r or r == LFG_ROLE_INVALID or not ZO_GetRoleIcon then return nil end
    local ok, icon = pcall(ZO_GetRoleIcon, r)
    return ok and icon or nil
end

Gp.RoleRank = function(tag) return RoleRank(tag) end
Gp.RoleIcon = function(tag) return RoleIcon(tag) end

function Gp:Members()
    local tags = {}
    local n = GetGroupSize()
    if SKT:TestSize() > 0 then
        tags = SKT:TestTags()
    elseif n and n > 0 then
        for i = 1, n do
            local tag = GetGroupUnitTagByIndex(i)
            if tag and DoesUnitExist(tag) then tags[#tags + 1] = tag end
        end
    elseif not self.db.locked then
        tags[1] = "player"
    end
    -- tanks first, then healers, then damage dealers (the group's own order within each)
    if self.db.sortRoles and #tags > 1 then
        local order = {}
        for i, tag in ipairs(tags) do order[tag] = i end
        table.sort(tags, function(a, b)
            local ra, rb = RoleRank(a), RoleRank(b)
            if ra ~= rb then return ra < rb end
            return order[a] < order[b]
        end)
    end
    return tags
end

-- a test member's effects: made up, the same each time for the same member and effect; timed ones
-- run over and over (20 s, each starting at its own point), some last, some are missing
function Gp:TestHas(tag)
    local has, i = {}, SKT.TestIndex(tag) or 1
    local now = GetFrameTimeSeconds()
    for c, name in ipairs(self.db.list or {}) do
        local kind = (i * 7 + c * 3) % 5
        if kind == 0 then
            -- missing
        elseif kind == 1 then
            has[Key(name)] = { started = 0, ending = 0, permanent = true }
        else
            local period = 20
            local started = now - ((now + i * 3.1 + c * 1.7) % period)
            has[Key(name)] = { started = started, ending = started + period, permanent = false }
        end
    end
    return has
end

-- tag -> { [effect key] = { ending, permanent } }
function Gp:Scan(tags)
    local out = {}
    for _, tag in ipairs(tags) do
        local has = {}
        if SKT.IsTestTag(tag) then has = self:TestHas(tag) end
        for i = 1, (SKT.IsTestTag(tag) and 0 or GetNumBuffs(tag)) do
            local name, started, ending, _, _, icon = GetUnitBuffInfo(tag, i)
            if name and name ~= "" then
                local k = Key(name)
                if self.watch[k] then
                    local prev = has[k]
                    if not prev or (ending or 0) > (prev.ending or 0) then
                        has[k] = { started = started, ending = ending,
                                   permanent = (not ending or ending <= started) }
                    end
                    if icon and icon ~= "" and self.db.icons[k] ~= icon then self.db.icons[k] = icon end
                end
            end
        end
        out[tag] = has
    end
    return out
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
local function Pool(make, parent)
    return { list = {}, n = 0, make = make, parent = parent }
end
local function Get(pool)
    pool.n = pool.n + 1
    local c = pool.list[pool.n]
    if not c then c = pool.make(pool.parent); pool.list[pool.n] = c end
    c:SetHidden(false)
    return c
end
local function Done(pool)
    for i = pool.n + 1, #pool.list do pool.list[i]:SetHidden(true) end
    pool.n = 0
end

local function MakeCell(parent)
    local f = WM:CreateControl(nil, parent, CT_CONTROL)
    f.bg = D.Tex(f, 1)
    f.bg:SetAnchorFill(f)
    f.tex = WM:CreateControl(nil, f, CT_TEXTURE)
    f.tex:SetAnchorFill(f)
    f.tex:SetTextureCoords(0.08, 0.92, 0.08, 0.92)
    f.tex:SetDrawLevel(2)
    -- has the effect: the green itself is the skill bars' cooldown sweep, receding to leave the
    -- black; a plain green fill for effects that don't run out
    f.green = D.Tex(f, 2)
    f.green:SetAnchorFill(f)
    f.cd = WM:CreateControl(nil, f, CT_COOLDOWN)
    f.cd:SetAnchorFill(f)
    f.cd:SetFillColor(0, 0, 0, 0.55)
    f.cd:SetDrawLevel(4)
    f.dash = D.Tex(f, 3)
    f.num = WM:CreateControl(nil, f, CT_LABEL)
    f.num:SetColor(1, 1, 1, 1)
    f.num:SetDrawLevel(6)
    f:SetHandler("OnMouseEnter", function(c)
        if not c.tip then return end
        InitializeTooltip(InformationTooltip, c, BOTTOM, 0, -6, TOP)
        SetTooltipText(InformationTooltip, c.tip)
    end)
    f:SetHandler("OnMouseExit", function() ClearTooltip(InformationTooltip) end)
    return f
end

local function MakeName(parent)
    local f = WM:CreateControl(nil, parent, CT_CONTROL)
    f.bg = D.Tex(f, 1)
    f.bg:SetAnchorFill(f)
    f.role = WM:CreateControl(nil, f, CT_TEXTURE)
    f.role:SetDrawLevel(3)
    f.text = WM:CreateControl(nil, f, CT_LABEL)
    f.text:SetDrawLevel(3)
    f.text:SetMaxLineCount(1)
    f.text:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    return f
end

function Gp:Build()
    local db = self.db
    local root = WM:CreateTopLevelWindow(NS)
    root:SetClampedToScreen(true)
    root:SetMouseEnabled(false)
    self.root = root
    self.cells = Pool(MakeCell, root)
    self.names = Pool(MakeName, root)
    self.lines = Pool(function(p) return D.Tex(p, 8) end, root)
    self.tag = SKT.Grid.Tag(root, "Group buffs")
    self.edges = {}
    for i = 1, 6 do self.edges[i] = D.Tex(root, 9) end
    self.dots = {}
    for i = 1, 5 do self.dots[i] = D.Tex(root, 9) end

    local drag
    SKT.Grid.Draggable(root, {
        start = function() drag = { x = db.x, y = db.y } end,
        move = function(dx, dy) db.x, db.y = drag.x + dx, drag.y + dy; self:Render() end,
        stop = function()
            local G = SKT.Grid
            db.x, db.y = G.SnapOne(db.x), G.SnapOne(db.y)
            self:Render()
        end,
    })

    self.fragment = ZO_HUDFadeSceneFragment:New(root)
    self.fragment:RegisterCallback("StateChange", function(_, newState)
        if newState == SCENE_FRAGMENT_SHOWN then self:Refresh() end
    end)
end

function Gp:Refresh()
    if not self.root then return end
    self.tags = self:Members()
    self.has = self:Scan(self.tags)
    self:Render()
end

function Gp:Render()
    local db, G = self.db, SKT.Grid
    local tags = self.tags or {}
    local list = db.list
    -- only in combat (if chosen): hidden out of combat, except while unlocked to place it
    -- only in a group; always there, or only in combat (as chosen); unlocked always, to place it
    local outOfCombat = db.locked and (not IsUnitGrouped("player")
        or (db.visibility == "combat" and not IsUnitInCombat("player")))
    if not db.enabled or #tags == 0 or #list == 0 or outOfCombat then
        self.cells.n, self.names.n, self.lines.n = 0, 0, 0
        Done(self.cells); Done(self.names); Done(self.lines)
        self.root:SetHidden(true)
        return
    end

    local trim = G.Trim()
    local px = D.Px()
    local s = D.OnPx(G.Boxes(db.size))
    -- the members' rows: their own height (the icon row on top stays square)
    local hh = D.OnPx(G.Boxes(db.rowHeight or db.size))
    local m = math.min(s, hh)
    local nameW = D.OnPx(G.Boxes(db.nameWidth))
    local cols, rows = #list, #tags + 1
    local W = nameW + cols * s - trim
    local H = s + #tags * hh - trim
    local bg = SKT.colors.bg
    local fontName = "$(MEDIUM_FONT)|" .. math.max(10, math.floor(m * 0.5)) .. "|soft-shadow-thin"
    local fontNum = "$(BOLD_FONT)|" .. math.max(8, math.floor(m * 0.42)) .. "|thick-outline"
    local numDown = D.OnPx(math.floor(m * 0.42) * 0.14)
    local now = GetFrameTimeSeconds()

    self.cells.n, self.names.n, self.lines.n = 0, 0, 0
    local function Line(x, y, w, h)
        local t = Get(self.lines)
        t:ClearAnchors()
        t:SetAnchor(TOPLEFT, self.root, TOPLEFT, x, y)
        t:SetDimensions(w, h)
        D.Solid(t, 1, 1, 1, 1)
    end

    for r = 1, rows do
        local y = (r == 1) and 0 or (s + (r - 2) * hh)
        local lastRow = (r == rows)
        local full = (r == 1) and s or hh
        local rowH = lastRow and (full - trim) or full
        local tag = tags[r - 1]
        local dim = false

        -- the name column (nothing over it in the top row: the icons start right of it)
        if tag then
            local nm = Get(self.names)
            nm:ClearAnchors()
            nm:SetAnchor(TOPLEFT, self.root, TOPLEFT, 0, y)
            nm:SetDimensions(nameW, rowH)
            D.Solid(nm.bg, bg[1], bg[2], bg[3], (db.nameAlpha or 30) / 100)
            nm.text:SetFont(fontName)
            -- the role's icon before the name (tank, healer, damage)
            local icon = db.roleIcons and RoleIcon(tag)
            local ri = D.OnPx(m * 0.8)
            nm.role:ClearAnchors()
            nm.role:SetAnchor(LEFT, nm, LEFT, D.OnPx(3), 0)
            nm.role:SetDimensions(ri, ri)
            nm.role:SetHidden(not icon)
            if icon then nm.role:SetTexture(icon) end
            local textX = icon and (D.OnPx(3) + ri + D.OnPx(3)) or D.OnPx(5)
            nm.text:ClearAnchors()
            nm.text:SetAnchor(LEFT, nm, LEFT, textX, 0)
            nm.text:SetWidth(nameW - textX - D.OnPx(3))
            local name = db.accountNames and GetUnitDisplayName(tag) or zo_strformat("<<1>>", GetUnitName(tag))
            if SKT.IsTestTag(tag) then name = SKT.TestName(tag) end
            dim = not SKT.IsTestTag(tag) and (IsUnitDead(tag) or not IsUnitOnline(tag))
            nm.text:SetText(name or "")
            nm.text:SetColor(dim and 0.55 or 0.92, dim and 0.55 or 0.92, dim and 0.6 or 0.95, 1)
        end

        for c = 1, cols do
            local x = nameW + (c - 1) * s
            local k = Key(list[c])
            local f = Get(self.cells)
            f:ClearAnchors()
            f:SetAnchor(TOPLEFT, self.root, TOPLEFT, x, y)
            f:SetDimensions((c == cols) and (s - trim) or s, rowH)
            D.Solid(f.bg, 0, 0, 0, CELL_BG_ALPHA)
            f.num:SetFont(fontNum)
            f.num:ClearAnchors()
            f.num:SetAnchor(CENTER, f, TOPLEFT, s / 2, full / 2 + numDown)
            f.dash:ClearAnchors()
            f.dash:SetAnchor(CENTER, f, TOPLEFT, s / 2, full / 2)
            f.dash:SetDimensions(D.OnPx(m * 0.32), math.max(px, D.OnPx(m * 0.06)))
            D.Solid(f.dash, 0.75, 0.76, 0.8, 0.8)
            f.entry, f.ending, f.started = nil, nil, nil
            f.cellW = (c == cols) and (s - trim) or s
            f.green:ClearAnchors()
            f.green:SetAnchorFill(f)
            f:SetAlpha(1)

            local function NoSweep()
                if f.cdKey then f.cd:ResetCooldown(); f.cdKey = nil end
                f.cd:SetHidden(true)
            end
            if not tag then
                -- the top row: each effect's icon, its name in a tooltip
                f.tex:SetTexture(db.icons[k] or UNKNOWN_ICON)
                f.tex:SetHidden(false)
                f.tex:SetDesaturation(0)
                f.green:SetHidden(true)
                NoSweep()
                f.dash:SetHidden(true)
                f.num:SetText("")
                f.tip = list[c]
                f:SetMouseEnabled(db.locked)
            else
                local h = self.has[tag] and self.has[tag][k]
                f.tip = nil
                f:SetMouseEnabled(false)
                f.tex:SetHidden(true)
                if h then
                    D.Solid(f.green, HAS_GREEN[1], HAS_GREEN[2], HAS_GREEN[3], HAS_ALPHA)
                    f.dash:SetHidden(true)
                    if not h.permanent and h.ending > now then
                        -- full green when gained, draining from the right: the green (left) is
                        -- what's left, the black the time used (moved along in :Tick)
                        NoSweep()
                        f.ending, f.started = h.ending, h.started
                        f.green:ClearAnchors()
                        f.green:SetAnchor(TOPLEFT, f, TOPLEFT, 0, 0)
                        f.green:SetAnchor(BOTTOMLEFT, f, BOTTOMLEFT, 0, 0)
                        f.green:SetHidden(false)
                    else
                        f.green:SetHidden(false)
                        NoSweep()
                    end
                    if dim then f:SetAlpha(0.6) end
                else
                    f.green:SetHidden(true)
                    NoSweep()
                    f.dash:SetHidden(false)
                    f.num:SetText("")
                end
            end
            if c < cols then Line(x + s - px, y, px, rowH) end
        end
        if tag then Line(nameW - px, y, px, rowH) end
        if not lastRow then
            -- under the top row only below the icons (the frame draws the name column's top)
            if tag then Line(0, y + full - px, W, px) else Line(nameW, y + s - px, W - nameW, px) end
        end
    end
    Done(self.cells); Done(self.names); Done(self.lines)

    self.root:SetDimensions(W, H)
    self:Outline(W, H, nameW, s)
    self.root:ClearAnchors()
    self.root:SetAnchor(TOPLEFT, GuiRoot, CENTER, D.OnPx(G.SnapOne(db.x)), D.OnPx(G.SnapOne(db.y)))
    self.root:SetMouseEnabled(not db.locked)
    self.tag:SetHidden(db.locked)
    local state = self.fragment:GetState()
    self.root:SetHidden(not (state == SCENE_FRAGMENT_SHOWN or state == SCENE_FRAGMENT_SHOWING))
    self:Tick(now)
end

-- the frame: a pixel outside the panel's edge, following its step (the icon row starts right of
-- the name column), with rounded corners at the icon row's top left and top right, the name
-- column's top left, and the bottom two; the inner corner of the step is square
function Gp:Outline(W, H, nameW, s)
    local t = D.Px()
    local C = 2 * t
    local function Place(tex, x, y, w, h)
        tex:ClearAnchors()
        tex:SetAnchor(TOPLEFT, self.root, TOPLEFT, x, y)
        tex:SetDimensions(math.max(0.01, w), math.max(0.01, h))
        D.Solid(tex, 1, 1, 1, 1)
        tex:SetHidden(false)
    end
    local e, d = self.edges, self.dots
    Place(e[1], nameW - t + C, -t, (W - nameW + 2 * t) - 2 * C, t)        -- top of the icon row
    Place(e[2], W, -t + C, t, H + 2 * t - 2 * C)                          -- right
    Place(e[3], -t + C, H, W + 2 * t - 2 * C, t)                          -- bottom
    Place(e[4], -t, s - t + C, t, (H - s + 2 * t) - 2 * C)                -- left of the names
    Place(e[5], -t + C, s - t, nameW - C, t)                              -- top of the names
    Place(e[6], nameW - t, -t + C, t, s - C)                              -- left of the icon row
    Place(d[1], nameW, 0, t, t)                                           -- rounded corners
    Place(d[2], W - t, 0, t, t)
    Place(d[3], 0, s, t, t)
    Place(d[4], 0, H - t, t, t)
    Place(d[5], W - t, H - t, t, t)
end

local function Secs(secs)
    if secs >= 60 then return math.floor(secs / 60 + 0.5) .. "m" end
    if secs >= 1 then return tostring(math.floor(secs + 0.5)) end
    return string.format("%.1f", secs)
end

function Gp:Tick(now)
    now = now or GetFrameTimeSeconds()
    local again = false
    local show = self.db.timers
    for i = 1, #self.cells.list do
        local f = self.cells.list[i]
        if not f:IsHidden() and f.ending then
            local left = f.ending - now
            f.num:SetText((show and left > 0) and Secs(left) or "")
            local total = math.max(0.1, f.ending - (f.started or f.ending))
            local frac = math.max(0, math.min(1, left / total))
            f.green:SetWidth(math.max(0.01, (f.cellW or 0) * frac))
            f.green:SetHidden(frac <= 0)
            if left <= 0 and SKT:TestSize() > 0 then again = true end
        end
    end
    if again and not self.testQueued then
        self.testQueued = true
        zo_callLater(function() self.testQueued = false; self:Refresh() end, 50)
    end
end

---------------------------------------------------------------------------
-- Settings, lock, events
---------------------------------------------------------------------------
function Gp:SetList(list)
    self.db.list = list
    self.watch = {}
    for _, name in ipairs(list) do self.watch[Key(name)] = true end
    self:Refresh()
end

function Gp:Queue()
    if self.queued then return end
    self.queued = true
    zo_callLater(function() self.queued = false; self:Refresh() end, 150)
end

function Gp:ApplyLock()
    self:Refresh()
    SKT.Grid:Update()
end

function Gp:ApplyEnabled()
    local on = self.db.enabled
    if on and not self.fragmentAdded then
        HUD_SCENE:AddFragment(self.fragment)
        HUD_UI_SCENE:AddFragment(self.fragment)
        self.fragmentAdded = true
    elseif not on and self.fragmentAdded then
        HUD_SCENE:RemoveFragment(self.fragment)
        HUD_UI_SCENE:RemoveFragment(self.fragment)
        self.fragmentAdded = false
    end
    self:Refresh()
end

function Gp:RegisterEvents()
    local function Q() self:Queue() end
    EM:RegisterForEvent(NS, EVENT_EFFECT_CHANGED, Q)
    if REGISTER_FILTER_UNIT_TAG_PREFIX then
        EM:AddFilterForEvent(NS, EVENT_EFFECT_CHANGED, REGISTER_FILTER_UNIT_TAG_PREFIX, "group")
    end
    local n = 0
    for _, ev in pairs({ EVENT_GROUP_MEMBER_JOINED, EVENT_GROUP_MEMBER_LEFT, EVENT_GROUP_UPDATE,
                          EVENT_GROUP_MEMBER_ROLE_CHANGED,
                          EVENT_GROUP_MEMBER_CONNECTED_STATUS, EVENT_UNIT_DEATH_STATE_CHANGED,
                          EVENT_PLAYER_ACTIVATED }) do
        if ev then n = n + 1; EM:RegisterForEvent(NS .. n, ev, Q) end
    end
    -- solo (showing yourself): your own effects
    EM:RegisterForEvent(NS .. "Self", EVENT_EFFECT_CHANGED, function()
        if GetGroupSize() == 0 then Q() end
    end)
    EM:AddFilterForEvent(NS .. "Self", EVENT_EFFECT_CHANGED, REGISTER_FILTER_UNIT_TAG, "player")
    EM:RegisterForUpdate(NS .. "Tick", 33, function() self:Tick() end)   -- smooth drain
    EM:RegisterForEvent(NS .. "Combat", EVENT_PLAYER_COMBAT_STATE, function() self:Refresh() end)
    EM:RegisterForEvent(NS .. "Scale", EVENT_ALL_GUI_SCREENS_RESIZED, function() self:Render() end)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
SKT:RegisterModule({
    key   = "Group",
    title = "Group",
    order = 24,

    defaults = {
        enabled = true,
        locked  = true,
        visibility = "always",  -- in a group: "always" or "combat"
        sortRoles = true,       -- tanks, then healers, then damage dealers
        roleIcons = true,       -- the role's icon before each name
        accountNames = false,   -- @names instead of character names
        timers = true,
        size = 24,
        nameWidth = 120,
        nameAlpha = 30,         -- % opacity of the name cells' background
        x = -640, y = -200,     -- top left, from the middle of the screen
        icons = {},             -- effect name (lower case) -> icon, learnt in play
    },

    OnLoad = function(self, db)
        Gp.db = db
        if type(db.list) ~= "table" then db.list = {} ; for i, v in ipairs(DEFAULT_LIST) do db.list[i] = v end end
        if type(db.icons) ~= "table" then db.icons = {} end
        Gp:Build()
        Gp:RegisterEvents()
        Gp:SetList(db.list)
        Gp:ApplyEnabled()
    end,

    BuildTab = function(self, page, db)
        local UI = SKT.UI
        local L = UI.Column(page, 16, 268)
        local R = UI.Column(page, 316, 268)
        local function render() Gp:Refresh() end

        L:Header("Group buffs")
        L:Check("Enable", function() return db.enabled end, function(v) db.enabled = v; Gp:ApplyEnabled() end)
        L:ChoiceRow({ { "always", "Always" }, { "combat", "In combat" } },
            function() return db.visibility or "always" end, function(v) db.visibility = v; render() end)
        L:Space(6)
        L:Check("Account names (@name)", function() return db.accountNames end,
            function(v) db.accountNames = v; render() end)
        L:Check("Sort by role", function() return db.sortRoles end,
            function(v) db.sortRoles = v; render() end, "Tanks first, then healers, then damage dealers.")
        L:Check("Role icons", function() return db.roleIcons end,
            function(v) db.roleIcons = v; render() end)
        L:Check("Time left", function() return db.timers end, function(v) db.timers = v; render() end)

        L:Header("Size")
        L:Slider("Cell width", 16, 48, 1,
            function() return db.size end, function(v) db.size = v; render() end, SKT.Grid.Fmt)
        L:Slider("Cell height", 8, 48, 1,
            function() return db.rowHeight or db.size end, function(v) db.rowHeight = v; render() end,
            SKT.Grid.Fmt)
        L:Slider("Name width", 48, 240, 8,
            function() return db.nameWidth end, function(v) db.nameWidth = v; render() end, SKT.Grid.Fmt)
        L:Slider("Name background opacity", 0, 100, 5,
            function() return db.nameAlpha or 30 end, function(v) db.nameAlpha = v; render() end,
            function(v) return v .. "%" end)

        -- the watched effects, in column order: add by name, move up and down, remove
        R:Header("Watched effects")
        local RX, top = R.x, R.y
        local bd = WM:CreateControlFromVirtual(page:GetName() .. "EditBG", page, "ZO_EditBackdrop")
        bd:SetAnchor(TOPLEFT, page, TOPLEFT, RX, top)
        bd:SetDimensions(180, 28)
        local eb = WM:CreateControlFromVirtual(page:GetName() .. "Edit", bd, "ZO_DefaultEditForBackdrop")
        eb:SetMaxInputChars(60)

        local rowsUI = {}
        local function Fill()
            for i, r in ipairs(rowsUI) do
                local name = db.list[i]
                r.label:SetText(name or "")
                r.label:SetHidden(not name)
                r.btn:SetHidden(not name)
                r.up:SetHidden(not name or i == 1)
                r.down:SetHidden(not name or i == #db.list)
            end
        end
        local function Add()
            local text = zo_strtrim(eb:GetText() or "")
            if text == "" then return end
            for _, v in ipairs(db.list) do if Key(v) == Key(text) then eb:SetText("") return end end
            if #db.list >= #rowsUI then SKT:Print("The list is full.") return end
            local list = db.list
            list[#list + 1] = text
            eb:SetText("")
            Gp:SetList(list)
            Fill()
        end
        eb:SetHandler("OnEnter", Add)
        UI.Button(page, "Add", RX + 188, top, "Add", 80, Add)

        local function Swap(a, b)
            local list = db.list
            if not list[a] or not list[b] then return end
            list[a], list[b] = list[b], list[a]
            Gp:SetList(list)
            Fill()
        end
        for i = 1, 12 do
            local y = top + 38 + (i - 1) * 30
            local label = SKT.MakeLabel(page:GetName() .. "Item" .. i, page, "", "ZoFontGame", SKT.colors.text)
            label:SetAnchor(TOPLEFT, page, TOPLEFT, RX, y + 4)
            label:SetDimensions(104, 22)
            label:SetMaxLineCount(1)
            label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
            local up = UI.Button(page, "Up" .. i, RX + 106, y, "Up", 44, function() Swap(i, i - 1) end)
            local down = UI.Button(page, "Down" .. i, RX + 152, y, "Down", 56, function() Swap(i, i + 1) end)
            local btn = UI.Button(page, "Del" .. i, RX + 210, y, "Remove", 62, function()
                table.remove(db.list, i)
                Gp:SetList(db.list)
                Fill()
            end)
            rowsUI[i] = { label = label, btn = btn, up = up, down = down }
        end
        Fill()
    end,
})
