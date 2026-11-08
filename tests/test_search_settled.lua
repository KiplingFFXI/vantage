-- While the settings search box holds text, a settled frame runs no new search and matches nothing again. Show conditions
-- draws a label twice with different help, which once made every frame there a new search. What the search found still
-- changes with the box.
local store, defaults = require('core.store'), require('ui.defaults');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {},
    party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window, imgui = require('ui.settings_window'), require('imgui');
local view = { rows = {}, context = { valid = true, job = 3, party = {}, entities = {} } };

local query = '';
local with_hint = imgui.InputTextWithHint;
imgui.InputTextWithHint = function(label, hint, value, ...)
    if label == '##find_settings' then value[1] = query; end;
    return with_hint(label, hint, value, ...);
end;
-- A new search hands back a new table, and the same search the table it kept.
local last, searches, matched = nil, 0, 0;
local search, matches = window.search, window.matches;
window.search = function(...)
    local results = search(...);
    if results ~= last then searches, last = searches + 1, results; end;
    return results;
end;
window.matches = function(...)
    matched = matched + 1;
    return matches(...);
end;
local function frames(count)
    for _ = 1, count do
        MOCK.imgui_calls = {};
        window.draw(app.state.settings, view, app.callbacks);
    end;
end;
local function open(page)
    local s = defaults.tidy(defaults.make());
    s.window.open, s.window.tab = true, page;
    app.state.settings = s;
    query = '';
    frames(2);
end;

for _, page in ipairs({ 'Conditions', 'Profiles', 'Home', 'Panels', 'Overhead', 'Recasts', 'Alerts', 'Filters', 'Help' }) do
    for _, text in ipairs({ 'haste', 'effects', 'colors' }) do
        open(page);
        query = text;
        frames(10);
        searches, matched = 0, 0;
        frames(20);
        assert(searches == 0, page .. ' ran ' .. searches .. ' new searches in 20 settled frames of ' .. text .. '.');
        assert(matched == 0, page .. ' matched ' .. matched .. ' times in 20 settled frames of ' .. text .. '.');
    end;
end;

-- A new word is a new search, and the page lights what it finds.
open('Conditions');
query = 'haste';
frames(10);
searches = 0;
query = 'zone';
frames(2);
assert(searches == 1, 'A new word runs one new search, not ' .. searches .. '.');
assert(#window.search('zone') > 0, 'Fixture: the word finds something.');

-- A plural stands for a whole word, not for the end of a longer one.
assert(window.matches('samples', 'Sample displays'), 'A plural finds its whole word.');
assert(not window.matches('less', 'Hide rules') and not window.matches('hows', 'Sample show'), 'A plural does not find the end of a word.');
