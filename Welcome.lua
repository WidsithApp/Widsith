-- Widsith — what the player is told once
--
-- The first time the addon runs on an account, two lines of welcome: what it
-- does, how the recording is saved, where the settings are. After that, the
-- first login on a new version says so in one line and points at the About
-- page, which lists what changed that a player would notice. Chat gets one
-- thing to read; a list waits where the player can read it when they choose.
-- Each is said once per account, kept in WidsithAccount, a few seconds after
-- the recorder's own login line so the two read in order. Through the same
-- channel as the recorder's news, so "Show chat messages" off keeps it quiet.

local _, WJ = ...

local DELAY = 3   -- s after entering the world

local WELCOME = {
  "Thanks for installing Widsith. It keeps a record of your character's journey as you play; replay it at widsith.app.",
  "The game saves the recording when you log out or reload. Click the icon by the minimap to save at any time, right-click it for the settings, or type /widsith help.",
}

-- What changed that a player would notice, by version, shown on the About
-- page under "What's new". A version with no entry is announced alone.
local NOTES = {
  ["0.7.0"] = {
    "Screenshot highlights are on, with chat in the pictures. Turn either off under Screenshots in the icon's menu.",
    "The save reminder comes after 45 minutes of unsaved play.",
    "The icon's settings are under Icon in the menu, and Show chat messages is in the options window.",
    "Your settings are shared by all your characters, and a paused character stays paused until you resume it.",
  },
}

-- The notes for this version, for the About page.
function WJ.whatsNew()
  return NOTES[WJ.VERSION]
end

local function tell()
  local account = WidsithAccount
  if not account then return end
  local version = WJ.VERSION
  if account.seenVersion == version then return end
  if account.seenVersion == nil and not account.usedBefore then
    for _, line in ipairs(WELCOME) do WJ.say(line) end
  elseif NOTES[version] then
    WJ.say(version .. " is installed. What's new is on the About page, under Options, AddOns, Widsith.")
  else
    WJ.say(version .. " is installed.")
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
