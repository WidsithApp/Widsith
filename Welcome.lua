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

local WELCOME = {
  "Thank you for installing " .. NAME .. "!",
  "  - Your gameplay is now being recorded",
  "  - View it or share it at widsith.app",
  "  - Automatic uploader available",
  "",
  "More details and support in the addon's options menu, and at widsith.app.",
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

-- Called by the recorder as a load begins, where it would say that it is
-- recording: says the welcome or the version's news if the account has yet to
-- see this version, and answers whether it said anything, so the recorder's
-- own line is left out when it did. A new version is usually installed
-- mid-session and reloaded, so a reload counts as much as a login.
function WJ.tellNews()
  local account = WidsithAccount
  if not account or account.seenVersion == WJ.VERSION then return false end
  local version = WJ.VERSION
  -- A blank line closes either, so it stands apart from what other addons print after it.
  if account.seenVersion == nil and not account.usedBefore then
    WJ.say(WJ.EMBLEM .. " " .. table.concat(WELCOME, "\n") .. "\n", true)
  else
    local recording = WJ.isRecording() and " and recording" or ""
    local lines = { version .. " is installed" .. recording .. "." .. (NOTES[version] and " What's new:" or "") }
    for _, note in ipairs(NOTES[version] or {}) do
      if note.chat then lines[#lines + 1] = "  - " .. note[1] end
    end
    WJ.announce(table.concat(lines, "\n") .. "\n")
  end
  account.seenVersion = version
  return true
end
