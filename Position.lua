-- Widsith — Position
--
-- The only polled part of the recorder. Once per second: sample the player's
-- map position, write POS when it changed, NOPOS when it became unavailable,
-- MAPINFO the first time a map is seen in the session, and STATE when any of
-- the polled conditions (mounted, swimming, …) changed. Every TIMER_PERIOD
-- ticks, write the periodic lines (TIME, SNAP, COUNT, and with SNAP the
-- character sheet and the game's counters), never while a loading screen is up.
--
-- The tick also notices an instantaneous relocation (consecutive samples on
-- the same continent further apart than a character can travel) and reports
-- it to Extras.lua, which names the spell that preceded it (SPELL).

local _, WJ = ...

local GetBestMapForUnit      = C_Map.GetBestMapForUnit
local GetPlayerMapPosition   = C_Map.GetPlayerMapPosition
local GetMapInfo             = C_Map.GetMapInfo
local GetWorldPosFromMapPos  = C_Map.GetWorldPosFromMapPos
local issecretvalue          = issecretvalue

local lastMapID, lastX, lastY      -- last written POS (formatted strings)
local posAvailable                 -- nil = unknown, true/false
local seenMaps = {}
local mapContinent = {}            -- mapID -> continentID from MAPINFO
local ticks = 0
local ticker

-- Faster than this between two samples is not travel: flight paths and
-- skyriding stay well under it.
local RELOCATION_YARDS_PER_SEC = 150
local lastWorld                    -- { wx, wy, continent, clock } of last POS

-- Current map and raw coordinates; nil coordinates when unavailable.
function WJ.currentPosition()
  local mapID = GetBestMapForUnit("player")
  if not mapID then return nil end
  local pos = GetPlayerMapPosition(mapID, "player")
  if not pos then return mapID end
  local x, y = pos:GetXY()
  return mapID, x, y
end

local function worldCorner(mapID, x, y)
  local ok, continentID, vec = pcall(GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
  if not ok or not vec then return nil end
  local wx, wy = vec:GetXY()
  return continentID, wx, wy
end

local function writeMapInfo(mapID)
  seenMaps[mapID] = true
  local info = GetMapInfo(mapID)
  local c0, wx0, wy0 = worldCorner(mapID, 0, 0)
  local _,  wx1, wy1 = worldCorner(mapID, 1, 1)
  mapContinent[mapID] = c0
  WJ.write("MAPINFO", mapID,
    info and info.parentMapID, info and info.mapType, info and info.name,
    wx0 and string.format("%.1f", wx0), wy0 and string.format("%.1f", wy0),
    wx1 and string.format("%.1f", wx1), wy1 and string.format("%.1f", wy1),
    c0)
end

---------------------------------------------------------------------------
-- STATE: polled conditions, written on change. Each is the game's
-- own flag at the instant of the sample; a jump shorter than a second is
-- usually missed by `falling`, which is what 1 Hz sampling sees.
--
-- The game hides some of these from addons at times: UnitIsAFK is secret while
-- chat is restricted (an encounter, a Mythic+ run, a PvP match, and on maps
-- where chat is restricted, such as dungeons and raids; Blizzard's
-- UnitDocumentation.lua marks it SecretInChatMessagingLockdown). Testing a
-- secret as true or false raises an error, so every flag is checked with
-- issecretvalue() first, and a hidden flag is written as an empty field. The
-- line is compared as written, so one STATE marks where the hiding began and
-- another where it ended.
---------------------------------------------------------------------------

local lastStateKey

-- "1" or "0", or "" when the game hides the flag.
local function flag(f, ...)
  if not f then return "0" end
  local v = f(...)
  if issecretvalue and issecretvalue(v) then return "" end
  return v and "1" or "0"
end

local function sampleState()
  local mounted   = flag(IsMounted)
  local swimming  = flag(IsSwimming)
  local flying    = flag(IsFlying)
  local falling   = flag(IsFalling)
  local indoors   = flag(IsIndoors)
  local stealthed = flag(IsStealthed)
  local afk       = flag(UnitIsAFK, "player")
  local taxi      = flag(UnitOnTaxi, "player")
  -- `falling` is written but doesn't trigger a line: it flips with nearly every landing after
  -- a JUMP, which has a line of its own. The field keeps its place in the line.
  -- Separated, since an empty field would otherwise shift the others along.
  local key = table.concat({ mounted, swimming, flying, indoors, stealthed, afk, taxi }, ",")
  if key ~= lastStateKey then
    lastStateKey = key
    WJ.write("STATE", mounted, swimming, flying, falling, indoors, stealthed, afk, taxi)
  end
end

---------------------------------------------------------------------------
-- Tick
---------------------------------------------------------------------------

local function noteWorld(mapID, wx, wy)
  local continent = mapContinent[mapID]
  local now = GetTime()
  if wx and lastWorld and lastWorld.continent == continent and continent ~= nil then
    local dt = now - lastWorld.clock
    if dt > 0 and dt <= 5 then
      local dx, dy = wx - lastWorld.wx, wy - lastWorld.wy
      local dist = math.sqrt(dx * dx + dy * dy)
      if dist / dt > RELOCATION_YARDS_PER_SEC then
        -- The move happened after the previous sample: that is where Extras.lua
        -- starts looking for the cast behind it.
        WJ.onRelocation("jump", dist, lastWorld.clock)
      end
    end
  end
  if wx then
    lastWorld = { wx = wx, wy = wy, continent = continent, clock = now }
  else
    lastWorld = nil
  end
end

local function samplePosition()
  local mapID, x, y = WJ.currentPosition()
  WJ.tickClock, WJ.tickHasPos = GetTime(), x ~= nil   -- for WJ.health()

  if mapID and not seenMaps[mapID] then writeMapInfo(mapID) end

  if x then
    local xs, ys = WJ.coord(x), WJ.coord(y)
    -- Standing still is still a sample: the relocation check below measures from the last
    -- tick that saw the character, not the last POS written, or a teleport cast while
    -- standing (every hearthstone) would be too far from its last line to be noticed.
    if lastWorld and mapID == lastMapID and xs == lastX and ys == lastY then
      lastWorld.clock = GetTime()
    end
    if mapID ~= lastMapID or xs ~= lastX or ys ~= lastY then
      -- World coordinates too: continuous across map changes. UnitPosition's
      -- first two returns are in the same order as the vector from
      -- GetWorldPosFromMapPos (MAPINFO): north-south first, then east-west.
      -- nil wherever map position is nil. The third return (height) is always 0
      -- and is kept only so the line's shape doesn't change.
      local wx, wy, wz = UnitPosition("player")
      noteWorld(mapID, wx, wy)
      WJ.write("POS", mapID, xs, ys,
        wx and string.format("%.1f", wx), wy and string.format("%.1f", wy), wz and string.format("%.1f", wz))
      WJ.lastPosHasWorld = wx ~= nil
      WJ.counts.pos = WJ.counts.pos + 1
      lastMapID, lastX, lastY = mapID, xs, ys
    end
    posAvailable = true
  elseif posAvailable ~= false then
    WJ.write("NOPOS", mapID)
    posAvailable = false
    lastMapID, lastX, lastY = nil, nil, nil
    lastWorld = nil
  end
end

---------------------------------------------------------------------------
-- The periodic lines. While a loading screen is up the client is still
-- loading the character: a reading taken then has the level but no money, no
-- experience to the next level, no map and every gear slot empty. A tick
-- inside a loading screen leaves the lines due, and the first tick after the
-- screen writes them, a few seconds late; the next fall due at their usual
-- tick. The screen is known from LOADING_SCREEN_ENABLED and
-- LOADING_SCREEN_DISABLED (Extras.lua hears both). Should the client ever not
-- report a screen's end, it stops holding the lines back after a period.
---------------------------------------------------------------------------

local periodicDue = false
local loadingSince   -- GetTime() when the loading screen now up appeared; nil when none is

-- The end of a screen also writes LOADSCREEN seconds: how long it was up, to a
-- tenth of a second. GetTime() is the computer's uptime, not the game's, so it
-- runs on through the screen; it is updated once a frame. At a login or a
-- reload the addon loads inside the screen and never hears it begin, so that
-- one has no line.
function WJ.onLoadingScreen(shown)
  if not shown and loadingSince then
    WJ.write("LOADSCREEN", string.format("%.1f", GetTime() - loadingSince))
  end
  loadingSince = shown and GetTime() or nil
end

local function loadingScreenUp()
  return loadingSince ~= nil and GetTime() - loadingSince < WJ.TIMER_PERIOD
end

local function writePeriodic()
  WJ.write("TIME", GetServerTime())
  WJ.snapshot()
end

-- Each part guarded on its own: whatever goes wrong in one is named in its ERR
-- line and costs neither of the others.
local samplePositionGuarded = WJ.guard("tick", samplePosition)
local sampleStateGuarded    = WJ.guard("state", sampleState)
local writePeriodicGuarded  = WJ.guard("periodic", writePeriodic)

local function tick()
  -- Paused: nothing is sampled, so a map or a state seen only during
  -- the pause is still new to the session that resumes.
  if not WJ.isRecording() then return end
  ticks = ticks + 1
  samplePositionGuarded()
  sampleStateGuarded()
  if ticks % WJ.TIMER_PERIOD == 0 then periodicDue = true end
  if periodicDue and not loadingScreenUp() then
    periodicDue = false
    writePeriodicGuarded()
  end
end

function WJ.startTicker()
  if ticker then return end
  ticks = 0
  ticker = C_Timer.NewTicker(1, WJ.guard("tick", tick))
end

-- On any PLAYER_ENTERING_WORLD forget the last sample so the next tick writes
-- a fresh POS or NOPOS for the new place. MAPINFO's seen-set is per session
-- and deliberately not reset. A loading screen also breaks the relocation
-- check: Events.lua reports that transition itself.
function WJ.onEnteringWorldPosition()
  posAvailable = nil
  lastMapID, lastX, lastY = nil, nil, nil
  lastWorld = nil
end

-- A session resumed after a pause starts as a new addon load would: every map
-- gets its MAPINFO again, and the first tick writes POS and STATE.
function WJ.resetPositionForSession()
  WJ.onEnteringWorldPosition()
  seenMaps = {}
  lastStateKey = nil
  periodicDue = false
  ticks = 0
end
