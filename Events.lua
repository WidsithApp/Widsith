-- Widsith — Events
--
-- Everything event-driven. Each handler turns one WoW event into zero or more
-- lines, using only what the event and the APIs expose at that instant. Where
-- a handler looks roundabout, the comment beside it says what the game does
-- that makes the obvious way wrong.

local _, WJ = ...

local write, counts = WJ.write, WJ.counts
local handlers = {}
WJ.handlers = handlers

local playerGUID

-- Values that may be compared, added or joined: present, of the right type and
-- not secret. Doing any of those to a secret value throws.
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

-- A game function by its dotted name ("C_Bank.DepositMoney"), and where it
-- lives: the namespace table, or _G for a global.
local function resolve(path)
  local namespace, name = path:match("^([^%.]+)%.(.+)$")
  if namespace then return _G[namespace], name end
  return _G, path
end

local function pass(ok, ...)
  if ok then return ... end
end

-- What the named game function returns, or nothing when the client lacks it
-- or it throws.
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
    currentInstanceMapID = instanceMapID
    transition = true
  elseif instanceType == "none" and currentInstanceMapID ~= 0 then
    write("INST", "leave", currentInstanceMapID, instanceType)
    currentInstanceMapID = 0
    transition = true
  end
  -- Any loading screen but login is a relocation: name the cast behind it, if one preceded
  -- it (a hearthstone out of a dungeon, a portal into a city). Walking through an instance
  -- door has no cast behind it; Extras.lua only accepts a cast that finished just before the
  -- loading screen appeared, so a mount or ability used on the way to the door stays silent.
  if not (isLogin or isReload) then
    WJ.onRelocation("load")
  end
end

-- Subzone text flaps at boundaries (6 changes in 3 s crossing a city district),
-- so the zone is written only once it has held for ZONE_SETTLE seconds.
local ZONE_SETTLE = 1.5
local zoneTimer

