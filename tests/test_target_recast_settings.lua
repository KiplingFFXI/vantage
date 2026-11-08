local defaults, profiles, custom = require('ui.defaults'), require('core.profiles'), require('core.customization');
-- Recast panels, their filters and alerts through tidy, profiles and the settings window.
local s = defaults.make();
for _, id in ipairs({ 'spell_recasts', 'ability_recasts', 'item_recasts' }) do
    assert(not s.panels[id].enabled and s.panels[id].locked, 'New recast panels are opt-in.');
    for key in pairs(s.panels.self_buffs) do
        if key ~= 'blink_icons' and key ~= 'blink_seconds' then
            assert(s.panels[id][key] ~= nil, 'Recast panel keeps every shared timer customization: ' .. key);
        end;
    end;
end;
s.panels.item_recasts.labels[95534] = 'My item';
s.panels.item_recasts.include[95534], s.panels.item_recasts.pinned[95534] = true, true;
s.panels.item_recasts.order, s.panels.item_recasts.effect_colors[95534] = { 95534 }, { 0.1, 0.2, 0.3, 1 };
s.panels.self_buffs.include[95534] = true;
s.alerts.rules = { defaults.rule('status'), defaults.rule('recast') };
s.alerts.rules[1].domain, s.alerts.rules[1].event = nil, 'gain';
s.alerts.rules[2].domain, s.alerts.rules[2].event, s.alerts.rules[2].effect = 'recast', 'ready', 95534;
s.alerts.rules[2].scope, s.alerts.rules[2].entity_id = 'party', 1234;
s = defaults.tidy(s);
assert(s.alerts.rules[1].domain == 'status' and s.alerts.rules[1].event == 'gain', 'A rule with no domain loads as a status rule.');
assert(s.alerts.rules[2].domain == 'recast' and s.alerts.rules[2].event == 'ready' and s.alerts.rules[2].effect == 95534);
assert(s.alerts.rules[2].scope == 'self' and s.alerts.rules[2].entity_id == 0);
assert(s.panels.item_recasts.labels[95534] == 'My item' and s.panels.item_recasts.pinned[95534]);
assert(not s.panels.self_buffs.include[95534], 'Status panels retain their original numeric bounds.');
local saved, target = profiles.new(MOCK_INSTALL_PATH .. '/config/addons/vantage'), defaults.make();
assert(saved:save_new('Target and recasts', s) and saved:load('Target and recasts', target));
assert(target.panels.item_recasts.labels[95534] == 'My item' and target.alerts.rules[2].effect == 95534);
assert(saved:save_layout(s, 'presentation') and saved:load_layout(target, 'presentation'));
assert(saved:save_layout(s, 'placement') and saved:load_layout(target, 'placement'));
local starter = assert(require('core.starters').apply(s, 'support'));
assert(custom.equal(starter.panels.item_recasts, s.panels.item_recasts), 'A starter keeps item recasts as they are.');

local catalogs = { spell = { { id = 10100, name = 'Test spell', kind = 'spell', group = 'spell_recasts' } },
    ability = { { id = 20010, name = 'Test ability', kind = 'ability', group = 'ability_recasts' } },
    item = { { id = 95534, name = 'Test item', kind = 'item', group = 'item_recasts' } } };
local all = { catalogs.spell[1], catalogs.ability[1], catalogs.item[1] };
package.loaded['core.recasts'] = { catalog = function(kind) return kind and catalogs[kind] or all; end };
local imgui, window = require('imgui'), require('ui.settings_window');
imgui.BeginCombo = function() return true; end;
local input = {};
imgui.InputText = function(label, value)
    if input[label] ~= nil then value[1], input[label] = input[label], nil; return true; end;
    return false;
end;
s = defaults.make(); s.window.open = true;
local view = require('ui.hud').sample(100);
local copied;
local cb = { changed = function() end, save = function() return true; end,
    copy_text = function(value) copied = value; return true; end };
