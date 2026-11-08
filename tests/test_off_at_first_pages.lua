-- Off at first, the ready pulse, the recast tints, the party cooldown watch and the panels' buff light read off where
-- they are shown and each turns on as one Undo step, in the real settings window through vantage.lua. The main page's
-- switches, the Recasts panel, the Party cooldowns panel and the Target and Watched enemies panels show them off;
-- each switch turns its one on as one step named for it, which Undo takes back. In a list turns the watch on with the
-- list, and turning the watch off ends its samples, so the main page stops saying
-- they are on. Show a test pulse shows while the pulse is on,
-- and plays. /vg get says each is off, /vg set turns it on and /vg reset
-- turns it off again. While the watch is off a member's use is not kept and wakes no refresh.
local store = require('core.store');
local SNAP = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 5, self_known = true, self_effects = {},
    party = { { id = 1002, name = 'Ally', scope = 'party', zone = 102, slot = 1, group = 1 } },
    entities = { [1002] = { id = 1002, name = 'Ally', kind = 'player' } } };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(SNAP); end, accept = function() end,
    packet_size = function(e) return e.size or 0; end, self_timer_revision = function() return 0; end, party_revision = function() return 0; end,
    resolve = function(id) return { id = id, name = 'Entity ' .. id, kind = 'player' }; end };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, status = function() return { active = false }; end };
local imgui = require('imgui');
local defaults = require('ui.defaults');
local custom = require('core.customization');
local copy = store.copy;
local app = dofile(ADDON_DIR .. '/vantage.lua');
local window = require('ui.settings_window');
MOCK.fire('load'); app.refresh(0);

local combo;
imgui.BeginCombo = function(label) return label == combo; end;
local view = { rows = {}, context = { valid = true, job = 5, entities = {} } };
local function frame(step)
    step = step or {};
    combo = step.combo;
    if step.click then MOCK.clicks[step.click] = true; end
    MOCK.imgui_calls = {};
    window.draw(app.state.settings, view, app.callbacks);
    assert(not step.click or not MOCK.clicks[step.click], 'The control is on the page: ' .. tostring(step.click));
    MOCK.clicks = {};
end;
local panels = require('ui.panel_frame');
local on_frame = { Cooldowns = 'cooldown_list', Recasts = 'recasts' };
local function begin(tab, setup)
    local s = defaults.tidy(defaults.make());
    -- The recast marks show with a panel of their kind on.
    if tab == 'Recasts' then s.panels.spell_recasts.enabled, s.panels.ability_recasts.enabled = true, true; end;
    if on_frame[tab] then panels.open(on_frame[tab], 'show'); tab = 'Display'; end
    s.window.open, s.window.tab = true, tab;
    for _, name in ipairs({ 'Recasts/Recast tints', 'Recasts/Ready pulse' }) do
        s.window.sections[name] = true;
    end
    app.state.settings = s;
    if setup then setup(s); end
    frame();
    app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
    return copy(s);
end;
-- The state a checkbox was last drawn with, by its label.
local function shown(label)
    local value;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Checkbox' and (call[2] == label or call[2] == '##' .. label) then value = call[3][1]; end;
    end;
    return value;
end;

-- The main page, Recasts and Party cooldowns show each one off, and Beside the party list too while the watch is off.
begin('Home');
for _, label in ipairs({ 'Ready pulse##main_pulse', 'Party cooldowns##main_party_cooldowns' }) do
    assert(shown(label) == false, 'The main page shows ' .. label .. ' off: ' .. tostring(shown(label)));
end;
begin('Recasts');
for _, label in ipairs({ 'Spells while my MP is too low##frame', 'Spells while Silenced or Muted##frame', 'Abilities under Amnesia##frame' }) do
    assert(shown(label) == false, 'Recasts shows ' .. label .. ' off: ' .. tostring(shown(label)));
end;
begin('Cooldowns');
assert(shown('On##frame_display') == false and shown('In a list##frame_list') == false and shown('Show samples##frame') == false,
    'Party cooldowns shows the watch, its list and its samples off.');
assert(shown('Beside the party list##frame') == false, 'and Beside the party list off, as nothing shows there.');
frame({ click = 'Beside the party list##frame' });
assert(app.state.settings.party_cooldowns.enabled == true and app.state.settings.party_cooldowns.strips == true and #app.state.history == 1,
    'Ticking it turns the watch on with it, in one step.');
-- A list left on with the watch off shows off, since nothing shows.
begin('Cooldowns', function(s) s.party_cooldowns.list.enabled = true; end);
assert(shown('In a list##frame_list') == false, 'The list switch shows off while the watch is off.');
frame({ click = 'In a list##frame_list' });
local watched = app.state.settings.party_cooldowns;
assert(watched.enabled == true and watched.list.enabled == true and #app.state.history == 1,
    'Its switch then turns the watch on with the list, in one step.');
