-- The test runner. Each file it is given registers tests with test(name, [options], body); the
-- body gets a fresh game (tools/harness/client.lua) and plays the addon through it. A test runs
-- once per client profile it names (options.clients, default both, or options.client for one),
-- on a game of its own. Failures from expect, eq and fail are collected and the test goes on, so
-- one run shows everything that is wrong; a Lua error ends the test and is reported with where.
--
-- After a body returns, the run also fails the test if the recorder wrote an ERR line (unless
-- options.errAllowed), a SPEECH line (speech is switched off), or said Problem in chat (unless
-- options.problemAllowed), and if the body called nothing on the game at all.
--
-- Run from the addon's folder, naming the test files:
--   npx --yes -p fengari-node-cli fengari tools/harness/run.lua [--version 0.6.3] tools/tests/*.lua
-- The exit code is the number of failed tests, 0 when every test passed.

local HARNESS_DIR = (arg and arg[0] and arg[0]:match("^(.-)[^/\\]+$")) or ""
local ADDON_DIR = HARNESS_DIR:match("^(.-)tools[/\\]harness[/\\]$") or (HARNESS_DIR .. "../../")
local client = assert(loadfile(HARNESS_DIR .. "client.lua"))()

local files, version = {}, nil
do
  local i = 1
  while i <= #arg do
    if arg[i] == "--version" then version, i = arg[i + 1], i + 2
    else files[#files + 1], i = arg[i], i + 1 end
  end
end
if #files == 0 then
  print("no test files named")
  os.exit(2)
end

local tests = {}
local current          -- the test being run: its failures go here

local function note(message)
  if not current then error("expect outside a test: " .. tostring(message), 2) end
  current.failures[#current.failures + 1] = message
end

-- The three ways a test says what it found.
function expect(ok, message) if not ok then note(message or "expected something that wasn't so") end end
function fail(message) note(message) end
function eq(got, want, what)
  if got ~= want then note((what or "value") .. ": got " .. tostring(got) .. ", wanted " .. tostring(want)) end
end
-- A list of strings against another, as "a / b / c".
function same(got, want, what)
  local g, w = table.concat(got, " / "), table.concat(want, " / ")
  if g ~= w then note((what or "list") .. ": got " .. g .. ", wanted " .. w) end
end

function test(name, options, body)
  if body == nil then body, options = options, {} end
  local clients = options.clients or (options.client and { options.client }) or { "forever", "retail" }
  for _, profile in ipairs(clients) do
    tests[#tests + 1] = { name = name, profile = profile, options = options, body = body }
  end
end

for _, file in ipairs(files) do
  local chunk = assert(loadfile(file))
  chunk()
end

local passed, failed = 0, 0
for _, t in ipairs(tests) do
  current = { failures = {} }
  local game = client.newGame(t.profile, ADDON_DIR, version)
  local ok, err = xpcall(function() t.body(game) end, debug.traceback)
  if not ok then note("error: " .. tostring(err)) end
  if ok then
    if not t.options.errAllowed then
      for _, l in ipairs(game.lines("ERR")) do note("the recorder wrote ERR " .. table.concat(l.fields, " ")) end
    end
    for _, l in ipairs(game.lines("SPEECH")) do note("the recorder wrote SPEECH " .. table.concat(l.fields, " ")) end
    if not t.options.problemAllowed then
      local said = game.said("Problem")
      if said then note("the recorder said something went wrong in chat: " .. said) end
    end
  end
  if #current.failures == 0 then
    passed = passed + 1
    print(string.format("ok    %-8s %s", t.profile, t.name))
  else
    failed = failed + 1
    print(string.format("FAIL  %-8s %s", t.profile, t.name))
    for _, f in ipairs(current.failures) do print("        " .. f:gsub("\n", "\n        ")) end
  end
end
current = nil

print(string.format("-- %d passed, %d failed, %d test files", passed, failed, #files))
os.exit(failed > 0 and math.min(failed, 125) or 0)
