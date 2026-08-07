-- Duration-bar style for buffs/DoTs: icon + name + time, draining fill,
-- desaturated "missing" state for DoTs that fell off the target.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local StatusBars = {}
ns.StatusBars = StatusBars

local COLOR_BUFF = { 0.25, 0.50, 0.84 }
local COLOR_DEBUFF = { 0.56, 0.29, 0.72 }
local COLOR_MISSING = { 0.35, 0.35, 0.35 }

local function CreateBar(parent)
  local holder = CreateFrame("Frame", nil, parent)

  holder.iconFrame = CreateFrame("Frame", nil, holder)
  holder.iconFrame:SetPoint("LEFT")
  holder.icon = holder.iconFrame:CreateTexture(nil, "ARTWORK")
  holder.icon:SetAllPoints()
  ns.CropIcon(holder.icon)

  holder.bar = CreateFrame("StatusBar", nil, holder)
  holder.bar:SetPoint("TOPLEFT", holder.iconFrame, "TOPRIGHT", 1, 0)
  holder.bar:SetPoint("BOTTOMRIGHT")
  holder.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")

  holder.bg = holder.bar:CreateTexture(nil, "BACKGROUND")
  holder.bg:SetAllPoints()
  holder.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  holder.bg:SetVertexColor(0.05, 0.06, 0.09, 0.9)

  holder.backdrop = holder:CreateTexture(nil, "BACKGROUND")
  holder.backdrop:SetPoint("TOPLEFT", -1, 1)
  holder.backdrop:SetPoint("BOTTOMRIGHT", 1, -1)
  holder.backdrop:SetTexture("Interface\\Buttons\\WHITE8X8")
  holder.backdrop:SetVertexColor(0, 0, 0, 0.9)

  holder.nameText = holder.bar:CreateFontString(nil, "OVERLAY")
  holder.nameText:SetPoint("LEFT", 5, 0)
  holder.nameText:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
  holder.nameText:SetJustifyH("LEFT")

  holder.timeText = holder.bar:CreateFontString(nil, "OVERLAY")
  holder.timeText:SetPoint("RIGHT", -5, 0)
  holder.timeText:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")

  return holder
end

local function AcquireBar(frame, index)
  frame.bars = frame.bars or {}
  local bar = frame.bars[index]
  if not bar then
    bar = CreateBar(frame)
    frame.bars[index] = bar
  end
  return bar
end

--------------------------------------------------------------------------------
-- Style interface
--------------------------------------------------------------------------------
function StatusBars:Build(frame, cfg)
  frame.bars = frame.bars or {}
  for _, bar in ipairs(frame.bars) do bar:Hide() end
end

