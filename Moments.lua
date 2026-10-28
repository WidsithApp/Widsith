-- Widsith — Moments
--
-- What happens to the character between the lines the other files write:
-- what a fight cost once it is over, what ended a life, buffs coming and
-- going, control lost, breath running out, a place discovered, the game's own counters
-- ticking over, and what nearby creatures say.
--
-- Two rules shape this file. Each line is something the game itself reported
-- at that moment; nothing here is worked out from other readings. And a fight
-- is written as one summary when it ends, never blow by blow: a replay plays
-- hours in minutes, where a fight is a blink, and while the character is in
-- combat the game hides these numbers from addons anyway (12.0's secret
-- values), releasing them once combat ends.
--
-- Checked on WoW Forever 1.60.1. Every API here is looked up before use, so a
-- client without one simply writes nothing for that family.

local _, WJ = ...

local write, field, handlers = WJ.write, WJ.field, WJ.handlers
local issecretvalue = issecretvalue

local function secret(v)
  return issecretvalue ~= nil and issecretvalue(v)
end

-- The value, or nil when the game hid it: for anything compared or used as a key.
local function plain(v)
  if secret(v) then return nil end
  return v
end

-- A table that may be read, or nil.
local function readable(v)
  if secret(v) or type(v) ~= "table" then return nil end
  return v
end

-- A name inside a comma list: the list's own separators can't appear in it.
local function listLabel(v)
  return (field(v):gsub("[,:]", " "))
end

---------------------------------------------------------------------------
-- FIGHT: one line per fight, from the game's built-in damage meter.
--
-- C_DamageMeter (DamageMeterDocumentation.lua) keeps a session for every
-- fight whether or not its window is shown: how long it lasted, what each
-- combatant dealt, took and healed, spell by spell. During the fight every
-- amount in it is secret; the game releases them as combat ends. So the line
-- is written at that instant, for the fight that has just ended, which also
-- gives a fight followed at once by another its own line.
--
-- If anything the line needs is still hidden or not there yet at that
-- instant, the meter is read again a second later, as long as no new fight
-- has begun by then (its numbers would be hidden again, and the newest
-- session would no longer be the one that ended).
--
-- The meter carries one session on through a short lull: a fight that begins
-- within a moment of the last one ending is, to the meter, the same session,
-- its duration and totals growing. Such a session is written again at the end
-- of each span of combat it grew through, so the last line for a meter ID is
-- the whole fight and the earlier ones are its stages; the same reading is
-- never written twice.
--
-- Only this character's own entry is read, plus the fight's totals and the
-- creatures fought. Other players' entries are left alone.
---------------------------------------------------------------------------

local FIGHT_SETTLE = 1   -- s after combat ends before the meter is read again, if it wasn't whole at once

local meterTypes = Enum and Enum.DamageMeterType or {}
local DONE    = meterTypes.DamageDone or 0
local TAKEN   = meterTypes.DamageTaken or 7
local HEALED  = meterTypes.HealingDone or 2
local ENEMIES = meterTypes.EnemyDamageTaken or 10

-- The last line written: the meter's session ID and the duration it reported then.
local lastFight

local function haveMeter()
  return C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions and C_DamageMeter.GetCombatSessionFromID
    and C_DamageMeter.GetCombatSessionSourceFromID
end

