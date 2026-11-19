-- SKTools-ESO by Scotskoogen-Chris
-- Init: runs after every file has loaded and registered its module.

local SKT = SKT

local function OnAddOnLoaded(_, addonName)
    if addonName ~= SKT.name then return end
    EVENT_MANAGER:UnregisterForEvent(SKT.name, EVENT_ADD_ON_LOADED)

    SKT:LoadSavedVars()

    for _, mod in ipairs(SKT.modules) do
        if mod.OnLoad then mod:OnLoad(SKT.db[mod.key] or SKT.db) end
    end

    -- every element follows the one lock
    for _, m in ipairs(SKT:Movables()) do
        if m.db.locked ~= SKT.db.locked then
            m.db.locked = SKT.db.locked
            m:ApplyLock()
        end
    end

    SLASH_COMMANDS["/sktools"] = function(arg)
        arg = zo_strlower(zo_strtrim(arg or ""))
        if arg == "unlock" or arg == "lock" then
            SKT:SetLocked(arg == "lock")
            SKT:Print("Elements " .. arg .. "ed.")
        else
            SKT:ToggleWindow()
        end
    end
end

EVENT_MANAGER:RegisterForEvent(SKT.name, EVENT_ADD_ON_LOADED, OnAddOnLoaded)

-- /rl and /reload: reload the UI (registered as soon as this file loads, so nothing earlier can stop it)
local function Reload() ReloadUI("ingame") end
SLASH_COMMANDS["/rl"] = Reload
SLASH_COMMANDS["/reload"] = Reload
