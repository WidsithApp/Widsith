-- A stand-in for the game client, so the addon can be run outside the game.
--
-- newGame(profile) builds a game: a fresh environment holding the globals the
-- addon reads, a clock, timers, frames, and a world the test changes by name
-- (game.world.money, game.world.combat, …). game.login() loads the addon into
-- it the way the game does; game.reload() writes the saved variables out and
-- loads it again, as a reload does. Every game is its own: nothing leaks from
-- one test to the next.
--
-- The stubs answer only what the game was seen to answer, on the builds named
-- in the profiles below, and nothing more. A green run means the addon still
-- does what the game was last seen to do. When a recording or the probe shows
-- the game answering differently, the stub changes with the fix.
--
-- Secret values are objects that raise an error on any use, so a missing secret
-- check shows as an ERR line, or as a failure to write the saved file (a secret
-- in SavedVariables breaks the save in the real game; here it fails the reload).
-- An aura read under restrictions raises the game's own error, as the game does.
--
-- Nothing here renders. A frame keeps what it was told (shown, alpha, size,
-- points, text, textures, scripts), so a test can read what the player is told
-- and press what they could press, never how it looks.

local ADDON = "Widsith"
local ADDON_FILES = { "Core.lua", "Position.lua", "Events.lua", "Extras.lua", "Moments.lua", "Screenshots.lua", "Save.lua", "Options.lua", "Welcome.lua" }

-- The two clients, as they were seen. Each key is one fact the stubs answer by.
local PROFILES = {
  forever = {
    label = "forever",
    version = "1.60.1", build = "70790", interface = 16001, project = 18, expansion = 0,
    realm = "CAMWOW US1 Realm 3 PvE", realmN = "CAMWOWUS1Realm3PvE", region = 1,
    surname = "Thornby",           -- every character has one; UnitName gives it
    dayTime = true,                -- C_DateAndTime.IsDayTime and DIEL_CYCLE_CHANGED exist
    diel = true,                   -- the minimap's day/night dial and its ring atlas
    missingEvents = {},
    -- /widsith check on 1.60.1 build 70840 named the old GetSpecialization global alone, no
    -- missing message and no missing event; pet battles and the stable are there.
    absent = { "GetSpecialization" },
  },
  retail = {
    label = "retail",
    version = "12.1.5", build = "70575", interface = 120105, project = 1, expansion = 11,
    realm = "Whitemane", realmN = "Whitemane", region = 1,
    surname = nil,
    dayTime = false,
    diel = false,                  -- the classic minimap button ring
    missingEvents = { DIEL_CYCLE_CHANGED = true },
    -- /widsith check on 12.1.5 build 70783 named these nine, in this order, and the one event.
    absent = { "C_SkillInfo.GetSkillLineInfo", "C_SkillInfo.GetSkillLineInfoByID", "UnitDefenseSkill",
      "C_GameRules.IsHardcoreActive", "C_GameRules.GetForeverExperiencePreset",
      "C_SpecializationInfo.GetCombatConfigIDForSpecGroup", "C_DateAndTime.IsDayTime",
      "C_StableInfo.BuyStableSlot", "C_StableInfo.GetNextStableSlotCost" },
  },
}
-- `absent` names what each client lacks of what the recorder uses, as a function's path: a global
-- or namespace.name. The stubs define every one of them, and the ones a profile names are taken
-- out after the environment is built, so a namespace stays while a call in it goes, as in the game.

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

local nothing = function() end
local emptyNamespace = setmetatable({}, { __index = function() return nothing end })