-- The meter's ID for its newest session.
local function newestFight()
  local sessions = readable(C_DamageMeter.GetAvailableCombatSessions())
  local newest = sessions and readable(sessions[#sessions])
  return newest and plain(newest.sessionID)
end

-- This character's entry among a session's combatants, and whether the game
-- hid any entry it had to look at to find it.
local function ownEntry(session)
  if not session then return nil, false end
  local sources = session.combatSources
  if secret(sources) then return nil, true end
  if type(sources) ~= "table" then return nil, false end
  local hidden = false
  for i = 1, #sources do
    local source = sources[i]
    if secret(source) then
      hidden = true
    elseif type(source) == "table" then
      local isMe = source.isLocalPlayer
      if secret(isMe) then
        hidden = true
      elseif isMe == true then
        return source, false
      end
    end
  end
  return nil, hidden
end

-- "id:amount,id:amount" from a list of the meter's entries, and whether the
-- game hid any part of it.
local function amounts(entries, idKey)
  local out, hidden = {}, false
  for i = 1, #entries do
    local entry = entries[i]
    if secret(entry) then
      hidden = true
      out[i] = ":"
    elseif type(entry) == "table" then
      local id, amount = entry[idKey], entry.totalAmount
      if secret(id) or secret(amount) then hidden = true end
      out[i] = field(id) .. ":" .. field(amount)
    else
      out[i] = ":"
    end
  end
  return table.concat(out, ","), hidden
end

-- The spells behind one of this character's totals, and whether the game hid
-- any of them. The meter answers by the combatant's GUID, which it refuses
-- from an addon while that GUID is secret.
local function spellAmounts(fightID, meterType, entry)
  if not entry then return nil, false end
  if secret(entry.sourceGUID) then return nil, true end
  local detail = C_DamageMeter.GetCombatSessionSourceFromID(fightID, meterType, entry.sourceGUID)
  if secret(detail) then return nil, true end
  local spells = type(detail) == "table" and detail.combatSpells or nil
  if secret(spells) then return nil, true end
  if type(spells) ~= "table" then return nil, false end
  return amounts(spells, "spellID")
end

-- The FIGHT line's fields for one of the meter's sessions, and whether the
-- line is whole: nothing in it hidden, and both this character's own damage
-- and the creatures fought already there.
local function readFight(id)
  local hidden = false
  local function note(isHidden) if isHidden then hidden = true end end
  local function open(v)
    if secret(v) then hidden = true return nil end
    if type(v) == "table" then return v end
  end
  local function value(v)
    if secret(v) then hidden = true end
    return v
  end

  local session = C_DamageMeter.GetCombatSessionFromID
  local done, taken = open(session(id, DONE)), open(session(id, TAKEN))
  local healed, enemies = open(session(id, HEALED)), open(session(id, ENEMIES))
  local dealt, dealtHidden = ownEntry(done)
  local hurt, hurtHidden = ownEntry(taken)
  local mended, mendedHidden = ownEntry(healed)
  note(dealtHidden) note(hurtHidden) note(mendedHidden)

  -- A creature is named; an opponent who is a player (a duel, PvP) is not: their
  -- entry has no creature ID, and stays an amount with no name.
  local foes = enemies and open(enemies.combatSources)
  local names, foeAmounts = {}, nil
  if foes then
    for i = 1, #foes do
      local foe = open(foes[i])
      local creature = foe and value(foe.sourceCreatureID)
      local isCreature = not secret(creature) and type(creature) == "number"
      names[i] = isCreature and listLabel(value(foe.name)) or ""
    end
    local foesHidden
    foeAmounts, foesHidden = amounts(foes, "sourceCreatureID")
    note(foesHidden)
  end
  local doneSpells, doneHidden = spellAmounts(id, DONE, dealt)
  local takenSpells, takenHidden = spellAmounts(id, TAKEN, hurt)
  note(doneHidden) note(takenHidden)

  local fields = { id, done and value(done.durationSeconds), dealt and value(dealt.totalAmount),
    hurt and value(hurt.totalAmount), mended and value(mended.totalAmount), done and value(done.totalAmount),
    doneSpells, takenSpells, foeAmounts, table.concat(names, ",") }
  local whole = not hidden and dealt ~= nil and foes ~= nil and #foes > 0
  return fields, whole
end

-- The newest session's line, if this reading of it hasn't been written: a new
-- session, or one already written whose duration has grown since. atOnce:
-- only a whole line; a second later, whatever the meter will show.
local function writeFight(atOnce)
  local id = newestFight()
  if id == nil then return end
  local f, whole = readFight(id)
  if atOnce and not whole then return end
  local duration = f[2]
  if secret(duration) or type(duration) ~= "number" then duration = nil end
  local totals = field(f[3]) .. "/" .. field(f[4]) .. "/" .. field(f[6])
  if lastFight and lastFight.id == id then
    -- Written before: again only if it has grown. The meter's clock alone
    -- runs on for a moment after combat, so a second later the duration must
    -- not be the whole of the difference: the totals have to have moved too.
    if duration == nil or lastFight.duration == nil or duration <= lastFight.duration then return end
    if not atOnce and totals == lastFight.totals then return end
  end
  lastFight = { id = id, duration = duration, totals = totals }
  write("FIGHT", f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8], f[9], f[10])
  return true
end

-- Whether the fight that just ended still needs its line: the read at the
-- instant didn't write one. The meter's clock runs on for a moment after
-- combat ends, so a line written at the instant must not be written again a
-- second later with a duration one second longer.
local settleNeeded = false

-- A second after combat ends, if no new fight has begun: the fight's line if
-- it couldn't be written at once, and what the fight did to auras and counters.
local function afterFight()
  if InCombatLockdown() then return end
  if haveMeter() and settleNeeded then writeFight(false) end
  settleNeeded = false
  if WJ.syncAuras then WJ.syncAuras() end
  if WJ.readTallies then WJ.readTallies(false) end
end

-- Called when the game's combat flag drops (Events.lua). The read at that
-- instant is an attempt: if the meter isn't ready, or the call fails, the
-- read a second later writes the line (and names any fault that persists).
function WJ.onCombatEnd()
  local ok, written = false, false
  if haveMeter() then ok, written = pcall(writeFight, true) end
  settleNeeded = not (ok and written)
  C_Timer.After(FIGHT_SETTLE, WJ.guard("afterFight", afterFight))
end

---------------------------------------------------------------------------
-- RECAP: the hits that ended a life, as the game's own death recap lists
-- them (C_DeathRecap, what the "Recap" button on the release dialog shows):
-- newest first, each with what it was, how much, the overkill, and the health
-- the character had before it. One line per hit, written with the DEATH.
--
-- The recap is announced in the system channel as a link, "[You died.]",
-- carrying its ID, just before PLAYER_DEAD. That ID asks for exactly this
-- death's recap. Without it the latest recap is taken only if its newest hit
-- is from the last few seconds: the recap of an earlier death stays around.
---------------------------------------------------------------------------

local RECAP_LINK_WINDOW = 5    -- s between the chat link and PLAYER_DEAD
local RECAP_FRESH       = 15   -- s; a latest recap older than this is another death's

local recapID, recapClock

local function noteRecapLink(message)
  local id = tonumber(message:match("|Hdeath:(%d+)|h"))
  if id then recapID, recapClock = id, GetTime() end
end

-- Called when a real death (not Feign Death) has been written (Events.lua).
function WJ.onDeath()
  if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return end
  local id
  if recapID and GetTime() - recapClock <= RECAP_LINK_WINDOW then id = recapID end
  recapID = nil

  local hits = readable(C_DeathRecap.GetRecapEvents(id))
  if not hits or #hits == 0 then return end
  if not id then
    local newest = readable(hits[1])
    local when = newest and plain(newest.timestamp)
    if type(when) ~= "number" or math.abs(GetServerTime() - when) > RECAP_FRESH then return end
  end

  local maxHealth = C_DeathRecap.GetRecapMaxHealth and C_DeathRecap.GetRecapMaxHealth(id) or nil
  for i = 1, #hits do
    local hit = readable(hits[i])
    if hit then
      write("RECAP", i, #hits, maxHealth, hit.event, hit.spellId, hit.school, hit.amount, hit.overkill,
        hit.currentHP, hit.timestamp, hit.sourceGUID, hit.environmentalType, hit.spellName)
    end
  end
end

---------------------------------------------------------------------------
-- AURA: a buff or debuff arriving on the character, and leaving it.
--
-- UNIT_AURA says which auras were added and which instances were removed.
-- Under combat restrictions both lists are secret, so `gain` and `lose`
-- cover the time outside fights: food and drink, buffs from other players,
-- the ghost form, what is cast before a pull.
--
-- What a fight did to the set is read when it is over, as a comparison with
-- what was known: `has` for an aura found on the character that was never
-- announced (the poison a creature left), `gone` for one no longer there.
-- Both say what is true as they are written, not when it began or ended.
-- The same comparison is made when a session opens and whenever the game
-- resends the whole set (after a death, a loading screen), which also gives
-- every aura a new instance number.
--
-- Addon code may not look at an aura the game hides. While combat,
-- encounter, challenge-mode or PvP-match restrictions are on, every aura is
-- hidden, and a few spells are hidden always. Asked for one then, the game
-- doesn't hand back a hidden value: the call raises an error ("Auras cannot
-- be accessed when secret while tainted"; the RequiresUnitAuraAccess
-- precondition in UnitAuraDocumentation.lua). So every read below first asks
-- C_Secrets whether the answer would be hidden, then goes through auraCall,
-- which makes the call inside pcall in case it is refused anyway. A
-- refused read is the game's rule, not a fault: that pass writes nothing and
-- reports nothing. A session that opens in combat therefore has no opening
-- `has` lines; they come with the comparison a second after the fight ends,
-- where everything on the character is new to the session.
---------------------------------------------------------------------------

