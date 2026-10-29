-- Widsith — Extras
--
-- Everything beyond the core journey: travel spells and mounts, reputation,
-- skills and professions, achievements, gear and the character sheet,
-- currency, encounters, spec and hearth, gear sets and talents, the guild, trading with NPCs and
-- players, pet battles, and the small things (jumps, screenshots, emotes).
-- Speech is here too, switched off. Every line here is a fact the game
-- stated; where a fact is inferred from a consequence (SPELL) the line says
-- so in a field.

local _, WJ = ...

local write, counts = WJ.write, WJ.counts
local handlers = WJ.handlers
local issecretvalue = issecretvalue

-- The game's Lua has unpack as a global; newer Lua keeps it in table.
local unpack = unpack or table.unpack

local function secret(v)
  return issecretvalue ~= nil and issecretvalue(v)
end

-- A number that may be compared or added: present and not secret.
local function usable(v)
  return type(v) == "number" and not secret(v)
end

---------------------------------------------------------------------------
-- Casts: MOUNT at cast time, SPELL when a cast is followed by a relocation.
--
-- UNIT_SPELLCAST_SUCCEEDED fires for every ability, so casts are only kept
-- in memory (the last few). A mount is known at cast time from the mount
-- journal — no list to maintain. A travel spell is known only by what
-- follows: a loading screen, or two samples further apart than anything can
-- travel (Position.lua). Then the most recent cast that finished within
-- CAST_SLACK seconds before the move began is written as SPELL with the time
-- it was cast and the reason it was singled out.
--
-- The window is measured from the start of the move, not from when it was
-- noticed. A loading screen is dated by LOADING_SCREEN_ENABLED (it can stay up
-- 30 s or more, and a window measured from PLAYER_ENTERING_WORLD would have to
-- be long enough to catch a mount summoned on the way to an instance door). A
-- jump is dated by the previous sample, which saw the character still in place.
--
-- The line also carries the time the cast *began*. UNIT_SPELLCAST_START and
-- UNIT_SPELLCAST_CHANNEL_START carry the same castGUID as the SUCCEEDED
-- that ends the cast, so a hearthstone's ten seconds of casting are known,
-- not guessed. Instant casts have no start; the field stays empty.
---------------------------------------------------------------------------

local casts = {}
local CAST_KEEP = 8
-- A teleport is the cast's own effect: the server moves the character as the
-- cast finishes, so the loading screen (or the far sample) follows within a
-- round trip — well under a second. 3 s allows for a bad lag spike; anything
-- older is a cast that merely happened before the player walked somewhere.
local CAST_SLACK = 3

-- castGUID -> session ms when that cast began; only the last few are kept.
local starts, startOrder = {}, {}

