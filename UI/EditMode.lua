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
  -- "-> FRAME" tells nobody anything; the name is the useful half
  local frameName = ns.FrameAnchorName(anchor)
  if anchor.parent == "FRAME" then
    return cfg.name .. "  |cff9aa3b5-> " .. (frameName or "frame?") .. "|r"
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

  -- Clicking a bar picks it for the nudge buttons. OnMouseDown, so it lands
  -- before a drag starts as well as on a plain click.
  overlay:SetScript("OnMouseDown", function(self)
    EditMode:Select(self.cfg.name)
  end)

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

  -- Drop a spell from the spellbook straight onto a bar. The overlay only
  -- exists in edit mode, which is why live bars can stay mouse-transparent.
  local function ReceiveSpell(self)
    local id, name, icon = ns.CursorSpell()
    if not name then return end
    if not ns.CanCapture(self.cfg) then
      ns:Print(("%s does not take spells (style: %s)."):format(self.cfg.name, self.cfg.style))
      return
    end
    ClearCursor()
    ns.CaptureSpell(self.cfg, id, name, icon)
  end
  overlay:SetScript("OnReceiveDrag", ReceiveSpell)
  -- Right click opens this bar's page in the config. Left click stays the spell
  -- drop: the cursor may be carrying a spell, and that is the older gesture.
  overlay:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
      EditMode:Select(self.cfg.name)
      if ns.Config and ns.Config.OpenAt then ns.Config:OpenAt(self.cfg.name) end
      return
    end
    ReceiveSpell(self)
  end)

  return overlay
end

--------------------------------------------------------------------------------
-- Nudge panel: 1px positioning without the mouse
--
-- Dragging cannot land on an exact pixel, and the 12px magnet actively fights
-- fine alignment. These are the arrow buttons ElvUI's mover carries, on the bar
-- you last clicked.
--------------------------------------------------------------------------------
local NUDGE_DIRECTIONS = {
  up = { 0, 1 }, down = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 },
}
local NUDGE_BIG = 10

local StyleOverlay -- defined below; Select re-styles every overlay

-- SetPoint offsets run along the SCREEN axes whatever anchor pair a bar uses,
-- so "up" is +y for a bar hanging below its parent just as much as for a free
-- one -- no per-anchor sign flipping.
function ns.NudgeDelta(direction, big)
  local d = NUDGE_DIRECTIONS[direction]
  if not d then return 0, 0 end
  local step = big and NUDGE_BIG or 1
  return d[1] * step, d[2] * step
end

local nudgeWin

local function SelectedCfg()
  return EditMode.selected and ns.DB:GetViewer(EditMode.selected) or nil
end

function EditMode:Nudge(direction, big)
  local cfg = SelectedCfg()
  if not cfg then return end
  local dx, dy = ns.NudgeDelta(direction, big)
  if dx == 0 and dy == 0 then return end
  local anchor = ns.CopyTable(ns.DB:GetAnchor(cfg))
  anchor.x, anchor.y = (anchor.x or 0) + dx, (anchor.y or 0) + dy
  ns.DB:SetAnchor(cfg, anchor)
  ns.Viewer:ApplyAllAnchors()
  self:RefreshOverlays()
end

local function BuildNudgeWindow()
  local W = ns.Widgets
  -- Tall enough for the D-pad AND the hint under it: the two used to overlap,
  -- the down arrow landing on the first line of text.
  nudgeWin = W.CreateWindow("CoACDMNudge", 176, 204, "Nudge")
  nudgeWin.barLabel = W.CreateLabel(nudgeWin, "", 12, W.colors.gold)
  nudgeWin.barLabel:SetPoint("TOPLEFT", 12, -36)
  nudgeWin.coords = W.CreateLabel(nudgeWin, "", 11, W.colors.inkDim)
  nudgeWin.coords:SetPoint("TOPLEFT", 12, -52)

  local function arrow(text, direction)
    return W.CreateButton(nudgeWin, text, 26, 20, function()
      EditMode:Nudge(direction, IsShiftKeyDown())
    end)
  end
  nudgeWin.up = arrow("^", "up")
  nudgeWin.up:SetPoint("TOP", nudgeWin, "TOP", 0, -70)
  nudgeWin.left = arrow("<", "left")
  nudgeWin.left:SetPoint("TOPRIGHT", nudgeWin.up, "TOPLEFT", -8, -24)
  nudgeWin.right = arrow(">", "right")
  nudgeWin.right:SetPoint("TOPLEFT", nudgeWin.up, "TOPRIGHT", 8, -24)
  nudgeWin.down = arrow("v", "down")
  nudgeWin.down:SetPoint("TOP", nudgeWin.up, "BOTTOM", 0, -28)

  nudgeWin.hint = W.CreateLabel(nudgeWin,
    "Click a bar to pick it.\nHold Shift for " .. NUDGE_BIG .. "px steps.", 10, W.colors.inkDim)
  nudgeWin.hint:SetPoint("BOTTOMLEFT", 12, 12)
  return nudgeWin
