-- HUD polish: previewed panels wear a SAMPLE tag, Shift over a locked display says where to unlock it, size labels
-- keep clear of other displays, and the resize cursor stays through a drag.
local imgui, resize = require('imgui'), require('ui.resize');
local defaults = require('ui.defaults');
local party_hud, native_hud, hud = require('ui.party_hud'), require('ui.native_party_hud'), require('ui.hud');
local NOTE = 'Locked: unlock it on the main page';

local function texts(value)
    local out = {};
    for index, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddText' and call[6] == value then out[#out + 1] = { x = call[4][1], y = call[4][2], ink = call[5], index = index }; end;
    end;
    return out;
end;
local function count(name)
    local total = 0;
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == name then total = total + 1; end; end;
    return total;
end;

-- Window rectangles and the pointer, as the overlays see them.
local position, size, rects, mx, my = {}, {}, {}, -1, -1;
imgui.SetNextWindowPos = function(value) position = { value[1], value[2] }; end;
imgui.SetNextWindowSize = function(value) size = { value[1], value[2] }; end;
imgui.Begin = function(name)
    rects[name] = { x = position[1], y = position[2], width = size[1], height = size[2] };
    return true;
end;
imgui.GetMousePos = function() return mx, my; end;
local function inside(rect) return rect.x + rect.width / 2, rect.y + rect.height / 2; end;

-- Shift over a locked display shows the note; it adds no mouse target, and moving off it or unlocking hides it.
local s = defaults.make();
for key, panel in pairs(s.panels) do panel.enabled = key == 'self_buffs'; end;
local view = hud.sample(100);
s.window.open = false;
hud.draw(view, s, 100, { shift = true });
mx, my = inside(rects['##vantage_self_buffs']);
MOCK.imgui_calls = {};
hud.draw(view, s, 100, { shift = true });
assert(#texts(NOTE) == 1 and count('InvisibleButton') == 0, 'A locked timer panel shows the note and catches nothing.');
MOCK.imgui_calls = {};
hud.draw(view, s, 100, { shift = false });
assert(#texts(NOTE) == 0, 'Without Shift there is no note.');
view.context.chat_open = true;
MOCK.imgui_calls = {};
hud.draw(view, s, 100, { shift = true });
assert(#texts(NOTE) == 0, 'Typing in chat shows no note.');
view.context.chat_open = false;
mx, my = 5, 5;
MOCK.imgui_calls = {};
hud.draw(view, s, 100, { shift = true });
assert(#texts(NOTE) == 0, 'The note shows only with the pointer on the display.');
s.panels.self_buffs.locked = false;
mx, my = inside(rects['##vantage_self_buffs']);
MOCK.imgui_calls = {};
hud.draw(view, s, 100, { shift = true });
assert(#texts(NOTE) == 0 and count('InvisibleButton') == 1, 'An unlocked panel shows its handles instead.');

-- The same note on locked notices and party list strips.
view.notices = { { visual = true, message = 'Protect is ending soon.', ends = 200 } };
hud.draw_notices(view, s, 100, { shift = true });
mx, my = inside(rects['##vantage_notices']);
MOCK.imgui_calls = {};
hud.draw_notices(view, s, 100, { shift = true });
assert(#texts(NOTE) == 1, 'Locked notices show the note.');
local roster, subjects = party_hud.sample(6, 100);
-- The game's party window, with a row for each member.
local game = { available = true, groups = { { x = 1300, y = 300, width = 200, height = 6 * 30, rows = {} } } };
for _, member in ipairs(roster.members) do
    game.groups[1].rows[member.slot] = { x = 1300, y = 300 + member.slot * 30, width = 200, height = 30, slot = member.slot };
end;
local p = s.party_ui;
p.enabled = true;
local function strips(options)
    options.native_geometry, options.global_style = game, s.style;
    return native_hud.draw(roster, subjects, p, 100, options);
end;
strips({ shift = true });
mx, my = inside(rects['##vantage_native_1']);
MOCK.imgui_calls = {};
strips({ shift = true });
assert(#texts(NOTE) == 1, 'A locked party strip shows the note.');
roster.typing = true;
MOCK.imgui_calls = {};
strips({ shift = true });
assert(#texts(NOTE) == 0, 'Typing in chat shows no note on the party strip either.');
roster.typing = false;
MOCK.imgui_calls = {};
strips({ shift = true, input_blocked = true });
assert(#texts(NOTE) == 0, 'Over the settings window there is no note.');

-- Icon panels in a sample preview wear the tag; bars panels say Sample in their heading.
s = defaults.make();
for key, panel in pairs(s.panels) do panel.enabled = key == 'self_buffs' or key == 'party'; end;
s.preview = true;
MOCK.imgui_calls = {};
hud.draw(hud.sample(100), s, 100, {});
assert(#texts('SAMPLE') == 1, 'The previewed icon panel wears one tag; the bars panel does not.');

-- A size label goes above its display, or below it when another display is there.
local list = imgui.GetWindowDrawList();
local lower, upper = { x = 100, y = 300, width = 200, height = 60 }, { x = 100, y = 200, width = 200, height = 90 };
local function label_box(rect, name)
    MOCK.imgui_calls = {};
    resize.hint(list, rect, 0xFFFFFFFF, nil, name, { font = 'Agave', font_size = 16 });
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddRectFilled' and call[4] == 0xFA171717 then return { y = call[2][2], bottom = call[3][2] }; end;
    end;
end;
resize.frame();
assert(label_box(lower, 'Lower').bottom <= lower.y, 'With nothing above it, a label sits above its display.');
resize.frame();
label_box(upper, 'Upper');
resize.frame();
local placed = label_box(lower, 'Lower');
assert(placed.y >= lower.y + lower.height, 'With a display above it, the label goes below.');
resize.frame(); resize.frame();
assert(label_box(lower, 'Lower').bottom <= lower.y, 'Once that display is no longer drawn, the label goes back above.');
resize.frame(); resize.frame();

-- The resize cursor stays while a drag is held, also with the pointer past the display.
local down, item, cursors = false, nil, 0;
imgui.IsMouseDown = function() return down; end;
imgui.SetCursorScreenPos = function(value) item = { x = value[1], y = value[2] }; end;
imgui.InvisibleButton = function(_, dimensions) item.width, item.height = dimensions[1], dimensions[2]; return false; end;
imgui.IsItemHovered = function() return item and mx >= item.x and mx < item.x + item.width and my >= item.y and my < item.y + item.height; end;
imgui.IsItemActivated = function() return down and imgui.IsItemHovered(); end;
imgui.IsItemActive = function() return down; end;
imgui.SetMouseCursor = function() cursors = cursors + 1; end;
local function held(draw, name)
    native_hud.cancel_layout_gesture();
    down, cursors = false, 0;
    draw();
    local rect = rects[name];
    mx, my, down = rect.x + rect.width - 1, rect.y + rect.height / 2, true;
    draw();
    mx, cursors = rect.x + rect.width + 900, 0;
    draw();
    local kept = cursors > 0;
    down = false;
    draw();
    return kept;
end;
s = defaults.make();
p = s.party_ui;
p.enabled, p.locked = true, false;
p.groups[1].native_detached, p.groups[1].detached_x, p.groups[1].detached_y = true, 400, 200;
p.groups[1].detached_width, p.groups[1].detached_height = 300, 200;
assert(held(function() native_hud.draw(roster, subjects, p, 100, { shift = true, global_style = s.style, native_geometry = game }); end,
    '##vantage_native_1'), 'A detached party strip keeps the resize cursor through a held drag.');
return 'Outlined footers, sample tags, the locked note, placed labels and the resize cursor';
