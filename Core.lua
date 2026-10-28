-- Widsith — Core
--
-- Session lifecycle, the line writer, chunked storage into SavedVariables,
-- and the /widsith command.
--
-- The recording is a list of sessions (one per login, reload or resume), each
-- a list of text lines: "<ms since session start> <TYPE> <fields…>", tab
-- separated. Every line is a fact the game stated, with IDs rather than names
-- wherever the game gives one; names ride along only as labels. This file is
-- the only place that knows how lines are laid out in the saved file.

local ADDON_NAME, WJ = ...
_G.Widsith = WJ

WJ.NAME          = "Widsith"
WJ.PREFIX        = "|cff33ff99" .. WJ.NAME .. "|r "
WJ.FORMAT        = 1     -- the line format; bumped only if a line's meaning changes
WJ.VERSION       = C_AddOns and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "0.0.0"
WJ.CHUNK_LINES   = 256
WJ.TIMER_PERIOD  = 300   -- seconds between TIME / SNAP / COUNT lines

-- Which client this is. WoW Forever runs the Mainline client and API with a
-- Classic-range interface number (16001 on 1.60.1). Its WOW_PROJECT_ID was
-- Mainline's (1) on its early builds and is 18 from build 70205 on; the Classic
-- flavours, whose interface numbers are in the same range, have IDs of their own.
local FOREVER_PROJECTS = { [WOW_PROJECT_MAINLINE or 1] = true, [18] = true }
WJ.INTERFACE = select(4, GetBuildInfo()) or 0
WJ.isForever = FOREVER_PROJECTS[WOW_PROJECT_ID] == true and WJ.INTERFACE < 100000

---------------------------------------------------------------------------
-- Value sanitising
---------------------------------------------------------------------------

local issecretvalue = issecretvalue
local floor, format, tostring, type = math.floor, string.format, tostring, type

-- Turn any Lua value into a field string. Secrets, nils and unknown types
-- become the empty field so a line never fails to write.
local function field(v)
  if v == nil then return "" end
  if issecretvalue and issecretvalue(v) then return "" end
  local t = type(v)
  if t == "number" then
    -- Whole numbers through %.0f, not %d: the client's %d may be 32-bit, which would wrap
    -- money above ~214,748 gold. %.0f is exact to 2^53 and never uses exponent notation.
    -- Zero is spelled out so a negative zero can't become "-0".
    if v == 0 then return "0" end
    if v % 1 == 0 then return format("%.0f", v) end
    return format("%.4f", v)
  elseif t == "string" then
    return (v:gsub("[\t\r\n]", " "))
  elseif t == "boolean" then
    return v and "1" or "0"
  end
  return ""
end
WJ.field = field

-- Format a 0..1 map coordinate. nil stays empty.
function WJ.coord(v)
  if v == nil or (issecretvalue and issecretvalue(v)) then return "" end
  return format("%.4f", v)
end

-- Comma list of fields.
function WJ.list(tbl)
  local out = {}
  for i = 1, #tbl do out[i] = field(tbl[i]) end
  return table.concat(out, ",")
end

---------------------------------------------------------------------------
-- Session state
---------------------------------------------------------------------------

local db                 -- WidsithDB
local session            -- current session table inside db.sessions
local buffer = {}        -- lines not yet packed into a chunk
local startClock         -- GetTime() at session start
local paused = false     -- see WJ.pause(); declared here so WJ.health() sees it
local previousOnFile     -- what the file held of the session before this load's first, for debug mode
local counts = { pos = 0, kills = 0, loot = 0, xp = 0, quests = 0, deaths = 0, jumps = 0, shots = 0, emotes = 0 }
WJ.counts = counts

local function nowMs()
  return floor((GetTime() - startClock) * 1000 + 0.5)
end
WJ.nowMs = nowMs

