-- Edit mode: per-viewer overlay with name + anchor label, mouse dragging,
-- offsets saved into the active layout. Moving the Power bar drags the tree.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local EditMode = {}
ns.EditMode = EditMode

EditMode.active = false

local overlays = {} -- [viewerName] = overlay frame

-- Magnetic snapping: when a dragged bar's center lands near the center axis of
-- another bar (or the screen), it clicks into alignment. Axes snap separately.
local SNAP_RANGE = 12

function EditMode:SnapDelta(cfg, frame, cx, cy)
  local bestDX, bestDY

  local function consider(tx, ty)
    if tx then
      local d = tx - cx
      if math.abs(d) <= SNAP_RANGE and (not bestDX or math.abs(d) < math.abs(bestDX)) then bestDX = d end
    end
    if ty then
      local d = ty - cy
      if math.abs(d) <= SNAP_RANGE and (not bestDY or math.abs(d) < math.abs(bestDY)) then bestDY = d end
    end
  end

  consider(UIParent:GetCenter()) -- screen center

  for _, other in ipairs(ns.profile.viewers) do
    -- Skip self and anything anchored below the dragged bar (it moved with us)
    if other.name ~= cfg.name and not ns.DB:WouldCycle(cfg.name, other.name) then
      local otherFrame = ns.Viewer:GetFrame(other.name)
      if otherFrame and otherFrame:IsShown() then
        consider(otherFrame:GetCenter())
      end
    end
  end

  return bestDX or 0, bestDY or 0
end

local function AnchorLabel(cfg)
  local anchor = ns.DB:GetAnchor(cfg)
  if anchor.parent == "FREE" or not anchor.parent then
    return cfg.name .. "  |cff9aa3b5(free)|r"
  end
  return cfg.name .. "  |cff9aa3b5-> " .. anchor.parent .. "|r"
end

local function CreateOverlay(viewerFrame, cfg)
  local overlay = CreateFrame("Frame", nil, viewerFrame)
  overlay:SetFrameStrata("HIGH")
  overlay:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
  })

  overlay.label = overlay:CreateFontString(nil, "OVERLAY")
  overlay.label:SetPoint("BOTTOM", overlay, "TOP", 0, 3)
  overlay.label:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")

  overlay:EnableMouse(true)
  overlay:RegisterForDrag("LeftButton")

  overlay:SetScript("OnDragStart", function(self)
    local frame = self.viewerFrame
    frame:SetMovable(true)
    self.dragStartX, self.dragStartY = frame:GetCenter()
    frame:StartMoving()
  end)

  overlay:SetScript("OnDragStop", function(self)
    local frame = self.viewerFrame
    frame:StopMovingOrSizing()
    frame:SetUserPlaced(false) -- keep the client's layout-cache out of our anchors
    frame:SetMovable(false)
    local endX, endY = frame:GetCenter()
    local snapX, snapY = EditMode:SnapDelta(self.cfg, frame, endX, endY)
    local dx = endX - (self.dragStartX or endX) + snapX
    local dy = endY - (self.dragStartY or endY) + snapY

    local viewerCfg = self.cfg
    local anchor = ns.CopyTable(ns.DB:GetAnchor(viewerCfg))
    anchor.x = (anchor.x or 0) + dx
    anchor.y = (anchor.y or 0) + dy
    ns.DB:SetAnchor(viewerCfg, anchor)

    ns.Viewer:ApplyAllAnchors()
    EditMode:RefreshOverlays()
  end)

  return overlay
end

local function StyleOverlay(overlay, cfg)
  local isRoot = cfg.name == "Power"
  if isRoot then
    overlay:SetBackdropColor(0.34, 0.83, 0.65, 0.14)
    overlay:SetBackdropBorderColor(0.34, 0.83, 0.65, 1)
    overlay.label:SetTextColor(0.34, 0.83, 0.65)
  else
    overlay:SetBackdropColor(0.18, 0.42, 0.33, 0.12)
    overlay:SetBackdropBorderColor(0.18, 0.42, 0.33, 1)
    overlay.label:SetTextColor(0.55, 0.85, 0.70)
  end
  overlay.label:SetText(AnchorLabel(cfg))
end

function EditMode:RefreshOverlays()
  for _, cfg in ipairs(ns.profile.viewers) do
    local viewerFrame = ns.Viewer:GetFrame(cfg.name)
    if viewerFrame then
      local overlay = overlays[cfg.name]
      if not overlay then
        overlay = CreateOverlay(viewerFrame, cfg)
        overlays[cfg.name] = overlay
      end
      overlay.viewerFrame = viewerFrame
      overlay.cfg = cfg
      overlay:SetParent(viewerFrame)
      overlay:ClearAllPoints()
      -- Give tiny/empty viewers a grabbable surface
      local w = math.max(viewerFrame:GetWidth() or 0, 90)
      local h = math.max(viewerFrame:GetHeight() or 0, 22)
      overlay:SetPoint("CENTER", viewerFrame, "CENTER")
      overlay:SetSize(w + 10, h + 10)
      StyleOverlay(overlay, cfg)
      if self.active then overlay:Show() else overlay:Hide() end
    end
  end
  for name, overlay in pairs(overlays) do
    if not ns.DB:GetViewer(name) then overlay:Hide() end
  end
end

function EditMode:Toggle()
  self.active = not self.active
  ns.Viewer:UpdateVisibility()
  self:RefreshOverlays()
  if ns.AggroAlert then ns.AggroAlert:Apply() end -- grabbable while editing
  if self.active then
    ns:Print("edit mode ON - drag bars to move them; drag the Power bar to move everything. /cdm edit to finish.")
  else
    ns:Print("edit mode off; layout saved.")
  end
end

ns:On("READY", function()
  ns:On("PROFILE_CHANGED", function()
    if EditMode.active then EditMode:RefreshOverlays() end
  end)
  ns:On("VIEWERS_CHANGED", function()
    if EditMode.active then EditMode:RefreshOverlays() end
  end)
end)
