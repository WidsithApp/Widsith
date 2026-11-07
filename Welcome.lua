-- Widsith — what the player is told once
--
-- The first time the addon runs on an account, a welcome: what it does, how
-- the recording is saved, where the settings are. After that, the first load
-- of a new version says so and lists what changed that a player would notice,
-- in a few words each. Either is one chat message, its lines under one name,
-- not a line of chat per point. Each is said once per account, kept in
-- WidsithAccount, a few seconds after the recorder's own login line so the two
-- read in order. Through the same channel as the recorder's news, so "Show
-- chat messages" off keeps it quiet. The About page lists the same notes.

local ADDON_NAME, WJ = ...

local DELAY = 3   -- s after entering the world

-- The addon's emblem, drawn in the line at the chat font's height, so the
-- message starts with the icon the text tells the player to click.
local EMBLEM = "|TInterface\\AddOns\\" .. ADDON_NAME .. "\\media\\emblem:16:16|t"
local NAME = "|cff33ff99" .. WJ.NAME .. "|r"

local WELCOME = {
  EMBLEM .. " " .. NAME .. " is now recording. Thank you for installing it.",
  "The recording is saved whenever you log out or reload. Click the icon by the minimap to save at any time.",
  "To watch the replay, drop the file Widsith.lua on widsith.app, or let the Widsith Uploader from the same site keep it in sync for you.",
  "More, and where to find help, is under Options, AddOns, Widsith.",
}

-- What changed that a player would notice, by version, a few words each. The
-- About page lists them all. Chat gets only the ones marked for it: what a
-- player may need to act on, or what changes the way things work. A change
-- they will simply see, or can do nothing about, stays off the message. A
-- version with no entry is announced alone.
local NOTES = {
  ["0.7.0"] = {
    { "Screenshot highlights on by default", chat = true },
    { "Chat shown in the screenshots by default", chat = true },
    { "Settings shared by all your characters", chat = true },
    { "A paused character stays paused until you resume it", chat = true },
    { "The save reminder at 45 minutes" },
    { "The icon's settings under Icon in the menu" },
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

-- Lines as one message with the emblem and the name as its heading, through
-- the recorder's channel, which honours "Show chat messages"; the heading is
-- the message's own, so no prefix is put before it.
local function announce(lines)
  WJ.say(table.concat(lines, "\n"), true)
end

local function tell()
  local account = WidsithAccount
  if not account then return end
  local version = WJ.VERSION
  if account.seenVersion == version then return end
  if account.seenVersion == nil and not account.usedBefore then
    announce(WELCOME)
  else
    local lines = { EMBLEM .. " " .. NAME .. " " .. version .. " is installed." .. (NOTES[version] and " What's new:" or "") }
    for _, note in ipairs(NOTES[version] or {}) do
      if note.chat then lines[#lines + 1] = "  - " .. note[1] end
    end
    announce(lines)
  end
  account.seenVersion = version
end

-- Once a load, at a login or a reload alike: a new version is usually installed
-- mid-session and reloaded, and waiting for the next login would miss that.
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", WJ.guard("welcome", function(self)
  C_Timer.After(DELAY, WJ.guard("welcome", tell))
  self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end))
