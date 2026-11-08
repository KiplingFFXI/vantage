local store, defaults = require('core.store'), require('ui.defaults');
local equal = require('core.customization').equal;
local snapshot = {valid = true, id = 1001, name = 'Tester', zone = 102, job = 1, job_name = 'WAR',
    self_known = true, self_effects = {}, party = {}, entities = {}};
package.loaded['core.client'] = {load = function() end, read = function() return store.copy(snapshot); end};
local app = dofile(ADDON_DIR .. '/vantage.lua');
local panel_ids = {'self_buffs', 'self_debuffs', 'target', 'party', 'watch'};
local function command(text)
    local event = {command = text};
    MOCK.fire('command', event);
    assert(event.blocked, 'Vantage consumes its sorting commands.');
end;
local function persisted_matches(value)
    local encoded = require('json').decode(store.encode(value));
    return store.equal(assert(store.read(app.state.path)), encoded);
end;
local function other_settings(value)
    local result = store.copy(value);
    result.party_ui.effects.sort = nil;
    for _, id in ipairs(panel_ids) do result.panels[id].sort = nil; end;
    return result;
end;
MOCK.fire('load'); app.refresh(1);
local seeded = store.copy(app.state.settings);
seeded.shared_layout = false;
seeded.party_ui.effects.sort = 'remaining';
seeded.party_ui.locked = true;
seeded.party_ui.style.icon_art = 'XI View';
seeded.party_ui.native.width = 276;
seeded.party_ui.effects.growth = 'left';
seeded.party_ui.effects.pinned = {33};
seeded.party_ui.effects.order = {40, 33};
seeded.party_ui.effects.exclude = {253};
seeded.effect_filters.enabled = true;
seeded.effect_filters.rules = {require('core.effect_filters').rule()};
seeded.effect_filters.rules[1].effect = 253;
for index, id in ipairs(panel_ids) do
    local panel = seeded.panels[id];
    panel.sort = index % 2 == 0 and 'fixed' or 'name';
    panel.locked, panel.enabled, panel.width = index % 2 == 0, index % 2 == 1, 240 + index * 13;
    panel.pinned, panel.order, panel.exclude = {33}, {40, 33}, {253};
    panel.growth = index % 2 == 0 and 'left' or 'right';
end;
for id in pairs(defaults.recast_panels) do
    seeded.panels[id].sort = id == 'recasts' and 'fixed' or 'name';
    seeded.panels[id].pinned, seeded.panels[id].order = {57}, {57, 58};
end;
app.state.settings = defaults.tidy(seeded);
app.state.hidden = true;
app.callbacks.changed('after'); assert(app.callbacks.save());
local initial = store.copy(app.state.settings);
local writes, original_write = 0, store.write;
store.write = function(path, ...)
    if path == app.state.path then writes = writes + 1; end;
    return original_write(path, ...);
end;

local function invalid_commands(expected)
    local history, previous_writes = app.callbacks.history_status().undo, writes;
    for _, text in ipairs({'/vg sort', '/vg sort fixed', '/vg sort newest', '/vg sort unknown',
        '/vg sort longest extra', '/vg sort oldest extra', '/vg sort remaining party', '/vg sort name self'}) do
        app.state.wake = false;
        command(text);
        assert(equal(expected, app.state.settings) and not app.state.wake,
            'Missing, unsupported or extra arguments only show usage.');
        assert(app.callbacks.history_status().undo == history and writes == previous_writes,
            'Invalid commands neither save nor consume Undo history.');
        assert(MOCK.printed[#MOCK.printed]:find('Usage: /vg sort longest|oldest|remaining|name', 1, true));
    end;
end;
invalid_commands(initial);

local sort_labels = {longest = 'longest remaining first', oldest = 'oldest applied first',
    remaining = 'soonest expiring first', name = 'by name'};
for _, choice in ipairs({'longest', 'oldest', 'remaining', 'name'}) do
    local before = store.copy(app.state.settings);
    local history, previous_writes = app.callbacks.history_status().undo, writes;
    app.state.wake = false;
    command('/vg sort ' .. choice);
    local applied = store.copy(app.state.settings);
    assert(applied.party_ui.effects.sort == choice, 'The strips take the sorting.');
    for _, id in ipairs(panel_ids) do assert(applied.panels[id].sort == choice, id .. ' uses the requested effect sorting.'); end;
    assert(equal(other_settings(before), other_settings(applied)),
        'Only the six effect sort choices change; pins, custom order, filters, locks, skins and cooldowns stay intact.');
    assert(app.state.hidden and app.state.wake, 'Sorting refreshes immediately without unhiding displays.');
    assert(writes == previous_writes + 1 and persisted_matches(applied), 'One command writes the complete choice once.');
    assert(app.callbacks.history_status().undo == history + 1, 'All effect displays form one Undo step.');
    local message = MOCK.printed[#MOCK.printed];
    assert(message:find('Buffs and debuffs now sort', 1, true) and message:find('/vg undo', 1, true)
        and message:find('Pinned effects stay first; saved custom orders remain available', 1, true),
        'Confirmation identifies the change and its Undo command.');
    assert(message:find(sort_labels[choice], 1, true), 'Confirmation distinguishes remaining duration from application age.');
    command('/vg undo');
    assert(equal(before, app.state.settings) and persisted_matches(before), 'Undo restores every previous per-display sort choice.');
    command('/vg redo');
    assert(equal(applied, app.state.settings) and persisted_matches(applied), 'Redo restores and persists the chosen sorting.');
    command('/vg sort ' .. choice);
    assert(equal(applied, app.state.settings) and app.callbacks.history_status().undo == history + 1,
        'Repeating the same sort does not add a redundant Undo step.');
    invalid_commands(applied);
end;
command('/vg sort LONGEST');
assert(app.state.settings.party_ui.effects.sort == 'longest', 'Command choices accept normal chat capitalization.');
command('/vg help');
assert(MOCK.printed[#MOCK.printed]:find('sort [longest|oldest|remaining|name]', 1, true), 'The normal help list advertises the command.');
assert(#MOCK.commands == 0, 'Sorting never sends game commands.');
MOCK.fire('unload');
return 'Opt-in global effect sort command, exact settings scope, persistence, Undo/Redo and invalid-argument handling';
