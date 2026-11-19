--[[-------------------------------------------------------------------------
  SKTools-ESO by Scotskoogen-Chris
  Keybinds: one account-wide set of keybinds.

  On a character whose keybinds you like, "Save as the account set" takes a
  copy of every rebindable keybind (the game's and every addon's). On any
  other character, tick "Use the account keybinds" and that character gets
  the same keys, now and every time it logs in.

  The first time a character switches to the account set, its own keybinds
  are kept as a backup, so "Restore this character's own keybinds" can put
  them back.

  Keybinds are matched by their action names (not their places in the
  list), so they land on the right actions even when addons add or remove
  keybinds. Keybinds added since the set was saved keep their keys, unless
  a key is taken by the set.
---------------------------------------------------------------------------]]

local SKT = SKT
local EM  = EVENT_MANAGER
local K = {}
SKT.Keybinds = K

local NS = "SKToolsESO_Keybinds"
local MAXB = (GetMaxBindingsPerAction and GetMaxBindingsPerAction()) or 4

local function NoKey(key) return key == nil or key == 0 or key == KEY_INVALID end

-- every rebindable action: fn(layer, category, action, id) with id = "layer name/action name"
local function Walk(fn)
    for l = 1, GetNumActionLayers() do
        local layerName, numCats = GetActionLayerInfo(l)
        for c = 1, (numCats or 0) do
            local _, numActions = GetActionLayerCategoryInfo(l, c)
            for a = 1, (numActions or 0) do
                local name, rebindable = GetActionInfo(l, c, a)
                if name and name ~= "" and rebindable then
                    fn(l, c, a, tostring(layerName) .. "/" .. name)
                end
            end
        end
    end
end

local function Combo(k) return table.concat({ k[1], k[2] or 0, k[3] or 0, k[4] or 0, k[5] or 0 }, ":") end

-- a copy of this character's keybinds: id -> { [bindingIndex] = { key, mod1, mod2, mod3, mod4 } }
-- (an action with no keys is kept too, as an empty list, so applying the set clears it)
function K:Snapshot()
    local set, count = {}, 0
    Walk(function(l, c, a, id)
        local binds = {}
        for b = 1, MAXB do
            local key, m1, m2, m3, m4 = GetActionBindingInfo(l, c, a, b)
            if not NoKey(key) then
                binds[b] = { key, m1 or 0, m2 or 0, m3 or 0, m4 or 0 }
                count = count + 1
            end
        end
        set[id] = binds
    end)
    return set, count
end

