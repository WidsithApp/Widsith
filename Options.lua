-- Widsith — the options panel
--
-- The same settings as the icon's menu, under Options → AddOns → Widsith, so a
-- hidden icon can always be brought back, and an About page beside it with the
-- version, what the addon does and where recordings are replayed. Both are
-- built with the game's own settings panel, so they look like the rest of it
-- and its search finds them. The settings themselves live in WidsithUI and are
-- read and changed through the icon's own functions, so a change here shows on
-- the icon at once, and the reverse.

local ADDON_NAME, WJ = ...

local SITE = "https://widsith.app"
local DISCORD = "https://discord.gg/532DstKnNE"
local CONTACT = "info@widsith.app"

local category

-- What each setting is when nothing has been changed: the panel's Defaults
-- button puts these back.
local DEFAULTS = { shown = true, remind = true, animate = true, chat = true, emote = false, onRing = true, locked = false, iconSize = 1 }

local function checkbox(name, key, tooltip)
  local setting = Settings.RegisterProxySetting(category, "WIDSITH_" .. key:upper(), Settings.VarType.Boolean, name,
    DEFAULTS[key],
    function() return WJ.getIconSetting(key) end,
    function(value) WJ.setIconSetting(key, value) end)
  Settings.CreateCheckbox(category, setting, tooltip)
end

local function sizeOptions()
  local container = Settings.CreateControlTextContainer()
  for _, entry in ipairs(WJ.ICON_SIZES) do
    container:Add(entry[1], entry[2])
  end
  return container:GetData()
end

-- The About page: a plain frame the panel shows as a canvas. Short lines
-- under small headings, to be read at a glance, and the addresses in edit
-- boxes so they can be copied (nothing can be opened from inside the game).
local ABOUT = {
  { "What it does", WJ.NAME .. " keeps a record of your character's journey as you play: where you went, what you did and when." },
  { "Saving", "The game writes the recording only when the interface reloads. The icon shrinks the longer you go unsaved; click it to save, which reloads." },
  { "Replaying", "Bring the recording to the website, or let the " .. WJ.NAME .. " uploader send it as you play, and watch the journey on the map." },
  { "Chat command", "/widsith, and /widsith help for the rest." },
}
local LINKS = {
  { "Website", SITE },
  { "Discord", DISCORD },
  { "Email", CONTACT },
}

-- An edit box that holds one address: copyable, not editable.
local function copyBox(parent, text)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(260, 22)
  box:SetAutoFocus(false)
  box:SetText(text)
  box:SetCursorPosition(0)
  box:SetScript("OnTextChanged", function(self, byUser)
    if byUser and self:GetText() ~= text then
      self:SetText(text)
      self:HighlightText()
    end
  end)
  box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return box
end

local function createAbout()
  local frame = CreateFrame("Frame")
  local WIDTH = 540

  local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText(WJ.NAME)

  local version = frame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  version:SetPoint("LEFT", title, "RIGHT", 8, 0)
  version:SetText("version " .. WJ.VERSION)

  local last = title
  for _, entry in ipairs(ABOUT) do
    local head = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    head:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -14)
    head:SetText(entry[1])
    local body = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -3)
    body:SetWidth(WIDTH)
    body:SetJustifyH("LEFT")
    body:SetText(entry[2])
    last = body
  end

  local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -18)
  hint:SetText("Click an address, then press Ctrl-C to copy it.")
  last = hint
  for _, entry in ipairs(LINKS) do
    local label = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -10)
    label:SetWidth(70)
    label:SetJustifyH("LEFT")
    label:SetText(entry[1])
    local box = copyBox(frame, entry[2])
    box:SetPoint("LEFT", label, "RIGHT", 8, 0)
    last = label
  end

  return frame
end

local function createPanel()
  if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then return end
  category = Settings.RegisterVerticalLayoutCategory(WJ.NAME)
  local layout = SettingsPanel:GetLayout(category)

  layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("The icon"))
  checkbox("Show the icon", "shown", "The icon by the minimap. Hidden, it can be brought back here or with /widsith icon.")
  checkbox("Remind me to save", "remind", "The icon shrinks over half an hour of unsaved play, then glows, and a reminder appears when you are resting somewhere safe. Off, the icon stays as it is.")
  checkbox("Animations", "animate", "The icon moves a little while recording, and more when recording starts or when pointed at. Off, nothing moves.")
  checkbox("Attach to minimap", "onRing", "Keep the icon on the minimap's ring, where dragging slides it round. Off, it can be dragged anywhere.")
  checkbox("Lock position", "locked", "The icon can't be dragged.")
  checkbox("Show chat messages", "chat", "Widsith's own news in chat: that it is recording, paused, or saved. A real problem is always said.")
  checkbox("Emote when saving", "emote", "When the recording is saved, the people nearby see an emote such as \"" .. UnitName("player") .. " scribbles some notes in their Widsith journal.\" At most once a minute, and never in combat or in an instance. Off unless you turn it on.")
  local sizeSetting = Settings.RegisterProxySetting(category, "WIDSITH_ICONSIZE", Settings.VarType.Number, "Icon size",
    DEFAULTS.iconSize,
    function() return WJ.getIconSetting("iconSize") end,
    function(value) WJ.setIconSetting("iconSize", value) end)
  Settings.CreateDropdown(category, sizeSetting, sizeOptions, "Small is the size of the day and night dial beside it.")

  layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("The recording"))
  layout:AddInitializer(CreateSettingsButtonInitializer("Save the recording", "Save now",
    function() if WJ.saveNow then WJ.saveNow() end end,
    "Reloads the interface, which is the only way the game writes the file: a few seconds of loading screen, then you carry on. Not in combat.", true))
  layout:AddInitializer(CreateSettingsButtonInitializer("Pause or resume recording", "Pause / Resume",
    function() if WJ.togglePause then WJ.togglePause() end end,
    "Paused, nothing is recorded until you resume, log in again or reload.", true))

  Settings.RegisterCanvasLayoutSubcategory(category, createAbout(), "About")
  -- Registering the category is the last step, as the game's own guide has it.
  Settings.RegisterAddOnCategory(category)
end

function WJ.openOptions()
  if not category then return end
  Settings.OpenToCategory(category:GetID())
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
  WJ.guard("options", createPanel)()
  if not category then WJ.openOptions = nil end
  self:UnregisterEvent("PLAYER_LOGIN")
end)