local function flush()
  if not session or #buffer == 0 then return end
  session.chunks[#session.chunks + 1] = table.concat(buffer, "\n")
  session.lines = (session.lines or 0) + #buffer
  buffer = {}
end

-- Append one line: <t> <TYPE> <fields...>
function WJ.write(kind, ...)
  if not session then return end
  local n = select("#", ...)
  local parts = { nowMs(), kind }
  for i = 1, n do
    parts[i + 2] = field((select(i, ...)))
  end
  buffer[#buffer + 1] = table.concat(parts, "\t")
  if #buffer >= WJ.CHUNK_LINES then flush() end
  if WJ.debug then print("|cff8888ffWJ|r " .. table.concat(parts, " ", 2)) end
end

function WJ.isRecording()
  return session ~= nil
end

-- The file was last written by the logout or reload that began this session,
-- so everything recorded since then is unsaved (Save.lua's reminder).
function WJ.secondsSinceSave()
  if not session then return 0 end
  return GetTime() - startClock
end

---------------------------------------------------------------------------
-- Chat. Nothing here is recorded.
---------------------------------------------------------------------------

local PREFIX = WJ.PREFIX
local errorCount = 0
local answering = false   -- true while a /widsith command the player typed is running

-- The recorder's own news (a session starting, a pause), which the player can switch off
-- in the icon's menu. WidsithUI is that menu's settings table; it is created when the
-- addon loads, after this file has run, so it is looked up each time. The answer to a
-- command the player typed always shows.
function WJ.say(text)
  local ui = WidsithUI
  if answering or ui == nil or ui.chat ~= false then print(PREFIX .. text) end
end

-- A real problem, which always shows.
function WJ.warn(text)
  print(PREFIX .. "|cffff4444Problem|r " .. text)
end

-- "1 line", "2 lines".
local function count(n, one, many)
  return format("%d %s", n, n == 1 and one or many)
end

---------------------------------------------------------------------------
-- Health: is the recorder working? Said in chat only when it isn't.
---------------------------------------------------------------------------

-- ok, message. Position.lua publishes tickClock / tickHasPos / lastPosHasWorld.
function WJ.health()
  if paused then return true, "recording is paused. Resume it from the icon or with /widsith resume." end
  if not session then return false, "no session was started, so nothing is being recorded." end
  if WJ.savesNotLoaded then
    return false, "the game didn't load the earlier recording, so this reload replaced it in the file."
  end
  if not WJ.tickClock or GetTime() - WJ.tickClock > 3 then
    return false, "the position sampler isn't running, so where you go isn't being recorded."
  end
  if errorCount > 0 then
    return false, format("something went wrong %s while recording. %s keeps recording; /widsith debug shows the details as they happen.",
      errorCount == 1 and "once" or errorCount .. " times", WJ.NAME)
  end
  if not WJ.tickHasPos then
    return true, "recording. No position is available here, which is normal inside instances."
  end
  if WJ.lastPosHasWorld == false then
    return false, "positions are being recorded without world coordinates."
  end
  return true, "recording, with positions and world coordinates."
end

function WJ.printHealth()
  local ok, message = WJ.health()
  if not ok then
    WJ.warn(message)
  elseif WJ.debug then
    print(PREFIX .. message)
  end
end

---------------------------------------------------------------------------
-- Character identity (refreshed every session)
---------------------------------------------------------------------------

-- The character's surname. On WoW Forever every character has one, and the game gives it as
-- UnitName's second value ("Aldwin", "Thornby"); Retail gives none for the player. Kept only
-- as a plain string: a secret or an empty value is left out.
local function surnameOf(unit)
  local _, surname = UnitName(unit)
  if type(surname) ~= "string" or (issecretvalue and issecretvalue(surname)) or surname == "" then
    return nil
  end
  return surname
end

local function describeCharacter()
  local _, _, classID = UnitClass("player")
  local _, _, raceID  = UnitRace("player")
  return {
    guid    = UnitGUID("player"),
    name    = (UnitName("player")),
    surname = surnameOf("player"),
    realm   = GetRealmName(),
    realmN  = GetNormalizedRealmName(),
    region  = GetCurrentRegion and GetCurrentRegion() or nil,
    classID = classID,
    raceID  = raceID,
    sex     = UnitSex("player"),
    faction = UnitFactionGroup("player"),
  }
end

---------------------------------------------------------------------------
-- Session start / end
---------------------------------------------------------------------------

function WJ.isPaused()
  return paused
end

-- isResume: started from the icon or /widsith resume after a pause, inside
-- the same addon load. Anything else is a login or a reload.
function WJ.startSession(isLogin, isReload, isResume)
  if session then return end
  paused = false
  startClock = GetTime()
  local serverTime = GetServerTime()
  local previous = db.sessions[#db.sessions]
  -- A counter of its own, so pruning old sessions from the file can never make a later
  -- session's id repeat an earlier one's (the id is serverTime-ordinal).
  db.nextSession = (db.nextSession or #db.sessions) + 1
  local ordinal = db.nextSession
  session = {
    id        = serverTime .. "-" .. ordinal,
    startedAt = serverTime,
    closed    = false,
    lines     = 0,
    chunks    = {},
    encoding  = "raw",
  }
  -- Appended, never indexed by the counter: once old sessions can be pruned the counter
  -- runs ahead of the array, and a gap would break #, ipairs and "the last session".
  db.sessions[#db.sessions + 1] = session
  db.character = describeCharacter()
  for k in pairs(counts) do counts[k] = 0 end

  local version, build, _, interface = GetBuildInfo()
  WJ.write("SESSION", serverTime, WJ.VERSION, WJ.FORMAT, version, build,
    WOW_PROJECT_ID, GetLocale(), isLogin, isReload, UnitGUID("player"), isResume and true or nil)

  WJ.requestTimePlayed()
  -- Equipment (and some unit data) isn't loaded yet at PLAYER_ENTERING_WORLD;
  -- the opening snapshot waits for it.
  C_Timer.After(5, WJ.guard("openingState", WJ.openingState))
  WJ.startTicker()

  if isResume then
    WJ.say("recording resumed.")
  else
    -- The previous session can only be here if it made the round trip through
    -- the SavedVariables file, so it shows that saving works (in debug mode).
    previousOnFile = "no earlier sessions on file."
    if previous then
      previousOnFile = format("previous session on file: %s%s.", count(previous.lines or 0, "line", "lines"),
        previous.closed and "" or ", |cffff4444not closed cleanly|r")
    end
    if isLogin then
      WJ.say(WJ.VERSION .. " is recording. Type /widsith help for commands.")
    else
      WJ.say("is recording.")
    end
    if WJ.debug then print(PREFIX .. previousOnFile) end
  end
  -- The icon lights now, not when its own frame hears the event (the order
  -- frames receive one isn't promised).
  if WJ.onRecordingStarted then WJ.guard("recordingStarted", WJ.onRecordingStarted)() end
  C_Timer.After(10, WJ.guard("health", WJ.printHealth))
end

function WJ.endSession(reason)
  if not session then return end
  WJ.write("END", GetServerTime(), reason)
  flush()
  session.closed = true
  session = nil
end

-- Pause: close this session with END … pause and record nothing until
-- Resume, which opens a new session with a fresh baseline. A pause never
-- outlives the addon load: the next login or reload records as always, so it
-- can't be forgotten for longer than one sitting.
function WJ.pause()
  if not session then return end
  WJ.endSession("pause")
  paused = true
  WJ.say("recording paused. Nothing is recorded until you resume, log in again or reload.")
end

function WJ.resume()
  if session then return end
  WJ.startSession(false, false, true)
  if WJ.onResume then WJ.guard("resume", WJ.onResume)() end
end

---------------------------------------------------------------------------
-- Played time. RequestTimePlayed() echoes to chat; the
-- echo is swallowed once per request, the way most addons do it.
---------------------------------------------------------------------------

-- Every chat window that shows system messages calls this once per reply, so
-- suppress by time window rather than by count. The client's chat code calls
-- ChatFrameUtil.DisplayTimePlayed (ChatFrameOverrides.lua); older clients the
-- global ChatFrame_DisplayTimePlayed. Whichever exists is wrapped.
local suppressUntil = 0
local function wrapTimePlayed(holder, key)
  if type(holder) ~= "table" then return end
  local original = holder[key]
  if type(original) ~= "function" then return end
  holder[key] = function(...)
    if GetTime() < suppressUntil then return end
    return original(...)
  end
end
wrapTimePlayed(ChatFrameUtil, "DisplayTimePlayed")
wrapTimePlayed(_G, "ChatFrame_DisplayTimePlayed")

function WJ.requestTimePlayed()
  if not RequestTimePlayed then return end
  suppressUntil = GetTime() + 5
  RequestTimePlayed()
end

---------------------------------------------------------------------------
-- Snapshot: level, money, position, quest log and gear, every few minutes
---------------------------------------------------------------------------

local EQUIP_SLOTS = 19

-- A quest log entry the player would call a quest: not a header, and not one of the hidden
-- tracking quests the client keeps in the log ("Level 3", "Level 13" … seen in the game),
-- which never show in the game's own log.
function WJ.isQuestEntry(info)
  return info and not info.isHeader and not info.isHidden and info.questID
end

local function questIDs()
  local ids = {}
  local n = C_QuestLog.GetNumQuestLogEntries()
  for i = 1, n do
    local info = C_QuestLog.GetInfo(i)
    if WJ.isQuestEntry(info) then
      ids[#ids + 1] = info.questID
    end
  end
  return ids
end
WJ.questIDs = questIDs

local function equipIDs()
  local ids = {}
  for slot = 1, EQUIP_SLOTS do
    ids[slot] = GetInventoryItemID("player", slot) or ""
  end
  return ids
end

function WJ.snapshot()
  local mapID, x, y = WJ.currentPosition()
  WJ.write("SNAP", UnitLevel("player"), UnitXP("player"), UnitXPMax("player"), GetMoney(),
    mapID, WJ.coord(x), WJ.coord(y), WJ.list(questIDs()), WJ.list(equipIDs()))
  WJ.write("COUNT", counts.pos, counts.kills, counts.loot, counts.xp, counts.quests, counts.deaths,
    counts.jumps, counts.shots, counts.emotes)
  -- The character sheet's numbers, when they changed (Extras.lua).
  if WJ.writeStats then WJ.writeStats() end
  -- The game's own counters, every one (Moments.lua).
  if WJ.readTallies then WJ.readTallies(true) end
end

-- The opening snapshot plus the state that has no change event of its own
-- yet in this session: quest titles (QLABEL), professions (SKILL), reputations (REP), currencies (CURRENCY), spec,
-- talents, gear sets, hearth location, the rules played under, auras and the game's counters.
-- Written once the client has loaded that data.
function WJ.openingState()
  WJ.snapshot()
  if WJ.writeQuestLabels then WJ.writeQuestLabels() end
  if WJ.writeOpeningExtras then WJ.writeOpeningExtras() end
  -- Guarded on its own: whatever goes wrong there is named, and nothing above depends on it.
  if WJ.writeOpeningMoments then WJ.guard("openingMoments", WJ.writeOpeningMoments)() end
end

---------------------------------------------------------------------------
-- Errors. One misbehaving handler, hook or timer (a secret value where none
-- was expected, an API that changed shape) must never stop the recording or
-- show the player an error popup. The failure itself is recorded as ERR,
-- rate-limited so a persistent fault can't flood.
---------------------------------------------------------------------------

function WJ.recordError(where, err)
  errorCount = errorCount + 1
  if errorCount <= 20 then
    WJ.write("ERR", where, tostring(err))
  end
  if errorCount == 1 then
    WJ.warn("something went wrong while recording (" .. tostring(where) .. "). " .. WJ.NAME ..
      " keeps recording; /widsith debug shows the details.")
  end
  if WJ.debug then print("|cffff4444WJ error in " .. where .. ":|r " .. tostring(err)) end
end

local function run(where, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then WJ.recordError(where, err) end
end

-- The same guard for code that runs outside an event handler: hook bodies and
-- C_Timer callbacks. `where` names it in the ERR line.
function WJ.guard(where, fn)
  return function(...) run(where, fn, ...) end
end

-- The game started this load without the recording file (see the boot below).
-- Written into the recording, said once in chat, and the save reminder stops:
-- while the client can't read the file back, every reload replaces it. (Early
-- WoW Forever builds wrote saved variables but never read them back.)
function WJ.noteSavesNotLoaded()
  WJ.savesNotLoaded = true
  WJ.write("ERR", "savedvariables", "empty at reload: the game did not load the recording file")
  WJ.warn("the game didn't load the earlier recording at this reload, so the file now holds only " ..
    "what is recorded from here on. To keep it, copy " .. ADDON_NAME .. ".lua out of SavedVariables " ..
    "before each reload or logout.")
end

---------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
WJ.frame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    if (...) ~= ADDON_NAME then return end
    WidsithDB = WidsithDB or {}
    db = WidsithDB
    db.format   = WJ.FORMAT
    db.sessions = db.sessions or {}
    WJ.db = db
    WJ.registerEvents(self)
    if WJ.installHooks then run("hooks", WJ.installHooks) end
    self:UnregisterEvent("ADDON_LOADED")
  elseif event == "PLAYER_ENTERING_WORLD" then
    local isLogin, isReload = ...
    if isLogin or isReload then
      -- A reload always follows a session of this game launch, so an empty file here
      -- means the client didn't read it back, or the addon was only just enabled.
      -- Either way the file is about to lose what it had.
      local savesNotLoaded = isReload and #db.sessions == 0
      run("session", WJ.startSession, isLogin, isReload)
      if savesNotLoaded then WJ.noteSavesNotLoaded() end
    end
    run(event, WJ.onEnteringWorld, isLogin, isReload)
  elseif event == "PLAYER_LOGOUT" then
    WJ.endSession()
  else
    local handler = WJ.handlers[event]
    if handler then run(event, handler, ...) end
  end
end)

---------------------------------------------------------------------------
-- /widsith
---------------------------------------------------------------------------

-- /widsith check: what this client is and what it lacks of what the recorder
-- uses. Every missing piece is already skipped quietly; this only says which.

local USED_APIS = {
  "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition", "C_Map.GetMapInfo", "C_Map.GetWorldPosFromMapPos",
  "UnitPosition", "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetInfo", "C_QuestLog.GetQuestObjectives",
  "C_QuestLog.GetTitleForQuestID", "RequestTimePlayed", "ChatFrame_DisplayTimePlayed", "GetLootSourceInfo",
  "C_Item.GetItemQualityByID", "C_Item.GetItemInfo", "C_MountJournal.GetMountFromSpell",
  "C_Reputation.GetFactionDataByID", "C_Reputation.GetNumFactions", "C_Reputation.GetFactionDataByIndex", "GetProfessions", "GetProfessionInfo", "GetAchievementInfo",
  "GetAverageItemLevel", "GetCritChance", "GetHaste", "GetMasteryEffect", "GetCombatRatingBonus",
  "GetVersatilityBonus", "C_SpecializationInfo.GetSpecialization", "C_SpecializationInfo.GetSpecializationInfo",
  "GetSpecialization", "GetBindLocation", "C_PetBattles.GetNumPets", "C_ChatInfo.PerformEmote",
  "JumpOrAscendStart", "C_TradeSkillUI.CraftRecipe", "C_TradeSkillUI.IsTradeSkillReady",
  "C_TradeSkillUI.GetAllRecipeIDs", "C_TradeSkillUI.GetFilteredRecipeIDs", "C_TradeSkillUI.GetRecipeInfo",
  "C_TradeSkillUI.GetBaseProfessionInfo", "C_TradeSkillUI.IsTradeSkillLinked", "BuyMerchantItem", "C_MerchantFrame.GetItemInfo",
  "C_Container.UseContainerItem", "RepairAllItems", "GetRepairAllCost", "BuyTrainerService",
  "GetTrainerServiceItemLink", "UnitCreatureType", "UnitIsFeignDeath", "IsFlying", "MenuUtil.CreateContextMenu",
  "C_SkillInfo.GetSkillLineInfo", "C_SkillInfo.GetSkillLineInfoByID", "C_QuestLog.AbandonQuest",
  "C_QuestLog.GetAbandonQuest", "GetGuildInfo", "IsInGuild", "GetTradePlayerItemInfo", "GetTradeTargetItemInfo",
  "GetPlayerTradeMoney", "GetTargetTradeMoney", "UnitDefenseSkill",
  "C_DamageMeter.GetAvailableCombatSessions", "C_DamageMeter.GetCombatSessionFromID",
  "C_DamageMeter.GetCombatSessionSourceFromID", "C_DeathRecap.GetRecapEvents", "C_DeathRecap.GetRecapMaxHealth",
  "C_UnitAuras.GetAuraDataByIndex", "C_Secrets.ShouldAurasBeSecret", "GetStatisticsCategoryList", "GetCategoryNumAchievements", "GetStatistic",
  "C_GameRules.IsHardcoreActive", "C_PlayerInfo.IsSelfFoundActive", "C_GameRules.GetForeverExperiencePreset",
  "C_EquipmentSet.GetEquipmentSetIDs", "C_EquipmentSet.GetEquipmentSetInfo", "C_EquipmentSet.GetItemIDs",
  "C_EquipmentSet.GetIgnoredSlots", "C_EquipmentSet.GetEquipmentSetAssignedSpec",
  "C_SpecializationInfo.GetActiveSpecGroup", "C_SpecializationInfo.GetCombatConfigIDForSpecGroup",
  "C_ClassTalents.GetActiveConfigID", "C_Traits.ConfigHasStagedChanges", "C_Traits.GetConfigInfo",
  "C_Traits.GetTreeNodes", "C_Traits.GetNodeInfo", "C_Traits.GenerateImportString",
  "C_CurrencyInfo.GetCurrencyListSize", "C_CurrencyInfo.GetCurrencyListInfo",
}

local function lookup(path)
  local v = _G
  for part in path:gmatch("[^%.]+") do
    if type(v) ~= "table" then return nil end
    v = v[part]
  end
  return v
end

function WJ.printClientCheck()
  local version, build = GetBuildInfo()
  print(format("%sclient %s (build %s), interface %s, project %s, expansion level %s%s.", PREFIX,
    tostring(version), tostring(build), tostring(WJ.INTERFACE), tostring(WOW_PROJECT_ID),
    tostring(LE_EXPANSION_LEVEL_CURRENT), WJ.isForever and ": WoW Forever" or ""))
  local missing = {}
  for _, path in ipairs(USED_APIS) do
    if type(lookup(path)) ~= "function" then missing[#missing + 1] = path end
  end
  print(PREFIX .. "missing functions: " .. (#missing > 0 and table.concat(missing, ", ") or "none"))
  local events = WJ.unregisteredEvents or {}
  print(PREFIX .. "missing events: " .. (#events > 0 and table.concat(events, ", ") or "none"))
  if WJ.savesNotLoaded then print(PREFIX .. "the game didn't load the recording file at the last reload.") end
end

local function estimateBytes()
  local total = 0
  for _, s in ipairs(db.sessions) do
    for _, c in ipairs(s.chunks) do total = total + #c end
  end
  for _, l in ipairs(buffer) do total = total + #l end
  return total
end

local function describeSize(bytes)
  if bytes >= 1024 * 1024 then return format("about %.1f MB", bytes / (1024 * 1024)) end
  return format("about %d KB", math.max(1, floor(bytes / 1024 + 0.5)))
end

local function printStatus()
  local onFile = count(#db.sessions, "session", "sessions") .. " on file, " .. describeSize(estimateBytes()) .. "."
  if session then
    print(format("%s%s is recording. This session: %s so far (%s, %s taken or handed in). %s", PREFIX, WJ.VERSION,
      count((session.lines or 0) + #buffer, "line", "lines"), count(counts.kills, "kill", "kills"),
      count(counts.quests, "quest", "quests"), onFile))
  elseif paused then
    print(format("%s%s is paused; resume it from the icon or with /widsith resume. %s", PREFIX, WJ.VERSION, onFile))
  else
    print(format("%s%s isn't recording. %s", PREFIX, WJ.VERSION, onFile))
  end
  local ok, message = WJ.health()
  if not ok then WJ.warn(message) end
  if WJ.debug then
    print(PREFIX .. "the file is WTF\\Account\\<account>\\" .. (GetRealmName() or "?") .. "\\" .. (UnitName("player") or "?") ..
      "\\SavedVariables\\" .. ADDON_NAME .. ".lua, written at logout or reload.")
    if previousOnFile then print(PREFIX .. previousOnFile) end
  end
  print(PREFIX .. "type /widsith help for commands.")
end

local HELP = {
  { "", "shows what has been recorded so far." },
  { "help", "shows this list." },
  { "about", "says what " .. WJ.NAME .. " is." },
  { "pause", "stops recording until you resume, log in again or reload." },
  { "resume", "starts recording again." },
  { "save", "reloads the interface, which writes the recording to disk." },
  { "icon", "shows or hides the recording icon." },
  { "options", "opens the settings panel." },
  { "check", "provides internal diagnostic information." },
  { "debug", "echoes every line to chat as it is recorded." },
}
local HELP_TESTING = {
  { "remind", "shows the save reminder now." },
  { "flush", "packs the lines waiting in memory into the file's chunks." },
  { "qlog", "lists the quest log as the game reports it." },
}

local function printCommands(list)
  for _, entry in ipairs(list) do
    local command = entry[1] == "" and "/widsith" or "/widsith " .. entry[1]
    print(PREFIX .. "|cffffffff" .. command .. "|r " .. entry[2])
  end
end

local function handleCommand(msg)
  local typed = msg:match("^(%S*)")
  local cmd = typed:lower()
  if cmd == "" then
    printStatus()
  elseif cmd == "help" then
    printCommands(HELP)
    if WJ.debug then
      print(PREFIX .. "these are for testing:")
      printCommands(HELP_TESTING)
    end
  elseif cmd == "about" then
    print(PREFIX .. "version " .. WJ.VERSION .. ".")
    print(PREFIX .. "keeps a record of your character's journey as you play: where you went, what you did and when.")
    print(PREFIX .. "recordings are replayed at https://widsith.app.")
  elseif cmd == "debug" then
    WJ.debug = not WJ.debug
    if WJ.debug then
      print(PREFIX .. "debug messages on. Every line is echoed to chat as it is recorded; type /widsith debug again to stop.")
    else
      print(PREFIX .. "debug messages off.")
    end
  elseif cmd == "flush" then
    flush()
    print(PREFIX .. "the lines waiting in memory are packed into the file's chunks; the game writes the file at the next logout or reload.")
  elseif cmd == "check" then
    WJ.printClientCheck()
  elseif cmd == "save" then
    -- WoW only writes SavedVariables on logout or UI reload; there is no
    -- other way to force it. A crash loses everything since the last write.
    if InCombatLockdown() then
      print(PREFIX .. "can't reload the interface in combat; try again when the fight is over.")
    else
      -- The icon reads this after the reload and says the recording was saved.
      if WidsithUI then WidsithUI.saving = true end
      ReloadUI()
    end
  elseif cmd == "icon" then
    if WJ.setIconShown then WJ.setIconShown(not WJ.iconShown()) end
  elseif cmd == "options" then
    if WJ.openOptions then WJ.openOptions() else print(PREFIX .. "this game client has no settings panel for addons.") end
  elseif cmd == "pause" then
    if session then
      WJ.pause()
    elseif paused then
      print(PREFIX .. "recording is already paused.")
    else
      print(PREFIX .. "isn't recording, so there is nothing to pause.")
    end
  elseif cmd == "resume" then
    if session then
      print(PREFIX .. "is already recording.")
    else
      WJ.resume()
    end
  elseif cmd == "remind" then
    if WJ.showReminder then WJ.showReminder() end
  elseif cmd == "qlog" then
    -- What the quest API reports right now, objective by objective.
    local n = C_QuestLog.GetNumQuestLogEntries()
    for i = 1, n do
      local info = C_QuestLog.GetInfo(i)
      if WJ.isQuestEntry(info) then
        local objs = C_QuestLog.GetQuestObjectives(info.questID)
        local parts = {}
        for idx, o in ipairs(objs or {}) do
          parts[idx] = format("%s %s/%s %s", tostring(o.type), tostring(o.numFulfilled), tostring(o.numRequired), tostring(o.text))
        end
        print(format("%d %s: %s", info.questID, tostring(info.title), #parts > 0 and table.concat(parts, " | ") or "(no objectives)"))
      end
    end
    local wasDebug = WJ.debug
    WJ.debug = true
    WJ.diffQuestLog(false)
    WJ.debug = wasDebug
  else
    -- "|" starts an escape sequence in chat, so a typed one is doubled to show as itself.
    print(format("%sdoesn't know '%s'. Type /widsith help for the commands.", PREFIX, (typed:gsub("|", "||"))))
  end
end

SLASH_WIDSITH1 = "/widsith"
SlashCmdList.WIDSITH = function(msg)
  answering = true
  local ok, err = pcall(handleCommand, msg or "")
  answering = false
  if not ok then error(err, 0) end
end
