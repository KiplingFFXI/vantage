-- With Grid mode on, the main page's Grid and snapping lists a tick only for each display that is on, as edit mode
-- outlines it (a strip while it is drawn, so an alliance strip only in an alliance), in the displays' order, under the
-- line Tick the displays that snap:, then Grid size and the rest. A display that is off keeps its tick: ticking another
-- keeps it, tidying keeps it, and turned on again it shows ticked. With no display on there is no line and no list. The
-- search finds a display's tick only while Grid mode and that display are on.
local store = require('core.store');
local SNAP = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, level = 75, self_known = true, self_effects = {},
    party = {}, entities = { [1001] = { id = 1001, index = 0x400, name = 'Tester', kind = 'player' } } };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(SNAP); end, accept = function() end,
    packet_size = function(e) return e.size or 0; end };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, status = function() return { active = false }; end };
local defaults, elements, snap = require('ui.defaults'), require('ui.elements'), require('ui.snap');
local app = dofile(ADDON_DIR .. '/vantage.lua');
local window = require('ui.settings_window');
MOCK.fire('load'); app.refresh(0);
local view = { rows = {}, context = { valid = true, job = 3, entities = {} } };
local LINE = 'Tick the displays that snap:';

-- Fresh settings with Grid mode on, on the main page.
local function fresh(change)
    local s = defaults.tidy(defaults.make());
    s.window.open, s.window.tab, s.edit_mode.grid_mode = true, 'Home', true;
    if change then change(s); end;
    app.state.settings = s;
    return s;
