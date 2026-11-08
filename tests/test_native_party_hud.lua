local overlay = require('ui.native_party_hud');
local imgui = require('imgui');
local p = require('ui.party_defaults').make();
local r, subjects = require('ui.party_hud').sample(18, 100);
local geometry = { available = true, groups = {} };
for group = 1, 3 do
    local frame = { x = 900, y = 40 + (group - 1) * 160, width = 116, height = 132, rows = {} };
    for _, member in ipairs(r.members) do if member.group == group then
        frame.rows[member.slot] = { x = frame.x, y = frame.y + member.slot % 6 * 22, width = 116, height = 22,
            slot = member.slot };
    end end
    geometry.groups[group] = frame;
end
p.enabled, p.locked = true, false;
local function plan() return overlay.plan(r, subjects, p, geometry, 1280, 720); end
local plans = plan();
assert(#plans == 3 and #plans[1].rows == 6);
-- A fresh strip leaves 26 px between the game's list and the nearest icon.
assert(plans[1].x + plans[1].width == 874 and plans[1].rows[2].area.y == 62);
assert(plans[1].width < p.native.width and plans[1].rows[1].area.align_right);
local small = plans[1].width;
local effect = subjects[1001].effects[1];
for _ = 1, 30 do subjects[1001].effects[#subjects[1001].effects + 1] = effect; end
assert(plan()[1].width > small and plan()[1].width <= p.native.width);
assert(plan()[1].width == 420);
p.native.side = 'right'; plans = plan();
assert(plans[1].x == 1042 and plans[1].width == 238 and not plans[1].rows[1].area.align_right);
p.native.side = 'left'; p.include_self = false;
assert(#plan()[1].rows == 5 and plan()[1].rows[1].member.slot == 1);
p.include_self = true; p.strips.alliance1 = false;
assert(#plan() == 2); p.strips.alliance1 = true;
-- Each strip has its own switch.
p.strips.alliance1, p.strips.alliance2 = false, false; assert(#plan() == 1 and plan()[1].group == 1);
p.strips.party, p.strips.alliance1 = false, true; assert(#plan() == 1 and plan()[1].group == 2, 'Alliance 1 shows without the party strip.');
p.strips.party, p.strips.alliance2 = true, true;
-- A member whose row isn't in the game's list gets no icons, and the others stay on their own rows.
local missing = geometry.groups[1].rows[2];
geometry.groups[1].rows[2] = nil;
plans = plan();
assert(#plans[1].rows == 5 and plans[1].rows[2].member.slot == 1 and plans[1].rows[3].member.slot == 3
    and plans[1].rows[3].area.y == 106, 'A member without a row is left out.');
geometry.groups[1].rows[2] = missing;
geometry.groups[2].x, geometry.groups[2].y = 650, 40;
assert(plan()[1].width == 82, 'A strip must stop the same 26 px before another native window.');
geometry.groups[2].x, geometry.groups[2].y = 900, 200;
p.groups[1].native_x, p.groups[1].native_y = 2000, -2000;
plans = plan(); assert(plans[1].x >= 0 and plans[1].x + plans[1].width <= 1280 and plans[1].y == 0);
p.groups[1].native_x, p.groups[1].native_y = 0, 0;
p.effects.icon_size = 64;
plans = plan(); assert(plans[1].rows[1].options.icon_size == 22 and plans[1].rows[1].options.rows == 1);
assert(p.effects.icon_size == 64 and p.effects.rows == nil, 'Native row limits never change saved preferences.');
-- The room is the whole step, never smaller than the row: these rows touch, so it stays the row's 22 px.
for _, frame in pairs(geometry.groups) do frame.pitch = 22; end;
plans = plan();
assert(plans[1].rows[1].options.icon_size == 22 and plans[1].rows[2].area.y == 62 and plans[1].rows[2].area.height == 22
    and plans[1].y == 40 and plans[1].height == 132, 'Touching rows keep the row room.');
for _, frame in pairs(geometry.groups) do frame.pitch = 30; end;
plans = plan();
assert(plans[1].rows[1].options.icon_size == 30 and plans[1].rows[2].area.y == 58 and plans[1].y == 36 and plans[1].height == 140,
    'A 30 px step gives 30 px, 4 px above and below each row.');
assert(p.effects.icon_size == 64, 'The room never changes the saved size.');
for _, frame in pairs(geometry.groups) do frame.pitch = nil; end;
-- Beside the rows the icons fill the room whatever size is saved.
p.effects.icon_size = 18;
assert(plan()[1].rows[1].options.icon_size == 22, 'Native icons fill the 22 px row, not the 18 px size control.');
p.effects.icon_size = 12;
assert(plan()[1].rows[1].options.icon_size == 22 and p.effects.icon_size == 12,
    'A smaller saved size still fills the row, and stays saved.');
p.effects.icon_size = 18;
local mx, my, pressed, down, cursor, active, item = -1, -1, false, false, {}, nil, nil;
imgui.GetMousePos = function() return mx, my; end;
imgui.IsMouseDown = function() return down; end;
imgui.SetCursorScreenPos = function(pos) cursor = pos; end;
imgui.InvisibleButton = function(id, size)
    item = id;
    if pressed and mx >= cursor[1] and mx < cursor[1] + size[1] and my >= cursor[2] and my < cursor[2] + size[2] then active = id; end;
end;
imgui.IsItemActivated = function() return pressed and item == active; end;
imgui.IsItemActive = function() return down and item == active; end;
local starts, ends, saves, targets, depth = 0, 0, 0, 0, 0;
imgui.PushStyleVar = function() depth = depth + 1; end;
imgui.PopStyleVar = function(n) depth = depth - n; end;
local callbacks = { native_geometry = geometry,
    begin_edit = function() starts = starts + 1; end, end_edit = function() ends = ends + 1; end,
    changed = function() saves = saves + 1; end, target = function() targets = targets + 1; end };
local function draw() return overlay.draw(r, subjects, p, 100, callbacks); end;
local _, shown = draw();
assert(not next(shown) and depth == 0 and #MOCK.font_stack == 0, 'Overlay never claims ownership of game frames.');
local move_plan=plan()[1];
local move_x,move_y=move_plan.x+move_plan.width/2,move_plan.y+move_plan.height/2;
mx, my, pressed, down = move_x, move_y, true, true; draw();
assert(starts == 0 and targets == 0, 'Ordinary clicks pass through.');
callbacks.shift = true; draw(); assert(starts == 0, 'Clicking a strip does not start an edit until it moves');
mx, my, pressed = move_x-30, move_y+20, false; draw();
down = false; draw();
assert(p.groups[1].native_x == -30 and p.groups[1].native_y == 20 and ends == 1 and saves == 1);
assert(p.groups[2].native_x == 0 and p.groups[3].native_y == 0);
p.locked, pressed, down = true, true, true; draw(); assert(starts == 1);
p.locked, r.typing = false, true; draw(); assert(starts == 1);
r.typing = false; draw(); assert(starts == 1);
mx, pressed = move_x-50, false; draw(); p.enabled = false; draw();
assert(saves == 2 and ends == 2 and depth == 0, 'Disabling closes and saves a drag once.');
overlay.cancel_layout_gesture(); assert(saves == 2);
p.enabled, down, pressed, callbacks.shift = true, false, false, false;
for _, key in ipairs({ 'map', 'hidden', 'in_event' }) do
    r[key] = true; local _, groups = draw(); assert(not next(groups)); r[key] = false;
end
geometry.available = false; local _, groups = draw(); assert(not next(groups)); geometry.available = true;
p.preview = true; draw(); assert(targets == 0 and depth == 0 and #MOCK.font_stack == 0);
local paint = require('ui.party_hud').paint_effects;
require('ui.party_hud').paint_effects = function() error('Render error'); end;
assert(not pcall(draw));
assert(depth == 0 and #MOCK.font_stack == 0, 'Render failure unwinds style and font state.');
require('ui.party_hud').paint_effects = paint;
return 'Native strip sizing, slot identity, overflow, collision bounds and Shift gestures';
