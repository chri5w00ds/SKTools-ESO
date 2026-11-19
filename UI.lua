-- SKTools-ESO by Scotskoogen-Chris
-- UI: the main tabbed settings window plus small control helpers modules can use.

local SKT = SKT
local WM = WINDOW_MANAGER

local WIN_W, WIN_H = 780, 600
local TAB_W, TAB_H = 140, 30
local HEADER_H = 56

local function col(c) return c[1], c[2], c[3], c[4] end
SKT.col = col

local function MakeBackdrop(name, parent, center, edge, edgeSize)
    local bd = WM:CreateControl(name, parent, CT_BACKDROP)
    bd:SetCenterColor(col(center))
    bd:SetEdgeColor(col(edge))
    bd:SetEdgeTexture("", 1, 1, edgeSize or 2, 0)
    return bd
end
SKT.MakeBackdrop = MakeBackdrop

local function MakeLabel(name, parent, text, font, color)
    local lbl = WM:CreateControl(name, parent, CT_LABEL)
    lbl:SetFont(font or "ZoFontGame")
    lbl:SetColor(col(color or SKT.colors.text))
    lbl:SetText(text or "")
    return lbl
end
SKT.MakeLabel = MakeLabel

---------------------------------------------------------------------------
-- Helpers for module tabs. All take (parent, name, x, y, ...).
---------------------------------------------------------------------------
SKT.UI = {}

local function Tooltip(control, text)
    if not text then return end
    control:SetMouseEnabled(true)
    control:SetHandler("OnMouseEnter", function(self)
        InitializeTooltip(InformationTooltip, self, BOTTOMLEFT, 0, -4, TOPLEFT)
        SetTooltipText(InformationTooltip, text)
    end)
    control:SetHandler("OnMouseExit", function() ClearTooltip(InformationTooltip) end)
end

-- A section heading: gold capitals with a bronze line under them (as wide as width).
function SKT.UI.Header(parent, name, x, y, text, width)
    local lbl = MakeLabel(parent:GetName() .. name, parent, zo_strupper(text or ""),
        "$(BOLD_FONT)|15|soft-shadow-thin", SKT.colors.title)
    lbl:SetAnchor(TOPLEFT, parent, TOPLEFT, x, y)
    local line = WM:CreateControl(parent:GetName() .. name .. "Line", parent, CT_TEXTURE)
    line:SetColor(SKT.col(SKT.colors.bronze))
    line:SetAnchor(TOPLEFT, parent, TOPLEFT, x, y + 22)
    line:SetDimensions(width or 270, 1)
    return lbl
end

