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

local _, WJ = ...

local DELAY = 3   -- s after entering the world

local WELCOME = {
  "Thanks for installing Widsith. It keeps a record of your character's journey as you play; replay it at widsith.app.",
  "The game saves the recording when you log out or reload. Click the icon by the minimap to save at any time, right-click it for the settings, or type /widsith help.",
}

-- What changed that a player would notice, by version, a few words each. A
-- version with no entry is announced alone.
local NOTES = {
  ["0.7.0"] = {
    "Screenshot highlights on by default, with chat in the pictures",
    "The save reminder at 45 minutes",
    "The icon's settings under Icon in the menu",
    "Settings shared by all your characters",
    "A paused character stays paused until you resume it",
  },
}

-- The notes for this version, for the About page.
function WJ.whatsNew()
  return NOTES[WJ.VERSION]
end

-- Lines as one message, the first on the name's line and the rest under it.
local function asOne(lines)
  return table.concat(lines, "\n")
end

local function tell()
  local account = WidsithAccount
  if not account then return end
  local version = WJ.VERSION
  if account.seenVersion == version then return end
  if account.seenVersion == nil and not account.usedBefore then
    WJ.say(asOne(WELCOME))
  elseif NOTES[version] then
    local lines = { version .. " is installed. What's new:" }
    for _, note in ipairs(NOTES[version]) do lines[#lines + 1] = "  - " .. note end
    WJ.say(asOne(lines))
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
