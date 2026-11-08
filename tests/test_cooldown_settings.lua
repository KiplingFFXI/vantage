-- The recast tints and ready pulse controls on the Recasts panel, the Party cooldowns panel, and their main page switches, in the real
-- settings window through vantage.lua. Each control writes its own key as one Undo step named for it; Undo puts it
-- back and Redo does it again. Search finds them before a page is opened. Profiles and shared presentation carry them
-- but leave each character its own locks and samples, and a use a member makes reaches the watch, not the tracker.
local store = require('core.store');
local SNAP = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {},
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
local profiles = require('core.profiles');
local copy = store.copy;
local app = dofile(ADDON_DIR .. '/vantage.lua');
local window = require('ui.settings_window');
MOCK.fire('load'); app.refresh(0);

local function found(query, tab, label)
    for _, result in ipairs(window.search(query)) do if result.tab == tab and result.label == label then return true; end end
    return false;
end;
-- The pulse is off at first, so what it hides finds the tick that turns it on, and a mark needs a recast display on.
for _, entry in ipairs({ { "Tint spells I can't afford", 'Display', 'Show this display' },
    { 'Lock spells while Silenced or Muted', 'Display', 'Show this display' },
    { 'Ready pulse', 'Display' }, { 'Shortest recast that pulses', 'Display', 'Pulse when a long recast is ready' }, { 'Never pulse for', 'Display', 'Pulse when a long recast is ready' },
    { 'silenced', 'Display', 'Recast marks and the ready pulse' }, { 'Show party cooldown list', 'Display', 'In a list' },
    { 'Benediction', 'Display' }, { 'two-hour', 'Display', 'Party cooldowns: two-hours and key abilities' },
    { 'Turn on Party list buffs', 'Display', 'Beside the party list' }, { 'Show beside your party\'s window', 'Display', 'Beside the party list' },
    { 'Turn on Overhead icons', 'Display', 'Over heads' },
    { 'Show party members over heads', 'Display', 'Over heads' },
    { 'Party cooldowns', 'Home' }, { 'Ready pulse', 'Home' }, { 'Lock abilities under Amnesia', 'Display', 'Show this display' } }) do
    assert(found(entry[1], entry[2], entry[3] or entry[1]), 'Search finds ' .. (entry[3] or entry[1]) .. ' on ' .. entry[2] .. ' before it is drawn.');
end;

local combo, slider, colored;
imgui.BeginCombo = function(label) return label == combo; end;
imgui.SliderFloat = function(label, value)
    if slider and slider[1] == label then value[1], slider = slider[2], nil; return true; end
    return false;
end;
imgui.ColorEdit4 = function(label, value)
    if colored and colored[1] == label then for i = 1, 4 do value[i] = colored[2][i]; end; colored = nil; return true; end
    return false;
end;
app.callbacks.recast_catalog = function(kind) return (not kind or kind == 'spell') and { { id = 10100, name = 'Cure', kind = 'spell' } } or {}; end;
local tested = 0;
local test_pulse = app.callbacks.test_pulse;
app.callbacks.test_pulse = function() tested = tested + 1; return test_pulse(); end;
local view = { rows = {}, context = { valid = true, job = 3, entities = {} } };
local function frame(step)
    step = step or {};
    combo, slider, colored = step.combo, step.slider, step.color;
    if step.click then MOCK.clicks[step.click] = true; end
    window.draw(app.state.settings, view, app.callbacks);
    assert(not step.click or not MOCK.clicks[step.click], 'The control is on the page: ' .. tostring(step.click));
    assert(not slider and not colored, 'The control is on the page.');
    MOCK.clicks = {};
