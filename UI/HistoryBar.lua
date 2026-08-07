-- History style: a row of icons for what was just cast, newest first.
--
-- Not built on UI/IconRow.lua on purpose: that module renders a CONFIGURED
-- element list through Triggers.Evaluate, which is the opposite of this bar's
-- input. Sharing it would mean threading a second, unrelated data source through
-- every branch of it.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local HistoryBar = {}
ns.HistoryBar = HistoryBar

local COLOR_FAILED = { 0.85, 0.25, 0.25 }

local function CreateIcon(parent)
  local btn = CreateFrame("Frame", nil, parent)

  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetAllPoints()
  ns.CropIcon(btn.icon)

  btn.border = btn:CreateTexture(nil, "OVERLAY")
  btn.border:SetPoint("TOPLEFT", -1, 1)
  btn.border:SetPoint("BOTTOMRIGHT", 1, -1)
  btn.border:SetTexture("Interface\\Buttons\\WHITE8X8")
  btn.border:SetDrawLayer("BACKGROUND", -1)

  btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
  btn.cooldown:SetAllPoints()
  btn.cooldown:SetReverse(false)

  local overlay = CreateFrame("Frame", nil, btn)
  overlay:SetAllPoints()
  overlay:SetFrameLevel(btn.cooldown:GetFrameLevel() + 1)
  btn.countText = overlay:CreateFontString(nil, "OVERLAY")
  btn.countText:SetPoint("BOTTOMRIGHT", -1, 1)
  btn.countText:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
  btn.countText:SetTextColor(1, 1, 1)

  return btn
end

local function AcquireIcon(frame, index)
  frame.historyIcons = frame.historyIcons or {}
  local btn = frame.historyIcons[index]
  if not btn then
    btn = CreateIcon(frame)
    frame.historyIcons[index] = btn
    -- Masque, keeping OUR border: it turns red for a failed cast, which is the
    -- whole point of this bar
    if ns.MasqueSkin then
      ns.MasqueSkin(frame, btn,
        { Icon = btn.icon, Cooldown = btn.cooldown, Count = btn.countText }, true)
    end
  end
  return btn
end

function HistoryBar:Build(frame, cfg)
  frame.historyIcons = frame.historyIcons or {}
  for _, btn in ipairs(frame.historyIcons) do btn:Hide() end
  if ns.MasqueReSkin then ns.MasqueReSkin(frame) end
end

-- The blacklist is stored as typed text; Entries wants an array of names.
local function BlacklistNames(text)
  if type(text) ~= "string" or text == "" then return nil end
  local names = {}
  for line in text:gmatch("[^\r\n]+") do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" then names[#names + 1] = trimmed end
  end
  return #names > 0 and names or nil
end

function HistoryBar:Update(frame, cfg)
  local h = cfg.history or {}
  local size = h.iconSize or 32
  local spacing = h.spacing or 4
  local visible = h.visible or 10
  local now = GetTime()

  local entries
  if ns.TestMode and ns.TestMode.active then
    -- Something to position against while dragging the bar in edit mode
    entries = {}
    for i = 1, math.min(visible, 4) do
      entries[i] = { name = "Sample " .. i, count = i == 2 and 3 or 1,
        icon = "Interface\\Icons\\Spell_Fire_FlameBolt",
        at = now - i, failed = i == 4 }
    end
  else
    entries = ns.CastLog:Entries({
      max = visible, fade = h.fade or 8,
      blacklist = BlacklistNames(h.blacklist), now = now,
    })
  end

  local current = ns.CastBar and ns.CastBar:Current()
  local font = ns.GetFont()

  for i, entry in ipairs(entries) do
    local btn = AcquireIcon(frame, i)
    btn:SetSize(size, size)
    btn.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    btn.countText:SetFont(font, ns.FontSize(math.max(size / 3, 8)), "OUTLINE")
    btn.countText:SetText(entry.count > 1 and entry.count or "")

    if entry.failed then
      btn.icon:SetVertexColor(COLOR_FAILED[1], COLOR_FAILED[2], COLOR_FAILED[3])
      btn.border:SetVertexColor(COLOR_FAILED[1], COLOR_FAILED[2], COLOR_FAILED[3], 0.9)
    else
      btn.icon:SetVertexColor(1, 1, 1)
      btn.border:SetVertexColor(0, 0, 0, 0.9)
    end

    -- Sweep on the newest icon only, and only while that spell is the one
    -- actually in progress
    if i == 1 and current and current.active and current.name == entry.name
      and current.duration and current.duration > 0 then
      btn.cooldown:SetCooldown(current.start, current.duration)
      btn.cooldown:Show()
    else
      btn.cooldown:Hide()
    end

    if h.tooltips ~= false then
      btn:EnableMouse(true)
      btn.tooltipName = entry.name
      btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipName or "")
        GameTooltip:Show()
      end)
      btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
      btn:EnableMouse(false)
      btn:SetScript("OnEnter", nil)
      btn:SetScript("OnLeave", nil)
    end

    btn:Show()
  end

  for i = #entries + 1, #(frame.historyIcons or {}) do
    frame.historyIcons[i]:Hide()
  end

  -- Layout. Entry 1 is the newest, and "growth" says which way older ones go.
  local count = #entries
  local total = count > 0 and (count * size + (count - 1) * spacing) or size
  frame:SetSize(total, size)
  local growth = h.growth or "LEFT"
  for i = 1, count do
    local btn = frame.historyIcons[i]
    btn:ClearAllPoints()
    local offset = (i - 1) * (size + spacing)
    if growth == "RIGHT" then
      -- Newest on the left, history extending right
      btn:SetPoint("LEFT", frame, "LEFT", offset, 0)
    else
      -- Newest on the right, history extending left (GCDhistory's default)
      btn:SetPoint("RIGHT", frame, "RIGHT", -offset, 0)
    end
  end
end
