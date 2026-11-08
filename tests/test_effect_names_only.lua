-- Every effect finder shows names. No row carries an effect's number and Effect sorting doesn't offer Effect ID, while
-- typing a number still finds its effect.
local defaults, hud = require('ui.defaults'), require('ui.hud');
local window, imgui = require('ui.settings_window'), require('imgui');
local selection = require('ui.effect_settings').selection;
local s = defaults.make();
s.window.open = true;
s.window.sections = setmetatable({}, { __index = function() return true; end });
local view = hud.sample(100);
view.context = { valid = true, job = 3, party = {}, entities = {} };
local cb = { now = function() return 100; end, save = function() return true; end, editor_changed = function() end,
    changed = function() end, reset = function() return true; end, sound_files = function() return {}; end };
local combo, inputs = nil, {};
local real_combo, real_hint, real_input = imgui.BeginCombo, imgui.InputTextWithHint, imgui.InputText;
imgui.BeginCombo = function(label, ...) real_combo(label, ...); return label == combo; end;
imgui.InputTextWithHint = function(label, hint, value, ...)
    real_hint(label, hint, value, ...);
    if inputs[label] ~= nil then value[1], inputs[label] = inputs[label], nil; return true; end;
    return false;
end;
imgui.InputText = function(label, value, ...)
    real_input(label, value, ...);
    if inputs[label] ~= nil then value[1], inputs[label] = inputs[label], nil; return true; end;
    return false;
end;
local function draw(page, clicks)
    s.window.tab, MOCK.imgui_calls = page, {};
    for _, label in ipairs(clicks or {}) do MOCK.clicks[label] = true; end;
    window.draw(s, view, cb);
    MOCK.clicks = {};
end;
local function called(kind, label, value)
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == kind and call[2] == label and (value == nil or call[3] == value) then return true; end;
    end;
    return false;
end;
-- The rows of the list on screen with the given id start.
local function rows(start)
    local found = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Selectable' and call[2]:find(start, 1, true) then found[#found + 1] = call[2]; end;
    end;
    return found;
end;
local function no_numbers(list, title)
    assert(#list > 0, 'Fixture: ' .. title .. ' has rows.');
    for _, row in ipairs(list) do assert(not row:match('^(.-)##'):find('%(%d+%)'), title .. ' shows a name: ' .. row); end;
end;

-- A panel's Filters tab.
local finds, effects = '##frame_Find an effect', '##frame_Effect';
local function effect_rows()
    local found = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Selectable' and tostring(call[2]):find('##%d+$') then found[#found + 1] = call[2]; end;
    end;
    return found;
end;
require('ui.panel_frame').open('self_buffs', 'filters');
combo = effects;
draw('Display');
assert(called('InputText', finds), 'The box to type a name in is there.');
inputs[finds] = 'Haste'; draw('Display'); draw('Display');
assert(called('Selectable', 'Haste##33'), 'The row reads Haste.');
no_numbers(effect_rows(), 'The panel list');
inputs[finds] = '33'; draw('Display'); draw('Display');
local list = effect_rows();
assert(#list == 1 and list[1] == 'Haste##33', 'A typed number still finds its effect: ' .. table.concat(list, ' '));
inputs[finds] = '3'; draw('Display'); draw('Display');
assert(not called('Selectable', 'Haste##33'), 'Only the whole number finds it.');
inputs[finds] = ''; draw('Display');
combo = nil;

-- An alert rule's picker.
require('ui.panel_frame').open('notices', 'show');
draw('Display', { 'New alert##frame' });
combo = '##Effect';
draw('Display');
assert(called('InputTextWithHint', '##effect_search_Effect', 'Find an effect by name'), 'The picker asks for a name.');
no_numbers(rows('##effect_'), 'The alert rule list');
inputs['##effect_search_Effect'] = '33'; draw('Display'); draw('Display');
assert(called('Selectable', 'Haste##effect_33'), 'The picker finds a typed number too.');
inputs['##effect_search_Effect'] = ''; draw('Display');
combo = nil;

-- The finders on the display pages share one selection: names in, and a number still finds.
local entries = { { id = 33, name = 'Haste' }, { id = 3, name = 'Poison' }, { id = 330, name = 'Attack Boost' } };
local pick = { query = '33' };
assert(selection(entries, pick) == 33 and #pick.ids == 1 and pick.labels[33] == 'Haste', 'A typed number picks its effect and shows its name.');
pick = { query = 'poison' };
assert(selection(entries, pick) == 3 and pick.labels[3] == 'Poison', 'A name finds it.');
pick = { query = '(33)' };
assert(selection(entries, pick) == nil and #pick.ids == 0, 'The number is no part of a row.');

-- Sort, on Party list buffs.
local panels = require('ui.panel_frame');
s.party_ui.enabled = true;
panels.open('party_ui', 'show');
combo = '##frame_Sort';
draw('Display');
combo = nil;
local offered = {};
for _, row in ipairs(rows('##')) do offered[row] = true; end;
for _, label in ipairs({ 'Longest remaining##longest', 'Oldest first##oldest', 'Ending soonest##remaining', 'Name##name' }) do
    assert(offered[label], 'Effect sorting offers ' .. label);
end;
assert(not offered['Effect ID##id'], 'Effect sorting doesn\'t offer Effect ID.');
s.party_ui.effects.sort = 'id';
assert(defaults.tidy(s).party_ui.effects.sort == 'longest', 'A sort it doesn\'t know loads as longest.');
draw('Display');
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'TextWrapped' then assert(not call[2]:find('name or ID', 1, true), 'No engineer words: ' .. call[2]); end;
end;
print('effect names only passed');
return true;
