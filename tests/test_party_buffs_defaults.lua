-- Party list buff countdowns start off, and the strips start 26 px from the game's party list. After that the player's
-- own choices stay: through every tidy, Countdowns on Party list buffs as one Undo step, a save and a reload, /vg set
-- and Apply setup. Profiles, shared layouts of the whole look and exports carry their countdowns and gap as they
-- are, and reading one writes nothing.
local defaults, store, share = require('ui.defaults'), require('core.store'), require('core.share');
local presets = require('setup_fixture');

-- Fresh settings, and a fresh install's load, start without countdowns, 26 px from the game's list.
local fresh = defaults.make();
assert(fresh.party_ui.effects.timers == false and fresh.party_ui.native.gap == 26, 'Fresh settings: no countdowns, 26 px.');
local install = defaults.tidy({});
assert(install.party_ui.effects.timers == false and install.party_ui.native.gap == 26, 'A fresh install: the same.');
local missing = defaults.make();
missing.party_ui.native.gap = nil;
assert(defaults.tidy(missing).party_ui.native.gap == 26, 'A save without the gap takes 26 px.');

-- The player's own choices stay through every tidy, 6 px too.
local chosen = defaults.tidy(defaults.make());
chosen.party_ui.effects.timers, chosen.party_ui.native.gap = true, 6;
for round = 1, 2 do
    chosen = defaults.tidy(store.copy(chosen));
    assert(chosen.party_ui.effects.timers == true and chosen.party_ui.native.gap == 6,
        'Countdowns on and 6 px stay, tidy ' .. round .. '.');
end;

-- Through the app: a save with the party list buffs on loads with the countdowns off, 26 px from the game's list.
local root = require('core.identity').root():gsub('[/' .. string.char(92) .. ']+$', '') .. '/';
local path = root .. 'Tester_1001/settings.json';
local saved = defaults.make();
saved.party_ui.enabled = true;
assert(store.write(path, saved), 'Fixture: the save.');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {},
    party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app;
local function load()
    if app then MOCK.fire('unload'); end;
    app = dofile(ADDON_DIR .. '/vantage.lua');
    MOCK.fire('load'); app.refresh(MOCK.now);
    return app.state.settings;
end;
local s = load();
assert(app.state.path:gsub(string.char(92), '/') == path:gsub(string.char(92), '/'), 'Fixture: the save loads.');
assert(s.party_ui.effects.timers == false and s.party_ui.native.gap == 26,
    'The save loads with countdowns off, 26 px from the game\'s list.');

-- The Countdowns switch on Party list buffs turns them on as one Undo step; Undo and Redo work as for any switch, and
-- the save holds the choice.
local window = require('ui.settings_window');
local function countdowns()
    local settings = app.state.settings;
    settings.window.open, settings.window.tab = true, 'Display';
    require('ui.panel_frame').open('party_ui', 'show');
    MOCK.clicks['Countdowns##frame'] = true;
    window.draw(settings, { rows = {}, context = { valid = true, job = 3 } }, app.callbacks);
    assert(not MOCK.clicks['Countdowns##frame'], 'Fixture: Countdowns is drawn.');
    MOCK.clicks = {};
end;
app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
countdowns();
local steps = app.callbacks.history_status();
assert(app.state.settings.party_ui.effects.timers == true and steps.undo == 1 and steps.undo_label == 'Countdowns',
    'Countdowns on, one Undo step.');
assert(app.callbacks.undo() and app.state.settings.party_ui.effects.timers == false, 'Undo turns them off.');
assert(app.callbacks.redo() and app.state.settings.party_ui.effects.timers == true, 'Redo turns them on.');
assert(app.callbacks.save(), 'The settings save.');
local disk = assert(store.read(path), 'The save reads.');
assert(disk.party_ui.effects.timers == true and disk.party_ui.native.gap == 26, 'The save holds the countdowns and 26 px.');

-- After a reload they stay on.
s = load();
assert(s.party_ui.effects.timers == true and s.party_ui.native.gap == 26, 'Reloaded: on, 26 px.');