local function writeZoneIfChanged()
  zoneTimer = nil
  local zone, subzone = GetZoneText(), GetSubZoneText()
  if zone ~= lastZone or subzone ~= lastSubzone then
    write("ZONE", zone, subzone)
    lastZone, lastSubzone = zone, subzone
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
-- Combat and rest. Plain frame events with no payload, nothing
-- secret. The opening state is written at session start (seedState) so a
-- session that begins mid-fight or in an inn reads right from its first line.
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
-- Group. Size, kind and who the other members are: class, GUID and
-- Name-Realm (character names are public in WoW), and each one's level in
-- the same order. GROUP_ROSTER_UPDATE fires often, so a line is written only
-- when the picture changed; the opening state is seeded at session start.
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
        -- classID:guid:Name-Realm. Each part passes through field() so a secret
        -- (instanced content can hide identity) becomes empty, never an error.
        local _, _, classID = UnitClass(unit)
        local name, realm = UnitFullName(unit)
        -- Through field() *before* concatenation: concatenating a secret value throws.
        name, realm = WJ.field(name), WJ.field(realm)
        if realm == "" then realm = WJ.field(GetNormalizedRealmName()) end
        local full = name ~= "" and (name .. "-" .. realm) or ""
        members[#members + 1] = WJ.field(classID) .. ":" .. WJ.field(UnitGUID(unit)) .. ":" .. full
        -- A level the game hides is an empty entry, so the list stays in step with the members.
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

-- Any addon's RequestTimePlayed() produces a reply for everyone; identical
-- consecutive replies carry no information.
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

-- The event carries what the level brought: health, power, talent points, PvP talent
-- slots, then strength, agility, stamina and intellect (UnitDocumentation.lua).
handlers.PLAYER_LEVEL_UP = function(level, ...)
  write("LEVEL", level, ...)
  -- Stats and UnitLevel() update after the event; snapshot once they have.
  C_Timer.After(1, WJ.guard("levelSnapshot", WJ.snapshot))
end

-- MONEY is written in its own section below, with the reason for each change.

local deathOutstanding = false
local lastFeignClock
local FEIGN_REPEAT = 2   -- s; a real death's second PLAYER_DEAD came 0.5 s after the first

-- Fires twice per death on 12.1, and also for Feign Death. A real death is
-- outstanding until PLAYER_ALIVE / PLAYER_UNGHOST, which dedupes its second
-- firing. A feign is never outstanding — nothing resurrects it, so it would
-- hide the next real death and write a stray ALIVE — and is deduped by time.
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

-- One NPC line per dialog: the same type and GUID within 10 s is the same
-- conversation (a quest giver fires several quest events per visit).
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
  local guid = UnitGUID("npc") or UnitGUID("questnpc")
  if guid then
    lastGiverGUID, lastGiverTime = guid, GetTime()
    -- The interaction manager never announces a quest-giver frame (type 4):
    -- it reports the frame hiding but never showing. These events are the show.
    noteNPC(4, guid)
  end
end
handlers.QUEST_GREETING = rememberGiver
handlers.QUEST_DETAIL   = rememberGiver
handlers.QUEST_COMPLETE = rememberGiver
handlers.QUEST_PROGRESS = rememberGiver

local function giverGUID()
  local guid = UnitGUID("npc") or UnitGUID("questnpc")
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

-- Whether the game says the quest is ready to turn in: every objective met,
-- counted or not (an escort, a delivery, a talk has no count to watch).
-- ReadyForTurnIn where the client has it, else the older IsComplete; nil
-- when neither answers.
local function questReady(questID)
  local ask = C_QuestLog.ReadyForTurnIn or C_QuestLog.IsComplete
  if type(ask) ~= "function" then return nil end
  local ok, answer = pcall(ask, questID)
  if not ok or (issecretvalue and issecretvalue(answer)) then return nil end
  return answer == true
end

-- A quest's objectives as they stand when it enters the log: one QPROG each,
-- so a reader has the whole list from the start. A count of 0 is an objective
-- listed, not progress.
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

-- Titles for every quest already in the log, so quests accepted before the
-- recording began still have a label (QLABEL). Written with the
-- opening snapshot, once quest data has loaded; a title the client doesn't
-- have yet is skipped rather than guessed.
function WJ.writeQuestLabels()
  if not C_QuestLog.GetTitleForQuestID then return end
  for _, questID in ipairs(WJ.questIDs()) do
    local title = C_QuestLog.GetTitleForQuestID(questID)
    if title and title ~= "" then write("QLABEL", questID, title) end
  end
end

-- Diff the whole log against the cache. Emits QPROG for every changed
-- objective, the whole list for a quest new to the log, and QDONE when the
-- game first says a quest is ready to turn in. Sub-millisecond even with a
-- full log (0.1–0.3 ms measured). A silent pass seeds the cache and writes
-- no progress: the seed two seconds after entering the world, and the one
-- with the opening snapshot, which alone also writes the quests already
-- ready, marked as the state the session began in.
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
            -- Trailing objective wording: free at capture, a
            -- label like every other, and the only way to name an objective
            -- that no kill precedes (gather, use, event).
            write("QPROG", questID, idx, o.fulfilled, o.required, o.type, o.text)
            changes = changes + 1
          end
        end
      elseif not silent then
        -- In the log without an accept of its own (shared, or taken on by the game).
        writeObjectiveList(questID, now)
        changes = changes + #now
      end
      -- The opening pass states what is ready, whatever an earlier session of this load knew
      -- (a session resumed after a pause opens with the same baseline as a reload).
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

-- Not a trigger (fires ~1/s while walking) — but in debug mode it shows
-- whether objective counts are fresh by the time it arrives.
handlers.QUEST_LOG_UPDATE = function()
  if WJ.debug then print("|cff8888ffWJ|r QUEST_LOG_UPDATE") end
end

-- The quest's own level, and the level the game rates its difficulty by (the
-- colour of its name in the log, which follows the player on a quest that
-- scales). Each is empty when the client can't say or hides it.
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
  -- Its objectives, listed at once; a quest the game hands over already
  -- finished is ready from this moment.
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
  -- The reward's money, as the game states it, explains the change it brings.
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

