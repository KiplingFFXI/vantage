-- Words on the pages: Hidden everywhere talks about no setting it doesn't have, and each display's show
-- conditions read as one line. The edit mode bar's own line is in test_edit_mode.lua.
local app = dofile(ADDON_DIR .. '/vantage.lua');
local window, conditions, imgui = require('ui.settings_window'), require('core.conditions'), require('imgui');
local s = app.state.settings;
s.window.open = true;
s.window.sections = setmetatable({}, { __index = function() return true; end });
local function draw(page)
    s.window.tab, MOCK.imgui_calls = page, {};
    window.draw(s, app.state.view, app.callbacks);
end;
local function lines(kind)
    local found = {};
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == kind then found[#found + 1] = call[2]; end; end;
    return found;
end;
local function has(list, text)
    for _, line in ipairs(list) do if line == text then return true; end; end;
    return false;
end;

-- Hidden everywhere: no sentence about a setting that isn't there.
require('ui.panel_frame').open('hidden', 'show');
draw('Display');
local index = require('ui.search_index').controls;
local words = table.concat(lines('TextWrapped'), ' ');
assert(words:find('Effects on this list are hidden on the timer panels, party list buffs, overhead icons and Pet.', 1, true), 'The page says what the list does: ' .. words);
assert(not words:find('party/alliance frames', 1, true) and not words:find('native buff strips', 1, true), 'Not frames and native strips.');

-- When to show: one format, whatever the display, with or without conditions.
require('ui.panel_frame').open('self_buffs', 'when');
draw('Display');
local said = lines('TextWrapped');
assert(has(said, 'Self buffs: always shows.'), 'The display: ' .. table.concat(said, ' | '));
for _, line in ipairs(said) do
    assert(not line:find(' shows: ', 1, true) and not line:find('Always shows', 1, true), 'One format: ' .. line);
end;
s.panels.self_buffs.conditions = conditions.tidy({ main_jobs = { 3 }, zones = { 'town' } });
app.state.settings_revision = app.state.settings_revision + 1;
draw('Display');
said = lines('TextWrapped');
assert(has(said, 'Self buffs: Main job WHM. In Towns.'), 'With conditions: ' .. table.concat(said, ' | '));
for _, entry in ipairs({ { 'rolls', 'Phantom Roll' }, { 'pet', 'Pet' }, { 'notices', 'Alerts' } }) do
    require('ui.panel_frame').open(entry[1], 'when');
    draw('Display');
    assert(has(lines('TextWrapped'), entry[2] .. ': always shows.'), 'Every display reads the same: ' .. entry[2]);
end;
print('settings wording passed');
return true;