end

function EditMode:RefreshNudge()
  if not self.active then
    if nudgeWin then nudgeWin:Hide() end
    return
  end
  if not nudgeWin then BuildNudgeWindow() end
  local cfg = SelectedCfg()
  if cfg then
    local anchor = ns.DB:GetAnchor(cfg)
    nudgeWin.barLabel:SetText(cfg.name)
    nudgeWin.coords:SetText(("x %d   y %d"):format(
      math.floor((anchor.x or 0) + 0.5), math.floor((anchor.y or 0) + 0.5)))
  else
    nudgeWin.barLabel:SetText("no bar picked")
    nudgeWin.coords:SetText("")
  end
  nudgeWin:Show()
end

function EditMode:Select(name)
  self.selected = name
  self:RefreshNudge()
  for viewerName, overlay in pairs(overlays) do
    if overlay.cfg then StyleOverlay(overlay, overlay.cfg, viewerName == name) end
  end
end

function StyleOverlay(overlay, cfg, selected)
  if selected == nil then selected = (EditMode.selected == cfg.name) end
  local isRoot = cfg.name == "Power"
  if selected then
    overlay:SetBackdropColor(0.85, 0.64, 0.29, 0.16)
    overlay:SetBackdropBorderColor(0.85, 0.64, 0.29, 1)
    overlay.label:SetTextColor(0.95, 0.78, 0.42)
  elseif isRoot then
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
  if self.active and ns.ExtraActionBar then ns.ExtraActionBar:LayoutOverlays() end
  self:RefreshNudge()
end

function EditMode:Toggle()
  self.active = not self.active
  ns.Viewer:UpdateVisibility()
  self:RefreshOverlays()
  if ns.AggroAlert then ns.AggroAlert:Apply() end -- grabbable while editing
  if ns.RangeAlert then ns.RangeAlert:Apply() end
  if ns.MissingBuffs then ns.MissingBuffs:Apply() end
  if ns.ExtraActionBar then ns.ExtraActionBar:SetEditing(self.active) end
  if self.active then
    ns:Print("edit mode ON - drag bars to move them; drag the Power bar to move everything. "
      .. "Click a bar and use the Nudge arrows for 1px steps; right click it to open its settings. "
      .. "Drop a spell from your spellbook on a bar to add it. /cdm edit to finish.")
  else
    ns:Print("edit mode off; layout saved.")
  end
end

--------------------------------------------------------------------------------
-- Spell capture from the spellbook (shift+click)
--
-- Ascension replaces the Blizzard spellbook with its own frame, so the buttons
-- are hooked by name. Buttons are recycled across pages, so one hook each is
-- enough. HookScript, never SetScript: the client's own click behaviour has to
-- survive.
--------------------------------------------------------------------------------
local SpellCapture = {}
ns.SpellCapture = SpellCapture

local BUTTON_PREFIXES = {
  "AscensionSpellbookFrameContentSpellsSpellButton",
  "AscensionSpellbookFrameContentPetSpellsSpellButton",
  "SpellButton", -- stock 3.3.5 spellbook, in case the custom frame is absent
}
local BUTTONS_PER_PAGE = 12

