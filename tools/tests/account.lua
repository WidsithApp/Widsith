-- What is the account's and what is the character's: the settings shared by every character
-- (WidsithAccount), the pause and the pictures taken kept with the character (WidsithUI), and
-- what the player is told once per account (Welcome.lua).

-- Chat since a point, with the colour codes and the emblem's texture taken out.
local function chatSince(game, from)
  local out = {}
  for i = from + 1, #game.chat do out[#out + 1] = (game.chat[i]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t ?", "")) end
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

test("a stopped character stays stopped through a reload and a login, until started again", function(game)
  game.login()
  game.advance(8)
  game.slash("stop")
  game.reload()
  game.advance(8)
  expect(not game.addon.isRecording() and game.addon.isPaused(), "a reload started recording on a paused character")
  expect(game.said("is not recording on this character. Start recording from the icon or with /widsith start."), "the stopped login wasn't said")
  game.hover()
  eq(game.tooltip.lines[2], "Stopped.", "the tooltip while stopped")
  game.loginAgain()
  game.advance(8)
  expect(not game.addon.isRecording(), "a login started recording on a paused character")
  eq(#game.G.WidsithDB.sessions, 1, "sessions on file while paused")
  game.openMenu()
  game.press(game.menuEntry("Start recording"))
  game.advance(8)
  expect(game.addon.isRecording(), "Resume didn't resume")
  game.reload()
  game.advance(8)
  expect(game.addon.isRecording(), "a reload after a resume didn't record")
end)

test("a stop is the character's: another character records", function(game)
  game.login()
  game.advance(8)
  game.slash("stop")
  game.loginAs("Maela", game.profile.surname and "Dunwood" or nil)
  game.advance(8)
  expect(game.addon.isRecording(), "a pause on one character paused the next")
end)

test("the welcome is said once, at the first login on the account", function(game)
  game.login()
  game.advance(4)
  local welcome = game.said("Thank you for installing")
  expect(welcome ~= nil, "no welcome at the first login")
  expect(welcome and welcome:find("^|TInterface\\AddOns\\Widsith\\media\\flame%-chat:16:16|t Thank you for installing |cff33ff99Widsith|r!\n"),
    "the welcome doesn't open with the flame and the thanks: " .. tostring(welcome))
  -- A rule above and below, each a message of its own so it sits at the margin, and the block
  -- between them with a blank line between its points, each behind a bullet in the flame's colour.
  -- The stand-in's chat window is 400 wide with a dash 8 wide: (400 - 24) / 8, rounded down.
  local RULE = string.rep("-", 47)
  local function plain(line) return (line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  local at
  for i, line in ipairs(game.chat) do if line == welcome then at = i end end
  eq(plain(game.chat[at - 1]), RULE, "the rule above the welcome, as wide as the chat window")
  eq(plain(game.chat[at + 1]), RULE .. "\n", "the rule below the welcome, closing with a blank line")
  -- Each dash under its own colour, the flame's dark orange first and its cream last.
  expect(game.chat[at - 1]:find("^|cffb9521a%-|r") and game.chat[at - 1]:find("|cfffff4d6%-|r$"), "the rule isn't the flame's colours from dark orange to cream: " .. game.chat[at - 1]:sub(1, 30))
  local lines = {}
  for line in (((welcome or "") .. "\n"):gsub("|T[^|]*|t ?", "")):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
  local B = "  |cfff4b04a\226\128\162|r "
  same(lines, { "Thank you for installing |cff33ff99Widsith|r!", "",
    B .. "Your gameplay is now being recorded, view it or share it by uploading the file at widsith.app", "",
    B .. "It is automatically saved whenever you log off, or reload the interface. Click the icon to manually trigger a reload", "",
    B .. "View the addon options for additional details and support information", "",
    B .. "A lightweight companion app is available on widsith.app that will automatically upload your progress for you whenever you save", "",
    "More details @ widsith.app" },
    "the welcome's lines")
  expect(welcome and welcome:find("Click the |TInterface\\AddOns\\Widsith\\media\\emblem:16:16|t icon to manually"), "the save line doesn't draw the icon it names, the flame on its disc")
  local messages = 0
  for _, line in ipairs(game.chat) do if line:find("Thank you for installing", 1, true) or line:find("Your gameplay is now", 1, true) then messages = messages + 1 end end
  eq(messages, 1, "the welcome's chat messages: one, its lines under one heading")
  expect(not game.said("is recording. Type /widsith help") and not game.said("is recording."), "the login line was said beside the welcome, which says it itself")
  eq(game.G.WidsithAccount.seenVersion, game.version, "the version the account has seen")
  game.clearChat()
  game.reload()
  game.advance(4)
  expect(not game.said("Thank you for installing"), "the welcome was said again after a reload")
  game.loginAs("Maela", game.profile.surname and "Dunwood" or nil)
  game.advance(4)
  expect(not game.said("Thank you for installing"), "the welcome was said again on another character")
end)

test("a new version is announced once per account as one message listing what changed, not as a welcome", function(game)
  game.saved = { WidsithAccount = { settings = {}, seenVersion = "0.6.3" } }
  -- Said as the world is entered, in the place of the recorder's own "is recording" line: a rule,
  -- the block, a rule, three messages.
  game.login()
  game.advance(4)
  local said = chatSince(game, 0)
  expect(not game.said("Thank you for installing"), "an upgrade was welcomed as a first use")
  eq(#said, 3, "chat messages at the login: the rule, the news, the rule")
  local RULE = string.rep("-", 47)
  eq(said[1], RULE, "the rule above")
  eq(said[3], RULE .. "\n", "the rule below, closing with a blank line")
  local lines = {}
  for line in ((said[2] or "") .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
  local B = "  \226\128\162 "
  same(lines, { "Widsith " .. game.version .. " is installed.", "", "What's new:", "",
    B .. "Screenshot highlights, and the include chat in screenshots options are now enabled by default", "",
    B .. "Changes you make to the general Widsith configuration are now shared across all your characters", "",
    B .. "Pause and Resume have been changed to Stop and Start to better reflect their behaviour", "",
    B .. "Characters that have had their recording stopped, now will not start again until manually started." },
    "the news: the version, What's new, the points a blank line apart behind bullets")
  -- Chat gets what a player may act on or what changes the way things work; the About page
  -- lists everything, the reminder's new length and the menu's shape included.
  expect(not said[2]:find("45 minutes", 1, true) and not said[2]:find("under Icon", 1, true), "a change a player can only see is in the message")
  eq(#game.addon.whatsNew(), 6, "the About page's notes")
  -- The About page lists the notes under a heading with the version.
  local about = game.panelRow("About")
  local texts = {}
  for _, r in ipairs(about.frame.regions) do texts[#texts + 1] = r.text end
  local joined = table.concat(texts, "\n")
  expect(joined:find("What's new in " .. game.version, 1, true), "the About page has no What's new heading")
  expect(joined:find("Screenshot highlights, and the include chat in screenshots options are now enabled by default", 1, true), "the About page doesn't list the notes")
  expect(joined:find("The save reminder comes after 45 minutes", 1, true), "the About page leaves out a note chat doesn't carry")
  game.clearChat()
  game.loginAs("Maela", game.profile.surname and "Dunwood" or nil)
  game.advance(4)
  expect(not game.said("is installed"), "the version was announced again on another character")
end)

test("a new version installed mid-session is announced at the reload, not the next login", function(game)
  game.saved = { WidsithAccount = { settings = {}, seenVersion = "0.6.3" } }
  game.login()
  game.advance(8)
  game.clearChat()
  -- Said once at this load; the reload is what a player does after installing a version.
  game.G.WidsithAccount.seenVersion = "0.6.3"
  game.reload()
  game.advance(4)
  expect(game.said(game.version .. " is installed."), "a reload on a version not yet seen said nothing")
  expect(not game.said("is recording."), "the reload line was said beside the version note, which says it itself")
  game.clearChat()
  game.reload()
  game.advance(4)
  expect(not game.said("is installed"), "a second reload announced the version again")
end)

test("a player who used the addon before this version is told the version, not welcomed", function(game)
  game.saved = { WidsithUI = { shown = true, remind = true, iconStyle = 4 } }
  game.login()
  game.advance(4)
  expect(not game.said("Thank you for installing"), "an existing player was welcomed as new")
  expect(game.said(game.version .. " is installed."), "an existing player wasn't told the version")
end)

test("with Show chat messages off, nothing is said at login, the welcome included", function(game)
  game.saved = { WidsithAccount = { settings = { chat = false } } }
  game.login()
  game.advance(8)
  eq(#game.chat, 0, "lines said with chat messages off")
end)

test("the rule is forty dashes when the chat window's font can't be read", function(game)
  game.saved = { WidsithAccount = { settings = {}, seenVersion = "0.6.3" } }
  -- No font to measure with: a chat frame whose GetFont isn't a function, at every build.
  game.onBuild = function(G) G.ChatFrame1.GetFont = false end
  game.login()
  game.advance(4)
  local said = chatSince(game, 0)
  eq(said[1], string.rep("-", 40), "the rule without a measure")
end)
