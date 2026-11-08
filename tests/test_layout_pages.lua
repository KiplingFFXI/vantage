-- Profiles and sharing, a panel's Place and When to show tabs and the main page's links, in the real settings window through
-- vantage.lua. Each control writes its own key as one Undo step named for it; Undo puts it back and Redo does it again.
-- Search finds them before a page is opened. /vg set, get and reset reach the edit mode grid, the anchors and the show
-- conditions. Profiles and shared presentation carry them; placement sharing carries a panel's anchor; each character
-- keeps its own locks. A save without them loads with every anchor and condition at its default.
local store = require('core.store');
local SNAP = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, level = 75, self_known = true, self_effects = {},
    party = {}, entities = { [1001] = { id = 1001, index = 0x400, name = 'Tester', kind = 'player' } } };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(SNAP); end, accept = function() end,
    packet_size = function(e) return e.size or 0; end };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, status = function() return { active = false }; end };
local imgui = require('imgui');
local defaults, custom, profiles = require('ui.defaults'), require('core.customization'), require('core.profiles');
local elements, conditions = require('ui.elements'), require('core.conditions');
local copy = store.copy;
local app = dofile(ADDON_DIR .. '/vantage.lua');
local window = require('ui.settings_window');
MOCK.fire('load'); app.refresh(0);

local function found(query, tab, label)
    for _, result in ipairs(window.search(query)) do if result.tab == tab and result.label == label then return true; end end
    return false;
end;
-- Grid size and Snap to the chat log show only while Grid mode is on, and it starts off, so they find Grid mode.
for _, entry in ipairs({ { 'Start edit mode', 'Home', 'Edit mode' }, { 'Grid size', 'Home', 'Grid mode' }, { 'Snap to the chat log', 'Home', 'Grid mode' }, { 'anchor', 'Display', 'Moves with' },
    { 'nudge', 'Home', 'Edit mode: grid, snapping and nudging' },
    { 'fallback', 'Display', 'What a display moves with' }, { 'Lowest level', 'Display' }, { 'Level Sync', 'Display' },
    { 'Battlefields', 'Display' }, { 'Mog House', 'Display' }, { 'In an alliance', 'Display' }, { 'Engaged', 'Display', 'Fighting' },
    { 'dynamis', 'Display', 'When each display shows' }, { 'Copy the export', 'Profiles' }, { 'Import from clipboard', 'Profiles' },
    { 'clipboard', 'Profiles', 'Import and export settings' }, { 'Edit mode', 'Home' } }) do
    assert(found(entry[1], entry[2], entry[3] or entry[1]), 'Search finds ' .. (entry[3] or entry[1]) .. ' on ' .. entry[2] .. ' before it is drawn.');
end;
-- The edit mode bar has no width or height box, so searching for them doesn't lead there.
for _, word in ipairs({ 'width', 'height' }) do
    assert(not found(word, 'Home', 'Edit mode: grid, snapping and nudging'), 'Search for ' .. word .. ' doesn\'t lead to edit mode.');
end;

local combo, slider;
imgui.BeginCombo = function(label) return label == combo; end;
imgui.SliderFloat = function(label, value)
    if slider and slider[1] == label then value[1], slider = slider[2], nil; return true; end
    return false;
end;
local view = { rows = {}, context = { valid = true, job = 3, entities = {} } };
local function frame(step)
    step = step or {};
    combo, slider = step.combo, step.slider;
    if step.click then MOCK.clicks[step.click] = true; end
    window.draw(app.state.settings, view, app.callbacks);
    assert(not step.click or not MOCK.clicks[step.click], 'The control is on the page: ' .. tostring(step.click));
    assert(not slider, 'The control is on the page.');
    MOCK.clicks = {};
end;
local function begin(tab, setup)
    local s = defaults.tidy(defaults.make());
    local id, place = tab:match('^(.-)/(.+)$');
    if place then tab = 'Display'; require('ui.panel_frame').open(id == 'Display' and 'self_buffs' or id, place); end
    s.window.open, s.window.tab = true, tab;
    app.state.settings = s;
    if setup then setup(s); end
    frame();
    app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
    return copy(s);
