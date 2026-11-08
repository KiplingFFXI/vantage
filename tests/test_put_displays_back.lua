-- Start over on Profiles and sharing. Put every display back where it started sends each display to the spot a fresh
-- install's first frame gives it on this screen at the size it has now, with nothing it moves with and locked. Its size,
-- what it shows and how it looks stay, as do Grid mode and a group's panel of its own. It is one Undo step. Reset all
-- settings puts every display in a fresh install's spots, and keeps profiles, job links, watched enemies and learned times.
local store, defaults = require('core.store'), require('ui.defaults');
local elements, setup, customization = require('ui.elements'), require('ui.setup_defaults'), require('core.customization');
MOCK.screen = { 1920, 1080 };
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, level = 75, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window = require('ui.settings_window');

-- Every display moved, following something and unlocked, with a size, choices and a look of its own.
local function moved()
    local s = app.state.settings;
    for _, element in ipairs(elements.movable) do
        local config = elements.config(s, element.id);
        if element.strip then
            config.native_x, config.native_y, config.native_side, config.detached_x, config.detached_y = 31, 32, 'left', 333, 334;
        else
            config[element.x], config[element.y] = 701, 702;
            config[element.anchor].to, config[element.anchor].dx = 'screen', 12;
        end;
        elements.lock_holder(s, element.id)[element.lock] = false;
    end;
    s.panels.self_buffs.width, s.panels.self_buffs.mode, s.panels.self_buffs.bar_style = 444, 'bars', 'rail';
    s.party_ui.groups[2].native_detached, s.party_ui.groups[2].detached_width = true, 500;
    s.rolls.width, s.pet.width = 345, 346;
    s.style.font_size, s.edit_mode.grid_mode, s.edit_mode.grid = 20, true, 24;
    s.job_profiles['3'], s.watch_ids = 'Raid', { 42 };
    s.durations.learned['spell:253:2:crab'] = { samples = { 57.5 }, unit = 'seconds', at = 1 };
    app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
end;
-- A fresh install's spots on this screen, clear of the chat log. Panels flow one after another, so a panel's size moves
-- the next one.
local function first_spots(sized)
    local first = defaults.tidy(defaults.make());
    if sized then sized(first); end;
    setup.place_fresh(first, { width = 1920, height = 1080, chat = app.state.snapshot.chat });
    return first;
end;
local function kept_sizes(first)
    first.panels.self_buffs.width, first.panels.self_buffs.mode, first.panels.self_buffs.bar_style = 444, 'bars', 'rail';
    first.rolls.width, first.pet.width, first.style.font_size = 345, 346, 20;
end;
local function at_first_spots(when, first)
    local s = app.state.settings;
    for _, element in ipairs(elements.movable) do
        local config, start = elements.config(s, element.id), elements.config(first, element.id);
        if element.strip then
            for _, key in ipairs({ 'native_x', 'native_y', 'native_side', 'detached_x', 'detached_y' }) do
                assert(store.equal(config[key], start[key]), when .. ', ' .. element.id .. ' has its first ' .. key);
            end;
        else
            assert(config[element.x] == start[element.x] and config[element.y] == start[element.y], when .. ', ' .. element.id .. ' is at its first spot: '
                .. tostring(config[element.x]) .. ', ' .. tostring(config[element.y]) .. ' and not ' .. tostring(start[element.x]) .. ', ' .. tostring(start[element.y]));
            assert(store.equal(config[element.anchor], start[element.anchor]), when .. ', ' .. element.id .. ' moves with nothing.');
        end;
        assert(elements.locked(s, element.id), when .. ', ' .. element.id .. ' is locked.');
    end;
end;
local function kept(when)
    local s = app.state.settings;
    assert(s.job_profiles['3'] == 'Raid' and s.watch_ids[1] == 42 and s.durations.learned['spell:253:2:crab'], when .. ', job links, watched enemies and learned times stay.');
end;

-- The button, on the page, with the line under it.
moved();
local s = app.state.settings;
s.window.open, s.window.tab = true, 'Profiles';
MOCK.imgui_calls = {};
window.draw(s, { rows = {}, context = { valid = true, entities = {} } }, app.callbacks);
local function said(text)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'TextWrapped' and call[2] == text then return true; end; end;
    return false;
end;
assert(said('Every display goes back to its first spot, locked. Looks and choices are kept.')
    and said('Every display goes back to a fresh install: locked, in its first spot. Profiles, job links, watched enemies and learned times are kept.'),
    'Start over says what each button does.');
local before = store.copy(s);
MOCK.clicks['Put every display back where it started'] = true;
window.draw(s, { rows = {}, context = { valid = true, entities = {} } }, app.callbacks);
assert(not MOCK.clicks['Put every display back where it started'], 'The button is on the page.');
at_first_spots('Put back', first_spots(kept_sizes));
kept('Put back');
s = app.state.settings;
assert(s.panels.self_buffs.width == 444 and s.panels.self_buffs.mode == 'bars' and s.panels.self_buffs.bar_style == 'rail' and s.rolls.width == 345 and s.pet.width == 346,
    'Sizes and what a display shows stay.');
assert(s.party_ui.groups[2].native_detached and s.party_ui.groups[2].detached_width == 500, 'A group\'s panel of its own stays a choice.');
assert(s.style.font_size == 20 and s.edit_mode.grid_mode and s.edit_mode.grid == 24, 'Looks and Grid mode stay.');
assert(app.callbacks.history_status().undo_label == 'Reset displays' and #app.state.history == 1, 'It is one Undo step.');
assert(app.callbacks.undo());
s = app.state.settings;
assert(customization.equal(store.copy(s.panels), before.panels) and s.rolls.x == 701 and not s.rolls.locked and s.party_ui.groups[1].native_x == 31,
    'Undo puts back every spot and lock.');

-- /vg reset panels resets the panels' places and sizes, with their locks, and leaves the other displays as they are.
local panels = customization.reset(store.copy(s), 'panels');
assert(panels.panels.self_buffs.width ~= 444 and panels.panels.self_buffs.locked == false and panels.rolls.x == 701, 'It resets the panels alone.');

-- /vg reset displays does what the button does.
moved();
local event = { command = '/vg reset displays' };
MOCK.fire('command', event);
assert(event.blocked, 'The command is taken.');
at_first_spots('The command', first_spots(kept_sizes));
kept('The command');

-- Reset all settings: the same spots, and it keeps what it says.
moved();
assert(app.callbacks.reset('all'));
at_first_spots('Reset all', first_spots());
kept('Reset all');
s = app.state.settings;
assert(s.panels.self_buffs.width ~= 444 and s.style.font_size ~= 20 and not s.edit_mode.grid_mode, 'Reset all settings resets the rest.');
assert(s.placement_screen.width == 1920 and s.placement_screen.height == 1080, 'The displays are placed for this screen.');
assert(#MOCK.commands == 0, 'Nothing is sent to the game.');
MOCK.fire('unload');
return 'Put every display back and Reset all settings give each display its first spot';
