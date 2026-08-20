-- The config panel rendered end to end, once per style and once per view.
--
-- `Config:Render` is one long function driving a y cursor through a branch per
-- style, and the branches share controls and helpers by name. The suite could not
-- see any of it: deleting a helper that three branches still called, or renaming a
-- control key, produced a panel that loads fine and errors the moment you open
-- that tab. Geometry is still not modelled -- what this pins is that every branch
-- RUNS, for every style, with an element selected and without.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
for _, file in ipairs({
  "Core/Init.lua", "Core/DB.lua", "Data/EquivGroups.lua", "Data/SpellHints.lua",
  "Core/Power.lua", "Core/Cooldowns.lua", "Core/CastLog.lua", "Core/Keybinds.lua",
  "Core/Auras.lua", "Core/Triggers.lua", "Core/Reminders.lua", "Core/Tracking.lua",
  "Core/Scanner.lua", "UI/Viewer.lua", "UI/Glow.lua", "UI/IconRow.lua",
  "UI/StatusBars.lua", "UI/ActivityBars.lua", "UI/HistoryBar.lua", "UI/PowerBar.lua",
  "UI/StackBar.lua", "UI/ReminderRow.lua", "UI/EditMode.lua", "UI/ExtraActionBar.lua",
  "UI/Config/Widgets.lua", "UI/Config/TriggerBuilder.lua", "UI/Config/Suggestions.lua",
  "UI/Config/Panel.lua",
}) do
  stub.loadAddonFile(file, ns)
end

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_panelrender")

_G.CoACDM_DB = nil
ns.DB:Init()

local Config = ns.Config
local ok, err = pcall(function() Config:Toggle() end)
check("the panel opens", ok)
if not ok then
  print("  " .. tostring(err))
  return T
end

-- Selecting a bar goes through its sidebar button, the same path a click takes,
-- so the test cannot drift from how selection actually works.
local win = _G.CoACDMConfig
-- Clicking re-renders, so a broken branch throws from inside the click rather
-- than from the explicit Render that follows. Both go through pcall or one bad
-- branch takes the whole file down instead of failing a single check.
local function Click(btn, label)
  local fine, e = pcall(function() btn:Fire("OnClick") end)
  if not fine then print("  " .. label .. ": " .. tostring(e)) end
  return fine
end

local function SelectBar(name)
  for _, btn in ipairs(win.sidebar.buttons) do
    if btn.viewerName == name and btn._shown then
      return Click(btn, "select " .. name)
    end
  end
  return false
end

local function RenderOK(label)
  local fine, e = pcall(function() Config:Render() end)
  if not fine then print("  " .. label .. ": " .. tostring(e)) end
  return fine
end

-- One bar per style. A fresh profile already ships some of them, and those are
-- preferred: a shipped bar carries the per-style config table its branch reads.
local STYLES = {
  "icons", "bars", "power", "stacks", "shield", "swing", "cast", "history",
  "reminders",
}
local made = {}
for _, style in ipairs(STYLES) do
  for _, v in ipairs(ns.profile.viewers) do
    if v.style == style and not made[style] then made[style] = v.name end
  end
  if not made[style] then
    local name = "T_" .. style
    if ns.DB:AddViewer(name, style) then made[style] = name end
  end
end
Config:Render()

for _, style in ipairs(STYLES) do
  local name = made[style]
  if name and SelectBar(name) then
    check("renders the " .. style .. " tab", RenderOK(style))
  else
    check("renders the " .. style .. " tab", false)
  end
end

-- With an element on the bar: the element list and the Add row are a separate
-- path through the same branch. Selecting one (which opens the trigger builder
-- beneath it) is driven by a click on a pooled row, and the row pool is a local
-- in Panel.lua -- so that one sub-path stays an in-game check.
for _, style in ipairs({ "icons", "bars", "shield" }) do
  local name = made[style]
  local viewer
  for _, v in ipairs(ns.profile.viewers) do if v.name == name then viewer = v end end
  if viewer then
    viewer.elements = { { kind = "cooldown", name = "Fireball" } }
    SelectBar(name)
    check("renders " .. style .. " with an element", RenderOK(style .. "+el"))
  else
    check("renders " .. style .. " with an element", false)
  end
end

-- The trigger builder, per element kind. Selecting a row is what opens it in the
-- panel and the row pool is a Panel.lua local, but Load is the public entry that
-- selection calls, so the builder's own branches are reachable from here.
for _, kind in ipairs({ "cooldown", "buff", "debuff", "trinket", "item", "totem" }) do
  local el = { kind = kind, name = "Fireball", conditions = {} }
  if kind == "trinket" then el.slot = 13 end
  local fine, e = pcall(function() ns.TriggerBuilder:Load(el, function() end) end)
  if not fine then print("  trigger " .. kind .. ": " .. tostring(e)) end
  check("the trigger builder renders for " .. kind, fine)
end

-- On an icon bar the builder grows a border cell, plus an Auto button ONLY when
-- the element carries its own colour (both paths differ in cell count)
for _, override in ipairs({ true, false }) do
  check("the trigger builder renders the border cell, override=" .. tostring(override),
    (function()
      local el = { kind = "cooldown", name = "Fireball", conditions = {},
        borderColor = override and { 1, 0, 0 } or nil,
        borderSize = override and 3 or nil,
        iconSize = override and 48 or nil }
      local fine, e = pcall(function()
        ns.TriggerBuilder:Load(el, function() end, "icons")
      end)
      if not fine then print("  trigger border: " .. tostring(e)) end
      return fine
    end)())
end

-- Conditions bucketed across two actions: one group header per action, each with
-- its own join, and a sound on the glow group.
check("the trigger builder renders grouped conditions", (function()
  local el = { kind = "buff", name = "Fireball", conditions = {
    { ctype = "remaining", op = "<", value = 3, action = "glow" },
    { ctype = "combat", action = "glow" },
    { ctype = "otheraura", action = "show", spell = "Bloodlust" },
  }, condGroups = { glow = { join = "all", sound = "none" } } }
  local fine, e = pcall(function() ns.TriggerBuilder:Load(el, function() end) end)
  if not fine then print("  trigger groups: " .. tostring(e)) end
  return fine
end)())

-- Every non-bar view
for _, entry in ipairs({
  { "generalBtn", "Appearance" },
  { "groupsBtn", "Buff Tracking" },
  { "profilesBtn", "Profiles" },
  { "trackingBtn", "Tracking" },
  { "hudBtn", "Class HUD" },
}) do
  check("renders the " .. entry[2] .. " view",
    Click(win[entry[1]], entry[2]) and RenderOK(entry[2]))
end

-- The bar list and the create block, at both states of the sidebar
check("renders with the create block open", (function()
  local fine = Click(win.newBar, "creating") and RenderOK("creating")
  Click(win.newBar, "creating off")
  return fine
end)())

return T
