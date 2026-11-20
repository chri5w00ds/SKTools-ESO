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

---------------------------------------------------------------------------
-- Reset target dummies: two keys (Controls > Keybindings > SKTools): one dummy (the one under
-- your crosshair, else the nearest), and all of them.
--   In a home you can edit: the dummy, or every target dummy in it, as Target Dummy Tools does: each one is
--   put away and the put-away undone at once, which places it back where it was, at full health.
--   (The housing editor is opened for it and closed again.)
--   Anywhere else (a friend's or guild home): the game's own reset, for the dummies you're
--   fighting (what the housing key, F5, does in combat with them).
---------------------------------------------------------------------------
ZO_CreateStringId("SI_BINDING_NAME_SKTOOLS_RESET_DUMMIES", "Reset all target dummies")
ZO_CreateStringId("SI_BINDING_NAME_SKTOOLS_RESET_DUMMY", "Reset target dummy")

local STEP_MS = 250

-- a placed furnishing that's a target dummy: in the Training Dummies furnishings, or named Target ...
local function IsDummy(furnitureId)
    local name, _, dataId = GetPlacedHousingFurnitureInfo(furnitureId)
    if dataId and GetFurnitureDataInfo and GetFurnitureCategoryName then
        local _, sub = GetFurnitureDataInfo(dataId)
        local cat = sub and GetFurnitureCategoryName(sub)
        if cat and zo_strlower(cat):find("dumm") then return true end
    end
    name = zo_strformat("<<1>>", name or "")
    return name:sub(1, 7) == "Target " or zo_strlower(name):find("dummy") ~= nil
end

local function Dummies()
    local list, id = {}, nil
    repeat
        id = GetNextPlacedHousingFurnitureId(id)
        if id and IsDummy(id) then list[#list + 1] = id end
    until not id
    return list
end

-- the dummy you mean: the one under your crosshair, else the one nearest you
local function TargetDummy(list)
    local tag = DoesUnitExist("reticleover") and "reticleover" or "player"
    local _, tx, ty, tz = GetUnitRawWorldPosition(tag)
    if not tx then return list[1] end
    local best, bestD
    for _, id in ipairs(list) do
        local x, y, z = HousingEditorGetFurnitureWorldPosition(id)
        if x then
            local d = (x - tx) ^ 2 + (y - ty) ^ 2 + (z - tz) ^ 2
            if not bestD or d < bestD then best, bestD = id, d end
        end
    end
    return best
end

function SKT:ResetDummy() self:ResetDummies(true) end

function SKT:ResetDummies(onlyOne)
    if not (GetCurrentZoneHouseId and GetCurrentZoneHouseId() ~= 0) then
        SKT:Print("Target dummies can only be reset in a home.")
        return
    end
    if self.resettingDummies then return end
    local canEdit = HOUSING_EDITOR_STATE and HOUSING_EDITOR_STATE:CanLocalPlayerEditHouse()
    if not canEdit or not GetNextPlacedHousingFurnitureId or not UndoLastHousingEditorCommand then
        -- not your home to edit: the game's reset, for the ones you're fighting
        if HousingEditorRequestResetEngagedTargetDummies then
            HousingEditorRequestResetEngagedTargetDummies()
            if SOUNDS and SOUNDS.HOUSING_EDITOR_CLOSED then PlaySound(SOUNDS.HOUSING_EDITOR_CLOSED) end
        end
        return
    end
    local list = Dummies()
    if #list == 0 then SKT:Print("No target dummies in this home.") return end
    if onlyOne then list = { TargetDummy(list) } end
    self.resettingDummies = true
    -- the editor, to put things away and undo it
    local wasMode = GetHousingEditorMode and GetHousingEditorMode() or HOUSING_EDITOR_MODE_DISABLED
    if wasMode == HOUSING_EDITOR_MODE_DISABLED then
        HousingEditorRequestModeChange(HOUSING_EDITOR_MODE_SELECTION)
    end
    local i, done = 0, 0
    local function Finish()
        if wasMode == HOUSING_EDITOR_MODE_DISABLED then HousingEditorRequestModeChange(HOUSING_EDITOR_MODE_DISABLED) end
        self.resettingDummies = false
        if onlyOne then
            SKT:Print(done == 1 and "Target dummy reset." or "The target dummy couldn't be reset.")
        else
            SKT:Print(string.format("Reset %d target %s.", done, done == 1 and "dummy" or "dummies"))
        end
    end
    local function Next()
        i = i + 1
        local id = list[i]
        if not id then Finish() return end
        local result = HousingEditorRequestRemoveFurniture(id)
        if result ~= HOUSING_REQUEST_RESULT_SUCCESS then
            zo_callLater(Next, STEP_MS)
            return
        end
        -- put back: undo the put-away
        zo_callLater(function()
            if CanUndoLastHousingEditorCommand() then
                UndoLastHousingEditorCommand()
                done = done + 1
            end
            zo_callLater(Next, STEP_MS)
        end, STEP_MS)
    end
    zo_callLater(Next, STEP_MS)
end