local function castStarted(unit, castGUID)
  if unit ~= "player" or castGUID == nil or secret(castGUID) then return end
  starts[castGUID] = WJ.nowMs()
  startOrder[#startOrder + 1] = castGUID
  if #startOrder > CAST_KEEP then starts[table.remove(startOrder, 1)] = nil end
end
handlers.UNIT_SPELLCAST_START = castStarted
handlers.UNIT_SPELLCAST_CHANNEL_START = castStarted

handlers.UNIT_SPELLCAST_SUCCEEDED = function(unit, castGUID, spellID)
  if unit ~= "player" or spellID == nil or secret(spellID) then return end
  local mountID = C_MountJournal and C_MountJournal.GetMountFromSpell and C_MountJournal.GetMountFromSpell(spellID)
  if mountID then
    -- A mount is summoned, not travelled by: never a candidate for SPELL (a
    -- mount called at an instance door would otherwise be named for the load).
    write("MOUNT", spellID, mountID)
    return
  end
  local startT
  if castGUID ~= nil and not secret(castGUID) then startT = starts[castGUID] end
  casts[#casts + 1] = { spellID = spellID, clock = GetTime(), t = WJ.nowMs(), startT = startT }
  if #casts > CAST_KEEP then table.remove(casts, 1) end
end

-- When the last loading screen appeared (GetTime()); consumed by the next
-- "load" relocation. LOADING_SCREEN_ENABLED and LOADING_SCREEN_DISABLED have
-- no payload (Blizzard's LoadingScreenDocumentation.lua). Position.lua is told
-- too: it writes no periodic lines while a loading screen is up.
local loadingClock
handlers.LOADING_SCREEN_ENABLED = function()
  loadingClock = GetTime()
  WJ.onLoadingScreen(true)
end

handlers.LOADING_SCREEN_DISABLED = function()
  WJ.onLoadingScreen(false)
end

-- reason "load": at a PLAYER_ENTERING_WORLD that isn't login or reload.
-- reason "jump": `distance` yards between samples; `since` = the previous sample's GetTime().
function WJ.onRelocation(reason, distance, since)
  local from, to
  if reason == "load" then
    -- No loading screen seen (a PLAYER_ENTERING_WORLD without one): nothing to
    -- date the move by, so nothing is named rather than something guessed.
    to, loadingClock = loadingClock, nil
    from = to and to - CAST_SLACK
  else
    to = GetTime()
    from = (since or to) - CAST_SLACK
  end
  if from then
    -- The cast behind a move is the one that finished just before it. A load is
    -- dated by its loading screen, so that is the latest cast in the window. A
    -- jump is only noticed at the next tick, up to a second after it, so a cast
    -- made on arrival (Sprint, travel form) can fall in the window too: there it
    -- is the earliest, since nothing else finishes while a teleport is cast.
    local pick
    for i = #casts, 1, -1 do
      local c = casts[i]
      if c.clock < from then break end
      if c.clock <= to then
        pick = c
        if reason == "load" then break end
      end
    end
    if pick then
      write("SPELL", pick.spellID, pick.t, reason, distance and string.format("%.0f", distance), pick.startT)
    end
  end
  wipe(casts)
end

---------------------------------------------------------------------------
-- Reputation: REP factionID reaction standing delta label.
--
-- Changes: the reputation list hides collapsed headers from index iteration,
-- so a diff over it misses factions. The game announces every change in chat
-- with the faction's name and the amount; the name resolves to an ID through
-- a one-time scan of GetFactionDataByID, and the standing is read from the
-- same call. Unknown name: empty ID, the label stands.
--
-- State: every faction the Reputation pane lists, with the opening snapshot
-- (writeReputations, below), the delta empty.
---------------------------------------------------------------------------

local FACTION_FORMATS = {
  { "FACTION_STANDING_INCREASED",              1 },
  { "FACTION_STANDING_INCREASED_ACH_BONUS",    1 },
  { "FACTION_STANDING_INCREASED_BONUS",        1 },
  { "FACTION_STANDING_INCREASED_DOUBLE_BONUS", 1 },
  { "FACTION_STANDING_INCREASED_ACCOUNT_WIDE", 1 },
  { "FACTION_STANDING_DECREASED",             -1 },
  { "FACTION_STANDING_DECREASED_ACCOUNT_WIDE",-1 },
  { "FACTION_STANDING_INCREASED_GENERIC",      1 },
  { "FACTION_STANDING_DECREASED_GENERIC",     -1 },
}
local factionPatterns   -- built on first use
local factionIDs        -- name -> factionID, built on first use

-- "Reputation with %s increased by %d." -> "^Reputation with (.-) increased by (%d+)"
local function patternFromFormat(fmt)
  local s = fmt:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2"):gsub("%%%.?%d*f", "\3")
  s = s:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")
  s = s:gsub("\1", "(.-)"):gsub("\2", "(%%d+)"):gsub("\3", "([%%d%%.]+)")
  return "^" .. s
end
WJ.patternFromFormat = patternFromFormat

local function ensureFactionPatterns()
  if factionPatterns then return end
  factionPatterns = {}
  for _, entry in ipairs(FACTION_FORMATS) do
    local fmt = _G[entry[1]]
    if type(fmt) == "string" then
      factionPatterns[#factionPatterns + 1] = { pattern = patternFromFormat(fmt), sign = entry[2] }
    end
  end
end

local function factionIDByName(name)
  if not factionIDs then
    factionIDs = {}
    local get = C_Reputation and C_Reputation.GetFactionDataByID
    if get then
      for id = 1, 4000 do
        local ok, data = pcall(get, id)
        if ok and data and data.name and not factionIDs[data.name] then
          factionIDs[data.name] = id
        end
      end
    end
  end
  return factionIDs[name]
end

-- Every reputation the game's Reputation pane lists, written with the opening
-- snapshot as REP lines with an empty delta: a standing as it is, not a gain.
-- Read the way the pane reads it (ReputationFrame.lua: C_Reputation.GetNumFactions
-- and GetFactionDataByIndex), since that list holds exactly the factions the
-- character has met. Asking by ID instead (GetFactionDataByID, as the name lookup
-- above does) answers with the same data but nothing in it says whether the
-- character has met the faction.
-- A plain header is skipped; a header with a standing of its own is a faction.
-- Every standing is written, the starting ones included (Neutral at 0, a home
-- city's Friendly), because the pane lists them too. Its one blind spot is
-- the pane's own: a header the player has collapsed hides its factions from the
-- list, and they are not asked for, since expanding it would change the
-- player's window. A change to one of them is still written when it happens.
local function writeReputations()
  local api = C_Reputation
  if not (api and api.GetNumFactions and api.GetFactionDataByIndex) then return end
  local ok, count = pcall(api.GetNumFactions)
  if not ok or not usable(count) then return end
  local written = {}
  for index = 1, count do
    local okData, data = pcall(api.GetFactionDataByIndex, index)
    if okData and type(data) == "table" then
      local id = data.factionID
      local isHeader, hasRep = data.isHeader, data.isHeaderWithRep
      local faction = not secret(isHeader) and not secret(hasRep) and (not isHeader or hasRep)
      if faction and usable(id) and id ~= 0 and not written[id] then
        written[id] = true
        write("REP", id, data.reaction, data.currentStanding, nil, data.name)
      end
    end
  end
end

handlers.CHAT_MSG_COMBAT_FACTION_CHANGE = function(msg)
  if type(msg) ~= "string" then return end
  ensureFactionPatterns()
  for _, p in ipairs(factionPatterns) do
    local name, amount = msg:match(p.pattern)
    if name then
      local id = factionIDByName(name)
      local data = id and C_Reputation.GetFactionDataByID(id)
      amount = tonumber(amount)
      write("REP", id, data and data.reaction, data and data.currentStanding,
        amount and amount * p.sign, name)
      return
    end
  end
end

---------------------------------------------------------------------------
-- Skills: SKILL on change and at session start; RECIPE; CRAFT; RECIPES (below).
--
-- On WoW Forever, every line of the character sheet's Skills tab (weapons,
-- defence, armour, languages, class and secondary skills) from C_SkillInfo, as
-- Forever's own SkillsFrame.lua reads it, with the line's category ID. Retail
-- has no C_SkillInfo; there, only the professions.
---------------------------------------------------------------------------

local skillState = {}
local knownSkillIDs = {}   -- every C_SkillInfo line seen this load

-- Also the line it belongs under, and the bonus from gear or buffs (the tab's green
-- "+N"). Some professions come as two lines (Skinning: 393, and 2947 hidden beneath
-- it); the parent says which is the profession and which its tier.
local function skillEntry(info)
  return { rank = info.rank, max = info.maxRank, name = info.name, category = info.skillLineCategoryID,
    parent = info.parentSkillLineID, modifier = info.modifier }
end

-- A collapsed header hides its lines from the index list, so a line seen once
-- is afterwards asked for by its ID: collapsing Weapon Skills must not read as
-- the skills vanishing, or hide a rise in one of them.
local function skillInfoNow(out)
  local api = C_SkillInfo
  if not (api and api.GetNumSkillLines and api.GetSkillLineInfo) then return end
  for index = 1, api.GetNumSkillLines() do
    local info = api.GetSkillLineInfo(index)
    if info and not info.isHeader and info.skillID then
      knownSkillIDs[info.skillID] = true
      out[info.skillID] = skillEntry(info)
    end
  end
  if not api.GetSkillLineInfoByID then return end
  for skillID in pairs(knownSkillIDs) do
    if not out[skillID] then
      local info = api.GetSkillLineInfoByID(skillID)
      if info and not info.isHeader then out[skillID] = skillEntry(info) end
    end
  end
end

local function skillsNow()
  local out = {}
  skillInfoNow(out)
  if not (GetProfessions and GetProfessionInfo) then return out end
  local ok, p1, p2, arch, fish, cook = pcall(GetProfessions)
  if not ok then return out end
  local indices = { p1, p2, arch, fish, cook }
  for i = 1, 5 do
    local index = indices[i]
    if index then
      local name, _, rank, max, _, _, skillLine = GetProfessionInfo(index)
      if skillLine and not out[skillLine] then out[skillLine] = { rank = rank, max = max, name = name } end
    end
  end
  return out
end

local function writeSkills(all)
  local now = skillsNow()
  for skillLine, s in pairs(now) do
    local prev = skillState[skillLine]
    if all or not prev or prev.rank ~= s.rank or prev.max ~= s.max or prev.modifier ~= s.modifier then
      write("SKILL", skillLine, s.rank, s.max, s.name, s.category, s.parent, s.modifier)
    end
  end
  skillState = now
end

-- The opening snapshot writes every skill and the guild (writeOpeningExtras). Until it
-- has, the change events the client fires while loading (SKILL_LINES_CHANGED,
-- PLAYER_GUILD_UPDATE, half a second into a login) would write them twice, the first
-- time with the guild's realm not yet known.
local opened = false

local skillPending = false
handlers.SKILL_LINES_CHANGED = function()
  if not opened or skillPending then return end
  skillPending = true
  C_Timer.After(0.5, WJ.guard("skills", function()
    skillPending = false
    writeSkills(false)
  end))
end

handlers.NEW_RECIPE_LEARNED = function(recipeID, recipeLevel, baseRecipeID)
  write("RECIPE", recipeID, recipeLevel, baseRecipeID)
end

local lastRecipeID
handlers.TRADE_SKILL_ITEM_CRAFTED_RESULT = function(data)
  if type(data) == "table" then
    write("CRAFT", lastRecipeID, data.itemID, data.quantity, data.craftingQuality)
  else
    write("CRAFT", lastRecipeID)
  end
end

---------------------------------------------------------------------------
-- Recipes known: RECIPES skillLineID recipeIDs list.
--
-- The client holds a profession's recipes only once its window has been
-- opened (before that the list is empty), so they are read when the player
-- opens the window, and never by opening it for them. TRADE_SKILL_SHOW,
-- TRADE_SKILL_LIST_UPDATE and TRADE_SKILL_DATA_SOURCE_CHANGED (a switch to
-- another profession inside the window) all lead to one read half a second
-- later, once C_TradeSkillUI.IsTradeSkillReady() says the window has loaded.
--
-- Only the player's own recipes: nothing is read while the window shows
-- someone else's (a profession linked in chat, a guild's or a guild member's
-- list, an NPC's), and nothing when the client can't say whose it shows.
--
-- skillLineID is the profession's own (GetBaseProfessionInfo), recipeIDs the
-- learned ones as a sorted comma list, from C_TradeSkillUI.GetAllRecipeIDs()
-- (every recipe of the profession, learned or not, whatever the window's
-- filters) and GetRecipeInfo(id).learned. A client without GetAllRecipeIDs
-- falls back to GetFilteredRecipeIDs(), the list the window itself shows,
-- which follows the window's filters and search: then list is "filtered"
-- rather than "all", and a recipe hidden by a filter is missing from it.
-- Written when the list differs from the last one written for that
-- profession in the session; a profession with no learned recipe writes
-- nothing.
---------------------------------------------------------------------------

local RECIPES_SETTLE = 0.5
local recipesWritten = {}   -- skillLineID -> recipeIDs as last written this session
local recipesPending = false

local function tradeSkillHas(name)
  local api = C_TradeSkillUI
  return type(api) == "table" and type(api[name]) == "function"
end

-- What a C_TradeSkillUI function returns, or nil when the client lacks it, it
-- throws, or the answer is secret.
local function tradeSkill(name, ...)
  if not tradeSkillHas(name) then return nil end
  local ok, value = pcall(C_TradeSkillUI[name], ...)
  if ok and not secret(value) then return value end
end

-- A table's member, or nil when the table is missing or the member secret.
local function member(t, key)
  if type(t) ~= "table" then return nil end
  local v = t[key]
  if secret(v) then return nil end
  return v
end

local function professionID()
  local base = tradeSkill("GetBaseProfessionInfo")
  local id = member(base, "professionID")
  if usable(id) and id ~= 0 then return id end
  local child = tradeSkill("GetChildProfessionInfo")
  id = member(child, "parentProfessionID")
  if usable(id) and id ~= 0 then return id end
  id = member(child, "professionID")
  if usable(id) and id ~= 0 then return id end
end

local function readRecipes()
  if tradeSkill("IsTradeSkillReady") ~= true or tradeSkill("IsDataSourceChanging") == true then return end
  -- Each must plainly answer false: a missing function, a throw or a secret is "can't tell".
  if not (tradeSkill("IsTradeSkillLinked") == false and tradeSkill("IsTradeSkillGuild") == false
    and tradeSkill("IsTradeSkillGuildMember") == false and tradeSkill("IsNPCCrafting") == false) then return end
  local skillLine = professionID()
  if not skillLine then return end
  local list, ids = "all", tradeSkill("GetAllRecipeIDs")
  if not tradeSkillHas("GetAllRecipeIDs") then
    list, ids = "filtered", tradeSkill("GetFilteredRecipeIDs")
  end
  if type(ids) ~= "table" then return end
  local learned = {}
  for _, id in ipairs(ids) do
    if usable(id) and member(tradeSkill("GetRecipeInfo", id), "learned") == true then
      learned[#learned + 1] = id
    end
  end
  if #learned == 0 then return end
  table.sort(learned)
  local recipeIDs = WJ.list(learned)
  if recipesWritten[skillLine] == recipeIDs then return end
  recipesWritten[skillLine] = recipeIDs
  write("RECIPES", skillLine, recipeIDs, list)
end

local function recipesSoon()
  if recipesPending then return end
  recipesPending = true
  C_Timer.After(RECIPES_SETTLE, WJ.guard("recipes", function()
    recipesPending = false
    readRecipes()
  end))
end
handlers.TRADE_SKILL_SHOW = recipesSoon
handlers.TRADE_SKILL_LIST_UPDATE = recipesSoon
handlers.TRADE_SKILL_DATA_SOURCE_CHANGED = recipesSoon

---------------------------------------------------------------------------
-- Achievements, gear, currency, encounters
---------------------------------------------------------------------------

handlers.ACHIEVEMENT_EARNED = function(achievementID, alreadyEarned)
  local name
  if GetAchievementInfo then
    local _, n = GetAchievementInfo(achievementID)
    name = n
  end
  write("ACHIEVE", achievementID, alreadyEarned and 1 or 0, name)
end

-- The event's second argument is documented both ways round (warcraft.wiki.gg: "true when a
-- slot becomes empty"), and trusting it wrote every EQUIP with an empty item. The slot
-- itself is the fact: read it, and an empty read is an emptied slot. Putting on a saved
-- gear set writes its EQUIP lines too, followed by GEARSWAP.
--
-- The event doesn't always come for every change. When the game takes a piece off and puts
-- it back by itself (a quest's disguise ending puts the helm in the bags and then back on the
-- head), the slot can be read empty at the one event and filled with no second event to say
-- so. So the slot is read again a second after its last event, and a second EQUIP is
-- written only when the item differs from the one written. Several changes to one slot
-- within the second share one re-read.
local EQUIP_RECHECK = 1
local equipWritten = {}   -- slot -> the item last written for it, as written
local equipTimers = {}    -- slot -> the re-read waiting for it

local function recheckEquip(slot)
  equipTimers[slot] = nil
  local item = GetInventoryItemID("player", slot)
  if secret(item) then return end
  item = WJ.field(item)
  if item == equipWritten[slot] then return end
  equipWritten[slot] = item
  write("EQUIP", slot, item, WJ.equipString(slot))
  WJ.statsSoon()
end

-- Beside the item's ID, the item as the game links it (Core.lua): an upgrade
-- or an enchant changes the string and not the ID.
handlers.PLAYER_EQUIPMENT_CHANGED = function(slot)
  local item = WJ.field(GetInventoryItemID("player", slot))
  write("EQUIP", slot, item, WJ.equipString(slot))
  WJ.statsSoon()
  if not usable(slot) then return end
  equipWritten[slot] = item
  if equipTimers[slot] then equipTimers[slot]:Cancel() end
  equipTimers[slot] = C_Timer.NewTimer(EQUIP_RECHECK, WJ.guard("equip", function() recheckEquip(slot) end))
end

---------------------------------------------------------------------------
-- Stats: what the gear added up to, as the character sheet shows it.
-- Written with every SNAP (Core.snapshot) and once equipment has settled
-- after a change (the client raises every slot at login), and only when a
-- value differs from the last STATS of the session. Never while the game
-- hides any of it: in combat, an encounter or a PvP match the attribute
-- calls answer secret values, and a line with its attributes empty says
-- nothing the sheet would show. Such a line is owed instead, and written a
-- second after combat ends, or at the next snapshot or gear change if the
-- restriction still holds. A function the client lacks is an empty field
-- and never defers a line; only a hidden value does. Every call is guarded:
-- a function the client doesn't have (WoW Forever, older rulesets) or one
-- that throws is an empty field. The stat APIs are SecretWhenUnitStatsRestricted
-- (Blizzard's UI source, warcraft.wiki.gg), so nothing is compared or added
-- before issecretvalue() says it may be, and the comparison with the last line
-- is made on the written field strings, which field() has already emptied.
---------------------------------------------------------------------------

local STATS_SETTLE = 1   -- s after the last EQUIP of a burst

local hiddenRead = false   -- whether a read since the last reset answered a secret value

-- The n-th return of fn(...), or nil when fn is missing or throws. A secret
-- answer is returned as it is (field() empties it) and noted.
local function ask(fn, n, ...)
  if type(fn) ~= "function" then return nil end
  local results = { pcall(fn, ...) }
  if not results[1] then return nil end
  local v = results[n + 1]
  if secret(v) then hiddenRead = true end
  return v
end

-- The sheet's Critical Strike (PaperDollFrame_SetCritChance): the highest of
-- melee, ranged, and the lowest spell-school chance (holy .. arcane).
-- A client without one of these (Forever, Classic) uses whichever exist.
local function critChance()
  local best = ask(GetCritChance, 1)
  if best ~= nil and not usable(best) then return best end   -- secret: field() empties it
  local ranged = ask(GetRangedCritChance, 1)
  if usable(ranged) and (best == nil or ranged > best) then best = ranged end
  local spell
  for school = 2, MAX_SPELL_SCHOOLS or 7 do
    local c = ask(GetSpellCritChance, 1, school)
    if not usable(c) then spell = nil break end
    if spell == nil or c < spell then spell = c end
  end
  if spell and (best == nil or spell > best) then best = spell end
  return best
end

-- Which primary stat the sheet shows: the spec's (PaperDollFrame:
-- select(6, C_SpecializationInfo.GetSpecializationInfo(spec, false, false, nil,
-- sex)); LE_UNIT_STAT_ 1 strength, 2 agility, 4 intellect). Empty without a spec,
-- when the sheet shows all three.
local function primaryStat()
  local getIndex = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
  local getInfo  = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
  local spec = ask(getIndex, 1)
  if not usable(spec) then return nil end
  return ask(getInfo, 6, spec, false, false, nil, UnitSex("player"))
end

-- The sheet's Versatility: the damage-done bonus from rating plus the flat bonus.
-- CR_VERSATILITY_DAMAGE_DONE is 29 in PaperDollFrame.lua (12.1.0).
local function versatility()
  local cr = CR_VERSATILITY_DAMAGE_DONE or 29
  local rating, bonus = ask(GetCombatRatingBonus, 1, cr), ask(GetVersatilityBonus, 1, cr)
  if not (usable(rating) and usable(bonus)) then return nil end
  return rating + bonus
end

---------------------------------------------------------------------------
-- The rest of the sheet, as WoW Forever's Classic-shaped sheet shows it (its own
-- PaperDollFrame.lua and PaperDollFrameStats.lua): spirit, power, attack power, hit / crit / haste for melee, ranged and spell,
-- expertise, armour and spell penetration, spell power and healing, defence,
-- dodge, parry, block, resistances, and weapon damage and speed. Written on
-- Retail too; whatever a client lacks is an empty field.
---------------------------------------------------------------------------

-- The sum of the arguments, or nil when one is missing or secret.
local function sum(...)
  local total = 0
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if not usable(v) then return nil end
    total = total + v
  end
  return total
end

-- The largest of the arguments present; nil when none is, or one is secret.
local function highest(...)
  local best
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if v ~= nil then
      if not usable(v) then return nil end
      if best == nil or v > best then best = v end
    end
  end
  return best
end

-- base + bonus + malus, the shape of UnitAttackPower and UnitRangedAttackPower.
local function effective(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, base, plus, minus = pcall(fn, ...)
  if not ok or base == nil then return nil end
  return sum(base, plus or 0, minus or 0)
end

-- The sheet's hit chance: the rating's bonus plus the flat modifier.
local function hitChance(rating, modifierFn)
  local fromRating = rating and ask(GetCombatRatingBonus, 1, rating)
  local modifier = ask(modifierFn, 1)
  if fromRating == nil and modifier == nil then return nil end
  return sum(fromRating or 0, modifier or 0)
end

-- The sheet's spell power: the lowest bonus over the spell schools (holy .. arcane).
local function spellPower()
  local lowest
  for school = 2, MAX_SPELL_SCHOOLS or 7 do
    local v = ask(GetSpellBonusDamage, 1, school)
    if not usable(v) then return nil end
    if lowest == nil or v < lowest then lowest = v end
  end
  return lowest
end

local DAMAGE_CLASS = Enum and Enum.Damageclass or {}
local RESISTANCES = { DAMAGE_CLASS.Holy or 1, DAMAGE_CLASS.Fire or 2, DAMAGE_CLASS.Nature or 3,
  DAMAGE_CLASS.Frost or 4, DAMAGE_CLASS.Shadow or 5, DAMAGE_CLASS.Arcane or 6 }

local function sheetValues()
  local critMelee, critRanged = ask(GetCritChance, 1), ask(GetRangedCritChance, 1)
  local critSpell = ask(GetSpellCritChance, 1)
  local hasteMelee = ask(GetMeleeHaste, 1)
  local hasteRanged = sum(ask(GetRangedHaste, 1), ask(GetRangedHaste, 2) or 0)
  local hasteSpell = ask(UnitSpellHaste, 1, "player")
  -- Any value may be nil, so each goes to an explicit position (# is unreliable with holes).
  local v, n = {}, 0
  local function put(x) n = n + 1; v[n] = x end
  put(ask(UnitStat, 2, "player", 5))                     -- spirit
  put(ask(UnitPowerType, 1, "player"))                   -- Enum.PowerType: 0 mana, 1 rage, 3 energy …
  put(ask(UnitPowerMax, 1, "player"))
  put(effective(UnitAttackPower, "player"))
  put(effective(UnitRangedAttackPower, "player"))
  put(hitChance(CR_HIT_MELEE, GetHitModifier))
  put(hitChance(CR_HIT_RANGED, GetRangedHitModifier))
  put(hitChance(CR_HIT_SPELL, GetSpellHitModifier))
  put(critMelee); put(critRanged); put(critSpell)
  put(hasteMelee); put(hasteRanged); put(hasteSpell)
  put(ask(GetExpertise, 1))
  put(ask(GetArmorPenetration, 1))
  put(spellPower())
  put(ask(GetSpellBonusHealing, 1))
  put(ask(GetSpellPenetration, 1))
  -- Defence with gear and buffs, as the sheet's local GetEffectiveDefenseSkill works it out
  -- (Camelot/PaperDollFrameStats.lua): max(0, base + modifier) of UnitDefenseSkill.
  local defenseBase, defenseModifier = ask(UnitDefenseSkill, 1, "player"), ask(UnitDefenseSkill, 2, "player")
  local defense = sum(defenseBase, defenseModifier or 0)
  put(defense and math.max(0, defense) or defenseBase)
  put(ask(GetDodgeChance, 1))
  put(ask(GetParryChance, 1))
  put(ask(GetBlockChance, 1))
  put(ask(GetShieldBlock, 1))
  for _, school in ipairs(RESISTANCES) do
    put(ask(UnitResistance, 2, "player", school))        -- effective resistance
  end
  local mhMin, mhMax, ohMin, ohMax
  if type(UnitDamage) == "function" then
    local ok, a, b, c, d = pcall(UnitDamage, "player")
    if ok then mhMin, mhMax, ohMin, ohMax = a, b, c, d end
  end
  put(mhMin); put(mhMax); put(ask(UnitAttackSpeed, 1, "player"))
  put(ohMin); put(ohMax); put(ask(UnitAttackSpeed, 2, "player"))
  put(ask(UnitRangedDamage, 2, "player"))                -- ranged min
  put(ask(UnitRangedDamage, 3, "player"))                -- ranged max
  put(ask(UnitRangedDamage, 1, "player"))                -- ranged speed
  -- Forever's sheet shows the best of melee, ranged and spell for Crit and Haste.
  return v, n, highest(critMelee, critRanged, critSpell), highest(hasteMelee, hasteRanged, hasteSpell)
end

local PRIMARY = 12       -- the only field not counted as "something readable"
local STATS_FIELDS = 51
local lastStats
local statsOwed = false   -- a line the game hid, to be written once it can be read whole

-- STATS ilvl str agi sta int armor crit haste mastery vers hpMax primary, then
-- spi powerType powerMax ap rap hitMelee hitRanged hitSpell critMelee critRanged critSpell
-- hasteMelee hasteRanged hasteSpell expertise armorPen spellPower spellHealing spellPen
-- defense dodge parry block shieldBlock resHoly resFire resNature resFrost resShadow
-- resArcane mhMin mhMax mhSpeed ohMin ohMax ohSpeed rangedMin rangedMax rangedSpeed
function WJ.writeStats()
  hiddenRead = false
  local sheet, sheetCount, foreverCrit, foreverHaste = sheetValues()
  local values = {
    ask(GetAverageItemLevel, 2),        -- equipped average, unrounded
    ask(UnitStat, 2, "player", 1),      -- effective strength
    ask(UnitStat, 2, "player", 2),      -- agility
    ask(UnitStat, 2, "player", 3),      -- stamina
    ask(UnitStat, 2, "player", 4),      -- intellect
    ask(UnitArmor, 2, "player"),        -- effective armor
    WJ.isForever and foreverCrit or critChance(),
    WJ.isForever and foreverHaste or ask(GetHaste, 1),
    ask(GetMasteryEffect, 1),
    versatility(),
    ask(UnitHealthMax, 1, "player"),
    -- Forever's sheet shows every attribute, so there is no primary stat to name there.
    not WJ.isForever and primaryStat() or nil,
  }
  for i = 1, sheetCount do values[PRIMARY + i] = sheet[i] end
  if hiddenRead then   -- the game is hiding part of the sheet: say it when it can be read whole
    statsOwed = true
    return
  end
  statsOwed = false
  local fields, any = {}, false
  for i = 1, STATS_FIELDS do
    fields[i] = WJ.field(values[i])
    if fields[i] ~= "" and i ~= PRIMARY then any = true end
  end
  if not any then return end   -- nothing readable (the client has none of it): nothing to say
  local key = table.concat(fields, "\t")
  if key == lastStats then return end
  lastStats = key
  write("STATS", unpack(fields, 1, STATS_FIELDS))
end

local statsTimer
local writeStatsSettled = WJ.guard("stats", function()
  statsTimer = nil
  WJ.writeStats()
end)

function WJ.statsSoon()
  if statsTimer then statsTimer:Cancel() end
  statsTimer = C_Timer.NewTimer(STATS_SETTLE, writeStatsSettled)
end

-- Called when combat ends (Events.lua): a line the fight hid is written a
-- second later, when the game has usually released the sheet.
function WJ.statsAfterCombat()
  if statsOwed then WJ.statsSoon() end
end

handlers.CURRENCY_DISPLAY_UPDATE = function(currencyID, quantity, change, gainSource, destroyReason)
  if currencyID == nil then return end   -- the login sweep fires with no currency
  write("CURRENCY", currencyID, quantity, change, gainSource, destroyReason)
end

-- Every currency the game's Currency tab lists, written with the opening
-- snapshot as CURRENCY lines with the change and its reasons empty: an amount
-- as it is, not a gain. Read the way the tab reads it, through
-- C_CurrencyInfo.GetCurrencyListSize and GetCurrencyListInfo(index), whose
-- CurrencyInfo says which rows are headers. A header is skipped. A currency
-- whose ID or amount the game hides is left out rather than written with no
-- amount. As with the reputations, the tab's one blind spot is kept: a group
-- the player has collapsed hides its currencies from the list, and the list
-- is never expanded to find them (ExpandCurrencyList would change the
-- player's window). A change to one of them is still written when it happens.
local function writeCurrencies()
  local api = C_CurrencyInfo
  if not (api and api.GetCurrencyListSize and api.GetCurrencyListInfo) then return end
  local ok, size = pcall(api.GetCurrencyListSize)
  if not ok or not usable(size) then return end
  local written = {}
  for index = 1, size do
    local okInfo, info = pcall(api.GetCurrencyListInfo, index)
    if okInfo and not secret(info) and type(info) == "table" then
      local id, isHeader, quantity = info.currencyID, info.isHeader, info.quantity
      if not secret(isHeader) and not isHeader and usable(id) and id ~= 0 and usable(quantity)
          and not written[id] then
        written[id] = true
        write("CURRENCY", id, quantity, nil, nil, nil)
      end
    end
  end
end

handlers.ENCOUNTER_START = function(encounterID, name, difficultyID, groupSize)
  write("ENCOUNTER", "start", encounterID, difficultyID, groupSize, "", name)
end

handlers.ENCOUNTER_END = function(encounterID, name, difficultyID, groupSize, success)
  write("ENCOUNTER", "end", encounterID, difficultyID, groupSize, success, name)
end

---------------------------------------------------------------------------
-- Spec and hearth location
---------------------------------------------------------------------------

local lastSpecID

local function writeSpec(force)
  local getIndex = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
  local getInfo  = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
  if not (getIndex and getInfo) then return end
  local index = getIndex()
  if not index then return end
  local specID, name = getInfo(index)
  if specID == nil or (specID == lastSpecID and not force) then return end
  lastSpecID = specID
  write("SPEC", specID, name)
end

handlers.PLAYER_SPECIALIZATION_CHANGED = function(unit)
  if unit == nil or unit == "player" then writeSpec(false) end
end

handlers.HEARTHSTONE_BOUND = function()
  write("BIND", GetBindLocation and GetBindLocation() or nil)
end

---------------------------------------------------------------------------
-- Gear sets and talents. Both are read the way the game's own windows read
-- them, and only through calls that may be missing on some client: a call the
-- client lacks, or one that throws, writes nothing.
---------------------------------------------------------------------------

local SETTLE = 0.5   -- s after the last of a burst of change events

local function pass(ok, ...)
  if ok then return ... end
end

-- What namespace.name(...) returns, or nothing when the client lacks it or it throws.
local function gameCall(namespace, name, ...)
  local api = _G[namespace]
  if type(api) ~= "table" or type(api[name]) ~= "function" then return end
  return pass(pcall(api[name], ...))
end

-- A table that may be read: present and not secret.
local function readable(t)
  if type(t) == "table" and not secret(t) then return t end
end

---------------------------------------------------------------------------
-- Gear sets: the equipment manager on the character pane (C_EquipmentSet, as
-- PaperDollFrame.lua reads it).
--
-- GEARSET setID name itemIDs ignoredSlots specID iconFileID: one line per set
-- with the opening snapshot, and whenever a set differs from its last line
-- (EQUIPMENT_SETS_CHANGED). itemIDs are GetItemIDs' answer for slots 1-19 in
-- slot order, an empty element where the game gives nothing; ignoredSlots are
-- the slots the set leaves alone when it is put on; specID is the spec the
-- set is assigned to. A deleted set is its ID with every other field empty.
--
-- GEARSWAP setID result startT: the game reporting a set put on
-- (EQUIPMENT_SWAP_FINISHED), with the time it announced the swap
-- (EQUIPMENT_SWAP_PENDING). The EQUIP lines in between are the swap's: gear
-- the character already had, changed into.
---------------------------------------------------------------------------

local GEAR_SLOTS = 19
local gearSetsWritten = {}   -- setID -> the fields last written for it this session
local gearSetsPending = false
local swapStartT

-- The set's fields, or nil when there is no such set or part of it is hidden (a
-- hidden item would read as a changed set).
local function gearSetFields(setID)
  local name, icon = gameCall("C_EquipmentSet", "GetEquipmentSetInfo", setID)
  if secret(name) or name == nil then return nil end
  local items = gameCall("C_EquipmentSet", "GetItemIDs", setID)
  if secret(items) then return nil end
  items = readable(items)
  local slots = {}
  for slot = 1, GEAR_SLOTS do
    local item = items and items[slot]
    if secret(item) then return nil end
    slots[slot] = WJ.field(item)
  end
  local ignoredTable = readable((gameCall("C_EquipmentSet", "GetIgnoredSlots", setID)))
  local ignored = {}
  if ignoredTable then
    for slot = 1, GEAR_SLOTS do
      local v = ignoredTable[slot]
      if not secret(v) and v == true then ignored[#ignored + 1] = slot end
    end
  end
  local specID
  local specIndex = gameCall("C_EquipmentSet", "GetEquipmentSetAssignedSpec", setID)
  if usable(specIndex) then
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    specID = ask(getInfo, 1, specIndex)
  end
  return { WJ.field(setID), WJ.field(name), table.concat(slots, ","), table.concat(ignored, ","),
    WJ.field(specID), WJ.field(icon) }
end

local function writeGearSets()
  local ids = readable((gameCall("C_EquipmentSet", "GetEquipmentSetIDs")))
  if not ids then return end
  local present, complete = {}, true
  for _, setID in ipairs(ids) do
    if usable(setID) then
      present[setID] = true
      local fields = gearSetFields(setID)
      if fields then
        local key = table.concat(fields, "\t")
        if gearSetsWritten[setID] ~= key then
          gearSetsWritten[setID] = key
          write("GEARSET", fields[1], fields[2], fields[3], fields[4], fields[5], fields[6])
        end
      end
    else
      complete = false
    end
  end
  -- A set is written as deleted only when the list could be read in full: a hidden ID
  -- might be any of them.
  if not complete then return end
  for setID in pairs(gearSetsWritten) do
    if not present[setID] then
      gearSetsWritten[setID] = nil
      write("GEARSET", setID, "", "", "", "", "")
    end
  end
end

handlers.EQUIPMENT_SETS_CHANGED = function()
  if not opened or gearSetsPending then return end
  gearSetsPending = true
  C_Timer.After(SETTLE, WJ.guard("gear sets", function()
    gearSetsPending = false
    writeGearSets()
  end))
end

handlers.EQUIPMENT_SWAP_PENDING = function()
  swapStartT = WJ.nowMs()
end

handlers.EQUIPMENT_SWAP_FINISHED = function(result, setID)
  write("GEARSWAP", setID, result, swapStartT)
  swapStartT = nil
end

---------------------------------------------------------------------------
-- Talents: TALENTS specGroup configID treeID nodes importString.
--
-- The talent window is the trait tree (Blizzard_ClassTalentsFrame.lua): the
-- active spec group's config, as WoW Forever's window finds it
-- (C_SpecializationInfo.GetCombatConfigIDForSpecGroup), or
-- C_ClassTalents.GetActiveConfigID on a client without spec groups; the tree
-- from C_Traits.GetConfigInfo; each node's bought ranks from
-- C_Traits.GetNodeInfo. nodes is every node with points bought, as
-- nodeID:entryID:rank in node order (a node the tree grants without a point
-- spent is left out); importString is the game's own export string for the
-- config, which talent calculators read. Written with the opening snapshot
-- and after a change has been applied, when it differs from the last line;
-- never while points are clicked but not applied (ConfigHasStagedChanges).
--
-- Classic-era clients have the older talent tabs instead (GetNumTalentTabs,
-- and GetTalentInfo(tab, index) with each talent's rank). WoW Forever's window
-- doesn't use them, so they aren't read: on such a client nothing is written.
---------------------------------------------------------------------------

local lastTalents
local talentsPending = false

local function talentFields()
  local group = gameCall("C_SpecializationInfo", "GetActiveSpecGroup")
  local configID
  if usable(group) then configID = gameCall("C_SpecializationInfo", "GetCombatConfigIDForSpecGroup", group) end
  if not usable(configID) then configID = gameCall("C_ClassTalents", "GetActiveConfigID") end
  if not usable(configID) then return nil end
  local staged = gameCall("C_Traits", "ConfigHasStagedChanges", configID)
  if secret(staged) or staged == true then return nil end
  local info = readable((gameCall("C_Traits", "GetConfigInfo", configID)))
  local treeIDs = info and readable(info.treeIDs)
  local treeID = treeIDs and treeIDs[1]
  if not usable(treeID) then return nil end
  local nodeIDs = readable((gameCall("C_Traits", "GetTreeNodes", treeID)))
  if not nodeIDs then return nil end
  -- A node the game hides can't be told apart from one with nothing bought, and leaving it
  -- out would read as a point taken back: then nothing is written at all.
  local bought = {}
  for _, nodeID in ipairs(nodeIDs) do
    if not usable(nodeID) then return nil end
    local node = gameCall("C_Traits", "GetNodeInfo", configID, nodeID)
    if secret(node) then return nil end
    node = readable(node)
    local rank = node and node.ranksPurchased
    if secret(rank) then return nil end
    if usable(rank) and rank > 0 then
      local entry = readable(node.activeEntry)
      bought[#bought + 1] = { id = nodeID, text = WJ.field(nodeID) .. ":" .. WJ.field(entry and entry.entryID) .. ":" .. WJ.field(rank) }
    end
  end
  table.sort(bought, function(a, b) return a.id < b.id end)
  local nodes = {}
  for i, b in ipairs(bought) do nodes[i] = b.text end
  local import = gameCall("C_Traits", "GenerateImportString", configID)
  if type(import) ~= "string" then import = nil end
  return { WJ.field(group), WJ.field(configID), WJ.field(treeID), table.concat(nodes, ","), WJ.field(import) }
end

local function writeTalents()
  local fields = talentFields()
  if not fields then return end
  local key = table.concat(fields, "\t")
  if key == lastTalents then return end
  lastTalents = key
  write("TALENTS", fields[1], fields[2], fields[3], fields[4], fields[5])
end

local function talentsSoon()
  if not opened or talentsPending then return end
  talentsPending = true
  C_Timer.After(SETTLE, WJ.guard("talents", function()
    talentsPending = false
    writeTalents()
  end))
end

-- A change applied, a switch of spec group or spec, a point gained at a level.
for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "ACTIVE_COMBAT_CONFIG_CHANGED",
  "ACTIVE_TALENT_GROUP_CHANGED", "CHARACTER_POINTS_CHANGED" }) do
  handlers[event] = talentsSoon
end
local specChanged = handlers.PLAYER_SPECIALIZATION_CHANGED
handlers.PLAYER_SPECIALIZATION_CHANGED = function(unit)
  specChanged(unit)
  if unit == nil or unit == "player" then talentsSoon() end
end

---------------------------------------------------------------------------
-- Guild: the player's own guild and rank, so the replay can
-- show the guild the character was in at the playhead. GUILD name rankName
-- realm rankIndex; all empty when the character left. At login the client
-- may not know the guild yet: nothing is written until it does, and a
-- character in no guild writes nothing at all.
---------------------------------------------------------------------------

local lastGuild   -- field key of the last GUILD written; nil before the first read
local NO_GUILD = "\t\t\t"

local function writeGuild()
  if not GetGuildInfo then return end
  local name, rankName, rankIndex, realm = GetGuildInfo("player")
  local fields = { WJ.field(name), WJ.field(rankName), WJ.field(realm), WJ.field(rankIndex) }
  local key = table.concat(fields, "\t")
  if key == lastGuild then return end
  if key == NO_GUILD then
    if IsInGuild and IsInGuild() then return end                 -- in one not loaded yet
    if lastGuild == nil then lastGuild = NO_GUILD return end     -- in none from the start
  end
  lastGuild = key
  write("GUILD", unpack(fields, 1, 4))
end

handlers.PLAYER_GUILD_UPDATE = function(unit)
  if opened and (unit == nil or unit == "player") then writeGuild() end
end

---------------------------------------------------------------------------
-- Trades: what the player gave and got in a completed trade
-- with another player. TRADE partnerGUID moneyGiven moneyReceived itemsGiven
-- itemsReceived partnerName, items as itemID:count comma lists. The trade
-- window (Blizzard's TradeFrame.lua) is read on every change,
-- since its slots are empty by the time it closes. TRADE_CLOSED fires for a
-- cancel too: completion is the game's "Trade complete." message
-- (UI_INFO_MESSAGE, ERR_TRADE_COMPLETE), which arrives after TRADE_CLOSED.
-- Both sides accepting is no substitute: when the partner accepts last, the
-- trade completes with no TRADE_ACCEPT_UPDATE(1, 1).
---------------------------------------------------------------------------

local TRADE_SLOTS = MAX_TRADABLE_ITEMS or 6   -- slot 7 shows an enchant; it isn't traded
local trade          -- the window as last seen: partner, money, items

-- itemID:count for each filled slot. idReturn = which return of infoFn is the itemID.
local function tradeItems(infoFn, linkFn, idReturn)
  if type(infoFn) ~= "function" then return "" end
  local out = {}
  for slot = 1, TRADE_SLOTS do
    local r = { pcall(infoFn, slot) }
    -- An empty slot still answers, with no name and item 0.
    if r[1] and r[2] and r[2] ~= "" then
      local itemID = r[idReturn + 1]
      if itemID == 0 then itemID = nil end
      if not usable(itemID) and type(linkFn) == "function" then
        local ok, link = pcall(linkFn, slot)
        itemID = ok and type(link) == "string" and not secret(link) and tonumber(link:match("item:(%d+)")) or nil
      end
      if itemID then out[#out + 1] = WJ.field(itemID) .. ":" .. WJ.field(r[4] or 1) end   -- r[4]: numItems
    end
  end
  return table.concat(out, ",")
end

local function readTrade()
  local name, realm = UnitFullName("NPC")
  name, realm = WJ.field(name), WJ.field(realm)
  if realm == "" then realm = WJ.field(GetNormalizedRealmName()) end
  trade = trade or {}
  trade.guid = UnitGUID("NPC") or trade.guid
  if name ~= "" then trade.name = name .. "-" .. realm end
  trade.gaveMoney = ask(GetPlayerTradeMoney, 1)
  trade.gotMoney = ask(GetTargetTradeMoney, 1)
  trade.gave = tradeItems(GetTradePlayerItemInfo, GetTradePlayerItemLink, 8)
  trade.got = tradeItems(GetTradeTargetItemInfo, GetTradeTargetItemLink, 7)
end

local function writeTrade()
  if not trade or trade.written then return end
  trade.written = true
  write("TRADE", trade.guid, trade.gaveMoney, trade.gotMoney, trade.gave, trade.got, trade.name)
  -- The money it moved explains the change that comes with it (Events.lua).
  if WJ.moneyFromTrade then WJ.moneyFromTrade(trade.gaveMoney, trade.gotMoney) end
end

handlers.TRADE_SHOW = function() trade = nil readTrade() end
handlers.TRADE_PLAYER_ITEM_CHANGED = readTrade
handlers.TRADE_TARGET_ITEM_CHANGED = readTrade
handlers.TRADE_MONEY_CHANGED = readTrade
handlers.PLAYER_TRADE_MONEY = readTrade
handlers.TRADE_ACCEPT_UPDATE = readTrade

-- Only the window opened last can complete, so the snapshot is the one traded.
handlers.UI_INFO_MESSAGE = function(_, message)
  if secret(message) then return end
  if ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE then
    writeTrade()
  elseif WJ.onInfoMessage then
    WJ.onInfoMessage(message)   -- a discovery's announcement (Moments.lua)
  end
end

---------------------------------------------------------------------------
-- Pet battles: a span with an outcome. The enemy team is recorded as
-- species IDs; a wild battle, an NPC trainer or another player.
---------------------------------------------------------------------------

local battleOpen, battleOutcome = false, nil

handlers.PET_BATTLE_OPENING_START = function()
  if not C_PetBattles then return end
  local enemy = (Enum and Enum.BattlePetOwner and Enum.BattlePetOwner.Enemy) or 2
  local species = {}
  local n = C_PetBattles.GetNumPets and C_PetBattles.GetNumPets(enemy) or 0
  for i = 1, n do species[i] = C_PetBattles.GetPetSpeciesID(enemy, i) end
  local kind = "pvp"
  if C_PetBattles.IsWildBattle and C_PetBattles.IsWildBattle() then
    kind = "wild"
  elseif C_PetBattles.IsPlayerNPC and C_PetBattles.IsPlayerNPC(enemy) then
    kind = "npc"
  end
  battleOpen, battleOutcome = true, nil
  write("PETBATTLE", "start", kind, WJ.list(species))
end

handlers.PET_BATTLE_FINAL_ROUND = function(winner)
  battleOutcome = (winner == 1) and "won" or "lost"
end

handlers.PET_BATTLE_CLOSE = function()
  if not battleOpen then return end   -- fires twice
  battleOpen = false
  write("PETBATTLE", "end", battleOutcome or "forfeit")
end

---------------------------------------------------------------------------
-- Speech: switched off. Nothing anyone types in chat is recorded, the
-- player's own /say and /yell included: what a player says is theirs, and it
-- isn't kept even in the file on their own disk.
--
-- The code stays, so that turning it on is a change of one line. On, it would
-- write what the character said aloud with /say or /yell (what anyone standing
-- nearby read in a bubble over them), only the player's own lines, never
-- anyone else's, never whispers, party, guild or channels: SPEECH kind
-- languageID text, the text as the game delivered it (links included), tabs
-- and line breaks made spaces by field() like any other. During chat lockdown
-- (12.0: combat in encounters) the text and the sender are secret (CHAT_MSG_SAY
-- is SecretInChatMessagingLockdown), so the line can't be told to be ours, and
-- nothing would be written.
--
-- Off, the chat events aren't even registered: the recorder never sees them.
---------------------------------------------------------------------------

local RECORD_SPEECH = false

-- The payload (ChatInfoDocumentation.lua): text, playerName, languageName, channelName,
-- playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, languageID,
-- lineID, guid, …
local function speech(kind)
  return function(text, _, _, _, _, _, _, _, _, languageID, _, guid)
    if secret(text) or secret(guid) or type(text) ~= "string" or text == "" then return end
    if guid ~= UnitGUID("player") then return end
    write("SPEECH", kind, languageID, text)
  end
end
if RECORD_SPEECH then
  handlers.CHAT_MSG_SAY  = speech("say")
  handlers.CHAT_MSG_YELL = speech("yell")
end

---------------------------------------------------------------------------
-- Screenshots (JUMP and EMOTE are hooks, below)
---------------------------------------------------------------------------

handlers.SCREENSHOT_SUCCEEDED = function()
  write("SHOT")
  counts.shots = counts.shots + 1
end

---------------------------------------------------------------------------
-- Repair cost is read while the merchant window is open, since the repair
-- hook runs after the money has already gone.
---------------------------------------------------------------------------

local repairCost = 0
local function noteRepairCost()
  if CanMerchantRepair and CanMerchantRepair() and GetRepairAllCost then
    repairCost = GetRepairAllCost() or 0
  else
    repairCost = 0
  end
end
handlers.MERCHANT_SHOW   = noteRepairCost
handlers.MERCHANT_UPDATE = noteRepairCost

---------------------------------------------------------------------------
-- Hooks: post-hooks on the functions the default UI calls. hooksecurefunc
-- never taints the original and works on protected functions. Each is
-- guarded so a function that no longer exists costs nothing, and each body
-- runs under WJ.guard so a throw is an ERR line named after the function,
-- never an error popup.
---------------------------------------------------------------------------

local function hook(owner, name, fn)
  if type(owner) == "table" then
    if type(owner[name]) == "function" then hooksecurefunc(owner, name, WJ.guard(name, fn)) end
  elseif type(_G[owner]) == "function" then
    hooksecurefunc(owner, WJ.guard(owner, fn))
  end
end

function WJ.installHooks()
  hook("JumpOrAscendStart", nil, function()
    write("JUMP")
    counts.jumps = counts.jumps + 1
  end)

  -- EMOTE: since 12.0 the game performs a typed emote (ChatFrameEditBox.lua) and one
  -- from the emote menu (ChatFrameMenuButton.lua) with C_ChatInfo.PerformEmote; DoEmote is only
  -- a deprecated wrapper around it (Deprecated_ChatInfo.lua), so hooking DoEmote alone missed
  -- every emote. Hook PerformEmote, which a DoEmote call also reaches; DoEmote only on a client
  -- without it, never both, or a DoEmote would be written twice. Post-hooks can't see whether
  -- the game refused the emote, so a refused one is still written.
  -- Opening the world map makes the character read it: the game performs READ itself every
  -- time the map opens, and the map's frame is already shown when the hook sees it. That READ
  -- is the map, not the player, so it is left out; a READ the player chooses with the map
  -- closed is still written.
  local function mapIsOpen()
    local map = WorldMapFrame
    if type(map) ~= "table" or type(map.IsShown) ~= "function" then return false end
    local ok, shown = pcall(map.IsShown, map)
    return ok and not secret(shown) and shown == true
  end
  local function emote(token)
    if type(token) ~= "string" or token == "" then return end
    if token == "READ" and mapIsOpen() then return end
    write("EMOTE", token)
    counts.emotes = counts.emotes + 1
  end
  if C_ChatInfo and type(C_ChatInfo.PerformEmote) == "function" then
    hook(C_ChatInfo, "PerformEmote", emote)
  else
    hook("DoEmote", nil, emote)
  end

  -- QABANDON: the game's abandon dialog sets the quest with
  -- C_QuestLog.SetAbandonQuest, then calls AbandonQuest; GetAbandonQuest still
  -- names it in the post-hook. QUEST_REMOVED follows, so
  -- the QREMOVE after a QABANDON is the abandon's, not a failure's.
  hook(C_QuestLog, "AbandonQuest", function()
    local questID = C_QuestLog.GetAbandonQuest and C_QuestLog.GetAbandonQuest()
    if questID and questID ~= 0 then write("QABANDON", questID) end
  end)

  hook(C_TradeSkillUI, "CraftRecipe", function(recipeID)
    lastRecipeID = recipeID
  end)

  -- BUY itemID quantity stackCount price currencyID — quantity as asked for,
  -- price and stack as the merchant lists them; the reader multiplies.
  hook("BuyMerchantItem", nil, function(index, quantity)
    local link = GetMerchantItemLink and GetMerchantItemLink(index)
    local itemID = link and link:match("item:(%d+)")
    local price, stack, currencyID
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
      local info = C_MerchantFrame.GetItemInfo(index)
      if info then price, stack, currencyID = info.price, info.stackCount, info.currencyID end
    elseif GetMerchantItemInfo then
      local _, _, p, s, _, _, _, _, c = GetMerchantItemInfo(index)
      price, stack, currencyID = p, s, c
    end
    write("BUY", itemID, quantity or stack, stack, price, currencyID)
  end)

  -- Right-clicking a bag item with a merchant open sells it. The hook runs
  -- after the request is sent but before the bag updates, so the slot still
  -- describes the item.
  hook(C_Container, "UseContainerItem", function(bag, slot)
    if not (MerchantFrame and MerchantFrame:IsShown()) then return end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or not info.itemID then return end
    local sellPrice = C_Item and C_Item.GetItemInfo and select(11, C_Item.GetItemInfo(info.itemID))
    write("SELL", info.itemID, info.stackCount, sellPrice)
  end)

  hook("RepairAllItems", nil, function(guildBankRepair)
    write("REPAIR", repairCost, guildBankRepair and 1 or 0)
  end)

  hook("BuyTrainerService", nil, function(index)
    local name = GetTrainerServiceInfo and GetTrainerServiceInfo(index)
    local cost = GetTrainerServiceCost and GetTrainerServiceCost(index)
    local link = GetTrainerServiceItemLink and GetTrainerServiceItemLink(index)
    local spellID = link and (link:match("spell:(%d+)") or link:match("enchant:(%d+)"))
    write("TRAIN", spellID, cost, name)
  end)
end

---------------------------------------------------------------------------
-- Opening state, written with the first snapshot (Core.openingState)
---------------------------------------------------------------------------

function WJ.writeOpeningExtras()
  opened = true
  writeSkills(true)
  writeReputations()
  writeCurrencies()
  writeSpec(true)
  -- Each guarded on its own, so whatever goes wrong there is named and the rest is still written.
  WJ.guard("talents", writeTalents)()
  WJ.guard("gear sets", writeGearSets)()
  if GetBindLocation then write("BIND", GetBindLocation()) end
  writeGuild()
end

-- A session resumed after a pause writes the character sheet afresh
-- with its first snapshot, and never names a cast from before the pause.
function WJ.resetExtrasForSession()
  lastStats = nil
  lastGuild = nil
  lastTalents = nil
  gearSetsWritten = {}
  swapStartT = nil
  recipesWritten = {}
  opened = false
  casts = {}
end
