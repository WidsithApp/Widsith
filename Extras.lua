-- Widsith — Extras
--
-- Everything beyond the core journey: travel spells and mounts, reputation,
-- skills and professions, achievements, gear and the character sheet,
-- currency, encounters, spec and hearth, gear sets and talents, the guild,
-- trading, pet battles, jumps and emotes. Speech is here too, switched off.

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
-- A mount is known at cast time from the mount journal. A travel spell is known
-- only by the move that follows it (a loading screen, or a jump in Position.lua):
-- the cast that finished just before the move began is written as SPELL.
-- UNIT_SPELLCAST_START carries the same castGUID as the SUCCEEDED that ends the
-- cast, which gives the time it began.
---------------------------------------------------------------------------

local casts = {}
local CAST_KEEP = 8
-- How long before a move its cast may have finished: a teleport follows its
-- cast within a round trip, and the rest allows for lag.
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
    -- A mount is summoned, not travelled by: never a candidate for SPELL.
    write("MOUNT", spellID, mountID)
    WJ.highlightShot("mount", "first")
    return
  end
  local startT
  if castGUID ~= nil and not secret(castGUID) then startT = starts[castGUID] end
  casts[#casts + 1] = { spellID = spellID, clock = GetTime(), t = WJ.nowMs(), startT = startT }
  if #casts > CAST_KEEP then table.remove(casts, 1) end
end

-- When the last loading screen appeared (GetTime()), used by the next "load"
-- relocation. Both events have no payload (LoadingScreenDocumentation.lua).
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
    -- No loading screen seen: nothing dates the move, so no cast is named.
    to, loadingClock = loadingClock, nil
    from = to and to - CAST_SLACK
  else
    to = GetTime()
    from = (since or to) - CAST_SLACK
  end
  if from then
    -- A load's cast is the latest in the window. A jump is noticed up to a second
    -- late, so a cast made on arrival can fall in the window too: there it is the earliest.
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
-- A change comes from the game's chat message, since the reputation list hides
-- the factions under a collapsed header. The name is matched to an ID by a
-- one-time scan of GetFactionDataByID; an unknown name leaves the ID empty.
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

-- Every faction the Reputation pane lists, read as ReputationFrame.lua reads it,
-- since only that list says which factions the character has met. A collapsed
-- header is never expanded, since that would change the player's window.
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
  if type(msg) ~= "string" or secret(msg) then return end
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
-- On WoW Forever, every line of the Skills tab from C_SkillInfo, as its
-- SkillsFrame.lua reads it. Retail's C_SkillInfo has no GetSkillLineInfo, so
-- there only the professions are written.
---------------------------------------------------------------------------

local skillState = {}
local knownSkillIDs = {}   -- every C_SkillInfo line seen this load

-- Also the parent line, which tells a profession from its tier, and the bonus
-- from gear or buffs (the tab's green "+N").
local function skillEntry(info)
  return { rank = info.rank, max = info.maxRank, name = info.name, category = info.skillLineCategoryID,
    parent = info.parentSkillLineID, modifier = info.modifier }
end

-- A collapsed header hides its lines from the index list, so a line seen once
-- is afterwards asked for by its ID.
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

-- Set by the opening snapshot, which writes every skill and the guild; the change
-- events the client fires while loading are ignored until then.
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
-- The client holds a profession's recipes only once its window has been opened,
-- so they are read when the player opens it, and only the player's own. A client
-- without GetAllRecipeIDs falls back to GetFilteredRecipeIDs, which follows the
-- window's filters, and list is "filtered" rather than "all".
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

-- The slot is read rather than the event's second argument, which is documented
-- both ways round. When the game takes a piece off and puts it back by itself no
-- second event may come, so the slot is read again a second after its last event.
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
-- Written with every SNAP and once equipment settles after a change, when a
-- value differs from the last STATS. The stat APIs are
-- SecretWhenUnitStatsRestricted (combat, an encounter, a PvP match), so a line
-- with a hidden value is held back until it can be read whole. A function the
-- client lacks, or one that throws, is an empty field.
---------------------------------------------------------------------------

local STATS_SETTLE = 1   -- s after the last EQUIP of a burst

local hiddenRead = false   -- whether a read since the last reset answered a secret value

-- The n-th return of fn(...), or nil when fn is missing or throws; a secret
-- answer is returned as it is and noted.
local function ask(fn, n, ...)
  if type(fn) ~= "function" then return nil end
  local results = { pcall(fn, ...) }
  if not results[1] then return nil end
  local v = results[n + 1]
  if secret(v) then hiddenRead = true end
  return v
end

-- The sheet's Critical Strike (PaperDollFrame_SetCritChance): the highest of melee,
-- ranged and the lowest spell-school chance, from whichever the client has.
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

-- The spec's primary stat, as PaperDollFrame.lua finds it (1 strength, 2 agility,
-- 4 intellect); empty without a spec.
local function primaryStat()
  local getIndex = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
  local getInfo  = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
  local spec = ask(getIndex, 1)
  if not usable(spec) then return nil end
  return ask(getInfo, 6, spec, false, false, nil, UnitSex("player"))
end

-- The sheet's Versatility: the damage-done bonus from rating plus the flat bonus.
-- CR_VERSATILITY_DAMAGE_DONE is 29 in PaperDollFrame.lua.
local function versatility()
  local cr = CR_VERSATILITY_DAMAGE_DONE or 29
  local rating, bonus = ask(GetCombatRatingBonus, 1, cr), ask(GetVersatilityBonus, 1, cr)
  if not (usable(rating) and usable(bonus)) then return nil end
  return rating + bonus
end

---------------------------------------------------------------------------
-- The rest of the sheet, as WoW Forever's Classic-shaped sheet shows it (its
-- PaperDollFrame.lua and PaperDollFrameStats.lua). Written on Retail too.
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
  -- Defence with gear and buffs, as GetEffectiveDefenseSkill in Camelot/PaperDollFrameStats.lua works it out.
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

