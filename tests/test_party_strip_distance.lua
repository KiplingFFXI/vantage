-- The distance on Party list (ui/native_party_hud.lua with core/party_distance.lua). Beside the game's list
-- it has a fixed column of its own nearest the list on every row, right-aligned, in the countdowns' look and color or
-- the warning color past the pick, at the size Distance size picks. Off, nothing moves. In a panel of its own it ends
-- the name's first line. Samples go by slot, your own row and members with no distance show none, and pointing at a
-- number gives its tooltip.
local overlay = require('ui.native_party_hud');
local imgui = require('imgui');
local countdown = require('ui.countdown_text');
local metrics = require('ui.text_metrics');
local theme = require('ui.party_theme');
local p = require('ui.party_defaults').make();
-- Text three quarters as tall as its size, rounded down, like the game's digits, with each letter half as wide, so the
-- number's size can be checked against the row, and the size has to be found by stepping up from where the search
-- starts.
rawset(imgui, 'CalcTextSize', function(text)
    local size = imgui.GetFontSize();
    return #tostring(text) * size / 2, math.floor(size * 3 / 4);
end);
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
p.enabled, p.locked = true, true;
local function plan() return overlay.plan(r, subjects, p, geometry, 1280, 720); end
local function by_slot(plans, group)
    local out = {};
    for _, row in ipairs(plans[group].rows) do out[row.member.slot] = row; end
    return out;
end

-- Off, the rows have no column and the strip is as it was.
local off = plan();
local off_x, off_width, off_area = off[1].x, off[1].width, off[1].rows[2].area.width;
assert(off[1].rows[1].distance_cell == nil and off_x + off_width == 874, 'Off, no column.');

-- On, every row gets the column nearest the game's list, as wide as the widest number plus 4 px, and the strip grows by
-- it, still 26 px from the list. The icons keep their room. Small, the default, is the size the numbers started at,
-- 0.6 of the 22 px row.
p.distance = true;
local plans = plan();
local options = plans[1].rows[1].options;
local function tall(at) return select(2, countdown.measure('Ashita', '0123456789', at, options, true)); end
local function column_at(at)
    return math.ceil(math.max((countdown.measure('Ashita', '00.0', at, options, true)),
        (countdown.measure('Ashita', '88.8', at, options, true)))) + 4;
end
local size = 13;
local column = column_at(size);
assert(p.distance_size == 'small' and column > 4, 'Fixture: Small to start.');
-- Small rounds 0.6 of the row to the nearest pixel, 12.6 to 13 in a 21 px row, and is never under 8 px.
local function small_at(height)
    for _, row in pairs(geometry.groups[1].rows) do row.height = height; end
    local cell = plan()[1].rows[1].distance_cell;
    for _, row in pairs(geometry.groups[1].rows) do row.height = 22; end
    return cell and cell.size;
end
assert(small_at(21) == 13 and small_at(10) == 8, 'Small is 0.6 of the row, rounded, and never under 8 px: '
    .. tostring(small_at(21)) .. ' ' .. tostring(small_at(10)));
assert(plans[1].x + plans[1].width == 874 and plans[1].width == off_width + column, 'The strip grows by the column.');
for _, row in ipairs(plans[1].rows) do
    local cell, area = row.distance_cell, row.area;
    assert(cell and cell.width == column and cell.size == size and cell.x + cell.width == 874, 'Each row has the column by the list.');
    assert(area.x + area.width == cell.x and area.width == off_area, 'The icons end where the column starts, with their room.');
    assert(cell.y == area.y and cell.height == area.height and cell.align_right, 'The column is the row\'s height.');
end
-- Past Small, the digits with their outline and shadow are as tall as they can be up to 70, 80 or 90% of the row, 15,
-- 17 or 19 px of 22, and the column widens to fit. The guess from 16 px is short each time, so the search has to step
-- up.
local function sized(pick, pitch)
    p.distance_size, geometry.groups[1].pitch = pick, pitch;
    local group = plan()[1];
    p.distance_size, geometry.groups[1].pitch = 'small', nil;
    return group.rows[1].distance_cell, group;
