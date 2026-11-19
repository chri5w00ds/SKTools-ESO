-- SKTools-ESO by Scotskoogen-Chris
-- About tab.

local SKT = SKT

SKT:RegisterModule({
    key   = "About",
    title = "About",
    order = 999,

    BuildTab = function(self, page)
        local L = SKT.UI.Column(page, 16, 568)
        L:Header("SKTools for Elder Scrolls Online")
        L:Text("Version " .. SKT.version .. "\nCreated by " .. SKT.author)
        L:Header("Commands")
        L:Text("/sktools  -  open or close this window\n" ..
               "/sktools unlock  -  unlock every element\n" ..
               "/sktools lock  -  lock every element\n" ..
               "/rl  or  /reload  -  reload the UI")
    end,
})
