-- Where a display goes and what the place rows say, with a working mouse: the first pick on Moves with, Across and Down
-- past the edge, a display that follows stopping at its limit, presses at the edge, the first spots that Put it back and
-- the resets use, a panel with a fixed height, a group with no room, and a group's panel moved from where it's drawn.
local game = { available = true, groups = { { x = 1780, y = 880, width = 140, height = 200,
    rows = { [0] = { x = 1780, y = 880, width = 140, height = 33, slot = 0 } } } } };
local w = require('world_fixture')({ 1920, 1080 }, { game = game });
local elements, frame, edit = require('ui.elements'), require('ui.panel_frame'), require('ui.edit_mode');
local defaults, setup = require('ui.defaults'), require('ui.setup_defaults');
local imgui = w.imgui;
MOCK.chat = { x = 16, y = 821, width = 1070, height = 223 };
w.snapshot.chat = MOCK.chat;
local screen = { width = 1920, height = 1080, chat = MOCK.chat };
local combo, slid, shown = nil, {}, {};
local begin_combo, slider = imgui.BeginCombo, imgui.SliderFloat;
rawset(imgui, 'BeginCombo', function(label, preview, ...) begin_combo(label, preview, ...); return label == combo; end);
rawset(imgui, 'SliderFloat', function(label, box, low, high, format, ...)
    slider(label, box, low, high, format, ...);
    shown[label] = { value = box[1], high = high };
    if slid[label] == nil then return false; end;
    box[1], slid[label] = slid[label], nil;
    return true;
end);
w.settle(1);

local function fresh(change, page)
    local s = defaults.tidy(defaults.make());
    for key, panel in pairs(s.panels) do panel.enabled, panel.locked = key == 'self_buffs' or key == 'self_debuffs' or key == 'target', false; end;
    s.preview, s.window.open, s.window.tab = true, true, 'Display';
    if change then change(s); end;
    local state = w.app.state;
    state.settings, state.history, state.redo, state.transaction = s, {}, {}, nil;
    state.settings_revision = state.settings_revision + 1;
    frame.open(page or 'self_buffs', 'place');
    w.settle();
    return s;
end;
local function anchor() return w.s().panels.self_buffs.anchor; end;
local function pick(choice)
    combo, MOCK.clicks[choice] = '##frame_Moves with', true;
    w.frame();
    combo, MOCK.clicks = nil, {};
    w.frame(); w.frame();
end;
local function click(label)
    MOCK.clicks[label] = true;
    w.frame();
    assert(not MOCK.clicks[label], 'The control is on screen: ' .. label);
    MOCK.clicks = {};
    w.frame(); w.frame();
end;
local function says(text)
    MOCK.imgui_calls = {};
    w.frame();
    for _, call in ipairs(MOCK.imgui_calls) do
        local value = call[1] == 'TextColored' and call[3] or call[2];
        if (call[1] == 'TextWrapped' or call[1] == 'TextUnformatted' or call[1] == 'TextColored') and tostring(value):find(text, 1, true) then return true; end;
    end;
    return false;
end;
local function middle(id)
    local rect = elements.drawn(id);
    return rect.x + rect.width / 2, rect.y + rect.height / 2;
end;
local function edit_on(on)
    MOCK.fire('command', { command = on and '/vg edit on' or '/vg edit off' });
    w.frame(); w.frame(); w.frame();
    assert(edit.active() == on, 'Fixture: edit mode changed.');
end;
local function select_it(id)
    local x, y = middle(id);
    w.press(x, y);
    w.release();
    assert(edit.selected() == id, 'Fixture: selected ' .. id);
end;
local function press(key, times)
    for _ = 1, times do w.keys[key] = true; w.frame(); w.keys[key] = nil; end;
    w.frame();
end;

