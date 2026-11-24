-- The ready pulse (core/ready_pulse.lua, ui/ready_pulse.lua). A recast at least the shortest length that becomes
-- ready pulses once: its length is the full cooldown when its start was seen, else the most it was seen with left.
-- Shorter ones and ignored ones don't. With an early warning it pulses that many seconds before ready, once, and not
-- again at ready. It draws on its row where a panel last drew it, or at a screen spot that moves only when unlocked
-- with Shift held. It takes no clicks and sends nothing.
local pulse, defaults, hud = require('core.ready_pulse'), require('ui.defaults'), require('ui.hud');
local imgui = require('imgui');
local function fresh() return defaults.tidy(defaults.make()); end;
local function recast(id, remaining, total, key, instance)
    return { key = key or ('recast:1001:spell:' .. id), instance = instance or 1, domain = 'recast', kind = 'spell', group = 'spell_recasts',
        effect = 10000 + id, recast_id = id, spell_id = id, name = 'Spell ' .. id, remaining = remaining, total = total };
end;
local function ready(row, now)
    local event = {};
    for key, value in pairs(row) do event[key] = value; end;
    event.category, event.kind, event.time, event.remaining = row.kind, 'ready', now, 0;
    return event;
end;

-- Fresh settings and a save without the pulse: off, rows, 60 s, no early warning, nothing ignored, locked.
local s = fresh();
local p = s.ready_pulse;
assert(p.enabled == false and p.spot == 'row' and p.min_seconds == 60 and p.early == 0 and next(p.ignore) == nil and p.locked,
    'A fresh pulse is off, on rows, for recasts of a minute or more, and its spot is locked.');
local old = defaults.tidy({ style = {}, panels = {} });
assert(old.ready_pulse.locked and old.ready_pulse.min_seconds == 60, 'A save without it gets the pulse at its defaults.');
local tidied = pulse.tidy({ spot = 'nowhere', size = 9000, length = 0, ignore = { [10057] = true, ['20005'] = true, [5] = true }, x = -7, extra = 1 });
assert(tidied.spot == 'row' and tidied.size == 256 and tidied.length == 0.2 and tidied.ignore[10057] and tidied.ignore[20005]
    and not tidied.ignore[5] and tidied.x == -1 and tidied.extra == 1, 'Tidy keeps choices in range and keeps keys it doesn\'t know.');

-- The pulse is off at first, so the checks of when it plays turn it on.
s.ready_pulse.enabled = true;

