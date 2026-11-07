-- Screenshot highlights (Screenshots.lua): with the setting on, the addon takes a picture at a
-- new level, a boss's first defeat, the first time in a zone or an instance, the first mount, the
-- first death and every death on a Hardcore realm. For the length of the picture chat and the
-- social windows are made transparent and a mark is drawn; everything is put back when the game
-- answers, or after three seconds if it never does. A SHOT line names the moment, says when chat
-- was left in, and is plain for the player's own screenshot.
--
-- The game's Screenshot() here counts the pictures in game.world.shotsTaken, notes how see-through
-- chat and the friends list were at that instant, and answers with game.world.shotAnswer (nil
-- says nothing at all). Chat starts at 0.8 and the friends list at 1.

-- Logged in, settled, with highlights on and chat hidden for the pictures: the tests here play
-- the hidden case, and the one that leaves chat in says so itself.
local function withHighlights(game)
  game.login()
  game.advance(8)
  game.addon.setIconSetting("screenshots", true)
  game.addon.setIconSetting("shotsChat", false)
end

local function shots(game, wanted, what)
  eq(game.world.shotsTaken, wanted, what .. ": screenshots")
end

local function levelUp(game, level)
  game.fire("PLAYER_LEVEL_UP", level, 17, 0, 0, 0, 1, 0, 1, 0)
end

test("with the setting off, a level takes no picture", function(game)
  game.login()
  game.advance(8)
  game.addon.setIconSetting("screenshots", false)
  levelUp(game, 6)
  game.advance(2)
  shots(game, 0, "with the setting off")
  same(game.fieldsOf("SHOT"), {}, "SHOT lines with the setting off")
end)

test("a level's picture is taken with chat and the friends list gone, and both come back", function(game)
  withHighlights(game)
  levelUp(game, 6)
  game.advance(2)
  shots(game, 1, "a level")
  eq(game.world.chatAtShot, 0, "chat was showing in a highlight's picture")
  eq(game.G.ChatFrame1.alpha, 0.8, "chat didn't come back as it was")
  eq(game.world.friendsAtShot, 0, "the friends list was showing in a highlight's picture")
  eq(game.G.FriendsFrame.alpha, 1, "the friends list didn't come back")
  same(game.fieldsOf("SHOT"), { "level" }, "SHOT lines")
end)

test("inside the gap after a picture, a lesser moment takes none and a greater one does", function(game)
  withHighlights(game)
  levelUp(game, 6)
  game.advance(2)
  shots(game, 1, "a level")
  game.addon.highlightShot("zone", "Westfall")      -- a lesser moment waits out the gap
  game.advance(4)
  shots(game, 1, "a zone inside the gap")
  game.fire("ENCOUNTER_END", 77, "Hogger", 1, 5, 1)   -- a greater moment, inside the gap
  game.advance(3)
  shots(game, 2, "a boss inside the gap")
  same(game.fieldsOf("SHOT"), { "level", "boss" }, "SHOT lines")
end)

test("a wipe is no moment", function(game)
  withHighlights(game)
  game.addon.SHOT_GAP = 1                             -- the tests needn't wait half a minute each
  game.fire("ENCOUNTER_END", 78, "Lost", 1, 5, 0)
  game.advance(3)
  shots(game, 0, "a wipe")
end)

test("a boss already pictured has no second picture", function(game)
  withHighlights(game)
  game.addon.SHOT_GAP = 1
  game.fire("ENCOUNTER_END", 77, "Hogger", 1, 5, 1)
  game.advance(3)
  shots(game, 1, "a boss's first defeat")
  game.advance(2)
  game.fire("ENCOUNTER_END", 77, "Hogger", 1, 5, 1)   -- that boss again
  game.advance(3)
  shots(game, 1, "a boss already pictured")
  same(game.fieldsOf("SHOT"), { "boss" }, "SHOT lines")
end)

test("a boss and a level in the same blow take one picture, the boss's", function(game)
  withHighlights(game)
  game.addon.SHOT_GAP = 1
  game.fire("ENCOUNTER_END", 79, "Other", 1, 5, 1)
  levelUp(game, 7)
  game.advance(4)
  shots(game, 1, "a boss and a level together")
  same(game.fieldsOf("SHOT"), { "boss" }, "SHOT lines")
end)

-- Neither a failure nor silence writes a SHOT line, and the moment still counts as pictured, so a
-- second first mount or the same zone again takes nothing.
test("a failure and no answer both bring chat back, and the moment counts as pictured", function(game)
  withHighlights(game)
  game.addon.SHOT_GAP = 1
  game.world.shotAnswer = "SCREENSHOT_FAILED"
  game.addon.highlightShot("mount", "first")
  game.advance(4)
  shots(game, 1, "a mount")
  eq(game.G.ChatFrame1.alpha, 0.8, "a failure left chat hidden")
  eq(game.G.FriendsFrame.alpha, 1, "a failure left the friends list hidden")
  game.advance(2)
  game.world.shotAnswer = nil
  game.world.position = 30
  game.addon.zoneChanged()
  game.advance(4)
  eq(game.G.ChatFrame1.alpha, 0, "the zone's picture should still be waiting on the game")
  game.advance(3)
  shots(game, 2, "a zone")
  eq(game.G.ChatFrame1.alpha, 0.8, "no answer left chat hidden")
  game.world.shotAnswer = "SCREENSHOT_SUCCEEDED"
  game.advance(2)
  game.addon.highlightShot("mount", "first")
  game.addon.zoneChanged()
  game.advance(4)
  shots(game, 2, "a second first mount and zone")
  same(game.fieldsOf("SHOT"), {}, "SHOT lines for a failure and for no answer")
end)

