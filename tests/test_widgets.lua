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

--------------------------------------------------------------------------------
-- Section headers cost the same vertical space regardless of title length: a
-- long section name must not shift the rows beneath it.
--------------------------------------------------------------------------------
local shortHead = W.CreateSectionHeader(stub.MakeFrame(), "LOOK")
local longHead = W.CreateSectionHeader(stub.MakeFrame(),
  "TRACKED RESOURCE (aura stacks)")
check("a section header reports a cost", type(shortHead.COST) == "number" and shortHead.COST > 0)
check("cost is independent of title length", shortHead.COST == longHead.COST)
check("a header reports its leading space", shortHead.LEAD > 0)
check("lead is part of the cost", shortHead.COST > shortHead.LEAD)
check("a header can be relabelled", (function()
  longHead:SetLabel("LOOK")
  return true
end)())

--------------------------------------------------------------------------------
-- Scale clamping, shared by the config window and the global bar scale
--------------------------------------------------------------------------------
check("an absent scale is 100%", ns.ClampScale(nil) == 1)
check("a plain scale passes through", ns.ClampScale(1.25) == 1.25)
-- A scale of 0 makes every bar vanish with nothing left to grab in edit mode,
-- and the config window with it -- the floor is not decoration.
check("zero is clamped to the floor", ns.ClampScale(0) == 0.4)
check("a negative scale is clamped to the floor", ns.ClampScale(-3) == 0.4)
check("an absurd scale is clamped to the ceiling", ns.ClampScale(99) == 3)
check("garbage reads as 100%", ns.ClampScale("wide") == 1)
check("scale rounds to whole percent", ns.ClampScale(1.23456) == 1.23)

return T
