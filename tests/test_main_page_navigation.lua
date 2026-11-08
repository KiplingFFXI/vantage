local defaults, store = require('ui.defaults'), require('core.store');
local custom, appearance = require('core.customization'), require('ui.appearance');
local imgui = require('imgui');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 1,
    self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
require('ui.native_party_hud').draw = function() return 0, {}; end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end,
    status = function() return { available = false }; end };
local opened_combo;
local begin_combo = imgui.BeginCombo;
imgui.BeginCombo = function(label, ...)
    begin_combo(label, ...);
    return label == opened_combo;
end;
local app = dofile(ADDON_DIR .. '/vantage.lua');
for _, query in ipairs({ { 'Skin', 'Skin' }, { 'Party list buffs', 'Party list buffs' } }) do
    local found = false;
    for _, result in ipairs(require('ui.settings_window').search(query[1])) do
        found = found or result.tab == 'Home' and result.label == query[2];
    end;
    assert(found, 'The main page\'s controls are discoverable before it is opened: ' .. query[1]);
end;
for _, query in ipairs({ 'apply theme everywhere', 'match fonts artwork', 'client window skin', 'presets', 'apply setup' }) do
    local found = false;
    for _, result in ipairs(require('ui.settings_window').search(query)) do found = found or result.tab == 'Home'; end;
    assert(found, 'More words for the setup controls lead to the main page: ' .. query);
