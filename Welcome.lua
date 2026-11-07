-- Widsith — what the player is told once
--
-- The first time the addon runs on an account, a welcome: what it does, how
-- the recording is saved, where the settings are. After that, the first load
-- of a new version says so and lists what changed that a player would notice,
-- in a few words each. Either is one chat message under the emblem and the
-- name, not a line of chat per point, and it takes the place of the
-- recorder's own "is recording" line at that load, saying so itself. Each is
-- said once per account, kept in WidsithAccount. Through the same channel as
-- the recorder's news, so "Show chat messages" off keeps it quiet. The About
-- page lists the same notes.

local _, WJ = ...

-- Paragraphs, a blank line between them.
local WELCOME = {
  "is now recording. Thank you for installing it.",
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

-- Whether this load has news to say: the account has yet to see this version.
function WJ.newsDue()
  return WidsithAccount ~= nil and WidsithAccount.seenVersion ~= WJ.VERSION
end

local function tell()
  local account = WidsithAccount
  if not account or not WJ.newsDue() then return end
  local version = WJ.VERSION
  local recording = WJ.isRecording() and " and recording" or ""
  if account.seenVersion == nil and not account.usedBefore then
    WJ.announce(table.concat(WELCOME, "\n\n"))
  else
    local lines = { version .. " is installed" .. recording .. "." .. (NOTES[version] and " What's new:" or "") }
    for _, note in ipairs(NOTES[version] or {}) do
      if note.chat then lines[#lines + 1] = "  - " .. note[1] end
    end
    WJ.announce(table.concat(lines, "\n"))
  end
  account.seenVersion = version
end

-- Once a load, at a login or a reload alike: a new version is usually installed
-- mid-session and reloaded, and waiting for the next login would miss that. The
-- recorder's frame hears the event first and leaves its "is recording" line
-- unsaid when news is due, so this is said in its place.
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", WJ.guard("welcome", function(self)
  tell()
  self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end))
