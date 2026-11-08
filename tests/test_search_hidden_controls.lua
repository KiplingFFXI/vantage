-- The settings search finds a control only while its page shows it. While Grid mode is off, the main page's fold with
-- the grid's controls and each display's tick aren't drawn, and while no group whose strip is shown is in a panel of its
-- own, neither is what only a panel of its own uses. The search leaves them out then, so no result opens onto a control
-- that isn't there, and their names and more words find the switch that shows them: Grid mode on the main page, and each
-- group's switch under Panels of their own. A display's name never finds Grid mode.
-- The search goes by the settings the window draws, as they are when it runs, so a page that drew those controls puts
-- nothing back once their state is off again, and the same search run again follows the change. With Grid mode on, the
-- page lists a tick only for each display that is on (tests/test_grid_tick_list.lua), and the search follows it.
local store, defaults = require('core.store'), require('ui.defaults');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {},
    party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window = require('ui.settings_window');
local elements, panels = require('ui.elements'), require('ui.panel_frame');
local view = { rows = {}, context = { valid = true, job = 3, party = {}, entities = {} } };

local grid_controls = { 'Grid size', 'Show the grid', 'Snap to the grid', 'Snap to the screen center and edges',
    'Snap to other displays', "Snap to the game's party list", 'Snap to the chat log', 'Snap distance' };
local link = 'Grid and snapping';
local link_names = { link, 'Tick the displays that snap' };
local SNAP, BACK = "Snap back beside the game's list when released", 'Put party buffs back beside the party list';
local panel_controls = { SNAP, 'Icon size in a panel of its own', BACK, 'Member order', 'Member names', 'Group to order' };
local more_words = { ['Snap panels of their own to game windows'] = SNAP, ['Snap buff panels to game windows'] = SNAP,
    ['Reattach panels of their own'] = BACK, ['Reattach buff panels'] = BACK, ['Members in a panel of its own'] = 'Member order',
    ['Detached panel members'] = 'Member order', ['Member name display'] = 'Member names', ['Party group to edit'] = 'Group to order' };
local switches = { 'Your party in a panel of its own', 'Alliance 1 in a panel of its own', 'Alliance 2 in a panel of its own' };

local function results(query)
    local found = {};
    for _, result in ipairs(window.search(query)) do found[result.tab .. '/' .. result.label] = true; end;
    return found;
end;
local function every_switch(found)
    for _, label in ipairs(switches) do if not found['Display/' .. label] then return false; end; end;
    return true;
end;
-- Whether the search found a control exactly when its own words match.
local function own(found, query, page, label)
    return (found[page .. '/' .. label] or false) == window.matches(query, require('ui.search_index').controls[page][label]);
end;
local function own_switches(found, query)
    for _, label in ipairs(switches) do if not own(found, query, 'Display', label) then return false; end; end;
    return true;
end;
local function fresh(change)
    local s = defaults.tidy(defaults.make());
    if change then change(s); end;
    return s;
end;
-- Draws the window with s on page, and the search goes by s from then on.
local function draw(s, page, tab)
    s.window.open, s.window.tab = true, page or 'Home';
    app.state.settings = s;
    if tab then panels.open('party_ui', tab); end;
    window.draw(s, view, app.callbacks);
    window.draw(s, view, app.callbacks);
end;
local function both_on(s)
    s.edit_mode.grid_mode = true;
    s.party_ui.enabled, s.party_ui.groups[1].native_detached = true, true;
    s.party_ui.name_display = 'short';
end;

-- While Grid mode is off and no group is in a panel of its own.
local function hidden(when)
    for _, label in ipairs(grid_controls) do
        local found = results(label);
        assert(not found['Home/' .. label], when .. ', ' .. label .. ' is not found on the main page.');
        assert(found['Home/Grid mode'], when .. ', ' .. label .. ' finds Grid mode on the main page.');
    end;
    for _, name in ipairs(link_names) do
        local found = results(name);
        assert(not found['Home/' .. link], when .. ', ' .. name .. ' doesn\'t find ' .. link);
        assert(found['Home/Grid mode'], when .. ', ' .. name .. ' finds Grid mode on Home.');
    end;
    for _, element in ipairs(elements.movable) do
        local found = results(element.label);
        assert(not found['Home/' .. element.label .. ' for Grid mode'], when .. ', ' .. element.label .. ' finds no tick on the main page.');
        assert(not found['Home/Grid mode'], when .. ', ' .. element.label .. ' doesn\'t find Grid mode.');
    end;
    for _, label in ipairs(panel_controls) do
        local found = results(label);
        assert(not found['Display/' .. label], when .. ', ' .. label .. ' is not found on Party list buffs.');
        assert(not found['Home/' .. label], when .. ', ' .. label .. ' is not found on the main page.');
        assert(every_switch(found), when .. ', ' .. label .. ' finds the switch of each group under Panels of their own.');
    end;
    for words, label in pairs(more_words) do
        local found = results(words);
        assert(not found['Display/' .. label] and every_switch(found), when .. ', ' .. words .. ' finds the switches, not ' .. label);
    end;
    for _, words in ipairs({ 'reattach', 'detached', 'buff panels' }) do
        local found = results(words);
        assert(every_switch(found), when .. ', ' .. words .. ' finds the switches.');
        for _, label in ipairs(panel_controls) do
            assert(not found['Display/' .. label], when .. ', ' .. words .. ' doesn\'t find ' .. label);
        end;
    end;
