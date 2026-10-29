-- A rough stand-in for the WoW client, to run the recorder outside the game: the fights,
-- deaths, auras and counters in Moments.lua, and in Extras.lua the opening reputations and
-- currencies, the recipes, the switched-off speech, the gear sets and the talents.
-- Secret values are objects that raise an error on any use, so a missing secret check
-- shows up as an ERR line in the recording. It can't show what the real APIs answer: the
-- stubs return what the game was seen to answer on WoW Forever build 70124.
-- An aura read under restrictions raises the game's own error, as it did on build 70235 for a
-- session that opened in combat, and the run ends by checking that session's lines
-- ("-- expect FAIL" when one is wrong; check.mjs fails on it).
-- It also plays and checks: the Currency tab's list read with the opening snapshot (a header,
-- a collapsed group, a hidden amount, and the list never expanded); a fight whose meter is
-- whole the instant combat ends (FIGHT at COMBAT leave's own time), one where it isn't until a
-- second later, and two fights in quick succession each getting a line; the map's own READ
-- left out and a READ with the map closed written; and a session whose opening aura read is
-- refused with the game's error although C_Secrets said it wouldn't be.
-- And three things Retail 12.1.5 (build 70448) was seen to do: UnitIsAFK answering a secret
-- (an encounter's chat lockdown), which must write a STATE with an empty afk field and no ERR
-- (a table can't be falsy in Lua, so the stand-in can't raise the game's own error; it shows a
-- missing check as a "1" instead); a loading screen across the five-minute mark, whose SNAP
-- must wait for the screen's end; and a quest disguise ending with one
-- PLAYER_EQUIPMENT_CHANGED read while the head slot was empty, which the re-read a second
-- later must put right.
--
-- Run from the addon's folder:
--   npx --yes -p fengari-node-cli fengari tools/recorder-mock.lua
-- It loads the recorder (all but Save.lua, which only draws the icon), plays a session
-- through it and prints the lines Moments.lua wrote, the REP, RECIPES and SPEECH lines,
-- every ERR line, and a count by type.
-- Any global the recorder asks for that isn't stubbed here answers nil (a function that
-- returns nothing, or an empty namespace), as a client lacking that API would.

-- The addon's folder, worked out from this file's own path (tools/recorder-mock.lua), so the
-- run works from any folder the path is given from.
local DIR = (arg and arg[0] and arg[0]:match("^(.-)tools[/\\][^/\\]+$")) or ""
local ADDON = "Widsith"

local clock = 5000
local inCombat = false
local realPrint = print
local chat = {}

local SECRET = setmetatable({}, {
  __index = function() error("SECRET indexed", 2) end,
  __newindex = function() error("SECRET assigned", 2) end,
  __concat = function() error("SECRET concatenated", 2) end,
  __len = function() error("SECRET length", 2) end,
  __call = function() error("SECRET called", 2) end,
  __lt = function() error("SECRET compared", 2) end,
  __le = function() error("SECRET compared", 2) end,
  __add = function() error("SECRET arithmetic", 2) end,
  __sub = function() error("SECRET arithmetic", 2) end,
  __mod = function() error("SECRET arithmetic", 2) end,
  __tostring = function() error("SECRET tostring", 2) end,
})
function issecretvalue(v) return rawequal(v, SECRET) end

-- Anything not stubbed: functions that return nothing, namespaces with such functions.
local nothing = function() end
local emptyNamespace = setmetatable({}, { __index = function() return nothing end })
setmetatable(_G, {
  __index = function(_, key)
    if type(key) ~= "string" or key:find("^Widsith") or key == "C_SkillInfo" then return nil end
    if key:find("^C_") then return emptyNamespace end
    if key:find("^%u%l") then return nothing end
    return nil
  end,
})

-- Frames and timers -------------------------------------------------------
local frames, timers = {}, {}
local frameNo = 0          -- rendered frames so far
local statFrames = {}      -- the frames in which a counter was read
local widget = {}
widget.__index = function(_, key) return rawget(widget, key) or nothing end
function widget:RegisterEvent(event) self.events[event] = true end
function widget:RegisterUnitEvent(event, unit) self.events[event] = unit end
function widget:UnregisterEvent(event) self.events[event] = nil end
function widget:SetScript(name, fn) self.scripts[name] = fn end
function CreateFrame()
  local f = setmetatable({ scripts = {}, events = {} }, widget)
  frames[#frames + 1] = f
  return f
end

local function fire(event, ...)
  for _, f in ipairs(frames) do
    local reg = f.events[event]
    if reg and f.scripts.OnEvent and (reg == true or reg == (...)) then f.scripts.OnEvent(f, event, ...) end
  end
end

-- Rendered frames: every OnUpdate script runs once per frame.
local function render(n)
  for _ = 1, n do
    frameNo = frameNo + 1
    for _, f in ipairs(frames) do
      if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.016) end
    end
  end
end

-- Time passes: timers fire in order, with frames rendered between them and after.
local function advance(seconds)
  local target = clock + seconds
  while true do
    local nextAt, nextIndex
    for i, t in ipairs(timers) do
      if t.at <= target and (not nextAt or t.at < nextAt) then nextAt, nextIndex = t.at, i end
    end
    if not nextIndex then break end
    local t = timers[nextIndex]
    clock = t.at
    if t.every then t.at = t.at + t.every else table.remove(timers, nextIndex) end
    t.fn(t)
    render(10)
  end
  clock = target
  render(30)
end

C_Timer = {
  After = function(seconds, fn) timers[#timers + 1] = { at = clock + seconds, fn = fn } end,
  NewTicker = function(seconds, fn)
    local t = { at = clock + seconds, fn = fn, every = seconds, Cancel = function(self) self.at = math.huge end }
    timers[#timers + 1] = t
    return t
  end,
  NewTimer = function(seconds, fn)
    local t = { at = clock + seconds, fn = fn, Cancel = function(self) self.at = math.huge end }
    timers[#timers + 1] = t
    return t
  end,
}

-- The client -------------------------------------------------------------------
function print(...) chat[#chat + 1] = table.concat({ ... }, " ") end
function GetTime() return clock end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
-- The millisecond clock: reading a counter costs a millisecond, so a pass spans frames.
local profileMs = 0
function debugprofilestop() return profileMs end
function GetServerTime() return 1790766000 + math.floor(clock) end
-- Another player's name from their GUID, as the game knows it; nothing for one it hasn't met.
function GetPlayerInfoByGUID(guid)
  if guid == "Player-4747-0BBBBBBB" then return "Paladin", "PALADIN", "Human", "Human", 2, "Someone", "" end
end
-- The character sheet: the attribute calls are SecretWhenUnitStatsRestricted and answer secrets
-- in combat; the item level is readable throughout, so a line read in a fight is part hidden.
function UnitStat(_, i) if inCombat then return SECRET, SECRET, SECRET, SECRET end return 10 + i, 12 + i, 2, 0 end
function UnitArmor() if inCombat then return SECRET, SECRET end return 50, 55 end
function UnitHealthMax() if inCombat then return SECRET end return 136 end
function GetAverageItemLevel() return 20, 18.5 end
-- The loot messages, worded as the English client words them, and a loot window of one slot.
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
LOOT_ITEM_CREATED_SELF = "You create: %s."
LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d."
LOOT_ITEM_BONUS_ROLL_SELF = "You receive bonus loot: %s."
LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE = "You receive bonus loot: %sx%d."
LOOT_ITEM_REFUND = "You are refunded: %s."
LOOT_ITEM_REFUND_MULTIPLE = "You are refunded: %sx%d."
local lootSlots = {}
function GetNumLootItems() return #lootSlots end
function GetLootSlotLink(slot) return lootSlots[slot] and lootSlots[slot].link end
function GetLootSourceInfo(slot) return lootSlots[slot] and lootSlots[slot].guid end
function GetBuildInfo() return "1.60.1", "70658", "Oct 27 2026", 16001 end
function GetLocale() return "enUS" end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
C_AddOns = { GetAddOnMetadata = function() return "0.2.23" end }
SlashCmdList = {}
-- Post-hooks on functions a stub here defines; anything else is left alone.
function hooksecurefunc(owner, name, fn)
  if type(owner) ~= "table" or type(rawget(owner, name)) ~= "function" then return end
  local original = owner[name]
  owner[name] = function(...) original(...) fn(...) end
end
-- The world map, and the emote the game performs when it opens.
WorldMapFrame = { shown = false, IsShown = function(self) return self.shown end }
C_ChatInfo = { PerformEmote = function() end }
function InCombatLockdown() return inCombat end
function UnitGUID(unit) if unit == "player" then return "Player-4747-0ABC1234" end end
function UnitName() return "Aldwin", "Thornby" end
function GetRealmName() return "Whitemane" end
function GetNormalizedRealmName() return "Whitemane" end
function UnitClass() return "Warrior", "WARRIOR", 1 end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return 5 end
function UnitXP() return 100 end
function UnitXPMax() return 2800 end
function GetMoney() return 334 end
function GetInstanceInfo() return "Eastern Kingdoms", "none", 0, "", 0, 0, false, 0 end
function IsResting() return false end
function IsInGroup() return false end
function UnitIsGhost() return false end
function UnitIsFeignDeath() return false end
-- Away: hidden while afkHidden, as UnitIsAFK is under the game's chat lockdown.
local afkHidden = false
function UnitIsAFK() if afkHidden then return SECRET end return false end
-- The character's gear by slot; an empty slot answers nil.
local inventory = {}
function GetInventoryItemID(_, slot) return inventory[slot] end
C_QuestLog = setmetatable({ GetNumQuestLogEntries = function() return 0 end }, { __index = function() return nothing end })
C_Map = setmetatable({ GetBestMapForUnit = function() return nil end }, { __index = function() return nothing end })
ERR_ZONE_EXPLORED = "Discovered: %s"
ERR_ZONE_EXPLORED_XP = "Discovered %s: %d experience gained"
ERR_TRADE_COMPLETE = "Trade complete."

Enum = { DamageMeterType = { DamageDone = 0, DamageTaken = 7, HealingDone = 2, EnemyDamageTaken = 10 } }
local fights = { { sessionID = 88, name = "Kobold Vermin", durationSeconds = 7 } }
-- A fight the meter isn't whole for at the instant combat ends, until the clock passes `at`:
-- "missing" leaves this character's entry out (as the game once did), "secret" still hides
-- the amounts.
local meterLate = {}
-- The duration the meter reports for its newest session: raised when a session carries on
-- through another span of combat.
local meterDuration = 24
-- This character's damage done in the newest session: raised when the session carries on.
local meterTotal = 181
local function meterSession(id, kind)
  local late = meterLate[id]
  if late and clock >= late.at then late = nil end
  if inCombat or (late and late.how == "secret") then
    return { combatSources = { { isLocalPlayer = true, totalAmount = SECRET, name = SECRET, sourceGUID = SECRET } },
      totalAmount = SECRET, durationSeconds = SECRET }
  end
  if late and late.how == "missing" and kind == 0 then
    return { combatSources = { { isLocalPlayer = false, totalAmount = 900, name = "Someone Else", sourceGUID = "Player-4747-0AAAAAAA" } },
      totalAmount = 900, durationSeconds = 24 }
  end
  if kind == 2 then return { combatSources = {}, totalAmount = 0, durationSeconds = 24 } end
  if kind == 10 then
    return { combatSources = { { isLocalPlayer = false, name = "Kobold Geomancer", sourceCreatureID = 476, totalAmount = 181 },
      { isLocalPlayer = false, name = "Hogger, the Gnoll: Elite", sourceCreatureID = 448, totalAmount = 12 },
      { isLocalPlayer = false, name = "Maela Dunwood", classFilename = "PALADIN", totalAmount = 16 } },
      totalAmount = 193, durationSeconds = 24 }
  end
  return { combatSources = { { isLocalPlayer = true, totalAmount = kind == 0 and meterTotal or 140, name = "Aldwin Thornby",
    sourceGUID = "Player-4747-0ABC1234" }, { isLocalPlayer = false, totalAmount = 900, name = "Someone Else", sourceGUID = "Player-4747-0AAAAAAA" } },
    totalAmount = kind == 0 and (meterTotal + 900) or 140, durationSeconds = meterDuration }
end
C_DamageMeter = {
  GetAvailableCombatSessions = function() return fights end,
  GetCombatSessionFromID = function(id, kind) return meterSession(id, kind) end,
  GetCombatSessionSourceFromID = function(_, kind, guid)
    if rawequal(guid, SECRET) then error("Secret values are only allowed during untainted execution") end
    if kind == 0 then return { combatSpells = { { spellID = 6603, totalAmount = 105 }, { spellID = 772, totalAmount = 43 }, { spellID = 78, totalAmount = 33 } } } end
    return { combatSpells = { { spellID = 20793, totalAmount = 117 }, { spellID = 6603, totalAmount = 23 } } }
  end,
}
local recapStale = false
C_DeathRecap = {
  GetRecapMaxHealth = function() return 136 end,
  GetRecapEvents = function(id)
    local at = recapStale and 1790766000 or (GetServerTime() + 0.004)
    return {
      { event = "SPELL_DAMAGE", spellId = 20793, spellName = "Fireball", school = 4, amount = 31, overkill = 4, currentHP = 27,
        timestamp = at, sourceGUID = "Creature-0-4621-0-46196-476-0000BCECFD", sourceName = "Kobold Geomancer Jaconelli" },
      { event = "SPELL_DAMAGE", spellId = 172, spellName = "Corruption", school = 32, amount = 9, overkill = -1, currentHP = 36,
        timestamp = at - 3.1, sourceGUID = "Player-4747-0BBBBBBB", sourceName = "Someone" },
      { event = "SWING_DAMAGE", school = 1, amount = 8, overkill = -1, currentHP = 44, timestamp = at - 6.9,
        sourceGUID = "Creature-0-4621-0-46196-476-0000BCECFD" },
      SECRET,
      { event = "ENVIRONMENTAL_DAMAGE", environmentalType = "FALLING", amount = 12, overkill = -1, currentHP = 47, timestamp = at - 30 },
    }
  end,
}
-- Auras. While restrictions are on (combat, or an encounter) the game refuses an addon's
-- aura read with an error rather than a secret value, and it refuses one whose spell is
-- always hidden at any time (RequiresUnitAuraAccess, UnitAuraDocumentation.lua); C_Secrets
-- says so in advance. Every refusal is counted. refuseUnforeseen refuses every read while
-- C_Secrets still says nothing is hidden, with the message the game gave on build 70235.
local encounter = false
local refuseUnforeseen = false
local auraRefusals = 0
local function aurasRestricted() return inCombat or encounter end
local function refuse(name)
  auraRefusals = auraRefusals + 1
  error(name .. "(): Auras cannot be accessed when secret while tainted by 'Widsith' Lua Taint: Widsith", 0)
end
local present = { HELPFUL = { { name = "Battle Shout", spellId = 6673, isHelpful = true, sourceUnit = "player", duration = 120, applications = 0, auraInstanceID = 11 } }, HARMFUL = {} }
C_Secrets = {
  ShouldAurasBeSecret = function() return aurasRestricted() end,
  ShouldUnitAuraIndexBeSecret = function(_, i, filter) local aura = present[filter][i] return aura ~= nil and aura.alwaysHidden == true end,
  ShouldUnitAuraInstanceBeSecret = function() return false end,
}
C_UnitAuras = {
  GetAuraDataByIndex = function(_, i, filter)
    local aura = present[filter][i]
    if aurasRestricted() or refuseUnforeseen or (aura and aura.alwaysHidden) then refuse("GetAuraDataByIndex") end
    return aura
  end,
  GetAuraCasterGUID = function(_, instance)
    if aurasRestricted() then refuse("GetAuraCasterGUID") end
    if instance == 133 then return "Player-4747-0BBBBBBB" end
    if instance == 140 then return "Creature-0-4621-0-46196-30-00003CF70B" end
    return "Player-4747-0ABC1234"
  end,
}
C_LossOfControl = { GetActiveLossOfControlData = function()
  return { locType = "STUN_MECHANIC", spellID = 853, displayText = "Stunned", duration = 3, lockoutSchool = 0, auraInstanceID = 37 }
end }
local stat = { [107] = "85", [108] = "4", [60] = "1", [347] = "1", [328] = "4|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t 62", [114] = "--", [1336] = "49 (Humanoid)" }
local statNames = { [107] = "Creatures killed", [108] = "Critters killed", [60] = "Total deaths", [347] = "Food eaten", [328] = "Total gold acquired",
  [114] = "Deaths from falling", [1336] = "Creature type killed the most" }
local statOrder = { 107, 108, 60, 347, 328, 114, 1336 }
function GetStatisticsCategoryList() return { 130 } end
function GetCategoryNumAchievements() return #statOrder end
local byIDReads = 0
function GetStatistic(category, i)
  profileMs = profileMs + 1
  statFrames[frameNo] = true
  -- The one-argument form, by ID, as the pane's own rows read it.
  if i == nil then
    byIDReads = byIDReads + 1
    return stat[category], false, category
  end
  return stat[statOrder[i]], false, statOrder[i]
end
function GetAchievementInfo(id) return id, statNames[id] end
-- The Reputation pane's list: a plain header, factions, a header with a standing of its own,
-- one whose ID the game hid, one listed twice.
local pane = {
  { factionID = 469, name = "Alliance", isHeader = true, isHeaderWithRep = false, reaction = 4, currentStanding = 0 },
  { factionID = 72, name = "Stormwind", isHeader = false, isHeaderWithRep = false, reaction = 5, currentStanding = 3150 },
  { factionID = 47, name = "Ironforge", isHeader = false, isHeaderWithRep = false, reaction = 4, currentStanding = 0 },
  { factionID = 1134, name = "Gilneas", isHeader = true, isHeaderWithRep = true, reaction = 6, currentStanding = 9500 },
  { factionID = SECRET, name = SECRET, isHeader = false, isHeaderWithRep = false, reaction = SECRET, currentStanding = SECRET },
  { factionID = 72, name = "Stormwind", isHeader = false, isHeaderWithRep = false, reaction = 5, currentStanding = 3150 },
}
C_Reputation = {
  GetNumFactions = function() return #pane end,
  GetFactionDataByIndex = function(i) return pane[i] end,
  GetFactionDataByID = function(id) if id == 72 then return pane[2] end end,
}
FACTION_STANDING_INCREASED = "Reputation with %s increased by %d."

-- The Currency tab's list (CurrencyInfoDocumentation.lua): a header, a currency held, one
-- whose amount the game hid, a collapsed header (its currencies aren't listed), another
-- group's header and a currency at 0, and a listed row the game answers nothing for.
-- Expanding a header would change the player's window; the stand-in counts any attempt.
local currencyList = {
  { name = "Miscellaneous", currencyID = 0, isHeader = true, isHeaderExpanded = true, currencyListDepth = 0, quantity = 0 },
  { name = "Valor Mark", currencyID = 3498, isHeader = false, currencyListDepth = 1, quantity = 12, maxQuantity = 0, totalEarned = 12, discovered = true },
  { name = SECRET, currencyID = 3499, isHeader = false, currencyListDepth = 1, quantity = SECRET, maxQuantity = 0, discovered = true },
  { name = "Legacy", currencyID = 0, isHeader = true, isHeaderExpanded = false, currencyListDepth = 0, quantity = 0 },
  { name = "Player vs. Player", currencyID = 0, isHeader = true, isHeaderExpanded = true, currencyListDepth = 0, quantity = 0 },
  { name = "Honor Token", currencyID = 3500, isHeader = false, currencyListDepth = 1, quantity = 0, maxQuantity = 75, discovered = true },
}
local currencyExpanded = 0
C_CurrencyInfo = {
  GetCurrencyListSize = function() return #currencyList + 1 end,
  GetCurrencyListInfo = function(i) return currencyList[i] end,
  ExpandCurrencyList = function() currencyExpanded = currencyExpanded + 1 end,
}

-- A profession window: whose it is, whether it has loaded, and its recipes (one ID hidden,
-- one recipe's details hidden).
local window = { ready = false, linked = false, npc = false }
local recipes = { [8613] = true, [8617] = false, [10662] = true, [19047] = false }
C_TradeSkillUI = {
  IsTradeSkillReady = function() return window.ready end,
  IsDataSourceChanging = function() return false end,
  IsTradeSkillLinked = function() return window.linked, window.linked and "Someone" or nil end,
  IsTradeSkillGuild = function() return false end,
  IsTradeSkillGuildMember = function() return false end,
  IsNPCCrafting = function() return window.npc end,
  GetBaseProfessionInfo = function() return { professionID = 393, professionName = "Skinning" } end,
  GetChildProfessionInfo = function() return { professionID = 2947, parentProfessionID = 393 } end,
  GetAllRecipeIDs = function() return { 10662, 8613, 8617, SECRET, 19047, 20000 } end,
  GetFilteredRecipeIDs = function() return { 8613, 10662 } end,
  GetRecipeInfo = function(id)
    if id == 20000 then return { learned = SECRET } end
    return { recipeID = id, learned = recipes[id] }
  end,
}
-- Gear sets: two, one with ignored slots (one of them hidden) and assigned to a spec; at
-- login the list also holds an ID the game hid.
local sets = {
  [0] = { name = "Questing", icon = 132347, items = { [1] = 10001, [5] = 10002, [16] = 25 }, ignored = { [4] = true, [19] = SECRET }, spec = 1 },
  [1] = { name = "Tank", icon = 134952, items = { [1] = 10001, [5] = 10003, [16] = 2209 }, ignored = {} },
}
local setListHidden = true
C_EquipmentSet = {
  GetEquipmentSetIDs = function()
    local ids = {}
    for id in pairs(sets) do ids[#ids + 1] = id end
    table.sort(ids)
    if setListHidden then ids[#ids + 1] = SECRET end
    return ids
  end,
  GetEquipmentSetInfo = function(id)
    local s = sets[id]
    if not s then return end
    return s.name, s.icon, id, id == 0, 3, 2, 1, 0, 1
  end,
  GetItemIDs = function(id) return sets[id] and sets[id].items end,
  GetIgnoredSlots = function(id) return sets[id] and sets[id].ignored end,
  GetEquipmentSetAssignedSpec = function(id) return sets[id] and sets[id].spec end,
}

-- Talents: a trait tree with two bought nodes, one granted free and one ID hidden; two spec groups.
local talent = { group = 1, staged = false, bought = { [9001] = 1, [9003] = 2 } }
C_SpecializationInfo = {
  GetSpecialization = function() return 1 end,
  GetSpecializationInfo = function() return 1491, "Warrior" end,
  GetActiveSpecGroup = function() return talent.group end,
  GetCombatConfigIDForSpecGroup = function(group) return 100 + group end,
}
C_ClassTalents = { GetActiveConfigID = function() return 100 + talent.group end }
C_Traits = {
  ConfigHasStagedChanges = function() return talent.staged end,
  GetConfigInfo = function(id) return { ID = id, treeIDs = { 790 } } end,
  GetTreeNodes = function() return { 9001, 9002, 9003, 9004, 9005 } end,
  GetNodeInfo = function(_, nodeID)
    if nodeID == 9005 then return { ranksPurchased = 0, activeRank = 1, activeEntry = { entryID = 19005, rank = 1 } } end
    if nodeID == 9002 and talent.secretNode then return SECRET end
    local r = talent.bought[nodeID] or 0
    return { ranksPurchased = r, activeRank = r, activeEntry = r > 0 and { entryID = nodeID + 10000, rank = r } or nil }
  end,
  GenerateImportString = function() return "BcQAAAAAAAAAAAAAAAAAAAAA" .. talent.group end,
}

C_GameRules = { IsHardcoreActive = function() return false end, GetForeverExperiencePreset = function() return 1 end }
C_PlayerInfo = { IsSelfFoundActive = function() return false end }

-- Run ------------------------------------------------------------------------------
local addonTable = {}
for _, file in ipairs({ "Core.lua", "Position.lua", "Events.lua", "Extras.lua", "Moments.lua" }) do
  assert(loadfile(DIR .. file))(ADDON, addonTable)
end

fire("ADDON_LOADED", ADDON)
local firstSessionAt = clock
fire("PLAYER_ENTERING_WORLD", true, false)
advance(8)   -- the opening snapshot

-- out of combat: food, a stranger's blessing, breath, a discovery, a kobold's line
fire("UNIT_AURA", "player", { addedAuras = { { name = "Food", spellId = 433, isHelpful = true, sourceUnit = "player", duration = 18, applications = 0, auraInstanceID = 115 } } })
advance(3)
stat[347] = "2"
fire("CRITERIA_UPDATE")
fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { 115, 999 } })
fire("UNIT_AURA", "player", { addedAuras = { { name = "Blessing of Might", spellId = 19740, isHelpful = true, duration = 3600, applications = 0, auraInstanceID = 133 } } })
-- a buff from a player the game can't name (GetPlayerInfoByGUID answers nothing for them)
fire("UNIT_AURA", "player", { addedAuras = { { name = "Arcane Intellect", spellId = 1459, isHelpful = true, duration = 1800, applications = 0, auraInstanceID = 134 } } })
fire("MIRROR_TIMER_START", "BREATH", 60000, 60000, -1, 0, "Breath")
advance(4)
fire("CHAT_MSG_SYSTEM", "Discovered Crystal Lake: 65 experience gained")
fire("UI_INFO_MESSAGE", 412, "Discovered: Crystal Lake")
fire("UI_INFO_MESSAGE", 412, "Discovered: Jasperlode Mine")
fire("UI_INFO_MESSAGE", 251, "Trade complete.")
fire("MIRROR_TIMER_START", "BREATH", 56065, 60000, 10, 0, "Breath")
fire("MIRROR_TIMER_STOP", "BREATH")
fire("CHAT_MSG_MONSTER_SAY", "Yiieeeee! Me run!", "Kobold Worker")
fire("CHAT_MSG_MONSTER_SAY", "Yiieeeee! Me run!", "Kobold Worker")
fire("CHAT_MSG_MONSTER_YELL", SECRET, SECRET)
-- the player's own /say and /yell: speech is switched off, so nothing may be written
fire("CHAT_MSG_SAY", "Well met!", "Aldwin", "Common", "", "", "", 0, 0, "", 7, 12, "Player-4747-0ABC1234")
fire("CHAT_MSG_YELL", "For the Alliance!", "Aldwin", "Common", "", "", "", 0, 0, "", 7, 13, "Player-4747-0ABC1234")
fire("PLAYER_LEVEL_UP", 6, 17, 0, 0, 0, 1, 0, 1, 0)
fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Reputation with Stormwind increased by 50.")

-- the map opened (the game performs READ as it opens) and closed; then the player's own /read
WorldMapFrame.shown = true
C_ChatInfo.PerformEmote("READ")
WorldMapFrame.shown = false
C_ChatInfo.PerformEmote("READ")

-- the player opens their own profession window: one RECIPES once it has loaded, and none again
-- for an unchanged list; a recipe learned, one more
fire("TRADE_SKILL_SHOW")
window.ready = true
fire("TRADE_SKILL_LIST_UPDATE")
fire("TRADE_SKILL_LIST_UPDATE")
advance(1)
fire("TRADE_SKILL_LIST_UPDATE")
advance(1)
recipes[8617] = true
fire("TRADE_SKILL_LIST_UPDATE")
advance(1)
-- someone else's recipes, linked in chat, and an NPC's: nothing
recipes[19047] = true
window.linked = true
fire("TRADE_SKILL_SHOW")
advance(1)
window.linked, window.npc = false, true
fire("TRADE_SKILL_DATA_SOURCE_CHANGED")
advance(1)
window.npc = false
-- a client without GetAllRecipeIDs: the window's own list, marked as filtered
local allRecipeIDs = C_TradeSkillUI.GetAllRecipeIDs
C_TradeSkillUI.GetAllRecipeIDs = nil
fire("TRADE_SKILL_SHOW")
advance(1)
C_TradeSkillUI.GetAllRecipeIDs = allRecipeIDs
window.ready = false

-- gear sets: a swap announced, two slots changing, the finish; then a set renamed and the
-- other deleted (one GEARSET each), a burst of the change event with nothing changed, and
-- a set with an item the game hid (nothing)
fire("EQUIPMENT_SWAP_PENDING")
advance(0.2)
fire("PLAYER_EQUIPMENT_CHANGED", 5, false)
fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
advance(0.1)
fire("EQUIPMENT_SWAP_FINISHED", true, 1)
fire("EQUIPMENT_SWAP_FINISHED", false, SECRET)
advance(2)
sets[1].name = "Defence"
sets[0] = nil
setListHidden = false
fire("EQUIPMENT_SETS_CHANGED")
fire("EQUIPMENT_SETS_CHANGED")
advance(1)
fire("EQUIPMENT_SETS_CHANGED")
advance(1)
sets[1].items[5] = SECRET
fire("EQUIPMENT_SETS_CHANGED")
advance(1)
sets[1].items[5] = 10003

-- talents: a point staged (nothing written), then applied (one TALENTS); the same tree again
-- (nothing); the other spec group (one more); a node the game hid (read as not bought)
talent.staged, talent.bought[9002] = true, 1
fire("TRAIT_CONFIG_UPDATED", 101)
advance(1)
talent.staged = false
fire("TRAIT_CONFIG_UPDATED", 101)
fire("PLAYER_TALENT_UPDATE")
advance(1)
fire("PLAYER_TALENT_UPDATE")
advance(1)
talent.group = 2
fire("ACTIVE_TALENT_GROUP_CHANGED", 2, 1)
fire("PLAYER_SPECIALIZATION_CHANGED", "player")
advance(1)
talent.secretNode = true
fire("TRAIT_CONFIG_UPDATED", 102)
advance(1)
talent.secretNode = false

-- a fight, with everything hidden while it lasts
inCombat = true
fire("PLAYER_REGEN_DISABLED")
fire("UNIT_AURA", "player", SECRET)
fire("UNIT_AURA", "player", { isFullUpdate = SECRET, addedAuras = SECRET, removedAuraInstanceIDs = SECRET })
fire("UNIT_AURA", "player", { addedAuras = { { name = SECRET, spellId = SECRET, auraInstanceID = SECRET } } })
fire("UNIT_AURA", "player", { isFullUpdate = true })
fire("LOSS_OF_CONTROL_ADDED", "player", 1)
fire("LOSS_OF_CONTROL_ADDED", "targettarget", 1)
-- a piece of gear changed in the fight: the sheet it asks for is hidden until the fight ends
fire("PLAYER_EQUIPMENT_CHANGED", 10, false)
advance(10)
-- the fight leaves a poison on the character, never announced
present.HARMFUL[1] = { name = "Poison", spellId = 11918, isHelpful = false, sourceUnit = "target", duration = 15, applications = 0, auraInstanceID = 140 }
fights[#fights + 1] = { sessionID = 89, name = "Kobold Geomancer", durationSeconds = 24 }
-- the meter hasn't this character's entry yet the instant combat ends: written a second later
meterLate[89] = { at = clock + 0.5, how = "missing" }
inCombat = false
fire("PLAYER_REGEN_ENABLED")
stat[107] = "86"
stat[1336] = "50 (Humanoid)"
advance(3)
-- the kobold's corpse looted (three cloth, through the loot window), then items the game pushed
-- without one, a craft, a refund, a wording no format explains, another player's loot, and an
-- upgraded item whose link carries bonus IDs
lootSlots = { { link = "|cff9d9d9d|Hitem:2589::::::::1:::::::|h[Linen Cloth]|h|r", guid = "Creature-0-4621-0-46196-476-0000BCECFD" } }
fire("LOOT_OPENED")
fire("CHAT_MSG_LOOT", "You receive loot: |cff9d9d9d|Hitem:2589::::::::1:::::::|h[Linen Cloth]|h|rx3.", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-4747-0ABC1234")
fire("CHAT_MSG_LOOT", "You receive item: |cffffffff|Hitem:6948::::::::1:::::::|h[Hearthstone]|h|r.", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-4747-0ABC1234")
fire("CHAT_MSG_LOOT", "You create: |cffffffff|Hitem:2581::::::::1:::::::|h[Heavy Linen Bandage]|h|rx2.", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-4747-0ABC1234")
fire("CHAT_MSG_LOOT", "You are refunded: |cffffffff|Hitem:1234::::::::1:::::::|h[Returned Thing]|h|r.", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-4747-0ABC1234")
fire("CHAT_MSG_LOOT", "You find: |cffffffff|Hitem:999::::::::1:::::::|h[Odd Thing]|h|r.", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-4747-0ABC1234")
fire("CHAT_MSG_LOOT", "Someone receives loot: |cffffffff|Hitem:4321::::::::1:::::::|h[Their Thing]|h|r.", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-4747-0BBBBBBB")
fire("CHAT_MSG_LOOT", "You receive item: |cffa335ee|Hitem:268213::::::::80:577::6:5:6652:10353:10254:1527:10255::::::|h[Upgraded Blade]|h|r.", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-4747-0ABC1234")
advance(1)
-- the poison runs out; then the game resends the whole set with new instance numbers
present.HARMFUL[1] = nil
fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { 140 } })
present.HELPFUL[1].auraInstanceID = 211
fire("UNIT_AURA", "player", { isFullUpdate = true })

-- a fight followed at once by another: the first is written the instant its combat ends
inCombat = true
fire("PLAYER_REGEN_DISABLED")
fights[#fights + 1] = { sessionID = 90, name = "Timber Wolf", durationSeconds = 5 }
inCombat = false
fire("PLAYER_REGEN_ENABLED")
inCombat = true
fire("PLAYER_REGEN_DISABLED")
advance(3)
fights[#fights + 1] = { sessionID = 91, name = "Timber Wolf", durationSeconds = 9 }

-- death in that fight, announced in chat first
fire("MIRROR_TIMER_STOP", "EXHAUSTION")
fire("MIRROR_TIMER_STOP", "BREATH")
fire("CHAT_MSG_SYSTEM", "|cff71d5ff|Hdeath:2|h[You died.]|h")
fire("PLAYER_DEAD")
fire("PLAYER_DEAD")
-- the meter still hides this fight's amounts the instant combat ends: written a second later
meterLate[91] = { at = clock + 0.5, how = "secret" }
inCombat = false
fire("PLAYER_REGEN_ENABLED")
stat[60] = "2"
fire("CRITERIA_UPDATE")
advance(3)
fire("PLAYER_UNGHOST")

-- the meter carries session 91 on through a lull: another span of combat begins within a
-- moment, and at its end the same session reports a longer duration and more damage, so it is
-- written again (here its amounts are still hidden at the instant, so by the read a second
-- later); a span that ends with the session unchanged but for the meter's clock writes nothing
inCombat = true
fire("PLAYER_REGEN_DISABLED")
advance(2)
meterDuration, meterTotal = 40, 300
meterLate[91] = { at = clock + 0.5, how = "secret" }
inCombat = false
fire("PLAYER_REGEN_ENABLED")
advance(2)
inCombat = true
fire("PLAYER_REGEN_DISABLED")
advance(2)
inCombat = false
fire("PLAYER_REGEN_ENABLED")
meterDuration = 41
advance(2)
meterDuration, meterTotal = 24, 181

-- a fight whole the instant it ends, the meter's clock ticking on a second later: one line, at once
inCombat = true
fire("PLAYER_REGEN_DISABLED")
advance(2)
fights[#fights + 1] = { sessionID = 92, name = "Mottled Boar", durationSeconds = 9 }
inCombat = false
fire("PLAYER_REGEN_ENABLED")
meterDuration = 25
advance(2)
meterDuration = 24

-- a death with no chat link and only an old recap on file: nothing may be written for it
recapStale = true
fire("PLAYER_DEAD")
fire("PLAYER_UNGHOST")
recapStale = false

-- a boss: the game hides whether the character is away for as long as it lasts
afkHidden = true
advance(3)
afkHidden = false
advance(2)

-- a quest's disguise comes off: the event fires for the head while the slot is empty, and the
-- helm goes back on with no event of its own; the re-read a second later writes it. Then a ring
-- changed twice within the second: one re-read, which finds what was written and adds nothing
fire("PLAYER_EQUIPMENT_CHANGED", 1, true)
advance(0.2)
inventory[1] = 10001
advance(2)
inventory[11] = 2001
fire("PLAYER_EQUIPMENT_CHANGED", 11, false)
advance(0.5)
inventory[11] = 2002
fire("PLAYER_EQUIPMENT_CHANGED", 11, false)
advance(2)

-- a loading screen across the five-minute mark: the periodic lines wait for its end
local loadingFrom = firstSessionAt + addonTable.TIMER_PERIOD - 2.5
local loadingTo = loadingFrom + 5
advance(loadingFrom - clock)
fire("LOADING_SCREEN_ENABLED")
advance(loadingTo - clock)
fire("PLAYER_ENTERING_WORLD", false, false)
fire("LOADING_SCREEN_DISABLED")
advance(3)

-- pause and resume: a fresh baseline
SlashCmdList.WIDSITH("pause")
SlashCmdList.WIDSITH("resume")
advance(8)

-- a session whose opening aura read the game refuses although C_Secrets said nothing was
-- hidden: no AURA lines, no ERR, and the rest of the opening kept
SlashCmdList.WIDSITH("pause")
local refusedBeforeUnforeseen = auraRefusals
refuseUnforeseen = true
SlashCmdList.WIDSITH("resume")
advance(8)
refuseUnforeseen = false
local refusedUnforeseen = auraRefusals - refusedBeforeUnforeseen

-- a session that opens in the middle of a fight: the game refuses aura reads, so the opening
-- has no AURA lines and no ERR; they come a second after the fight ends. One aura's spell is
-- always hidden and is never written.
SlashCmdList.WIDSITH("pause")
present.HELPFUL[2] = { name = "Hidden", spellId = 99999, isHelpful = true, duration = 0, applications = 0, auraInstanceID = 250, alwaysHidden = true }
present.HELPFUL[3] = { name = "Blessing of Kings", spellId = 20217, isHelpful = true, duration = 3600, applications = 0, auraInstanceID = 251 }
inCombat = true
SlashCmdList.WIDSITH("resume")
advance(8)
inCombat = false
fire("PLAYER_REGEN_ENABLED")
advance(3)
-- an encounter's restriction on a client that can't be asked first: the read itself is refused
local secrets = C_Secrets
C_Secrets = nil
encounter = true
local refusedBefore = auraRefusals
fire("UNIT_AURA", "player", { isFullUpdate = true })
fire("UNIT_AURA", "player", { addedAuras = { { name = "Renew", spellId = 139, isHelpful = true, duration = 15, applications = 0, auraInstanceID = 260 } } })
local refusedInEncounter = auraRefusals - refusedBefore
C_Secrets = secrets
encounter = false
fire("PLAYER_LOGOUT")

-- What the session that opened in a fight must hold, checked line by line.
local function expect(ok, what) if not ok then realPrint("-- expect FAIL: " .. what) end end
local last = WidsithDB.sessions[#WidsithDB.sessions]
local seen, beforeLeave, afterLeave, left = {}, {}, {}, false
for line in (table.concat(last.chunks, "\n") .. "\n"):gmatch("([^\n]*)\n") do
  local kind, rest = line:match("^%d+\t([^\t]+)\t?(.*)$")
  if kind then
    seen[kind] = true
    local bucket = left and afterLeave or beforeLeave
    bucket[#bucket + 1] = kind .. " " .. rest:gsub("\t", " ")
    if kind == "COMBAT" and rest == "leave" then left = true end
    expect(not rest:find("99999", 1, true), "an always-hidden aura was written: " .. line)
  end
end
local function has(list, prefix)
  for _, l in ipairs(list) do if l:sub(1, #prefix) == prefix then return true end end
  return false
end
expect(has(beforeLeave, "COMBAT enter"), "the session opened in combat without a COMBAT enter")
expect(not has(beforeLeave, "AURA"), "an AURA line was written while the game was hiding auras")
expect(has(beforeLeave, "RULES") and has(beforeLeave, "TALLY") and has(beforeLeave, "REP"),
  "the opening snapshot lost its other lines when auras were refused")
expect(has(afterLeave, "AURA has 6673") and has(afterLeave, "AURA has 20217"),
  "the auras weren't read a second after the fight that the session opened in")
expect(refusedInEncounter > 0, "the stand-in never refused a read, so the guard went untested")
expect(has(afterLeave, "AURA gain 139"), "an announced aura went unwritten when its caster couldn't be read")
expect(not has(beforeLeave, "STATS") and has(afterLeave, "STATS"),
  "the sheet of a session that opened in a fight should be written after the fight, not hidden inside it")
expect(not seen.ERR, "a refused aura read was written as ERR")
local framesWithReads = 0
for _ in pairs(statFrames) do framesWithReads = framesWithReads + 1 end
expect(framesWithReads >= 4, "the counters were read in " .. framesWithReads .. " frames: a pass should be spread across frames")
expect(byIDReads > 0, "no counter was read by ID: every pass after the first should be")

-- Session 1: the currencies at the opening, each fight's line and when, the emotes.
local function lines(session)
  local out = {}
  for line in (table.concat(session.chunks, "\n") .. "\n"):gmatch("([^\n]*)\n") do
    local t, kind, rest = line:match("^(%d+)\t([^\t]+)\t?(.*)$")
    if t then out[#out + 1] = { t = tonumber(t), kind = kind, fields = rest } end
  end
  return out
end
local first = lines(WidsithDB.sessions[1])
local currencies, fightAfterLeave, fightCount, reads, leaveT = {}, {}, {}, 0, nil
local fightLastDuration, fightLastAfter = {}, {}
for _, l in ipairs(first) do
  if l.kind == "CURRENCY" then currencies[#currencies + 1] = l.fields end
  if l.kind == "COMBAT" and l.fields == "enter" then leaveT = nil end
  if l.kind == "COMBAT" and l.fields == "leave" then leaveT = l.t end
  if l.kind == "FIGHT" then
    local id, duration = l.fields:match("^(%d+)\t(%d+)")
    fightCount[id] = (fightCount[id] or 0) + 1
    -- The first line's timing, and the last line's duration, for a session written more than once.
    if not fightAfterLeave[id] then fightAfterLeave[id] = leaveT and (l.t - leaveT) or -1 end
    fightLastDuration[id] = tonumber(duration)
    fightLastAfter[id] = leaveT and (l.t - leaveT) or -1
  end
  if l.kind == "EMOTE" and l.fields == "READ" then reads = reads + 1 end
end
expect(#currencies == 2 and currencies[1] == "3498\t12\t\t\t" and currencies[2] == "3500\t0\t\t\t",
  "the opening CURRENCY lines aren't the two listed currencies with plain amounts and no change: "
  .. table.concat(currencies, " / "):gsub("\t", " "))
expect(currencyExpanded == 0, "the recorder expanded the player's currency list")
expect(fightAfterLeave["89"] == 1000, "a fight whose meter wasn't whole at once wasn't written a second later")
expect(fightAfterLeave["90"] == 0, "a fight followed at once by another wasn't written as its combat ended")
expect(fightAfterLeave["91"] == 1000, "a fight whose amounts were still hidden at once wasn't written a second later")
for id, n in pairs(fightCount) do
  expect(n == (id == "91" and 2 or 1), "the meter's session " .. id .. " was written " .. n .. " times")
end
expect(fightAfterLeave["92"] == 0 and fightCount["92"] == 1,
  "a fight written whole at the instant was written again a second later, when only the meter's clock had moved on: "
  .. tostring(fightCount["92"]) .. " lines")
expect(fightLastDuration["91"] == 40 and fightLastAfter["91"] == 1000,
  "a session the meter carried on through another span of combat wasn't written again, a second after that span's end, with its grown duration: "
  .. tostring(fightLastDuration["91"]) .. " s, " .. tostring(fightLastAfter["91"]) .. " ms after leave")
expect(reads == 1, "READ written " .. reads .. " times: the map's own should be left out, the player's kept")
expect(WidsithDB.character.name == "Aldwin" and WidsithDB.character.surname == "Thornby",
  "the character table doesn't hold the first name and the surname apart: "
  .. tostring(WidsithDB.character.name) .. " / " .. tostring(WidsithDB.character.surname))

-- Session 1 again: the hidden afk flag, the disguise's re-read, the loading screen.
local function split(fields)
  local out = {}
  for f in (fields .. "\t"):gmatch("([^\t]*)\t") do out[#out + 1] = f end
  return out
end
local afkHiddenSeen, afkBack, stateShape = false, false, true
local equipLines = {}
local screenFromMs, screenToMs = (loadingFrom - firstSessionAt) * 1000, (loadingTo - firstSessionAt) * 1000
local snapsInScreen, snapAfterScreen = 0, nil
for _, l in ipairs(first) do
  if l.kind == "STATE" then
    local f = split(l.fields)
    if #f ~= 8 then stateShape = false end
    if f[7] == "" then afkHiddenSeen = true elseif afkHiddenSeen and f[7] == "0" then afkBack = true end
  end
  if l.kind == "EQUIP" then
    local slot, item = l.fields:match("^(%d+)\t?(.*)$")
    equipLines[slot] = equipLines[slot] or {}
    table.insert(equipLines[slot], { t = l.t, item = item })
  end
  if l.kind == "SNAP" then
    if l.t >= screenFromMs and l.t <= screenToMs then snapsInScreen = snapsInScreen + 1 end
    if l.t > screenToMs and not snapAfterScreen then snapAfterScreen = l.t - screenToMs end
  end
end
expect(stateShape, "a STATE line hasn't its eight fields")
expect(afkHiddenSeen, "no STATE line with an empty afk field while the game hid the flag")
expect(afkBack, "no STATE line when the hidden afk flag could be read again")
local head, ring, weapon = equipLines["1"] or {}, equipLines["11"] or {}, equipLines["16"] or {}
expect(#head == 2 and head[1].item == "" and head[2].item == "10001" and math.abs(head[2].t - head[1].t - 1000) <= 1,
  "a slot read empty at its event and filled a second later wasn't written again by the re-read: "
  .. #head .. " EQUIP lines for the head")
expect(#ring == 2, "a slot changed twice within the second wrote " .. #ring .. " EQUIP lines, not one for each event")
expect(#weapon == 1, "a slot that read the same a second later wrote " .. #weapon .. " EQUIP lines, not one")
expect(snapsInScreen == 0, "a SNAP was written while a loading screen was up")
expect(snapAfterScreen ~= nil and snapAfterScreen <= 1000,
  "the SNAP held back by a loading screen wasn't written at the first tick after it: "
  .. tostring(snapAfterScreen) .. " ms after the screen")

local refused = lines(WidsithDB.sessions[3])
local refusedKinds = {}
for _, l in ipairs(refused) do refusedKinds[l.kind] = true end
expect(refusedUnforeseen > 0, "the stand-in never refused the opening aura read")
expect(not refusedKinds.AURA and not refusedKinds.ERR, "an opening aura read refused unforeseen wrote AURA or ERR")
expect(refusedKinds.RULES and refusedKinds.TALLY and refusedKinds.CURRENCY,
  "the opening lost its other lines when the aura read was refused")

-- Other players are named: a recap's hit from a player carries their GUID in full and the
-- recap's name for them, an aura they cast carries their GUID and the name the game gives, and
-- a caster the game can't name has the GUID alone. The word Player is never written.
local recapNamed, blessingNamed, intellectUnnamed, wordPlayer = false, false, false, false
for _, session in ipairs(WidsithDB.sessions) do
  for line in (table.concat(session.chunks, "\n") .. "\n"):gmatch("([^\n]*)\n") do
    local f = {}
    for v in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = v end
    if f[2] == "RECAP" and f[13] == "Player-4747-0BBBBBBB" and f[16] == "Someone" then recapNamed = true end
    if f[2] == "AURA" and f[4] == "19740" and f[10] == "Player-4747-0BBBBBBB" and f[11] == "Someone" then blessingNamed = true end
    if f[2] == "AURA" and f[4] == "1459" and f[10] == "Player-4747-0ABC1234" and (f[11] or "") == "" then intellectUnnamed = true end
    if (f[2] == "AURA" and f[10] == "Player") or (f[2] == "RECAP" and f[13] == "Player") then wordPlayer = true end
  end
end
-- The sheet is never written while the game hides part of it: no STATS inside a fight in any
-- session, and the one a gear change asked for in a fight follows that fight within a second.
local statsInFight, statsOwedWritten, statsLines = false, false, 0
for _, session in ipairs(WidsithDB.sessions) do
  local fighting, leftAt = false, nil
  for line in (table.concat(session.chunks, "\n") .. "\n"):gmatch("([^\n]*)\n") do
    local t, kind, rest = line:match("^(%d+)\t([^\t]+)\t?(.*)$")
    if kind == "COMBAT" then
      fighting = rest == "enter"
      if not fighting then leftAt = tonumber(t) end
    elseif kind == "STATS" then
      statsLines = statsLines + 1
      if fighting then statsInFight = true end
      if leftAt and tonumber(t) - leftAt <= 1500 then statsOwedWritten = true end
    end
  end
end
expect(statsLines > 0, "no STATS line was written at all")
expect(not statsInFight, "a STATS line was written while the game hid the sheet")
expect(statsOwedWritten, "the sheet a fight hid wasn't written in the second after it")
-- A session's opening line says how big the file was before it: a number, never smaller than
-- the one before.
local sizeFields, sizesInOrder = 0, true
for i, session in ipairs(WidsithDB.sessions) do
  local first = (table.concat(session.chunks, "\n") .. "\n"):match("([^\n]*)\n")
  local f = {}
  for v in (first .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = v end
  local bytes = f[2] == "SESSION" and tonumber(f[14]) or nil
  if bytes then
    sizeFields = sizeFields + 1
    if sizeFields > 1 and bytes < (WidsithDB.sessions[i - 1].sizeSeen or 0) then sizesInOrder = false end
    session.sizeSeen = bytes
  end
end
expect(sizeFields == #WidsithDB.sessions and sizesInOrder, "a SESSION line doesn't say what the file held before it, or the sizes don't grow")
-- Loot lines say which message they came from, by the client's own formats, with the count and
-- the item as linked; a wording no format explains keeps the kind empty; another player's loot
-- is never written.
local lootByItem = {}
for _, session in ipairs(WidsithDB.sessions) do
  for line in (table.concat(session.chunks, "\n") .. "\n"):gmatch("([^\n]*)\n") do
    local f = {}
    for v in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = v end
    if f[2] == "LOOT" then lootByItem[f[3]] = f end
  end
end
local function lootIs(item, qty, source, kind, itemString)
  local f = lootByItem[item]
  return f ~= nil and f[4] == qty and (f[5] or "") == source and (f[7] or "") == kind and (f[8] or "") == itemString
end
expect(lootIs("2589", "3", "Creature-0-4621-0-46196-476-0000BCECFD", "loot", "item:2589::::::::1:::::::"),
  "corpse loot wasn't written as kind loot with its count, source and item string")
expect(lootIs("6948", "1", "", "item", "item:6948::::::::1:::::::"), "a pushed item wasn't written as kind item")
expect(lootIs("2581", "2", "", "create", "item:2581::::::::1:::::::"), "a craft wasn't written as kind create with its count")
expect(lootIs("1234", "1", "", "refund", "item:1234::::::::1:::::::"), "a refund wasn't written as kind refund")
expect(lootIs("999", "1", "", "", "item:999::::::::1:::::::"), "a wording no format explains wasn't written with its kind empty")
expect(lootByItem["4321"] == nil, "another player's loot was written")
expect(lootIs("268213", "1", "", "item", "item:268213::::::::80:577::6:5:6652:10353:10254:1527:10255::::::"),
  "an upgraded item's link wasn't kept whole")
expect(recapNamed, "a recap's hit from a player wasn't written with their GUID and the recap's name")
expect(blessingNamed, "an aura cast by a player wasn't written with their GUID and name")
expect(intellectUnnamed, "an aura whose caster the game can't name wasn't written with the GUID alone")
expect(not wordPlayer, "the word Player was written for a caster or a recap's source")

local NEW = { FIGHT = true, RECAP = true, AURA = true, CC = true, MIRROR = true, DISCOVER = true, TALLY = true, NPCSAY = true, RULES = true,
  LEVEL = true, DEATH = true, COMBAT = true, SESSION = true, END = true, ERR = true, REP = true, SPEECH = true, RECIPES = true,
  GEARSET = true, GEARSWAP = true, TALENTS = true, EQUIP = true, SPEC = true, CURRENCY = true, EMOTE = true }
local kinds = {}
for s, session in ipairs(WidsithDB.sessions) do
  realPrint("== session " .. s .. " ==")
  for line in (table.concat(session.chunks, "\n") .. "\n"):gmatch("([^\n]*)\n") do
    local kind = line:match("^%d+\t([^\t]+)")
    kinds[kind] = (kinds[kind] or 0) + 1
    if NEW[kind] then realPrint((line:gsub("\t", " | "))) end
  end
end
local parts = {}
for kind, n in pairs(kinds) do parts[#parts + 1] = kind .. "=" .. n end
table.sort(parts)
realPrint("-- " .. table.concat(parts, " "))
for _, line in ipairs(chat) do
  if line:find("Problem") or line:find("error") then realPrint("-- chat: " .. line) end
end
