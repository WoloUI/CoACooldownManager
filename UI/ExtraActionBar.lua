-- Movable ExtraActionBar: lets edit mode reposition the client's ExtraActionBar
-- container and, individually, each pooled extra-action button.
--
-- The client re-anchors these frames when it shows them (ClearAllPoints+SetPoint
-- on zone/encounter events), so we post-hook their SetPoint and reassert our
-- saved position behind a re-entrancy guard (Approach A). Buttons are protected
-- action frames: we never move them in combat -- requests made in combat are
-- deferred to PLAYER_REGEN_ENABLED. Edit mode is expected out of combat.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local EAB = {}
ns.ExtraActionBar = EAB

-- Ascension frame names (from the in-game inspector). Buttons live in a pool and
-- are named ...ExtraActionButtonTemplate1, 2, ... -- the trailing index is the
-- button's slot, so a saved position keyed by name is really "slot N goes here".
local BAR_NAME = "ExtraActionBar"
local POOL_FRAME = "ExtraActionBarPoolFrame"
-- Sample placeholder maps to slot 1 so a real slot-1 button inherits its spot.
local SAMPLE_KEY = "ExtraActionBarPoolFrameExtraActionButtonTemplate1"

local guard = {}          -- [frame] = true while WE are calling SetPoint on it
local overlays = {}       -- [key] = drag overlay frame
local sampleButton        -- our non-secure preview button (created lazily)

--------------------------------------------------------------------------------
-- Pure decision seams (unit-tested without live frames)
--------------------------------------------------------------------------------

-- What point should be forced given a saved entry? nil = leave the client's own.
function EAB.ResolvePoint(saved)
  if saved and saved.x and saved.y then return saved.x, saved.y end
  return nil
end

-- A button is "detached" (positioned independently) once it has a saved entry.
function EAB.IsDetached(name, data)
  return not not (data and data.buttons and data.buttons[name])
end

--------------------------------------------------------------------------------
-- Frame plumbing
--------------------------------------------------------------------------------

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

-- Reassert a saved position onto a frame, guarding against the SetPoint hook
-- re-entering, and never touching protected frames mid-combat.
function EAB:Reposition(frame, saved)
  local x, y = EAB.ResolvePoint(saved)
  if not frame or not x then return end
  if InCombat() then self.deferred = true; return end
  guard[frame] = true
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
  if frame.SetUserPlaced then frame:SetUserPlaced(false) end
  guard[frame] = false
end

-- Single hook body: when the client (or anything) moves a tracked frame, put it
-- back where the player parked it.
local function HookedSetPoint(self)
  if guard[self] then return end
  local d = ns.DB:GetExtraAction()
  local saved = self.__cdmEAKind == "bar" and d.bar or d.buttons[self.__cdmEAKind]
  EAB:Reposition(self, saved)
end

local function EnsureHooked(frame, kind)
  if not frame then return end
  frame.__cdmEAKind = kind
  if frame.__cdmEAHooked then return end
  frame.__cdmEAHooked = true
  hooksecurefunc(frame, "SetPoint", HookedSetPoint)
end

-- Walk the pool's children (never guess button names) -> { [name] = frame }.
local function DiscoverButtons()
  local out = {}
  local pool = _G[POOL_FRAME]
  if not pool or not pool.GetChildren then return out end
  local kids = { pool:GetChildren() }
  for _, kid in ipairs(kids) do
    local n = kid.GetName and kid:GetName()
    if n and n:find("ExtraActionButton") then out[n] = kid end
  end
  return out
end

-- Reassert every saved position and make sure new frames are hooked.
function EAB:Apply()
  self.deferred = false
  local d = ns.DB:GetExtraAction()
  local bar = _G[BAR_NAME]
  if bar then
    EnsureHooked(bar, "bar")
    if d.bar then self:Reposition(bar, d.bar) end
  end
  for name, btn in pairs(DiscoverButtons()) do
    EnsureHooked(btn, name)
    local saved = d.buttons[name]
    if saved then self:Reposition(btn, saved) end
  end
end

--------------------------------------------------------------------------------
-- Edit-mode preview + drag overlays
--------------------------------------------------------------------------------

local function SampleButton()
  if sampleButton then return sampleButton end
  local f = CreateFrame("Frame", "CoACDMExtraSampleButton", UIParent)
  f:SetSize(52, 52)
  f:SetFrameStrata("MEDIUM")
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetAllPoints()
  f.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
  f.border = f:CreateTexture(nil, "OVERLAY")
  f.border:SetPoint("TOPLEFT", -2, 2)
  f.border:SetPoint("BOTTOMRIGHT", 2, -2)
  f.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  f:Hide()
  sampleButton = f
  return f
end

