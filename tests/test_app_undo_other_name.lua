-- A change made while a step of another name is still open is a step of its own. A step closes at the save 0.6 s after
-- its last change when nothing saved it at once, so a tick, a button or a Shift move of the settings window in that time
-- used to join it, and one Undo took back both under the first one's name and flags.
-- Everything goes through vantage.lua, the real settings window and the real Arrange on screen, frame by frame at
-- 60 fps, with ImGui doing what it does in the game: a Ctrl-click slider takes each typed key at once and its box stays
-- the active item. A Checkbox reports its click on the frame the button comes up, and the item pressed is active while
-- the button is held. Each case runs twice: quick, and with 0.7 s to spare (two steps either way).
local store = require('core.store');
local imgui = require('imgui');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 17, level = 75, self_known = true, self_effects = {},
    party = {}, entities = { [1001] = { id = 1001, index = 0x400, name = 'Tester', kind = 'player' } } };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local hud = require('ui.hud');
local hud_draw = hud.draw;
hud.draw, hud.draw_notices = function() end, function() end;
-- The party list strips get the app's party_options and call its begin_edit as a drag starts and its changed as it
-- ends. The stub keeps them, so a drag is made through those calls.
local strip_options;
require('ui.native_party_hud').draw = function(_, _, _, _, options) strip_options = options; return 0, {}; end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end,
    status = function() return { available = false }; end };
local typed, active, pressed = nil, false, false;
local slider_call = imgui.SliderFloat;
rawset(imgui, 'SliderFloat', function(label, value, ...)
    slider_call(label, value, ...);
    if typed and label == '##main_scale' then value[1] = typed; typed = nil; return true; end;
    return false;
end);
rawset(imgui, 'IsAnyItemActive', function() return active; end);
rawset(imgui, 'IsMouseClicked', function() return pressed; end);
-- Arrange on screen's picks and keys, as tests/test_edit_bar_steps_after_nudge.lua drives them.
local last_button, activate, focused, keys = nil, nil, false, {};
rawset(imgui, 'GetBackgroundDrawList', function() return imgui.GetWindowDrawList(); end);
rawset(imgui, 'GetForegroundDrawList', function() return imgui.GetWindowDrawList(); end);
rawset(imgui, 'InvisibleButton', function(label) last_button = label; return false; end);
rawset(imgui, 'IsItemActivated', function() return activate ~= nil and last_button == '##edit_hit_' .. activate; end);
rawset(imgui, 'IsWindowFocused', function() return focused; end);
rawset(imgui, 'IsKeyPressed', function(key) return keys[key] == true; end);
local app = dofile(ADDON_DIR .. '/vantage.lua');
local elements, edit = require('ui.elements'), require('ui.edit_mode');
local function command(line) local event = { command = line }; MOCK.fire('command', event); assert(event.blocked, line); end;
local function settings() return app.state.settings; end;
local function frame() MOCK.frame(1 / 60); activate = nil; end;
local function frames(seconds) for _ = 1, math.floor(seconds * 60 + 0.5) do frame(); end; end;
local function labels()
    local out = {};
    for index, entry in ipairs(app.state.history) do out[index] = entry.label; end;
    return table.concat(out, ', ');
end;
-- Every open step saved, and no steps.
local function fresh()
    MOCK.mouse_down, active, typed, pressed, focused, MOCK.key_shift, MOCK.hovered = false, false, nil, false, false, false, false;
    MOCK.mouse_x, MOCK.mouse_y = -1, -1;
    frames(0.7); frame();
    assert(not app.state.transaction, 'Fixture: nothing open.');
    app.state.history, app.state.redo = {}, {};
end;
local tick = 'Self buffs##main_self_buffs';
-- A click on the Self buffs tick: the press, the tick active while held, then the release, where Checkbox reports it.
local function click_tick(hold)
    MOCK.mouse_down, active = true, true; frames(hold);
    MOCK.mouse_down, active, MOCK.clicks[tick] = false, false, true; frame();
    assert(not MOCK.clicks[tick], 'Fixture: the tick got its click.');
end;

MOCK.fire('load'); app.refresh(0);
command('/vg');
MOCK.content_width = 1000;
frame(); frame();
assert(settings().window.open, 'Fixture: the settings window is open.');

-- A. A size typed into Size (Ctrl-click the slider, as its tip says), then Self buffs ticked wait s after the last key.
local function typed_then_tick(wait)
    fresh();
    local self_on = settings().panels.self_buffs.enabled;
    MOCK.mouse_down, active = true, true; frame();
    MOCK.mouse_down = false; frame();
    typed = 1.2; frame(); frames(0.15);
    typed = 1.25; frame();
    assert(settings().style.scale == 1.25 and app.state.transaction and app.state.transaction.label == 'Size',
        'Fixture: the typed size is in, its step open.');
    frames(wait);
    click_tick(0.1);
    assert(settings().panels.self_buffs.enabled == not self_on, 'Fixture: the tick turned Self buffs.');
    frames(0.7); frame();
    local steps = labels();
    app.callbacks.undo();
    local undone = 'size ' .. tostring(settings().style.scale) .. ', Self buffs ' .. tostring(settings().panels.self_buffs.enabled)
        .. ' (was ' .. tostring(self_on) .. ')';
    local right = settings().style.scale == 1.25 and settings().panels.self_buffs.enabled == self_on;
    -- Back where the case started, for the next.
    app.callbacks.undo();
    return steps, right, undone;
