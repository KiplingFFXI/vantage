-- The room for each member's icons beside the game's rows: the whole step from one row to the next, whatever icon size
-- a save holds. At 1920x1080 with the game menu at 1:1 the game's rows are 14 px tall and 20 px apart, so the icons draw
-- at 20 px, centred on each row in whole pixels, each member's touching the next member's, and with no space between
-- them. Party cooldown cells and panels of their own keep 3 px between them, and a panel of its own keeps the saved icon
-- size.
local overlay, defaults = require('ui.native_party_hud'), require('ui.party_defaults');
local hud, layout, imgui = require('ui.party_hud'), require('ui.party_layout'), require('imgui');
local store = require('core.store');

-- One function gives the room, in whole pixels, for the strips and the settings alike: the whole step, never less than
-- the row, and the row without a step; a step between whole pixels rounds up, so members never leave a gap. A row or
-- step that float error put a hair off a whole pixel stays on that pixel.
assert(overlay.room(14, 20) == 20 and overlay.room(22, 22) == 22 and overlay.room(14, 15) == 15, 'The whole step, never less than the row.');
assert(overlay.room(14, nil) == 14 and overlay.room(18.9, 27) == 27 and overlay.room(18.9, nil) == 18, 'Without a step the row; whole pixels.');
assert(overlay.room(14, 26.666666666666668) == 27 and overlay.room(14, 23.999999999999996) == 24
    and overlay.room(14, 20.000000000000004) == 20 and overlay.room(13.999999999999998, nil) == 14, 'A part pixel rounds up, float error doesn\'t.');

-- The game's party list at the bottom right of a 1920x1080 screen: count members, rows 14 px tall, step px apart,
-- the last at y 1037 unless bottom says otherwise.
local function party(count, step, bottom, height)
    local roster, subjects = hud.sample(6, 100);
    for index = #roster.members, count + 1, -1 do table.remove(roster.members, index); end;
    height, step, bottom = height or 14, step or 20, bottom or 1037;
    local first = bottom - (count - 1) * step;
    local frame = { x = 1795, y = first, width = 106, height = (count - 1) * step + height, rows = {}, row_height = height,
        pitch = count > 1 and step or nil, measured_by = count > 1 and 'rows' or 'none' };
    for _, member in ipairs(roster.members) do
        frame.rows[member.slot] = { x = 1795, y = first + member.slot * step, width = 106, height = height, slot = member.slot };
        local subject = subjects[member.id];
        subject.effects, subject.known = {}, true;
        for effect = 1, 30 do
            subject.effects[effect] = { effect = effect, name = 'Effect ' .. effect, kind = 'buff', remaining = 30, total = 60, status = 'estimated' };
        end;
    end;
    return roster, subjects, { available = true, groups = { frame } };
end;
local p = defaults.make();
p.enabled, p.effects.icon_size = true, 37;
local roster, subjects, geometry = party(6);
local function plan(screen_height) return overlay.plan(roster, subjects, p, geometry, 1920, screen_height or 1080)[1]; end;
local function cells(item)
    return layout.effect_cells(layout.effects(subjects[item.member.id], item.options), item.options, item.area);
