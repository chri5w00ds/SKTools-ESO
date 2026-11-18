-- SKTools-ESO by Scotskoogen-Chris
-- Core: namespace, saved variables, profiles, module registry.

SKT = SKT or {}
local SKT = SKT

SKT.name    = "SKTools-ESO"
SKT.version = "0.7.0"
SKT.author  = "Scotskoogen-Chris"
SKT.svName  = "SKToolsESO_SV"
SKT.svVer   = 1

-- Colours (dark navy theme, matching SKTools for WoW)
SKT.colors = {
    bg        = { 0.05, 0.07, 0.14, 0.96 },  -- very dark navy, not black
    panel     = { 0.08, 0.11, 0.20, 1.00 },
    edge      = { 0.62, 0.66, 0.74, 1.00 },  -- classic silver border
    title     = { 0.95, 0.76, 0.31, 1.00 },  -- gold
    text      = { 0.90, 0.90, 0.92, 1.00 },
    muted     = { 0.60, 0.64, 0.72, 1.00 },
    tabActive = { 0.16, 0.22, 0.38, 1.00 },
    tabIdle   = { 0.09, 0.12, 0.22, 1.00 },
}

-- Defaults for the shared profile. Modules add their own defaults via RegisterModule.
SKT.defaults = {
    window = { x = nil, y = nil },
    lastTab = "General",
    snap = true,      -- moved elements snap to a grid (shown while unlocked)
    grid = 8,
}

---------------------------------------------------------------------------
-- Module registry: each module = one settings tab.
--   SKT:RegisterModule({
--       key      = "MyModule",           -- unique key, also the saved-vars sub-table
--       title    = "My Module",          -- tab label
--       order    = 10,                   -- tab order (lower = further left)
--       defaults = { enabled = true },   -- merged into the profile under db[key]
--       OnLoad   = function(self, db) end,         -- called after saved vars load
--       BuildTab = function(self, parent, db) end, -- build the tab's controls
--   })
---------------------------------------------------------------------------
SKT.modules = {}

function SKT:RegisterModule(mod)
    assert(mod and mod.key, "SKTools-ESO: module needs a key")
    mod.order = mod.order or 100
    mod.title = mod.title or mod.key
    if mod.defaults then
        self.defaults[mod.key] = mod.defaults
    end
    table.insert(self.modules, mod)
    table.sort(self.modules, function(a, b) return a.order < b.order end)
end

function SKT:GetModule(key)
    for _, mod in ipairs(self.modules) do
        if mod.key == key then return mod end
    end
end

---------------------------------------------------------------------------
-- Saved variables
-- Account-wide by default. Each character can opt into its own profile
-- (stored in that character's "Meta" record). Switching needs a /reloadui.
---------------------------------------------------------------------------
function SKT:LoadSavedVars()
    self.meta = ZO_SavedVars:NewCharacterIdSettings(self.svName, self.svVer, "Meta",
        { useCharacterProfile = false })

    if self.meta.useCharacterProfile then
        self.db = ZO_SavedVars:NewCharacterIdSettings(self.svName, self.svVer, "Profile", self.defaults)
        self.profileMode = "character"
    else
        self.db = ZO_SavedVars:NewAccountWide(self.svName, self.svVer, "Profile", self.defaults)
        self.profileMode = "account"
    end
end

function SKT:SetCharacterProfile(enabled)
    self.meta.useCharacterProfile = enabled and true or false
end

function SKT:Print(msg)
    d("|cF2C14E[SKTools]|r " .. tostring(msg))
end
