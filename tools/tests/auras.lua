-- Auras on the character (Moments.lua): AURA has, gain, gone and lose, with the caster's GUID and
-- name; nothing read while the game hides auras (in a fight, in an encounter); an aura whose spell
-- is always hidden never written; and a read the game refuses never written as ERR.
--
-- An AURA line's fields: how, spell ID, helpful, duration, stacks, the character's own, name,
-- the caster's GUID, the caster's name.

-- Whether any line in a list of "kind fields" strings starts with the prefix.
local function has(list, prefix)
  for _, l in ipairs(list) do if l:sub(1, #prefix) == prefix then return true end end
  return false
end

-- The first AURA line of a kind for a spell.
local function aura(game, how, spell)
  for _, l in ipairs(game.lines("AURA")) do
    if l.fields[1] == how and l.fields[2] == tostring(spell) then return l end
  end
end
-- A session's lines as "KIND fields", split at its first COMBAT leave.
local function splitAtLeave(game, session)
  local before, after, left = {}, {}, false
  for _, l in ipairs(game.written[session].lines) do
    local text = l.kind .. " " .. table.concat(l.fields, " ")
    local bucket = left and after or before
    bucket[#bucket + 1] = text
    if l.kind == "COMBAT" and l.fields[1] == "leave" then left = true end
  end
  return before, after
end

test("an aura gained and lost out of combat is written as gain then lose, and an unknown removal writes nothing", function(game)
  game.login()
  game.advance(8)
  local opening = #game.lines("AURA")
  -- Food the character ate: announced on arrival, then gone; instance 999 was never announced.
  game.fire("UNIT_AURA", "player", { addedAuras = { { name = "Food", spellId = 433, isHelpful = true, sourceUnit = "player", duration = 18, applications = 0, auraInstanceID = 115 } } })
  game.advance(3)
  game.fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { 115, 999 } })
  local gain = aura(game, "gain", 433)
  expect(gain ~= nil, "the food's arrival wasn't written as AURA gain 433")
  if gain then
    eq(gain.fields[7], "Food", "the food's name")
    eq(gain.fields[8] or "", "", "a caster written for the character's own aura")
  end
  expect(aura(game, "lose", 433) ~= nil, "the food's end wasn't written as AURA lose 433")
  -- After the opening's lines, the food's two follow, and nothing for 999.
  local since = {}
  for i, l in ipairs(game.lines("AURA")) do
    if i > opening then since[#since + 1] = l.fields[1] .. " " .. l.fields[2] end
  end
  same(since, { "gain 433", "lose 433" }, "the AURA lines after the opening")
end)

test("another player's aura carries their GUID and the name the game gives, or the GUID alone", function(game)
  game.login()
  game.advance(8)
  -- A stranger's blessing: the game gives the caster's GUID, and GetPlayerInfoByGUID their name.
  game.fire("UNIT_AURA", "player", { addedAuras = { { name = "Blessing of Might", spellId = 19740, isHelpful = true, duration = 3600, applications = 0, auraInstanceID = 133 } } })
  -- A buff from a player the game can't name (GetPlayerInfoByGUID answers nothing for them).
  game.fire("UNIT_AURA", "player", { addedAuras = { { name = "Arcane Intellect", spellId = 1459, isHelpful = true, duration = 1800, applications = 0, auraInstanceID = 134 } } })
  local blessing, intellect = aura(game, "gain", 19740), aura(game, "gain", 1459)
  expect(blessing and blessing.fields[8] == "Player-4747-0BBBBBBB" and blessing.fields[9] == "Someone",
    "an aura cast by a player wasn't written with their GUID and name")
  expect(intellect and intellect.fields[8] == game.character.guid and (intellect.fields[9] or "") == "",
    "an aura whose caster the game can't name wasn't written with the GUID alone")
  for _, l in ipairs(game.lines("AURA")) do
    expect(l.fields[8] ~= "Player", "the word Player was written for a caster: " .. table.concat(l.fields, " "))
  end
end)

test("nothing is read from auras in a fight, whatever UNIT_AURA carries", function(game)
  game.login()
  game.advance(8)
  local before = #game.lines("AURA")
  game.world.combat = true
  game.fire("PLAYER_REGEN_DISABLED")
  -- The payload hidden whole, its lists hidden, an added aura's fields hidden, and a full update
  -- the game announces while every aura is hidden.
  game.fire("UNIT_AURA", "player", game.SECRET)
  game.fire("UNIT_AURA", "player", { isFullUpdate = game.SECRET, addedAuras = game.SECRET, removedAuraInstanceIDs = game.SECRET })
  game.fire("UNIT_AURA", "player", { addedAuras = { { name = game.SECRET, spellId = game.SECRET, auraInstanceID = game.SECRET } } })
  game.fire("UNIT_AURA", "player", { isFullUpdate = true })
  game.advance(10)
  eq(#game.lines("AURA"), before, "AURA lines written in a fight")
  eq(game.world.auraRefusals, 0, "aura reads the game refused in a fight (C_Secrets said they were hidden)")
end)

test("an aura a fight left is found a second after it, and its end is written", function(game)
  game.login()
  game.advance(8)
  game.world.combat = true
  game.fire("PLAYER_REGEN_DISABLED")
  game.advance(10)
  -- The fight leaves a poison on the character, never announced.
  game.world.present.HARMFUL[1] = { name = "Poison", spellId = 11918, isHelpful = false, sourceUnit = "target", duration = 15, applications = 0, auraInstanceID = 140 }
  game.world.combat = false
  game.fire("PLAYER_REGEN_ENABLED")
  game.advance(3)
  local poison = aura(game, "has", 11918)
  expect(poison ~= nil, "the poison the fight left wasn't found a second after it as AURA has 11918")
  if poison then
    eq(poison.fields[8], "Creature-0-4621-0-46196-30-00003CF70B", "the poison's caster")
    eq(poison.fields[9] or "", "", "a name written for a creature caster")
  end
  -- The poison runs out.
  game.world.present.HARMFUL[1] = nil
  game.fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { 140 } })
  expect(aura(game, "lose", 11918) ~= nil, "the poison's end wasn't written as AURA lose 11918")
end)