end;
local function click(label) return { { click = label } }; end;
local function slide(label, value) return { { slider = { '##' .. label, value } } }; end;
local function pick(label, shown, value) return { { combo = '##' .. label, click = shown .. '##' .. value } }; end;
local function screen(s) s.panels.self_buffs.anchor.to = 'screen'; end;
local function beside(s) s.panels.self_buffs.anchor.to, s.panels.self_buffs.anchor.element = 'element', 'target'; end;
local function pet_screen(s) s.pet.locked, s.pet.anchor.to = false, 'screen'; end;
local function pet_beside(s) s.pet.locked, s.pet.anchor.to, s.pet.anchor.element = false, 'element', 'target'; end;
-- The ticks and the grid's controls show while Grid mode is on.
local function grid_on(s) s.edit_mode.grid_mode = true; end;
-- { page, name, setup, steps, check(settings), Undo label, key }
local rows = {
    { 'Home', 'Grid mode', nil, click('Grid mode##main_grid_mode'), function(s) return s.edit_mode.grid_mode == true; end, 'Grid mode', 'edit_mode' },
    { 'Home', 'A tick for Grid mode', grid_on, click('Self buffs##grid_tick_self_buffs'),
        function(s) return #s.edit_mode.grid_displays == 1 and s.edit_mode.grid_displays[1] == 'self_buffs'; end, 'Tick Self buffs for Grid mode', 'edit_mode' },
    { 'Home', 'Grid size', grid_on, slide('main_grid_size', 24), function(s) return s.edit_mode.grid == 24; end, 'Grid size', 'edit_mode' },
    { 'Home', 'Show the grid', grid_on, click('Show the grid##main_show_grid'), function(s) return s.edit_mode.show_grid == false; end, 'Show the grid', 'edit_mode' },
    { 'Home', 'Snap to the grid', grid_on, click('Snap to the grid##main_snap_grid'), function(s) return s.edit_mode.snap_grid == false; end, 'Snap to the grid', 'edit_mode' },
    { 'Home', 'Snap to the screen center and edges', grid_on, click('Snap to the screen center and edges##main_snap_screen'), function(s) return s.edit_mode.snap_screen == false; end,
        'Snap to the screen center and edges', 'edit_mode' },
    { 'Home', 'Snap to other displays', grid_on, click('Snap to other displays##main_snap_elements'), function(s) return s.edit_mode.snap_elements == false; end, 'Snap to other displays', 'edit_mode' },
    { 'Home', "Snap to the game's party list", grid_on, click("Snap to the game's party list##main_snap_party"), function(s) return s.edit_mode.snap_party == false; end,
        "Snap to the game's party list", 'edit_mode' },
    { 'Home', 'Snap to the chat log', grid_on, click('Snap to the chat log##main_snap_chat'), function(s) return s.edit_mode.snap_chat == false; end, 'Snap to the chat log', 'edit_mode' },
    { 'Home', 'Snap distance', grid_on, slide('main_snap_distance', 12), function(s) return s.edit_mode.snap_distance == 12; end, 'Snap distance', 'edit_mode' },
    { 'pet/place', 'Moves with on Pet', nil, pick('frame_Moves with', 'A spot on the screen', 'screen'), function(s) return s.pet.anchor.to == 'screen'; end, 'Moves with', 'pet' },
    { 'pet/place', 'Moves with another display on Pet', nil, pick('frame_Moves with', 'Phantom Roll', 'element:rolls'),
        function(s) return s.pet.anchor.to == 'element' and s.pet.anchor.element == 'rolls'; end, 'Moves with', 'pet' },
    { 'pet/place', 'Spot on Pet', pet_screen, pick('frame_Spot', 'Bottom right', 'bottom_right'), function(s) return s.pet.anchor.point == 'bottom_right'; end, 'Spot', 'pet' },
    { 'pet/place', 'Across from it on Pet', pet_screen, slide('frame_Across from it', -40), function(s) return s.pet.anchor.dx == -40; end, 'Across from it', 'pet' },
    { 'pet/place', 'Down from it on Pet', pet_screen, slide('frame_Down from it', 25), function(s) return s.pet.anchor.dy == 25; end, 'Down from it', 'pet' },
    { 'pet/place', 'Side on Pet', pet_beside, pick('frame_Side', 'Right', 'right'), function(s) return s.pet.anchor.side == 'right'; end, 'Side', 'pet' },
    { 'pet/place', 'Line up on Pet', pet_beside, pick('frame_Line up', 'Middle', 'center'), function(s) return s.pet.anchor.align == 'center'; end, 'Line up', 'pet' },
    { 'pet/place', 'Gap on Pet', pet_beside, slide('frame_Gap', 20), function(s) return s.pet.anchor.gap == 20; end, 'Gap', 'pet' },
    { 'pet/place', 'Along the side on Pet', pet_beside, slide('frame_Along the side', -15), function(s) return s.pet.anchor.offset == -15; end, 'Along the side', 'pet' },
    { 'pet/place', 'Across on Pet', pet_beside, slide('frame_Across', 777), function(s) return s.pet.x == 777; end, 'Across', 'pet' },
    { 'pet/place', 'Down on Pet', pet_beside, slide('frame_Down', 333), function(s) return s.pet.y == 333; end, 'Down', 'pet' },
    { 'pet/place', 'Put it back where it started on Pet', pet_beside, click('Put it back where it started##frame'), function(s) return s.pet.anchor.to == 'none'; end, 'Put Pet back', 'pet' },
    { 'Display/place', 'Moves with', nil, pick('frame_Moves with', 'A spot on the screen', 'screen'), function(s) return s.panels.self_buffs.anchor.to == 'screen'; end,
        'Moves with', 'panels' },
    -- Phantom Roll and the cooldown list have theirs on their Size and place tab too.
    { 'rolls/place', 'Moves with on Phantom Roll', nil, pick('frame_Moves with', 'A spot on the screen', 'screen'), function(s) return s.rolls.anchor.to == 'screen'; end,
        'Moves with', 'rolls' },
    { 'cooldown_list/place', 'Moves with on the cooldown list', function(s) s.party_cooldowns.enabled, s.party_cooldowns.list.enabled = true, true; end,
        pick('frame_Moves with', 'A spot on the screen', 'screen'),
        function(s) return s.party_cooldowns.list.anchor.to == 'screen'; end, 'Moves with', 'party_cooldowns' },
    { 'Display/place', 'Moves with another display', nil, pick('frame_Moves with', 'Pet', 'element:pet'),
        function(s) return s.panels.self_buffs.anchor.to == 'element' and s.panels.self_buffs.anchor.element == 'pet'; end, 'Moves with', 'panels' },
    { 'Display/place', 'Spot', screen, pick('frame_Spot', 'Bottom right', 'bottom_right'), function(s) return s.panels.self_buffs.anchor.point == 'bottom_right'; end, 'Spot', 'panels' },
    { 'Display/place', 'Across from it', screen, slide('frame_Across from it', -40), function(s) return s.panels.self_buffs.anchor.dx == -40; end, 'Across from it', 'panels' },
    { 'Display/place', 'Down from it', screen, slide('frame_Down from it', 25), function(s) return s.panels.self_buffs.anchor.dy == 25; end, 'Down from it', 'panels' },
    { 'Display/place', 'Side', beside, pick('frame_Side', 'Right', 'right'), function(s) return s.panels.self_buffs.anchor.side == 'right'; end, 'Side', 'panels' },
    { 'Display/place', 'Line up', beside, pick('frame_Line up', 'Middle', 'center'), function(s) return s.panels.self_buffs.anchor.align == 'center'; end, 'Line up', 'panels' },
    { 'Display/place', 'Gap', beside, slide('frame_Gap', 20), function(s) return s.panels.self_buffs.anchor.gap == 20; end, 'Gap', 'panels' },
    { 'Display/place', 'Along the side', beside, slide('frame_Along the side', -15), function(s) return s.panels.self_buffs.anchor.offset == -15; end, 'Along the side', 'panels' },
    { 'Display/place', 'Across', beside, slide('frame_Across', 777), function(s) return s.panels.self_buffs.x == 777; end, 'Across', 'panels' },
    { 'Display/place', 'Down', beside, slide('frame_Down', 333), function(s) return s.panels.self_buffs.y == 333; end, 'Down', 'panels' },
    { 'Display/place', 'Put it back where it started', beside, click('Put it back where it started##frame'), function(s) return s.panels.self_buffs.anchor.to == 'none'; end,
        'Put Self buffs back', 'panels' },
    { 'Display/when', 'Main job RDM', nil, click('RDM##frame_main'), function(s) return s.panels.self_buffs.conditions.main_jobs[5] == true; end, 'RDM', 'panels' },
    { 'Display/when', 'Sub job NIN', nil, click('NIN##frame_sub'), function(s) return s.panels.self_buffs.conditions.sub_jobs[13] == true; end, 'NIN', 'panels' },
    { 'Display/when', 'Lowest level', nil, slide('frame_From_min', 50), function(s) return s.panels.self_buffs.conditions.level_min == 50; end, 'Lowest level', 'panels' },
    { 'Display/when', 'Highest level', nil, slide('frame_To_max', 60), function(s) return s.panels.self_buffs.conditions.level_max == 60; end, 'Highest level', 'panels' },
    { 'Display/when', 'Level Sync', nil, click('Only while synced##frame_Level Sync_sync_yes'), function(s) return s.panels.self_buffs.conditions.level_sync == 'yes'; end,
        'Level Sync', 'panels' },
    { 'Display/when', 'Dungeons', nil, click('Dungeons##frame_zone'), function(s) return s.panels.self_buffs.conditions.zones.dungeon == true; end, 'Dungeons', 'panels' },
    { 'Display/when', 'Battlefields', nil, click('Battlefields##frame_zone'), function(s) return s.panels.self_buffs.conditions.zones.battlefield == true; end,
        'Battlefields', 'panels' },
    { 'Display/when', 'In a party', nil, click('In a party##frame_group'), function(s) return s.panels.self_buffs.conditions.group.party == true; end,
        'In a party', 'panels' },
    { 'Display/when', 'Fighting', nil, click('Only while engaged##frame_Fighting_fight_yes'), function(s) return s.panels.self_buffs.conditions.engaged == 'yes'; end, 'Fighting', 'panels' },
    { 'Display/when', 'Pet', nil, click('Only with no pet out##frame_Pet_pet_no'), function(s) return s.panels.self_buffs.conditions.pet == 'no'; end, 'Pet', 'panels' },
    { 'Display/when', 'Clear these conditions', function(s) s.panels.self_buffs.conditions.main_jobs[5] = true; end, click('Clear these conditions##frame_when'),
        function(s) return next(s.panels.self_buffs.conditions.main_jobs) == nil; end, 'Clear the When to show choices of Self buffs', 'panels' },
};
local function outside(s, key)
    local value = copy(s);
    value[key], value.window, value.profile_job = nil, nil, nil;
    return value;
end;
for _, row in ipairs(rows) do
    local before = begin(row[1], row[3]);
    local key = row[7];
    local own_before = copy(app.state.settings[key]);
    for _, step in ipairs(row[4]) do frame(step); end
    local s = app.state.settings;
    assert(row[5](s), 'The control writes its key: ' .. row[2]);
    assert(#app.state.history == 1 and app.state.history[1].label == row[6],
        'One Undo step named ' .. row[6] .. ': ' .. row[2] .. ' (' .. #app.state.history .. ', ' .. tostring(app.state.history[1] and app.state.history[1].label) .. ')');
    assert(custom.equal(outside(s, key), outside(before, key)), 'Nothing else changes: ' .. row[2]);
    local after = copy(s[key]);
    assert(app.callbacks.undo());
    assert(custom.equal(app.state.settings[key], own_before), 'Undo puts it back: ' .. row[2]);
    assert(app.callbacks.redo());
    assert(custom.equal(app.state.settings[key], after), 'Redo does it again: ' .. row[2]);
end;
-- A display that would follow round can't be picked: the page says why and nothing changes.
begin('pet/place', function(s) pet_beside(s); s.panels.target.anchor.to, s.panels.target.anchor.element = 'element', 'rolls'; end);
frame({ combo = '##frame_Moves with', click = 'Target timers##element:target' });
assert(#app.state.history == 0 and app.state.settings.pet.anchor.element == 'target', 'Fixture: it already follows Target timers.');
app.state.settings.rolls.anchor.to, app.state.settings.rolls.anchor.element = 'element', 'pet';
frame({ combo = '##frame_Moves with', click = 'Phantom Roll##element:rolls' });
assert(#app.state.history == 0 and app.state.settings.pet.anchor.element == 'target', 'A display that follows it back can\'t be picked.');
-- Moves with on a panel's Size and place tab says the same.
begin('Display/place', function(s) beside(s); s.panels.target.anchor.to, s.panels.target.anchor.element = 'element', 'pet'; end);
frame({ combo = '##frame_Moves with', click = 'Target timers##element:target' });
assert(#app.state.history == 0 and app.state.settings.panels.self_buffs.anchor.element == 'target', 'Fixture: it already follows Target timers.');
app.state.settings.pet.anchor.to, app.state.settings.pet.anchor.element = 'element', 'self_buffs';
frame({ combo = '##frame_Moves with', click = 'Pet##element:pet' });
assert(#app.state.history == 0 and app.state.settings.panels.self_buffs.anchor.element == 'target', 'A display that follows it back can\'t be picked.');
-- The pages say it in plain words.
begin('Display/when', function(s) s.panels.self_buffs.conditions = conditions.tidy({ main_jobs = { 3 }, zones = { 'town' } }); end);
local said = {};
for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'TextWrapped' then said[#said + 1] = call[2]; end; end;
local words = table.concat(said, ' | ');
assert(words:find('Self buffs: Main job WHM. In Towns.', 1, true), 'Plain words: ' .. words);
assert(not words:find('?', 1, true), 'No question marks.');
-- The main page starts and ends edit mode.
begin('Home');
frame({ click = 'Edit mode##main' });
assert(require('ui.edit_mode').active(), 'Edit mode turns it on.');
frame({ click = 'End edit mode##main_edit_end' });
assert(not require('ui.edit_mode').active(), 'End edit mode turns it off.');
-- The main page's links.
begin('Home');
frame({ click = 'Profiles' });
assert(app.state.settings.window.tab == 'Profiles', 'The main page opens Profiles.');
app.state.settings.window.tab = 'Home'; frame();
frame({ click = 'Help' });
assert(app.state.settings.window.tab == 'Help', 'The main page opens Help.');

-- /vg set, get and reset.
local function command(text) local event = { command = text }; MOCK.fire('command', event); return event; end;
begin('Home');
command('/vg set edit_mode.grid 32');
assert(app.state.settings.edit_mode.grid == 32, '/vg set reaches the grid.');
command('/vg set edit_mode.grid 9999');
assert(app.state.settings.edit_mode.grid == 32, 'An out-of-range grid is turned down and nothing changes.');
command('/vg set panels.target.anchor {"to":"screen","point":"bottom","dx":0,"dy":-20}');
assert(app.state.settings.panels.target.anchor.to == 'screen' and app.state.settings.panels.target.anchor.dy == -20, '/vg set reaches an anchor.');
command('/vg set rolls.conditions.engaged yes');
assert(app.state.settings.rolls.conditions.engaged == 'yes', '/vg set reaches a show condition.');
command('/vg get edit_mode.grid');
assert(MOCK.printed[#MOCK.printed]:find('edit_mode.grid = 32', 1, true), '/vg get reads the grid.');
assert(app.callbacks.reset('edit_mode') and app.state.settings.edit_mode.grid == 16, '/vg reset edit_mode restores it.');
assert(app.callbacks.reset('moves_with') and app.state.settings.panels.target.anchor.to == 'none', '/vg reset moves_with clears them.');
-- /vg reset layout takes Grid mode, its ticks and the grid back as well, as one Undo step.
do
    local s = app.state.settings;
    s.edit_mode.grid, s.edit_mode.grid_mode, s.edit_mode.grid_displays = 40, true, { 'pet' };
    s.panels.target.anchor.to = 'chat';
    assert(app.callbacks.reset('layout'), 'Fixture: the reset ran.');
    s = app.state.settings;
    assert(s.edit_mode.grid == 16 and s.edit_mode.grid_mode == false and #s.edit_mode.grid_displays == 0 and s.panels.target.anchor.to == 'none',
        '/vg reset layout resets the grid and every anchor.');
    assert(app.callbacks.history_status().undo_label == 'Reset layout', 'It is one named Undo step.');
    assert(app.callbacks.undo() and app.state.settings.edit_mode.grid == 40 and app.state.settings.panels.target.anchor.to == 'chat', 'Undo brings them back.');
    assert(app.callbacks.reset('moves_with'), 'Fixture: back to no anchors.');
end;
assert(app.callbacks.reset('conditions') and app.state.settings.rolls.conditions.engaged == 'any', '/vg reset conditions clears them.');

-- Profiles, shared presentation and placement sharing.
local s = app.state.settings;
s.edit_mode.grid, s.rolls.locked = 20, false;
s.panels.target.anchor = { to = 'screen', point = 'top', dx = 0, dy = 30, element = '', side = 'below', align = 'start', gap = 4, offset = 0 };
s.pet.anchor = { to = 'chat', side = 'above', align = 'start', gap = 4, offset = 0, element = '', point = 'top_left', dx = 0, dy = 0 };
s.alerts.notice_anchor = { to = 'party', side = 'above', align = 'end', gap = 6, offset = 0, element = '', point = 'top_left', dx = 0, dy = 0 };
s.rolls.conditions = conditions.tidy({ main_jobs = { 17 } });
s.alerts.notice_conditions = conditions.tidy({ engaged = 'yes' });
local saved = profiles.capture(s);
assert(saved.edit_mode.grid == 20 and saved.panels.target.anchor.to == 'screen' and saved.rolls.conditions.main_jobs[17], 'A profile saves them.');
local presentation = profiles.capture_layout(s, 'presentation').presentation;
assert(presentation.edit_mode.grid == 20 and presentation.pet.anchor.to == 'chat' and presentation.alerts.notice_anchor.to == 'party'
    and presentation.alerts.notice_conditions.engaged == 'yes' and presentation.rolls.conditions.main_jobs[17], 'Shared presentation carries them.');
local other = defaults.tidy(defaults.make());
assert(profiles.apply_layout(other, { scope = 'presentation', presentation = presentation }, 'presentation'));
assert(other.edit_mode.grid == 20 and other.pet.anchor.to == 'chat' and other.alerts.notice_anchor.to == 'party' and other.rolls.locked,
    'Another character takes them and keeps its own locks.');
local placement = profiles.capture_layout(s, 'placement');
assert(placement.target.anchor.to == 'screen', 'Placement sharing carries a panel\'s anchor.');
other = defaults.tidy(defaults.make());
assert(profiles.apply_layout(other, placement, 'placement') and other.panels.target.anchor.dy == 30, 'and another character takes it.');
assert(app.callbacks.profile_save('Layout test', false) and app.callbacks.profile_load('Layout test'), 'Fixture: the profile saves and loads.');
assert(app.state.settings.edit_mode.grid == 20 and app.state.settings.alerts.notice_conditions.engaged == 'yes', 'Loading the profile brings them back.');

-- A save without them: every display gets an anchor and conditions at their defaults; an odd one is tidied.
local plain = defaults.make();
plain.edit_mode = nil;
for _, panel in pairs(plain.panels) do panel.anchor, panel.conditions = nil, nil; end;
plain.alerts.notice_anchor, plain.alerts.notice_conditions, plain.party_ui.conditions, plain.overhead.conditions = nil, nil, nil, nil;
plain.pet.anchor = 'beside the moon';
plain.rolls.conditions = { main_jobs = 'COR', level_min = -4 };
local loaded = defaults.tidy(plain);
local fresh = defaults.make();
assert(custom.equal(loaded.edit_mode, fresh.edit_mode), 'The edit mode settings are added at their defaults.');
for _, element in ipairs(elements.list) do
    if element.anchor then assert(custom.equal(elements.anchor(loaded, element.id), elements.anchor(fresh, element.id)),
        element.id .. ' gets its anchor at its default.'); end;
    if element.conditions then assert(custom.equal(elements.conditions(loaded, element.id), elements.conditions(fresh, element.id)),
        element.id .. ' gets its show conditions at their default.'); end;
end;
MOCK.fire('unload');
return true;
