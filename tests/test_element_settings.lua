-- The Phantom Roll and Pet pages and their Home switches, in the real settings window through vantage.lua. Each control
-- writes its own key as one Undo step named for it; Undo puts it back and Redo does it again. Search finds them before
-- a page is opened. /vg set, get, reset, lock and unlock reach them. Profiles and shared presentation carry them but
-- leave each character its own locks and samples; skins and Apply setup start their colors again. A roll reaches the
-- Phantom Roll display, and a charm, Familiar or /check the pet display, at the packet, not the tracker. The pet
-- display reads ability recasts, and a zone change clears both.
local store = require('core.store');
local SNAP = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 17, level = 75, self_known = true, self_effects = {},
    party = { { id = 1002, name = 'Ally', scope = 'party', zone = 102, slot = 1, group = 1 } },
    entities = { [1001] = { id = 1001, index = 0x400, name = 'Tester', kind = 'player' }, [1002] = { id = 1002, name = 'Ally', kind = 'player' } } };
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
for _, entry in ipairs({ { 'Show Phantom Roll display', 'Display', 'Show this display' }, { 'Show the bust chance', 'Display' }, { 'Lucky number color', 'Display' },
    { 'lucky', 'Display', 'Phantom Roll: totals, lucky numbers and bust chance' }, { 'double-up', 'Display', 'Phantom Roll: totals, lucky numbers and bust chance' },
    { 'Show pet display', 'Display', 'Show this display' }, { 'Show charm time', 'Display', 'Show charm and jug time' }, { 'Show charm and jug time', 'Display' },
    { 'Hide on the pet display', 'Display', 'Find an effect' }, { 'TP bar color', 'Display', 'TP bar' }, { 'Show effects as', 'Display' }, { 'Icons', 'Display', 'Show effects as' },
    { 'List with names', 'Display', 'Show effects as' }, { 'Show maneuvers and overload risk', 'Display' },
    { 'charm', 'Display', 'Pet: HP, TP, effects, recasts and charm time' }, { 'sic', 'Display', 'Pet: HP, TP, effects, recasts and charm time' },
    { 'Phantom Roll', 'Home' }, { 'Edit Pet', 'Home' } }) do
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
app.callbacks.catalog = nil;
local view = { rows = {}, context = { valid = true, job = 17, entities = {} } };
local function frame(step)
    step = step or {};
    combo, slider, colored = step.combo, step.slider, step.color;
    if step.click then MOCK.clicks[step.click] = true; end
    window.draw(app.state.settings, view, app.callbacks);
    assert(not step.click or not MOCK.clicks[step.click], 'The control is on the page: ' .. tostring(step.click));
    assert(not slider and not colored, 'The control is on the page.');
    MOCK.clicks = {};