local AURA_FILTERS = { "HELPFUL", "HARMFUL" }

local auraSpell = {}   -- aura instance -> spell ID, to name an aura when it ends

-- What C_Secrets says, or nil when the client lacks the question or it fails.
local function askSecrets(name, ...)
  local ask = C_Secrets and C_Secrets[name]
  if type(ask) ~= "function" then return nil end
  local ok, answer = pcall(ask, ...)
  if ok then return plain(answer) end
end

-- Whether the game is hiding auras from addons right now. A client without
-- C_Secrets.ShouldAurasBeSecret is taken to hide them in combat.
local function aurasHidden()
  local hidden = askSecrets("ShouldAurasBeSecret")
  if hidden == nil then return InCombatLockdown() and true or false end
  return hidden == true
end

-- One C_UnitAuras call that can never raise. Returns its first answer, or
-- nil and true when the game refused it.
local function auraCall(name, ...)
  local call = C_UnitAuras and C_UnitAuras[name]
  if type(call) ~= "function" then return nil, false end
  local ok, answer = pcall(call, ...)
  if not ok then return nil, true end
  return answer, false
end

-- Who cast it, as far as that is ours to say: nothing for the character's
-- own, a creature's or pet's GUID in full, and for another player only that
-- it was a player.
local function auraCaster(aura, own)
  if own then return nil end
  local instance = plain(aura.auraInstanceID)
  if instance == nil or aurasHidden() then return nil end
  if askSecrets("ShouldUnitAuraInstanceBeSecret", "player", instance) == true then return nil end
  local guid = plain((auraCall("GetAuraCasterGUID", "player", instance)))
  if type(guid) ~= "string" then return nil end
  if guid:find("^Player%-") then return "Player" end
  return guid