-- A long recast seen from its start pulses at ready; a short one doesn't.
local watch = pulse.new();
local long, short = recast(57, 170, 180), recast(58, 20, 30);
watch:update({ long, short }, {}, s, 10);
assert(#watch.active == 0, 'Nothing pulses while recasts run.');
local active = watch:update({}, { ready(long, 20), ready(short, 20) }, s, 20);
assert(#active == 1 and active[1].effect == 10057 and active[1].kind == 'spell' and active[1].spell_id == 57,
    'The 180 s recast pulses with its own icon; the 30 s one does not.');
assert(#watch:update({}, {}, s, 20.5) == 1, 'The pulse plays for its length.');
assert(#watch:update({}, {}, s, 21) == 0, 'Then it is gone.');

-- A recast whose start wasn't seen is as long as the most it was seen with left.
watch = pulse.new();
local baseline = recast(60, 95, nil);
watch:update({ baseline }, {}, s, 10);
baseline.remaining = 80;
watch:update({ baseline }, {}, s, 25);
assert(#watch:update({}, { ready(baseline, 105) }, s, 105) == 1, 'Seen with 95 s left, it is long enough.');
watch = pulse.new();
local brief = recast(61, 40, nil);
watch:update({ brief }, {}, s, 10);
assert(#watch:update({}, { ready(brief, 50) }, s, 50) == 0, 'Seen with 40 s left and no start, it is too short.');

-- Ignored recasts never pulse; turning the pulse off clears it.
watch = pulse.new();
s.ready_pulse.ignore[10057] = true;
watch:update({ long }, {}, s, 10);
assert(#watch:update({}, { ready(long, 20) }, s, 20) == 0, 'An ignored recast does not pulse.');
s.ready_pulse.ignore = {};
watch:update({ long }, {}, s, 30);
assert(#watch:update({}, { ready(long, 31) }, s, 31) == 1, 'Taken off the list, it pulses again.');
s.ready_pulse.enabled = false;
assert(#watch:update({}, {}, s, 31.1) == 0, 'Turned off, nothing plays.');
s.ready_pulse.enabled = true;

-- An early warning pulses once, that many seconds before ready, and not again at ready.
watch = pulse.new();
s.ready_pulse.early = 5;
local soon = recast(70, 120, 120);
watch:update({ soon }, {}, s, 0);
soon.remaining = 6;
assert(#watch:update({ soon }, {}, s, 114) == 0, 'Six seconds left is not yet the warning.');
soon.remaining = 4.9;
assert(#watch:update({ soon }, {}, s, 115.1) == 1, 'Five seconds left, it pulses.');
soon.remaining = 3;
watch:update({ soon }, {}, s, 117);
assert(#watch:update({}, { ready(soon, 120) }, s, 120) == 0, 'It does not pulse again at ready.');
-- A new use of the same recast warns again.
local again = recast(70, 120, 120, nil, 2);
watch:update({ again }, {}, s, 130);
again.remaining = 4;
assert(#watch:update({ again }, {}, s, 246) == 1, 'The next use warns again.');
s.ready_pulse.early = 0;

-- Drawing on its row: the combined recast panel draws the row and notes its icon; once the row is gone, the pulse
-- draws there, in a window that takes no clicks.
local function frame(view, settings, now, callbacks)
    MOCK.imgui_calls = {};
    hud.draw(view, settings, now, callbacks or {});
end;
local function pulse_window()
    local inside, images, rings, flags, fills = false, {}, {}, nil, 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Begin' then inside = call[2] == '##vantage_pulse'; if inside then flags = call[4]; end;
        elseif call[1] == 'End' then inside = false;
        elseif inside then
            local copy = MOCK.drawn[call];
            if call[1] == 'draw:AddImage' then images[#images + 1] = copy; elseif call[1] == 'draw:AddRect' then rings[#rings + 1] = copy; end;
            if call[1] == 'draw:AddRectFilled' then fills = fills + 1; end;
        end;
    end;
    return flags, images, rings, fills;
end;
local panel_settings = fresh();
-- The pulse is off at first, so the checks of how it draws turn it on.
panel_settings.ready_pulse.enabled = true;
for _, panel in pairs(panel_settings.panels) do panel.enabled = false; end;
panel_settings.recast_display, panel_settings.panels.recasts.enabled, panel_settings.panels.recasts.mode = 'combined', true, 'icons';
require('ui.icons').status = function() return 'status'; end;
local shown = recast(57, 10, 180, 'r57');
local view = { valid = true, rows = { shown }, context = { valid = true, id = 1001 } };
frame(view, panel_settings, 10);
assert(pulse_window() == nil, 'With no pulse playing, no pulse window.');
local drawn = pulse.new();
drawn:update({ shown }, {}, panel_settings, 10);
view = { valid = true, rows = {}, context = { valid = true, id = 1001 }, pulses = drawn:update({}, { ready(shown, 11) }, panel_settings, 11) };
frame(view, panel_settings, 11.2);
local flags, images, rings = pulse_window();
assert(flags and bit.band(flags, ImGuiWindowFlags_NoMouseInputs) ~= 0, 'The pulse window takes no clicks.');
assert(#rings == 1, 'The pulse rings its icon once.');
-- Its ring is centered where the row's icon was drawn.
local icon = panel_settings.style.icon_size * panel_settings.style.scale;
local ring = rings[1];
local center_x = (ring[2][1] + ring[3][1]) / 2;
assert(math.abs(center_x - (panel_settings.panels.recasts.x + 4 + icon / 2)) < icon, 'The pulse is on the row where it was drawn: ' .. center_x);
-- It grows and fades over its length.
frame(view, panel_settings, 11.8);
local _, _, later = pulse_window();
assert(later[1] and later[1][3][1] - later[1][2][1] > ring[3][1] - ring[2][1], 'The pulse grows.');
assert(bit.rshift(bit.band(later[1][4], 0xFF000000), 24) < bit.rshift(bit.band(ring[4], 0xFF000000), 24), 'The pulse fades.');

-- The screen spot: drawn there whether or not a panel shows the recast; it moves only unlocked with Shift held.
panel_settings.ready_pulse.spot, panel_settings.ready_pulse.x, panel_settings.ready_pulse.y = 'screen', 300, 200;
local on_screen = pulse.new();
on_screen:update({ shown }, {}, panel_settings, 20);
view.pulses = on_screen:update({}, { ready(shown, 21) }, panel_settings, 21);
frame(view, panel_settings, 21.1);
flags, images, rings = pulse_window();
local size = panel_settings.ready_pulse.size * panel_settings.style.scale;
assert(rings[1] and math.abs((rings[1][2][1] + rings[1][3][1]) / 2 - (300 + size / 2)) < 1, 'The pulse plays at its screen spot.');
-- Locked, Shift and a drag change nothing.
local changes = 0;
local callbacks = { changed = function(stage) if stage == 'after' then changes = changes + 1; end end, save = function() end };
local clicked = false;
rawset(imgui, 'IsItemHovered', function() return true; end);
rawset(imgui, 'IsMouseClicked', function() return not clicked; end);
MOCK.key_shift, MOCK.mouse_down, MOCK.mouse_x, MOCK.mouse_y = true, true, 310, 210;
frame(view, panel_settings, 21.2, { shift = true, changed = callbacks.changed, save = callbacks.save });
MOCK.mouse_x, MOCK.mouse_y = 410, 260;
frame(view, panel_settings, 21.3, { shift = true, changed = callbacks.changed, save = callbacks.save });
assert(panel_settings.ready_pulse.x == 300 and panel_settings.ready_pulse.y == 200 and changes == 0, 'A locked spot stays put under Shift.');
-- Unlocked, a Shift drag moves it, as one Undo step.
panel_settings.ready_pulse.locked = false;
MOCK.mouse_x, MOCK.mouse_y = 310, 210;
frame(view, panel_settings, 21.4, { shift = true, changed = callbacks.changed, save = callbacks.save });
flags = pulse_window();
assert(flags and bit.band(flags, ImGuiWindowFlags_NoMouseInputs) == 0, 'Unlocked with Shift held, the spot can be dragged.');
clicked = true;
MOCK.mouse_x, MOCK.mouse_y = 410, 260;
frame(view, panel_settings, 21.5, { shift = true, changed = callbacks.changed, save = callbacks.save });
assert(panel_settings.ready_pulse.x == 400 and panel_settings.ready_pulse.y == 250 and changes == 1,
    'The drag moves the spot: ' .. panel_settings.ready_pulse.x .. ', ' .. panel_settings.ready_pulse.y);
-- Across at Centered stays Centered on a drag straight down, and a drag across and back to where it started puts it
-- back. An Across typed past the screen's edge, kept for a bigger screen, stays on a drag straight up.
local elements = require('ui.elements');
local moves = { shift = true, changed = callbacks.changed, save = callbacks.save };
local function drag_spot(steps)
    MOCK.mouse_down = false;
    frame(view, panel_settings, 21.5, moves);
    local spot = elements.drawn('pulse');
    -- From a whole pixel, as a mouse gives.
    local from_x, from_y = math.floor(spot.x) + 10, math.floor(spot.y) + 10;
    clicked, MOCK.mouse_down, MOCK.mouse_x, MOCK.mouse_y = false, true, from_x, from_y;
    frame(view, panel_settings, 21.5, moves);
    clicked = true;
    for _, step in ipairs(steps) do
        MOCK.mouse_x, MOCK.mouse_y = from_x + step[1], from_y + step[2];
        frame(view, panel_settings, 21.5, moves);
        if step.across then
            assert(panel_settings.ready_pulse.x == step.across, 'Fixture: the drag moves the spot across: ' .. panel_settings.ready_pulse.x);
        end;
    end;
end;
local middle = math.floor((1600 - size) / 2);
panel_settings.ready_pulse.x = -1;
drag_spot({ { 0, 40 } });
assert(panel_settings.ready_pulse.x == -1 and panel_settings.ready_pulse.y == 290 and elements.drawn('pulse').x == middle,
    'A drag straight down moves the spot down and Across stays Centered: ' .. panel_settings.ready_pulse.x .. ', ' .. panel_settings.ready_pulse.y);
drag_spot({ { 30, 0, across = middle + 30 }, { 0, 0 } });
assert(panel_settings.ready_pulse.x == -1 and elements.drawn('pulse').x == middle,
    'A drag across and back to where it started puts Centered back: ' .. panel_settings.ready_pulse.x);
panel_settings.ready_pulse.x = 5000;
drag_spot({ { 0, -40 } });
assert(panel_settings.ready_pulse.x == 5000 and panel_settings.ready_pulse.y == 250 and elements.drawn('pulse').x == 1600 - size,
    'A drag straight up keeps an Across typed past the screen\'s edge: ' .. panel_settings.ready_pulse.x .. ', ' .. panel_settings.ready_pulse.y);
-- At Size 0.85, as a save writes it and a load reads it back, the spot at an Across typed past the screen's edge is
-- drawn at a fraction of a pixel. A drag straight down keeps that Across, also with the pulse ticked to snap,
-- sitting on the screen's edge it snaps to. A drag right and down pushes into the edge it sits on, so it goes across
-- and Across becomes where the spot is drawn.
local scale = panel_settings.style.scale;
panel_settings.style.scale = tonumber(string.format('%.14g', 0.85000002384185791015625));
local fraction = 1600 - panel_settings.ready_pulse.size * panel_settings.style.scale;
assert(fraction ~= math.floor(fraction), 'Fixture: at Size 0.85 the spot is drawn at a fraction of a pixel: ' .. fraction);
panel_settings.ready_pulse.x, panel_settings.ready_pulse.y = 5000, 250;
drag_spot({ { 0, 40 } });
assert(panel_settings.ready_pulse.x == 5000 and panel_settings.ready_pulse.y == 290 and elements.drawn('pulse').x == fraction,
    'At Size 0.85 a drag straight down keeps an Across typed past the screen\'s edge: ' .. panel_settings.ready_pulse.x);
local e = panel_settings.edit_mode;
e.grid_mode, e.snap_grid, e.snap_screen, e.snap_elements, e.snap_party, e.snap_chat = true, false, true, false, false, false;
require('ui.snap').tick(panel_settings, 'pulse', true);
assert(require('ui.snap').on(panel_settings, 'pulse'), 'Fixture: Snap while moving is on and the pulse is ticked for it.');
panel_settings.ready_pulse.x, panel_settings.ready_pulse.y = 5000, 250;
drag_spot({ { 0, 40 } });
e.grid_mode = false;
assert(panel_settings.ready_pulse.x == 5000 and panel_settings.ready_pulse.y == 290,
    'Ticked to snap, on the screen\'s edge it snaps to, a drag straight down at Size 0.85 keeps that Across: ' .. panel_settings.ready_pulse.x);
panel_settings.style.scale = scale;
panel_settings.ready_pulse.x, panel_settings.ready_pulse.y = 5000, 250;
drag_spot({ { 20, 40 } });
assert(panel_settings.ready_pulse.x == 1600 - size and panel_settings.ready_pulse.y == 290 and elements.drawn('pulse').x == 1600 - size,
    'A drag right and down that pushes into the edge sets Across to where the spot is drawn: ' .. panel_settings.ready_pulse.x);
panel_settings.ready_pulse.x, panel_settings.ready_pulse.y = 400, 250;
-- Without Shift it takes no clicks, unlocked or not.
MOCK.key_shift, MOCK.mouse_down = false, false;
frame(view, panel_settings, 21.6, {});
flags = pulse_window();
assert(flags and bit.band(flags, ImGuiWindowFlags_NoMouseInputs) ~= 0, 'Without Shift the pulse takes no clicks.');
rawset(imgui, 'IsItemHovered', nil); rawset(imgui, 'IsMouseClicked', nil);
-- A test pulse for rows, with no recast row on screen, plays at the screen spot.
panel_settings.ready_pulse.spot = 'row';
local tester = pulse.new();
tester:test(panel_settings, 30);
view.pulses, view.rows = tester.active, {};
frame(view, panel_settings, 30.2, {});
flags, images, rings = pulse_window();
assert(rings[1] and math.abs((rings[1][2][1] + rings[1][3][1]) / 2 - (panel_settings.ready_pulse.x + size / 2)) < 1,
    'A test pulse with no row to play on plays at the screen spot.');

-- Paused timer panels, or panels their own rules hide, don't take the screen spot's pulses with them, as they don't
-- take the alert notices. A pulse on its row waits for the rows.
panel_settings.ready_pulse.spot = 'screen';
local paused = pulse.new();
paused:update({ shown }, {}, panel_settings, 40);
view.pulses, view.rows = paused:update({}, { ready(shown, 41) }, panel_settings, 41), {};
panel_settings.enabled = false;
frame(view, panel_settings, 41.1, {});
flags, images, rings = pulse_window();
assert(rings[1], 'The screen spot pulses while the timer panels are paused.');
-- The event, map and hidden interface rules hide every display, pulses too, so the app doesn't draw then
-- (vantage.lua hidden_by_rules). Hide while typing is the panels' own.
panel_settings.enabled, panel_settings.visibility.hide_typing, view.context.chat_open = true, true, true;
frame(view, panel_settings, 41.2, {});
flags, images, rings = pulse_window();
assert(rings[1], 'and while their rule for typing hides them.');
view.pulses[1].spot = 'row';
frame(view, panel_settings, 41.3, {});
assert(pulse_window() == nil, 'A pulse on its row doesn\'t play where the hidden panels drew it.');
panel_settings.visibility.hide_typing, view.context.chat_open = false, nil;
-- Locked, with nothing playing, holding Shift outlines the spot and shows its lock note over it, and it still takes
-- no clicks.
view.pulses = {};
panel_settings.ready_pulse.locked = true;
MOCK.key_shift, MOCK.mouse_x, MOCK.mouse_y = true, 5, 5;
frame(view, panel_settings, 50, { shift = true });
local fills;
flags, images, rings, fills = pulse_window();
assert(flags and bit.band(flags, ImGuiWindowFlags_NoMouseInputs) ~= 0 and #rings == 1 and fills == 0
    and math.abs(rings[1][2][1] - panel_settings.ready_pulse.x) < 1, 'Shift outlines a locked spot.');
MOCK.mouse_x, MOCK.mouse_y = panel_settings.ready_pulse.x + 5, panel_settings.ready_pulse.y + 5;
frame(view, panel_settings, 50.05, { shift = true });
flags, images, rings, fills = pulse_window();
assert(flags and bit.band(flags, ImGuiWindowFlags_NoMouseInputs) ~= 0 and fills > 0, 'and over it shows its lock note.');
MOCK.key_shift = false;
frame(view, panel_settings, 50.1, {});
assert(pulse_window() == nil, 'Without Shift a spot with nothing playing draws nothing.');

-- The largest pulse, 256 at Size 2.5, grows to 512 on screen, the most an action icon draws. Its ring goes around that,
-- and its spot is that big.
panel_settings.ready_pulse.size, panel_settings.style.scale = 256, 2.5;
panel_settings.ready_pulse.x, panel_settings.ready_pulse.y = 100, 100;
local largest = pulse.new();
largest:update({ shown }, {}, panel_settings, 60);
view.pulses, view.rows = largest:update({}, { ready(shown, 61) }, panel_settings, 61), {};
frame(view, panel_settings, 61.99, {});
flags, images, rings = pulse_window();
local image, edge = images[1], math.max(2, math.floor(3 * 2.5 + 0.5));
local across = image and image[4][1] - image[3][1];
assert(across and across > 500 and across <= 512, 'The pulse grows to 512 at most: ' .. tostring(across));
assert(rings[1] and math.abs(rings[1][2][1] - (image[3][1] - edge)) < 0.001 and math.abs(rings[1][3][1] - (image[4][1] + edge)) < 0.001,
    'Its ring is around the icon.');
assert(math.abs((image[3][1] + image[4][1]) / 2 - (100 + 256)) < 0.001, 'It plays centered on its spot.');
view.pulses = {};
MOCK.key_shift = true;
frame(view, panel_settings, 63, { shift = true });
flags, images, rings = pulse_window();
assert(rings[1] and math.abs(rings[1][3][1] - rings[1][2][1] - 512) < 0.001 and math.abs(rings[1][2][1] - 100) < 0.001,
    'Its spot is 512 across.');
MOCK.key_shift = false;

-- In the app: the screen spot reads every recast kind, the test pulse plays, and /vg lock covers the spot.
local store = require('core.store');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
app.state.settings.ready_pulse.enabled = true;
assert(app.callbacks.test_pulse(), 'The test pulse plays.');
assert(#app.state.view.pulses == 1 and app.state.view.pulses[1].test, 'The test pulse is playing.');
app.state.settings.ready_pulse.locked = false;
MOCK.fire('command', { command = '/vg lock' });
assert(app.state.settings.ready_pulse.locked and app.state.settings.party_cooldowns.list.locked, '/vg lock locks the pulse spot and the cooldown list.');
MOCK.fire('command', { command = '/vg unlock' });
assert(not app.state.settings.ready_pulse.locked, '/vg unlock unlocks them.');
assert(app.callbacks.reset('ready_pulse') and app.state.settings.ready_pulse.locked, '/vg reset ready_pulse restores the pulse settings.');
MOCK.fire('unload');
return 'The ready pulse plays when and where its settings say';
