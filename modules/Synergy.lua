--[[-------------------------------------------------------------------------
  SKTools-ESO by Scotskoogen-Chris
  Synergy cooldowns: for tanks, which group member can take which synergy.

  A synergy has a 20 second cooldown for the player who took it, and every
  morph of a skill shares that cooldown (Spear Shards and Necrotic Orb's
  synergies share one too). So the columns are synergy families: taking any
  synergy in a family starts that member's 20 seconds for the whole family.

  Same look as the group buffs: one row per group member (tanks, healers,
  then damage dealers, with role icons), one column per family with its
  icon on top (names in a tooltip; learnt the first time anyone takes one).
  Ready: the cell is green. Just taken: dark, with the skill bars' cooldown
  sweep and the seconds left until it's green again.

  Shown while you're queued as a tank (or always, if you choose). The
  families are a list you edit in the Synergy tab: a name, then the
  synergies in it separated by commas.
---------------------------------------------------------------------------]]

local SKT = SKT
local D   = SKT.Draw
local WM  = WINDOW_MANAGER
local EM  = EVENT_MANAGER
local NS  = "SKToolsESO_Synergy"

local Sy = {}
SKT.Synergy = Sy

local COOLDOWN = 20
local UNKNOWN_ICON = "/esoui/art/icons/icon_missing.dds"
local READY = { 0.48, 0.80, 0.50 }      -- the group buffs' green
local READY_ALPHA = 0.7

-- families: a name and the synergies in it (each shares one cooldown)
local DEFAULT_FAMILIES = {
    { name = "Orbs and Shards", list = "Combustion, Healing Combustion, Blessed Shards, Holy Shards, Spear Shards" },
    { name = "Conduit",         list = "Conduit" },
    { name = "Blood Altar",     list = "Blood Funnel, Blood Feast" },
    { name = "Harvest",         list = "Harvest" },
    { name = "Bone Wall",       list = "Bone Wall, Spinal Surge" },
    { name = "Grave Robber",    list = "Grave Robber, Pure Agony" },
    { name = "Shackle",         list = "Shackle" },
    { name = "Ignite",          list = "Ignite" },
}

-- a usable icon: a texture path, and not the game's "missing" one
local function IsIcon(v)
    return type(v) == "string" and v:find("%.dds$") ~= nil and not v:find("icon_missing")
end

-- the synergies' own ability ids -> the synergy's name (as in the family lists). The 2023 ids from
-- Group Synergy Tracker's comments, and the older ones from AiM's Synergy Tracker.
local SYNERGY_IDS = {
    [85434] = "Combustion",   [63512] = "Combustion",   [48052] = "Blessed Shards", [95926] = "Holy Shards",
    [108799] = "Combustion",  [108802] = "Combustion",  [108821] = "Holy Shards",   [108924] = "Blessed Shards",
    [43769] = "Conduit",      [108607] = "Conduit",
    [85576] = "Harvest",      [108826] = "Harvest",
    [115567] = "Grave Robber", [115571] = "Grave Robber", [118610] = "Pure Agony",
    [39424] = "Bone Wall",    [42196] = "Spinal Surge", [108794] = "Bone Wall",     [108797] = "Spinal Surge",
    [39519] = "Blood Funnel", [41965] = "Blood Feast",  [108782] = "Blood Funnel",  [108787] = "Blood Feast",
    [108805] = "Shackle",     [108807] = "Ignite",
    [22270] = "Purify",       [108824] = "Purify",
    [39451] = "Spawn Broodlings", [41997] = "Black Widows", [42019] = "Arachnophobia",
    [108788] = "Spawn Broodlings", [108791] = "Black Widows", [108792] = "Arachnophobia",
    [108793] = "Radiate",     [108822] = "Supernova",   [108823] = "Gravity Crush",
    [108808] = "Hidden Refresh", [108814] = "Soul Leech", [102321] = "Charged Lightning",
    [88887] = "Icy Escape",
}

local function Key(name) return zo_strlower(zo_strformat("<<1>>", name or "")) end

-- synergy name -> family index; and which families the synergy ids cover
function Sy:Index()
    self.byName = {}
    for i, f in ipairs(self.db.families) do
        for part in string.gmatch(f.list or "", "[^,]+") do
            local k = Key(zo_strtrim(part))
            if k ~= "" then self.byName[k] = i end
        end
    end
    self.idFam = {}
    for _, n in pairs(SYNERGY_IDS) do
        local fam = self.byName[Key(n)]
        if fam then self.idFam[fam] = true end
    end
end

---------------------------------------------------------------------------
-- Who took what
---------------------------------------------------------------------------
Sy.cd = {}       -- member name (lower case) -> { [family] = { start, stop } }

local function MemberKey(name) return Key(name) end

