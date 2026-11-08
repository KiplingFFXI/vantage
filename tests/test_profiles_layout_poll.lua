-- The shared layout poll (core/profiles.lua read_layout): an unchanged shared_layout.json is decoded once, not on every
-- poll, and once it reads as the one seen, later polls know it without a walk. Loading it takes copies, so the value
-- the poll keeps is never changed by the settings it went into.
local profiles, defaults, json = require('core.profiles'), require('ui.defaults'), require('core.json');
local folder = MOCK_INSTALL_PATH .. '/config/addons/vantage/poll';
local saved = profiles.new(folder);
local function fresh() return defaults.tidy(defaults.make()); end
-- Every table in value, keys and entries both.
local function tables(value, found)
    found = found or {};
    if type(value) == 'table' and not found[value] then
        found[value] = true;
        for key, entry in pairs(value) do tables(key, found); tables(entry, found); end
    end
    return found;
end
local function shares(settings, layout)
    local kept = tables(layout);
    for value in pairs(tables(settings)) do if kept[value] then return true; end end
    return false;
end
local first = fresh();
assert(saved:save_layout(first, 'presentation'), 'Fixture: a shared layout is saved.');
local decode, decodes = json.decode, 0;
json.decode = function(...) decodes = decodes + 1; return decode(...); end;

local mine = fresh();
mine.shared_scope = 'presentation';
decodes = 0;
assert(saved:load_layout(mine, 'presentation'));
assert(decodes == 1, 'Loading the shared layout decodes it once: ' .. decodes);
decodes = 0;
for _ = 1, 5 do
    local layout, issue, unchanged = saved:read_layout();
    assert(layout and not issue and unchanged, 'The file is the one last read.');
end
assert(decodes == 0, 'Polls of the unchanged file decode nothing: ' .. decodes);

-- The settings share no table with the value the poll keeps, so a change here leaves that value as the file has it.
local kept = saved:read_layout();
assert(not shares(mine, kept), 'The loaded settings share no table with the value read.');
mine.panels.target.x = mine.panels.target.x + 50;
mine.style.outline_color[1] = 0.5;
kept = saved:read_layout();
assert(kept.presentation.panels.target.x == first.panels.target.x and kept.presentation.style.outline_color[1] == first.style.outline_color[1],
    'The value read stays as the file has it.');

-- Another character's save: the next poll decodes it and finds it new, and once loaded it is the one seen.
local other = fresh();
other.panels.target.x = 777;
assert(saved:save_layout(other, 'presentation'));
decodes = 0;
local changed, _, unchanged = saved:read_layout();
assert(changed.presentation.panels.target.x == 777 and not unchanged and decodes == 1, 'A changed file is decoded and is new.');
assert(saved:load_layout(mine, 'presentation', changed) and mine.panels.target.x == 777, 'It loads.');
assert(not shares(mine, changed), 'And the settings share no table with it.');
decodes = 0;
local _, _, seen = saved:read_layout();
assert(seen and decodes == 0, 'Then it is the one seen, with no decode: ' .. decodes);

-- This character's own write: the poll decodes it once, finds it the one seen, and from then on knows it at once.
mine.panels.target.x = 123;
assert(saved:publish_layout(mine, profiles.capture_layout(mine)));
decodes = 0;
local own, _, ours = saved:read_layout();
assert(own.presentation.panels.target.x == 123 and ours and decodes == 1, 'Its own file reads as the one seen.');
assert(saved.layout_seen == own, 'The value read is the one seen from then on.');
decodes = 0;
local _, _, still = saved:read_layout();
assert(still and decodes == 0, 'The next poll needs no decode: ' .. decodes);
json.decode = decode;
