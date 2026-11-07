-- Quests, loot, loot rolls, duels and /roll (Events.lua), and the small things that happen out of
-- combat (Moments.lua and Extras.lua): a discovery, the breath bar, an NPC's line, a trade's end
-- and the player's own speech.

-- The character as the game's messages name them: with the surname where the client gives one.
local function fullName(game)
  return game.character.name .. (game.character.surname and (" " .. game.character.surname) or "")
end

-- A loot message as the game sends it: the text, ten fields that don't matter here, then the GUID
-- of whoever the loot is for.
local function lootMessage(game, text, guid)
  game.fire("CHAT_MSG_LOOT", text, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, guid)
end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------

-- The world's quest log already holds quest 200, ready to turn in; each test adds what it needs.
local function acceptBoarsAndAKey(game)
  local log = game.world.questLog
  log[#log + 1] = { questID = 100, title = "Boars and a Key", ready = false, level = 4, difficulty = 6, objectives = {
    { numFulfilled = 0, numRequired = 8, type = "monster", text = "Boar slain" },
    { numFulfilled = 0, numRequired = 1, type = "item", text = "Rusty Key" } } }
  game.fire("QUEST_ACCEPTED", 100)
  return log[#log]
end

-- Each QPROG and QDONE line for a quest, as P<objective>:<count>/<required> and D<opening mark>.
local function questLines(game, questID)
  local out = {}
  for _, l in ipairs(game.lines()) do
    local f = l.fields
    if l.kind == "QPROG" and f[1] == questID then out[#out + 1] = "P" .. f[2] .. ":" .. f[3] .. "/" .. f[4] end
    if l.kind == "QDONE" and f[1] == questID then out[#out + 1] = "D" .. (f[2] or "") end
  end
  return out
end

test("a quest's objectives are listed at accept, its progress written as it comes, and QDONE once when it is ready", function(game)
  game.login()
  game.advance(8)
  -- A quest accepted with two objectives, one advanced, both met (ready to turn in), handed in.
  local quest = acceptBoarsAndAKey(game)
  game.advance(2)
  quest.objectives[1].numFulfilled = 3
  game.fire("UNIT_QUEST_LOG_CHANGED", "player")
  game.advance(1)
  quest.objectives[1].numFulfilled = 8
  quest.objectives[2].numFulfilled = 1
  quest.ready = true
  game.fire("UNIT_QUEST_LOG_CHANGED", "player")
  game.advance(1)
  game.fire("QUEST_TURNED_IN", 100, 250, 1200)
  game.change(1200)
  table.remove(game.world.questLog)
  game.fire("QUEST_REMOVED", 100)
  game.fire("UNIT_QUEST_LOG_CHANGED", "player")
  game.advance(1)

  local lines = table.concat(questLines(game, "100"), " ")
  eq(lines, "P1:0/8 P2:0/1 P1:3/8 P1:8/8 P2:1/1 D", "the quest's lines aren't the list at accept, the progress, then one QDONE")
  local accept = game.last("QACCEPT")
  expect(accept and accept.fields[1] == "100" and accept.fields[4] == "4" and accept.fields[5] == "6",
    "a quest's level and difficulty level weren't written at accept: " .. (accept and table.concat(accept.fields, " ") or "no QACCEPT"))
  local turnin = game.last("QTURNIN")
  expect(turnin and turnin.fields[1] == "100" and turnin.fields[2] == "250" and turnin.fields[3] == "1200",
    "the turn-in wasn't written with its experience and money: " .. (turnin and table.concat(turnin.fields, " ") or "no QTURNIN"))
  same(game.fieldsOf("QREMOVE"), { "100" }, "QREMOVE lines")
  -- The reward's money explains the change it brings.
  local money = game.last("MONEY")
  expect(money and money.fields[2] == "quest" and money.fields[4] == "1200",
    "a quest's reward wasn't written as MONEY quest 1200: " .. (money and table.concat(money.fields, " ") or "no MONEY"))
  -- Quest 200 stayed ready throughout, so it is written only as the session's opening state.
  same(questLines(game, "200"), { "D1" }, "quest 200's lines")
end)

test("a quest already ready as a session begins is written as the opening state of every session", function(game)
  game.login()
  game.advance(8)
  -- A pause and a resume make a second session, which opens on the same baseline as a reload.
  game.slash("stop")
  game.advance(5)
  game.slash("start")
  game.advance(8)
  eq(#game.written, 2, "sessions after a pause and a resume")
  local opening, other = 0, 0
  for _, l in ipairs(game.lines("QDONE")) do
    if l.fields[1] == "200" then
      if l.fields[2] == "1" then opening = opening + 1 else other = other + 1 end
    end
  end
  eq(opening, #game.written, "sessions opening with quest 200 written as ready")
  eq(other, 0, "QDONE lines for quest 200 not marked as the opening state")
end)

---------------------------------------------------------------------------
-- Loot
---------------------------------------------------------------------------

-- LOOT itemID qty source quality kind itemString, by item ID.
local function lootByItem(game)
  local out = {}
  for _, l in ipairs(game.lines("LOOT")) do out[l.fields[1]] = l.fields end
  return out
end
local function lootIs(loot, item, qty, source, kind, itemString)
  local f = loot[item]
  return f ~= nil and f[2] == qty and (f[3] or "") == source and (f[5] or "") == kind and (f[6] or "") == itemString
end

test("loot lines say which message they came from, with the count, the source and the item as linked", function(game)
  game.login()
  game.advance(8)
  local self = game.character.guid
  -- The kobold's corpse looted (three cloth, through the loot window), then items the game pushed
  -- without one, a craft, a refund, a wording no format explains, and an upgraded item whose link
  -- carries bonus IDs.
  game.world.lootSlots = { { link = "|cff9d9d9d|Hitem:2589::::::::1:::::::|h[Linen Cloth]|h|r", guid = "Creature-0-4621-0-46196-476-0000BCECFD" } }
  game.fire("LOOT_OPENED")
  lootMessage(game, "You receive loot: |cff9d9d9d|Hitem:2589::::::::1:::::::|h[Linen Cloth]|h|rx3.", self)
  lootMessage(game, "You receive item: |cffffffff|Hitem:6948::::::::1:::::::|h[Hearthstone]|h|r.", self)
  lootMessage(game, "You create: |cffffffff|Hitem:2581::::::::1:::::::|h[Heavy Linen Bandage]|h|rx2.", self)
  lootMessage(game, "You are refunded: |cffffffff|Hitem:1234::::::::1:::::::|h[Returned Thing]|h|r.", self)
  lootMessage(game, "You find: |cffffffff|Hitem:999::::::::1:::::::|h[Odd Thing]|h|r.", self)
  lootMessage(game, "You receive item: |cffa335ee|Hitem:268213::::::::80:577::6:5:6652:10353:10254:1527:10255::::::|h[Upgraded Blade]|h|r.", self)
  game.advance(1)

  local loot = lootByItem(game)
  expect(lootIs(loot, "2589", "3", "Creature-0-4621-0-46196-476-0000BCECFD", "loot", "item:2589::::::::1:::::::"),
    "corpse loot wasn't written as kind loot with its count, source and item string")
  expect(lootIs(loot, "6948", "1", "", "item", "item:6948::::::::1:::::::"), "a pushed item wasn't written as kind item")
  expect(lootIs(loot, "2581", "2", "", "create", "item:2581::::::::1:::::::"), "a craft wasn't written as kind create with its count")
  expect(lootIs(loot, "1234", "1", "", "refund", "item:1234::::::::1:::::::"), "a refund wasn't written as kind refund")
  expect(lootIs(loot, "999", "1", "", "", "item:999::::::::1:::::::"), "a wording no format explains wasn't written with its kind empty")
  expect(lootIs(loot, "268213", "1", "", "item", "item:268213::::::::80:577::6:5:6652:10353:10254:1527:10255::::::"),
    "an upgraded item's link wasn't kept whole")
end)

test("another player's loot is never written", function(game)
  game.login()
  game.advance(8)
  lootMessage(game, "Someone receives loot: |cffffffff|Hitem:4321::::::::1:::::::|h[Their Thing]|h|r.", "Player-4747-0BBBBBBB")
  game.advance(1)
  expect(lootByItem(game)["4321"] == nil, "another player's loot was written")
end)

---------------------------------------------------------------------------
-- Loot rolls
---------------------------------------------------------------------------

test("the character's loot roll choices and wins are written as LOOTROLL, never as LOOT", function(game)
  game.login()
  game.advance(8)
  -- Need (sent as the character's), greed (no sender), a pass, the win and the loot that follows
  -- it, and another player's choice (nothing).
  local SWORD = "|cff1eff00|Hitem:4567::::::::5:::::::|h[Greenish Sword]|h|r"
  local CLOAK = "|cff1eff00|Hitem:4568::::::::5:::::::|h[Greenish Cloak]|h|r"
  local BOOTS = "|cff1eff00|Hitem:4569::::::::5:::::::|h[Greenish Boots]|h|r"
  local self = game.character.guid
  lootMessage(game, "|HlootHistory:12|h[Loot]|h: You have selected Need for: " .. SWORD .. " |HlootHistory:12|h|cnLOOT_LINK_COLOR:[View Loot Rolls]|r|h", self)
  lootMessage(game, "|HlootHistory:13|h[Loot]|h: You have selected Greed for: " .. CLOAK .. " |HlootHistory:13|h|cnLOOT_LINK_COLOR:[View Loot Rolls]|r|h")
  lootMessage(game, "|HlootHistory:14|h[Loot]|h: You passed on: " .. BOOTS, self)
  lootMessage(game, "|HlootHistory:12|h[Loot]|h: You won: " .. SWORD, self)
  lootMessage(game, "You receive loot: " .. SWORD .. ".", self)
  lootMessage(game, "|HlootHistory:13|h[Loot]|h: Maela has selected Need for: " .. CLOAK, "Player-4747-0CCCCCCC")
  game.advance(1)

  same(game.fieldsOf("LOOTROLL"), { "need 4567 item:4567::::::::5:::::::", "greed 4568 item:4568::::::::5:::::::",
    "pass 4569 item:4569::::::::5:::::::", "won 4567 item:4567::::::::5:::::::" }, "LOOTROLL lines")
  local loot = lootByItem(game)
  expect(lootIs(loot, "4567", "1", "", "loot", "item:4567::::::::5:::::::"), "the loot after a won roll wasn't written as LOOT")
  expect(loot["4568"] == nil and loot["4569"] == nil, "a roll's message was written as loot")
  eq(#game.lines("LOOT"), 1, "LOOT lines: only the won sword's")
end)

---------------------------------------------------------------------------
-- Duels and /roll
---------------------------------------------------------------------------

test("a duel the character is in is written with its winner and loser, and one no message explains as finished", function(game)
  game.login()
  game.advance(8)
  local me = fullName(game)
  -- Names as each client words them: WoW Forever gives the surname. A namesake on Forever shares
  -- the first name with another surname; on Retail names are one word, so a namesake can only be
  -- from another realm.
  local rival = game.character.surname and "Maela Dunwood" or "Maela"
  local namesake = game.character.surname and (game.character.name .. " Smith") or (game.character.name .. "-Stormrage")
  -- The character wins one (the message, then the game's end of it), flees from another (the end,
  -- then the message half a second later), two strangers' duels and a namesake's nearby (nothing),
  -- and one under chat lockdown whose end fires twice: one line, with no names.
  game.fire("CHAT_MSG_SYSTEM", me .. " has defeated " .. rival .. " in a duel")
  game.fire("DUEL_FINISHED")
  game.advance(3)
  game.fire("DUEL_FINISHED")
  game.advance(0.5)
  game.fire("CHAT_MSG_SYSTEM", me .. " has fled from " .. rival .. " in a duel")
  game.advance(3)
  game.fire("CHAT_MSG_SYSTEM", "Bertrand has defeated Someone in a duel")
  game.fire("CHAT_MSG_SYSTEM", namesake .. " has defeated " .. rival .. " in a duel")
  game.fire("DUEL_FINISHED")
  game.world.chatLockdown = true
  game.fire("CHAT_MSG_SYSTEM", game.SECRET)
  game.fire("DUEL_FINISHED")
  game.advance(3)

  same(game.fieldsOf("DUEL"), { "knockout " .. me .. " " .. rival, "retreat " .. rival .. " " .. me, "finished  " }, "DUEL lines")
end)

test("the character's own /roll is written, with or without the surname, and no one else's", function(game)
  game.login()
  game.advance(8)
  local me = fullName(game)
  local namesake = game.character.surname and (game.character.name .. " Smith") or (game.character.name .. "-Stormrage")
  -- The character's own with the surname where the client gives one, another player's, the
  -- character's without the surname (as Retail words it), and a namesake's.
  game.fire("CHAT_MSG_SYSTEM", me .. " rolls 42 (1-100)")
  game.fire("CHAT_MSG_SYSTEM", "Maela Dunwood rolls 7 (1-100)")
  game.fire("CHAT_MSG_SYSTEM", game.character.name .. " rolls 3 (1-6)")
  game.fire("CHAT_MSG_SYSTEM", namesake .. " rolls 99 (1-100)")
  game.advance(1)
  same(game.fieldsOf("ROLL"), { "42 1 100", "3 1 6" }, "ROLL lines")
end)

---------------------------------------------------------------------------
-- Out of combat: a discovery, the breath bar, an NPC's line, a trade's end, the player's speech
---------------------------------------------------------------------------

test("an area discovered is written once, though the game announces it twice", function(game)
  game.login()
  game.advance(8)
  -- Crystal Lake is announced in the system channel with its experience and again on screen; the
  -- second is the same discovery. Jasperlode Mine is announced on screen only, with no experience.
  game.fire("CHAT_MSG_SYSTEM", "Discovered Crystal Lake: 65 experience gained")
  game.fire("UI_INFO_MESSAGE", 412, "Discovered: Crystal Lake")
  game.fire("UI_INFO_MESSAGE", 412, "Discovered: Jasperlode Mine")
  game.advance(1)
  same(game.fieldsOf("DISCOVER"), { "65 Crystal Lake", " Jasperlode Mine" }, "DISCOVER lines")
end)

test("the game's trade-complete message with no trade window seen writes nothing", function(game)
  game.login()
  game.advance(8)
  local before = #game.lines()
  game.fire("UI_INFO_MESSAGE", 251, "Trade complete.")
  eq(#game.lines(), before, "lines written for a trade's end with no trade window seen")
end)

test("the breath bar's starts and stop are written, and a stop for a bar never started is not", function(game)
  game.login()
  game.advance(8)
  -- Underwater: the bar starts draining, starts again refilling, then stops when full. The game
  -- also stops bars that never showed (it does so for every kind at a death).
  game.fire("MIRROR_TIMER_START", "BREATH", 60000, 60000, -1, 0, "Breath")
  game.advance(4)
  game.fire("MIRROR_TIMER_START", "BREATH", 56065, 60000, 10, 0, "Breath")
  game.fire("MIRROR_TIMER_STOP", "BREATH")
  game.fire("MIRROR_TIMER_STOP", "EXHAUSTION")
  game.advance(1)
  same(game.fieldsOf("MIRROR"), { "start BREATH 60000 60000 -1", "start BREATH 56065 60000 10", "stop BREATH" }, "MIRROR lines")
end)

test("an NPC's line is written once however often it is repeated, and a hidden one not at all", function(game)
  game.login()
  game.advance(8)
  game.fire("CHAT_MSG_MONSTER_SAY", "Yiieeeee! Me run!", "Kobold Worker")
  game.fire("CHAT_MSG_MONSTER_SAY", "Yiieeeee! Me run!", "Kobold Worker")
  game.fire("CHAT_MSG_MONSTER_YELL", game.SECRET, game.SECRET)
  game.advance(1)
  same(game.fieldsOf("NPCSAY"), { "say Kobold Worker Yiieeeee! Me run!" }, "NPCSAY lines")
end)

test("the player's own /say and /yell write nothing", function(game)
  game.login()
  game.advance(8)
  -- Speech is switched off, so nothing may be written (the runner fails a test on any SPEECH line).
  local before = #game.lines()
  local guid = game.character.guid
  game.fire("CHAT_MSG_SAY", "Well met!", game.character.name, "Common", "", "", "", 0, 0, "", 7, 12, guid)
  game.fire("CHAT_MSG_YELL", "For the Alliance!", game.character.name, "Common", "", "", "", 0, 0, "", 7, 13, guid)
  eq(#game.lines(), before, "lines written for the player's own speech")
end)
