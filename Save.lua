-- Widsith — the recording icon and the save reminder
--
-- WoW writes SavedVariables only on logout or a UI reload, so a crash loses
-- everything since the last one. The addon's one on-screen element is the
-- Widsith flame on a disc in the minimap ring, a gauge of unsaved play: it
-- lights when recording starts, burns down while the recording goes unsaved,
-- then the ring glows and, once the character is resting, a reminder appears.
-- A left click saves, which is a UI reload; stopped, the flame is out and grey.
--
-- Settings are the account's (WidsithAccount); a save under way and the last
-- emote are the character's (WidsithUI). Nothing here is written to the
-- recording. The ring and highlight are the game's own art; the flame, disc and
-- glow are the addon's (media/).

local ADDON_NAME, WJ = ...

local BURN_TIME    = 45 * 60 -- seconds of unsaved play from a full flame to an ember
local REMIND_GAP   = 10 * 60 -- seconds from one reminder to the next
local SHOW_FOR     = 30      -- seconds an ignored reminder stays up
local CHECK_EVERY  = 5

local floor, format, max, min = math.floor, string.format, math.max, math.min
local PREFIX = WJ.PREFIX
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\"

-- What each setting is until the player changes it: one list for menu and panel.
local DEFAULTS = { shown = true, remind = true, animate = true, chat = true, emote = false, onRing = true, locked = false,
  iconSize = 1, screenshots = true, shotsChat = true }
WJ.DEFAULTS = DEFAULTS

local settings            -- the account's settings (WidsithAccount.settings)
local icon, bubble
local lastReminder = -math.huge
local bubbleHideAt
local bubbleForced       -- shown by /widsith remind: only the timer hides it

-- Chat, through the recorder's channel when it has one (it honours "Show chat messages").
local function say(text)
  if WJ.say then WJ.say(text) else print(PREFIX .. text) end
end

-- A setting as the player has it, or its default while they haven't touched it.
local function setting(key)
  local value = settings and settings[key]
  if value == nil then return DEFAULTS[key] end
  return value
end

local function duration(seconds)
  local m = floor(seconds / 60)
  if m < 1 then return "under a minute" end
  if m < 60 then return m .. " min" end
  return format("%d h %d min", floor(m / 60), m % 60)
end

-- Resting (an inn or a city), out of combat, alive, on the ground and in the
-- open world: a reload here costs nothing but the loading screen.
local function calm()
  if not IsResting() then return false end
  if InCombatLockdown() or UnitAffectingCombat("player") then return false end
  if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return false end
  if IsInInstance() then return false end
  if WJ.gameCall("C_PetBattles", "IsInBattle") then return false end
  return true
end

-- Saving is a reload; the flag survives it, so the interface that comes back says
-- so. Refused while the game failed to load the file back (WJ.savesNotLoaded),
-- when a reload would replace the recording on disk.
local save = WJ.attempt("save", function()
  if InCombatLockdown() then
    print(PREFIX .. "can't reload the interface in combat; try again when the fight is over.")
    return
  end
  if WJ.savesNotLoaded then
    print(PREFIX .. "not reloading: the game didn't load the earlier recording at the last reload, and a reload now would replace it. Copy the file out of SavedVariables first.")
    return
  end
  WidsithUI.saving = true
  ReloadUI()
end)

-- An emote when the recording is saved, off by default. It hooks every reload,
-- since each one writes the file, at most once a minute (the time kept in
-- WidsithUI, which outlives the reload), and never in combat, in an instance or
-- while the game forbids addons to send chat.
local EMOTES = {
  "scribbles some notes in their Widsith journal.",
  "dates a fresh page in their Widsith journal.",
  "jots down the day's travels in their Widsith journal.",
  "blots the ink dry in their Widsith journal.",
}
local EMOTE_GAP = 60 -- seconds between two emotes, at the least

