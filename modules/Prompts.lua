--[[-------------------------------------------------------------------------
  SKTools-ESO by Scotskoogen-Chris
  Prompts: two of the game's on-screen prompts that ESO's own HUD editor can't move, made movable
  with the rest of SKTools (unlock, drag, snap to the grid):

    Player interaction   the prompt for other players: group invites, duels, trades, the
                         target's name over it (ZO_PlayerToPlayerArea's prompt)
    Instance warning     "You will be removed from this instance" with its countdown and the
                         leave-now key (ZO_InstanceKickWarning, alive and dead versions)

  Until one is moved it stays where the game puts it. While unlocked each shows a box in its place
  to drag; Reset puts it back where the game had it.
---------------------------------------------------------------------------]]

local SKT = SKT
local D   = SKT.Draw
local WM  = WINDOW_MANAGER
local EM  = EVENT_MANAGER
local NS  = "SKToolsESO_Prompts"

local Pr = {}
SKT.Prompts = Pr

-- each prompt: the game's controls to move, the box's size, and where the game puts it (the
-- bottom middle of the box, from the middle of the screen)
local PROMPTS = {
    {
        key = "interact", title = "Player interaction", w = 420, h = 70,
        controls = function() return { ZO_PlayerToPlayerAreaPromptContainer } end,
        default = function() return 0, GuiRoot:GetHeight() / 2 - 285 end,
    },
    {
        key = "kick", title = "Instance warning", w = 420, h = 70,
        controls = function()
            return { ZO_InstanceKickWarning_AliveContainer, ZO_InstanceKickWarning_DeadContainer }
        end,
        default = function()
            local off = ZO_COMMON_INFO_DEFAULT_KEYBOARD_BOTTOM_OFFSET_Y or -100
            if IsInGamepadPreferredMode and IsInGamepadPreferredMode() then
                off = ZO_COMMON_INFO_DEFAULT_GAMEPAD_BOTTOM_OFFSET_Y or off
            end
            return 0, GuiRoot:GetHeight() / 2 + off
        end,
    },
}

-- where a prompt is now: moved (saved), or the game's own place
function Pr:Pos(p)
    local pos = self.db.pos[p.key]
    if type(pos) == "table" then return pos.x, pos.y, true end
    local x, y = p.default()
    return x, y, false
end

-- the box: where the prompt goes; shown (with its name) only while unlocked
function Pr:Build(p)
    local box = WM:CreateTopLevelWindow(NS .. p.key)
    box:SetClampedToScreen(true)
    box:SetDimensions(p.w, p.h)
    box:SetDrawTier(DT_HIGH)
    box.bg = D.Tex(box, 1); box.bg:SetAnchorFill(box)
    D.Solid(box.bg, 0.05, 0.07, 0.14, 0.55)
    box.ring = D.NewRing(box, 2)
    box.text = WM:CreateControl(nil, box, CT_LABEL)
    box.text:SetFont("$(MEDIUM_FONT)|16|soft-shadow-thin")
    box.text:SetColor(0.92, 0.92, 0.95, 1)
    box.text:SetText(p.title)
    box.text:SetAnchor(CENTER, box, CENTER, 0, 0)
    box.tag = SKT.Grid.Tag(box, p.title)
    p.box = box

    local drag
    SKT.Grid.Draggable(box, {
        start = function()
            local x, y = self:Pos(p)
            drag = { x = x, y = y }
        end,
        move = function(dx, dy)
            self.db.pos[p.key] = { x = drag.x + dx, y = drag.y + dy }
            self:Place(p)
        end,
        stop = function()
            local G, pos = SKT.Grid, self.db.pos[p.key]
            if pos then pos.x, pos.y = G.SnapOne(pos.x), G.SnapOne(pos.y) end
            self:Place(p)
        end,
    })
end

-- the box where the prompt is, the game's controls on it (once moved)
function Pr:Place(p)
    local x, y, moved = self:Pos(p)
    local box = p.box
    box:ClearAnchors()
    box:SetAnchor(BOTTOM, GuiRoot, CENTER, D.OnPx(x), D.OnPx(y))
    D.DrawRing(box.ring, box, 0, 0, p.w, p.h, D.White)
    local unlocked = self.db.enabled and not self.db.locked
    box:SetHidden(not unlocked)
    box:SetMouseEnabled(unlocked)
    box.tag:SetHidden(not unlocked)
    if self.db.enabled and moved then
        for _, c in ipairs(p.controls()) do
            if c then
                c:ClearAnchors()
                c:SetAnchor(BOTTOM, box, BOTTOM, 0, 0)
            end
        end
    end
end

-- back where the game had it (its own anchors, as its code sets them)
function Pr:Restore(p)
    if p.key == "interact" then
        local c = ZO_PlayerToPlayerAreaPromptContainer
        if c then c:ClearAnchors(); c:SetAnchor(BOTTOM, ZO_PlayerToPlayerArea, BOTTOM, 0, -285) end
    else
        local _, y = p.default()
        local off = y - GuiRoot:GetHeight() / 2
        for _, c in ipairs(p.controls()) do
            if c then c:ClearAnchors(); c:SetAnchor(BOTTOM, c:GetParent(), BOTTOM, 0, off) end
        end
    end
end

function Pr:PlaceAll()
    for _, p in ipairs(PROMPTS) do
        if not self.db.enabled and type(self.db.pos[p.key]) == "table" then self:Restore(p) end
        self:Place(p)
    end
    SKT.Grid:Update()
end

-- the game puts them back on some changes (gamepad mode, loading): put them where they belong
function Pr:Queue()
    zo_callLater(function() self:PlaceAll() end, 100)
end

function Pr:ApplyLock() self:PlaceAll() end

SKT:RegisterModule({
    key   = "Prompts",
    title = "Prompts",
    order = 26,

    defaults = {
        enabled = true,
        locked  = true,
        pos     = {},        -- key -> { x, y } (bottom middle, from the middle of the screen); unset: the game's place
    },

    OnLoad = function(self, db)
        Pr.db = db
        if type(db.pos) ~= "table" then db.pos = {} end
        for _, p in ipairs(PROMPTS) do Pr:Build(p) end
        local n = 0
        for _, ev in pairs({ EVENT_PLAYER_ACTIVATED, EVENT_GAMEPAD_PREFERRED_MODE_CHANGED,
                             EVENT_INSTANCE_KICK_TIME_UPDATE, EVENT_ALL_GUI_SCREENS_RESIZED }) do
            if ev then n = n + 1; EM:RegisterForEvent(NS .. n, ev, function() Pr:Queue() end) end
        end
        Pr:PlaceAll()
    end,

    BuildTab = function(self, page, db)
        local L = SKT.UI.Column(page, 16, 268)
        L:Header("Prompts")
        L:Check("Enable", function() return db.enabled end, function(v) db.enabled = v; Pr:PlaceAll() end)
        L:Header("Reset position")
        for _, p in ipairs(PROMPTS) do
            L:Button(p.title, 200, function()
                db.pos[p.key] = nil
                Pr:Restore(p)
                Pr:Place(p)
            end)
        end
    end,
})
