-- SavedVariables, per character+spec profiles, shared layouts, migrations.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local DB = {}
ns.DB = DB

local DB_VERSION = 3

--------------------------------------------------------------------------------
-- Defaults
--------------------------------------------------------------------------------
-- Special alerts (out of range, custom warnings): reminder-style, own anchor
local function AlertsViewer()
  return {
    name = "Alerts", style = "reminders", enabled = true,
    anchor = { parent = "FREE", point = "CENTER", relPoint = "CENTER", x = 0, y = 140 },
    iconSize = 28, spacing = 6, fontSize = 15, growth = "CENTER",
    visibility = "always", elements = {},
  }
end

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
    AlertsViewer(),
  }
end

-- Party/raid HoT tracking (see Core/Tracking.lua)
local function DefaultTracking()
  return { enabled = false, indicators = {} }
end

local function DefaultProfile()
  return {
    viewers = DefaultViewers(),
    scanner = { seen = {}, rejected = {} },
    tracking = DefaultTracking(),
  }
end

-- The "out of range" reminder type was replaced by the standalone OUT OF RANGE
-- overlay (db.global.range), so drop leftover rows: without an evaluator they
-- would sit in the element list forever doing nothing. Idempotent, and applied
-- to imported strings too since older exports can still carry them.
function DB.StripRangeReminders(profile)
  local removed = 0
  if type(profile) ~= "table" then return removed end
  for _, viewer in ipairs(profile.viewers or {}) do
    if viewer.style == "reminders" and type(viewer.elements) == "table" then
      for i = #viewer.elements, 1, -1 do
        if viewer.elements[i].rtype == "range" then
          table.remove(viewer.elements, i)
          removed = removed + 1
        end
      end
    end
  end
  return removed
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

  -- v2: add the Alerts viewer to profiles created before it existed
  if db.version < 2 and db.chars then
    for _, char in pairs(db.chars) do
      for _, profile in pairs(char.specs or {}) do
        local found = false
        for _, v in ipairs(profile.viewers or {}) do
          if v.name == "Alerts" then found = true break end
        end
        if profile.viewers and not found then
          table.insert(profile.viewers, AlertsViewer())
        end
      end
    end
  end
  db.global = db.global or {}
  db.global.equivGroups = db.global.equivGroups or {}
  db.global.appearance = db.global.appearance or {} -- font/texture/fontScale
  db.global.profiles = db.global.profiles or {}     -- named profile templates (account-wide library)
  -- Aggro alert overlay (screen-space, shared by every character like the minimap)
  db.global.aggro = db.global.aggro or {
    enabled = true, size = 256, color = { 1, 0.1, 0.1 }, pulse = true,
    sound = nil, x = 0, y = 40,
  }
  -- Out-of-range alert overlay (same deal: screen-space, account-wide).
  -- Sits below screen center so it never lands on top of the aggro arrows.
  db.global.range = db.global.range or {
    enabled = true, text = "OUT OF RANGE", size = 28, color = { 1, 0.35, 0.35 },
    pulse = true, sound = nil, spell = nil, x = 0, y = -80,
  }
  db.chars = db.chars or {}

  -- v3: config becomes per-character. Layouts (positions) move from the
  -- account-global table into each character, and spec assignments stop being
  -- live references: they materialize as independent copies of the template,
  -- so what each character sees today stays identical but no longer bleeds.
  if db.version < 3 then
    local globalLayouts = db.global.layouts
    for _, char in pairs(db.chars) do
      if globalLayouts and not char.layouts then
        char.layouts = ns.CopyTable(globalLayouts)
      end
      char.specs = char.specs or {}
      for specKey, name in pairs(char.assignments or {}) do
        local named = db.global.profiles[name]
        if named then char.specs[specKey] = ns.CopyTable(named) end
      end
    end
    db.global.layouts = nil
  end
  db.version = DB_VERSION

  -- Sweep the retired "out of range" reminder rows out of every stored profile
  for _, char in pairs(db.chars) do
    for _, profile in pairs(char.specs or {}) do DB.StripRangeReminders(profile) end
  end
  for _, template in pairs(db.global.profiles) do DB.StripRangeReminders(template) end

  local char = db.chars[CharKey()] or {}
  db.chars[CharKey()] = char
  char.specs = char.specs or {}
  char.layouts = char.layouts or { default = {} }
  char.activeLayout = char.activeLayout or "default"
  char.lastSpec = char.lastSpec or nil
  char.assignments = char.assignments or {} -- [specKey] = template it was loaded from (label only)

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
  -- Profiles created before the Tracking tab existed
  profile.tracking = profile.tracking or DefaultTracking()
  self.char.lastSpec = specKey
  self.profile = profile
  ns.profile = profile
