-- The search costs nothing until a key is typed: the window loads and draws with no index, and an empty box asks nothing of
-- it. The first key builds it, once. A control it doesn't know makes one new search. The plain words reach the row that
-- sets what they mean, and a click on a result opens the display, the tab and the fold, with the control lit.
local store, defaults = require('core.store'), require('ui.defaults');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {},
    party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window, imgui, frame = require('ui.settings_window'), require('imgui'), require('ui.panel_frame');
local view = { rows = {}, context = { valid = true, job = 3, party = {}, entities = {} } };

local indexed, index_frame = 0, frame.index;
frame.index = function(...) indexed = indexed + 1; return index_frame(...); end;
local query = '';
local with_hint = imgui.InputTextWithHint;
imgui.InputTextWithHint = function(label, hint, value, ...)
    if label == '##find_settings' then value[1] = query; end;
    return with_hint(label, hint, value, ...);
end;
local function draw(click)
    MOCK.imgui_calls = {};
    if click then MOCK.clicks[click] = true; end;
    window.draw(app.state.settings, view, app.callbacks);
    if click then assert(not MOCK.clicks[click], 'The control is on the page: ' .. click); end;
end;
local function said(text)
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'TextUnformatted' and tostring(call[2]):find(text, 1, true) then return true; end;
    end;
    return false;
end;

-- Every page and a display, with nothing in the box.
local s = defaults.tidy(defaults.make());
s.window.open = true;
app.state.settings = s;
for _, page in ipairs({ 'Home', 'Durations', 'Profiles', 'Help', 'Display' }) do
    s.window.tab = page;
    draw(); draw();
end;
assert(#window.search('') == 0 and window.search('') == window.search(nil), 'An empty box finds nothing.');
assert(package.loaded['ui.search_index'] == nil and indexed == 0, 'No page and no empty box loads the index.');

-- The first key builds it, and no other does.
s.window.tab = 'Home';
query = 'f';
draw();
local index = package.loaded['ui.search_index'];
assert(index and indexed == 1, 'The first key builds the index.');
query = 'fo'; draw();
query = 'fon'; draw(); draw();
assert(indexed == 1 and package.loaded['ui.search_index'] == index, 'The next keys use it.');

-- An empty box leaves it alone, and the marks wait for a key.
query = ''; draw();
local kept = index.controls.Home.Moving;
index.controls.Home.Moving = 'Moving, untouched';
draw(); draw();
assert(index.controls.Home.Moving == 'Moving, untouched', 'With an empty box a page marks nothing.');
query = 'moving'; draw();
assert(index.controls.Home.Moving ~= 'Moving, untouched' and index.controls.Home.Moving:find('Moving', 1, true), 'With text in the box the page marks again.');
index.controls.Home.Moving = kept;

-- A control the index doesn't know makes one new search, and then it is found.
local main_page = require('ui.main_page');
local draw_main = main_page.draw;
local found = function(text, label)
    for _, result in ipairs(window.search(text)) do if result.tab == 'Home' and result.label == label then return true; end; end;
    return false;
end;
query = 'zebra';
draw(); draw();
local before = window.search(query);
assert(before == window.search(query) and not found(query, 'A new zebra control'), 'Fixture: nothing new yet.');
main_page.draw = function(a, b, c, d, helpers)
    helpers.mark('A new zebra control', 'Its help.');
    return draw_main(a, b, c, d, helpers);
end;
draw();
main_page.draw = draw_main;
assert(window.search(query) ~= before and found(query, 'A new zebra control'), 'A new control makes a new search, which finds it.');
draw(); draw();
local settled = window.search(query);
draw();
assert(window.search(query) == settled and indexed == 1, 'Nothing new, no new search, and the index is the same one.');
query = ''; draw();

-- Plain words. Beside the game's list the icons fill the row step, so the room a row has is what Longest row sets.
for _, word in ipairs({ 'room', 'gap', 'next row', 'icon room', 'Touching the next row' }) do
    local lands = false;
    for _, result in ipairs(window.search(word)) do
        lands = lands or result.panel == 'party_ui' and result.place == 'place' and result.label == 'Longest row';
    end;
    assert(lands, word .. ' leads to Longest row on Party list buffs\' Size and place tab.');
end;
-- A row's other names go before words only its help holds, and after what is called what was typed.
for _, word in ipairs({ 'room', 'next row', 'icon room' }) do assert(window.search(word)[1].label == 'Longest row', word .. ' leads there first.'); end;
assert(window.search('gap')[1].label:find('gap', 1, true) and not window.search('gap')[1].alias, 'What is called gap comes before it.');
local border = window.search('panel borders')[1];
assert(border.tab == 'Home' and border.label == 'Border', 'A control\'s more words on the main page rank as a panel\'s do.');
local font = window.search('font')[1];
assert(font.tab == 'Home' and font.label == 'Font', 'font leads to Font on the main page first: ' .. tostring(font.label));
local edit = false;
for _, result in ipairs(window.search('Start edit mode')) do edit = edit or result.tab == 'Home' and result.label == 'Edit mode'; end;
assert(edit, 'Edit mode finds the main page\'s button.');
-- What finds a control went in on its own page, none on another.
for _, entry in ipairs({ { 'Recast tracking coverage', 'Help', 'What can be tracked' }, { 'Export diagnostic report', 'Help', 'Export report' },
    { 'Rename profile', 'Profiles', 'Rename profile' }, { 'Frameless timer panels', 'Home', 'No boxes or headings' } }) do
    local lands, elsewhere = false, false;
    for _, result in ipairs(window.search(entry[1])) do
        if result.label == entry[3] then
            lands = lands or result.tab == entry[2];
            elsewhere = elsewhere or result.tab ~= entry[2];
        end;
    end;
    assert(lands and not elsewhere, entry[1] .. ' leads to ' .. entry[3] .. ' on ' .. entry[2]);
end;
assert(not index.controls.Help.Alerts:find('Enable alert rules', 1, true), 'The main page\'s more words stay off Help\'s heading of the same name.');

-- A click on a result: the display, the tab, and the control lit with the search still on.
local function click(text, row)
    s.window.tab, query = 'Home', text;
    frame.open('self_buffs', 'show');
    draw(); draw(row);
    query = text;
    draw(); draw();
    assert(said('matching controls on this page'), row .. ' lights the control.');
end;
click('room', 'Longest row  /  Party list buffs, Size and place');
assert(s.window.tab == 'Display' and frame.context() == 'party_ui/place', 'room opens Party list buffs\' Size and place tab.');
-- And a closed fold opens, and stays open.
s.window.sections['Overhead/Head offsets by name'] = nil;
click('Head height offset', 'Head height offset  /  Overhead icons, Size and place');
assert(frame.context() == 'overhead/place' and s.window.sections['Overhead/Head offsets by name'] == true, 'The result opens its tab and its fold.');
query = ''; draw();
MOCK.fire('unload');
return 'The index waits for the first key, is built once, and every word it holds leads somewhere';
