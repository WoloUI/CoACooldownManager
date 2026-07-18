-- Glow styles for ready/proc icons. Style, color, speed, and pixel line
-- count/thickness are global (Appearance tab):
--   proc   - WeakAuras-style proc glow (UIActionBarFX flipbook)
--   pixel  - bright dashes running around the icon border
--   pulse  - classic action-button border, alpha-pulsing
--   shine  - rotating starburst behind the icon
--   solid  - static bright 2px border
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Glow = {}
ns.Glow = Glow

local BASE_PIXEL_SPEED = 0.25 -- loops per second at 100% speed
local PROC_TEXTURE = "Interface\\AddOns\\CoACooldownManager\\Textures\\UIActionBarFX"
-- Loop flipbook region of UIActionBarFX (6 rows x 5 columns, 30 frames)
local PROC_COORDS = { 0.412598, 0.575195, 0.000976562, 0.391602 }
local PROC_ROWS, PROC_COLS, PROC_FRAMES = 6, 5, 30

local function GlowFrame(btn)
  if not btn.glowFrame then
    btn.glowFrame = CreateFrame("Frame", nil, btn)
    btn.glowFrame:SetAllPoints()
    btn.glowFrame:SetFrameLevel(btn:GetFrameLevel() + 5)
    btn.glowFrame.widgets = {}
  end
  return btn.glowFrame
end

local function Settings()
  return ns.GetGlowSpeed(), ns.GetGlowLines(), ns.GetGlowThickness()
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
  local anim = tex:CreateAnimationGroup()
  anim:SetLooping("BOUNCE")
  local alpha = anim:CreateAnimation("Alpha")
  alpha:SetChange(-0.55)
  alpha:SetDuration(0.6)
  w.anim, w.animAlpha = anim, alpha
  w.SetLayout = function(self, size)
    tex:SetSize(size * 1.7, size * 1.7)
    local speed = Settings()
    if self._speed ~= speed then
      self._speed = speed
      self.anim:Stop()
      self.animAlpha:SetDuration(0.6 / speed)
      self.anim:Play()
    end
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
    local _, _, thickness = Settings()
    local t, b, l, r = self.textures[1], self.textures[2], self.textures[3], self.textures[4]
    local pad = 1
    t:ClearAllPoints(); t:SetSize(size + 2 * pad + 2 * thickness, thickness)
    t:SetPoint("BOTTOM", frame, "TOP", 0, pad)
    b:ClearAllPoints(); b:SetSize(size + 2 * pad + 2 * thickness, thickness)
    b:SetPoint("TOP", frame, "BOTTOM", 0, -pad)
    l:ClearAllPoints(); l:SetSize(thickness, size + 2 * pad)
    l:SetPoint("RIGHT", frame, "LEFT", -pad, 0)
    r:ClearAllPoints(); r:SetSize(thickness, size + 2 * pad)
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
  w.anim, w.animRot = anim, rot
  w.SetLayout = function(self, size)
    tex:SetSize(size * 1.8, size * 1.8)
    local speed = Settings()
    if self._speed ~= speed then
      self._speed = speed
      self.anim:Stop()
      self.animRot:SetDuration(4 / speed)
      self.anim:Play()
    end
  end
  return w
end

function builders.pixel(frame)
  local w = { textures = {} }
  w.EnsureCount = function(self, count)
    for i = #self.textures + 1, count do
      local tex = frame:CreateTexture(nil, "OVERLAY")
      tex:SetTexture("Interface\\Buttons\\WHITE8X8")
      self.textures[i] = tex
    end
    for i = count + 1, #self.textures do
      self.textures[i]:Hide()
    end
  end
  w.SetLayout = function(self, size)
    local speed, lines, thickness = Settings()
    self.side = size + 4
    self.speed = BASE_PIXEL_SPEED * speed
    self.lines = lines
    self.thickness = thickness
    self.length = math.max(thickness * 4, 8)
    self:EnsureCount(lines)
  end
  frame.pixelUpdater = frame.pixelUpdater or CreateFrame("Frame", nil, frame)
  w.updater = frame.pixelUpdater
  w.updater:SetScript("OnUpdate", function()
    if not w.active then return end
    local side = w.side or 36
    local half = side / 2
    local perimeter = side * 4
    local lines = w.lines or 8
    local base = (GetTime() * (w.speed or BASE_PIXEL_SPEED)) % 1
    for i = 1, lines do
      local tex = w.textures[i]
      if not tex then break end
      local d = ((base + (i - 1) / lines) % 1) * perimeter
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
      if horizontal then
        tex:SetSize(w.length or 8, w.thickness or 2)
      else
        tex:SetSize(w.thickness or 2, w.length or 8)
      end
      tex:ClearAllPoints()
      tex:SetPoint("CENTER", frame, "CENTER", x, y)
    end
  end)
  return w
end

-- WeakAuras-style proc glow: 30-frame flipbook over the UIActionBarFX atlas
function builders.proc(frame)
  local w = { textures = {} }
  local tex = frame:CreateTexture(nil, "OVERLAY")
  tex:SetTexture(PROC_TEXTURE)
  tex:SetBlendMode("ADD")
  tex:SetPoint("CENTER")
  w.textures[1] = tex

  local function SetTile(frameIndex)
    local i = frameIndex - 1
    local row = math.floor(i / PROC_COLS)
    local column = i % PROC_COLS
    local left0, right0, top0, bottom0 = PROC_COORDS[1], PROC_COORDS[2], PROC_COORDS[3], PROC_COORDS[4]
    local dx = (right0 - left0) / PROC_COLS
    local dy = (bottom0 - top0) / PROC_ROWS
    local left = left0 + dx * column
    local top = top0 + dy * row
    tex:SetTexCoord(left, left + dx, top, top + dy)
  end
  SetTile(1)

  frame.procUpdater = frame.procUpdater or CreateFrame("Frame", nil, frame)
  w.updater = frame.procUpdater
  w.elapsed, w.frame = 0, 1
  w.updater:SetScript("OnUpdate", function(_, elapsed)
    if not w.active then return end
    w.elapsed = w.elapsed + elapsed
    local frameDuration = 1 / (30 * (w.speed or 1))
    while w.elapsed >= frameDuration do
      w.elapsed = w.elapsed - frameDuration
      w.frame = w.frame + 1
      if w.frame > PROC_FRAMES then w.frame = 1 end
      SetTile(w.frame)
    end
  end)

  w.SetLayout = function(self, size)
    tex:SetSize(size * 1.5, size * 1.5)
    self.speed = Settings()
  end
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

  w:SetLayout(size)
  local color = ns.GetGlowColor()
  for i, tex in ipairs(w.textures) do
    if style ~= "pixel" or i <= (w.lines or #w.textures) then
      tex:SetVertexColor(color[1], color[2], color[3], 1)
      tex:Show()
    end
  end
  if w.anim and not w.anim:IsPlaying() then w.anim:Play() end
  w.active = true
  btn._glowStyle = style
end
