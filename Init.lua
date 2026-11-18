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

    SLASH_COMMANDS["/sktools"] = function(arg)
        arg = zo_strlower(zo_strtrim(arg or ""))
        if arg == "unlock" or arg == "lock" then
            for _, m in ipairs({ SKT.Resources, SKT.Skills }) do
                if m and m.db then
                    m.db.locked = (arg == "lock")
                    m:ApplyLock()
                end
            end
            SKT:Print("Resource bars and skill bars " .. arg .. "ed.")
        else
            SKT:ToggleWindow()
        end
    end
end

EVENT_MANAGER:RegisterForEvent(SKT.name, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
