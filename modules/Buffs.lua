--[[-------------------------------------------------------------------------
  SKTools-ESO by Scotskoogen-Chris
  Buffs: the effects on you.

    Buffs      rows: Major, Minor          growing left from their right edge
    Debuffs    rows: Major, Minor          growing right from their left edge
    Other buffs (growing left), Other debuffs (growing right):
               everything that is neither Major nor Minor (skill buffs, set
               procs, food...)
    Instance   (its own element and tab) rows: buffs, debuffs, growing out from its centre:
               inside dungeons, trials and arenas, the effects the instance
               itself and its enemies put on you

  Each row is a strip of icons in the Essentials style (flush, thin white
  lines that neighbours share, rounded outer corners), as long as it has
  effects; the rows sit flush on each other, lined up on the side they grow
  from. The time left sits in the middle of each icon, stacks in the top
  right; in its last 3 seconds an icon blinks. Empty rows close up; an
  empty panel hides. Unlock to place them (box by box on the grid).
---------------------------------------------------------------------------]]

local SKT = SKT
local D   = SKT.Draw
local WM  = WINDOW_MANAGER
local EM  = EVENT_MANAGER
local NS  = "SKToolsESO_Buffs"

local B = {}
SKT.Buffs = B
local I = {}                -- the Instance element: its own settings, lock and tab
SKT.Instance = I
B.sources = {}              -- abilityId -> who put it on you (COMBAT_UNIT_TYPE_*)

local PANELS = {
    { key = "buffs",    grow = "left",  rows = { "major", "minor" }, name = "Buffs" },
    { key = "debuffs",  grow = "right", rows = { "major", "minor" }, name = "Debuffs" },
    { key = "otherBuffs",   grow = "left",   rows = { "buff" }, name = "Other buffs" },
    { key = "otherDebuffs", grow = "right",  rows = { "debuff" }, name = "Other debuffs" },
    { key = "instance", grow = "centre", rows = { "buff", "debuff" }, name = "Instance effects" },
}

---------------------------------------------------------------------------
-- Sorting the effects on you
---------------------------------------------------------------------------
local function InInstance()
    if IsUnitInDungeon and IsUnitInDungeon("player") then return true end
    if IsPlayerInRaid and IsPlayerInRaid() then return true end
    if GetCurrentZoneDungeonDifficulty and DUNGEON_DIFFICULTY_NONE
       and GetCurrentZoneDungeonDifficulty() ~= DUNGEON_DIFFICULTY_NONE then return true end
    return false
end

local function Grade(name)
    local n = zo_strformat("<<1>>", name or "")
    if n:find("^Major ") then return "major" end
    if n:find("^Minor ") then return "minor" end
    return "other"
end

-- from an enemy or the world (not you, your group, your pets)
local function FromInstance(abilityId, castByPlayer)
    if castByPlayer then return false end
    local src = B.sources[abilityId]
    return src == COMBAT_UNIT_TYPE_OTHER or src == COMBAT_UNIT_TYPE_NONE
end

function B:Collect()
    local out = {
        buffs = { major = {}, minor = {} },
        debuffs = { major = {}, minor = {} },
        otherBuffs = { buff = {} },
        otherDebuffs = { debuff = {} },
        instance = { buff = {}, debuff = {} },
    }
    local separate = I.db and I.db.enabled and InInstance()
    for i = 1, GetNumBuffs("player") do
        local name, started, ending, slot, stacks, icon, _, effectType, _, _, abilityId, _, castByPlayer =
            GetUnitBuffInfo("player", i)
        if name and name ~= "" then
            local permanent = not ending or ending <= started
            local e = { name = name, icon = icon, started = started, ending = ending, stacks = stacks or 0,
                        permanent = permanent, id = abilityId, slot = slot }
            local debuff = (effectType == BUFF_EFFECT_TYPE_DEBUFF)
            local grade = Grade(name)
            if separate and grade == "other" and FromInstance(abilityId, castByPlayer) then
                table.insert(out.instance[debuff and "debuff" or "buff"], e)
            elseif grade ~= "other" then
                table.insert(out[debuff and "debuffs" or "buffs"][grade], e)
            elseif not permanent or self.db.showPermanent then
                if debuff then table.insert(out.otherDebuffs.debuff, e)
                else table.insert(out.otherBuffs.buff, e) end
            end
        end
    end
    -- the soonest to run out nearest the side the row grows from, then those that don't run out
    local function Order(a, b)
        if a.permanent ~= b.permanent then return not a.permanent end
        if not a.permanent and a.ending ~= b.ending then return a.ending < b.ending end
        return a.name < b.name
    end
    for _, p in pairs(out) do for _, list in pairs(p) do table.sort(list, Order) end end
    return out
