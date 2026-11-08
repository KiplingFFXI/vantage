-- Party buff icons beside the game's party list at other game menu sizes, read from the game's memory as
-- core/native_party_ui.lua reads it. The menu at 1:1, 1600x900 and 1440x810 in 1920x1080, 1920x1080 in 2560x1440 and
-- 1280x720 in 1920x1080 scale the game's rows by 1, 1.2, 4/3, 4/3 and 1.5. Each member's icons fill the step from one
-- row to the next in whole pixels, centred on the row to the nearest pixel, and touch the next member's: no gap at any
-- join, and where the step isn't a whole number of pixels at most 1 px of overlap. The strip's window takes in the icons above the first row
-- and below the last, another group's window there still bounds the strip, the line in the settings gives the size
-- that draws, and the pointer over a pixel two members share finds the lower member, whose icons draw on top.
local native, overlay = require('core.native_party_ui'), require('ui.native_party_hud');
local defaults, hud, layout, widget = require('ui.party_defaults'), require('ui.party_hud'), require('ui.party_layout'), require('ui.party_size_widget');

-- The game's memory as tests/test_native_geometry.lua lays it out, each group's six rows 14 px tall and 20 px apart in
-- menu pixels, the party's last row at bottom.
local mem = {};
local function put16(at, value) value = value % 65536; mem[at], mem[at + 1] = value % 256, math.floor(value / 256); end;
local function row(group, index, x, y, w, h)
    local node, item = 0x60000 + group * 0x1000 + index * 0x40, 0x80000 + group * 0x1000 + index * 0x80;
    mem[node], mem[node + 0x10], mem[node + 0x14] = 0, item, 0;
    if index == 1 then mem[0x40000 + group * 0x100 + 0x14] = node; else mem[node - 0x40] = node; end;
    put16(item, 1); put16(item + 0x3A, index);
    put16(item + 0x2A, x); put16(item + 0x2C, y); put16(item + 0x2E, w); put16(item + 0x30, h);
end;
local function game(menu_width, bottom)
    mem = {};
    mem[0x10019], mem[0x11001], mem[0x11007] = 0x20100, 0x20200, 0x20300;
    for group = 1, 3 do
        local container, ptr = 0x30000 + group * 0x100, 0x40000 + group * 0x100;
        mem[0x20000 + group * 0x100], mem[container], mem[container + 8] = container, 0x50000, ptr;
        mem[ptr + 0x0C], mem[ptr + 0x69], mem[ptr + 0x6A] = container, 1, 1;
        require('native_menu_fixture')(mem, container, ptr, group);
        for index = 1, 6 do row(group, index, menu_width - 125, bottom - (6 - index) * 20 - (group - 1) * 140, 106, 14); end;
    end;
    native._set_platform({
        valid = function(ptr, _, write) return not write and mem[ptr] ~= false; end,
        read32 = function(ptr) return mem[ptr]; end,
        read8 = function(ptr) return mem[ptr]; end,
        write8 = function() error('Geometry is read only.'); end,
        find = function(pattern, usage) return usage == 1 and 0 or pattern:sub(1, 2) == '6D' and 0x12000 or pattern:sub(1, 2) == '66' and 0x10000 or 0x11000; end,
    });
end;
local function whole(...)
    for _, value in ipairs({ ... }) do if type(value) ~= 'number' or value ~= math.floor(value) then return false; end; end;
    return true;
end;

local roster, subjects = hud.sample(6, 100);
local p = defaults.make();
p.enabled = true;

