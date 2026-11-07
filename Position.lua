-- Widsith — Position
--
-- The only polled part of the recorder. Once a second it samples the player's
-- position and writes POS when it changed, NOPOS when it became unavailable,
-- MAPINFO for a map new to the session, and STATE when a polled condition
-- (mounted, swimming, …) changed. Every TIMER_PERIOD ticks it writes the
-- periodic lines (TIME, SNAP, COUNT). A move too fast to be travel is reported
-- to Extras.lua, which names the spell behind it (SPELL).

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

-- Faster than this between two samples is not travel.
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
-- STATE: the game's own flags at each sample, written on change.
-- UnitIsAFK is secret while chat is restricted (UnitDocumentation.lua marks it
-- SecretInChatMessagingLockdown), so every flag is checked with issecretvalue()
-- first and a hidden one is written as an empty field.
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
  -- `falling` is written but doesn't trigger a line: it flips at nearly every landing after a JUMP.
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
        -- The move happened after the previous sample, so the cast is looked for from there.
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
    -- Standing still is still a sample: the relocation check measures from the last
    -- tick that saw the character, not the last POS written.
    if lastWorld and mapID == lastMapID and xs == lastX and ys == lastY then
      lastWorld.clock = GetTime()
    end
    if mapID ~= lastMapID or xs ~= lastX or ys ~= lastY then
      -- World coordinates too, continuous across map changes, in the same order as
      -- GetWorldPosFromMapPos (north-south first). The height is always 0.
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
-- The periodic lines. A tick during a loading screen leaves them due for the
-- first tick after it, unless the screen has been up longer than a period.
---------------------------------------------------------------------------

local periodicDue = false
local loadingSince   -- GetTime() when the loading screen now up appeared; nil when none is

-- The end of a loading screen writes LOADSCREEN, how long it was up in seconds.
function WJ.onLoadingScreen(shown)
  if not shown and loadingSince then
    WJ.write("LOADSCREEN", string.format("%.1f", GetTime() - loadingSince))
  end
  loadingSince = shown and GetTime() or nil
end

local function loadingScreenUp()
  return loadingSince ~= nil and GetTime() - loadingSince < WJ.TIMER_PERIOD
end

WJ.loadingScreenUp = loadingScreenUp

local function writePeriodic()
  WJ.write("TIME", GetServerTime())
  WJ.snapshot()
end

-- Each part guarded on its own: an error in one is its own ERR line and the others still run.
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

-- On any PLAYER_ENTERING_WORLD forget the last sample, so the next tick writes a
-- fresh POS or NOPOS; maps seen stay seen for the session.
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
