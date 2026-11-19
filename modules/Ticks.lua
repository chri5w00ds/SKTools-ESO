--[[-------------------------------------------------------------------------
  SKTools-ESO by Scotskoogen-Chris
  Stamina ticks: when the next stamina regeneration tick is due.

  Stamina comes back in ticks, every 2 seconds in combat. Blocking or
  sprinting at the moment of a tick gives nothing back, but the timer runs
  on. A spark sweeps across the stamina bar from left to right, reaching the
  right end as the tick lands, then starts again.

  An optional sound plays a set time before each tick.

  The timer locks onto the real ticks: a stamina gain about the size of your
  stamina recovery (or one landing when a tick is due) counts as a tick and
  sets the timer, and the time between ticks is measured.
---------------------------------------------------------------------------]]

local SKT = SKT
local D   = SKT.Draw
local EM  = EVENT_MANAGER
local NS  = "SKToolsESO_Ticks"

local T = {}
SKT.Ticks = T

local STAMINA = COMBAT_MECHANIC_FLAGS_STAMINA or POWERTYPE_STAMINA


---------------------------------------------------------------------------
-- Drawing: a spark and the warning bracket, on the stamina bar
---------------------------------------------------------------------------
function T:Build()
    local R = SKT.Resources
    if not (R and R.bars and R.bars.stamina) then return false end
    local bar = R.bars.stamina
    self.bar = bar

    -- the warning zone at the right end: a light band with a bracket (top, bottom and left edges)
    self.zone = D.Tex(bar, 6)
    self.zoneL = D.Tex(bar, 6)
    self.zoneT = D.Tex(bar, 6)
    self.zoneB = D.Tex(bar, 6)

    -- the spark: a bright line with a soft glow either side
    self.glow = D.Tex(bar, 6)
    self.spark = D.Tex(bar, 6)
    return true
end

function T:Layout()
    if not self.bar then return end
    local bar, db = self.bar, self.db
    local w, h = bar.w or 0, bar.h or 0
    local px = D.Px()

    local zw = D.OnPx(w * math.min(0.9, (db.warn or 0.4) / self.period))
    self.zoneW = zw
    for _, t in ipairs({ self.zone, self.zoneL, self.zoneT, self.zoneB }) do t:ClearAnchors() end
    self.zone:SetAnchor(TOPRIGHT, bar, TOPRIGHT, 0, 0)
    self.zone:SetDimensions(zw, h)
    D.Solid(self.zone, 1, 1, 1, 0.14)
    self.zoneL:SetAnchor(TOPRIGHT, bar, TOPRIGHT, -zw, 0)
    self.zoneL:SetDimensions(px, h)
    self.zoneT:SetAnchor(TOPRIGHT, bar, TOPRIGHT, 0, 0)
    self.zoneT:SetDimensions(zw, px)
    self.zoneB:SetAnchor(BOTTOMRIGHT, bar, BOTTOMRIGHT, 0, 0)
    self.zoneB:SetDimensions(zw, px)
    for _, t in ipairs({ self.zoneL, self.zoneT, self.zoneB }) do D.Solid(t, 1, 1, 1, 0.65) end

    local sw = D.OnPx(math.max(2 * px, h * 0.18))
    self.spark:SetDimensions(sw, h)
    D.Solid(self.spark, 1, 1, 1, 0.95)
    self.glow:SetDimensions(sw * 4, h)
    self.glowW = sw * 4
    self.sparkW = sw
    -- the glow: clear at the sides, light in the middle (two halves)
    D.Solid(self.glow, 1, 1, 1, 0.22)

    local showZone = db.showZone
    for _, t in ipairs({ self.zone, self.zoneL, self.zoneT, self.zoneB }) do t:SetHidden(not showZone) end
    self:Update()
end

---------------------------------------------------------------------------
-- The timer
---------------------------------------------------------------------------
T.period = 2.0      -- seconds between ticks (measured)
T.last = nil        -- when the last tick landed (GetFrameTimeSeconds)

local function Regen()
    local c = GetPlayerStat and STAT_STAMINA_REGEN_COMBAT and GetPlayerStat(STAT_STAMINA_REGEN_COMBAT) or 0
    local i = GetPlayerStat and STAT_STAMINA_REGEN_IDLE and GetPlayerStat(STAT_STAMINA_REGEN_IDLE) or 0
    return c, i
end

local function Near(gain, regen)
    return regen and regen > 0 and math.abs(gain - regen) <= math.max(8, regen * 0.2)
end

