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
-- Name-Realm (character names are public in WoW). GROUP_ROSTER_UPDATE
-- fires often, so a line is written only when the picture changed; the
-- opening state is seeded at session start.
---------------------------------------------------------------------------

local lastGroup

local function groupLine()
  local size = GetNumGroupMembers() or 0
  local kind = IsInRaid() and "raid" or (IsInGroup() and "party" or "none")
  local members = {}
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
      end
    end
  end
  return size, kind, table.concat(members, ",")
end

local function writeGroupIfChanged()
  local size, kind, classes = groupLine()
  local key = size .. kind .. classes
  if key == lastGroup then return end
  lastGroup = key
  write("GROUP", size, kind, classes)
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

handlers.PLAYER_MONEY = function()
  write("MONEY", GetMoney())
end

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
-- objective. Sub-millisecond even with a full log (0.1–0.3 ms measured).
local function diffQuestLog(silent)
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
      end
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
    if not seen[questID] then objectives[questID] = nil end
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

handlers.QUEST_ACCEPTED = function(questID)
  local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
  write("QACCEPT", questID, giverGUID(), title)
  counts.quests = counts.quests + 1
  objectives[questID] = readObjectives(questID)
end

handlers.QUEST_TURNED_IN = function(questID, xpReward, moneyReward)
  write("QTURNIN", questID, xpReward, moneyReward, giverGUID())
  counts.quests = counts.quests + 1
  objectives[questID] = nil
end

handlers.QUEST_REMOVED = function(questID)
  write("QREMOVE", questID)
  objectives[questID] = nil
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

-- The format strings this client lacks, for /widsith check.
function WJ.missingLootFormatNames()
  if not lootPatterns then buildLootPatterns() end
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
