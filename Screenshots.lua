-- Widsith — Screenshots
--
-- SHOT: the game saved a screenshot. The player's own are only noted. With
-- "Screenshot highlights" on, the addon takes some itself: each new level, a
-- boss's first defeat, the first time in a zone or an instance, the first mount,
-- the first death, and every death on a Hardcore realm.
--
-- For its own shots it hides the social windows, and chat unless "Show chat in
-- the pictures" is on, and draws a small mark in the corner, until the game
-- answers; the line names the moment and says when chat was left in. Windows are
-- made transparent rather than hidden, which would disturb chat docking, and
-- chat frames aren't protected, so this works in combat.

local _, WJ = ...

local write, counts = WJ.write, WJ.counts
local handlers = WJ.handlers

WJ.SHOT_GAP = 30         -- s between shots, unless the later moment matters more
local HOLD_LIMIT = 30    -- s a shot can wait for a clear screen before it is given up
local ANSWER_WAIT = 3    -- s before chat comes back if the game says nothing

-- How long after the moment the picture is taken, and which wins when two fall
-- together. A picture of a place waits while the world map covers it.
local MOMENTS = {
  death    = { wait = 1,   rank = 5 },
  boss     = { wait = 2,   rank = 4 },
  level    = { wait = 1.5, rank = 3 },
  mount    = { wait = 3,   rank = 2 },
  instance = { wait = 3,   rank = 2, place = true },
  zone     = { wait = 3,   rank = 1, place = true },
}

local MARK_PATCHES, MARK_PIXELS = 4, 2
local MARK_LEVELS = { 0, 85 / 255, 170 / 255, 1 }

-- The parts Blizzard's code moves together with chat, and the buttons beside it.
local CHAT_WINDOW_PARTS = { "", "Tab", "EditBox", "ButtonFrame", "Minimized" }
local CHAT_SHARED_PARTS = {
  "GeneralDockManager", "ChatMenu", "TextToSpeechButtonFrame",
  "ChatFrameMenuButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton",
  "ChatFrameToggleVoiceMuteButton",
}
-- The social windows, hidden whatever the settings say: friends, communities,
-- and the Battle.net and whisper pop-ups.
local SOCIAL_PARTS = {
  "FriendsFrame", "FriendsTooltip", "FriendsFriendsFrame", "CommunitiesFrame",
  "BNToastFrame", "QuickJoinToastButton", "ChatAlertFrame",
}

local pending          -- the moment waiting for its picture
local taking           -- which moment the screenshot now being taken is for
local lastShotAt, lastShotRank
local ownShotSecond    -- the second, by the computer's clock, of the player's own last screenshot
local hidden = {}      -- frame -> the alpha to put back
local mark, patches

---------------------------------------------------------------------------
-- What has already had its picture, kept with the character's settings
---------------------------------------------------------------------------

local function seenList(why)
  if not WidsithUI then return {} end
  WidsithUI.shotsSeen = WidsithUI.shotsSeen or {}
  WidsithUI.shotsSeen[why] = WidsithUI.shotsSeen[why] or {}
  return WidsithUI.shotsSeen[why]
end

---------------------------------------------------------------------------
-- What leaves the screen for the picture
---------------------------------------------------------------------------

