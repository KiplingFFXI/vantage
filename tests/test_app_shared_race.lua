-- Another character's publish can land between this character's read of shared_layout.json and its write. The
-- write then reports that the file changed since it was read, and the publish reads it again, merges and writes
-- once more: both moves are shared at once, with no "review it again" message and no 5 s wait.
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

-- store.write says which failures are a file changed since it was read.
local folder = app.state.path:gsub('Tester_1001/settings.json$', '');
local probe = folder .. 'race_probe.json';
assert(store.write(probe, { a = 1 }), 'Fixture: a file.');
local ok, why, code = store.write(probe, { a = 2 }, { a = 0 });
assert(not ok and code == 'changed' and why:find('changed', 1, true), 'A file that changed since it was read says so by code.');
ok, why, code = store.write(probe, { 'no' }, nil);
assert(ok and code == nil, 'Fixture: a plain write.');

command('/vg set shared_layout true');
for _ = 1, 30 do MOCK.frame(.11); end;
said();
local layout_path = folder .. 'shared_layout.json';
local other = require('core.profiles').new(folder);
local theirs = store.copy(app.state.settings);
assert(other:load_layout(theirs), 'Fixture: the other character has the shared layout.');
local x = theirs.panels.self_debuffs.x;
-- The other character's write lands right after this character reads the shared file to publish.
local real_read, armed = store.read, true;
store.read = function(path, ...)
    local a, b = real_read(path, ...);
    if armed and path == layout_path then
        armed = false;
        theirs.panels.self_debuffs.x = x + 70;
        assert(other:publish_layout(theirs, require('core.profiles').capture_layout(theirs)), 'Fixture: the other character published.');
    end;
    return a, b;
end;
command('/vg set panels.self_buffs.x 333');
store.read = real_read;
assert(not armed, 'Fixture: the other write landed mid-publish.');
local message = said();
-- /vg set says the one line it says for any setting it saved, and nothing more.
assert(message == '[Vantage] panels.self_buffs.x is now 333.' and app.state.problem == nil, 'Nothing to review is said: ' .. message);
assert(not app.state.dirty and not app.state.publish_pending, 'Nothing is left to save or publish.');
local file = assert(store.read(layout_path), 'Fixture: the shared layout reads.');
assert(file.self_buffs.x == 333 and file.self_debuffs.x == x + 70, 'Both moves are in the shared file at once.');
assert(app.state.settings.panels.self_debuffs.x == x + 70 and store.read(app.state.path).panels.self_debuffs.x == x + 70,
    'This character took the other move, in memory and in its file.');
return true;
