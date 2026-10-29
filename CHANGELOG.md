# What changed

Each version of Widsith, newest first, with the date it was handed out. The addon only ever records, so a change here is to what it records or to what you see in game.

## 0.5.0 · not yet released

- Other players are named. A buff another player casts on you records who cast it, and a death at another player's hands records who dealt each hit, as the game names them. Group members and trade partners were already named; this makes the recording consistent.
- The character sheet is never recorded while a fight hides part of it. The line waits for the fight to end, instead of being written with its attributes empty.
- `/widsith size` says how big the recording is and which sessions are the largest, and each session's opening line records the file's size before it.
- Each loot line says which message it came from: loot from a corpse or container, an item the game put in your bags, something you crafted, a bonus roll or a refund. It also keeps the item exactly as the game linked it, so an upgrade step no longer looks like the item dropping again.
- Quests are recorded whole: every objective is listed the moment you accept a quest, the game's own "ready to turn in" is recorded when it happens, and a quest that was already finished when you logged in is recorded as such.

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
