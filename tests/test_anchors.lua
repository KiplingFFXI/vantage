-- Anchors (core/anchors.lua, ui/elements.lua): a display anchored to a point of the screen keeps its distance from
-- it; one anchored beside another display, the game's party list or the chat log follows it, and goes to its fallback
-- spot (its own x and y) while that isn't on the screen. An anchor that would follow itself round has none. Outside
-- edit mode a Shift drag detaches an anchored display and moves it from where its anchor drew it. Saves without
-- anchors load with none, and a bad anchor tidies to none.
local anchors, elements, defaults = require('core.anchors'), require('ui.elements'), require('ui.defaults');
local hud, imgui = require('ui.hud'), require('imgui');
local equal = require('core.customization').equal;

-- The places, worked out.
local a = anchors.make();
assert(a.to == 'none' and not anchors.active(a), 'A fresh anchor follows nothing.');
a.to, a.point, a.dx, a.dy = 'screen', 'bottom_right', -10, -20;
local x, y = anchors.position(a, 100, 50, nil, 1600, 900);
assert(x == 1490 and y == 830, 'A bottom right screen anchor keeps its corner 10 px left and 20 px up of the screen\'s: ' .. x .. ', ' .. y);
a.point, a.dx, a.dy = 'center', 0, 0;
x, y = anchors.position(a, 100, 50, nil, 1600, 900);
assert(x == 750 and y == 425, 'A center anchor keeps it in the middle.');
a.point = 'top';
x, y = anchors.position(a, 100, 50, nil, 1920, 1080);
assert(x == 910 and y == 0, 'A top edge anchor keeps it centered at the top on any screen.');
local target = { x = 100, y = 200, width = 300, height = 80 };
a.to, a.side, a.gap, a.align, a.offset = 'element', 'below', 4, 'start', 0;
x, y = anchors.position(a, 100, 50, target, 1600, 900);
assert(x == 100 and y == 284, 'Below it, lined up with its start.');
a.align = 'center'; x = anchors.position(a, 100, 50, target, 1600, 900);
assert(x == 200, 'Lined up with its middle.');
a.align = 'end'; x = anchors.position(a, 100, 50, target, 1600, 900);
assert(x == 300, 'Lined up with its far end.');
a.align, a.offset = 'start', 10; x = anchors.position(a, 100, 50, target, 1600, 900);
assert(x == 110, 'Moved along the side.');
a.side, a.offset = 'right', 0; x, y = anchors.position(a, 100, 50, target, 1600, 900);
assert(x == 404 and y == 200, 'Right of it.');
a.side = 'left'; x = anchors.position(a, 100, 50, target, 1600, 900);
assert(x == -4, 'Left of it, which the display keeps on the screen itself.');
a.side = 'above'; x, y = anchors.position(a, 100, 50, target, 1600, 900);
assert(y == 146, 'Above it.');
assert(anchors.position(a, 100, 50, nil, 1600, 900) == nil, 'With nothing to follow there is no place.');
-- A move keeps the anchor and changes how far it sits from it.
local moved = anchors.make();
moved.to, moved.side, moved.gap, moved.offset = 'element', 'below', 4, 0;
anchors.move(moved, 7, 5); assert(moved.gap == 9 and moved.offset == 7, 'Below: down widens the gap, across moves it along.');
moved.side = 'above'; anchors.move(moved, 0, 5); assert(moved.gap == 4, 'Above: down narrows the gap.');
moved.side = 'right'; anchors.move(moved, 3, 2); assert(moved.gap == 7 and moved.offset == 9, 'Right: right widens the gap, down moves it along.');
moved.side = 'left'; anchors.move(moved, 3, 0); assert(moved.gap == 4, 'Left: right narrows the gap.');
moved.to = 'screen'; moved.dx, moved.dy = 0, 0; anchors.move(moved, -12, 30);
assert(moved.dx == -12 and moved.dy == 30, 'A screen anchor moves its distance from the point.');
-- Tidy: what can't be followed is no anchor.
local ids = elements.anchorable;
assert(anchors.tidy({ to = 'nowhere' }, 'rolls', ids).to == 'none', 'An unknown kind is no anchor.');
assert(anchors.tidy({ to = 'element', element = 'rolls' }, 'rolls', ids).to == 'none', 'A display can\'t follow itself.');
assert(anchors.tidy({ to = 'element', element = 'overhead' }, 'rolls', ids).to == 'none', 'Overhead icons have no place to follow.');
assert(anchors.tidy({ to = 'element', element = 'gone' }, 'rolls', ids).to == 'none', 'A display that doesn\'t exist is no anchor.');
local tidied = anchors.tidy({ to = 'screen', point = 'middle', dx = 1e9, dy = 'far', gap = -900, side = 'under' }, 'rolls', ids);
assert(tidied.to == 'screen' and tidied.point == 'top_left' and tidied.dx == 16000 and tidied.dy == 0 and tidied.gap == -300
    and tidied.side == 'below', 'Bad values tidy to their limits and defaults.');

