--[[-------------------------------------------------------------------------
  SKTools-ESO by Scotskoogen-Chris
  Synergy cooldowns: for tanks, which group member can take which synergy.

  A synergy has a 20 second cooldown for the player who took it, and every
  morph of a skill shares that cooldown (Spear Shards and Necrotic Orb's
  synergies share one too). So the columns are synergy families: taking any
  synergy in a family starts that member's 20 seconds for the whole family.

  Same look as the group buffs: one row per group member (tanks, healers,
  then damage dealers, with role icons), one column per family with its
  icon on top (names in a tooltip; learnt the first time anyone takes one).
  Ready: the cell is green. Just taken: dark, with the skill bars' cooldown
  sweep and the seconds left until it's green again.

  Shown while you're queued as a tank (or always, if you choose). The
  families are a list you edit in the Synergy tab: a name, then the
  synergies in it separated by commas.
---------------------------------------------------------------------------]]

local SKT = SKT
local D   = SKT.Draw
local WM  = WINDOW_MANAGER
local EM  = EVENT_MANAGER
local NS  = "SKToolsESO_Synergy"

local Sy = {}
SKT.Synergy = Sy

local COOLDOWN = 20
local UNKNOWN_ICON = "/esoui/art/icons/icon_missing.dds"
local READY = { 0.48, 0.80, 0.50 }      -- the group buffs' green
local READY_ALPHA = 0.7

-- families: a name and the synergies in it (each shares one cooldown)
local DEFAULT_FAMILIES = {
    { name = "Orbs and Shards", list = "Combustion, Healing Combustion, Blessed Shards, Holy Shards, Spear Shards" },
    { name = "Conduit",         list = "Conduit" },
    { name = "Blood Altar",     list = "Blood Funnel, Blood Feast" },
    { name = "Harvest",         list = "Harvest" },
    { name = "Bone Wall",       list = "Bone Wall, Spinal Surge" },
    { name = "Grave Robber",    list = "Grave Robber, Pure Agony" },
    { name = "Shackle",         list = "Shackle" },
    { name = "Ignite",          list = "Ignite" },
}

local function Key(name) return zo_strlower(zo_strformat("<<1>>", name or "")) end

-- synergy name -> family index
function Sy:Index()
    self.byName = {}
    for i, f in ipairs(self.db.families) do
        for part in string.gmatch(f.list or "", "[^,]+") do
            local k = Key(zo_strtrim(part))
            if k ~= "" then self.byName[k] = i end
        end
    end
end

---------------------------------------------------------------------------
-- Who took what
---------------------------------------------------------------------------
Sy.cd = {}       -- member name (lower case) -> { [family] = { start, stop } }

local function MemberKey(name) return Key(name) end

function Sy:OnSynergy(sourceName, abilityName, icon)
    local fam = self.byName and self.byName[Key(abilityName)]
    if not fam then return end
    local who = MemberKey(sourceName)
    if who == "" then return end
    local now = GetFrameTimeSeconds()
    local mine = self.cd[who] or {}
    self.cd[who] = mine
    -- the first hit of a use starts the cooldown; later hits of the same use don't move it
    local c = mine[fam]
    if c and now < c.stop then return end
    mine[fam] = { start = now, stop = now + COOLDOWN }
    local fk = Key(self.db.families[fam].name)
    if icon and icon ~= "" and not self.db.icons[fk] then self.db.icons[fk] = icon end
    self:Queue()
end