local function partsToHide(chatToo)
  local parts, seen = {}, {}
  local function add(frame)
    if type(frame) == "table" and frame.SetAlpha and not seen[frame] then
      seen[frame] = true
      parts[#parts + 1] = frame
    end
  end
  for _, name in ipairs(SOCIAL_PARTS) do add(_G[name]) end
  if chatToo then
    for _, name in pairs(CHAT_FRAMES or {}) do
      for _, suffix in ipairs(CHAT_WINDOW_PARTS) do add(_G[name .. suffix]) end
    end
    for _, name in ipairs(CHAT_SHARED_PARTS) do add(_G[name]) end
  end
  return parts
end

local function hideParts(chatToo)
  for _, frame in ipairs(partsToHide(chatToo)) do
    local ok, alpha = pcall(frame.GetAlpha, frame)
    if not ok or type(alpha) ~= "number" or (issecretvalue and issecretvalue(alpha)) then alpha = 1 end
    hidden[frame] = alpha
    pcall(frame.SetAlpha, frame, 0)
  end
end

local function showParts()
  for frame, alpha in pairs(hidden) do
    pcall(frame.SetAlpha, frame, alpha)
    hidden[frame] = nil
  end
end

---------------------------------------------------------------------------
-- The mark
---------------------------------------------------------------------------

local function markCode(guid, session, second)
  local text = guid .. "|" .. string.format("%d", session) .. "|" .. string.format("%d", second)
  local h = 7.0
  for i = 1, #text do h = (h * 1000003 + text:byte(i)) % 2147483647 end
  for _ = 1, 3 do h = (h * 1000003 + 1) % 2147483647 end
  return h % 16777216
end
WJ.markCode = markCode

-- On the world's own frame, so a hidden interface doesn't take the mark with it.
local function buildMark()
  mark = CreateFrame("Frame", nil, WorldFrame)
  mark:SetFrameStrata("TOOLTIP")
  mark:SetFrameLevel(9000)
  mark:Hide()
  patches = {}
  for i = 1, MARK_PATCHES do
    local patch = mark:CreateTexture(nil, "OVERLAY")
    patch:SetSnapToPixelGrid(false)
    patch:SetTexelSnappingBias(0)
    patches[i] = patch
  end
end

-- Sized in real pixels, worked out each time in case the window has changed.
local function showMark()
  if not mark then buildMark() end
  local _, height = GetPhysicalScreenSize()
  local pixel = (768 / height) / mark:GetEffectiveScale()
  local size = MARK_PIXELS * pixel
  mark:ClearAllPoints()
  mark:SetPoint("TOPLEFT", WorldFrame, "TOPLEFT", 0, 0)
  mark:SetSize(MARK_PATCHES * size, size)
  local code = markCode(UnitGUID("player"), WJ.sessionStartedAt(), math.floor(WJ.nowMs() / 1000))
  for i, patch in ipairs(patches) do
    local value = math.floor(code / 64 ^ (MARK_PATCHES - i)) % 64
    local r, g, b = math.floor(value / 16), math.floor(value / 4) % 4, value % 4
    patch:SetColorTexture(MARK_LEVELS[r + 1], MARK_LEVELS[g + 1], MARK_LEVELS[b + 1], 1)
    patch:ClearAllPoints()
    patch:SetPoint("TOPLEFT", mark, "TOPLEFT", (i - 1) * size, 0)
    patch:SetSize(size, size)
  end
  mark:Show()
end

---------------------------------------------------------------------------
-- Taking one
---------------------------------------------------------------------------

local function putBack()
  taking = nil
  showParts()
  if mark then mark:Hide() end
end

local function take(moment)
  local this = { why = moment.why, chatShown = WJ.getIconSetting("shotsChat") == true }
  taking = this
  lastShotAt, lastShotRank = GetTime(), MOMENTS[moment.why].rank
  if moment.key ~= nil then seenList(moment.why)[moment.key] = true end
  -- First, so that nothing that goes wrong below can leave anything hidden.
  C_Timer.After(ANSWER_WAIT, WJ.guard("shot", function()
    if taking == this then putBack() end
  end))
  hideParts(not this.chatShown)
  showMark()
  Screenshot()
end

handlers.SCREENSHOT_SUCCEEDED = function()
  if not taking then
    ownShotSecond = time()
    write("SHOT")
  elseif taking.chatShown then
    write("SHOT", taking.why, 1)
  else
    write("SHOT", taking.why)
  end
  counts.shots = counts.shots + 1
  if taking then putBack() end
end

handlers.SCREENSHOT_FAILED = function()
  if taking then putBack() end
end

-- The zone a map belongs to, walking up from a cave or a town's own small map.
-- A zone's text can't do this: some small areas name themselves as a zone.
local function realZone()
  local mapID = WJ.currentPosition()
  local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
  for _ = 1, 8 do
    if not mapID or mapID == 0 then return nil end
    local info = C_Map.GetMapInfo(mapID)
    if not info then return nil end
    if info.mapType == zoneType then return mapID end
    if info.mapType < zoneType then return nil end
    mapID = info.parentMapID
  end
end

local function screenIsBusy(moment)
  return WJ.loadingScreenUp() or (MOMENTS[moment.why].place and WJ.mapIsOpen())
end

-- A shot given up here isn't marked as seen, so a later chance can still take it.
local function whenReady(moment, retries)
  if pending ~= moment then return end
  if screenIsBusy(moment) and retries > 0 then
    C_Timer.After(1, WJ.guard("shot", function() whenReady(moment, retries - 1) end))
    return
  end
  -- The game names a screenshot's file after its second, so one taken in the
  -- same second as the player's own would replace theirs: wait a second.
  if ownShotSecond == time() then
    C_Timer.After(1, WJ.guard("shot", function() whenReady(moment, retries) end))
    return
  end
  pending = nil
  -- Nothing is taken while paused, or if the setting was turned off meanwhile.
  if not WJ.isRecording() or not WJ.getIconSetting("screenshots") or taking or screenIsBusy(moment) then return end
  if moment.why == "zone" and realZone() ~= moment.key then return end
  take(moment)
end

local function isHardcore()
  local check = C_GameRules and C_GameRules.IsHardcoreActive
  if not check then return false end
  local ok, active = pcall(check)
  return ok and active == true
end

-- `key` names what can only have one picture: the boss, the zone, the first of
-- something. None means every time.
function WJ.highlightShot(why, key)
  if not WJ.getIconSetting("screenshots") then return end
  if why == "death" and isHardcore() then key = nil end
  if key ~= nil and seenList(why)[key] then return end
  local rank = MOMENTS[why].rank
  if lastShotAt and GetTime() - lastShotAt < WJ.SHOT_GAP and rank <= lastShotRank then return end
  if pending and MOMENTS[pending.why].rank >= rank then return end
  local moment = { why = why, key = key }
  pending = moment
  C_Timer.After(MOMENTS[why].wait, WJ.guard("shot", function() whenReady(moment, HOLD_LIMIT) end))
end

function WJ.zoneChanged()
  if IsInInstance() then return end
  local zone = realZone()
  if zone then WJ.highlightShot("zone", zone) end
end
