-- The main page, drawn on its own: What to show, How it looks and Moving. test_main_page_navigation.lua draws it in the
-- real settings window, with Profiles, Durations and Help in its top bar.
local defaults, copy, equal = require('ui.defaults'), require('core.store').copy, require('core.customization').equal;
local appearance = require('ui.appearance');
local page, imgui = require('ui.main_page'), require('imgui');
local s;
local changes, opens, notes, sections, headers, marks, texts = {}, {}, {}, {}, {}, {}, {};
local combo, sliders, hidden, shows, edits = nil, {}, false, 0, {};
imgui.BeginCombo = function(label, preview)
    MOCK.imgui_calls[#MOCK.imgui_calls + 1] = { 'BeginCombo', label, preview };
    return label == combo;
end;
imgui.SliderFloat = function(label, value)
    MOCK.imgui_calls[#MOCK.imgui_calls + 1] = { 'SliderFloat', label, value[1] };
    local chosen = sliders[label];
    if chosen == nil then return false; end;
    sliders[label], value[1] = nil, chosen;
    return true;
end;
for _, name in ipairs({ 'TextWrapped', 'TextUnformatted' }) do
    local original = imgui[name];
    imgui[name] = function(value, ...) texts[value] = true; return original(value, ...); end;
end;
local helper = { search = { '' }, look = {} };
helper.changed = function(fn, save, label) changes[#changes + 1] = { label = label, save = save }; fn(); end;
helper.open_page = function(name, panel, destination) opens[#opens + 1] = { name, panel, destination }; end;
helper.note = function(value) notes[#notes + 1] = value; end;
helper.mark = function(label) marks[label] = true; end;
helper.tip = function() end;
helper.heading = function(label) headers[#headers + 1] = label; end;
helper.section = function(label, help)
    headers[#headers + 1] = label;
    if helper.search[1] ~= '' then helper.mark(label, help); end;
    return sections[label] == true;
end;
-- tests/test_look_confirm.lua and tests/test_shared_look.lua cover the questions.
helper.confirm_look = function(_, action) action(); end;
helper.confirm_line = function() end;
helper.ask = function(_, _, action) action(); end;
helper.profile = { apply_starter = function() return true; end };
local cb = {
    displays_hidden = function() return hidden; end,
    show_displays = function() shows = shows + 1; end,
    edit_mode = function(on) edits[#edits + 1] = on; end,
};
local function draw(clicks, opened)
    combo, texts, headers, opens, MOCK.imgui_calls = opened, {}, {}, {}, {};
    for label in pairs(clicks or {}) do MOCK.clicks[label] = true; end;
    page.draw(imgui, s, {}, cb, helper);
    local missing = next(MOCK.clicks);
    MOCK.clicks = {};
    assert(missing == nil, 'Every requested control is on the page: ' .. tostring(missing));
end;
local function called(kind, label)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == kind and call[2] == label then return call; end; end;
end;
local function opened() return opens[#opens] or {}; end;
local function fresh() s = defaults.make(); changes, sections = {}, {}; return s; end;
local function one(label, save)
    local last = changes[#changes];
    return #changes == 1 and last.label == label and (save == nil or last.save == save);
end;

-- A fresh install: the three parts in order, with More look closed.
fresh();
local before = copy(s);
draw();
assert(equal(s, before) and #changes == 0, 'Opening the page writes nothing.');
assert(table.concat(headers, '|') == 'What to show|How it looks|More look|Moving', 'The parts in order: ' .. table.concat(headers, '|'));
assert(called('BeginCombo', '##main_skin') and called('BeginCombo', '##main_font') and called('Checkbox', 'Self buffs##main_self_buffs')
    and not called('BeginCombo', '##main_icon_art') and not called('SliderFloat', '##main_opacity'), 'More look stays closed at first.');
for _, text in ipairs({ 'Timer panels are paused.', 'The Hidden everywhere list is paused.', 'Edit mode is on.', 'Vantage displays are hidden (/vg hide).' }) do
    assert(not texts[text], 'A fresh install shows no attention line: ' .. text);
end;
assert(not called('Button', 'End samples##main') and not called('Button', 'Resume##main_resume'), 'And no button for one.');

-- Rows that depend on a mode stay hidden until that mode is on.
fresh();
sections['More look'] = true;
draw();
assert(called('BeginCombo', '##main_window_type'), 'Fresh: Window frame shows.');
appearance.apply(s, 'Mint');
draw();
assert(not called('BeginCombo', '##main_window_type'), 'Window frame shows only for Original FFXI and XI View.');
appearance.apply(s, 'XI View');
draw();
assert(called('BeginCombo', '##main_window_type'), 'XI View offers it.');
-- Every row of What to show is a tick and Edit. What the party list buffs show is on their Show tab.
s.party_ui.enabled = true;
draw();
assert(called('Checkbox', 'Party list buffs##main_party_ui') and called('Button', 'Edit##main_party_ui')
    and not called('Checkbox', 'Your party##main_group_party') and not called('RadioButton', 'Buffs only##main_kind_buff')
    and not called('Checkbox', 'Light up debuffs you can remove##main_party_light'), 'The party list buffs on: still one tick and Edit.');

-- Two columns in a wide window, one in a narrow one.
MOCK.content_width = 1000;
draw();
assert(called('BeginTable', '##main_show') and called('Checkbox', 'Self buffs##main_self_buffs') and called('Checkbox', 'Alerts##main_alerts'),
    'Wide: two columns, with every row.');
MOCK.content_width = 500;
draw();
assert(not called('BeginTable', '##main_show') and called('Checkbox', 'Self buffs##main_self_buffs') and called('Checkbox', 'Alerts##main_alerts'),
    'Narrow: one column, with every row.');
MOCK.content_width = nil;

-- How it looks. A skin pick changes the look in one step and leaves what isn't the look alone.
fresh();
draw({ ['Mint##Mint'] = true }, '##main_skin');
assert(appearance.candidate(s) == 'Mint' and require('ui.party_theme').party(s.party_ui, s.style).theme == 'Mint' and one('Skin: Mint', true),
    'Skin applies when picked, in one step.');
fresh();
s.party_ui.native.width, s.party_ui.native.gap = 319, 11;
s.party_ui.groups[2].native_detached, s.party_ui.groups[2].detached_width, s.party_ui.groups[2].detached_height = true, 447, 531;
s.party_ui.effects.icon_size = 41;
local unskinned, skinned = copy(s), copy(s);
assert(appearance.apply(skinned, 'XI View', { matching = true, window_type = s.style.window_type }));
draw({ ['XI View##XI View'] = true }, '##main_skin');
assert(one('Skin: XI View', true) and equal(s, skinned), 'A skin pick is one step that changes only the look.');
local function layout(config)
    local value = copy(config);
    value.style = nil;
    return value;
end;
assert(equal(layout(s.party_ui), layout(unskinned.party_ui)) and s.party_ui.native.width == 319
    and s.party_ui.groups[2].detached_width == 447, 'A skin pick leaves the custom strip sizes alone.');
fresh();
sections['More look'] = true;
for _, slider in ipairs({
    { '##main_text_size', 30.4, function() return s.style.font_size == 30; end, 'Text size' },
    { '##main_scale', 1.25, function() return s.style.scale == 1.25; end, 'Size' },
    { '##main_window_text', 30.4, function() return s.window_style.font_size == 30; end, 'Settings text size' },
    { '##main_icon_size', 40, function() return s.style.icon_size == 40; end, 'Icon size' },
    { '##main_bar_height', 40, function() return s.style.bar_height == 40; end, 'Row height' },
    { '##main_gap', 6, function() return s.style.gap == 6; end, 'Space between rows' },
    { '##main_title_size', 20, function() return s.style.title_size == 20; end, 'Heading size' },
    { '##main_opacity', 0.5, function() return s.style.opacity == 0.5; end, 'Opacity' },
    { '##main_rounding', 7, function() return s.style.rounding == 7; end, 'Corner rounding' },
}) do
    changes = {};
    sliders[slider[1]] = slider[2];
    draw();
    assert(slider[3]() and one(slider[4], false), 'The slider writes its key in a step that saves when it ends: ' .. slider[4]);
end;
for _, tick in ipairs({
    { 'Background##main_background', 'background' }, { 'Border##main_border', 'border' }, { 'No boxes or headings##main_minimal', 'minimal' },
    { 'Shadow##main_text_shadow', 'text_shadow' }, { 'Outline##main_text_outline', 'text_outline' },
    { 'Color each countdown by how sure Vantage is of its time##main_status_time_color', 'status_time_color' },
}) do
    local was = s.style[tick[2]] == true;
    changes = {};
    draw({ [tick[1]] = true });
    assert((s.style[tick[2]] == true) == not was and #changes == 1, 'The tick writes its key: ' .. tick[1]);
end;
-- The other text's outline color shows only with its outline on, and Window type picks the client's frame.
s.style.text_outline = true;
draw();
assert(called('ColorEdit4', 'Outline color##main_text_color'), 'Its color shows with the outline on.');
s.style.text_outline = false;
draw();
assert(not called('ColorEdit4', 'Outline color##main_text_color'), 'And not with it off.');
fresh();
sections['More look'] = true;
draw({ ['Window Type 3##3'] = true }, '##main_window_type');
assert(s.style.window_type == 3 and require('ui.theme').window(s).window_type == 3 and one('Window frame', true), 'Window frame writes the type for every display and this window.');
-- Art picks each write their own key, and Colors puts the skin's colors back as one step.
for _, art in ipairs({ { '##main_icon_art', 'icon_art' }, { '##main_recast_icon_art', 'recast_icon_art' }, { '##main_gauge_art', 'gauge_art' } }) do
    changes = {};
    draw({ ['XI View##XI View'] = true }, art[1]);
    assert(s.style[art[2]] == 'XI View' and #changes == 1, 'The pick writes its key: ' .. art[1]);
end;
sections.Colors = true;
s.style.text_color = { 0.1, 0.2, 0.3, 1 };
changes = {};
draw({ ["Back to the skin's colors##main_colors_reset"] = true });
assert(not equal(s.style.text_color, { 0.1, 0.2, 0.3, 1 }) and one("Back to the skin's colors", true), 'One step puts the skin\'s colors back.');

-- What to show.
fresh();
s.enabled, s.panels.self_buffs.enabled = false, false;
draw({ ['Self buffs##main_self_buffs'] = true });
assert(s.enabled and s.panels.self_buffs.enabled and one('Self buffs', true), 'A timer switch resumes timer panels.');
fresh();
s.enabled, s.panels.self_debuffs.enabled = false, true;
-- Paused, the tick reads off, so a click turns it on; turning off is the case with timer panels running.
draw({ ['Self debuffs##main_self_debuffs'] = true });
assert(s.enabled and s.panels.self_debuffs.enabled, 'Paused, the tick reads off and turns it on.');
changes = {};
draw({ ['Self debuffs##main_self_debuffs'] = true });
assert(s.enabled and not s.panels.self_debuffs.enabled and s.panels.self_buffs.enabled, 'Turning a timer off leaves the others and doesn\'t pause them.');
for _, id in ipairs({ { 'Party members\' timers##main_party', 'party' }, { 'Watched enemy timers##main_watch', 'watch' }, { 'Target timers##main_target', 'target' } }) do
    s.panels[id[2]].enabled = false;
    draw({ [id[1]] = true });
    assert(s.panels[id[2]].enabled, 'Timer switch: ' .. id[1]);
end;
s.party_ui.enabled, s.party_ui.preview = false, true;
for key in pairs(s.party_ui.strips) do s.party_ui.strips[key] = false; end;
draw({ ['Party list buffs##main_party_ui'] = true });
assert(s.party_ui.enabled and s.party_ui.strips.party and not s.party_ui.strips.alliance1,
    'Turning the party list buffs on gives them a group to show.');
draw({ ['Party list buffs##main_party_ui'] = true });
assert(not s.party_ui.enabled and not s.party_ui.preview, 'Turning them off ends their samples.');
for _, link in ipairs({
    { 'Edit##main_self_buffs', 'Display', 'self_buffs' }, { 'Edit##main_self_debuffs', 'Display', 'self_debuffs' }, { 'Edit##main_party', 'Display', 'party' },
    { 'Edit##main_watch', 'Display', 'watch' }, { 'Edit##main_target', 'Display', 'target' }, { 'Edit##main_recasts', 'Display', 'recasts' },
    { 'Edit##main_pulse', 'Display', 'recasts', 'Ready pulse' }, { 'Edit##main_party_ui', 'Display', 'party_ui' }, { 'Edit##main_overhead', 'Display', 'overhead' },
    { 'Edit##main_party_cooldowns', 'Display', 'cooldown_list' }, { 'Edit##main_rolls', 'Display', 'rolls' }, { 'Edit##main_pet', 'Display', 'pet' }, { 'Edit##main_alerts', 'Display', 'notices' },
    { 'Edit##main_hidden', 'Display', 'hidden' },
}) do
    changes = {};
    draw({ [link[1]] = true });
    assert(opened()[1] == link[2] and opened()[2] == link[3] and opened()[3] == link[4] and #changes == 0, 'Edit opens its editor and changes nothing: ' .. link[1]);
end;
-- Each display's own switch, and turning one off ends its samples.
fresh();
for _, row in ipairs({ { 'Overhead icons##main_overhead', 'overhead' }, { 'Phantom Roll##main_rolls', 'rolls' }, { 'Pet##main_pet', 'pet' } }) do
    local was = s[row[2]].enabled == true;
    s[row[2]].preview = true;
    draw({ [row[1]] = true });
    assert(s[row[2]].enabled == not was, 'The tick writes its display: ' .. row[1]);
    if was then assert(not s[row[2]].preview, 'Off ends its samples: ' .. row[1]); end;
    if not was then
        draw({ [row[1]] = true });
        assert(not s[row[2]].enabled and not s[row[2]].preview, 'Off ends its samples: ' .. row[1]);
    end;
end;
-- The three visibility rows: one tick over three keys, drawn partly ticked while they differ.
fresh();
local HIDE = 'Hide Vantage in cutscenes, on the map and when the game hides its menus##main_hide_game';
changes = {};
draw({ [HIDE] = true });
assert(not s.visibility.hide_events and not s.visibility.hide_map and not s.visibility.hide_ui and one('Hide Vantage with the game', true),
    'One tick writes all three keys in one step.');
s.visibility.hide_map = true;
local function partly()
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'draw:AddRectFilled' then return true; end; end;
    return false;
end;
draw();
assert(partly(), 'Keys that differ draw it partly ticked.');
draw({ [HIDE] = true });
assert(s.visibility.hide_events and s.visibility.hide_map and s.visibility.hide_ui, 'A click sets them all.');
draw();
assert(not partly(), 'All the same, no mark.');
draw({ ['Hide timer panels while I type##main_hide_typing'] = true, ['Show details when I point at a timer##main_hover'] = true });
assert(s.visibility.hide_typing == true and s.style.hover == false, 'The other two write their keys.');
-- Short ticks share a line while the window has the room, and a narrow one gives each its own.
local function one_line(first, second)
    local beside, seen = false, false;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Checkbox' and call[2] == first then seen = true;
        elseif seen and call[1] == 'SameLine' then beside = true;
        elseif seen and call[1] == 'Checkbox' then return call[2] == second and beside; end;
    end;
end;
local TYPING, HOVER = 'Hide timer panels while I type##main_hide_typing', 'Show details when I point at a timer##main_hover';
local PEEK, GRID = 'Hold Shift to see through this window##main_peek', 'Grid mode##main_grid_mode';
draw();
assert(one_line(TYPING, HOVER) and one_line(PEEK, GRID), 'With room they share a line.');
MOCK.content_width = 400;
draw();
assert(not one_line(TYPING, HOVER) and not one_line(PEEK, GRID), 'Narrow, each has its own.');
MOCK.content_width = nil;
-- Hidden everywhere names the effects hidden, by what the player knows them as.
fresh();
draw();
assert(texts['Hidden everywhere: nothing yet'], 'Nothing hidden yet.');
s.effect_filters.rules = { { enabled = true, effect = 253, kind = 'all', name = '', job = 0, scope = 'all' },
    { enabled = false, effect = 33, kind = 'all', name = '', job = 0, scope = 'all' },
    { enabled = true, effect = 33, kind = 'all', name = '', job = 0, scope = 'self' } };
draw();
assert(texts['Hidden everywhere: Signet and 1 other rule'], 'Only rules that are on and hide an effect everywhere are named, and the rest are counted.');
s.effect_filters.rules[1].enabled = false;
draw();
assert(texts['Hidden everywhere: 1 rule'], 'A rule that hides by who or what still counts.');
s.effect_filters.rules[2].enabled = true;
draw();
assert(texts['Hidden everywhere: Haste and 1 other rule'], 'A rule that\'s off is left out.');
s.effect_filters.rules[#s.effect_filters.rules + 1] = { enabled = true, effect = 0, kind = 'buff', name = '', job = 0, scope = 'all' };
draw();
assert(texts['Hidden everywhere: Haste and 2 other rules'], 'Two or more take the plural.');
-- An effect the game has no name for is still on the Hidden everywhere list, so it counts with the other rules.
s.effect_filters.rules = { { enabled = true, effect = 1000, kind = 'all', name = '', job = 0, scope = 'all' } };
draw();
assert(texts['Hidden everywhere: 1 rule'], 'A hidden effect with no name counts as a rule.');
s.effect_filters.rules[2] = { enabled = true, effect = 253, kind = 'all', name = '', job = 0, scope = 'all' };
draw();
assert(texts['Hidden everywhere: Signet and 1 other rule'], 'Beside one with a name, it is the other rule.');

-- Recasts. In separate panels a tick is that panel's switch, and resumes timer panels.
fresh();
s.enabled, s.panels.spell_recasts.enabled = false, false;
draw({ ['Spells##main_recast_spell'] = true });
assert(s.panels.spell_recasts.enabled and s.enabled and one('Spell recasts', true), 'A recast tick resumes timer panels.');
-- With one combined panel a tick is that panel's kind.
fresh();
s.recast_display, s.panels.recasts.enabled = 'combined', true;
s.panels.recasts.recast_categories = { spell = true, ability = true, item = true };
draw({ ['Items##main_recast_item'] = true });
assert(s.panels.recasts.recast_categories.item == false and s.panels.recasts.enabled and not s.panels.spell_recasts.enabled == not defaults.make().panels.spell_recasts.enabled,
    'Kinds change only the combined panel.');
draw({ ['Abilities##main_recast_ability'] = true, ['Spells##main_recast_spell'] = true });
assert(not s.panels.recasts.enabled, 'With no kind left the combined panel is off.');
draw({ ['Spells##main_recast_spell'] = true });
assert(s.panels.recasts.enabled and s.panels.recasts.recast_categories.spell and not s.panels.recasts.recast_categories.ability,
    'A tick on a panel that was off brings only its kind.');
fresh();
changes = {};
draw({ ['Ready pulse##main_pulse'] = true });
assert(s.ready_pulse.enabled == true and one('Ready pulse', true), 'Ready pulse writes its switch.');

-- Alerts.
fresh();
changes = {};
draw({ ['Alerts##main_alerts'] = true });
assert(s.alerts.enabled == not defaults.make().alerts.enabled and one('Alerts', true), 'Alerts writes its key.');
s.alerts.muted = true;
draw();
assert(texts['Muted'] and called('Button', 'Unmute##main_unmute'), 'Muted says so and offers Unmute.');
changes = {};
draw({ ['Unmute##main_unmute'] = true });
assert(not s.alerts.muted and one('Unmute alerts', true), 'Unmute is one step.');
draw();
assert(not texts['Muted'] and not called('Button', 'Unmute##main_unmute'), 'Not muted: no line.');

-- Moving. The line names only the displays that are on, each by its own switch. Fresh settings have Self buffs, Self
-- debuffs, Target timers and Alerts on. One button says Unlock all, or Lock all once a display that is on is
-- unlocked, and either sets every display's lock, on or off.
local function line_for(words) for text in pairs(texts) do if text:find(words, 1, true) then return text; end; end; end;
fresh();
s.party_ui.enabled, s.party_ui.locked = true, false;
draw();
assert(texts['Unlocked: Party list buffs. Hold Shift and drag one to move it.'], 'The line names the unlocked displays: ' .. tostring(line_for('nlocked')));
s.party_ui.enabled = false;
draw();
assert(texts['Every display is locked.'], 'A display that is off doesn\'t count.');
s.panels.self_buffs.locked, s.panels.self_debuffs.locked, s.panels.target.locked, s.alerts.notice_locked = false, false, false, false;
s.pet.enabled, s.pet.locked = true, false;
draw();
assert(texts['Unlocked: Self buffs, Self debuffs, Target timers, Alerts, Pet. Hold Shift and drag one to move it.'],
    'Every one is named, however many: ' .. tostring(line_for('nlocked')));
s.panels.self_buffs.enabled, s.panels.self_debuffs.enabled, s.panels.target.enabled, s.alerts.enabled, s.pet.enabled = false, false, false, false, false;
draw();
assert(not line_for('nlocked') and not texts['Every display is locked.'], 'With no display on there is nothing to say.');
s.panels.self_buffs.enabled, s.panels.self_buffs.locked = true, true;
for _, action in ipairs({ { 'Unlock all', false, 'Lock all' }, { 'Lock all', true, 'Unlock all' } }) do
    changes = {};
    draw({ [action[1] .. '##main'] = true });
    assert(not called('Button', action[3] .. '##main'), 'One button, with one word at a time.');
    for _, id in ipairs(defaults.panel_order) do assert(s.panels[id].locked == action[2], 'Locks every panel: ' .. id); end;
    assert(s.party_ui.locked == action[2] and s.alerts.notice_locked == action[2] and s.party_cooldowns.list.locked == action[2]
        and s.ready_pulse.locked == action[2] and s.rolls.locked == action[2] and s.pet.locked == action[2] and one(action[1], true),
        'One step locks or unlocks every display.');
end;
edits = {};
draw({ ['Edit mode##main'] = true });
assert(edits[1] == true and #changes == 1, 'Edit mode starts edit mode and changes no setting.');
assert(s.window.peek, 'Hold Shift to see through this window starts on.');
draw({ ['Hold Shift to see through this window##main_peek'] = true });
assert(s.window.peek == false, 'It writes its key.');
-- Grid mode: a tick that starts off, with nothing under it. On, as one step that saves, the fold Grid and snapping shows
-- under it, with the ticks and the grid's controls; off, the fold goes.
local function folded() for _, label in ipairs(headers) do if label == 'Grid and snapping' then return true; end; end; return false; end;
fresh();
draw();
assert(called('Checkbox', 'Grid mode##main_grid_mode') and s.edit_mode.grid_mode == false and not folded(),
    'Grid mode starts off, and no fold while it is off.');
changes = {};
draw({ ['Grid mode##main_grid_mode'] = true });
assert(s.edit_mode.grid_mode == true and one('Grid mode', true), 'The tick turns Grid mode on, as one step that saves.');
draw();
assert(folded() and not called('SliderFloat', '##main_grid_size'), 'The fold shows, and a closed fold draws nothing.');
sections['Grid and snapping'] = true;
draw();
assert(called('Checkbox', 'Self buffs##grid_tick_self_buffs') and called('SliderFloat', '##main_grid_size') and called('Checkbox', 'Show the grid##main_show_grid')
    and called('Checkbox', 'Snap to the chat log##main_snap_chat') and called('SliderFloat', '##main_snap_distance'), 'Open, it holds the ticks and the grid\'s controls.');
-- Each writes the edit mode key it always did. Ticks are one step that saves, and sliders don't save until you let go.
changes = {};
draw({ ['Self buffs##grid_tick_self_buffs'] = true });
assert(require('ui.snap').ticked(s, 'self_buffs') and one('Tick Self buffs for Grid mode', true), 'A display\'s tick is one step that saves.');
changes = {};
draw({ ['Snap to the chat log##main_snap_chat'] = true });
assert(s.edit_mode.snap_chat == not defaults.make().edit_mode.snap_chat and one('Snap to the chat log', true), 'A snap tick writes its key.');
sliders['##main_grid_size'], sliders['##main_snap_distance'] = 24, 9;
draw();
assert(s.edit_mode.grid == 24 and s.edit_mode.snap_distance == 9, 'The sliders write their keys.');
draw({ ['Grid mode##main_grid_mode'] = true });
draw();
assert(s.edit_mode.grid_mode == false and not folded() and not called('SliderFloat', '##main_grid_size'), 'Turned off, the fold goes.');

-- Show samples turns samples on only on the displays that are on, and End samples turns them all off.
fresh();
s.overhead.enabled, s.rolls.enabled = true, false;
changes = {};
draw({ ['Show samples##main'] = true });
assert(s.preview and s.overhead.preview and not s.rolls.preview and not s.party_ui.preview and one('Show samples', true), 'Samples show on what is on.');
draw();
assert(called('Button', 'End samples##main') and not called('Button', 'Show samples##main'), 'The button flips to End samples.');
s.rolls.preview, s.party_ui.preview = true, true;
changes = {};
draw({ ['End samples##main'] = true });
assert(not s.preview and not s.overhead.preview and not s.rolls.preview and not s.party_ui.preview and one('End samples', true), 'End samples ends every sample in one step.');
draw();
assert(called('Button', 'Show samples##main') and not called('Button', 'End samples##main'), 'And it flips back.');
fresh();
s.enabled, s.overhead.enabled, s.party_ui.enabled, s.rolls.enabled, s.pet.enabled, s.party_cooldowns.enabled = false, false, false, false, false, false;
notes = {};
draw({ ['Show samples##main'] = true });
assert(not s.preview and notes[1] == 'Samples show on the timer panels, Party list buffs, Overhead icons, the Party cooldowns list, Phantom Roll and Pet. Turn one on first.', 'With nothing on it says so.');

-- The attention lines show only while something needs a hand, one fix per line.
fresh();
s.enabled, changes = false, {};
draw({ ['Resume##main_resume'] = true });
assert(texts['Timer panels are paused.'] and s.enabled and one('Resume timer panels', true), 'Paused timers get a line and Resume.');
s.effect_filters.enabled, changes = false, {};
draw({ ['Use it again##main_use_list'] = true });
assert(texts['The Hidden everywhere list is paused.'] and s.effect_filters.enabled and one('Use the Hidden everywhere list', true), 'A paused list gets a line and Use it again.');
hidden, changes = true, {};
draw({ ['Show##main_show'] = true });
assert(texts['Vantage displays are hidden (/vg hide).'] and shows == 1 and #changes == 0, 'Hidden displays get a line; Show saves nothing.');
hidden = false;
local edit_mode = require('ui.edit_mode');
local active = edit_mode.active;
edit_mode.active = function() return true; end;
edits = {};
draw({ ['End edit mode##main_edit_end'] = true });
assert(texts['Edit mode is on.'] and edits[1] == false, 'Edit mode gets a line and its way out.');
edit_mode.active = active;
draw();
assert(not called('Button', 'Resume##main_resume') and not called('Button', 'Use it again##main_use_list') and not called('Button', 'Show##main_show')
    and not called('Button', 'End edit mode##main_edit_end'), 'Each line shows only while its condition holds.');

-- A frame makes no closures: the search marks run only while there is a search, and every label on the page is one the
-- index holds, marked in some state while searching.
marks = {};
fresh();
draw();
assert(next(marks) == nil, 'With no search nothing is marked.');
helper.search[1] = 'zzzz';
sections['More look'], sections.Colors, sections['Grid and snapping'] = true, true, true;
s.enabled, s.effect_filters.enabled, s.party_ui.enabled, s.alerts.muted, s.style.text_outline, s.preview = false, false, true, true, true, true;
s.edit_mode.grid_mode = true;
s.party_cooldowns.enabled, s.party_cooldowns.list.enabled, s.party_cooldowns.strips, s.party_cooldowns.overhead = true, false, false, false;
s.ready_pulse.enabled = true;
for _, id in ipairs({ 'recasts', 'spell_recasts', 'ability_recasts', 'item_recasts' }) do s.panels[id].enabled = false; end;
hidden = true;
edit_mode.active = function() return true; end;
-- A display's tick for Grid mode shows only while that display is on.
local elements = require('ui.elements');
local on = elements.on;
elements.on = function() return true; end;
draw();
-- Paused, no timer panel has samples to end.
s.enabled = true;
draw();
-- Lock all takes over from Unlock all while a display is unlocked.
s.panels.self_buffs.locked = false;
draw();
elements.on, edit_mode.active, hidden = on, active, false;
s.style.minimal = false;

-- A drag changes the settings every frame, so while the mouse is held the page's lines wait for it to come up. Settings
-- put in their place, as Undo does, are read at once.
local revision = 1;
cb.settings_revision = function() return revision; end;
local held = fresh();
draw();
assert(texts['Hidden everywhere: nothing yet'], 'Fixture: nothing hidden.');
MOCK.mouse_down = true;
s.effect_filters.rules = { { enabled = true, effect = 253, kind = 'all', name = '', job = 0, scope = 'all' } };
revision = 2;
draw();
assert(texts['Hidden everywhere: nothing yet'], 'While the mouse is held, the line waits.');
MOCK.mouse_down = false;
draw();
assert(texts['Hidden everywhere: Signet'], 'Let go, it catches up.');
MOCK.mouse_down = true;
fresh();
draw();
assert(texts['Hidden everywhere: nothing yet'] and s ~= held, 'Settings put in their place are read at once, held or not.');
MOCK.mouse_down, cb.settings_revision = false, nil;
local labels = 0;
for _, entry in ipairs(page.labels) do
    labels = labels + 1;
    assert(marks[entry[1]], 'The page marks its indexed label: ' .. entry[1]);
end;
helper.search[1] = '';
assert(labels > 60, 'The index lists the page\'s rows: ' .. labels);
assert(#MOCK.commands == 0, 'The page sends no game commands.');
return 'The main page shows what is on, writes each setting in one step, and points to the full editors';