end;
-- The space between each cell and the next on one line.
local function spaces(list)
    local out = {};
    for index = 2, #list do
        if list[index].y == list[1].y then out[#out + 1] = math.abs(list[index].x - list[index - 1].x) - list[index - 1].width; end;
    end;
    return out;
end;
local function all(list, value)
    for _, item in ipairs(list) do if item ~= value then return false; end; end;
    return #list > 0;
end;

-- Every save draws the same: 20 px icons centred on each row in whole pixels, from 3 px above it to 3 px below, so one
-- member's icons end just where the next member's start, and the window grows by 3 px each way. It holds for any icon
-- size. A 420 px strip holds 21 touching icons.
for _, size in ipairs({ 12, 18, 20, 32, 37, 128 }) do
    local what = 'at ' .. size;
    p.effects.icon_size = size;
    local strip = plan();
    assert(strip.y == 934 and strip.height == 120 and strip.width == 420 and #strip.rows == 6, 'A full party\'s window is 120 px: ' .. what);
    for index, item in ipairs(strip.rows) do
        assert(item.options.icon_size == 20 and item.area.y == item.row.y - 3 and item.area.height == 20,
            'Each member\'s icons run from 3 px above the row to 3 px below it: ' .. what);
        if index > 1 then
            local above = strip.rows[index - 1].area;
            assert(item.area.y == above.y + above.height, 'One member\'s icons touch the next member\'s, and never overlap: ' .. what);
        end;
    end;
    local touched = cells(strip.rows[1]);
    assert(#touched == 21 and touched[1].height == 20 and touched[1].icon_size == 20 and touched[1].y == strip.rows[1].row.y - 3
        and all(spaces(touched), 0), 'A 420 px strip holds 21 touching icons of 20 px: ' .. what);
end;
p.effects.icon_size = 37;
assert(p.effects.icon_scale == nil, 'No icon scale: the saved icon size is the size in a panel of its own.');

-- Icons keep the whole room. An area narrower than one icon shows none, with no space left between them it shows the
-- icons that fit, and an empty one works out no place at all.
local three = { { effect = 1, kind = 'buff' }, { effect = 2, kind = 'buff' }, { effect = 3, kind = 'buff' } };
local touching = { icon_size = 20, cell_gap = 0 };
local some, left_out = layout.effect_cells(three, touching, { x = 0, y = 0, width = 15, height = 20 });
assert(#some == 0 and left_out == 3, 'No room for one 20 px icon: none show.');
some, left_out = layout.effect_cells(three, touching, { x = 0, y = 0, width = 45, height = 20 });
assert(#some == 2 and left_out == 1 and some[1].width == 20 and some[2].width == 20 and some[2].x == 20, 'Two whole icons fit in 45 px.');
local used;
some, left_out, used = layout.effect_cells(three, touching, { x = 0, y = 0, width = 0, height = 20 });
assert(#some == 0 and left_out == 3 and used == 0, 'An empty area places nothing.');
-- Beside the game's list, a strip with less space than one icon shows none and the settings say why, and a Longest
-- row under one icon still gives that icon its whole room.
local window = geometry.groups[1];
window.x = 41;
for _, row in pairs(window.rows) do row.x = 41; end;
local tight = plan();
assert(tight.width == 15 and overlay.no_room and #cells(tight.rows[1]) == 0, 'With 15 px beside the list no 20 px icon shows.');
window.x = 1795;
for _, row in pairs(window.rows) do row.x = 1795; end;
assert(plan().width == 420 and not overlay.no_room, 'With room again they show.');
roster, subjects, geometry = party(6, 50, 1037, 40);
p.native.width = 40;
local roomy = plan();
local first = cells(roomy.rows[1]);
assert(roomy.width == 50 and #first == 1 and first[1].width == 50 and not overlay.no_room, 'A 40 px Longest row still shows one 50 px icon.');
p.native.width = 420;

-- Five members: a 100 px window from 3 px above the first row.
roster, subjects, geometry = party(5);
assert(plan().height == 100 and plan().y == geometry.groups[1].y - 3);

-- Growing with its buffs, the strip needs the room's width for each icon and nothing between them.
roster, subjects, geometry = party(6);
for _, member in ipairs(roster.members) do
    local list = subjects[member.id].effects;
    for index = #list, 4, -1 do list[index] = nil; end;
end;
assert(plan().width == 3 * 20, 'Three touching 20 px icons need 60 px.');

-- A panel of its own keeps the saved icon size and 3 px between icons.
roster, subjects, geometry = party(6);
local group = p.groups[1];
group.native_detached, group.detached_x, group.detached_y, group.detached_width, group.detached_height = true, 200, 200, 420, 600;
local panel = plan();
local in_panel = cells(panel.rows[1]);
assert(panel.detached and panel.rows[1].options.icon_size == 37 and in_panel[1].icon_size == 37 and all(spaces(in_panel), 3),
    'A panel of its own draws 37 px icons 3 px apart.');
group.native_detached = false;

-- Scaled rows: the room is the whole step, and the shift above each row whole pixels.
roster, subjects, geometry = party(6, 27, 1000, 18.9);
for _, item in ipairs(plan().rows) do
    assert(item.options.icon_size == 27 and item.row.y - item.area.y == 4 and item.area.height == 27, 'Centred in whole pixels on a scaled row.');
end;

-- Rows that touch, 22 px tall and 22 apart: the room is the row, drawn on it.
roster, subjects, geometry = party(6, 22, 1037, 22);
local same = plan();
assert(same.y == geometry.groups[1].y and same.height == geometry.groups[1].height, 'Touching rows keep the window.');
for _, item in ipairs(same.rows) do
    assert(item.options.icon_size == 22 and item.area.y == item.row.y and item.area.height == 22, 'Touching rows keep each area.');
end;

-- One member with no measured step: the row, 14 px.
roster, subjects, geometry = party(1);
local solo = plan();
assert(solo.y == geometry.groups[1].y and solo.height == 14 and solo.rows[1].area.y == solo.rows[1].row.y
    and solo.rows[1].options.icon_size == 14, 'Solo without a step draws at the row.');
-- With a step measured another way (the game's empty slots, or earlier this session) it takes the whole step.
local alone = geometry.groups[1].y;
geometry.groups[1].pitch, geometry.groups[1].measured_by = 20, 'session';
solo = plan();
assert(solo.y == alone - 3 and solo.height == 20 and solo.rows[1].options.icon_size == 20, 'Solo with a remembered step takes 20 px.');

-- The window stays on the screen: at the very bottom the strip moves up by the overhang, at the very top it starts at 0.
roster, subjects, geometry = party(6, 20, 1066);
local strip = plan();
assert(strip.y + strip.height <= 1080 and strip.height == 120 and strip.rows[6].area.y + strip.rows[6].area.height <= 1080,
    'The grown window fits above the screen\'s bottom.');
roster, subjects, geometry = party(6, 20, 100);
strip = plan();
assert(strip.y == 0 and strip.rows[1].area.y >= 0, 'The grown window starts at the top of the screen.');

-- Another group's window that touches only the overhang still bounds the strip.
roster, subjects, geometry = party(6);
geometry.groups[2] = { x = 1600, y = 800, width = 106, height = 136, rows = {} };
assert(plan().width == 1769 - 1706 - 26, 'The strip stops the same 26 px before the window above.');
geometry.groups[2] = nil;

-- The per-group summary the settings read gives the same room the strips draw.
roster, subjects, geometry = party(6);
local rooms = overlay.rooms(p, geometry);
assert(#rooms == 1 and rooms[1].group == 1 and rooms[1].row_height == 14 and rooms[1].pitch == 20 and rooms[1].room == 20
    and rooms[1].measured_by == 'rows' and rooms[1].attached == true and rooms[1].members == 6);
assert(overlay.rooms(p, geometry)[1].room == 20 and plan().rows[1].options.icon_size == 20, 'The summary matches what draws.');
p.groups[1].native_detached = true;
assert(overlay.rooms(p, geometry)[1].attached == false, 'A strip in a panel of its own is not attached.');
p.groups[1].native_detached = false;
assert(#overlay.rooms(p, store.copy(geometry)) == 1, 'The status copy reads the same.');
p.strips.party = false; assert(#overlay.rooms(p, geometry) == 0, 'A strip switched off is left out.'); p.strips.party = true;
geometry.available = false; assert(#overlay.rooms(p, geometry) == 0); geometry.available = true;
assert(#overlay.rooms(p, nil) == 0 and #overlay.rooms(p, { available = true }) == 0, 'No geometry gives an empty list.');
roster, subjects, geometry = party(1);
rooms = overlay.rooms(p, geometry);
assert(rooms[1].pitch == nil and rooms[1].room == 14 and rooms[1].measured_by == 'none' and rooms[1].members == 1,
    'Solo without a step reads the row.');
roster, subjects, geometry = party(6, 22, 1037, 22);
rooms = overlay.rooms(p, geometry);
assert(rooms[1].room == 22, 'Touching rows give the row.');
local frame = geometry.groups[1];
frame.row_height, frame.measured_by = nil, nil;
rooms = overlay.rooms(p, geometry);
assert(rooms[1].row_height == 22 and rooms[1].measured_by == 'rows', 'A geometry without its summary fields reads its rows.');

-- The room is always the whole step, so fresh settings have no room choice.
assert(defaults.make().effects.row_room == nil, 'Fresh settings have no room choice.');

-- An export holds no room either. Add and Replace bring none, so a string of fresh settings changes nothing and
-- Profiles and sharing says so.
local share, settings = require('core.share'), require('ui.defaults').tidy(require('ui.defaults').make());
for _, kind in ipairs({ 'element', 'profile' }) do
    local clean = assert(share.read(assert(share.export(settings, kind, kind == 'element' and 'party_ui' or nil, 'Tester'))));
    assert((clean.data.party_ui or clean.data).effects.row_room == nil, 'A string holds no room: ' .. kind);
    for _, mode in ipairs({ 'add', 'replace' }) do
        local base = require('ui.defaults').tidy(require('ui.defaults').make());
        local candidate = assert(share.candidate(base, clean, mode));
        assert(candidate.party_ui.effects.row_room == nil, 'An import brings no room: ' .. kind .. ' ' .. mode);
        local lines = share.changes(base, candidate);
        assert(#lines == 1 and lines[1] == 'Nothing changes.', 'Nothing changes: ' .. kind .. ' ' .. mode .. ': ' .. table.concat(lines, ' | '));
    end;
end;

-- Shift on an attached strip's edge shows the move cursor; a panel of its own shows a resize one there.
local mx, my, cursor, shown = -1, -1, {}, {};
ImGuiMouseCursor_ResizeAll, ImGuiMouseCursor_ResizeEW, ImGuiMouseCursor_ResizeNS = 'all', 'ew', 'ns';
ImGuiMouseCursor_ResizeNWSE, ImGuiMouseCursor_ResizeNESW = 'nwse', 'nesw';
imgui.GetMousePos = function() return mx, my; end;
imgui.SetCursorScreenPos = function(value) cursor = value; end;
imgui.InvisibleButton = function() end;
imgui.IsItemHovered = function() return true; end;
imgui.SetMouseCursor = function(value) shown[#shown + 1] = value; end;
roster, subjects, geometry = party(6);
p.locked = false;
strip = plan();
mx, my = strip.x + 1, strip.y + strip.height / 2;
local callbacks = { shift = true, native_geometry = geometry };
MOCK.screen = { 1920, 1080 };
overlay.draw(roster, subjects, p, 100, callbacks);
assert(shown[#shown] == 'all', 'An attached strip\'s edge only moves it.');
p.groups[1].native_detached, p.groups[1].detached_x, p.groups[1].detached_y = true, 200, 200;
p.groups[1].detached_width, p.groups[1].detached_height = 300, 240;
mx, my = 201, 320;
overlay.draw(roster, subjects, p, 100, callbacks);
assert(shown[#shown] == 'ew', 'A panel of its own resizes from its edge.');
assert(cursor[1] == 200 and #MOCK.font_stack == 0);
overlay.cancel_layout_gesture();
return 'Party strip room: the whole step for every save, touching icons, 3 px for panels, summary and shares';