test("a full resend with new instance numbers writes no line again", function(game)
  game.login()
  game.advance(8)
  local before = game.fieldsOf("AURA")
  expect(has(before, "has 6673"), "the opening didn't write Battle Shout as AURA has 6673")
  -- The game resends the whole set, with a new instance number for Battle Shout.
  game.world.present.HELPFUL[1].auraInstanceID = 211
  game.fire("UNIT_AURA", "player", { isFullUpdate = true })
  same(game.fieldsOf("AURA"), before, "the AURA lines after a resend of the same set")
end)

test("an opening aura read refused although nothing was said hidden writes no AURA or ERR, and keeps the rest of the opening", function(game)
  game.world.refuseUnforeseen = true
  game.login()
  game.advance(8)
  game.world.refuseUnforeseen = false
  expect(game.world.auraRefusals > 0, "the stand-in never refused the opening aura read")
  eq(#game.lines("AURA", 1), 0, "AURA lines from an opening whose aura read was refused")
  eq(#game.lines("ERR", 1), 0, "ERR lines from an opening whose aura read was refused")
  expect(#game.lines("RULES", 1) > 0 and #game.lines("TALLY", 1) > 0 and #game.lines("CURRENCY", 1) > 0,
    "the opening lost its other lines when the aura read was refused")
end)

test("a session that opens in a fight writes its auras a second after it, never the always-hidden one", function(game)
  game.login()
  game.advance(8)
  game.slash("pause")
  -- One aura's spell is always hidden; another is new to the session.
  game.world.present.HELPFUL[2] = { name = "Hidden", spellId = 99999, isHelpful = true, duration = 0, applications = 0, auraInstanceID = 250, alwaysHidden = true }
  game.world.present.HELPFUL[3] = { name = "Blessing of Kings", spellId = 20217, isHelpful = true, duration = 3600, applications = 0, auraInstanceID = 251 }
  game.world.combat = true
  game.world.fights[#game.world.fights + 1] = { sessionID = 93, name = "Riverpaw Runt", durationSeconds = 6 }
  game.world.meterDuration, game.world.meterTotal = 6, 50
  game.slash("resume")
  game.advance(8)
  game.world.meterDuration, game.world.meterTotal = 14, 120
  game.world.combat = false
  game.fire("PLAYER_REGEN_ENABLED")
  game.advance(3)
  local before, after = splitAtLeave(game, 2)
  expect(has(before, "COMBAT enter"), "the session opened in combat without a COMBAT enter")
  expect(not has(before, "AURA"), "an AURA line was written while the game was hiding auras")
  expect(has(before, "RULES") and has(before, "TALLY") and has(before, "REP"),
    "the opening snapshot lost its other lines when auras were refused")
  expect(has(after, "AURA has 6673") and has(after, "AURA has 20217"),
    "the auras weren't read a second after the fight that the session opened in")
  for _, l in ipairs(game.lines()) do
    local text = table.concat(l.fields, " ")
    expect(not text:find("99999", 1, true), "an always-hidden aura was written: " .. l.kind .. " " .. text)
  end
end)

test("in an encounter on a client without C_Secrets a refused read writes nothing, and an announced aura is still written", function(game)
  game.login()
  game.advance(8)
  -- An encounter's restriction on a client that can't be asked first: the read itself is refused.
  game.G.C_Secrets = nil
  game.world.encounter = true
  local refusedBefore = game.world.auraRefusals
  game.fire("UNIT_AURA", "player", { isFullUpdate = true })
  game.fire("UNIT_AURA", "player", { addedAuras = { { name = "Renew", spellId = 139, isHelpful = true, duration = 15, applications = 0, auraInstanceID = 260 } } })
  expect(game.world.auraRefusals - refusedBefore > 0, "the stand-in never refused a read, so the guard went untested")
  local renew = aura(game, "gain", 139)
  expect(renew ~= nil, "an announced aura went unwritten when its caster couldn't be read")
  if renew then eq(renew.fields[8] or "", "", "a caster written although its read was refused") end
  eq(#game.lines("ERR"), 0, "a refused aura read was written as ERR")
end)
