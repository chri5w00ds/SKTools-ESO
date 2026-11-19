--[[-------------------------------------------------------------------------
  SKTools-ESO by Scotskoogen-Chris
  Minimap: a round map of where you are, following you, north up, with
  your arrow in the middle turning with you, in a thin silver ring.

  Above it, in its own frame, where you are; inside the circle at the
  bottom, your own time. Each can be switched off.

  The map is the game's own map of your zone (or city, or delve), drawn
  from its tiles. Zoom with the mouse wheel over the map (while the cursor
  is shown) or the Zoom slider. Unlock to place it box by box on the grid.
---------------------------------------------------------------------------]]

local SKT = SKT
local D   = SKT.Draw
local WM  = WINDOW_MANAGER
local EM  = EVENT_MANAGER
local NS  = "SKToolsESO_Minimap"

local M = {}
SKT.Minimap = M

local PLAYER_PIP = "EsoUI/Art/MapPins/UI-WorldMapPlayerPip.dds"
-- the camera's view: a narrow wedge from the middle of the texture to its top edge, brightest at
-- the tip and fading to nothing at its end
local VIEW_CONE = "SKTools-ESO/Media/ViewCone.dds"
local BEE = "SKTools-ESO/Media/Logo.dds"   -- the SKTools bee (faces right)
local CONE_SIZE = 0.444
local CIRCLE = "SKTools-ESO/Media/Circle.dds"
-- the frame: a polished silver ring, as the WoW SKTools widget frames (Media/MinimapRing.dds, 512 px,
-- its hole 235 px across the middle: the map fills it, the ring just over the map's edge)
local FRAME = "SKTools-ESO/Media/MinimapRing.dds"
local FRAME_SCALE = 256 / 235
local QUEST_ICON = "EsoUI/Art/Compass/quest_icon.dds"
local QUEST_ICON_FOCUS = "EsoUI/Art/Compass/quest_icon_assisted.dds"
local GROUP_COLOR  = { 0.45, 0.72, 0.92 }   -- pastel blue
local LEADER_COLOR = { 0.95, 0.76, 0.31 }   -- gold   -- the texture's width as a share of the map's (the cone: 20 % of it)

local function SilverAt(f)
    local t, b = { 0.94, 0.94, 0.96 }, { 0.58, 0.59, 0.63 }
    return t[1] + (b[1] - t[1]) * f, t[2] + (b[2] - t[2]) * f, t[3] + (b[3] - t[3]) * f
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
function M:Build()
    local db = self.db
    local root = WM:CreateTopLevelWindow(NS)
    root:SetClampedToScreen(true)
    root:SetMouseEnabled(false)
    self.root = root

    -- the map window: a scroll control, so the map is cut off at its edges
    local view = WM:CreateControl(NS .. "View", root, CT_SCROLL)
    view:SetAnchor(TOPLEFT, root, TOPLEFT, 0, 0)
    self.view = view

    -- the silver ring: a silver disk a pixel bigger than the map, behind it
    self.disk = D.Tex(root, 0)
    self.frame = WM:CreateControl(NS .. "Frame", root, CT_TEXTURE)
    self.frame:SetTexture(FRAME)
    self.frame:SetDrawTier(DT_HIGH)
    self.frame:SetDrawLevel(9)
    self.viewBg = D.Tex(root, 0)
    self.viewBg:SetAnchorFill(view)
    D.Solid(self.viewBg, 0.05, 0.07, 0.14, 1)

    self.map = WM:CreateControl(NS .. "Map", view, CT_CONTROL)
    self.tiles = {}
    self.pins, self.pinN = {}, 0

    -- the camera's view cone, under the arrow
    self.cone = WM:CreateControl(NS .. "Cone", root, CT_TEXTURE)
    self.cone:SetTexture(VIEW_CONE)
    self.cone:SetDrawTier(DT_HIGH)
    self.cone:SetDrawLevel(5)

    -- the arrow: drawn above the map (a higher tier than the map window's contents)
    self.pip = WM:CreateControl(NS .. "Pip", root, CT_TEXTURE)
    self.pip:SetTexture(PLAYER_PIP)
    self.pip:SetDrawTier(DT_HIGH)
    self.pip:SetDrawLevel(10)

    -- the info strip
    self.info = D.Tex(root, 1)
    self.infoLine = D.Tex(root, 9)     -- the line between map and strip
    self.lines = {}
    for i = 1, 3 do
        local l = WM:CreateControl(nil, root, CT_LABEL)
        l:SetDrawLevel(4)
        l:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
        l:SetColor(0.92, 0.92, 0.95, 1)
        self.lines[i] = l
    end
    self.ringAll = D.NewRing(root, 9)

    -- the bee: opens the settings window; faces right, and left while the window is open
    local bee = WM:CreateControl(NS .. "Bee", root, CT_TEXTURE)
    bee:SetTexture(BEE)
    bee:SetDrawTier(DT_HIGH)
    bee:SetMouseEnabled(true)
    bee:SetHandler("OnMouseUp", function(_, button, upInside)
        if upInside and button == MOUSE_BUTTON_INDEX_LEFT then SKT:ToggleWindow() end
    end)
    bee:SetHandler("OnMouseEnter", function(c) c:SetColor(1, 1, 0.82, 1) end)
    bee:SetHandler("OnMouseExit", function(c) c:SetColor(1, 1, 1, 1) end)
    self.bee = bee
    self:FaceBee()

    -- zoom with the mouse wheel over the map
    view:SetMouseEnabled(true)
    view:SetHandler("OnMouseWheel", function(_, delta)
        db.zoom = zo_clamp((db.zoom or 6) * (delta > 0 and 1.15 or 1 / 1.15), 1, 40)
        self:PlaceMap()
        if self.zoomSlider then self.zoomSlider:SetValue(zo_round(db.zoom)) end
    end)

    local drag
    SKT.Grid.Draggable(root, {
        start = function() drag = { x = db.x, y = db.y } end,
        move = function(dx, dy)
            db.x, db.y = drag.x + dx, drag.y + dy
            self:Layout()
        end,
        stop = function()
            local G = SKT.Grid
            local w = D.OnPx(G.Boxes(db.size))
            db.x = G.SnapOne(db.x - w / 2) + w / 2
            db.y = G.SnapOne(db.y)
            self:Layout()
        end,
    })

    self.tag = SKT.Grid.Tag(root, "Minimap")
    self.fragment = ZO_HUDFadeSceneFragment:New(root)
    -- coming back from a menu (Escape and the like): lay it out again, so every setting shows
    self.fragment:RegisterCallback("StateChange", function(_, newState)
        if newState == SCENE_FRAGMENT_SHOWN then self:Layout() end
    end)
end

function M:Layout()
    if not self.root then return end
    local db, G = self.db, SKT.Grid
    local trim = G.Trim()
    local px = D.Px()
    local s = D.OnPx(G.Boxes(db.size))
    local w = s - trim

    -- default place: top right of the screen
    if not db.x then
        db.x = GuiRoot:GetWidth() / 2 - s / 2 - 32
        db.y = -GuiRoot:GetHeight() / 2 + 32
    end

    -- the location: a framed strip above the circle, a little gap between them
    local fontSize = math.max(10, math.floor(math.max(w, 120) * 0.075))
    -- the location strip: one fixed size (a little roomier than one line needs); the text is
    -- sized to fit it
    self.zoneFont = fontSize
    local zoneLines = 1
    local stripH = db.showZone and D.OnPx(fontSize * 1.35 + 12) or 0
    -- the bee keeps its original size (a line's height), whatever the strip
    local beeH = D.OnPx(fontSize * 1.35 + 6)
    -- with the frame: the gap also clears the part of the frame that stands out past the map
    self.gap = D.OnPx(6)
    if db.frame ~= false then self.gap = D.OnPx(6 + w * (FRAME_SCALE - 1) / 2) end
    local top = db.showZone and (stripH + self.gap) or 0

    self.info:ClearAnchors()
    self.info:SetAnchor(TOPLEFT, self.root, TOPLEFT, 0, 0)
    self.info:SetDimensions(w, math.max(0.01, stripH))
    local c = SKT.colors.bg
    D.Fill(self.info, c[1], c[2], c[3], (db.bgAlpha or 90) / 100)
    self.info:SetHidden(not db.showZone)
    self.infoLine:SetHidden(true)

    -- the bee on the left of the strip
    local beeSize = D.OnPx(math.max(12, beeH - 2 * px))
    self.bee:ClearAnchors()
    self.bee:SetAnchor(LEFT, self.root, TOPLEFT, D.OnPx(3), stripH / 2)
    self.bee:SetDimensions(beeSize, beeSize)
    self.bee:SetHidden(not db.showZone)
    local textLeft = D.OnPx(3) + beeSize + D.OnPx(2)

    local zoneLabel = self.lines[1]
    zoneLabel:SetFont("$(MEDIUM_FONT)|" .. fontSize .. "|soft-shadow-thin")
    zoneLabel:ClearAnchors()
    -- centred on the whole strip; kept as wide on the right as the bee takes on the left, so a
    -- long name never runs under the bee
    zoneLabel:SetAnchor(CENTER, self.root, TOPLEFT, w / 2, stripH / 2)
    zoneLabel:SetWidth(math.max(20, w - 2 * textLeft))
    zoneLabel:SetMaxLineCount(zoneLines)
    zoneLabel:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    zoneLabel:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    self.zoneRoom = math.max(20, w - 2 * textLeft)
    zoneLabel:SetHidden(not db.showZone)
    if db.showZone then
        D.DrawRing(self.ringAll, self.root, 0, 0, w, stripH, SilverAt)
    end
    for _, t in ipairs(self.ringAll.edges) do t:SetHidden(not db.showZone) end
    for _, t in ipairs(self.ringAll.dots) do t:SetHidden(not db.showZone) end

    -- the circle
    self.view:ClearAnchors()
    self.view:SetAnchor(TOPLEFT, self.root, TOPLEFT, 0, top)
    self.view:SetDimensions(w, w)
    self.mapView = w

    -- the arrow: a little bigger with a bigger map
    local pipSize = D.OnPx(math.max(13, w * 0.096))
    self.pip:ClearAnchors()
    self.pip:SetAnchor(CENTER, self.view, CENTER, 0, 0)
    self.pip:SetDimensions(pipSize, pipSize)

    local coneSize = D.OnPx(w * CONE_SIZE)
    self.cone:ClearAnchors()
    self.cone:SetAnchor(CENTER, self.view, CENTER, 0, 0)
    self.cone:SetDimensions(coneSize, coneSize)
    self.cone:SetHidden(not db.showCone)

    -- your own time: inside the circle, at the bottom
    local clock = self.lines[2]
    clock:SetFont("$(BOLD_FONT)|" .. fontSize .. "|thick-outline")
    -- centred across the full width of the circle; the digits' middle 7 % of the map up from its
    -- bottom (the font's line leaves room below the digits: moved down by 0.14 of the font size)
    clock:ClearAnchors()
    clock:SetWidth(w)
    clock:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    clock:SetAnchor(CENTER, self.view, BOTTOM, 0, D.OnPx(-w * 0.07 + fontSize * 0.14))
    clock:SetDrawTier(DT_HIGH)
    clock:SetHidden(not db.showTimeLocal)
    self.lines[3]:SetHidden(true)

    self.root:SetDimensions(w, top + w)

    -- the silver disk behind the map (its edge shows as the ring), shaded top to bottom
    self.disk:ClearAnchors()
    self.disk:SetAnchor(CENTER, self.view, CENTER, 0, 0)
    self.disk:SetDimensions(w + 2 * px, w + 2 * px)
    local r1, g1, b1 = SilverAt(0)
    local r2, g2, b2 = SilverAt(1)
    D.VGrad(self.disk, r1, g1, b1, 1, r2, g2, b2, 1)
    -- the silver frame round the map (or, without it, the thin ring the disk makes)
    local framed = db.frame ~= false
    self.frame:ClearAnchors()
    self.frame:SetAnchor(CENTER, self.view, CENTER, 0, 0)
    local fs = D.OnPx(w * FRAME_SCALE)
    self.frame:SetDimensions(fs, fs)
    self.frame:SetHidden(not framed)
    self.disk:SetHidden(framed)

    self.root:ClearAnchors()
    local left = G.SnapOne((db.x or 0) - s / 2)
    local rootTop = G.SnapOne(db.y or 0)
    self.root:SetAnchor(TOPLEFT, GuiRoot, CENTER, D.OnPx(left), D.OnPx(rootTop))

    self.clipKey = nil
    self:PlaceMap()
    self:Clip()
    self:UpdateInfo()
end

-- the bee faces right, and left while the settings window is open
function M:FaceBee()
    if not self.bee then return end
    local open = SKT.window and not SKT.window:IsHidden()
    if open then self.bee:SetTextureCoords(1, 0, 0, 1) else self.bee:SetTextureCoords(0, 1, 0, 1) end
end

-- cut the map, its background and the silver disk to circles round the map window's centre
-- (screen positions, so this runs again whenever the minimap moves)
function M:Clip()
    if not self.view then return end
    local cx, cy = self.view:GetCenter()
    if not cx then return end
    local r = (self.mapView or 0) / 2
    -- nothing moved: nothing to do (checked often, as the minimap's place settles a frame late)
    local key = cx .. ":" .. cy .. ":" .. r .. ":" .. #self.tiles .. ":" .. tostring(self.tileKey)
        .. ":" .. #(self.pins or {})
    if key == self.clipKey then return end
    self.clipKey = key
    local px = D.Px()
    local function Cut(t, radius)
        if t.SetCircularClip then t:SetCircularClip(cx, cy, radius) end
    end
    Cut(self.viewBg, r)
    Cut(self.disk, r + px)
    Cut(self.cone, r)
    for _, t in ipairs(self.tiles) do Cut(t, r) end
    for _, t in ipairs(self.pins or {}) do Cut(t, r) end
end

---------------------------------------------------------------------------
-- Pins: quests, points of interest (wayshrines and the like), your waypoint and your group,
-- on the map so they move with it. Group pins: round dots (the leader bigger and gold).
---------------------------------------------------------------------------
function M:GetPin()
    self.pinN = self.pinN + 1
    local t = self.pins[self.pinN]
    if not t then
        t = WM:CreateControl(nil, self.view, CT_TEXTURE)
        t:SetDrawTier(DT_HIGH)
        self.pins[self.pinN] = t
        self.clipKey = nil
    end
    t:SetHidden(false)
    t:SetColor(1, 1, 1, 1)
    t:SetTextureRotation(0)
    return t
end

local function Place(m, t, x, y, size, tex, level, scale)
    size = size * ((scale or m.db.pinSize or 100) / 100)
    t:SetTexture(tex)
    t:SetDrawLevel(level or 3)
    t:SetDimensions(size, size)
    t:ClearAnchors()
    t:SetAnchor(CENTER, m.map, TOPLEFT, x * m.mapSize, y * m.mapSize)
    t.nx, t.ny = x, y
end

-- the pins that stay put: points of interest, quests, your waypoint
function M:CollectPins()
    local db = self.db
    local list = {}
    if db.pinPOI and GetCurrentMapZoneIndex and GetNumPOIs then
        local zi = GetCurrentMapZoneIndex()
        for i = 1, (zi and GetNumPOIs(zi) or 0) do
            local x, y, _, icon, shown = GetPOIMapInfo(zi, i)
            if shown and icon and icon ~= "" and x and x > 0 and y > 0 then
                list[#list + 1] = { x = x, y = y, tex = icon, size = 22, level = 2 }
            end
        end
    end
    local crumbs = WORLD_MAP_QUEST_BREADCRUMBS
    if db.pinQuest and crumbs and crumbs.GetSteps then
        for qi = 1, (MAX_JOURNAL_QUESTS or 25) do
            if IsValidQuestIndex(qi) then
                local focus = GetTrackedIsAssisted and GetTrackedIsAssisted(TRACK_TYPE_QUEST, qi)
                local ok, steps = pcall(crumbs.GetSteps, crumbs, qi)
                if ok and type(steps) == "table" then
                    for _, step in pairs(steps) do
                        if type(step) == "table" then
                            for _, c in pairs(step) do
                                if type(c) == "table" and c.xLoc and c.insideCurrentMapWorld ~= false then
                                    list[#list + 1] = { x = c.xLoc, y = c.yLoc, size = focus and 26 or 20,
                                        tex = focus and QUEST_ICON_FOCUS or QUEST_ICON, level = focus and 5 or 4 }
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if db.pinWaypoint and GetMapPlayerWaypoint then
        local x, y = GetMapPlayerWaypoint()
        if x and y and (x > 0 or y > 0) then
            list[#list + 1] = { x = x, y = y, size = 14, tex = CIRCLE, level = 5, ring = true,
                color = { 0.95, 0.76, 0.31 } }
        end
    end
    self.staticPins = list
end

-- lay every pin out: the fixed ones from the list, the group from where they are now
function M:LayoutPins()
    if not self.pins or not self.mapSize then return end
    self.pinN = 0
    for _, p in ipairs(self.staticPins or {}) do
        if p.ring then
            local back = self:GetPin()
            Place(self, back, p.x, p.y, p.size + 4, CIRCLE, p.level - 1)
            back:SetColor(0, 0, 0, 0.85)
        end
        local t = self:GetPin()
        Place(self, t, p.x, p.y, p.size, p.tex, p.level)
        if p.color then t:SetColor(p.color[1], p.color[2], p.color[3], 1) end
    end
    self.groupFrom = self.pinN + 1
    self:LayoutGroupPins()
end

function M:LayoutGroupPins()
    if not self.pins or not self.mapSize or not self.groupFrom then return end
    self.pinN = self.groupFrom - 1
    if self.db.pinGroup then
        for i = 1, GetGroupSize() do
            local tag = GetGroupUnitTagByIndex(i)
            if tag and not AreUnitsEqual(tag, "player") and IsUnitOnline(tag) then
                local x, y = GetMapPlayerPosition(tag)
                if x and y and (x > 0 or y > 0) then
                    local leader = IsUnitGroupLeader(tag)
                    local size = leader and 12 or 9
                    local back = self:GetPin()
                    local gs = self.db.groupSize or 100
                    Place(self, back, x, y, size + 4, CIRCLE, 6, gs)
                    back:SetColor(0, 0, 0, 0.85)
                    local t = self:GetPin()
                    Place(self, t, x, y, size, CIRCLE, 7, gs)
                    local c = leader and LEADER_COLOR or GROUP_COLOR
                    t:SetColor(c[1], c[2], c[3], 1)
                end
            end
        end
    end
    for i = self.pinN + 1, #self.pins do self.pins[i]:SetHidden(true) end
end

function M:RefreshPins()
    if not self.pins then return end
    if self.db.enabled then self:CollectPins() else self.staticPins = {} end
    self:LayoutPins()
end

---------------------------------------------------------------------------
-- The map
---------------------------------------------------------------------------
local function WorldMapOpen()
    return ZO_WorldMap_IsWorldMapShowing and ZO_WorldMap_IsWorldMapShowing()
end

-- the map's tiles: rebuilt when the map changes
function M:LoadTiles()
    local nh, nv = GetMapNumTiles()
    nh, nv = nh or 0, nv or 0
    local first = (nh > 0) and GetMapTileTexture(1) or ""
    if first == self.tileKey and nh == self.nh then return end
    self.tileKey, self.nh, self.nv = first, nh, nv
    self.pinsDirty = true
    local n = nh * nv
    for i = 1, n do
        local t = self.tiles[i]
        if not t then
            t = WM:CreateControl(nil, self.map, CT_TEXTURE)
            t:SetDrawLevel(1)
            self.tiles[i] = t
        end
        t:SetTexture(GetMapTileTexture(i))
        t:SetHidden(false)
    end
    for i = n + 1, #self.tiles do self.tiles[i]:SetHidden(true) end
    self:SizeTiles()
    self:Clip()
end

function M:SizeTiles()
    local size = (self.mapView or 200) * (self.db.zoom or 6)
    self.mapSize = size
    self.map:SetDimensions(size, size)
    local nh, nv = self.nh or 0, self.nv or 0
    if nh == 0 then return end
    self:LayoutPins()
    local tw, th = size / nh, size / nv
    for row = 0, nv - 1 do
        for col = 0, nh - 1 do
            local t = self.tiles[row * nh + col + 1]
            if t then
                t:ClearAnchors()
                t:SetAnchor(TOPLEFT, self.map, TOPLEFT, col * tw, row * th)
                t:SetDimensions(tw, th)
            end
        end
    end
end

function M:PlaceMap()
    if not self.mapView then return end
    if (self.mapView * (self.db.zoom or 6)) ~= self.mapSize then self:SizeTiles() end
    local x, y, heading = GetMapPlayerPosition("player")
    x, y = x or 0.5, y or 0.5
    local half = self.mapView / 2
    self.map:ClearAnchors()
    self.map:SetAnchor(TOPLEFT, self.view, TOPLEFT, half - x * self.mapSize, half - y * self.mapSize)
    if heading then self.pip:SetTextureRotation(heading) end
    self:LayoutGroupPins()
    if self.db.showCone and GetPlayerCameraHeading then
        local cam = GetPlayerCameraHeading()
        if cam then self.cone:SetTextureRotation(cam) end
    end
    self:Clip()
end

-- once a second, when the world map is closed: make sure the map is the one you are on
function M:CheckMap()
    if WorldMapOpen() then return end
    if SetMapToPlayerLocation then SetMapToPlayerLocation() end
    self:LoadTiles()
end

---------------------------------------------------------------------------
-- The info strip
---------------------------------------------------------------------------
function M:UpdateInfo()
    if not self.lines then return end
    local db = self.db
    if db.showZone then
        local zone = zo_strformat("<<1>>", GetUnitZone("player") or "")
        local place = zo_strformat("<<1>>", GetPlayerLocationName() or "")
        -- the whole name on one line: at the usual size if it fits, else smaller until it does
        local label = self.lines[1]
        local room = self.zoneRoom or 0
        local base = self.zoneFont or 14
        local text = (place ~= "" and place ~= zone) and (place .. "  ·  " .. zone) or zone
        local function Font(sz) return "$(MEDIUM_FONT)|" .. sz .. "|soft-shadow-thin" end
        local size = base
        label:SetFont(Font(size))
        local ok, w = pcall(label.GetStringWidth, label, text)
        if ok and type(w) == "number" and w > room and room > 0 then
            size = math.max(8, math.floor(base * room / w))
            label:SetFont(Font(size))
            -- the font's widths don't scale exactly: step down until it fits
            for sz = size, 8, -1 do
                label:SetFont(Font(sz))
                size = sz
                local ok2, w2 = pcall(label.GetStringWidth, label, text)
                if not ok2 or type(w2) ~= "number" or w2 <= room then break end
            end
        end
        label:SetMaxLineCount(1)
        label:SetText(text)
    end
    if db.showTimeLocal then
        -- 24-hour, always four digits: 03:00, 23:00
        local secs = GetSecondsSinceMidnight and GetSecondsSinceMidnight() or 0
        self.lines[2]:SetText(string.format("%02d:%02d", math.floor(secs / 3600) % 24, math.floor(secs / 60) % 60))
    end
end

---------------------------------------------------------------------------
-- Lock, show
---------------------------------------------------------------------------
function M:ApplyLock()
    local locked = self.db.locked
    self.root:SetMouseEnabled(not locked)
    self.tag:SetHidden(locked)
    -- while unlocked the map lets the drag through (no wheel zoom then)
    self.view:SetMouseEnabled(locked)
    SKT.Grid:Update()
end

function M:ApplyEnabled()
    local on = self.db.enabled
    if on and not self.fragmentAdded then
        HUD_SCENE:AddFragment(self.fragment)
        HUD_UI_SCENE:AddFragment(self.fragment)
        self.fragmentAdded = true
    elseif not on and self.fragmentAdded then
        HUD_SCENE:RemoveFragment(self.fragment)
        HUD_UI_SCENE:RemoveFragment(self.fragment)
        self.fragmentAdded = false
        self.root:SetHidden(true)
    end
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
SKT:RegisterModule({
    key   = "Minimap",
    title = "Minimap",
    order = 40,

    defaults = {
        enabled = true,
        locked  = true,
        -- x, y: top centre from the middle of the screen (nil: top right of the screen)
        size = 224,
        zoom = 6,                 -- how many times the map window the whole map is
        bgAlpha = 90,
        showZone = true,
        frame = true,             -- the silver frame round the map
        showTimeLocal = true,
        showCone = true,          -- the camera's view cone
        pinQuest = true,
        pinPOI = true,            -- wayshrines, dungeons, delves and other points of interest
        pinWaypoint = true,
        pinGroup = true,
        pinSize = 100,            -- % of the pins' own sizes (50 to 300)
        groupSize = 100,          -- % of the group dots' size (50 to 300)
    },

    OnLoad = function(self, db)
        M.db = db
        local NUM = { size = 224, zoom = 6, bgAlpha = 90 }
        for k, v in pairs(NUM) do if type(db[k]) ~= "number" then db[k] = v end end
        M:Build()
        M:Layout()
        M:ApplyLock()
        M:ApplyEnabled()

        EM:RegisterForUpdate(NS .. "Pos", 33, function()
            if M.db.enabled and not M.root:IsHidden() and not WorldMapOpen() then M:PlaceMap() end
        end)
        EM:RegisterForUpdate(NS .. "Slow", 1000, function()
            if not M.db.enabled then return end
            M:CheckMap()
            M:UpdateInfo()
            -- the fixed pins, every few seconds (quests move on, places get discovered)
            M.pinTimer = (M.pinTimer or 0) + 1
            if M.pinsDirty or M.pinTimer >= 3 then
                M.pinsDirty, M.pinTimer = false, 0
                if not WorldMapOpen() then M:RefreshPins() end
            end
        end)
        local function Changed() zo_callLater(function() M:CheckMap(); M:UpdateInfo() end, 200) end
        EM:RegisterForEvent(NS, EVENT_PLAYER_ACTIVATED, Changed)
        EM:RegisterForEvent(NS, EVENT_ZONE_CHANGED, Changed)
        EM:RegisterForEvent(NS .. "Scale", EVENT_ALL_GUI_SCREENS_RESIZED, function() M:Layout() end)
        local function Soon() M.pinsDirty = true end
        local n = 0
        for _, ev in pairs({ EVENT_QUEST_ADDED, EVENT_QUEST_REMOVED, EVENT_QUEST_ADVANCED,
                              EVENT_QUEST_CONDITION_COUNTER_CHANGED, EVENT_QUEST_POSITION_REQUEST_COMPLETE,
                              EVENT_TRACKING_UPDATE, EVENT_PLAYER_WAYPOINT_CHANGED, EVENT_POI_UPDATED,
                              EVENT_POI_DISCOVERED }) do
            if ev then n = n + 1; EM:RegisterForEvent(NS .. "Pin" .. n, ev, Soon) end
        end
        if WORLD_MAP_QUEST_BREADCRUMBS and WORLD_MAP_QUEST_BREADCRUMBS.RegisterCallback then
            WORLD_MAP_QUEST_BREADCRUMBS:RegisterCallback("QuestAvailable", Soon)
            WORLD_MAP_QUEST_BREADCRUMBS:RegisterCallback("QuestRemoved", Soon)
        end
    end,

    BuildTab = function(self, page, db)
        local L = SKT.UI.Column(page, 16, 268)
        local R = SKT.UI.Column(page, 316, 268)
        local function relayout() M:Layout() end

        L:Header("Minimap")
        L:Check("Enable", function() return db.enabled end, function(v) db.enabled = v; M:ApplyEnabled() end)

        L:Header("Size")
        L:Slider("Size", 96, 480, 8,
            function() return db.size end, function(v) db.size = v; relayout() end, SKT.Grid.Fmt)
        M.zoomSlider = L:Slider("Zoom", 1, 40, 1,
            function() return zo_round(db.zoom) end,
            function(v) db.zoom = v; M:PlaceMap() end,
            function(v) return "x" .. v end)
        L:Slider("Location strip opacity", 0, 100, 5,
            function() return db.bgAlpha end, function(v) db.bgAlpha = v; relayout() end,
            function(v) return v .. "%" end)
        L:Button("Reset position", 180, function() db.x, db.y = nil, nil; relayout() end)

        R:Header("Show")
        R:Check("Location", function() return db.showZone end, function(v) db.showZone = v; relayout() end)
        R:Check("Your own time", function() return db.showTimeLocal end, function(v) db.showTimeLocal = v; relayout() end)
        R:Check("Camera view cone", function() return db.showCone end, function(v) db.showCone = v; relayout() end)
        R:Check("Silver frame", function() return db.frame ~= false end, function(v) db.frame = v; relayout() end)

        R:Header("Pins")
        local function pins() M:RefreshPins() end
        R:Check("Quests", function() return db.pinQuest end, function(v) db.pinQuest = v; pins() end)
        R:Check("Wayshrines and places", function() return db.pinPOI end, function(v) db.pinPOI = v; pins() end)
        R:Check("Your waypoint", function() return db.pinWaypoint end, function(v) db.pinWaypoint = v; pins() end)
        R:Check("Group members", function() return db.pinGroup end, function(v) db.pinGroup = v; pins() end)
        -- 0.5 to 3 (3 = 300 %), in tenths
        R:Slider("Pin size", 5, 30, 1,
            function() return zo_round((db.pinSize or 100) / 10) end,
            function(v) db.pinSize = v * 10; pins() end,
            function(v) return string.format("%.1f", v / 10) end)
        R:Slider("Group icon size", 5, 30, 1,
            function() return zo_round((db.groupSize or 100) / 10) end,
            function(v) db.groupSize = v * 10; pins() end,
            function(v) return string.format("%.1f", v / 10) end)
    end,
})