end;
local function begin(tab, setup)
    local s = defaults.tidy(defaults.make());
    local id, place = 'recasts', tab:match('^Display/(.+)$');
    if not place then id, place = 'cooldown_list', tab:match('^Cooldowns/(.+)$'); end
    if place then tab = 'Display'; require('ui.panel_frame').open(id, place); end
    -- The tints, the pulse and the watch are off at first; they start on here, so each switch below turns one off. The
    -- marks show with a panel of their kind on.
    s.recast_tints.mp, s.recast_tints.spell_lock, s.recast_tints.ability_lock = true, true, true;
    s.panels.spell_recasts.enabled, s.panels.ability_recasts.enabled = true, true;
    s.ready_pulse.enabled, s.party_cooldowns.enabled = true, true;
    s.window.open, s.window.tab = true, tab;
    for _, name in ipairs({ 'Recasts/Recast tints', 'Recasts/Ready pulse' }) do s.window.sections[name] = true; end
    app.state.settings = s;
    if setup then setup(s); end
    frame();
    app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
    return copy(s);
end;
local function click(label) return { { click = label } }; end;
local function slide(label, value) return { { slider = { '##' .. label, value } } }; end;
local function pick(label, shown, value) return { { combo = '##' .. label, click = shown .. '##' .. value } }; end;
local function paint(label, value) return { { color = { label, value } } }; end;
local function listed(s) s.party_cooldowns.list.enabled = true; end;
local function unlocked(s) s.party_cooldowns.list.enabled, s.party_cooldowns.list.locked = true, false; end;
-- { page, name, setup, steps, check(settings), Undo label, key }
local rows = {
    { 'Display/show', 'Spells while my MP is too low', nil, click('Spells while my MP is too low##frame'), function(s) return s.recast_tints.mp == false; end, 'Spells while my MP is too low', 'recast_tints' },
    { 'Display/show', 'MP mark color', nil, paint('Color##frame_mp', { 1, 0, 0, 0.5 }), function(s) return s.recast_tints.mp_color[1] == 1 and s.recast_tints.mp_color[2] == 0; end, 'MP mark color', 'recast_tints' },
    { 'Display/show', 'Spells while Silenced or Muted', nil, click('Spells while Silenced or Muted##frame'), function(s) return s.recast_tints.spell_lock == false; end, 'Spells while Silenced or Muted', 'recast_tints' },
    { 'Display/show', 'Spell lock color', nil, paint('Color##frame_spell_lock', { 0, 0, 1, 1 }), function(s) return s.recast_tints.spell_lock_color[3] == 1; end, 'Spell lock color', 'recast_tints' },
    { 'Display/show', 'Abilities under Amnesia', nil, click('Abilities under Amnesia##frame'), function(s) return s.recast_tints.ability_lock == false; end, 'Abilities under Amnesia', 'recast_tints' },
    { 'Display/show', 'Ability lock color', nil, paint('Color##frame_ability_lock', { 0, 1, 0, 1 }), function(s) return s.recast_tints.ability_lock_color[2] == 1; end, 'Ability lock color', 'recast_tints' },
    { 'Display/show', 'Only recasts of at least', nil, slide('frame_Only recasts of at least', 300), function(s) return s.ready_pulse.min_seconds == 300; end, 'Only recasts of at least', 'ready_pulse' },
    { 'Display/show', 'Start early', nil, slide('frame_Start early', 5), function(s) return s.ready_pulse.early == 5; end, 'Start early', 'ready_pulse' },
    { 'Display/show', 'Pulse spot', nil, pick('frame_Pulse spot', 'A spot of its own', 'screen'), function(s) return s.ready_pulse.spot == 'screen'; end, 'Pulse spot', 'ready_pulse' },
    { 'Display/show', 'Pulse size', nil, slide('frame_Pulse size', 96), function(s) return s.ready_pulse.size == 96; end, 'Pulse size', 'ready_pulse' },
    { 'Display/show', 'Pulse color', nil, paint('Pulse color##frame', { 0, 1, 1, 1 }), function(s) return s.ready_pulse.color[1] == 0; end, 'Pulse color', 'ready_pulse' },
    { 'Display/show', 'Pulse for', nil, slide('frame_Pulse for', 2.5), function(s) return s.ready_pulse.length == 2.5; end, 'Pulse for', 'ready_pulse' },
    { 'Display/place', 'Lock pulse spot', function(s) s.ready_pulse.spot = 'screen'; end, click('Locked##frame_pulse'), function(s) return s.ready_pulse.locked == false; end, 'Lock pulse spot', 'ready_pulse' },
    { 'Display/place', 'Pulse spot across', function(s) s.ready_pulse.spot = 'screen'; end, slide('frame_Across_pulse', 500), function(s) return s.ready_pulse.x == 500; end, 'Pulse spot across', 'ready_pulse' },
    { 'Display/place', 'Pulse spot down', function(s) s.ready_pulse.spot = 'screen'; end, slide('frame_Down_pulse', 90), function(s) return s.ready_pulse.y == 90; end, 'Pulse spot down', 'ready_pulse' },
    { 'Display/show', 'Never pulse for', nil, { { combo = '##Never pulse for', click = 'Cure##effect_10100' } },
        function(s) return s.ready_pulse.ignore[10100] == true; end, 'Never pulse for Cure', 'ready_pulse' },
    { 'Display/show', 'Pulse again', function(s) s.ready_pulse.ignore[10100] = true; end, click('Pulse again'),
        function(s) return next(s.ready_pulse.ignore) == nil; end, 'Pulse again for Cure', 'ready_pulse' },
    { 'Cooldowns/show', 'In a list', nil, click('In a list##frame_list'), function(s) return s.party_cooldowns.list.enabled; end, 'In a list', 'party_cooldowns' },
    { 'Cooldowns/show', 'Show samples', listed, click('Show samples##frame'),
        function(s) return s.party_cooldowns.preview and s.party_cooldowns.list.enabled; end, 'Show samples', 'party_cooldowns' },
    { 'Cooldowns/show', 'Locked', listed, click('Locked##frame'), function(s) return s.party_cooldowns.list.locked == false; end, 'Locked', 'party_cooldowns' },
    { 'Cooldowns/show', 'Show', nil, click('On##frame_display'), function(s) return s.party_cooldowns.enabled == false; end, 'Show this display', 'party_cooldowns' },
    { 'Cooldowns/show', 'Beside the party list', nil, click('Beside the party list##frame'), function(s) return s.party_cooldowns.strips == false; end, 'Beside the party list', 'party_cooldowns' },
    { 'Cooldowns/show', 'Over heads', nil, click('Over heads##frame'), function(s) return s.party_cooldowns.overhead == true; end, 'Over heads', 'party_cooldowns' },
    -- Every group off, as it starts when each was unticked: turning them on brings Your party back too.
    { 'Cooldowns/show', 'Turn on Party list buffs', function(s) s.party_ui.strips.party, s.party_ui.strips.alliance1, s.party_ui.strips.alliance2 = false, false, false; end,
        click('Turn on Party list buffs##frame'), function(s) return s.party_ui.enabled and s.party_ui.strips.party; end, 'Turn on Party list buffs', 'party_ui' },
    { 'Cooldowns/show', 'Show beside your party\'s window', function(s)
        s.party_ui.enabled, s.party_ui.strips.party, s.party_ui.strips.alliance1, s.party_ui.strips.alliance2 = true, false, false, false;
    end, click('Show beside your party\'s window##frame'), function(s) return s.party_ui.strips.party; end, 'Show beside your party\'s window', 'party_ui' },
    { 'Cooldowns/show', 'Turn on Overhead icons', function(s) s.party_cooldowns.overhead = true; end, click('Turn on Overhead icons##frame'),
        function(s) return s.overhead.enabled; end, 'Turn on Overhead icons', 'overhead' },
    { 'Cooldowns/show', 'Show party members over heads', function(s)
        s.party_cooldowns.overhead, s.overhead.enabled, s.overhead.units.party, s.overhead.units.alliance = true, true, false, false;
    end, click('Show party members over heads##frame'), function(s) return s.overhead.units.party; end, 'Show party members over heads', 'overhead' },
    { 'Cooldowns/show', 'Benediction', nil, click('Benediction##frame_watch_18'), function(s) return s.party_cooldowns.ignore[18] == true; end, 'Benediction', 'party_cooldowns' },
    { 'Cooldowns/show', 'Watch every ability', function(s) s.party_cooldowns.ignore[18] = true; end, click('Watch every ability##frame'),
        function(s) return next(s.party_cooldowns.ignore) == nil; end, 'Watch every ability', 'party_cooldowns' },
    { 'Cooldowns/show', 'Show its heading', listed, click('Show its heading##frame'), function(s) return s.party_cooldowns.list.show_heading == false; end, 'Show its heading', 'party_cooldowns' },
    { 'Cooldowns/show', 'Sort', listed, pick('frame_Sort', 'Member name', 'name'), function(s) return s.party_cooldowns.list.sort == 'name'; end, 'Sort', 'party_cooldowns' },
    { 'Cooldowns/show', 'Most shown', listed, slide('frame_Most shown', 5), function(s) return s.party_cooldowns.list.max_rows == 5; end, 'Most shown', 'party_cooldowns' },
    { 'Cooldowns/place', 'Width', unlocked, slide('frame_Width', 420), function(s) return s.party_cooldowns.list.width == 420; end, 'Width', 'party_cooldowns' },
    { 'Cooldowns/place', 'Tallest', unlocked, slide('frame_Tallest', 30), function(s) return s.party_cooldowns.list.height == 60; end, 'Tallest', 'party_cooldowns' },
    { 'Cooldowns/place', 'Put it back where it started', function(s) unlocked(s); s.party_cooldowns.list.x = 600; end, click('Put it back where it started##frame'),
        function(s) return s.party_cooldowns.list.x == 40; end, 'Put Party cooldowns list back', 'party_cooldowns' },
    { 'Cooldowns/filters', 'WHM', listed, click('WHM##frame_list_job'), function(s) return s.party_cooldowns.list.jobs[3] == true; end, 'WHM', 'party_cooldowns' },
    { 'Cooldowns/filters', 'Clear list filters', function(s) listed(s); s.party_cooldowns.list.jobs[3], s.party_cooldowns.list.abilities[18] = true, true; end, click('Clear list filters##frame'),
        function(s) return next(s.party_cooldowns.list.jobs) == nil and next(s.party_cooldowns.list.abilities) == nil; end, 'Clear list filters', 'party_cooldowns' },
    { 'Cooldowns/show', 'Reset this display', function(s) s.party_cooldowns.strips, s.party_cooldowns.ignore[18] = false, true; end,
        { { click = 'Reset this display##frame' }, { click = 'Reset##look_frame_reset_cooldown_list' } },
        function(s) return s.party_cooldowns.strips and next(s.party_cooldowns.ignore) == nil; end, 'Reset Party cooldowns', 'party_cooldowns' },
    { 'Home', 'Party cooldowns', nil, click('Party cooldowns##main_party_cooldowns'), function(s) return s.party_cooldowns.enabled == false; end, 'Party cooldowns', 'party_cooldowns' },
    -- With nowhere to show them, turning them on shows the list.
    { 'Home', 'Party cooldowns on', function(s) s.party_cooldowns.enabled, s.party_cooldowns.strips = false, false; end, click('Party cooldowns##main_party_cooldowns'),
        function(s) return s.party_cooldowns.enabled and s.party_cooldowns.list.enabled; end, 'Party cooldowns', 'party_cooldowns' },
    -- Beside the party list with no group ticked is nowhere too, and so is over heads with nobody to show them on.
    { 'Home', 'Party cooldowns on, no group ticked', function(s)
        s.party_cooldowns.enabled, s.party_ui.enabled, s.party_ui.strips.party, s.party_ui.strips.alliance1, s.party_ui.strips.alliance2 = false, true, false, false, false;
    end, click('Party cooldowns##main_party_cooldowns'), function(s) return s.party_cooldowns.enabled and s.party_cooldowns.list.enabled; end, 'Party cooldowns', 'party_cooldowns' },
    { 'Home', 'Party cooldowns on, over heads for nobody', function(s)
        s.party_cooldowns.enabled, s.party_cooldowns.strips, s.party_cooldowns.overhead = false, false, true;
        s.overhead.enabled, s.overhead.units.party, s.overhead.units.alliance = true, false, false;
    end, click('Party cooldowns##main_party_cooldowns'), function(s) return s.party_cooldowns.enabled and s.party_cooldowns.list.enabled; end, 'Party cooldowns', 'party_cooldowns' },
    { 'Home', 'Ready pulse', nil, click('Ready pulse##main_pulse'), function(s) return s.ready_pulse.enabled == false; end, 'Ready pulse', 'ready_pulse' },
    { 'Home', 'End samples', function(s) s.party_cooldowns.list.enabled, s.party_cooldowns.preview = true, true; end, click('End samples##main'),
        function(s) return not s.party_cooldowns.preview and s.party_cooldowns.list.enabled; end, 'End samples', 'party_cooldowns' },
};
local function outside(s, key)
    local value = copy(s);
    value[key], value.window, value.profile_job = nil, nil, nil;
    return value;
