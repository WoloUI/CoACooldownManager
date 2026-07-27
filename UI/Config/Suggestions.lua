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
local MAX_VISIBLE = 18

local function EnsureWindow()
  if win then return win end
  W = ns.Widgets
  win = W.CreateWindow("CoACDMSuggestions", 480, 200, "CoACDM - Suggested spells")

  win.info = W.CreateLabel(win, "", 12, W.colors.inkDim)
  win.info:SetPoint("TOPLEFT", 12, -38)

  win.rows = {}

  win.addAll = W.CreateButton(win, "Add all", 90, 22, function()
    for _, item in ipairs(currentResults) do
      if not item.done then ns.Scanner:Accept(item) end
    end
    win:Hide()
    ns:Print(#currentResults .. " suggestion(s) processed.")
  end)

  win.dismiss = W.CreateButton(win, "Not now", 90, 22, function()
    win:Hide()
  end)

  win:SetScript("OnHide", function()
    local shown = {}
    for i = 1, math.min(win.shownCount or 0, #currentResults) do
      if not currentResults[i].done then shown[#shown + 1] = currentResults[i] end
    end
    if #shown > 0 then ns.Scanner:Dismiss(shown) end
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

  row.accept = W.CreateButton(row, "Add", 44, 20, function()
    ns.Scanner:Accept(row.item)
    row.item.done = true
    row:Hide()
  end)
  row.accept:SetPoint("LEFT", row.category, "RIGHT", 6, 0)

  row.reject = W.CreateButton(row, "X", 20, 20, function()
    ns.Scanner:Reject(row.item)
    row.item.done = true
    row:Hide()
  end)
  row.reject:SetPoint("LEFT", row.accept, "RIGHT", 4, 0)

  return row
end

function Suggestions:Show(results)
  currentResults = results
  local w = EnsureWindow()

  local count = math.min(#results, MAX_VISIBLE)
  w:SetHeight(70 + count * ROW_HEIGHT + 36)
  if #results > MAX_VISIBLE then
    w.info:SetText(("Found %d spell(s), showing the first %d. Add or dismiss these, then run /cdm scan again for the rest:")
      :format(#results, MAX_VISIBLE))
  else
    w.info:SetText("Found " .. #results .. " spell(s) for your bars. Pick a bar and add what you want:")
  end

  local targets = ns.CaptureTargetOptions()
  for i, item in ipairs(results) do
    if i > MAX_VISIBLE then break end
    local row = w.rows[i]
    if not row then
      row = CreateRow(w, i)
      w.rows[i] = row
    end
    row.item = item
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", w, "TOPLEFT", 12, -56 - (i - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", w, "RIGHT", -12, 0)
    row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.name:SetText(item.name)
    row.cd:SetText(item.cooldown > 0 and ns.FormatTime(item.cooldown) or "")
    row.category:SetOptions(targets)
    -- Default to the bar the classification suggests, but only if it still
    -- exists and can take spells; otherwise fall back to the first real bar.
    item.target = item.target or CATEGORY_VIEWER[item.category]
    local valid = false
    for _, option in ipairs(targets) do
      if option.value == item.target then valid = true break end
    end
    if not valid then item.target = targets[1] and targets[1].value end
    row.category:SetValue(item.target)
    row:Show()
  end
  for i = count + 1, #w.rows do
    w.rows[i]:Hide()
  end
  -- Only what was actually on screen counts as shown: the overflow must not be
  -- marked seen, or suggestions the user never laid eyes on get buried.
  w.shownCount = count

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