end

-- how: "gain" for one the game has just announced, "has" for one found already there.
local function writeAura(how, aura)
  local source = plain(aura.sourceUnit)
  local own
  if source ~= nil then own = source == "player" end
  write("AURA", how, aura.spellId, aura.isHelpful, aura.duration, aura.applications, own,
    aura.name, auraCaster(aura, own))
end

-- Every aura on the character the game lets addons see, or nil while it
-- hides them (or refuses partway, when nothing from that pass is used). An
-- aura whose spell is always hidden is left out and the rest are read.
local function aurasPresent()
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) or aurasHidden() then return nil end
  local list = {}
  for _, filter in ipairs(AURA_FILTERS) do
    for i = 1, 255 do
      if askSecrets("ShouldUnitAuraIndexBeSecret", "player", i, filter) ~= true then
        local aura, refused = auraCall("GetAuraDataByIndex", "player", i, filter)
        if refused or secret(aura) then return nil end
        if type(aura) ~= "table" then break end
        list[#list + 1] = aura
      end
    end
  end
  return list
end

-- Compare what is on the character with what was known, by spell: instance
-- numbers don't survive a resend.
local function syncAuras()
  local list = aurasPresent()
  if not list then return end
  local before = {}
  for _, spell in pairs(auraSpell) do before[spell] = true end
  local now, fresh = {}, {}
  for i = 1, #list do
    local aura = list[i]
    local instance, spell = plain(aura.auraInstanceID), plain(aura.spellId)
    if instance ~= nil and spell ~= nil then
      fresh[instance] = spell
      if not before[spell] and not now[spell] then writeAura("has", aura) end
      now[spell] = true
    end
  end
  for spell in pairs(before) do
    if not now[spell] then write("AURA", "gone", spell) end
  end
  auraSpell = fresh
end
WJ.syncAuras = syncAuras

handlers.UNIT_AURA = function(_, info)
  info = readable(info)
  if not info then return end
  if plain(info.isFullUpdate) == true then
    syncAuras()
    return
  end
  local added = readable(info.addedAuras)
  if added then
    for i = 1, #added do
      local aura = readable(added[i])
      local instance, spell = aura and plain(aura.auraInstanceID), aura and plain(aura.spellId)
      if instance ~= nil and spell ~= nil then
        auraSpell[instance] = spell
        writeAura("gain", aura)
      end
    end
  end
  local removed = readable(info.removedAuraInstanceIDs)
  if removed then
    for i = 1, #removed do
      local instance = plain(removed[i])
      local spell = instance ~= nil and auraSpell[instance]
      if spell then
        auraSpell[instance] = nil
        write("AURA", "lose", spell)
      end
    end
  end
end
WJ.unitEvents.UNIT_AURA = "player"

---------------------------------------------------------------------------
-- CC: the character losing control: stunned, rooted, feared, silenced. What
-- the game's own loss-of-control alert shows, which it doesn't hide for one's
-- own character even in combat: the kind, the spell, and how long it lasts.
-- The event fires for other units in sight as well; only the player's is kept.
---------------------------------------------------------------------------

handlers.LOSS_OF_CONTROL_ADDED = function(unit, index)
  if plain(unit) ~= "player" then return end
  local get = C_LossOfControl and C_LossOfControl.GetActiveLossOfControlData
  local data = get and readable(get(index))
  if not data then return end
  write("CC", data.locType, data.spellID, data.duration, data.lockoutSchool, data.displayText)
end

---------------------------------------------------------------------------
-- MIRROR: the timer bars under the portrait: breath underwater, fatigue in
-- deep water. The game starts the bar when it begins to drain, starts it
-- again with a positive rate when it begins to refill, and stops it when it
-- is full. On death it sends a stop for every kind of bar whether one was
-- showing or not, so a stop is written only for a bar that was started.
---------------------------------------------------------------------------

local barsRunning = {}

handlers.MIRROR_TIMER_START = function(name, value, maxValue, rate)
  local bar = plain(name)
  if type(bar) ~= "string" then return end
  barsRunning[bar] = true
  write("MIRROR", "start", bar, value, maxValue, rate)
end

handlers.MIRROR_TIMER_STOP = function(name)
  local bar = plain(name)
  if type(bar) ~= "string" or not barsRunning[bar] then return end
  barsRunning[bar] = nil
  write("MIRROR", "stop", bar)
end

---------------------------------------------------------------------------
-- DISCOVER: uncovering a new area of the map. The game says so twice: in the
-- system channel with the experience gained ("Discovered Crystal Lake: 65
-- experience gained") and on screen ("Discovered: Crystal Lake"). Both are
-- matched with the client's own format strings, so any language works. The
-- game gives no ID for the area found (the exploration API answers with the
-- area the character stands in, which need not be the one uncovered), so the
-- name is all there is.
---------------------------------------------------------------------------

local DISCOVER_REPEAT = 5   -- s; the two announcements of one discovery arrive together

local discoverPatterns
local lastDiscovery, lastDiscoveryClock

local function discovery(message)
  if not discoverPatterns then
    discoverPatterns = {}
    for _, name in ipairs({ "ERR_ZONE_EXPLORED_XP", "ERR_ZONE_EXPLORED" }) do
      local fmt = _G[name]
      if type(fmt) == "string" then discoverPatterns[#discoverPatterns + 1] = WJ.patternFromFormat(fmt) .. "$" end
    end
  end
  for _, pattern in ipairs(discoverPatterns) do
    local name, xp = message:match(pattern)
    if name and name ~= "" then return name, tonumber(xp) end
  end
end

local function noteDiscovery(message)
  local name, xp = discovery(message)
  if not name then return end
  local now = GetTime()
  if name == lastDiscovery and now - lastDiscoveryClock < DISCOVER_REPEAT then return end
  lastDiscovery, lastDiscoveryClock = name, now
  write("DISCOVER", xp, name)
end

handlers.CHAT_MSG_SYSTEM = function(message)
  message = plain(message)
  if type(message) ~= "string" then return end
  noteRecapLink(message)
  noteDiscovery(message)
end

-- The on-screen announcement (UI_INFO_MESSAGE, handled in Extras.lua).
function WJ.onInfoMessage(message)
  if type(message) == "string" then noteDiscovery(message) end
end

---------------------------------------------------------------------------
-- TALLY: the game's own counters, the ones the Statistics pane shows:
-- creatures and critters killed, food eaten, deaths by cause, flight paths
-- taken, duels won. A session opens with every counter that has a value;
-- after that a line is written when one changes, which the game does within
-- a second or two of the act (CRITERIA_UPDATE says that something moved, but
-- not what). A counter's name rides along the first time it is written.
--
-- Counters of money are left out: the game hands them over as formatted text
-- with coin icons, and MONEY already records every change exactly.
--
-- Two ways to read a counter, far apart in cost. By category and index, the
-- way StatisticsFrame.lua lists the pane, GetStatistic takes about 0.7 ms a
-- counter on Retail 12.1.5, and the pane there has over two thousand (WoW
-- Forever has two hundred): read in one frame they freeze the game for a
-- second and a half. By its ID, GetStatistic(id) answers the same in about
-- 0.002 ms. So the first pass of a load walks the pane by index to learn the
-- IDs, spread across frames at a few milliseconds each, and every pass after
-- it reads all the counters by ID, which takes a few milliseconds in all.
---------------------------------------------------------------------------

local TALLY_SETTLE = 2       -- s after the game reports progress before counters are read
local TALLY_BUDGET = 3       -- ms of a frame spent reading counters
local NO_VALUE = "--"        -- what the game returns for a counter that has never moved

local tallies, tallyNamed = {}, {}
local statIDs = {}           -- every counter's ID, in the pane's order, from the first pass
local talliesOpened = false  -- the first pass has finished: the IDs are known
local byIDWorks = true       -- GetStatistic(id) answers for the ID asked; else passes stay by index
local tallyQueued = false
local pass                   -- the pass under way, or nil
local passWanted = false     -- a pass was asked for while one ran
local walker = CreateFrame("Frame")
local onFrame                -- the walker's OnUpdate, below

local function haveTallies()
  return GetStatisticsCategoryList and GetCategoryNumAchievements and GetStatistic
end

-- The client's millisecond clock, or a clock that never moves on a client
-- without one (then a pass finishes in one frame).
local function clockMs()
  local t = debugprofilestop and debugprofilestop()
  if type(t) ~= "number" then return 0 end
  return t
end

-- One counter's reading: its line when the value differs from the last one read.
local function noteCounter(id, value)
  value, id = plain(value), plain(id)
  if type(value) == "number" then value = field(value) end
  if type(id) ~= "number" or type(value) ~= "string" or value:find("|", 1, true) then return id end
  local before = tallies[id] or NO_VALUE
  tallies[id] = value
  if value == before then return id end
  local label
  if not tallyNamed[id] then
    tallyNamed[id] = true
    if GetAchievementInfo then label = select(2, GetAchievementInfo(id)) end
  end
  write("TALLY", id, value, label)
  return id
end

-- The pass's next counter read; false when none is left. The first pass walks
-- the pane by index and remembers each ID; a pass by ID reads the IDs it learnt.
local function readNext()
  if pass.byID then
    if pass.index >= #statIDs then return false end
    pass.index = pass.index + 1
    local id = statIDs[pass.index]
    local value, _, answered = GetStatistic(id)
    if plain(answered) ~= id then
      -- A client whose GetStatistic(id) doesn't answer for the ID: stay by index from here.
      byIDWorks = false
      return false
    end
    noteCounter(id, value)
    return true
  end
  while true do
    if pass.category > #pass.categories then return false end
    if pass.index < pass.count then
      pass.index = pass.index + 1
      local value, _, id = GetStatistic(pass.categories[pass.category], pass.index)
      id = noteCounter(id, value)
      if type(id) == "number" then pass.ids[#pass.ids + 1] = id end
      return true
    end
    pass.category = pass.category + 1
    pass.index = 0
    local category = plain(pass.categories[pass.category])
    local count = category ~= nil and plain(GetCategoryNumAchievements(category)) or nil
    pass.count = type(count) == "number" and count or 0
  end
end

local function startPass()
  if talliesOpened and byIDWorks then
    pass = { byID = true, index = 0 }
  else
    local categories = readable(GetStatisticsCategoryList())
    if not categories then return end
    pass = { byID = false, categories = categories, category = 0, index = 0, count = 0, ids = {} }
  end
  walker:SetScript("OnUpdate", onFrame)
end

local function stopPass()
  pass = nil
  walker:SetScript("OnUpdate", nil)
end

local function finishPass()
  if not pass.byID then
    statIDs = pass.ids
    talliesOpened = true
  end
  stopPass()
  if passWanted then
    passWanted = false
    startPass()
  end
end

-- A few milliseconds of counters, then the frame goes on.
local function step()
  local deadline = clockMs() + TALLY_BUDGET
  repeat
    if not readNext() then
      finishPass()
      return
    end
  until clockMs() > deadline
end

onFrame = function()
  if not pass then
    stopPass()
    return
  end
  local ok, err = pcall(step)
  if not ok then
    stopPass()
    passWanted = false
    WJ.recordError("tallies", err)
  end
end

-- opening: the request that may start the first pass. Any other request waits
-- until that pass has finished, then reads every counter by ID. A pass asked
-- for while one runs follows it, once, however many ask.
local function readTallies(opening)
  if not haveTallies() then return end
  if not opening and not talliesOpened then return end
  if pass then
    passWanted = true
    return
  end
  startPass()
end
WJ.readTallies = readTallies

handlers.CRITERIA_UPDATE = function()
  if tallyQueued or not talliesOpened then return end
  tallyQueued = true
  C_Timer.After(TALLY_SETTLE, WJ.guard("tallies", function()
    tallyQueued = false
    readTallies(false)
  end))
end

---------------------------------------------------------------------------
-- NPCSAY: what creatures and NPCs say, yell and emote nearby. A line a
-- speaker repeats is written once a minute at most, and no more than twenty
-- lines a minute in all, so a busy street can't fill the recording. Players'
-- chat is never read here: these events carry only the game's own characters.
---------------------------------------------------------------------------

local NPC_REPEAT     = 60   -- s before the same speaker's same line is written again
local NPC_PER_MINUTE = 20
local NPC_REMEMBERED = 200  -- lines remembered for NPC_REPEAT before the memory is cleared

local npcSaid, npcSaidCount = {}, 0
local npcMinute, npcThisMinute = 0, 0

local function npcSpeech(kind)
  return function(text, speaker)
    text, speaker = plain(text), plain(speaker)
    if type(text) ~= "string" or text == "" then return end
    if type(speaker) ~= "string" then speaker = "" end
    local now = GetTime()
    local key = speaker .. "\t" .. text
    if npcSaid[key] and now - npcSaid[key] < NPC_REPEAT then return end
    if now - npcMinute >= 60 then npcMinute, npcThisMinute = now, 0 end
    if npcThisMinute >= NPC_PER_MINUTE then return end
    npcThisMinute = npcThisMinute + 1
    if not npcSaid[key] then
      if npcSaidCount >= NPC_REMEMBERED then npcSaid, npcSaidCount = {}, 0 end
      npcSaidCount = npcSaidCount + 1
    end
    npcSaid[key] = now
    write("NPCSAY", kind, speaker, text)
  end
end

handlers.CHAT_MSG_MONSTER_SAY     = npcSpeech("say")
handlers.CHAT_MSG_MONSTER_YELL    = npcSpeech("yell")
handlers.CHAT_MSG_MONSTER_EMOTE   = npcSpeech("emote")
handlers.CHAT_MSG_MONSTER_WHISPER = npcSpeech("whisper")
handlers.CHAT_MSG_MONSTER_PARTY   = npcSpeech("party")
handlers.CHAT_MSG_RAID_BOSS_EMOTE = npcSpeech("boss")

---------------------------------------------------------------------------
-- RULES: the rules this character plays under, which never change during a
-- session: hardcore, self-found, and the interface preset chosen at the
-- character screen (WoW Forever: 0 Classic, 1 Modern).
---------------------------------------------------------------------------

local function answer(owner, name)
  local fn = owner and owner[name]
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn)
  if ok then return value end
end

local function writeRules()
  local hardcore = answer(C_GameRules, "IsHardcoreActive")
  local selfFound = answer(C_PlayerInfo, "IsSelfFoundActive")
  local preset = answer(C_GameRules, "GetForeverExperiencePreset")
  if hardcore == nil and selfFound == nil and preset == nil then return end
  write("RULES", hardcore, selfFound, preset)
end

---------------------------------------------------------------------------
-- Session start and resume
---------------------------------------------------------------------------

-- At session start: the meter's newest fight is from before this session, and
-- must never be written as one that just ended.
function WJ.seedMoments()
  lastFightID = nil
  if haveMeter() then
    local ok, id = pcall(newestFight)
    if ok then lastFightID = id end
  end
end

-- With the opening snapshot, once the client has loaded the character. The
-- counters are not here: the snapshot itself starts their first pass.
function WJ.writeOpeningMoments()
  writeRules()
  syncAuras()
end

-- A session resumed after a pause starts from nothing known.
function WJ.resetMomentsForSession()
  auraSpell = {}
  barsRunning = {}
  tallies, tallyNamed, talliesOpened = {}, {}, false
  statIDs, byIDWorks = {}, true
  stopPass()
  passWanted = false
  npcSaid, npcSaidCount = {}, 0
  recapID = nil
  lastDiscovery = nil
end