end

---------------------------------------------------------------------------
-- A panel
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
    f.num = WM:CreateControl(nil, f, CT_LABEL)
    f.num:SetColor(1, 1, 1, 1)
    f.num:SetDrawLevel(6)
    f.stack = WM:CreateControl(nil, f, CT_LABEL)
    f.stack:SetColor(1, 1, 1, 1)
    f.stack:SetDrawLevel(6)
    -- the game's own tooltip for the effect, while the cursor is over it
    f:SetHandler("OnMouseEnter", function(c)
        local e = c.effect
        if not e then return end
        InitializeTooltip(GameTooltip, c, BOTTOM, 0, -6, TOP)
        if e.slot and GameTooltip.SetBuff then
            GameTooltip:SetBuff(e.slot, "player")
        elseif e.id then
            GameTooltip:SetAbilityId(e.id)
        end
    end)
    f:SetHandler("OnMouseExit", function() ClearTooltip(GameTooltip) end)
    return f
end

local function Pool(make, parent)
    return { list = {}, n = 0, make = make, parent = parent }
end
local function Get(pool)
    pool.n = pool.n + 1
    local c = pool.list[pool.n]
    if not c then c = pool.make(pool.parent); pool.list[pool.n] = c end
    if c.SetHidden then c:SetHidden(false) end
    return c
end
local function Done(pool)
    for i = pool.n + 1, #pool.list do
        local c = pool.list[i]
        if c.SetHidden then c:SetHidden(true)
        else
            for _, t in ipairs(c.edges) do t:SetHidden(true) end
            for _, t in ipairs(c.dots) do t:SetHidden(true) end
        end
    end
    pool.n = 0
end

-- the settings a panel follows: the Instance element has its own
function B:Cfg(p)
    return (p.def.key == "instance") and I.db or self.db
end

-- where a panel sits: x is the edge it grows from, y its top (from the middle of the screen)
function B:Pos(p)
    if p.def.key == "instance" then return I.db end
    return self.db.pos[p.def.key]
end

function B:BuildPanel(def)
    local p = { def = def }
    local root = WM:CreateTopLevelWindow(NS .. def.key)
    root:SetClampedToScreen(true)
    root:SetMouseEnabled(false)
    p.root = root
    p.icons = Pool(MakeIcon, root)
    p.lines = Pool(function(par) return D.Tex(par, 8) end, root)
    p.rings = Pool(function(par) return D.NewRing(par, 9) end, root)
    p.tag = SKT.Grid.Tag(root, def.name)

    local drag
    SKT.Grid.Draggable(root, {
        start = function() local pos = self:Pos(p); drag = { x = pos.x, y = pos.y } end,
        move = function(dx, dy)
            local pos = self:Pos(p)
            pos.x, pos.y = drag.x + dx, drag.y + dy
            self:Render(p)
        end,
        stop = function()
            local G, pos = SKT.Grid, self:Pos(p)
            pos.x, pos.y = G.SnapOne(pos.x), G.SnapOne(pos.y)
            self:Render(p)
        end,
    })

    p.fragment = ZO_HUDFadeSceneFragment:New(root)
    p.fragment:RegisterCallback("StateChange", function(_, newState)
        if newState == SCENE_FRAGMENT_SHOWN then self:Render(p) end
    end)
    return p
end

function B:PanelOn(p)
    local key = p.def.key
    if key == "instance" then return I.db.enabled end
    return self.db.enabled and self.db.show[key]
end

