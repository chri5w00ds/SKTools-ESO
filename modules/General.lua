-- SKTools-ESO by Scotskoogen-Chris
-- General tab: profile settings.

local SKT = SKT

SKT:RegisterModule({
    key   = "General",
    title = "General",
    order = 1,

    BuildTab = function(self, page)
        local L = SKT.UI.Column(page, 16, 268)
        local R = SKT.UI.Column(page, 316, 268)
        local function relayoutAll()
            if SKT.Resources and SKT.Resources.root then SKT.Resources:ApplyLayout() end
            if SKT.Skills and SKT.Skills.root then SKT.Skills:Layout(); SKT.Skills:Refresh() end
            SKT.Grid:Update(true)
        end

        L:Header("Elements")
        SKT.lockBox = L:Check("Lock all elements",
            function() return SKT.db.locked ~= false end,
            function(v) SKT:SetLocked(v) end,
            "Untick to move and size every element.\nAlso /sktools lock and /sktools unlock.")
        L:Check("Snap to grid",
            function() return SKT.db.snap ~= false end,
            function(v) SKT.db.snap = v; relayoutAll() end)
        L:Slider("Grid size", 2, 32, 1,
            function() return SKT.db.grid or 8 end,
            function(v) SKT.db.grid = v; relayoutAll() end,
            function(v) return v .. " px" end)

        L:Header("Test group (while unlocked)")
        L:Choice({ { 0, "Off" }, { 4, "4 players" }, { 12, "12 players" } },
            function() return SKT.db.testGroup or 0 end,
            function(v) SKT.db.testGroup = v; SKT:RefreshTest() end)

        L:Header("Profile")
        L:Check("Character-specific settings",
            function() return SKT.meta.useCharacterProfile end,
            function(checked)
                SKT:SetCharacterProfile(checked)
                SKT:Print("Profile change takes effect after /reloadui.")
            end,
            "Off: every character shares the same settings.\nOn: this character has its own. Takes effect after a reload.")
        L:Button("Reload UI", 140, function() ReloadUI("ingame") end)

        R:Header("Features")
        R:Check("Stamina tick",
            function() return SKT.Ticks and SKT.Ticks.db and SKT.Ticks.db.enabled end,
            function(v) if SKT.Ticks and SKT.Ticks.db then SKT.Ticks.db.enabled = v end end,
            "A spark sweeping across your stamina bar to the next regeneration tick.")
    end,
})
