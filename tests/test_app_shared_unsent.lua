-- A change to the shared layout that could not be written to shared_layout.json is retried while the character
-- stays loaded. If the character is switched away from, or Vantage unloads, before a retry gets through, the change
-- must not be lost: the character's own file notes that it is still to be sent, with the layout it started from, and
-- the next login sends it before it reads the shared file. Reading the shared file first would put the older layout
-- back over the change. What another character changed meanwhile is merged in, as with any publish. When the
-- character's own file can't be written either and the character is switched away from, the copy kept to save
-- again has that note.
local store = require('core.store');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {}, party = {}, entities = {} };
require('app_fixture')(snapshot);
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, update = function() end,
    status = function() return { active = false }; end, restore = function() return true; end, suspend = function() end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
local function command(text) local event = { command = text }; MOCK.fire('command', event); end;
local function frames(count) for _ = 1, count do MOCK.frame(.11); end; end;
local function said() local out = {}; for i = 1, #MOCK.printed do out[#out + 1] = MOCK.printed[i]; end; MOCK.printed = {}; return table.concat(out, ' | '); end;
local function login(id, name)
    snapshot.id, snapshot.name = id, name;
    app.refresh(MOCK.now);
    frames(3);
end
MOCK.fire('load'); app.refresh(0);
app.state.dirty = true; assert(app.callbacks.save(), 'Fixture: the settings are on disk.');
local folder = app.state.path:gsub('Tester_1001/settings.json$', '');
local layout_path, own_path = folder .. 'shared_layout.json', app.state.path;
command('/vg set shared_layout true');
frames(30);
local start_x = app.state.settings.panels.self_buffs.x;
assert(assert(store.read(layout_path)).self_buffs.x == start_x and not app.state.publish_pending, 'Fixture: the layout is shared.');
assert(store.read(own_path).shared_unsent == nil, 'With nothing owed, the character\'s file notes nothing.');
said();

-- The shared file can't be written, as while another program holds it.
local real_write, locked = store.write, true;
store.write = function(path, ...)
    if locked and path == layout_path then return false, 'shared_layout.json is in use.'; end
    return real_write(path, ...);
end;
command('/vg set panels.self_buffs.x 333');
assert(app.state.publish_pending == true and said():find('Your settings were saved, but not the shared layout.', 1, true),
    'Fixture: the change is saved for this character and still owed to the shared layout.');
local disk = store.read(own_path);
assert(disk.panels.self_buffs.x == 333, 'Fixture: the character\'s own file has the change.');
assert(type(disk.shared_unsent) == 'table' and disk.shared_unsent.base.self_buffs.x == start_x,
    'The character\'s file notes the change still to be sent, with the layout it started from.');
assert(app.state.settings.shared_unsent == nil, 'The note is in the file only, never in the settings in use.');
assert(store.read(layout_path).self_buffs.x == start_x, 'Fixture: the shared file still has the old layout.');
-- A retry that fails too leaves the note as it is, and writes the character\'s file no more.
local writes = 0;
local counted = store.write;
store.write = function(path, ...) if path == own_path then writes = writes + 1; end return counted(path, ...); end;
frames(120);
assert(app.state.publish_pending == true and writes == 0, 'Failed retries don\'t write the character\'s file again: ' .. writes);
store.write = counted;

-- Switched away from while it is still owed, then back once the shared file can be written. The other character,
-- in the same game, shares its layout too and moves a different panel meanwhile, so the shared file as this game last
-- saw it already holds that move.
login(1002, 'Other');
assert(app.state.path ~= own_path and app.state.settings.shared_layout == false, 'Fixture: another character, not sharing yet.');
locked = false;
command('/vg set shared_layout true');
frames(30);
local their_x = app.state.settings.panels.self_debuffs.x + 70;
command('/vg set panels.self_debuffs.x ' .. their_x);
frames(5);
assert(store.read(layout_path).self_debuffs.x == their_x and store.read(layout_path).self_buffs.x == start_x and not app.state.publish_pending,
    'Fixture: the other character moved a panel and shared it.');
