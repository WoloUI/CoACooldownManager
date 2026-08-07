-- Keybind abbreviation: what fits under a 32px icon.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("Core/Keybinds.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_keybinds")

local A = ns.AbbrevKey

-- Two sources feed this, and they disagree about everything. GetBindingKey
-- returns raw tokens ("SHIFT-BUTTON4"); an action button's own HotKey text is
-- already Blizzard-abbreviated ("s-1") or spelled out in the client's language
-- ("Mouse Button 4"). Both have to come out the same.
check("a bare key is left alone", A("4") == "4")
check("blizzard's shift prefix loses its dash", A("s-1") == "S1")
check("blizzard's ctrl prefix loses its dash", A("c-1") == "C1")
check("blizzard's alt prefix loses its dash", A("a-1") == "A1")
check("a raw shift binding abbreviates", A("SHIFT-1") == "S1")
check("a raw ctrl binding abbreviates", A("CTRL-F") == "CF")
check("a raw alt binding abbreviates", A("ALT-Q") == "AQ")
check("stacked modifiers keep their order", A("CTRL-SHIFT-3") == "CS3")

-- Mouse buttons are the case that started this: "Mouse Button 4" runs off the
-- side of a 32px icon.
check("a spelled-out mouse button shortens", A("Mouse Button 4") == "M4")
check("a raw mouse button shortens", A("BUTTON4") == "M4")
-- Middle click arrives BOTH ways: BUTTON3 from a binding, "Middle Mouse" (with a
-- space) from an action button's own label. The label form matched nothing and
-- printed the whole word across the icon.
check("a raw middle button shortens", A("BUTTON3") == "M3")
check("a spelled-out middle button shortens", A("Middle Mouse") == "M3")
check("a modified middle button keeps both parts", A("SHIFT-BUTTON3") == "SM3")
check("the wheel shortens", A("MOUSEWHEELUP") == "MU")
check("the wheel down shortens", A("MOUSEWHEELDOWN") == "MD")
check("a modified mouse button keeps both parts", A("SHIFT-BUTTON4") == "SM4")

check("numpad keys shorten", A("NUMPAD7") == "N7")
check("numpad symbols shorten", A("NUMPADDIVIDE") == "N/")
check("space is legible", A("SPACE") == "SpB")
check("named keys shorten", A("PAGEDOWN") == "PD")
check("insert shortens", A("INSERT") == "Ins")
check("a modified named key keeps both parts", A("ALT-HOME") == "AHm")

-- Nothing else may leak a dash: a leftover separator is exactly the "s-1" the
-- abbreviation exists to remove.
check("no dash survives", not A("CTRL-ALT-BUTTON5"):find("%-"))
check("nil in, nil out", A(nil) == nil)
check("an empty string stays empty", A("") == "")

--------------------------------------------------------------------------------
-- Which of a spell's buttons gets the glow. ElvUI hides the Blizzard bars but
-- leaves their actions in place, so the same spell answers on both -- and the
-- Blizzard one, scanned first, had the glow drawn on an invisible frame.
local function Btn(name, visible)
  return { GetName = function() return name end, IsVisible = function() return visible end }
end
local hidden, shown = Btn("MultiBarLeftButton1", false), Btn("ElvUI_Bar4Button1", true)
check("the visible button wins, whatever the scan order",
  ns.VisibleButton({ hidden, shown }) == shown)
check("order does not matter", ns.VisibleButton({ shown, hidden }) == shown)
check("one button is that button", ns.VisibleButton({ hidden }) == hidden)
check("nothing visible still answers", ns.VisibleButton({ hidden, hidden }) == hidden)
check("an empty list answers nothing", ns.VisibleButton({}) == nil)
check("no list answers nothing", ns.VisibleButton(nil) == nil)

return T
