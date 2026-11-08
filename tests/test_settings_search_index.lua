-- The settings search lists each control under the page that draws it. Every label the index holds before
-- a page is opened is drawn and marked on that page, in some state, with search on. Every page and topic it
-- names is a page of the window.
local defaults, store = require('ui.defaults'), require('core.store');
local imgui = require('imgui');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {},
    party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end, resolve = function(id) return { id = id }; end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window = require('ui.settings_window');
local index, tabs = require('ui.search_index').controls, window._tabs;
local pages = {};
for _, page in ipairs(tabs) do pages[page] = true; end;
assert(#tabs == 5, 'The window has five pages.');

-- The index as it stands before any page is drawn.
local static = {};
for page, labels in pairs(index) do
    assert(pages[page], 'The search index names a page of the window: ' .. page);
    static[page] = {};
    for label in pairs(labels) do static[page][label] = true; end;
end;
for _, row in ipairs(require('ui.search_index').entries) do
    assert(pages[row[1]], 'A search topic opens a page of the window: ' .. row[1] .. ' / ' .. row[2]);
end;
for _, page in ipairs(tabs) do assert(static[page], 'Every page is indexed before it is opened: ' .. page); end;
-- The icon size for a panel of its own and the ways there and back are found before the panel is opened.
for _, label in ipairs({ 'Icon size in a panel of its own', 'Put party buffs back beside the party list' }) do
    assert(static.Display[label], 'The index holds ' .. label .. ' on the panels.');
    assert(not static.Home[label], 'The main page has no ' .. label .. '.');
end;
-- Profile sharing's controls are found before Profiles is opened.
for _, label in ipairs({ 'Export a saved profile', 'Export a saved profile to a file', 'Import from clipboard',
    'Import from a file', 'Keep my own display positions', 'Save as a new profile', 'Load profile', 'Overwrite profile', 'Rename profile',
    'Delete profile', 'Load this profile when I change to', 'Link this job', 'Unlink this job', 'Unlink all jobs',
    'Undo the last profile change', 'Share settings across my characters', 'What to share across characters', 'Export',
    'Copy the export', 'Import and add', 'Import and replace', 'Save it as', 'Put every display back where it started',
    'Reset all settings' }) do
    assert(static.Profiles[label], 'The index holds ' .. label .. ' on Profiles.');
end;
-- What a player would type finds the control that does that job.
local function more_words(when)
    for _, entry in ipairs({
        { 'Customize', 'Home', 'What to show' },
        -- The pet panel's rows.
        { 'Show charm time', 'Display', 'Show charm and jug time' }, { 'Show charm and jug time', 'Display', 'Show charm and jug time' },
        { 'Show effects as', 'Display', 'Show effects as' }, { 'List with names', 'Display', 'Show effects as' },
        { 'Show maneuvers and overload risk', 'Display', 'Show maneuvers and overload risk' },
        -- What a display's tabs do.
        { 'Effect visibility', 'Display', 'Find an effect' }, { 'Notice placement and size', 'Display', 'Notice position and resizing' },
        { 'Customize display filters', 'Display', 'Effect filters, labels and pinned order' },
        { 'Clear every anchor', 'Display', 'Moves with' }, { "Every display's anchor", 'Display', 'Moves with' },
        -- What is on Profiles and sharing and the main page.
        { 'Overwrite profile', 'Profiles', 'Overwrite profile' }, { 'Rename profile', 'Profiles', 'Rename profile' },
        { 'Import a profile from the clipboard', 'Profiles', 'Import from clipboard' }, { 'Paste a share string', 'Profiles', 'Import from clipboard' },
        { 'Open a profile file', 'Profiles', 'Import from a file' }, { 'Use a profile for a job', 'Profiles', 'Load this profile when I change to' },
        { 'Choose current job', 'Profiles', 'Load this profile when I change to' },
        { 'Share selected settings across characters', 'Profiles', 'Share settings across my characters' },
        { 'Reset panel layouts', 'Profiles', 'Put every display back where it started' },
        { 'What to export', 'Profiles', 'Export' }, { 'Copy a share string', 'Profiles', 'Copy the export' },
        { 'Accent color', 'Home', 'Accent color' },
        { 'Only on a mob or player named', 'Durations', 'Add duration override' }, { 'Record recent diagnostic events', 'Help', 'Record recent events' },
        { 'Export diagnostic report', 'Help', 'Export report' },
        { 'Tick displays for Grid mode', 'Home', 'Grid mode' },
        { 'Find an effect', 'Display', 'Find an effect' },
        -- The other buttons and topics.
        { 'Show party list buffs', 'Home', 'Party list buffs' }, { 'Party list buff settings', 'Home', 'Party list buffs' },
        { 'Customize party', 'Home', 'Party list buffs' },
        { 'Self buffs', 'Home', 'Self buffs' }, { 'Self debuffs', 'Home', 'Self debuffs' },
        { 'Customize timers', 'Home', 'Edit Self buffs' }, { 'Customize recasts', 'Home', 'Edit Recasts' },
        { 'Customize appearance', 'Home', 'How it looks' }, { 'Open filters', 'Home', 'Edit Hidden everywhere' },
        { 'More customization', 'Home', 'More look' },
        { 'Starter layouts', 'Home', 'Starter profile' }, { 'healer', 'Home', 'Starter profile' },
        { 'Skin, size and customization', 'Home', 'Skin and size' },
        -- Grid and snapping shows only while Grid mode is on, and it is off in both checks, so its name and more words
        -- find Grid mode, which shows it.
        { 'Grid and snapping', 'Home', 'Grid mode' }, { 'Tick the displays that snap', 'Home', 'Grid mode' },
        -- The main page's settings.
        { 'Status and recast icon size', 'Home', 'Icon size' }, { 'Timer icon size', 'Home', 'Icon size' },
        { 'Overall scale', 'Home', 'Size' }, { 'Timer scale', 'Home', 'Size' },
        { 'Menu text size', 'Home', 'Settings text size' },
        { 'Hold Shift to see through this window', 'Home', 'Hold Shift to see through this window' },
        { 'peek', 'Home', 'Hold Shift to see through this window' },
        { 'Timer window style', 'Home', 'Window frame' }, { 'Menu window style', 'Home', 'Window frame' },
        { 'Enable alert rules', 'Display', 'Show this display' },
        { 'Recast icons', 'Home', 'Recast icons' }, { 'Minimal skin', 'Home', 'Skin' },
        { 'Show this panel', 'Display', 'Show this display' }, { 'label color', 'Display', 'Name color', 'Layout' },
        { 'value color', 'Display', 'Countdown color' }, { 'warning color', 'Display', 'Ending soon color' },
        { 'warning color', 'Display', 'Ready soon color' },
        -- Show samples, the main page's color rows and the buttons that reset.
        { 'End sample displays', 'Home', 'Show samples' }, { 'Sample party', 'Display', 'Show samples' },
        { 'Name', 'Home', 'Name' }, { 'Countdown', 'Home', 'Countdown' },
        { 'Detail text', 'Home', 'Detail text' }, { 'Bar track', 'Home', 'Bar track' },
        { 'Reset alert settings', 'Display', 'Reset this display' },
        -- The party list buffs' icon size shows only while a group is in a panel of its own, and none is in both checks,
        -- so these find each group's switch for that.
        { 'Buff and debuff icon size', 'Display', 'Your party in a panel of its own' },
        { 'Party icon size', 'Display', 'Your party in a panel of its own' },
        -- The party list buffs' countdown switch.
        { 'Show effect countdowns', 'Display', 'Countdowns' },
        -- The countdown and blink rows.
        { 'Bold effect countdowns', 'Home', 'Bold countdowns' }, { 'Countdown text outline', 'Home', 'Countdown outline' },
        { 'Effect countdown shadow', 'Home', 'Countdown shadow' }, { 'Blink expiring icons', 'Home', 'Blink before an effect ends' },
        -- What only a panel of its own uses. With no group in a panel of its own these words find each group's switch
        -- for that.
        { 'Snap buff panels to game windows', 'Display', 'Your party in a panel of its own' },
        { 'Reattach buff panels', 'Display', 'Your party in a panel of its own' },
        { 'Detached panel members', 'Display', 'Your party in a panel of its own' },
    }) do
        local found = false;
        for _, result in ipairs(window.search(entry[1])) do
            found = found or result.tab == entry[2] and (result.label == entry[3] or result.label == entry[4]);
        end;
        assert(found, when .. ', ' .. entry[1] .. ' finds ' .. entry[3] .. ' on ' .. entry[2]);
    end;
end;
-- The words for what Profiles and sharing shows only in some states: at first they find the control that shows it, and
-- once it is there the control itself.
local function state_names(when, index)
    for _, entry in ipairs({
        { 'Reset job profile links', 'Link this job', 'Unlink all jobs' },
        { 'Add from a share string', 'Import from clipboard', 'Import and add' },
        { 'Replace from a share string', 'Import from clipboard', 'Import and replace' },
        { 'Name for the imported profile', 'Import from clipboard', 'Save it as' },
        { 'Cancel the import', 'Import from clipboard', 'Clear the import' },
    }) do
        local found = false;
        for _, result in ipairs(window.search(entry[1])) do found = found or result.tab == 'Profiles' and result.label == entry[index]; end;
        assert(found, when .. ', ' .. entry[1] .. ' finds ' .. entry[index]);
    end;
end;
-- Bold countdowns is on the main page and on no display, and the words for a control find it where it is.
local function where_it_is(when)
    for _, result in ipairs(window.search('Bold countdowns')) do
        assert(result.tab ~= 'Display' or result.label ~= 'Bold countdowns', when .. ', Bold countdowns is on the main page only.');
    end;
    for _, entry in ipairs({
        { 'Timer icon size', 'Home', 'Icon size' }, { 'Recast icon artwork', 'Home', 'Recast icons' },
        { 'Only effects I applied', 'Display', 'Only effects I cast' }, { 'Selected members', 'Display', 'Members' },
        { 'Show party list buffs', 'Display', 'Show this display' },
        { 'Party buffs only', 'Display', 'Show buffs or debuffs' }, { 'Party debuffs only', 'Display', 'Show buffs or debuffs' },
        { 'Effect types', 'Display', 'Show buffs or debuffs' }, { 'Strip gap', 'Display', "Gap from the game's list" },
        { 'Reset strip offsets', 'Display', 'Put moved groups back' },
        { 'Strip maximum width', 'Display', 'Longest row' }, { 'Party & alliance', 'Display', 'Buffs beside the game party list' },
        { 'Hover details', 'Home', 'Show details when I point at a timer' },
        -- Snap distance shows only while Grid mode is on, and it is off in both checks, so it finds Grid mode.
        { 'Snap distance', 'Home', 'Grid mode' },
    }) do
        local found = false;
        for _, result in ipairs(window.search(entry[1])) do found = found or result.tab == entry[2] and result.label == entry[3]; end;
        assert(found, when .. ', ' .. entry[1] .. ' finds ' .. entry[3] .. ' on ' .. entry[2]);
    end;
    -- Grid mode, on the main page, is found by the words a player would type.
    for _, words in ipairs({ 'grid mode', 'grid', 'snap', 'snap to grid' }) do
        local found = false;
        for _, result in ipairs(window.search(words)) do found = found or result.tab == 'Home' and result.label == 'Grid mode'; end;
        assert(found, when .. ', ' .. words .. ' finds Grid mode on the main page');
    end;
end;
-- No control sets how many diagnostic events are kept, so words about a maximum find no tick on Help.
local function no_maximum(when)
    for _, words in ipairs({ 'Maximum diagnostic entries', 'maximum entries' }) do
        for _, result in ipairs(window.search(words)) do
            assert(not (result.tab == 'Help' and result.label == 'Record recent events'), when .. ', ' .. words .. ' finds no tick on Help');
        end;
    end;
end;
more_words('Before any page is drawn');
state_names('Before any page is drawn', 2);
where_it_is('Before any page is drawn');
no_maximum('Before any page is drawn');
-- More words are added beside a control's own keywords, not in place of them.
for _, entry in ipairs({ { 'cursor subtarget', 'Follow the cursor while I am choosing a target' } }) do
    local found = false;
    for _, result in ipairs(window.search(entry[1])) do found = found or result.tab == 'Display' and result.label == entry[2]; end;
    assert(found, 'Before any page is drawn, ' .. entry[1] .. ' still finds ' .. entry[2] .. ' on its panel');
end;
-- A label still holding this once every page is drawn was never marked. The panel frame keeps its own words, and
-- tests/test_panel_search.lua walks them.
local UNMARKED = '\0';
static.Display = nil;
for page, labels in pairs(static) do for label in pairs(labels) do index[page][label] = UNMARKED; end; end;

local combo;
local begin_combo, find = imgui.BeginCombo, imgui.InputTextWithHint;
imgui.BeginCombo = function(label, ...) begin_combo(label, ...); return label == combo; end;
imgui.InputTextWithHint = function(label, hint, value, ...)
    if label == '##find_settings' then value[1] = 'zzzz'; end;
    return find(label, hint, value, ...);
end;
local recasts = { { id = 10100, name = 'Cure', kind = 'spell', group = 'spell_recasts' } };
app.callbacks.recast_catalog = function(kind) return (not kind or kind == 'spell') and recasts or {}; end;
local view = { rows = {}, context = { valid = true, job = 3, party = { { id = 1001, name = 'Tester' }, { id = 1002, name = 'Friend' } },
    target = { id = 42, name = 'Crab', kind = 'monster' }, entities = {} } };
local function draw(page, click, opened)
    local s = app.state.settings;
    s.window.open, s.window.tab = true, page;
    combo = opened;
    if click then MOCK.clicks[click] = true; end;
    window.draw(s, view, app.callbacks);
    MOCK.clicks = {};
end;
local function every_page() for _, page in ipairs(tabs) do draw(page); draw(page); end; end;
local function fresh(change)
    local s = defaults.tidy(defaults.make());
    if change then change(s); end;
    app.state.settings = s;
    return s;
end;

-- Fresh settings.
fresh();
every_page();

-- Everything on: the party list strips, combined recasts, bars, rules and custom looks.
fresh(function(s)
    for _, panel in pairs(s.panels) do panel.gradient = true; end;
    local p = s.party_ui;
    p.enabled, p.preview = true, true;
    p.name_display = 'short';
    p.groups[2].native_detached = true;
    p.effects.fit_all = false;
    -- Party countdowns start off; on here, so their controls show.
    p.effects.timers = true;
    -- The party list buffs' own icons, a custom look.
    p.style.icon_art = 'Client';
    s.recast_display = 'combined';
    for _, panel in pairs(s.panels) do
        panel.mode, panel.order, panel.countdown_outline = 'bars', { 33 }, true;
    end;
    s.watch_ids = { 42 };
    -- The panels' buff light is off at first, so its glow and color controls show only once it is on.
    s.panels.target.dispel_light, s.panels.watch.dispel_light = true, true;
    local rule = defaults.rule('rule_1');
    rule.flash = true;
    s.alerts.rules = { rule };
    s.effect_filters.rules = { { enabled = true, effect = 253, kind = 'all', name = '', job = 0, scope = 'self' } };
    -- Grid mode starts off; on here, so the main page's grid controls show, with the ticks of the displays that are on.
    s.edit_mode.grid_mode = true;
    s.durations.learn = true;
    s.shared_layout = true;
end);
every_page();
-- The main page's lines that show only while something needs them, and the other text's outline.
fresh(function(s)
    s.enabled, s.effect_filters.enabled, s.alerts.enabled, s.alerts.muted, s.style.text_outline = false, false, true, true, true;
    s.ready_pulse.enabled = true;
    for _, id in ipairs({ 'recasts', 'spell_recasts', 'ability_recasts', 'item_recasts' }) do s.panels[id].enabled = false; end;
    local watch = s.party_cooldowns;
    watch.enabled, watch.list.enabled, watch.strips, watch.overhead = true, false, false, false;
end);
app.callbacks.edit_mode(true);
app.state.hidden = true;
require('ui.panel_frame').open('pet');
for _, page in ipairs({ 'Home', 'Display' }) do draw(page); draw(page); end;
app.callbacks.edit_mode(false);
app.state.hidden = false;
-- Lock all takes over from Unlock all while a display that is on is unlocked.
fresh(function(s) s.panels.self_buffs.locked = false; end);
draw('Home'); draw('Home');

-- The party list strips, separate recasts and icons.
fresh(function(s)
    local p = s.party_ui;
    p.enabled, p.name_display = true, 'job';
    for _, panel in pairs(s.panels) do panel.mode = 'icons'; end;
end);
every_page();
-- Timer durations with an override for each way to change the time, and a learned time to clear.
for _, mode in ipairs({ 'fixed', 'add', 'percent', 'count_up' }) do
    fresh(function(s)
        local rule = require('core.durations').override();
        rule.id, rule.mode = 253, mode;
        s.durations.overrides = { rule };
        s.durations.learned = { ['spell:253:2:crab'] = { samples = { 58, 60, 61 }, unit = 'Crab', at = 1 } };
    end);
    draw('Durations'); draw('Durations');
end;
-- The pet display with outlined countdowns.
fresh(function(s) s.pet.countdown_outline = true; end);
require('ui.panel_frame').open('pet');
draw('Display'); draw('Display');
-- Alerts' Size and place tab moving with a spot on the screen, then with another display, drawn on the screen.
for _, to in ipairs({ 'screen', 'element' }) do
    fresh(function(s) s.alerts.notice_anchor.to, s.alerts.notice_anchor.element = to, 'target'; end);
    require('ui.elements').record('notices', { x = 40, y = 120, width = 300, height = 80 });
    require('ui.panel_frame').open('notices', 'place');
    draw('Display'); draw('Display');
end;
-- Grid mode on with every display on, so the main page lists each display's tick: the recast panels one by one,
-- then combined, and the strips as they are drawn on the screen.
for _, recasts in ipairs({ 'separate', 'combined' }) do
    fresh(function(s)
        s.edit_mode.grid_mode, s.recast_display = true, recasts;
        for _, panel in pairs(s.panels) do panel.enabled = true; end;
        s.party_cooldowns.enabled, s.party_cooldowns.list.enabled = true, true;
        s.ready_pulse.enabled, s.ready_pulse.spot = true, 'screen';
        s.rolls.enabled, s.pet.enabled = true, true;
    end);
    for group = 1, 3 do require('ui.elements').record('strip_' .. group, { x = 600, y = 300 + group * 100, width = 60, height = 20 }); end;
    draw('Home'); draw('Home');
end;
-- An export read from the clipboard, with what Import and add and Import and replace would change, and one display
-- picked to copy.
fresh();
local shared = assert(require('core.share').export(app.state.settings, 'layout'));
imgui.GetClipboardText = function() return shared; end;
draw('Profiles', 'Import from clipboard'); draw('Profiles');
imgui.GetClipboardText = nil;
draw('Profiles', 'One display##element', '##Export'); draw('Profiles');

-- A saved profile, picked, overwritten and recoverable, and the job link on Home.
fresh();
assert(app.callbacks.profile_save('Healer', false), 'Fixture: the profile is saved.');
draw('Profiles', 'Healer', '##profiles');
draw('Profiles', 'Overwrite##profile_overwrite'); draw('Profiles');
draw('Profiles', 'Confirm overwrite'); draw('Profiles');
draw('Profiles', 'Link##profile_link'); draw('Profiles');
-- A whole profile placed on another screen size, read from the clipboard, and a file Import from a file lists.
local placed = store.copy(app.state.settings);
placed.placement_screen = { width = 2560, height = 1440 };
local profile_text = assert(require('core.share').export(placed, 'profile'));
imgui.GetClipboardText = function() return profile_text; end;
draw('Profiles', 'Import from clipboard'); draw('Profiles');
imgui.GetClipboardText = nil;
MOCK.dirs = MOCK.dirs or {};
MOCK.dirs[require('core.identity').root() .. 'shared/'] = { 'Raid.txt' };
draw('Profiles', 'Import from a file##profile_open_file'); draw('Profiles');
draw('Home'); draw('Home');

more_words('Once each page is drawn');
state_names('Once each page is drawn', 3);
where_it_is('Once each page is drawn');
no_maximum('Once each page is drawn');
-- What to share shows while sharing is on, so until then its words find the switch.
local function leads_to(label)
    local found = false;
    for _, result in ipairs(window.search('What to share across characters')) do found = found or result.tab == 'Profiles' and result.label == label; end;
    return found;
end;
assert(leads_to('Share settings across my characters'), 'With sharing off, What to share finds its switch.');
-- Each change counts, as every change the window makes does, so the search reads the switch again.
app.state.settings.shared_layout, app.state.settings_revision = true, app.state.settings_revision + 1;
assert(leads_to('What to share across characters'), 'With sharing on, it finds itself.');
app.state.settings.shared_layout, app.state.settings_revision = false, app.state.settings_revision + 1;
local missing = {};
for page, labels in pairs(static) do
    for label in pairs(labels) do
        local marked = index[page][label] ~= UNMARKED;
        -- A label ending in a space stands for the controls it begins, such as Watch Crab.
        if not marked and label:sub(-1) == ' ' then
            for drawn, text in pairs(index[page]) do
                marked = marked or not static[page][drawn] and drawn:sub(1, #label) == label and text ~= UNMARKED;
            end;
        end;
        if not marked then missing[#missing + 1] = page .. ': ' .. label; end;
    end;
end;
table.sort(missing);
assert(#missing == 0, 'Indexed labels that their page never marks:\n' .. table.concat(missing, '\n'));
-- The other way: every label a page marks is in the index before that page is opened, so search finds a
-- control on a page the player hasn't visited. Names that come from the player's data are the exception:
-- members, jobs, groups, the displays whose looks differ, and the controls a label ending in a space stands for.
local dynamic = { Tester = true, Friend = true, Timing = true, Cooldowns = true };
for _, job in ipairs({ 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN',
    'BLU', 'COR', 'PUP' }) do dynamic[job] = true; end;
local unindexed = {};
for page, labels in pairs(index) do
    for label in pairs(static[page] and labels or {}) do
        local known = static[page][label] or dynamic[label];
        for prefix in pairs(static[page]) do
            known = known or prefix:sub(-1) == ' ' and label:sub(1, #prefix) == prefix;
        end;
        if not known then unindexed[#unindexed + 1] = page .. ': ' .. label; end;
    end;
end;
table.sort(unindexed);
assert(#unindexed == 0, 'Labels a page marks that the index lacks until it is drawn:\n' .. table.concat(unindexed, '\n'));
imgui.BeginCombo, imgui.InputTextWithHint = begin_combo, find;
MOCK.fire('unload');
return 'Every indexed label is marked on its page, and every page the search names exists';