local function SetBarDisplay(holder, display, element, cfg, now)
  local w = ns.ResolveWidth(cfg, cfg.barWidth or 250)
  local h = cfg.barHeight or 20
  holder:SetSize(w, h)

  -- The bar is normally anchored to the right edge of the square icon. With the
  -- icon hidden it is re-anchored to the holder instead, so it spans the whole
  -- row rather than leaving a gap where the icon used to be. Re-anchoring
  -- rather than sizing the icon frame to zero keeps the intent readable.
  --
  -- Only on a CHANGE: this runs for every row on every tick, and re-anchoring a
  -- frame that is already where it belongs is wasted work. `nil` on a fresh
  -- holder never equals either boolean, so the first pass always anchors.
  local showIcon = cfg.showIcon ~= false
  if holder._iconShown ~= showIcon then
    holder._iconShown = showIcon
    holder.bar:ClearAllPoints()
    holder.bar:SetPoint("BOTTOMRIGHT")
    if showIcon then
      holder.iconFrame:Show()
      holder.bar:SetPoint("TOPLEFT", holder.iconFrame, "TOPRIGHT", 1, 0)
    else
      holder.iconFrame:Hide()
      holder.bar:SetPoint("TOPLEFT")
    end
  end
  if showIcon then holder.iconFrame:SetSize(h, h) end
  local font = ns.GetFont()
  local fontSize = ns.FontSize(cfg.fontSize or 11)
  holder.nameText:SetFont(font, fontSize, "OUTLINE")
  holder.timeText:SetFont(font, fontSize, "OUTLINE")
  holder.bar:SetStatusBarTexture(ns.GetTexture())
  local showTimer = cfg.showTimer ~= false

  holder.icon:SetTexture(display.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
  holder.icon:SetDesaturated(display.missing or display.desaturate)
  holder.nameText:SetText(display.name or "")

  local color = element.kind == "debuff" and COLOR_DEBUFF or COLOR_BUFF
  if display.missing then
    holder.bar:SetStatusBarColor(COLOR_MISSING[1], COLOR_MISSING[2], COLOR_MISSING[3])
    holder.bar:SetMinMaxValues(0, 1)
    ns.SetBarStatic(holder.bar, 0)
    holder.nameText:SetTextColor(0.65, 0.65, 0.65)
    holder.timeText:SetText(showTimer and "--" or "")
  else
    holder.bar:SetStatusBarColor(color[1], color[2], color[3])
    holder.nameText:SetTextColor(1, 1, 1)
    if display.duration > 0 then
      local remaining = math.max(0, display.expirationTime - now)
      holder.bar:SetMinMaxValues(0, display.duration)
      ns.SetBarDrain(holder.bar, display.expirationTime) -- per-frame smooth fill
      holder.timeText:SetText(showTimer and ns.FormatTime(remaining) or "")
    else -- permanent aura
      holder.bar:SetMinMaxValues(0, 1)
      ns.SetBarStatic(holder.bar, 1)
      holder.timeText:SetText("")
    end
  end

  if cfg.showStacks ~= false and display.stacks and display.stacks > 1 then
    holder.nameText:SetText((display.name or "") .. " (" .. display.stacks .. ")")
  end
end

local function LayoutBars(frame, cfg, count)
  local w = ns.ResolveWidth(cfg, cfg.barWidth or 250)
  local h = cfg.barHeight or 20
  local spacing = cfg.spacing or 3
  local total = count > 0 and (count * h + (count - 1) * spacing) or h
  frame:SetSize(w, total)

  local growUp = (cfg.growth or "UP") == "UP"
  for i = 1, count do
    local bar = frame.bars[i]
    bar:ClearAllPoints()
    local offset = (i - 1) * (h + spacing)
    if growUp then
      bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, offset)
    else
      bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -offset)
    end
  end
end

function StatusBars:Update(frame, cfg)
  local now = GetTime()
  local shown = 0
  if ns.TestMode and ns.TestMode.active then
    shown = ns.TestMode:FillBars(frame, cfg, AcquireBar, SetBarDisplay)
  else
    for _, element in ipairs(cfg.elements) do
      local display = ns.Triggers:Evaluate(element)
      if ns.ActionGlow then ns.ActionGlow(element, display) end
      if display.shown then
        shown = shown + 1
        local bar = AcquireBar(frame, shown)
        SetBarDisplay(bar, display, element, cfg, now)
        bar:Show()
      end
    end
  end
  if frame.bars then
    for i = shown + 1, #frame.bars do
      frame.bars[i]:Hide()
    end
  end
  LayoutBars(frame, cfg, shown)
end

-- Test seams
StatusBars._SetBarDisplay = SetBarDisplay

--------------------------------------------------------------------------------
-- Shield style ("shield"): a vertical, slightly curved column of segments per
-- tracked shield buff, draining with the REAL absorb left on the unit
-- (Ascension backports UnitGetTotalAbsorbs), amount below. Lives in this file
-- so no .toc change is needed (a new file would need a full client restart).
--------------------------------------------------------------------------------
local ShieldBar = {}
ns.ShieldBar = ShieldBar

-- UnitGetTotalAbsorbs is a UNIT total (no per-aura split on this client).
-- A per-unit ledger splits it across the tracked shields: each instance's
-- size is the total's jump when its aura (re)appears, drains are attributed
-- to the OLDEST shield first (WoW consumes absorbs in application order),
-- and every tick the ledger is reconciled so the sum matches the real total.
-- With a single shield up the value is exact.
local ledgers = {} -- [unit] = weak table [element] = {exp, initial, remaining, appliedAt, seenAt}
local STALE = 0.4  -- instances updated within this window count as live
local GRACE = 1.0  -- absorb registration can lag the aura: grow freely this long

