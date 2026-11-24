-- A key typed in the settings search runs one search over every control, topic and display row. Each row's words are
-- lowered once and kept, and a display row builds its result key only once it matches. Measured with the compiler off
-- and the collector stopped, after the index is built, each search right after a collection.
local store, defaults = require('core.store'), require('ui.defaults');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {},
    party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window = require('ui.settings_window');
local view = { rows = {}, context = { valid = true, job = 3, party = {}, entities = {} } };
local s = defaults.tidy(defaults.make());
s.window.tab, s.window.open = 'Home', true;
app.state.settings = s;
app.state.settings_revision = (app.state.settings_revision or 0) + 1;
for _, page in ipairs({ 'Home', 'Durations', 'Profiles', 'Help', 'Display' }) do
    s.window.tab = page;
    MOCK.imgui_calls = {};
    window.draw(s, view, app.callbacks);
end;

-- A player typing: each search's words differ from the last, so none is the one just kept.
local words = { 'e', 'ef', 'eff', 'effe', 'effec', 'effects', 'haste', 'colors', 'window', 'font', 'recast', 'settings font' };
local function query(round, index) return words[index] .. string.rep(' ', round % 3); end;
for round = 1, 3 do for index = 1, #words do window.search(query(round, index)); end; end;

local lower, lowered = string.lower, 0;
string.lower = function(text) lowered = lowered + 1; return lower(text); end;
jit.off(); jit.flush();
local made, searches = 0, 0;
for round = 4, 6 do
    for index = 1, #words do
        collectgarbage('collect'); collectgarbage('collect');
        collectgarbage('stop');
        local before = collectgarbage('count');
        window.search(query(round, index));
        made = made + collectgarbage('count') - before;
        collectgarbage('restart');
        searches = searches + 1;
    end;
end;
string.lower = lower;
jit.on();
local each, lowers = made / searches, lowered / searches;
-- Before, every row's words were lowered again on each search, about 4900 texts, and with a key for every display row
-- that made 265 KB on the 64-bit runtime. Lowering each text once took it to 154 KB, and keys for the rows that match to
-- 79 KB. The query, and each result's label as the results are put in order, are still lowered each search.
assert(lowers < 1000, ('A search lowers %.0f texts again.'):format(lowers));
assert(each < 120, ('A search after a collection makes %.1f KB.'):format(each));
MOCK.fire('unload');
return ('A search makes %.1f KB and lowers %.0f texts'):format(each, lowers);