said();
login(1001, 'Tester');
frames(10);
assert(app.state.path == own_path, 'Fixture: back on the first character.');
assert(app.state.settings.panels.self_buffs.x == 333, 'Its change is still there after the switch: ' .. tostring(app.state.settings.panels.self_buffs.x));
local shared = store.read(layout_path);
assert(shared.self_buffs.x == 333, 'And it is in the shared layout now: ' .. tostring(shared.self_buffs.x));
assert(shared.self_debuffs.x == their_x and app.state.settings.panels.self_debuffs.x == their_x,
    'What the other character changed meanwhile is kept, in the shared file and here.');
assert(not app.state.publish_pending and store.read(own_path).shared_unsent == nil, 'Once sent, nothing is owed and the note is gone.');
assert(store.read(own_path).panels.self_buffs.x == 333 and store.read(own_path).panels.self_debuffs.x == their_x, 'The character\'s file has both.');
assert(not said():find('could not', 1, true), 'Nothing is reported as failed.');

-- The same over an unload and a load.
locked = true;
command('/vg set panels.self_buffs.x 444');
assert(app.state.publish_pending == true and store.read(own_path).shared_unsent.base.self_buffs.x == 333, 'Fixture: a second change is owed.');
MOCK.fire('unload');
assert(store.read(layout_path).self_buffs.x == 333, 'Fixture: the unload could not send it either.');
assert(store.read(own_path).shared_unsent ~= nil, 'The note outlasts the unload.');
locked = false;
app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(MOCK.now);
frames(10);
assert(app.state.settings.panels.self_buffs.x == 444, 'After a reload the change is still there: ' .. tostring(app.state.settings.panels.self_buffs.x));
assert(store.read(layout_path).self_buffs.x == 444 and not app.state.publish_pending and store.read(own_path).shared_unsent == nil,
    'And it is sent, with nothing left owed.');
assert(app.state.settings.shared_unsent == nil, 'The note never reaches the settings in use.');

-- The write that takes the note out can fail with the publish already through. The settings themselves were saved,
-- so nothing says they were not, and the note is taken out by a later try. So a later login doesn't send the layout
-- again over an old base.
locked = true;
command('/vg set panels.self_buffs.x 450');
assert(app.state.publish_pending == true and store.read(own_path).shared_unsent ~= nil, 'Fixture: a change is owed, with its note.');
locked = false;
-- The next save writes the settings, publishes, and then fails to write the file again without the note.
local own_writes, unlocked = 0, store.write;
store.write = function(path, ...)
    if path == own_path then
        own_writes = own_writes + 1;
        if own_writes == 2 then return false, 'settings.json is in use.'; end
    end
    return unlocked(path, ...);
end;
said();
command('/vg sort oldest');
local heard = said();
assert(not app.state.publish_pending and store.read(layout_path).self_buffs.x == 450, 'Fixture: the publish went through with the save.');
assert(own_writes == 2 and store.read(own_path).shared_unsent ~= nil, 'Fixture: the write that takes the note out failed.');
assert(heard:find('now sort', 1, true) and not heard:find('could not be saved', 1, true), 'The settings were saved, and the command says so: ' .. heard);
frames(80);
assert(store.read(own_path).shared_unsent == nil, 'The note is taken out by a later try.');
assert(not app.state.dirty and not said():find('could not', 1, true), 'With nothing left to save and nothing reported as failed.');
store.write = unlocked;

-- A note in a file whose character no longer shares its layout is dropped by the next save and sends nothing.
locked = true;
command('/vg set panels.self_buffs.x 555');
assert(store.read(own_path).shared_unsent ~= nil, 'Fixture: a third change is owed.');
command('/vg set shared_layout false');
frames(5);
assert(store.read(own_path).shared_unsent == nil and not app.state.publish_pending, 'With sharing off the note is dropped.');
locked = false;
frames(60);
assert(store.read(layout_path).self_buffs.x == 450, 'And nothing is sent.');