end
for pick, want in pairs({ medium = { 18, 15 }, large = { 21, 17 }, largest = { 23, 19 } }) do
    local cell, group = sized(pick);
    assert(cell.size == want[1] and tall(cell.size) <= want[2] and tall(cell.size + 1) > want[2],
        'Distance size ' .. pick .. ' fits ' .. want[2] .. ' px: ' .. cell.size);
    assert(cell.width == column_at(cell.size) and group.width == off_width + cell.width, 'The column widens to fit: ' .. pick);
end
-- Where the step between rows is less than the room, as at a menu size that puts it between pixels, the digits fit
-- the step, so they keep their space from the next member's. Small stays 0.6 of the row.
local stepped = sized('largest', 21.5);
assert(stepped.size == 22 and tall(stepped.size) == 18, 'Largest fits 90% of the 21 px step: ' .. stepped.size);
assert(sized('small', 21.5).size == size, 'Small doesn\'t change with the step.');
-- For a font whose digits grow faster past 16 px than the guess allows, the search steps down, and for one whose
-- digits are tall for their size, no pick is smaller than Small.
local scaled = imgui.CalcTextSize;
rawset(imgui, 'CalcTextSize', function(text)
    local at = imgui.GetFontSize();
    return #tostring(text) * at / 2, at + 2 * math.max(0, at - 16);
end);
assert(sized('largest').size == 16, 'The search steps down from a guess that\'s too big: ' .. sized('largest').size);
rawset(imgui, 'CalcTextSize', function(text)
    local at = imgui.GetFontSize();
    return #tostring(text) * at / 2, at + 8;
end);
assert(sized('medium').size == size, 'Medium is never smaller than Small: ' .. sized('medium').size);
-- And for one whose digits measure the same at any size, the search stops at twice the room.
rawset(imgui, 'CalcTextSize', function(text)
    return #tostring(text) * imgui.GetFontSize() / 2, 4;
end);
assert(sized('largest').size == 44, 'The search stops at twice the room: ' .. sized('largest').size);
rawset(imgui, 'CalcTextSize', scaled);
p.native.side = 'right';
plans = plan();
local right = plans[1].rows[2];
assert(right.distance_cell.x == 1042 and right.area.x == 1042 + column and not right.distance_cell.align_right,
    'On the right side the column is first, and the icons after it.');
p.native.side = 'left';
-- Turned off again, nothing moves.
p.distance = false;
plans = plan();
assert(plans[1].x == off_x and plans[1].width == off_width and plans[1].rows[2].distance_cell == nil, 'Off again, as before.');
p.distance = true;

-- No room for the column and one icon says so, as no room for one icon does with it off.
geometry.groups[1].x = 26 + 22 + column - 1;
for _, row in pairs(geometry.groups[1].rows) do row.x = geometry.groups[1].x; end
local narrow = plan();
assert(overlay.no_room == true, 'The column and one icon don\'t fit.');
for _, row in ipairs(narrow[1].rows) do
    assert(row.distance_cell == nil and row.area.width == 0, 'Nor does half a number, or an icon, as the line says.');
end
p.distance = false; plan();
assert(overlay.no_room == false, 'One icon fits without the column.');
p.distance = true;
geometry.groups[1].x = 900;
for _, row in pairs(geometry.groups[1].rows) do row.x = 900; end

