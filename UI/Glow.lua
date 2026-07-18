-- Glow styles for ready/proc icons. Style + color are global (Appearance tab):
--   pixel  - bright dashes running around the icon border (most visible)
--   pulse  - classic action-button border, alpha-pulsing
--   shine  - rotating starburst behind the icon
--   solid  - static bright 2px border
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Glow = {}
ns.Glow = Glow

local PIXEL_COUNT = 8
local PIXEL_SPEED = 0.30 -- loops per second

local function GlowFrame(btn)
  if not btn.glowFrame then
    btn.glowFrame = CreateFrame("Frame", nil, btn)
    btn.glowFrame:SetAllPoints()
    btn.glowFrame:SetFrameLevel(btn:GetFrameLevel() + 5)
    btn.glowFrame.widgets = {}
  end
  return btn.glowFrame
end

--------------------------------------------------------------------------------
-- Style builders (created once per button, on demand)
--------------------------------------------------------------------------------
local builders = {}

function builders.pulse(frame)
  local w = { textures = {} }
  local tex = frame:CreateTexture(nil, "OVERLAY")
  tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  tex:SetBlendMode("ADD")
  tex:SetPoint("CENTER")
  w.textures[1] = tex
  w.main = tex
  local anim = tex:CreateAnimationGroup()
  anim:SetLooping("BOUNCE")
  local alpha = anim:CreateAnimation("Alpha")
  alpha:SetChange(-0.55)
  alpha:SetDuration(0.6)
  w.anim = anim
  w.SetLayout = function(self, size)
    tex:SetSize(size * 1.7, size * 1.7)
  end
  return w
end

function builders.solid(frame)
  local w = { textures = {} }
  for i = 1, 4 do
    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    w.textures[i] = tex
  end
  w.SetLayout = function(self, size)
    local t, b, l, r = self.textures[1], self.textures[2], self.textures[3], self.textures[4]
    local pad = 1
    t:ClearAllPoints(); t:SetSize(size + 2 * pad + 4, 2)
    t:SetPoint("BOTTOM", frame, "TOP", 0, pad)
    b:ClearAllPoints(); b:SetSize(size + 2 * pad + 4, 2)
    b:SetPoint("TOP", frame, "BOTTOM", 0, -pad)
    l:ClearAllPoints(); l:SetSize(2, size + 2 * pad)
    l:SetPoint("RIGHT", frame, "LEFT", -pad, 0)
    r:ClearAllPoints(); r:SetSize(2, size + 2 * pad)
    r:SetPoint("LEFT", frame, "RIGHT", pad, 0)
  end
  return w
end

function builders.shine(frame)
  local w = { textures = {} }
  local tex = frame:CreateTexture(nil, "OVERLAY")
  tex:SetTexture("Interface\\Cooldown\\star4")
  tex:SetBlendMode("ADD")
  tex:SetPoint("CENTER")
  w.textures[1] = tex
  local anim = tex:CreateAnimationGroup()
  anim:SetLooping("REPEAT")
  local rot = anim:CreateAnimation("Rotation")
  rot:SetDegrees(360)
  rot:SetDuration(4)
  w.anim = anim
  w.SetLayout = function(self, size)
    tex:SetSize(size * 1.8, size * 1.8)
  end
  return w
end

function builders.pixel(frame)
  local w = { textures = {} }
  for i = 1, PIXEL_COUNT do
    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    w.textures[i] = tex
  end
  w.SetLayout = function(self, size)
    self.side = size + 4
  end
  -- Dashes travel clockwise around the border
  frame.pixelUpdater = frame.pixelUpdater or CreateFrame("Frame", nil, frame)
  w.updater = frame.pixelUpdater
  w.updater:SetScript("OnUpdate", function()
    if not w.active then return end
    local side = w.side or 36
    local half = side / 2
    local perimeter = side * 4
    local base = (GetTime() * PIXEL_SPEED) % 1
    for i, tex in ipairs(w.textures) do
      local d = ((base + (i - 1) / PIXEL_COUNT) % 1) * perimeter
      local x, y, horizontal
      if d < side then
        x, y, horizontal = -half + d, half, true
      elseif d < side * 2 then
        x, y, horizontal = half, half - (d - side), false
      elseif d < side * 3 then
        x, y, horizontal = half - (d - side * 2), -half, true
      else
        x, y, horizontal = -half, -half + (d - side * 3), false
      end
      if horizontal then tex:SetSize(8, 2) else tex:SetSize(2, 8) end
      tex:ClearAllPoints()
      tex:SetPoint("CENTER", frame, "CENTER", x, y)
    end
  end)
  return w
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
local function HideWidget(w)
  if not w then return end
  w.active = false
  if w.anim then w.anim:Stop() end
  for _, tex in ipairs(w.textures) do tex:Hide() end
end

-- Applies/refreshes the glow on a button. Called every display update.
function Glow:Set(btn, enabled, size)
  local style = ns.GetGlowStyle()

  if btn._glowStyle and (btn._glowStyle ~= style or not enabled) then
    local frame = btn.glowFrame
    HideWidget(frame and frame.widgets[btn._glowStyle])
    btn._glowStyle = nil
  end
  if not enabled then return end

  local frame = GlowFrame(btn)
  local w = frame.widgets[style]
  if not w then
    w = (builders[style] or builders.pixel)(frame)
    frame.widgets[style] = w
  end

  local color = ns.GetGlowColor()
  for _, tex in ipairs(w.textures) do
    tex:SetVertexColor(color[1], color[2], color[3], 1)
    tex:Show()
  end
  w:SetLayout(size)
  if w.anim and not w.anim:IsPlaying() then w.anim:Play() end
  w.active = true
  btn._glowStyle = style
end