-- The first pick. The chat log and the game's list sit at the bottom of the screen, so Side's Below would put it off the
-- screen or over them.
fresh();
assert(anchor().side == 'below', 'Fixture: Side starts on Below.');
pick('The chat log##chat');
local drawn = elements.drawn('self_buffs');
assert(anchor().to == 'chat' and anchor().side == 'above' and elements.anchored('self_buffs') and drawn.y + drawn.height <= MOCK.chat.y,
    'Picked with Side on Below, the chat log puts it above the log.');
fresh();
pick('The game\'s party list##party');
drawn = elements.drawn('self_buffs');
assert(anchor().to == 'party' and anchor().side == 'left' and drawn.x + drawn.width <= 1780, 'And the game\'s list puts it to the left.');
fresh(function(s) s.panels.self_buffs.anchor.side = 'right'; end);
pick('The chat log##chat');
assert(anchor().side == 'right', 'A side the player chose stays.');
fresh();
drawn = elements.drawn('self_buffs');
local x, y = drawn.x, drawn.y;
pick('A spot on the screen##screen');
drawn = elements.drawn('self_buffs');
assert(anchor().to == 'screen' and anchor().point == 'top_left' and drawn.x == x and drawn.y == y, 'A spot on the screen starts as where it is now.');

-- A side of the log with no room says what happened, and the line that says it can't be read doesn't.
fresh(function(s) local kept = s.panels.self_buffs.anchor; kept.to, kept.side = 'chat', 'below'; end);
assert(says('There\'s no room on that side of the chat log, so it is at Across and Down.'), 'No room below the log says so.');
fresh(function(s) local kept = s.panels.self_buffs.anchor; kept.to, kept.side = 'chat', 'above'; end);
assert(not says('There\'s no room'), 'With room it says nothing.');

-- Across and Down read what's on the screen. What was typed stays, for a bigger screen.
fresh();
slid['##frame_Across'] = 5000;
w.frame(); w.frame(); w.frame();
drawn = elements.drawn('self_buffs');
assert(w.s().panels.self_buffs.x == 5000 and drawn.x + drawn.width == 1920, 'Fixture: the display stops at the edge and the number is kept.');
assert(shown['##frame_Across'].value == drawn.x and shown['##frame_Across'].high == 1920 - drawn.width, 'Across shows where it is, and goes as far as it still fits.');
assert(shown['##frame_Down'].value == drawn.y and shown['##frame_Down'].high == 1080 - drawn.height, 'And so does Down.');

-- A display that follows another says why it stops, once it has.
fresh(function(s)
    s.panels.self_buffs.x, s.panels.self_buffs.y = 200, 200;
    local kept = s.panels.self_debuffs.anchor;
    kept.to, kept.element, kept.side, kept.gap, kept.offset = 'element', 'self_buffs', 'right', 4, 0;
end);
edit_on(true);
x, y = middle('self_debuffs');
MOCK.key_shift = true;
w.press(x, y);
w.to(x + 200, y);
assert(not tostring(edit._message()):find('follows something', 1, true), 'Inside its limit nothing is said.');
w.to(x + 500, y);
assert(tostring(edit._message()) == 'Self debuffs follows something, so it goes no further. Set Moves with to Nothing to place it freely.', 'Past it, the way out is said.');
w.release();
MOCK.key_shift = false;
edit_on(false);

-- A press toward an edge it sits on changes nothing, so the way back has no dead presses.
fresh(function(s)
    s.panels.self_buffs.x, s.panels.self_buffs.y = 1500, 100;
    local kept = s.panels.self_debuffs.anchor;
    kept.to, kept.element, kept.side, kept.gap = 'element', 'self_buffs', 'right', 4;
end);
edit_on(true);
select_it('self_debuffs');
press(ImGuiKey_RightArrow, 5);
assert(w.s().panels.self_debuffs.anchor.gap == 4, 'At the edge a press toward it changes nothing.');
edit_on(false);
fresh(function(s) local kept = s.panels.target.anchor; kept.to, kept.point, kept.dx, kept.dy = 'screen', 'top_right', 0, 600; end);
edit_on(true);
select_it('target');
press(ImGuiKey_RightArrow, 5);
assert(w.s().panels.target.anchor.dx == 0, 'A spot on the screen stays on it too.');
local edge = elements.drawn('target').x;
press(ImGuiKey_LeftArrow, 1);
assert(elements.drawn('target').x == edge - 1, 'The first press back moves it.');
edit_on(false);