local function copyTable(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

---------------------------------------------------------------------------
-- The world: what the stubs answer from. Each value is one the game was seen to give.
---------------------------------------------------------------------------

local function newWorld(profile)
  local w = {}
  w.combat = false
  w.encounter = false          -- an encounter's restriction on aura reads
  w.refuseUnforeseen = false   -- every aura read refused while C_Secrets says nothing is hidden
  w.afkHidden = false
  w.notLoaded = false          -- the client still loading the character: xp and money read 0
  w.xp, w.xpMax, w.level = 100, 2800, 5
  w.money = 334
  w.grouped = false
  w.npcGUID = nil
  w.resting, w.instance, w.taxi, w.dead = false, false, false, false
  w.hardcore = false
  w.chatLockdown = false
  w.mapShown = false
  w.position = nil             -- mapID the recorder's currentPosition answers, when a test sets it
  w.inventory = { [6] = 3001, [7] = 3002, [8] = 3003 }
  w.durability = { [6] = { 30, 40 }, [7] = { 0, 50 }, [8] = { 12, 60 } }
  w.durabilityReads = 0
  w.weather = { type = 1, intensity = 0.5 }
  w.daytime = true
  w.lootSlots = {}
  w.merchantOpen = false
  w.sendMoney = 0
  w.inbox = {}
  w.questLog = { { questID = 200, title = "An Old Errand", ready = true, level = 2,
    objectives = { { numFulfilled = 1, numRequired = 1, type = "item", text = "Old Letter" } } } }
  w.fights = { { sessionID = 88, name = "Kobold Vermin", durationSeconds = 7 } }
  w.meterLate = {}             -- [sessionID] = { at = clock, how = "missing" | "secret" }
  w.meterDuration = 24
  w.meterTotal = 181
  w.recapStale = false
  w.present = { HELPFUL = { { name = "Battle Shout", spellId = 6673, isHelpful = true, sourceUnit = "player", duration = 120, applications = 0, auraInstanceID = 11 } }, HARMFUL = {} }
  w.auraRefusals = 0
  w.stat = { [107] = "85", [108] = "4", [60] = "1", [347] = "1", [328] = "4|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t 62", [114] = "--", [1336] = "49 (Humanoid)" }
  w.statNames = { [107] = "Creatures killed", [108] = "Critters killed", [60] = "Total deaths", [347] = "Food eaten", [328] = "Total gold acquired",
    [114] = "Deaths from falling", [1336] = "Creature type killed the most" }
  w.statOrder = { 107, 108, 60, 347, 328, 114, 1336 }
  w.statFrames = {}            -- the rendered frames in which a counter was read
  w.byIDReads = 0
  w.pane = {
    { factionID = 469, name = "Alliance", isHeader = true, isHeaderWithRep = false, reaction = 4, currentStanding = 0 },
    { factionID = 72, name = "Stormwind", isHeader = false, isHeaderWithRep = false, reaction = 5, currentStanding = 3150 },
    { factionID = 47, name = "Ironforge", isHeader = false, isHeaderWithRep = false, reaction = 4, currentStanding = 0 },
    { factionID = 1134, name = "Gilneas", isHeader = true, isHeaderWithRep = true, reaction = 6, currentStanding = 9500 },
    { factionID = SECRET, name = SECRET, isHeader = false, isHeaderWithRep = false, reaction = SECRET, currentStanding = SECRET },
    { factionID = 72, name = "Stormwind", isHeader = false, isHeaderWithRep = false, reaction = 5, currentStanding = 3150 },
  }
  w.currencyList = {
    { name = "Miscellaneous", currencyID = 0, isHeader = true, isHeaderExpanded = true, currencyListDepth = 0, quantity = 0 },
    { name = "Valor Mark", currencyID = 3498, isHeader = false, currencyListDepth = 1, quantity = 12, maxQuantity = 0, totalEarned = 12, discovered = true },
    { name = SECRET, currencyID = 3499, isHeader = false, currencyListDepth = 1, quantity = SECRET, maxQuantity = 0, discovered = true },
    { name = "Legacy", currencyID = 0, isHeader = true, isHeaderExpanded = false, currencyListDepth = 0, quantity = 0 },
    { name = "Player vs. Player", currencyID = 0, isHeader = true, isHeaderExpanded = true, currencyListDepth = 0, quantity = 0 },
    { name = "Honor Token", currencyID = 3500, isHeader = false, currencyListDepth = 1, quantity = 0, maxQuantity = 75, discovered = true },
  }
  w.currencyExpanded = 0
  w.window = { ready = false, linked = false, npc = false }   -- a profession window
  w.recipes = { [8613] = true, [8617] = false, [10662] = true, [19047] = false }
  w.sets = {
    [0] = { name = "Questing", icon = 132347, items = { [1] = 10001, [5] = 10002, [16] = 25 }, ignored = { [4] = true, [19] = SECRET }, spec = 1 },
    [1] = { name = "Tank", icon = 134952, items = { [1] = 10001, [5] = 10003, [16] = 2209 }, ignored = {} },
  }
  w.setListHidden = true
  w.talent = { group = 1, staged = false, bought = { [9001] = 1, [9003] = 2 } }
  w.maps = {
    [30] = { mapType = 3, parentMapID = 13 }, [55] = { mapType = 5, parentMapID = 52 }, [52] = { mapType = 3, parentMapID = 13 },
    [13] = { mapType = 2, parentMapID = 0 }, [40] = { mapType = 3, parentMapID = 13 },
    [41] = { mapType = 3, parentMapID = 13 }, [42] = { mapType = 3, parentMapID = 13 },
  }
  w.shotAnswer = "SCREENSHOT_SUCCEEDED"   -- what the game says after Screenshot(); nil says nothing
  w.shotsTaken, w.chatAtShot, w.friendsAtShot = 0, nil, nil
  w.cursor = { 1300, 700 }
  w.screen = { 1280, 768 }
  return w
end

---------------------------------------------------------------------------
-- Widgets: frames, textures, font strings and animations, as objects that keep
-- what they were told. Any method not listed answers nothing.
---------------------------------------------------------------------------

local Widget = {}
-- A method the game's frames have and this list doesn't answers nothing; a field (lowercase,
-- or one of the game's own named children) that was never set answers nil, as the game's would.
local FRAME_FIELDS = { DielFrame = true }
Widget.__index = function(_, key)
  local method = rawget(Widget, key)
  if method then return method end
  if type(key) == "string" and key:find("^%u") and not FRAME_FIELDS[key] then return nothing end
  return nil
end

function Widget:RegisterEvent(event)
  if self.game.profile.missingEvents[event] then error('Attempt to register unknown event "' .. event .. '"') end
  self.events[event] = true
end
function Widget:RegisterUnitEvent(event, unit)
  if self.game.profile.missingEvents[event] then error('Attempt to register unknown event "' .. event .. '"') end
  self.events[event] = unit
end
function Widget:UnregisterEvent(event) self.events[event] = nil end
function Widget:SetScript(name, fn) self.scripts[name] = fn end
function Widget:GetScript(name) return self.scripts[name] end
function Widget:HookScript(name, fn)
  local before = self.scripts[name]
  self.scripts[name] = function(...) if before then before(...) end fn(...) end
end
function Widget:Show() self.shown = true end
function Widget:Hide() self.shown = false end
function Widget:SetShown(shown) self.shown = shown and true or false end
function Widget:IsShown() return self.shown end
function Widget:IsVisible()
  local f = self
  while f do
    if not f.shown then return false end
    f = f.parent
  end
  return true
end
function Widget:SetAlpha(a) self.alpha = a end
function Widget:GetAlpha() return self.alpha end
function Widget:SetScale(s) self.scale = s end
function Widget:GetScale() return self.scale end
function Widget:GetEffectiveScale()
  local s, f = 1, self
  while f do s = s * (f.scale or 1) f = f.parent end
  return s
end
function Widget:SetParent(parent) self.parent = parent end
function Widget:GetParent() return self.parent end
function Widget:GetName() return self.name end
function Widget:GetObjectType() return self.kind end
function Widget:SetSize(w, h) self.width, self.height = w, h end
function Widget:SetWidth(w) self.width = w end
function Widget:SetHeight(h) self.height = h end
function Widget:GetWidth() return self.width end
function Widget:GetHeight() return self.height end
function Widget:GetSize() return self.width, self.height end
function Widget:SetPoint(point, relativeTo, relativePoint, x, y)
  -- The short forms the game allows: SetPoint(point), SetPoint(point, x, y), SetPoint(point, frame, point).
  if type(relativeTo) == "number" then relativeTo, relativePoint, x, y = nil, nil, relativeTo, relativePoint end
  if type(relativePoint) == "number" then x, y, relativePoint = relativePoint, x, nil end
  self.points[#self.points + 1] = { point, relativeTo, relativePoint or point, x or 0, y or 0 }
end
function Widget:SetAllPoints(frame) self.points[#self.points + 1] = { "ALL", frame or self.parent, "ALL", 0, 0 } end
function Widget:ClearAllPoints() self.points = {} end
function Widget:GetNumPoints() return #self.points end
function Widget:GetPoint(i)
  local p = self.points[i or 1]
  if p then return p[1], p[2], p[3], p[4], p[5] end
end
-- A frame's centre on screen: the one it was given, else its first anchor's frame's centre plus
-- the offset (in the frame's own units), else its parent's.
function Widget:GetCenter()
  if self.center then return self.center[1], self.center[2] end
  local p = self.points[1]
  if p and type(p[2]) == "table" and p[2].GetCenter then
    local x, y = p[2]:GetCenter()
    if x then return x + p[4], y + p[5] end
  end
  if self.parent then return self.parent:GetCenter() end
end
function Widget:SetFrameStrata(s) self.strata = s end
function Widget:GetFrameStrata() return self.strata end
function Widget:SetFrameLevel(l) self.level = l end
function Widget:GetFrameLevel() return self.level end
function Widget:IsMouseOver() return self.mouseOver == true end
function Widget:SetText(text) self.text = text end
function Widget:GetText() return self.text end
function Widget:GetStringHeight() return 12 end
function Widget:GetStringWidth() return 8 * #(self.text or "") end
function Widget:SetTexture(path) self.texture = path end
function Widget:SetAtlas(name) self.atlas = name end
function Widget:SetTexCoord(...) self.texCoord = { ... } end
function Widget:SetVertexColor(r, g, b) self.color = { r, g, b } end
function Widget:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function Widget:SetBackdrop(b) self.backdrop = b end
function Widget:Play() self.playing = true end
function Widget:Stop() self.playing = false end
function Widget:IsPlaying() return self.playing == true end
function Widget:SetLooping(l) self.looping = l end

local function newWidget(game, kind, name, parent)
  local w = setmetatable({ game = game, kind = kind, name = name, parent = parent, shown = true, alpha = 1,
    scale = 1, width = 0, height = 0, points = {}, scripts = {}, events = {}, strata = "MEDIUM", level = 1,
    regions = {}, children = {} }, Widget)
  if parent and parent.children then parent.children[#parent.children + 1] = w end
  if name and name ~= "" then game.G[name] = w end
  return w
end

function Widget:CreateTexture(name, layer, template, subLevel)
  local t = newWidget(self.game, "Texture", name, self)
  t.layer, t.subLevel = layer, subLevel
  self.regions[#self.regions + 1] = t
  return t
end
function Widget:CreateFontString(name, layer, template)
  local s = newWidget(self.game, "FontString", name, self)
  s.layer, s.template = layer, template
  self.regions[#self.regions + 1] = s
  return s
end
function Widget:CreateAnimationGroup(name)
  local g = newWidget(self.game, "AnimationGroup", name, self)
  g.animations = {}
  return g
end
function Widget:CreateAnimation(kind)
  local a = newWidget(self.game, kind or "Animation", nil, self)
  self.animations[#self.animations + 1] = a
  return a
end

---------------------------------------------------------------------------
-- The game
---------------------------------------------------------------------------

-- dir: the addon's folder, with its trailing separator. version: what the TOC says, which the
-- game would answer from it (the runner reads it, since this Lua can't open files).
local function newGame(profileName, dir, version)
  local profile = PROFILES[profileName]
  assert(profile, "no such client profile: " .. tostring(profileName))
  local game = { profile = profile, dir = dir, version = version or "0.0.0", chat = {}, sent = {}, written = {}, clock = 5000, loads = 0 }
  local world = newWorld(profile)
  game.world = world
  game.SECRET = SECRET
  game.character = { name = "Aldwin", surname = profile.surname, guid = "Player-4747-0ABC1234" }
  local realPrint = print
  local frames, timers = {}, {}
  local frameNo = 0
  local profileMs = 0
  local addonTable
  local G

  ---------------------------------------------------------------------------
  -- Time: a clock, rendered frames, and timers that fire in order
  ---------------------------------------------------------------------------

  local function render(n)
    for _ = 1, n do
      frameNo = frameNo + 1
      for _, f in ipairs(frames) do
        if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.016) end
      end
    end
  end
  game.render = render

  -- The game promises nothing about the order frames hear an event in, and has been seen to
  -- hand one to a later frame first; so the frames hear it last-made first, the reverse of the
  -- addon's file order, which is what would hide a dependence on the order.
  local function fire(event, ...)
    local list = copyTable(frames)
    for i = #list, 1, -1 do
      local f = list[i]
      local reg = f.events[event]
      if reg and f.scripts.OnEvent and (reg == true or reg == (...)) then f.scripts.OnEvent(f, event, ...) end
    end
  end
  game.fire = fire

  local function advance(seconds)
    if game.reloadAsked then game.reload() end
    local target = game.clock + seconds
    while true do
      local nextAt, nextIndex
      for i, t in ipairs(timers) do
        if t.at <= target and (not nextAt or t.at < nextAt) then nextAt, nextIndex = t.at, i end
      end
      if not nextIndex then break end
      local t = timers[nextIndex]
      game.clock = t.at
      if t.every then t.at = t.at + t.every else table.remove(timers, nextIndex) end
      t.fn(t)
      render(10)
      if game.reloadAsked then game.reload() end
    end
    game.clock = target
    render(30)
  end
  game.advance = advance

  local function serverTime() return 1790766000 + math.floor(game.clock) end

  ---------------------------------------------------------------------------
  -- The environment: the globals the addon reads
  ---------------------------------------------------------------------------

  local function buildEnvironment()
    G = {}
    game.G = G
    G._G = G
    for _, name in ipairs({ "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select", "type", "tostring",
      "tonumber", "rawget", "rawset", "rawequal", "rawlen", "setmetatable", "getmetatable", "string", "table", "math" }) do
      G[name] = _G[name]
    end
    G.unpack = table.unpack
    -- The game's Lua is 5.1 with math.atan2; this Lua is 5.3, whose atan takes two arguments.
    G.math = copyTable(math)
    G.math.atan2 = G.math.atan2 or function(y, x) return math.atan(y, x) end
    G.issecretvalue = function(v) return rawequal(v, SECRET) end
    G.print = function(...)
      local parts = {}
      for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
      game.chat[#game.chat + 1] = table.concat(parts, " ")
    end
    G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    G.GetTime = function() return game.clock end
    G.debugprofilestop = function() return profileMs end
    G.GetServerTime = serverTime
    -- The computer's own clock, which names screenshot files; here the same as the realm's.
    G.time = serverTime
    G.date = function(fmt, t) return os.date(fmt, t) end
    G.CreateFrame = function(kind, name, parent, template)
      local f = newWidget(game, kind or "Frame", name, parent)
      f.template = template
      frames[#frames + 1] = f
      return f
    end
    G.C_Timer = {
      After = function(seconds, fn) timers[#timers + 1] = { at = game.clock + seconds, fn = fn } end,
      NewTicker = function(seconds, fn)
        local t = { at = game.clock + seconds, fn = fn, every = seconds, Cancel = function(self) self.at = math.huge end }
        timers[#timers + 1] = t
        return t
      end,
      NewTimer = function(seconds, fn)
        local t = { at = game.clock + seconds, fn = fn, Cancel = function(self) self.at = math.huge end }
        timers[#timers + 1] = t
        return t
      end,
    }
    -- Post-hooks on functions a stub here defines; anything else is left alone.
    G.hooksecurefunc = function(owner, name, fn)
      if type(owner) == "string" then owner, name, fn = G, owner, name end
      if type(owner) ~= "table" or type(rawget(owner, name)) ~= "function" then return end
      local original = owner[name]
      owner[name] = function(...) original(...) fn(...) end
    end
    G.SlashCmdList = {}

    -- The client
    G.GetBuildInfo = function() return profile.version, profile.build, "Oct 27 2026", profile.interface end
    G.GetLocale = function() return "enUS" end
    G.WOW_PROJECT_ID, G.WOW_PROJECT_MAINLINE = profile.project, 1
    G.LE_EXPANSION_LEVEL_CURRENT = profile.expansion
    G.C_AddOns = { GetAddOnMetadata = function() return game.version end }
    G.GetCurrentRegion = function() return profile.region end
    G.InCombatLockdown = function() return world.combat end
    G.UnitAffectingCombat = function() return world.combat end
    G.IsResting = function() return world.resting end
    G.IsInInstance = function() return world.instance end
    G.UnitOnTaxi = function() return world.taxi end
    G.UnitIsDeadOrGhost = function() return world.dead end
    G.UnitIsGhost = function() return false end
    G.UnitIsFeignDeath = function() return false end
    G.IsInGroup = function() return world.grouped end
    G.GetNumGroupMembers = function() return world.grouped and 2 or 0 end
    G.UnitIsUnit = function(a, b) return a == b end
    G.UnitFullName = function(unit) if unit == "party1" and world.grouped then return "Maela", nil end end
    G.UnitIsAFK = function() if world.afkHidden then return SECRET end return false end
    G.GetInstanceInfo = function() return "Eastern Kingdoms", "none", 0, "", 0, 0, false, 0 end
    G.GetPhysicalScreenSize = function() return world.screen[1], world.screen[2] end
    G.GetCursorPosition = function() return world.cursor[1], world.cursor[2] end
    G.ReloadUI = function() game.reloadAsked = true end
    G.SendChatMessage = function(text, kind) game.sent[#game.sent + 1] = { text = text, kind = kind } end
    G.RequestTimePlayed = function() end

    -- The character
    G.UnitGUID = function(unit)
      if unit == "player" then return game.character.guid end
      if unit == "npc" then return world.npcGUID end
      if unit == "party1" and world.grouped then return "Player-4747-0CCCCCCC" end
    end
    G.UnitName = function() return game.character.name, game.character.surname end
    G.GetRealmName = function() return profile.realm end
    G.GetNormalizedRealmName = function() return profile.realmN end
    G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
    G.UnitRace = function() return "Human", "Human", 1 end
    G.UnitSex = function() return 2 end
    G.UnitFactionGroup = function() return "Alliance", "Alliance" end
    G.UnitLevel = function(unit) if unit == "party1" then return 7 end return world.level end
    G.UnitXP = function() if world.notLoaded then return 0 end return world.xp end
    G.UnitXPMax = function() if world.notLoaded then return 0 end return world.xpMax end
    G.GetMoney = function() if world.notLoaded then return 0 end return world.money end
    -- Another player's name from their GUID, as the game knows it; nothing for one it hasn't met.
    G.GetPlayerInfoByGUID = function(guid)
      if guid == "Player-4747-0BBBBBBB" then return "Paladin", "PALADIN", "Human", "Human", 2, "Someone", "" end
    end
    -- The character sheet: the attribute calls are SecretWhenUnitStatsRestricted and answer secrets
    -- in combat; the item level is readable throughout, so a line read in a fight is part hidden.
    G.UnitStat = function(_, i) if world.combat then return SECRET, SECRET, SECRET, SECRET end return 10 + i, 12 + i, 2, 0 end
    G.UnitArmor = function() if world.combat then return SECRET, SECRET end return 50, 55 end
    G.UnitHealthMax = function() if world.combat then return SECRET end return 136 end
    G.GetAverageItemLevel = function() return 20, 18.5 end
    -- The character's gear by slot; an empty slot answers nil.
    G.GetInventoryItemID = function(_, slot) return world.inventory[slot] end
    G.GetInventoryItemLink = function(_, slot)
      local id = world.inventory[slot]
      if id then return "|cffffffff|Hitem:" .. id .. "::::::::1:::::::|h[Worn Thing]|h|r" end
    end
    -- Durability by slot, current and maximum; nothing for an empty slot. Every read is counted.
    G.GetInventoryItemDurability = function(slot)
      world.durabilityReads = world.durabilityReads + 1
      local d = world.durability[slot]
      if d == SECRET then return SECRET, SECRET end
      if d then return d[1], d[2] end
    end

    -- Loot, as the English client words it, and a loot window
    G.LOOT_ITEM_SELF = "You receive loot: %s."
    G.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
    G.LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
    G.LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
    G.LOOT_ITEM_CREATED_SELF = "You create: %s."
    G.LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d."
    G.LOOT_ITEM_BONUS_ROLL_SELF = "You receive bonus loot: %s."
    G.LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE = "You receive bonus loot: %sx%d."
    G.LOOT_ITEM_REFUND = "You are refunded: %s."
    G.LOOT_ITEM_REFUND_MULTIPLE = "You are refunded: %sx%d."
    G.GetNumLootItems = function() return #world.lootSlots end
    G.GetLootSlotLink = function(slot) return world.lootSlots[slot] and world.lootSlots[slot].link end
    G.GetLootSourceInfo = function(slot) return world.lootSlots[slot] and world.lootSlots[slot].guid end
    -- 1 is an item; a coin slot says 2 (Enum.LootSlotType.Money).
    G.GetLootSlotType = function(slot) return world.lootSlots[slot] and (world.lootSlots[slot].type or 1) end
    G.YOU_LOOT_MONEY = "You loot %s"
    G.YOU_LOOT_MONEY_GUILD = "You loot %s (%s deposited to guild bank)"
    G.LOOT_MONEY_SPLIT = "Your share of the loot is %s."
    G.LOOT_MONEY_SPLIT_GUILD = "Your share of the loot is %s. (%s deposited to guild bank)"
    G.LOOT_MONEY_REFUND = "You are refunded %s."
    G.GOLD_AMOUNT = "%d Gold"
    G.SILVER_AMOUNT = "%d Silver"
    G.COPPER_AMOUNT = "%d Copper"
    G.ERR_ZONE_EXPLORED = "Discovered: %s"
    G.ERR_ZONE_EXPLORED_XP = "Discovered %s: %d experience gained"
    G.ERR_TRADE_COMPLETE = "Trade complete."
    G.FACTION_STANDING_INCREASED = "Reputation with %s increased by %d."
    -- Duels and /roll, as the English client words them; loot rolls the character makes and wins,
    -- need and greed as Retail 12.1.5 words them (a loot history link either side of the item), a
    -- pass and a win as WoW Forever 1.60.1 does (one link, before it).
    G.DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$s in a duel"
    G.DUEL_WINNER_RETREAT = "%2$s has fled from %1$s in a duel"
    G.RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
    G.LOOT_ROLL_NEED_SELF = "|HlootHistory:%d|h[Loot]|h: You have selected Need for: %s |HlootHistory:%d|h|cnLOOT_LINK_COLOR:[View Loot Rolls]|r|h"
    G.LOOT_ROLL_GREED_SELF = "|HlootHistory:%d|h[Loot]|h: You have selected Greed for: %s |HlootHistory:%d|h|cnLOOT_LINK_COLOR:[View Loot Rolls]|r|h"
    G.LOOT_ROLL_PASSED_SELF = "|HlootHistory:%d|h[Loot]|h: You passed on: %s"
    G.LOOT_ROLL_YOU_WON = "|HlootHistory:%d|h[Loot]|h: You won: %s"

    G.Enum = { DamageMeterType = { DamageDone = 0, DamageTaken = 7, HealingDone = 2, EnemyDamageTaken = 10 },
      LootSlotType = { None = 0, Item = 1, Money = 2, Currency = 3 },
      PlayerInteractionType = { None = 0, TradePartner = 1, Item = 2, Gossip = 3, QuestGiver = 4, Merchant = 5, TaxiNode = 6,
        Trainer = 7, Banker = 8, GuildBanker = 10, Registrar = 11, MailInfo = 17, Auctioneer = 21 } }

    -- The quest log
    local function questByID(id) for _, q in ipairs(world.questLog) do if q.questID == id then return q end end end
    G.C_QuestLog = setmetatable({
      GetNumQuestLogEntries = function() return #world.questLog end,
      GetInfo = function(i) local q = world.questLog[i] return q and { questID = q.questID, title = q.title, level = q.level, isHeader = false, isHidden = false } end,
      GetLogIndexForQuestID = function(id) for i, q in ipairs(world.questLog) do if q.questID == id then return i end end end,
      GetQuestDifficultyLevel = function(id) local q = questByID(id) return q and q.difficulty end,
      GetQuestObjectives = function(id) local q = questByID(id) return q and q.objectives end,
      GetTitleForQuestID = function(id) local q = questByID(id) return q and q.title end,
      ReadyForTurnIn = function(id) local q = questByID(id) return q ~= nil and q.ready == true end,
    }, { __index = function() return nothing end })
    -- The map the character is on, when a test puts them somewhere; no coordinates on it.
    G.C_Map = setmetatable({
      GetBestMapForUnit = function() return world.position end,
      GetMapInfo = function(id) return world.maps[id] end,
    }, { __index = function() return nothing end })

    -- The windows that move money: a merchant (a stack of five listed at 250 copper, cloth in the
    -- bags that sells at 10 each, a repair bill of 340), flight paths listed at 500 and 600, a
    -- trainer's service at 500, the mailbox (money to attach, postage of 30, the inbox), and the
    -- guild bank. Each function the default UI calls to move money is defined, so it can be hooked.
    G.MerchantFrame = { IsShown = function() return world.merchantOpen end }
    G.C_MerchantFrame = { GetItemInfo = function() return { price = 250, stackCount = 5 } end, SellAllJunkItems = function() end }
    G.C_Container = setmetatable({ UseContainerItem = function() end,
      GetContainerItemInfo = function() return { itemID = 2589, stackCount = 3 } end }, { __index = function() return nothing end })
    G.C_Item = setmetatable({ GetItemInfo = function() return "Linen Cloth", nil, 1, 5, 0, "Trade Goods", "Cloth", 200, "", 0, 10 end },
      { __index = function() return nothing end })
    G.BuyMerchantItem = function() end
    G.RepairAllItems = function() end
    G.GetRepairAllCost = function() if world.merchantOpen then return 340, true end return 0, false end
    G.TakeTaxiNode = function() end
    G.TaxiNodeCost = function(i) return ({ [3] = 500, [4] = 600 })[i] end
    G.BuyTrainerService = function() end
    G.GetTrainerServiceCost = function() return 500, 0, 0 end
    G.SendMail = function() end
    -- The price the mail window shows for a send is the postage and the attached money together
    -- (Retail 12.1.5: 1 gold attached shows 10030), and the game takes both in one change.
    G.GetSendMailMoney = function() return world.sendMoney end
    G.GetSendMailPrice = function() return 30 + world.sendMoney end
    G.GetInboxNumItems = function() return #world.inbox end
    G.GetInboxHeaderInfo = function(i)
      local l = world.inbox[i]
      if l then return nil, nil, l.sender, l.subject, l.money, l.cod, 30, false, true, false, false, false, false end
    end
    G.GetInboxInvoiceInfo = function(i) return world.inbox[i] and world.inbox[i].invoice end
    G.TakeInboxMoney = function() end
    G.WithdrawGuildBankMoney = function() end

    -- The damage meter. A fight the meter isn't whole for at the instant combat ends, until the
    -- clock passes world.meterLate[id].at: "missing" leaves this character's entry out (as the game
    -- once did), "secret" still hides the amounts.
    local function meterSession(id, kind)
      local late = world.meterLate[id]
      if late and game.clock >= late.at then late = nil end
      if world.combat or (late and late.how == "secret") then
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
      local own = game.character.name .. (game.character.surname and (" " .. game.character.surname) or "")
      return { combatSources = { { isLocalPlayer = true, totalAmount = kind == 0 and world.meterTotal or 140, name = own,
        sourceGUID = game.character.guid }, { isLocalPlayer = false, totalAmount = 900, name = "Someone Else", sourceGUID = "Player-4747-0AAAAAAA" } },
        totalAmount = kind == 0 and (world.meterTotal + 900) or 140, durationSeconds = world.meterDuration }
    end
    G.C_DamageMeter = {
      GetAvailableCombatSessions = function() return world.fights end,
      GetCombatSessionFromID = function(id, kind) return meterSession(id, kind) end,
      GetCombatSessionSourceFromID = function(_, kind, guid)
        if rawequal(guid, SECRET) then error("Secret values are only allowed during untainted execution") end
        if kind == 0 then return { combatSpells = { { spellID = 6603, totalAmount = 105 }, { spellID = 772, totalAmount = 43 }, { spellID = 78, totalAmount = 33 } } } end
        return { combatSpells = { { spellID = 20793, totalAmount = 117 }, { spellID = 6603, totalAmount = 23 } } }
      end,
    }
    G.C_DeathRecap = {
      GetRecapMaxHealth = function() return 136 end,
      GetRecapEvents = function()
        local at = world.recapStale and 1790766000 or (serverTime() + 0.004)
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
    -- says so in advance. Every refusal is counted. world.refuseUnforeseen refuses every read
    -- while C_Secrets still says nothing is hidden, with the message the game gave on build 70235.
    local function aurasRestricted() return world.combat or world.encounter end
    local function refuse(name)
      world.auraRefusals = world.auraRefusals + 1
      error(name .. "(): Auras cannot be accessed when secret while tainted by 'Widsith' Lua Taint: Widsith", 0)
    end
    G.C_Secrets = {
      ShouldAurasBeSecret = function() return aurasRestricted() end,
      ShouldUnitAuraIndexBeSecret = function(_, i, filter) local aura = world.present[filter][i] return aura ~= nil and aura.alwaysHidden == true end,
      ShouldUnitAuraInstanceBeSecret = function() return false end,
    }
    G.C_UnitAuras = {
      GetAuraDataByIndex = function(_, i, filter)
        local aura = world.present[filter][i]
        if aurasRestricted() or world.refuseUnforeseen or (aura and aura.alwaysHidden) then refuse("GetAuraDataByIndex") end
        return aura
      end,
      GetAuraCasterGUID = function(_, instance)
        if aurasRestricted() then refuse("GetAuraCasterGUID") end
        if instance == 133 then return "Player-4747-0BBBBBBB" end
        if instance == 140 then return "Creature-0-4621-0-46196-30-00003CF70B" end
        return game.character.guid
      end,
    }
    G.C_LossOfControl = { GetActiveLossOfControlData = function()
      return { locType = "STUN_MECHANIC", spellID = 853, displayText = "Stunned", duration = 3, lockoutSchool = 0, auraInstanceID = 37 }
    end }

    -- The statistics pane. The millisecond clock: reading a counter costs a millisecond, so a
    -- pass spans frames.
    G.GetStatisticsCategoryList = function() return { 130 } end
    G.GetCategoryNumAchievements = function() return #world.statOrder end
    G.GetStatistic = function(category, i)
      profileMs = profileMs + 1
      world.statFrames[frameNo] = true
      -- The one-argument form, by ID, as the pane's own rows read it.
      if i == nil then
        world.byIDReads = world.byIDReads + 1
        return world.stat[category], false, category
      end
      return world.stat[world.statOrder[i]], false, world.statOrder[i]
    end
    G.GetAchievementInfo = function(id) return id, world.statNames[id] end

    -- The Reputation pane's list and the Currency tab's list (expanding a header would change the
    -- player's window; the stand-in counts any attempt).
    G.C_Reputation = {
      GetNumFactions = function() return #world.pane end,
      GetFactionDataByIndex = function(i) return world.pane[i] end,
      GetFactionDataByID = function(id) if id == 72 then return world.pane[2] end end,
    }
    G.C_CurrencyInfo = {
      GetCurrencyListSize = function() return #world.currencyList + 1 end,
      GetCurrencyListInfo = function(i) return world.currencyList[i] end,
      ExpandCurrencyList = function() world.currencyExpanded = world.currencyExpanded + 1 end,
    }

    -- A profession window: whose it is, whether it has loaded, and its recipes (one ID hidden,
    -- one recipe's details hidden).
    G.C_TradeSkillUI = {
      CraftRecipe = function() end,   -- the crafting call, which the recorder hooks
      IsTradeSkillReady = function() return world.window.ready end,
      IsDataSourceChanging = function() return false end,
      IsTradeSkillLinked = function() return world.window.linked, world.window.linked and "Someone" or nil end,
      IsTradeSkillGuild = function() return false end,
      IsTradeSkillGuildMember = function() return false end,
      IsNPCCrafting = function() return world.window.npc end,
      GetBaseProfessionInfo = function() return { professionID = 393, professionName = "Skinning" } end,
      GetChildProfessionInfo = function() return { professionID = 2947, parentProfessionID = 393 } end,
      GetAllRecipeIDs = function() return { 10662, 8613, 8617, SECRET, 19047, 20000 } end,
      GetFilteredRecipeIDs = function() return { 8613, 10662 } end,
      GetRecipeInfo = function(id)
        if id == 20000 then return { learned = SECRET } end
        return { recipeID = id, learned = world.recipes[id] }
      end,
    }
    -- Gear sets: two, one with ignored slots (one of them hidden) and assigned to a spec; at
    -- login the list also holds an ID the game hid.
    G.C_EquipmentSet = {
      GetEquipmentSetIDs = function()
        local ids = {}
        for id in pairs(world.sets) do ids[#ids + 1] = id end
        table.sort(ids)
        if world.setListHidden then ids[#ids + 1] = SECRET end
        return ids
      end,
      GetEquipmentSetInfo = function(id)
        local s = world.sets[id]
        if not s then return end
        return s.name, s.icon, id, id == 0, 3, 2, 1, 0, 1
      end,
      GetItemIDs = function(id) return world.sets[id] and world.sets[id].items end,
      GetIgnoredSlots = function(id) return world.sets[id] and world.sets[id].ignored end,
      GetEquipmentSetAssignedSpec = function(id) return world.sets[id] and world.sets[id].spec end,
    }
    -- Talents: a trait tree with two bought nodes, one granted free and one ID hidden; two spec groups.
    G.C_SpecializationInfo = {
      GetSpecialization = function() return 1 end,
      GetSpecializationInfo = function() return 1491, "Warrior" end,
      GetActiveSpecGroup = function() return world.talent.group end,
      GetCombatConfigIDForSpecGroup = function(group) return 100 + group end,
    }
    G.C_ClassTalents = { GetActiveConfigID = function() return 100 + world.talent.group end }
    G.C_Traits = {
      ConfigHasStagedChanges = function() return world.talent.staged end,
      GetConfigInfo = function(id) return { ID = id, treeIDs = { 790 } } end,
      GetTreeNodes = function() return { 9001, 9002, 9003, 9004, 9005 } end,
      GetNodeInfo = function(_, nodeID)
        if nodeID == 9005 then return { ranksPurchased = 0, activeRank = 1, activeEntry = { entryID = 19005, rank = 1 } } end
        if nodeID == 9002 and world.talent.secretNode then return SECRET end
        local r = world.talent.bought[nodeID] or 0
        return { ranksPurchased = r, activeRank = r, activeEntry = r > 0 and { entryID = nodeID + 10000, rank = r } or nil }
      end,
      GenerateImportString = function() return "BcQAAAAAAAAAAAAAAAAAAAAA" .. world.talent.group end,
    }
    G.C_GameRules = { IsHardcoreActive = function() return world.hardcore end,
      GetForeverExperiencePreset = function() return 1 end }
    G.C_PlayerInfo = { IsSelfFoundActive = function() return false end }
    -- The Skills tab: no lines until its answers are stubbed, so the recorder writes the
    -- professions alone.
    G.C_SkillInfo = { GetNumSkillLines = function() return 0 end, GetSkillLineInfo = function() end,
      GetSkillLineInfoByID = function() end }
    G.C_StableInfo = { BuyStableSlot = function() end, GetNextStableSlotCost = function() return 0 end }
    G.GetSpecialization = function() return 1 end
    G.UnitDefenseSkill = function() return 1, 0 end

    -- The weather where the character is (WeatherScriptDocumentation.lua: a WeatherInfo of type and
    -- intensity), and whether it is day (C_DateAndTime.IsDayTime, WoW Forever's API).
    G.C_Weather = { GetCurrentWeather = function() return world.weather end }
    G.C_DateAndTime = { IsDayTime = function() return world.daytime end }

    -- The world map, the emote the game performs when it opens, and chat's lockdown
    G.WorldMapFrame = { IsShown = function() return world.mapShown end }
    G.C_ChatInfo = { PerformEmote = function() end, InChatMessagingLockdown = function() return world.chatLockdown end }
    G.ChatFrameUtil = { DisplayTimePlayed = function() end }

    -- The screen: the world's frame, the interface's parent, the minimap and its cluster, the
    -- chat window and the friends list, as frames with a place on screen.
    G.WorldFrame = newWidget(game, "Frame", "WorldFrame", nil)
    G.UIParent = newWidget(game, "Frame", "UIParent", nil)
    G.UIParent.width, G.UIParent.height, G.UIParent.center = 1366, 768, { 683, 384 }
    G.MinimapCluster = newWidget(game, "Frame", "MinimapCluster", G.UIParent)
    G.MinimapCluster.center = { 1250, 650 }
    G.Minimap = newWidget(game, "Frame", "Minimap", G.MinimapCluster)
    G.Minimap.width, G.Minimap.height, G.Minimap.center = 140, 140, { 1250, 650 }
    if profile.diel then
      -- The day/night dial on the ring's top right, anchored on the cluster as Forever's own
      -- minimap code places it.
      local dial = newWidget(game, "Frame", "MinimapClusterDielFrame", G.MinimapCluster)
      dial.width, dial.height, dial.center = 42, 42, { 1313, 722 }
      dial.points[1] = { "CENTER", G.MinimapCluster, "CENTER", 63, 72 }
      G.MinimapCluster.DielFrame = dial
      G.MinimapCluster.SetEditModeScale = function(self, scale) self.scale = scale end
    end
    G.C_Texture = { GetAtlasInfo = function(name)
      if profile.diel and name == "UI-HUD-Minimap-Frame-Cycle" then return { width = 42, height = 42 } end
    end }
    G.CHAT_FRAMES = { "ChatFrame1" }
    G.ChatFrame1 = newWidget(game, "Frame", "ChatFrame1", G.UIParent)
    G.ChatFrame1.alpha = 0.8
    -- The default chat window, 400 wide in a 14-point font; a font string here measures eight
    -- units a character, so a dash is eight.
    G.ChatFrame1.width, G.ChatFrame1.height = 400, 160
    G.ChatFrame1.GetFont = function() return "Fonts\\FRIZQT__.TTF", 14, "" end
    G.DEFAULT_CHAT_FRAME = G.ChatFrame1
    G.FriendsFrame = newWidget(game, "Frame", "FriendsFrame", G.UIParent)
    G.Screenshot = function()
      world.shotsTaken = world.shotsTaken + 1
      world.chatAtShot = G.ChatFrame1.alpha
      world.friendsAtShot = G.FriendsFrame.alpha
      if world.shotAnswer then fire(world.shotAnswer) end
    end

    -- The tooltip: its lines kept, so a test can read them.
    local tooltip = newWidget(game, "GameTooltip", "GameTooltip", G.UIParent)
    tooltip.shown = false
    tooltip.lines = {}
    tooltip.SetOwner = function(self, owner, anchor) self.owner, self.anchor = owner, anchor end
    tooltip.SetText = function(self, text) self.lines = { text } end
    tooltip.AddLine = function(self, text) self.lines[#self.lines + 1] = text end
    tooltip.Hide = function(self) self.shown = false self.lines = {} end
    game.tooltip = tooltip

    -- The context menu: the tree it is given is kept as the last menu opened, each entry with
    -- what pressing it does, so a test can find "Remind me to save" and press it.
    local function menuNode(kind, name)
      local node = { kind = kind, name = name, entries = {} }
      node.CreateTitle = function(_, text) node.entries[#node.entries + 1] = menuNode("title", text) end
      node.CreateButton = function(_, text, fn)
        local entry = menuNode("button", text)
        entry.press = fn
        node.entries[#node.entries + 1] = entry
        return entry
      end
      node.CreateCheckbox = function(_, text, isChecked, toggle)
        local entry = menuNode("checkbox", text)
        entry.isChecked, entry.press = isChecked, toggle
        node.entries[#node.entries + 1] = entry
        return entry
      end
      node.CreateRadio = function(_, text, isSelected, select)
        local entry = menuNode("radio", text)
        entry.isChecked, entry.press = isSelected, select
        node.entries[#node.entries + 1] = entry
        return entry
      end
      node.CreateDivider = function() node.entries[#node.entries + 1] = menuNode("divider", "") end
      return node
    end
    G.MenuUtil = { CreateContextMenu = function(owner, generator)
      local root = menuNode("root")
      generator(owner, root)
      game.lastMenu = root
      return root
    end }

    -- The settings panel: each row it is given is kept in order, with its setting (its value read
    -- and set through the addon's own functions), its default, its tooltip and the row it depends
    -- on, so a test can read the panel as the player sees it, change a setting from it, and put
    -- the defaults back as the panel's Defaults button does.
    local panel = { rows = {}, categories = {}, registered = false, openedTo = nil }
    game.panel = panel
    local function row(entry) panel.rows[#panel.rows + 1] = entry return entry end
    G.Settings = {
      VarType = { Boolean = "boolean", Number = "number" },
      RegisterVerticalLayoutCategory = function(name)
        local category = { name = name, GetID = function() return name end }
        panel.categories[#panel.categories + 1] = category
        return category
      end,
      RegisterProxySetting = function(category, variable, varType, name, default, get, set)
        return { variable = variable, varType = varType, name = name, default = default,
          GetValue = function() return get() end, SetValue = function(_, value) set(value) end,
          GetDefaultValue = function() return default end }
      end,
      CreateCheckbox = function(category, setting, tooltip)
        return row({ kind = "checkbox", name = setting.name, setting = setting, tooltip = tooltip,
          SetParentInitializer = function(self, parent, enabledWhen) self.parent, self.enabledWhen = parent, enabledWhen end })
      end,
      CreateDropdown = function(category, setting, options, tooltip)
        return row({ kind = "dropdown", name = setting.name, setting = setting, options = options(), tooltip = tooltip })
      end,
      CreateControlTextContainer = function()
        local data = {}
        return { Add = function(_, value, label) data[#data + 1] = { value = value, label = label } end, GetData = function() return data end }
      end,
      RegisterCanvasLayoutSubcategory = function(category, frame, name)
        row({ kind = "canvas", name = name, frame = frame })
        return { name = name, GetID = function() return name end }
      end,
      RegisterAddOnCategory = function() panel.registered = true end,
      OpenToCategory = function(id) panel.openedTo = id end,
    }
    G.SettingsPanel = { GetLayout = function() return { AddInitializer = function(_, init) row(init) end } end }
    G.CreateSettingsListSectionHeaderInitializer = function(name) return { kind = "header", name = name } end
    G.CreateSettingsButtonInitializer = function(name, buttonText, press, tooltip)
      return { kind = "button", name = name, button = buttonText, press = press, tooltip = tooltip }
    end

    -- What this client lacks: each path taken out, the namespace kept.
    local absentGlobals = {}
    for _, path in ipairs(profile.absent) do
      local namespace, name = path:match("^([^.]+)%.(.+)$")
      if namespace then
        if type(rawget(G, namespace)) == "table" then G[namespace][name] = nil end
      else
        G[path] = nil
        absentGlobals[path] = true
      end
    end

    -- A test's own change to the game, made again at every build (a login, a reload), since
    -- each build starts from the stubs: game.onBuild = function(G) ... end.
    if game.onBuild then game.onBuild(G) end

    -- Anything not stubbed: functions that return nothing, namespaces with such functions; a
    -- global the profile says this client lacks answers nil.
    setmetatable(G, {
      __index = function(_, key)
        if type(key) ~= "string" or key:find("^Widsith") or absentGlobals[key] then return nil end
        if key:find("^C_") then return emptyNamespace end
        if key:find("^%u%l") then return nothing end
        return nil
      end,
    })
  end

  ---------------------------------------------------------------------------
  -- Loading the addon, logging in, reloading, logging out
  ---------------------------------------------------------------------------

  -- Every line the recorder writes, as it is written, with the session it belongs to: what
  -- Core.lua's write is told, before it goes into the file's chunks.
  local function mirrorWrites()
    local write = addonTable.write
    addonTable.write = function(kind, ...)
      -- Nothing is written outside a session, so nothing is mirrored either.
      if not addonTable.isRecording() then return write(kind, ...) end
      local fields = {}
      for i = 1, select("#", ...) do fields[i] = addonTable.field((select(i, ...))) end
      if kind == "SESSION" then game.written[#game.written + 1] = { lines = {} } end
      local session = game.written[#game.written]
      if session then
        local line = { t = addonTable.nowMs(), kind = kind, fields = fields, raw = kind .. "\t" .. table.concat(fields, "\t") }
        session.lines[#session.lines + 1] = line
      end
      return write(kind, ...)
    end
  end

  local function loadAddon()
    addonTable = {}
    game.addon = addonTable
    game.loads = game.loads + 1
    for _, file in ipairs(ADDON_FILES) do
      local chunk, err = loadfile(dir .. file, "t", G)
      if not chunk then error(err, 0) end
      chunk(ADDON, addonTable)
      if file == "Core.lua" then mirrorWrites() end
    end
  end

  -- The game's own order at a login: the addon's files, ADDON_LOADED, PLAYER_LOGIN, then the
  -- world entered. The saved tables are what game.saved holds, if a test set them first, as a
  -- file an earlier version wrote; otherwise none, a first run.
  function game.login()
    buildEnvironment()
    frames, timers = {}, {}
    local tables = game.saved or {}
    G.WidsithDB, G.WidsithUI, G.WidsithAccount = tables.WidsithDB, tables.WidsithUI, tables.WidsithAccount
    loadAddon()
    fire("ADDON_LOADED", ADDON)
    fire("PLAYER_LOGIN")
    fire("PLAYER_ENTERING_WORLD", true, false)
  end

  -- What the game writes to the saved file at a logout or reload: the two tables, copied. A
  -- secret or a function in either would break the real save, so it fails here.
  local function saved(name, value, path)
    if rawequal(value, SECRET) then error("a secret value in " .. name .. " at " .. path .. " would break the saved file", 0) end
    local t = type(value)
    if t == "function" or t == "userdata" or t == "thread" then
      error("a " .. t .. " in " .. name .. " at " .. path .. " would break the saved file", 0)
    end
    if t ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[saved(name, k, path)] = saved(name, v, path .. "." .. tostring(k)) end
    return out
  end

  -- What the game saves at a logout or reload: the three tables, copied as the file would hold
  -- them.
  local function savedTables()
    return {
      WidsithDB = saved("WidsithDB", G.WidsithDB, "WidsithDB"),
      WidsithUI = saved("WidsithUI", G.WidsithUI, "WidsithUI"),
      WidsithAccount = saved("WidsithAccount", G.WidsithAccount, "WidsithAccount"),
    }
  end

  local function loadOn(tables, isLogin, isReload)
    buildEnvironment()
    frames, timers = {}, {}
    G.WidsithDB, G.WidsithUI, G.WidsithAccount = tables.WidsithDB, tables.WidsithUI, tables.WidsithAccount
    loadAddon()
    fire("ADDON_LOADED", ADDON)
    fire("PLAYER_LOGIN")
    fire("PLAYER_ENTERING_WORLD", isLogin, isReload)
  end

  -- A reload: PLAYER_LOGOUT, the saved variables written out, the interface loaded afresh on
  -- them, and the world entered again as a reload. The clock runs on, as GetTime does.
  function game.reload()
    game.reloadAsked = nil
    fire("PLAYER_LOGOUT")
    loadOn(savedTables(), false, true)
  end

  -- A logout and a login on the same character: the file written and read back, the world
  -- entered as a login.
  function game.loginAgain()
    fire("PLAYER_LOGOUT")
    loadOn(savedTables(), true, false)
  end

  -- A logout and a login on another character of the same account: the account's table kept,
  -- the character's two fresh.
  function game.loginAs(name, surname, guid)
    fire("PLAYER_LOGOUT")
    local tables = savedTables()
    tables.WidsithDB, tables.WidsithUI = nil, nil
    game.character = { name = name, surname = surname, guid = guid or ("Player-4747-" .. name) }
    loadOn(tables, true, false)
  end

  -- A reload after which the game didn't read the file back, as early WoW Forever builds did.
  function game.reloadWithoutFile()
    game.reloadAsked = nil
    fire("PLAYER_LOGOUT")
    saved("WidsithDB", G.WidsithDB, "WidsithDB")
    buildEnvironment()
    frames, timers = {}, {}
    loadAddon()
    fire("ADDON_LOADED", ADDON)
    fire("PLAYER_LOGIN")
    fire("PLAYER_ENTERING_WORLD", false, true)
  end

  function game.logout()
    fire("PLAYER_LOGOUT")
    game.saved = savedTables()
    return game.saved
  end

  ---------------------------------------------------------------------------
  -- What a test does and reads
  ---------------------------------------------------------------------------

  function game.slash(text) G.SlashCmdList.WIDSITH(text) end

  -- A money change: the total moves and PLAYER_MONEY fires.
  function game.change(copper)
    world.money = world.money + copper
    fire("PLAYER_MONEY")
  end

  -- A window opened at an NPC (by Enum.PlayerInteractionType's name) and closed.
  function game.openWindow(name, guid)
    world.npcGUID = guid
    fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", G.Enum.PlayerInteractionType[name])
  end
  function game.closeWindow(name)
    fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", G.Enum.PlayerInteractionType[name])
    world.npcGUID = nil
  end

  -- The lines written so far: all of them, or those of one kind, across every session; a
  -- session's own by its number (1 is the first since login); the last line of a kind.
  function game.lines(kind, session)
    local out = {}
    for n, s in ipairs(game.written) do
      if session == nil or session == n then
        for _, l in ipairs(s.lines) do
          if kind == nil or l.kind == kind then out[#out + 1] = l end
        end
      end
    end
    return out
  end
  function game.last(kind)
    local all = game.lines(kind)
    return all[#all]
  end
  -- The fields of every line of a kind, each line's joined with spaces, for a list to compare.
  function game.fieldsOf(kind, session)
    local out = {}
    for _, l in ipairs(game.lines(kind, session)) do out[#out + 1] = table.concat(l.fields, " ") end
    return out
  end
  -- The lines as the saved file holds them, parsed from WidsithDB's chunks: what a reload reads.
  function game.onFile()
    local sessions = {}
    for _, s in ipairs(G.WidsithDB and G.WidsithDB.sessions or {}) do
      local lines = {}
      for line in (table.concat(s.chunks, "\n") .. "\n"):gmatch("([^\n]*)\n") do
        local t, kind, rest = line:match("^(%d+)\t([^\t]+)\t?(.*)$")
        if t then
          local fields = {}
          for v in (rest .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = v end
          if rest == "" then fields = {} end
          lines[#lines + 1] = { t = tonumber(t), kind = kind, fields = fields, raw = kind .. "\t" .. rest }
        end
      end
      sessions[#sessions + 1] = { id = s.id, closed = s.closed, lines = lines }
    end
    return sessions
  end

  -- Chat: whether a line containing the text was printed (plain text, colour codes ignored).
  function game.said(text)
    for _, line in ipairs(game.chat) do
      if line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):find(text, 1, true) then return line end
    end
    return nil
  end
  function game.clearChat() game.chat = {} end

  -- The icon, its menu (opened by a right click, as the player does), and an entry of the last
  -- menu by name, through submenus.
  function game.icon() return G.WidsithRecordingIcon end
  function game.openMenu()
    local icon = game.icon()
    icon.scripts.OnClick(icon, "RightButton")
    return game.lastMenu
  end
  function game.menuEntry(...)
    local node = game.lastMenu
    for i = 1, select("#", ...) do
      local name = select(i, ...)
      local found
      for _, entry in ipairs(node and node.entries or {}) do
        if entry.name == name then found = entry break end
      end
      if not found then return nil end
      node = found
    end
    return node
  end
  -- Pressing an entry: a checkbox or a radio is pressed to change, a button to act.
  function game.press(entry)
    assert(entry and entry.press, "nothing to press")
    entry.press()
  end
  -- A row of the settings panel by its name, and the panel's Defaults button.
  function game.panelRow(name)
    for _, r in ipairs(game.panel.rows) do if r.name == name then return r end end
  end
  function game.panelDefaults()
    for _, r in ipairs(game.panel.rows) do
      if r.setting then r.setting:SetValue(r.setting.default) end
    end
  end
  -- The save reminder, by the title it shows; nil until it has been created.
  function game.reminder()
    for _, f in ipairs(frames) do
      for _, r in ipairs(f.regions) do
        if type(r.text) == "string" and r.text:find("^Recording unsaved for") then return f end
      end
    end
  end
  -- The frames made since this load, for a test that looks for one by what it holds.
  function game.frames() return frames end
  function game.hover() local icon = game.icon() icon.scripts.OnEnter(icon) end
  function game.clickSave() local icon = game.icon() icon.scripts.OnClick(icon, "LeftButton") end

  return game
end

return { newGame = newGame, PROFILES = PROFILES, SECRET = SECRET }