end;
local function command(value) local event = { command = value }; MOCK.fire('command', event); return event; end;
local function frame(click, combo)
    MOCK.imgui_calls, opened_combo = {}, combo;
    if click then MOCK.clicks[click] = true; end;
    MOCK.frame(.11);
    assert(#MOCK.font_stack == 0, 'Settings leave the selected font stack balanced.');
    if click then assert(not MOCK.clicks[click], 'The visible control receives its click: ' .. click); end;
end;
local function called(kind, label)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == kind and call[2] == label then return true; end; end;
    return false;
end;
local BACK = '< Back##frame';
local function settings() return app.state.settings; end;
-- To the main page from wherever a step left the window.
local function home() frame(settings().window.tab ~= 'Home' and BACK or nil); end;
local function clear_history() app.state.history, app.state.redo, app.state.transaction = {}, {}, nil; end;
local function history() return custom.history_value(settings()); end;
local function undo_redo(before, after, label)
    assert(#app.state.history == 1 and app.callbacks.history_status().undo_label == label,
        'The Home action is one named Undo step: ' .. label);
    command('/vg undo'); assert(custom.equal(history(), before), 'Undo restores ' .. label);
    command('/vg redo'); assert(custom.equal(history(), after), 'Redo restores ' .. label);
end;
MOCK.fire('load'); app.refresh(0);
assert(settings().window.tab == 'Home' and not settings().window.open, 'New settings start on the main page.');
for _, alias in ipairs({ '/vg', '/vantage' }) do
    settings().window.tab, settings().window.open = 'Help', false;
    assert(command(alias).blocked and settings().window.open and settings().window.tab == 'Home', alias .. ' opens the main page.');
end;
settings().window.open, settings().window.tab = false, 'Profiles';
command('/vg'); assert(settings().window.open and settings().window.tab == 'Home', 'Opening the settings starts with quick setup.');
MOCK.content_width = 1000;
clear_history();
local unopened = history();
frame(); frame();
assert(custom.equal(history(), unopened) and #app.state.history == 0, 'Opening the main page preserves every HUD setting and creates no Undo step.');
assert(not called('Selectable', 'Main page##nav_Home') and not called('Button', 'Home') and not called('Button', 'More look settings ...'),
    'The main page has no sidebar entry, and no Home button in the header.');
assert(not called('Checkbox', 'Show timers and recasts') and not called('Checkbox', 'Sample displays'), 'The main page avoids ambiguous global toolbar switches.');
assert(not called('Button', 'Filters'), 'The toolbar has no Filters.');
-- Profiles, Timer durations and Help sit beside Find a setting, and a narrow window gives them a line of their own. The X and
-- Esc close the window, so it has no Close button.
local function box_width()
    local width;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'SetNextItemWidth' then width = call[2]; end;
        if call[1] == 'InputTextWithHint' and call[2] == '##find_settings' then return width; end;
    end;
end;
assert(called('Button', 'Profiles') and called('Button', 'Timer durations') and called('Button', 'Help') and not called('Button', 'Close'), 'The top bar has the tool pages and no Close.');
assert(box_width() == -312, 'With room the search leaves them theirs: ' .. tostring(box_width()));
MOCK.content_width = 400;
frame();
assert(box_width() == -1 and called('Button', 'Profiles'), 'Narrow, the search takes the line and they go under it.');
MOCK.content_width = nil;
-- The top bar is the way to the tool pages. Each has a panel's top line, and Back comes home.
for _, page in ipairs({ { 'Durations', 'Timer durations', 'Timer durations' }, { 'Profiles', 'Profiles and sharing', 'Profiles' }, { 'Help', 'Help', 'Help' } }) do
    frame(page[3]);
    assert(settings().window.tab == page[1], 'The main page opens ' .. page[1]);
    frame();
    local named = false;
    for _, call in ipairs(MOCK.imgui_calls) do named = named or call[1] == 'TextColored' and call[3] == page[2]; end;
    assert(called('Button', BACK) and named, page[1] .. ' has Back and its name on its top line.');
    frame(BACK);
    assert(settings().window.tab == 'Home', 'Back goes to the main page from ' .. page[1]);
end;
assert(#app.state.history == 0, 'Ordinary page navigation does not occupy Undo history.');
local panels = require('ui.panel_frame');
panels.open('notices', 'show');
for _, page in ipairs({ 'Home', 'Help', 'Profiles', 'Display' }) do
    settings().window.tab = page;
    frame();
    assert(not called('Checkbox', 'Show timers and recasts') and not called('Checkbox', 'Sample displays'),
        'Unrelated editors cannot accidentally change the timer master or sample mode: ' .. page);
end;
panels.open('self_buffs', 'filters');
settings().window.tab = 'Display';
frame(); frame();
assert(settings().window.tab == 'Display' and called('InputText', '##frame_Find an effect'), 'The timer editor exposes effect controls directly.');
local effects_found = false;
for _, result in ipairs(require('ui.settings_window').search('Find an effect')) do
    effects_found = effects_found or result.tab == 'Display';
end;
assert(effects_found, 'Search retains effect customization after removing the duplicate sidebar entry.');
panels.open('recasts', 'show');
settings().window.tab = 'Display';
local rule_count = #settings().alerts.rules;
frame(); frame('Make an alert for a recast##frame'); frame();
assert(panels.context() == 'notices/show' and called('InputText', '##frame_Rule name') and #settings().alerts.rules == rule_count + 1
    and settings().alerts.rules[#settings().alerts.rules].domain == 'recast', 'The alert shortcut opens its selected rule.');
home();
frame(); assert(settings().window.tab == 'Home', 'Back from a display opens the main page.');
frame('Edit##main_pet');
assert(panels.context() == 'pet/show', 'Edit opens the detailed page.');
local indexed_home = false;
for _, result in ipairs(require('ui.settings_window').search('Grid mode')) do
    if result.label == 'Grid mode' then
        assert(result.tab == 'Home', 'Edit cannot index the remaining main page controls under the destination page.');
        indexed_home = true;
    end;
end;
assert(indexed_home, 'Controls drawn after Edit stay indexed under the main page.');

-- Effective toggles resume the display.
home();
local s = settings();
s.enabled, s.panels.self_buffs.enabled = false, true;
clear_history(); local before = history();
frame('Self buffs##main_self_buffs');
assert(settings().enabled and settings().panels.self_buffs.enabled);
undo_redo(before, history(), 'Self buffs');
home(); s = settings();
s.party_ui.enabled = true;
for key in pairs(s.party_ui.strips) do s.party_ui.strips[key] = false; end;
panels.open('party_ui', 'show');
s.window.tab = 'Display';
frame();
clear_history(); before = history(); frame('Alliance 2##frame_strip');
s = settings();
assert(s.party_ui.enabled and s.party_ui.strips.alliance2 and not s.party_ui.strips.party);
undo_redo(before, history(), 'Alliance 2');

home(); s = settings();
s.recast_display, s.panels.recasts.enabled = 'combined', true;
s.panels.recasts.recast_categories = { spell = true, ability = true, item = true };
clear_history(); before = history(); frame('Items##main_recast_item');
assert(settings().panels.recasts.enabled and not settings().panels.recasts.recast_categories.item);
undo_redo(before, history(), 'Item recasts');

home(); s = settings();
-- Set by hand here, so the page's lines hear of it as they would from a change.
s.preview, s.party_ui.preview = true, true;
app.state.settings_revision = app.state.settings_revision + 1;
clear_history(); before = history(); frame('End samples##main');
s = settings(); assert(not s.preview and not s.party_ui.preview, 'End samples ends the samples.');
assert(s.party_ui.enabled and s.panels.recasts.enabled, 'Ending samples keeps the chosen live displays enabled.');
undo_redo(before, history(), 'End samples');
command('/vg undo'); command('/vg redo'); home();

-- The links only route; skin and size picks are covered by test_main_page.lua.
home(); clear_history(); before = history();
frame('Edit##main_hidden');
assert(panels.context() == 'hidden/show' and custom.equal(history(), before) and #app.state.history == 0,
    'The link to the Hidden everywhere list only navigates.');
assert(#MOCK.commands == 0, 'The main page never sends a gameplay command.');
home();
for _, action in ipairs({ { 'Unlock all', false }, { 'Lock all', true } }) do
    clear_history(); before = history();
    frame(action[1] .. '##main');
    for _, id in ipairs(defaults.panel_order) do assert(settings().panels[id].locked == action[2]); end;
    assert(settings().party_ui.locked == action[2] and settings().alerts.notice_locked == action[2],
        'It includes the panels, the party list buffs and notices.');
    undo_redo(before, history(), action[1]);
end;
-- Nothing to show samples on, so Show samples leaves no Undo step.
settings().window.tab, settings().window.open = 'Home', true;
settings().enabled, settings().overhead.enabled, settings().party_ui.enabled = false, false, false;
settings().rolls.enabled, settings().pet.enabled, settings().party_cooldowns.enabled = false, false, false;
frame();
local steps = #app.state.history;
frame('Show samples##main');
assert(#app.state.history == steps and not settings().preview, 'With nothing on, Show samples is not an Undo step.');
local search_window, sorted, sort = require('ui.settings_window'), 0, table.sort;
search_window.search('font');
table.sort = function(...) sorted = sorted + 1; return sort(...); end;
local font_results = search_window.search('font');
local second_results = search_window.search('font');
table.sort = sort;
assert(sorted == 0 and custom.equal(font_results, second_results), 'Repeated searches reuse sorted labels without changing the result order.');
MOCK.fire('unload');
return true;