end;

-- B. Arrange on screen: an arrow press on Phantom Roll, then Self buffs ticked in the settings window wait s later.
local function nudge_then_tick(wait)
    fresh();
    local x, self_on = settings().rolls.x, settings().panels.self_buffs.enabled;
    focused = true; frame();
    keys[ImGuiKey_RightArrow] = true; frame(); keys[ImGuiKey_RightArrow] = nil; frame();
    assert(settings().rolls.x == x + 1 and app.state.transaction and app.state.transaction.label == 'Nudge Phantom Roll',
        'Fixture: the press moved it, its step open.');
    focused = false;
    frames(wait);
    click_tick(0.1);
    assert(settings().panels.self_buffs.enabled == not self_on, 'Fixture: the tick turned Self buffs.');
    frames(0.7); frame();
    local steps = labels();
    app.callbacks.undo();
    local undone = 'Phantom Roll x+' .. tostring(settings().rolls.x - x) .. ', Self buffs ' .. tostring(settings().panels.self_buffs.enabled)
        .. ' (was ' .. tostring(self_on) .. ')';
    local right = settings().rolls.x == x + 1 and settings().panels.self_buffs.enabled == self_on;
    app.callbacks.undo();
    return steps, right, undone;
end;

-- A Party list strip drag, 20 px down, through the calls the strip makes, released at the end.
local function strip_drag()
    local group = settings().party_ui.groups[1];
    local y = group.native_y or 0;
    MOCK.key_shift, MOCK.mouse_down = true, true; frame();
    strip_options.begin_edit(); group.native_y = y + 20; frames(0.2);
    MOCK.mouse_down = false; strip_options.changed(); frame();
    assert(app.state.transaction and app.state.transaction.label == 'Party layout', 'Fixture: the strip drag\'s step is open.');
    return y;
end;

-- C. A Party list strip drag, then Self buffs ticked wait s after the release.
local function strip_then_tick(wait)
    fresh();
    local self_on = settings().panels.self_buffs.enabled;
    local y = strip_drag();
    MOCK.key_shift = false;
    frames(wait);
    click_tick(0.1);
    assert(settings().panels.self_buffs.enabled == not self_on, 'Fixture: the tick turned Self buffs.');
    frames(0.7); frame();
    local steps = labels();
    app.callbacks.undo();
    local undone = 'strip y+' .. tostring((settings().party_ui.groups[1].native_y or 0) - y) .. ', Self buffs '
        .. tostring(settings().panels.self_buffs.enabled) .. ' (was ' .. tostring(self_on) .. ')';
    local right = settings().party_ui.groups[1].native_y == y + 20 and settings().panels.self_buffs.enabled == self_on;
    app.callbacks.undo();
    return steps, right, undone;
end;

