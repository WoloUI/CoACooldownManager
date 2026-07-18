-- Scan suggestions window: accept / reject / recategorize found spells.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Suggestions = {}
ns.Suggestions = Suggestions

local W
local win
local currentResults = {}

local CATEGORY_OPTIONS = {
  { text = "Essential", value = "essential" },
  { text = "Defensives", value = "defensives" },
  { text = "Utility", value = "utility" },
}

local ROW_HEIGHT = 26
local MAX_VISIBLE = 12

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
    local pendingLeft = false
    for _, item in ipairs(currentResults) do
      if not item.done then pendingLeft = true break end
    end
    if pendingLeft then
      ns.Scanner:Dismiss(currentResults)
    end
  end)
  return win
end

local function CreateRow(parent, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(ROW_HEIGHT)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(20, 20)
  row.icon:SetPoint("LEFT", 0, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  row.name = W.CreateLabel(row, "", 12)
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetWidth(170)

  row.cd = W.CreateLabel(row, "", 11, W.colors.inkDim)
  row.cd:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
  row.cd:SetWidth(44)

  row.category = W.CreateDropdown(row, 96, function(_, value)
    row.item.category = value
  end)
  row.category:SetPoint("LEFT", row.cd, "RIGHT", 4, 0)
  row.category:SetOptions(CATEGORY_OPTIONS)

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
  w.info:SetText("Found " .. #results .. " spell(s) for your bars. Adjust the category and add what you want:")

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
    row.category:SetValue(item.category)
    row:Show()
  end
  for i = #results + 1, #w.rows do
    w.rows[i]:Hide()
  end
  if #results > MAX_VISIBLE then
    w.info:SetText(w.info:GetText() .. "  |cff9aa3b5(showing " .. MAX_VISIBLE .. ")|r")
  end

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