-- entries: array of { element, exp }. Returns the unit's instance table.
local function UpdateLedger(unit, entries, total, now)
  local insts = ledgers[unit]
  if not insts then
    insts = setmetatable({}, { __mode = "k" })
    ledgers[unit] = insts
  end

  -- stamp known instances; collect (re)applied shields. A replaced instance
  -- (refresh changed the expiration) is dropped NOW so its old value does
  -- not count against the new one's size
  local fresh = {}
  for _, entry in ipairs(entries) do
    local inst = insts[entry.element]
    if inst and inst.exp == entry.exp then
      inst.seenAt = now
    else
      insts[entry.element] = nil
      fresh[#fresh + 1] = entry
    end
  end

  -- live set: recently-updated instances (covers several viewers ticking the
  -- same unit) — expired shields age out of the math on their own
  local live, sum = {}, 0
  for _, inst in pairs(insts) do
    if now - (inst.seenAt or 0) <= STALE then
      live[#live + 1] = inst
      sum = sum + inst.remaining
    end
  end

  -- new instances split whatever the total holds beyond the known shields
  if #fresh > 0 then
    local share = math.max(total - sum, 1) / #fresh
    for _, entry in ipairs(fresh) do
      local inst = { exp = entry.exp, initial = share, remaining = share,
        appliedAt = now, seenAt = now }
      insts[entry.element] = inst
      live[#live + 1] = inst
      sum = sum + share
    end
  end

  -- reconcile with the real total
  local excess = sum - total
  if excess > 0 then
    table.sort(live, function(a, b) return (a.appliedAt or 0) < (b.appliedAt or 0) end)
    for _, inst in ipairs(live) do
      if excess <= 0 then break end
      local cut = math.min(inst.remaining, excess)
      inst.remaining = inst.remaining - cut
      excess = excess - cut
    end
  elseif excess < 0 then
    -- Total grew without a tracked (re)application: goes to the newest.
    -- Right after an application the absorb amount can register LATE (the
    -- aura event beats it), so young instances grow freely — their real size
    -- is this late jump. Past the grace window, cap at the known size so an
    -- untracked external shield cannot inflate ours.
    local newest
    for _, inst in ipairs(live) do
      if not newest or (inst.appliedAt or 0) > (newest.appliedAt or 0) then newest = inst end
    end
    if newest then
      local grown = newest.remaining - excess
      if now - (newest.appliedAt or 0) <= GRACE then
        newest.remaining = grown
        if grown > newest.initial then newest.initial = grown end
      else
        newest.remaining = math.min(grown, newest.initial)
      end
    end
  end
  return insts
end
ShieldBar._UpdateLedger = UpdateLedger -- test seam

-- No absorb API: fall back to draining with the buff's remaining time
local function TimeFraction(display)
  if display.duration and display.duration > 0 then
    return math.max(0, display.expirationTime - GetTime()) / display.duration, nil
  end
  return 1, nil
end

local function AcquireColumn(frame, index)
  frame.shieldCols = frame.shieldCols or {}
  local col = frame.shieldCols[index]
  if not col then
    col = CreateFrame("Frame", nil, frame)
    col.segs = {}
    col.valueText = col:CreateFontString(nil, "OVERLAY")
    col.valueText:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    col.valueText:SetPoint("TOP", col, "BOTTOM", 0, -2)
    frame.shieldCols[index] = col
  end
  return col
end

local function SetColumnDisplay(col, fraction, absorb, missing, cfg)
  local sc = cfg.shield or {}
  local count = sc.segments or 14
  local segW, segH = sc.segW or 24, sc.segH or 7
  local gap = sc.gap or 2
  local curve = sc.curve or 12
  local color = sc.color or { 1, 0.72, 0.2 }
  col:SetSize(segW + math.abs(curve), count * (segH + gap) - gap)

  local lit = missing and 0 or math.floor(fraction * count + 0.5)
  local base = curve >= 0 and 0 or -curve -- keep negative bows inside the frame
  for i = 1, count do
    local seg = col.segs[i]
    if not seg then
      seg = col:CreateTexture(nil, "ARTWORK")
      seg:SetTexture("Interface\\Buttons\\WHITE8X8")
      col.segs[i] = seg
    end
    local t = count > 1 and (i - 1) / (count - 1) or 0
    seg:SetSize(segW, segH)
    seg:ClearAllPoints()
    seg:SetPoint("BOTTOMLEFT", col, "BOTTOMLEFT",
      base + curve * math.sin(t * math.pi), (i - 1) * (segH + gap))
    if i <= lit then
      seg:SetVertexColor(color[1], color[2], color[3], 1)
    else
      seg:SetVertexColor(0.18, 0.18, 0.22, 0.55)
    end
    seg:Show()
  end
  for i = count + 1, #col.segs do col.segs[i]:Hide() end

  col.valueText:SetFont(ns.GetFont(), ns.FontSize(cfg.fontSize or 11), "OUTLINE")
  if missing then
    col.valueText:SetText("--")
    col.valueText:SetTextColor(0.65, 0.65, 0.65)
  elseif sc.showValue ~= false and absorb then
    col.valueText:SetText(ns.FormatShortNumber(absorb))
    col.valueText:SetTextColor(1, 1, 1)
  else
    col.valueText:SetText("")
  end
end

function ShieldBar:Build(frame, cfg)
  frame.shieldCols = frame.shieldCols or {}
  for _, col in ipairs(frame.shieldCols) do col:Hide() end
end

function ShieldBar:Update(frame, cfg)
  local shown = 0
  if ns.TestMode and ns.TestMode.active then
    -- Looping preview: a shield draining over 10 seconds
    local fraction = 1 - (GetTime() % 10) / 10
    local col = AcquireColumn(frame, 1)
    SetColumnDisplay(col, fraction, math.floor(fraction * 18500), false, cfg)
    col:Show()
    shown = 1
  else
    -- Evaluate first, then run ONE ledger pass per unit so simultaneous
    -- shields on the same unit split the absorb total correctly
    local toShow, byUnit = {}, {}
    for _, element in ipairs(cfg.elements or {}) do
      local display = ns.Triggers:Evaluate(element)
      if display.shown then
        toShow[#toShow + 1] = { element = element, display = display }
        if not display.missing and UnitGetTotalAbsorbs then
          local unit = element.unit or "player"
          byUnit[unit] = byUnit[unit] or {}
          table.insert(byUnit[unit], { element = element, exp = display.expirationTime })
        end
      end
    end
    local now = GetTime()
    local instsByUnit = {}
    for unit, entries in pairs(byUnit) do
      instsByUnit[unit] = UpdateLedger(unit, entries, UnitGetTotalAbsorbs(unit) or 0, now)
    end
    for _, entry in ipairs(toShow) do
      shown = shown + 1
      local col = AcquireColumn(frame, shown)
      local fraction, absorb = 0, nil
      if not entry.display.missing then
        local unit = entry.element.unit or "player"
        local inst = instsByUnit[unit] and instsByUnit[unit][entry.element]
        if inst then
          fraction = inst.initial > 0 and math.min(inst.remaining / inst.initial, 1) or 0
          absorb = math.floor(inst.remaining + 0.5)
        else
          fraction, absorb = TimeFraction(entry.display)
        end
      end
      SetColumnDisplay(col, fraction, absorb, entry.display.missing, cfg)
      col:Show()
    end
  end
  if frame.shieldCols then
    for i = shown + 1, #frame.shieldCols do frame.shieldCols[i]:Hide() end
  end

  -- Columns sit side by side; +14px under them for the amount text
  local sc = cfg.shield or {}
  local colW = (sc.segW or 24) + math.abs(sc.curve or 12)
  local colH = (sc.segments or 14) * ((sc.segH or 7) + (sc.gap or 2)) - (sc.gap or 2)
  local spacing = cfg.spacing or 10
  local total = shown > 0 and (shown * colW + (shown - 1) * spacing) or colW
  frame:SetSize(math.max(total, 20), colH + 14)
  for i = 1, shown do
    local col = frame.shieldCols[i]
    col:ClearAllPoints()
    col:SetPoint("TOPLEFT", frame, "TOPLEFT", (i - 1) * (colW + spacing), 0)
  end
end
