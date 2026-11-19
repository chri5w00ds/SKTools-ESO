-- SKTools-ESO by Scotskoogen-Chris
-- Core: namespace, saved variables, profiles, module registry.

SKT = SKT or {}
local SKT = SKT

SKT.name    = "SKTools-ESO"
SKT.version = "0.40.5"
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
    -- the settings window's ESO trim
    panelBg   = { 0.078, 0.11, 0.20, 1.00 },
    panelEdge = { 0.17, 0.21, 0.31, 1.00 },
    bronze    = { 0.54, 0.46, 0.31, 1.00 },
    gold      = { 0.79, 0.65, 0.35, 1.00 },
}

-- Defaults for the shared profile. Modules add their own defaults via RegisterModule.
SKT.defaults = {
    window = { x = nil, y = nil },
    lastTab = "General",
    snap = true,      -- moved elements snap to a grid (shown while unlocked)
    locked = true,    -- one lock for every element
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

-- elements that can be unlocked and moved (each has db.locked, db.enabled and :ApplyLock())
function SKT:Movables()
    local list = {}
    for _, m in ipairs({ self.Resources, self.Skills, self.CC, self.Minimap, self.Buffs, self.Instance, self.Group, self.Synergy, self.Shared, self.Prompts }) do
        if m and m.db then list[#list + 1] = m end
    end
    return list
end

---------------------------------------------------------------------------
-- Test group: while elements are unlocked, a made-up group of 4 or 12 fills the group buffs,
-- synergy grid and DPS meter, to place and size them. SKT.db.testGroup: 0 (off), 4 or 12.
---------------------------------------------------------------------------
local TEST_MEMBERS = {
    { "Ironhide", LFG_ROLE_TANK },  { "Mendwell", LFG_ROLE_HEAL }, { "Ashblade", LFG_ROLE_DPS },
    { "Quickfang", LFG_ROLE_DPS },  { "Stoneward", LFG_ROLE_TANK }, { "Dawnbloom", LFG_ROLE_HEAL },
    { "Emberveil", LFG_ROLE_DPS },  { "Frostmark", LFG_ROLE_DPS }, { "Nightsong", LFG_ROLE_DPS },
    { "Stormcall", LFG_ROLE_DPS },  { "Grimshot", LFG_ROLE_DPS },  { "Sunreaver", LFG_ROLE_DPS },
}
local TEST_PREFIX = "skttest"

function SKT:TestSize()
    local n = self.db and self.db.testGroup or 0
    if self.db and self.db.locked == false and (n == 4 or n == 12) then return n end
    return 0
end
function SKT:TestTags()
    local tags = {}
    for i = 1, self:TestSize() do tags[i] = TEST_PREFIX .. i end
    return tags
end
function SKT.IsTestTag(tag) return type(tag) == "string" and tag:sub(1, #TEST_PREFIX) == TEST_PREFIX end
local function TestIndex(tag) return tonumber(tag:sub(#TEST_PREFIX + 1)) end
function SKT.TestName(tag) local m = TEST_MEMBERS[TestIndex(tag)]; return m and m[1] or "" end
function SKT.TestRole(tag) local m = TEST_MEMBERS[TestIndex(tag)]; return m and m[2] or nil end
function SKT.TestIndex(tag) return TestIndex(tag) end
-- a unit's name, test members included
function SKT.UnitName(tag)
    if SKT.IsTestTag(tag) then return SKT.TestName(tag) end
    return zo_strformat("<<1>>", GetUnitName(tag))
end

-- everything that shows the test group, redrawn
function SKT:RefreshTest()
    if self.Group and self.Group.root then self.Group:Refresh() end
    if self.Synergy and self.Synergy.root then self.Synergy:Refresh() end
    if self.Shared and self.Shared.panels then self.Shared:RenderAll() end
end

-- lock or unlock every element at once
function SKT:SetLocked(locked)
    self.db.locked = locked and true or false
    for _, m in ipairs(self:Movables()) do
        m.db.locked = self.db.locked
        m:ApplyLock()
    end
    self:RefreshTest()
    if self.lockBox then ZO_CheckButton_SetCheckState(self.lockBox, self.db.locked) end
end

-- to the chat as a system message (shows in every chat tab, also with chat addons that hide d())
function SKT:Print(msg)
    local text = "|cF2C14E[SKTools]|r " .. tostring(msg)
    if CHAT_ROUTER and CHAT_ROUTER.AddSystemMessage then
        CHAT_ROUTER:AddSystemMessage(text)
    elseif CHAT_SYSTEM and CHAT_SYSTEM.AddMessage then
        CHAT_SYSTEM:AddMessage(text)
    else
        d(text)
    end
end
