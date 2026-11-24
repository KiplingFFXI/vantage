-- Watch my target's help on Overhead icons names no row of Watched enemy timers. A row's help is part of what finds it,
-- so a search for When empty finds the timer panels' row, and not this button or the Watched mobs tick it hides under.
local defaults = require('ui.defaults');
local app = dofile(ADDON_DIR .. '/vantage.lua');
local window = require('ui.settings_window');

local s = defaults.tidy(defaults.make());
s.window.open, s.window.tab = true, 'Home';
app.state.settings = s;
window.draw(s, { rows = {}, context = { valid = false } }, app.callbacks);

local function overhead_watch(query)
    local found, list = false, {};
    for _, result in ipairs(window.search(query)) do
        if result.label == 'When empty' then found = true; end;
        if result.panel == 'overhead' and (result.label == 'Watch my target' or result.label == 'Watched mobs') then list[#list + 1] = result.label; end;
    end;
    return found, table.concat(list, ', ');
end;

for _, query in ipairs({ 'when empty', 'empty' }) do
    local found, listed = overhead_watch(query);
    assert(found, 'Fixture: a search for ' .. query .. ' finds the timer panels\' When empty row.');
    assert(listed == '', 'A search for ' .. query .. ' lists nothing for watching on Overhead icons: ' .. listed);
end;
-- With a mob watched the button hides, and its words go to the Watched mobs tick. The words go the other way round, so
-- the search isn't answered from the last one.
s.watch_ids[1] = 1234;
window.draw(s, { rows = {}, context = { valid = false } }, app.callbacks);
local found, listed = overhead_watch('empty when');
assert(found and listed == '', 'With a mob watched it still lists nothing for watching on Overhead icons: ' .. listed);
MOCK.fire('unload');
return true;