-- A group's panel saved past the edge moves from where it's drawn: every pixel of the drag shows.
fresh(function(s)
    s.party_ui.enabled, s.party_ui.preview, s.party_ui.locked = true, true, false;
    s.party_ui.groups[1].native_detached, s.party_ui.groups[1].detached_x = true, 1900;
end);
edit_on(true);
drawn = elements.drawn('strip_1');
local start = drawn.x;
assert(start < 1900, 'Fixture: it\'s held on the screen.');
select_it('strip_1');
MOCK.key_shift = true;
x, y = middle('strip_1');
w.press(x, y);
w.to(x - 50, y);
w.frame();
assert(elements.drawn('strip_1').x == start - 50 and w.s().party_ui.groups[1].detached_x == start - 50, 'The first pixels of a drag move it.');
w.release();
MOCK.key_shift = false;
edit_on(false);

-- A group with no room on its side says so on Place.
local function no_room(side)
    fresh(function(s) s.party_ui.enabled, s.party_ui.preview, s.party_ui.native.side = true, true, side; end, 'party_ui');
    return says('There\'s no room on that side of the game\'s list, so these buffs aren\'t showing.');
end;
assert(no_room('right'), 'The list at the screen\'s edge has no room to its right.');
assert(not no_room('left'), 'To its left it has.');

-- Put it back, Reset this display and /vg reset panels all go where a fresh install's first frame goes.
local function at_first(id)
    local element, config = elements.by_id[id], elements.config(w.s(), id);
    local first_x, first_y = setup.first_spot(id, screen);
    return config[element.x] == first_x and config[element.y] == first_y;
end;
local function moved(s)
    for _, id in ipairs(defaults.panel_order) do s.panels[id].x, s.panels[id].y = 701, 702; end;
end;
fresh(moved);
assert(not at_first('self_buffs'), 'Fixture: it has moved.');
click('Put it back where it started##frame');
assert(at_first('self_buffs'), 'Put it back goes to the first spot.');
fresh(moved);
click('Reset this display##frame');
click('Reset##look_frame_reset_self_buffs');
assert(at_first('self_buffs'), 'So does Reset this display.');
fresh(moved);
MOCK.fire('command', { command = '/vg reset panels' });
for _, id in ipairs(defaults.panel_order) do assert(at_first(id), '/vg reset panels puts it back: ' .. id); end;

-- Put every display back makes room for a panel with a fixed height.
fresh(function(s)
    s.recast_display = 'separate';
    for key, panel in pairs(s.panels) do panel.enabled, panel.empty = key ~= 'recasts', 'show'; end;
    s.panels.self_buffs.auto_height, s.panels.self_buffs.height_limit = false, 400;
    s.panels.target.auto_height, s.panels.target.height_limit = false, 500;
end);
MOCK.fire('command', { command = '/vg reset displays' });
w.settle(4);
local function covers(id)
    local a = elements.drawn(id);
    for _, element in ipairs(elements.movable) do
        local b = element.id ~= id and elements.drawn(element.id);
        if b and a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height then return element.id; end;
    end;
    return nil;
end;
assert(elements.drawn('self_buffs').height == 400 and elements.drawn('target').height == 500, 'Fixture: the heights stay.');
assert(not covers('self_buffs') and not covers('target'), 'The panels flow past them: ' .. tostring(covers('self_buffs') or covers('target')));
return 'A first pick, Across and Down, a display that follows, the first spots and a group with no room all do what they say';