-- Called when combat ends (Events.lua): a line the fight held back is written a second later.
function WJ.statsAfterCombat()
  if statsOwed then WJ.statsSoon() end
end

handlers.CURRENCY_DISPLAY_UPDATE = function(currencyID, quantity, change, gainSource, destroyReason)
  if currencyID == nil then return end   -- the login sweep fires with no currency
  write("CURRENCY", currencyID, quantity, change, gainSource, destroyReason)
end

-- Every currency the Currency tab lists, read as the tab reads it. A collapsed
-- group is never expanded, since that would change the player's window.
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
  if not secret(success) and not secret(encounterID) and success == 1 then WJ.highlightShot("boss", encounterID) end
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
-- Gear sets and talents, read the way the game's own windows read them. A call
-- the client lacks, or one that throws, writes nothing.
---------------------------------------------------------------------------

local SETTLE = 0.5   -- s after the last of a burst of change events

-- What namespace.name(...) returns, or nothing when the client lacks it or it throws (Core.lua).
local gameCall = WJ.gameCall

-- A table that may be read: present and not secret.
local function readable(t)
  if type(t) == "table" and not secret(t) then return t end
end

---------------------------------------------------------------------------
-- Gear sets: the equipment manager (C_EquipmentSet, as PaperDollFrame.lua reads it).
--
-- GEARSET setID name itemIDs ignoredSlots specID iconFileID: one line per set
-- with the opening snapshot and whenever a set changes, itemIDs for slots 1-19
-- in order. A deleted set is its ID with every other field empty.
-- GEARSWAP setID result startT: a set put on (EQUIPMENT_SWAP_FINISHED), with the
-- time of EQUIPMENT_SWAP_PENDING. The EQUIP lines in between are the swap's.
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
-- The trait tree (Blizzard_ClassTalentsFrame.lua) of the active spec group's
-- config, found as WoW Forever's window finds it, or by GetActiveConfigID on a
-- client without spec groups. nodes is nodeID:entryID:rank for each node with
-- points bought. Never written while changes are staged but not applied.
-- Classic-era talent tabs (GetNumTalentTabs) aren't read: there nothing is written.
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
-- Guild: GUILD name rankName realm rankIndex, all empty when the character
-- leaves. At login the client may not know the guild yet, so nothing is
-- written until it does; a character in no guild writes nothing.
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
-- Trades: TRADE partnerGUID moneyGiven moneyReceived itemsGiven itemsReceived
-- partnerName, items as itemID:count lists. The window (TradeFrame.lua) is read
-- on every change, since its slots are empty by the time it closes. TRADE_CLOSED
-- fires for a cancel too, and a trade can complete with no TRADE_ACCEPT_UPDATE(1, 1),
-- so completion is the "Trade complete." message (ERR_TRADE_COMPLETE).
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
  local guid = UnitGUID("NPC")
  if secret(guid) then guid = nil end
  trade.guid = guid or trade.guid
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
  local enemy = (Enum and Enum.BattlePetOwner and Enum.BattlePetOwner.Enemy) or 2
  -- A client that can't say how many pets there are can't describe the battle.
  local n = gameCall("C_PetBattles", "GetNumPets", enemy)
  if n == nil then return end
  local species = {}
  for i = 1, n do species[i] = gameCall("C_PetBattles", "GetPetSpeciesID", enemy, i) end
  local kind = "pvp"
  if gameCall("C_PetBattles", "IsWildBattle") then
    kind = "wild"
  elseif gameCall("C_PetBattles", "IsPlayerNPC", enemy) then
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
-- Speech: switched off, so nothing anyone types in chat is recorded. On, it would
-- write SPEECH kind languageID text for the player's own /say and /yell only.
-- CHAT_MSG_SAY is SecretInChatMessagingLockdown, so nothing is written during chat lockdown.
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

