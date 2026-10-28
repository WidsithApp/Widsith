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
- groups, trades, buying and selling at vendors, mounts, pet battles, discoveries and what NPCs say.

It keeps no chat: nothing you or other players type is written. Names are kept beside IDs only as labels for reading.

Widsith never connects to anything, as no WoW addon can. Everything stays in its saved file on your computer, which the game writes each time you log out or reload the interface. You take that file to widsith.app yourself, or let the Widsith Uploader app send it for you.

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
- `/widsith pause` stops recording until `/widsith resume`, or until the next login or reload.
- `/widsith save` reloads the interface so the game writes the saved file.
- `/widsith icon` shows or hides the recording icon.
- `/widsith options` opens the settings, also found under Options, AddOns, Widsith.
- `/widsith check` names the game client and lists anything Widsith uses that this client lacks.
- `/widsith debug` turns on verbose chat: every line echoed as it is written, and every problem.

## The recording icon and saving

The game writes an addon's saved file only when you log out or reload the interface, so play since the last save is lost if the game closes unexpectedly. The icon by the minimap shows how much play is unsaved. Its flame is lit while Widsith records and grows shorter over half an hour of unsaved play. After that the ring around it glows, and Widsith offers to save once you are resting and out of combat.

A left click on the icon saves by reloading the interface. A right click opens a menu to pause or resume, turn the reminder, the animations or the chat messages on and off, attach the icon to the minimap or lock it in place, change its size, or hide it. While recording is paused, the icon is dark. The settings panel holds the same switches, so a hidden icon can always be brought back.

## The files

- `Widsith.toc` names the addon, the game versions it loads on and its files.
- `Core.lua` starts a new part of the recording at each login and reload, writes the lines, takes the opening snapshot of the character, and answers `/widsith`.
- `Position.lua` reads the character's position once a second, notices teleports, and writes the periodic time, snapshot and counter lines.
- `Events.lua` records the world, progress, quests, kills, loot, NPCs, combat, rest and groups.
- `Extras.lua` records mounts and travel, reputation, professions and skills, achievements, gear and stats, currencies, encounters, specialisation, gear sets, talents, the hearthstone, vendors and trainers, pet battles, and emotes.
- `Moments.lua` records each fight's summary from the damage meter, the death recap, buffs and debuffs outside combat, loss of control, breath and fatigue, discoveries, the game's own statistics as they change, what NPCs say, and the rules a character plays under.
- `Save.lua` draws the recording icon and offers the save reminder.
- `Options.lua` is the settings panel and its About page.
- `media/` holds the icon's images: the flame, the disc under it, the glow, and the emblem shown in the addon list. They are drawn by the scripts in `tools/`. Everything else on screen is the game's own art, loaded from the game.
- `LICENSE.txt` is the licence.

## Tools and the check

`tools/` is for working on the addon and is not needed to play with it.

- `check.mjs` is what runs on every pull request: `node tools/check.mjs` from this folder. Every Lua file must parse, and the recorder must get through `recorder-mock.lua` without a Lua error or a wrong line. It needs Node and nothing installed.
- `recorder-mock.lua` is a rough stand-in for the game client. It loads the recorder (all but `Save.lua`), plays some made-up play through it with hidden values that raise an error on any use, and prints the lines written. It catches a typo or a missing check for a hidden value without starting the game, though it cannot show what the real game answers. Run it with `npx --yes -p fengari-node-cli fengari tools/recorder-mock.lua`.
- `build-flame.mjs` and `build-glow.mjs` draw the images in `media/`. The flame script needs sharp, so run `npm install` in `tools/` first. Given a folder or file such as `tools/previews`, they also write previews to look at.

## Licence

Copyright (c) 2026 Reflective Grove LLC. All rights reserved.

Widsith is free to download and use, and its source is open for anyone to read, as Blizzard's addon policy requires. It may not be copied, changed or redistributed without written permission. The terms are in `LICENSE.txt` and at [widsith.app/licence](https://widsith.app/licence).

World of Warcraft is a trademark of Blizzard Entertainment, Inc. Widsith is a fan project and is not made, endorsed or supported by Blizzard Entertainment.

## Contact

Questions, ideas and bug reports are welcome on [Discord](https://discord.gg/532DstKnNE) or by email to info@widsith.app.
