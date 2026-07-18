-- SavedVariables, per character+spec profiles, shared layouts, migrations.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local DB = {}
ns.DB = DB

local DB_VERSION = 1

--------------------------------------------------------------------------------
-- Defaults
--------------------------------------------------------------------------------
local function DefaultViewers()
  return {
    {
      name = "Power", style = "power", enabled = true,
      anchor = { parent = "FREE", point = "CENTER", relPoint = "CENTER", x = 0, y = -220 },
      power = {
        bar1 = "auto", bar2 = "auto", -- "auto" | "none" | powerType number
        width = 340, height = 26, subHeight = 18, fontSize = 12,
        showTicks = true, showCombo = true,
      },
      visibility = "always", elements = {},
    },
    {
      name = "Essential", style = "icons", enabled = true,
      anchor = { parent = "Power", point = "BOTTOM", relPoint = "TOP", x = 0, y = 6 },
      iconSize = 40, spacing = 5, fontSize = 13, growth = "CENTER",
      visibility = "always", elements = {},
    },
    {
      name = "Defensives", style = "icons", enabled = true,
      anchor = { parent = "Power", point = "TOP", relPoint = "BOTTOM", x = 0, y = -8 },
      iconSize = 32, spacing = 5, fontSize = 11, growth = "CENTER",
      visibility = "always", elements = {},
    },
    {
      name = "Utility", style = "icons", enabled = true,
      anchor = { parent = "Defensives", point = "TOP", relPoint = "BOTTOM", x = 0, y = -6 },
      iconSize = 32, spacing = 5, fontSize = 11, growth = "CENTER",
      visibility = "always", elements = {},
    },
    {
      name = "Buffs", style = "bars", enabled = true,
      anchor = { parent = "Power", point = "BOTTOM", relPoint = "TOP", x = 0, y = 58 },
      barWidth = 250, barHeight = 20, spacing = 3, fontSize = 11, growth = "UP",
      visibility = "always", elements = {},
    },
    {
      name = "Target DoTs", style = "bars", enabled = true,
      anchor = { parent = "Power", point = "BOTTOM", relPoint = "TOP", x = 0, y = 110 },
      barWidth = 210, barHeight = 18, spacing = 3, fontSize = 11, growth = "UP",
      visibility = "target", elements = {},
    },
    {
      name = "Reminders", style = "reminders", enabled = true,
      anchor = { parent = "Power", point = "BOTTOM", relPoint = "TOP", x = 0, y = 160 },
      iconSize = 24, spacing = 6, fontSize = 12, growth = "CENTER",
      visibility = "always", elements = {},
    },
  }
end

local function DefaultProfile()
  return {
    viewers = DefaultViewers(),
    scanner = { seen = {}, rejected = {} },
  }
end

--------------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------------
local function CharKey()
  return UnitName("player") .. "-" .. GetRealmName()
end

function DB:GetSpecKey()
  if SpecializationUtil and SpecializationUtil.GetActiveSpecialization then
    local ok, spec = pcall(SpecializationUtil.GetActiveSpecialization)
    if ok and spec then return "spec" .. tostring(spec) end
  end
  if GetActiveTalentGroup then
    local ok, group = pcall(GetActiveTalentGroup)
    if ok and group then return "talents" .. tostring(group) end
  end
  return "spec1"
end

function DB:GetSpecName()
  if SpecializationUtil and SpecializationUtil.GetActiveSpecialization
    and SpecializationUtil.GetSpecializationInfo then
    local ok, spec = pcall(SpecializationUtil.GetActiveSpecialization)
    if ok and spec then
      local ok2, name = pcall(SpecializationUtil.GetSpecializationInfo, spec)
      if ok2 and name then return tostring(name) end
    end
  end
  return self:GetSpecKey()
end

--------------------------------------------------------------------------------
-- Init / profile activation
--------------------------------------------------------------------------------
function DB:Init()
  if type(CoACDM_DB) ~= "table" then
    CoACDM_DB = nil
  end
  local ok = pcall(function()
    CoACDM_DB = CoACDM_DB or {}
    assert(CoACDM_DB.version == nil or type(CoACDM_DB.version) == "number")
  end)
  if not ok then
    CoACDM_DB_backup = CoACDM_DB
    CoACDM_DB = {}
    ns:Print("saved settings were corrupt; a backup was kept in CoACDM_DB_backup and defaults restored.")
  end

  local db = CoACDM_DB
  db.version = db.version or DB_VERSION
  db.global = db.global or {}
  db.global.layouts = db.global.layouts or { default = {} }
  db.global.equivGroups = db.global.equivGroups or {}
  db.global.appearance = db.global.appearance or {} -- font/texture/fontScale
  db.chars = db.chars or {}

  local char = db.chars[CharKey()] or {}
  db.chars[CharKey()] = char
  char.specs = char.specs or {}
  char.activeLayout = char.activeLayout or "default"
  char.lastSpec = char.lastSpec or nil

  self.db = db
  self.char = char
  self:ActivateProfile()

  ns:RegisterEvent("ASCENSION_CA_SPECIALIZATION_ACTIVE_ID_CHANGED", function()
    DB:OnSpecChanged()
  end)
  ns:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", function()
    DB:OnSpecChanged()
  end)
