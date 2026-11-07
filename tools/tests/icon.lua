-- The recording icon and the save reminder (Save.lua), the settings panel and the About page
-- (Options.lua), and what a reload carries across: what the player is told and what each control
-- does, on a client that never draws.

test("a login lights the icon and says the version is recording, under the emblem", function(game)
  -- An account that has seen this version: a first login says the welcome in this line's place.
  game.saved = { WidsithAccount = { settings = {}, seenVersion = game.version } }
  game.login()
  game.advance(8)
  local icon = game.icon()
  expect(icon ~= nil, "no icon frame was made at login")
  expect(icon and icon:IsShown(), "the icon isn't shown by default")
  expect(game.addon.isRecording(), "not recording after login")
  local line = game.said(game.version .. " is recording. Type /widsith help for commands.")
  expect(line ~= nil, "the login line wasn't said")
  expect(line and line:find("^|TInterface\\AddOns\\Widsith\\media\\flame%-chat:16:16|t |cff33ff99Widsith|r " .. game.version:gsub("%.", "%%.") .. " is recording"),
    "the login line doesn't open with the emblem and the name: " .. tostring(line))
  -- The icon's disc is the addon's own; the ring is the game's: the dial's atlas on a client with
  -- the dial, the classic tracking border without it.
  local atlas, border = false, false
  for _, r in ipairs(icon.regions) do
    if r.atlas == "UI-HUD-Minimap-Frame-Cycle" then atlas = true end
    if r.texture == "Interface\\Minimap\\MiniMap-TrackingBorder" then border = true end
  end
  if game.profile.diel then
    expect(atlas and not border, "on a client with the day/night dial the ring should be the dial's atlas")
  else
    expect(border and not atlas, "on a client without the dial the ring should be the classic border")
  end
end)

test("the tooltip says what the icon is doing and what a click does", function(game)
  game.login()
  game.advance(8)
  game.hover()
  local lines = game.tooltip.lines
  eq(lines[1], "Widsith", "the tooltip's title")
  expect(lines[2] and lines[2]:find("^Recording, under a minute unsaved%.$"), "the state line: " .. tostring(lines[2]))
  eq(lines[3], "Click to save. Right-click for options.", "the tooltip's last line")
  game.advance(46 * 60)
  game.hover()
  lines = game.tooltip.lines
  expect(lines[2] and lines[2]:find("unsaved%. Time to save%.$"), "after 45 minutes the tooltip should ask for a save: " .. tostring(lines[2]))
end)

