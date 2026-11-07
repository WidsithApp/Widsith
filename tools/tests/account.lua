-- What is the account's and what is the character's: the settings shared by every character
-- (WidsithAccount), the pause and the pictures taken kept with the character (WidsithUI), and
-- what the player is told once per account (Welcome.lua).

local function chatSince(game, from)
  local out = {}
  for i = from + 1, #game.chat do out[#out + 1] = (game.chat[i]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  return out
end

test("a setting changed on one character is the same on the next", function(game)
  game.login()
  game.advance(8)
  game.openMenu()
  game.press(game.menuEntry("Emote when saving"))
  game.press(game.menuEntry("Icon", "Large"))
  game.press(game.menuEntry("Screenshots", "Screenshot highlights"))
  game.loginAs("Maela", game.profile.surname and "Dunwood" or nil)
  game.advance(8)
  expect(game.addon.getIconSetting("emote"), "the emote setting didn't carry to the next character")
  eq(game.addon.getIconSetting("iconSize"), 1.8, "the icon size on the next character")
  expect(not game.addon.getIconSetting("screenshots"), "screenshots turned off on one character came back on the next")
  eq(#game.G.WidsithDB.sessions, 1, "the next character's recording is its own")
end)

test("the first character after the upgrade lends its settings to the account, and is known to have used the addon before", function(game)
  -- A character's file as the versions before this one left it: the settings in WidsithUI.
  game.saved = {
    WidsithUI = { shown = true, remind = false, iconStyle = 4, emote = true, iconSize = 1.4, screenshots = false,
      shotsSeen = { zone = { [30] = true } }, point = { "CENTER", "BOTTOMLEFT", 100, 200 } },
    WidsithDB = { format = 1, sessions = { { id = "1-1", startedAt = 1, closed = true, lines = 1, chunks = { "0\tSESSION" }, encoding = "raw" } }, nextSession = 1 },
  }
  game.login()
  game.advance(8)
  expect(not game.addon.getIconSetting("remind"), "the character's reminders-off setting wasn't taken as the account's")
  expect(game.addon.getIconSetting("emote"), "the character's emote setting wasn't taken")
  eq(game.addon.getIconSetting("iconSize"), 1.4, "the icon size taken")
  expect(not game.addon.getIconSetting("screenshots"), "screenshots turned off before the upgrade came on")
  expect(game.G.WidsithUI.remind == nil and game.G.WidsithUI.emote == nil, "the settings were left in the character's table too")
  expect(game.G.WidsithUI.shotsSeen and game.G.WidsithUI.shotsSeen.zone[30], "the pictures taken were lost from the character's table")
  expect(game.G.WidsithAccount.usedBefore, "the account doesn't know the addon was in use before")
  -- A second character's old settings don't replace the account's.
  game.loginAs("Maela", game.profile.surname and "Dunwood" or nil)
  game.G.WidsithUI.remind = true
  game.advance(8)
  expect(not game.addon.getIconSetting("remind"), "a later character's old setting replaced the account's")
end)

test("a paused character stays paused through a reload and a login, until resumed", function(game)
  game.login()
  game.advance(8)
  game.slash("pause")
  game.reload()
  game.advance(8)
  expect(not game.addon.isRecording() and game.addon.isPaused(), "a reload started recording on a paused character")
  expect(game.said("is paused on this character. Resume recording from the icon or with /widsith resume."), "the paused login wasn't said")
  game.hover()
  eq(game.tooltip.lines[2], "Paused.", "the tooltip while paused")
  game.loginAgain()
  game.advance(8)
  expect(not game.addon.isRecording(), "a login started recording on a paused character")
  eq(#game.G.WidsithDB.sessions, 1, "sessions on file while paused")
  game.openMenu()
  game.press(game.menuEntry("Resume recording"))
  game.advance(8)
  expect(game.addon.isRecording(), "Resume didn't resume")
  game.reload()
  game.advance(8)
  expect(game.addon.isRecording(), "a reload after a resume didn't record")
end)

test("a pause is the character's: another character records", function(game)
  game.login()
  game.advance(8)
  game.slash("pause")
  game.loginAs("Maela", game.profile.surname and "Dunwood" or nil)
  game.advance(8)
  expect(game.addon.isRecording(), "a pause on one character paused the next")
end)

test("the welcome is said once, at the first login on the account", function(game)
  game.login()
  game.advance(4)
  expect(game.said("Thanks for installing Widsith."), "no welcome at the first login")
  expect(game.said("click the Widsith icon by the minimap"), "the welcome doesn't say how to save")
  expect(game.said("Right-click the icon for the settings, or type /widsith help."), "the welcome doesn't say where the settings are")
  eq(game.G.WidsithAccount.seenVersion, game.version, "the version the account has seen")
  game.clearChat()
  game.reload()
  game.advance(4)
  expect(not game.said("Thanks for installing"), "the welcome was said again after a reload")
  game.loginAs("Maela", game.profile.surname and "Dunwood" or nil)
  game.advance(4)
  expect(not game.said("Thanks for installing"), "the welcome was said again on another character")
end)

test("a new version is announced once per account, with what changed, and not as a welcome", function(game)
  game.saved = { WidsithAccount = { settings = {}, seenVersion = "0.6.3" } }
  game.login()
  local from = #game.chat
  game.advance(4)
  local said = chatSince(game, from)
  expect(not game.said("Thanks for installing"), "an upgrade was welcomed as a first use")
  eq(said[1], "Widsith " .. game.version .. " is installed. What's new:", "the version line")
  expect(#said >= 3 and said[2]:find("^Widsith ") and said[2]:find("Screenshot highlights", 1, true), "the notes don't follow: " .. tostring(said[2]))
  game.clearChat()
  game.loginAs("Maela", game.profile.surname and "Dunwood" or nil)
  game.advance(4)
  expect(not game.said("is installed"), "the version was announced again on another character")
end)

test("a player who used the addon before this version is told the version, not welcomed", function(game)
  game.saved = { WidsithUI = { shown = true, remind = true, iconStyle = 4 } }
  game.login()
  game.advance(4)
  expect(not game.said("Thanks for installing"), "an existing player was welcomed as new")
  expect(game.said(game.version .. " is installed."), "an existing player wasn't told the version")
end)

test("with Show chat messages off, nothing is said at login, the welcome included", function(game)
  game.saved = { WidsithAccount = { settings = { chat = false } } }
  game.login()
  game.advance(8)
  eq(#game.chat, 0, "lines said with chat messages off")
end)