function T:OnStamina(value)
    local prev = self.value
    self.value = value
    if not prev then return end
    local gain = value - prev
    if gain <= 0 then return end

    local now = GetFrameTimeSeconds()
    local c, i = Regen()
    local due = self.last and (self:Remaining(now) < 0.3 or self:Remaining(now) > self.period - 0.3)
    if Near(gain, c) or Near(gain, i) or due then
        if self.last then
            local gap = now - self.last
            -- the measured time between ticks (2 s in combat; out of combat it can differ)
            if gap > 0.8 and gap < 1.25 then self.period = 1
            elseif gap > 1.7 and gap < 2.5 then self.period = 2 end
        end
        self.last = now
        self.warned = false
        self:Layout()
    end
end

-- seconds until the next tick, carrying on in steps of the period when no tick shows
-- (blocking or sprinting at the tick, or a full bar)
function T:Remaining(now)
    if not self.last then return nil end
    local since = (now or GetFrameTimeSeconds()) - self.last
    local p = self.period
    return p - (since % p)
end

function T:Update()
    if not self.bar then return end
    local db = self.db
    local R = SKT.Resources
    local sb = self.bar
    local full = (sb.cur or 0) >= (sb.max or 1)
    local show = db.enabled and R.db.enabled and self.last ~= nil
        and (not db.combatOnly or IsUnitInCombat("player"))
        and not (db.hideFull and full)

    if not show then
        for _, t in ipairs({ self.spark, self.glow, self.zone, self.zoneL, self.zoneT, self.zoneB }) do t:SetHidden(true) end
        return
    end
    for _, t in ipairs({ self.zone, self.zoneL, self.zoneT, self.zoneB }) do t:SetHidden(not db.showZone) end

    local left = self:Remaining()
    local f = 1 - left / self.period
    local w = sb.w or 0
    local x = math.max(self.sparkW / 2, math.min(w - self.sparkW / 2, w * f))   -- kept inside the bar
    self.spark:ClearAnchors()
    self.spark:SetAnchor(TOPLEFT, sb, TOPLEFT, D.OnPx(x - self.sparkW / 2), 0)
    self.glow:ClearAnchors()
    self.glow:SetAnchor(TOPLEFT, sb, TOPLEFT, x - self.glowW / 2, 0)
    self.spark:SetHidden(false)
    self.glow:SetHidden(false)

    -- the sound as the spark enters the zone
    if db.sound and not self.warned and left <= (db.warn or 0.4) then
        self.warned = true
        SKT.PlaySoundKey(db.soundName or "DEFAULT_CLICK")
    elseif left > (db.warn or 0.4) then
        self.warned = false
    end
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
SKT:RegisterModule({
    key   = "Ticks",
    title = "Stamina tick",
    order = 12,

    defaults = {
        enabled    = true,
        showZone   = true,
        warn       = 0.4,     -- seconds before the tick marked (and the sound)
        hideFull   = true,
        combatOnly = false,
        sound      = false,
        soundName  = "DEFAULT_CLICK",
    },

    OnLoad = function(self, db)
        T.db = db
        if type(db.warn) ~= "number" then db.warn = 0.4 end
        -- always: no marked zone, and shown in and out of combat
        db.showZone, db.combatOnly = false, false
        if not T:Build() then return end

        T.value = GetUnitPower("player", STAMINA)
        EM:RegisterForEvent(NS, EVENT_POWER_UPDATE, function(_, _, _, powerType, value)
            if powerType == STAMINA then T:OnStamina(value) end
        end)
        EM:AddFilterForEvent(NS, EVENT_POWER_UPDATE, REGISTER_FILTER_UNIT_TAG, "player")
        EM:RegisterForUpdate(NS, 0, function() T:Update() end)

        -- the resource bars re-lay their bars; the spark and zone follow
        local R = SKT.Resources
        local layout = R.Layout
        R.Layout = function(r, ...)
            layout(r, ...)
            T:Layout()
        end
        T:Layout()
    end,

    BuildTab = function(self, page, db)
        local L = SKT.UI.Column(page, 16, 268)
        local R = SKT.UI.Column(page, 316, 268)

        L:Header("Spark")
        L:Check("Hide while stamina is full",
            function() return db.hideFull end, function(v) db.hideFull = v end)

        R:Header("Sound")
        R:Check("Play a sound before the tick",
            function() return db.sound end, function(v) db.sound = v end)
        R:Slider("How long before", 1, 10, 1,
            function() return zo_round((db.warn or 0.4) * 10) end,
            function(v) db.warn = v / 10 end,
            function(v) return string.format("%.1f s", v / 10) end)
        R:Space(4)
        local h = SKT.UI.SoundPicker(page, R:Id(), R.x, R.y,
            function() return db.soundName end, function(v) db.soundName = v end)
        R:Space(h)
    end,
})