-- Saves without anchors load with none, for every display.
local fresh = defaults.tidy(defaults.make());
for _, element in ipairs(elements.list) do
    local anchor = elements.anchor(fresh, element.id);
    assert(element.anchor == nil or (anchor and anchor.to == 'none'), element.id .. ' starts with no anchor.');
end;
local old = defaults.make();
for _, panel in pairs(old.panels) do panel.anchor = nil; end;
old.alerts.notice_anchor, old.rolls.anchor = nil, nil;
local loaded = defaults.tidy(old);
assert(loaded.panels.self_buffs.anchor.to == 'none' and loaded.alerts.notice_anchor.to == 'none' and loaded.rolls.anchor.to == 'none',
    'A save without anchors gets them at their defaults.');
-- Two displays that would follow each other: the tidy leaves one following.
local circle = defaults.make();
circle.rolls.anchor = { to = 'element', element = 'pet', side = 'below', align = 'start', gap = 4, offset = 0 };
circle.pet.anchor = { to = 'element', element = 'rolls', side = 'below', align = 'start', gap = 4, offset = 0 };
circle = defaults.tidy(circle);
assert((circle.rolls.anchor.to == 'none') ~= (circle.pet.anchor.to == 'none'), 'A circle of anchors is broken once.');
-- One that only follows into a circle of others isn't in it, so it keeps its anchor.
circle = defaults.make();
circle.rolls.anchor = { to = 'element', element = 'pet', side = 'below', align = 'start', gap = 4, offset = 0 };
circle.pet.anchor = { to = 'element', element = 'rolls', side = 'below', align = 'start', gap = 4, offset = 0 };
circle.panels.target.anchor = { to = 'element', element = 'rolls', side = 'below', align = 'start', gap = 4, offset = 0 };
assert(elements.circular(circle, 'rolls') and not elements.circular(circle, 'target'), 'Only the circle is circular.');
circle = defaults.tidy(circle);
assert(circle.panels.target.anchor.to == 'element' and circle.panels.target.anchor.element == 'rolls'
    and (circle.rolls.anchor.to == 'none') ~= (circle.pet.anchor.to == 'none'), 'One that follows into it keeps its anchor.');
-- /vg set refuses a circle, as the Size and place tab never offers one, rather than tidying it away unseen.
local custom = require('core.customization');
local base = defaults.make();
base.pet.anchor = { to = 'element', element = 'rolls', side = 'below', align = 'start', gap = 4, offset = 0, point = 'top_left', dx = 0, dy = 0 };
base.panels.target.anchor = { to = 'element', element = 'pet', side = 'below', align = 'start', gap = 4, offset = 0, point = 'top_left', dx = 0, dy = 0 };
base = defaults.tidy(base);
local made, why = custom.set(base, 'rolls.anchor',
    '{"to":"element","element":"pet","side":"below","align":"start","gap":4,"offset":0,"point":"top_left","dx":0,"dy":0}');
assert(not made and why:find('would move with a display that moves with it', 1, true), '/vg set refuses a circle: ' .. tostring(why));
made, why = custom.set(base, 'rolls.anchor.element', 'pet');
assert(made and made.rolls.anchor.to == 'none' and made.panels.target.anchor.element == 'pet', 'A name alone makes no circle: ' .. tostring(why));
made, why = custom.set(made, 'rolls.anchor.to', 'element');
assert(not made and why:find('would move with a display that moves with it', 1, true), 'and so is a switch that would make one: ' .. tostring(why));

