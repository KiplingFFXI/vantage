-- The Timer durations page and the target and watched enemy panels' light, in the real settings window through
-- vantage.lua. Each control writes its own key as one Undo step named for it; Undo puts it back and Redo does it
-- again. The times learned from your casts are saved with the settings but stay out of Undo: an Undo or Redo keeps
-- what was learned since, Clear learned durations is one Undo step whose Undo brings them back, and resets, profiles
-- and shared presentation leave them with this character. Search and Home find the page.
local store = require('core.store');
local SNAP = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(SNAP); end };
package.loaded['core.observer'] = { read = function() return {}; end, wear_off = 'Observed wearoff' };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, status = function() return { active = false }; end };
local imgui = require('imgui');
local defaults = require('ui.defaults');
local custom = require('core.customization');
local profiles = require('core.profiles');
local copy = store.copy;
local app = dofile(ADDON_DIR .. '/vantage.lua');
local window = require('ui.settings_window');
local page = require('ui.duration_settings');
MOCK.fire('load'); app.refresh(0);

local function found(query, tab, label)
    for _, result in ipairs(window.search(query)) do if result.tab == tab and result.label == label then return true; end end
    return false;
end;
assert(found('learned durations', 'Durations', 'Duration overrides and learned durations'), 'Search names the Timer durations page.');
-- What isn't drawn yet finds the control that shows it: the Add button of an empty list, the panel picker for a light
-- only some panels have.
for _, entry in ipairs({ { 'Add duration override', 'Durations' }, { 'Learn from my casts', 'Durations' }, { 'Clear learned durations', 'Durations', 'Learn from my casts' },
    { 'count up', 'Durations', 'Duration overrides and learned durations' }, { 'Change the time to', 'Durations', 'Add duration override' },
    { 'Light up buffs', 'Display', 'Light up buffs you can remove' }, { 'Glow around lit icons', 'Display', 'Light up buffs you can remove' },
    { 'Glow around lit buffs', 'Display', 'Light up buffs you can remove' }, { 'Light up debuffs', 'Display', 'Light up debuffs you can remove' },
    { 'cursna', 'Display', 'Debuffs you can remove' },
    { 'dispel', 'Display', 'Mob buffs you can remove' }, { 'dispellable', 'Display', 'Mob buffs you can remove' } }) do
    assert(found(entry[1], entry[2], entry[3] or entry[1]), 'Search finds ' .. (entry[3] or entry[1]) .. ' on ' .. entry[2] .. ' before it is drawn.');
end;

local combo, slider, typed, colored;
imgui.BeginCombo = function(label) return label == combo; end;
imgui.SliderFloat = function(label, value)
    if slider and slider[1] == label then value[1], slider = slider[2], nil; return true; end
    return false;
end;
imgui.ColorEdit4 = function(label, value)
    if colored and colored[1] == label then for i = 1, 4 do value[i] = colored[2][i]; end; colored = nil; return true; end
    return false;
end;
local input, input_with_hint = imgui.InputText, imgui.InputTextWithHint;
local function typing(label, value)
    if typed and typed[1] == label then value[1], typed = typed[2], nil; return true; end
    return false;
end;
imgui.InputText = function(label, value, ...) if typing(label, value) then return true; end return input(label, value, ...); end;
imgui.InputTextWithHint = function(label, hint, value, ...) if typing(label, value) then return true; end return input_with_hint(label, hint, value, ...); end;
local view = { rows = {}, context = { valid = true, job = 3, target = { id = 0x1000100, name = 'Crab', kind = 'monster' }, entities = {} } };
local function frame(step)
    step = step or {};
    combo, slider, typed, colored = step.combo, step.slider, step.typed, step.color;
    if step.click then MOCK.clicks[step.click] = true; end
    window.draw(app.state.settings, view, app.callbacks);
    assert(not step.click or not MOCK.clicks[step.click], 'The control is on the page: ' .. tostring(step.click));
    assert(not slider and not typed and not colored, 'The control is on the page.');
    MOCK.clicks = {};
