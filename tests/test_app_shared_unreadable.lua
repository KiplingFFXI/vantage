-- With sharing on and shared_layout.json unreadable, a change saves this character's own file once and is
-- published on its own retry, which backs off while the file stays unreadable. The message names the shared
-- file, commands don't say the save failed, and the shared poll waits for the publish, so a repaired file
-- can't replace the change still to be sent: the retry merges it.
local store = require('core.store');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
require('ui.party_hud').draw = function() return 0, {}; end;
require('ui.native_party_hud').draw = function() return 0, {}; end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, update = function() end,
    status = function() return { active = false }; end, restore = function() return true; end, suspend = function() end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
local function command(text) local event = { command = text }; MOCK.fire('command', event); end;
local function said() local out = {}; for i = 1, #MOCK.printed do out[#out + 1] = MOCK.printed[i]; end; MOCK.printed = {}; return table.concat(out, ' | '); end;
MOCK.fire('load'); app.refresh(0);
app.state.dirty = true; assert(app.callbacks.save(), 'Fixture: the settings are on disk.');
command('/vg set shared_layout true');
for _ = 1, 30 do MOCK.frame(.11); end;
local layout_path = app.state.path:gsub('Tester_1001/settings.json$', '') .. 'shared_layout.json';
local good = assert(store.read(layout_path), 'Fixture: the shared layout reads.');
local function damage() local f = assert(io.open(layout_path, 'wb'), 'Fixture: the file opens.'); f:write('{"self_buffs":{"x":'); f:close(); end;
damage();
said();
local real_write, writes, publishes = store.write, 0, 0;
store.write = function(path, ...)
    if path == app.state.path then writes = writes + 1; end;
    if path == layout_path then publishes = publishes + 1; end;
    return real_write(path, ...);
end;
local real_read, reads = store.read, 0;
store.read = function(path, ...)
    if path == layout_path then reads = reads + 1; end;
    return real_read(path, ...);
end;
command('/vg set panels.self_buffs.x 333');
local message = said();
assert(writes == 1 and not app.state.dirty, 'The own file is saved once and nothing is left to save.');
assert(message:find('shared layout', 1, true) and message:find('shared_layout.json', 1, true) and message:find('saved', 1, true),
    'The message names the shared file: ' .. message);
local own = store.read(app.state.path) or {};
assert(own.panels and own.panels.self_buffs.x == 333, 'The own file has the change.');
reads = 0;
for _ = 1, 600 do MOCK.frame(.1); end;
assert(writes == 1, 'Over 60 s the own file is not written again (' .. writes .. ' writes).');
assert(reads >= 3 and reads <= 5, 'The publish is retried, backing off: ' .. reads .. ' reads of the shared file in 60 s.');
assert(said() == '', 'The same problem is said once.');
-- /vg sort saves the own file, so it doesn't say the save failed.
command('/vg sort oldest');
assert(not said():find('could not be saved', 1, true), 'A command whose own save worked does not say it failed.');
-- The file is repaired by hand, with another character's move in it; this character's change is merged in,
-- not replaced. (Vantage never writes over a file it can't read.)
local theirs = store.copy(good);
theirs.self_debuffs.x = 997;
local repaired = assert(io.open(layout_path, 'wb'), 'Fixture: the file opens.');
repaired:write(store.encode(theirs)); repaired:close();
for _ = 1, 700 do MOCK.frame(.1); if not app.state.publish_pending then break; end; end;
assert(not app.state.publish_pending, 'The retry publishes once the file is fixed.');
local file = assert(real_read(layout_path), 'Fixture: the shared layout reads.');
assert(file.self_buffs.x == 333 and file.self_debuffs.x == 997, 'The retry merged both moves: ' .. file.self_buffs.x .. ', ' .. file.self_debuffs.x);
assert(app.state.settings.panels.self_buffs.x == 333 and app.state.settings.panels.self_debuffs.x == 997, 'The settings have both moves.');
assert(app.state.problem == nil, 'The shared problem is cleared once it publishes.');
store.write, store.read = real_write, real_read;
return true;