-- Two independent facts about a kill:
--   KILL  from PARTY_KILL — attributed, but silent inside instances and
--         for a pet's killing blow.
--   TDIED from PLAYER_TARGET_DIED — fires for our target's death whoever
--         landed the blow; the GUID is secret inside instances.
-- When both describe the same unit in the same second, TDIED is dropped.

local lastKillGUID, lastKillTime = nil, 0

-- What the thing was, at the instant it died: classification (normal, elite,
-- rare, rareelite, worldboss, trivial, minus), level (-1 is "??"), creature
-- type as its ID (1 Beast … 7 Humanoid …; UnitCreatureType returns name, id
-- since 11.1.5) with the localized name as a trailing label. Read from the
-- target unit, so only when the dying unit is our current target. Secrets
-- and mismatches become empty fields.
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

-- Which message a loot line came from, told by the game's own wording in the
-- player's language: the format strings the client prints a player's own loot
-- with ("You receive loot: %s.", "You receive item: %sx%d.", and so on),
-- turned into patterns once, on first use. Each kind has a form with a count
-- and one without; the counted forms are tried first, since the plain form's
-- "%s" would swallow a trailing "x3". A message that matches none keeps its
-- kind empty, never guessed: a wrong kind would show loot dropping from
-- nowhere. "item" is what the game pushes into the bags without a loot
-- window: quest rewards, mail, and on Retail every step of an item upgrade,
-- which prints the same item again each time.
local LOOT_FORMATS = {
  { "LOOT_ITEM_SELF_MULTIPLE", "loot" },             { "LOOT_ITEM_SELF", "loot" },
  { "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "item" },      { "LOOT_ITEM_PUSHED_SELF", "item" },
  { "LOOT_ITEM_CREATED_SELF_MULTIPLE", "create" },   { "LOOT_ITEM_CREATED_SELF", "create" },
  { "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", "bonus" }, { "LOOT_ITEM_BONUS_ROLL_SELF", "bonus" },
  { "LOOT_ITEM_REFUND_MULTIPLE", "refund" },         { "LOOT_ITEM_REFUND", "refund" },
}
local lootPatterns          -- { pattern, kind, slots }: slots[n] is "s" (the link) or "d" (the count)
local missingLootFormats = {}

-- A format string as a Lua pattern anchored at both ends: "%s" and "%d" (and
-- their positional forms, "%1$s") become captures; the rest matches literally.
local function lootPattern(fmt)
  local slots = {}
  local body = fmt:gsub("%%%d*%$?([sd])", function(kind)
    slots[#slots + 1] = kind
    return kind == "s" and "\1" or "\2"
  end)
  body = body:gsub("[%%%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
  body = body:gsub("\1", "(.-)"):gsub("\2", "(%%d+)")
  return "^" .. body .. "$", slots
end

local function buildLootPatterns()
  lootPatterns = {}
  for _, entry in ipairs(LOOT_FORMATS) do
    local fmt = _G[entry[1]]
    if type(fmt) == "string" and fmt ~= "" then
      local pattern, slots = lootPattern(fmt)
      lootPatterns[#lootPatterns + 1] = { pattern = pattern, kind = entry[2], slots = slots }
    else
      missingLootFormats[#missingLootFormats + 1] = entry[1]
    end
  end
end

local buildMoneyPatterns   -- the money messages' patterns, built the same way (the money section)

-- The format strings this client lacks, for /widsith check.
function WJ.missingLootFormatNames()
  if not lootPatterns then buildLootPatterns() end
  buildMoneyPatterns()
  return missingLootFormats
end

-- The kind of a loot message and the count it names, or nothing for a
-- wording the client's own formats don't explain.
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

handlers.CHAT_MSG_LOOT = function(msg, _, _, _, _, _, _, _, _, _, _, guid)
  -- The wiki doesn't mark `guid` or the text NeverSecret. A secret one can't be
  -- compared (it throws), so whose loot it was can't be told: skip the line
  -- rather than record a group member's loot as the player's.
  if issecretvalue and (issecretvalue(guid) or issecretvalue(msg)) then return end
  if guid ~= playerGUID or type(msg) ~= "string" then return end
  local itemID = msg:match("item:(%d+)")
  if not itemID then return end
  itemID = tonumber(itemID)
  local kind, count = lootKind(msg)
  local qty = count or tonumber(msg:match("|h|rx(%d+)")) or 1
  -- The item as the game linked it: the ID with the bonus IDs, enchant, gems
  -- and context that make this copy the item it is (an upgrade step changes
  -- them, a drop doesn't). The plain ID stays the field a reader counts by.
  local itemString = msg:match("|H(item:[^|]+)|h")
  local source
  if GetTime() - lootWindow.time <= LOOT_WINDOW then
    source = lootWindow.items[itemID]
  end
  -- The item's quality (0 poor … 5 legendary), so the replay can tell
  -- grey junk from an epic. From the item cache; if the item isn't cached
  -- yet, from the link's own quality tag. Neither: empty.
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
-- Money: MONEY total kind window said source, on every PLAYER_MONEY.
--
-- PLAYER_MONEY has no payload: GetMoney() is the new total, and the change is
-- the difference from the last one. The game never says in it why money
-- moved; it says so around it. Either the default UI calls a function (buy,
-- repair, fly, take a letter's money), or the game reports it in an event or a
-- chat message of its own (a quest's reward, a bonus roll, "You loot 1
-- Silver"). Each of those sets a pending reason: its kind, the amount the game
-- stated for it, and where it came from when the game names that (the corpse,
-- the vendor). The next change takes the oldest reason still pending. A reason
-- that no change follows within two seconds is dropped: the server refused it
-- (a flight the player couldn't afford), so it writes nothing.
--
-- The hooks are post-hooks (hooksecurefunc): they show that the call was
-- made, never that it worked, so the change is the figure and the stated
-- amount is only a check on it. A flight's listed cost, for one, ignores the
-- faction discount. Beside the reason is the window open at the time, as the
-- interaction manager names it, which is how the game's own money receipts
-- tell the mailbox's takings from a merchant's.
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

-- Set a reason. opts.after: the game's own report, which may come after the
-- change it explains; if the change already came (by the same amount, with no
-- reason, or under another reason that stated it), the report adds nothing.
-- opts.replaces: a confirmation that takes the place of the request before it.
-- opts.repeats: one call that brings several changes (selling all junk), each
-- of which carries it, until two seconds pass without one or something else
-- is done.
local function moneyReason(kind, said, source, opts)
  local now = GetTime()
  expireReasons(now)
  said, source = plainNumber(said), plainString(source)
  if opts and opts.after and said then
    local c = lastChange
    if c and now - c.at < MONEY_WINDOW and c.delta and math.abs(c.delta) == said and c.kind ~= kind then
      c.kind = c.kind or kind
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

-- The windows open, by the interaction manager's own names for them
-- (Enum.PlayerInteractionType: Merchant, MailInfo, TaxiNode …) in lower case.
-- The names, never the numbers: the clients number them differently. Each
-- remembers the NPC it was opened at, which is the source for a vendor's,
-- trainer's or flight master's reason.
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

local moneyEvents = {}    -- joined to the handlers above at registration

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

-- A change is written a frame after its event, not at it: the message or
-- event that explains it may arrive in the same frame, after PLAYER_MONEY
-- itself (the chat line for looted coin does). The frame costs the line a few
-- milliseconds of time. Within one frame's changes, a reason that states an
-- amount goes to the change of exactly that amount first (a share and the
-- player's own coin can land together); what is left takes the oldest reason.
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
    lastChange = { at = c.at, delta = c.delta, kind = r and r.kind }
    lastTotal = plainNumber(c.total)
  end
end

-- Written out at once when the session ends, so a change in the last frame
-- before a logout or a pause isn't lost.
function WJ.flushMoney()
  writeChanges()
end

handlers.PLAYER_MONEY = function()
  local window = openWindows[#openWindows]
  changesDue[#changesDue + 1] = { total = GetMoney(), at = GetTime(), window = window and window.name }
  if #changesDue == 1 then C_Timer.After(0, WJ.guard("money", writeChanges)) end
end

-- Loot money. The loot window lists coin as a slot with no number in it
-- (GetLootSlotType says Money); the amount is in the chat message the game
-- prints, in the client's own words: "You loot %s", "Your share of the loot is
-- %s.", and the forms with the guild's cut. Each is turned into a pattern the
-- way the item messages are, the longer forms first so the plain one can't
-- swallow them. The coins are read with the client's own "%d Gold", "%d
-- Silver" and "%d Copper", and the stated amount is kept only when they
-- account for every digit in it; anything else would be a guess.
local MONEY_FORMATS = {
  { "YOU_LOOT_MONEY_GUILD", "loot" },     { "YOU_LOOT_MONEY", "loot" },
  { "LOOT_MONEY_SPLIT_GUILD", "share" },  { "LOOT_MONEY_SPLIT", "share" },
  { "LOOT_MONEY_REFUND", "refund" },
}
local COIN_FORMATS = { { "GOLD_AMOUNT", 10000 }, { "SILVER_AMOUNT", 100 }, { "COPPER_AMOUNT", 1 } }
local moneyPatterns, coinPatterns

local function buildMoneyPatterns()
  if moneyPatterns then return end
  moneyPatterns, coinPatterns = {}, {}
  for _, entry in ipairs(MONEY_FORMATS) do
    local fmt = _G[entry[1]]
    if type(fmt) == "string" and fmt ~= "" then
      moneyPatterns[#moneyPatterns + 1] = { pattern = (lootPattern(fmt)), kind = entry[2] }
    else
      missingLootFormats[#missingLootFormats + 1] = entry[1]
    end
  end
  for _, entry in ipairs(COIN_FORMATS) do
    local fmt = _G[entry[1]]
    if type(fmt) == "string" and fmt ~= "" then
      -- Unanchored: a coin is one part of the amount.
      coinPatterns[#coinPatterns + 1] = { pattern = (lootPattern(fmt)):sub(2, -2), copper = entry[2] }
    else
      missingLootFormats[#missingLootFormats + 1] = entry[1]
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

-- The last loot window's coin: where it came from, and whether the window was
-- a pickpocket's. Nothing marks a pickpocket's window as such; it is the one
-- that opens within two seconds of Pick Pocket (spell 921) succeeding.
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
  local source
  local n = plainNumber((ask("GetNumLootItems"))) or 0
  for slot = 1, n do
    if moneySlot and plainNumber((ask("GetLootSlotType", slot))) == moneySlot then
      source = plainString((ask("GetLootSourceInfo", slot)))
      break
    end
  end
  if stolen and not source then source = pickPocket.target end
  lootMoney = { at = now, source = source, stolen = stolen }
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

-- Money the game states outright, as an event: a bonus roll's or a toast's
-- coin, a crafting order's commission.
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

-- A completed trade (Extras.lua writes its line, then tells the money). Money
-- both ways in one trade states no single amount.
function WJ.moneyFromTrade(gave, got)
  gave, got = plainNumber(gave) or 0, plainNumber(got) or 0
  if gave == 0 and got == 0 then return end
  local said
  if gave == 0 then said = got elseif got == 0 then said = gave end
  moneyReason("trade", said, nil, AFTER)
end

-- What the game says while a window is open, kept for the call that follows:
-- the repair bill (the repair hook runs once the bill is paid), a quest's fee,
-- the cost a confirmation dialog names, a commodity's total, and each letter's
-- money and cash on delivery. A letter's sender is never read.
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
-- An auction house's letter says what it is in its invoice: a sale's
-- proceeds, or a buyer's money coming back.
local function letterKind(l)
  if l.invoice == "seller" or l.invoice == "seller_temp_invoice" then return "ahsale" end
  if l.invoice == "buyer" then return "ahrefund" end
  return "mailtake"
end

-- A vendor's stated price: the listing is for one stack, so a purchase with
-- no quantity buys a stack, and one with a quantity buys that many of the
-- stack's units (as the merchant frame works out whether it can be afforded).
local function buyPrice(index, quantity)
  local info = plainTable((ask("C_MerchantFrame.GetItemInfo", index)))
  local price = info and plainNumber(info.price)
  if not price then return end
  local stack, count = plainNumber(info.stackCount), plainNumber(quantity)
  if not count or not stack or stack < 1 then return price end
  return math.floor(price / stack * count + 0.5)
end

-- An item sold from the bags: its unit sell price times the stack, while the
-- slot still holds what was sold; once the bag has moved on, the sale is the
-- newest entry of the merchant's buy-back list.
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

-- The functions the default UI calls to move money, one row each: the
-- function, the kind, and what the game states for it. That reader gets the
-- call's arguments and returns the amount; a second value names a different
-- kind, or false when the call moves no money after all. npc names the window
-- whose NPC is the source; the rest are moneyReason's options.
local MONEY_HOOKS = {
  { "BuyMerchantItem", "buy", buyPrice, npc = "merchant" },
  { "C_Container.UseContainerItem", "sell", sellPrice, npc = "merchant" },
  { "C_MerchantFrame.SellAllJunkItems", "junk", nil, npc = "merchant", repeats = true },
  { "BuybackItem", "buyback", function(slot) return (select(3, ask("GetBuybackItemInfo", slot))) end, npc = "merchant" },
  { "RepairAllItems", "repair", function(guildBankRepair)
    return repairCost, guildBankRepair and "guildrepair" or nil
  end, npc = "merchant" },
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
  -- Sending a letter takes the money attached and the postage, in that order.
  { "SendMail", "mailsend", function()
    local money = plainNumber((ask("GetSendMailMoney")))
    if not money or money <= 0 then return nil, false end
    return money
  end },
  { "SendMail", "postage", function() return (ask("GetSendMailPrice")) end },
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

-- Every hook guarded: a function this client lacks is skipped, and a throw in
-- one is an ERR line named after it.
function WJ.installMoneyHooks()
  for _, signal in ipairs(MONEY_HOOKS) do
    local owner, name = resolve(signal[1])
    if type(owner) == "table" and type(owner[name]) == "function" then
      local fn = WJ.guard(signal[1], function(...) fromHook(signal, ...) end)
      if owner == _G then hooksecurefunc(name, fn) else hooksecurefunc(owner, name, fn) end
    end
  end
end

-- The money handlers join whatever else listens to the same event, each
-- guarded on its own so a fault in one never silences the other.
local function joinMoneyEvents()
  for event, fn in pairs(moneyEvents) do
    local first = handlers[event]
    if first then
      local a, b = WJ.guard(event, first), WJ.guard(event, fn)
      handlers[event] = function(...) a(...) b(...) end
    else
      handlers[event] = fn
    end
  end
  moneyEvents = {}
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

-- A client without an event (WoW Forever has no pet battles, for one) throws on
-- registering it. That family is simply not recorded; /widsith check lists them.
function WJ.registerEvents(frame)
  joinMoneyEvents()
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

-- Called at session start, once the player and quest log exist. Seeds the
-- caches so pre-existing state never emits a change line.
function WJ.seedState()
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

-- A session resumed after a pause opens the way a reload does: the
-- seeded state, the instance the character is in, where it is, and (Extras)
-- the character sheet. Whatever changed during the pause is only ever seen
-- as the difference between the last session's lines and these.
function WJ.onResume()
  currentInstanceMapID = 0
  lastZone, lastSubzone = nil, nil
  WJ.resetPositionForSession()
  if WJ.resetExtrasForSession then WJ.resetExtrasForSession() end
  if WJ.resetMomentsForSession then WJ.resetMomentsForSession() end
  WJ.onEnteringWorld(false, true)
  writeZoneIfChanged()
end
