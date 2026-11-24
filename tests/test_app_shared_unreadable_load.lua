-- A character that loads, or rejoins sharing by Undo, while shared_layout.json can't be read (saved by hand with a JSON
-- typo, say) runs on its own layout meanwhile, and that layout is the base its shared changes are sent over. So a save
-- that changes nothing shared publishes nothing, a shared change made meanwhile is merged into the file once it reads,
-- and the next poll loads the fixed file. Another character's move in the file stays, there and here. Each way in has
-- another character's move to Self debuffs in the file:
-- 1. Logs in while the file is broken, then closes the settings window, which saves.
-- 2. Logs in while it is broken, moves Self buffs and unloads with that still owed. The file is fixed before the next load.
-- 3. Undo turns sharing back on while the file is broken.
-- 4. Switches from another character that shares the layout while the file is broken, and the file is then put back as
--    that character last saw it.
local store = require('core.store');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {}, party = {}, entities = {} };
require('app_fixture')(snapshot);
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, update = function() end,
    status = function() return { active = false }; end, restore = function() return true; end, suspend = function() end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
local function command(text) local event = { command = text }; MOCK.fire('command', event); end;
local function frames(count) for _ = 1, count do MOCK.frame(.11); end; end;
-- Frames until nothing is left to publish, and at least 60 of them (6.6 s), so the shared poll has run as well.
local function settle()
    for count = 1, 700 do
        MOCK.frame(.11);
        if count >= 60 and not app.state.publish_pending then return; end;
    end;
end;
local function login(id, name) snapshot.id, snapshot.name = id, name; app.refresh(MOCK.now); frames(3); end;
-- Vantage unloads and loads again, as /addon reload or the next game session does. between runs while it is unloaded.
local function reload(between)
    MOCK.fire('unload');
    if between then between(); end;
    app = dofile(ADDON_DIR .. '/vantage.lua');
    MOCK.fire('load'); app.refresh(MOCK.now);
    frames(10);
end;
MOCK.fire('load'); app.refresh(0);
app.state.dirty = true; assert(app.callbacks.save(), 'Fixture: the settings are on disk.');
local folder = app.state.path:gsub('Tester_1001/settings.json$', '');
local layout_path, own_path = folder .. 'shared_layout.json', app.state.path;
command('/vg set shared_layout true');
frames(30);
-- The shared file as a hand edit leaves it: a JSON typo, or that fixed.
local function damage() local f = assert(io.open(layout_path, 'wb'), 'Fixture: the file opens.'); f:write('{"self_buffs":{"x":'); f:close(); end;
local function put(layout) local f = assert(io.open(layout_path, 'wb'), 'Fixture: the file opens.'); f:write(store.encode(layout)); f:close(); end;
local function unreadable()
    return store.read(layout_path) == nil and tostring(app.state.problem):find('shared_layout.json', 1, true) ~= nil;
end;
-- The shared file, which this character shares and runs on.
local function synced(when)
    local file = assert(store.read(layout_path), 'Fixture: the shared file reads ' .. when .. '.');
    local panels = app.state.settings.panels;
    assert(app.state.settings.shared_layout and not app.state.publish_pending and file.self_buffs.x == panels.self_buffs.x
        and file.self_debuffs.x == panels.self_debuffs.x, 'Fixture: this character shares the layout in the file ' .. when .. '.');
    return file;
end;
-- Once the file reads again, the other character's move is in it and here, and so is this character's own move, if it made one.
local function check(way, theirs_x, own_x)
    assert(not app.state.publish_pending, 'Fixture: nothing is left to publish (' .. way .. ').');
    local file = assert(store.read(layout_path), 'Fixture: the fixed file reads (' .. way .. ').');
    local panels = app.state.settings.panels;
    assert(file.self_debuffs.x == theirs_x and panels.self_debuffs.x == theirs_x,
        ('%s: the other character moved Self debuffs to %s, and that stays in the file (%s) and is taken here (%s).')
            :format(way, tostring(theirs_x), tostring(file.self_debuffs.x), tostring(panels.self_debuffs.x)));
    if own_x then
        assert(file.self_buffs.x == own_x and panels.self_buffs.x == own_x,
            ('%s: this character moved Self buffs to %s, and that is in the file (%s) and here (%s).')
                :format(way, tostring(own_x), tostring(file.self_buffs.x), tostring(panels.self_buffs.x)));
    end;
end;