-- Drawing: the displays put where their anchors say, through hud.draw.
local function frame(settings, callbacks, notices)
    elements.frame();
    MOCK.imgui_calls, MOCK.positions = {}, {};
    hud.draw({ valid = true, rows = {}, context = { valid = true, id = 1001, chat = MOCK.chat }, cooldowns = {}, notices = notices }, settings, 100,
        callbacks or {});
end;
local function at(window) return MOCK.positions[window]; end;
local s = defaults.tidy(defaults.make());
for _, panel in pairs(s.panels) do panel.enabled = false; end;
s.rolls.enabled, s.rolls.preview, s.pet.enabled, s.pet.preview = true, true, true, true;
s.party_cooldowns.list.enabled, s.party_cooldowns.preview = true, true;
-- The party cooldown watch is off at first, and its list shows only while it is on.
s.party_cooldowns.enabled = true;
s.rolls.x, s.rolls.y, s.pet.x, s.pet.y, s.party_cooldowns.list.x, s.party_cooldowns.list.y = 300, 40, 700, 40, 1100, 40;
frame(s);
local rolls = elements.drawn('rolls');
assert(at('##vantage_rolls')[1] == 300 and at('##vantage_rolls')[2] == 40 and rolls.x == 300, 'With no anchor a display is at its own spot.');
s.rolls.anchor = { to = 'screen', point = 'bottom_right', dx = -10, dy = -10, element = '', side = 'below', align = 'start', gap = 4, offset = 0 };
frame(s);
rolls = elements.drawn('rolls');
assert(at('##vantage_rolls')[1] == 1600 - rolls.width - 10 and at('##vantage_rolls')[2] == 900 - rolls.height - 10, 'A screen anchor puts it at its corner.');
assert(s.rolls.x == 300 and s.rolls.y == 40, 'Its own spot stays as its fallback.');
-- The cooldown list above the Phantom Roll display, where that was drawn the frame before.
s.party_cooldowns.list.anchor = { to = 'element', element = 'rolls', side = 'above', align = 'start', gap = 6, offset = 0 };
frame(s);
local list = elements.drawn('cooldown_list');
assert(list.x == rolls.x and list.y == rolls.y - list.height - 6 and elements.anchored('cooldown_list'), 'It follows the display it is anchored to.');
-- With the Phantom Roll display gone, the list goes to its fallback spot.
s.rolls.enabled = false;
frame(s); frame(s);
list = elements.drawn('cooldown_list');
assert(list.x == 1100 and list.y == 40 and not elements.anchored('cooldown_list'), 'With what it follows gone, it is at its fallback spot.');
s.rolls.enabled = true;
-- Beside the chat log, where Vantage reads it.
s.pet.anchor = { to = 'chat', side = 'right', align = 'start', gap = 4, offset = 10, element = '', point = 'top_left', dx = 0, dy = 0 };
frame(s);
local pet = elements.drawn('pet');
assert(pet.x == MOCK.chat.x + MOCK.chat.width + 4 and pet.y == MOCK.chat.y + 10, 'It follows the chat log: ' .. pet.x .. ', ' .. pet.y);
-- Beside the game's party list.
elements.party_list = { x = 1300, y = 700, width = 200, height = 120 };
s.pet.anchor = { to = 'party', side = 'above', align = 'end', gap = 8, offset = 0, element = '', point = 'top_left', dx = 0, dy = 0 };
frame(s);
pet = elements.drawn('pet');
assert(pet.x == 1300 + 200 - pet.width and pet.y == 700 - pet.height - 8, 'It follows the game\'s party list.');
elements.party_list = nil;
frame(s);
pet = elements.drawn('pet');
assert(pet.x == 700 and pet.y == 40, 'With the party list unknown, it is at its fallback spot.');
-- A circle drawn by hand still places nothing by its anchor.
s.pet.anchor = { to = 'element', element = 'rolls', side = 'below', align = 'start', gap = 4, offset = 0, point = 'top_left', dx = 0, dy = 0 };
s.rolls.anchor = { to = 'element', element = 'pet', side = 'below', align = 'start', gap = 4, offset = 0, point = 'top_left', dx = 0, dy = 0 };
frame(s); frame(s);
assert(elements.drawn('rolls').x == 300 and elements.drawn('pet').x == 700, 'A circle of anchors leaves both at their fallback spots.');
s.rolls.anchor, s.pet.anchor = anchors.make(), anchors.make();

