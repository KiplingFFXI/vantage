-- Grid mode (settings.edit_mode.grid_mode and grid_displays, the displays ticked for it) through vantage.lua. Fresh
-- settings have it off with nothing ticked, and so does a save without the keys, which loads without a write; the first
-- save writes both. Tidying keeps only the ids of the displays a move can tick, each once, in their order. /vg get and
-- set reach both, and one tick set alone is taken wherever tidying puts it, the reply giving the whole list. Share
-- strings, profiles and shared layouts carry them, with Add and with Replace. A string with a key Vantage doesn't know
-- is still refused, and a tick that shares the character's name stays a tick. The character here is called Pet.
local store, defaults, anchors = require('core.store'), require('ui.defaults'), require('core.anchors');
local elements, snap, share, profiles = require('ui.elements'), require('ui.snap'), require('core.share'), require('core.profiles');
local function ticks(e) return table.concat(e.grid_displays, ' '); end;

-- Fresh settings, and what tidying keeps.
local fresh = defaults.make();
assert(fresh.edit_mode.grid_mode == false and type(fresh.edit_mode.grid_displays) == 'table' and next(fresh.edit_mode.grid_displays) == nil,
    'Fresh settings have Grid mode off, with no display ticked.');
local e = anchors.tidy_edit({ grid_mode = true, grid_displays = { 'pet', 'nope', 5, 'self_buffs', 'pet', 'Pet', '' } }, elements.movable);
assert(e.grid_mode == true and ticks(e) == 'self_buffs pet', 'Tidying keeps each real id once, in the displays\' order: ' .. ticks(e));
e = anchors.tidy_edit({ grid_mode = 'yes', grid_displays = { pet = true, self_buffs = 1 } }, elements.movable);
assert(e.grid_mode == false and next(e.grid_displays) == nil, 'A switch that is not true or false is off, and a map ticks nothing.');
e = anchors.tidy_edit({ grid_displays = 'pet' }, elements.movable);
assert(next(e.grid_displays) == nil, 'Nor does a word.');
local odd = defaults.make();
odd.edit_mode.grid_displays = { 'strip_3', 'overhead', 'rolls' };
assert(ticks(defaults.tidy(odd).edit_mode) == 'rolls strip_3', 'A save is tidied the same way: overhead icons are not moved, so not ticked.');

