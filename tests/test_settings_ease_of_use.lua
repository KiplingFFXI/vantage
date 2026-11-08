-- Settings ease of use: search finds the control, each setting has one name, pages read like a player tool
-- and carry less clutter. Saved keys and values are what they were.
local defaults, hud, store = require('ui.defaults'), require('ui.hud'), require('core.store');
local window, imgui = require('ui.settings_window'), require('imgui');
local panels = require('ui.panel_frame');
local s = defaults.make();
s.window.open = true;
local all_open = setmetatable({}, { __index = function() return true; end });
s.window.sections = all_open;
local view = hud.sample(100);
view.context = { valid = true, job = 3, party = { { id = 1001, name = 'Tester', scope = 'party' }, { id = 1002, name = 'Friend', scope = 'party' } },
    target = { id = 42, name = 'Crab', kind = 'monster' }, entities = {} };
local labels = {};
local cb = {
    now = function() return 100; end, save = function() return true; end, editor_changed = function() end,
    changed = function(stage, label) if stage == 'before' then labels[#labels + 1] = label; end; end,
    reset = function() return true; end, sound_files = function() return {}; end,
};
local combo, inputs, colors, sliders, hovered = nil, {}, {}, {}, false;
local real = { BeginCombo = imgui.BeginCombo, InputText = imgui.InputText, InputTextWithHint = imgui.InputTextWithHint,
    ColorEdit4 = imgui.ColorEdit4, SliderFloat = imgui.SliderFloat, IsItemHovered = imgui.IsItemHovered };
imgui.BeginCombo = function(label, ...) real.BeginCombo(label, ...); return label == combo; end;
local function typed(label, value)
    if inputs[label] ~= nil then value[1], inputs[label] = inputs[label], nil; return true; end;
    return false;
end;
imgui.InputText = function(label, value, ...) real.InputText(label, value, ...); return typed(label, value); end;
imgui.InputTextWithHint = function(label, hint, value, ...) real.InputTextWithHint(label, hint, value, ...); return typed(label, value); end;
imgui.ColorEdit4 = function(label, value, ...)
    real.ColorEdit4(label, value, ...);
    if colors[label] then colors[label] = nil; value[1] = 0.5; return true; end;
    return false;
end;
imgui.SliderFloat = function(label, value, ...)
    real.SliderFloat(label, value, ...);
    if sliders[label] ~= nil then value[1], sliders[label] = sliders[label], nil; return true; end;
    return false;
end;
imgui.IsItemHovered = function() return hovered; end;

local function draw(page, clicks)
    s.window.tab, MOCK.imgui_calls = page, {};
    for _, label in ipairs(clicks or {}) do MOCK.clicks[label] = true; end;
    window.draw(s, view, cb);
    for _, label in ipairs(clicks or {}) do assert(not MOCK.clicks[label], 'Fixture: the control was on screen: ' .. label); end;
    MOCK.clicks = {};
    assert(#MOCK.font_stack == 0, 'Each frame balances its fonts.');
end;
-- A tab of a panel.
local function on(id, key)
    panels.open(id, key);
    draw('Display');
    draw('Display');
end;
local function calls(kind, label)
    local found = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == kind and (label == nil or call[2] == label) then found[#found + 1] = call; end;
    end;
    return found;
end;
local function shown(kind, text)
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == kind and (call[2] == text or call[3] == text) then return true; end;
    end;
    return false;
end;
local function index_of(kind, label)
    for index, call in ipairs(MOCK.imgui_calls) do if call[1] == kind and call[2] == label then return index; end; end;
end;
local function clicked(page, clicks, label, before)
    labels = {};
    if before then before(); end;
    draw(page, clicks);
    assert(#labels == 1 and labels[1] == label, 'Undo names the edit: ' .. label .. ' (got ' .. tostring(labels[1]) .. ')');
end;

-- 4.1 Search that finds the control.
-- Every page drawn once, so the index holds what each page marks.
for _, page in ipairs(window._tabs) do draw(page); draw(page); end;
on('party_ui', 'place');
s.panels.self_buffs.mode = 'bars';
-- With a search typed every tab and section is drawn, which marks the controls whose labels carry an ID:
-- members, jobs and the party's effect filters.
s.alerts.rules = { defaults.rule('rule_1') };
imgui.InputTextWithHint = function(label, hint, value, ...)
    if label == '##find_settings' then value[1] = 'zzzz'; end;
    return false;
end;
for _, page in ipairs(window._tabs) do draw(page); end;
imgui.InputTextWithHint = function(label, hint, value, ...)
    if label == '##find_settings' then value[1] = ''; end;
    return false;
end;
draw('Home');
imgui.InputTextWithHint = function(label, hint, value, ...) real.InputTextWithHint(label, hint, value, ...); return typed(label, value); end;
local marked = require('ui.search_index').controls.Display['Clear this display\'s filters'] and require('ui.search_index').controls.Display.WAR;
assert(marked, 'Fixture: the labels with an ID were marked.');
for page, entries in pairs(require('ui.search_index').controls) do
    for label in pairs(entries) do
        assert(not label:find('##', 1, true), 'The index holds the words the player sees: ' .. page .. ': ' .. label);
        -- A panel's Down is how far down the screen it sits.
        assert(label ~= 'Up' and (label ~= 'Down' or page == 'Display') and label ~= 'First' and label ~= 'Last' and label ~= 'Edit',
            'Reorder buttons and bare Edit links stay out of search: ' .. page .. ': ' .. label);
        assert(label ~= 'General' and label ~= 'Advanced', 'Editor tab buttons stay out of search: ' .. page .. ': ' .. label);
    end;
end;
local edits = {};
for _, result in ipairs(window.search('edit')) do if result.tab == 'Home' then edits[result.label] = true; end; end;
for _, name in ipairs({ 'Self buffs', 'Self debuffs', 'Target timers', "Party members' timers", 'Watched enemy timers', 'Party list buffs' }) do
    assert(edits['Edit ' .. name], 'The main page\'s Edit links are found by the display they open: ' .. name);
end;
for _, query in ipairs({ 'font', 'size', 'lock', 'edit', 'party', 'sound', 'icon size' }) do
    local results, named = window.search(query), true;
    for position, result in ipairs(results) do
        local hit = window.matches(query, result.label);
        assert(not hit or named, 'A result named by the query comes before keyword-only ones: ' .. query .. ' #' .. position);
        named = named and hit;
    end;
end;
local font_rank;
for position, result in ipairs(window.search('font')) do
    if result.tab == 'Home' and result.label == 'Font' then font_rank = font_rank or position; end;
end;
assert(font_rank and font_rank <= 3, 'Home Font is near the top for font: ' .. tostring(font_rank));
-- The results box shows up to eight rows.
local function results_height(query)
    MOCK.imgui_calls = {};
    imgui.InputTextWithHint = function(label, hint, value, ...)
        if label == '##find_settings' then value[1] = query; end;
        return false;
    end;
    s.window.tab = 'Home';
    window.draw(s, view, cb);
    imgui.InputTextWithHint = function(label, hint, value, ...) real.InputTextWithHint(label, hint, value, ...); return typed(label, value); end;
    local found = calls('BeginChild', '##search_results')[1];
    MOCK.imgui_calls = {};
    imgui.InputTextWithHint = function(label, hint, value, ...)
        if label == '##find_settings' then value[1] = ''; end;
        return false;
    end;
    window.draw(s, view, cb);
    imgui.InputTextWithHint = function(label, hint, value, ...) real.InputTextWithHint(label, hint, value, ...); return typed(label, value); end;
    return found and found[3][2], #window.search(query);
end;
local height, count = results_height('size');
assert(count > 8 and height == 8 * 23 + 6, 'A long result list shows eight rows: ' .. tostring(height));
height, count = results_height('bust chance');
assert(count < 8 and height == count * 23 + 6, 'A short list shows only its rows.');

-- The timer Filters tab's three ticks show once an effect is picked, Find an effect leads to them before that, and Undo names
-- them.
for _, label in ipairs({ 'Include in this panel', 'Hide in this panel', 'Pin above other effects' }) do
    local found = false;
    for _, result in ipairs(window.search(label)) do found = found or result.tab == 'Display' and result.label == 'Find an effect'; end;
    assert(found, 'Search finds what shows ' .. label);
end;
on('self_buffs', 'filters');
inputs['##frame_Find an effect'] = 'Haste'; draw('Display'); draw('Display');
clicked('Display', { 'Show only##frame_effect' }, 'Show this effect only');
assert(s.panels.self_buffs.include[33] == true, 'Fixture: Haste is included.');
clicked('Display', { 'Hide here##frame' }, 'Hide here');
clicked('Display', { 'Pin first##frame' }, 'Pin first');

-- Edits that said only Settings change in Undo now say what they change.
inputs['##frame_Rename it'] = 'Speed';
clicked('Display', nil, 'Rename it');
clicked('Display', { 'Add to My order##frame' }, 'Add to My order');
clicked('Display', { 'Remove##effect' }, 'Remove from Show only');
clicked('Display', { "Clear this display's filters##frame" }, "Clear this display's filters");
draw('Display');
clicked('Display', { 'Buffs##filter_Buffs' }, 'Show kind: Buffs');
s.panels.party.members = {};
on('party', 'show');
clicked('Display', { 'Tester##member_1001' }, 'Members');
s.panels.self_buffs.mode = 'bars';
on('self_buffs', 'look');
s.panels.self_buffs.field_colors.name = { 1, 0, 0, 1 };
clicked('Display', { 'frame_back_Color_part' }, 'Use the shared color: Part color');
clicked('Display', { 'Put the row text back as it started##frame' }, 'Put the row text back as it started');
s.panels.self_buffs.colors.background = { 0, 0, 0, 1 };
clicked('Display', { 'frame_back_Background color' }, 'Use the shared color: Background color');
s.panels.self_buffs.colors.background = { 0, 0, 0, 1 };
draw('Display');
clicked('Display', { "Back to the skin's colors##frame" }, "Back to the skin's colors");
on('self_buffs', 'place');
clicked('Display', { 'Put it back where it started##frame' }, 'Put Self buffs back');
on('notices', 'show');
clicked('Display', { 'New alert##frame' }, 'Add alert: ' .. defaults.rule().name);
combo = '##Effect';
clicked('Display', { 'Haste##effect_33' }, 'Rule effect');
combo = nil;
s.alerts.rules[1].event = 'remaining';
inputs['##thresholds'] = '20, 5';
clicked('Display', nil, 'Thresholds');
clicked('Display', { 'Delete##alert' }, 'Delete rule');

-- 4.2 One name per setting, on every page that shows it.
s = defaults.make();
s.window.open, s.window.sections, s.preview = true, all_open, true;
s.party_ui.enabled = true;
draw('Home');
assert(shown('TextUnformatted', 'Window frame') and not shown('TextUnformatted', 'Window'), 'The main page calls it Window frame.');
assert(#calls('Button', 'Edit##main_self_buffs') == 1 and #calls('Button', 'More timer panel settings ...') == 0
    and #calls('Button', 'Grid and snapping ...') == 0 and #calls('Button', 'More display settings ...') == 0
    and #calls('Button', 'More placement settings ...') == 0 and #calls('Button', 'Placement guides and snapping ...') == 0,
    'The main page says Edit beside what it opens.');
assert(#calls('Checkbox', 'Grid mode##main_grid_mode') == 1, 'The main page calls it Grid mode.');
assert(#calls('Checkbox', 'Hold Shift to see through this window##main_peek') == 1, 'The main page calls peek Hold Shift to see through this window.');
assert(#calls('Button', 'End samples##main') == 1, 'While samples show, the main page ends them.');
for _, label in ipairs({ '##main_icon_size', '##main_scale' }) do
    assert(#calls('SliderFloat', label) == 1, 'The main page has one of: ' .. label);
end;
assert(#calls('BeginCombo', '##main_recast_icon_art') == 1 and #calls('BeginCombo', '##main_window_type') == 1,
    'And of the artwork and the window frame.');
assert(#calls('SliderFloat', '##main_window_text') == 1, 'And of the text size of this window.');
combo = '##main_skin'; draw('Home'); combo = nil;
assert(#calls('Selectable', 'Frameless##Minimal') == 1, 'The skin list calls the Minimal skin Frameless.');
on('self_buffs', 'place');
assert(#calls('SliderFloat', '##Timer icon size') == 0 and #calls('SliderFloat', '##main_icon_size') == 0, 'A panel has no icon size: the main page has it.');
on('notices', 'show');
assert(#calls('Checkbox', 'On##frame_display') == 1 and #calls('Checkbox', 'Alerts on') == 0 and #calls('Checkbox', 'Enable alert rules') == 0,
    'Alerts calls it Show, as every display does.');
on('recasts', 'show');
assert(#calls('BeginCombo', '##Recast icon artwork') == 0 and #calls('BeginCombo', '##frame_Icons show') == 1,
    'The Recasts panel keeps Icons show; Recast icons is on the main page.');

-- 4.3 Pages that read like a player tool.
local function preview(label)
    local found = calls('BeginCombo', label)[1];
    return found and found[3];
end;
-- Member names shows while a group is in a panel of its own.
s.party_ui.groups[1].native_detached = true;
on('party_ui', 'place');
assert(preview('##frame_Buff side') == 'Left', 'The combo shows a label, not a program value.');
on('party_ui', 'look');
assert(preview('##frame_Member names') == 'Full name', 'The combo shows a label, not a program value.');
s.party_ui.groups[1].native_detached = false;
on('party_ui', 'place');
assert(preview('##frame_Icons fill') == 'Left to right');
on('party_ui', 'show');
assert(preview('##frame_Sort') == 'Longest remaining');
s.panels.self_buffs.mode, s.panels.self_buffs.show_elapsed = 'bars', true;
on('self_buffs', 'look');
assert(preview('##frame_Label position') == 'Before the value' and preview('##frame_Line up rows') == 'Left');
local anchor_to = s.panels.self_buffs.anchor.to;
s.panels.self_buffs.anchor.to = 'chat';
on('self_buffs', 'place');
assert(preview('##frame_Side') == 'Below' and preview('##frame_Line up') == 'Start');
s.panels.self_buffs.anchor.to = anchor_to;
-- Panel colors have readable names, and each Shared lines up.
on('self_buffs', 'look');
-- The fill's end draws only with Shaded bars, so its row shows only then.
assert(#calls('ColorEdit4', 'Bar fill end color##frame') == 0, 'A row that would change nothing is left out.');
for _, panel in pairs(s.panels) do panel.gradient = true; end;
on('self_buffs', 'look');
for _, panel in pairs(s.panels) do panel.gradient = false; end;
for _, name in ipairs({ 'Background color', 'Border color', 'Bar track color', 'Title color', 'Name color', 'Countdown color',
    'Detail text color', 'Bar fill start color', 'Bar fill end color', 'Ending soon color' }) do
    assert(#calls('ColorEdit4', name .. '##frame') == 1, 'Panel color named for what it paints: ' .. name);
end;
local column, inherits;
inherits = 0;
for index, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'TextUnformatted' and call[2] == 'Shared' then
        inherits = inherits + 1;
        local before;
        for back = index - 1, 1, -1 do
            local call = MOCK.imgui_calls[back];
            if call[1] == 'SameLine' then before = call; break; end;
            assert(call[1] ~= 'ColorEdit4' and call[1] ~= 'Button', 'Fixture: Shared follows its color on the same line.');
        end;
        assert(before and type(before[2]) == 'number' and before[2] > 0, 'Shared is placed at a fixed x.');
        column = column or before[2];
        assert(before[2] == column, 'Every Shared lines up.');
    end;
end;
assert(inherits == 11, 'Every color that can go back says it is shared: ' .. inherits);
-- Values that stand for something say what.
s.style.title_size, s.panels.self_buffs.row_height, s.alerts.notice_x, s.alerts.notice_height = 0, 0, -1, 0;
local function format(label)
    local found = calls('SliderFloat', label)[1];
    return found and found[6];
end;
on('self_buffs', 'place');
assert(format('##frame_Row height') == ('Shared (%.0f)'):format(s.style.bar_height), 'Row height says the shared height it uses.');
s.style.font_size = 16;
draw('Home');
for label, text in pairs({ ['##main_title_size'] = 'Same as Text size', ['##main_text_size'] = '%.0f' }) do
    assert(format(label) == text, 'The slider says what its value means: ' .. label .. ' ' .. tostring(format(label)));
end;
s.style.title_size = 20; draw('Home');
assert(format('##main_title_size') == '%.0f', 'A real value shows as a number.');
local rule = defaults.rule('rule_1'); rule.volume, rule.sound = -1, 'ding.wav'; s.alerts.rules = { rule };
require('ui.alert_panel').edit('rule_1');
on('notices', 'show');
assert(format('##frame_Volume') == 'Same as Sound volume');
on('notices', 'place');
assert(format('##frame_Across_notices') == 'Centered');
assert(format('##frame_Tallest') == 'Fit');
s.panels.self_buffs.mode = 'icons';
on('self_buffs', 'place');
assert(format('##frame_Size_countdown') == 'Automatic');
-- Every countdown has the one time format, so recast and status panels have no Time format pick.
s.panels.spell_recasts.mode, s.panels.self_buffs.mode = 'bars', 'bars';
for _, id in ipairs({ 'spell_recasts', 'self_buffs' }) do
    for _, which in ipairs({ 'show', 'place', 'look', 'filters', 'when' }) do
        on(id, which);
        assert(#calls('BeginCombo', '##frame_Time format') == 0, 'No Time format pick: ' .. id .. ' ' .. which);
    end;
end;
-- Hidden everywhere: an effect goes on the list by name, and the list gives it its Remove.
s.effect_filters.rules = {};
on('hidden', 'show');
assert(#calls('Button', 'Remove##effect') == 0, 'Nothing is listed.');
inputs['##frame_Find an effect'] = 'Level Sync';
draw('Display');
draw('Display', { 'Hide it everywhere##frame' });
assert(#s.effect_filters.rules == 1 and s.effect_filters.rules[1].effect == 269, 'Fixture: Level Sync is hidden.');
draw('Display');
assert(#calls('Button', 'Remove##effect') == 1, 'On the list, it has its Remove.');

-- 4.4 Less clutter.
s = defaults.make();
s.window.open, s.window.sections, s.preview = true, all_open, false;
local function text_like(pattern)
    for _, call in ipairs(MOCK.imgui_calls) do
        for index = 2, 3 do
            if type(call[index]) == 'string' and call[index]:find(pattern, 1, true) then return true; end;
        end;
    end;
    return false;
end;
on('self_buffs', 'show');
assert(not text_like('Editing:'), 'The header names the panel, so there is no Editing line.');
assert(not text_like('Live data enabled') and not text_like('Sample data') and not text_like('Display hidden') and not shown('TextWrapped', 'Locked'),
    'The status line does not repeat the switches.');
s.panels.self_buffs.locked = false; draw('Display');
assert(shown('TextWrapped', 'Unlocked: hold Shift and drag it to move it, or drag an edge to resize it.'), 'An unlocked display says how to move it.');
s.party_ui.enabled = true;
-- Beside the game's party list a group only moves; a group in a panel of its own also resizes. The lock's help, the
-- Unlocked line and Help say so.
local MOVES, RESIZES = 'Unlocked: hold Shift and drag a group to move it.', 'Unlocked: hold Shift and drag a group to move it, or drag a panel\'s edge to resize it.';
s.party_ui.locked = false; on('party_ui', 'show');
assert(shown('TextWrapped', MOVES) and not shown('TextWrapped', RESIZES), 'Groups beside the game\'s party list only move.');
local lock_help = false;
for _, result in ipairs(window.search('Unlock first, then hold Shift and drag a group to move it. A group in a panel of its own also resizes from its edges and corners.')) do
    lock_help = lock_help or result.panel == 'party_ui' and result.label == 'Locked';
end;
assert(lock_help, 'The lock\'s help says a group moves and a panel of its own also resizes.');
s.party_ui.groups[1].native_detached = true; draw('Display');
assert(shown('TextWrapped', RESIZES), 'A panel of its own also resizes.');
s.party_ui.groups[1].native_detached, s.party_ui.locked = false, true;
draw('Help');
assert(text_like('Shift + left-drag any edge or corner to resize; a group beside the game\'s party list only moves.')
    and not text_like('detaches it'), 'Help says a group beside the game\'s party list only moves.');
assert(text_like('outlines every display at once: pick one, then hold Shift and drag it or nudge it'), 'Help says edit mode moves a display with Shift held.');
-- The header names the panel on every tab, with no Editing line.
for _, key in ipairs({ 'show', 'place' }) do
    on('party_ui', key);
    assert(not text_like('Editing:') and shown('TextColored', 'Party list buffs'), 'The heading and no Editing line: ' .. key);
end;
-- Headers open as ImGui opens them, so a section with nothing saved shows its default.
local real_set, real_header, open_next = imgui.SetNextItemOpen, imgui.CollapsingHeader, nil;
imgui.SetNextItemOpen = function(value, ...) open_next = value; return real_set(value, ...); end;
imgui.CollapsingHeader = function(label, ...) real_header(label, ...); return open_next == true; end;
s.window.sections = {};
draw('Durations');
assert(#calls('Button', 'Add duration override') == 1, 'Duration overrides opens by default.');
imgui.SetNextItemOpen, imgui.CollapsingHeader = real_set, real_header;
s.window.sections = all_open;
-- No page has a preview pane. Samples show on the displays themselves.
for _, page in ipairs(window._tabs) do
    draw(page);
    assert(#calls('CollapsingHeader', 'Preview pane##shared_preview') == 0 and #calls('BeginChild', '##preview_footer') == 0, 'No preview pane on ' .. page);
end;
-- Recast panels never offer who it is on or who cast it, and have one Show.
s.panels.spell_recasts.mode, s.panels.self_buffs.mode, s.panels.target.mode = 'bars', 'bars', 'bars';
on('spell_recasts', 'show');
assert(#calls('Checkbox', 'Who it is on##frame') == 0 and #calls('Checkbox', 'Who cast it##frame') == 0 and #calls('Checkbox', 'Time elapsed##frame') == 1,
    'A recast panel offers no target or caster part.');
assert(#calls('Checkbox', 'On##frame_display') == 1, 'The Recasts panel shows each panel switch once.');
local recast_panel = s.panels.spell_recasts;
recast_panel.show_target, recast_panel.show_source = true, true;
draw('Display');
assert(#calls('Checkbox', 'Who it is on##frame') == 0 and #calls('Checkbox', 'Who cast it##frame') == 0, 'Saved on, they are not offered either.');
recast_panel.show_target, recast_panel.show_source = false, false;
on('target', 'show');
assert(#calls('Checkbox', 'Who it is on##frame') == 1 and #calls('Checkbox', 'Who cast it##frame') == 1 and #calls('Checkbox', 'On##frame_display') == 1);
-- A recast row still draws what a saved layout turned on.
local fields = require('ui.fields');
local p = store.copy(recast_panel);
p.show_target, p.show_source = true, true;
local row = { domain = 'recast', effect = 10004, name = 'Cure IV', entity_name = 'Tester', status = 'server', deadline = 120, total = 30, start = 90 };
local drawn = {};
for _, entry in ipairs(fields.build(row, p, s.style, 100, function() return '' end, '0:20', 'Cure IV')) do drawn[entry.id] = entry.text; end;
assert(drawn.target == 'Tester' and drawn.source == nil, 'A recast row draws the saved target field; a caster with no name is left out.');
row.source_name = 'Tester';
drawn = {};
for _, entry in ipairs(fields.build(row, p, s.style, 100, function() return '' end, '0:20', 'Cure IV')) do drawn[entry.id] = entry.text; end;
assert(drawn.source == 'by Tester', 'A named caster draws in the saved caster field.');
-- Position, height and bar span sliders end at the screen or a practical span; typing still goes further.
local function slider(label)
    local found = calls('SliderFloat', label)[1];
    return found and found[4], found and found[5];
end;
s.panels.self_buffs.mode = 'bars';
on('self_buffs', 'place');
local low, high = slider('##frame_Across'); assert(low == 0 and high == 1600, 'X ends at the screen width.');
low, high = slider('##frame_Down'); assert(high == 900, 'Y ends at the screen height.');
sliders['##frame_Across'] = 5000; draw('Display');
assert(s.panels.self_buffs.x == 5000, 'A typed value past the screen is kept.');
on('self_buffs', 'place');
low, high = slider('##frame_Tallest'); assert(high == 900);
on('notices', 'place');
low, high = slider('##frame_Across_notices'); assert(low == -1 and high == 1600);
low, high = slider('##frame_Down_notices'); assert(high == 900);
on('notices', 'place');
low, high = slider('##frame_Tallest'); assert(high == 900);
MOCK.screen = { 0, 0 };
on('self_buffs', 'place'); low, high = slider('##frame_Across'); assert(high == 40, 'A first frame with no screen size still draws a slider.');
MOCK.screen = nil;

for name, fn in pairs(real) do imgui[name] = fn; end;
assert(#MOCK.commands == 0);
return 'Search finds the control, settings have one name, and the pages read plainly with less clutter';