-- A panel beside a panel drawn the same frame.
s.panels.self_buffs.enabled, s.panels.target.enabled, s.preview = true, true, true;
s.panels.target.anchor = { to = 'element', element = 'self_buffs', side = 'below', align = 'start', gap = 12, offset = 0, point = 'top_left', dx = 0, dy = 0 };
frame(s);
local own, aimed = elements.drawn('self_buffs'), elements.drawn('target');
assert(aimed.x == own.x and aimed.y == own.y + own.height + 12, 'It follows a panel drawn the same frame.');
s.panels.target.anchor = { to = 'screen', point = 'bottom_left', dx = 5, dy = -5, element = '', side = 'below', align = 'start', gap = 4, offset = 0 };
frame(s);
aimed = elements.drawn('target');
assert(aimed.x == 5 and aimed.y == 900 - aimed.height - 5, 'A panel keeps its screen corner.');
assert(elements.anchored('target'), 'An anchor placed it, so Place says nothing of its fallback spot.');
s.panels.target.anchor = { to = 'party', side = 'above', align = 'start', gap = 4, offset = 0, element = '', point = 'top_left', dx = 0, dy = 0 };
frame(s);
assert(not elements.anchored('target'), 'A panel whose anchor is gone is at its fallback spot, which Place says.');

-- Outside edit mode a Shift drag detaches an anchored display.
for _, panel in pairs(s.panels) do panel.enabled = false; end;
s.preview = false;
s.party_cooldowns.list.locked = false;
s.party_cooldowns.list.anchor = { to = 'screen', point = 'top_right', dx = -20, dy = 20, element = '', side = 'below', align = 'start', gap = 4, offset = 0 };
frame(s);
list = elements.drawn('cooldown_list');
local start_x, start_y = list.x, list.y;
local changes = 0;
local callbacks = { shift = true, changed = function(stage) if stage == 'after' then changes = changes + 1; end end, save = function() end };
local clicked = false;
rawset(imgui, 'IsItemHovered', function() return true; end);
rawset(imgui, 'IsMouseClicked', function() return not clicked; end);
MOCK.mouse_down, MOCK.mouse_x, MOCK.mouse_y = true, start_x + 30, start_y + 30;
frame(s, callbacks);
clicked = true;
MOCK.mouse_x, MOCK.mouse_y = start_x - 70, start_y + 60;
frame(s, callbacks);
assert(s.party_cooldowns.list.anchor.to == 'none' and s.party_cooldowns.list.x == start_x - 100 and s.party_cooldowns.list.y == start_y + 30
    and changes > 0, 'The drag detaches it and moves it from where it was drawn.');
MOCK.mouse_down = false;
frame(s, {});
rawset(imgui, 'IsItemHovered', nil); rawset(imgui, 'IsMouseClicked', nil);
s.party_cooldowns.list.locked = true;
-- So does each other kind: a panel, the Phantom Roll box and the alert notices, each unlocked in turn. A Shift click
-- leaves it where its anchor drew it; the drag then detaches it and moves it from there.
local function shift_drag(window, from_x, from_y, dx, dy, notices)
    changes = 0;
    local pressed = false;
    rawset(imgui, 'IsItemHovered', function() return true; end);
    rawset(imgui, 'IsMouseClicked', function() return not pressed; end);
    MOCK.mouse_down, MOCK.mouse_x, MOCK.mouse_y = true, from_x, from_y;
    frame(s, callbacks, notices);
    pressed = true;
    frame(s, callbacks, notices);
    local held = MOCK.positions[window];
    MOCK.mouse_x, MOCK.mouse_y = from_x + dx, from_y + dy;
    frame(s, callbacks, notices);
    MOCK.mouse_down = false;
    frame(s, {}, notices);
    rawset(imgui, 'IsItemHovered', nil); rawset(imgui, 'IsMouseClicked', nil);
    return held;