end;
for _, row in ipairs(rows) do
    local before = begin(row[1], row[3]);
    local key = row[7];
    local own_before = copy(app.state.settings[key]);
    for _, step in ipairs(row[4]) do frame(step); end
    local s = app.state.settings;
    assert(row[5](s), 'The control writes its key: ' .. row[2]);
    assert(#app.state.history == 1 and app.state.history[1].label == row[6],
        'One Undo step named ' .. row[6] .. ': ' .. row[2] .. ' (' .. #app.state.history .. ', ' .. tostring(app.state.history[1] and app.state.history[1].label) .. ')');
    assert(custom.equal(outside(s, key), outside(before, key)), 'Nothing else changes: ' .. row[2]);
    local after = copy(s[key]);
    assert(app.callbacks.undo());
    assert(custom.equal(app.state.settings[key], own_before), 'Undo puts it back: ' .. row[2]);
    assert(app.callbacks.redo());
    assert(custom.equal(app.state.settings[key], after), 'Redo does it again: ' .. row[2]);
end;
-- A place ticked with nothing to draw on says so on the Show tab, in the problem color, with the button that puts it
-- right. Anything else needs no warning.
do
    local strip = { 'Party list buffs is off, so nothing shows beside the party list.', 'Turn on Party list buffs##frame' };
    local strip_unset = { 'Party list buffs has no group ticked, so nothing shows beside the party list.', 'Show beside your party\'s window##frame' };
    local heads_off = { 'Overhead icons is off, so nothing shows over heads.', 'Turn on Overhead icons##frame' };
    local heads_unset = { 'Overhead icons isn\'t set to show party or alliance members.', 'Show party members over heads##frame' };
    -- The warnings the page shows, each with the call before its line.
    local function warned(setup)
        begin('Cooldowns/show', setup);
        MOCK.imgui_calls = {};
        frame();
        local seen = {};
        for _, warning in ipairs({ strip, strip_unset, heads_off, heads_unset }) do
            local line, button;
            for index, call in ipairs(MOCK.imgui_calls) do
                if call[1] == 'TextWrapped' and call[2] == warning[1] then line = MOCK.imgui_calls[index - 1]; end;
                if call[1] == 'Button' and call[2] == warning[2] then button = true; end;
            end;
            assert((line ~= nil) == (button == true), 'The line and its button go together: ' .. warning[1]);
            seen[warning] = line;
        end;
        return seen;
    end;
    local function shows(setup, ...)
        local seen, expected = warned(setup), { ... };
        for _, warning in ipairs(expected) do assert(seen[warning], 'It says: ' .. warning[1]); seen[warning] = nil; end;
        local left = next(seen);
        assert(not left, 'It has no call to say: ' .. (left and left[1] or ''));
    end;
    local look;
    local color = warned(function(s) look = require('ui.theme').window(s); end)[strip];
    assert(color and color[1] == 'PushStyleColor' and custom.equal(color[3], look.problem_messages), 'The warning takes the problem color.');
    assert(not custom.equal(look.problem_messages, look.notes), 'Fixture: that is not the color of a note.');
    shows(nil, strip);
    shows(function(s) s.party_ui.enabled = true; end);
    shows(function(s) s.party_cooldowns.enabled = false; end);
    shows(function(s) s.party_cooldowns.strips = false; end);
    shows(function(s) s.party_cooldowns.list.enabled = true; end, strip);
    local function groups(enabled, party, alliance1, alliance2)
        return function(s) s.party_ui.enabled, s.party_ui.strips.party, s.party_ui.strips.alliance1, s.party_ui.strips.alliance2 = enabled, party, alliance1, alliance2; end;
    end;
    shows(groups(true, false, false, false), strip_unset);
    shows(groups(false, false, false, false), strip);
    shows(groups(true, false, true, false));
    shows(groups(true, false, false, true));
    local function heads(enabled, party, alliance)
        return function(s)
            s.party_cooldowns.strips, s.party_cooldowns.overhead = false, true;
            s.overhead.enabled, s.overhead.units.party, s.overhead.units.alliance = enabled, party, alliance;
        end;
    end;
    shows(heads(false, true, true), heads_off);
    shows(heads(false, false, false), heads_off);
    shows(heads(true, false, false), heads_unset);
    shows(heads(true, true, false));
    shows(heads(true, false, true));
    shows(function(s) heads(false, true, true)(s); s.party_cooldowns.enabled = false; end);
    shows(function(s) heads(false, true, true)(s); s.party_cooldowns.strips = true; end, strip, heads_off);
end;

-- Filters has the 18 job ticks and no ability ticks, and a saved ability filter stays in force with no tick for it.
begin('Cooldowns/filters', function(s) listed(s); s.party_cooldowns.list.abilities[18] = true; end);
MOCK.imgui_calls = {};
frame();
do
    local job_ticks, ability_ticks, watch_ticks, lines = 0, 0, 0, {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Checkbox' and type(call[2]) == 'string' then
            if call[2]:find('##frame_list_job', 1, true) then job_ticks = job_ticks + 1; end
            if call[2]:find('_ability_', 1, true) then ability_ticks = ability_ticks + 1; end
        elseif call[1] == 'TextWrapped' then lines[call[2]] = true; end
    end
    assert(job_ticks == 18 and ability_ticks == 0, 'Filters has one tick for each job and none for an ability: ' .. job_ticks .. ' ' .. ability_ticks);
    assert(not lines.Jobs and not lines.Abilities, 'With one kind of tick the tab needs no line naming it.');
    local watch, list = require('core.party_cooldowns'), app.state.settings.party_cooldowns.list;
    assert(watch.listed(list, { job = 3, ability = 18 }) and not watch.listed(list, { job = 3, ability = 74 }), 'A saved ability filter keeps working.');
    begin('Cooldowns/show');
    MOCK.imgui_calls = {};
    frame();
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Checkbox' and tostring(call[2]):find('_watch_', 1, true) then watch_ticks = watch_ticks + 1; end
    end
    assert(watch_ticks == #watch.list, 'Abilities to watch keeps a tick for each ability.');
    -- Each job name is on the left of its first tick, with the first ticks in one column.
    local names, column = {}, nil;
    for index, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'TextUnformatted' and #tostring(call[2]) == 3 then
            local at, gap = index + 1, nil;
            while MOCK.imgui_calls[at] and MOCK.imgui_calls[at][1] ~= 'Checkbox' do
                if MOCK.imgui_calls[at][1] == 'SameLine' then gap = MOCK.imgui_calls[at][3]; end
                at = at + 1;
            end
            if gap and tostring(MOCK.imgui_calls[at][2]):find('_watch_', 1, true) then
                names[#names + 1] = call[2];
                column = column or #call[2] * 8 + gap;
                assert(gap > 0 and #call[2] * 8 + gap == column, call[2] .. ': the ticks start in the column.');
                assert(MOCK.imgui_calls[index - 1][1] == 'AlignTextToFramePadding', call[2] .. ': the name lines up with its ticks.');
            end
        end
    end
    assert(#names == 18, 'All 18 job names sit beside their ticks: ' .. #names);
end
-- The test pulse plays one pulse and changes no setting.
begin('Display/show');
frame({ click = 'Show a test pulse##frame' });
assert(tested == 1 and #app.state.view.pulses == 1 and #app.state.history == 0, 'Show a test pulse plays one and is no Undo step.');

-- /vg set and /vg get reach the new settings; the samples turn the list on.
local function command(text) local event = { command = text }; MOCK.fire('command', event); return event; end;
begin('Home');
command('/vg set party_cooldowns.preview true');
assert(app.state.settings.party_cooldowns.preview and app.state.settings.party_cooldowns.list.enabled, '/vg set of the samples turns the list on.');
command('/vg set recast_tints.mp false');
assert(app.state.settings.recast_tints.mp == false, '/vg set reaches the recast tints.');
command('/vg set ready_pulse.min_seconds 120');
assert(app.state.settings.ready_pulse.min_seconds == 120, '/vg set reaches the ready pulse.');
-- The tints are off at first, so the reset turns off the two that began on here.
assert(app.callbacks.reset('recast_tints') and custom.equal(app.state.settings.recast_tints, require('core.recast_tints').make()),
    '/vg reset recast_tints restores the tints.');

-- Shared presentation carries the settings, and each character keeps its own locks and samples.
local s = app.state.settings;
s.party_cooldowns.list.locked, s.party_cooldowns.preview, s.ready_pulse.locked = false, true, false;
-- The tints are off at first, so on is the saved choice the presentation must carry.
s.party_cooldowns.list.width, s.ready_pulse.size, s.recast_tints.mp = 333, 80, true;
local shared = profiles.capture_layout(s, 'presentation');
local content = shared.presentation;
assert(content.party_cooldowns.list.width == 333 and content.ready_pulse.size == 80 and content.recast_tints.mp == true,
    'Shared presentation carries the cooldown list, the pulse and the tints.');
assert(content.party_cooldowns.list.locked == nil and content.ready_pulse.locked == nil and content.party_cooldowns.preview == nil,
    'but not the locks or the samples.');
local other = defaults.tidy(defaults.make());
local applied = profiles.apply_layout(other, shared, 'presentation');
assert(applied and other.party_cooldowns.list.width == 333 and other.party_cooldowns.list.locked and other.ready_pulse.locked
    and not other.party_cooldowns.preview, 'Another character takes them with its own locks and samples.');
local saved = profiles.capture(s);
assert(saved.party_cooldowns.preview == false and saved.party_cooldowns.list.width == 333, 'A profile saves the settings without the samples.');

-- A member's use reaches the watch at the packet, not the tracker, and shows from the next refresh.
local queued = #app.state.queue;
local observer = require('core.observer');
local events = MOCK.events.packet_in;
local handler = events and events.vantage_packet_in;
assert(handler, 'Fixture: the packet handler.');
local real = observer.read;
observer.read = function() return { { kind = 'cooldown', entity_id = 1002, ability = 18, entity_name = 'Ally', scope = 'party' } }; end;
s.party_cooldowns.enabled = true;
handler({ id = 0x028, size = 64, data = '', data_raw = {} });
observer.read = real;
assert(#app.state.queue == queued, 'A use is not queued for the tracker.');
app.refresh(1);
local entry = app.state.view.cooldowns and app.state.view.cooldowns[1];
assert(entry and entry.ability == 18 and entry.member_name == 'Ally' and entry.deadline > 7000, 'The list has the use after the refresh.');
s.party_cooldowns.enabled = false;
handler({ id = 0x028, size = 64, data = '', data_raw = {} });
MOCK.fire('unload');
return 'The recast tints, ready pulse and party cooldown controls each write their key as one Undo step';
