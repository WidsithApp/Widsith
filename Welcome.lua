-- Widsith — what the player is told once
--
-- A welcome the first time the addon runs on an account, then the news of each new
-- version, as one chat message in place of the recorder's "is recording" line. The
-- recorder asks for it (WJ.tellNews), since the order frames hear an event in isn't
-- promised. What has been seen is kept in WidsithAccount.

local _, WJ = ...

local NAME = "|cff33ff99" .. WJ.NAME .. "|r"

-- A message is a block with a rule above and below; each rule is a message of its own,
-- since the game indents every line of a message after its first.
local BULLET = "  |cfff4b04a\226\128\162|r "   -- a bullet, as its UTF-8 bytes: the game's Lua has no \u escape

-- As many dashes as fit the chat window without wrapping, or forty when that can't be read.
local RULE_FALLBACK = 40
local RULE_INSET = 24
local function ruleLength()
  local frame = DEFAULT_CHAT_FRAME or ChatFrame1
  if type(frame) ~= "table" or type(frame.GetWidth) ~= "function" or type(frame.GetFont) ~= "function" then return RULE_FALLBACK end
  local ok, n = pcall(function()
    local width = frame:GetWidth()
    local path, size, flags = frame:GetFont()
    if not (width and path and size) then return nil end
    local probe = UIParent:CreateFontString(nil, "ARTWORK")
    probe:SetFont(path, size, flags)
    probe:SetText("-")
    local dash = probe:GetStringWidth()
    probe:Hide()
    if not dash or dash <= 0 then return nil end
    return math.floor((width - RULE_INSET) / dash)
  end)
  if not ok or not n then return RULE_FALLBACK end
  return math.max(20, math.min(120, n))
end

-- The rule shades through the flame's colours, dash by dash.
local FLAME = { { 0xb9, 0x52, 0x1a }, { 0xf4, 0xb0, 0x4a }, { 0xff, 0xf4, 0xd6 } }
local function flameAt(t)
  local span = #FLAME - 1
  local i = math.min(span, math.floor(t * span) + 1)
  local a, b, k = FLAME[i], FLAME[i + 1], t * span - (i - 1)
  local r, g, bl = a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k
  return string.format("|cff%02x%02x%02x", math.floor(r + 0.5), math.floor(g + 0.5), math.floor(bl + 0.5))
end
local function rule()
  local n = ruleLength()
  local parts = {}
  for i = 1, n do parts[i] = flameAt((i - 1) / math.max(1, n - 1)) .. "-|r" end
  return table.concat(parts)
end

local WELCOME = {
  "Thank you for installing " .. NAME .. "!",
  BULLET .. "Your gameplay is now being recorded, view it or share it by uploading the file at widsith.app",
  BULLET .. "It is automatically saved whenever you log off, or reload the interface. Click the " .. WJ.ICON .. " icon to manually trigger a reload",
  BULLET .. "View the addon options for additional details and support information",
  BULLET .. "A lightweight companion app is available on widsith.app that will automatically upload your progress for you whenever you save",
  "More details @ widsith.app",
}

local function block(points)
  local line = rule()
  WJ.say(line, true)
  WJ.say(WJ.EMBLEM .. " " .. table.concat(points, "\n\n"), true)
  WJ.say(line .. "\n", true)
end

-- What changed, by version. The About page lists every note; chat only those marked chat,
-- for what a player may act on or what changes how things work.
local NOTES = {
  ["0.7.0"] = {
    { "Screenshot highlights, and the include chat in screenshots options are now enabled by default", chat = true },
    { "Changes you make to the general Widsith configuration are now shared across all your characters", chat = true },
    { "Pause and Resume have been changed to Stop and Start to better reflect their behaviour", chat = true },
    { "Characters that have had their recording stopped, now will not start again until manually started.", chat = true },
    { "The save reminder comes after 45 minutes of unsaved play" },
    { "The icon's settings are under Icon in the menu, and Show chat messages is in the options window" },
  },
}

-- The notes for this version, for the About page.
function WJ.whatsNew()
  local notes = NOTES[WJ.VERSION]
  if not notes then return nil end
  local out = {}
  for _, note in ipairs(notes) do out[#out + 1] = note[1] end
  return out
end

-- Says the welcome or this version's news if the account hasn't seen it, at a login or a
-- reload alike, and answers whether it said anything.
function WJ.tellNews()
  local account = WidsithAccount
  if not account or account.seenVersion == WJ.VERSION then return false end
  local version = WJ.VERSION
  if account.seenVersion == nil and not account.usedBefore then
    block(WELCOME)
  else
    local points = { NAME .. " " .. version .. " is installed." }
    if NOTES[version] then points[#points + 1] = "What's new:" end
    for _, note in ipairs(NOTES[version] or {}) do
      if note.chat then points[#points + 1] = BULLET .. note[1] end
    end
    block(points)
  end
  account.seenVersion = version
  return true
end
