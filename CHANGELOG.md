# What changed

Each version of Widsith, newest first, with the date it was handed out. The addon only ever records, so a change here is to what it records or to what you see in game.

## 0.6.3 · 2026-11-05

- Experience or gold you gain while a loading screen is up, such as the experience for discovering the place you arrive in after a portal or a teleport, is recorded when you arrive. It used to be missed, and only turned up in the recording a few minutes later.

## 0.6.2 · 2026-11-05

- A fight that is still going when you reload or resume recording is recorded when it ends. It used to be lost.
- The flame, its tooltip and the save reminder count the time since the game last wrote the recording. After a pause and resume they used to start over as if you had just saved.
- Something going wrong in a /widsith command, or when you click the icon, its menu or a button in the settings panel, now shows one plain line in chat instead of a red error.
- A /widsith command typed with a space before it is read as typed.
- /widsith check names every pet-battle function the addon uses, so on a client without pet battles it says so.
- The About panel says the game writes the recording when you log out as well as when you reload.

## 0.6.1 · 2026-11-04

- A second setting, "Show chat in the pictures", keeps your chat windows in the screenshots Widsith takes. The friends list, the guild window and Battle.net pop-ups are always hidden. It is off unless you turn it on.
- The two screenshot settings sit together in the icon's menu, under Screenshots. In the settings panel the chat one is greyed until "Screenshot highlights" is on.
- A reputation gain inside a dungeon or raid, where the game hides its message, no longer shows a Problem in chat.
- After a reload, the last fight from before it is no longer recorded again when your next combat ends.
- Quests and trades inside instances are recorded even when the game hides who the quest giver or the other player is.
- A highlight screenshot due in the same second as one of your own now waits a second, so it no longer replaces your picture.
- The README now covers the screenshots, your guild, the other players a recording names, and `/widsith size`.

## 0.6.0 · 2026-11-02

- A new setting, "Screenshot highlights", takes a screenshot when you reach a new level, defeat a boss for the first time, enter a zone or an instance for the first time, summon your first mount or die for the first time, and at every death on a Hardcore realm. Chat, the friends list and the guild window are hidden for the picture, and a tiny mark goes in its corner. The pictures go in your Screenshots folder. Your own screenshots aren't touched. It is off unless you turn it on, in the icon's menu or under Options, AddOns, Widsith.

## 0.5.0 · 2026-10-29

- Other players are named. A buff another player casts on you records who cast it, and a death at another player's hands records who dealt each hit, as the game names them. Group members and trade partners were already named; this makes the recording consistent.
- The character sheet is never recorded while a fight hides part of it. The line waits for the fight to end, instead of being written with its attributes empty.
- `/widsith size` says how big the recording is and which sessions are the largest, and each session's opening line records the file's size before it.
- Each loot line says which message it came from: loot from a corpse or container, an item the game put in your bags, something you crafted, a bonus roll or a refund. It also keeps the item exactly as the game linked it, so an upgrade step no longer looks like the item dropping again.
- Quests are recorded whole: every objective is listed the moment you accept a quest, the game's own "ready to turn in" is recorded when it happens, and a quest that was already finished when you logged in is recorded as such.
- Each change to your gold records why it happened whenever the game says, from loot and quest rewards to vendors, flights, the mailbox and the auction house, along with the window you had open. Quests also record their level when you accept them, and the members of your group are recorded with their levels.
- Gear is recorded as the game links it, with its enchant, gems, suffix and upgrade, not only by item ID, so the site can show the piece you actually wore.
- More of what happens around you is recorded: the weather and, on WoW Forever, the turn from day to night, how worn your gear is and the moment a piece breaks, the duels you win or lose, your own rolls and your choices in group loot rolls, and how long each loading screen took.

## 0.4.7 · 2026-10-29

- Ready for WoW Forever's launch: the addon is marked for the released client (1.60.1) as well as for Retail 12.1.5, so either game loads it with no "out of date" warning. What it records is unchanged since 0.4.6.

## 0.4.6 · 2026-10-22

- Inside dungeons, raids and delves on Retail, the once-a-second record stopped for the length of the run and chat showed a Problem each time. It now carries on, and a flag the game hides there is left blank.
- The five-minute snapshot no longer falls inside a loading screen, where it read an empty character.
- Gear is read again a second after a change, so a quest's disguise no longer leaves a slot recorded as empty.

## 0.4.5 · 2026-10-14

- The game's statistics are read by ID after the first pass, so the pass after a fight takes a few milliseconds instead of over a second on Retail.

## 0.4.4 · 2026-10-14

- The statistics read is spread across frames: on Retail it froze the game for over a second every few seconds.
- Marked for Retail 12.1.5.

## 0.4.3 · 2026-10-14

- WoW Forever characters are recorded with their surname, so the site can name them in full.

## 0.4.2 · 2026-10-10

- The emote when saving is off unless you turn it on, and is sent at most once a minute.

## 0.4.1 · 2026-10-09

- Every currency you hold is recorded at login, not only when one changes.
- A fight is written the instant it ends.
- Opening the map no longer counts as a /read emote.

## 0.4.0 · 2026-10-07

The first public version.

- The flame by the minimap shows how much play is unsaved and grows shorter over half an hour. A left click saves, a right click opens the menu.
- A settings panel with an About page, under Options, AddOns, Widsith.
- One command, `/widsith`, with `help`, `about`, `pause`, `save`, `check` and more.
- Chat says only what you need to know; `/widsith debug` prints everything.
- An emote to nearby players when you save.

Versions before 0.4.0 were the private beta, named WoW Journey until 0.3.0.
