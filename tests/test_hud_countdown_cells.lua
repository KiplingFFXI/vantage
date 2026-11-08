-- Icon cells, timer rows and the panels' sizes hold still as countdowns count down, so nothing drops out on the clock.
package.loaded['ui.icons'] = {status=function() return 123; end};
local imgui = require('imgui');
local hud, defaults = require('ui.hud'), require('ui.defaults');
MOCK.screen = {1600, 1000};
local s = defaults.make();
s.style.font, s.style.font_size, s.style.scale, s.style.gap = 'Ashita', 14, 1, 4;
for id, p in pairs(s.panels) do p.enabled = id == 'self_buffs' or id == 'self_debuffs'; end;
local p = s.panels.self_buffs;

local function row(slot, left, now)
    return {key='row'..slot, effect=40 + slot, slot=slot, scope='self', entity_id=1001, kind='buff', status='server',
        present=true, deadline=now + left, total=36000, name='Effect '..slot};
end;
local function frame(lefts, start, now)
    local rows = {};
    for index, left in ipairs(lefts) do rows[index] = row(index - 1, left, start); end;
    MOCK.imgui_calls = {};
    hud.draw({valid=true, context={id=1001, valid=true}, rows=rows}, s, now, {});
    local cells, sizes, xs = {}, {}, {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddImage' and call[2] == 123 then
            cells[#cells + 1] = call[3][1] .. ',' .. call[3][2];
            xs[call[3][2]] = xs[call[3][2]] or {};
            table.insert(xs[call[3][2]], call[3][1]);
        elseif call[1] == 'SetNextWindowSize' then
            sizes[#sizes + 1] = call[2][1] .. 'x' .. call[2][2];
        end;
    end;
    local pitch = math.huge;
    for _, line in pairs(xs) do
        table.sort(line);
        for index = 2, #line do pitch = math.min(pitch, line[index] - line[index - 1]); end;
    end;
    return table.concat(cells, ' '), table.concat(sizes, ' '), pitch;
end;

-- 16 px icons with 16 px countdowns, 78 px wide, one row tall. '1m' turns into '60s'.
s.style.icon_size = 16;
p.mode, p.width, p.auto_width, p.auto_height, p.max_rows, p.stack_direction = 'icons', 78, false, false, 32, 'horizontal';
p.icon_countdown_size, p.icon_countdown_gap, p.height_limit, p.show_heading = 16, 0, 44, false;
local before_cells, before_sizes = frame({60.51, 60.51, 60.51}, 100, 100.49);
local after_cells, after_sizes = frame({60.51, 60.51, 60.51}, 100, 100.52);
assert(before_cells == after_cells and before_sizes == after_sizes,
    'Crossing from 1m to 60s keeps the same cells and panel size.');
-- Cells fit the widest compact countdown, so they don't depend on which countdowns are showing.
p.height_limit = 200;
assert(frame({5.5, 8.5}, 100, 100) == frame({3000, 2400}, 100, 100), 'Short and long compact timers share one layout.');

-- Property, in two fonts: a narrow 1 beside a wide 0, and wide units beside a thin colon. Every countdown has the one
-- time format, so cells never move as time passes; each round still saves a format of its own, which changes nothing.
local fonts = {};
for index, widths in ipairs({ {['0']=9, ['1']=5, m=12, h=9, s=7, [':']=4, [' ']=4, ['-']=6, other=8},
    {m=20, h=20, s=20, [':']=2, [' ']=4, ['-']=6, other=6} }) do
    fonts[index] = function(text)
        local width = 0;
        for character in tostring(text):gmatch('.') do width = width + (widths[character] or widths.other); end;
        return width, 18;
    end;
end;
local calc = imgui.CalcTextSize;
math.randomseed(20261016);
local edges = {16.2, 60.3, 61.2, 100.6, 110.3, 600.4, 660.1, 1000.2, 1110.4, 3600.2, 3610.5, 36000.4};
local checked, moved = 0, 0;
for round = 1, 96 do
    imgui.CalcTextSize = fonts[round % 2 + 1];
    s.style.icon_size, s.style.scale, s.style.gap = math.random(12, 40), ({1, 1.25, 1.5})[math.random(3)], math.random(0, 8);
    p.width, p.auto_width, p.min_width, p.max_width = math.random(40, 300), math.random(4) == 1, 24, math.random(60, 400);
    p.auto_height, p.height_limit = math.random(2) == 1, math.random(30, 300);
    p.stack_direction = math.random(2) == 1 and 'vertical' or 'horizontal';
    p.icon_countdown_size = math.random(3) == 1 and 0 or math.random(6, 24);
    p.icon_countdown_position = math.random(4) == 1 and 'inside' or 'below';
    p.icon_countdown_gap = math.random(0, 6);
    p.countdown_bold, p.countdown_outline, p.countdown_shadow = math.random(2) == 1, math.random(2) == 1, math.random(2) == 1;
    local lefts = {};
    for index = 1, math.random(1, 12) do
        lefts[index] = math.random(3) > 1 and edges[math.random(#edges)] or math.random(1600, 720000) / 100;
    end;
    -- A few rounds in a small cell, where '1m' turning into '60s' would widen it.
    if round <= 8 then
        imgui.CalcTextSize, s.style.icon_size, s.style.scale = fonts[2], 12, 1;
        p.width, p.auto_width, p.stack_direction, p.icon_countdown_position = 120, false, 'horizontal', 'below';
        lefts = {61.2, 61.2, 100.6};
    end;
    local first_cells, first_sizes = frame(lefts, 1000, 1000);
    checked = checked + 1;
    for step = 1, 60 do
        local cells, sizes = frame(lefts, 1000, 1000 + step * 0.25);
        if cells ~= first_cells or sizes ~= first_sizes then moved = moved + 1; end;
    end;
end;
imgui.CalcTextSize = calc;
assert(checked == 96 and moved == 0, 'Icon cells and panel sizes stay put while timers count down.');
