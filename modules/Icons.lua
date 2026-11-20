--[[-------------------------------------------------------------------------
  SKTools-ESO by Scotskoogen-Chris
  Head icons: an icon floating above group members' heads, in the world.

    Roles     tanks and healers get the tank and healer icons (each can be changed)
    Friends   anyone on your friends list can be given their own icon, kept by @name, so it
              follows them whenever they're in your group or under your crosshair
    Others    optionally, group members with no icon get the healer icon

  Shown only in combat (the default), always, or while the "Show head icons" key is held (set
  in Controls > Keybindings > SKTools). While the Icons tab is open, every set icon shows.
  Never over your own head, except while the tab is open: the friend chosen in its list, when
  they're not in your group, shows their icon over yours, to see it and tune it.

  Icons are DDS files (DXT5, with alpha; square, 64 or 128 px). The ones made for SKTools are
  in Media/Icons. Others can be added by name: a file put in that folder (Media/Icons/Name.dds,
  added as "Name"), or any texture path from the game, such as /esoui/art/....

  Each icon is placed where the head is on screen: the point a set height above the player's
  feet, projected through the camera (ESO's 3D render space gives the camera's place and
  facing), so it follows them as they and the camera move. ESO only gives the positions of group members,
  your own character and whatever is under your crosshair, so those are who can have icons.
---------------------------------------------------------------------------]]

local SKT = SKT
local WM  = WINDOW_MANAGER
local EM  = EVENT_MANAGER
local NS  = "SKToolsESO_Icons"

local Ic = {}
SKT.Icons = Ic

ZO_CreateStringId("SI_BINDING_NAME_SKTOOLS_HEAD_ICONS", "Show head icons (hold)")

local MEDIA = "SKTools-ESO/Media/Icons/"
-- the icons made for SKTools: key -> name shown
local BUILT_IN = { "Tank", "Healer", "Star", "Diamond", "Circle", "Triangle", "Square", "Heart", "Moon", "Crown", "Arrow", "Raspberry", "Dumbbell", "Butterfly", "BlueMan", "RedPanda", "Raccoon" }

-- an icon's key -> texture path ("Tank" -> SKTools' own, "/esoui/..." as given)
local function Path(key)
    if type(key) ~= "string" or key == "" then return nil end
    if key:find("/") then return key end
    return MEDIA .. key .. ".dds"
end

