-- Widsith — Events
--
-- Everything event-driven. Each handler turns one WoW event into zero or more
-- lines, using only what the event and the APIs expose at that instant.

local _, WJ = ...

local write, counts = WJ.write, WJ.counts
local handlers = {}
WJ.handlers = handlers

local playerGUID

-- Values that are present, of the right type and not secret; comparing,
-- adding or joining a secret value throws.
local function secret(v)
  return issecretvalue ~= nil and issecretvalue(v)
end
local function plainNumber(v)
  if type(v) == "number" and not secret(v) then return v end
end
local function plainString(v)
  if type(v) == "string" and not secret(v) and v ~= "" then return v end
end
local function plainTable(v)
  if type(v) == "table" and not secret(v) then return v end
end

-- A dotted name ("C_Bank.DepositMoney") as its namespace table (or _G) and key.
local function resolve(path)
  local namespace, name = path:match("^([^%.]+)%.(.+)$")
  if namespace then return _G[namespace], name end
  return _G, path
end

local function pass(ok, ...)
  if ok then return ... end
end

-- Calls a game function by name; nothing when the client lacks it or it throws.
local function ask(path, ...)
  local owner, name = resolve(path)
  if type(owner) ~= "table" then return end
  local fn = owner[name]
  if type(fn) ~= "function" then return end
  return pass(pcall(fn, ...))
end

---------------------------------------------------------------------------
-- World / instance
---------------------------------------------------------------------------

local currentInstanceMapID = 0
local lastZone, lastSubzone

function WJ.onEnteringWorld(isLogin, isReload)
  playerGUID = UnitGUID("player")
  WJ.onEnteringWorldPosition()
  if isLogin or isReload then WJ.seedState() end

  local name, instanceType, difficultyID, _, _, _, _, instanceMapID = GetInstanceInfo()
  local transition = false
  if instanceType ~= "none" and instanceMapID ~= currentInstanceMapID then
    write("INST", "enter", instanceMapID, instanceType, difficultyID, name)
    if instanceType == "party" or instanceType == "raid" or instanceType == "scenario" then
      WJ.highlightShot("instance", instanceMapID)
    end
    currentInstanceMapID = instanceMapID
    transition = true
  elseif instanceType == "none" and currentInstanceMapID ~= 0 then
    write("INST", "leave", currentInstanceMapID, instanceType)
    currentInstanceMapID = 0
    transition = true
  end
  -- Any loading screen but login is a relocation; Extras.lua names the cast
  -- behind it (a hearthstone, a portal) when one finished just before it.
  if not (isLogin or isReload) then
    WJ.onRelocation("load")
    WJ.catchUpProgress()
  end
end

-- Subzone text flaps at boundaries, so the zone is written only once it has
-- held for ZONE_SETTLE seconds.
local ZONE_SETTLE = 1.5
local zoneTimer

local function writeZoneIfChanged()
  zoneTimer = nil
  local zone, subzone = GetZoneText(), GetSubZoneText()
  if zone ~= lastZone or subzone ~= lastSubzone then
    write("ZONE", zone, subzone)
    -- Noted first, so a fault below can't write it twice.
    lastZone, lastSubzone = zone, subzone
    WJ.zoneChanged()
  end
end

local writeZoneGuarded = WJ.guard("zone", writeZoneIfChanged)

local function zoneChanged()
  if zoneTimer then zoneTimer:Cancel() end
  zoneTimer = C_Timer.NewTimer(ZONE_SETTLE, writeZoneGuarded)
end
handlers.ZONE_CHANGED_NEW_AREA = zoneChanged
handlers.ZONE_CHANGED          = zoneChanged
handlers.ZONE_CHANGED_INDOORS  = zoneChanged

handlers.PLAYER_CONTROL_LOST   = function() write("CTRL", "lost") end
handlers.PLAYER_CONTROL_GAINED = function() write("CTRL", "gained") end

---------------------------------------------------------------------------
-- Combat and rest. The opening state is written at session start (seedState).
---------------------------------------------------------------------------

handlers.PLAYER_REGEN_DISABLED = function() write("COMBAT", "enter") end
handlers.PLAYER_REGEN_ENABLED  = function()
  write("COMBAT", "leave")
  -- The fight's summary, once the game releases its numbers (Moments.lua).
  if WJ.onCombatEnd then WJ.onCombatEnd() end
  -- The character sheet the fight kept hidden, if a line was due (Extras.lua).
  if WJ.statsAfterCombat then WJ.statsAfterCombat() end
end

---------------------------------------------------------------------------
-- Group. Size, kind, each other member's class, GUID and Name-Realm, and
-- their levels. GROUP_ROSTER_UPDATE fires often: a line only on a change.
---------------------------------------------------------------------------

local lastGroup