-- 1. Logs in while the file is broken, then closes the settings window.
local start = synced('at the start');
local theirs = store.copy(start);
theirs.self_debuffs.x = 997;
assert(start.self_debuffs.x ~= 997, 'Fixture: 997 is a move.');
reload(function()
    assert(store.write(layout_path, theirs), 'Fixture: another character moved Self debuffs.');
    damage();
end);
assert(app.state.path == own_path and app.state.settings.shared_layout and unreadable(),
    'Fixture: the character loads sharing, and the shared file can\'t be read: ' .. tostring(app.state.problem));
assert(app.state.settings.panels.self_debuffs.x == start.self_debuffs.x, 'Fixture: it runs on its own layout meanwhile.');
assert(app.callbacks.editor_changed(true) and not app.state.dirty and not app.state.navigation_dirty,
    'Fixture: closing the settings window saved this character\'s file.');
assert(not app.state.publish_pending, 'Closing the settings window changed nothing shared, so there is nothing to publish.');
frames(20);
assert(store.read(layout_path) == nil, 'Fixture: the shared file is still broken.');
put(theirs);
settle();
check('Logged in while it was broken, then closed the settings window', 997);

-- 2. Logs in while the file is broken and moves Self buffs, unloads with that owed, and loads after the file is fixed.
start = synced('before the second way');
theirs = store.copy(start);
theirs.self_debuffs.x = 888;
assert(start.self_debuffs.x ~= 888 and start.self_buffs.x ~= 333, 'Fixture: 888 and 333 are moves.');
reload(function()
    assert(store.write(layout_path, theirs), 'Fixture: another character moved Self debuffs.');
    damage();
end);
assert(app.state.path == own_path and unreadable(), 'Fixture: the shared file can\'t be read at the load: ' .. tostring(app.state.problem));
command('/vg set panels.self_buffs.x 333');
local own = store.read(own_path) or {};
assert(own.panels and own.panels.self_buffs.x == 333 and type(own.shared_unsent) == 'table',
    'Fixture: the move is saved for this character, with a note that the shared layout still owes it.');
assert(type(own.shared_unsent.base) == 'table' and own.shared_unsent.base.self_buffs.x == start.self_buffs.x,
    'The note has the layout this character loaded as the base its move is sent over.');
reload(function()
    assert(type((store.read(own_path) or {}).shared_unsent) == 'table', 'Fixture: the note outlasts the unload.');
    put(theirs);
end);
settle();
check('Moved Self buffs while it was broken, then unloaded and loaded once it was fixed', 888, 333);

-- 3. Undo turns sharing back on while the file is broken.
start = synced('before the third way');
command('/vg set shared_layout false');
frames(5);
assert(app.state.settings.shared_layout == false, 'Fixture: this character stopped sharing.');
theirs = store.copy(start);
theirs.self_debuffs.x = 777;
assert(start.self_debuffs.x ~= 777, 'Fixture: 777 is a move.');
assert(store.write(layout_path, theirs), 'Fixture: another character moved Self debuffs.');
damage();
command('/vg undo');
frames(25);
assert(app.state.settings.shared_layout == true and unreadable(),
    'Fixture: Undo turned sharing back on, and the shared file can\'t be read: ' .. tostring(app.state.problem));
assert(not app.state.publish_pending, 'The Undo changed nothing shared, so there is nothing to publish.');
put(theirs);
settle();
check('Undo turned sharing back on while it was broken', 777);

-- 4. Switches from another character that shares the layout while the file is broken, and the file is put back as
-- that character last saw it, the typo undone.
synced('before the fourth way');
login(1002, 'Other');
assert(app.state.path ~= own_path and app.state.settings.shared_layout == false, 'Fixture: another character, not sharing yet.');
command('/vg set shared_layout true');
frames(30);
command('/vg set panels.self_debuffs.x 555');
frames(30);
theirs = synced('after the other character moved Self debuffs');
assert(theirs.self_debuffs.x == 555, 'Fixture: the other character moved Self debuffs and shared it.');
damage();
login(1001, 'Tester');
frames(10);
assert(app.state.path == own_path and unreadable(),
    'Fixture: back on the first character, which can\'t read the shared file: ' .. tostring(app.state.problem));
assert(app.state.settings.panels.self_debuffs.x ~= 555, 'Fixture: it runs on its own layout meanwhile.');
put(theirs);
frames(30);
assert(app.callbacks.editor_changed(true), 'Fixture: closing the settings window saved this character\'s file.');
settle();
check('Switched from a character that last saw the same file, while it was broken', 555);
return 'A character that ran while shared_layout.json could not be read keeps other characters\' moves once it is fixed';