-- The paint: a list that keeps every text pass in order, and each text's last pass, the fill, with its ink and place.
local texts, passes = {}, {};
local list = setmetatable({}, { __index = function(_, name)
    if name == 'AddText' then
        return function(_, _, at, point, ink, text)
            texts[text] = { x = point[1], y = point[2], ink = ink, size = at };
            passes[#passes + 1] = texts[text];
        end;
    end;
    return function() end;
end });
local tips = {};
local mx, my = -1, -1;
rawset(imgui, 'GetWindowDrawList', function() return list; end);
rawset(imgui, 'GetMousePos', function() return mx, my; end);
rawset(imgui, 'IsWindowHovered', function() return false; end);
rawset(imgui, 'IsMouseDown', function() return false; end);
rawset(imgui, 'TextUnformatted', function(text) tips[#tips + 1] = text; end);
local callbacks = { native_geometry = geometry };
local function draw()
    for key in pairs(texts) do texts[key] = nil; end
    for index = #passes, 1, -1 do passes[index] = nil; end
    for index = #tips, 1, -1 do tips[index] = nil; end
    overlay.draw(r, subjects, p, 100, callbacks);
end
local look = theme.party(p, nil);
local plain_ink = theme.u32(look.gauge_text_color, look.opacity);
local warning = require('ui.theme').colors('Phoenix').warning_color;
local warn_ink = theme.u32(warning, look.opacity);
local function numbers()
    local out = {};
    for text in pairs(texts) do if text:match('^%d+%.%d$') then out[#out + 1] = text; end end
    table.sort(out);
    return table.concat(out, ' ');
end

-- Bramble (slot 1) at 20.4 and Cinder (slot 2) at 21.9 past Spell range. Your own row and the others show none.
local members = {};
for _, member in ipairs(r.members) do members[member.slot] = member; end
members[0].tenths = 50;
members[1].tenths, members[1].far = 204, false;
members[2].tenths, members[2].far = 219, true;
draw();
assert(numbers() == '20.4 21.9', 'Only the members with a distance: ' .. numbers());
assert(texts['20.4'].ink == plain_ink and texts['21.9'].ink == warn_ink, 'The countdowns\' color, and the warning color past the pick.');
local rows = by_slot(plan(), 1);
local left, top = countdown.padding(rows[1].options);
for slot, text in pairs({ [1] = '20.4', [2] = '21.9' }) do
    local cell = rows[slot].distance_cell;
    local width = countdown.measure(look.font, text, size, rows[slot].options, true);
    assert(texts[text].x == math.floor(cell.x + cell.width - width + 0.5) + left, 'Right-aligned against the list: ' .. text);
    assert(texts[text].y == cell.y + 6 + top, 'Centered in its row, 5.5 px from the top rounded, outline included: ' .. text);
    assert(texts[text].size == size, 'At the column\'s size: ' .. text);
end
-- On the right side it ends 4 px short of the icons.
p.native.side = 'right';
draw();
rows = by_slot(plan(), 1);
local width = countdown.measure(look.font, '20.4', size, rows[1].options, true);
assert(texts['20.4'].x == math.floor(rows[1].distance_cell.x + rows[1].distance_cell.width - 4 - width + 0.5) + left,
    'On the right side it ends 4 px short of the icons.');
p.native.side = 'left';
-- With a style, its Ending soon and alerts color.
callbacks.global_style = { warning_color = { 0, 1, 0, 1 } };
draw();
assert(texts['21.9'].ink == theme.u32({ 0, 1, 0, 1 }, look.opacity), 'The main page\'s warning color.');
callbacks.global_style = nil;

-- Pointing at a number gives its tooltip, and at your own row's empty column nothing.
rows = by_slot(plan(), 1);
mx, my = rows[1].distance_cell.x + 2, rows[1].distance_cell.y + 2;
draw();
assert(#tips == 1 and tips[1]:find('^Bramble\n20%.4 yalms from you, counting height%.'), 'The tooltip: ' .. tostring(tips[1]));
mx, my = rows[0].distance_cell.x + 2, rows[0].distance_cell.y + 2;
draw();
assert(#tips == 0, 'Your own row has no tooltip.');
mx, my = -1, -1;

-- Samples by slot, your own row too, colored as if both of you were Hume. Area picks never color the alliance.
p.preview = true;
draw();
assert(numbers() == '14.3 20.4 21.9 30.6 4.2 9.6', 'Samples by slot: ' .. numbers());
local function ink_of(group, slot)
    rows = by_slot(plan(), group);
    local cell, ink = rows[slot].distance_cell, nil;
    for _, entry in ipairs(passes) do
        if entry.y >= cell.y and entry.y < cell.y + cell.height and entry.x >= cell.x and entry.x < cell.x + cell.width then
            ink = entry.ink;
        end
    end
    return ink;
end
assert(ink_of(1, 4) == warn_ink and ink_of(1, 3) == plain_ink and ink_of(2, 10) == warn_ink, 'Spell range colors the alliance too.');
p.distance_warn = 'ten';
draw();
assert(ink_of(1, 2) == warn_ink and ink_of(1, 1) == plain_ink and ink_of(2, 10) == plain_ink, 'An area pick never colors the alliance.');
p.distance_warn = 'none';
draw();
assert(ink_of(1, 5) == plain_ink, 'Never leaves every number plain.');
p.distance_warn, p.preview = 'spell', false;

-- In a panel of its own: the number ends the name's first line, the name wraps short of it, and the panel's least
-- width grows to fit it.
local own = p.groups[1];
own.native_detached, own.detached_x, own.detached_y, own.detached_width, own.detached_height = true, 300, 200, 260, 500;
p.distance = false;
local before = plan()[1];
local least, label_width = before.min_width, before.rows[2].label_width;
p.distance = true;
local panel = plan()[1];
local function wide(text) return metrics.width(look.font, text, look.font_size); end
local room = math.ceil(math.max(wide('00.0'), wide('88.8'))) + 6;
-- The name's line needs a letter and the number, and the icons' line an icon, as before.
local name_least = math.max(40, math.ceil(math.max(wide('W'), wide('M'), wide('0')) + 30));
local wanted = math.max(name_least + room, p.effects.icon_size + 30);
assert(least == math.max(name_least, p.effects.icon_size + 30) and wanted > least, 'Fixture: the number widens the panel.');
assert(panel.detached and panel.min_width == wanted, 'The least width grows to fit the number: ' .. panel.min_width);
local bob = panel.rows[2];
assert(bob.label_width == label_width - room and bob.distance_right == bob.label_x + label_width, 'The name wraps short of it.');
draw();
local text_ink = theme.u32(look.colors.text, look.opacity);
assert(texts['20.4'] and texts['20.4'].ink == text_ink and texts['21.9'].ink == warn_ink, 'The text color, or the warning color.');
local number_width = math.ceil(metrics.width(look.font, '20.4', look.font_size)) + 1;
assert(texts['20.4'].x == bob.distance_right - number_width and texts['20.4'].y == bob.label_y, 'At the end of the first line.');
-- Distance size doesn't reach it. The number keeps the name's text size and its place.
p.distance_size = 'largest';
assert(plan()[1].min_width == wanted, 'Largest leaves the panel\'s least width.');
draw();
assert(texts['20.4'].size == look.font_size and texts['20.4'].x == bob.distance_right - number_width, 'Largest leaves the number.');
p.distance_size = 'small';
-- The mouse on the number gives its tooltip, and on the name the name.
mx, my = bob.distance_right - 2, bob.label_y + 2;
draw();
assert(#tips == 1 and tips[1]:find('20.4 yalms from you', 1, true), 'The number\'s tooltip in a panel.');
mx = bob.label_x + 2;
draw();
assert(#tips == 1 and tips[1] == 'Bramble', 'The name\'s tooltip: ' .. tostring(tips[1]));
mx, my = -1, -1;
assert(overlay.panel_size(p, 1, 40, 1280, 720) == wanted, 'A panel sized to fit settles with the number.');
p.distance = false;
assert(overlay.panel_size(p, 1, 40, 1280, 720) == least, 'And without it.');
own.native_detached = false;
return 'The distance column, its colors, samples, panel and tooltip';