local function groupLine()
  local size = GetNumGroupMembers() or 0
  local kind = IsInRaid() and "raid" or (IsInGroup() and "party" or "none")
  local members, levels = {}, {}
  if size > 0 then
    local prefix, count = kind == "raid" and "raid" or "party", kind == "raid" and size or size - 1
    for i = 1, count do
      local unit = prefix .. i
      if not UnitIsUnit(unit, "player") then
        -- classID:guid:Name-Realm, each part through field() before joining,
        -- so a secret (instances can hide identity) becomes empty.
        local _, _, classID = UnitClass(unit)
        local name, realm = UnitFullName(unit)
        name, realm = WJ.field(name), WJ.field(realm)
        if realm == "" then realm = WJ.field(GetNormalizedRealmName()) end
        local full = name ~= "" and (name .. "-" .. realm) or ""
        members[#members + 1] = WJ.field(classID) .. ":" .. WJ.field(UnitGUID(unit)) .. ":" .. full
        -- A hidden level is an empty entry, keeping the list in step.
        levels[#levels + 1] = WJ.field(UnitLevel(unit))
      end
    end
  end
  return size, kind, table.concat(members, ","), table.concat(levels, ",")
end

local function writeGroupIfChanged()
  local size, kind, classes, levels = groupLine()
  local key = size .. kind .. classes
  if levels ~= "" then key = key .. "\t" .. levels end
  if key == lastGroup then return end
  lastGroup = key
  write("GROUP", size, kind, classes, levels)
end

handlers.GROUP_ROSTER_UPDATE = writeGroupIfChanged
handlers.GROUP_JOINED        = writeGroupIfChanged
handlers.GROUP_LEFT          = writeGroupIfChanged

local lastResting
handlers.PLAYER_UPDATE_RESTING = function()
  local resting = IsResting() and true or false
  if resting == lastResting then return end
  lastResting = resting
  write("REST", resting and "enter" or "leave")
end

-- Any addon's RequestTimePlayed() produces a reply for everyone; repeats are skipped.
local lastPlayedTotal
handlers.TIME_PLAYED_MSG = function(total, thisLevel)
  if total == lastPlayedTotal then return end
  lastPlayedTotal = total
  write("PLAYED", total, thisLevel)
end

---------------------------------------------------------------------------
-- Progress
---------------------------------------------------------------------------

local lastXP, lastXPMax, lastLevel

handlers.PLAYER_XP_UPDATE = function(unit)
  if unit ~= "player" then return end
  local xp, max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
  if xp == lastXP and max == lastXPMax and level == lastLevel then return end
  lastXP, lastXPMax, lastLevel = xp, max, level
  write("XP", xp, max, level)
  counts.xp = counts.xp + 1
end

-- The payload is what the level brought, health to intellect (UnitDocumentation.lua).
handlers.PLAYER_LEVEL_UP = function(level, ...)
  write("LEVEL", level, ...)
  -- Stats and UnitLevel() update after the event; snapshot once they have.
  C_Timer.After(1, WJ.guard("levelSnapshot", function() WJ.snapshot() end))
  WJ.highlightShot("level")
end

-- MONEY has its own section below.

local deathOutstanding = false
local lastFeignClock
local FEIGN_REPEAT = 2   -- s

-- Fires twice per death, and for Feign Death. A real death is outstanding
-- until PLAYER_ALIVE / PLAYER_UNGHOST; a feign is never resurrected, so it is
-- deduped by time instead.
handlers.PLAYER_DEAD = function()
  local feign = UnitIsFeignDeath and UnitIsFeignDeath("player") or false
  if feign then
    local now = GetTime()
    if lastFeignClock and now - lastFeignClock <= FEIGN_REPEAT then return end
    lastFeignClock = now
  elseif deathOutstanding then
    return
  end
  local mapID, x, y = WJ.currentPosition()
  write("DEATH", mapID, WJ.coord(x), WJ.coord(y), feign)
  if not feign then
    counts.deaths = counts.deaths + 1
    deathOutstanding = true
    -- The hits that did it (Moments.lua).
    if WJ.onDeath then WJ.onDeath() end
    WJ.highlightShot("death", "first")
  end
end

handlers.PLAYER_ALIVE = function()
  if UnitIsGhost("player") then
    write("GHOST")
  elseif deathOutstanding then
    write("ALIVE")
    deathOutstanding = false
  end
  -- Otherwise this is the PLAYER_ALIVE that follows every PLAYER_ENTERING_WORLD.
end

handlers.PLAYER_UNGHOST = function()
  write("ALIVE")
  deathOutstanding = false
end

---------------------------------------------------------------------------
-- NPC interaction
---------------------------------------------------------------------------

-- One NPC line per dialog: the same type and GUID within 10 s is one visit.
local lastNPCKey, lastNPCTime = nil, 0

local function noteNPC(interactionType, guid)
  local key = tostring(interactionType) .. ":" .. WJ.field(guid)
  if key == lastNPCKey and GetTime() - lastNPCTime <= 10 then return end
  lastNPCKey, lastNPCTime = key, GetTime()
  write("NPC", interactionType, guid)
end

handlers.PLAYER_INTERACTION_MANAGER_FRAME_SHOW = function(interactionType)
  noteNPC(interactionType, UnitGUID("npc"))
end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------

-- The quest frame often closes before QUEST_ACCEPTED / QUEST_TURNED_IN fire,
-- taking the "npc" unit with it. Remember the giver while the dialog is open.
local lastGiverGUID, lastGiverTime = nil, 0
local GIVER_WINDOW = 10

local function rememberGiver()
  local guid = plainString(UnitGUID("npc")) or plainString(UnitGUID("questnpc"))
  if guid then
    lastGiverGUID, lastGiverTime = guid, GetTime()
    -- The interaction manager reports a quest-giver frame (type 4) hiding, never showing.
    noteNPC(4, guid)
  end
end
handlers.QUEST_GREETING = rememberGiver
handlers.QUEST_DETAIL   = rememberGiver
handlers.QUEST_COMPLETE = rememberGiver
handlers.QUEST_PROGRESS = rememberGiver

local function giverGUID()
  local guid = plainString(UnitGUID("npc")) or plainString(UnitGUID("questnpc"))
  if guid then return guid end
  if lastGiverGUID and GetTime() - lastGiverTime <= GIVER_WINDOW then
    return lastGiverGUID
  end
  return nil
end

-- Objective cache for QPROG diffs: objectives[questID][index] = numFulfilled
local objectives = {}
-- Whether the game last said each quest was ready to turn in: ready[questID] = true/false
local ready = {}

-- Whether the game says the quest is ready to turn in, counted objectives or
-- not: ReadyForTurnIn, else the older IsComplete; nil when neither answers.
local function questReady(questID)
  local ask = C_QuestLog.ReadyForTurnIn or C_QuestLog.IsComplete
  if type(ask) ~= "function" then return nil end
  local ok, answer = pcall(ask, questID)
  if not ok or (issecretvalue and issecretvalue(answer)) then return nil end
  return answer == true
end

-- A quest's objectives as it enters the log, one QPROG each.
local function writeObjectiveList(questID, list)
  for idx, o in ipairs(list) do
    write("QPROG", questID, idx, o.fulfilled, o.required, o.type, o.text)
  end
end

local function readObjectives(questID)
  local list = C_QuestLog.GetQuestObjectives(questID)
  local out = {}
  if list then
    for i, o in ipairs(list) do
      out[i] = { fulfilled = o.numFulfilled, required = o.numRequired, type = o.type, text = o.text }
    end
  end
  return out
end

-- A QLABEL for every quest already in the log, with the opening snapshot; a
-- title the client hasn't loaded is skipped.
function WJ.writeQuestLabels()
  if not C_QuestLog.GetTitleForQuestID then return end
  for _, questID in ipairs(WJ.questIDs()) do
    local title = C_QuestLog.GetTitleForQuestID(questID)
    if title and title ~= "" then write("QLABEL", questID, title) end
  end
end

-- Diff the whole log against the cache: QPROG for each changed objective, the
-- whole list for a quest new to the log, QDONE when one becomes ready. A
-- silent pass only seeds the cache; the opening one also writes the quests
-- already ready.
local function diffQuestLog(silent, opening)
  local seen = {}
  local n = C_QuestLog.GetNumQuestLogEntries()
  local quests, changes = 0, 0
  for i = 1, n do
    local info = C_QuestLog.GetInfo(i)
    if WJ.isQuestEntry(info) then
      local questID = info.questID
      seen[questID] = true
      quests = quests + 1
      local now = readObjectives(questID)
      local prev = objectives[questID]
      if prev and not silent then
        for idx, o in ipairs(now) do
          local p = prev[idx]
          if not p or p.fulfilled ~= o.fulfilled then
            -- The objective's wording rides along as a label.
            write("QPROG", questID, idx, o.fulfilled, o.required, o.type, o.text)
            changes = changes + 1
          end
        end
      elseif not silent then
        -- In the log without an accept of its own (shared, or taken on by the game).
        writeObjectiveList(questID, now)
        changes = changes + #now
      end
      -- The opening pass states what is ready, whatever an earlier session knew.
      local isReady = questReady(questID)
      if isReady and opening then write("QDONE", questID, 1)
      elseif isReady and not silent and not ready[questID] then write("QDONE", questID) end
      ready[questID] = isReady == true
      if WJ.debug and not silent then
        local parts = {}
        for idx, o in ipairs(now) do
          parts[idx] = tostring(prev and prev[idx] and prev[idx].fulfilled) .. ">" .. tostring(o.fulfilled) .. "/" .. tostring(o.required)
        end
        print(string.format("|cff8888ffWJ qlog|r %d [%s]", questID, table.concat(parts, " ")))
      end
      objectives[questID] = now
    end
  end
  for questID in pairs(objectives) do
    if not seen[questID] then objectives[questID], ready[questID] = nil, nil end
  end
  if WJ.debug and not silent then
    print(string.format("|cff8888ffWJ qlog|r diff: %d entries, %d quests, %d changes", n, quests, changes))
  end
end
WJ.diffQuestLog = diffQuestLog

local diffPending = false
local runDiff = WJ.guard("questDiff", function()
  diffPending = false
  diffQuestLog(false)
end)
local function scheduleDiff()
  if diffPending then return end
  diffPending = true
  C_Timer.After(0.5, runDiff)
end

handlers.UNIT_QUEST_LOG_CHANGED = function(unit)
  if WJ.debug then print("|cff8888ffWJ|r UNIT_QUEST_LOG_CHANGED " .. tostring(unit)) end
  if unit == "player" then scheduleDiff() end
end

-- Too frequent to trigger a diff; shown in debug mode only.
handlers.QUEST_LOG_UPDATE = function()
  if WJ.debug then print("|cff8888ffWJ|r QUEST_LOG_UPDATE") end
end

-- The quest's own level, and the level its difficulty colour is rated by
-- (which follows the player on a scaling quest).
local function questLevels(questID)
  local index = plainNumber((ask("C_QuestLog.GetLogIndexForQuestID", questID)))
  local info = index and plainTable((ask("C_QuestLog.GetInfo", index)))
  local level = info and plainNumber(info.level)
  local difficulty = plainNumber((ask("C_QuestLog.GetQuestDifficultyLevel", questID)))
  return level, difficulty
end

handlers.QUEST_ACCEPTED = function(questID)
  local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
  write("QACCEPT", questID, giverGUID(), title, questLevels(questID))
  counts.quests = counts.quests + 1
  -- Its objectives, and QDONE if it comes already finished.
  local list = readObjectives(questID)
  writeObjectiveList(questID, list)
  objectives[questID] = list
  local isReady = questReady(questID)
  if isReady then write("QDONE", questID) end
  ready[questID] = isReady == true
end

handlers.QUEST_TURNED_IN = function(questID, xpReward, moneyReward)
  write("QTURNIN", questID, xpReward, moneyReward, giverGUID())
  counts.quests = counts.quests + 1
  -- The reward's money is the reason for the change it brings.
  local reward = plainNumber(moneyReward)
  if reward and reward > 0 then WJ.moneyReason("quest", reward, nil, { after = true }) end
  objectives[questID], ready[questID] = nil, nil
end

handlers.QUEST_REMOVED = function(questID)
  write("QREMOVE", questID)
  objectives[questID], ready[questID] = nil, nil
end

---------------------------------------------------------------------------
-- Kills
---------------------------------------------------------------------------

-- KILL from PARTY_KILL is attributed but silent for a pet's killing blow;
-- TDIED from PLAYER_TARGET_DIED fires for the target whoever killed it. Both
-- hide the GUID inside instances. TDIED is dropped when KILL covered it.

local lastKillGUID, lastKillTime = nil, 0

-- Classification, level (-1 is "??"), creature type ID and its localized name
-- (UnitCreatureType returns name, id). Read from the target, so only when the
-- dying unit is the current target.
local function creatureFacts(unit)
  local typeName, typeID = UnitCreatureType(unit)
  return UnitClassification(unit), UnitLevel(unit), typeID, typeName
end

local function targetFacts(guid)
  if guid == nil or (issecretvalue and issecretvalue(guid)) then return nil end
  local targetGUID = UnitGUID("target")
  if targetGUID == nil or (issecretvalue and issecretvalue(targetGUID)) then return nil end
  if targetGUID ~= guid then return nil end
  return creatureFacts("target")
end

handlers.PARTY_KILL = function(attackerGUID, targetGUID)
  local role
  if issecretvalue and issecretvalue(attackerGUID) then
    role = "?"          -- never compare a secret; it's still a kill
  elseif attackerGUID == playerGUID then
    role = "P"
  elseif attackerGUID ~= nil and attackerGUID == UnitGUID("pet") then
    role = "T"
  else
    role = "G"
  end
  write("KILL", targetGUID, role, targetFacts(targetGUID))
  counts.kills = counts.kills + 1
  if not (issecretvalue and issecretvalue(targetGUID)) then
    lastKillGUID, lastKillTime = targetGUID, GetTime()
  end
end

handlers.PLAYER_TARGET_DIED = function()
  local guid = UnitGUID("target")
  local secret = issecretvalue and issecretvalue(guid)
  if not secret and guid ~= nil and guid == lastKillGUID and GetTime() - lastKillTime <= 1 then
    return
  end
  if secret then
    write("TDIED", "")
  else
    write("TDIED", guid, creatureFacts("target"))
  end
  counts.kills = counts.kills + 1
end

---------------------------------------------------------------------------
-- Loot
---------------------------------------------------------------------------

-- Which message a loot line came from, matched against the client's own
-- format strings in the player's language. Counted forms come first, since
-- the plain form's "%s" would swallow a trailing "x3"; no match leaves the
-- kind empty. "item" is pushed into the bags without a loot window (quest
-- rewards, mail, each step of an item upgrade on Retail).
local LOOT_FORMATS = {
  { "LOOT_ITEM_SELF_MULTIPLE", "loot" },             { "LOOT_ITEM_SELF", "loot" },
  { "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "item" },      { "LOOT_ITEM_PUSHED_SELF", "item" },
  { "LOOT_ITEM_CREATED_SELF_MULTIPLE", "create" },   { "LOOT_ITEM_CREATED_SELF", "create" },
  { "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", "bonus" }, { "LOOT_ITEM_BONUS_ROLL_SELF", "bonus" },
  { "LOOT_ITEM_REFUND_MULTIPLE", "refund" },         { "LOOT_ITEM_REFUND", "refund" },
}
local lootPatterns          -- { pattern, kind, slots, args }: slots[n] is "s" (the link) or "d" (the count)
local missingFormats = {}

-- A format string as an anchored Lua pattern, "%s" and "%d" (and "%1$s") as
-- captures. A positional format may reorder its arguments, so slots[n] says
-- what the nth capture is and args[n] which argument it fills.
local function messagePattern(fmt)
  local slots, args = {}, {}
  local body = fmt:gsub("%%(%d*)%$?([sd])", function(position, kind)
    slots[#slots + 1] = kind
    args[#args + 1] = tonumber(position) or #args + 1
    return kind == "s" and "\1" or "\2"
  end)
  body = body:gsub("[%%%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
  body = body:gsub("\1", "(.-)"):gsub("\2", "(%%d+)")
  return "^" .. body .. "$", slots, args
end

-- One pattern per format the client has; one it lacks is noted for /widsith check.
local function buildPatterns(formats)
  local out = {}
  for _, entry in ipairs(formats) do
    local fmt = _G[entry[1]]
    if type(fmt) == "string" and fmt ~= "" then
      local pattern, slots, args = messagePattern(fmt)
      out[#out + 1] = { pattern = pattern, kind = entry[2], slots = slots, args = args }
    else
      missingFormats[#missingFormats + 1] = entry[1]
    end
  end
  return out
end

-- A message's values by the format's argument numbers, or nothing on no match.
local function messageArgs(p, msg)
  local captures = { msg:match(p.pattern) }
  if captures[1] == nil then return end
  local values = {}
  for i, arg in ipairs(p.args) do values[arg] = captures[i] end
  return values
end

local function buildLootPatterns()
  lootPatterns = buildPatterns(LOOT_FORMATS)
end

-- The other messages' patterns, built the same way in their own sections.
local buildMoneyPatterns, buildRollPatterns, buildSystemPatterns

-- The format strings this client lacks, for /widsith check.
function WJ.missingFormatNames()
  if not lootPatterns then buildLootPatterns() end
  buildMoneyPatterns()
  buildRollPatterns()
  buildSystemPatterns()
  return missingFormats
end

-- The kind of a loot message and the count it names, if any.
local function lootKind(msg)
  if not lootPatterns then buildLootPatterns() end
  for _, p in ipairs(lootPatterns) do
    local first, second = msg:match(p.pattern)
    if first then
      local count
      for i, slot in ipairs(p.slots) do
        if slot == "d" then count = tonumber(i == 1 and first or second) end
      end
      return p.kind, count
    end
  end
end

-- Snapshot of the last loot window: itemID -> source GUID, plus when it opened.
local lootWindow = { time = 0, items = {} }
local LOOT_WINDOW = 5

handlers.LOOT_OPENED = function()
  local items = {}
  local n = GetNumLootItems()
  for slot = 1, n do
    local link = GetLootSlotLink(slot)
    local itemID = link and link:match("item:(%d+)")
    if itemID then
      local guid = GetLootSourceInfo(slot)
      items[tonumber(itemID)] = guid
    end
  end
  lootWindow.time, lootWindow.items = GetTime(), items
end

-- LOOTROLL choice itemID itemString: the character's own group loot choices
-- and wins, from the loot channel's self-only wordings (the sender of a roll
-- message isn't documented). A win's item arrives as its own LOOT.
local ROLL_FORMATS = {
  { "LOOT_ROLL_NEED_SELF", "need" }, { "LOOT_ROLL_GREED_SELF", "greed" },
  { "LOOT_ROLL_PASSED_SELF", "pass" }, { "LOOT_ROLL_YOU_WON", "won" },
}
local rollPatterns

function buildRollPatterns()
  if not rollPatterns then rollPatterns = buildPatterns(ROLL_FORMATS) end
end

-- Writes the line and returns true when the message is a roll.
local function noteLootRoll(msg)
  buildRollPatterns()
  for _, p in ipairs(rollPatterns) do
    local values = messageArgs(p, msg)
    if values then
      -- The item is the format's "%s"; any numbers are the loot history's.
      local link
      for i, slot in ipairs(p.slots) do
        if slot == "s" then link = values[p.args[i]] break end
      end
      link = link or ""
      write("LOOTROLL", p.kind, tonumber(link:match("item:(%d+)")), link:match("|H(item:[^|]+)|h"))
      return true
    end
  end
  return false
end

handlers.CHAT_MSG_LOOT = function(msg, _, _, _, _, _, _, _, _, _, _, guid)
  -- Neither the text nor `guid` is marked NeverSecret; a secret one is skipped.
  if type(msg) ~= "string" or secret(msg) then return end
  -- A roll names an item but isn't loot.
  if noteLootRoll(msg) then return end
  if secret(guid) or guid ~= playerGUID then return end
  local itemID = msg:match("item:(%d+)")
  if not itemID then return end
  itemID = tonumber(itemID)
  local kind, count = lootKind(msg)
  local qty = count or tonumber(msg:match("|h|rx(%d+)")) or 1
  -- The full item string: bonus IDs, enchant, gems and context.
  local itemString = msg:match("|H(item:[^|]+)|h")
  local source
  if GetTime() - lootWindow.time <= LOOT_WINDOW then
    source = lootWindow.items[itemID]
  end
  -- Quality from the item cache, else the link's own quality tag.
  local quality
  if C_Item and C_Item.GetItemQualityByID then
    local ok, q = pcall(C_Item.GetItemQualityByID, itemID)
    if ok then quality = q end
  end
  if quality == nil then quality = tonumber(msg:match("|cnIQ(%d)")) end
  write("LOOT", itemID, qty, source, quality, kind, itemString)
  counts.loot = counts.loot + 1
end

---------------------------------------------------------------------------
-- Duels and /roll, from system messages everyone nearby sees; a line is kept
-- only when the character is in it.
---------------------------------------------------------------------------

local alsoEvents = {}     -- joined to the handlers at registration

-- Whether a name in a message is the character's own. On WoW Forever a
-- message may give a surname after the name, which must then be theirs.
local function isCharacter(name)
  name = plainString(name)
  if not name then return false end
  local own, surname = UnitName("player")
  own, surname = plainString(own), plainString(surname)
  if not own then return false end
  local first, rest = name:match("^(%S+)%s*(.-)$")
  if first ~= own then return false end
  return rest == "" or surname == nil or rest == surname
end

local SYSTEM_FORMATS = {
  { "DUEL_WINNER_KNOCKOUT", "knockout" }, { "DUEL_WINNER_RETREAT", "retreat" },
  { "RANDOM_ROLL_RESULT", "roll" },
}
local systemPatterns

function buildSystemPatterns()
  if not systemPatterns then systemPatterns = buildPatterns(SYSTEM_FORMATS) end
end

-- DUEL outcome winner loser. Both duel messages give the winner as their
-- first argument, whatever order the wording puts them in.
local DUEL_WAIT = 2       -- s between DUEL_FINISHED and its message, either way round
local duelExplainedAt = -math.huge
local duelWaiting = false

local function noteDuel(outcome, winner, loser)
  if not (isCharacter(winner) or isCharacter(loser)) then return end
  duelExplainedAt = GetTime()
  write("DUEL", outcome, winner, loser)
end

-- ROLL result min max: the character's own /roll.
local function noteRoll(name, result, low, high)
  if isCharacter(name) then write("ROLL", tonumber(result), tonumber(low), tonumber(high)) end
end

alsoEvents.CHAT_MSG_SYSTEM = function(text)
  -- The text is hidden under the game's chat lockdown.
  if type(text) ~= "string" or secret(text) then return end
  buildSystemPatterns()
  for _, p in ipairs(systemPatterns) do
    local values = messageArgs(p, text)
    if values then
      if p.kind == "roll" then
        noteRoll(values[1], values[2], values[3], values[4])
      else
        noteDuel(p.kind, values[1], values[2])
      end
      return
    end
  end
end

-- The end of the character's duel, which doesn't say who won. With no readable
-- message within DUEL_WAIT either side, it is written finished with no names.
handlers.DUEL_FINISHED = function()
  local finishedAt = GetTime()
  if duelWaiting or finishedAt - duelExplainedAt <= DUEL_WAIT then return end
  duelWaiting = true
  C_Timer.After(DUEL_WAIT, WJ.guard("duel", function()
    duelWaiting = false
    if duelExplainedAt >= finishedAt then return end
    write("DUEL", "finished", "", "")
  end))
end

---------------------------------------------------------------------------
-- Gear wear. SNAP lists each worn slot's durability; BROKEN slot itemID when a
-- worn item reaches zero. UPDATE_INVENTORY_DURABILITY has no payload and fires
-- constantly in a fight, so it schedules one read WEAR_WAIT seconds later.
---------------------------------------------------------------------------

local EQUIP_SLOTS = WJ.EQUIP_SLOTS   -- the worn slots, in SNAP's order
local WEAR_WAIT = 5
local wearItem, wearValue = {}, {}   -- each slot's item and durability as last read
local wearDue = false

-- A worn slot's current and maximum durability, and whether either is secret.
-- GetInventoryItemDurability takes the slot alone: it reads the player's gear.
local function slotWear(slot)
  local current, maximum = ask("GetInventoryItemDurability", slot)
  if secret(current) or secret(maximum) then return nil, nil, true end
  return plainNumber(current), plainNumber(maximum), false
end

local function slotItem(slot)
  return plainNumber((ask("GetInventoryItemID", "player", slot)))
end

-- SNAP's durability field, "current/max" per slot. seed: the opening read,
-- where watching for a break starts.
function WJ.durabilityList(seed)
  local entries = {}
  for slot = 1, EQUIP_SLOTS do
    local current, maximum, hidden = slotWear(slot)
    entries[slot] = (current and maximum) and (WJ.field(current) .. "/" .. WJ.field(maximum)) or ""
    if seed then wearItem[slot], wearValue[slot] = slotItem(slot), (not hidden) and current or nil end
  end
  return table.concat(entries, ",")
end

local readWear = WJ.guard("durability", function()
  wearDue = false
  for slot = 1, EQUIP_SLOTS do
    local current, _, hidden = slotWear(slot)
    if not hidden then
      local item = slotItem(slot)
      -- Only the same item going from above zero to zero is a break.
      if current == 0 and item ~= nil and item == wearItem[slot] and (wearValue[slot] or 0) > 0 then
        write("BROKEN", slot, item)
      end
      wearItem[slot], wearValue[slot] = item, current
    end
  end
end)

handlers.UPDATE_INVENTORY_DURABILITY = function()
  if wearDue then return end
  wearDue = true
  C_Timer.After(WEAR_WAIT, readWear)
end

---------------------------------------------------------------------------
-- Weather and daylight. WEATHER type intensity from C_Weather.GetCurrentWeather()
-- at WEATHER_CHANGED (type as Enum.WeatherType); DAYLIGHT isDay from
-- DIEL_CYCLE_CHANGED. Both also with the opening snapshot. DIEL_CYCLE_CHANGED
-- and C_DateAndTime.IsDayTime() exist on WoW Forever, not on Retail.
---------------------------------------------------------------------------

local lastWeather, lastDaylight

local function writeWeather(opening)
  local info = plainTable((ask("C_Weather.GetCurrentWeather")))
  if not info then return end
  local kind, intensity = plainNumber(info.type), plainNumber(info.intensity)
  if kind == nil and intensity == nil then return end
  local key = WJ.field(kind) .. "/" .. WJ.field(intensity)
  if key == lastWeather then return end
  lastWeather = key
  write("WEATHER", kind, intensity)
end

local function writeDaylight(isDay, opening)
  if type(isDay) ~= "boolean" or secret(isDay) then return end
  if isDay == lastDaylight then return end
  lastDaylight = isDay
  write("DAYLIGHT", isDay)
end

handlers.WEATHER_CHANGED = function() writeWeather(false) end
handlers.DIEL_CYCLE_CHANGED = function(isDayTime) writeDaylight(isDayTime, false) end

-- With the opening snapshot (Core.openingState).
function WJ.writeOpeningWorld()
  writeWeather(true)
  writeDaylight((ask("C_DateAndTime.IsDayTime")), true)
end

---------------------------------------------------------------------------
-- Money: MONEY total kind window said source, on every PLAYER_MONEY.
--
-- PLAYER_MONEY has no payload and no reason: GetMoney() is the new total. The
-- reason comes from around it, either a hooked default-UI call (buy, repair,
-- fly, take a letter's money) or the game's own event or chat message (a
-- quest reward, a bonus roll, "You loot 1 Silver"). Each sets a pending
-- reason with the amount the game stated and its source; the next change
-- takes it, and one with no change within MONEY_WINDOW is dropped.
--
-- Hooks run after the call and can't tell it worked, so the change is the
-- figure and the stated amount is what the game listed. The open window, by the
-- interaction manager's name, tells a mailbox's takings from a merchant's.
---------------------------------------------------------------------------

local MONEY_WINDOW = 2    -- s a reason waits for the change it explains
local AFTER = { after = true }
local pending = {}        -- reasons waiting for a change, oldest first
local lastTotal           -- the total the last change left
local lastChange          -- the last change: when, by how much, and the reason it was given

local function expireReasons(now)
  for i = #pending, 1, -1 do
    if now - pending[i].at >= MONEY_WINDOW then table.remove(pending, i) end
  end
end

-- Set a reason. opts.after: the game's report, which may come after its
-- change; a change of that amount already written is completed rather than
-- given a second reason. opts.replaces: a confirmation that replaces the
-- request before it. opts.repeats: one call bringing several changes
-- (selling all junk).
local function moneyReason(kind, said, source, opts)
  local now = GetTime()
  expireReasons(now)
  said, source = plainNumber(said), plainString(source)
  if opts and opts.after and said then
    -- The same reason waiting without its amount: the report completes it.
    for _, r in ipairs(pending) do
      if r.kind == kind and r.said == nil then
        r.said, r.source = said, r.source or source
        return
      end
    end
    local c = lastChange
    if c and now - c.at < MONEY_WINDOW and c.delta and math.abs(c.delta) == said and (c.kind ~= kind or c.said == nil) then
      c.kind, c.said = c.kind or kind, c.said or said
      return
    end
    for _, r in ipairs(pending) do
      if r.said == said and r.kind ~= kind then return end
    end
  end
  for i = #pending, 1, -1 do
    local r = pending[i]
    if r.repeats or (opts and opts.replaces and r.kind == kind) then table.remove(pending, i) end
  end
  pending[#pending + 1] = { kind = kind, said = said, source = source, at = now, repeats = opts and opts.repeats }
end
WJ.moneyReason = moneyReason

-- Open windows by their Enum.PlayerInteractionType name in lower case (the
-- clients number them differently), each with its NPC as a reason's source.
local windowNames = {}
do
  local types = Enum and Enum.PlayerInteractionType
  if type(types) == "table" then
    for name, value in pairs(types) do
      if type(name) == "string" and type(value) == "number" then windowNames[value] = name:lower() end
    end
  end
end
local openWindows = {}    -- in the order shown; the last is the one in front

local function closeWindow(interactionType)
  for i = #openWindows, 1, -1 do
    if openWindows[i].type == interactionType then table.remove(openWindows, i) end
  end
end

local function windowOpen(name)
  for i = #openWindows, 1, -1 do
    if openWindows[i].name == name then return openWindows[i] end
  end
end

local moneyEvents = {}    -- joined to the handlers at registration

moneyEvents.PLAYER_INTERACTION_MANAGER_FRAME_SHOW = function(interactionType)
  if not plainNumber(interactionType) then return end
  closeWindow(interactionType)
  openWindows[#openWindows + 1] = { type = interactionType, name = windowNames[interactionType],
    guid = plainString(UnitGUID("npc")) }
end
moneyEvents.PLAYER_INTERACTION_MANAGER_FRAME_HIDE = function(interactionType)
  if plainNumber(interactionType) then closeWindow(interactionType) end
end
-- A loading screen closes every window.
moneyEvents.LOADING_SCREEN_ENABLED = function() openWindows = {} end

-- A change is written a frame later, since its explaining message can follow
-- PLAYER_MONEY in the same frame. A reason goes first to a change of exactly
-- its amount; what is left takes the oldest reason.
local changesDue = {}

local function writeChanges()
  local due = changesDue
  changesDue = {}
  if #due == 0 then return end
  expireReasons(due[#due].at)
  local running = lastTotal
  for _, c in ipairs(due) do
    local total = plainNumber(c.total)
    c.delta = total and running and total - running
    running = total
  end
  for _, c in ipairs(due) do
    if c.delta then
      for i, r in ipairs(pending) do
        if r.said and r.said == math.abs(c.delta) then
          c.reason = r
          if r.repeats then r.at = c.at else table.remove(pending, i) end
          break
        end
      end
    end
  end
  for _, c in ipairs(due) do
    if not c.reason and pending[1] then
      c.reason = pending[1]
      if c.reason.repeats then c.reason.at = c.at else table.remove(pending, 1) end
    end
  end
  for _, c in ipairs(due) do
    local r = c.reason
    write("MONEY", c.total, r and r.kind, c.window, r and r.said, r and r.source)
    lastChange = { at = c.at, delta = c.delta, kind = r and r.kind, said = r and r.said }
    lastTotal = plainNumber(c.total)
  end
end

-- Written out at once when the session ends.
function WJ.flushMoney()
  writeChanges()
end

handlers.PLAYER_MONEY = function()
  local window = openWindows[#openWindows]
  changesDue[#changesDue + 1] = { total = GetMoney(), at = GetTime(), window = window and window.name }
  if #changesDue == 1 then C_Timer.After(0, WJ.guard("money", writeChanges)) end
end

-- Loot money. The loot window's coin slot has no amount; it is in the
-- CHAT_MSG_MONEY message, read with the client's own formats (longer forms
-- first) and its "%d Gold" / "%d Silver" / "%d Copper" strings.
local MONEY_FORMATS = {
  { "YOU_LOOT_MONEY_GUILD", "loot" },     { "YOU_LOOT_MONEY", "loot" },
  { "LOOT_MONEY_SPLIT_GUILD", "share" },  { "LOOT_MONEY_SPLIT", "share" },
  { "LOOT_MONEY_REFUND", "refund" },
}
local COIN_FORMATS = { { "GOLD_AMOUNT", 10000 }, { "SILVER_AMOUNT", 100 }, { "COPPER_AMOUNT", 1 } }
local moneyPatterns, coinPatterns

-- Declared with the loot patterns, so /widsith check can build them too.
function buildMoneyPatterns()
  if moneyPatterns then return end
  moneyPatterns, coinPatterns = buildPatterns(MONEY_FORMATS), {}
  for _, entry in ipairs(COIN_FORMATS) do
    local fmt = _G[entry[1]]
    if type(fmt) == "string" and fmt ~= "" then
      -- Unanchored: a coin is one part of the amount.
      coinPatterns[#coinPatterns + 1] = { pattern = (messagePattern(fmt)):sub(2, -2), copper = entry[2] }
    else
      missingFormats[#missingFormats + 1] = entry[1]
    end
  end
end

-- "1 Silver, 20 Copper" -> 120, or nil when any digit is left unexplained.
local function coinAmount(text)
  local total, found, rest = 0, false, text
  for _, coin in ipairs(coinPatterns) do
    local n
    rest = rest:gsub(coin.pattern, function(digits) n = tonumber(digits) return "" end, 1)
    if n then total, found = total + n * coin.copper, true end
  end
  if not found or rest:find("%d") then return nil end
  return total
end

-- The last loot window's coin source. Nothing marks a pickpocket's window; it
-- is the one opening soon after Pick Pocket (spell 921) succeeds.
local PICK_POCKET, PICK_POCKET_WINDOW = 921, 2
local lootMoney = { at = -math.huge }
local pickPocket = { at = -math.huge }

moneyEvents.UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
  if unit ~= "player" or plainNumber(spellID) ~= PICK_POCKET then return end
  pickPocket = { at = GetTime(), target = plainString(UnitGUID("target")) }
end

moneyEvents.LOOT_OPENED = function()
  local now = GetTime()
  local stolen = now - pickPocket.at <= PICK_POCKET_WINDOW
  local moneySlot = Enum and Enum.LootSlotType and Enum.LootSlotType.Money
  local source, hasCoin = nil, false
  local n = plainNumber((ask("GetNumLootItems"))) or 0
  for slot = 1, n do
    if moneySlot and plainNumber((ask("GetLootSlotType", slot))) == moneySlot then
      hasCoin = true
      source = plainString((ask("GetLootSourceInfo", slot)))
      break
    end
  end
  if stolen and not source then source = pickPocket.target end
  lootMoney = { at = now, source = source, stolen = stolen }
  -- A coin slot is a reason by itself; the chat message fills in the amount later.
  if hasCoin then moneyReason(stolen and "pickpocket" or "loot", nil, source) end
end

moneyEvents.CHAT_MSG_MONEY = function(text)
  if type(text) ~= "string" or secret(text) then return end
  buildMoneyPatterns()
  for _, p in ipairs(moneyPatterns) do
    local amount = text:match(p.pattern)
    if amount then
      local kind = p.kind
      local fromWindow = kind ~= "refund" and GetTime() - lootMoney.at <= LOOT_WINDOW
      if kind == "loot" and fromWindow and lootMoney.stolen then kind = "pickpocket" end
      moneyReason(kind, coinAmount(amount), fromWindow and lootMoney.source or nil, AFTER)
      return
    end
  end
end

-- Money the game states in an event of its own.
moneyEvents.BONUS_ROLL_RESULT = function(typeIdentifier, _, quantity)
  if plainString(typeIdentifier) == "money" then moneyReason("bonus", quantity, nil, AFTER) end
end
moneyEvents.SHOW_LOOT_TOAST = function(typeIdentifier, _, quantity)
  if plainString(typeIdentifier) == "money" then moneyReason("toast", quantity, nil, AFTER) end
end
moneyEvents.CRAFTINGORDERS_DISPLAY_CRAFTER_FULFILLED_MSG = function(_, _, _, tipAmount)
  local tip = plainNumber(tipAmount)
  if tip and tip > 0 then moneyReason("commission", tip, nil, AFTER) end
end

-- A completed trade, from Extras.lua; money both ways states no single amount.
function WJ.moneyFromTrade(gave, got)
  gave, got = plainNumber(gave) or 0, plainNumber(got) or 0
  if gave == 0 and got == 0 then return end
  local said
  if gave == 0 then said = got elseif got == 0 then said = gave end
  moneyReason("trade", said, nil, AFTER)
end

-- Costs the game states while a window is open, kept for the hooked call that
-- follows (the repair hook runs only once the bill is paid).
local repairCost, questFee, talentWipeCost, commodityTotal
local gossipCost = {}
local letters = {}

local function noteRepairCost()
  local cost, canRepair = ask("GetRepairAllCost")
  repairCost = (not secret(canRepair) and canRepair) and plainNumber(cost) or nil
end
moneyEvents.MERCHANT_SHOW = noteRepairCost
moneyEvents.MERCHANT_UPDATE = noteRepairCost

moneyEvents.QUEST_COMPLETE = function() questFee = plainNumber((ask("GetQuestMoneyToGet"))) end
moneyEvents.CONFIRM_TALENT_WIPE = function(cost) talentWipeCost = plainNumber(cost) end
moneyEvents.GOSSIP_CONFIRM = function(gossipID, _, cost) gossipCost = { id = plainNumber(gossipID), cost = plainNumber(cost) } end
moneyEvents.COMMODITY_PRICE_UPDATED = function(_, total) commodityTotal = plainNumber(total) end

local function readLetter(index)
  local money, cod = select(5, ask("GetInboxHeaderInfo", index))
  return { money = plainNumber(money), cod = plainNumber(cod), invoice = plainString((ask("GetInboxInvoiceInfo", index))) }
end
moneyEvents.MAIL_INBOX_UPDATE = function()
  letters = {}
  for i = 1, plainNumber((ask("GetInboxNumItems"))) or 0 do letters[i] = readLetter(i) end
end
local function letter(index)
  return (plainNumber(index) and letters[index]) or readLetter(index)
end
-- An auction house letter's invoice type tells a sale from a refunded bid.
local function letterKind(l)
  if l.invoice == "seller" or l.invoice == "seller_temp_invoice" then return "ahsale" end
  if l.invoice == "buyer" then return "ahrefund" end
  return "mailtake"
end

-- A vendor's price is per listed stack; a quantity buys that many units of it.
local function buyPrice(index, quantity)
  local info = plainTable((ask("C_MerchantFrame.GetItemInfo", index)))
  local price = info and plainNumber(info.price)
  if not price then return end
  local stack, count = plainNumber(info.stackCount), plainNumber(quantity)
  if not count or not stack or stack < 1 then return price end
  return math.floor(price / stack * count + 0.5)
end

-- An item sold from the bags: unit price times stack while the slot still
-- holds it, else the newest buy-back entry.
local function sellPrice(bag, slot)
  if not windowOpen("merchant") then return nil, false end
  local info = plainTable((ask("C_Container.GetContainerItemInfo", bag, slot)))
  local itemID = info and plainNumber(info.itemID)
  if itemID then
    local unit = plainNumber((select(11, ask("C_Item.GetItemInfo", itemID))))
    if unit then return unit * (plainNumber(info.stackCount) or 1) end
  end
  local n = plainNumber((ask("GetNumBuybackItems")))
  if n and n > 0 then return (select(3, ask("GetBuybackItemInfo", n))) end
end

local function commodityDeposit(item, duration, quantity)
  return (ask("C_AuctionHouse.CalculateCommodityDeposit", (ask("C_Item.GetItemID", item)), duration, quantity))
end
local function itemDeposit(item, duration, quantity)
  return (ask("C_AuctionHouse.CalculateItemDeposit", item, duration, quantity))
end

-- The default UI's money calls: function, kind, and a reader given the call's
-- arguments that returns the amount and optionally another kind, or false for
-- no money. npc names the window whose NPC is the source.
local MONEY_HOOKS = {
  { "BuyMerchantItem", "buy", buyPrice, npc = "merchant" },
  { "C_Container.UseContainerItem", "sell", sellPrice, npc = "merchant" },
  { "C_MerchantFrame.SellAllJunkItems", "junk", nil, npc = "merchant", repeats = true },
  { "BuybackItem", "buyback", function(slot) return (select(3, ask("GetBuybackItemInfo", slot))) end, npc = "merchant" },
  -- When the guild pays, nothing changes and the reason lapses.
  { "RepairAllItems", "repair", function() return repairCost end, npc = "merchant" },
  { "TakeTaxiNode", "taxi", function(index) return (ask("TaxiNodeCost", index)) end, npc = "taxinode" },
  { "BuyTrainerService", "train", function(index) return (ask("GetTrainerServiceCost", index)) end, npc = "trainer" },
  { "ConfirmTalentWipe", "respec", function() return talentWipeCost end },
  { "GetQuestReward", "questfee", function()
    if questFee and questFee > 0 then return questFee end
    return nil, false
  end },
  { "C_GossipInfo.SelectOption", "gossip", function(optionID, _, confirmed)
    local cost = gossipCost.cost
    if confirmed ~= true or not cost or cost <= 0 then return nil, false end
    if gossipCost.id and plainNumber(optionID) ~= gossipCost.id then return nil, false end
    return cost
  end },
  -- GetSendMailPrice is postage and attached money together, taken in one change.
  { "SendMail", "mailsend", function() return (ask("GetSendMailPrice")) end },
  { "TakeInboxMoney", "mailtake", function(index)
    local l = letter(index)
    return l.money, letterKind(l)
  end },
  { "AutoLootMailItem", "mailtake", function(index)
    local l = letter(index)
    if l.cod and l.cod > 0 then return l.cod, "cod" end
    if l.money and l.money > 0 then return l.money, letterKind(l) end
    return nil, false
  end },
  { "TakeInboxItem", "cod", function(index)
    local l = letter(index)
    if l.cod and l.cod > 0 then return l.cod end
    return nil, false
  end },
  { "C_AuctionHouse.PostItem", "ahdeposit", itemDeposit },
  { "C_AuctionHouse.ConfirmPostItem", "ahdeposit", itemDeposit, replaces = true },
  { "C_AuctionHouse.PostCommodity", "ahdeposit", commodityDeposit },
  { "C_AuctionHouse.ConfirmPostCommodity", "ahdeposit", commodityDeposit, replaces = true },
  { "C_AuctionHouse.PlaceBid", "ahbid", function(_, bidAmount) return bidAmount end },
  { "C_AuctionHouse.ConfirmCommoditiesPurchase", "ahbuy", function() return commodityTotal end },
  { "C_AuctionHouse.CancelAuction", "ahcancel", function(auctionID)
    return (ask("C_AuctionHouse.GetCancelCost", auctionID))
  end },
  { "DepositGuildBankMoney", "guildbankin", function(copper) return copper end },
  { "WithdrawGuildBankMoney", "guildbankout", function(copper) return copper end },
  { "BuyGuildBankTab", "guildtab", function() return (ask("GetGuildBankTabCost")) end },
  { "C_Bank.DepositMoney", "bankin", function(_, amount) return amount end },
  { "C_Bank.WithdrawMoney", "bankout", function(_, amount) return amount end },
  { "C_Bank.PurchaseBankTab", "banktab", function(bankType)
    local tab = plainTable((ask("C_Bank.FetchNextPurchasableBankTabData", bankType)))
    return tab and tab.tabCost
  end },
  { "C_TransmogOutfitInfo.CommitAndApplyAllPending", "transmog", function()
    return (ask("C_TransmogOutfitInfo.GetPendingTransmogCost"))
  end },
  { "C_BarberShop.ApplyCustomizationChoices", "barber", function() return (ask("C_BarberShop.GetCurrentCost")) end },
  { "C_ItemUpgrade.UpgradeItem", "upgrade" },
  { "C_CraftingOrders.PlaceNewOrder", "craftorder", function(orderInfo)
    local info = plainTable(orderInfo)
    return info and info.tipAmount
  end },
  { "C_BlackMarket.ItemPlaceBid", "blackmarket", function(_, bid) return bid end },
  { "BuyGuildCharter", "charter", function() return (ask("GetGuildCharterCost")) end },
  { "C_StableInfo.BuyStableSlot", "stable", function() return (ask("C_StableInfo.GetNextStableSlotCost")) end },
}

local function fromHook(signal, ...)
  local kind, said = signal[2], nil
  if signal[3] then
    local amount, other = signal[3](...)
    if other == false then return end
    said, kind = amount, other or kind
  end
  local window = signal.npc and windowOpen(signal.npc)
  moneyReason(kind, said, window and window.guid, signal)
end

-- A function this client lacks is skipped; each hook is guarded.
function WJ.installMoneyHooks()
  for _, signal in ipairs(MONEY_HOOKS) do
    local owner, name = resolve(signal[1])
    if type(owner) == "table" and type(owner[name]) == "function" then
      local fn = WJ.guard(signal[1], function(...) fromHook(signal, ...) end)
      if owner == _G then hooksecurefunc(name, fn) else hooksecurefunc(owner, name, fn) end
    end
  end
end

-- Joins extra handlers to any already on the same event, each guarded on its own.
local function joinEvents(extra)
  for event, fn in pairs(extra) do
    local first = handlers[event]
    if first then
      local a, b = WJ.guard(event, first), WJ.guard(event, fn)
      handlers[event] = function(...) a(...) b(...) end
    else
      handlers[event] = fn
    end
  end
end

local function joinSharedEvents()
  joinEvents(moneyEvents)
  joinEvents(alsoEvents)
  moneyEvents, alsoEvents = {}, {}
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

-- Unit events that would otherwise fire for every unit in range.
WJ.unitEvents = {
  UNIT_SPELLCAST_SUCCEEDED = "player",
  UNIT_SPELLCAST_START = "player",
  UNIT_SPELLCAST_CHANNEL_START = "player",
  UNIT_QUEST_LOG_CHANGED   = "player",
  PLAYER_XP_UPDATE         = "player",
}

-- Registering an event the client lacks throws (WoW Forever has no pet
-- battles); those are skipped and listed by /widsith check.
function WJ.registerEvents(frame)
  joinSharedEvents()
  local missing = {}
  for event in pairs(handlers) do
    local unit = WJ.unitEvents[event]
    local ok
    if unit and frame.RegisterUnitEvent then
      ok = pcall(frame.RegisterUnitEvent, frame, event, unit)
    else
      ok = pcall(frame.RegisterEvent, frame, event)
    end
    if not ok then missing[#missing + 1] = event end
  end
  table.sort(missing)
  WJ.unregisteredEvents = missing
end

-- Experience and money granted behind a loading screen may come with no event,
-- so each arrival and snapshot rereads them and writes any difference through
-- the event's own handler. Experience with no maximum, or money at zero where the lines
-- said more, is a character not yet loaded and is skipped.
-- atOnce: write a money change now, before the snapshot that follows.
function WJ.catchUpProgress(atOnce)
  local max = plainNumber(UnitXPMax("player"))
  if max and max > 0 then handlers.PLAYER_XP_UPDATE("player") end
  local due = changesDue[#changesDue]
  local known = due and plainNumber(due.total) or lastTotal
  local total = plainNumber(GetMoney())
  local unloaded = total == 0 and known and known > 0
  if total and total ~= known and not unloaded then handlers.PLAYER_MONEY() end
  if atOnce then writeChanges() end
end

-- Called at session start. Seeds the caches so existing state writes no change.
function WJ.seedState()
  -- Weather and daylight are stated afresh with the opening snapshot.
  lastWeather, lastDaylight = nil, nil
  lastXP, lastXPMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
  if InCombatLockdown() then write("COMBAT", "enter") end
  if WJ.seedMoments then WJ.seedMoments() end
  lastResting = IsResting() and true or false
  if lastResting then write("REST", "enter") end
  lastTotal, lastChange = plainNumber(GetMoney()), nil
  lastGroup = nil
  if IsInGroup() then writeGroupIfChanged() else lastGroup = "0none" end
  C_Timer.After(2, WJ.guard("questSeed", function() diffQuestLog(true) end))
end

-- A session resumed after a pause opens the way a reload does.
function WJ.onResume()
  currentInstanceMapID = 0
  lastZone, lastSubzone = nil, nil
  lastWeather, lastDaylight = nil, nil
  wearItem, wearValue = {}, {}
  WJ.resetPositionForSession()
  if WJ.resetExtrasForSession then WJ.resetExtrasForSession() end
  if WJ.resetMomentsForSession then WJ.resetMomentsForSession() end
  WJ.onEnteringWorld(false, true)
  writeZoneIfChanged()
end
