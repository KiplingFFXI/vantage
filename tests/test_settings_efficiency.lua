local defaults, store = require('ui.defaults'), require('core.store');
local window = require('ui.settings_window');
local hud, theme, appearance = require('ui.hud'), require('ui.theme'), require('ui.appearance');
local imgui = require('imgui');
local original_open, original_section, next_open = imgui.SetNextItemOpen, imgui.CollapsingHeader, false;
imgui.SetNextItemOpen = function(value) next_open = value; end;
imgui.CollapsingHeader = function() return next_open; end;
local app = dofile(ADDON_DIR .. '/vantage.lua');
app.refresh(0);
local original_changed, original_write = app.callbacks.changed, store.write;
local counts;
app.callbacks.changed = function(stage, label)
    counts[stage] = (counts[stage] or 0) + 1;
    return original_changed(stage, label);
end;
store.write = function(...)
    counts.writes = counts.writes + 1;
    return original_write(...);
end;
for _, case in ipairs({
    {'Your party##frame_strip', 'Display', 'strips', 'party', true},
    {'Alliance 1##frame_strip', 'Display', 'strips', 'alliance1', true},
    {'Alliance 2##frame_strip', 'Display', 'strips', 'alliance2', true},
    {'Show samples##frame', 'Display', 'party_ui', 'preview', false},
}) do
    local s = app.state.settings;
    local function owner(settings) return case[3] == 'strips' and settings.party_ui.strips or settings[case[3]]; end;
    s.window.open, s.window.tab = true, case[2];
    require('ui.panel_frame').open('party_ui', 'show');
    s.enabled, s.preview, s.party_ui.enabled, s.party_ui.preview = false, false, true, false;
    owner(s)[case[4]] = case[5];
    app.state.history, app.state.redo, app.state.transaction, app.state.dirty = {}, {}, nil, false;
    assert(original_write(app.state.path, s));
    counts = {before=0, after=0, writes=0};
    MOCK.clicks[case[1]] = true;
    window.draw(s, hud.sample(0), app.callbacks);
    assert(not MOCK.clicks[case[1]], 'The checkbox was visited: ' .. case[1]);
    assert(owner(s)[case[4]] ~= case[5]);
    assert(counts.before == 1 and counts.after == 1 and counts.writes == 1, 'Exactly one saved transaction: ' .. case[1]);
    assert(#app.state.history == 1 and not app.state.dirty);
    assert(owner(assert(store.read(app.state.path)))[case[4]] ~= case[5], 'Reload reads the changed value.');
    assert(app.callbacks.undo());
    assert(owner(app.state.settings)[case[4]] == case[5]);
    assert(app.callbacks.redo());
    assert(owner(app.state.settings)[case[4]] ~= case[5]);
end;
local s = app.state.settings;

local first = window.search('Buff side');
assert(first == window.search('Buff side'), 'Stable searches reuse matching results.');
assert(#first > 0);
for _, query in ipairs({'No boxes or headings', 'Frameless timer panels'}) do
    assert(#window.search(query) > 0, 'A label and its more words stay searchable: ' .. query);
end;

local a = defaults.make();
appearance.apply(a, 'XI View');
local name, details = appearance.describe(a);
assert(name == 'XI View' and #details == 0);
local _, again = appearance.describe(a);
assert(details == again, 'Unchanged appearance reuses its summary.');
a.party_ui.style.icon_art = 'Client';
local changed, differences = appearance.describe(a);
assert(changed == 'Mixed / customized' and differences ~= details and #differences == 1);
assert(differences[1].label == 'Party buff icons');
a.party_ui.style.icon_art = 'XI View';
assert(appearance.current(a) == 'XI View', 'Direct edits restore a current summary.');
a.panels.self_buffs.effect_colors['33'] = {1,0,0,1};
assert(appearance.current(a) == 'XI View', 'A color set for one effect is no custom look: a skin keeps it.');
a.panels.self_buffs.colors.title = {1,0,0,1};
assert(appearance.current(a) == 'Mixed / customized', 'Nested color edits invalidate the summary.');

local original_window, resolved = theme.window, 0;
theme.window = function(...) resolved = resolved + 1; return original_window(...); end;
-- One frame first, so the appearance summary the main page shows is already cached.
for _, page in ipairs({ 'Home', 'Display' }) do
    s.window.tab = page;
    window.draw(s, hud.sample(0), app.callbacks);
    counts, resolved = {before=0, after=0, writes=0}, 0;
    window.draw(s, hud.sample(0), app.callbacks);
    assert(resolved == 1, 'The settings frame resolves its menu look once: ' .. page);
end;
theme.window = original_window;
s.window.tab, s.party_ui.enabled, s.party_ui.preview = 'Party & alliance', false, true;
MOCK.imgui_calls = {};
window.draw(s, hud.sample(0), app.callbacks);
-- The header's switch says the party list buffs are off; no status line claims sample or live data.
local shown_off, stale_status = false, false;
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'Checkbox' and call[2] == 'On##frame_display' and call[3][1] == false then shown_off = true; end;
    if call[1] == 'TextWrapped' and (call[2]:find('Sample data', 1, true) or call[2]:find('Live data', 1, true)) then stale_status = true; end;
end;
assert(shown_off and not stale_status, 'The party list buffs off report hidden even if a sample preference remains enabled.');
s.party_ui.preview = false;
local original_filter, filter_calls = hud.filter_rows, 0;
hud.filter_rows = function(...) filter_calls = filter_calls + 1; return original_filter(...); end;
require('ui.panel_frame').open('party_ui', 'filters');
s.window.tab = 'Display';
window.draw(s, hud.sample(0), app.callbacks);
assert(require('ui.panel_frame').context():match('/filters$'), 'Fixture: the display\'s Filters tab is open.');
assert(filter_calls == 0, 'Catalog browsing skips live-panel filtering.');
hud.filter_rows = original_filter;
local editor, entries, selection = require('ui.effect_settings'), {{id=33,name='Haste',kind='buff'}}, {query='Haste', effect=33};
assert(editor.selection(entries, selection) == 33);
local labels = selection.labels;
assert(editor.selection(entries, selection) == 33 and selection.labels == labels);
entries[1].name = 'Slow';
assert(editor.selection(entries, selection) == nil and selection.labels ~= labels, 'Same-table resource renames invalidate effect choices.');
selection.query = 'Slow';
assert(editor.selection(entries, selection) == 33);
store.write = original_write;
app.callbacks.changed = original_changed;
imgui.SetNextItemOpen, imgui.CollapsingHeader = original_open, original_section;
return 'Saved checkbox transactions, staged choices, semantic appearance invalidation, search cache and menu-look reuse';