-- Turning the watch off ends its samples, as the other displays' switches end theirs, so the main page has none to end.
local function home_says(text)
    app.state.settings.window.tab = 'Home';
    frame();
    for _, call in ipairs(MOCK.imgui_calls) do
        for _, value in pairs(call) do if type(value) == 'string' and value:find(text, 1, true) then return true; end; end;
    end;
    return false;
end;
begin('Cooldowns', function(s) s.party_cooldowns.enabled, s.party_cooldowns.list.enabled, s.party_cooldowns.preview = true, true, true; end);
assert(home_says('End samples##main'), 'Fixture: the main page offers End samples.');
app.state.settings.window.tab = 'Display';
frame();
frame({ click = 'On##frame_display' });
watched = app.state.settings.party_cooldowns;
assert(watched.enabled == false and watched.preview == false and #app.state.history == 1 and app.state.history[1].label == 'Show this display',
    'Turning the watch off ends its samples, in one step named for it.');
frame();
assert(shown('Show samples##frame') == false, 'and the panel shows its samples off.');
assert(not home_says('End samples##main'), 'The main page has no samples left to end.');
assert(app.callbacks.undo() and app.state.settings.party_cooldowns.enabled and app.state.settings.party_cooldowns.preview,
    'Undo puts the watch and its samples back.');

-- Each switch turns its one on as one Undo step named for it, and nothing else changes; Undo takes it back.
local function click(label) return { { click = label } }; end;
-- { page, control, steps, check(settings), Undo label, key }
local rows = {
    { 'Recasts', 'Spells while my MP is too low', click('Spells while my MP is too low##frame'), function(s) return s.recast_tints.mp == true; end, 'Spells while my MP is too low', 'recast_tints' },
    { 'Recasts', 'Spells while Silenced or Muted', click('Spells while Silenced or Muted##frame'), function(s) return s.recast_tints.spell_lock == true; end, 'Spells while Silenced or Muted', 'recast_tints' },
    { 'Recasts', 'Abilities under Amnesia', click('Abilities under Amnesia##frame'), function(s) return s.recast_tints.ability_lock == true; end, 'Abilities under Amnesia', 'recast_tints' },
    { 'Cooldowns', 'Show', click('On##frame_display'), function(s) return s.party_cooldowns.enabled == true and s.party_cooldowns.strips == true; end, 'Show this display', 'party_cooldowns' },
    { 'Cooldowns', 'In a list', click('In a list##frame_list'),
        function(s) return s.party_cooldowns.enabled == true and s.party_cooldowns.list.enabled == true; end, 'In a list', 'party_cooldowns' },
    { 'Home', 'Ready pulse', click('Ready pulse##main_pulse'), function(s) return s.ready_pulse.enabled == true; end, 'Ready pulse', 'ready_pulse' },
    { 'Home', 'Party cooldowns', click('Party cooldowns##main_party_cooldowns'),
        function(s) return s.party_cooldowns.enabled == true and s.party_cooldowns.list.enabled == true; end, 'Party cooldowns', 'party_cooldowns' },
};
local function outside(s, key)
    local value = copy(s);
    value[key], value.window, value.profile_job = nil, nil, nil;
    return value;
