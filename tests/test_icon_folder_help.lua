-- Reload icons and Open icons folder say the same on the main page and on Party list, from one string each, and
-- the icon set picks leave the zip sentence to the warning line under them. Help text feeds the search words.
local window = require('ui.settings_window');
local packs = require('ui.icon_packs');
local main = require('ui.main_page');
local ZIP = 'Vantage reads folders, not zip files, so extract a zipped set into a folder first.';
assert(type(packs.reload_help) == 'string' and type(packs.open_help) == 'string', 'Both helps are kept in one place.');
assert(packs.reload_help:find(ZIP, 1, true) and packs.open_help:find(ZIP, 1, true), 'The buttons keep the zip sentence.');
local helps = {};
for _, entry in ipairs(main.labels) do helps[entry[1]] = entry[2]; end;
assert(helps['Reload icons'] == packs.reload_help and helps['Open icons folder'] == packs.open_help,
    'The main page uses the shared helps.');
assert(helps['Icons'] and not helps['Icons']:find(ZIP, 1, true), 'The main page\'s Icons help drops the zip sentence.');
for _, query in ipairs({ 'zip', 'extract' }) do
    local found = {};
    for _, result in ipairs(window.search(query)) do found[result.tab .. '/' .. tostring(result.label)] = true; end;
    for _, place in ipairs({ 'Home/Reload icons', 'Home/Open icons folder', 'Display/Reload Party list icons',
        'Display/Open Party list icons folder' }) do
        assert(found[place], query .. ' finds ' .. place);
    end;
    assert(not found['Home/Icons'] and not found['Display/Party buff icons'], query .. ' leaves out the icon set picks.');
end;