function Sy:Members()
    local tags = {}
    local n = GetGroupSize()
    if n and n > 0 then
        for i = 1, n do
            local tag = GetGroupUnitTagByIndex(i)
            if tag and DoesUnitExist(tag) then tags[#tags + 1] = tag end
        end
    elseif not self.db.locked then
        tags[1] = "player"
    end
    if #tags > 1 and SKT.Group and SKT.Group.RoleRank then
        local order = {}
        for i, tag in ipairs(tags) do order[tag] = i end
        table.sort(tags, function(a, b)
            local ra, rb = SKT.Group.RoleRank(a), SKT.Group.RoleRank(b)
            if ra ~= rb then return ra < rb end
            return order[a] < order[b]
        end)
    end
    return tags
end

local function IAmTank()
    if GetSelectedLFGRole and GetSelectedLFGRole() == LFG_ROLE_TANK then return true end
    return GetGroupMemberSelectedRole and GetGroupMemberSelectedRole("player") == LFG_ROLE_TANK
end

---------------------------------------------------------------------------
-- The grid
---------------------------------------------------------------------------
local function Pool(make, parent) return { list = {}, n = 0, make = make, parent = parent } end
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
    f.bg = D.Tex(f, 1); f.bg:SetAnchorFill(f)
    f.tex = WM:CreateControl(nil, f, CT_TEXTURE)
    f.tex:SetAnchorFill(f)
    f.tex:SetTextureCoords(0.08, 0.92, 0.08, 0.92)
    f.tex:SetDrawLevel(2)
    f.green = D.Tex(f, 2); f.green:SetAnchorFill(f)
    f.cd = WM:CreateControl(nil, f, CT_COOLDOWN)
    f.cd:SetAnchorFill(f)
    f.cd:SetDrawLevel(4)
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
    f.bg = D.Tex(f, 1); f.bg:SetAnchorFill(f)
    f.role = WM:CreateControl(nil, f, CT_TEXTURE)
    f.role:SetDrawLevel(3)
    f.text = WM:CreateControl(nil, f, CT_LABEL)
    f.text:SetDrawLevel(3)
    f.text:SetMaxLineCount(1)
    f.text:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    return f
end

function Sy:Build()
    local db = self.db
    local root = WM:CreateTopLevelWindow(NS)
    root:SetClampedToScreen(true)
    root:SetMouseEnabled(false)
    self.root = root
    self.cells = Pool(MakeCell, root)
    self.names = Pool(MakeName, root)
    self.lines = Pool(function(p) return D.Tex(p, 8) end, root)
    self.edges, self.dots = {}, {}
    for i = 1, 6 do self.edges[i] = D.Tex(root, 9) end
    for i = 1, 5 do self.dots[i] = D.Tex(root, 9) end
    self.tag = SKT.Grid.Tag(root, "Synergy cooldowns")

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

function Sy:Refresh()
    if not self.root then return end
    self.tags = self:Members()
    self:Render()
end

function Sy:Queue()
    if self.queued then return end
    self.queued = true
    zo_callLater(function() self.queued = false; self:Refresh() end, 100)
end

function Sy:Render()
    local db, G = self.db, SKT.Grid
    local tags = self.tags or {}
    local fams = db.families
    local roleOk = (not db.tankOnly) or IAmTank() or not db.locked
    if not db.enabled or not roleOk or #tags == 0 or #fams == 0 then
        self.cells.n, self.names.n, self.lines.n = 0, 0, 0
        Done(self.cells); Done(self.names); Done(self.lines)
        self.root:SetHidden(true)
        return
    end

    local trim = G.Trim()
    local px = D.Px()
    local s = D.OnPx(G.Boxes(db.size))
    local nameW = D.OnPx(G.Boxes(db.nameWidth))
    local cols, rows = #fams, #tags + 1
    local W = nameW + cols * s - trim
    local H = rows * s - trim
    local bg = SKT.colors.bg
    local fontName = "$(MEDIUM_FONT)|" .. math.max(10, math.floor(s * 0.5)) .. "|soft-shadow-thin"
    local fontNum = "$(BOLD_FONT)|" .. math.max(8, math.floor(s * 0.42)) .. "|thick-outline"
    local numDown = D.OnPx(math.floor(s * 0.42) * 0.14)
    local now = GetFrameTimeSeconds()
    local sk = SKT.Skills and SKT.Skills.db
    local sweepAlpha = ((sk and sk.gcdAlpha) or 62) / 100

    self.cells.n, self.names.n, self.lines.n = 0, 0, 0
    local function Line(x, y, w, h)
        local t = Get(self.lines)
        t:ClearAnchors()
        t:SetAnchor(TOPLEFT, self.root, TOPLEFT, x, y)
        t:SetDimensions(w, h)
        D.Solid(t, 1, 1, 1, 1)
    end

    for r = 1, rows do
        local y = (r - 1) * s
        local lastRow = (r == rows)
        local rowH = lastRow and (s - trim) or s
        local tag = tags[r - 1]
        local who

        if tag then
            local nm = Get(self.names)
            nm:ClearAnchors()
            nm:SetAnchor(TOPLEFT, self.root, TOPLEFT, 0, y)
            nm:SetDimensions(nameW, rowH)
            D.Solid(nm.bg, bg[1], bg[2], bg[3], 0.92)
            nm.text:SetFont(fontName)
            local icon = SKT.Group and SKT.Group.RoleIcon and SKT.Group.RoleIcon(tag)
            local ri = D.OnPx(s * 0.8)
            nm.role:ClearAnchors()
            nm.role:SetAnchor(LEFT, nm, LEFT, D.OnPx(3), 0)
            nm.role:SetDimensions(ri, ri)
            nm.role:SetHidden(not icon)
            if icon then nm.role:SetTexture(icon) end
            local textX = icon and (D.OnPx(6) + ri) or D.OnPx(5)
            nm.text:ClearAnchors()
            nm.text:SetAnchor(LEFT, nm, LEFT, textX, 0)
            nm.text:SetWidth(nameW - textX - D.OnPx(3))
            local name = zo_strformat("<<1>>", GetUnitName(tag))
            nm.text:SetText(name)
            nm.text:SetColor(0.92, 0.92, 0.95, 1)
            who = self.cd[MemberKey(GetUnitName(tag))]
        end

        for c = 1, cols do
            local x = nameW + (c - 1) * s
            local fam = fams[c]
            local f = Get(self.cells)
            f:ClearAnchors()
            f:SetAnchor(TOPLEFT, self.root, TOPLEFT, x, y)
            f:SetDimensions((c == cols) and (s - trim) or s, rowH)
            D.Solid(f.bg, 0, 0, 0, 0.4)
            f.num:SetFont(fontNum)
            f.num:ClearAnchors()
            f.num:SetAnchor(CENTER, f, TOPLEFT, s / 2, s / 2 + numDown)
            f.stop = nil
            if not tag then
                -- the top row: each family's icon, its synergies in a tooltip
                f.tex:SetTexture(db.icons[Key(fam.name)] or UNKNOWN_ICON)
                f.tex:SetHidden(false)
                f.green:SetHidden(true)
                f.cd:SetHidden(true)
                f.num:SetText("")
                f.tip = fam.name .. "\n" .. (fam.list or "")
                f:SetMouseEnabled(db.locked)
            else
                f.tip = nil
                f:SetMouseEnabled(false)
                f.tex:SetHidden(true)
                D.Solid(f.green, READY[1], READY[2], READY[3], READY_ALPHA)
                f.green:SetHidden(false)
                local cdv = who and who[c]
                if cdv and now < cdv.stop then
                    -- cooling down: the skill bars' sweep over the green, the seconds in the middle
                    f.stop = cdv.stop
                    f.cd:SetFillColor(0, 0, 0, math.max(0.5, sweepAlpha))
                    local key = cdv.start .. ":" .. cdv.stop
                    if f.cdKey ~= key then
                        f.cd:StartCooldown((cdv.stop - now) * 1000, COOLDOWN * 1000,
                            CD_TYPE_RADIAL, CD_TIME_TYPE_TIME_UNTIL, false)
                        f.cdKey = key
                    end
                    f.cd:SetHidden(false)
                else
                    if f.cdKey then f.cd:ResetCooldown(); f.cdKey = nil end
                    f.cd:SetHidden(true)
                    f.num:SetText("")
                end
            end
            if c < cols then Line(x + s - px, y, px, rowH) end
        end
        if tag then Line(nameW - px, y, px, rowH) end
        if not lastRow then
            if tag then Line(0, y + s - px, W, px) else Line(nameW, y + s - px, W - nameW, px) end
        end
    end
    Done(self.cells); Done(self.names); Done(self.lines)

    self.root:SetDimensions(W, H)
    if SKT.Group and SKT.Group.Outline then SKT.Group.Outline(self, W, H, nameW, s) end
    self.root:ClearAnchors()
    self.root:SetAnchor(TOPLEFT, GuiRoot, CENTER, D.OnPx(G.SnapOne(db.x)), D.OnPx(G.SnapOne(db.y)))
    self.root:SetMouseEnabled(not db.locked)
    self.tag:SetHidden(db.locked)
    local state = self.fragment:GetState()
    self.root:SetHidden(not (state == SCENE_FRAGMENT_SHOWN or state == SCENE_FRAGMENT_SHOWING))
    self:Tick(now)
end

local function Secs(secs)
    if secs >= 1 then return tostring(math.floor(secs + 0.5)) end
    return string.format("%.1f", secs)
end

function Sy:Tick(now)
    now = now or GetFrameTimeSeconds()
    local again = false
    for i = 1, #self.cells.list do
        local f = self.cells.list[i]
        if not f:IsHidden() and f.stop then
            local left = f.stop - now
            if left > 0 then
                f.num:SetText(Secs(left))
            else
                again = true   -- one just came off cooldown: back to green
            end
        end
    end
    if again then self:Render() end
end

---------------------------------------------------------------------------
-- Lock, events
---------------------------------------------------------------------------
function Sy:ApplyLock()
    self:Refresh()
    SKT.Grid:Update()
end

function Sy:ApplyEnabled()
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

function Sy:RegisterEvents()
    -- a synergy taken by a group member (or you): the taker is the source
    local function OnCombat(_, result, isError, abilityName, abilityGraphic, _, sourceName)
        if isError or not abilityName or abilityName == "" then return end
        self:OnSynergy(sourceName, abilityName, abilityGraphic)
    end
    for i, unitType in pairs({ COMBAT_UNIT_TYPE_GROUP, COMBAT_UNIT_TYPE_PLAYER }) do
        local id = NS .. "Combat" .. i
        EM:RegisterForEvent(id, EVENT_COMBAT_EVENT, OnCombat)
        EM:AddFilterForEvent(id, EVENT_COMBAT_EVENT, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, unitType)
    end
    local function Q() self:Queue() end
    local n = 0
    for _, ev in pairs({ EVENT_GROUP_MEMBER_JOINED, EVENT_GROUP_MEMBER_LEFT, EVENT_GROUP_UPDATE,
                         EVENT_GROUP_MEMBER_ROLE_CHANGED, EVENT_PLAYER_ACTIVATED }) do
        if ev then n = n + 1; EM:RegisterForEvent(NS .. n, ev, Q) end
    end
    EM:RegisterForUpdate(NS .. "Tick", 100, function() self:Tick() end)
    EM:RegisterForEvent(NS .. "Scale", EVENT_ALL_GUI_SCREENS_RESIZED, function() self:Render() end)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
SKT:RegisterModule({
    key   = "Synergy",
    title = "Synergy",
    order = 24.5,

    defaults = {
        enabled = true,
        locked  = true,
        tankOnly = true,        -- only while you're queued as a tank
        size = 24,
        nameWidth = 120,
        x = -640, y = 40,       -- top left, from the middle of the screen
        icons = {},             -- family name (lower case) -> icon, learnt in play
    },

    OnLoad = function(self, db)
        Sy.db = db
        if type(db.families) ~= "table" then
            db.families = {}
            for i, f in ipairs(DEFAULT_FAMILIES) do db.families[i] = { name = f.name, list = f.list } end
        end
        if type(db.icons) ~= "table" then db.icons = {} end
        Sy:Index()
        Sy:Build()
        Sy:RegisterEvents()
        Sy:ApplyEnabled()
    end,

    BuildTab = function(self, page, db)
        local UI = SKT.UI
        local L = UI.Column(page, 16, 268)
        local R = UI.Column(page, 316, 268)
        local function render() Sy:Refresh() end

        L:Header("Synergy cooldowns")
        L:Check("Enable", function() return db.enabled end, function(v) db.enabled = v; Sy:ApplyEnabled() end)
        L:Check("Only when I'm the tank", function() return db.tankOnly end,
            function(v) db.tankOnly = v; render() end)

        L:Header("Size")
        L:Slider("Cell size", 16, 48, 1,
            function() return db.size end, function(v) db.size = v; render() end, SKT.Grid.Fmt)
        L:Slider("Name width", 48, 240, 8,
            function() return db.nameWidth end, function(v) db.nameWidth = v; render() end, SKT.Grid.Fmt)

        -- the families: a name, then its synergies separated by commas
        R:Header("Synergy families")
        local RX, top = R.x, R.y
        local function Edit(name, x, y, w)
            local bd = WM:CreateControlFromVirtual(page:GetName() .. name .. "BG", page, "ZO_EditBackdrop")
            bd:SetAnchor(TOPLEFT, page, TOPLEFT, x, y)
            bd:SetDimensions(w, 28)
            local eb = WM:CreateControlFromVirtual(page:GetName() .. name, bd, "ZO_DefaultEditForBackdrop")
            eb:SetMaxInputChars(200)
            return eb
        end
        local nameBox = Edit("FamName", RX, top, 268)
        nameBox:SetDefaultText("Name, e.g. Orbs and Shards")
        local listBox = Edit("FamList", RX, top + 34, 268)
        listBox:SetDefaultText("Synergies, e.g. Combustion, Holy Shards")

        local rowsUI = {}
        local function Fill()
            for i, r in ipairs(rowsUI) do
                local f = db.families[i]
                r.label:SetText(f and f.name or "")
                r.label:SetHidden(not f)
                r.btn:SetHidden(not f)
                r.up:SetHidden(not f or i == 1)
                r.down:SetHidden(not f or i == #db.families)
                r.tipText = f and f.list or nil
            end
        end
        local function Changed()
            Sy:Index()
            Sy:Refresh()
            Fill()
        end
        local function Add()
            local name = zo_strtrim(nameBox:GetText() or "")
            local list = zo_strtrim(listBox:GetText() or "")
            if name == "" then return end
            if list == "" then list = name end
            if #db.families >= #rowsUI then SKT:Print("The list is full.") return end
            db.families[#db.families + 1] = { name = name, list = list }
            nameBox:SetText(""); listBox:SetText("")
            Changed()
        end
        listBox:SetHandler("OnEnter", Add)
        UI.Button(page, "FamAdd", RX, top + 68, "Add family", 140, Add)

        local function Swap(a, b)
            local f = db.families
            if not f[a] or not f[b] then return end
            f[a], f[b] = f[b], f[a]
            Changed()
        end
        for i = 1, 10 do
            local y = top + 108 + (i - 1) * 30
            local label = SKT.MakeLabel(page:GetName() .. "Fam" .. i, page, "", "ZoFontGame", SKT.colors.text)
            label:SetAnchor(TOPLEFT, page, TOPLEFT, RX, y + 4)
            label:SetDimensions(104, 22)
            label:SetMaxLineCount(1)
            label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
            label:SetMouseEnabled(true)
            local row = { label = label }
            label:SetHandler("OnMouseEnter", function(c)
                if not row.tipText then return end
                InitializeTooltip(InformationTooltip, c, BOTTOM, 0, -6, TOP)
                SetTooltipText(InformationTooltip, row.tipText)
            end)
            label:SetHandler("OnMouseExit", function() ClearTooltip(InformationTooltip) end)
            row.up = UI.Button(page, "FamUp" .. i, RX + 106, y, "Up", 44, function() Swap(i, i - 1) end)
            row.down = UI.Button(page, "FamDown" .. i, RX + 152, y, "Down", 56, function() Swap(i, i + 1) end)
            row.btn = UI.Button(page, "FamDel" .. i, RX + 210, y, "Remove", 62, function()
                table.remove(db.families, i)
                Changed()
            end)
            rowsUI[i] = row
        end
        Fill()
    end,
})