-- A save whose edit mode settings hold neither key.
local snapshot = { valid = true, id = 1001, name = 'Pet', zone = 102, job = 3, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
local plain = defaults.make();
plain.edit_mode.grid_mode, plain.edit_mode.grid_displays = nil, nil;
local folder = MOCK_INSTALL_PATH .. '/config/addons/vantage/Pet_1001';
MOCK_MKDIR(folder);
local text = store.encode(plain);
local file = assert(io.open(folder .. '/settings.json', 'wb'), 'Fixture: the settings file opens.');
file:write(text); file:close();
local function raw()
    local saved = assert(io.open(folder .. '/settings.json', 'rb'));
    local value = saved:read('*a'); saved:close();
    return value;
end;
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
for _ = 1, 10 do MOCK.frame(0.11); end;
assert(app.state.path == folder .. '/settings.json' and not app.state.unread, 'Fixture: the save without the keys loads.');
e = app.state.settings.edit_mode;
assert(e.grid_mode == false and next(e.grid_displays) == nil, 'It loads with Grid mode off and nothing ticked.');
assert(raw() == text, 'Loading it writes nothing.');

-- /vg get and set.
local function command(line)
    local event = { command = line };
    MOCK.fire('command', event);
    assert(event.blocked, line);
    return MOCK.printed[#MOCK.printed] or '';
end;
local said = command('/vg get edit_mode.grid_mode');
assert(said:find('edit_mode.grid_mode = false', 1, true), '/vg get reads Grid mode: ' .. said);
local steps = #app.state.history;
said = command('/vg set edit_mode.grid_mode true');
assert(app.state.settings.edit_mode.grid_mode == true and said:find('edit_mode.grid_mode is now true.', 1, true)
    and #app.state.history == steps + 1, '/vg set turns it on, as one Undo step: ' .. said);
local disk = assert(store.read(app.state.path));
assert(disk.edit_mode.grid_mode == true and type(disk.edit_mode.grid_displays) == 'table' and next(disk.edit_mode.grid_displays) == nil,
    'The first save writes both.');
said = command('/vg set edit_mode.grid_mode maybe');
assert(app.state.settings.edit_mode.grid_mode == true and #app.state.history == steps + 1, 'A word that is not on or off changes nothing: ' .. said);
said = command('/vg set edit_mode.grid_displays ["pet","nope","self_buffs","pet",7]');
assert(ticks(app.state.settings.edit_mode) == 'self_buffs pet' and said:find('edit_mode.grid_displays is now ["self_buffs","pet"].', 1, true),
    '/vg set takes a list of ids, keeps each real one once, in the displays\' order, and says what it kept: ' .. said);
said = command('/vg get edit_mode.grid_displays');
assert(said:find('edit_mode.grid_displays = ["self_buffs","pet"]', 1, true), '/vg get reads the ticks: ' .. said);
said = command('/vg set edit_mode.grid_displays.1 nope');
assert(ticks(app.state.settings.edit_mode) == 'self_buffs pet', 'One entry set to a display that does not exist changes nothing: ' .. said);
-- One entry set to a real display is taken wherever tidying puts it, as tidying keeps each tick once, in the displays'
-- order, and the reply gives the whole list, as one Undo step.
for _, case in ipairs({
    { '["self_buffs","pet"]', '.1 rolls', 'rolls pet', '["rolls","pet"]' },
    -- Alerts come before Phantom Roll, so the new tick goes second.
    { '["self_buffs","notices"]', '.1 rolls', 'notices rolls', '["notices","rolls"]' },
    -- Phantom Roll was ticked already, so the entry it replaces is unticked, and the list says so.
    { '["notices","rolls"]', '.1 rolls', 'rolls', '["rolls"]' },
    { '["notices","rolls"]', '.2 notices', 'notices', '["notices"]' },
}) do
    command('/vg set edit_mode.grid_displays ' .. case[1]);
    app.state.history, app.state.redo = {}, {};
    said = command('/vg set edit_mode.grid_displays' .. case[2]);
    assert(ticks(app.state.settings.edit_mode) == case[3] and said:find('edit_mode.grid_displays is now ' .. case[4] .. '.', 1, true)
        and #app.state.history == 1, case[1] .. ' with' .. case[2] .. ' gives ' .. case[4] .. ', as one Undo step: ' .. said);
end;
command('/vg set edit_mode.grid_displays ["self_buffs","pet"]');
app.state.history, app.state.redo = {}, {};
said = command('/vg set edit_mode.grid_displays.2 nope');
assert(ticks(app.state.settings.edit_mode) == 'self_buffs pet' and #app.state.history == 0 and not said:find('is now', 1, true),
    'A display that does not exist is still refused: ' .. said);
said = command('/vg set edit_mode.grid_displays []');
assert(next(app.state.settings.edit_mode.grid_displays) == nil and said:find('edit_mode.grid_displays is now [].', 1, true),
    'An empty list unticks every display: ' .. said);
assert(next(assert(store.read(app.state.path)).edit_mode.grid_displays) == nil, 'and saves.');

-- Exports. A layout and a profile string carry Grid mode and the ticks.
local mine = defaults.tidy(defaults.make());
mine.edit_mode.grid_mode = true;
snap.tick(mine, 'pet', true); snap.tick(mine, 'rolls', true);
assert(share.VERSION == 1, 'Exports stay at version 1.');
-- Settings of your own with Grid mode on and Self buffs ticked, and fresh ones.
local function yours(on)
    local value = defaults.tidy(defaults.make());
    if on then value.edit_mode.grid_mode = true; snap.tick(value, 'self_buffs', true); end;
    return value;
end;
for _, kind in ipairs({ 'layout', 'profile' }) do
    local exported = assert(share.export(mine, kind, nil, 'Pet'));
    assert(exported:sub(1, 5) == 'VG:1:', 'A ' .. kind .. ' string is version 1.');
    local payload = assert(share.read(exported));
    assert(payload.data.edit_mode.grid_mode == true and ticks(payload.data.edit_mode) == 'rolls pet',
        'A ' .. kind .. ' string carries both, and the pet tick though the character is called Pet: ' .. ticks(payload.data.edit_mode));
    for _, mode in ipairs({ 'add', 'replace' }) do
        local into = assert(share.candidate(yours(false), payload, mode));
        assert(into.edit_mode.grid_mode == true and ticks(into.edit_mode) == 'rolls pet', kind .. ' ' .. mode .. ' brings both into fresh settings.');
        into = assert(share.candidate(yours(true), payload, mode));
        if mode == 'replace' then
            assert(into.edit_mode.grid_mode == true and ticks(into.edit_mode) == 'rolls pet', kind .. ' replace brings both over your own.');
        else
            assert(into.edit_mode.grid_mode == true and ticks(into.edit_mode) == 'self_buffs', kind .. ' add keeps your own ticks, as it keeps what you changed.');
        end;
    end;
end;
-- A key Vantage doesn't know is still refused.
local unknown = assert(share.read(assert(share.export(mine, 'layout', nil, 'Pet'))));
unknown.data.edit_mode.grid_foo = true;
local body = store.encode(unknown);
local refused, why, what = share.read('VG:1:' .. share.crc32(body) .. ':' .. body);
assert(refused == nil and why == share.NEWER and tostring(what):find('grid_foo', 1, true), 'A string with an unknown key is refused: ' .. tostring(what));

-- Profiles and shared layouts. A saved profile brings both.
local s = app.state.settings;
s.edit_mode.grid_mode = false;
assert(app.callbacks.profile_save('Saved', false), 'Fixture: the profile saves.');
local path = require('core.identity').root() .. 'profiles.json';
local saved = assert(store.read(path));
saved.Saved.edit_mode.grid_mode, saved.Saved.edit_mode.grid_displays = true, { 'pulse', 'target' };
local written = assert(io.open(path, 'wb')); written:write(store.encode(saved)); written:close();
s.edit_mode.grid_mode = true; snap.tick(s, 'pet', true);
assert(app.callbacks.profile_load('Saved'), 'Fixture: the profile loads.');
s = app.state.settings;
assert(s.edit_mode.grid_mode == true and ticks(s.edit_mode) == 'target pulse', 'A profile brings both.');
-- A shared presentation brings both, and its grid.
local presentation = profiles.capture_layout(mine, 'presentation').presentation;
presentation.edit_mode.grid = 24;
local other = yours(true);
assert(profiles.apply_layout(other, { scope = 'presentation', presentation = presentation }, 'presentation'));
assert(other.edit_mode.grid == 24 and other.edit_mode.grid_mode == true and ticks(other.edit_mode) == 'rolls pet',
    'A shared presentation brings both, and its grid.');
MOCK.fire('unload');
return 'Grid mode starts off, loads off from a save without it, and travels in strings, profiles and shared layouts';