local function MakeOverlay(key, label)
  local o = CreateFrame("Frame", nil, UIParent)
  o:SetFrameStrata("HIGH")
  o:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
  })
  o:SetBackdropColor(0.83, 0.55, 0.20, 0.16)       -- amber to read apart from viewers
  o:SetBackdropBorderColor(0.95, 0.68, 0.28, 1)
  o.label = o:CreateFontString(nil, "OVERLAY")
  o.label:SetPoint("BOTTOM", o, "TOP", 0, 3)
  o.label:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
  o.label:SetTextColor(0.98, 0.78, 0.4)
  o.label:SetText(label)
  o.eaKind = key

  o:EnableMouse(true)
  o:RegisterForDrag("LeftButton")
  o:SetScript("OnDragStart", function(self)
    local t = self.target
    if not t then return end
    t:SetMovable(true)
    t:StartMoving()
  end)
  o:SetScript("OnDragStop", function(self)
    local t = self.target
    if not t then return end
    t:StopMovingOrSizing()
    t:SetMovable(false)
    local ex, ey = t:GetCenter()
    if not ex then return end
    local snapX, snapY = ns.EditMode:SnapDelta({ name = "__extraAction" }, t, ex, ey)
    ex, ey = ex + snapX, ey + snapY
    local scx, scy = UIParent:GetCenter()
    local x, y = ex - scx, ey - scy
    if self.eaKind == "bar" then
      ns.DB:SetExtraBarPos(x, y)
    else
      ns.DB:SetExtraButtonPos(self.eaKind, x, y)
    end
    EAB:Apply()
    EAB:LayoutOverlays()
  end)
  return o
end

local function EnsureOverlay(key, target, label)
  local o = overlays[key]
  if not o then o = MakeOverlay(key, label); overlays[key] = o end
  o.target = target
  o.label:SetText(label)
  o:Show()
  return o
end

-- Park overlays (and the sample button) over their targets.
function EAB:LayoutOverlays()
  if not self.editing then return end
  local d = ns.DB:GetExtraAction()
  -- Sample sits at its saved slot-1 spot (or over the bar / screen center).
  if sampleButton and sampleButton:IsShown() then
    sampleButton:ClearAllPoints()
    local saved = d.buttons[SAMPLE_KEY]
    if saved and saved.x then
      sampleButton:SetPoint("CENTER", UIParent, "CENTER", saved.x, saved.y)
    else
      local bar = _G[BAR_NAME]
      if bar and bar:IsShown() then
        sampleButton:SetPoint("CENTER", bar, "CENTER", 0, 0)
      else
        sampleButton:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
      end
    end
  end
  for _, o in pairs(overlays) do
    if o:IsShown() and o.target and o.target.GetCenter and o.target:GetCenter() then
      local w = math.max(o.target:GetWidth() or 0, 40)
      local h = math.max(o.target:GetHeight() or 0, 40)
      o:ClearAllPoints()
      o:SetPoint("CENTER", o.target, "CENTER", 0, 0)
      o:SetSize(w + 8, h + 8)
    end
  end
end

function EAB:ShowPreview()
  self.forced = {}
  local bar = _G[BAR_NAME]
  if bar and bar.Show then
    if not bar:IsShown() then bar:Show(); table.insert(self.forced, bar) end
    EnsureHooked(bar, "bar")
    EnsureOverlay("bar", bar, BAR_NAME)
  end

  local btns = DiscoverButtons()
  local any = false
  for name, btn in pairs(btns) do
    any = true
    if not btn:IsShown() then btn:Show(); table.insert(self.forced, btn) end
    EnsureHooked(btn, name)
    EnsureOverlay(name, btn, name)
  end
  if not any then
    local sample = SampleButton()
    sample:Show()
    EnsureOverlay(SAMPLE_KEY, sample, "Extra button (sample)")
  end

  self:Apply()
  self:LayoutOverlays()
end

function EAB:HidePreview()
  for _, o in pairs(overlays) do o:Hide() end
  if sampleButton then sampleButton:Hide() end
  for _, f in ipairs(self.forced or {}) do
    if f.Hide and not InCombat() then f:Hide() end
  end
  self.forced = nil
end

-- Driven by EditMode:Toggle in lockstep with the viewer overlays.
function EAB:SetEditing(active)
  self.editing = active and true or false
  if self.editing then
    self:ShowPreview()
  else
    self:HidePreview()
    self:Apply() -- reassert saved positions once the preview is torn down
  end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

ns:On("READY", function()
  EAB:Apply()
  ns:On("PROFILE_CHANGED", function()
    EAB:Apply()
    if EAB.editing then EAB:LayoutOverlays() end
  end)
  -- Flush any reposition that was blocked while in combat.
  ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if EAB.deferred then EAB:Apply() end
  end)
end)