end;
for _, row in ipairs(rows) do
    local before = begin(row[1]);
    local key = row[6];
    local own_before = copy(app.state.settings[key]);
    for _, step in ipairs(row[3]) do frame(step); end
    local s = app.state.settings;
    assert(row[4](s), 'The control turns it on: ' .. row[1] .. ' / ' .. row[2]);
    assert(#app.state.history == 1 and app.state.history[1].label == row[5],
        'One Undo step named ' .. row[5] .. ': ' .. row[2] .. ' (' .. #app.state.history .. ', ' .. tostring(app.state.history[1] and app.state.history[1].label) .. ')');
    assert(custom.equal(outside(s, key), outside(before, key)), 'Nothing else changes: ' .. row[2]);
    frame();
    assert(shown(row[3][1].click) == true, 'Its control now shows on: ' .. row[2]);
    assert(app.callbacks.undo());
    assert(custom.equal(app.state.settings[key], own_before), 'Undo turns it off again: ' .. row[2]);
end;

-- The panels' light: the switch on the panel's Show tab turns it on in one step, and then the glow and its color show on
-- Look, the glow on.
for _, entry in ipairs({ { 'Target', 'target', 'Light up buffs you can remove' }, { 'Watched enemies', 'watch', 'Light up buffs you can remove' },
    { 'Self debuffs', 'self_debuffs', 'Light up debuffs you can remove' }, { 'Party', 'party', 'Light up debuffs you can remove' } }) do
    local tick, glow = entry[3] .. '##frame', 'Glow around lit icons##frame';
    panels.open(entry[2], 'look');
    begin('Display');
    assert(shown(glow) == nil, entry[1] .. ' has no glow switch while the light is off.');
    panels.open(entry[2], 'show');
    frame();
    assert(shown(tick) == false, entry[1] .. ' shows the light off.');
    app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
    frame({ click = tick });
    local p = app.state.settings.panels[entry[2]];
    assert(p.dispel_light == true and #app.state.history == 1 and app.state.history[1].label == entry[3],
        entry[1] .. ': the switch turns the light on in one step.');
    frame();
    assert(shown(tick) == true, entry[1] .. ': lit.');
    panels.open(entry[2], 'look');
    frame();
    assert(shown(glow) == true, entry[1] .. ': with its glow on.');
    assert(app.callbacks.undo() and app.state.settings.panels[entry[2]].dispel_light == false, entry[1] .. ': Undo turns it off.');
end;

-- Off, the Ready pulse fold has its tick and no test. On, a test pulse plays and is no Undo step.
begin('Recasts');
assert(shown('Pulse when a long recast is ready##frame') == false, 'The fold has the tick, off.');
for _, call in ipairs(MOCK.imgui_calls) do assert(call[2] ~= 'Show a test pulse##frame', 'No test while the pulse is off.'); end;
begin('Recasts', function(s) s.ready_pulse.enabled = true; end);
frame({ click = 'Show a test pulse##frame' });
assert(#app.state.history == 0 and #app.state.view.pulses >= 1, 'With the pulse on, a test pulse is no Undo step.');

-- /vg get, /vg set and /vg reset.
local function command(text) local event = { command = text }; MOCK.fire('command', event); return event; end;
begin('Home');
for _, path in ipairs({ 'ready_pulse.enabled', 'recast_tints.mp', 'recast_tints.spell_lock', 'recast_tints.ability_lock',
    'party_cooldowns.enabled', 'panels.target.dispel_light', 'panels.watch.dispel_light' }) do
    command('/vg get ' .. path);
    assert(MOCK.printed[#MOCK.printed]:find(path .. ' = false', 1, true), '/vg get says ' .. path .. ' is off: ' .. MOCK.printed[#MOCK.printed]);
    command('/vg set ' .. path .. ' true');
    command('/vg get ' .. path);
    assert(MOCK.printed[#MOCK.printed]:find(path .. ' = true', 1, true), '/vg set turns ' .. path .. ' on: ' .. MOCK.printed[#MOCK.printed]);
end;
local s = app.state.settings;
assert(s.ready_pulse.enabled and s.recast_tints.mp and s.party_cooldowns.enabled and s.panels.target.dispel_light, 'Fixture: each is on.');
for _, scope in ipairs({ 'ready_pulse', 'recast_tints', 'party_cooldowns', 'target', 'watch' }) do assert(app.callbacks.reset(scope)); end;
s = app.state.settings;
assert(s.ready_pulse.enabled == false and s.recast_tints.mp == false and s.recast_tints.spell_lock == false and s.recast_tints.ability_lock == false
    and s.party_cooldowns.enabled == false and s.panels.target.dispel_light == false and s.panels.watch.dispel_light == false,
    'A reset turns each off again.');

-- While the watch is off, a member's use is not kept and wakes no refresh; on, it wakes one and is kept.
local events = MOCK.events.packet_in;
local handler = events and events.vantage_packet_in;
assert(handler, 'Fixture: the packet handler.');
local observer = require('core.observer');
local real = observer.read;
observer.read = function() return { { kind = 'cooldown', entity_id = 1002, ability = 18, entity_name = 'Ally', scope = 'party' } }; end;
app.state.wake = false;
handler({ id = 0x028, size = 64, data = '', data_raw = {} });
assert(not app.state.wake, 'A use seen while the watch is off wakes no refresh.');
app.refresh(1);
assert(next(app.cooldowns.members) == nil and #app.state.view.cooldowns == 0, 'and is not kept.');
app.state.settings.party_cooldowns.enabled = true;
handler({ id = 0x028, size = 64, data = '', data_raw = {} });
assert(app.state.wake, 'With the watch on, a use wakes a refresh.');
app.refresh(2);
assert(app.cooldowns.members[1002] and #app.state.view.cooldowns == 1, 'and is kept.');
observer.read = real;
MOCK.fire('unload');
return 'Each of the four reads off where it is shown and turns on as one Undo step';