-- A column of controls laid out top to bottom, each section under a heading.
--   local c = SKT.UI.Column(page, x, width)
--   c:Header("Size"); c:Check(...); c:Slider(...); c:Button(...); c:Space(8)
-- c.y is where the next control goes (for custom controls: place at c.y, then c:Space(height)).
function SKT.UI.Column(page, x, width)
    local c = { page = page, x = x, w = width or 270, y = 14, n = 0 }
    local function Id() c.n = c.n + 1; return "C" .. x .. "_" .. c.n end
    function c:Header(text)
        if self.y > 14 then self.y = self.y + 14 end
        local h = SKT.UI.Header(page, Id(), self.x, self.y, text, self.w)
        self.y = self.y + 32
        return h
    end
    function c:Check(text, get, set, tip)
        local cb = SKT.UI.Checkbox(page, Id(), self.x, self.y, text, get, set, tip)
        self.y = self.y + 26
        return cb
    end
    function c:Slider(text, minV, maxV, step, get, set, fmt)
        local sl = SKT.UI.Slider(page, Id(), self.x, self.y, self.w, text, minV, maxV, step, get, set, fmt)
        self.y = self.y + 44
        return sl
    end
    function c:Button(text, w, fn)
        local b = SKT.UI.Button(page, Id(), self.x, self.y, text, w or 180, fn)
        self.y = self.y + 34
        return b
    end
    -- buttons side by side: { { text, width, fn }, ... }
    function c:Buttons(list)
        local bx, out = self.x, {}
        for _, b in ipairs(list) do
            out[#out + 1] = SKT.UI.Button(page, Id(), bx, self.y, b[1], b[2], b[3])
            bx = bx + b[2] + 8
        end
        self.y = self.y + 34
        return unpack(out)
    end
    -- one of several: ticks that act as radio buttons. options = { { value, text }, ... }
    function c:Choice(options, get, set)
        local boxes = {}
        local function Sync()
            for _, b in ipairs(boxes) do ZO_CheckButton_SetCheckState(b.cb, get() == b.value) end
        end
        for _, o in ipairs(options) do
            local value = o[1]
            local cb = self:Check(o[2], function() return get() == value end, function()
                set(value); Sync()
            end)
            boxes[#boxes + 1] = { cb = cb, value = value }
        end
        return boxes
    end
    -- a colour: its name, a swatch (click: ESO's colour picker) and Reset. get() -> {r,g,b} or nil
    -- (nil: the default), set({r,g,b} or nil), default = {r,g,b}
    -- the same, side by side on one line (short labels)
    function c:ChoiceRow(options, get, set)
        local boxes = {}
        local function Sync()
            for _, b in ipairs(boxes) do ZO_CheckButton_SetCheckState(b.cb, get() == b.value) end
        end
        -- each one after the last one's label (measured), so long labels never run into the next
        local x = self.x
        for _, o in ipairs(options) do
            local value = o[1]
            local cb = SKT.UI.Checkbox(page, Id(), x, self.y, o[2],
                function() return get() == value end, function() set(value); Sync() end)
            boxes[#boxes + 1] = { cb = cb, value = value }
            local label = cb.label or GetControl(cb, "Label")
            local tw = (label and label:GetTextWidth()) or (#o[2] * 8)
            x = x + 24 + tw + 18
        end
        self.y = self.y + 26
        return boxes
    end
    -- a colour: its name, a swatch (click: ESO's colour picker) and Reset. get() -> {r,g,b} or nil
    -- (nil: the default), set({r,g,b} or nil), default = {r,g,b}; enabled() (optional): when false
    -- the row is dimmed and the swatch doesn't open. Returns Paint (call it to redraw the row).
    function c:Color(text, get, set, default, enabled)
        local id = page:GetName() .. Id()
        local lbl = WM:CreateControl(id .. "L", page, CT_LABEL)
        lbl:SetFont("ZoFontGame")
        lbl:SetText(text)
        lbl:SetAnchor(TOPLEFT, page, TOPLEFT, self.x, self.y + 4)
        lbl:SetDimensions(self.w - 56 - 80 - 16, 22)
        lbl:SetMaxLineCount(1)
        lbl:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
        local sw = WM:CreateControl(id .. "S", page, CT_TEXTURE)
        sw:SetDimensions(56, 16)
        sw:SetAnchor(TOPLEFT, page, TOPLEFT, self.x + self.w - 56 - 88, self.y + 7)
        local edge = WM:CreateControl(id .. "E", sw, CT_BACKDROP)
        edge:SetAnchor(TOPLEFT, sw, TOPLEFT, -1, -1)
        edge:SetAnchor(BOTTOMRIGHT, sw, BOTTOMRIGHT, 1, 1)
        edge:SetCenterColor(0, 0, 0, 0)
        edge:SetEdgeColor(0.85, 0.85, 0.88, 1)
        edge:SetEdgeTexture("", 1, 1, 1, 0)
        -- the click: a plain button over the swatch (a little bigger, easy to hit)
        local hit = WM:CreateControl(id .. "B", page, CT_BUTTON)
        hit:SetAnchor(TOPLEFT, sw, TOPLEFT, -3, -4)
        hit:SetAnchor(BOTTOMRIGHT, sw, BOTTOMRIGHT, 3, 4)
        hit:SetDrawLevel(10)
        hit:SetMouseEnabled(true)
        local reset = SKT.UI.Button(page, Id(), self.x + self.w - 80, self.y, "Reset", 80, function() end)
        local function On() return not enabled or enabled() end
        local function Paint()
            local col = get() or default
            local on = On()
            sw:SetColor(col[1] or col.r, col[2] or col.g, col[3] or col.b, on and 1 or 0.35)
            lbl:SetColor(SKT.col(on and SKT.colors.text or SKT.colors.muted))
            hit:SetEnabled(on)
            reset:SetEnabled(on and get() ~= nil)
        end
        hit:SetHandler("OnClicked", function()
            if not On() then return end
            local col = get() or default
            COLOR_PICKER:Show(function(r, g, b) set({ r, g, b }); Paint() end,
                col[1] or col.r, col[2] or col.g, col[3] or col.b, 1, text)
        end)
        hit:SetHandler("OnMouseEnter", function() if On() then edge:SetEdgeColor(0.95, 0.76, 0.31, 1) end end)
        hit:SetHandler("OnMouseExit", function() edge:SetEdgeColor(0.85, 0.85, 0.88, 1) end)
        reset:SetHandler("OnClicked", function() set(nil); Paint() end)
        Paint()
        self.y = self.y + 36
        return Paint
    end
    function c:Text(text)
        local t = SKT.UI.Text(page, Id(), self.x, self.y, text, self.w)
        self.y = self.y + math.max(20, (t:GetTextHeight() or 20)) + 6
        return t
    end
    function c:Space(n) self.y = self.y + (n or 8) end
    function c:Id() return Id() end
    return c
end

function SKT.UI.Text(parent, name, x, y, text, width)
    local lbl = MakeLabel(parent:GetName() .. name, parent, text, "ZoFontGame", SKT.colors.text)
    lbl:SetAnchor(TOPLEFT, parent, TOPLEFT, x, y)
    lbl:SetDimensionConstraints(0, 0, width or 520, 0)
    return lbl
end

-- Checkbox. getFn() -> bool, setFn(bool).
function SKT.UI.Checkbox(parent, name, x, y, text, getFn, setFn, tooltip)
    local cb = WM:CreateControlFromVirtual(parent:GetName() .. name, parent, "ZO_CheckButton")
    cb:SetAnchor(TOPLEFT, parent, TOPLEFT, x + 2, y)
    ZO_CheckButton_SetLabelText(cb, text)
    local label = cb.label or GetControl(cb, "Label")
    if label then label:SetColor(col(SKT.colors.text)) end
    ZO_CheckButton_SetCheckState(cb, getFn())
    ZO_CheckButton_SetToggleFunction(cb, function(_, checked) setFn(checked) end)
    Tooltip(cb, tooltip)
    return cb
end

-- Slider with label above and current value on the right. Takes ~40 px of height.
function SKT.UI.Slider(parent, name, x, y, width, text, minV, maxV, step, getFn, setFn, fmt)
    local base = parent:GetName() .. name
    local lbl = MakeLabel(base .. "Label", parent, text, "ZoFontGameSmall", SKT.colors.text)
    lbl:SetAnchor(TOPLEFT, parent, TOPLEFT, x, y)

    local val = MakeLabel(base .. "Value", parent, "", "ZoFontGameSmall", SKT.colors.title)
    val:SetAnchor(TOPRIGHT, parent, TOPLEFT, x + width, y)

    local s = WM:CreateControl(base, parent, CT_SLIDER)
    s:SetDimensions(width, 14)
    s:SetAnchor(TOPLEFT, parent, TOPLEFT, x, y + 20)
    s:SetMouseEnabled(true)
    s:SetOrientation(ORIENTATION_HORIZONTAL)
    s:SetThumbTexture("EsoUI/Art/Miscellaneous/scrollbox_elevator.dds",
                      "EsoUI/Art/Miscellaneous/scrollbox_elevator_disabled.dds", nil, 8, 16)
    s:SetMinMax(minV, maxV)
    s:SetValueStep(step)

    local bg = WM:CreateControl(base .. "BG", s, CT_BACKDROP)
    bg:SetCenterColor(0, 0, 0, 0.6)
    bg:SetAnchor(TOPLEFT, s, TOPLEFT, 0, 4)
    bg:SetAnchor(BOTTOMRIGHT, s, BOTTOMRIGHT, 0, -4)
    bg:SetEdgeTexture("EsoUI/Art/Tooltips/UI-SliderBackdrop.dds", 32, 4)

    local function show(v) val:SetText(fmt and fmt(v) or tostring(v)) end
    local start = getFn()
    s:SetValue(start)
    show(start)
    s:SetHandler("OnValueChanged", function(_, v)
        v = zo_roundToNearest(v, step)
        show(v)
        setFn(v)
    end)
    return s
end

-- Sounds to choose from (only those this client has are offered).
SKT.SOUND_CHOICES = {
    { "Click", "DEFAULT_CLICK" },
    { "Tick",  "BOOK_PAGE_TURN" },
    { "Ding",  "QUEST_FOCUSED" },
    { "Chime", "NEW_NOTIFICATION" },
    { "Bell",  "ACHIEVEMENT_AWARDED" },
    { "Alarm", "DUEL_START" },
    { "Horn",  "AVA_GATE_OPENED" },
}

function SKT.PlaySoundKey(key)
    local snd = SOUNDS and SOUNDS[key or ""]
    if snd then PlaySound(snd) end
end

-- A sound picker: buttons two to a row, the chosen one marked with ». Pressing one plays it.
-- Returns the height used.
function SKT.UI.SoundPicker(parent, name, x, y, getFn, setFn)
    local buttons = {}
    local function Mark()
        for _, b in ipairs(buttons) do
            b.btn:SetText((getFn() == b.key and "» " or "") .. b.label)
        end
    end
    local n = 0
    for _, c in ipairs(SKT.SOUND_CHOICES) do
        if SOUNDS and SOUNDS[c[2]] then
            local i = n
            n = n + 1
            local btn = SKT.UI.Button(parent, name .. c[2], x + (i % 2) * 132, y + math.floor(i / 2) * 32,
                c[1], 128, function()
                    setFn(c[2])
                    SKT.PlaySoundKey(c[2])
                    Mark()
                end)
            buttons[#buttons + 1] = { btn = btn, key = c[2], label = c[1] }
        end
    end
    Mark()
    return math.ceil(n / 2) * 32
end

-- Standard ESO button.
function SKT.UI.Button(parent, name, x, y, text, width, onClick)
    local btn = WM:CreateControlFromVirtual(parent:GetName() .. name, parent, "ZO_DefaultButton")
    btn:SetWidth(width or 160)
    btn:SetText(text)
    btn:SetAnchor(TOPLEFT, parent, TOPLEFT, x, y)
    btn:SetHandler("OnClicked", onClick)
    return btn
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------
local BEE = "SKTools-ESO/Media/Logo.dds"

function SKT:BuildWindow()
    if self.window then return end
    local C = self.colors

    local win = WM:CreateTopLevelWindow("SKToolsESO_Window")
    win:SetDimensions(WIN_W, WIN_H)
    win:SetClampedToScreen(true)
    win:SetMouseEnabled(true)
    win:SetMovable(true)
    win:SetHidden(true)
    win:SetDrawLayer(DL_OVERLAY)

    local pos = self.db.window
    if pos.x and pos.y then
        win:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, pos.x, pos.y)
    else
        win:SetAnchor(CENTER, GuiRoot, CENTER, 0, 0)
    end
    win:SetHandler("OnMoveStop", function(c)
        self.db.window.x, self.db.window.y = c:GetLeft(), c:GetTop()
    end)

    -- the navy ground and a thin silver frame with rounded corners
    local bg = WM:CreateControl("$(parent)BG", win, CT_TEXTURE)
    bg:SetAnchorFill(win)
    bg:SetColor(col(C.bg))
    self.windowRing = SKT.Draw.NewRing(win, 9)
    SKT.Draw.DrawRing(self.windowRing, win, 0, 0, WIN_W, WIN_H, function(f)
        local t, b = { 0.70, 0.71, 0.76 }, { 0.48, 0.49, 0.54 }
        return t[1] + (b[1] - t[1]) * f, t[2] + (b[2] - t[2]) * f, t[3] + (b[3] - t[3]) * f
    end)

    -- the bee and the name
    local bee = WM:CreateControl("$(parent)Bee", win, CT_TEXTURE)
    bee:SetTexture(BEE)
    bee:SetDimensions(44, 44)
    bee:SetAnchor(TOPLEFT, win, TOPLEFT, 12, 6)

    local title = MakeLabel("$(parent)Title", win, "SKTools", "$(BOLD_FONT)|26|soft-shadow-thick", C.title)
    title:SetAnchor(LEFT, bee, RIGHT, 8, 0)

    local ver = MakeLabel("$(parent)Ver", win, "v" .. self.version, "ZoFontGameSmall", C.muted)
    ver:SetAnchor(TOPRIGHT, win, TOPRIGHT, -44, 20)

    local close = WM:CreateControlFromVirtual("$(parent)Close", win, "ZO_CloseButton")
    close:SetAnchor(TOPRIGHT, win, TOPRIGHT, -12, 16)
    close:SetHandler("OnClicked", function() self:HideWindow() end)

    -- the bronze divider with a diamond in its middle
    local div = WM:CreateControl("$(parent)Div", win, CT_TEXTURE)
    div:SetColor(col(C.bronze))
    div:SetAnchor(TOPLEFT, win, TOPLEFT, 16, HEADER_H)
    div:SetDimensions(WIN_W - 32, 1)
    local d1 = WM:CreateControl("$(parent)Diamond", win, CT_TEXTURE)
    d1:SetColor(col(C.gold))
    d1:SetDimensions(10, 10)
    d1:SetAnchor(CENTER, win, TOPLEFT, WIN_W / 2, HEADER_H)
    d1:SetTextureRotation(math.pi / 4)
    local d2 = WM:CreateControl("$(parent)DiamondIn", win, CT_TEXTURE)
    d2:SetColor(col(C.bg))
    d2:SetDimensions(7, 7)
    d2:SetAnchor(CENTER, win, TOPLEFT, WIN_W / 2, HEADER_H)
    d2:SetTextureRotation(math.pi / 4)
    d2:SetDrawLevel(2)

    -- the tab list and the page, each on a slightly lighter panel
    local tabCol = MakeBackdrop("$(parent)Tabs", win, C.panelBg, C.panelEdge, 1)
    tabCol:SetAnchor(TOPLEFT, win, TOPLEFT, 12, HEADER_H + 12)
    tabCol:SetAnchor(BOTTOMLEFT, win, BOTTOMLEFT, 12, -12)
    tabCol:SetWidth(TAB_W + 8)

    local content = MakeBackdrop("$(parent)Content", win, C.panelBg, C.panelEdge, 1)
    content:SetAnchor(TOPLEFT, tabCol, TOPRIGHT, 8, 0)
    content:SetAnchor(BOTTOMRIGHT, win, BOTTOMRIGHT, -12, -12)

    self.window, self.content, self.tabs, self.pages = win, content, {}, {}

    -- anything that shows whether the window is open (the minimap's bee) follows it
    local function Changed() if SKT.Minimap and SKT.Minimap.FaceBee then SKT.Minimap:FaceBee() end end
    win:SetHandler("OnEffectivelyShown", Changed)
    win:SetHandler("OnEffectivelyHidden", Changed)

    for i, mod in ipairs(self.modules) do
        self:CreateTab(tabCol, mod, i)
    end

    self:SelectTab(self:GetModule(self.db.lastTab) and self.db.lastTab or self.modules[1].key)
end

-- a tab: plain text on the panel; the chosen one gold with a › before it
function SKT:CreateTab(tabCol, mod, index)
    local tab = WM:CreateControl("SKToolsESO_Tab" .. mod.key, tabCol, CT_BUTTON)
    tab:SetDimensions(TAB_W, TAB_H)
    tab:SetAnchor(TOPLEFT, tabCol, TOPLEFT, 4, 8 + (index - 1) * TAB_H)
    tab:SetMouseEnabled(true)

    local marker = MakeLabel("$(parent)Marker", tab, "›", "$(BOLD_FONT)|18|soft-shadow-thin", self.colors.title)
    marker:SetAnchor(LEFT, tab, LEFT, 8, -1)
    marker:SetHidden(true)

    local lbl = MakeLabel("$(parent)Label", tab, mod.title, "$(MEDIUM_FONT)|16|soft-shadow-thin", self.colors.text)
    lbl:SetAnchor(LEFT, tab, LEFT, 22, 0)

    tab:SetHandler("OnClicked", function() self:SelectTab(mod.key) end)
    tab:SetHandler("OnMouseEnter", function() if self.activeTab ~= mod.key then lbl:SetColor(col(self.colors.gold)) end end)
    tab:SetHandler("OnMouseExit",  function() if self.activeTab ~= mod.key then lbl:SetColor(col(self.colors.text)) end end)

    self.tabs[mod.key] = { button = tab, marker = marker, label = lbl }
end

function SKT:SelectTab(key)
    local mod = self:GetModule(key)
    if not mod then return end

    if not self.pages[key] then
        local page = WM:CreateControl("SKToolsESO_Page" .. key, self.content, CT_CONTROL)
        page:SetAnchorFill(self.content)
        if mod.BuildTab then mod:BuildTab(page, self.db[key] or self.db) end
        self.pages[key] = page
    end

    for k, t in pairs(self.tabs) do
        local active = (k == key)
        t.marker:SetHidden(not active)
        t.label:SetColor(col(active and self.colors.title or self.colors.text))
        if self.pages[k] then self.pages[k]:SetHidden(not active) end
    end

    self.activeTab = key
    self.db.lastTab = key
end

function SKT:ShowWindow()
    self:BuildWindow()
    self.window:SetHidden(false)
    SCENE_MANAGER:SetInUIMode(true)
end

function SKT:HideWindow()
    if self.window then self.window:SetHidden(true) end
end

function SKT:ToggleWindow()
    if self.window and not self.window:IsHidden() then
        self:HideWindow()
    else
        self:ShowWindow()
    end
end
