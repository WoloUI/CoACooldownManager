-- Config widget behaviour: the edit-box commit guard must not swallow a real
-- edit just because the same string was committed earlier on another bar.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("UI/Config/Widgets.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_widgets")

local W = ns.Widgets
local parent = stub.MakeFrame()

local committed = {}
local box = W.CreateEditBox(parent, 44, 20, function(_, text)
  committed[#committed + 1] = text
end, "32")

-- Enter commits exactly once: the handler clears focus, which fires
-- OnEditFocusLost and would otherwise commit the same text a second time.
box:SetFocus()
box:SetText("40")
box:Fire("OnEnterPressed")
check("Enter commits once", #committed == 1 and committed[1] == "40")

-- Render() repaints the shared box with another bar's value, then the user
-- types the same number they typed on the previous bar. This is the reported
-- bug: the stale guard used to drop it and the value snapped back.
box:SetText("32")
box:SetFocus()
box:SetText("40")
box:Fire("OnEnterPressed")
check("same value on another bar still commits",
  #committed == 2 and committed[2] == "40")

-- Click-away (no Enter) commits too.
box:SetFocus()
box:SetText("18")
box:ClearFocus()
check("focus loss commits", #committed == 3 and committed[3] == "18")

-- Focusing and leaving without typing commits nothing.
box:SetFocus()
box:ClearFocus()
check("untouched box commits nothing", #committed == 3)

return T
