-- SKTools-ESO by Scotskoogen-Chris
-- General tab: profile settings.

local SKT = SKT

SKT:RegisterModule({
    key   = "General",
    title = "General",
    order = 1,

    BuildTab = function(self, page)
        SKT.UI.Header(page, "Head", 16, 12, "General")

        local modeText = (SKT.profileMode == "character")
            and "Current profile: this character only."
            or  "Current profile: account-wide (shared by all characters)."
        SKT.UI.Text(page, "Mode", 16, 48, modeText)

        SKT.UI.Checkbox(page, "CharProfile", 16, 84, "Use a character-specific profile",
            function() return SKT.meta.useCharacterProfile end,
            function(checked)
                SKT:SetCharacterProfile(checked)
                SKT:Print("Profile change takes effect after /reloadui.")
            end,
            "Off: settings apply to every character on this account.\nOn: this character gets its own settings.")

        SKT.UI.Button(page, "Reload", 16, 124, "Reload UI", 140, function() ReloadUI("ingame") end)

        -- snap to grid, for every element SKTools draws
        local function relayoutAll()
            if SKT.Resources and SKT.Resources.root then SKT.Resources:ApplyLayout() end
            if SKT.Skills and SKT.Skills.root then SKT.Skills:Layout(); SKT.Skills:Refresh() end
            SKT.Grid:Update(true)
        end
        SKT.UI.Header(page, "HeadGrid", 16, 180, "Moving elements")
        SKT.UI.Checkbox(page, "Snap", 16, 216, "Snap to grid",
            function() return SKT.db.snap ~= false end,
            function(v) SKT.db.snap = v; relayoutAll() end,
            "A moved element snaps to the grid shown while unlocked.\nSizes are taken in whole grid boxes.")
        SKT.UI.Slider(page, "Grid", 16, 248, 260, "Grid size", 2, 32, 1,
            function() return SKT.db.grid or 8 end,
            function(v) SKT.db.grid = v; relayoutAll() end,
            function(v) return v .. " px" end)
        SKT.UI.Button(page, "Unlock", 16, 304, "Unlock elements", 180, function()
            SLASH_COMMANDS["/sktools"]("unlock")
        end)
        SKT.UI.Button(page, "Lock", 206, 304, "Lock elements", 160, function()
            SLASH_COMMANDS["/sktools"]("lock")
        end)
    end,
})
