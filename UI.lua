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

function SKT.UI.Header(parent, name, x, y, text)
    local lbl = MakeLabel(parent:GetName() .. name, parent, text, "ZoFontWinH3", SKT.colors.title)
    lbl:SetAnchor(TOPLEFT, parent, TOPLEFT, x, y)
    return lbl
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
function SKT:BuildWindow()
    if self.window then return end

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

    local bg = MakeBackdrop("$(parent)BG", win, self.colors.bg, self.colors.edge, 2)
    bg:SetAnchorFill(win)

    local title = MakeLabel("$(parent)Title", win, "SKTools", "ZoFontWinH1", self.colors.title)
    title:SetAnchor(TOPLEFT, win, TOPLEFT, 18, 10)

    local sub = MakeLabel("$(parent)Sub", win, "Elder Scrolls Online  ·  by " .. self.author,
        "ZoFontGameSmall", self.colors.muted)
    sub:SetAnchor(TOPLEFT, title, BOTTOMLEFT, 2, -2)

    local ver = MakeLabel("$(parent)Ver", win, "v" .. self.version, "ZoFontGameSmall", self.colors.muted)
    ver:SetAnchor(TOPRIGHT, win, TOPRIGHT, -44, 16)

    local close = WM:CreateControlFromVirtual("$(parent)Close", win, "ZO_CloseButton")
    close:SetAnchor(TOPRIGHT, win, TOPRIGHT, -10, 12)
    close:SetHandler("OnClicked", function() self:HideWindow() end)

    local tabCol = MakeBackdrop("$(parent)Tabs", win, self.colors.panel, self.colors.edge, 1)
    tabCol:SetAnchor(TOPLEFT, win, TOPLEFT, 12, HEADER_H)
    tabCol:SetAnchor(BOTTOMLEFT, win, BOTTOMLEFT, 12, -12)
    tabCol:SetWidth(TAB_W + 8)

    local content = MakeBackdrop("$(parent)Content", win, self.colors.panel, self.colors.edge, 1)
    content:SetAnchor(TOPLEFT, tabCol, TOPRIGHT, 8, 0)
    content:SetAnchor(BOTTOMRIGHT, win, BOTTOMRIGHT, -12, -12)

    self.window, self.content, self.tabs, self.pages = win, content, {}, {}

    for i, mod in ipairs(self.modules) do
        self:CreateTab(tabCol, mod, i)
    end

    self:SelectTab(self:GetModule(self.db.lastTab) and self.db.lastTab or self.modules[1].key)
end

function SKT:CreateTab(tabCol, mod, index)
    local tab = WM:CreateControl("SKToolsESO_Tab" .. mod.key, tabCol, CT_BUTTON)
    tab:SetDimensions(TAB_W, TAB_H)
    tab:SetAnchor(TOPLEFT, tabCol, TOPLEFT, 4, 4 + (index - 1) * (TAB_H + 4))
    tab:SetMouseEnabled(true)

    local bg = MakeBackdrop("$(parent)BG", tab, self.colors.tabIdle, self.colors.edge, 1)
    bg:SetAnchorFill(tab)

    -- Active tab is marked by a shape (arrow) as well as colour.
    local marker = MakeLabel("$(parent)Marker", tab, "›", "ZoFontWinH3", self.colors.title)
    marker:SetAnchor(LEFT, tab, LEFT, 6, 0)
    marker:SetHidden(true)

    local lbl = MakeLabel("$(parent)Label", tab, mod.title, "ZoFontGame", self.colors.text)
    lbl:SetAnchor(LEFT, tab, LEFT, 20, 0)

    tab:SetHandler("OnClicked", function() self:SelectTab(mod.key) end)
    tab:SetHandler("OnMouseEnter", function() if self.activeTab ~= mod.key then lbl:SetColor(col(self.colors.title)) end end)
    tab:SetHandler("OnMouseExit",  function() if self.activeTab ~= mod.key then lbl:SetColor(col(self.colors.text)) end end)

    self.tabs[mod.key] = { button = tab, bg = bg, marker = marker, label = lbl }
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
        t.bg:SetCenterColor(col(active and self.colors.tabActive or self.colors.tabIdle))
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