end

function DB:ActivateProfile()
  local specKey = self:GetSpecKey()
  local profile = self.char.specs[specKey]
  if not profile then
    -- New spec: start from the previously active profile when there is one,
    -- so bars carry over and only spells need adjusting.
    local last = self.char.lastSpec and self.char.specs[self.char.lastSpec]
    profile = last and ns.CopyTable(last) or DefaultProfile()
    profile.scanner = profile.scanner or { seen = {}, rejected = {} }
    self.char.specs[specKey] = profile
  end
  self.char.lastSpec = specKey
  self.profile = profile
  ns.profile = profile
end

function DB:OnSpecChanged()
  local before = self.profile
  self:ActivateProfile()
  if self.profile ~= before then
    ns:Fire("PROFILE_CHANGED")
    ns:Print("profile switched to " .. self:GetSpecName() .. ".")
  end
end

function DB:ResetProfile()
  self.char.specs[self:GetSpecKey()] = DefaultProfile()
  self:ActivateProfile()
  ns:Fire("PROFILE_CHANGED")
  ns:Print("profile reset to defaults.")
end

--------------------------------------------------------------------------------
-- Viewers
--------------------------------------------------------------------------------
function DB:GetViewer(name)
  for _, v in ipairs(self.profile.viewers) do
    if v.name == name then return v end
  end
end

function DB:AddViewer(name, style)
  if self:GetViewer(name) then return nil, "a bar with that name already exists" end
  local viewer = {
    name = name, style = style or "icons", enabled = true,
    anchor = { parent = "Power", point = "BOTTOM", relPoint = "TOP", x = 0, y = 200 },
    iconSize = style == "stacks" and 16 or 32,
    spacing = style == "stacks" and 4 or 5,
    fontSize = 11, growth = "CENTER",
    barWidth = 250, barHeight = 20,
    visibility = "always", elements = {},
  }
  if style == "stacks" then
    -- CoA pseudo-resource: an aura whose stacks render as filled segments
    viewer.stack = { spellID = nil, maxStacks = 3, onlyMine = true, unit = "player", showCount = false }
  end
  table.insert(self.profile.viewers, viewer)
  ns:Fire("VIEWERS_CHANGED")
  return viewer
end

function DB:DeleteViewer(name)
  if name == "Power" then return end -- root anchor is not deletable
  for i, v in ipairs(self.profile.viewers) do
    if v.name == name then
      table.remove(self.profile.viewers, i)
      -- Re-parent children of the removed viewer to the root
      for _, other in ipairs(self.profile.viewers) do
        if other.anchor.parent == name then other.anchor.parent = "Power" end
      end
      local layout = self:GetLayout()
      layout[name] = nil
      ns:Fire("VIEWERS_CHANGED")
      return true
    end
  end
end

--------------------------------------------------------------------------------
-- Layout (positions/anchors, shared across profiles by default)
--------------------------------------------------------------------------------
function DB:GetLayout()
  local layouts = self.db.global.layouts
  local name = self.char.activeLayout
  layouts[name] = layouts[name] or {}
  return layouts[name]
end

-- Effective anchor = layout override or the viewer's own default.
function DB:GetAnchor(viewer)
  local layout = self:GetLayout()
  return layout[viewer.name] or viewer.anchor
end

function DB:SetAnchor(viewer, anchor)
  local layout = self:GetLayout()
  layout[viewer.name] = anchor
end

-- True when setting `parentName` as parent of `childName` would create a cycle.
function DB:WouldCycle(childName, parentName)
  local seen = { [childName] = true }
  local current = parentName
  while current and current ~= "FREE" do
    if seen[current] then return true end
    seen[current] = true
    local v = self:GetViewer(current)
    if not v then return false end
    current = self:GetAnchor(v).parent
  end
  return false
end