-- lay a panel out from the effects in its rows
function B:Render(p)
    local cfg, G = self:Cfg(p), SKT.Grid
    local key = p.def.key
    local data = self.data and self.data[key] or {}

    -- the rows with something in them (all of them, with empty places, while unlocked)
    local rows = {}
    for _, r in ipairs(p.def.rows) do
        local list = data[r] or {}
        if #list > 0 or not cfg.locked then
            rows[#rows + 1] = { list = list, n = (#list > 0) and #list or 4 }
        end
    end

    if not self:PanelOn(p) or #rows == 0 then
        p.icons.n, p.lines.n, p.rings.n = 0, 0, 0
        Done(p.icons); Done(p.lines); Done(p.rings)
        p.root:SetHidden(true)
        p.shown = false
        return
    end

    local trim = G.Trim()
    local px = D.Px()
    local s = D.OnPx(G.Boxes(cfg.size))
    local left = (p.def.grow == "left")
    local centre = (p.def.grow == "centre")
    local maxN = 1
    for _, r in ipairs(rows) do maxN = math.max(maxN, r.n) end
    local W = maxN * s - trim
    local H = #rows * s - trim

    local fontNum = "$(BOLD_FONT)|" .. math.max(9, math.floor(s * 0.42)) .. "|thick-outline"
    local fontStack = "$(BOLD_FONT)|" .. math.max(8, math.floor(s * 0.3)) .. "|thick-outline"
    local numDown = D.OnPx(math.floor(s * 0.42) * 0.14)

    local function Line(x, y, w, h)
        local t = Get(p.lines)
        t:ClearAnchors()
        t:SetAnchor(TOPLEFT, p.root, TOPLEFT, x, y)
        t:SetDimensions(w, h)
        D.Solid(t, 1, 1, 1, 1)
    end

    p.icons.n, p.lines.n, p.rings.n = 0, 0, 0
    for ri, r in ipairs(rows) do
        local y = (ri - 1) * s
        local rowW = r.n * s - trim
        local rowH = (ri == #rows) and (s - trim) or s
        -- a row's left edge: flush left, flush right when the panel grows left, centred when it
        -- grows from its centre (on whole icons, so the grid still lines up when it can)
        local x0 = left and (W - rowW) or 0
        if centre then x0 = math.floor((maxN - r.n) / 2) * s + (((maxN - r.n) % 2 == 1) and s / 2 or 0) end
        for c = 1, r.n do
            -- the soonest to run out sits next to the side the row grows from
            local slot = left and (r.n - c + 1) or c
            local e = r.list[slot]
            local f = Get(p.icons)
            f:ClearAnchors()
            f:SetAnchor(TOPLEFT, p.root, TOPLEFT, x0 + (c - 1) * s, y)
            f:SetDimensions((c == r.n) and (s - trim) or s, rowH)
            f.num:SetFont(fontNum)
            f.num:ClearAnchors()
            f.num:SetAnchor(CENTER, f, TOPLEFT, s / 2, s / 2 + numDown)
            f.stack:SetFont(fontStack)
            f.stack:ClearAnchors()
            f.stack:SetAnchor(TOPRIGHT, f, TOPLEFT, s - D.OnPx(2), 0)
            f.effect = e
            -- tooltips while locked (unlocked, the panel is dragged instead)
            f:SetMouseEnabled(cfg.locked and e ~= nil)
            if e then
                f.tex:SetTexture(e.icon)
                f.tex:SetHidden(false)
                f.stack:SetText((e.stacks and e.stacks > 1) and tostring(e.stacks) or "")
            else
                f.tex:SetHidden(true)
                f.stack:SetText("")
                f.num:SetText("")
            end
            f:SetAlpha(1)
            if c < r.n then Line(x0 + c * s - px, y, px, rowH) end
        end
        -- each row its own frame; rows sit flush, sharing the line between them
        local ring = Get(p.rings)
        D.DrawRing(ring, p.root, x0, y, rowW, rowH, D.White)
    end
    Done(p.icons); Done(p.lines); Done(p.rings)

    p.root:SetDimensions(W, H)
    local pos = self:Pos(p)
    local x, y = G.SnapOne(pos.x), G.SnapOne(pos.y)
    p.root:ClearAnchors()
    if left then
        -- the right edge on its grid line (its frame line just inside it)
        p.root:SetAnchor(TOPRIGHT, GuiRoot, CENTER, D.OnPx(x - trim), D.OnPx(y))
    elseif centre then
        p.root:SetAnchor(TOP, GuiRoot, CENTER, D.OnPx(x - trim / 2), D.OnPx(y))
    else
        p.root:SetAnchor(TOPLEFT, GuiRoot, CENTER, D.OnPx(x), D.OnPx(y))
    end
    p.root:SetMouseEnabled(not cfg.locked)
    p.tag:SetHidden(cfg.locked)
    -- shown only while its HUD fragment is up (not over the map or menus)
    local state = p.fragment:GetState()
    p.root:SetHidden(not (state == SCENE_FRAGMENT_SHOWN or state == SCENE_FRAGMENT_SHOWING))
    p.shown = true
    self:TickPanel(p, GetFrameTimeSeconds())
end

---------------------------------------------------------------------------
-- Timers
---------------------------------------------------------------------------
local function Secs(secs)
    if secs >= 3600 then return math.floor(secs / 3600 + 0.5) .. "h" end
    if secs >= 60 then return math.floor(secs / 60 + 0.5) .. "m" end
    if secs >= 1 then return tostring(math.floor(secs + 0.5)) end
    return string.format("%.1f", secs)
end

function B:TickPanel(p, now)
    local cfg = self:Cfg(p)
    for i = 1, p.icons.n > 0 and p.icons.n or #p.icons.list do
        local f = p.icons.list[i]
        local e = f and not f:IsHidden() and f.effect
        if e and not e.permanent then
            local left = e.ending - now
            f.num:SetText((cfg.timers and left > 0) and Secs(left) or "")
            if cfg.blink and left > 0 and left <= 3 then
                f:SetAlpha(0.45 + 0.55 * math.abs(math.cos(left * math.pi * 1.5)))
            else
                f:SetAlpha(1)
            end
        elseif e then
            f.num:SetText("")
        end
    end
end

function B:Tick()
    local now = GetFrameTimeSeconds()
    for _, p in ipairs(self.panels) do
        if p.shown then self:TickPanel(p, now) end
    end
end

---------------------------------------------------------------------------
-- Refresh, lock, events
---------------------------------------------------------------------------
function B:Refresh()
    if not self.panels then return end
    self.data = self:Collect()
    for _, p in ipairs(self.panels) do self:Render(p) end
end

function B:Queue()
    if self.queued then return end
    self.queued = true
    zo_callLater(function() self.queued = false; self:Refresh() end, 60)
end

function B:ApplyLock()
    self:Refresh()
    SKT.Grid:Update()
end

function B:ApplyEnabled()
    for _, p in ipairs(self.panels) do
        local on = self:PanelOn(p)
        if on and not p.fragmentAdded then
            HUD_SCENE:AddFragment(p.fragment)
            HUD_UI_SCENE:AddFragment(p.fragment)
            p.fragmentAdded = true
        elseif not on and p.fragmentAdded then
            HUD_SCENE:RemoveFragment(p.fragment)
            HUD_UI_SCENE:RemoveFragment(p.fragment)
            p.fragmentAdded = false
        end
    end
    self:Refresh()
end

function I:ApplyLock() B:ApplyLock() end

function B:RegisterEvents()
    EM:RegisterForEvent(NS, EVENT_EFFECT_CHANGED, function(_, change, _, _, _, _, _, _, _, _, _, _, _, _, _,
                                                         abilityId, sourceType)
        if change ~= EFFECT_RESULT_FADED and abilityId then self.sources[abilityId] = sourceType end
        self:Queue()
    end)
    EM:AddFilterForEvent(NS, EVENT_EFFECT_CHANGED, REGISTER_FILTER_UNIT_TAG, "player")
    EM:RegisterForEvent(NS .. "Act", EVENT_PLAYER_ACTIVATED, function() self:Refresh() end)
    EM:RegisterForEvent(NS .. "Scale", EVENT_ALL_GUI_SCREENS_RESIZED, function() self:Refresh() end)
    EM:RegisterForUpdate(NS .. "Tick", 100, function() self:Tick() end)
end

-- built once both modules have their settings
local function Start()
    if B.started or not (B.db and I.db) then return end
    B.started = true
    B.panels = {}
    for _, def in ipairs(PANELS) do B.panels[#B.panels + 1] = B:BuildPanel(def) end
    B:RegisterEvents()
    B:ApplyEnabled()
end

local function LookOptions(col, cfg, refresh)
    col:Header("Look")
    col:Slider("Icon size", 20, 64, 1,
        function() return cfg.size end, function(v) cfg.size = v; refresh() end, SKT.Grid.Fmt)
    col:Check("Time left", function() return cfg.timers end, function(v) cfg.timers = v; refresh() end)
    col:Check("Blink in the last 3 seconds", function() return cfg.blink end, function(v) cfg.blink = v; refresh() end)
end

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------
SKT:RegisterModule({
    key   = "Buffs",
    title = "Buffs",
    order = 22,

    defaults = {
        enabled = true,
        locked  = true,
        show = { buffs = true, debuffs = true, otherBuffs = true, otherDebuffs = true },
        showPermanent = false,  -- effects that never run out, in the Other panel
        size = 32,
        timers = true,
        blink = true,
        -- x: the edge each grows from, y: its top; from the middle of the screen
        pos = {
            buffs   = { x = -16,  y = 160 },
            debuffs = { x = 16,   y = 160 },
            otherBuffs   = { x = 0, y = 248 },   -- the Other panels: their centres
            otherDebuffs = { x = 0, y = 296 },
        },
    },

    OnLoad = function(self, db)
        B.db = db
        if type(db.show) ~= "table" then db.show = {} end
        if db.show.otherBuffs == nil then db.show.otherBuffs = (db.show.other ~= false) end
        if db.show.otherDebuffs == nil then db.show.otherDebuffs = (db.show.other ~= false) end
        local DEF = { buffs = { -16, 160 }, debuffs = { 16, 160 }, otherBuffs = { 0, 248 }, otherDebuffs = { 0, 296 } }
        for k, v in pairs(DEF) do
            if type(db.pos[k]) ~= "table" then db.pos[k] = { x = v[1], y = v[2] } end
        end
        -- 0.13.0 kept top-left corners: start the new layout from its defaults
        if db.layoutVersion ~= 2 then
            db.pos.buffs = { x = -16, y = 160 }
            db.pos.debuffs = { x = 16, y = 160 }
            db.layoutVersion = 2
        end
        -- 0.16.0's single Other panel: its place goes to the Other buffs panel
        if type(db.pos.other) == "table" and not db.otherSplit then
            db.pos.otherBuffs = { x = db.pos.other.x, y = db.pos.other.y }
            db.pos.otherDebuffs = { x = db.pos.other.x, y = db.pos.other.y + 48 }
        end
        db.otherSplit = true
        Start()
    end,

    BuildTab = function(self, page, db)
        local L = SKT.UI.Column(page, 16, 268)
        local R = SKT.UI.Column(page, 316, 268)
        local function refresh() B:Refresh() end

        L:Header("Effects on you")
        L:Check("Enable", function() return db.enabled end, function(v) db.enabled = v; B:ApplyEnabled() end)

        L:Header("Panels")
        L:Check("Buffs", function() return db.show.buffs end,
            function(v) db.show.buffs = v; B:ApplyEnabled() end, "Major and Minor buffs.")
        L:Check("Debuffs", function() return db.show.debuffs end,
            function(v) db.show.debuffs = v; B:ApplyEnabled() end, "Major and Minor debuffs.")
        L:Check("Other buffs", function() return db.show.otherBuffs end,
            function(v) db.show.otherBuffs = v; B:ApplyEnabled() end)
        L:Check("Other debuffs", function() return db.show.otherDebuffs end,
            function(v) db.show.otherDebuffs = v; B:ApplyEnabled() end)
        L:Check("Effects that never run out", function() return db.showPermanent end,
            function(v) db.showPermanent = v; refresh() end,
            "Passives, set bonuses, mundus and the like, in the Other panels.")

        LookOptions(R, db, refresh)
    end,
})

SKT:RegisterModule({
    key   = "Instance",
    title = "Instance",
    order = 23,

    defaults = {
        enabled = true,
        locked  = true,
        size = 40,
        timers = true,
        blink = true,
        x = 0, y = -320,        -- centre and top, from the middle of the screen
    },

    OnLoad = function(self, db)
        I.db = db
        if type(db.x) ~= "number" then db.x = -80 end
        if type(db.y) ~= "number" then db.y = -320 end
        Start()
    end,

    BuildTab = function(self, page, db)
        local L = SKT.UI.Column(page, 16, 268)
        local R = SKT.UI.Column(page, 316, 268)
        local function refresh() B:Refresh() end

        L:Header("Instance effects")
        L:Check("Enable", function() return db.enabled end, function(v) db.enabled = v; B:ApplyEnabled() end,
            "In dungeons, trials and arenas: the effects the instance and its enemies put on you.")

        LookOptions(R, db, refresh)
    end,
})
