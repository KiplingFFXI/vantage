-- Bitmap fonts measure a countdown by its ink: the first glyph's left edge, the advances between and the last
-- glyph's right edge. The widest digit then depends on where it sits, so a countdown can be wider than one made
-- of the single widest digit. Every countdown still stays inside its row, on one line when the panel has the
-- width, and cells never widen as timers count down.
package.loaded['ui.icons'] = {status=function() return 123; end};
local imgui = require('imgui');
local metrics, countdown = require('ui.text_metrics'), require('ui.countdown_text');
local glyphs = {};
metrics.countdown = function(_, value, _, compact)
    local left, right, x = nil, nil, 0;
    for character in tostring(value or ''):gmatch('.') do
        local glyph = glyphs[character] or glyphs.other;
        if compact and character ~= ' ' then
            left, right = math.min(left or x + glyph[2], x + glyph[2]), math.max(right or x + glyph[3], x + glyph[3]);
        end;
        x = x + glyph[1];
    end;
    if not compact then return x, 12; end;
    return (right or 0) - (left or 0), 12;
end;
local drawn = {};
countdown.draw = function(_, _, text, x, y) drawn[#drawn + 1] = {text=text, x=x, y=y}; return true; end;
local hud, defaults = require('ui.hud'), require('ui.defaults');
MOCK.screen = {1600, 1000};
local s = defaults.make();
s.style.font, s.style.font_size, s.style.scale = 'Ashita', 14, 1;
for id, panel in pairs(s.panels) do panel.enabled = id == 'self_buffs'; end;
local p = s.panels.self_buffs;
p.mode, p.auto_height, p.height_limit, p.max_rows, p.stack_direction = 'icons', true, 600, 32, 'horizontal';
p.icon_countdown_position, p.countdown_bold, p.countdown_outline, p.countdown_shadow = 'below', false, false, false;
local function frame(lefts, now)
    local rows = {};
    for index, left in ipairs(lefts) do
        rows[index] = {key='row' .. index, effect=40 + index, slot=index - 1, scope='self', entity_id=1001, kind='buff',
            status='server', present=true, deadline=1000 + left, total=36000, name='Effect ' .. index};
    end;
    MOCK.imgui_calls, drawn = {}, {};
    hud.draw({valid=true, context={id=1001, valid=true}, rows=rows}, s, now, {});
    local tops, x, y, width, height = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddImage' and call[2] == 123 then tops[#tops + 1] = MOCK.drawn[call][3]; end;
        if call[1] == 'SetNextWindowPos' then x, y = call[2][1], call[2][2]; end;
        if call[1] == 'SetNextWindowSize' then width, height = call[2][1], call[2][2]; end;
    end;
    return tops, y + height;
end;

-- A font where '4' starts a pixel left of '0', so '45m' is wider than '00m'.
glyphs = {['0']={8, 1, 8}, ['4']={8, 0, 6}, m={8, 0, 8}, s={8, 1, 7}, h={8, 1, 7}, [':']={8, 3, 5}, ['-']={8, 1, 7},
    [' ']={8, 0, 0}, other={8, 1, 7}};
s.style.icon_size, s.style.gap = 16, 4;
p.width, p.auto_width, p.icon_countdown_size, p.icon_countdown_gap = 300, false, 0, 0;
frame({2700}, 1000);
assert(#drawn == 1 and drawn[1].text == '45m', 'A 45m countdown is drawn on one line: ' .. tostring(drawn[1] and drawn[1].text));

-- A cell too narrow for its countdown: the countdown wraps, and the row holds every line it can wrap to.
local function inside(tops, bottom)
    for _, line in ipairs(drawn) do
        local below = bottom - 4;
        for _, top in ipairs(tops) do if top[2] > line.y then below = math.min(below, top[2] - s.style.gap); end; end;
        if line.y + 12 > below + 0.001 then return false; end;
    end;
    return true;
end;
imgui.CalcTextSize = function(text) return #tostring(text) * 8, 18; end;
glyphs = {other={10, 0, 14}, s={3, 0, 2}, ['0']={10, 0, 13}, ['1']={11, 2, 3}, [' ']={5, 0, 0}, ['2']={5, 3, 9}, ['3']={5, 2, 5},
    m={8, 3, 5}, h={9, 2, 6}, [':']={3, 2, 7}, ['-']={11, 2, 3}, ['6']={11, 1, 3}, ['7']={7, 1, 9}, ['5']={9, 1, 5},
    ['8']={8, 3, 5}, ['4']={11, 3, 7}, ['9']={9, 0, 10}};
s.style.icon_size, s.style.gap = 14, 2;
-- 12345h, as long as countdowns come in the one time format they all have.
p.width, p.icon_countdown_gap = 24, 1;
local tops, bottom = frame({12345 * 3600 + 0.4}, 1000);
assert(#drawn > 1 and inside(tops, bottom), 'A wrapped countdown stays inside its row.');

math.randomseed(20261016);
local spilled, split, widened, frames = 0, 0, 0, 0;
for round = 1, 160 do
    -- A new font is a new measurement token.
    imgui.CalcTextSize = function(text) return #tostring(text) * 8, 18; end;
    for _, character in ipairs({'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'm', 's', 'h', ':', '-', ' ', 'other'}) do
        local advance = math.random(4, 10);
        local left = character == ' ' and 0 or math.random(0, 2);
        glyphs[character] = {advance, left, character == ' ' and 0 or math.random(left + 1, advance + 1)};
    end;
    s.style.icon_size, s.style.gap = math.random(12, 32), math.random(0, 6);
    -- Wide rounds have room for every countdown on one line; narrow ones wrap.
    local wide = round % 3 ~= 0;
    p.auto_width, p.width, p.max_width = wide and math.random(2) == 1, wide and 700 or math.random(24, 60), 900;
    p.icon_countdown_size = math.random(3) == 1 and 0 or math.random(8, 20);
    p.icon_countdown_gap = math.random(0, 4);
    local lefts = {};
    for index = 1, math.random(1, 5) do lefts[index] = math.random(1, 400000) / 10; end;
    local first_width;
    for step = 0, 40 do
        tops, bottom = frame(lefts, 1000 + step * 37.3);
        if not inside(tops, bottom) then spilled = spilled + 1; end;
        if wide and #drawn > #tops then split = split + 1; end;
        -- Each icon is centered in its cell, so the first icon's left edge moves out when cells widen.
        local width = tops[1] and tops[1][1];
        if first_width and width and width > first_width + 0.001 then widened = widened + 1; end;
        first_width = first_width or width;
        frames = frames + 1;
    end;
end;
assert(frames > 6000 and spilled == 0, spilled .. ' frames spill a countdown below its row.');
assert(split == 0, split .. ' frames split a countdown over two lines in a panel with room for it.');
assert(widened == 0, widened .. ' frames widened a cell as timers counted down.');

-- A bitmap font that finishes loading keeps its font token, but its countdowns now measure by their ink, so
-- the cells are measured again and hold them.
local fonts = require('ui.fonts');
local ready, renderer = false, fonts.countdown_renderer;
fonts.countdown_renderer = function() return ready and function() return true; end or nil; end;
metrics.countdown = function(_, value) return #tostring(value or '') * (ready and 14 or 8), 12; end;
s.style.font, s.style.icon_size, s.style.gap = 'Original FFXI', 16, 4;
p.width, p.auto_width, p.icon_countdown_size, p.icon_countdown_gap = 600, false, 0, 0;
local function pitch()
    local tops = frame({2700, 2400}, 1000);
    return tops[2] and tops[1] and math.abs(tops[2][1] - tops[1][1]);
end;
local loading = pitch();
ready = true;
local loaded = pitch();
fonts.countdown_renderer = renderer;
assert(loading and loaded and loading >= 3 * 8 + 4 and loaded >= 3 * 14 + 4, 'Cells follow a bitmap font once it loads.');