-- /vg set: 6 px stays, through a reload too.
local function command(line) local event = { command = line }; MOCK.fire('command', event); assert(event.blocked); end;
command('/vg set party_ui.native.gap 6');
assert(app.state.settings.party_ui.native.gap == 6 and app.state.settings.party_ui.effects.timers == true, '/vg set: 6 px.');
command('/vg set party_ui.effects.timers false');
command('/vg set party_ui.effects.timers true');
assert(app.state.settings.party_ui.effects.timers == true, '/vg set turns them off and on again.');
assert(app.callbacks.save(), 'The settings save again.');
s = load();
assert(s.party_ui.effects.timers == true and s.party_ui.native.gap == 6, 'Reloaded: countdowns on at 6 px, as set.');

-- Apply setup keeps the countdowns, and its tidy turns nothing off. Like the rest of the strips' layout, their spacing
-- starts again at the fresh 26 px.
local applied = store.copy(s);
assert(presets.apply(applied, { skin = 'keep', size = 'minimal', matching = true }), 'Fixture: Apply setup.');
applied = defaults.tidy(applied);
assert(applied.party_ui.effects.timers == true and applied.party_ui.native.gap == 26, 'Apply setup: countdowns kept, 26 px.');

-- An export holding these countdowns and this gap.
local function string_of(kind, timers, gap)
    local made = defaults.tidy(defaults.make());
    made.party_ui.effects.timers, made.party_ui.native.gap = timers, gap;
    return assert(share.export(made, kind, kind == 'element' and 'party_ui' or nil, 'Tester'));
end;
-- Over your own countdowns on at 6 px. Reading a string with them off at 26 px and listing what it changes write
-- nothing, and the list names areas, never a setting. Replace with it turns the countdowns off at 26 px, as one Undo
-- step that puts yours back; loading a profile does the same.
local on_disk = store.read(path);
local own = store.copy(app.state.settings);
assert(own.party_ui.effects.timers == true and own.party_ui.native.gap == 6, 'Fixture: your countdowns on at 6 px.');
local function one_step(name, label, run)
    app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
    assert(run(), name .. ': it comes in.');
    local party, status = app.state.settings.party_ui, app.callbacks.history_status();
    assert(party.effects.timers == false and party.native.gap == 26, name .. ': countdowns off, 26 px.');
    assert(status.undo == 1 and (label == nil or status.undo_label == label), name .. ': one Undo step.');
    assert(app.callbacks.undo() and store.equal(app.state.settings, own), name .. ': Undo puts them back.');
end;
for _, kind in ipairs({ 'element', 'profile' }) do
    app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
    local payload = assert(share.read(string_of(kind, false, 26)));
    local lines = assert(app.callbacks.share_preview(payload, 'replace'));
    assert(store.equal(store.read(path), on_disk) and store.equal(app.state.settings, own) and #app.state.history == 0
        and app.state.transaction == nil, kind .. ': reading it and listing what it changes write nothing.');
    for _, line in ipairs(lines) do
        assert(line:match('^[%a &]+: %d+ settings? change%.$') or line:match('^[%a &]+: %d+ rules? now, %d+ after%.$')
            or line:match('^Shared hide rules: turned o[nf]f?%.$'), kind .. ': a plain line: ' .. line);
    end;
    assert(table.concat(lines, ' '):find('Party list buffs: ', 1, true), kind .. ': the list says the party list buffs change.');
    one_step(kind .. ' string', 'Replace with an export', function() return app.callbacks.share_import(payload, 'replace'); end);
end;
assert(require('core.profiles').new(root):save_new('Plain', defaults.make()), 'Fixture: a profile with countdowns off at 26 px.');
one_step('A profile', nil, function() return app.callbacks.profile_load('Plain'); end);
MOCK.fire('unload');

-- A profile carries its countdowns and gap as they are, 6 px too, whatever the settings it goes into have, and loading
-- writes nothing.
local profiles = require('core.profiles').new(MOCK_INSTALL_PATH .. '/config/addons/vantage/party-buffs-profiles');
assert(profiles:save_new('Current', defaults.tidy(defaults.make())), 'Fixture: a profile with countdowns off at 26 px.');
local profile_file = assert(store.read(profiles.path));
for _, start in ipairs({ { false, 26 }, { true, 6 } }) do
    local receiver = defaults.tidy(defaults.make());
    receiver.party_ui.effects.timers, receiver.party_ui.native.gap = start[1], start[2];
    assert(profiles:load('Current', receiver), 'Fixture: the profile loads.');
    assert(store.equal(store.read(profiles.path), profile_file), 'Loading it writes nothing.');
    receiver = defaults.tidy(receiver);
    assert(receiver.party_ui.effects.timers == false and receiver.party_ui.native.gap == 26,
        'The profile loads with countdowns off, 26 px from the game\'s list.');
