-- Money (Events.lua): MONEY total kind window said source for every change of gold, with the
-- reason the game gave for it, the window open at the time, the amount the game stated and where
-- the money came from; and, beside it, the quest's levels on QACCEPT and a party member's level
-- on GROUP.
--
-- Each change is the world's total moving and PLAYER_MONEY firing (game.change). The functions
-- the default UI calls to move money are called through game.G, where the recorder has hooked
-- them, as the default UI would call them.

local CORPSE = "Creature-0-4621-0-46196-299-0000C0FFEE"
local CORPSE2 = "Creature-0-4621-0-46196-299-0000C0FFEF"
local VENDOR = "Creature-0-4621-0-46196-1250-00004AAAAA"
local FLIGHT = "Creature-0-4621-0-46196-352-00004BBBBB"
local TRAINER = "Creature-0-4621-0-46196-914-00004CCCCC"

-- The MONEY lines of the login's session, each by how much the total moved from the one before
-- (the first from the total the test started with).
local function moneyRows(game, start)
  local rows, previous = {}, start
  for _, l in ipairs(game.lines("MONEY", 1)) do
    local total = tonumber(l.fields[1])
    rows[#rows + 1] = { delta = total and previous and total - previous, kind = l.fields[2] or "", window = l.fields[3] or "",
      said = l.fields[4] or "", source = l.fields[5] or "", fields = #l.fields }
    previous = total
  end
  return rows
end

-- Each expected row is { what, delta, kind, window, said, source }; there must be one MONEY line
-- for each, in order, with five fields.
local function expectMoney(game, start, expected)
  local rows = moneyRows(game, start)
  expect(#rows == #expected,
    #rows .. " MONEY lines for " .. #expected .. " changes: a reason no change followed wrote a line, or a change wrote none")
  for i, e in ipairs(expected) do
    local m = rows[i]
    local got = m and string.format("%s %s/%s/%s/%s", tostring(m.delta), m.kind, m.window, m.said, m.source) or "nothing"
    expect(m and m.fields == 5 and m.delta == e[2] and m.kind == e[3] and m.window == e[4] and m.said == e[5] and m.source == e[6],
      e[1] .. " isn't written as " .. string.format("%d %s/%s/%s/%s", e[2], e[3], e[4], e[5], e[6]) .. ": " .. got)
  end
end

-- A quest accepted with two objectives, both met, and handed in for 1200 copper: the reward
-- arrives as QUEST_TURNED_IN states it, then PLAYER_MONEY.
local function questScene(game)
  local log = game.world.questLog
  log[#log + 1] = { questID = 100, title = "Boars and a Key", ready = false, level = 4, difficulty = 6, objectives = {
    { numFulfilled = 0, numRequired = 8, type = "monster", text = "Boar slain" },
    { numFulfilled = 0, numRequired = 1, type = "item", text = "Rusty Key" } } }
  local quest = log[#log]
  game.fire("QUEST_ACCEPTED", 100)
  game.advance(2)
  quest.objectives[1].numFulfilled = 8
  quest.objectives[2].numFulfilled = 1
  quest.ready = true
  game.fire("UNIT_QUEST_LOG_CHANGED", "player")
  game.advance(1)
  game.fire("QUEST_TURNED_IN", 100, 250, 1200)
  game.change(1200)
  table.remove(log, #log)
  game.fire("QUEST_REMOVED", 100)
  game.fire("UNIT_QUEST_LOG_CHANGED", "player")
  game.advance(1)
end

test("a quest's level and difficulty level are written when it is accepted", function(game)
  game.login()
  game.advance(8)
  questScene(game)
  local quest
  for _, l in ipairs(game.lines("QACCEPT", 1)) do
    if l.fields[1] == "100" then quest = l end
  end
  expect(quest ~= nil and quest.fields[4] == "4" and quest.fields[5] == "6",
    "a quest's level and difficulty level weren't written at accept: " .. (quest and table.concat(quest.fields, " ", 4) or "no QACCEPT"))
end)

-- Money that moves behind a loading screen, with no reason, is the session tests' case, with
-- the loading screen.
test("a quest's reward is written as quest money with the amount the game stated", function(game)
  game.login()
  game.advance(8)
  local start = game.world.money
  questScene(game)
  expectMoney(game, start, {
    { "a quest's reward", 1200, "quest", "", "1200", "" },
  })
end)

test("a party member's level is written beside them", function(game)
  game.login()
  game.advance(8)
  -- A party of two forms and breaks up.
  game.world.grouped = true
  game.fire("GROUP_ROSTER_UPDATE")
  game.world.grouped = false
  game.fire("GROUP_LEFT")
  local party
  for _, l in ipairs(game.lines("GROUP", 1)) do
    if l.fields[1] == "2" then party = l end
  end
  expect(party ~= nil and party.fields[3] == "1:Player-4747-0CCCCCCC:Maela-" .. game.profile.realmN and party.fields[4] == "7",
    "a party member's level wasn't written beside them: " .. (party and table.concat(party.fields, " ") or "no GROUP"))
end)

test("a corpse's coin names the corpse, and a share of someone else's loot names no one", function(game)
  game.login()
  game.advance(8)
  local start = game.world.money
  -- A corpse's coin: the loot window lists it, the chat message states it.
  game.world.lootSlots = { { type = 2, guid = CORPSE } }
  game.fire("LOOT_OPENED")
  game.fire("CHAT_MSG_MONEY", "You loot 1 Silver, 20 Copper")
  game.change(120)
  game.advance(6)
  -- A share of someone else's loot, with no loot window of the player's own.
  game.fire("CHAT_MSG_MONEY", "Your share of the loot is 45 Copper.")
  game.change(45)
  game.advance(1)
  expectMoney(game, start, {
    { "a corpse's coin", 120, "loot", "", "120", CORPSE },
    { "a share", 45, "share", "", "45", "" },
  })
end)

test("a corpse's coin whose message comes after the change was written keeps the window's reason", function(game)
  game.login()
  game.advance(8)
  local start = game.world.money
  -- The chat message arrives after the change has been written (as the game does under
  -- auto-loot): the window's coin slot is the reason, the message adds nothing late.
  game.world.lootSlots = { { type = 2, guid = CORPSE2 } }
  game.fire("LOOT_OPENED")
  game.change(33)
  game.advance(0.3)
  game.fire("CHAT_MSG_MONEY", "You loot 33 Copper")
  game.advance(1)
  expectMoney(game, start, {
    { "a corpse's coin whose message came late", 33, "loot", "", "", CORPSE2 },
  })
end)

test("a loot message that comes after its change was written explains no change after it", function(game)
  game.login()
  game.advance(8)
  local start = game.world.money
  game.world.lootSlots = { { type = 2, guid = CORPSE2 } }
  game.fire("LOOT_OPENED")
  game.change(33)
  game.advance(0.3)
  game.fire("CHAT_MSG_MONEY", "You loot 33 Copper")
  game.advance(1)
  -- A change the game says nothing about, within two seconds of the late message.
  game.change(5)
  game.advance(1)
  expectMoney(game, start, {
    { "a corpse's coin whose message came late", 33, "loot", "", "", CORPSE2 },
    { "a change with no reason after the late message", 5, "", "", "", "" },
  })
end)

test("a vendor's purchase, sale and repair each name the vendor and the price stated", function(game)
  game.login()
  game.advance(8)
  local start = game.world.money
  -- Two of a stack of five bought, three cloth sold, everything repaired.
  game.world.merchantOpen = true
  game.openWindow("Merchant", VENDOR)
  game.fire("MERCHANT_SHOW")
  game.G.BuyMerchantItem(1, 2)
  game.change(-100)
  game.advance(0.5)
  game.G.C_Container.UseContainerItem(0, 1)
  game.change(30)
  game.advance(0.5)
  game.G.RepairAllItems(false)
  game.change(-340)
  game.advance(0.5)
  game.world.merchantOpen = false
  game.closeWindow("Merchant")
  game.fire("MERCHANT_CLOSED")
  expectMoney(game, start, {
    { "a vendor's purchase", -100, "buy", "merchant", "100", VENDOR },
    { "a sale to a vendor", 30, "sell", "merchant", "30", VENDOR },
    { "a repair", -340, "repair", "merchant", "340", VENDOR },
  })
end)

test("a discounted flight is written at the cost it was listed at, naming the flight master", function(game)
  game.login()
  game.advance(8)
  local start = game.world.money
  -- A flight listed at 500 that costs 450 with the faction discount.
  game.openWindow("TaxiNode", FLIGHT)
  game.G.TakeTaxiNode(3)
  game.change(-450)
  game.closeWindow("TaxiNode")
  game.advance(1)
  expectMoney(game, start, {
    { "a discounted flight", -450, "taxi", "taxinode", "500", FLIGHT },
  })
end)

test("a trainer's service names the trainer", function(game)
  game.login()
  game.advance(8)
  local start = game.world.money
  game.openWindow("Trainer", TRAINER)
  game.G.BuyTrainerService(2)
  game.change(-500)
  game.closeWindow("Trainer")
  game.advance(1)
  expectMoney(game, start, {
    { "a trainer's service", -500, "train", "trainer", "500", TRAINER },
  })
end)

-- The mailbox: a letter sent with 2 silver attached, which the game takes with the postage in one
-- change, then an empty letter, then an auction's proceeds taken, then money that moves with the
-- mailbox open and nothing said why.
local function mailScene(game)
  game.openWindow("MailInfo", nil)
  game.world.sendMoney = 200
  game.G.SendMail("Bertrand", "For the road", "")
  game.change(-230)
  game.world.sendMoney = 0
  game.advance(1)
  game.G.SendMail("Bertrand", "Nothing in it", "")
  game.change(-30)
  game.advance(1)
  game.world.inbox = { { sender = "Stormwind Auction House", subject = "Auction successful: Linen Cloth", money = 7600, cod = 0, invoice = "seller" } }
  game.fire("MAIL_INBOX_UPDATE")
  game.G.TakeInboxMoney(1)
  game.change(7600)
  game.advance(2.5)
  game.change(15)
  game.closeWindow("MailInfo")
  game.advance(1)
end

test("the mailbox's money is written as a letter's cost, an auction's proceeds, or no reason", function(game)
  game.login()
  game.advance(8)
  local start = game.world.money
  mailScene(game)
  expectMoney(game, start, {
    { "a letter sent with money", -230, "mailsend", "mailinfo", "230", "" },
    { "an empty letter", -30, "mailsend", "mailinfo", "30", "" },
    { "an auction's proceeds", 7600, "ahsale", "mailinfo", "7600", "" },
    { "a change with no reason at the mailbox", 15, "", "mailinfo", "", "" },
  })
end)

test("no letter's sender or subject, or mail's recipient, is written anywhere", function(game)
  game.login()
  game.advance(8)
  mailScene(game)
  -- What the recorder wrote, and everything the game would save at a logout.
  local private = { "Stormwind Auction House", "Auction successful", "Bertrand" }
  local found = {}
  local function look(text, where)
    for _, word in ipairs(private) do
      if text:find(word, 1, true) then found[#found + 1] = word .. " in " .. where end
    end
  end
  for _, l in ipairs(game.lines()) do look(l.raw, "a " .. l.kind .. " line") end
  local function walk(value, path)
    if type(value) == "string" then look(value, path)
    elseif type(value) == "table" then
      for k, v in pairs(value) do walk(tostring(k), path) walk(v, path .. "." .. tostring(k)) end
    end
  end
  local saved = game.logout()
  walk(saved.WidsithDB, "WidsithDB")
  walk(saved.WidsithUI, "WidsithUI")
  expect(#found == 0, "a letter's sender or subject, or a letter's recipient, was written: " .. table.concat(found, ", "))
end)

test("a guild bank withdrawal is written with the amount asked for", function(game)
  game.login()
  game.advance(8)
  local start = game.world.money
  game.openWindow("GuildBanker", nil)
  game.G.WithdrawGuildBankMoney(20000)
  game.change(20000)
  game.closeWindow("GuildBanker")
  game.advance(1)
  expectMoney(game, start, {
    { "a guild bank withdrawal", 20000, "guildbankout", "guildbanker", "20000", "" },
  })
end)

test("a flight the server refuses writes nothing, and doesn't explain a change over two seconds later", function(game)
  game.login()
  game.advance(8)
  local start = game.world.money
  -- No change follows the request, and the next change, over two seconds later, isn't
  -- explained by it.
  game.openWindow("TaxiNode", FLIGHT)
  game.G.TakeTaxiNode(4)
  game.closeWindow("TaxiNode")
  game.advance(2.2)
  game.change(7)
  game.advance(1)
  expectMoney(game, start, {
    { "the change after a refused flight", 7, "", "", "", "" },
  })
end)

test("a loot message after its own change in the same frame explains that change and nothing after", function(game)
  game.login()
  game.advance(8)
  local start = game.world.money
  game.change(65)
  game.fire("CHAT_MSG_MONEY", "You loot 65 Copper")
  game.advance(1)
  game.change(3)
  game.advance(1)
  expectMoney(game, start, {
    { "a change whose loot message came after it in the same frame", 65, "loot", "", "65", "" },
    { "the change after that late message", 3, "", "", "", "" },
  })
end)

test("two changes in one frame are told apart by the amount the message states", function(game)
  game.login()
  game.advance(8)
  local start = game.world.money
  -- The message for the second arrives after both.
  game.change(9)
  game.change(80)
  game.fire("CHAT_MSG_MONEY", "You loot 80 Copper")
  game.advance(1)
  expectMoney(game, start, {
    { "the first of two changes in one frame", 9, "", "", "", "" },
    { "the second, which the late message states exactly", 80, "loot", "", "80", "" },
  })
end)
