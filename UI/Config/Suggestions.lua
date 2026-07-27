-- Scan suggestions window: accept / reject / recategorize found spells.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Suggestions = {}
ns.Suggestions = Suggestions

local W
local win
local currentResults = {}

-- The dropdown targets the user's own bars, resolved at SHOW time: it used to
-- be a fixed essential/defensives/utility list, so custom bars could never be
-- picked. The classification still chooses the default row by row.
local CATEGORY_VIEWER = {
  essential = "Essential",
  defensives = "Defensives",
  utility = "Utility",
}

local ROW_HEIGHT = 26
local MAX_VISIBLE = 14
local HEADER_H = 82 -- title + search row + info line

-- Pending suggestions matching the search box, in display order. `done` items
-- (added or dismissed) drop out so the list closes up as you work through it.
local function Filtered()
  local needle = (win and win.search and win.search:GetText() or ""):lower()
  local list = {}
  for _, item in ipairs(currentResults) do
    if not item.done
      and (needle == "" or item.name:lower():find(needle, 1, true)) then
      list[#list + 1] = item
    end
  end
  return list
end

local function EnsureWindow()
  if win then return win end
  W = ns.Widgets
  win = W.CreateWindow("CoACDMSuggestions", 480, 200, "CoACDM - Suggested spells")

  -- Name filter. Re-renders per keystroke via OnTextChanged, so the commit
  -- semantics of CreateEditBox (Enter / focus loss) don't matter here.
  win.search = W.CreateEditBox(win, 180, 20, nil, "Search")
  win.search:SetPoint("TOPLEFT", 12, -36)
  win.search:HookScript("OnTextChanged", function()
    win.offset = 0
    Suggestions:Render()
  end)

  win.info = W.CreateLabel(win, "", 11, W.colors.inkDim)
  win.info:SetPoint("TOPLEFT", 200, -41)
  -- Bounded and wrapping: the old single-line sentence ran off the frame
  win.info:SetWidth(268)
  win.info:SetJustifyH("LEFT")

  win.rows = {}
  win.offset = 0

  -- Wheel paging, the same idiom the long LibSharedMedia dropdowns use, so no
  -- ScrollFrame/scrollbar template is needed.
  win:EnableMouseWheel(true)
  win:SetScript("OnMouseWheel", function(self, delta)
    local total = #Filtered()
    local maxOffset = math.max(0, total - MAX_VISIBLE)
    local newOffset = math.min(maxOffset, math.max(0, (self.offset or 0) - delta))
    if newOffset ~= self.offset then
      self.offset = newOffset
      Suggestions:Render()
    end
  end)

  -- "Add all" adds what the search currently matches, not the whole scan:
  -- with a filter typed in, adding the other 40 hidden rows would be a trap.
  win.addAll = W.CreateButton(win, "Add all", 90, 22, function()
    local list = Filtered()
    for _, item in ipairs(list) do ns.Scanner:Accept(item) end
    for _, item in ipairs(list) do item.done = true end
    ns:Print(#list .. " suggestion(s) added.")
    if #Filtered() == 0 then win:Hide() else Suggestions:Render() end
  end)

  win.dismiss = W.CreateButton(win, "Not now", 90, 22, function()
    win:Hide()
  end)

  -- Closing without deciding remembers the batch as seen so it doesn't nag on
  -- login. Scroll and search reach every row now, so there is no hidden
  -- overflow being buried unseen.
  win:SetScript("OnHide", function()
    local pending = {}
    for _, item in ipairs(currentResults) do
      if not item.done then pending[#pending + 1] = item end
    end
    if #pending > 0 then ns.Scanner:Dismiss(pending) end
  end)
  return win
end

local function CreateRow(parent, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(ROW_HEIGHT)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(20, 20)
  row.icon:SetPoint("LEFT", 0, 0)
  ns.CropIcon(row.icon)

  row.name = W.CreateLabel(row, "", 12)
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetWidth(170)

  row.cd = W.CreateLabel(row, "", 11, W.colors.inkDim)
  row.cd:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
  row.cd:SetWidth(44)

  -- Resolved at CLICK time: rows are pooled and re-bound to another item on
  -- every render, so capturing row.item here would write to the wrong spell.
  row.category = W.CreateDropdown(row, 110, function(_, value)
    row.item.target = value
  end)
  row.category:SetPoint("LEFT", row.cd, "RIGHT", 4, 0)

  -- Both re-render instead of just hiding the row: the list closes up, so a
  -- scrolled/filtered view never leaves a gap where the handled spell was.
  row.accept = W.CreateButton(row, "Add", 44, 20, function()
    ns.Scanner:Accept(row.item)
    row.item.done = true
    Suggestions:Render()
  end)
  row.accept:SetPoint("LEFT", row.category, "RIGHT", 6, 0)

  row.reject = W.CreateButton(row, "X", 20, 20, function()
    ns.Scanner:Reject(row.item)
    row.item.done = true
    Suggestions:Render()
  end)
  row.reject:SetPoint("LEFT", row.accept, "RIGHT", 4, 0)

  return row
end

-- Repaints the visible window of the filtered list. Safe to call from the
-- search box, the wheel handler and the per-row buttons.
function Suggestions:Render()
  local w = win
  if not w then return end
  local list = Filtered()
  local pending = #list

  -- Clamp: removing rows can leave the offset past the end of a shorter list
  local maxOffset = math.max(0, pending - MAX_VISIBLE)
  w.offset = math.min(math.max(w.offset or 0, 0), maxOffset)

  local count = math.min(pending, MAX_VISIBLE)
  w:SetHeight(HEADER_H + math.max(count, 1) * ROW_HEIGHT + 36)

  local searching = (w.search:GetText() or "") ~= ""
  if pending == 0 then
    w.info:SetText(searching and "No pending spell matches that name."
      or "Nothing left to review.")
  elseif pending > MAX_VISIBLE then
    w.info:SetText(("%d pending%s - showing %d-%d. Mouse wheel to scroll."):format(
      pending, searching and " (filtered)" or "",
      w.offset + 1, w.offset + count))
  else
    w.info:SetText(("%d pending%s. Pick a bar and add what you want."):format(
      pending, searching and " (filtered)" or ""))
  end

  local targets = ns.CaptureTargetOptions()
  for slot = 1, count do
    local item = list[w.offset + slot]
    local row = w.rows[slot]
    if not row then
      row = CreateRow(w, slot)
      w.rows[slot] = row
    end
    row.item = item
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", w, "TOPLEFT", 12, -HEADER_H + 26 - (slot - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", w, "RIGHT", -12, 0)
    row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.name:SetText(item.name)
    row.cd:SetText(item.cooldown > 0 and ns.FormatTime(item.cooldown) or "")
    row.category:SetOptions(targets)
    -- Default to the bar the classification suggests, but only if it still
    -- exists and can take spells; otherwise fall back to the first real bar.
    -- The old fixed dropdown could show "Defensives" with no such bar, and
    -- Accept then silently did nothing.
    item.target = item.target or CATEGORY_VIEWER[item.category]
    local valid = false
    for _, option in ipairs(targets) do
      if option.value == item.target then valid = true break end
    end
    if not valid then item.target = targets[1] and targets[1].value end
    row.category:SetValue(item.target)
    row:Show()
  end
  for slot = count + 1, #w.rows do
    w.rows[slot]:Hide()
  end
end

function Suggestions:Show(results)
  currentResults = results
  local w = EnsureWindow()
  w.search:SetText("")
  w.offset = 0
  self:Render()

  w.addAll:ClearAllPoints()
  w.addAll:SetPoint("BOTTOMRIGHT", -12, 10)
  w.dismiss:ClearAllPoints()
  w.dismiss:SetPoint("RIGHT", w.addAll, "LEFT", -6, 0)
  w:Show()
end

ns:On("READY", function()
  ns:On("SCAN_RESULTS", function(results)
    Suggestions:Show(results)
  end)
end)

-- Test seams
Suggestions._MAX_VISIBLE = MAX_VISIBLE
Suggestions._Filtered = Filtered
function Suggestions:_Window() return win end
