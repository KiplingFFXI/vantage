-- The search topic Your own icon sets opens Artwork on the main page, where Icons, Reload icons and Open icons folder are,
-- and keeps it open once the search is cleared, as a link there does. Folds open only as SetNextItemOpen says, as in ImGui.
local store, defaults = require('core.store'), require('ui.defaults');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {},
    party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window, imgui = require('ui.settings_window'), require('imgui');
local view = { rows = {}, context = { valid = true, job = 3, party = {}, entities = {} } };

local next_open;
rawset(imgui, 'SetNextItemOpen', function(value) next_open = value; end);
rawset(imgui, 'CollapsingHeader', function(label)
    MOCK.imgui_calls[#MOCK.imgui_calls + 1] = { 'CollapsingHeader', label };
    local open = next_open == true;
    next_open = nil;
    return open;
end);

local s = defaults.tidy(defaults.make());
s.window.tab, s.window.open = 'Home', true;
app.state.settings = s;
app.state.settings_revision = (app.state.settings_revision or 0) + 1;
local function draw()
    MOCK.imgui_calls = {};
    window.draw(s, view, app.callbacks);
    return MOCK.imgui_calls;
end;
local function drew(calls, kind, label)
    for _, call in ipairs(calls) do if call[1] == kind and call[2] == label then return true; end; end;
    return false;
end;

local calls = draw();
assert(not drew(calls, 'Button', 'Reload icons##main_reload_icons'), 'Fixture: Artwork starts closed.');
local topic;
for _, found in ipairs(window.search('icon sets')) do
    if found.label == 'Your own icon sets' and found.tab == 'Home' then topic = found; end;
end;
assert(topic and topic.topic, 'Fixture: the topic is found.');
window.open_result(topic);
draw();
calls = draw();
assert(drew(calls, 'Button', 'Reload icons##main_reload_icons') and drew(calls, 'Button', 'Open icons folder##main_open_icons')
    and drew(calls, 'BeginCombo', '##main_icon_art'), 'The topic opens Artwork, where the icon set controls are.');
assert(s.window.sections['Home/Artwork'] == true, 'And Artwork stays open.');
MOCK.fire('unload');
return 'ok';