-- D. A Party list strip drag, then, Shift still held, the settings window Shift-dragged 60 px right and 30 down, its
-- press wait s after the strip's release. With Hold Shift to see through this window off, so a press inside it moves it.
-- Undo of that move puts the window back.
local function strip_then_window(wait)
    fresh();
    local w = settings().window;
    w.peek = false;
    local wx, wy = w.x, w.y;
    local y = strip_drag();
    frames(wait);
    MOCK.hovered, MOCK.mouse_x, MOCK.mouse_y = true, wx + 600, wy + 400;
    MOCK.mouse_down, pressed = true, true; frame(); pressed = false;
    MOCK.mouse_x, MOCK.mouse_y = wx + 660, wy + 430; frames(0.3);
    MOCK.mouse_down = false; frame();
    MOCK.key_shift, MOCK.hovered = false, false;
    assert(settings().window.x == wx + 60 and settings().window.y == wy + 30, 'Fixture: the Shift drag moved the window: '
        .. tostring(settings().window.x - wx) .. ', ' .. tostring(settings().window.y - wy));
    frames(0.7); frame();
    local steps, last = labels(), app.state.history[#app.state.history];
    local flagged = last and last.window_geometry == true;
    app.callbacks.undo();
    local undone = 'window +' .. tostring(settings().window.x - wx) .. ',+' .. tostring(settings().window.y - wy)
        .. ', strip y+' .. tostring((settings().party_ui.groups[1].native_y or 0) - y) .. ', last step window_geometry '
        .. tostring(flagged);
    local right = settings().window.x == wx and settings().window.y == wy and settings().party_ui.groups[1].native_y == y + 20;
    app.callbacks.undo();
    settings().window.peek = true;
    return steps, right, undone;
end;

-- E. Timer durations: a Party list strip drag, then Reset this page clicked wait s after the release. That button goes
-- through call('reset') to callbacks.reset in vantage.lua, not through the settings window's changed().
local function strip_then_reset(wait)
    fresh();
    local y = strip_drag();
    MOCK.key_shift = false;
    frames(wait);
    MOCK.mouse_down, active = true, true; frames(0.1);
    MOCK.mouse_down, active, MOCK.clicks['Reset this page'] = false, false, true; frame();
    assert(not MOCK.clicks['Reset this page'] and settings().durations.learn == false, 'Fixture: Reset this page reset the page.');
    frames(0.7); frame();
    local steps = labels();
    app.callbacks.undo();
    local undone = 'strip y+' .. tostring((settings().party_ui.groups[1].native_y or 0) - y) .. ', learn '
        .. tostring(settings().durations.learn) .. ' (was true)';
    local right = settings().party_ui.groups[1].native_y == y + 20 and settings().durations.learn == true;
    app.callbacks.undo();
    return steps, right, undone;
end;

local report, wrong = {}, {};
local function case(name, quick, control)
    local steps, right, undone = quick();
    local control_steps, control_right, control_undone = control();
    -- The control shows the test reaches the right path: with 0.7 s to spare each change is its own step and one Undo
    -- takes back only the last.
    assert(control_right, 'Fixture (' .. name .. ' control): ' .. control_steps .. '; one Undo -> ' .. control_undone);
    report[#report + 1] = name .. ': steps [' .. steps .. '], one Undo -> ' .. undone .. '; control [' .. control_steps .. ']';
    if not right then wrong[#wrong + 1] = name; end;
end;

case('A typed Size, tick 0.3 s later', function() return typed_then_tick(0.3); end, function() return typed_then_tick(0.7); end);
fresh();
assert(strip_options, 'Fixture: the strips drew and have the app\'s party_options.');
case('C strip drag, tick 0.2 s later', function() return strip_then_tick(0.2); end, function() return strip_then_tick(0.7); end);
case('D strip drag, window Shift move 0.2 s later', function() return strip_then_window(0.2); end,
    function() return strip_then_window(0.7); end);
-- Learning on, so Reset this page has something to put back, and the Timer durations page open.
settings().durations.learn = true; app.state.dirty = true; app.callbacks.save();
settings().window.tab = 'Durations';
case('E strip drag, Reset this page 0.2 s later', function() return strip_then_reset(0.2); end,
    function() return strip_then_reset(0.7); end);
settings().window.tab = 'Home';

-- B needs Phantom Roll drawn and picked in Arrange on screen.
hud.draw = hud_draw;
local s = settings();
s.rolls.enabled, s.rolls.preview = true, true;
s.rolls.x, s.rolls.y = 300, 20;
command('/vg edit');
frame();
local e = s.edit_mode;
e.snap_grid, e.snap_screen, e.snap_elements, e.snap_party, e.snap_chat = false, false, false, false, false;
local rect = elements.drawn('rolls');
assert(rect, 'Fixture: Phantom Roll is drawn.');
MOCK.key_shift, MOCK.mouse_x, MOCK.mouse_y, MOCK.mouse_down = false, rect.x + 10, rect.y + 10, true;
activate = 'rolls'; frame();
MOCK.mouse_down = false; frames(0.7); frame();
assert(edit.selected() == 'rolls', 'Fixture: Phantom Roll is picked.');
case('B nudge, tick 0.2 s later', function() return nudge_then_tick(0.2); end, function() return nudge_then_tick(0.7); end);
command('/vg edit');

assert(#wrong == 0, #wrong .. ' of ' .. #report .. ' cases join two changes in one Undo step (' .. table.concat(wrong, ', ')
    .. '): ' .. table.concat(report, ' | '));

-- Calls in one frame still share a step, whatever their names, and a run of changes of one name stays one step.
fresh();
app.callbacks.changed('before', 'First'); settings().style.scale = 1.1; app.callbacks.changed('after');
app.callbacks.changed('before', 'Second'); settings().style.font_size = settings().style.font_size + 1; app.callbacks.changed('after');
frames(0.7); frame();
assert(labels() == 'First', 'One frame\'s calls share a step: [' .. labels() .. ']');
for _ = 1, 3 do
    app.callbacks.changed('before', 'Run'); settings().style.font_size = settings().style.font_size + 1; app.callbacks.changed('after');
    frame();
end;
frames(0.7); frame();
assert(labels() == 'First, Run', 'A run of one name is one step: [' .. labels() .. ']');
app.callbacks.undo(); app.callbacks.undo();
return 'Each change is its own Undo step';