end;
local on_at_six = defaults.tidy(defaults.make());
on_at_six.party_ui.effects.timers, on_at_six.party_ui.native.gap = true, 6;
assert(profiles:save_new('On at six', on_at_six), 'Fixture: a profile with countdowns on at 6 px.');
local into = defaults.tidy(defaults.make());
assert(profiles:load('On at six', into) and into.party_ui.effects.timers == true and into.party_ui.native.gap == 6,
    'A profile carries its countdowns and gap as they are.');

-- A shared layout of the whole look loads the same way, and loading writes nothing. Joined for placement it brings the
-- party list's place, the gap with it, and the countdowns stay yours.
for _, case in ipairs({ { true, 6 }, { false, 26 } }) do
    local timers, gap = case[1], case[2];
    local look = defaults.tidy(defaults.make());
    look.party_ui.effects.timers, look.party_ui.native.gap = timers, gap;
    assert(profiles:save_layout(look, 'presentation'), 'Fixture: a shared layout of the whole look.');
    local layout_file = assert(store.read(profiles.layout_path));
    local loaded = defaults.tidy(defaults.make());
    assert(profiles:load_layout(loaded, 'presentation'), 'Fixture: the shared layout loads.');
    assert(store.equal(store.read(profiles.layout_path), layout_file), 'Loading it writes nothing.');
    assert(loaded.party_ui.effects.timers == timers and loaded.party_ui.native.gap == gap,
        'A shared layout: countdowns ' .. tostring(timers) .. ' at ' .. gap .. ' px.');
    local placed = defaults.tidy(defaults.make());
    placed.party_ui.effects.timers, placed.party_ui.native.gap = true, 12;
    assert(profiles:load_layout(placed, 'placement'), 'Fixture: the shared layout of the whole look joins for placement.');
    assert(store.equal(store.read(profiles.layout_path), layout_file), 'Joining it writes nothing.');
    assert(placed.party_ui.native.gap == gap and placed.party_ui.effects.timers == true,
        'Joined for placement: ' .. gap .. ' px, and the countdowns stay on: ' .. placed.party_ui.native.gap .. ', '
        .. tostring(placed.party_ui.effects.timers));
end;

-- An export carries its countdowns and gap as they are, Add and Replace alike. One on at 6 px says what changes;
-- one off at 26 px changes nothing onto fresh settings, and Add onto your own countdowns on at 6 px keeps yours, as Add
-- keeps what you changed.
for _, kind in ipairs({ 'element', 'profile' }) do
    for _, case in ipairs({ { true, 6 }, { false, 26 } }) do
        local timers, gap = case[1], case[2];
        local payload = assert(share.read(string_of(kind, timers, gap)));
        for _, mode in ipairs({ 'add', 'replace' }) do
            local base = defaults.tidy(defaults.make());
            local candidate = assert(share.candidate(base, payload, mode));
            local name = kind .. ' ' .. mode .. ' at ' .. gap .. ' px';
            assert(candidate.party_ui.effects.timers == timers and candidate.party_ui.native.gap == gap,
                name .. ': countdowns ' .. tostring(timers) .. ' at ' .. gap .. ' px.');
            local lines = share.changes(base, candidate);
            if timers then
                assert(#lines > 0 and lines[1] ~= 'Nothing changes.', name .. ': the import says what changes.');
            else
                assert(#lines == 1 and lines[1] == 'Nothing changes.', name .. ': it changes nothing: ' .. table.concat(lines, ' '));
            end;
        end;
        if not timers then
            local yours = defaults.tidy(defaults.make());
            yours.party_ui.effects.timers, yours.party_ui.native.gap = true, 6;
            local added = assert(share.candidate(yours, payload, 'add'));
            assert(added.party_ui.effects.timers == true and added.party_ui.native.gap == 6, kind .. ' add keeps yours.');
        end;
    end;
end;
return 'Party countdowns start off, the strips start 26 px from the game\'s list, and a player\'s choices stay through a save, a reload, a profile, a shared layout and an export';
