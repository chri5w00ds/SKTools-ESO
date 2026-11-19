--[[-------------------------------------------------------------------------
  SKTools-ESO by Scotskoogen-Chris
  CC notifier: a banner naming the crowd control on you and what gets you
  out of it, with a sound.

    Stunned, knocked down, feared, charmed, disoriented, levitated
        -> BREAK FREE
    Rooted (immobilized)
        -> ROLL DODGE
    Snared, silenced (off by default: they come often and Break Free
    doesn't remove them)
        -> shown with what helps

  The action is the big word, so the two cases read apart at a glance by
  their words (and their marks: » BREAK FREE « points in, « ROLL DODGE » points out), not only by
  colour. Under it: the CC and the ability that caused it, the ability's
  icon on the left, and a bar draining over the CC's duration.

  Unlock to place it (box by box on the grid) and set its size.
---------------------------------------------------------------------------]]

local SKT = SKT
local D   = SKT.Draw
local WM  = WINDOW_MANAGER
local EM  = EVENT_MANAGER
local NS  = "SKToolsESO_CC"

local C = {}
SKT.CC = C

local BREAK, DODGE, OTHER = "break", "dodge", "other"

-- result -> the CC's name, what gets you out, and the setting that turns it on
local KINDS = {}
local function Kind(result, name, action, setting, help)
    if result then KINDS[result] = { name = name, action = action, setting = setting, help = help } end
end
Kind(ACTION_RESULT_STUNNED,     "Stunned",      BREAK, "hard")
Kind(ACTION_RESULT_KNOCKBACK,   "Knocked down", BREAK, "hard")
Kind(ACTION_RESULT_FEARED,      "Feared",       BREAK, "hard")
Kind(ACTION_RESULT_CHARMED,     "Charmed",      BREAK, "hard")
Kind(ACTION_RESULT_DISORIENTED, "Disoriented",  BREAK, "hard")
Kind(ACTION_RESULT_LEVITATED,   "Levitated",    BREAK, "hard")
Kind(ACTION_RESULT_ROOTED,      "Rooted",       DODGE, "root")
Kind(ACTION_RESULT_IMMOBILIZED, "Immobilized",  DODGE, "root")
Kind(ACTION_RESULT_SNARED,      "Snared",       OTHER, "snare", "SNARE BREAK / PURGE")
Kind(ACTION_RESULT_SILENCED,    "Silenced",     OTHER, "silence", "MOVE OUT / PURGE")

local ACTION_TEXT = {
    [BREAK] = "» BREAK FREE «",
    [DODGE] = "« ROLL DODGE »",
}
local ACTION_COLOR = {
    [BREAK] = { 0.95, 0.42, 0.40 },     -- pastel red
    [DODGE] = { 0.45, 0.72, 0.92 },     -- pastel blue
    [OTHER] = { 0.86, 0.78, 0.52 },     -- pastel gold
}

---------------------------------------------------------------------------
-- The banner
---------------------------------------------------------------------------
function C:Build()
    local db = self.db
    local root = WM:CreateTopLevelWindow(NS)
    root:SetClampedToScreen(true)
    root:SetMouseEnabled(false)
    root:SetHidden(true)
    root:SetDrawLayer(DL_OVERLAY)
    self.root = root

    self.bg = D.Tex(root, 1)
    self.bg:SetAnchorFill(root)

    self.icon = WM:CreateControl(nil, root, CT_TEXTURE)
    self.icon:SetTextureCoords(0.08, 0.92, 0.08, 0.92)
    self.icon:SetDrawLevel(2)
    self.iconLine = D.Tex(root, 3)

    self.action = WM:CreateControl(nil, root, CT_LABEL)
    self.action:SetDrawLevel(4)
    self.what = WM:CreateControl(nil, root, CT_LABEL)
    self.what:SetDrawLevel(4)
    self.what:SetColor(0.85, 0.87, 0.92, 1)

    self.track = D.Tex(root, 2)
    self.fill = D.Tex(root, 3)

    self.ring = D.NewRing(root, 9)
    self.tag = SKT.Grid.Tag(root, "CC alert")

    local drag
    SKT.Grid.Draggable(root, {
        start = function() drag = { x = db.x, y = db.y } end,
        move = function(dx, dy)
            db.x, db.y = drag.x + dx, drag.y + dy
            self:Layout()
        end,
        stop = function()
            local G = SKT.Grid
            local w = D.OnPx(G.Boxes(db.width))
            db.x = G.SnapOne(db.x - w / 2) + w / 2
            db.y = G.SnapOne(db.y)
            self:Layout()
        end,
    })
end

function C:Layout()
    if not self.root then return end
    local db, G = self.db, SKT.Grid
    local trim = G.Trim()
    local fullW = D.OnPx(G.Boxes(db.width))
    local fullH = D.OnPx(G.Boxes(db.height))
    local w, h = fullW - trim, fullH - trim
    local px = D.Px()
    self.root:SetDimensions(w, h)
    self.w, self.h = w, h

    local c = SKT.colors.bg
    D.Solid(self.bg, c[1], c[2], c[3], (db.bgAlpha or 85) / 100)

    -- the icon: a square on the left, a line between it and the text
    local isz = h
    self.icon:ClearAnchors()
    self.icon:SetAnchor(TOPLEFT, self.root, TOPLEFT, 0, 0)
    self.icon:SetDimensions(isz, h)
    self.iconLine:ClearAnchors()
    self.iconLine:SetAnchor(TOPLEFT, self.root, TOPLEFT, isz - px, 0)
    self.iconLine:SetDimensions(px, h)
    D.Solid(self.iconLine, 1, 1, 1, 0.9)

    -- the duration bar along the bottom
    local bh = D.OnPx(math.max(2 * px, h * 0.1))
    self.track:ClearAnchors()
    self.track:SetAnchor(BOTTOMLEFT, self.root, BOTTOMLEFT, isz, 0)
    self.track:SetDimensions(w - isz, bh)
    D.Solid(self.track, 0, 0, 0, 0.6)
    self.fill:ClearAnchors()
    self.fill:SetAnchor(BOTTOMLEFT, self.root, BOTTOMLEFT, isz, 0)
    self.fill:SetHeight(bh)
    self.barW = w - isz

    -- the words, centred in the space right of the icon
    local big = math.max(12, math.floor(h * 0.42))
    local small = math.max(10, math.floor(h * 0.2))
    self.action:SetFont("$(BOLD_FONT)|" .. big .. "|thick-outline")
    self.what:SetFont("$(MEDIUM_FONT)|" .. small .. "|soft-shadow-thick")
    local cx = isz + (w - isz) / 2
    self.action:ClearAnchors()
    self.action:SetAnchor(CENTER, self.root, TOPLEFT, cx, h * 0.40)
    self.what:ClearAnchors()
    self.what:SetAnchor(CENTER, self.root, TOPLEFT, cx, h * 0.76)

    D.DrawRing(self.ring, self.root, 0, 0, w, h, function(f)
        local t, b = { 0.94, 0.94, 0.96 }, { 0.58, 0.59, 0.63 }
        return t[1] + (b[1] - t[1]) * f, t[2] + (b[2] - t[2]) * f, t[3] + (b[3] - t[3]) * f
    end)

    self.root:ClearAnchors()
    local left = G.SnapOne((db.x or 0) - fullW / 2)
    local top = G.SnapOne(db.y or -200)
    self.root:SetAnchor(TOPLEFT, GuiRoot, CENTER, D.OnPx(left), D.OnPx(top))
end

-- show a CC: kind (from KINDS), the ability's name and icon, how long (seconds)
function C:Show(kind, abilityName, icon, secs, preview)
    local col = ACTION_COLOR[kind.action]
    self.action:SetText(ACTION_TEXT[kind.action] or kind.help or kind.name)
    self.action:SetColor(col[1], col[2], col[3], 1)
    local what = kind.name
    if abilityName and abilityName ~= "" then what = what .. "  ·  " .. zo_strformat("<<1>>", abilityName) end
    self.what:SetText(what)
    self.icon:SetTexture((icon and icon ~= "") and icon or "/esoui/art/icons/icon_missing.dds")
    D.Solid(self.fill, col[1], col[2], col[3], 1)

    self.kind = kind
    self.start = GetFrameTimeSeconds()
    self.stop = self.start + (secs or 3)
    self.preview = preview
    self.root:SetHidden(false)
    self:Tick()
    EM:RegisterForUpdate(NS .. "Tick", 0, function() self:Tick() end)

    if not preview and self.db.sound then
        SKT.PlaySoundKey(kind.action == DODGE and self.db.soundDodge or self.db.soundBreak)
    end
end

function C:Hide()
    if self.preview and not self.db.locked then return end
    self.kind, self.preview = nil, nil
    EM:UnregisterForUpdate(NS .. "Tick")
    self.root:SetHidden(true)
end

function C:Tick()
    local now = GetFrameTimeSeconds()
    if self.preview then
        -- the preview loops its bar
        local f = 1 - ((now - self.start) % 4) / 4
        self.fill:SetWidth(math.max(0.01, self.barW * f))
        return
    end
    if now >= self.stop then self:Hide() return end
    local f = (self.stop - now) / (self.stop - self.start)
    self.fill:SetWidth(math.max(0.01, self.barW * f))
end

function C:ShowPreview()
    self:Show(KINDS[ACTION_RESULT_STUNNED] or { name = "Stunned", action = BREAK },
        "Example ability", nil, 4, true)
end

function C:ApplyLock()
    local locked = self.db.locked
    self.root:SetMouseEnabled(not locked)
    self.tag:SetHidden(locked)
    if locked then
        if self.preview then self.preview = nil; self:Hide() end
    else
        self:Layout()
        self:ShowPreview()
    end
    SKT.Grid:Update()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- CC you put on yourself (mounting, resurrecting, changing armory builds and the like) and CC from
-- the world while out of combat are not an enemy's: no alert
local function SelfInflicted(sourceType, sourceUnitId, targetUnitId, abilityName)
    if sourceType == COMBAT_UNIT_TYPE_PLAYER or sourceType == COMBAT_UNIT_TYPE_PLAYER_PET then return true end
    if sourceUnitId and targetUnitId and sourceUnitId ~= 0 and sourceUnitId == targetUnitId then return true end
    if (sourceType == COMBAT_UNIT_TYPE_NONE or sourceType == nil) and not IsUnitInCombat("player") then return true end
    if not abilityName or abilityName == "" then return true end
    return false
end

local function OnCC(_, result, isError, abilityName, abilityGraphic, _, _, sourceType, _, _, hitValue,
                    _, _, _, sourceUnitId, targetUnitId, abilityId)
    local db = C.db
    if isError or not db.enabled then return end
    if SelfInflicted(sourceType, sourceUnitId, targetUnitId, abilityName) then return end
    local kind = KINDS[result]
    if not kind or not db[kind.setting] then return end
    -- a weaker CC doesn't replace a Break Free banner that is still up
    if C.kind and C.kind.action == BREAK and kind.action ~= BREAK and GetFrameTimeSeconds() < (C.stop or 0) then
        return
    end
    local secs = (hitValue and hitValue > 0 and hitValue < 60000) and (hitValue / 1000) or (db.fallback or 3)
    local icon = (abilityGraphic and abilityGraphic ~= "") and abilityGraphic or (abilityId and GetAbilityIcon(abilityId))
    C:Show(kind, abilityName, icon, secs)
end

function C:RegisterEvents()
    for result in pairs(KINDS) do
        local id = NS .. result
        EM:RegisterForEvent(id, EVENT_COMBAT_EVENT, OnCC)
        EM:AddFilterForEvent(id, EVENT_COMBAT_EVENT,
            REGISTER_FILTER_COMBAT_RESULT, result,
            REGISTER_FILTER_TARGET_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER)
    end
    -- the game says when a hard CC ends (broken free, or run out)
    if EVENT_PLAYER_STUNNED_STATE_CHANGED then
        EM:RegisterForEvent(NS .. "Stun", EVENT_PLAYER_STUNNED_STATE_CHANGED, function(_, stunned)
            if not stunned and C.kind and C.kind.action == BREAK then C:Hide() end
        end)
    end
    EM:RegisterForEvent(NS .. "Dead", EVENT_PLAYER_DEAD, function() C:Hide() end)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
SKT:RegisterModule({
    key   = "CC",
    title = "CC alert",
    order = 25,

    defaults = {
        enabled = true,
        locked  = true,
        x = 0, y = -200,          -- top centre, from the middle of the screen
        width = 320, height = 56,
        bgAlpha = 85,
        hard = true,              -- stuns, knockdowns, fears, charms, disorients
        root = true,              -- roots and immobilizes
        snare = false,
        silence = false,
        fallback = 3,             -- seconds shown when the game gives no duration
        sound = true,
        soundBreak = "DUEL_START",
        soundDodge = "QUEST_FOCUSED",
    },

    OnLoad = function(self, db)
        C.db = db
        local NUM = { x = 0, y = -200, width = 320, height = 56, bgAlpha = 85, fallback = 3 }
        for k, v in pairs(NUM) do if type(db[k]) ~= "number" then db[k] = v end end
        C:Build()
        C:RegisterEvents()
        C:Layout()
        C:ApplyLock()
    end,

    BuildTab = function(self, page, db)
        local L = SKT.UI.Column(page, 16, 268)
        local R = SKT.UI.Column(page, 316, 268)
        local function relayout() C:Layout() end

        L:Header("CC alert")
        L:Check("Enable", function() return db.enabled end,
            function(v) db.enabled = v; if not v then C:Hide() end end)

        L:Header("Show for")
        L:Check("Stuns, knockdowns, fears", function() return db.hard end, function(v) db.hard = v end,
            "Break Free: stuns, knockdowns, fears, charms, disorients.")
        L:Check("Roots", function() return db.root end, function(v) db.root = v end,
            "Roll Dodge: roots and immobilizes.")
        L:Check("Snares", function() return db.snare end, function(v) db.snare = v end)
        L:Check("Silences", function() return db.silence end, function(v) db.silence = v end)

        L:Header("Size")
        L:Slider("Width", 120, 640, 8,
            function() return db.width end, function(v) db.width = v; relayout() end, SKT.Grid.Fmt)
        L:Slider("Height", 24, 160, 4,
            function() return db.height end, function(v) db.height = v; relayout() end, SKT.Grid.Fmt)
        L:Slider("Background opacity", 0, 100, 5,
            function() return db.bgAlpha end, function(v) db.bgAlpha = v; relayout() end,
            function(v) return v .. "%" end)
        L:Button("Reset position", 180, function() db.x, db.y = 0, -200; relayout() end)

        R:Header("Sound")
        R:Check("Play a sound", function() return db.sound end, function(v) db.sound = v end)
        R:Space(6)
        SKT.MakeLabel(page:GetName() .. "SndBreakLabel", page, "Break Free", "ZoFontGame", SKT.colors.gold)
            :SetAnchor(TOPLEFT, page, TOPLEFT, R.x, R.y)
        R:Space(26)
        R:Space(SKT.UI.SoundPicker(page, R:Id(), R.x, R.y,
            function() return db.soundBreak end, function(v) db.soundBreak = v end))
        R:Space(10)
        SKT.MakeLabel(page:GetName() .. "SndDodgeLabel", page, "Roll Dodge", "ZoFontGame", SKT.colors.gold)
            :SetAnchor(TOPLEFT, page, TOPLEFT, R.x, R.y)
        R:Space(26)
        R:Space(SKT.UI.SoundPicker(page, R:Id(), R.x, R.y,
            function() return db.soundDodge end, function(v) db.soundDodge = v end))
    end,
})
