local store, profiles, defaults = require('core.store'), require('core.profiles'), require('ui.defaults');
local path = MOCK_INSTALL_PATH .. '/config/addons/vantage/review.json';
local original_open = io.open;
local function raw_write(target, value)
    local file = assert(original_open(target, 'wb'));
    assert(file:write(store.encode(value)));
    assert(file:close());
end
assert(store.equal({ [33] = { on = true } }, { ['33'] = { on = true } }));
assert(not store.equal({ a = 1 }, { a = 1, b = 2 }));
assert(not store.equal({ [33] = true, ['33'] = false }, { ['33'] = false }));
assert(store.write(path, { version = 1 }));
local original = store.read(path);
raw_write(path, { version = 2 });
assert(not store.write(path, { version = 3 }, original));
assert(store.read(path).version == 2, 'An edit between reading and saving remains intact.');
local intercepted;
io.open = function(target, mode)
    local file, message, code = original_open(target, mode);
    if file and mode == 'wb' and target:sub(-4) == '.tmp' and not intercepted then
        intercepted = target;
        return {
            write = function(_, text) return file:write(text); end,
            close = function() local result = file:close(); raw_write(path, { version = 4 }); return result; end,
        };
    end
    return file, message, code;
end
assert(not store.write(path, { version = 5 }, store.read(path)));
io.open = original_open;
assert(store.read(path).version == 4, 'An edit made during the temporary-file write is preserved.');
assert(not ashita.fs.exists(intercepted), 'A rejected temporary file is cleaned up.');

local p = profiles.new(MOCK_INSTALL_PATH .. '/config/addons/vantage/profile-review');
local s = defaults.make();
assert(p:save_new('Keep', s));
s.active_profile, s.job_profiles['1'] = 'Keep', 'Keep';
local original_write = store.write;
local pending, revision = false, 0;
store.write = function(target, value, expected)
    if target == p.path and pending then
        pending = false;
        local data = store.read(target);
        revision = revision + 1;
        data.Peer = { revision = revision };
        raw_write(target, data);
    end
    return original_write(target, value, expected);
end
local function interfere(fn)
    pending = true;
    assert(not fn(), 'Concurrent profile changes must refuse the stale mutation.');
    assert(p:source('Keep').exists and store.read(p.path).Peer.revision == revision);
    assert(s.active_profile == 'Keep' and s.job_profiles['1'] == 'Keep');
end
interfere(function() return p:save_new('New', s); end);
assert(not p:source('New').exists);
interfere(function() return p:overwrite('Keep', s, p:source('Keep').token); end);
interfere(function() return p:rename('Keep', 'Renamed', s, p:source('Keep').token); end);
interfere(function() return p:delete('Keep', p:source('Keep').token, s); end);
assert(p:recovery() == nil, 'Failed writes do not add recovery entries.');
s.style.font_size = 22;
assert(p:overwrite('Keep', s, p:source('Keep').token));
interfere(function() return p:recover(s); end);
assert(p:recovery().kind == 'overwrite' and store.read(p.path).Keep.style.font_size == 22);
assert(p:recover(s) and store.read(p.path).Keep.style.font_size == 16);
store.write = original_write;

s.job_profiles[1] = 'Stale numeric link';
assert(p:link(s, 1, 'Keep') and s.job_profiles[1] == nil and s.job_profiles['1'] == 'Keep');
local missing = profiles.new(MOCK_INSTALL_PATH .. '/config/addons/vantage/not-shared');
local loaded, problem, found = missing:load_layout(s);
assert(loaded and not problem and found == false);
s.panels.future_panel = false;
assert(p:save_layout(s, 'placement') and p:save_layout(s, 'presentation'));
local receiver = defaults.make(); receiver.panels.future_panel = false;
assert(p:load_layout(receiver, 'presentation') and receiver.panels.future_panel == false);
assert(p:save_layout(s, 'placement') and p:load_layout(receiver, 'placement'));
local layout = profiles.capture_layout(s, 'presentation');
layout.presentation.style.font, layout.presentation.window_style.font_size = 'Consolas', 25;
assert(store.write(p.layout_path, layout));
receiver.window_style.font_size = 12;
loaded, problem, found = p:load_layout(receiver, 'presentation');
assert(loaded and not problem and found == true);
assert(receiver.style.font == 'Consolas' and receiver.window_style.font_size == 25,
    'A shared presentation brings its font and window text size.');
assert(profiles.capture_layout(s, 'invalid') == nil);
assert(p:save_new('Future', s));
receiver.panels.future_panel = { members = { [1001] = true } };
assert(p:load('Future', receiver), 'Unknown future panel keys cannot crash a profile load.');
return true;
