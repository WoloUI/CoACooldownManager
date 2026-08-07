-- Cell packing for the config form grid. The old grid pinned labels and controls
-- to fixed columns, so a long label reached the control beside it; cells pack
-- against the live content width instead, which is also what lets a resized
-- window use its extra space.
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

print("test_formlayout")

local P = ns.PackCells

-- Three dropdowns fit one row at the default content width (110*3 + 12*2 = 354)
local r = P(528, { 110, 110, 110 }, 12)
check("three cells fit one row at 528", #r == 3
  and r[1].row == 1 and r[2].row == 1 and r[3].row == 1)
check("the first cell starts at zero", r[1].x == 0)
check("the second clears the first plus the gap", r[2].x == 122)
check("the third follows on", r[3].x == 244)

-- The same three in a narrow pane: two, then one
r = P(240, { 110, 110, 110 }, 12)
check("a narrow pane wraps to two rows", r[3].row == 2)
check("the wrapped cell restarts at zero", r[3].x == 0)
check("the first row still holds two", r[1].row == 1 and r[2].row == 1)

-- A cell wider than the pane still lands somewhere sane
r = P(100, { 300 }, 12)
check("an oversized cell still gets row 1", #r == 1 and r[1].row == 1)
check("an oversized cell starts at zero", r[1].x == 0)

-- Rows are contiguous from 1 and never skip
r = P(240, { 110, 110, 110, 110, 110 }, 12)
local rows, contiguous = {}, true
for _, cell in ipairs(r) do rows[cell.row] = true end
for i = 1, 3 do if not rows[i] then contiguous = false end end
check("rows are contiguous from 1", contiguous)
check("five cells at 240 need three rows", r[5].row == 3)

-- No cell is ever positioned past the pane, at any width
local overflowed = nil
for width = 300, 1200, 20 do
  local packed = P(width, { 110, 44, 44, 110, 66, 128 }, 12)
  for _, cell in ipairs(packed) do
    if cell.x < 0 or cell.x > width then overflowed = width end
  end
end
check("no cell is positioned past the pane", overflowed == nil)

-- A wider pane packs more per row: the whole point of the resizable window
local narrow = P(400, { 110, 110, 110, 110 }, 12)
local wide = P(1000, { 110, 110, 110, 110 }, 12)
check("a wider pane uses fewer rows", wide[4].row < narrow[4].row)

-- Gap affects packing. 231 rather than 232: two 110s with a 12 gap need exactly
-- 232, so at 232 both gaps fit and the case proves nothing.
check("a zero gap packs tighter",
  P(231, { 110, 110 }, 0)[2].row == 1 and P(231, { 110, 110 }, 12)[2].row == 2)
check("a row that fits exactly does not wrap", P(232, { 110, 110 }, 12)[2].row == 1)

-- A cell narrower than the control it holds does not clip: it parks the NEXT
-- cell on top of it. The Display dropdown was 150px wide in a 118px cell and ran
-- into "On unit", so FormCells clamps the width up to the real control.
local function FakeControl(width)
  local x
  return {
    GetWidth = function() return width end,
    ClearAllPoints = function() end,
    SetPoint = function(_, _, px) x = px end,
    Show = function() end,
    X = function() return x end,
  }
end
local wide, next_ = FakeControl(150), FakeControl(90)
ns.FormCells(0, {
  { control = wide, width = 118 },
  { control = next_, width = 108 },
}, 528)
check("an oversized control pushes the next cell clear of it",
  next_.X() >= 150 + 12)

-- Degenerate input
check("no widths returns an empty table", #P(528, {}, 12) == 0)
check("no widths returns a table, not nil", type(P(528, {}, 12)) == "table")

return T