-- A picture of a place waits for the world map to close, and is given up if the character has
-- moved on by then; a zone given up isn't marked as pictured, so coming back takes it.
test("a zone waits for the world map to close, and is given up if the character moved on", function(game)
  withHighlights(game)
  game.addon.SHOT_GAP = 1
  game.world.position = 40
  game.world.mapShown = true
  game.addon.zoneChanged()
  game.advance(5)
  shots(game, 0, "a new zone with the map open")
  game.world.mapShown = false
  game.advance(2)
  shots(game, 1, "a new zone once the map closed")
  game.world.position = 41
  game.world.mapShown = true
  game.addon.zoneChanged()
  game.advance(4)
  game.world.position = 42
  game.world.mapShown = false
  game.advance(2)
  shots(game, 1, "a zone left behind while the map was open")
  game.world.position = 41
  game.addon.zoneChanged()
  game.advance(4)
  shots(game, 2, "that zone, on coming back")
  same(game.fieldsOf("SHOT"), { "zone", "zone" }, "SHOT lines")
end)

test("an instance has one picture", function(game)
  withHighlights(game)
  game.addon.SHOT_GAP = 1
  game.addon.highlightShot("instance", 36)
  game.advance(4)
  shots(game, 1, "a first instance")
  game.addon.highlightShot("instance", 36)
  game.advance(4)
  shots(game, 1, "an instance already pictured")
  same(game.fieldsOf("SHOT"), { "instance" }, "SHOT lines")
end)

-- Map 55 is a cave inside zone 52; map 13 is the continent both belong to.
test("a cave counts as its zone and a continent is no zone", function(game)
  withHighlights(game)
  game.addon.SHOT_GAP = 1
  game.world.position = 55
  game.addon.zoneChanged()
  game.advance(4)
  shots(game, 1, "a cave, the first of its zone")
  game.world.position = 52
  game.addon.zoneChanged()
  game.advance(4)
  shots(game, 1, "the zone a cave belongs to")
  game.world.position = 13
  game.addon.zoneChanged()
  game.advance(4)
  shots(game, 1, "a continent")
  same(game.fieldsOf("SHOT"), { "zone" }, "SHOT lines")
end)

test("only the first death has a picture", function(game)
  withHighlights(game)
  game.addon.SHOT_GAP = 1
  game.fire("PLAYER_DEAD")
  game.advance(3)
  shots(game, 1, "a first death")
  game.fire("PLAYER_ALIVE")
  game.advance(2)
  game.addon.highlightShot("death", "first")
  game.advance(3)
  shots(game, 1, "a second death")
  same(game.fieldsOf("SHOT"), { "death" }, "SHOT lines")
end)

-- Hardcore realms are WoW Forever's: Retail has no C_GameRules.IsHardcoreActive to ask.
test("every death has a picture on a Hardcore realm", { client = "forever" }, function(game)
  withHighlights(game)
  game.addon.SHOT_GAP = 1
  game.fire("PLAYER_DEAD")
  game.advance(3)
  game.fire("PLAYER_ALIVE")
  game.advance(2)
  game.world.hardcore = true
  game.addon.highlightShot("death", "first")
  game.advance(3)
  shots(game, 2, "a Hardcore death")
  same(game.fieldsOf("SHOT"), { "death", "death" }, "SHOT lines")
end)

test("with chat left in the pictures, chat stays, the social windows still go, and the line says so", function(game)
  withHighlights(game)
  game.addon.setIconSetting("shotsChat", true)
  game.world.position = 42
  game.addon.zoneChanged()
  game.advance(4)
  shots(game, 1, "a zone with chat left in")
  eq(game.world.chatAtShot, 0.8, "chat was hidden though the setting leaves it in")
  eq(game.world.friendsAtShot, 0, "the friends list was showing with chat left in")
  eq(game.G.FriendsFrame.alpha, 1, "the friends list didn't come back with chat left in")
  same(game.fieldsOf("SHOT"), { "zone 1" }, "SHOT lines")
end)

-- The game names a screenshot's file after the second it was taken in, so a highlight due in the
-- same second as the player's own waits for the next second rather than replace their file.
test("the player's own screenshot in the second a highlight falls due makes it wait a second", function(game)
  withHighlights(game)
  game.advance(math.ceil(game.clock) - game.clock)   -- to a whole second
  game.addon.highlightShot("level")
  game.advance(1.4)
  game.fire("SCREENSHOT_SUCCEEDED")   -- the player's own, in the second the level's picture is due
  game.advance(0.3)
  shots(game, 0, "a highlight in the same second as the player's own")
  game.advance(1)
  shots(game, 1, "a highlight a second after the player's own")
  same(game.fieldsOf("SHOT"), { "", "level" }, "SHOT lines")
end)

test("a highlight waiting when the setting is turned off is not taken", function(game)
  withHighlights(game)
  game.addon.highlightShot("level")
  game.addon.setIconSetting("screenshots", false)
  game.advance(3)
  shots(game, 0, "a highlight after the setting was turned off")
end)

test("the player's own screenshot is noted plainly and touches nothing", function(game)
  game.login()
  game.advance(8)
  game.fire("SCREENSHOT_SUCCEEDED")   -- the player's own
  eq(game.G.ChatFrame1.alpha, 0.8, "the player's own screenshot touched chat")
  eq(game.G.FriendsFrame.alpha, 1, "the player's own screenshot touched the friends list")
  same(game.fieldsOf("SHOT"), { "" }, "SHOT lines")
end)

-- The mark is worked out from the character, the session and the second, in plain arithmetic
-- that must give the same sum in any Lua.
test("the mark's sum is unchanged", function(game)
  game.login()
  eq(game.addon.markCode("Player-1071-072D2F76", 1793530000, 1793530012), 13038999, "the mark's sum changed")
end)