test("a click saves: the interface reloads and the player is told", function(game)
  game.login()
  game.advance(8)
  game.clickSave()
  expect(game.reloadAsked, "a left click didn't ask for a reload")
  game.advance(1)   -- the reload happens
  eq(game.loads, 2, "the addon loaded again")
  expect(game.said("saved."), "the player wasn't told the recording was saved")
  expect(game.addon.isRecording(), "not recording after the reload")
  expect(game.icon() and game.icon():IsShown(), "the icon is gone after the reload")
  -- The reload closed the first session on the file, whole, and started a second one (whose
  -- lines are still in memory, packed into the file at the next reload or logout).
  local onFile = game.onFile()
  eq(#onFile, 2, "sessions on file after one reload")
  expect(onFile[1].closed, "the first session wasn't closed by the reload")
  eq(onFile[1].lines[#onFile[1].lines].kind, "END", "the first session's last line")
  eq(#onFile[1].lines, #game.written[1].lines, "the first session's lines on file against the lines written")
  eq(game.written[2].lines[1].kind, "SESSION", "the second session's first line")
  eq(game.written[2].lines[1].fields[9], "1", "the second session's SESSION line says it is a reload")
end)

test("a click in combat refuses to reload and says so", function(game)
  game.login()
  game.advance(8)
  game.world.combat = true
  game.fire("PLAYER_REGEN_DISABLED")
  game.clickSave()
  expect(not game.reloadAsked, "a click in combat asked for a reload")
  expect(game.said("can't reload the interface in combat"), "the refusal wasn't said")
end)

test("the unsaved time runs from the last reload, through a pause", function(game)
  game.login()
  game.advance(100)
  local before = game.addon.secondsSinceSave()
  game.slash("stop")
  game.advance(50)
  game.slash("start")
  game.advance(8)
  expect(game.addon.secondsSinceSave() >= before + 58, "the unsaved time reset at a pause or resume")
  game.clickSave()
  game.advance(1)
  expect(game.addon.secondsSinceSave() < 2, "the unsaved time didn't reset at the reload: " .. tostring(game.addon.secondsSinceSave()))
end)

test("the reminder appears once the flame has burnt down, only somewhere calm", function(game)
  game.login()
  game.advance(8)
  expect(game.reminder() == nil, "a reminder before anything was unsaved")
  game.advance(46 * 60)
  expect(game.reminder() == nil, "the reminder showed while the character wasn't resting")
  game.world.resting = true
  game.advance(6)
  local bubble = game.reminder()
  expect(bubble and bubble:IsShown(), "the reminder didn't show once resting")
  if bubble then
    expect(bubble.regions[1].text:find("^Recording unsaved for 46 min"), "the reminder's title: " .. tostring(bubble.regions[1].text))
    -- Clicking the reminder saves.
    bubble.scripts.OnClick(bubble)
    expect(game.reloadAsked, "clicking the reminder didn't ask for a reload")
  end
end)

test("reminders can be turned off from the menu, and the reminder goes with them", function(game)
  game.login()
  game.advance(46 * 60)
  game.world.resting = true
  game.advance(6)
  expect(game.reminder() and game.reminder():IsShown(), "no reminder to turn off")
  game.openMenu()
  local entry = game.menuEntry("Remind me to save")
  expect(entry and entry.isChecked(), "the menu's reminder entry isn't on by default")
  game.press(entry)
  expect(not game.addon.getIconSetting("remind"), "pressing the entry didn't turn reminders off")
  expect(not game.reminder():IsShown(), "the reminder stayed up after reminders were turned off")
  game.advance(20 * 60)
  expect(not game.reminder():IsShown(), "a reminder showed with reminders off")
end)

test("the menu lists every setting with its default", function(game)
  game.login()
  game.advance(8)
  local menu = game.openMenu()
  expect(menu.entries[1].kind == "title" and menu.entries[1].name == "Widsith", "the menu doesn't open with the addon's name")
  eq(game.menuEntry("Stop recording") ~= nil, true, "Stop recording while recording")
  -- The top level, in order: what the player reaches for. The icon's own settings under Icon,
  -- the sizes under a line in it; Show chat messages is the panel's alone.
  local names = {}
  for _, entry in ipairs(menu.entries) do names[#names + 1] = entry.kind .. ":" .. entry.name end
  same(names, { "title:Widsith", "button:Stop recording", "checkbox:Remind me to save", "checkbox:Emote when saving",
    "button:Screenshots", "button:Icon", "button:Hide icon" }, "the menu's top level")
  local iconNames = {}
  for _, entry in ipairs(game.menuEntry("Icon").entries) do iconNames[#iconNames + 1] = entry.kind .. ":" .. entry.name end
  same(iconNames, { "checkbox:Animations", "checkbox:Attach to minimap", "checkbox:Lock position", "divider:",
    "radio:Small", "radio:Medium", "radio:Large" }, "the Icon submenu")
  local defaults = { { "Remind me to save", true }, { "Emote when saving", false }, { "Screenshots", "Screenshot highlights", true },
    { "Screenshots", "Show chat in the pictures", true }, { "Icon", "Animations", true }, { "Icon", "Attach to minimap", true },
    { "Icon", "Lock position", false }, { "Icon", "Small", true }, { "Icon", "Large", false } }
  for _, d in ipairs(defaults) do
    local want = table.remove(d)
    local entry = game.menuEntry(table.unpack(d))
    expect(entry ~= nil, "no menu entry " .. table.concat(d, " > "))
    if entry then eq(entry.isChecked(), want, table.concat(d, " > ") .. " by default") end
  end
  expect(game.menuEntry("Show chat messages") == nil, "Show chat messages is still in the menu")
end)

test("pausing from the menu closes the session and the menu then offers Resume", function(game)
  game.login()
  game.advance(8)
  game.openMenu()
  game.press(game.menuEntry("Stop recording"))
  expect(not game.addon.isRecording(), "still recording after Pause")
  expect(game.said("recording stopped on this character until you start it again"), "the stop wasn't said")
  eq(game.last("END").fields[2], "pause", "the END line's reason")
  game.openMenu()
  expect(game.menuEntry("Stop recording") == nil and game.menuEntry("Start recording") ~= nil, "the menu doesn't offer Resume while paused")
  game.press(game.menuEntry("Start recording"))
  expect(game.addon.isRecording(), "not recording after Resume")
  game.advance(8)
  eq(#game.written, 2, "sessions after a pause and a resume")
end)

test("the icon can be hidden and brought back, from the menu, the command and the panel", function(game)
  game.login()
  game.advance(8)
  game.openMenu()
  game.press(game.menuEntry("Hide icon"))
  expect(not game.icon():IsShown(), "Hide icon left the icon shown")
  expect(game.said("icon hidden. Bring it back from Options, AddOns, Widsith, or with /widsith icon."), "hiding wasn't explained")
  game.slash("icon")
  expect(game.icon():IsShown(), "/widsith icon didn't bring the icon back")
  local row = game.panelRow("Show the icon")
  expect(row ~= nil, "no Show the icon row in the panel")
  if row then
    row.setting:SetValue(false)
    expect(not game.icon():IsShown(), "the panel's row didn't hide the icon")
    eq(row.setting:GetValue(), false, "the panel's row reads the icon as hidden")
  end
end)

test("the settings panel has every setting, and Defaults puts them back", function(game)
  game.login()
  game.advance(8)
  expect(game.panel.registered, "the panel's category wasn't registered")
  local names = {}
  for _, r in ipairs(game.panel.rows) do names[#names + 1] = r.kind .. ":" .. r.name end
  same(names, { "header:The icon", "checkbox:Show the icon", "checkbox:Remind me to save", "checkbox:Animations",
    "checkbox:Attach to minimap", "checkbox:Lock position", "checkbox:Show chat messages", "checkbox:Emote when saving",
    "dropdown:Icon size", "header:The recording", "checkbox:Screenshot highlights", "checkbox:Show chat in the pictures",
    "button:Save the recording", "button:Stop or start recording", "canvas:About" }, "the panel's rows")
  local chat = game.panelRow("Show chat in the pictures")
  expect(chat and chat.parent == game.panelRow("Screenshot highlights"), "the chat row doesn't depend on the highlights row")
  expect(chat and chat.enabledWhen() == true, "the chat row isn't enabled while highlights are on, as they are by default")
  game.panelRow("Screenshot highlights").setting:SetValue(false)
  expect(chat.enabledWhen() == false, "the chat row isn't greyed once highlights are off")
  -- Every setting's default is what the menu's default is, and changing one shows on the icon's side.
  game.panelRow("Emote when saving").setting:SetValue(true)
  expect(game.addon.getIconSetting("emote"), "the panel's emote row didn't set the setting")
  game.panelDefaults()
  expect(not game.addon.getIconSetting("emote"), "Defaults left Emote when saving on")
  expect(game.addon.getIconSetting("screenshots"), "Defaults left Screenshot highlights off")
  expect(game.addon.getIconSetting("shotsChat"), "Defaults left Show chat in the pictures off")
  expect(game.addon.getIconSetting("remind"), "Defaults turned reminders off")
  eq(game.addon.getIconSetting("iconSize"), 1, "Defaults' icon size")
  -- The panel's buttons do what the icon does.
  game.panelRow("Stop or start recording").press()
  expect(not game.addon.isRecording(), "the panel's Pause didn't pause")
  game.panelRow("Stop or start recording").press()
  expect(game.addon.isRecording(), "the panel's Resume didn't resume")
  game.panelRow("Save the recording").press()
  expect(game.reloadAsked, "the panel's Save now didn't ask for a reload")
end)

test("the About page names the version, the site, Discord and the email", function(game)
  game.login()
  game.advance(8)
  local about = game.panelRow("About")
  expect(about ~= nil, "no About page")
  if not about then return end
  -- The headings and lines are font strings; the addresses sit in edit boxes, to be copied.
  local texts = {}
  for _, r in ipairs(about.frame.regions) do texts[#texts + 1] = r.text end
  for _, f in ipairs(about.frame.children) do texts[#texts + 1] = f.text end
  local joined = table.concat(texts, "\n")
  expect(joined:find("version " .. game.version, 1, true), "the About page doesn't show the version")
  expect(joined:find("https://widsith.app", 1, true), "the About page doesn't name the site")
  expect(joined:find("https://discord.gg/532DstKnNE", 1, true), "the About page doesn't name Discord")
  expect(joined:find("info@widsith.app", 1, true), "the About page doesn't name the email")
  expect(joined:find("writes the recording only when you log out or reload", 1, true), "the About page doesn't say when the game writes the file")
end)

test("settings survive a reload, and a saved position is kept", function(game)
  game.login()
  game.advance(8)
  game.openMenu()
  game.press(game.menuEntry("Icon", "Animations"))
  game.press(game.menuEntry("Icon", "Lock position"))
  game.press(game.menuEntry("Icon", "Large"))
  game.clickSave()
  game.advance(1)
  expect(not game.addon.getIconSetting("animate"), "Animations came back on after the reload")
  expect(game.addon.getIconSetting("locked"), "Lock position came off after the reload")
  eq(game.addon.getIconSetting("iconSize"), 1.8, "the icon size after the reload")
end)

test("an emote on saving, when turned on, at most once a minute", function(game)
  game.login()
  game.advance(8)
  game.clickSave()
  game.advance(1)
  eq(#game.sent, 0, "an emote was sent with the setting off")
  game.openMenu()
  game.press(game.menuEntry("Emote when saving"))
  game.clickSave()
  game.advance(1)
  eq(#game.sent, 1, "no emote on a save with the setting on")
  expect(game.sent[1] and game.sent[1].kind == "EMOTE" and game.sent[1].text:find("Widsith journal", 1, true), "the emote isn't about the journal")
  game.clickSave()
  game.advance(1)
  eq(#game.sent, 1, "a second emote within a minute")
  game.advance(61)
  game.clickSave()
  game.advance(1)
  eq(#game.sent, 2, "no emote a minute later")
end)

test("a reload the game didn't read the file back from is said once, and saving stops asking", { errAllowed = true, problemAllowed = true }, function(game)
  game.login()
  game.advance(8)
  game.reloadWithoutFile()
  game.advance(8)
  expect(game.said("the game didn't load the earlier recording at this reload"), "the lost file wasn't said")
  local err = game.last("ERR")
  expect(err and err.fields[1] == "savedvariables", "no ERR savedvariables line")
  game.hover()
  expect(game.tooltip.lines[2]:find("Don't reload", 1, true), "the tooltip doesn't warn against reloading: " .. tostring(game.tooltip.lines[2]))
  game.clickSave()
  expect(not game.reloadAsked, "a click reloaded although the file wasn't loaded")
  expect(game.said("not reloading: the game didn't load the earlier recording"), "the refusal wasn't said")
  game.advance(46 * 60)
  game.world.resting = true
  game.advance(6)
  expect(game.reminder() == nil or not game.reminder():IsShown(), "the reminder asked for a reload that would replace the file")
end)

test("the compartment entry opens the settings panel", function(game)
  game.login()
  game.advance(8)
  game.G.Widsith_OnAddonCompartmentClick()
  eq(game.panel.openedTo, "Widsith", "the panel opened to")
end)
