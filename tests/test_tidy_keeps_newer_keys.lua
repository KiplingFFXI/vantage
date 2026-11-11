-- A setting a newer Vantage saved survives a load here: every tidied table keeps the keys it doesn't know, including
-- those whose tidy builds them anew (an anchor, When to show, the hide rules and each rule, a duration override, the
-- settings window's look and the party list buffs' look). So going back to an older Vantage and forward again keeps them.
-- What an older Vantage saved in those two looks, which nothing reads now, still goes.
local defaults, store, json = require('ui.defaults'), require('core.store'), require('core.json');
local settings = defaults.make();
local marked = {};
local function mark(t, label)
    t.zz_newer = { label = label, list = { 1, 2 } };
    marked[#marked + 1] = label;
end
mark(settings, 'root'); mark(settings.style, 'style'); mark(settings.panels.self_buffs, 'panel');
mark(settings.panels.self_buffs.anchor, 'anchor'); mark(settings.panels.self_buffs.conditions, 'conditions');
mark(settings.alerts.notice_anchor, 'notice anchor'); mark(settings.window_style, 'window_style');
mark(settings.party_ui, 'party_ui'); mark(settings.party_ui.style, 'party_ui.style'); mark(settings.overhead, 'overhead');
mark(settings.durations, 'durations'); mark(settings.effect_filters, 'effect_filters');
settings.effect_filters.rules = { { enabled = true, effect = 33, kind = 'all', name = '', job = 0, scope = 'all' } };
mark(settings.effect_filters.rules[1], 'hide rule');
local override = require('core.durations').override();
override.id = 57;
settings.durations.overrides = { override };
mark(override, 'duration override');
-- Through a save and a load, as a file written by a newer Vantage is read.
local loaded = defaults.tidy(json.decode(store.encode(settings)));
local function at(label)
    local tables = { root = loaded, style = loaded.style, panel = loaded.panels.self_buffs, anchor = loaded.panels.self_buffs.anchor,
        conditions = loaded.panels.self_buffs.conditions, ['notice anchor'] = loaded.alerts.notice_anchor,
        window_style = loaded.window_style, party_ui = loaded.party_ui, ['party_ui.style'] = loaded.party_ui.style,
        overhead = loaded.overhead, durations = loaded.durations, effect_filters = loaded.effect_filters,
        ['hide rule'] = loaded.effect_filters.rules[1], ['duration override'] = loaded.durations.overrides[1] };
    return tables[label];
end
for _, label in ipairs(marked) do
    local kept = at(label) and at(label).zz_newer;
    assert(type(kept) == 'table' and kept.label == label and kept.list[2] == 2, 'A newer key survives in ' .. label .. '.');
end
-- What tidy knows is still tidied.
settings.panels.self_buffs.anchor.gap, settings.durations.overrides[1].seconds = 9000, -5;
loaded = defaults.tidy(json.decode(store.encode(settings)));
assert(loaded.panels.self_buffs.anchor.gap == 300 and loaded.durations.overrides[1].seconds == 1, 'Known keys are tidied as before.');
-- An export still holds only what this Vantage knows.
local text = assert(require('core.share').export(loaded, 'profile', nil, 'Tester'));
assert(not text:find('zz_newer', 1, true), 'An export leaves the unknown keys out.');
-- Every key the looks had before they followed the skin goes, and a newer one stays.
local old = defaults.make();
local window_keys = { 'linked', 'theme', 'window_type', 'window_art', 'font', 'rounding', 'spacing', 'tabs', 'tabs_hovered',
    'tabs_unfocused', 'open_tab', 'open_tab_line', 'open_tab_unfocused', 'open_tab_line_unfocused' };
for _, entry in ipairs(require('ui.theme').WINDOW_COLORS) do window_keys[#window_keys + 1] = entry.key; end
local style_keys = { 'theme', 'window_type', 'window_art', 'gauge_art', 'font', 'font_size', 'rounding', 'border', 'background',
    'minimal', 'colors' };
for _, key in ipairs(window_keys) do old.window_style[key] = { 0.5, 0.5, 0.5, 1 }; end
for _, key in ipairs(style_keys) do old.party_ui.style[key] = 'Mint'; end
old.window_style.zz_newer, old.party_ui.style.zz_newer = 1, 2;
old = defaults.tidy(json.decode(store.encode(old)));
for _, key in ipairs(window_keys) do assert(old.window_style[key] == nil, 'The window look loses ' .. key .. '.'); end
for _, key in ipairs(style_keys) do assert(old.party_ui.style[key] == nil, 'The strips style loses ' .. key .. '.'); end
assert(#window_keys == 51 and old.window_style.zz_newer == 1 and old.party_ui.style.zz_newer == 2, 'and the newer keys stay.');
-- A newer display stays in the panels map, and a newer overhead type in its map: each is a table. Anything else there,
-- from a hand edit or /vg set, goes, as the settings window and the layout export read each one as a table.
local stray = defaults.make();
stray.panels.zz_newer, stray.overhead.types.zz_newer = { label = 'newer panel' }, { label = 'newer type' };
stray.panels['1'], stray.panels.zz_flag = 0.5, true;
stray.overhead.types.enabled, stray.overhead.types['2'] = false, 'x';
stray = defaults.tidy(json.decode(store.encode(stray)));
assert(stray.panels.zz_newer and stray.panels.zz_newer.label == 'newer panel' and stray.overhead.types.zz_newer
    and stray.overhead.types.zz_newer.label == 'newer type', 'A newer display or overhead type stays.');
assert(stray.panels['1'] == nil and stray.panels.zz_flag == nil and stray.overhead.types.enabled == nil
    and stray.overhead.types['2'] == nil, 'A value that is no table goes from both maps.');
local custom = require('core.customization');
local set = assert(custom.set(defaults.make(), 'panels', '[0.5]'));
for id, panel in pairs(set.panels) do assert(type(panel) == 'table', '/vg set panels [0.5] keeps no ' .. tostring(id) .. ' that is no table.'); end
assert(require('core.share').export(set, 'layout', nil, 'Tester'), 'The layout export reads every display.');
set = assert(custom.set(defaults.make(), 'overhead.types', '{"enabled":false}'));
assert(set.overhead.types.enabled == nil, '/vg set overhead.types {"enabled":false} keeps no value that is no table.');