end

--------------------------------------------------------------------------------
-- Named profiles + spec assignments
--------------------------------------------------------------------------------
function DB:GetNamedProfileNames()
  local names = {}
  for name in pairs(self.db.global.profiles) do names[#names + 1] = name end
  table.sort(names)
  return names
end

-- Snapshots the ACTIVE setup under a name (overwrites an existing name).
function DB:SaveProfileAs(name)
  if not name or name == "" then return nil, "give the profile a name" end
  self.db.global.profiles[name] = ns.CopyTable(self.profile)
  return true
end

-- Creates a fresh named profile with the default bars.
function DB:CreateNamedProfile(name)
  if not name or name == "" then return nil, "give the profile a name" end
  if self.db.global.profiles[name] then return nil, "a profile with that name already exists" end
  self.db.global.profiles[name] = DefaultProfile()
  return true
end

-- Duplicates a saved template into a new one. newName is optional: when nil/empty
-- an unused "<source> (copy)" / "(copy 2)" ... name is generated. An explicit name
-- that already exists is rejected (like CreateNamedProfile). The copy is fully
-- independent; scanner/tracking materialize on assign, same as any template.
function DB:DuplicateNamedProfile(sourceName, newName)
  local source = sourceName and self.db.global.profiles[sourceName]
  if not source then return nil, "select a profile to duplicate" end
  local finalName
  if newName and newName ~= "" then
    if self.db.global.profiles[newName] then
      return nil, "a profile with that name already exists"
    end
    finalName = newName
  else
    finalName = sourceName .. " (copy)"
    local n = 2
    while self.db.global.profiles[finalName] do
      finalName = sourceName .. " (copy " .. n .. ")"
      n = n + 1
    end
  end
  self.db.global.profiles[finalName] = ns.CopyTable(source)
  return true, finalName
end

-- Loads an independent COPY of the named template into the spec: later edits
-- stay on this character (templates never change under you). nil only clears
-- the "loaded from" label and keeps the spec's bars as they are.
function DB:AssignProfile(specKey, profileName)
  self.char.assignments[specKey] = profileName
  if profileName then
    local named = self.db.global.profiles[profileName]
    if not named then return end
    local copy = ns.CopyTable(named)
    copy.scanner = copy.scanner or { seen = {}, rejected = {} }
    copy.tracking = copy.tracking or DefaultTracking()
    self.char.specs[specKey] = copy
    if specKey == self:GetSpecKey() then
      self:ActivateProfile()
      ns:Fire("PROFILE_CHANGED")
    end
  end
end

-- Deletes the template only; character copies loaded from it are untouched.
function DB:DeleteNamedProfile(name)
  self.db.global.profiles[name] = nil
  for specKey, assigned in pairs(self.char.assignments) do
    if assigned == name then self.char.assignments[specKey] = nil end
  end
end

-- All specs of this character: { { key = "spec1", name = "..." }, ... }
function DB:GetSpecs()
  local specs = {}
  if SpecializationUtil and SpecializationUtil.GetNumSpecializations then
    local ok, count = pcall(SpecializationUtil.GetNumSpecializations)
    if ok and count and count > 0 then
      for i = 1, count do
        local ok2, name = pcall(SpecializationUtil.GetSpecializationInfo, i)
        specs[#specs + 1] = { key = "spec" .. i, name = ok2 and name and tostring(name) or ("Spec " .. i) }
      end
      return specs
    end
  end
  return {
    { key = "talents1", name = "Primary talents" },
    { key = "talents2", name = "Secondary talents" },
  }
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
    viewer.stack = { spellID = nil, maxStacks = 3, onlyMine = true, unit = "player", showCount = true }
  elseif style == "shield" then
    -- Curved absorb column per tracked shield buff
    viewer.shield = { segments = 14, segW = 24, segH = 7, gap = 2, curve = 12,
      showValue = true, color = { 1, 0.72, 0.2 } }
    viewer.spacing = 10
  elseif style == "swing" then
    -- Main-hand/off-hand/ranged swing timers (event-driven, no elements)
    viewer.swing = { width = 200, height = 16, showLabel = true, showTime = true,
      show_mh = true, show_oh = true, show_ranged = true }
    viewer.growth = "UP"
  elseif style == "cast" then
    -- Player cast bar with channel ticks (event-driven, no elements)
    viewer.cast = { width = 220, height = 22, showIcon = true, showTime = true,
      showTicks = true, tickSeconds = 1.0 }
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
-- Layout (positions/anchors, per CHARACTER, shared across its specs/profiles)
--------------------------------------------------------------------------------
function DB:GetLayout()
  local layouts = self.char.layouts
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

-- ExtraActionBar mover positions live in the active layout under a reserved key
-- (cannot collide with a viewer name, and export/import only touch viewer keys).
-- Shape: { bar = {x,y} or nil, buttons = { [frameName] = {x,y} } }.
function DB:GetExtraAction()
  local layout = self:GetLayout()
  local ea = layout.__extraAction or {}
  ea.buttons = ea.buttons or {}
  layout.__extraAction = ea
  return ea
end

function DB:SetExtraBarPos(x, y)
  self:GetExtraAction().bar = { x = x, y = y }
end

function DB:SetExtraButtonPos(name, x, y)
  self:GetExtraAction().buttons[name] = { x = x, y = y }
end

function DB:ResetExtraAction()
  self:GetLayout().__extraAction = nil
end

--------------------------------------------------------------------------------
-- Profile import/export (share strings with other players)
-- Own token serializer + base64: imported data is PARSED, never executed.
--------------------------------------------------------------------------------
local SEP = "\1"

local function SerializeValue(v, out)
  local t = type(v)
  if t == "table" then
    out[#out + 1] = "T"
    for key, val in pairs(v) do
      SerializeValue(key, out)
      SerializeValue(val, out)
    end
    out[#out + 1] = "t"
  elseif t == "number" then
    out[#out + 1] = "N" .. tostring(v)
  elseif t == "boolean" then
    out[#out + 1] = v and "B1" or "B0"
  elseif t == "string" then
    out[#out + 1] = "S" .. v:gsub(SEP, "")
  end
end

local function Serialize(tbl)
  local out = {}
  SerializeValue(tbl, out)
  return table.concat(out, SEP)
end

local function ParseTokens(tokens, i)
  local tok = tokens[i]
  if not tok then return nil, i + 1 end
  local tag, rest = tok:sub(1, 1), tok:sub(2)
  if tag == "T" then
    local tbl = {}
    i = i + 1
    while tokens[i] and tokens[i] ~= "t" do
      local key, value
      key, i = ParseTokens(tokens, i)
      value, i = ParseTokens(tokens, i)
      if key ~= nil then tbl[key] = value end
    end
    return tbl, i + 1
  elseif tag == "N" then
    return tonumber(rest), i + 1
  elseif tag == "B" then
    return rest == "1", i + 1
  elseif tag == "S" then
    return rest, i + 1
  end
  return nil, i + 1
end

local function Deserialize(text)
  local tokens = {}
  for token in (text .. SEP):gmatch("(.-)" .. SEP) do
    tokens[#tokens + 1] = token
  end
  local value = ParseTokens(tokens, 1)
  return value
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function B64Encode(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64
    out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
      .. (b and B64:sub(c3 + 1, c3 + 1) or "=")
      .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
  end
  return table.concat(out)
end

local B64_REV
local function B64Decode(data)
  if not B64_REV then
    B64_REV = {}
    for i = 1, 64 do B64_REV[B64:byte(i)] = i - 1 end
  end
  data = data:gsub("[^%w%+/=]", "")
  local out = {}
  for i = 1, #data, 4 do
    local c1, c2, c3, c4 = data:byte(i, i + 3)
    local n1, n2 = B64_REV[c1], B64_REV[c2]
    if not n1 or not n2 then return nil end
    local n3 = c3 and c3 ~= 61 and B64_REV[c3] or nil -- 61 = '='
    local n4 = c4 and c4 ~= 61 and B64_REV[c4] or nil
    local n = n1 * 262144 + n2 * 4096 + (n3 or 0) * 64 + (n4 or 0)
    out[#out + 1] = string.char(math.floor(n / 65536) % 256)
    if n3 then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
    if n4 then out[#out + 1] = string.char(n % 256) end
  end
  return table.concat(out)
end

local PREFIX = "!CDM1!"

function DB:ExportProfile()
  local payload = {
    v = 1,
    spec = self:GetSpecName(),
    profile = self.profile,
    layout = {},
    groups = {},
  }
  local layout = self:GetLayout()
  local allGroups = ns.GetEquivGroups()
  for _, viewer in ipairs(self.profile.viewers) do
    if layout[viewer.name] then
      payload.layout[viewer.name] = layout[viewer.name]
    end
    if viewer.style == "reminders" then
      for _, reminder in ipairs(viewer.elements) do
        if reminder.rtype == "group" and reminder.group and allGroups[reminder.group] then
          payload.groups[reminder.group] = allGroups[reminder.group]
        end
      end
    end
  end
  return PREFIX .. B64Encode(Serialize(payload))
end

function DB:ImportProfile(text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local body = text:match("^!CDM1!(.+)$")
  if not body then return nil, "that is not a CoACDM profile string" end
  local decoded = B64Decode(body)
  if not decoded then return nil, "the string is damaged (bad encoding)" end
  local ok, data = pcall(Deserialize, decoded)
  if not ok or type(data) ~= "table" or type(data.profile) ~= "table"
    or type(data.profile.viewers) ~= "table" or #data.profile.viewers == 0 then
    return nil, "the string does not contain a valid profile"
  end

  data.profile.scanner = data.profile.scanner or { seen = {}, rejected = {} }
  data.profile.tracking = data.profile.tracking or DefaultTracking()
  DB.StripRangeReminders(data.profile) -- older exports may still carry them
  -- Import replaces the spec's profile: the "loaded from" label no longer applies
  self.char.assignments[self:GetSpecKey()] = nil
  self.char.specs[self:GetSpecKey()] = data.profile
  self.profile = data.profile
  ns.profile = data.profile

  local layout = self:GetLayout()
  for name, anchor in pairs(data.layout or {}) do
    layout[name] = anchor
  end
  for key, group in pairs(data.groups or {}) do
    if not self.db.global.equivGroups[key] then
      self.db.global.equivGroups[key] = group
    end
  end

  ns:Fire("PROFILE_CHANGED")
  return data.spec or "profile"
end

-- Test seams
DB._Serialize = Serialize
DB._Deserialize = Deserialize
DB._B64Encode = B64Encode
DB._B64Decode = B64Decode

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
