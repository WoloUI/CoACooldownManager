-- Config panel layout arithmetic. Frame geometry is not modelled by the stub, so
-- the numbers that decide the sidebar scroll region live in pure functions.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("UI/Config/Panel.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_panelayout")

local MIN_H, MAX_H = 420, 1000

-- The window can never be shrunk into a broken layout
local min = ns.SidebarMetrics(MIN_H, false)
check("minimum height leaves a positive list", min.listHeight > 0)
check("minimum height fits at least one bar", min.visibleRows >= 1)

-- Taller window, more bars
local tall = ns.SidebarMetrics(MAX_H, false)
check("a taller window fits more bars", tall.visibleRows > min.visibleRows)
check("a taller window has a taller list", tall.listHeight > min.listHeight)

-- Today's size still behaves sensibly
local now = ns.SidebarMetrics(560, false)
check("560px fits more rows than the minimum", now.visibleRows > min.visibleRows)
check("560px fits fewer rows than the maximum", now.visibleRows < tall.visibleRows)

-- The create block eats exactly its own height out of the list
local collapsed = ns.SidebarMetrics(560, false)
local expanded = ns.SidebarMetrics(560, true)
check("expanding the create block shrinks the list by its height",
  collapsed.listHeight - expanded.listHeight == expanded.createBlockHeight)
check("the collapsed block reports no create height", collapsed.createBlockHeight == 0)
check("the expanded block reports a positive create height", expanded.createBlockHeight > 0)

-- The list never reaches the pinned block, at any height, in either state
local overlapped = nil
for h = MIN_H, MAX_H, 20 do
  for _, creating in ipairs({ false, true }) do
    local m = ns.SidebarMetrics(h, creating)
    -- listTop is negative from the sidebar top; the list bottom measured the same
    -- way must stay above the top of "+ New bar...", which newBarY measures from
    -- the sidebar BOTTOM. Convert both to distance-from-bottom.
    local listBottomFromBottom = h + m.listTop - m.listHeight
    if m.listHeight <= 0 or listBottomFromBottom < m.newBarY then
      overlapped = h .. (creating and " creating" or "")
    end
  end
end
check("the list never overlaps the pinned block", overlapped == nil)

-- Content width tracks the window and is unchanged at the old size
-- 760 - SIDEBAR_W(190) - PAD(12) - 30 = 528, today's value at the 780 window
check("content width at 780 matches the shipped layout", ns.ContentWidth(780) == 528)
check("content width grows with the window", ns.ContentWidth(1000) > ns.ContentWidth(780))
check("content width never goes negative", ns.ContentWidth(0) >= 0)

return T
