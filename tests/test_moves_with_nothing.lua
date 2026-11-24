-- Moves with set to Nothing on Size and place (ui/panel_frame.lua): a display its anchor placed stays where it is drawn,
-- so it doesn't jump to its Across and Down, which are hidden on A spot on the screen. That is its own Across and Down
-- from then on, and the change is one Undo step. One whose anchor didn't place it is at its Across and Down already,
-- and keeps them. Timer panels, the boxes and the alert notices each keep their spot in keys of their own.
local w = require('world_fixture')({ 1920, 1080 });
local elements, frame, defaults = require('ui.elements'), require('ui.panel_frame'), require('ui.defaults');
local imgui = w.imgui;
local combo = nil;
local begin_combo = imgui.BeginCombo;
rawset(imgui, 'BeginCombo', function(label, preview, ...) begin_combo(label, preview, ...); return label == combo; end);
w.settle(1);

local function fresh(change, page)
    local s = defaults.tidy(defaults.make());
    for key, panel in pairs(s.panels) do panel.enabled, panel.locked = key == 'self_buffs' or key == 'self_debuffs', false; end;
    s.preview, s.window.open, s.window.tab = true, true, 'Display';
    if change then change(s); end;
    local state = w.app.state;
    state.settings, state.history, state.redo, state.transaction = s, {}, {}, nil;
    state.settings_revision = state.settings_revision + 1;
    frame.open(page or 'self_buffs', 'place');
    w.settle();
    return s;
end;
local function pick(label, choice)
    combo, MOCK.clicks[choice] = label, true;
    w.frame();
    assert(not MOCK.clicks[choice], 'The choice is in the list: ' .. choice);
    combo, MOCK.clicks = nil, {};
    w.frame(); w.frame();
end;
local function settle() w.frame(0.7); w.frame(); end;

-- A timer panel on A spot on the screen, with its hidden Across and Down somewhere else.
fresh(function(s)
    local p = s.panels.self_buffs;
    p.x, p.y = 40, 160;
    p.anchor.to, p.anchor.point, p.anchor.dx, p.anchor.dy = 'screen', 'top_left', 600, 400;
end);
local drawn = elements.drawn('self_buffs');
assert(elements.anchored('self_buffs') and drawn.x == 600 and drawn.y == 400, 'Fixture: the spot puts it at 600, 400.');
pick('##frame_Moves with', 'Nothing##none');
local p = w.s().panels.self_buffs;
drawn = elements.drawn('self_buffs');
assert(p.anchor.to == 'none', 'Fixture: Nothing was picked.');
assert(p.x == 600 and p.y == 400 and drawn.x == 600 and drawn.y == 400,
    ('Nothing keeps it where it was: it went from 600, 400 to %d, %d'):format(drawn.x, drawn.y));
settle();
assert(#w.app.state.history == 1, 'It is one Undo step: ' .. #w.app.state.history);
w.app.callbacks.undo();
w.frame(); w.frame();
p = w.s().panels.self_buffs;
assert(p.anchor.to == 'screen' and p.x == 40 and p.y == 160, 'Undo puts back the spot and its Across and Down.');

-- A panel that follows another one.
fresh(function(s)
    s.panels.self_buffs.x, s.panels.self_buffs.y = 200, 200;
    local p2 = s.panels.self_debuffs;
    p2.x, p2.y = 900, 700;
    p2.anchor.to, p2.anchor.element, p2.anchor.side, p2.anchor.gap, p2.anchor.offset = 'element', 'self_buffs', 'right', 4, 10;
end, 'self_debuffs');
drawn = elements.drawn('self_debuffs');
local x, y = drawn.x, drawn.y;
assert(elements.anchored('self_debuffs') and x ~= 900, 'Fixture: it is drawn beside Self buffs.');
pick('##frame_Moves with', 'Nothing##none');
p = w.s().panels.self_debuffs;
drawn = elements.drawn('self_debuffs');
assert(p.anchor.to == 'none' and p.x == x and p.y == y and drawn.x == x and drawn.y == y,
    ('A panel that followed another stays where it was: it went from %d, %d to %d, %d'):format(x, y, drawn.x, drawn.y));

-- A box, the Pet, that follows Phantom Roll.
fresh(function(s)
    s.rolls.enabled, s.rolls.preview, s.rolls.x, s.rolls.y = true, true, 500, 300;
    s.pet.enabled, s.pet.preview, s.pet.x, s.pet.y = true, true, 1400, 50;
    s.pet.anchor.to, s.pet.anchor.element, s.pet.anchor.side, s.pet.anchor.gap = 'element', 'rolls', 'below', 4;
end, 'pet');
drawn = elements.drawn('pet');
x, y = drawn.x, drawn.y;
assert(elements.anchored('pet') and x == 500, 'Fixture: the Pet is drawn below Phantom Roll.');
pick('##frame_Moves with', 'Nothing##none');
drawn = elements.drawn('pet');
assert(w.s().pet.anchor.to == 'none' and w.s().pet.x == x and w.s().pet.y == y and drawn.x == x and drawn.y == y,
    ('The Pet stays where it was: it went from %d, %d to %d, %d'):format(x, y, drawn.x, drawn.y));

-- The alert notices keep their spot in notice_x and notice_y. They show in edit mode with no alert up.
fresh(function(s)
    s.alerts.enabled, s.alerts.notice_locked, s.alerts.notice_x, s.alerts.notice_y = true, false, 985, 10;
    local kept = s.alerts.notice_anchor;
    kept.to, kept.point, kept.dx, kept.dy = 'screen', 'top_left', 300, 500;
end, 'notices');
MOCK.fire('command', { command = '/vg edit on' });
w.frame(); w.frame(); w.frame();
drawn = elements.drawn('notices');
assert(elements.anchored('notices') and drawn.x == 300 and drawn.y == 500, 'Fixture: the spot puts the notices at 300, 500.');
pick('##frame_Moves with_notices', 'Nothing##none');
drawn = elements.drawn('notices');
local alerts = w.s().alerts;
assert(alerts.notice_anchor.to == 'none' and alerts.notice_x == 300 and alerts.notice_y == 500 and drawn.x == 300 and drawn.y == 500,
    ('The notices stay where they were: they went from 300, 500 to %d, %d'):format(drawn.x, drawn.y));

-- Following a display that is off, they are at their own spot already: Across at Centered stays Centered.
fresh(function(s)
    s.alerts.enabled, s.alerts.notice_locked, s.alerts.notice_x, s.alerts.notice_y = true, false, -1, 10;
    local kept = s.alerts.notice_anchor;
    kept.to, kept.element, kept.side = 'element', 'rolls', 'below';
end, 'notices');
w.frame(); w.frame();
assert(not elements.anchored('notices') and elements.drawn('notices') ~= nil, 'Fixture: Phantom Roll is off, so the notices are at their own spot.');
pick('##frame_Moves with_notices', 'Nothing##none');
alerts = w.s().alerts;
assert(alerts.notice_anchor.to == 'none' and alerts.notice_x == -1 and alerts.notice_y == 10, 'Their own Across and Down stay as they were.');
MOCK.fire('command', { command = '/vg edit off' });
w.frame();
MOCK.fire('unload');
return true;