end;
local corner = { to = 'screen', point = 'bottom_left', dx = 5, dy = -5, element = '', side = 'below', align = 'start', gap = 4, offset = 0 };
local target_panel = s.panels.target;
target_panel.enabled, target_panel.locked, target_panel.attach_to, target_panel.dock = true, false, '', 'free';
target_panel.x, target_panel.y, target_panel.anchor = 600, 300, require('core.store').copy(corner);
frame(s, callbacks);
local drawn = elements.drawn('target');
assert(drawn.x == 5 and drawn.x ~= target_panel.x, 'Fixture: the panel is at its anchor\'s corner.');
start_x, start_y = drawn.x, drawn.y;
local held = shift_drag('##vantage_target', drawn.x + drawn.width / 2, drawn.y + drawn.height / 2, 40, -30);
assert(held and held[1] == start_x and held[2] == start_y, 'A Shift click leaves the panel where its anchor drew it.');
assert(target_panel.anchor.to == 'none' and target_panel.x == start_x + 40 and target_panel.y == start_y - 30 and changes > 0,
    'The drag detaches the panel and moves it from there: ' .. target_panel.x .. ', ' .. target_panel.y);
target_panel.enabled, target_panel.locked = false, true;
s.rolls.locked, s.rolls.x, s.rolls.y, s.rolls.anchor = false, 300, 40, require('core.store').copy(corner);
frame(s, callbacks);
drawn = elements.drawn('rolls');
start_x, start_y = drawn.x, drawn.y;
assert(start_x == 5 and start_y > 40, 'Fixture: the Phantom Roll box is at its anchor\'s corner.');
held = shift_drag('##vantage_rolls', drawn.x + drawn.width / 2, drawn.y + drawn.height / 2, 60, -20);
assert(held and held[1] == start_x and held[2] == start_y, 'A Shift click leaves the box where its anchor drew it.');
assert(s.rolls.anchor.to == 'none' and s.rolls.x == start_x + 60 and s.rolls.y == start_y - 20 and changes > 0,
    'The drag detaches the Phantom Roll box and moves it from there: ' .. s.rolls.x .. ', ' .. s.rolls.y);
s.rolls.locked = true;
local up = { { visual = true, ends = 200, message = 'Haste wore off' } };
s.alerts.enabled, s.alerts.muted, s.alerts.notice_locked, s.alerts.notice_x, s.alerts.notice_y = true, false, false, 100, 100;
s.alerts.notice_anchor = require('core.store').copy(corner);
frame(s, callbacks, up);
drawn = elements.drawn('notices');
start_x, start_y = drawn.x, drawn.y;
assert(start_x == 5 and start_y > 100, 'Fixture: the notices are at their anchor\'s corner.');
held = shift_drag('##vantage_notices', drawn.x + drawn.width / 2, drawn.y + drawn.height / 2, 50, -40, up);
assert(held and held[1] == start_x and held[2] == start_y, 'A Shift click leaves the notices where their anchor drew them: ' .. tostring(held and held[1]));
assert(s.alerts.notice_anchor.to == 'none' and s.alerts.notice_x == start_x + 50 and s.alerts.notice_y == start_y - 40 and changes > 0,
    'The drag detaches the notices and moves them from there: ' .. s.alerts.notice_x .. ', ' .. s.alerts.notice_y);
s.alerts.notice_locked = true;
-- In edit mode the display's own drag waits: edit mode moves it.
s.party_cooldowns.list.anchor = { to = 'screen', point = 'top_right', dx = -20, dy = 20, element = '', side = 'below', align = 'start', gap = 4, offset = 0 };
frame(s);
MOCK.imgui_calls = {};
elements.frame();
hud.draw({ valid = true, rows = {}, context = { valid = true, id = 1001 }, cooldowns = {} }, s, 100, { shift = true, editing = true });
local list_flags;
for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Begin' and call[2] == '##vantage_cooldowns' then list_flags = call[4]; end; end;
assert(list_flags and require('bit').band(list_flags, ImGuiWindowFlags_NoMouseInputs) ~= 0, 'In edit mode its own window takes no clicks.');
assert(equal(s.party_cooldowns.list.anchor.to, 'screen'), 'and its anchor stays.');
return true;
