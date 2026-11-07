-- The extras (Extras.lua, and the counters in Moments.lua): recipes known, gear sets and the swaps
-- between them, talents and spec, currencies, reputations, the game's own counters, and the
-- character table the file keeps beside the sessions.

-- A gear set's items as GEARSET writes them: slots 1 to 19 in order, an empty element where the
-- set has nothing.
local function slotList(items)
  local out = {}
  for slot = 1, 19 do out[slot] = items[slot] and tostring(items[slot]) or "" end
  return table.concat(out, ",")
end

-- The lines of a kind written after the n-th one of the session's lines.
local function since(game, n, kind)
  local out = {}
  for i, l in ipairs(game.lines()) do
    if i > n and (kind == nil or l.kind == kind) then out[#out + 1] = l end
  end
  return out
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------

test("the player's own profession window writes one RECIPES once it has loaded, and again only when a recipe is learned", function(game)
  game.login()
  game.advance(8)
  eq(#game.lines("RECIPES"), 0, "RECIPES lines before any window was opened")
  -- The player opens their own profession window. It hasn't loaded at the first event; the
  -- list updates twice as it does, and once more with nothing changed.
  game.fire("TRADE_SKILL_SHOW")
  game.world.window.ready = true
  game.fire("TRADE_SKILL_LIST_UPDATE")
  game.fire("TRADE_SKILL_LIST_UPDATE")
  game.advance(1)
  game.fire("TRADE_SKILL_LIST_UPDATE")
  game.advance(1)
  -- The profession is Skinning (393). GetAllRecipeIDs lists every recipe, learned or not: one ID
  -- is hidden and one recipe's learned flag is hidden, and neither is written.
  same(game.fieldsOf("RECIPES"), { "393 8613,10662 all" }, "the RECIPES lines once the window loaded, read twice")
  -- A recipe learned: one more line, with the whole list.
  game.world.recipes[8617] = true
  game.fire("TRADE_SKILL_LIST_UPDATE")
  game.advance(1)
  same(game.fieldsOf("RECIPES"), { "393 8613,10662 all", "393 8613,8617,10662 all" }, "the RECIPES lines after a recipe was learned")
end)

test("someone else's linked profession window and an NPC's write no RECIPES", function(game)
  game.login()
  game.advance(8)
  game.world.window.ready = true
  game.world.recipes[19047] = true
  -- A profession linked in chat: the window shows someone else's recipes.
  game.world.window.linked = true
  game.fire("TRADE_SKILL_SHOW")
  game.advance(1)
  eq(#game.lines("RECIPES"), 0, "RECIPES lines from someone else's linked window")
  -- An NPC's crafting window.
  game.world.window.linked, game.world.window.npc = false, true
  game.fire("TRADE_SKILL_DATA_SOURCE_CHANGED")
  game.advance(1)
  eq(#game.lines("RECIPES"), 0, "RECIPES lines from an NPC's window")
end)

test("a client without GetAllRecipeIDs writes the window's own list, marked as filtered", function(game)
  game.login()
  game.advance(8)
  game.world.window.ready = true
  local allRecipeIDs = game.G.C_TradeSkillUI.GetAllRecipeIDs
  game.G.C_TradeSkillUI.GetAllRecipeIDs = nil
  game.fire("TRADE_SKILL_SHOW")
  game.advance(1)
  game.G.C_TradeSkillUI.GetAllRecipeIDs = allRecipeIDs
  -- GetFilteredRecipeIDs answers what the window shows, the two learned recipes.
  same(game.fieldsOf("RECIPES"), { "393 8613,10662 filtered" }, "the RECIPES line from the window's own list")
end)

---------------------------------------------------------------------------
-- Gear sets
---------------------------------------------------------------------------

test("the opening writes one GEARSET per set, and a hidden ID in the list deletes nothing", function(game)
  game.login()
  game.advance(8)
  -- GEARSET setID name itemIDs ignoredSlots specID iconFileID. The first set leaves slot 4 alone
  -- (and a slot the game hides, left out) and is assigned to the first spec (1491); the second
  -- has neither. The list also holds an ID the game hid, so no set can be called deleted.
  local sets = game.lines("GEARSET")
  eq(#sets, 2, "GEARSET lines at the opening")
  same(sets[1] and sets[1].fields or {}, { "0", "Questing", slotList({ [1] = 10001, [5] = 10002, [16] = 25 }), "4", "1491", "132347" }, "the first set's GEARSET")
  same(sets[2] and sets[2].fields or {}, { "1", "Tank", slotList({ [1] = 10001, [5] = 10003, [16] = 2209 }), "", "", "134952" }, "the second set's GEARSET")
end)

test("a set put on writes GEARSWAP with the time the swap was announced", function(game)
  game.login()
  game.advance(8)
  -- A swap announced, two slots changing, the finish; then a second finish the game gives with
  -- the set's ID hidden and no swap announced before it.
  game.fire("EQUIPMENT_SWAP_PENDING")
  game.advance(0.2)
  game.fire("PLAYER_EQUIPMENT_CHANGED", 5, false)
  game.fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
  game.advance(0.1)
  game.fire("EQUIPMENT_SWAP_FINISHED", true, 1)
  game.fire("EQUIPMENT_SWAP_FINISHED", false, game.SECRET)
  game.advance(2)
  -- GEARSWAP setID result startT.
  local swaps = game.lines("GEARSWAP")
  eq(#swaps, 2, "GEARSWAP lines")
  local first = swaps[1]
  if first then
    eq(first.fields[1], "1", "the swap's set")
    eq(first.fields[2], "1", "the swap's result")
    eq(tonumber(first.fields[3]), first.t - 300, "the swap's start, against the finish 300 ms later")
  end
  -- The second: the hidden ID and the start are empty, the result is the game's.
  same(swaps[2] and swaps[2].fields or {}, { "", "0", "" }, "the second GEARSWAP, with its set hidden and no swap announced")
  -- The slots the swap changed were written as EQUIP between the two.
  local equips = {}
  for _, l in ipairs(game.lines("EQUIP")) do
    if first and l.t <= first.t and l.t >= first.t - 300 then equips[#equips + 1] = l.fields[1] end
  end
  same(equips, { "5", "16" }, "the swap's EQUIP lines")
end)

test("a set renamed and the other deleted write one GEARSET each, and a change with nothing new writes none", function(game)
  game.login()
  game.advance(8)
  local before = #game.lines()
  game.world.sets[1].name = "Defence"
  game.world.sets[0] = nil
  game.world.setListHidden = false
  game.fire("EQUIPMENT_SETS_CHANGED")
  game.fire("EQUIPMENT_SETS_CHANGED")
  game.advance(1)
  -- The renamed set in full, then the deleted one as its ID with every other field empty.
  local sets = since(game, before, "GEARSET")
  eq(#sets, 2, "GEARSET lines after a rename and a delete")
  same(sets[1] and sets[1].fields or {}, { "1", "Defence", slotList({ [1] = 10001, [5] = 10003, [16] = 2209 }), "", "", "134952" }, "the renamed set's GEARSET")
  same(sets[2] and sets[2].fields or {}, { "0", "", "", "", "", "" }, "the deleted set's GEARSET")
  -- The event again, with nothing changed: nothing.
  before = #game.lines()
  game.fire("EQUIPMENT_SETS_CHANGED")
  game.advance(1)
  eq(#since(game, before, "GEARSET"), 0, "GEARSET lines from a change event with nothing changed")
end)

test("a gear set holding an item the game hid writes nothing", function(game)
  game.login()
  game.advance(8)
  local before = #game.lines()
  -- A hidden item would read as a changed set, so the set isn't read at all.
  game.world.sets[1].items[5] = game.SECRET
  game.fire("EQUIPMENT_SETS_CHANGED")
  game.advance(1)
  eq(#since(game, before, "GEARSET"), 0, "GEARSET lines for a set with a hidden item")
end)

---------------------------------------------------------------------------
-- Talents and spec
---------------------------------------------------------------------------

test("the opening writes the spec and the talent tree", function(game)
  game.login()
  game.advance(8)
  -- SPEC specID name.
  same(game.fieldsOf("SPEC"), { "1491 Warrior" }, "the opening SPEC lines")
  -- TALENTS specGroup configID treeID nodes importString: the nodes with points bought, as
  -- nodeID:entryID:rank in node order; the node the tree grants without a point (9005) is left out.
  local talents = game.lines("TALENTS")
  eq(#talents, 1, "TALENTS lines at the opening")
  same(talents[1] and talents[1].fields or {}, { "1", "101", "790", "9001:19001:1,9003:19003:2", "BcQAAAAAAAAAAAAAAAAAAAAA1" }, "the opening TALENTS")
end)

test("a talent point writes TALENTS once applied, never while staged, and again for the other spec group", function(game)
  game.login()
  game.advance(8)
  -- A point staged: nothing written.
  game.world.talent.staged, game.world.talent.bought[9002] = true, 1
  game.fire("TRAIT_CONFIG_UPDATED", 101)
  game.advance(1)
  eq(#game.lines("TALENTS"), 1, "TALENTS lines while a point was staged, the opening's included")
  -- Applied: one TALENTS.
  game.world.talent.staged = false
  game.fire("TRAIT_CONFIG_UPDATED", 101)
  game.fire("PLAYER_TALENT_UPDATE")
  game.advance(1)
  -- The same tree again: nothing.
  game.fire("PLAYER_TALENT_UPDATE")
  game.advance(1)
  -- The other spec group: one more. The spec itself is the same, so no SPEC line.
  game.world.talent.group = 2
  game.fire("ACTIVE_TALENT_GROUP_CHANGED", 2, 1)
  game.fire("PLAYER_SPECIALIZATION_CHANGED", "player")
  game.advance(1)
  same(game.fieldsOf("TALENTS"), {
    "1 101 790 9001:19001:1,9003:19003:2 BcQAAAAAAAAAAAAAAAAAAAAA1",
    "1 101 790 9001:19001:1,9002:19002:1,9003:19003:2 BcQAAAAAAAAAAAAAAAAAAAAA1",
    "2 102 790 9001:19001:1,9002:19002:1,9003:19003:2 BcQAAAAAAAAAAAAAAAAAAAAA2",
  }, "the TALENTS lines")
  eq(#game.lines("SPEC"), 1, "SPEC lines after a switch of spec group within one spec")
end)

test("a talent node the game hid writes no TALENTS, rather than a point taken back", function(game)
  game.login()
  game.advance(8)
  -- Node 9002 has a point bought and is then hidden. Leaving it out would read as the point
  -- taken back, so nothing is written until the tree can be read whole.
  game.world.talent.bought[9002] = 1
  game.world.talent.secretNode = true
  game.fire("TRAIT_CONFIG_UPDATED", 101)
  game.advance(1)
  eq(#game.lines("TALENTS"), 1, "TALENTS lines after a change with a node hidden, the opening's included")
  -- Once the node can be read, the change is written.
  game.world.talent.secretNode = false
  game.fire("TRAIT_CONFIG_UPDATED", 101)
  game.advance(1)
  eq(#game.lines("TALENTS"), 2, "TALENTS lines once the node could be read again")
end)

---------------------------------------------------------------------------
-- Currencies and reputations
---------------------------------------------------------------------------

test("the opening writes each listed currency with its amount and no change, and never expands the list", function(game)
  game.login()
  game.advance(8)
  -- CURRENCY currencyID quantity change gainSource destroyReason. The Currency tab lists two
  -- currencies under headers, a third whose amount the game hides (left out), and a collapsed
  -- group that is never opened.
  local lines = game.lines("CURRENCY")
  local got = {}
  for _, l in ipairs(lines) do got[#got + 1] = table.concat(l.fields, "|") end
  same(got, { "3498|12|||", "3500|0|||" }, "the opening CURRENCY lines aren't the two listed currencies with plain amounts and no change")
  eq(game.world.currencyExpanded, 0, "the recorder expanded the player's currency list")
end)

test("the opening writes a REP line for each faction the Reputation pane lists", function(game)
  game.login()
  game.advance(8)
  -- REP factionID reaction standing delta label, the delta empty at the opening. This pins what
  -- the recorder does today with the pane in client.lua: a plain header (Alliance) is skipped, a
  -- header with a standing of its own (Gilneas) is written as a faction, a faction whose ID the
  -- game hides is left out, and Stormwind, listed twice, is written once.
  local got = {}
  for _, l in ipairs(game.lines("REP")) do got[#got + 1] = table.concat(l.fields, "|") end
  same(got, { "72|5|3150||Stormwind", "47|4|0||Ironforge", "1134|6|9500||Gilneas" }, "the opening REP lines")
end)

---------------------------------------------------------------------------
-- The game's counters
---------------------------------------------------------------------------

test("the counters are read by index at the opening, across frames, and by ID after", function(game)
  game.login()
  game.advance(8)
  -- TALLY counterID value label. Every counter with a value, its name the first time: the money
  -- counter (formatted text with a coin icon) and one that never moved ("--") are left out.
  same(game.fieldsOf("TALLY"), { "107 85 Creatures killed", "108 4 Critters killed", "60 1 Total deaths",
    "347 1 Food eaten", "1336 49 (Humanoid) Creature type killed the most" }, "the opening TALLY lines")
  eq(game.world.byIDReads, 0, "counters read by ID before the opening pass had learnt the IDs")
  local openingFrames = 0
  for _ in pairs(game.world.statFrames) do openingFrames = openingFrames + 1 end
  expect(openingFrames >= 2, "the opening pass read every counter in " .. openingFrames .. " frame: it should be spread across frames")
  -- Food eaten: the game says something moved, and the counters are read again two seconds later.
  local before = #game.lines()
  game.world.stat[347] = "2"
  game.fire("CRITERIA_UPDATE")
  game.advance(3)
  -- Only the counter that changed is written, without its name this time.
  local tallies = since(game, before, "TALLY")
  eq(#tallies, 1, "TALLY lines after one counter changed")
  same(tallies[1] and tallies[1].fields or {}, { "347", "2", "" }, "the changed counter's TALLY")
  -- A fight: a creature killed, and the type killed the most moves on; read a second after it.
  before = #game.lines()
  game.world.combat = true
  game.fire("PLAYER_REGEN_DISABLED")
  game.advance(2)
  game.world.combat = false
  game.fire("PLAYER_REGEN_ENABLED")
  game.world.stat[107] = "86"
  game.world.stat[1336] = "50 (Humanoid)"
  game.advance(3)
  same(game.fieldsOf("TALLY"), { "107 85 Creatures killed", "108 4 Critters killed", "60 1 Total deaths",
    "347 1 Food eaten", "1336 49 (Humanoid) Creature type killed the most", "347 2 ", "107 86 ", "1336 50 (Humanoid) " },
    "the TALLY lines after the fight")
  local framesWithReads = 0
  for _ in pairs(game.world.statFrames) do framesWithReads = framesWithReads + 1 end
  expect(framesWithReads >= 4, "the counters were read in " .. framesWithReads .. " frames: a pass should be spread across frames")
  expect(game.world.byIDReads > 0, "no counter was read by ID: every pass after the first should be")
end)

test("a nudge from the game with no counter changed writes no TALLY", function(game)
  game.login()
  game.advance(8)
  local before = #game.lines()
  game.fire("CRITERIA_UPDATE")
  game.advance(3)
  expect(game.world.byIDReads > 0, "the counters weren't read again after the game said something moved")
  eq(#since(game, before, "TALLY"), 0, "TALLY lines when no counter changed")
end)

---------------------------------------------------------------------------
-- The character table
---------------------------------------------------------------------------

test("the character table holds the first name and the surname apart, with the realm, class and race", function(game)
  game.login()
  game.advance(8)
  local c = game.G.WidsithDB and game.G.WidsithDB.character
  expect(c ~= nil, "no character table in the saved file")
  if not c then return end
  -- On WoW Forever every character has a surname; Retail gives none.
  expect(c.name == "Aldwin" and c.surname == game.character.surname,
    "the character table doesn't hold the first name and the surname apart: " .. tostring(c.name) .. " / " .. tostring(c.surname))
  if game.profile.label == "forever" then eq(c.surname, "Thornby", "the surname on Forever") else eq(c.surname, nil, "the surname on Retail") end
  eq(c.guid, game.character.guid, "the character's GUID")
  eq(c.realm, game.profile.realm, "the realm")
  eq(c.realmN, game.profile.realmN, "the normalised realm")
  eq(c.region, game.profile.region, "the region")
  eq(c.classID, 1, "the class ID")
  eq(c.raceID, 1, "the race ID")
end)
