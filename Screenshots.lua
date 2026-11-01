-- Widsith — Screenshots
--
-- SHOT: the game saved a screenshot. The player's own are only noted, and
-- nothing about them changes. With "Screenshot highlights" turned on the addon
-- also takes some itself: each new level, a boss's first defeat, the first time
-- in a zone, the first mount, the first death, and every death on a Hardcore
-- realm. Those lines say which moment it was, which tells them from the player's.
--
-- For the length of one of its own shots the addon hides chat, whispers
-- included, and draws a small mark in the very corner of the screen, worked out
-- from the character, the session and the second. The game answers within about
-- a tenth of a second and both go back. Chat frames aren't protected, so this
-- works in combat. What is hidden is made transparent rather than hidden, which
-- would disturb how the windows are docked.

local _, WJ = ...

local write, counts = WJ.write, WJ.counts
local handlers = WJ.handlers

WJ.SHOT_GAP = 30         -- s between shots, unless the later moment matters more
local LOADING_RETRIES = 30   -- s to wait for a loading screen to end before giving a shot up
local ANSWER_WAIT = 3    -- s before chat comes back if the game says nothing

-- How long after the moment the picture is taken, and which wins when two fall
-- together: a boss's last blow is often the level-up too.
local MOMENTS = {
  death = { wait = 1,   rank = 5 },
  boss  = { wait = 2,   rank = 4 },
  level = { wait = 1.5, rank = 3 },
  mount = { wait = 3,   rank = 2 },
  zone  = { wait = 3,   rank = 1 },
}

local MARK_PATCHES, MARK_PIXELS = 4, 2   -- four patches, 2 by 2 pixels, each one of 64 colours
local MARK_LEVELS = { 0, 85 / 255, 170 / 255, 1 }

-- The parts Blizzard's code moves together with chat, and the pop-ups beside it.
local CHAT_WINDOW_PARTS = { "", "Tab", "EditBox", "ButtonFrame", "Minimized" }
local CHAT_SHARED_PARTS = {
  "GeneralDockManager", "ChatMenu", "TextToSpeechButtonFrame", "QuickJoinToastButton",
  "ChatFrameMenuButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton",
  "ChatFrameToggleVoiceMuteButton", "ChatAlertFrame", "BNToastFrame",
}

local pending          -- the moment waiting for its picture
local taking           -- which moment the screenshot now being taken is for
local lastShotAt, lastShotRank
local hiddenChat = {}  -- frame -> the alpha to put back
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
-- Chat
---------------------------------------------------------------------------

local function chatParts()
  local parts, seen = {}, {}
  local function add(frame)
    if type(frame) == "table" and frame.SetAlpha and not seen[frame] then
      seen[frame] = true
      parts[#parts + 1] = frame
    end
  end
  for _, name in pairs(CHAT_FRAMES or {}) do
    for _, suffix in ipairs(CHAT_WINDOW_PARTS) do add(_G[name .. suffix]) end
  end
  for _, name in ipairs(CHAT_SHARED_PARTS) do add(_G[name]) end
  return parts
end

local function hideChat()
  for _, frame in ipairs(chatParts()) do
    local ok, alpha = pcall(frame.GetAlpha, frame)
    if not ok or type(alpha) ~= "number" or (issecretvalue and issecretvalue(alpha)) then alpha = 1 end
    hiddenChat[frame] = alpha
    pcall(frame.SetAlpha, frame, 0)
  end
end

local function showChat()
  for frame, alpha in pairs(hiddenChat) do
    pcall(frame.SetAlpha, frame, alpha)
    hiddenChat[frame] = nil
  end
end

---------------------------------------------------------------------------
-- The mark
---------------------------------------------------------------------------

-- Plain arithmetic in floating point, with every step under 2^53, where such a
-- number is still exact, so the same sum comes out in any Lua.
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

-- Sizes are one real pixel in the frame's own units, worked out each time in
-- case the window has changed.
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
  showChat()
  if mark then mark:Hide() end
end

local function take(moment)
  local this = { why = moment.why }
  taking = this
  lastShotAt, lastShotRank = GetTime(), MOMENTS[moment.why].rank
  if moment.key ~= nil then seenList(moment.why)[moment.key] = true end
  -- First, so that nothing that goes wrong below can leave chat hidden.
  C_Timer.After(ANSWER_WAIT, function()
    if taking == this then putBack() end
  end)
  hideChat()
  showMark()
  Screenshot()
end

handlers.SCREENSHOT_SUCCEEDED = function()
  if taking then write("SHOT", taking.why) else write("SHOT") end
  counts.shots = counts.shots + 1
  if taking then putBack() end
end

handlers.SCREENSHOT_FAILED = function()
  if taking then putBack() end
end

local function whenReady(moment, retries)
  if pending ~= moment then return end
  if WJ.loadingScreenUp() and retries > 0 then
    C_Timer.After(1, WJ.guard("shot", function() whenReady(moment, retries - 1) end))
    return
  end
  pending = nil
  -- Paused, nothing is recorded, so nothing is taken either.
  if not WJ.isRecording() or taking then return end
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
  C_Timer.After(MOMENTS[why].wait, WJ.guard("shot", function() whenReady(moment, LOADING_RETRIES) end))
end