-- The button's spell, with the source that answered. The custom frame cannot
-- be inspected offline, hence the chain: /cdm spellbook prints what wins.
--
-- Verified in-game 2026-07-27: on this client only the THIRD path answers --
-- the buttons carry no `.spellID` and there is no SpellBook_GetSpellID. The
-- name FontString is the real resolver, which suits the addon anyway: a name
-- follows the learned rank, so Cinderheart resolves to its Rank 10 id.
-- The first two are kept as cheap, more-precise paths in case a client update
-- starts populating them.
function SpellCapture.ButtonSpell(button)
  if not button then return nil end
  if button.spellID then
    local id, name, icon = ns.ResolveSpell(button.spellID)
    if name then return id, name, icon, "button.spellID" end
  end
  if _G.SpellBook_GetSpellID and button.GetID then
    local ok, slot = pcall(_G.SpellBook_GetSpellID, button:GetID())
    if ok and slot then
      local link = GetSpellLink and GetSpellLink(slot, BOOKTYPE_SPELL)
      local linkId = link and tonumber(link:match("spell:(%d+)"))
      if linkId then
        local id, name, icon = ns.ResolveSpell(linkId)
        if name then return id, name, icon, "SpellBook_GetSpellID" end
      end
    end
  end
  local frameName = button.GetName and button:GetName()
  local nameText = frameName and _G[frameName .. "SpellName"]
  local text = nameText and nameText.GetText and nameText:GetText()
  if text and text ~= "" then
    local id, name, icon = ns.ResolveSpell(text)
    if name then return id, name, icon, "SpellName text" end
  end
  return nil
end

local function OnSpellButtonClick(button)
  if not IsShiftKeyDown() then return end
  -- shift+click in the spellbook also means "insert a link" when a chat box is
  -- open; leave that alone
  if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then return end
  local viewer = ns.Config and ns.Config.CaptureTarget and ns.Config:CaptureTarget()
  if not viewer then
    ns:Print("open the config panel and select a spell bar first, then shift+click to add spells to it.")
    return
  end
  local id, name, icon = SpellCapture.ButtonSpell(button)
  if not name then
    ns:Print("could not read that spellbook button - run /cdm spellbook and send the output.")
    return
  end
  ns.CaptureSpell(viewer, id, name, icon)
end

local hooked = {}

function SpellCapture:HookButtons()
  for _, prefix in ipairs(BUTTON_PREFIXES) do
    local count = prefix == "AscensionSpellbookFrameContentSpellsSpellButton"
      and (_G.SPELLS_PER_PAGE or BUTTONS_PER_PAGE) or BUTTONS_PER_PAGE
    for i = 1, count do
      local button = _G[prefix .. i]
      if button and not hooked[button] and button.HookScript then
        button:HookScript("OnClick", OnSpellButtonClick)
        hooked[button] = true
      end
    end
  end
end

-- /cdm spellbook: which resolver answers for the buttons currently on screen.
-- Only VISIBLE buttons are listed. The pet tab and the stock 3.3.5 spellbook
-- frames exist on this client but sit empty and hidden, so listing them printed
-- 24 "unresolved" lines that looked like failures and buried the real ones.
function SpellCapture:Diagnose()
  self:HookButtons()
  local shown, resolved = 0, 0
  for _, prefix in ipairs(BUTTON_PREFIXES) do
    for i = 1, (_G.SPELLS_PER_PAGE or BUTTONS_PER_PAGE) do
      local button = _G[prefix .. i]
      if button and button.IsVisible and button:IsVisible() then
        shown = shown + 1
        local id, name, _, source = SpellCapture.ButtonSpell(button)
        if name then resolved = resolved + 1 end
        ns:Print(("  %s%d: %s (id=%s) via %s"):format(
          prefix, i, name or "|cffff5555unresolved|r", tostring(id), source or "-"))
      end
    end
  end
  if shown == 0 then
    ns:Print("no spellbook buttons on screen - open your spellbook first.")
    return
  end
  local viewer = ns.Config and ns.Config.CaptureTarget and ns.Config:CaptureTarget()
  ns:Print(("%d/%d visible buttons resolved; capture target: %s"):format(
    resolved, shown,
    viewer and viewer.name or "|cffff5555none (open the config panel and pick a bar)|r"))
  if resolved < shown then
    ns:Print("unresolved buttons above are the ones shift+click cannot read - send this output.")
  end
end

ns:On("READY", function()
  SpellCapture:HookButtons()
  -- the spellbook frame can be created after login
  ns:RegisterEvent("PLAYER_ENTERING_WORLD", function() SpellCapture:HookButtons() end)
end)

ns:On("READY", function()
  ns:On("PROFILE_CHANGED", function()
    if EditMode.active then EditMode:RefreshOverlays() end
  end)
  ns:On("VIEWERS_CHANGED", function()
    if EditMode.active then EditMode:RefreshOverlays() end
  end)
end)