end;
-- Put it back and Reset this display go where a fresh install's first frame puts a display on this screen.
local function first_spot(id, chat) return require('ui.setup_defaults').first_spot(id, { width = 1600, height = 900, chat = chat }); end;
local function begin(tab, setup)
    local s = defaults.tidy(defaults.make());
    local id, place = tab:match('^(%a+)/(.+)$');
    if place then tab = 'Display'; require('ui.panel_frame').open(id:lower(), place); end
    s.window.open, s.window.tab = true, tab;
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
local function on(s) s.rolls.enabled, s.pet.enabled = true, true; end;
local function unlocked(s) s.rolls.locked = false; end;
local function pet_unlocked(s) s.pet.locked = false; end;
-- { page, name, setup, steps, check(settings), Undo label, key }
local rows = {
    { 'Rolls/show', 'Show Phantom Roll display', nil, click('On##frame_display'), function(s) return s.rolls.enabled; end, 'Show this display', 'rolls' },
    { 'Rolls/show', 'Show samples', function(s) s.rolls.enabled = true; end, click('Show samples##frame'), function(s) return s.rolls.preview and s.rolls.enabled; end, 'Show samples', 'rolls' },
    { 'Rolls/show', 'Turning it off ends the samples', function(s) s.rolls.enabled, s.rolls.preview = true, true; end, click('On##frame_display'),
        function(s) return not s.rolls.enabled and not s.rolls.preview; end, 'Show this display', 'rolls' },
    { 'Rolls/show', 'Locked', nil, click('Locked##frame'), function(s) return s.rolls.locked == false; end, 'Locked', 'rolls' },
    { 'Rolls/show', 'Show what it gives', nil, click('Show what it gives##frame'), function(s) return s.rolls.show_effect == false; end, 'Show what it gives', 'rolls' },
    { 'Rolls/show', 'Show lucky and unlucky numbers', nil, click('Show lucky and unlucky numbers##frame'), function(s) return s.rolls.show_numbers == false; end, 'Show lucky and unlucky numbers', 'rolls' },
    { 'Rolls/show', 'Show the bust chance', nil, click('Show the bust chance##frame'), function(s) return s.rolls.show_odds == false; end, 'Show the bust chance', 'rolls' },
    { 'Rolls/show', 'Show who got it', nil, click('Show who got it##frame'), function(s) return s.rolls.show_members == false; end, 'Show who got it', 'rolls' },
    { 'Rolls/show', 'Most rolls shown', nil, slide('frame_Most rolls shown', 2), function(s) return s.rolls.max_rolls == 2; end, 'Most rolls shown', 'rolls' },
    { 'Rolls/look', 'Show its heading', nil, click('Show its heading##frame'), function(s) return s.rolls.show_heading == false; end, 'Show its heading', 'rolls' },
    { 'Rolls/place', 'Across', unlocked, slide('frame_Across', 500), function(s) return s.rolls.x == 500; end, 'Across', 'rolls' },
    { 'Rolls/place', 'Down', unlocked, slide('frame_Down', 90), function(s) return s.rolls.y == 90; end, 'Down', 'rolls' },
    { 'Rolls/place', 'Width', unlocked, slide('frame_Width', 400), function(s) return s.rolls.width == 400; end, 'Width', 'rolls' },
    { 'Rolls/place', 'Tallest', unlocked, slide('frame_Tallest', 30), function(s) return s.rolls.height == 60; end, 'Tallest', 'rolls' },
    { 'Rolls/place', 'Put it back where it started', function(s) s.rolls.locked, s.rolls.x = false, 600; end, click('Put it back where it started##frame'),
        function(s) return s.rolls.x == first_spot('rolls') and s.rolls.x ~= 600; end, 'Put Phantom Roll back', 'rolls' },
    { 'Rolls/look', 'Lucky number color', nil, paint('Lucky number color##frame', { 0, 0, 1, 1 }), function(s) return s.rolls.lucky_color[3] == 1 and s.rolls.lucky_color[1] == 0; end, 'Lucky number color', 'rolls' },
    { 'Rolls/look', 'Unlucky number color', nil, paint('Unlucky number color##frame', { 0, 1, 0, 1 }), function(s) return s.rolls.unlucky_color[2] == 1 and s.rolls.unlucky_color[1] == 0; end, 'Unlucky number color', 'rolls' },
    { 'Rolls/look', 'Not reached color', nil, paint('Not reached color##frame', { 1, 0, 0, 1 }), function(s) return s.rolls.missed_color[1] == 1 and s.rolls.missed_color[2] == 0; end, 'Not reached color', 'rolls' },
    { 'Rolls/show', 'Reset this display', function(s) s.rolls.show_odds, s.rolls.x = false, 9; end, { { click = 'Reset this display##frame' }, { click = 'Reset##look_frame_reset_rolls' } },
        function(s) return s.rolls.show_odds and s.rolls.x == first_spot('rolls', app.state.snapshot.chat); end, 'Reset Phantom Roll', 'rolls' },
    { 'Pet/show', 'Show pet display', nil, click('On##frame_display'), function(s) return s.pet.enabled; end, 'Show this display', 'pet' },
    { 'Pet/show', 'Show samples', function(s) s.pet.enabled = true; end, click('Show samples##frame'), function(s) return s.pet.preview and s.pet.enabled; end, 'Show samples', 'pet' },
    { 'Pet/show', 'Turning the pet off ends the samples', function(s) s.pet.enabled, s.pet.preview = true, true; end, click('On##frame_display'),
        function(s) return not s.pet.enabled and not s.pet.preview; end, 'Show this display', 'pet' },
    { 'Pet/show', 'Locked', nil, click('Locked##frame'), function(s) return s.pet.locked == false; end, 'Locked', 'pet' },
    { 'Pet/show', 'Show HP, MP and TP', nil, click('Show HP, MP and TP##frame'), function(s) return s.pet.show_vitals == false; end, 'Show HP, MP and TP', 'pet' },
    { 'Pet/show', 'Show automaton HP as a number', nil, click('Show automaton HP as a number##frame'), function(s) return s.pet.exact_hp == true; end,
        'Show automaton HP as a number', 'pet' },
    { 'Pet/show', 'Show charm and jug time', nil, click('Show charm and jug time##frame'), function(s) return s.pet.show_charm == false; end, 'Show charm and jug time', 'pet' },
    { 'Pet/show', 'Effects: None', nil, click('None##frame_Effects_none'), function(s) return s.pet.show_effects == false and s.pet.kinds == 'all'; end, 'Effects', 'pet' },
    { 'Pet/show', 'Effects: Debuffs only', nil, click('Debuffs only##frame_Effects_debuff'), function(s) return s.pet.show_effects and s.pet.kinds == 'debuff'; end, 'Effects', 'pet' },
    { 'Pet/show', 'Effects back on from None', function(s) s.pet.show_effects, s.pet.kinds = false, 'debuff'; end, click('Buffs only##frame_Effects_buff'),
        function(s) return s.pet.show_effects and s.pet.kinds == 'buff'; end, 'Effects', 'pet' },
    { 'Pet/show', 'Show effects as', nil, click('List with names##frame_Show effects as_list'), function(s) return s.pet.effects_as == 'list'; end, 'Show effects as', 'pet' },
    { 'Pet/show', 'Show effect countdowns', nil, click('Show effect countdowns##frame'), function(s) return s.pet.show_countdowns == false; end, 'Show effect countdowns', 'pet' },
    { 'Pet/show', 'Most effects shown', nil, slide('frame_Most effects shown', 4), function(s) return s.pet.max_effects == 4; end, 'Most effects shown', 'pet' },
    { 'Pet/show', 'Show maneuvers and overload risk', nil, click('Show maneuvers and overload risk##frame'), function(s) return s.pet.show_maneuvers == false; end, 'Show maneuvers and overload risk', 'pet' },
    { 'Pet/show', 'Show pet command recasts', nil, click('Show pet command recasts##frame'), function(s) return s.pet.show_recasts == false; end, 'Show pet command recasts', 'pet' },
    { 'Pet/show', 'Most recasts shown', nil, slide('frame_Most recasts shown', 3), function(s) return s.pet.max_recasts == 3; end, 'Most recasts shown', 'pet' },
    { 'Pet/filters', 'Use the Hidden everywhere list', nil, click('Use the Hidden everywhere list##frame'), function(s) return s.pet.shared_rules == false; end, 'Use the Hidden everywhere list', 'pet' },
    { 'Pet/filters', 'Clear this display\'s filters', function(s) s.pet.include, s.pet.exclude = { 33 }, { 4 }; end, click('Clear this display\'s filters##frame'),
        function(s) return #s.pet.include == 0 and #s.pet.exclude == 0; end, 'Clear this display\'s filters', 'pet' },
    { 'Pet/place', 'Width', pet_unlocked, slide('frame_Width', 300), function(s) return s.pet.width == 300; end, 'Width', 'pet' },
    { 'Pet/place', 'Tallest', pet_unlocked, slide('frame_Tallest', 30), function(s) return s.pet.height == 60; end, 'Tallest', 'pet' },
    { 'Pet/place', 'Put it back where it started', function(s) s.pet.locked, s.pet.y = false, 10; end, click('Put it back where it started##frame'), function(s) return s.pet.y == select(2, first_spot('pet')) and s.pet.y ~= 10; end,
        'Put Pet back', 'pet' },
    { 'Pet/look', 'HP bar', nil, paint('HP bar##frame', { 1, 0, 1, 1 }), function(s) return s.pet.hp_color[1] == 1 and s.pet.hp_color[2] == 0; end, 'HP bar', 'pet' },
    { 'Pet/look', 'TP bar', nil, paint('TP bar##frame', { 0, 0, 0, 1 }), function(s) return s.pet.tp_color[1] == 0; end, 'TP bar', 'pet' },
    { 'Pet/show', 'Reset this display', function(s) s.pet.max_effects = 2; end, { { click = 'Reset this display##frame' }, { click = 'Reset##look_frame_reset_pet' } },
        function(s) return s.pet.max_effects == 8; end, 'Reset Pet', 'pet' },
    { 'Home', 'Phantom Roll', nil, click('Phantom Roll##main_rolls'), function(s) return s.rolls.enabled; end, 'Phantom Roll', 'rolls' },
    { 'Home', 'Pet', nil, click('Pet##main_pet'), function(s) return s.pet.enabled; end, 'Pet', 'pet' },
    { 'Home', 'Pet off ends its samples', function(s) s.pet.enabled, s.pet.preview = true, true; end, click('Pet##main_pet'),
        function(s) return not s.pet.enabled and not s.pet.preview; end, 'Pet', 'pet' },
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
-- The main page counts their samples as on, and ends them with the rest.
begin('Home', function(s) on(s); s.rolls.preview, s.pet.preview = true, true; end);
frame({ click = 'End samples##main' });
assert(not app.state.settings.rolls.preview and not app.state.settings.pet.preview and app.state.settings.rolls.enabled, 'End samples ends theirs too.');
-- Every countdown has one time format, so neither page offers a choice of it and search finds none there.
local combos = {};
imgui.BeginCombo = function(label) combos[label] = true; return label == combo; end;
for _, tab in ipairs({ 'Rolls', 'Pet' }) do
    combos = {};
    begin(tab);
    assert(not combos['##Time format'] and not combos['##frame_Time format'] and not found('Time format', 'Display', 'Time format'),
        'No time format to pick on ' .. tab .. '.');
end;
-- The shared countdown text reaches them.
begin('Home');
frame({ click = 'Bold##main_countdown_bold' });
assert(app.state.settings.rolls.countdown_bold and app.state.settings.pet.countdown_bold and app.state.settings.panels.self_buffs.countdown_bold,
    'Bold on the main page reaches the Phantom Roll display, the pet display and every panel.');

-- /vg set, get, reset, lock and unlock.
local function command(text) local event = { command = text }; MOCK.fire('command', event); return event; end;
begin('Home');
command('/vg set rolls.preview true');
assert(app.state.settings.rolls.preview and app.state.settings.rolls.enabled, '/vg set of the samples turns the display on.');
command('/vg set pet.max_recasts 4');
assert(app.state.settings.pet.max_recasts == 4, '/vg set reaches the pet display.');
command('/vg set pet.enabled false');
assert(not app.state.settings.pet.enabled and not app.state.settings.pet.preview, 'Off by /vg set, its samples end too.');
assert(app.callbacks.reset('pet') and app.state.settings.pet.max_recasts == 6, '/vg reset pet restores it.');
assert(app.callbacks.reset('rolls') and not app.state.settings.rolls.enabled, '/vg reset rolls restores it.');
command('/vg unlock');
assert(not app.state.settings.rolls.locked and not app.state.settings.pet.locked, '/vg unlock unlocks them.');
command('/vg lock');
assert(app.state.settings.rolls.locked and app.state.settings.pet.locked, '/vg lock locks them.');

-- Shared presentation carries them, and each character keeps its own locks and samples.
local s = app.state.settings;
s.rolls.locked, s.rolls.preview, s.rolls.enabled, s.pet.locked, s.pet.width = false, true, true, false, 333;
local shared = profiles.capture_layout(s, 'presentation');
local content = shared.presentation;
assert(content.pet.width == 333 and content.rolls.enabled == true, 'Shared presentation carries both displays.');
assert(content.rolls.locked == nil and content.rolls.preview == nil and content.pet.locked == nil, 'but not their locks or samples.');
local other = defaults.tidy(defaults.make());
local applied = profiles.apply_layout(other, shared, 'presentation');
assert(applied and other.pet.width == 333 and other.pet.locked and other.rolls.locked and not other.rolls.preview,
    'Another character takes them with its own locks and samples.');
local saved = profiles.capture(s);
assert(saved.rolls.preview == false and saved.pet.width == 333, 'A profile saves them without the samples.');
-- Skins and Apply setup start their colors again.
s.rolls.lucky_color, s.pet.hp_color = { 0, 0, 0, 1 }, { 0, 0, 0, 1 };
local appearance = require('ui.appearance');
local names = {};
for _, entry in ipairs(appearance.replaced(s)) do names[#names + 1] = entry.label; end
assert(table.concat(names, ','):find('Phantom Roll', 1, true) and table.concat(names, ','):find('Pet display', 1, true),
    'A skin\'s question names the Phantom Roll and pet displays: ' .. table.concat(names, ','));
assert(appearance.apply(s, 'Mint', { matching = true }));
assert(s.rolls.lucky_color[1] == 0.45 and s.pet.hp_color[1] == 0.4, 'A skin starts their colors again.');
s.rolls.unlucky_color = { 0, 0, 0, 1 };
assert(require('setup_fixture').apply(s, { skin = 'Phoenix', size = 'minimal', matching = false }));
assert(s.rolls.unlucky_color[1] == 1, 'Apply setup starts their colors again.');

-- A roll reaches the Phantom Roll display at the packet, and a charm the pet display, not the tracker.
local observer = require('core.observer');
local handler = MOCK.events.packet_in.vantage_packet_in;
local real = observer.read;
local queued = #app.state.queue;
s.rolls.enabled, s.pet.enabled = true, true;
observer.read = function() return { { kind = 'roll', entity_id = 1001, ability = 105, total = 4, targets = { 1001 }, results = { 'got' }, scope = 'self' },
    { kind = 'check', entity_id = 0x1000123, level = 70, scope = 'enemy' } }; end;
handler({ id = 0x028, size = 64, data = '', data_raw = {} });
observer.read = real;
assert(#app.state.queue == queued, 'Neither is queued for the tracker.');
app.refresh(1);
local entry = app.state.view.rolls and app.state.view.rolls[1];
assert(entry and entry.ability == 105 and entry.total == 4, 'The display has the roll after the refresh.');
assert(app.pet.levels[0x1000123] == 70, 'The pet display has the level.');
s.rolls.enabled = false;
observer.read = function() return { { kind = 'roll', entity_id = 1001, ability = 108, total = 4, scope = 'self' } }; end;
handler({ id = 0x028, size = 64, data = '', data_raw = {} });
observer.read = real;
app.refresh(2);
assert(next(app.rolls.rollers) == nil, 'Off, a roll is not kept.');
-- A zone change clears the pet display's levels.
handler({ id = 0x00A, size = 0x100, data = string.rep('\0', 0x100), data_raw = {} });
assert(next(app.pet.levels) == nil, 'A zone change clears them.');

-- The pet display needs your ability recasts read; nothing else does here.
local t = 10;
for id in pairs(defaults.recast_panels) do s.panels[id].enabled = false; end
s.ready_pulse.enabled, s.pet.enabled = false, false;
app.state.recast_demand = nil; app.refresh(t);
assert(app.state.recast_demand == 'falsefalsefalse', 'Fixture: nothing reads recasts: ' .. tostring(app.state.recast_demand));
s.pet.enabled = true;
app.refresh(t + 1);
assert(app.state.recast_demand == 'falsetruefalse', 'The pet display reads ability recasts: ' .. tostring(app.state.recast_demand));
s.pet.show_recasts = false;
app.refresh(t + 2);
assert(app.state.recast_demand == 'falsefalsefalse', 'not when it shows none.');
MOCK.fire('unload');
return 'The Phantom Roll and pet controls each write their key as one Undo step';
