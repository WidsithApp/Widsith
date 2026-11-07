-- Widsith — what the player is told once
--
-- The first time the addon runs on an account, a welcome: that it is
-- recording, where the replay is, that the uploader exists, where to find
-- more. After that, the first load of a new version says so and lists what
-- changed that a player would notice, in a few words each. Either is one chat
-- message under the emblem, a short list, not a line of chat per point. It is
-- said in the place of the recorder's own "is recording" line at that load:
-- the recorder asks here as it decides that line (WJ.tellNews), rather than
-- this file hearing the event itself, since the game promises nothing about
-- the order frames hear an event in. Said once per account, kept in
-- WidsithAccount; through the recorder's channel, so "Show chat messages" off
-- keeps it quiet. The About page lists the same notes.

local _, WJ = ...

local NAME = "|cff33ff99" .. WJ.NAME .. "|r"

-- Either message is a block of its own in chat: a rule above and below, each
-- a message of its own since the game indents every line of a message after
-- its first; between them one message with the flame on its first line, a
-- blank line between its points, each point behind a bullet in the flame's
-- colour.
local BULLET = "  |cfff4b04a\226\128\162|r "   -- a bullet, as its UTF-8 bytes: the game's Lua has no \u escape

-- The rule is as wide as the chat window it lands in: its width over the width
-- of one dash in its font, less the frame's insets and the scroll bar's room,
-- rounded down so it never wraps. Forty dashes when any of that can't be read.
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

-- The rule in the flame's colours, dark orange through gold to cream, left to
-- right: each dash under its own colour. Colour codes take no width.
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

-- What changed that a player would notice, by version, a few words each. The
-- About page lists them all. Chat gets only the ones marked for it: what a
-- player may need to act on, or what changes the way things work. A change
-- they will simply see, or can do nothing about, stays off the message. A
-- version with no entry is announced alone.
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

-- Called by the recorder as a load begins, where it would say that it is
-- recording: says the welcome or the version's news if the account has yet to
-- see this version, and answers whether it said anything, so the recorder's
-- own line is left out when it did. A new version is usually installed
-- mid-session and reloaded, so a reload counts as much as a login.
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