end;
-- While both show them: each is found by its name and more words, and the switches that show them only by their own
-- words.
local function shown(when)
    for _, label in ipairs(grid_controls) do
        local found = results(label);
        assert(found['Home/' .. label], when .. ', ' .. label .. ' is found on the main page.');
        assert(own(found, label, 'Home', 'Grid mode'), when .. ', ' .. label .. ' finds Grid mode only by its own words.');
    end;
    for _, name in ipairs(link_names) do
        local found = results(name);
        assert(found['Home/' .. link], when .. ', ' .. name .. ' finds ' .. link);
        assert(own(found, name, 'Home', 'Grid mode'), when .. ', ' .. name .. ' finds Grid mode only by its own words.');
    end;
    for _, element in ipairs(elements.movable) do
        local found = results(element.label);
        assert((found['Home/' .. element.label .. ' for Grid mode'] or false) == elements.on(app.state.settings, element.id),
            when .. ', ' .. element.label .. ' finds its tick on the main page while it is on.');
        assert(not found['Home/Grid mode'], when .. ', ' .. element.label .. ' doesn\'t find Grid mode.');
    end;
    assert(results('Self buffs')['Home/Self buffs for Grid mode'], when .. ', Self buffs, on at first, finds its tick.');
    for _, label in ipairs(panel_controls) do
        local found = results(label);
        assert(found['Display/' .. label], when .. ', ' .. label .. ' is found on Party list buffs.');
        assert(not found['Home/' .. label], when .. ', ' .. label .. ' stays off the main page.');
        assert(own_switches(found, label), when .. ', ' .. label .. ' finds the switches only by their own words.');
    end;
    for words, label in pairs(more_words) do
        local found = results(words);
        assert(found['Display/' .. label] and own_switches(found, words), when .. ', ' .. words .. ' finds ' .. label);
    end;
    assert(results('reattach')['Display/' .. BACK], when .. ', reattach finds the way back.');
end;

hidden('Before the window is drawn');
draw(fresh());
hidden('Fresh settings');
-- These searches, one by one: none lists a control the page doesn't show.
for _, entry in ipairs({ { 'Watched enemy timers', 'Home', 'Watched enemy timers for Grid mode' }, { 'Self debuffs', 'Home', 'Self debuffs for Grid mode' },
    { 'Snap to the chat log', 'Home' }, { 'Snap distance', 'Home' }, { 'Grid size', 'Home' }, { 'reattach', 'Display', BACK } }) do
    assert(not results(entry[1])[entry[2] .. '/' .. (entry[3] or entry[1])], 'Fresh settings, ' .. entry[1] .. ' lists nothing hidden.');
end;

-- Bar fill end color shows only with the switch that makes it draw, and finds it until then.
draw(fresh(function(s) for _, panel in pairs(s.panels) do panel.mode = 'bars'; end; end));
assert(not results('Bar fill end color')['Display/Bar fill end color'] and results('Bar fill end color')['Display/Shaded bars'],
    'Bar fill end color finds Shaded bars while that is off.');
draw(fresh(function(s)
    for _, panel in pairs(s.panels) do panel.mode, panel.gradient = 'bars', true; end;
end));
assert(results('Bar fill end color')['Display/Bar fill end color'], 'With it on the search finds the row.');

-- Grid mode on and the party in a panel of its own, with both pages drawn.
local on = fresh(both_on);
draw(on, 'Home');
draw(on, 'Display', 'place');
draw(on);
shown('With both on');
-- Each state alone shows only its own.
draw(fresh(function(s) s.edit_mode.grid_mode = true; end));
assert(results('Snap distance')['Home/Snap distance'] and not results('Reattach panels of their own')['Display/' .. BACK]
    and every_switch(results('Reattach panels of their own')), 'Grid mode on alone shows only the grid\'s controls.');
draw(fresh(function(s) s.party_ui.groups[1].native_detached = true; end));
assert(not results('Snap distance')['Home/Snap distance'] and results('Reattach panels of their own')['Display/' .. BACK],
    'A panel of its own alone shows only what a panel of its own uses.');
-- A group in a panel of its own whose strip is off shows none of it.
draw(fresh(function(s) s.party_ui.groups[2].native_detached, s.party_ui.strips.alliance1 = true, false; end));
assert(not results('Reattach panels of their own')['Display/' .. BACK], 'A panel of its own whose strip is off shows none of it.');

-- Off again: what the pages drew stays out.
draw(fresh());
hidden('Off again after the pages drew them');
-- The same search, run again as the settings change under it, follows them. A change made here by hand counts as one,
-- as a change made on a page or by a command does.
local s = fresh(both_on);
draw(s);
assert(results('snap distance')['Home/Snap distance'], 'Fixture: with Grid mode on, snap distance finds Snap distance.');
s.edit_mode.grid_mode = false;
app.state.settings_revision = app.state.settings_revision + 1;
local found = results('snap distance');
assert(not found['Home/Snap distance'] and found['Home/Grid mode'], 'Grid mode turned off, the same search finds Grid mode instead.');
s.edit_mode.grid_mode = true;
app.state.settings_revision = app.state.settings_revision + 1;
assert(results('snap distance')['Home/Snap distance'], 'And on again, Snap distance.');
assert(results('reattach')['Display/' .. BACK], 'Fixture: with the party in a panel of its own, reattach finds it.');
s.party_ui.groups[1].native_detached = false;
app.state.settings_revision = app.state.settings_revision + 1;
assert(not results('reattach')['Display/' .. BACK] and every_switch(results('reattach')),
    'The party back beside the list, the same search finds the switches instead.');
MOCK.fire('unload');
return true;
