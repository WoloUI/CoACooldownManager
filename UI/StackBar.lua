-- Stack-points style: renders an aura's stack count as filled segments,
-- for CoA pseudo-resources (e.g. Reaper's 3-stack spender buff). Behaves
-- like a secondary resource bar and anchors like any other viewer.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local StackBar = {}
ns.StackBar = StackBar

local DEFAULT_COLOR = { 0.88, 0.64, 0.29 }
local EMPTY_COLOR = { 0.12, 0.09, 0.05, 0.85 }

local function AcquireSegments(frame, count)
  frame.segments = frame.segments or {}
  for i = #frame.segments + 1, count do
    local seg = frame:CreateTexture(nil, "ARTWORK")
    seg:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.segments[i] = seg

    local border = frame:CreateTexture(nil, "BACKGROUND")
    border:SetTexture("Interface\\Buttons\\WHITE8X8")
    border:SetVertexColor(0, 0, 0, 0.9)
    frame.segments[i].border = border
  end
  return frame.segments
end

function StackBar:Build(frame, cfg)
  cfg.stack = cfg.stack or { spellID = nil, maxStacks = 3, onlyMine = true }
  if not frame.countText then
    frame.countText = frame:CreateFontString(nil, "OVERLAY")
  end
  frame.countText:SetFont(ns.GetFont(), ns.FontSize(cfg.fontSize or 11), "OUTLINE")
end

function StackBar:Update(frame, cfg)
  local stack = cfg.stack or {}
  local maxStacks = math.max(stack.maxStacks or 3, 1)
  local size = cfg.iconSize or 16
  local spacing = cfg.spacing or 4
  local color = stack.color or DEFAULT_COLOR

  local current = 0
  if ns.TestMode and ns.TestMode.active then
    current = math.min(2, maxStacks)
  elseif stack.spellID then
    local aura = ns.Auras:GetAura(stack.unit or "player", stack.spellID, stack.onlyMine ~= false)
    current = aura and math.max(aura.count, 1) or 0
  end

  local segments = AcquireSegments(frame, maxStacks)
  local totalWidth = maxStacks * size + (maxStacks - 1) * spacing
  frame:SetSize(totalWidth, size)

  for i = 1, maxStacks do
    local seg = segments[i]
    seg:SetSize(size, size)
    seg:ClearAllPoints()
    seg:SetPoint("LEFT", frame, "LEFT", (i - 1) * (size + spacing), 0)
    seg.border:ClearAllPoints()
    seg.border:SetPoint("TOPLEFT", seg, "TOPLEFT", -1, 1)
    seg.border:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", 1, -1)
    if i <= current then
      seg:SetVertexColor(color[1], color[2], color[3], 1)
    else
      seg:SetVertexColor(EMPTY_COLOR[1], EMPTY_COLOR[2], EMPTY_COLOR[3], EMPTY_COLOR[4])
    end
    seg:Show()
    seg.border:Show()
  end
  for i = maxStacks + 1, #segments do
    segments[i]:Hide()
    segments[i].border:Hide()
  end

  if stack.showCount then
    frame.countText:Show()
    frame.countText:ClearAllPoints()
    frame.countText:SetPoint("LEFT", frame, "RIGHT", 5, 0)
    frame.countText:SetText(current .. "/" .. maxStacks)
  else
    frame.countText:Hide()
  end
end