function Ic:AllIcons()
    local list = {}
    for _, k in ipairs(BUILT_IN) do list[#list + 1] = k end
    for _, k in ipairs(self.db.custom or {}) do list[#list + 1] = k end
    return list
end

---------------------------------------------------------------------------
-- Who gets which icon
---------------------------------------------------------------------------
local function Account(tag)
    local n = GetUnitDisplayName(tag)
    return (n and n ~= "") and zo_strlower(n) or nil
end

-- the friends list: lower-case @names, and how they're written
function Ic:Friends()
    local list = {}
    for i = 1, (GetNumFriends and GetNumFriends() or 0) do
        local name = GetFriendInfo(i)
        if name and name ~= "" then list[#list + 1] = name end
    end
    table.sort(list, function(a, b) return zo_strlower(a) < zo_strlower(b) end)
    return list
end

function Ic:IsFriend(acct)
    if not acct then return false end
    if IsFriend then
        local ok, yes = pcall(IsFriend, acct)
        if ok then return yes end
    end
    for _, n in ipairs(self:Friends()) do if zo_strlower(n) == acct then return true end end
    return false
end

-- a unit's icon key, or nil
function Ic:IconFor(tag)
    local db = self.db
    local acct = Account(tag)
    if acct and db.friends[acct] and self:IsFriend(acct) then return db.friends[acct] end
    local role = GetGroupMemberSelectedRole and GetGroupMemberSelectedRole(tag)
    if (not role or role == LFG_ROLE_INVALID) and AreUnitsEqual(tag, "player") and GetSelectedLFGRole then
        role = GetSelectedLFGRole()          -- you, out of a group: the role you've chosen
    end
    if role == LFG_ROLE_TANK and db.tank ~= "" then return db.tank end
    if role == LFG_ROLE_HEAL and db.healer ~= "" then return db.healer end
    if db.fillHealer and IsUnitGrouped(tag) then return db.healer end
    return nil
end

---------------------------------------------------------------------------
-- Drawing, in the world
---------------------------------------------------------------------------
function Ic:Build()
    -- the camera: a hidden control set to where the camera is each frame, to read its position
    -- and the way it faces
    self.cam = WM:CreateControl(NS .. "Camera", GuiRoot, CT_CONTROL)
    self.cam:SetAnchorFill(GuiRoot)
    self.cam:Create3DRenderSpace()
    self.cam:SetHidden(true)

    -- the icons: flat on the screen, placed where each head is (projected through the camera),
    -- under the rest of the HUD
    local win = WM:CreateTopLevelWindow(NS)
    win:SetMouseEnabled(false)
    win:SetAnchorFill(GuiRoot)
    win:SetDrawLayer(DL_BACKGROUND)
    win:SetDrawTier(DT_LOW)
    win:SetDrawLevel(0)
    self.win = win
    self.pool = {}
    self.fragment = ZO_HUDFadeSceneFragment:New(win)
    HUD_SCENE:AddFragment(self.fragment)
    HUD_UI_SCENE:AddFragment(self.fragment)
    if LOOT_SCENE then LOOT_SCENE:AddFragment(self.fragment) end
    win:SetHandler("OnUpdate", function() self:Update() end)
end

function Ic:Get(i)
    local c = self.pool[i]
    if not c then
        c = WM:CreateControl(nil, self.win, CT_TEXTURE)
        self.pool[i] = c
    end
    c:SetHidden(false)
    return c
end

-- should they show now? in combat (or always), while the key is held, or while the tab is open
function Ic:Showing()
    local db = self.db
    if not db.enabled then return false, false end
    local tabOpen = SKT.window and not SKT.window:IsHidden() and SKT.activeTab == "Icons"
    if tabOpen then return true, true end
    local hud = (HUD_SCENE and HUD_SCENE:IsShowing()) or (HUD_UI_SCENE and HUD_UI_SCENE:IsShowing())
    if not hud then return false, false end
    if self.keyDown then return true, false end
    if db.combatOnly then return IsUnitInCombat("player"), false end
    return true, false
end

-- who to draw: { tag, key }
function Ic:Targets(preview)
    local out, seen = {}, {}
    local n = GetGroupSize()
    for i = 1, (n or 0) do
        local tag = GetGroupUnitTagByIndex(i)
        if tag and DoesUnitExist(tag) and not AreUnitsEqual(tag, "player") and IsUnitOnline(tag) then
            local key = self:IconFor(tag)
            if key then out[#out + 1] = { tag = tag, key = key }; seen[Account(tag) or tag] = true end
        end
    end
    -- a friend under the crosshair (not in your group)
    if DoesUnitExist("reticleover") and IsUnitPlayer("reticleover") then
        local acct = Account("reticleover")
        if acct and not seen[acct] and self.db.friends[acct] and self:IsFriend(acct) then
            out[#out + 1] = { tag = "reticleover", key = self.db.friends[acct] }
        end
    end
    -- never over your own head, except: with the Icons tab open, the friend chosen in the list,
    -- when they're not in your group, shows their icon over yours (to see it and tune it)
    local f = preview and self.previewFriend
    if f then
        local key = self.db.friends[zo_strlower(f)] or self.selected   -- theirs, else the one chosen
        local inGroup = false
        for i = 1, (n or 0) do
            local tag = GetGroupUnitTagByIndex(i)
            if tag and Account(tag) == zo_strlower(f) then inGroup = true; break end
        end
        if key and not inGroup then out[#out + 1] = { tag = "player", key = key } end
    end
    return out
end

function Ic:Update()
    local show, preview = self:Showing()
    local n = 0
    if show and Set3DRenderSpaceToCurrentCamera and GetUnitRawWorldPosition then
        local db = self.db
        local cam = self.cam
        Set3DRenderSpaceToCurrentCamera(cam:GetName())
        local cx, cy, cz = GuiRender3DPositionToWorldPosition(cam:Get3DRenderSpaceOrigin())
        local fx, fy, fz = cam:Get3DRenderSpaceForward()
        local rx, ry, rz = cam:Get3DRenderSpaceRight()
        local ux, uy, uz = cam:Get3DRenderSpaceUp()
        local myZone, px, py, pz = GetUnitRawWorldPosition("player")
        -- which way is "in front": your own character always is (third person), so the camera's
        -- forward is turned round if it points the other way
        if px and ((px - cx) * fx + (py - cy) * fy + (pz - cz) * fz) < 0 then
            fx, fy, fz = -fx, -fy, -fz
        end
        local uiW = GuiRoot:GetWidth()
        local alpha = (db.alpha or 100) / 100
        local size = (db.size or 100) / 100
        local lift = (db.height or 280)                  -- cm above the feet
        for _, t in ipairs(self:Targets(preview)) do
            local zone, wx, wy, wz = GetUnitRawWorldPosition(t.tag)
            local path = Path(t.key)
            if zone and zone == myZone and wx and path then
                -- from the camera, in metres
                local dx, dy, dz = (wx - cx) / 100, (wy + lift - cy) / 100, (wz - cz) / 100
                local depth = dx * fx + dy * fy + dz * fz
                if depth > 0.5 then
                    local sx = dx * rx + dy * ry + dz * rz
                    local sy = dx * ux + dy * uy + dz * uz
                    local fw = GetWorldDimensionsOfViewFrustumAtDepth(depth)
                    if fw and fw > 0 then
                        local scale = uiW / fw                   -- screen units per metre at that depth
                        local px2 = (db.style == "fixed") and (48 * size) or (0.9 * size * scale)
                        px2 = math.max(8, math.min(256, px2))
                        n = n + 1
                        local c = self:Get(n)
                        if c.path ~= path then c:SetTexture(path); c.path = path end
                        c:SetDimensions(px2, px2)
                        c:ClearAnchors()
                        c:SetAnchor(BOTTOM, GuiRoot, CENTER, sx * scale, -sy * scale)
                        c:SetAlpha(alpha)
                    end
                end
            end
        end
    end
    for i = n + 1, #self.pool do self.pool[i]:SetHidden(true) end
end

-- /skticons: what the icons see, to find out why one doesn't show
SLASH_COMMANDS["/skticons"] = function()
    local show, preview = Ic:Showing()
    SKT:Print(string.format("3D: %s, showing: %s (tab open: %s), in combat: %s",
        tostring(Set3DRenderSpaceToCurrentCamera ~= nil and GetUnitRawWorldPosition ~= nil),
        tostring(show), tostring(preview), tostring(IsUnitInCombat("player"))))
    local zone, x, y, z = GetUnitRawWorldPosition("player")
    SKT:Print(string.format("You: zone %s at %s, %s, %s; your icon: %s; role %s",
        tostring(zone), tostring(x), tostring(y), tostring(z), tostring(Ic:IconFor("player")),
        tostring(GetSelectedLFGRole and GetSelectedLFGRole())))
    SKT:Print("Icons to draw: " .. #Ic:Targets(preview))
    if Set3DRenderSpaceToCurrentCamera then
        Set3DRenderSpaceToCurrentCamera(Ic.cam:GetName())
        local cx, cy, cz = GuiRender3DPositionToWorldPosition(Ic.cam:Get3DRenderSpaceOrigin())
        local fx, fy, fz = Ic.cam:Get3DRenderSpaceForward()
        SKT:Print(string.format("Camera at %.0f, %.0f, %.0f facing %.2f, %.2f, %.2f; view 10 m away: %s m wide",
            cx or 0, cy or 0, cz or 0, fx or 0, fy or 0, fz or 0,
            tostring(GetWorldDimensionsOfViewFrustumAtDepth and GetWorldDimensionsOfViewFrustumAtDepth(10))))
    end
    local shown = 0
    for _, c in ipairs(Ic.pool) do if not c:IsHidden() then shown = shown + 1 end end
    SKT:Print("On screen: " .. shown)
end

-- the key: held to show them
function Ic:KeyDown() self.keyDown = true end
function Ic:KeyUp() self.keyDown = false end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
SKT:RegisterModule({
    key   = "Icons",
    title = "Head icons",
    order = 24.8,

    defaults = {
        enabled    = true,
        combatOnly = true,       -- only in combat (the key shows them any time)
        style      = "grow",     -- "grow": a size in the world; "fixed": the same size on screen
        size       = 100,        -- %
        height     = 280,        -- cm above the feet
        alpha      = 100,        -- %
        tank       = "Tank",
        healer     = "Healer",
        fillHealer = false,      -- group members with no icon: the healer icon
        friends    = {},         -- lower-case @name -> icon key
        custom     = {},         -- added icons: names in Media/Icons, or texture paths
    },

    OnLoad = function(self, db)
        Ic.db = db
        if type(db.friends) ~= "table" then db.friends = {} end
        if type(db.custom) ~= "table" then db.custom = {} end
        Ic.selected = db.tank or "Tank"
        Ic:Build()
    end,

    BuildTab = function(self, page, db)
        local UI = SKT.UI
        local L = UI.Column(page, 16, 268)
        local R = UI.Column(page, 316, 268)

        L:Header("Head icons")
        L:Check("Enable", function() return db.enabled end, function(v) db.enabled = v end)
        L:Check("Only in combat", function() return db.combatOnly end, function(v) db.combatOnly = v end)
        L:Check("No icon: use the healer icon", function() return db.fillHealer end,
            function(v) db.fillHealer = v end)

        L:Header("Size")
        L:ChoiceRow({ { "grow", "Grow when closer" }, { "fixed", "Fixed" } },
            function() return db.style end, function(v) db.style = v end)
        L:Slider("Size", 25, 300, 5, function() return db.size end, function(v) db.size = v end,
            function(v) return v .. "%" end)
        L:Slider("Height above the head", 150, 600, 10, function() return db.height end,
            function(v) db.height = v end, function(v) return string.format("%.1f m", v / 100) end)
        L:Slider("Opacity", 10, 100, 5, function() return db.alpha end, function(v) db.alpha = v end,
            function(v) return v .. "%" end)

        -- the icons: click one to choose it, then give it to a role or a friend
        R:Header("Icons")
        local grid, cells = R.y, {}
        local status = WM:CreateControl(page:GetName() .. "IcSel", page, CT_LABEL)
        local function Mark()
            for _, cell in ipairs(cells) do
                local on = cell.key == Ic.selected
                cell.edge:SetEdgeColor(on and 0.95 or 0.35, on and 0.76 or 0.36, on and 0.31 or 0.42, 1)
            end
            status:SetText("Chosen: " .. tostring(Ic.selected or ""))
        end
        local function Grid()
            local list = Ic:AllIcons()
            for i, key in ipairs(list) do
                local cell = cells[i]
                if not cell then
                    cell = WM:CreateControl(page:GetName() .. "IcCell" .. i, page, CT_BUTTON)
                    cell:SetDimensions(36, 36)
                    cell.tex = WM:CreateControl(nil, cell, CT_TEXTURE)
                    cell.tex:SetAnchor(TOPLEFT, cell, TOPLEFT, 3, 3)
                    cell.tex:SetAnchor(BOTTOMRIGHT, cell, BOTTOMRIGHT, -3, -3)
                    cell.edge = WM:CreateControl(nil, cell, CT_BACKDROP)
                    cell.edge:SetAnchorFill(cell)
                    cell.edge:SetCenterColor(0, 0, 0, 0.35)
                    cell.edge:SetEdgeTexture("", 1, 1, 1, 0)
                    cell:SetHandler("OnClicked", function(c) Ic.selected = c.key; Mark() end)
                    cell:SetHandler("OnMouseEnter", function(c)
                        InitializeTooltip(InformationTooltip, c, BOTTOM, 0, -6, TOP)
                        SetTooltipText(InformationTooltip, c.key)
                    end)
                    cell:SetHandler("OnMouseExit", function() ClearTooltip(InformationTooltip) end)
                    cells[i] = cell
                end
                cell.key = key
                cell.tex:SetTexture(Path(key))
                cell:ClearAnchors()
                cell:SetAnchor(TOPLEFT, page, TOPLEFT, R.x + ((i - 1) % 7) * 38, grid + math.floor((i - 1) / 7) * 38)
                cell:SetHidden(false)
            end
            for i = #list + 1, #cells do cells[i]:SetHidden(true) end
            Mark()
        end
        R:Space(4 * 38 + 2)
        status:SetFont("ZoFontGameSmall")
        status:SetColor(SKT.col(SKT.colors.muted))
        status:SetAnchor(TOPLEFT, page, TOPLEFT, R.x, R.y)
        R:Space(20)

        -- roles
        R:Buttons({
            { "Tank icon", 128, function() db.tank = Ic.selected or "Tank" end },
            { "Healer icon", 128, function() db.healer = Ic.selected or "Healer" end },
        })

        -- friends: pick one from the drop-down, then give them the chosen icon
        local friends = Ic:Friends()
        local fname = friends[1]
        local ddCtrl = WM:CreateControlFromVirtual(page:GetName() .. "IcFriends", page,
            ZO_ScrollableComboBox and "ZO_ScrollableComboBox" or "ZO_ComboBox")
        ddCtrl:SetAnchor(TOPLEFT, page, TOPLEFT, R.x, R.y)
        ddCtrl:SetDimensions(268, 28)
        local dd = ZO_ComboBox_ObjectFromContainer(ddCtrl)
        if dd.SetSortsItems then dd:SetSortsItems(false) end
        local function Label(name)
            local icon = db.friends[zo_strlower(name)]
            return icon and (name .. "  (" .. icon .. ")") or name
        end
        local function Fill()
            dd:ClearItems()
            if #friends == 0 then
                dd:AddItem(dd:CreateItemEntry("No friends", function() end), ZO_COMBOBOX_SUPPRESS_UPDATE)
            end
            for _, name in ipairs(friends) do
                dd:AddItem(dd:CreateItemEntry(Label(name), function()
                    fname = name
                    Ic.previewFriend = name
                end), ZO_COMBOBOX_SUPPRESS_UPDATE)
            end
            dd:UpdateItems()
            if fname then
                dd:SetSelectedItemText(Label(fname))
            else
                dd:SetSelectedItemText("No friends")
            end
        end
        Ic.previewFriend = fname
        R:Space(36)
        R:Buttons({
            { "Give icon", 128, function()
                if fname then db.friends[zo_strlower(fname)] = Ic.selected; Fill() end
            end },
            { "Remove", 128, function()
                if fname then db.friends[zo_strlower(fname)] = nil; Fill() end
            end },
        })
        Fill()

        -- add an icon: a file in Media/Icons (its name) or a game texture path
        R:Header("Add an icon")
        local bd = WM:CreateControlFromVirtual(page:GetName() .. "IcAddBG", page, "ZO_EditBackdrop")
        bd:SetAnchor(TOPLEFT, page, TOPLEFT, R.x, R.y)
        bd:SetDimensions(180, 28)
        local eb = WM:CreateControlFromVirtual(page:GetName() .. "IcAdd", bd, "ZO_DefaultEditForBackdrop")
        eb:SetMaxInputChars(200)
        eb:SetDefaultText("Name or path")
        local function Add()
            local v = zo_strtrim(eb:GetText() or ""):gsub("%.dds$", "")
            if v == "" then return end
            if v:find("/") then v = v .. ".dds" end
            for _, k in ipairs(Ic:AllIcons()) do if k == v then return end end
            if #Ic:AllIcons() >= 28 then SKT:Print("The icon list is full.") return end
            db.custom[#db.custom + 1] = v
            eb:SetText("")
            Ic.selected = v
            Grid()
        end
        eb:SetHandler("OnEnter", Add)
        UI.Button(page, "IcAddBtn", R.x + 188, R.y, "Add", 80, Add)
        R:Space(34)
        R:Button("Remove chosen icon", 200, function()
            for i, k in ipairs(db.custom) do
                if k == Ic.selected then table.remove(db.custom, i); Ic.selected = "Tank"; Grid(); return end
            end
        end)
        Grid()
    end,
})