local function emoteOnSave()
  if setting("emote") ~= true or not WJ.isRecording() then return end
  if InCombatLockdown() or UnitAffectingCombat("player") or IsInInstance() then return end
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
  if type(SendChatMessage) ~= "function" then return end
  local now = time()
  if WidsithUI.emotedAt and now - WidsithUI.emotedAt < EMOTE_GAP then return end
  if pcall(SendChatMessage, EMOTES[math.random(#EMOTES)], "EMOTE") then WidsithUI.emotedAt = now end
end

---------------------------------------------------------------------------
-- The reminder
---------------------------------------------------------------------------

local function hideBubble()
  if bubble then bubble:Hide() end
end

local function placeBubble()
  bubble:ClearAllPoints()
  local _, y = icon:GetCenter()
  if y and y < UIParent:GetHeight() / 2 then
    bubble:SetPoint("BOTTOMRIGHT", icon, "TOPRIGHT", 0, 4)
  else
    bubble:SetPoint("TOPRIGHT", icon, "BOTTOMRIGHT", 0, -4)
  end
end

local function updateBubbleText()
  bubble.title:SetText("Recording unsaved for " .. duration(WJ.secondsSinceSave()))
  bubble:SetHeight(bubble.title:GetStringHeight() + bubble.body:GetStringHeight() + 24)
end

local function createBubble()
  bubble = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
  bubble:SetFrameStrata("HIGH")
  bubble:SetClampedToScreen(true)
  bubble:SetWidth(250)
  bubble:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  bubble:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
  bubble:SetBackdropBorderColor(0.6, 0.6, 0.6)

  bubble.title = bubble:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  bubble.title:SetPoint("TOPLEFT", 10, -9)
  bubble.title:SetWidth(216)
  bubble.title:SetJustifyH("LEFT")

  bubble.body = bubble:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  bubble.body:SetPoint("TOPLEFT", bubble.title, "BOTTOMLEFT", 0, -5)
  bubble.body:SetWidth(230)
  bubble.body:SetJustifyH("LEFT")
  bubble.body:SetText("Click here to save it. Saving reloads the interface: a few seconds of loading screen, then you carry on.")

  local close = CreateFrame("Button", nil, bubble, "UIPanelCloseButton")
  close:SetSize(20, 20)
  close:SetPoint("TOPRIGHT", 1, 1)
  close:SetScript("OnClick", hideBubble)

  bubble:SetScript("OnClick", save)
  bubble:Hide()
end

local function showBubble(forced)
  bubbleForced = forced
  if not bubble then createBubble() end
  placeBubble()
  updateBubbleText()
  bubble:Show()
  lastReminder = GetTime()
  bubbleHideAt = lastReminder + SHOW_FOR
end

---------------------------------------------------------------------------
-- The flame
---------------------------------------------------------------------------

-- The flame is one outline in nested layers from its base, dark to light: four,
-- or three when small. Each layer is a white cell of one strip, coloured here, so
-- one texture serves lit, dimmed and out; Large has a strip of bigger cells.
local STRIP, STRIP_LARGE = MEDIA .. "flame", MEDIA .. "flame-large"
local STRIP_CELLS = 8
local FOUR  = { cells = { 0, 1, 2, 3 }, colours = { "b9521a", "e08a2b", "f4b04a", "fff4d6" } }
local THREE = { cells = { 0, 4, 5 },    colours = { "b9521a", "f4b04a", "fff4d6" } }
local OUT   = { cells = { 0, 2 },       colours = { "6f6a72", "4d4954" } }
local FOUR_FROM = 24          -- flame height in px from which four layers are drawn
local FLAME = 0.8             -- the flame's box as a share of the disc
local BOTTOM = 0.88           -- where the box's bottom sits, down the disc
local EMBER = 0.18            -- the flame's share of its height when burnt down
local HALO = "f4b04a"         -- the radiate halo's colour
local BREATHE = 2.1           -- seconds out (and the same back)
local RING_ATLAS = "UI-HUD-Minimap-Frame-Cycle"
local DISC = MEDIA .. "disc"

-- Sizes offered in the menu, relative to the day/night indicator; Small matches it.
local SIZES = {
  { 1,   "Small" },
  { 1.4, "Medium" },
  { 1.8, "Large" },
}
local LARGE = 1.8     -- from here up, the large strip
local disc, layers, halos, embers, glow, pulse
local discSize       -- the disc's size in the icon's units
local dueSince
local wasRecording

local function rgb(hex)
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

local function size()
  return setting("iconSize")
end

local function animate()
  return setting("animate")
end

-- A cell of the strip onto a texture.
local function setCell(texture, cell)
  texture:SetTexture(size() >= LARGE and STRIP_LARGE or STRIP)
  texture:SetTexCoord(cell / STRIP_CELLS, (cell + 1) / STRIP_CELLS, 0, 1)
end

-- The flame's full height in the icon's units, and which drawing it gets.
local function flameHeight()
  return discSize * FLAME
end

local function drawing()
  if not WJ.isRecording() then return OUT end
  return flameHeight() * size() >= FOUR_FROM and FOUR or THREE
end

-- How much of the flame is left, from 1 after a save to EMBER after BURN_TIME.
-- Full when reminders are off, nothing is recording, or WJ.savesNotLoaded.
local function gauge()
  if not WJ.isRecording() or not setting("remind") or WJ.savesNotLoaded then return 1 end
  local burnt = min(1, WJ.secondsSinceSave() / BURN_TIME)
  return 1 - burnt * (1 - EMBER)
end

local function due()
  return WJ.isRecording() and setting("remind") and not WJ.savesNotLoaded and WJ.secondsSinceSave() >= BURN_TIME
end

-- Lay the layers out on the base for the size, drawing and gauge, dimmer as it shrinks.
local function layoutFlame()
  local d = drawing()
  local g = gauge()
  local h = flameHeight() * g
  local bright = 0.5 + 0.5 * (g - EMBER) / (1 - EMBER)
  if d == OUT then bright = 1 end
  for i, layer in ipairs(layers) do
    local cell = d.cells[i]
    if cell then
      setCell(layer, cell)
      local r, gr, b = rgb(d.colours[i])
      layer:SetVertexColor(r * bright, gr * bright, b * bright)
      layer:SetSize(h, h)
      layer:Show()
    else
      layer:Hide()
    end
  end
end

-- Breathing: the inner layers swell a little and settle; the outer holds still.
local function setBreathing(on)
  for i, layer in ipairs(layers) do
    local group = layer.breathe
    if on and layer:IsShown() and i > 1 then
      if not group:IsPlaying() then
        -- The heart a moment behind the layer before it.
        if i == #layers then
          C_Timer.After(0.3, WJ.guard("breathe", function() if layer.breathe and not layer.breathe:IsPlaying() and layer:IsShown() then layer.breathe:Play() end end))
        else
          group:Play()
        end
      end
    elseif group:IsPlaying() then
      group:Stop()
    end
  end
end

-- The flare when recording starts: two halos grow and fade while the layers swell,
-- played late enough that a fading loading screen doesn't hide it.
local FLARE_DELAY = 0.8

local function radiate()
  if not icon or not icon:IsShown() or not animate() or not WJ.isRecording() then return end
  for _, halo in ipairs(halos) do
    setCell(halo, 0)
    local h = flameHeight()
    halo:SetSize(h, h)
    halo.anim:Stop()
    halo.anim:Play()
  end
  for _, layer in ipairs(layers) do
    if layer:IsShown() then
      layer.flare:Stop()
      layer.flare:Play()
    end
  end
end

-- The spark when the flame is pointed at: the inner layers flare and two embers
-- lift off the tip, at (39, 3) of the outline's 64-unit box.
local function spark()
  if not animate() or not WJ.isRecording() then return end
  local h = flameHeight() * gauge()
  for i, layer in ipairs(layers) do
    if i > 1 and layer:IsShown() then
      layer.spark:Stop()
      layer.spark:Play()
    end
  end
  for _, ember in ipairs(embers) do
    ember:ClearAllPoints()
    ember:SetPoint("CENTER", layers[1], "BOTTOM", h * (39 - 32) / 64, h * (64 - 3) / 64)
    ember:SetSize(max(2, h * 0.08), max(2, h * 0.08))
    ember.anim:Stop()
    ember.anim:Play()
  end
end

local function updateIcon()
  if not icon then return end
  local recording = WJ.isRecording()
  -- A reminder shown on demand (/widsith remind) lights the glow too, so both can be seen at once.
  local isDue = due() or (bubbleForced and bubble and bubble:IsShown() and recording)
  layoutFlame()
  local shade = recording and 1 or 0.55
  disc:SetVertexColor(shade, shade, shade)
  setBreathing(recording and animate() and icon:IsShown())
  -- Due: the glow pulses, or holds still with animations off.
  if isDue then
    glow:Show()
    if animate() then
      if not pulse:IsPlaying() then pulse:Play() end
    elseif pulse:IsPlaying() then
      pulse:Stop()
      glow:SetAlpha(0.7)
    elseif not dueSince then
      glow:SetAlpha(0.7)
    end
    dueSince = dueSince or GetTime()
  else
    dueSince = nil
    pulse:Stop()
    glow:Hide()
  end
  -- Recording that has just begun: the flare follows the lit flame a moment later.
  if recording and wasRecording == false then
    C_Timer.After(FLARE_DELAY, WJ.guard("flare", radiate))
  end
  wasRecording = recording
end

-- Where the day/night indicator exists, the icon takes its parent, scale and
-- layer, so it follows the minimap through Edit Mode, times the chosen size.
local function diel()
  return MinimapCluster and MinimapCluster.DielFrame
end

local function matchDiel()
  local d = diel()
  if d then
    icon:SetParent(d:GetParent())
    icon:SetFrameStrata(d:GetFrameStrata())
    icon:SetFrameLevel(d:GetFrameLevel())
  end
  icon:SetScale((d and d:GetScale() or 1) * size())
  layoutFlame()
end

-- A saved position is kept in UIParent's units, so it stays put whatever the
-- icon's own scale; a SetPoint offset is in the icon's units.
local function toIconUnits()
  return UIParent:GetEffectiveScale() / icon:GetEffectiveScale()
end

-- On the ring (the default) the icon's place is an angle round the minimap's
-- centre, worked in screen pixels so neither frame's scale matters.
local function onRing()
  return setting("onRing") and Minimap ~= nil
end

local function screenCenter(frame)
  local x, y = frame:GetCenter()
  if not x then return nil end
  local s = frame:GetEffectiveScale()
  return x * s, y * s
end

-- Radius in screen pixels, and the default angle: the dial's own, mirrored left to right.
local function ringGeometry()
  local mx, my = screenCenter(Minimap)
  local d = diel()
  if mx and d then
    local dx, dy = screenCenter(d)
    if dx then
      return math.sqrt((dx - mx) ^ 2 + (dy - my) ^ 2), math.atan2(dy - my, mx - dx)
    end
  end
  return (Minimap:GetWidth() / 2 + 10) * Minimap:GetEffectiveScale(), math.rad(135)
end

local function placeIcon()
  icon:ClearAllPoints()
  local p = settings.point
  local d = diel()
  if onRing() and screenCenter(Minimap) then
    local radius, defaultAngle = ringGeometry()
    local angle = settings.ringAngle or defaultAngle
    local k = icon:GetEffectiveScale()
    icon:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius / k, math.sin(angle) * radius / k)
  elseif p then
    local k = toIconUnits()
    icon:SetPoint(p[1], UIParent, p[2], p[3] * k, p[4] * k)
  elseif d and d:GetNumPoints() > 0 then
    -- The indicator's offsets are in its units; ours are divided by the chosen size.
    local point, relativeTo, relativePoint, x, y = d:GetPoint(1)
    icon:SetPoint(point, relativeTo, relativePoint, -(x or 0) / size(), (y or 0) / size())
  elseif MinimapCluster then
    icon:SetPoint("TOPRIGHT", MinimapCluster, "TOPLEFT", -6, -6)
  else
    icon:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -240, -12)
  end
end

function WJ.iconShown()
  return settings ~= nil and setting("shown")
end

function WJ.setIconShown(shown)
  if not settings then return end
  settings.shown = shown
  if icon then
    icon:SetShown(shown)
    updateIcon()
  end
  if shown then
    say("icon shown.")
  else
    say("icon hidden. Bring it back from Options, AddOns, " .. WJ.NAME .. ", or with /widsith icon.")
  end
end

-- Three lines: the name, the state, what the buttons do.
local function showTooltip(self)
  spark()
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
  GameTooltip:SetText(WJ.NAME)
  if WJ.isRecording() then
    if WJ.savesNotLoaded then
      GameTooltip:AddLine("Recording. Don't reload: the earlier recording didn't load, so copy the file out first.", 1, 0.3, 0.3, true)
    elseif due() then
      GameTooltip:AddLine("Recording, " .. duration(WJ.secondsSinceSave()) .. " unsaved. Time to save.", 1, 0.82, 0)
    else
      GameTooltip:AddLine("Recording, " .. duration(WJ.secondsSinceSave()) .. " unsaved.", 1, 1, 1)
    end
  elseif WJ.isPaused() then
    GameTooltip:AddLine("Stopped.", 1, 1, 1)
  else
    GameTooltip:AddLine("Not recording.", 1, 0.3, 0.3)
  end
  local click = WJ.savesNotLoaded and "" or "Click to save. "
  GameTooltip:AddLine(click .. "Right-click for options.", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

-- The settings, as the menu here and the options panel (Options.lua) change
-- them; every change goes through here, so the icon follows at once.
local function setOnRing(on)
  if onRing() and not on then
    -- Leaving the ring: stay exactly where it is, now free to drag anywhere.
    local x, y = screenCenter(icon)
    local s = UIParent:GetEffectiveScale()
    if x then settings.point = { "CENTER", "BOTTOMLEFT", x / s, y / s } end
  end
  settings.onRing = on
  placeIcon()
end

WJ.ICON_SIZES = SIZES

function WJ.getIconSetting(key)
  if not settings then return nil end
  if key == "onRing" then return onRing() end
  if key == "iconSize" then return size() end
  return setting(key)
end

function WJ.setIconSetting(key, value)
  if not settings then return end
  if key == "shown" then
    if value ~= setting("shown") then WJ.setIconShown(value) end
    return
  end
  if not icon then
    settings[key] = value
    return
  end
  if key == "onRing" then
    setOnRing(value)
  elseif key == "iconSize" then
    settings.iconSize = value
    matchDiel()
    placeIcon()
  else
    settings[key] = value
    if key == "remind" and not value then hideBubble() end
    -- The glow's pulse is an animation too; with none, it holds still.
    if key == "animate" and not value and pulse:IsPlaying() then pulse:Stop(); glow:SetAlpha(0.7) end
  end
  updateIcon()
end

WJ.saveNow = save

-- The player's action, from the menu or the settings panel.
WJ.togglePause = WJ.attempt("pause", function()
  if WJ.isRecording() then
    WJ.pause()
    hideBubble()
  elseif WJ.isPaused() then
    WJ.resume()
  end
  updateIcon()
end)

-- The player's action, a right click on the icon.
local openMenu = WJ.attempt("menu", function(self)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  GameTooltip:Hide()
  MenuUtil.CreateContextMenu(self, function(_, root)
    root:CreateTitle(WJ.NAME)
    if WJ.isRecording() then
      root:CreateButton("Stop recording", WJ.togglePause)
    elseif WJ.isPaused() then
      root:CreateButton("Start recording", WJ.togglePause)
    end
    local function checkbox(menu, name, key)
      menu:CreateCheckbox(name,
        function() return WJ.getIconSetting(key) end,
        function() WJ.setIconSetting(key, not WJ.getIconSetting(key)) end)
    end
    checkbox(root, "Remind me to save", "remind")
    checkbox(root, "Emote when saving", "emote")
    local shots = root:CreateButton("Screenshots")
    checkbox(shots, "Screenshot highlights", "screenshots")
    checkbox(shots, "Show chat in the pictures", "shotsChat")
    -- The icon's own settings, the sizes under a divider.
    local iconMenu = root:CreateButton("Icon")
    checkbox(iconMenu, "Animations", "animate")
    checkbox(iconMenu, "Attach to minimap", "onRing")
    checkbox(iconMenu, "Lock position", "locked")
    if iconMenu.CreateDivider then iconMenu:CreateDivider() end
    for _, entry in ipairs(SIZES) do
      iconMenu:CreateRadio(entry[2],
        function() return size() == entry[1] end,
        function() WJ.setIconSetting("iconSize", entry[1]) end)
    end
    root:CreateButton("Hide icon", function() WJ.setIconShown(false) end)
  end)
end)

-- A scale animation about the base, once, in a group of its own.
local function scaleFromBase(group, from, to, seconds, smoothing)
  local anim = group:CreateAnimation("Scale")
  anim:SetOrigin("BOTTOM", 0, 0)
  anim:SetScaleFrom(from, from)
  anim:SetScaleTo(to, to)
  anim:SetDuration(seconds)
  anim:SetSmoothing(smoothing)
  return anim
end

local function createFlame()
  -- The disc first, the flame's layers on it from the outside in, and the two
  -- halos between, so the flare shows behind the flame.
  disc = icon:CreateTexture(nil, "ARTWORK", nil, -3)
  disc:SetTexture(DISC)
  halos = {}
  for i = 1, 2 do
    local halo = icon:CreateTexture(nil, "ARTWORK", nil, -2)
    halo:SetVertexColor(rgb(HALO))
    halo:SetAlpha(0)
    halo:SetPoint("BOTTOM", disc, "BOTTOM", 0, discSize * (1 - BOTTOM))
    local group = halo:CreateAnimationGroup()
    local grow = scaleFromBase(group, 1, 2.2, 1.2, "OUT")
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.7)
    fade:SetToAlpha(0)
    fade:SetDuration(1.2)
    fade:SetSmoothing("OUT")
    if i == 2 then
      grow:SetStartDelay(0.35)
      fade:SetStartDelay(0.35)
    end
    halo.anim = group
    halos[i] = halo
  end
  layers = {}
  for i = 1, 4 do
    local layer = icon:CreateTexture(nil, "ARTWORK", nil, i - 1)
    layer:SetPoint("BOTTOM", disc, "BOTTOM", 0, discSize * (1 - BOTTOM))
    -- Breathing: the second layer swells to 1.04, the inner ones to 1.1, and back.
    local breathe = layer:CreateAnimationGroup()
    breathe:SetLooping("BOUNCE")
    scaleFromBase(breathe, 1, i == 2 and 1.04 or 1.1, BREATHE, "IN_OUT")
    layer.breathe = breathe
    -- The flare at relighting: swollen, settling.
    local flare = layer:CreateAnimationGroup()
    local f = scaleFromBase(flare, 1.15, 1, 0.6, "OUT")
    f:SetStartDelay(0.05 * (i - 1))
    layer.flare = flare
    -- The spark when pointed at: a quick swell and a slower settling.
    local sparkGroup = layer:CreateAnimationGroup()
    local up = scaleFromBase(sparkGroup, 1, i == 2 and 1.08 or 1.15, 0.32, "OUT")
    up:SetOrder(1)
    up:SetStartDelay(0.05 * math.max(0, i - 2))
    local down = scaleFromBase(sparkGroup, i == 2 and 1.08 or 1.15, 1, 0.48, "IN_OUT")
    down:SetOrder(2)
    layer.spark = sparkGroup
    layers[i] = layer
  end
  -- The embers: two small diamonds drifting up from the tip as they fade.
  embers = {}
  local drift = { { 0.45, 1.2, 1.1, 0, "f4b04a" }, { -0.4, 1.3, 1.2, 0.35, "fff4d6" } }
  for i, d in ipairs(drift) do
    local ember = icon:CreateTexture(nil, "ARTWORK", nil, 5)
    ember:SetColorTexture(rgb(d[5]))
    ember:SetRotation(math.rad(45))
    ember:SetAlpha(0)
    local group = ember:CreateAnimationGroup()
    local move = group:CreateAnimation("Translation")
    move:SetOffset(d[1] * discSize * 0.3, d[2] * discSize * 0.3)
    move:SetDuration(d[3])
    move:SetSmoothing("OUT")
    move:SetStartDelay(d[4])
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(d[3])
    fade:SetSmoothing("IN")
    fade:SetStartDelay(d[4])
    ember.anim = group
    embers[i] = ember
  end
end

local function createIcon()
  icon = CreateFrame("Button", "WidsithRecordingIcon", UIParent)
  icon:SetFrameStrata("MEDIUM")
  icon:SetClampedToScreen(true)
  icon:SetMovable(true)
  icon:RegisterForDrag("LeftButton")
  icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  -- The ring is asked for by its element name, as the day/night indicator does,
  -- so the client picks a larger drawing when the interface is scaled up; the
  -- member name (…-c60) would pin the small one and blur. Retail has no such
  -- ring and gets the classic minimap-button ring.
  local ring = icon:CreateTexture(nil, "OVERLAY")
  local highlight = icon:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  highlight:SetBlendMode("ADD")
  if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(RING_ATLAS) then
    icon:SetSize(42, 42)
    ring:SetAtlas(RING_ATLAS)
    ring:SetAllPoints()
    discSize = 33
    createFlame()
    disc:SetSize(discSize, discSize)
    disc:SetPoint("CENTER")
    highlight:SetSize(40, 40)
    highlight:SetPoint("CENTER")
  else
    -- The classic minimap button; its ring sits in the top left of its texture.
    icon:SetSize(31, 31)
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(50, 50)
    ring:SetPoint("TOPLEFT")
    discSize = 18
    createFlame()
    disc:SetSize(discSize, discSize)
    disc:SetPoint("TOPLEFT", 7, -6)
    highlight:SetAllPoints()
  end
  -- The glow sits behind the ring and reaches a little past it.
  glow = icon:CreateTexture(nil, "BACKGROUND")
  glow:SetTexture(MEDIA .. "glow")
  glow:SetSize(icon:GetWidth() * 1.45, icon:GetHeight() * 1.45)
  glow:SetPoint("CENTER", disc, "CENTER")
  glow:Hide()
  pulse = glow:CreateAnimationGroup()
  pulse:SetLooping("BOUNCE")
  local fade = pulse:CreateAnimation("Alpha")
  fade:SetFromAlpha(0.25)
  fade:SetToAlpha(1)
  fade:SetDuration(1.2)
  fade:SetSmoothing("IN_OUT")

  -- Round the ring: follow the cursor's angle from the minimap's centre while dragged.
  local function followCursor()
    local mx, my = screenCenter(Minimap)
    if not mx then return end
    local cx, cy = GetCursorPosition()
    settings.ringAngle = math.atan2(cy - my, cx - mx)
    placeIcon()
  end
  -- The icon's scripts run under the guard like every handler.
  icon:SetScript("OnDragStart", WJ.guard("iconDrag", function(self)
    if setting("locked") then return end
    if onRing() then
      self:SetScript("OnUpdate", WJ.guard("iconDrag", followCursor))
    else
      self:StartMoving()
    end
  end))
  icon:SetScript("OnDragStop", WJ.guard("iconDrag", function(self)
    if onRing() then
      self:SetScript("OnUpdate", nil)
      if bubble and bubble:IsShown() then placeBubble() end
      return
    end
    self:StopMovingOrSizing()
    -- Kept with the settings, not in the client's layout cache.
    self:SetUserPlaced(false)
    local point, _, relativePoint, x, y = self:GetPoint(1)
    local k = toIconUnits()
    settings.point = { point, relativePoint, x / k, y / k }
    if bubble and bubble:IsShown() then placeBubble() end
  end))
  -- A left click saves, the right button opens the menu; a drag is never a click.
  icon:SetScript("OnClick", WJ.guard("iconClick", function(self, button)
    if button == "RightButton" then
      openMenu(self)
    else
      GameTooltip:Hide()
      save()
    end
  end))
  icon:SetScript("OnEnter", WJ.guard("iconTooltip", showTooltip))
  icon:SetScript("OnLeave", WJ.guard("iconTooltip", function() GameTooltip:Hide() end))

  -- Modern clients snap textures to the pixel grid, which steps the edges of
  -- scaled ones, so the icon's parts draw unsnapped.
  local parts = { disc, ring, highlight, glow, halos[1], halos[2], embers[1], embers[2] }
  for _, layer in ipairs(layers) do parts[#parts + 1] = layer end
  for _, t in ipairs(parts) do
    if t.SetSnapToPixelGrid then
      t:SetSnapToPixelGrid(false)
      t:SetTexelSnappingBias(0)
    end
  end

  matchDiel()
  placeIcon()
  -- The minimap's layout may settle a moment after login; place it again then.
  C_Timer.After(1, WJ.guard("iconPlace", placeIcon))
  -- Edit Mode rescales the minimap and moves the indicator with it; follow it.
  if diel() and type(MinimapCluster.SetEditModeScale) == "function" then
    hooksecurefunc(MinimapCluster, "SetEditModeScale", WJ.guard("iconScale", function()
      matchDiel()
      if onRing() or not settings.point then placeIcon() end
    end))
  end
  icon:SetShown(setting("shown"))
  wasRecording = WJ.isRecording()
  updateIcon()
end

---------------------------------------------------------------------------
-- The check, every few seconds: the flame burns down, the reminder shows
---------------------------------------------------------------------------

local function check()
  if not icon then return end
  updateIcon()
  if bubble and bubble:IsShown() then
    local expired = GetTime() >= bubbleHideAt and not bubble:IsMouseOver()
    local unwanted = not bubbleForced and (not setting("remind") or not calm())
    if unwanted or expired then
      hideBubble()
    else
      updateBubbleText()
    end
    return
  end
  if due() and GetTime() - lastReminder >= REMIND_GAP and calm() then
    showBubble()
  end
end

-- /widsith remind: show the reminder now, whatever the time or place.
function WJ.showReminder()
  if icon then showBubble(true) updateIcon() end
end

-- The addon compartment entry (TOC: AddonCompartmentFunc) opens the options
-- panel, or on a client without one shows or hides the icon.
Widsith_OnAddonCompartmentClick = WJ.attempt("compartment", function()
  if WJ.openOptions then
    WJ.openOptions()
  else
    WJ.setIconShown(not WJ.iconShown())
  end
end)

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", WJ.guard("icon", function(self, event, ...)
  if event == "ADDON_LOADED" then
    if (...) ~= ADDON_NAME then return end
    settings = WJ.loadSettings()
    -- A place saved for an older icon style lands elsewhere: start afresh, once.
    if settings.iconStyle ~= 4 then
      settings.point = nil
      settings.iconStyle = 4
    end
    self:UnregisterEvent("ADDON_LOADED")
  elseif event == "PLAYER_LOGIN" then
    WJ.guard("icon", createIcon)()
    C_Timer.NewTicker(CHECK_EVERY, WJ.guard("saveReminder", check))
    -- The recorder calls this when a session starts: the flame lights then.
    WJ.onRecordingStarted = updateIcon
    if type(ReloadUI) == "function" then hooksecurefunc("ReloadUI", WJ.guard("saveEmote", emoteOnSave)) end
    self:UnregisterEvent("PLAYER_LOGIN")
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- A reload asked for as a save: say so. The flame is lit by the recorder's
    -- call, since this frame may hear the event first.
    local _, isReload = ...
    if isReload and WidsithUI.saving then
      WidsithUI.saving = nil
      say("saved.")
    end
  end
end))