-- A damaged note doesn't stop a load: its layout is sent as a first publish would be.
command('/vg set shared_layout true');
frames(30);
MOCK.fire('unload');
local file = store.read(own_path);
file.shared_unsent = { base = 'not a layout' };
file.panels.self_buffs.x = 666;
assert(store.write(own_path, file), 'Fixture: a file with a damaged note.');
app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(MOCK.now);
frames(10);
assert(app.state.settings.panels.self_buffs.x == 666 and store.read(layout_path).self_buffs.x == 666, 'A damaged note still sends the layout.');
assert(store.read(own_path).shared_unsent == nil and app.state.problem == nil, 'And leaves nothing behind: ' .. tostring(app.state.problem));

-- The character's own file can't be written when a shared change saves (read-only, or held by another program), so the
-- change isn't sent yet, and the character is switched away from before a retry gets through.
local own_locked = true;
store.write = function(path, ...)
    if own_locked and path == own_path then return false, 'settings.json is in use.'; end
    return unlocked(path, ...);
end;
command('/vg set panels.self_buffs.x 777');
local kept = app.state.unsaved[own_path];
assert(kept and kept.panels.self_buffs.x == 777 and store.read(layout_path).self_buffs.x == 666,
    'Fixture: the change is kept to save again, and the shared file still has the old layout.');
assert(type(kept.shared_unsent) == 'table' and type(kept.shared_unsent.base) == 'table' and kept.shared_unsent.base.self_buffs.x == 666,
    'The copy kept notes the shared change as still to be sent, with the layout it started from.');
login(1002, 'Other');
local their_dx = app.state.settings.panels.self_debuffs.x + 40;
command('/vg set panels.self_debuffs.x ' .. their_dx);
frames(5);
assert(store.read(layout_path).self_debuffs.x == their_dx and store.read(layout_path).self_buffs.x == 666,
    'Fixture: the other character moved a panel and shared it.');
own_locked = false;
frames(60);
disk = store.read(own_path);
assert(app.state.unsaved[own_path] == nil and disk.panels.self_buffs.x == 777, 'Fixture: the kept copy reached the character\'s file.');
assert(type(disk.shared_unsent) == 'table', 'The character\'s file has the note too.');
login(1001, 'Tester');
frames(10);
shared = store.read(layout_path);
assert(app.state.settings.panels.self_buffs.x == 777 and shared.self_buffs.x == 777,
    'The next login sends the change, not the older shared layout over it: ' .. tostring(app.state.settings.panels.self_buffs.x) .. ', ' .. tostring(shared.self_buffs.x));
assert(shared.self_debuffs.x == their_dx and app.state.settings.panels.self_debuffs.x == their_dx,
    'What the other character changed meanwhile is kept, in the shared file and here.');
assert(not app.state.publish_pending and store.read(own_path).shared_unsent == nil, 'Once sent, nothing is owed and the note is gone.');

-- The same when the file still can't be written on the way back, so the copy kept is what loads.
own_locked = true;
command('/vg set panels.self_buffs.x 888');
assert(type(app.state.unsaved[own_path].shared_unsent) == 'table', 'Fixture: the copy kept notes the change.');
login(1002, 'Other');
login(1001, 'Tester');
frames(10);
assert(app.state.settings.panels.self_buffs.x == 888 and store.read(layout_path).self_buffs.x == 777,
    'The kept copy loads with its change, which waits for the character\'s own file to save.');
own_locked = false;
frames(60);
assert(store.read(layout_path).self_buffs.x == 888 and app.state.settings.panels.self_buffs.x == 888 and not app.state.publish_pending,
    'It is sent once the character\'s own file is saved.');
assert(store.read(layout_path).self_debuffs.x == their_dx, 'And the other character\'s move stays.');
store.write = real_write;
return 'An unsent shared layout change outlasts a switch and a reload';
