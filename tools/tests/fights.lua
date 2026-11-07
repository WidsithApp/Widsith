-- Fights, deaths and the character sheet: the FIGHT line the damage meter gives when combat ends
-- (Moments.lua), COMBAT enter and leave, DEATH and the death recap's RECAP lines, the STATE line's
-- afk flag (Position.lua), the STATS line a fight keeps hidden (Extras.lua), CC for control lost,
-- and the game's kill counter read once a fight is over.
--
-- The stand-in's meter answers from game.world: its sessions are game.world.fights (the newest
-- last), the character's own damage and the fight's length are game.world.meterTotal and
-- game.world.meterDuration, every amount is secret while game.world.combat is on, and
-- game.world.meterLate[id] keeps a session unready for a moment after combat ends. A fresh game
-- holds one session, 88, from before the login.

-- Into combat and out of it, as the game says so.
local function enterCombat(game)
  game.world.combat = true
  game.fire("PLAYER_REGEN_DISABLED")
end
local function leaveCombat(game)
  game.world.combat = false
  game.fire("PLAYER_REGEN_ENABLED")
end

-- What the FIGHT lines say of each meter session, over every session of the recording: how many
-- lines it has, how many milliseconds after the COMBAT leave before it the first and the last were
-- written (-1 for one written inside a fight), and the duration the last one gave.
local function fightsByID(game)
  local out, leaveT = {}, nil
  for _, l in ipairs(game.lines()) do
    if l.kind == "COMBAT" and l.fields[1] == "enter" then leaveT = nil end
    if l.kind == "COMBAT" and l.fields[1] == "leave" then leaveT = l.t end
    if l.kind == "FIGHT" then
      local id = l.fields[1]
      local f = out[id] or { count = 0 }
      out[id] = f
      f.count = f.count + 1
      local after = leaveT and (l.t - leaveT) or -1
      if f.count == 1 then f.firstAfter = after end
      f.lastAfter, f.lastDuration = after, tonumber(l.fields[2])
    end
  end
  return out
end

-- Every meter session written has the number of lines it should: one, unless the test says more.
local function countsAre(game, wanted)
  for id, f in pairs(fightsByID(game)) do
    eq(f.count, wanted[id] or 1, "the meter's session " .. id .. " was written this many times")
  end
end

