# Widsith

A World of Warcraft addon that keeps a record of your character's journey while you play: where you went, what you did and when. It runs by itself from the moment you log in, and you never have to remember to start it.

Widsith only records. It writes what happens to your character into its saved file on your computer, and the website [widsith.app](https://widsith.app) turns that file into a journey you can replay on the map and keep.

## What it records

Widsith writes down facts as the game reports them, with the game's own IDs, at the moment they happen. It does not guess or interpret. Among other things it records:

- where the character is, once a second, as the map ID and position the game gives, and every zone change, flight, hearth and teleport;
- quests accepted, progressed, abandoned and turned in;
- kills, deaths, loot, money, levels and experience;
- each fight, as one summary from the game's own damage meter once the fight ends, never a line per blow;
- reputation, professions and recipes, skills, achievements, currencies, gear, gear sets, talents, specialisation and the character sheet's stats;
- your group, your own guild, trades, buying and selling at vendors, mounts, pet battles, duels, discoveries and what NPCs say;
- that a screenshot was taken, whether it was yours or one of Widsith's own highlights (see Screenshots below).

It keeps no chat: nothing you or other players type is written. Names are kept beside IDs only as labels for reading. Other players are named only where the game names them to you: the members of your group, the players you trade with, a player who casts a buff on you, a player who dealt one of the hits in your death recap, and the players you duel.

Widsith never connects to anything, as no WoW addon can. Everything stays on your computer. The recording is kept in its saved file, which the game writes each time you log out or reload the interface. You take that file to widsith.app yourself, or let the Widsith Uploader app send it for you. The screenshots Widsith takes, if you turn them on, are pictures only, and they stay in the game's own Screenshots folder beside yours.

The saved file is `WTF\Account\<account>\<realm>\<character>\SavedVariables\Widsith.lua`, one per character.

## Installing

Download the addon from [widsith.app](https://widsith.app), or clone this repository, and put the folder in the game's `Interface\AddOns` folder so that it is named `Widsith`:

```
cd "World of Warcraft\_retail_\Interface\AddOns"
git clone https://github.com/WidsithApp/Widsith.git Widsith
```

The same addon loads on Retail and on WoW Forever, which has its own `Interface\AddOns` folder inside its own game folder, `_forever_`. Start the game or type `/reload`, and chat says that Widsith is recording.

Each version is also on this repository's Releases page as a zip, built from its tag by the workflow in `.github/workflows/release.yml`: the same file widsith.app and the addon sites hand out.

## Commands

- `/widsith` says whether Widsith is recording.
- `/widsith help` lists the commands.
- `/widsith about` gives the version, what Widsith is, and the website.
- `/widsith size` says how big the recording is and which sessions are the largest.
- `/widsith pause` stops recording until `/widsith resume`, or until the next login or reload.
- `/widsith save` reloads the interface so the game writes the saved file.
- `/widsith icon` shows or hides the recording icon.
- `/widsith options` opens the settings, also found under Options, AddOns, Widsith.
- `/widsith check` names the game client and lists anything Widsith uses that this client lacks.
- `/widsith debug` turns on verbose chat: every line echoed as it is written, and every problem.

## The recording icon and saving

The game writes an addon's saved file only when you log out or reload the interface, so play since the last save is lost if the game closes unexpectedly. The icon by the minimap shows how much play is unsaved. Its flame is lit while Widsith records and grows shorter over half an hour of unsaved play. After that the ring around it glows, and Widsith offers to save once you are resting and out of combat.

A left click on the icon saves by reloading the interface. A right click opens a menu to pause or resume, turn the reminder, the animations, the chat messages or the emote when saving on and off, attach the icon to the minimap or lock it in place, change its size, set the screenshot settings, or hide it. While recording is paused, the icon is dark. The settings panel holds the same switches, so a hidden icon can always be brought back.

## Screenshots

With "Screenshot highlights" turned on, Widsith takes a screenshot when you reach a new level, defeat a boss for the first time, enter a zone or an instance for the first time, summon your first mount or die for the first time, and at every death on a Hardcore realm. For the picture it hides the friends list, the guild window and the Battle.net pop-ups, and chat as well unless "Show chat in the pictures" is on, and it draws a tiny mark in the corner. The pictures go in the game's own Screenshots folder, and your own screenshots aren't touched. Both settings are off unless you turn them on, under Screenshots in the icon's menu or under Options, AddOns, Widsith.

## The files

- `Widsith.toc` names the addon, the game versions it loads on and its files.
- `Core.lua` starts a new part of the recording at each login and reload, writes the lines, takes the opening snapshot of the character, and answers `/widsith`.
- `Position.lua` reads the character's position once a second, notices teleports, and writes the periodic time, snapshot and counter lines.
- `Events.lua` records the world, progress, quests, kills, loot, NPCs, combat, rest and groups.
- `Extras.lua` records mounts and travel, reputation, professions and skills, achievements, gear and stats, currencies, encounters, specialisation, gear sets, talents, the hearthstone, vendors and trainers, pet battles, and emotes.
- `Moments.lua` records each fight's summary from the damage meter, the death recap, buffs and debuffs outside combat, loss of control, breath and fatigue, discoveries, the game's own statistics as they change, what NPCs say, and the rules a character plays under.
- `Screenshots.lua` notes every screenshot, and takes the addon's own at the highlights.
- `Save.lua` draws the recording icon and offers the save reminder.
- `Options.lua` is the settings panel and its About page.
- `media/` holds the icon's images: the flame, the disc under it, the glow, and the emblem shown in the addon list. They are drawn by the scripts in `tools/`. Everything else on screen is the game's own art, loaded from the game.
- `LICENSE.txt` is the licence.

## Tools and the check

`tools/` is for working on the addon and is not needed to play with it.

- `check.mjs` is what runs on every pull request: `node tools/check.mjs` from this folder. Every Lua file must parse as the game's Lua would read it, and every test must pass. It needs Node and nothing installed. `node tools/check.mjs tests` runs the tests alone, and `node tools/check.mjs tests money` only the files whose names contain the word.
- `harness/` is a stand-in for the game client and a test runner. `client.lua` builds a game outside the game: the globals the addon reads, a clock, frames, timers, and a world a test changes by name, as two client profiles (WoW Forever and Retail) with the facts each was seen to have; hidden values are objects that raise an error on any use. It can log in, reload the interface on the saved file the way the game does, press the icon and its menu, and read the settings panel and chat. `run.lua` runs the files under `tests/`, each test on a fresh game and on both profiles unless it says otherwise.
- `tests/` holds one file per theme: money, fights, auras, quests and loot, the world, sessions, the extras, the commands, screenshots, and the icon with the settings panel. A test says in a plain sentence what must be so, plays it, and reads the lines written or what the player was told.

The stand-in answers only what the game was seen to answer, on the builds its profiles name. A test passing means the addon still does what the game was last seen to do, and nothing more: the real game is checked in the game. When a recording shows the game answering differently, the stub changes with the fix.
- `build-flame.mjs` and `build-glow.mjs` draw the images in `media/`. The flame script needs sharp, so run `npm install` in `tools/` first. Given a folder or file such as `tools/previews`, they also write previews to look at.

## Licence

Copyright (c) 2026 Reflective Grove LLC. All rights reserved.

Widsith is free to download and use, and its source is open for anyone to read, as Blizzard's addon policy requires. It may not be copied, changed or redistributed without written permission. The terms are in `LICENSE.txt` and at [widsith.app/licence](https://widsith.app/licence).

The official copies are the ones published at widsith.app, in this repository and on its Releases page, and on CurseForge and Wago. A copy from anywhere else, or a changed one, isn't ours: we can't support it and aren't responsible for what it does.

Widsith is a fan project. It is not made, endorsed or supported by Blizzard Entertainment. World of Warcraft and Warcraft are trademarks or registered trademarks of Blizzard Entertainment, Inc. in the U.S. and/or other countries.

## Contact

Questions, ideas and bug reports are welcome on [Discord](https://discord.gg/532DstKnNE) or by email to info@widsith.app.
