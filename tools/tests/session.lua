-- Sessions and the lines that keep time (Core.lua and Position.lua): the SESSION line that opens
-- each one and the END that closes it, the opening snapshot, the periodic TIME, SNAP and COUNT,
-- the file's size each session states, and what a loading screen does to the periodic lines and
-- to experience and money the game changed behind it (Events.lua).

-- The fields of the first line of a kind at or after a time, and its place in the session.
local function firstAfter(lines, kind, fromMs, test)
  for i, l in ipairs(lines) do
    if l.kind == kind and l.t >= fromMs and (test == nil or test(l)) then return l, i end
  end
end

test("a login opens a session whose SESSION line names the time, the versions, the client and the character", function(game)
  game.login()
  local serverTime = game.G.GetServerTime()
  game.advance(8)
  local first = game.written[1] and game.written[1].lines[1]
  expect(first ~= nil and first.kind == "SESSION", "the login's first line isn't SESSION")
  if not first then return end
  eq(first.t, 0, "the SESSION line's time")
  local f = first.fields
  eq(#f, 12, "the SESSION line's field count")
  eq(f[1], tostring(serverTime), "the SESSION line's server time")
  eq(f[2], game.version, "the addon's version")
  eq(f[3], "1", "the line format")
  eq(f[4], game.profile.version, "the client's version")
  eq(f[5], game.profile.build, "the client's build")
  eq(f[6], tostring(game.profile.project), "the client's project")
  eq(f[7], "enUS", "the client's locale")
  eq(f[8], "1", "isLogin at a login")
  eq(f[9], "0", "isReload at a login")
  eq(f[10], game.character.guid, "the character's GUID")
  eq(f[11], "", "the resume flag at a login")
  eq(f[12], "0", "the file's size before the first session")
end)

test("a pause closes the session with END pause, and the resume opens one that says it is a resume", function(game)
  game.login()
  game.advance(8)
  game.slash("pause")
  local ended = game.last("END")
  expect(ended ~= nil, "no END line at the pause")
  if ended then
    eq(ended.fields[1], tostring(game.G.GetServerTime()), "the END line's server time")
    eq(ended.fields[2], "pause", "the END line's reason")
  end
  eq(game.written[1].lines[#game.written[1].lines].kind, "END", "the paused session's last line")
  game.advance(20)
  game.slash("resume")
  game.advance(8)
  eq(#game.written, 2, "sessions after a pause and a resume")
  local opening = game.written[2] and game.written[2].lines[1]
  expect(opening and opening.kind == "SESSION", "the resumed session doesn't open with SESSION")
  if opening then
    eq(opening.fields[1], tostring(game.G.GetServerTime() - 8), "the resumed SESSION line's server time")
    eq(opening.fields[8], "0", "isLogin at a resume")
    eq(opening.fields[9], "0", "isReload at a resume")
    eq(opening.fields[11], "1", "the resume flag at a resume")
    expect(tonumber(opening.fields[12]) and tonumber(opening.fields[12]) > 0,
      "the resumed SESSION line doesn't say what the file held before it: " .. tostring(opening.fields[12]))
  end
end)

test("the opening snapshot is written five seconds in, with the state that has no event of its own", function(game)
  game.login()
  game.advance(4)
  eq(#game.lines("SNAP"), 0, "SNAP lines before five seconds")
  game.advance(4)
  local snap = game.lines("SNAP")
  eq(#snap, 1, "SNAP lines after the opening")
  eq(snap[1] and snap[1].t, 5000, "the opening SNAP's time")
  -- The SNAP reads the level, experience, its maximum and the money the world holds.
  if snap[1] then
    eq(snap[1].fields[1], "5", "the opening SNAP's level")
    eq(snap[1].fields[2], "100", "the opening SNAP's experience")
    eq(snap[1].fields[3], "2800", "the opening SNAP's maximum")
    eq(snap[1].fields[4], "334", "the opening SNAP's money")
  end
  for _, kind in ipairs({ "COUNT", "STATS", "TALLY", "RULES", "REP", "CURRENCY" }) do
    expect(#game.lines(kind) > 0, "the opening wrote no " .. kind .. " line")
  end
  -- A login has no TIME line: the SESSION line states the server time.
  eq(#game.lines("TIME"), 0, "TIME lines in the opening")
end)

test("TIME, SNAP and COUNT are written every period", function(game)
  game.login()
  local startedAt = tonumber(game.G.GetServerTime())
  game.advance(8)
  local period = game.addon.TIMER_PERIOD
  game.advance(period - 8 - 1)
  eq(#game.lines("TIME"), 0, "TIME lines before the first period")
  eq(#game.lines("SNAP"), 1, "SNAP lines before the first period")
  game.advance(2)
  local times = game.lines("TIME")
  eq(#times, 1, "TIME lines after one period")
  eq(times[1] and times[1].t, period * 1000, "the first TIME line's time")
  eq(times[1] and times[1].fields[1], tostring(startedAt + period), "the first TIME line's server time")
  local snaps, counts = game.lines("SNAP"), game.lines("COUNT")
  eq(#snaps, 2, "SNAP lines after one period")
  eq(#counts, 2, "COUNT lines after one period")
  eq(snaps[2] and snaps[2].t, period * 1000, "the periodic SNAP's time")
  eq(counts[2] and counts[2].t, period * 1000, "the periodic COUNT's time")
  -- TIME comes first, then the SNAP and the COUNT.
  local lines = game.written[1].lines
  local _, timeAt = firstAfter(lines, "TIME", 0)
  local _, snapAt = firstAfter(lines, "SNAP", period * 1000)
  local _, countAt = firstAfter(lines, "COUNT", period * 1000)
  expect(timeAt and snapAt and countAt and timeAt < snapAt and snapAt < countAt, "the periodic lines aren't TIME, SNAP, COUNT in that order")
  game.advance(period)
  eq(#game.lines("TIME"), 2, "TIME lines after two periods")
  eq(#game.lines("SNAP"), 3, "SNAP lines after two periods")
  eq(#game.lines("COUNT"), 3, "COUNT lines after two periods")
end)

-- A session's opening line says how big the file was before it: a number, never smaller than
-- the one before. Several sessions, made by a pause and a resume, a reload, and another pause
-- and resume, then a logout that packs them all into the file.
test("each SESSION line says what the file held before it, and the sizes never shrink", function(game)
  game.login()
  game.advance(8)
  game.slash("pause")
  game.slash("resume")
  game.advance(8)
  game.reload()
  game.advance(8)
  game.slash("pause")
  game.advance(5)
  game.slash("resume")
  game.advance(8)
  game.logout()
  local onFile = game.onFile()
  eq(#onFile, 4, "sessions on file")
  local sizeFields, sizesInOrder, previous = 0, true, nil
  local sizes = {}
  for _, session in ipairs(onFile) do
    local first = session.lines[1]
    local bytes = first and first.kind == "SESSION" and tonumber(first.fields[12]) or nil
    sizes[#sizes + 1] = tostring(bytes)
    if bytes then
      sizeFields = sizeFields + 1
      if previous and bytes < previous then sizesInOrder = false end
      previous = bytes
    end
  end
  expect(sizeFields == #onFile and sizesInOrder,
    "a SESSION line doesn't say what the file held before it, or the sizes don't grow: " .. table.concat(sizes, " / "))
  eq(sizes[1], "0", "the first session's size")
end)

-- A loading screen across the five-minute mark: the periodic lines wait for its end. Behind it
-- the game grants experience for the place arrived in, and money moves, with neither
-- PLAYER_XP_UPDATE nor PLAYER_MONEY heard: both are written on arrival, before the SNAP.
test("a loading screen holds the periodic lines back, and what changed behind it is written on arrival", function(game)
  game.login()
  local sessionAt = game.clock
  game.advance(8)
  local period = game.addon.TIMER_PERIOD
  local loadingFrom = sessionAt + period - 2.5
  local loadingTo = loadingFrom + 5
  local clockBeforeScreen = game.clock
  game.advance(loadingFrom - game.clock)
  game.fire("LOADING_SCREEN_ENABLED")
  game.advance(2)
  game.world.xp = game.world.xp + 85
  game.world.money = game.world.money + 250
  game.advance(loadingTo - game.clock)
  game.fire("PLAYER_ENTERING_WORLD", false, false)
  game.fire("LOADING_SCREEN_DISABLED")
  game.advance(3)
  expect(clockBeforeScreen < loadingFrom, "the scenes ran past the loading screen's start")

  local first = game.written[1].lines
  local screenFromMs, screenToMs = (loadingFrom - sessionAt) * 1000, (loadingTo - sessionAt) * 1000
  local snapsInScreen, snapAfterScreen = 0, nil
  for _, l in ipairs(first) do
    if l.kind == "SNAP" then
      if l.t >= screenFromMs and l.t <= screenToMs then snapsInScreen = snapsInScreen + 1 end
      if l.t > screenToMs and not snapAfterScreen then snapAfterScreen = l.t - screenToMs end
    end
  end
  -- What the game granted behind the screen, written on arrival and before the SNAP.
  local xpAt, moneyAt, xpIndex, moneyIndex, snapIndex, moneyLine
  for i, l in ipairs(first) do
    if l.t >= screenToMs then
      if l.kind == "XP" and not xpAt and table.concat(l.fields, " ") == "185 2800 5" then xpAt, xpIndex = l.t, i end
      if l.kind == "MONEY" and not moneyAt then moneyAt, moneyIndex, moneyLine = l.t, i, l end
      if l.kind == "SNAP" and not snapIndex then snapIndex = i end
    end
  end
  expect(xpAt and xpAt - screenToMs <= 50,
    "experience granted behind a loading screen wasn't written on arrival: " .. tostring(xpAt and xpAt - screenToMs) .. " ms after it")
  expect(moneyAt and moneyAt - screenToMs <= 50,
    "money moved behind a loading screen wasn't written on arrival: " .. tostring(moneyAt and moneyAt - screenToMs) .. " ms after it")
  expect(snapIndex and xpIndex and moneyIndex and xpIndex < snapIndex and moneyIndex < snapIndex,
    "the SNAP after the loading screen came before the lines of what changed behind it")
  -- The money that moved behind the screen has no reason: no window, no message, no source.
  same(moneyLine and moneyLine.fields or {}, { "584", "", "", "", "" }, "money that moved behind a loading screen")
  expect(snapsInScreen == 0, "a SNAP was written while a loading screen was up")
  expect(snapAfterScreen ~= nil and snapAfterScreen <= 1000,
    "the SNAP held back by a loading screen wasn't written at the first tick after it: "
    .. tostring(snapAfterScreen) .. " ms after the screen")
  same(game.fieldsOf("LOADSCREEN"), { "5.0" }, "LOADSCREEN lines")
end)

-- An arrival whose PLAYER_ENTERING_WORLD comes before the client has loaded the character:
-- experience, its maximum and money read 0 there, though the game granted 60 experience and 75
-- copper behind the screen. Nothing is written at the arrival; the five-minute snapshot writes
-- both once the values are real. Then experience the game grants with no PLAYER_XP_UPDATE heard,
-- before that snapshot: the snapshot reads it first, so an XP line comes before the SNAP that
-- shows it. (Played in the login's session; a resumed one opens the same way.)
test("an arrival read before the character has loaded writes nothing, and the next snapshot writes what changed first", function(game)
  game.login()
  local sessionAt = game.clock
  game.advance(8)
  game.fire("LOADING_SCREEN_ENABLED")
  game.advance(1)
  game.world.xp = game.world.xp + 60
  game.world.money = game.world.money + 75
  game.advance(2)
  game.world.notLoaded = true
  local unloadedArrivalMs = (game.clock - sessionAt) * 1000
  game.fire("PLAYER_ENTERING_WORLD", false, false)
  game.world.notLoaded = false
  game.fire("LOADING_SCREEN_DISABLED")
  game.advance(2)
  game.world.xp = game.world.xp + 40
  game.advance(sessionAt + game.addon.TIMER_PERIOD + 2 - game.clock)
  local xpNow = game.world.xp

  -- The experience no event announced, written as XP before the five-minute SNAP that shows it
  -- (and the arrival read while the character wasn't loaded wrote nothing: no XP or MONEY line
  -- from that arrival until the snapshot's own, and the snapshot's MONEY line has its total).
  local xpWritten, snapShows, xpFirst, moneyFirst = false, false, false, false
  local moneyTotal, earlyLines = nil, 0
  for _, l in ipairs(game.written[1].lines) do
    if not snapShows and (l.kind == "XP" or l.kind == "MONEY") and l.t >= unloadedArrivalMs then
      if l.t < (game.addon.TIMER_PERIOD - 1) * 1000 then earlyLines = earlyLines + 1 end
      if l.kind == "MONEY" then moneyTotal = l.fields[1] end
    end
    if l.kind == "XP" and l.fields[1] == tostring(xpNow) then xpWritten = true end
    if l.kind == "SNAP" and l.fields[2] == tostring(xpNow) and not snapShows then
      snapShows, xpFirst = true, xpWritten
      moneyFirst = moneyTotal ~= nil and moneyTotal == l.fields[4]
    end
  end
  expect(snapShows, "no SNAP showed the experience the game granted without an event")
  expect(xpFirst, "experience granted without an event reached a SNAP with no XP line before it")
  expect(earlyLines == 0, earlyLines .. " XP or MONEY lines written from an arrival read before the character had loaded")
  expect(moneyFirst, "money the game moved behind a loading screen read before loading reached a SNAP with no MONEY line of its total before it")
end)

test("experience granted with no event before a periodic snapshot is written as XP before the SNAP", function(game)
  game.login()
  local sessionAt = game.clock
  game.advance(8)
  game.world.xp = game.world.xp + 40
  game.advance(sessionAt + game.addon.TIMER_PERIOD + 2 - game.clock)
  local periodMs = game.addon.TIMER_PERIOD * 1000
  local lines = game.written[1].lines
  local xp, xpAt = firstAfter(lines, "XP", 0)
  local snap, snapAt = firstAfter(lines, "SNAP", periodMs)
  expect(xp ~= nil, "no XP line for experience granted without an event")
  if xp then
    eq(table.concat(xp.fields, " "), "140 2800 5", "the XP line's fields")
    eq(xp.t, periodMs, "the XP line's time")
  end
  expect(snap and snap.fields[2] == "140", "the periodic SNAP doesn't show the experience granted")
  expect(xpAt and snapAt and xpAt < snapAt, "the XP line didn't come before the SNAP that shows it")
end)

test("a logout closes the session with END and every line is on file", function(game)
  game.login()
  game.advance(8)
  local saved = game.logout()
  local ended = game.last("END")
  expect(ended ~= nil, "no END line at the logout")
  if ended then
    eq(ended.fields[1], tostring(game.G.GetServerTime()), "the END line's server time")
    eq(ended.fields[2], "", "the END line's reason at a logout")
  end
  expect(saved and saved.WidsithDB and saved.WidsithDB.sessions and #saved.WidsithDB.sessions == 1,
    "the saved file doesn't hold the one session")
  local onFile = game.onFile()
  eq(#onFile, 1, "sessions on file after a logout")
  if onFile[1] then
    expect(onFile[1].closed, "the session wasn't closed by the logout")
    eq(#onFile[1].lines, #game.written[1].lines, "the session's lines on file against the lines written")
    eq(onFile[1].lines[#onFile[1].lines].kind, "END", "the session's last line on file")
    for i, l in ipairs(game.written[1].lines) do
      local f = onFile[1].lines[i]
      if not (f and f.raw == l.raw and f.t == l.t) then
        fail("line " .. i .. " on file isn't the line written: " .. tostring(f and f.raw) .. " against " .. l.raw)
        break
      end
    end
  end
end)
