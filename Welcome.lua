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

-- Either message is a block of its own in chat: a rule above and below, the
-- flame on its first line, a blank line between its points.
local RULE = "----------------------------------------"

local WELCOME = {
  "Thank you for installing " .. NAME .. "!",
  "  - Your gameplay is now being recorded. View it or share it by uploading the file at widsith.app",
  "  - It is saved whenever you log off or reload the interface. Click the " .. WJ.EMBLEM .. " icon by the minimap to save at any time",
  "  - The addon's options menu, under Options, AddOns, Widsith, has more details and support information",
  "  - A lightweight companion app from widsith.app uploads your progress for you whenever you save",
  "More details at widsith.app",
}

local function block(points)
  return RULE .. "\n" .. WJ.EMBLEM .. " " .. table.concat(points, "\n\n") .. "\n" .. RULE .. "\n"
end

-- What changed that a player would notice, by version, a few words each. The
-- About page lists them all. Chat gets only the ones marked for it: what a
-- player may need to act on, or what changes the way things work. A change
-- they will simply see, or can do nothing about, stays off the message. A
-- version with no entry is announced alone.
local NOTES = {
  ["0.7.0"] = {
    { "Screenshot highlights and chat in the screenshots are now on by default", chat = true },
    { "Changes to your Widsith settings are now shared across all your characters", chat = true },
    { "Pause and Resume are now Stop and Start, which is what they do: a stopped recording records nothing", chat = true },
    { "A character whose recording you stopped stays stopped until you start it again", chat = true },
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
    WJ.say(block(WELCOME), true)
  else
    local points = { NAME .. " " .. version .. " is installed." }
    if NOTES[version] then points[#points + 1] = "What's new:" end
    for _, note in ipairs(NOTES[version] or {}) do
      if note.chat then points[#points + 1] = "  - " .. note[1] end
    end
    WJ.say(block(points), true)
  end
  account.seenVersion = version
  return true
end