local function frame(tab, click)
    s.window.tab = tab;
    if click then MOCK.clicks[click] = true; end;
    MOCK.imgui_calls = {};
    window.draw(s, view, cb);
    assert(#MOCK.font_stack == 0);
end;
for _, query in ipairs({ 'Recasts', 'Show item recasts', 'Recast ready', 'recast labels groups' }) do
    assert(#window.search(query) > 0, 'New controls are searchable before opening: ' .. query);
end;
local panels = require('ui.panel_frame');
panels.open('item_recasts', 'show');
frame('Display', 'On##frame_display'); assert(s.panels.item_recasts.enabled);
panels.open('item_recasts', 'look');
frame('Display', 'Start a new line##frame_part'); assert(s.panels.item_recasts.field_newlines.name);
input['##frame_Label_part'] = 'Ready:'; frame('Display'); assert(s.panels.item_recasts.field_labels.name == 'Ready:');
-- This panel's Filters tab holds the effect editor.
panels.open('item_recasts', 'filters');
frame('Display');
assert(s.window.tab == 'Display' and panels.context() == 'recasts/filters');
frame('Display', 'Test item##95534');
frame('Display', 'Pin first##frame'); assert(s.panels.item_recasts.pinned[95534]);
input['##frame_Rename it'] = 'Item ready'; frame('Display'); assert(s.panels.item_recasts.labels[95534] == 'Item ready');
panels.open('spell_recasts', 'filters');
frame('Display');
frame('Display', 'Show only##frame_effect');
local selected_spell;
for id in pairs(s.panels.spell_recasts.include) do selected_spell = id; end;
assert(selected_spell and selected_spell >= 10000 and selected_spell < 20000 and not s.panels.spell_recasts.include[95534], 'Each recast kind picks from its own list.');
panels.open('item_recasts', 'show');
frame('Display', 'Make an alert for a recast##frame');
assert(panels.context() == 'notices/show' and #s.alerts.rules == 1 and s.alerts.rules[1].domain == 'recast' and s.alerts.rules[1].event == 'ready');
frame('Display', 'Test item##effect_95534'); assert(s.alerts.rules[1].effect == 95534);
local unsupported = false;
for _, call in ipairs(MOCK.imgui_calls) do unsupported = unsupported or call[2] == 'Who to watch' or call[2] == 'Allow estimated timers'; end;
assert(not unsupported, 'Recast alerts expose only supported self cooldowns.');
frame('Display', 'Buff or debuff##status');
assert(s.alerts.rules[1].domain == 'status' and s.alerts.rules[1].effect == 0 and s.alerts.rules[1].event == 'remaining', 'Changing domains clears incompatible alert identity.');
local sort, sorts = table.sort, 0;
table.sort = function(values, compare)
    if type(values[1]) == 'table' and type(values[1].id) == 'number' and values[1].id >= 10000 then sorts = sorts + 1; end;
    return sort(values, compare);
end;
panels.open('item_recasts', 'filters');
frame('Display'); frame('Display'); local baseline = sorts;
frame('Display'); assert(sorts == baseline, 'Unchanged recast catalogs reuse their sorted lists and name indexes.');
catalogs.item = { { id = 95534, name = 'Renamed item', kind = 'item', group = 'item_recasts' } };
frame('Display'); assert(sorts > baseline, 'Replacing a resource catalog invalidates the cached picker.');
baseline = sorts;
view.recast_version = 5; frame('Display'); assert(sorts > baseline, 'The core recast version invalidates cached live entries.');
baseline = sorts;
view.rows[#view.rows + 1] = { domain = 'recast', effect = 95533, name = 'Observed item', kind = 'item', group = 'item_recasts' };
frame('Display'); assert(sorts > baseline, 'New live identities invalidate the catalog even without a version change.');
table.sort = sort;
view.rows, catalogs.item = {}, {};
s.panels.item_recasts.pinned, s.panels.item_recasts.labels = {}, {};
frame('Display');
MOCK.clicks['Show only##frame_effect'] = true;
frame('Display');
MOCK.clicks['Show only##frame_effect'] = nil;
assert(next(s.panels.item_recasts.include) == nil, 'An empty equipped-item catalog cannot create a sentinel-ID filter.');
s.panels.item_recasts.include[95534] = true;
frame('Display', "Clear this display's filters##frame");
assert(next(s.panels.item_recasts.include) == nil, 'Remembered filters can still be cleared without current item data.');
assert(#MOCK.commands == 0);