function Sy:OnSynergy(sourceName, abilityName, icon, byId)
    local fam = self.byName and self.byName[Key(abilityName)]
    if not fam then
        -- some effects carry more than the synergy's name ("Spinal Surge Shield"): match the start
        local k = Key(abilityName)
        for name, i in pairs(self.byName or {}) do
            if #name >= 5 and k:sub(1, #name) == name then fam = i; break end
        end
    end
    if not fam then return end
    -- a family the synergy ids cover is counted from those only: by name, your own skills (your seed's
    -- "Harvest" heal) and the effects a synergy leaves behind would start it at the wrong time
    if not byId and self.idFam and self.idFam[fam] then return end
    local who = MemberKey(sourceName)
    if who == "" then return end
    local now = GetFrameTimeSeconds()
    local mine = self.cd[who] or {}
    self.cd[who] = mine
    -- the first hit of a use starts the cooldown; later hits of the same use don't move it
    local c = mine[fam]
    if c and now < c.stop then return end
    mine[fam] = { start = now, stop = now + COOLDOWN }
    local fk = Key(self.db.families[fam].name)
    -- (only when there's still nothing: the source skill's icon, found at load, comes first)
    if IsIcon(icon) and not IsIcon(self.db.icons[fk]) and not self.scanning then self.db.icons[fk] = icon end
    self:Queue()
end

