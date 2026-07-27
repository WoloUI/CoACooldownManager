-- Slash argument parsing and spell capture from the cursor.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_capture")

local cmd, rest = ns.ParseSlash("scan debug")
check("splits command and argument", cmd == "scan" and rest == "debug")
cmd, rest = ns.ParseSlash("  Scan   DEBUG  ")
check("lowercases and trims", cmd == "scan" and rest == "debug")
cmd, rest = ns.ParseSlash("edit")
check("bare command has an empty argument", cmd == "edit" and rest == "")
cmd, rest = ns.ParseSlash(nil)
check("nil message is empty", cmd == "" and rest == "")

-- Cursor resolution. This client returns "spell", spellbookIndex, bookType --
-- there is no 4th spellID return, which is what broke drag & drop.
_G.__spellbookEntries = {
  { id = 1003, name = "Inferno Barrier", rank = "Rank 3" },
}
_G.__spells = { [1003] = { name = "Inferno Barrier", rank = "Rank 3", icon = "icon1" } }

_G.GetCursorInfo = function() return "spell", 1, "spell" end
local id, name, icon = ns.CursorSpell()
check("resolves a 3-value spell cursor", id == 1003 and name == "Inferno Barrier")
check("resolves the icon", icon == "icon1")

_G.GetCursorInfo = function() return "item", 1, "item" end
check("ignores a non-spell cursor", ns.CursorSpell() == nil)

_G.GetCursorInfo = function() return nil end
check("ignores an empty cursor", ns.CursorSpell() == nil)

-- Element construction, shared by all three capture paths.
check("icons bar accepts captures", ns.CanCapture({ style = "icons" }) == true)
check("bars accepts captures", ns.CanCapture({ style = "bars" }) == true)
check("shield accepts captures", ns.CanCapture({ style = "shield" }) == true)
check("power bar rejects captures", ns.CanCapture({ style = "power" }) == false)
check("nil viewer rejects captures", ns.CanCapture(nil) == false)

local icons = { name = "Essential", style = "icons", elements = {} }
check("adds to an icon bar", ns.AddCapturedSpell(icons, 1003, "Inferno Barrier", "icon1") == true)
check("stores the name and id", icons.elements[1].name == "Inferno Barrier"
  and icons.elements[1].spellID == 1003)
check("icon bars capture cooldowns", icons.elements[1].kind == "cooldown"
  and icons.elements[1].unit == "player"
  and icons.elements[1].showWhen == "always")

local added, reason = ns.AddCapturedSpell(icons, 1003, "Inferno Barrier", "icon1")
check("refuses a duplicate", added == false and reason == "already")

local buffs = { name = "Buffs", style = "bars", elements = {} }
ns.AddCapturedSpell(buffs, 1003, "Inferno Barrier", "icon1")
check("buff bars capture present-only buffs", buffs.elements[1].kind == "buff"
  and buffs.elements[1].unit == "player"
  and buffs.elements[1].showWhen == "present")

local dots = { name = "Target DoTs", style = "bars", elements = {} }
ns.AddCapturedSpell(dots, 1003, "Inferno Barrier", "icon1")
check("Target DoTs capture target debuffs", dots.elements[1].kind == "debuff"
  and dots.elements[1].unit == "target"
  and dots.elements[1].showWhen == "always")

check("a power bar cannot be captured onto",
  ns.AddCapturedSpell({ name = "Power", style = "power", elements = {} }, 1003, "X") == false)
check("a nameless spell cannot be captured", ns.AddCapturedSpell(icons, nil, nil) == false)

-- An explicit kind hint. The scanner already knows whether a spell is a DoT or
-- a self buff, so it says so instead of leaving AddCapturedSpell to guess from
-- the bar's NAME -- a duration bar the user called anything other than
-- "Target DoTs" used to turn a DoT into a buff on the player.
local myDots = { name = "Mis DoTs", style = "bars", elements = {} }
ns.AddCapturedSpell(myDots, 1003, "Inferno Barrier", "icon1", "dots")
check("a dots hint makes a target debuff on any bar name",
  myDots.elements[1].kind == "debuff"
  and myDots.elements[1].unit == "target"
  and myDots.elements[1].showWhen == "always")

local myBuffs = { name = "Whatever", style = "bars", elements = {} }
ns.AddCapturedSpell(myBuffs, 1003, "Inferno Barrier", "icon1", "buffs")
check("a buffs hint makes a self buff",
  myBuffs.elements[1].kind == "buff"
  and myBuffs.elements[1].unit == "player"
  and myBuffs.elements[1].showWhen == "present")

-- The hint never overrides the bar's own nature: an icon row is a cooldown row.
local iconRow = { name = "Essential", style = "icons", elements = {} }
ns.AddCapturedSpell(iconRow, 1003, "Inferno Barrier", "icon1", "dots")
check("an icon bar stays a cooldown even with a dots hint",
  iconRow.elements[1].kind == "cooldown" and iconRow.elements[1].unit == "player")

-- Without a hint the old name-based default still applies, so drag and
-- shift+click keep behaving exactly as before.
local named = { name = "Target DoTs", style = "bars", elements = {} }
ns.AddCapturedSpell(named, 1003, "Inferno Barrier", "icon1")
check("no hint falls back to the bar name", named.elements[1].kind == "debuff"
  and named.elements[1].unit == "target")

return T