end;
-- A change made here by hand counts as one, as a change made on a page or by a command does, so the search reads the
-- settings again.
local function changed() app.state.settings_revision = app.state.settings_revision + 1; end;
-- Draws the main page. Returns the ids of the ticks it lists, in order, whether the line came once before the
-- first of them and Grid size after the last (or neither line nor tick came), whether Grid size came, and the
-- value each tick showed.
local function page(click)
    MOCK.imgui_calls = {};
    if click then MOCK.clicks[click] = true; end;
    window.draw(app.state.settings, view, app.callbacks);
    assert(not click or not MOCK.clicks[click], 'Fixture: the control is on the page: ' .. tostring(click));
    MOCK.clicks = {};
    local ids, shown, lines, line_at, first_at, last_at, grid_at = {}, {}, 0, nil, nil, nil, nil;
    for index, call in ipairs(MOCK.imgui_calls) do
        local id = call[1] == 'Checkbox' and type(call[2]) == 'string' and call[2]:match('##grid_tick_(.+)$');
        if id then ids[#ids + 1], shown[id], first_at, last_at = id, call[3][1], first_at or index, index; end;
        if call[1] == 'TextWrapped' and call[2] == LINE then lines, line_at = lines + 1, index; end;
        if grid_at == nil and call[1] == 'SliderFloat' and call[2] == '##main_grid_size' then grid_at = index; end;
    end;
    local placed = #ids == 0 and lines == 0 or lines == 1 and first_at ~= nil and line_at < first_at and grid_at ~= nil and last_at < grid_at;
    return table.concat(ids, ' '), placed, grid_at ~= nil, shown;
end;
local function found(label)
    for _, result in ipairs(window.search(label)) do if result.tab == 'Home' and result.label == label .. ' for Grid mode' then return true; end; end;
    return false;
end;
-- The search finds the tick of each display listed, by its name, and none of the others.
local function searched(listed, when)
    local on = {};
    for id in listed:gmatch('%S+') do on[id] = true; end;
    for _, element in ipairs(elements.movable) do
        assert(found(element.label) == (on[element.id] == true), when .. ', the search finds the tick of ' .. element.label .. ' only while it is listed.');
    end;
end;
local function every_display(s, recasts)
    s.recast_display = recasts;
    for _, panel in pairs(s.panels) do panel.enabled = true; end;
    s.party_cooldowns.enabled, s.party_cooldowns.list.enabled = true, true;
    s.ready_pulse.enabled, s.ready_pulse.spot = true, 'screen';
    s.rolls.enabled, s.pet.enabled = true, true;
end;

-- Fresh settings have Self buffs, Self debuffs, Target timers and Alerts on.
local s = fresh();
local listed, placed, grid = page();
assert(listed == 'self_buffs self_debuffs target notices' and placed and grid,
    'Grid mode on, the page lists the ticks of the displays that are on, under the line, then Grid size: ' .. listed);
searched(listed, 'Fresh settings');
s.edit_mode.grid_mode = false;
changed();
listed, placed, grid = page();
assert(listed == '' and placed and not grid, 'Grid mode off, there is no line, no tick and no Grid size.');
searched('', 'Grid mode off');

-- Every display on: the recast panels one by one, then combined, in the displays' order.
s = fresh(function(value) every_display(value, 'separate'); end);
listed, placed = page();
assert(listed == 'self_buffs self_debuffs target party watch spell_recasts ability_recasts item_recasts notices cooldown_list pulse rolls pet'
    and placed, 'Every display on lists each of them: ' .. listed);
searched(listed, 'Every display on');
s.recast_display = 'combined';
changed();
listed, placed = page();
assert(listed == 'self_buffs self_debuffs target party watch recasts notices cooldown_list pulse rolls pet' and placed,
    'With combined recasts, Combined recasts instead of the three: ' .. listed);
searched(listed, 'Combined recasts');

-- A strip shows while it is drawn: the party strip in a party, an alliance strip only in an alliance.
s = fresh(function(value) value.party_ui.enabled = true; end);
elements.record('strip_1', { x = 600, y = 700, width = 60, height = 20 });
listed = page();
assert(listed == 'self_buffs self_debuffs target notices strip_1', 'In a party, the party strip is listed: ' .. listed);
searched(listed, 'In a party');
elements.record('strip_2', { x = 600, y = 500, width = 60, height = 20 });
elements.record('strip_3', { x = 600, y = 300, width = 60, height = 20 });
listed = page();
assert(listed == 'self_buffs self_debuffs target notices strip_1 strip_2 strip_3', 'In an alliance, the alliance strips too: ' .. listed);
searched(listed, 'In an alliance');
elements.frame(); elements.frame();
listed = page();
assert(listed == 'self_buffs self_debuffs target notices', 'A strip no longer drawn goes from the list: ' .. listed);
searched(listed, 'With no strip drawn');

-- A display that is off keeps its tick.
s = fresh(function(value) value.pet.enabled = true; end);
local steps = #app.state.history;
listed = page('Pet##grid_tick_pet');
assert(table.concat(s.edit_mode.grid_displays, ' ') == 'pet' and #app.state.history == steps + 1, 'Fixture: Pet is ticked, as one Undo step.');
s.pet.enabled = false;
changed();
listed = page();
assert(listed == 'self_buffs self_debuffs target notices' and snap.ticked(s, 'pet'), 'Pet turned off goes from the list and keeps its tick.');
assert(not found('Pet'), 'The search no longer finds Pet\'s tick.');
page('Self buffs##grid_tick_self_buffs');
assert(table.concat(s.edit_mode.grid_displays, ' ') == 'self_buffs pet', 'Ticking another display keeps it.');
assert(table.concat(defaults.tidy(store.copy(s)).edit_mode.grid_displays, ' ') == 'self_buffs pet', 'Tidying keeps it.');
s.pet.enabled = true;
changed();
local ticked;
listed, placed, grid, ticked = page();
assert(listed == 'self_buffs self_debuffs target notices pet' and ticked.pet == true and ticked.self_buffs == true
    and ticked.target == false, 'Turned on again, Pet is listed and shows ticked: ' .. listed);
assert(found('Pet'), 'And the search finds its tick again.');

-- With no display on, the list and its line are left out, and the grid's controls show.
s = fresh(function(value)
    for _, panel in pairs(value.panels) do panel.enabled = false; end;
    value.alerts.enabled = false;
end);
listed, placed, grid = page();
assert(listed == '' and placed and grid, 'With no display on there is no line and no tick, and Grid size still shows.');
searched('', 'With no display on');
MOCK.fire('unload');
return true;