test("combat the meter keeps no session for writes no FIGHT, and the fight from before the session never is", function(game)
  game.login()
  game.advance(8)
  -- The meter's newest session is still the fight from before the login, which is no fight that
  -- just ended.
  enterCombat(game)
  game.advance(2)
  leaveCombat(game)
  game.advance(2)
  same(game.fieldsOf("COMBAT"), { "enter", "leave" }, "the COMBAT lines")
  expect(fightsByID(game)["88"] == nil, "the meter's fight from before the session was written when a later combat ended")
  eq(#game.lines("FIGHT"), 0, "FIGHT lines for combat the meter kept no session for")
end)

test("a fight whose meter hasn't this character's entry at the instant is written a second after combat ends", function(game)
  game.login()
  game.advance(8)
  enterCombat(game)
  game.advance(10)
  table.insert(game.world.fights, { sessionID = 89, name = "Kobold Geomancer", durationSeconds = 24 })
  -- The meter hasn't this character's entry yet the instant combat ends.
  game.world.meterLate[89] = { at = game.clock + 0.5, how = "missing" }
  leaveCombat(game)
  game.advance(3)
  local f = fightsByID(game)["89"]
  eq(f and f.firstAfter, 1000, "a fight whose meter wasn't whole at once wasn't written a second later: ms after leave")
  countsAre(game, {})
  local line = game.last("FIGHT")
  -- The line is the whole one: the meter's length, this character's own damage, and the creatures.
  eq(line and line.fields[2], "24", "the fight's duration")
  eq(line and line.fields[3], "181", "the character's own damage")
end)

test("a fight followed at once by another is written the instant its combat ends", function(game)
  game.login()
  game.advance(8)
  enterCombat(game)
  table.insert(game.world.fights, { sessionID = 90, name = "Timber Wolf", durationSeconds = 5 })
  leaveCombat(game)
  enterCombat(game)
  game.advance(3)
  leaveCombat(game)
  game.advance(3)
  local f = fightsByID(game)["90"]
  eq(f and f.firstAfter, 0, "a fight followed at once by another wasn't written as its combat ended: ms after leave")
  -- The second span has no session of its own on the meter, so 90 is still the newest and is
  -- not written again.
  countsAre(game, {})
end)

test("a fight whose amounts are still hidden at the instant is written a second later", function(game)
  game.login()
  game.advance(8)
  enterCombat(game)
  game.advance(3)
  table.insert(game.world.fights, { sessionID = 91, name = "Timber Wolf", durationSeconds = 9 })
  -- The meter still hides this fight's amounts the instant combat ends.
  game.world.meterLate[91] = { at = game.clock + 0.5, how = "secret" }
  leaveCombat(game)
  game.advance(3)
  local f = fightsByID(game)["91"]
  eq(f and f.firstAfter, 1000, "a fight whose amounts were still hidden at once wasn't written a second later: ms after leave")
  countsAre(game, {})
end)

test("a session the meter carries on through a lull is written again with its grown duration, never for the meter's clock alone", function(game)
  game.login()
  game.advance(8)
  enterCombat(game)
  game.advance(3)
  table.insert(game.world.fights, { sessionID = 91, name = "Timber Wolf", durationSeconds = 9 })
  game.world.meterLate[91] = { at = game.clock + 0.5, how = "secret" }
  leaveCombat(game)
  game.advance(3)
  -- Another span of combat begins within a moment, and at its end the same session reports a
  -- longer duration and more damage, so it is written again (its amounts are still hidden at the
  -- instant, so by the read a second later).
  enterCombat(game)
  game.advance(2)
  game.world.meterDuration, game.world.meterTotal = 40, 300
  game.world.meterLate[91] = { at = game.clock + 0.5, how = "secret" }
  leaveCombat(game)
  game.advance(2)
  -- A span that ends with the session unchanged but for the meter's clock writes nothing.
  enterCombat(game)
  game.advance(2)
  leaveCombat(game)
  game.world.meterDuration = 41
  game.advance(2)
  local f = fightsByID(game)["91"]
  eq(f and f.count, 2, "the meter's session 91 was written this many times")
  eq(f and f.firstAfter, 1000, "the session's first line, ms after its leave")
  expect(f and f.lastDuration == 40 and f.lastAfter == 1000,
    "a session the meter carried on through another span of combat wasn't written again, a second after that span's end, with its grown duration: "
    .. tostring(f and f.lastDuration) .. " s, " .. tostring(f and f.lastAfter) .. " ms after leave")
end)

test("a fight whole at the instant is written once, not again when only the meter's clock ticks on", function(game)
  game.login()
  game.advance(8)
  enterCombat(game)
  game.advance(2)
  table.insert(game.world.fights, { sessionID = 92, name = "Mottled Boar", durationSeconds = 9 })
  leaveCombat(game)
  game.world.meterDuration = 25
  game.advance(2)
  local f = fightsByID(game)["92"]
  expect(f and f.firstAfter == 0 and f.count == 1,
    "a fight written whole at the instant was written again a second later, when only the meter's clock had moved on: "
    .. tostring(f and f.count) .. " lines")
end)

test("a fight running at a resume is written once at its end, with what it grew to, and its sheet after it", function(game)
  game.login()
  game.advance(8)
  -- A session that opens in the middle of a fight. The meter hides the fight's standing, so the
  -- opening seeds nothing of it, and the fight's end writes it once, whole, with what it grew to.
  game.slash("stop")
  game.world.combat = true
  table.insert(game.world.fights, { sessionID = 93, name = "Riverpaw Runt", durationSeconds = 6 })
  game.world.meterDuration, game.world.meterTotal = 6, 50
  game.slash("start")
  game.advance(8)
  game.world.meterDuration, game.world.meterTotal = 14, 120
  leaveCombat(game)
  game.advance(3)
  local lines93 = {}
  for _, l in ipairs(game.lines("FIGHT")) do
    if l.fields[1] == "93" then lines93[#lines93 + 1] = table.concat(l.fields, " ") end
  end
  expect(#lines93 == 1 and lines93[1]:match("^93 14 ") ~= nil,
    "a fight running at a resume wasn't written once at its end with what it grew to: "
    .. #lines93 .. " lines, " .. (lines93[1] or "none"))
  -- The session opened in combat, so the sheet its opening snapshot asked for was hidden: none
  -- inside the fight, and one in the second after it.
  local leftAt, before, after = nil, 0, 0
  for _, l in ipairs(game.lines(nil, 2)) do
    if l.kind == "COMBAT" and l.fields[1] == "leave" then leftAt = l.t end
    if l.kind == "STATS" then
      if not leftAt then before = before + 1 elseif l.t - leftAt <= 1500 then after = after + 1 end
    end
  end
  eq(game.lines("COMBAT", 2)[1] and game.lines("COMBAT", 2)[1].fields[1], "enter", "the session that opened in a fight starts with")
  eq(before, 0, "STATS lines written in the fight the session opened in")
  eq(after, 1, "STATS lines in the second after the fight the session opened in")
end)

test("a death announced in chat writes one DEATH and the recap, a player's hit with their GUID and the recap's name", function(game)
  game.login()
  game.advance(8)
  enterCombat(game)
  game.advance(3)
  table.insert(game.world.fights, { sessionID = 91, name = "Timber Wolf", durationSeconds = 9 })
  -- On death the game stops every mirror bar, shown or not; the recap is announced in chat as a
  -- link before PLAYER_DEAD, which fires twice for one death.
  game.fire("MIRROR_TIMER_STOP", "EXHAUSTION")
  game.fire("MIRROR_TIMER_STOP", "BREATH")
  game.fire("CHAT_MSG_SYSTEM", "|cff71d5ff|Hdeath:2|h[You died.]|h")
  game.fire("PLAYER_DEAD")
  game.fire("PLAYER_DEAD")
  leaveCombat(game)
  game.advance(3)
  game.fire("PLAYER_UNGHOST")
  eq(#game.lines("DEATH"), 1, "DEATH lines for one death announced twice")
  eq(#game.lines("ALIVE"), 1, "ALIVE lines after the death")
  -- Other players are named: a recap's hit from a player carries their GUID in full and the
  -- recap's name for them. The word Player is never written for a recap's source.
  local recapNamed, wordPlayer = false, false
  for _, l in ipairs(game.lines("RECAP")) do
    if l.fields[11] == "Player-4747-0BBBBBBB" and l.fields[14] == "Someone" then recapNamed = true end
    if l.fields[11] == "Player" then wordPlayer = true end
  end
  expect(#game.lines("RECAP") > 0, "no RECAP lines for a death the chat announced")
  expect(recapNamed, "a recap's hit from a player wasn't written with their GUID and the recap's name")
  expect(not wordPlayer, "the word Player was written for a caster or a recap's source")
end)

test("a death with no chat link and only an old recap writes no RECAP", function(game)
  game.login()
  game.advance(8)
  -- The latest recap on file is another death's: nothing may be written from it.
  game.world.recapStale = true
  game.fire("PLAYER_DEAD")
  game.fire("PLAYER_UNGHOST")
  game.world.recapStale = false
  game.advance(2)
  eq(#game.lines("DEATH"), 1, "DEATH lines for the death")
  eq(#game.lines("RECAP"), 0, "RECAP lines from a recap of an earlier death")
end)

test("the afk flag the game hides is an empty field in STATE, and is written again once it can be read", function(game)
  game.login()
  game.advance(8)
  -- A boss: the game hides whether the character is away for as long as it lasts.
  game.world.afkHidden = true
  game.advance(3)
  game.world.afkHidden = false
  game.advance(2)
  local stateShape, afkHiddenSeen, afkBack = true, false, false
  for _, l in ipairs(game.lines("STATE")) do
    if #l.fields ~= 8 then stateShape = false end
    if l.fields[7] == "" then afkHiddenSeen = true elseif afkHiddenSeen and l.fields[7] == "0" then afkBack = true end
  end
  expect(#game.lines("STATE") > 0, "no STATE line was written at all")
  expect(stateShape, "a STATE line hasn't its eight fields")
  expect(afkHiddenSeen, "no STATE line with an empty afk field while the game hid the flag")
  expect(afkBack, "no STATE line when the hidden afk flag could be read again")
end)

test("no STATS line inside a fight, and the sheet a gear change in a fight asked for follows it within 1.5 s", function(game)
  game.login()
  game.advance(8)
  expect(#game.lines("STATS") > 0, "no STATS line was written at all")
  enterCombat(game)
  -- A piece of gear changed in the fight: the sheet it asks for is hidden until the fight ends.
  -- The new piece raises the item level, so the sheet it asks for differs from the one written.
  game.world.inventory[10] = 3010
  game.G.GetAverageItemLevel = function() return 21, 19.5 end
  game.fire("PLAYER_EQUIPMENT_CHANGED", 10, false)
  game.advance(10)
  leaveCombat(game)
  game.advance(3)
  local fighting, leftAt, statsInFight, statsOwedWritten = false, nil, false, false
  for _, l in ipairs(game.lines()) do
    if l.kind == "COMBAT" then
      fighting = l.fields[1] == "enter"
      if not fighting then leftAt = l.t end
    elseif l.kind == "STATS" then
      if fighting then statsInFight = true end
      if leftAt and l.t - leftAt <= 1500 and l.fields[1] == "19.5000" then statsOwedWritten = true end
    end
  end
  expect(not statsInFight, "a STATS line was written while the game hid the sheet")
  expect(statsOwedWritten, "the sheet a fight hid wasn't written in the second after it")
end)

test("losing control writes CC for the character, never for another unit", function(game)
  game.login()
  game.advance(8)
  enterCombat(game)
  game.fire("LOSS_OF_CONTROL_ADDED", "player", 1)
  game.fire("LOSS_OF_CONTROL_ADDED", "targettarget", 1)
  game.advance(2)
  leaveCombat(game)
  game.advance(2)
  same(game.fieldsOf("CC"), { "STUN_MECHANIC 853 3 0 Stunned" }, "the CC lines")
end)

-- A pin of what the recorder does now, not a rule from a recording: the counters are read a
-- second after a fight ends (Moments.lua's afterFight), so a kill the game counted as combat ended
-- is written by that read; CRITERIA_UPDATE's own read two seconds later finds nothing new. The
-- counter was named in the opening pass, so the change carries no label.
test("a kill counted at the end of a fight is one TALLY, a second after combat ends", function(game)
  game.login()
  game.advance(8)
  same(game.fieldsOf("TALLY"), { "107 85 Creatures killed", "108 4 Critters killed", "60 1 Total deaths", "347 1 Food eaten",
    "1336 49 (Humanoid) Creature type killed the most" }, "the opening TALLY lines")
  enterCombat(game)
  game.advance(5)
  table.insert(game.world.fights, { sessionID = 89, name = "Kobold Geomancer", durationSeconds = 24 })
  leaveCombat(game)
  game.world.stat[107] = "86"
  game.fire("CRITERIA_UPDATE")
  game.advance(4)
  local leave = game.last("COMBAT")
  local changes = {}
  for _, l in ipairs(game.lines("TALLY")) do
    if leave and l.t >= leave.t then
      changes[#changes + 1] = table.concat(l.fields, " ") .. " @" .. (l.t - leave.t)
    end
  end
  same(changes, { "107 86  @1000" }, "the TALLY lines after the fight, with ms after leave")
end)
