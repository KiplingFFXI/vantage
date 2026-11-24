-- Each Profiles button, run the way ui/profiles_page.lua runs it in the frame it is clicked in, decodes profiles.json
-- at most once. A read of the file whose text didn't change reuses what the last read decoded, and a save still
-- sees a change another game made to the file since it was read.
local app = dofile(ADDON_DIR .. '/vantage.lua');
local c = app.callbacks;
local store, json, profiles, defaults = require('core.store'), require('core.json'), require('core.profiles'), require('ui.defaults');
local peer = profiles.new(require('core.identity').root());
local path = peer.path;
local reading, decodes = false, 0;
local read, decode = store.read, json.decode;
store.read = function(file, ...)
    local was = reading;
    reading = was or file == path;
    local value, why = read(file, ...);
    reading = was;
    return value, why;
end;
json.decode = function(...)
    if reading then decodes = decodes + 1; end;
    return decode(...);
end;
for i = 1, 4 do assert(c.profile_save('P' .. i, false)); end;
c.profile_status('P1');

local token;
local clicks = {
    { 'Overwrite', function() token = c.profile_status('P1').token; end },
    { 'Overwrite Confirm', function() assert(c.profile_save('P1', true, token)); end },
    { 'Save as new', function() assert(c.profile_save('New', false)); c.profile_status('New'); end },
    { 'Load', function() assert(c.profile_load('P2')); end },
    { 'Rename', function()
        assert(c.profile_rename('P3', 'Renamed', c.profile_status('P3').token)); c.profile_status('Renamed');
    end },
    { 'Delete', function() token = c.profile_status('New').token; end },
    { 'Delete Confirm', function() assert(c.profile_delete('New', token)); end },
    { 'Undo the last profile change', function() assert(c.profile_recover()); end },
    { 'Load after the undo', function() assert(c.profile_load('New')); end },
};
local over = {};
for _, click in ipairs(clicks) do
    local before = decodes;
    click[2]();
    if decodes - before > 1 then over[#over + 1] = click[1] .. ' ' .. (decodes - before); end;
end;
assert(#over == 0, 'Profiles buttons that decode profiles.json more than once in their frame: ' .. table.concat(over, ', '));
local names = c.profile_list();
assert(#names == 5 and names[1] == 'New' and names[2] == 'P1' and names[3] == 'P2' and names[4] == 'P4' and names[5] == 'Renamed',
    'The buttons did what they do: ' .. table.concat(names, ', '));

-- Another game saves the file between this game's read of it and its write. The write still says it changed.
local stale = c.profile_status('P2').token;
local cache = {};
local original = assert(store.read(path, cache));
local edited = defaults.make(); edited.style.font_size = 31;
assert(peer:overwrite('P2', edited, peer:source('P2').token), 'Fixture: the other game saved P2.');
local data = store.copy(original);
data.P4 = nil;
local ok, _, code = store.write(path, data, original, cache);
assert(not ok and code == 'changed', 'A write over a file changed since it was read is refused: ' .. tostring(code));
assert(peer:source('P4').exists and store.read(path).P2.style.font_size == 31, 'The newer file is kept.');
assert(not c.profile_save('P2', true, stale) and store.read(path).P2.style.font_size == 31, 'An Overwrite read before the change is still refused.');
return true;
