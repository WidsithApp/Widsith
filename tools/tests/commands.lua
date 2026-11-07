-- The /widsith command (Core.lua's handleCommand) and what happens when something the player
-- asked for goes wrong: what each command answers in chat, what it does to the recording, and
-- that a fault in a click or a command is noted and answered without stopping anything. Also the
-- health line said ten seconds after a login.

-- Chat as the player reads it: colour codes left out.
local function plain(line)
  return (line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- The chat lines printed since the index given, as the player reads them.
local function chatSince(game, from)
  local out = {}
  for i = from + 1, #game.chat do out[#out + 1] = plain(game.chat[i]) end
  return out
end

-- The size the recorder states for a number of bytes (Core.lua's describeSize).
local function describeSize(bytes)
  if bytes >= 1024 * 1024 then return string.format("about %.1f MB", bytes / (1024 * 1024)) end
  return string.format("about %d KB", math.max(1, math.floor(bytes / 1024 + 0.5)))
end

-- One session's bytes as the recorder counts them: its packed chunks on file, and for the
-- session being recorded the lines still waiting in memory, each as it is written ("<ms>\t<raw>").
local function sessionBytes(game, n)
  local s = game.G.WidsithDB.sessions[n]
  local total = 0
  for _, c in ipairs(s.chunks) do total = total + #c end
  if not s.closed then
    local packed = s.lines or 0
    local lines = game.written[n].lines
    for i = packed + 1, #lines do total = total + #(tostring(lines[i].t) .. "\t" .. lines[i].raw) end
  end
  return total
end

---------------------------------------------------------------------------
-- Faults in what the player asked for
---------------------------------------------------------------------------

-- A click whose action throws: no Lua error reaches the player, the fault is an ERR line like any
-- other, and the player is answered. The guard the icon's actions wrap themselves in is pressed
-- as the menu's Pause would press it, with an action that fails. The recorder's write and warn are
-- stood in for the moment, to catch what the guard notes and says.
test("a click whose action throws is noted as ERR, answered in chat, and the recording goes on", { errAllowed = true, problemAllowed = true }, function(game)
  game.login()
  game.advance(8)
  local realWrite, realWarn = game.addon.write, game.addon.warn
  local noted, answered
  game.addon.write = function(kind, where, what) if kind == "ERR" then noted = where .. ": " .. tostring(what) end end
  game.addon.warn = function(text) answered = text end
  game.addon.attempt("pause", function() error("boom") end)()
  game.addon.write, game.addon.warn = realWrite, realWarn
  expect(noted and noted:find("^pause: ") and noted:find("boom", 1, true), "a click's fault wasn't noted as ERR pause: " .. tostring(noted))
  expect(answered and answered:find("didn't work", 1, true), "a click's fault wasn't answered in chat: " .. tostring(answered))
  expect(game.addon.isRecording(), "a failed pause stopped the recording")
end)

-- A command whose body throws, typed with spaces before it: no Lua error reaches the player, the
-- fault is an ERR line like any other, and the command is answered in chat.
test("a command whose body throws is noted as ERR command and answered in chat", { errAllowed = true, problemAllowed = true }, function(game)
  game.login()
  game.advance(8)
  local realCheck, realWrite, realWarn = game.addon.printClientCheck, game.addon.write, game.addon.warn
  local noted, answered
  game.addon.printClientCheck = function() error("boom") end
  game.addon.write = function(kind, where, what) if kind == "ERR" then noted = where .. ": " .. tostring(what) end end
  game.addon.warn = function(text) answered = text end
  game.slash("  check")
  game.addon.printClientCheck, game.addon.write, game.addon.warn = realCheck, realWrite, realWarn
  expect(noted and noted:find("^command: ") and noted:find("boom", 1, true), "a command's fault wasn't noted as ERR command: " .. tostring(noted))
  expect(answered and answered:find("didn't work", 1, true), "a command's fault wasn't answered in chat: " .. tostring(answered))
  expect(game.addon.isRecording(), "a failed command stopped the recording")
end)

---------------------------------------------------------------------------
-- /widsith check
---------------------------------------------------------------------------

-- What each client lacks of what the recorder uses, in the order the recorder lists them. WoW
-- Forever has no pet battles; Retail has no day and night and no stable.
local MISSING_FUNCTIONS = {
  forever = "C_PetBattles.IsInBattle, C_PetBattles.GetNumPets, C_PetBattles.GetPetSpeciesID, C_PetBattles.IsWildBattle, "
    .. "C_PetBattles.IsPlayerNPC",
  retail = "C_DateAndTime.IsDayTime, C_StableInfo.BuyStableSlot, C_StableInfo.GetNextStableSlotCost",
}
local MISSING_EVENTS = {
  forever = "PET_BATTLE_CLOSE, PET_BATTLE_FINAL_ROUND, PET_BATTLE_OPENING_START",
  retail = "DIEL_CYCLE_CHANGED",
}

test("/widsith check names the client and what it lacks: every message is there", function(game)
  game.login()
  game.advance(8)
  local from = #game.chat
  game.slash("check")
  local said = chatSince(game, from)
  local p = game.profile
  eq(said[1], "Widsith client " .. p.version .. " (build " .. p.build .. "), interface " .. p.interface .. ", project " .. p.project
    .. ", expansion level " .. p.expansion .. (p.label == "forever" and ": WoW Forever" or "") .. ".", "the client line")
  eq(said[2], "Widsith missing functions: " .. MISSING_FUNCTIONS[p.label], "the missing functions line")
  eq(said[3], "Widsith missing messages: none", "/widsith check didn't say every message is there")
  eq(said[4], "Widsith missing events: " .. MISSING_EVENTS[p.label], "the missing events line")
  eq(#said, 4, "lines /widsith check printed")
end)

---------------------------------------------------------------------------
-- The status line, help and about
---------------------------------------------------------------------------

test("/widsith alone says the version, the lines so far, the kills and quests, and the file", function(game)
  game.login()
  game.advance(8)
  local from = #game.chat
  game.slash("")
  local said = chatSince(game, from)
  local lines = #game.written[1].lines
  local plural = function(n, one, many) return n .. " " .. (n == 1 and one or many) end
  local c = game.addon.counts
  eq(said[1], "Widsith " .. game.version .. " is recording. This session: " .. plural(lines, "line", "lines") .. " so far ("
    .. plural(c.kills, "kill", "kills") .. ", " .. plural(c.quests, "quest", "quests") .. " taken or handed in). 1 session on file, "
    .. describeSize(sessionBytes(game, 1)) .. ".", "the status line")
  eq(said[2], "Widsith type /widsith help for commands.", "the status's last line")
  eq(#said, 2, "lines the status printed with all well and debug off")
end)

test("/widsith alone with debug on names the file's path by realm and character", function(game)
  game.login()
  game.advance(8)
  game.slash("debug")
  local from = #game.chat
  game.slash("")
  local said = chatSince(game, from)
  -- The path names the realm as GetRealmName gives it and the character by first name only.
  eq(said[2], "Widsith the file is WTF\\Account\\<account>\\" .. game.profile.realm .. "\\" .. game.character.name
    .. "\\SavedVariables\\Widsith.lua, written at logout or reload.", "the file's path line")
  eq(said[3], "Widsith no earlier sessions on file.", "what the file held before this load")
  eq(said[4], "Widsith type /widsith help for commands.", "the status's last line")
end)

test("/widsith alone while paused says so, and how to resume", function(game)
  game.login()
  game.advance(8)
  game.slash("pause")
  local from = #game.chat
  game.slash("")
  local said = chatSince(game, from)
  expect(said[1] and said[1]:find("^Widsith " .. game.version:gsub("%.", "%%.") .. " is paused; resume it from the icon or with /widsith resume%. 1 session on file, about %d+ KB%.$"),
    "the paused status line: " .. tostring(said[1]))
end)

local HELP = {
  "Widsith /widsith shows what has been recorded so far.",
  "Widsith /widsith help shows this list.",
  "Widsith /widsith about says what Widsith is.",
  "Widsith /widsith size says how big the recording is, and which sessions are the largest.",
  "Widsith /widsith pause stops recording until you resume, log in again or reload.",
  "Widsith /widsith resume starts recording again.",
  "Widsith /widsith save reloads the interface, which writes the recording to disk.",
  "Widsith /widsith icon shows or hides the recording icon.",
  "Widsith /widsith options opens the settings panel.",
  "Widsith /widsith check names the game client and lists anything Widsith uses that this client lacks.",
  "Widsith /widsith debug echoes every line to chat as it is recorded.",
}
local HELP_TESTING = {
  "Widsith these are for testing:",
  "Widsith /widsith remind shows the save reminder now.",
  "Widsith /widsith flush packs the lines waiting in memory into the file's chunks.",
  "Widsith /widsith qlog lists the quest log as the game reports it.",
}

test("/widsith help lists every command, and the testing ones only with debug on", function(game)
  game.login()
  game.advance(8)
  local from = #game.chat
  game.slash("help")
  same(chatSince(game, from), HELP, "help with debug off")
  game.slash("debug")
  from = #game.chat
  game.slash("help")
  local want = {}
  for _, l in ipairs(HELP) do want[#want + 1] = l end
  for _, l in ipairs(HELP_TESTING) do want[#want + 1] = l end
  same(chatSince(game, from), want, "help with debug on")
end)

test("/widsith about says the version, what it does and where recordings are replayed", function(game)
  game.login()
  game.advance(8)
  local from = #game.chat
  game.slash("about")
  same(chatSince(game, from), {
    "Widsith version " .. game.version .. ".",
    "Widsith keeps a record of your character's journey as you play: where you went, what you did and when.",
    "Widsith recordings are replayed at https://widsith.app.",
  }, "the about lines")
end)

---------------------------------------------------------------------------
-- /widsith size
---------------------------------------------------------------------------

test("/widsith size gives the total and the three largest sessions, this one marked", function(game)
  game.login()
  game.advance(8)
  -- Four sessions: three closed by pauses, the fourth recording. Each runs a different time,
  -- so their sizes differ.
  for i = 1, 3 do
    game.slash("pause")
    game.slash("resume")
    game.advance(8 + 60 * i)
  end
  eq(#game.G.WidsithDB.sessions, 4, "sessions on file after three pauses")
  local total, sizes = 0, {}
  for n = 1, 4 do
    local b = sessionBytes(game, n)
    total = total + b
    sizes[#sizes + 1] = { n = n, bytes = b }
  end
  table.sort(sizes, function(a, b) return a.bytes > b.bytes end)
  local from = #game.chat
  game.slash("size")
  local said = chatSince(game, from)
  eq(said[1], "Widsith 4 sessions on file, " .. describeSize(total) .. " in all. The game writes the whole file at every logout and reload.", "the total line")
  eq(#said, 4, "lines /widsith size printed: the total and three sessions")
  for i = 1, 3 do
    local e = sizes[i]
    local s = game.G.WidsithDB.sessions[e.n]
    local lines = #game.written[e.n].lines
    local want = "Widsith   session " .. e.n .. ": " .. describeSize(e.bytes) .. ", " .. lines .. " lines, started "
      .. os.date("%Y-%m-%d", s.startedAt) .. (e.n == 4 and " (this one)" or "")
    eq(said[i + 1], want, "the size's session line " .. i)
  end
end)

---------------------------------------------------------------------------
-- pause, resume, debug, flush
---------------------------------------------------------------------------

test("/widsith pause pauses, and a second pause says it already is", function(game)
  game.login()
  game.advance(8)
  game.slash("pause")
  expect(not game.addon.isRecording(), "still recording after /widsith pause")
  expect(game.said("recording paused. Nothing is recorded until you resume, log in again or reload."), "the pause wasn't said")
  eq(game.last("END").fields[2], "pause", "the END line's reason")
  local from = #game.chat
  game.slash("pause")
  same(chatSince(game, from), { "Widsith recording is already paused." }, "a second pause")
  eq(#game.lines("END"), 1, "END lines after two pauses")
end)

test("/widsith resume while recording says so; after a pause it starts a new session", function(game)
  game.login()
  game.advance(8)
  local from = #game.chat
  game.slash("resume")
  same(chatSince(game, from), { "Widsith is already recording." }, "resume while recording")
  eq(#game.written, 1, "sessions after a resume while recording")
  game.slash("pause")
  game.slash("resume")
  expect(game.addon.isRecording(), "not recording after /widsith resume")
  expect(game.said("recording resumed."), "the resume wasn't said")
  eq(#game.written, 2, "sessions after a pause and a resume")
  eq(game.written[2].lines[1].kind, "SESSION", "the resumed session's first line")
end)

test("/widsith debug echoes every line written to chat, and again turns it off", function(game)
  game.login()
  game.advance(8)
  local from = #game.chat
  game.slash("debug")
  same(chatSince(game, from), { "Widsith debug messages on. Every line is echoed to chat as it is recorded; type /widsith debug again to stop." }, "debug on")
  game.change(100)
  game.advance(1)
  local money = game.last("MONEY")
  expect(money ~= nil, "no MONEY line was written for the change")
  if money then
    local echo = "WJ MONEY " .. table.concat(money.fields, " ")
    local found = false
    for _, l in ipairs(game.chat) do if plain(l) == echo then found = true end end
    expect(found, "the MONEY line wasn't echoed to chat as " .. echo)
  end
  from = #game.chat
  game.slash("debug")
  same(chatSince(game, from), { "Widsith debug messages off." }, "debug off")
  from = #game.chat
  game.change(100)
  game.advance(1)
  eq(#game.lines("MONEY") >= 2, true, "a second MONEY line was written")
  for _, l in ipairs(chatSince(game, from)) do
    expect(not l:find("^WJ "), "a line was echoed with debug off: " .. l)
  end
end)

test("/widsith flush packs the lines in memory into the file without a logout", function(game)
  game.login()
  game.advance(8)
  eq(#game.onFile()[1].lines, 0, "lines in the file's chunks before the flush")
  local from = #game.chat
  game.slash("flush")
  same(chatSince(game, from), { "Widsith the lines waiting in memory are packed into the file's chunks; the game writes the file at the next logout or reload." }, "the flush's answer")
  local onFile = game.onFile()
  eq(#onFile[1].lines, #game.written[1].lines, "lines in the file's chunks after the flush against the lines written")
  expect(not onFile[1].closed, "the flush closed the session")
  expect(game.addon.isRecording(), "not recording after the flush")
end)

---------------------------------------------------------------------------
-- remind, qlog, options, save, icon
---------------------------------------------------------------------------

test("/widsith remind shows the reminder at once, with the icon's glow", function(game)
  game.login()
  game.advance(8)
  expect(game.reminder() == nil, "a reminder before anything was unsaved")
  game.slash("remind")
  local bubble = game.reminder()
  expect(bubble and bubble:IsShown(), "/widsith remind didn't show the reminder")
  local glow
  for _, r in ipairs(game.icon().regions) do
    if type(r.texture) == "string" and r.texture:find("\\media\\glow$") then glow = r end
  end
  expect(glow ~= nil, "no glow on the icon")
  expect(glow and glow:IsShown(), "the glow didn't light with a reminder shown on demand")
end)

test("/widsith qlog lists the quest log objective by objective", function(game)
  game.login()
  game.advance(8)
  game.slash("qlog")
  expect(game.said("200 An Old Errand: item 1/1 Old Letter"), "the quest log wasn't listed")
  expect(not game.addon.debug, "debug was left on after /widsith qlog")
end)

test("/widsith options opens the settings panel", function(game)
  game.login()
  game.advance(8)
  game.slash("options")
  eq(game.panel.openedTo, "Widsith", "the panel opened to")
end)

test("/widsith save saves as the icon does: the interface reloads", function(game)
  game.login()
  game.advance(8)
  game.slash("save")
  expect(game.reloadAsked, "/widsith save didn't ask for a reload")
end)

test("/widsith icon hides the icon and shows it again", function(game)
  game.login()
  game.advance(8)
  game.slash("icon")
  expect(not game.icon():IsShown(), "/widsith icon left the icon shown")
  expect(game.said("icon hidden. Bring it back from Options, AddOns, Widsith, or with /widsith icon."), "hiding wasn't explained")
  game.slash("icon")
  expect(game.icon():IsShown(), "a second /widsith icon didn't bring the icon back")
  expect(game.said("icon shown."), "showing wasn't said")
end)

---------------------------------------------------------------------------
-- What the command doesn't know
---------------------------------------------------------------------------

test("an unknown command is named back, with a pipe doubled to show as itself", function(game)
  game.login()
  game.advance(8)
  local from = #game.chat
  game.slash("foo")
  same(chatSince(game, from), { "Widsith doesn't know 'foo'. Type /widsith help for the commands." }, "an unknown command")
  from = #game.chat
  game.slash("a|b")
  same(chatSince(game, from), { "Widsith doesn't know 'a||b'. Type /widsith help for the commands." }, "an unknown command with a pipe")
end)

---------------------------------------------------------------------------
-- Health, ten seconds after a login
---------------------------------------------------------------------------

test("ten seconds after a login nothing is said when all is well", function(game)
  game.login()
  game.advance(8)
  local from = #game.chat
  game.advance(4)
  same(chatSince(game, from), {}, "chat between eight and twelve seconds after login")
end)

-- The sampler can't be kept from starting from outside the addon: its ticker is made inside the
-- login, before a test can step in. What can be made so is a sampler that fails every tick before
-- it notes that it ran: the position read throws, so the tick never stamps its clock, and the
-- health check finds no tick within three seconds.
test("ten seconds after a login, a sampler that never completes a tick is said", { errAllowed = true, problemAllowed = true }, function(game)
  game.login()
  game.addon.currentPosition = function() error("no position") end
  game.advance(12)
  expect(game.said("Problem the position sampler isn't running, so where you go isn't being recorded."), "the stopped sampler wasn't said")
  local err = game.last("ERR")
  expect(err and err.fields[1] == "tick", "the failing tick wasn't noted as ERR tick")
end)