-- Screen width and height, menu width and height, and the size the icons draw at.
local cases = {
    { 1920, 1080, 1920, 1080, 20 }, { 1920, 1080, 1600, 900, 24 }, { 1920, 1080, 1440, 810, 27 },
    { 2560, 1440, 1920, 1080, 27 }, { 1920, 1080, 1280, 720, 30 },
};
local share;
for _, case in ipairs(cases) do
    local width, height, menu_width, menu_height, size = case[1], case[2], case[3], case[4], case[5];
    local what = menu_width .. 'x' .. menu_height .. ' in ' .. width .. 'x' .. height;
    local menu, overlaps, steps = { width = menu_width, height = menu_height }, 0, 0;
    -- 60 places one menu pixel apart, so a row lands on every part of a screen pixel the scale gives.
    for bottom = menu_height - 43 - 59, menu_height - 43 do
        game(menu_width, bottom);
        local geometry = native.geometry(roster, width, height, menu);
        local rooms = overlay.rooms(p, geometry);
        assert(geometry.available and rooms[1].room == size and math.abs(rooms[1].pitch - 20 * width / menu_width) < 0.001,
            'The step is read from the game\'s rows and the icons get it in whole pixels: ' .. what);
        assert(widget.step(p, rooms):find('(' .. size .. ' px here)', 1, true), 'The settings line gives the size that draws: ' .. what);
        local strip = overlay.plan(roster, subjects, p, geometry, width, height)[1];
        assert(#strip.rows == 6 and whole(strip.x, strip.y, strip.width, strip.height), 'The strip\'s window is on whole pixels: ' .. what);
        for index, item in ipairs(strip.rows) do
            local area, game_row = item.area, item.row;
            assert(item.options.icon_size == size and area.height == size and whole(area.x, area.y), 'Each member\'s icons are ' .. size .. ' px: ' .. what);
            assert(math.abs(area.y + size / 2 - (game_row.y + game_row.height / 2)) <= 0.5 + 1e-9, 'Centred on the game\'s row to the nearest pixel: ' .. what);
            local cells = layout.effect_cells(layout.effects(subjects[item.member.id], item.options), item.options, area);
            for number, cell in ipairs(cells) do
                assert(cell.height == size and cell.y == area.y and (number == 1 or math.abs(cell.x - cells[number - 1].x) == size),
                    'Icons touch side to side: ' .. what);
            end;
            if index > 1 then
                local above = strip.rows[index - 1].area;
                local join = area.y - (above.y + above.height);
                assert(join == 0 or join == -1, 'No gap between members and at most 1 px over: ' .. what .. ' row ' .. bottom);
                steps, overlaps = steps + 1, overlaps + (join == -1 and 1 or 0);
                if join == -1 and not share and width == 1920 then share = { bottom = bottom, index = index }; end;
            end;
        end;
        assert(strip.y <= strip.rows[1].area.y and strip.rows[6].area.y + size <= strip.y + strip.height and strip.y >= 0
            and strip.y + strip.height <= height, 'The window takes in every member\'s icons and stays on the screen: ' .. what);
    end;
    if size == 27 then assert(overlaps > 0 and overlaps < steps, 'A step between whole pixels sometimes overlaps by 1 px: ' .. what);
    else assert(overlaps == 0, 'A whole step joins exactly: ' .. what); end;
end;

-- Another group's window that reaches only the icons above the party's first row still bounds the strip; one that ends
-- where the strip's window starts doesn't.
game(1440, 767);
local geometry = native.geometry(roster, 1920, 1080, { width = 1440, height = 810 });
local frame, gap = geometry.groups[1], p.native.gap;
local normal = overlay.plan(roster, subjects, p, geometry, 1920, 1080)[1];
assert(frame.y - normal.y >= 4, 'The icons reach above the game\'s first row.');
-- Far enough across to leave the strip room with the gap on both sides.
geometry.groups[2] = { x = 1560, y = normal.y - 100, width = 106, height = 100, rows = {} };
assert(overlay.plan(roster, subjects, p, geometry, 1920, 1080)[1].width == normal.width, 'A window ending where the strip starts leaves it.');
geometry.groups[2].height = 101;
local bounded = overlay.plan(roster, subjects, p, geometry, 1920, 1080)[1];
assert(bounded.width < normal.width and bounded.width == math.floor(frame.x - gap - 1666 - gap), 'One reaching the icons above the first row bounds it.');

-- The pointer on the pixel two members share finds the lower member, drawn later and on top; just above it, the upper.
game(1440, share.bottom);
geometry = native.geometry(roster, 1920, 1080, { width = 1440, height = 810 });
local strip = overlay.plan(roster, subjects, p, geometry, 1920, 1080)[1];
local upper, lower = strip.rows[share.index - 1], strip.rows[share.index];
assert(lower.area.y == upper.area.y + upper.area.height - 1, 'These two members share a pixel row.');
local cells = layout.effect_cells(layout.effects(subjects[lower.member.id], lower.options), lower.options, lower.area);
local named;
hud.effect_tooltip = function(_, _, member) named = member.name; end;
MOCK.screen, MOCK.mouse_x, MOCK.mouse_y = { 1920, 1080 }, cells[1].x + 1, lower.area.y;
overlay.draw(roster, subjects, p, 100, { native_geometry = geometry });
assert(named == lower.member.name, 'The shared pixel belongs to the lower member.');
named, MOCK.mouse_y = nil, lower.area.y - 1;
overlay.draw(roster, subjects, p, 100, { native_geometry = geometry });
assert(named == upper.member.name, 'Just above it, the upper member.');
return 'Party strip at scaled menus: whole-pixel icons that fill the step, no gap, at most 1 px over, window, bounds, hover';
