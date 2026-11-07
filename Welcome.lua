-- Widsith — what the player is told once
--
-- The first time the addon runs on an account, a few lines of welcome: what
-- it does, how the recording is saved, where the settings are. After that,
-- the first login on a new version says so and names what changed, if
-- anything a player would notice. Each is said once per account, kept in
-- WidsithAccount, a few seconds after the recorder's own login line so the
-- two read in order. Through the same channel as the recorder's news, so
-- "Show chat messages" off keeps it quiet.

local _, WJ = ...

local DELAY = 3   -- s after entering the world

local WELCOME = {
  "Thanks for installing Widsith. It keeps a record of your character's journey as you play, and the recording is replayed at widsith.app.",
  "The game writes the recording when you log out or reload. To save it at any time, click the Widsith icon by the minimap, which reloads the interface.",
  "Right-click the icon for the settings, or type /widsith help.",
}

-- What changed that a player would notice, by version. A version with no
-- entry is announced in one line.
local NOTES = {
  ["0.7.0"] = {
    "Screenshot highlights are on, with chat in the pictures. Turn either off under Screenshots in the icon's menu.",
    "The save reminder comes after 45 minutes of unsaved play.",
    "The icon's settings are under Icon in the menu, and Show chat messages is in the options window.",
    "Your settings are now shared by all your characters, and a paused character stays paused until you resume it.",
  },
}

local function tell()
  local account = WidsithAccount
  if not account then return end
  local version = WJ.VERSION
  if account.seenVersion == version then return end
  if account.seenVersion == nil and not account.usedBefore then
    for _, line in ipairs(WELCOME) do WJ.say(line) end
  else
    WJ.say(version .. " is installed." .. (NOTES[version] and " What's new:" or ""))
    for _, line in ipairs(NOTES[version] or {}) do WJ.say(line) end
  end
  account.seenVersion = version
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", WJ.guard("welcome", function(self, _, isLogin)
  if not isLogin then return end
  C_Timer.After(DELAY, WJ.guard("welcome", tell))
  self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end))