end;
local LEARNED = { ['spell:253:2:crab'] = { samples = { 58, 60, 61 }, unit = 'Crab', at = 5 } };
local function begin(tab, setup)
    local s = defaults.tidy(defaults.make());
    s.window.open, s.window.tab = true, tab;
    for _, name in ipairs({ 'Duration overrides', 'Learned durations' }) do s.window.sections['Durations/' .. name] = true; end
    for _, name in ipairs({ 'Look and size', 'What to show', 'Buffs and debuffs', 'Recasts', 'Alerts', 'Move and lock', 'Profiles' }) do
        s.window.sections['Home/' .. name] = true;
    end
    s.durations.learned = copy(LEARNED);
    page._pick.kind, page._pick.query, page._pick.rule, page._pick.place = 'spell', '', nil, 1;
    app.state.settings = s;
    if setup then setup(s.durations, s); end
    frame();
    app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
    return copy(s);
end;
local function click(label) return { { click = label } }; end;
local function slide(label, value) return { { slider = { '##' .. label, value } } }; end;
local function pick(label, shown, value) return { { combo = '##' .. label, click = shown .. '##' .. value } }; end;
local function one(rule) return function(d) local value = require('core.durations').override(); for k, v in pairs(rule) do value[k] = v; end; d.overrides = { value }; end; end;
-- { name, setup, steps, check(durations, before), Undo label }
local rows = {
    { 'Add duration override', nil, { { typed = { '##Find what to override', '253' } }, { click = 'Add duration override' } },
        function(d) local r = d.overrides[1]; return #d.overrides == 1 and r.kind == 'spell' and r.id == 253 and r.mode == 'fixed' and r.seconds == 60; end,
        'Add duration override' },
    { 'Add an effect override', nil, { { combo = '##Override applies to', click = 'An effect##effect' }, { typed = { '##Find what to override', '4' } },
        { click = 'Add duration override' } }, function(d) return d.overrides[1].kind == 'effect' and d.overrides[1].id == 4; end, 'Add duration override' },
    { 'Override enabled', one({ id = 253 }), click('Override enabled'), function(d) return d.overrides[1].enabled == false; end, 'Override enabled' },
    { 'Change the time to', one({ id = 253 }), pick('Change the time to', 'Count up from when it landed', 'count_up'),
        function(d) return d.overrides[1].mode == 'count_up'; end, 'Change the time to' },
    { 'Fixed time', one({ id = 253 }), slide('Fixed time', 45), function(d) return d.overrides[1].seconds == 45; end, 'Fixed time' },
    { 'Seconds to add or take away', one({ id = 253, mode = 'add' }), slide('Seconds to add or take away', -12),
        function(d) return d.overrides[1].offset == -12; end, 'Seconds to add or take away' },
    { 'Percent of the estimate', one({ id = 253, mode = 'percent' }), slide('Percent of the estimate', 150),
        function(d) return d.overrides[1].percent == 150; end, 'Percent of the estimate' },
    { 'Only on a mob or player named', one({ id = 253 }), { { typed = { '##Only on a mob or player named', 'Goblin Smithy' } } },
        function(d) return d.overrides[1].name == 'Goblin Smithy'; end, 'Only on a mob or player named' },
    { 'Use my target\'s name', one({ id = 253 }), click('Use my target\'s name'), function(d) return d.overrides[1].name == 'Crab'; end, 'Only on a mob or player named' },
    { 'Remove selected override', one({ id = 253 }), click('Remove selected override'), function(d) return #d.overrides == 0; end, 'Remove duration override' },
    { 'Clear duration overrides', one({ id = 253 }), click('Clear duration overrides'), function(d) return #d.overrides == 0; end, 'Clear duration overrides' },
    { 'Learn from my casts', nil, click('Learn from my casts'), function(d) return d.learn == true; end, 'Learn from my casts' },
    { 'Casts before a learned time is used', function(d) d.learn = true; end, slide('Casts before a learned time is used', 5), function(d) return d.learn_samples == 5; end,
        'Casts before a learned time is used' },
    { 'Clear learned durations', nil, click('Clear learned durations'), function(d) return next(d.learned) == nil; end, 'Clear learned durations' },
    { 'Reset this page', function(d) d.learn, d.learn_samples = true, 7; one({ id = 253 })(d); end, click('Reset this page'),
        function(d) return d.learn == false and d.learn_samples == 3 and #d.overrides == 0 and d.learned['spell:253:2:crab']; end, 'Reset durations' },
};
local function outside(s)
    local value = copy(s);
    value.durations, value.window, value.profile_job = nil, nil, nil;
    return value;
end;
for _, row in ipairs(rows) do
    local before = begin('Durations', row[2]);
    local d_before = copy(app.state.settings.durations);
    for _, step in ipairs(row[3]) do frame(step); end
    local s = app.state.settings;
    assert(row[4](s.durations, d_before), 'The control writes its key: ' .. row[1]);
    assert(#app.state.history == 1 and app.state.history[1].label == row[5],
        'One Undo step named ' .. row[5] .. ': ' .. row[1] .. ' (' .. #app.state.history .. ', ' .. tostring(app.state.history[1] and app.state.history[1].label) .. ')');
    assert(custom.equal(outside(s), outside(before)), 'Nothing outside the timer durations changes: ' .. row[1]);
    local after = copy(s.durations);
    assert(app.callbacks.undo());
    assert(custom.equal(app.state.settings.durations, d_before), 'Undo puts it back: ' .. row[1]);
    assert(app.callbacks.redo());
    assert(custom.equal(app.state.settings.durations, after), 'Redo does it again: ' .. row[1]);
end;

-- The page lists each learned time: what made it, the effect, the mob, the middle time and how many casts.
begin('Durations');
MOCK.imgui_calls = {};
frame();
local listed = false;
for _, call in ipairs(MOCK.imgui_calls) do listed = listed or call[1] == 'TextWrapped' and call[2] == 'A spell with no name: Sleep I on Crab, 60s from 3 casts'; end;
assert(listed, 'The learned time is listed.');
-- Each override is named by its own kind, whatever the pick is on: an effect rule for Refresh (43) is not spell 43, which
-- has no name here, as this client has no spell names.
begin('Durations', function(d) d.overrides = { require('core.durations').override(), require('core.durations').override() };
    d.overrides[1].kind, d.overrides[1].id = 'effect', 43; d.overrides[2].id = 43; end);
local shown = {};
local begin_combo = imgui.BeginCombo;
imgui.BeginCombo = function(label, preview) if label == '##Override to edit' then shown[#shown + 1] = preview; end return begin_combo(label, preview); end;
for _, kind in ipairs({ 'spell', 'effect' }) do page._pick.kind, page._pick.rule, page._pick.place = kind, nil, 1; frame(); end;
page._pick.kind, page._pick.rule, page._pick.place = 'spell', nil, 2; frame();
imgui.BeginCombo = begin_combo;
assert(shown[1] == '1. Refresh / 60s' and shown[2] == '1. Refresh / 60s', 'The effect rule is named for its effect: ' .. tostring(shown[1]) .. ', ' .. tostring(shown[2]));
assert(shown[3] == '2. A spell with no name / 60s', 'The spell rule for its spell: ' .. tostring(shown[3]));

-- The offset slider runs evenly, 10 minutes either way, and typing reaches an hour either way. Fixed time still starts
-- at its own low end.
local ends = {};
local slide_float = imgui.SliderFloat;
imgui.SliderFloat = function(label, value, low, high, ...)
    ends[label] = { low, high };
    return slide_float(label, value, low, high, ...);
end;
begin('Durations', one({ id = 253, mode = 'add' }));
local offset = ends['##Seconds to add or take away'];
assert(offset and offset[1] == -600 and offset[2] == 600, 'The offset slider runs from -600 to 600: ' .. tostring(offset and offset[1]) .. ' to ' .. tostring(offset and offset[2]));
frame({ slider = { '##Seconds to add or take away', -3600 } });
assert(app.state.settings.durations.overrides[1].offset == -3600, 'Typing reaches an hour off.');
frame({ slider = { '##Seconds to add or take away', 4000 } });
assert(app.state.settings.durations.overrides[1].offset == 3600, 'And no more than an hour on.');
begin('Durations', one({ id = 253 }));
assert(ends['##Fixed time'][1] == 1 and ends['##Fixed time'][2] == 3600, 'Fixed time runs from 1 to an hour.');
imgui.SliderFloat = slide_float;

-- The pick stays on its override when the list changes around it. Undo puts copies in place of the rules, and the pick
-- goes to the copy of the one picked.
local previews = {};
imgui.BeginCombo = function(label, preview) previews[label] = preview; return begin_combo(label, preview); end;
begin('Durations', function(d)
    local make = require('core.durations').override;
    d.overrides = { make(), make(), make() };
    for index, id in ipairs({ 43, 33, 3 }) do d.overrides[index].kind, d.overrides[index].id = 'effect', id; end;
end);
frame({ click = 'Remove selected override' });
frame();
assert(#app.state.settings.durations.overrides == 2 and page.override(app.state.settings).id == 33, 'Fixture: the first is gone, and the next is picked.');
page._pick.rule, page._pick.place = nil, 2;
frame();
local picked = previews['##Override to edit'];
assert(page.override(app.state.settings).id == 3 and picked:find('^2%. '), 'Fixture: the last is picked: ' .. tostring(picked));
assert(app.callbacks.undo());
frame();
assert(page.override(app.state.settings).id == 3 and page._pick.place == 3, 'Undo puts the first back above it, and the pick stays on it.');
assert(previews['##Override to edit'] == '3. ' .. picked:sub(4), 'The list shows it at its new place: ' .. tostring(previews['##Override to edit']));
frame({ click = 'Override enabled' });
local rules = app.state.settings.durations.overrides;
assert(rules[3].enabled == false and rules[1].enabled and rules[2].enabled, 'What is edited is the override picked.');
assert(app.callbacks.undo() and app.callbacks.redo());
frame();
assert(page.override(app.state.settings).id == 3 and previews['##Override to edit'] == '3. [Off] ' .. picked:sub(4),
    'Undo and Redo leave it picked: ' .. tostring(previews['##Override to edit']));

-- What the list calls each override and the learned lines are made when the settings change, not every frame.
local format, made = string.format, {};
string.format = function(pattern, ...) made[pattern] = (made[pattern] or 0) + 1; return format(pattern, ...); end;
frame(); frame(); frame();
string.format = format;
assert(not made['%d. %s%s'] and not made['%s%s%s, %ds from %d %s'] and not made['%d learned time%s:'],
    'Frames with no change make none of it again.');
string.format = function(pattern, ...) made[pattern] = (made[pattern] or 0) + 1; return format(pattern, ...); end;
frame({ click = 'Override enabled' });
frame(); frame();
string.format = format;
assert(made['%d. %s%s'] == 3 and made['%d learned time%s:'] == 1, 'A change makes them once: ' .. tostring(made['%d. %s%s']));
assert(previews['##Override to edit'] == '3. ' .. picked:sub(4), 'And the list says what changed: ' .. tostring(previews['##Override to edit']));
imgui.BeginCombo = begin_combo;

-- The panels' light: its switch on the panel's Show tab and its glow and color on Look, each as one Undo step.
local panels = require('ui.panel_frame');
for _, entry in ipairs({ { 'Target', 'target', 'Light up buffs you can remove##frame' }, { 'Watched enemies', 'watch', 'Light up buffs you can remove##frame' },
    { 'Self debuffs', 'self_debuffs', 'Light up debuffs you can remove##frame' }, { 'Party', 'party', 'Light up debuffs you can remove##frame' } }) do
    -- The light is off at first: its switch turns it on, and its glow and color show once it is on.
    for _, control in ipairs({ { click = entry[3], key = 'dispel_light', value = true },
        { click = 'Glow around lit icons##frame', key = 'dispel_glow', value = false, lit = true },
        { color = { 'Light color##frame', { 0.2, 0.9, 1, 1 } }, key = 'dispel_color', lit = true } }) do
        panels.open(entry[2], control.lit and 'look' or 'show');
        begin('Display', control.lit and function(_, s) s.panels[entry[2]].dispel_light = true; end);
        app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
        local p = app.state.settings.panels[entry[2]];
        frame({ click = control.click, color = control.color });
        local written = control.key == 'dispel_color' and p.dispel_color[2] == 0.9 or p[control.key] == control.value;
        assert(written and #app.state.history == 1, entry[2] .. ' writes ' .. control.key .. ' in one step.');
        assert(app.callbacks.undo() and app.state.settings.panels[entry[2]][control.key] ~= nil
            and custom.equal(app.state.settings.panels[entry[2]][control.key], defaults.make().panels[entry[2]][control.key]), 'Undo puts ' .. control.key .. ' back.');
    end;
end;
-- Other panels have no light.
panels.open('self_buffs', 'show');
begin('Display');
MOCK.imgui_calls = {};
frame();
for _, call in ipairs(MOCK.imgui_calls) do
    assert(call[2] ~= 'Light up buffs you can remove##frame' and call[2] ~= 'Light up debuffs you can remove##frame', 'Self buffs has no light.');
end;

-- Learning through the app: a cast of yours on a mob and its wear-off add a sample, saved with the settings but not
-- an Undo step; Undo of an earlier change keeps it.
begin('Durations', function(d) d.learn, d.learned = true, {}; end);
app.callbacks.changed('before', 'Fixed time'); app.state.settings.durations.learn_samples = 4; app.callbacks.changed('after'); app.callbacks.save();
assert(#app.state.history == 1, 'Fixture: one change to undo.');
local function says(text)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'TextWrapped' and call[2] == text then return true; end; end;
    return false;
end;
MOCK.imgui_calls = {};
frame();
assert(says('Nothing learned yet.'), 'Fixture: nothing learned yet.');
local MOB = 0x1000100;
app.state.queue = { { kind = 'apply', entity_id = MOB, entity_name = 'Crab', effect = 2, spell = 253, action_category = 4, source = 1001,
    scope = 'enemy', duration = 60 } };
app.refresh(100);
app.state.queue = { { kind = 'remove', entity_id = MOB, effect = 2, source = 1001, scope = 'enemy', reason = 'Observed wearoff' } };
app.refresh(157.5);
assert(not app.state.settings.durations.learned['spell:253:2:crab'], 'The wear-off waits a second.');
app.refresh(158.6);
local entry = app.state.settings.durations.learned['spell:253:2:crab'];
assert(entry and entry.samples[1] == 57.5 and app.state.learned_at and not app.state.dirty,
    'The wear-off is learned and waits for the next save.');
assert(#app.state.history == 1, 'Learning makes no Undo step.');
MOCK.imgui_calls = {};
frame();
assert(says('1 learned time:') and says('A spell with no name: Sleep I on Crab, 58s from 1 cast'),
    'Learning counts as a change, so the page lists it at once.');
assert(app.callbacks.save() and store.read(app.state.path).durations.learned['spell:253:2:crab'].samples[1] == 57.5, 'It saves with the settings.');
assert(app.callbacks.undo() and app.state.settings.durations.learn_samples == 3, 'Undo takes back the change.');
assert(app.state.settings.durations.learned['spell:253:2:crab'].samples[1] == 57.5, 'And keeps what was learned since.');
assert(app.callbacks.redo() and app.state.settings.durations.learned['spell:253:2:crab'], 'Redo keeps it too.');
-- Clear learned durations, then Undo brings them back and Redo clears them again.
begin('Durations');
frame({ click = 'Clear learned durations' });
assert(next(app.state.settings.durations.learned) == nil, 'Cleared.');
assert(app.callbacks.undo() and app.state.settings.durations.learned['spell:253:2:crab'].samples[3] == 61, 'Undo brings them back.');
assert(app.callbacks.redo() and next(app.state.settings.durations.learned) == nil, 'Redo clears them again.');

-- Resets, profiles and shared presentation leave the learned times with this character.
begin('Durations', function(d) d.learn = true; one({ id = 253, seconds = 30 })(d); end);
assert(app.callbacks.reset('durations') and app.state.settings.durations.learned['spell:253:2:crab'] and #app.state.settings.durations.overrides == 0,
    '/vg reset durations keeps the learned times.');
assert(app.callbacks.reset('all') and app.state.settings.durations.learned['spell:253:2:crab'], 'Reset all keeps them.');
begin('Durations', function(d) one({ id = 253, seconds = 30 })(d); end);
assert(profiles.capture(app.state.settings).durations.learned == nil, 'A profile holds no learned times.');
assert(profiles.capture(app.state.settings).durations.overrides[1].seconds == 30, 'A profile holds the overrides.');
assert(app.callbacks.profile_save('Timers', false), 'Fixture: the profile saves.');
app.state.settings.durations.learned = { ['spell:259:2:crab'] = { samples = { 88 }, unit = 'Crab', at = 9 } };
app.state.settings.durations.overrides = {};
assert(app.callbacks.profile_load('Timers'), 'Fixture: the profile loads.');
assert(app.state.settings.durations.overrides[1].seconds == 30 and app.state.settings.durations.learned['spell:259:2:crab']
    and not app.state.settings.durations.learned['spell:253:2:crab'], 'A profile brings its overrides and keeps this character\'s learned times.');
local shared = profiles.capture_layout(app.state.settings, 'presentation');
assert(shared.presentation.durations and shared.presentation.durations.overrides[1].seconds == 30 and shared.presentation.durations.learned == nil,
    'Shared presentation carries the overrides, not the learned times.');
local other = defaults.tidy(defaults.make());
other.durations.learned = { ['spell:57:33:'] = { samples = { 178 }, unit = '', at = 2 } };
assert(profiles.apply_layout(other, shared, 'presentation'), 'Fixture: the shared presentation applies.');
assert(other.durations.overrides[1].seconds == 30 and other.durations.learned['spell:57:33:'] and not other.durations.learned['spell:259:2:crab'],
    'Another character takes the overrides and keeps its own learned times.');
local placement = defaults.tidy(defaults.make());
assert(profiles.apply_layout(placement, profiles.capture_layout(app.state.settings, 'placement'), 'placement') and #placement.durations.overrides == 0,
    'Placement sharing leaves the durations alone.');
-- /vg get and set reach them.
local event = { command = '/vg set durations.learn true' };
MOCK.fire('command', event);
assert(event.blocked and app.state.settings.durations.learn == true, '/vg set reaches the timer durations.');

-- The main page's Timer durations opens the page.
begin('Home');
frame({ click = 'Timer durations' });
assert(app.state.settings.window.tab == 'Durations' and #app.state.history == 0, 'The main page opens Timer durations.');
assert(#MOCK.commands == 0, 'The page sends no game commands.');
return 'Every Timer durations control is one Undo step, and the learned times stay out of Undo, profiles and sharing';
