-- Suggestions window: name filter, wheel scrolling, and the bar dropdown.
-- The list is longer than the window, so the offset/clamp arithmetic is the
-- part that breaks silently.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("UI/Config/Widgets.lua", ns)
stub.loadAddonFile("UI/Config/Suggestions.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_suggestions")

ns.profile = {
  viewers = {
    { name = "Essential", style = "icons", elements = {} },
    { name = "My Cooldowns", style = "icons", elements = {} },
    { name = "Power", style = "power", elements = {} },
  },
}
local accepted, rejected, dismissed = {}, {}, 0
ns.Scanner = {
  Accept = function(_, item) accepted[#accepted + 1] = item.name end,
  Reject = function(_, item) rejected[#rejected + 1] = item.name end,
  Dismiss = function(_, list) dismissed = #list end,
}

local results = {}
for i = 1, 20 do
  results[i] = { spellID = i, name = ("Spell %02d"):format(i), icon = "x",
    category = "essential", cooldown = 30 }
end
results[3].name = "Inferno Barrier"
results[7].name = "Inferno Blast"

local S = ns.Suggestions
S:Show(results)
local win = S:_Window()
local MAX = S._MAX_VISIBLE

check("window caps the visible rows", #win.rows == MAX)
check("starts at the top", win.offset == 0)
check("first row is the first result", win.rows[1].item.name == results[1].name)
check("last visible row honours the offset", win.rows[MAX].item.name == results[MAX].name)

-- Wheel: negative delta scrolls down, and the offset stops at the end.
win:Fire("OnMouseWheel", -1)
check("wheel down advances the offset", win.offset == 1)
check("rows follow the offset", win.rows[1].item.name == results[2].name)
win:Fire("OnMouseWheel", 1)
check("wheel up goes back", win.offset == 0)
win:Fire("OnMouseWheel", 1)
check("cannot scroll above the top", win.offset == 0)
for _ = 1, 50 do win:Fire("OnMouseWheel", -1) end
check("cannot scroll past the end", win.offset == 20 - MAX)

-- Search filters by name, case-insensitively, and resets the scroll.
win.search:SetText("inferno")
check("search resets the offset", win.offset == 0)
check("search filters to matches", win.rows[1].item.name == "Inferno Barrier"
  and win.rows[2].item.name == "Inferno Blast")
check("non-matching rows are hidden", not win.rows[3]:IsShown())

win.search:SetText("BARRIER")
check("search is case-insensitive", win.rows[1].item.name == "Inferno Barrier")

win.search:SetText("nothing matches this")
check("an empty result set does not error", win.offset == 0)

win.search:SetText("")
check("clearing the search restores every row", win.rows[1].item.name == results[1].name)

-- Handling a row closes the list up rather than leaving a gap.
win.rows[1].accept:Fire("OnClick")
check("accept forwards to the scanner", accepted[1] == results[1].name)
check("accepted row leaves the list", win.rows[1].item.name == results[2].name)
win.rows[1].reject:Fire("OnClick")
check("reject forwards to the scanner", rejected[1] == results[2].name)
check("rejected row leaves the list", win.rows[1].item.name == results[3].name)

-- The bar dropdown offers the user's own bars, and a category with no matching
-- bar falls back instead of silently targeting a bar that does not exist.
check("dropdown lists capturable bars only",
  #win.rows[1].category.options == 2
  and win.rows[1].category.options[2].value == "My Cooldowns")
check("a missing category bar falls back to a real one",
  win.rows[1].item.target == "Essential")

-- "Add all" only takes what the filter currently shows.
win.search:SetText("Spell 1")
local before = #accepted
local shown = 0
for _, row in ipairs(win.rows) do
  if row:IsShown() then shown = shown + 1 end
end
win.addAll:Fire("OnClick")
check("add all adds only the filtered rows", #accepted - before == shown and shown > 0)
win.search:SetText("")
check("add all leaves unmatched spells pending", #S._Filtered() > 0)

return T
