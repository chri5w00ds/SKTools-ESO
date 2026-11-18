-- SKTools-ESO by Scotskoogen-Chris
-- About tab.

local SKT = SKT

SKT:RegisterModule({
    key   = "About",
    title = "About",
    order = 999,

    BuildTab = function(self, page)
        SKT.UI.Header(page, "Head", 16, 12, "About SKTools")
        SKT.UI.Text(page, "Body", 16, 48,
            "SKTools for Elder Scrolls Online\n" ..
            "Version " .. SKT.version .. "\n" ..
            "Created by " .. SKT.author .. "\n\n" ..
            "Commands:\n" ..
            "  /sktools          - open or close this window\n" ..
            "  /sktools unlock   - unlock the resource and skill bars to move them\n" ..
            "  /sktools lock     - lock them")
    end,
})