function WJ.mapIsOpen()
  local map = WorldMapFrame
  if type(map) ~= "table" or type(map.IsShown) ~= "function" then return false end
  local ok, shown = pcall(map.IsShown, map)
  return ok and not secret(shown) and shown == true
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
-- Hooks: post-hooks on the functions the default UI calls; hooksecurefunc never
-- taints the original. A function the client lacks is skipped, and a throw in a
-- body is written as an ERR line named after the function.
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

  -- EMOTE: the game performs typed and menu emotes with C_ChatInfo.PerformEmote
  -- (ChatFrameEditBox.lua, ChatFrameMenuButton.lua), and DoEmote is a deprecated wrapper
  -- around it (Deprecated_ChatInfo.lua), so DoEmote is hooked only on a client without it.
  -- A refused emote is still written. The game performs READ itself whenever the world map
  -- opens, so a READ with the map open is left out.
  local function emote(token)
    if type(token) ~= "string" or token == "" then return end
    if token == "READ" and WJ.mapIsOpen() then return end
    write("EMOTE", token)
    counts.emotes = counts.emotes + 1
  end
  if C_ChatInfo and type(C_ChatInfo.PerformEmote) == "function" then
    hook(C_ChatInfo, "PerformEmote", emote)
  else
    hook("DoEmote", nil, emote)
  end

  -- QABANDON: the abandon dialog sets the quest with C_QuestLog.SetAbandonQuest before
  -- calling AbandonQuest, so GetAbandonQuest still names it here. The QREMOVE that follows is the abandon's.
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

-- Each guarded on its own, so whatever goes wrong there is named and the rest is still written.
function WJ.writeOpeningExtras()
  opened = true
  WJ.guard("skills", writeSkills)(true)
  WJ.guard("reputations", writeReputations)()
  WJ.guard("currencies", writeCurrencies)()
  WJ.guard("spec", writeSpec)(true)
  WJ.guard("talents", writeTalents)()
  WJ.guard("gear sets", writeGearSets)()
  WJ.guard("bind", function() if GetBindLocation then write("BIND", GetBindLocation()) end end)()
  WJ.guard("guild", writeGuild)()
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