function Sy:Members()
    local tags = {}
    local n = GetGroupSize()
    if SKT:TestSize() > 0 then
        local who = self.db.who
        if who == "me" then
            tags[1] = "player"
        else
            for _, tag in ipairs(SKT:TestTags()) do
                if who == "all" or SKT.TestRole(tag) == LFG_ROLE_TANK then tags[#tags + 1] = tag end
            end
        end
    elseif n and n > 0 then
        for i = 1, n do
            local tag = GetGroupUnitTagByIndex(i)
            if tag and DoesUnitExist(tag) then
                local who = self.db.who
                local keep = (who == "all")
                    or (who == "me" and AreUnitsEqual(tag, "player"))
                    or (who == "tanks" and GetGroupMemberSelectedRole(tag) == LFG_ROLE_TANK)
                if keep then tags[#tags + 1] = tag end
            end
        end
        if #tags == 0 and not self.db.locked then tags[1] = "player" end   -- something to place
    elseif not self.db.locked or self.db.who ~= "tanks" then
        tags[1] = "player"      -- on your own: you
    end
    if #tags > 1 and SKT.Group and SKT.Group.RoleRank then
        local order = {}
        for i, tag in ipairs(tags) do order[tag] = i end
        table.sort(tags, function(a, b)
            local ra, rb = SKT.Group.RoleRank(a), SKT.Group.RoleRank(b)
            if ra ~= rb then return ra < rb end
            return order[a] < order[b]
        end)
    end
    return tags
end


---------------------------------------------------------------------------
-- The grid
---------------------------------------------------------------------------
local function Pool(make, parent) return { list = {}, n = 0, make = make, parent = parent } end
local function Get(pool)
    pool.n = pool.n + 1
    local c = pool.list[pool.n]
    if not c then c = pool.make(pool.parent); pool.list[pool.n] = c end
    c:SetHidden(false)
    return c
end
local function Done(pool)
    for i = pool.n + 1, #pool.list do pool.list[i]:SetHidden(true) end
    pool.n = 0
end

local function MakeCell(parent)
    local f = WM:CreateControl(nil, parent, CT_CONTROL)
    f.bg = D.Tex(f, 1); f.bg:SetAnchorFill(f)
    f.tex = WM:CreateControl(nil, f, CT_TEXTURE)
    f.tex:SetAnchorFill(f)
    f.tex:SetTextureCoords(0.08, 0.92, 0.08, 0.92)
    f.tex:SetDrawLevel(2)
    f.green = D.Tex(f, 2); f.green:SetAnchorFill(f)
    f.cd = WM:CreateControl(nil, f, CT_COOLDOWN)
    f.cd:SetAnchorFill(f)
    f.cd:SetDrawLevel(4)
    f.num = WM:CreateControl(nil, f, CT_LABEL)
    f.num:SetColor(1, 1, 1, 1)
    f.num:SetDrawLevel(6)
    f:SetHandler("OnMouseEnter", function(c)
        if not c.tip then return end
        InitializeTooltip(InformationTooltip, c, BOTTOM, 0, -6, TOP)
        SetTooltipText(InformationTooltip, c.tip)
    end)
    f:SetHandler("OnMouseExit", function() ClearTooltip(InformationTooltip) end)
    return f
end

local function MakeName(parent)
    local f = WM:CreateControl(nil, parent, CT_CONTROL)
    f.bg = D.Tex(f, 1); f.bg:SetAnchorFill(f)
    f.role = WM:CreateControl(nil, f, CT_TEXTURE)
    f.role:SetDrawLevel(3)
    f.text = WM:CreateControl(nil, f, CT_LABEL)
    f.text:SetDrawLevel(3)
    f.text:SetMaxLineCount(1)
    f.text:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    return f
end

function Sy:Build()
    local db = self.db
    local root = WM:CreateTopLevelWindow(NS)
    root:SetClampedToScreen(true)
    root:SetMouseEnabled(false)
    self.root = root
    self.cells = Pool(MakeCell, root)
    self.names = Pool(MakeName, root)
    self.lines = Pool(function(p) return D.Tex(p, 8) end, root)
    self.edges, self.dots = {}, {}
    for i = 1, 6 do self.edges[i] = D.Tex(root, 9) end
    for i = 1, 5 do self.dots[i] = D.Tex(root, 9) end
    self.tag = SKT.Grid.Tag(root, "Synergy cooldowns")

    local drag
    SKT.Grid.Draggable(root, {
        start = function() drag = { x = db.x, y = db.y } end,
        move = function(dx, dy) db.x, db.y = drag.x + dx, drag.y + dy; self:Render() end,
        stop = function()
            local G = SKT.Grid
            db.x, db.y = G.SnapOne(db.x), G.SnapOne(db.y)
            self:Render()
        end,
    })

    self.fragment = ZO_HUDFadeSceneFragment:New(root)
    self.fragment:RegisterCallback("StateChange", function(_, newState)
        if newState == SCENE_FRAGMENT_SHOWN then self:Refresh() end
    end)
end

function Sy:Refresh()
    if not self.root then return end
    self.tags = self:Members()
    self:Render()
end

function Sy:Queue()
    if self.queued then return end
    self.queued = true
    zo_callLater(function() self.queued = false; self:Refresh() end, 100)
end

function Sy:Render()
    local db, G = self.db, SKT.Grid
    local tags = self.tags or {}
    local fams = db.families
    -- shown: always, only in combat, or never (while unlocked always, to place it)
    -- only in a group; always there, or only in combat (as chosen); unlocked always, to place it
    local vis = db.visibility
    local showOk = not db.locked or (IsUnitGrouped("player")
        and (vis == "always" or (vis == "combat" and IsUnitInCombat("player"))))
    -- set to always: shown even with nobody to list (no tank in the group, or not grouped), as the
    -- row of synergy icons, so it's always there
    local empty = #tags == 0 and not (vis == "always" or not db.locked)
    if not db.enabled or not showOk or empty or #fams == 0 then
        self.cells.n, self.names.n, self.lines.n = 0, 0, 0
        Done(self.cells); Done(self.names); Done(self.lines)
        self.root:SetHidden(true)
        return
    end

    local trim = G.Trim()
    local px = D.Px()
    local s = D.OnPx(G.Boxes(db.size))
    local hh = D.OnPx(G.Boxes(db.rowHeight or db.size))   -- the members' rows (the icon row stays square)
    local m = math.min(s, hh)
    local nameW = D.OnPx(G.Boxes(db.nameWidth))
    local cols, rows = #fams, #tags + 1
    local W = nameW + cols * s - trim
    local H = s + #tags * hh - trim
    local bg = SKT.colors.bg
    local fontName = "$(MEDIUM_FONT)|" .. math.max(10, math.floor(m * 0.5)) .. "|soft-shadow-thin"
    local fontNum = "$(BOLD_FONT)|" .. math.max(8, math.floor(m * 0.42)) .. "|thick-outline"
    local numDown = D.OnPx(math.floor(m * 0.42) * 0.14)
    local now = GetFrameTimeSeconds()
    local sk = SKT.Skills and SKT.Skills.db
    local sweepAlpha = ((sk and sk.gcdAlpha) or 62) / 100

    self.cells.n, self.names.n, self.lines.n = 0, 0, 0
    local function Line(x, y, w, h)
        local t = Get(self.lines)
        t:ClearAnchors()
        t:SetAnchor(TOPLEFT, self.root, TOPLEFT, x, y)
        t:SetDimensions(w, h)
        D.Solid(t, 1, 1, 1, 1)
    end

    for r = 1, rows do
        local y = (r == 1) and 0 or (s + (r - 2) * hh)
        local full = (r == 1) and s or hh
        local lastRow = (r == rows)
        local rowH = lastRow and (full - trim) or full
        local tag = tags[r - 1]
        local who

        if tag then
            local nm = Get(self.names)
            nm:ClearAnchors()
            nm:SetAnchor(TOPLEFT, self.root, TOPLEFT, 0, y)
            nm:SetDimensions(nameW, rowH)
            D.Solid(nm.bg, bg[1], bg[2], bg[3], (db.nameAlpha or 30) / 100)
            nm.text:SetFont(fontName)
            local icon = SKT.Group and SKT.Group.RoleIcon and SKT.Group.RoleIcon(tag)
            local ri = D.OnPx(m * 0.8)
            nm.role:ClearAnchors()
            nm.role:SetAnchor(LEFT, nm, LEFT, D.OnPx(3), 0)
            nm.role:SetDimensions(ri, ri)
            nm.role:SetHidden(not icon)
            if icon then nm.role:SetTexture(icon) end
            local textX = icon and (D.OnPx(6) + ri) or D.OnPx(5)
            nm.text:ClearAnchors()
            nm.text:SetAnchor(LEFT, nm, LEFT, textX, 0)
            nm.text:SetWidth(nameW - textX - D.OnPx(3))
            local name = SKT.UnitName(tag)
            nm.text:SetText(name)
            nm.text:SetColor(0.92, 0.92, 0.95, 1)
            who = SKT.IsTestTag(tag) and self:TestCd(tag, #fams) or self.cd[MemberKey(GetUnitName(tag))]
        end

        for c = 1, cols do
            local x = nameW + (c - 1) * s
            local fam = fams[c]
            local f = Get(self.cells)
            f:ClearAnchors()
            f:SetAnchor(TOPLEFT, self.root, TOPLEFT, x, y)
            f:SetDimensions((c == cols) and (s - trim) or s, rowH)
            D.Solid(f.bg, 0, 0, 0, 0.4)
            f.num:SetFont(fontNum)
            f.num:ClearAnchors()
            f.num:SetAnchor(CENTER, f, TOPLEFT, s / 2, full / 2 + numDown)
            f.stop, f.start = nil, nil
            f.cellW = (c == cols) and (s - trim) or s
            f.cd:SetHidden(true)
            f.green:ClearAnchors()
            f.green:SetAnchor(TOPRIGHT, f, TOPRIGHT, 0, 0)
            f.green:SetAnchor(BOTTOMRIGHT, f, BOTTOMRIGHT, 0, 0)
            if not tag then
                -- the top row: each family's icon, its synergies in a tooltip
                local icon = db.icons[Key(fam.name)]
                f.tex:SetTexture(IsIcon(icon) and icon or UNKNOWN_ICON)
                f.tex:SetHidden(false)
                f.green:SetHidden(true)
                f.cd:SetHidden(true)
                f.num:SetText("")
                f.tip = fam.name .. "\n" .. (fam.list or "")
                f:SetMouseEnabled(db.locked)
            else
                f.tip = nil
                f:SetMouseEnabled(false)
                f.tex:SetHidden(true)
                -- as the group buffs: full green when taken, draining from the left (the black is
                -- the time gone, the green what's left), the seconds in the middle; ready is the
                -- plain black cell
                local cdv = who and who[c]
                if cdv and now < cdv.stop then
                    f.stop, f.start = cdv.stop, cdv.start
                    D.Solid(f.green, READY[1], READY[2], READY[3], READY_ALPHA)
                    f.green:SetHidden(false)
                else
                    f.green:SetHidden(true)
                    f.num:SetText("")
                end
            end
            if c < cols then Line(x + s - px, y, px, rowH) end
        end
        if tag then Line(nameW - px, y, px, rowH) end
        if not lastRow then
            if tag then Line(0, y + full - px, W, px) else Line(nameW, y + s - px, W - nameW, px) end
        end
    end
    Done(self.cells); Done(self.names); Done(self.lines)

    self.root:SetDimensions(W, H)
    if not self.iconRing then self.iconRing = D.NewRing(self.root, 9) end
    local ring = self.iconRing
    if #tags == 0 then
        -- nobody listed: just the row of synergy icons, in its own frame
        for _, t in ipairs(self.edges) do t:SetHidden(true) end
        for _, t in ipairs(self.dots) do t:SetHidden(true) end
        D.DrawRing(ring, self.root, nameW, 0, W - nameW, H, D.White)
    else
        for _, t in ipairs(ring.edges) do t:SetHidden(true) end
        for _, t in ipairs(ring.dots) do t:SetHidden(true) end
        if SKT.Group and SKT.Group.Outline then SKT.Group.Outline(self, W, H, nameW, s) end
    end
    self.root:ClearAnchors()
    self.root:SetAnchor(TOPLEFT, GuiRoot, CENTER, D.OnPx(G.SnapOne(db.x)), D.OnPx(G.SnapOne(db.y)))
    self.root:SetMouseEnabled(not db.locked)
    self.tag:SetHidden(db.locked)
    local state = self.fragment:GetState()
    self.root:SetHidden(not (state == SCENE_FRAGMENT_SHOWN or state == SCENE_FRAGMENT_SHOWING))
    self:Tick(now)
end

local function Secs(secs)
    if secs >= 1 then return tostring(math.floor(secs + 0.5)) end
    return string.format("%.1f", secs)
end

-- a test member's cooldowns: each synergy taken every 30 s from its own point, cooling 20 s of them
function Sy:TestCd(tag, n)
    local out, i = {}, SKT.TestIndex(tag) or 1
    local now = GetFrameTimeSeconds()
    for c = 1, n do
        local start = now - ((now + i * 4.3 + c * 2.9) % 30)
        out[c] = { start = start, stop = start + COOLDOWN }
    end
    return out
end

function Sy:Tick(now)
    now = now or GetFrameTimeSeconds()
    local again = false
    for i = 1, #self.cells.list do
        local f = self.cells.list[i]
        if not f:IsHidden() and f.stop then
            local left = f.stop - now
            if left > 0 then
                f.num:SetText(Secs(left))
                local frac = math.max(0, math.min(1, left / math.max(0.1, f.stop - (f.start or f.stop))))
                f.green:SetWidth(math.max(0.01, (f.cellW or 0) * frac))
            else
                again = true   -- one just came off cooldown: ready again
            end
        end
    end
    -- the test group's synergies come round again: redraw once a second
    if not again and SKT:TestSize() > 0 and now >= (self.testNext or 0) then
        self.testNext = now + 1
        again = true
    end
    if again then self:Render() end
end

---------------------------------------------------------------------------
-- Lock, events
---------------------------------------------------------------------------
function Sy:ApplyLock()
    self:Refresh()
    SKT.Grid:Update()
end

function Sy:ApplyEnabled()
    local on = self.db.enabled
    if on and not self.fragmentAdded then
        HUD_SCENE:AddFragment(self.fragment)
        HUD_UI_SCENE:AddFragment(self.fragment)
        self.fragmentAdded = true
    elseif not on and self.fragmentAdded then
        HUD_SCENE:RemoveFragment(self.fragment)
        HUD_UI_SCENE:RemoveFragment(self.fragment)
        self.fragmentAdded = false
    end
    self:Refresh()
end

-- the health check has no icon to learn from: Blood Altar's own, from the skill if this client
-- knows it by that id and name, else the Undaunted skill art
function Sy:AltarIcon()
    if self.altarIcon then return self.altarIcon end
    local icon
    for _, id in ipairs({ 39489, 41967, 41958 }) do   -- Blood Altar, Sanguine Altar, Overflowing Altar
        local ok, name = pcall(GetAbilityName, id)
        if ok and name and zo_strformat("<<1>>", name):find("Altar") then
            icon = GetAbilityIcon(id)
            if icon and icon ~= "" then break end
        end
    end
    self.altarIcon = (icon and icon ~= "") and icon or "/esoui/art/icons/ability_undaunted_001.dds"
    return self.altarIcon
end

-- Each column shows the icon of the skill that makes the synergy, as on the skill bars (the synergy's
-- own name is shared by unrelated abilities, which gave wrong icons). Family name -> that skill and
-- its morphs.
local SOURCE_SKILLS = {
    ["orbs and shards"] = "Necrotic Orb, Energy Orb, Mystic Orb",
    ["conduit"]         = "Lightning Splash, Liquid Lightning, Lightning Flood",
    ["blood altar"]     = "Blood Altar, Sanguine Altar, Overflowing Altar",
    ["harvest"]         = "Healing Seed, Budding Seeds, Corrupting Pollen",
    ["bone wall"]       = "Bone Shield, Spiked Bone Shield, Bone Surge",
    ["grave robber"]    = "Boneyard, Unnerving Boneyard, Avid Boneyard",
    ["shackle"]         = "Dragonknight Standard, Shifting Standard, Standard of Might",
    ["ignite"]          = "Dark Talons, Burning Talons, Choking Talons",
}

-- look through the skill lines (as the skills window shows them), then, for any still without one,
-- through the game's abilities a few thousand a frame; first the skill names, the synergy names last
function Sy:ScanIcons()
    local db = self.db
    local want, fallback, left = {}, {}, 0
    for _, f in ipairs(db.families) do
        local fk = Key(f.name)
        if not IsIcon(db.icons[fk]) then
            local skills = f.skills or SOURCE_SKILLS[fk]
            for part in string.gmatch(skills or "", "[^,]+") do
                local k = Key(zo_strtrim(part))
                if k ~= "" and not want[k] then want[k] = fk; left = left + 1 end
            end
            for part in string.gmatch(f.list or "", "[^,]+") do
                local k = Key(zo_strtrim(part))
                if k ~= "" and not fallback[k] then fallback[k] = fk end
            end
        end
    end
    if next(want) == nil and next(fallback) == nil then return end

    -- 1. the skill lines
    if GetNumSkillTypes then
        for t = 1, GetNumSkillTypes() do
            for l = 1, GetNumSkillLines(t) do
                for a = 1, GetNumSkillAbilities(t, l) do
                    local ok, id = pcall(GetSkillAbilityId, t, l, a, false)
                    if ok and id and id > 0 then
                        local fk = want[Key(GetAbilityName(id))]
                        if fk and not IsIcon(db.icons[fk]) then
                            local icon = GetAbilityIcon(id)
                            if IsIcon(icon) then db.icons[fk] = icon end
                        end
                    end
                end
            end
        end
    end

    -- 2. every ability: the skill names first, then (still nothing) the synergy names
    local function Missing()
        for _, f in ipairs(db.families) do
            if not IsIcon(db.icons[Key(f.name)]) then return true end
        end
        return false
    end
    if not Missing() then self:Render(); return end
    local found2 = {}
    self.scanning = true
    local id, LAST, STEP = 1, 250000, 4000
    EM:RegisterForUpdate(NS .. "Scan", 0, function()
        local stop = math.min(LAST, id + STEP)
        for i = id, stop do
            if DoesAbilityExist(i) then
                local k = Key(GetAbilityName(i))
                local fk = want[k]
                if fk and not IsIcon(db.icons[fk]) then
                    local icon = GetAbilityIcon(i)
                    if IsIcon(icon) then db.icons[fk] = icon end
                end
                local fb = fallback[k]
                if fb and not found2[fb] then
                    local icon = GetAbilityIcon(i)
                    if IsIcon(icon) then found2[fb] = icon end
                end
            end
        end
        id = stop + 1
        if id > LAST then
            EM:UnregisterForUpdate(NS .. "Scan")
            self.scanning = false
            for fk, icon in pairs(found2) do
                if not IsIcon(db.icons[fk]) then db.icons[fk] = icon end
            end
            self:Render()
        end
    end)
end

-- every synergy name the tracker knows (the families' lists and the id table)
function Sy:AllNames()
    local names = {}
    for _, f in ipairs(self.db.families) do
        for part in string.gmatch(f.list or "", "[^,]+") do
            local k = Key(zo_strtrim(part))
            if k ~= "" then names[k] = true end
        end
    end
    for _, n in pairs(SYNERGY_IDS) do names[Key(n)] = true end
    self.allNames = names
    return names
end


function Sy:RegisterEvents()
    -- a synergy taken by a group member (or you): the taker is the source
    -- (the event's "graphic" is a number, not an icon: the icon comes from the ability id)
    -- Unit ids -> names: the synergy events often come without names, only unit ids. Every effect
    -- and combat event on a group member that does carry a name fills this in.
    self.unitNames = self.unitNames or {}
    local function Learn(unitId, name)
        if unitId and unitId ~= 0 and name and name ~= "" then self.unitNames[unitId] = name end
    end
    local function Who(name, unitId, otherId, otherName)
        if name and name ~= "" then return name end
        local n = self.unitNames[unitId]
        if n then return n end
        n = self.unitNames[otherId]
        if n then return n end
        return otherName or ""
    end
    self.Learn = Learn

    -- by name: whoever it lands on took it (your seed healing the tank is the tank's synergy, not yours)
    local function OnCombat(_, result, isError, abilityName, _, _, sourceName, sourceType, targetName, targetType,
                            _, _, _, _, sourceUnitId, targetUnitId, abilityId)
        Learn(sourceUnitId, sourceName); Learn(targetUnitId, targetName)
        if isError or not abilityName or abilityName == "" then return end
        local onGroup = targetType == COMBAT_UNIT_TYPE_PLAYER or targetType == COMBAT_UNIT_TYPE_GROUP
        local taker = onGroup and Who(targetName, targetUnitId) or ""
        if taker == "" then taker = Who(sourceName, sourceUnitId) end
        self:OnSynergy(taker, abilityName, abilityId and GetAbilityIcon(abilityId) or nil)
    end
    for i, unitType in pairs({ COMBAT_UNIT_TYPE_GROUP, COMBAT_UNIT_TYPE_PLAYER }) do
        local id = NS .. "Combat" .. i
        EM:RegisterForEvent(id, EVENT_COMBAT_EVENT, OnCombat)
        EM:AddFilterForEvent(id, EVENT_COMBAT_EVENT, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, unitType)
    end
    -- Group members' synergies, the way other synergy trackers (Group Synergy Tracker, AiM's) do it:
    -- the game does send the synergy's own combat event for group members when listened for by its
    -- ability id, with the taker as the target. Both the current ids and the older ones.
    local function OnSynergyId(_, result, isError, abilityName, _, _, sourceName, sourceType,
                               targetName, targetType, _, _, _, _, sourceUnitId, targetUnitId, abilityId)
        Learn(sourceUnitId, sourceName); Learn(targetUnitId, targetName)
        if isError then return end
        -- only the synergy being gained (later results of the same use, refreshes and fades, don't
        -- start it again)
        if result ~= ACTION_RESULT_EFFECT_GAINED then return end
        -- the taker: the target, by name or (these usually come without names) by unit id
        local taker = Who(targetName, targetUnitId)
        local name = SYNERGY_IDS[abilityId] or abilityName
        if self.debug then
            SKT:Print(zo_strformat("<<1>>: <<2>> (id <<3>>, result <<4>>, unit <<5>>)",
                taker ~= "" and taker or "?", name, abilityId, result, targetUnitId or 0))
        end
        self.idSeen = true
        self:OnSynergy(taker, name, nil, true)
    end
    self.listening = {}
    self.ListenId = function(_, id)
        if self.listening[id] then return end
        self.listening[id] = true
        local reg = NS .. "Id" .. id
        EM:RegisterForEvent(reg, EVENT_COMBAT_EVENT, OnSynergyId)
        EM:AddFilterForEvent(reg, EVENT_COMBAT_EVENT, REGISTER_FILTER_ABILITY_ID, id)
    end
    for id in pairs(SYNERGY_IDS) do self:ListenId(id) end

    -- every combat event on a group member: learns their unit ids; with /sktsynergy on, shows them
    EM:RegisterForEvent(NS .. "Spy", EVENT_COMBAT_EVENT,
        function(_, result, _, abilityName, _, _, sourceName, _, targetName, _, _, _, _, _,
                 sourceUnitId, targetUnitId, abilityId)
            Learn(sourceUnitId, sourceName); Learn(targetUnitId, targetName)   -- always: names for the ids
            if not self.debug or not abilityName or abilityName == "" then return end
            -- everything that names a synergy, and everything else that involves another group
            -- member (once a second per ability, so it doesn't flood)
            local named = self.allNames and self.allNames[Key(abilityName)]
            if not named then
                local now = GetFrameTimeSeconds()
                self.spySeen = self.spySeen or {}
                if (self.spySeen[abilityId] or 0) > now then return end
                self.spySeen[abilityId] = now + 1
            end
            SKT:Print(zo_strformat("[event] <<1>> id <<2>>: <<3>> -> <<4>> (result <<5>>)",
                abilityName, abilityId, sourceName ~= "" and sourceName or "?",
                targetName ~= "" and targetName or "?", result))
        end)
    EM:AddFilterForEvent(NS .. "Spy", EVENT_COMBAT_EVENT, REGISTER_FILTER_TARGET_COMBAT_UNIT_TYPE,
        COMBAT_UNIT_TYPE_GROUP)

    -- ESO only sends combat events where you (or your pet) are the source or target, so a synergy
    -- another group member takes doesn't reach us that way. Effects on group members do: most
    -- synergies leave a buff or heal effect on the taker named as the synergy.
    EM:RegisterForEvent(NS .. "Effect", EVENT_EFFECT_CHANGED,
        function(_, change, _, effectName, unitTag, _, _, _, iconName, _, _, _, _, _, unitId)
            if unitTag then Learn(unitId, GetUnitName(unitTag)) end
            if change ~= EFFECT_RESULT_GAINED or not unitTag then return end
            if AreUnitsEqual(unitTag, "player") and unitTag ~= "player" then return end  -- you: once
            if self.debug then
                SKT:Print(zo_strformat("<<1>>: <<2>>", GetUnitName(unitTag), effectName))
            end
            self:OnSynergy(GetUnitName(unitTag), effectName, iconName)
        end)
    EM:AddFilterForEvent(NS .. "Effect", EVENT_EFFECT_CHANGED, REGISTER_FILTER_UNIT_TAG_PREFIX, "group")
    -- Blood Funnel and Blood Feast are instant heals that leave no effect behind, so neither of the
    -- above sees another member take them. Their health does reach us: the synergy is only offered
    -- below 60 % health and heals 40 % (Funnel) or 65 % (Feast) of it at once. A jump that big from
    -- that low in one update is counted as the Blood Altar synergy.
    -- Updates can split the heal, or land after other damage or healing, so it looks at the lowest
    -- health over the last second and a half rather than only the update before.
    self.healthLog = {}
    EM:RegisterForEvent(NS .. "Health", EVENT_POWER_UPDATE,
        function(_, unitTag, _, powerType, value, max)
            if powerType ~= COMBAT_MECHANIC_FLAGS_HEALTH or not unitTag or not max or max <= 0 then return end
            if self.idSeen or AreUnitsEqual(unitTag, "player") then return end   -- ids work: no guessing
            local name = GetUnitName(unitTag)
            local now = GetFrameTimeSeconds()
            local log = self.healthLog[name] or {}
            self.healthLog[name] = log
            if IsUnitDead(unitTag) or value <= 0 then
                for i = #log, 1, -1 do log[i] = nil end   -- dead: a revive isn't a synergy
                return
            end
            -- drop what's older than 1.5 s, find the lowest
            local low, j = nil, 0
            for i = 1, #log do
                local e = log[i]
                if now - e.t <= 1.5 then
                    j = j + 1; log[j] = e
                    if not low or e.v < low then low = e.v end
                end
            end
            for i = #log, j + 1, -1 do log[i] = nil end
            log[#log + 1] = { t = now, v = value }
            if low and low < 0.65 * max and (value - low) >= 0.30 * max then
                for i = #log, 1, -1 do log[i] = nil end
                if self.debug then SKT:Print(zo_strformat("<<1>>: Blood Altar synergy (health jump)", name)) end
                self:OnSynergy(name, "Blood Funnel", self:AltarIcon())
            end
        end)
    EM:AddFilterForEvent(NS .. "Health", EVENT_POWER_UPDATE, REGISTER_FILTER_UNIT_TAG_PREFIX, "group",
        REGISTER_FILTER_POWER_TYPE, COMBAT_MECHANIC_FLAGS_HEALTH)

    -- /sktsynergy: list the effects group members gain, to find a synergy's name to add to a family
    SLASH_COMMANDS["/sktsynergy"] = function()
        self.debug = not self.debug
        SKT:Print(self.debug and "Synergy test on: group members' effects and events show in chat. /sktsynergy again to stop."
            or "Stopped showing group effects.")
    end

    local function Q() self:Queue() end
    local n = 0
    for _, ev in pairs({ EVENT_GROUP_MEMBER_JOINED, EVENT_GROUP_MEMBER_LEFT, EVENT_GROUP_UPDATE,
                         EVENT_GROUP_MEMBER_ROLE_CHANGED, EVENT_PLAYER_ACTIVATED,
                         EVENT_PLAYER_COMBAT_STATE }) do
        if ev then n = n + 1; EM:RegisterForEvent(NS .. n, ev, Q) end
    end
    EM:RegisterForUpdate(NS .. "Tick", 33, function() self:Tick() end)   -- smooth drain
    EM:RegisterForEvent(NS .. "Scale", EVENT_ALL_GUI_SCREENS_RESIZED, function() self:Render() end)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
SKT:RegisterModule({
    key   = "Synergy",
    title = "Synergy",
    order = 24.5,

    defaults = {
        enabled = true,
        locked  = true,
        who = "tanks",          -- "tanks" (the group's tanks), "me", "all"
        visibility = "always",  -- in a group: "always" or "combat"
        size = 24,
        nameWidth = 120,
        nameAlpha = 30,         -- % opacity of the name cells' background
        x = -640, y = 40,       -- top left, from the middle of the screen
        icons = {},             -- family name (lower case) -> icon, learnt in play
    },

    OnLoad = function(self, db)
        Sy.db = db
        if db.who ~= "tanks" and db.who ~= "me" and db.who ~= "all" then db.who = "tanks" end
        if db.visibility ~= "always" and db.visibility ~= "combat" then
            db.visibility = "always"
        end
        db.tankOnly, db.onlyTanks = nil, nil
        if type(db.families) ~= "table" then
            db.families = {}
            for i, f in ipairs(DEFAULT_FAMILIES) do db.families[i] = { name = f.name, list = f.list } end
        end
        if type(db.icons) ~= "table" then db.icons = {} end
        if (db.iconsVersion or 0) < 2 then db.icons = {}; db.iconsVersion = 2 end    -- the old picks were off
        for k, v in pairs(db.icons) do if not IsIcon(v) then db.icons[k] = nil end end   -- bad ones learnt before
        Sy:Index()
        Sy:Build()
        Sy:RegisterEvents()
        Sy:ApplyEnabled()
        Sy:ScanIcons()
    end,

    BuildTab = function(self, page, db)
        local UI = SKT.UI
        local L = UI.Column(page, 16, 268)
        local R = UI.Column(page, 316, 268)
        local function render() Sy:Refresh() end

        L:Header("Synergy cooldowns")
        L:Check("Enable", function() return db.enabled end, function(v) db.enabled = v; Sy:ApplyEnabled() end)

        L:Header("Show")
        L:ChoiceRow({ { "tanks", "Tanks" }, { "me", "Only me" }, { "all", "Group" } },
            function() return db.who end, function(v) db.who = v; Sy:Refresh() end)

        L:Header("Visibility")
        L:ChoiceRow({ { "always", "Always" }, { "combat", "In combat" } },
            function() return db.visibility end, function(v) db.visibility = v; Sy:Refresh() end)

        L:Header("Size")
        L:Slider("Cell width", 16, 48, 1,
            function() return db.size end, function(v) db.size = v; render() end, SKT.Grid.Fmt)
        L:Slider("Cell height", 8, 48, 1,
            function() return db.rowHeight or db.size end, function(v) db.rowHeight = v; render() end,
            SKT.Grid.Fmt)
        L:Slider("Name width", 48, 240, 8,
            function() return db.nameWidth end, function(v) db.nameWidth = v; render() end, SKT.Grid.Fmt)
        L:Slider("Name background opacity", 0, 100, 5,
            function() return db.nameAlpha or 30 end, function(v) db.nameAlpha = v; render() end,
            function(v) return v .. "%" end)

        -- the families: a name, then its synergies separated by commas
        R:Header("Synergy families")
        local RX, top = R.x, R.y
        local function Edit(name, x, y, w)
            local bd = WM:CreateControlFromVirtual(page:GetName() .. name .. "BG", page, "ZO_EditBackdrop")
            bd:SetAnchor(TOPLEFT, page, TOPLEFT, x, y)
            bd:SetDimensions(w, 28)
            local eb = WM:CreateControlFromVirtual(page:GetName() .. name, bd, "ZO_DefaultEditForBackdrop")
            eb:SetMaxInputChars(200)
            return eb
        end
        local nameBox = Edit("FamName", RX, top, 268)
        nameBox:SetDefaultText("Name, e.g. Orbs and Shards")
        local listBox = Edit("FamList", RX, top + 34, 268)
        listBox:SetDefaultText("Synergies, e.g. Combustion, Holy Shards")

        local rowsUI = {}
        local function Fill()
            for i, r in ipairs(rowsUI) do
                local f = db.families[i]
                r.label:SetText(f and f.name or "")
                r.label:SetHidden(not f)
                r.btn:SetHidden(not f)
                r.up:SetHidden(not f or i == 1)
                r.down:SetHidden(not f or i == #db.families)
                r.tipText = f and f.list or nil
            end
        end
        local function Changed()
            Sy:Index()
            Sy:Refresh()
            Fill()
        end
        local function Add()
            local name = zo_strtrim(nameBox:GetText() or "")
            local list = zo_strtrim(listBox:GetText() or "")
            if name == "" then return end
            if list == "" then list = name end
            if #db.families >= #rowsUI then SKT:Print("The list is full.") return end
            db.families[#db.families + 1] = { name = name, list = list }
            nameBox:SetText(""); listBox:SetText("")
            Changed()
        end
        listBox:SetHandler("OnEnter", Add)
        UI.Button(page, "FamAdd", RX, top + 68, "Add family", 140, Add)

        local function Swap(a, b)
            local f = db.families
            if not f[a] or not f[b] then return end
            f[a], f[b] = f[b], f[a]
            Changed()
        end
        for i = 1, 10 do
            local y = top + 108 + (i - 1) * 32
            local label = SKT.MakeLabel(page:GetName() .. "Fam" .. i, page, "", "ZoFontGame", SKT.colors.text)
            label:SetAnchor(TOPLEFT, page, TOPLEFT, RX, y + 4)
            label:SetDimensions(94, 22)
            label:SetMaxLineCount(1)
            label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
            label:SetMouseEnabled(true)
            local row = { label = label }
            label:SetHandler("OnMouseEnter", function(c)
                if not row.tipText then return end
                InitializeTooltip(InformationTooltip, c, BOTTOM, 0, -6, TOP)
                SetTooltipText(InformationTooltip, row.tipText)
            end)
            label:SetHandler("OnMouseExit", function() ClearTooltip(InformationTooltip) end)
            row.up = UI.Button(page, "FamUp" .. i, RX + 96, y, "Up", 44, function() Swap(i, i - 1) end)
            row.down = UI.Button(page, "FamDown" .. i, RX + 142, y, "Down", 54, function() Swap(i, i + 1) end)
            row.btn = UI.Button(page, "FamDel" .. i, RX + 198, y, "Remove", 70, function()
                table.remove(db.families, i)
                Changed()
            end)
            rowsUI[i] = row
        end
        Fill()
    end,
})
