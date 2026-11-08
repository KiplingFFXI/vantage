local profiles, store, defaults = require('core.profiles'), require('core.store'), require('ui.defaults');
local p = profiles.new(MOCK_INSTALL_PATH .. '/config/addons/vantage');
local s = defaults.make();
assert(p:save_new('zulu', s));
assert(p:save_new('Alpha', s));
s.active_profile = 'alpha';
local reads, read = 0, store.read;
store.read = function(path, ...)
    if path == p.path then reads = reads + 1; end;
    return read(path, ...);
end;
local summary = p:summary(s);
assert(reads == 1, 'Names and active source come from one read.');
assert(#summary.names == 2 and summary.names[1] == 'Alpha' and summary.names[2] == 'zulu');
assert(summary.status.exists and summary.status.name == 'Alpha' and not summary.status.modified and not summary.problem);
local names, problem = p:list();
local status, why = p:source(s.active_profile, s);
assert(reads == 3, 'Legacy list and source remain fresh.');
assert(table.concat(names, '|') == table.concat(summary.names, '|') and problem == summary.problem);
assert(status.token == summary.status.token and status.modified == summary.status.modified and why == summary.problem);
s.style.font_size = s.style.font_size + 1;
assert(p:summary(s).status.modified, 'Unsaved presentation changes are detected.');
s.active_profile = 'Missing';
summary = p:summary(s);
assert(not summary.status.exists and not summary.status.modified and summary.status.name == 'Missing' and not summary.problem);

local data = assert(store.read(p.path));
data.Bad = false;
data['Invalid##name'] = {};
data.ALPHA = store.copy(data.Alpha);
assert(store.write(p.path, data));
s.active_profile = 'alpha';
summary = p:summary(s);
assert(#summary.names == 3 and summary.names[1] == 'ALPHA' and summary.names[2] == 'Alpha');
assert(not summary.status.exists and type(summary.problem) == 'string', 'Ambiguous names preserve the source error.');
data.ALPHA = nil;
data.Alpha.style = 'invalid';
assert(store.write(p.path, data));
summary = p:summary(s);
status, why = p:source(s.active_profile, s);
assert(summary.status.exists == status.exists and summary.status.modified == status.modified and summary.problem == why,
    'Malformed profile fields follow the same validation as a fresh source lookup.');

local file = assert(io.open(p.path, 'wb')); file:write('invalid JSON'); file:close();
summary = p:summary(s);
assert(#summary.names == 0 and not summary.status.exists and summary.status.name == 'alpha' and type(summary.problem) == 'string');
assert(not p:save_new('Keep', s));
file = assert(io.open(p.path, 'rb')); assert(file:read('*a') == 'invalid JSON'); file:close();
return true;
