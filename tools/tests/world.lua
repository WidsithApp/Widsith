-- The world and the character's gear: the weather and the daylight (Events.lua), durability and
-- broken gear (Events.lua), gear changes and the worn items' strings (Extras.lua, Core.lua's
-- snapshot), and the READ emote the game performs when the map opens (Extras.lua's hooks).

---------------------------------------------------------------------------
-- Weather and daylight
---------------------------------------------------------------------------

-- The opening wrote rain at half strength. The same weather announced again writes nothing,
-- heavier rain announced three times writes one line, weather the game hides writes nothing (and
-- no ERR), and back as it was writes nothing.
test("weather is written once per change, however often it is announced, and hidden weather is skipped", function(game)
  game.login()
  game.advance(8)
  game.fire("WEATHER_CHANGED")
  game.world.weather = { type = 1, intensity = 0.8 }
  game.fire("WEATHER_CHANGED")
  game.fire("WEATHER_CHANGED")
  game.fire("WEATHER_CHANGED")
  local shownWeather = game.world.weather
  game.world.weather = game.SECRET
  game.fire("WEATHER_CHANGED")
  game.world.weather = shownWeather
  game.fire("WEATHER_CHANGED")
  game.advance(1)
  same(game.fieldsOf("WEATHER"), { "1 0.5000", "1 0.8000" }, "WEATHER lines")
end)

-- C_DateAndTime.IsDayTime and DIEL_CYCLE_CHANGED are WoW Forever's; Retail has neither. The
-- opening wrote day; night falls, announced twice, and is written once.
test("daylight is written at the opening and once when night falls", { client = "forever" }, function(game)
  game.login()
  game.advance(8)
  game.world.daytime = false
  game.fire("DIEL_CYCLE_CHANGED", false)
  game.fire("DIEL_CYCLE_CHANGED", false)
  game.advance(1)
  same(game.fieldsOf("DAYLIGHT"), { "1", "0" }, "DAYLIGHT lines")
end)

-- On Retail there is no IsDayTime to read at the opening, and DIEL_CYCLE_CHANGED can't be
-- registered, so the event never reaches the recorder.
test("a client without the day and night cycle writes no DAYLIGHT", { client = "retail" }, function(game)
  game.login()
  game.advance(8)
  game.world.daytime = false
  game.fire("DIEL_CYCLE_CHANGED", false)
  game.advance(1)
  same(game.fieldsOf("DAYLIGHT"), {}, "DAYLIGHT lines")
end)

-- Heavier rain and night, then a pause and a resume, then a reload: each later session opens
-- with the weather and (where the client has it) the night, as they are then.
test("each later session opens with the weather and the time of day", function(game)
  game.login()
  game.advance(8)
  game.world.weather = { type = 1, intensity = 0.8 }
  game.fire("WEATHER_CHANGED")
  game.world.daytime = false
  game.fire("DIEL_CYCLE_CHANGED", false)
  game.advance(1)
  game.slash("pause")
  game.advance(5)
  game.slash("resume")
  game.advance(8)
  game.clickSave()
  game.advance(8)
  eq(#game.written, 3, "sessions after a pause, a resume and a reload")
  local wantDaylight = game.profile.dayTime and { "0" } or {}
  for s = 2, #game.written do
    same(game.fieldsOf("WEATHER", s), { "1 0.8000" }, "session " .. s .. "'s opening weather")
    same(game.fieldsOf("DAYLIGHT", s), wantDaylight, "session " .. s .. "'s opening daylight")
  end
end)

---------------------------------------------------------------------------
-- Durability and broken gear
---------------------------------------------------------------------------

-- A fight's burst of the event while the boots wear down to nothing. No read at any event, one
-- pass five seconds after the first, one BROKEN for the boots; the legs, broken since the
-- session opened, never write one. The waist (6) is at 30/40, the legs (7) at 0/50 and the feet
-- (8) at 12/60 from the start.
test("a burst of durability events reads once, five seconds on, and writes one BROKEN for the boots", function(game)
  game.login()
  game.advance(8)
  local burstFromMs = game.addon.nowMs()
  local readsBefore = game.world.durabilityReads
  for i = 1, 20 do
    if i == 10 then game.world.durability[8] = { 0, 60 } end
    game.fire("UPDATE_INVENTORY_DURABILITY")
    game.advance(0.1)
  end
  local readsInBurst = game.world.durabilityReads - readsBefore
  game.advance(5)
  local readsAfterBurst = game.world.durabilityReads - readsBefore
  eq(readsInBurst, 0, "durability reads at the events themselves")
  eq(readsAfterBurst, game.addon.EQUIP_SLOTS, "slots a burst of the durability event read (one pass)")
  same(game.fieldsOf("BROKEN"), { "8 3003" }, "BROKEN lines")
  local broken = game.last("BROKEN")
  local brokenAt = broken and (broken.t - burstFromMs)
  expect(brokenAt and brokenAt >= 0 and brokenAt <= 5000,
    "the BROKEN line wasn't written within five seconds of the burst's start: " .. tostring(brokenAt) .. " ms")
end)

-- A long fight, the event every half second for twelve seconds: the boots repaired, a belt put
-- on already broken, the legs' durability hidden for a while and back at zero; no BROKEN, and a
-- pass at most every five seconds.
test("a long fight's durability events make a pass each five seconds and no BROKEN for gear that didn't break", function(game)
  game.login()
  game.advance(8)
  game.world.durability[8] = { 0, 60 }   -- the boots already broken as this fight starts
  local readsBefore = game.world.durabilityReads
  for i = 1, 24 do
    if i == 2 then game.world.durability[8] = { 60, 60 } end
    if i == 6 then game.world.inventory[6], game.world.durability[6] = 3004, { 0, 40 } end
    if i == 10 then game.world.durability[7] = game.SECRET end
    if i == 20 then game.world.durability[7] = { 0, 50 } end
    game.fire("UPDATE_INVENTORY_DURABILITY")
    game.advance(0.5)
  end
  game.advance(6)
  local passesInFight = (game.world.durabilityReads - readsBefore) / game.addon.EQUIP_SLOTS
  expect(passesInFight >= 2 and passesInFight <= 3,
    "a twelve-second fight's durability events made " .. passesInFight .. " passes, not one each five seconds")
  same(game.fieldsOf("BROKEN"), {}, "BROKEN lines")
end)

-- Every SNAP lists each worn slot's durability as current/max, an empty entry for a slot with
-- none or one the game hides. Here the later snapshot is taken with the legs' values hidden.
test("every SNAP's durability field has one entry per slot, and the opening's is each slot's current/max", function(game)
  game.login()
  game.advance(8)
  game.world.durability[7] = game.SECRET
  game.advance(game.addon.TIMER_PERIOD + 2)
  game.world.durability[7] = { 0, 50 }
  game.advance(game.addon.TIMER_PERIOD + 2)
  local snaps = game.lines("SNAP")
  expect(#snaps >= 3, "SNAP lines: " .. #snaps .. ", wanted the opening and two more")
  local wantWear = {}
  for slot = 1, game.addon.EQUIP_SLOTS do wantWear[slot] = "" end
  wantWear[6], wantWear[7], wantWear[8] = "30/40", "0/50", "12/60"
  eq(snaps[1] and snaps[1].fields[11], table.concat(wantWear, ","), "the opening SNAP's durability")
  for i, l in ipairs(snaps) do
    local entries = select(2, (l.fields[11] or ""):gsub(",", ",")) + 1
    eq(entries, game.addon.EQUIP_SLOTS, "entries in SNAP " .. i .. "'s durability field")
  end
end)

---------------------------------------------------------------------------
-- Gear changes and the worn items' strings
---------------------------------------------------------------------------

local function equipLines(game, slot)
  local out = {}
  for _, l in ipairs(game.lines("EQUIP")) do
    if l.fields[1] == tostring(slot) then out[#out + 1] = l end
  end
  return out
end

-- A quest's disguise comes off: the event fires for the head while the slot is empty, and the
-- helm goes back on with no event of its own; the re-read a second later writes it.
test("a slot read empty at its event and filled a second later is written again by the re-read", function(game)
  game.login()
  game.advance(8)
  game.fire("PLAYER_EQUIPMENT_CHANGED", 1, true)
  game.advance(0.2)
  game.world.inventory[1] = 10001
  game.advance(2)
  local head = equipLines(game, 1)
  expect(#head == 2 and head[1].fields[2] == "" and head[2].fields[2] == "10001" and math.abs(head[2].t - head[1].t - 1000) <= 1,
    "a slot read empty at its event and filled a second later wasn't written again by the re-read: "
    .. #head .. " EQUIP lines for the head")
end)

-- A ring changed twice within the second: one line for each event, and the one re-read finds
-- what was written and adds nothing.
test("a slot changed twice within the second writes one EQUIP for each event", function(game)
  game.login()
  game.advance(8)
  game.world.inventory[11] = 2001
  game.fire("PLAYER_EQUIPMENT_CHANGED", 11, false)
  game.advance(0.5)
  game.world.inventory[11] = 2002
  game.fire("PLAYER_EQUIPMENT_CHANGED", 11, false)
  game.advance(2)
  local ring = equipLines(game, 11)
  eq(#ring, 2, "EQUIP lines for a slot changed twice within the second (one for each event)")
end)

-- A weapon put on: the re-read a second later finds the same item and writes nothing more.
test("a slot that reads the same a second later writes one EQUIP", function(game)
  game.login()
  game.advance(8)
  game.world.inventory[16] = 2209
  game.fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
  game.advance(2)
  eq(#equipLines(game, 16), 1, "EQUIP lines for a slot that read the same a second later")
end)

-- Gear as linked: every EQUIP with an item carries its item string, an emptied slot none. A
-- session's first SNAP lists the worn items' strings, later ones only when they changed. The
-- five-minute snapshots: one with nothing changed, one after a ring is put on, one after that
-- with nothing changed; then a pause and a resume, whose session's first SNAP lists them again.
test("EQUIP carries the item string, and a SNAP lists the worn strings first and then only when they changed", function(game)
  game.login()
  game.advance(8)
  game.advance(game.addon.TIMER_PERIOD + 2)
  game.world.inventory[11] = 2001
  game.fire("PLAYER_EQUIPMENT_CHANGED", 11, false)
  game.advance(2)
  game.world.inventory[6] = nil
  game.fire("PLAYER_EQUIPMENT_CHANGED", 6, true)
  game.advance(2)
  game.advance(game.addon.TIMER_PERIOD + 2)
  game.advance(game.addon.TIMER_PERIOD + 2)
  game.slash("pause")
  game.advance(5)
  game.slash("resume")
  game.advance(8)
  game.advance(game.addon.TIMER_PERIOD + 2)
  eq(#game.written, 2, "sessions after a pause and a resume")

  local equipStringsRight, emptied = true, false
  for _, l in ipairs(game.lines("EQUIP")) do
    local item = l.fields[2] or ""
    local want = item ~= "" and ("item:" .. item .. "::::::::1:::::::") or ""
    if (l.fields[3] or "") ~= want then equipStringsRight = false end
    if item == "" then emptied = true end
  end
  expect(emptied, "no EQUIP line for the emptied slot")
  expect(equipStringsRight, "an EQUIP line's item string doesn't match its item")

  local snapFirstHas, snapLaterEmpty, snapRepeats, snapChangedListed = true, false, false, false
  for s = 1, #game.written do
    local firstSnap, lastStrings = true, nil
    for _, l in ipairs(game.lines("SNAP", s)) do
      local strings = l.fields[10] or ""
      if firstSnap then
        if strings == "" then snapFirstHas = false end
        firstSnap = false
      elseif strings == "" then
        snapLaterEmpty = true
      elseif strings == lastStrings then
        snapRepeats = true
      else
        snapChangedListed = true
      end
      if strings ~= "" then lastStrings = strings end
    end
  end
  expect(snapFirstHas, "a session's first SNAP doesn't list the worn items' strings")
  expect(snapLaterEmpty, "no later SNAP left the strings out although nothing changed")
  expect(not snapRepeats, "a SNAP repeated the strings it had already written")
  expect(snapChangedListed, "the SNAP after the gear changed didn't list the new strings")
end)

---------------------------------------------------------------------------
-- The map's own READ emote
---------------------------------------------------------------------------

-- The game performs READ itself as the world map opens, with the map's frame already shown
-- when the hook sees it: that one is the map's and is left out. A READ with the map closed is
-- the player's own and is written.
test("the READ the game performs as the map opens is left out, and the player's own is written", function(game)
  game.login()
  game.advance(8)
  game.world.mapShown = true
  game.G.C_ChatInfo.PerformEmote("READ")
  game.world.mapShown = false
  game.G.C_ChatInfo.PerformEmote("READ")
  game.advance(1)
  local reads = 0
  for _, l in ipairs(game.lines("EMOTE")) do
    if l.fields[1] == "READ" then reads = reads + 1 end
  end
  expect(reads == 1, "READ written " .. reads .. " times: the map's own should be left out, the player's kept")
end)
