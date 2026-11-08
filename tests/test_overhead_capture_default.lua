-- Overhead icons read the camera at the 2nd BeginScene at first. A present picked is kept, through the next load too.
local store = require('core.store');
local defaults = require('ui.defaults');
local fresh = defaults.make().overhead.camera;
assert(fresh.capture == 'scene', 'A fresh install reads the camera at scene.');
local function tidied(change)
    local value = defaults.make();
    change(value.overhead);
    return defaults.tidy(store.copy(value)).overhead;
end
assert(tidied(function(o) o.camera.capture = 'present'; end).camera.capture == 'present', 'A present picked is kept.');
assert(tidied(function(o) o.camera.capture = 'scene'; end).camera.capture == 'scene', 'A save at scene stays there.');

-- Through vantage.lua: a save on disk without the name's size, which loads filled in.
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
local folder = MOCK_INSTALL_PATH .. '/config/addons/vantage/';
local file = defaults.make();
local layout = file.overhead.layout;
layout.name_height, layout.name_cap, layout.target_height, layout.target_cap = nil, nil, nil, nil;
for _, t in pairs(file.overhead.types) do t.name_lift = nil; end
assert(store.write(folder .. 'Tester_1001/settings.json', file), 'Fixture: the save.');
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
for _ = 1, 3 do MOCK.frame(0.11); end
local o = app.state.settings.overhead;
assert(app.state.path == folder .. 'Tester_1001/settings.json', 'Fixture: its settings loaded.');
assert(o.camera.capture == 'scene', 'The save loads at scene: ' .. o.camera.capture);
assert(o.layout.name_cap == 24 and o.layout.target_cap == 16 and o.types.party.name_lift == 0.5 and o.types.mob.name_lift == 0,
    'The name\'s size is filled in.');

-- Present picked now: saved, and a load of that file keeps it.
local event = { command = '/vg set overhead.camera.capture present' };
MOCK.fire('command', event);
local saved = assert(store.read(app.state.path), 'Fixture: the save reads.');
assert(saved.overhead.camera.capture == 'present', 'Present is saved.');
assert(defaults.tidy(saved).overhead.camera.capture == 'present', 'and the next load keeps it.');

-- A whole camera table set now is picked now too, so the present in it is kept, and so is a whole overhead table's.
local function command(text) local e = { command = text }; MOCK.fire('command', e); assert(e.blocked, text); end
command('/vg set overhead.camera.capture scene');
command('/vg set overhead.camera {"capture":"present","scene_index":2,"hold_ms":250,"max_distance":60}');
o = app.state.settings.overhead;
assert(o.camera.capture == 'present', 'A whole camera table keeps its present: ' .. o.camera.capture);
command('/vg set overhead.camera.capture scene');
local whole = store.copy(o);
whole.camera.capture = 'present';
command('/vg set overhead ' .. store.encode(whole));
o = app.state.settings.overhead;
assert(o.camera.capture == 'present', 'So does a whole overhead table: ' .. o.camera.capture);
return true;
