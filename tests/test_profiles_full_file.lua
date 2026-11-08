-- Saved profiles (core/profiles.lua): when profiles.json has no room left for a save, a rename or a recovery, the
-- message says the file is full and that deleting a profile makes room, and the file stays as it was.
local profiles, store, defaults = require('core.profiles'), require('core.store'), require('ui.defaults');
local folder = MOCK_INSTALL_PATH .. '/config/addons/vantage/full';
local saved = profiles.new(folder);
local FULL = 'The saved profiles file is full. Delete a profile to make room.';
local LIMIT = 2097152;
local function content()
    local file = assert(io.open(saved.path, 'rb'));
    local text = file:read('*a'); file:close(); return text;
end
-- Seeds profiles.json with the profiles in data, and one more whose note is long enough that the file is size bytes.
local function seed(data, size)
    data.Big = { note = '' };
    data.Big.note = ('x'):rep(size - #store.encode(data));
    assert(#store.encode(data) == size, 'Fixture: the file is ' .. size .. ' bytes.');
    assert(store.write(saved.path, data));
end

local settings = defaults.tidy(defaults.make());
seed({ Small = { note = 'x' } }, LIMIT - 1000);
local before = content();
local ok, why = saved:save_new('Raid', settings);
assert(not ok and why == FULL, 'A save that doesn\'t fit says the file is full: ' .. tostring(why));
assert(content() == before, 'and leaves the file as it was.');
ok, why = saved:overwrite('Small', settings, saved:source('Small', settings).token);
assert(not ok and why == FULL and content() == before, 'So does an overwrite that makes a profile bigger: ' .. tostring(why));

-- A rename to a longer name, with the file a byte short of full.
seed({ A = { note = 'kept' } }, LIMIT - 1);
before = content();
ok, why = saved:rename('A', 'Alliance', settings);
assert(not ok and why == FULL and content() == before, 'A rename that doesn\'t fit says so too: ' .. tostring(why));
ok, why = saved:rename('A', 'B', settings);
assert(ok and not why and store.read(saved.path).B.note == 'kept', 'One that fits is done.');

-- Putting back a deleted profile when another save filled the file meanwhile.
seed({}, LIMIT - 60000);
assert(saved:save_new('Raid', settings), 'Fixture: a profile is saved.');
assert(saved:delete('Raid'), 'Fixture: and deleted.');
local data = store.read(saved.path);
data.Big.note = data.Big.note .. ('x'):rep(LIMIT - #store.encode(data) - 10);
assert(store.write(saved.path, data), 'Fixture: another save fills the file.');
before = content();
ok, why = saved:recover();
assert(not ok and why == FULL and content() == before, 'Recovery that doesn\'t fit says the file is full: ' .. tostring(why));

-- Room made, a save fits again.
data = store.read(saved.path);
data.Big = nil;
assert(store.write(saved.path, data));
assert(saved:save_new('Raid', settings), 'With a profile deleted, the save fits.');