-- put a set onto this character: first clear every action in the set and any key the set uses,
-- then bind the set's keys
function K:Apply(set)
    if not set then return false end
    if IsUnitInCombat("player") then
        self.pending = set
        SKT:Print("Keybinds will be applied when you leave combat.")
        return false
    end

    local used = {}
    for _, binds in pairs(set) do
        for _, k in pairs(binds) do used[Combo(k)] = true end
    end

    local places = {}
    Walk(function(l, c, a, id)
        if set[id] then
            UnbindAllKeysFromAction(l, c, a)
            places[#places + 1] = { l, c, a, set[id] }
        else
            -- not in the set (added since): keeps its keys unless the set uses one
            for b = 1, MAXB do
                local key, m1, m2, m3, m4 = GetActionBindingInfo(l, c, a, b)
                if not NoKey(key) and used[Combo({ key, m1, m2, m3, m4 })] then
                    if not (UnbindKeyFromAction and pcall(UnbindKeyFromAction, l, c, a, b)) then
                        UnbindAllKeysFromAction(l, c, a)
                    end
                end
            end
        end
    end)

    local bound = 0
    for _, p in ipairs(places) do
        for b, k in pairs(p[4]) do
            if pcall(BindKeyToAction, p[1], p[2], p[3], b, k[1], k[2], k[3], k[4], k[5]) then
                bound = bound + 1
            end
        end
    end
    return true, bound
end

local function Stamp()
    return GetDateStringFromTimestamp(GetTimeStamp()) .. " " .. GetTimeString()
end

function K:SaveAccountSet()
    local set, count = self:Snapshot()
    self.acc.set = set
    self.acc.from = zo_strformat("<<1>>", GetUnitName("player"))
    self.acc.when = Stamp()
    SKT:Print(("Saved %d keybinds from %s as the account set."):format(count, self.acc.from))
    self:UpdateInfo()
end

function K:UseAccountSet(on)
    if on then
        if not self.acc.set then
            SKT:Print("No account set yet: save one first, on the character whose keybinds you want.")
            return false
        end
        -- keep this character's own keybinds the first time, to restore later
        if not self.char.backup then
            self.char.backup = self:Snapshot()
            self.char.backupWhen = Stamp()
        end
        self.char.enabled = true
        local ok, n = self:Apply(self.acc.set)
        if ok then SKT:Print(("Account keybinds applied (%d keys)."):format(n)) end
    else
        self.char.enabled = false
    end
    self:UpdateInfo()
    return true
end

function K:RestoreOwn()
    if not self.char.backup then
        SKT:Print("This character has no saved keybinds of its own to restore.")
        return
    end
    self.char.enabled = false
    local ok, n = self:Apply(self.char.backup)
    if ok then SKT:Print(("This character's own keybinds restored (%d keys)."):format(n)) end
    if self.useBox then ZO_CheckButton_SetCheckState(self.useBox, false) end
    self:UpdateInfo()
end

function K:UpdateInfo()
    if not self.info then return end
    local lines = {}
    if self.acc.set then
        lines[#lines + 1] = ("Account set: from |cF2C14E%s|r, saved %s."):format(self.acc.from or "?", self.acc.when or "?")
    else
        lines[#lines + 1] = "Account set: none saved yet."
    end
    lines[#lines + 1] = self.char.enabled and "This character uses the account set."
                                         or "This character uses its own keybinds."
    if self.char.backup then
        lines[#lines + 1] = ("Own keybinds kept as a backup (%s)."):format(self.char.backupWhen or "?")
    end
    self.info:SetText(table.concat(lines, "\n"))
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
SKT:RegisterModule({
    key   = "Keybinds",
    title = "Keybinds",
    order = 30,

    OnLoad = function(self)
        -- always account-wide and per character, whichever settings profile is in use
        K.acc  = ZO_SavedVars:NewAccountWide(SKT.svName, SKT.svVer, "KeybindsAccount", { autoSync = false })
        K.char = ZO_SavedVars:NewCharacterIdSettings(SKT.svName, SKT.svVer, "KeybindsChar", { enabled = false })

        -- applied once a session, after login, when this character uses the account set
        EM:RegisterForEvent(NS, EVENT_PLAYER_ACTIVATED, function()
            EM:UnregisterForEvent(NS, EVENT_PLAYER_ACTIVATED)
            if K.char.enabled and K.acc.set then
                zo_callLater(function() K:Apply(K.acc.set) end, 1500)
            end
        end)
        EM:RegisterForEvent(NS, EVENT_PLAYER_COMBAT_STATE, function(_, inCombat)
            if not inCombat and K.pending then
                local set = K.pending
                K.pending = nil
                K:Apply(set)
            end
        end)
        -- keep the account set up to date with keys changed on a character that uses it
        if EVENT_KEYBINDING_SET then
            EM:RegisterForEvent(NS .. "Set", EVENT_KEYBINDING_SET, function()
                if K.acc.autoSync and K.char.enabled and not K.syncQueued then
                    K.syncQueued = true
                    zo_callLater(function()
                        K.syncQueued = false
                        K.acc.set = K:Snapshot()
                        K.acc.from = zo_strformat("<<1>>", GetUnitName("player"))
                        K.acc.when = Stamp()
                        K:UpdateInfo()
                    end, 500)
                end
            end)
        end
    end,

    BuildTab = function(self, page)
        local L = SKT.UI.Column(page, 16, 568)

        L:Header("Account-wide keybinds")
        L:Button("Save this character's keybinds as the account set", 380, function() K:SaveAccountSet() end)
        K.useBox = L:Check("Use the account keybinds on this character",
            function() return K.char.enabled end,
            function(v)
                if not K:UseAccountSet(v) and K.useBox then ZO_CheckButton_SetCheckState(K.useBox, false) end
            end,
            "Applied now and at every login. The first time, this character's own keybinds are kept as a backup.")
        L:Check("Keep the account set up to date",
            function() return K.acc.autoSync end,
            function(v) K.acc.autoSync = v end,
            "A keybind changed on a character that uses the account set changes the set too.")
        L:Space(4)
        L:Buttons({
            { "Apply the account set again", 240, function()
                if K.acc.set and K.char.enabled then
                    local ok, n = K:Apply(K.acc.set)
                    if ok then SKT:Print(("Account keybinds applied (%d keys)."):format(n)) end
                end
            end },
            { "Restore own keybinds", 220, function() K:RestoreOwn() end },
        })

        L:Header("Status")
        K.info = L:Text("")
        K:UpdateInfo()
    end,
})
