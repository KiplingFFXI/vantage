-- Exports are checked against fresh settings (core/share.lua), so a key that left defaults.make() would refuse
-- every string that holds it. Fresh settings keep every key in share_keys_fixture.lua, and a string holding them all
-- reads.
local frozen, defaults, share, store = require('share_keys_fixture'), require('ui.defaults'), require('core.share'), require('core.store');
local fresh = defaults.make();
local function at(path)
    local node = fresh;
    for name in path:gmatch('[^.]+') do
        if type(node) ~= 'table' then return nil; end;
        node = name == '[]' and node[1] or node[name];
    end;
    return node;
end;
local count = 0;
for parent, names in pairs(frozen) do
    local node = at(parent);
    assert(type(node) == 'table', 'Fresh settings keep ' .. (parent == '' and 'their top' or parent) .. '.');
    for name in names:gmatch('%S+') do
        count = count + 1;
        local path = (parent == '' and '' or parent .. '.') .. name;
        assert(node[name] ~= nil, 'Fresh settings keep ' .. path .. '.');
    end;
end;
assert(count >= 1531, 'The list holds every key a string could hold at 1.0 and since.');
-- A profile string of fresh settings holds every key a profile carries, and reads back.
local settings = defaults.tidy(defaults.make());
local text = assert(share.export(settings, 'profile', nil, 'Tester'));
local payload = assert(share.read(text));
assert(payload.data.party_ui.effects.icon_size == 32, 'It reads back.');
-- Read against a template without a frozen key, a string that holds it is refused: the check above is what keeps it.
text = assert(share.export(settings, 'element', 'party_ui', 'Tester'));
assert(assert(share.read(text)).data.effects.icon_size == 32);
local make = defaults.make;
defaults.make = function(...) local value = make(...); value.party_ui.effects.icon_size = nil; return value; end;
local ok, refused, why, what = pcall(share.read, text);
defaults.make = make;
-- The reason is in plain words; the third value names the key.
assert(ok and refused == nil and why == share.NEWER and what:find('icon_size', 1, true), 'A missing key refuses the strings that hold it.');
assert(store.equal(make(), fresh), 'Fresh settings are the same each time.');
return 'Fresh settings keep every frozen key, and a string holding them reads';
