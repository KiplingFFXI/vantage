-- An icon cell holds the widest countdown of every shape its timers can show. Bitmap countdowns are measured by
-- their ink, the leftmost to the rightmost inked pixel of any glyph, so a glyph whose ink starts past its own
-- advance or reaches past the glyphs after it can make a text wider than one built from the widest digit of
-- each place. Each probe is the widest text of its shape, measured exactly.
package.loaded['ui.icons'] = {status=function() return 123; end};
local imgui = require('imgui');
local metrics, countdown = require('ui.text_metrics'), require('ui.countdown_text');
-- glyphs[c] = {advance, ink left, ink right}, both ink edges from where the glyph starts.
local glyphs = {};
local function ink(value)
    local left, right, x = nil, nil, 0;
    for character in tostring(value or ''):gmatch('.') do
        local glyph = glyphs[character] or glyphs.other;
        if character ~= ' ' then
            left, right = math.min(left or x + glyph[2], x + glyph[2]), math.max(right or x + glyph[3], x + glyph[3]);
        end;
        x = x + glyph[1];
    end;
    return (right or 0) - (left or 0), x;
end;
metrics.countdown = function(_, value, _, compact)
    local width, advance = ink(value);
    return compact and width or advance, 12;
end;
local drawn = {};
countdown.draw = function(_, _, text, x, y)
    drawn[#drawn + 1] = {text=text, x=x, y=y};
    MOCK.imgui_calls[#MOCK.imgui_calls + 1] = {'countdown', #drawn};
    return true;
end;
local hud, defaults = require('ui.hud'), require('ui.defaults');
MOCK.screen = {1600, 1000};
local s = defaults.make();
s.style.font, s.style.font_size, s.style.scale = 'Ashita', 14, 1;
for id, panel in pairs(s.panels) do panel.enabled = id == 'self_buffs'; end;
local p = s.panels.self_buffs;
p.mode, p.auto_height, p.height_limit, p.max_rows, p.stack_direction = 'icons', true, 600, 32, 'horizontal';
p.icon_countdown_position, p.countdown_bold, p.countdown_outline, p.countdown_shadow = 'below', false, false, false;
-- Draws the timers and returns each drawn countdown with the clip rect it was drawn in, the icon tops, the
-- pitch between neighbouring icons and the panel's bottom edge.
local function frame(lefts, now)
    local rows = {};
    for index, left in ipairs(lefts) do
        rows[index] = {key='row' .. index, effect=40 + index, slot=index - 1, scope='self', entity_id=1001, kind='buff',
            status='server', present=true, deadline=1000 + left, total=36000, name='Effect ' .. index};
    end;
    MOCK.imgui_calls, drawn = {}, {};
    hud.draw({valid=true, context={id=1001, valid=true}, rows=rows}, s, now, {});
    local clip, shown, icons, y, height = nil, {}, {}, 0, 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        local values = MOCK.drawn[call];
        if call[1] == 'draw:PushClipRect' then clip = {values[2][1], values[2][2], values[3][1], values[3][2]}; end;
        if call[1] == 'countdown' then
            local entry = drawn[call[2]];
            entry.clip = clip;
            shown[#shown + 1] = entry;
        end;
        if call[1] == 'draw:AddImage' and call[2] == 123 then icons[#icons + 1] = values[3]; end;
        if call[1] == 'SetNextWindowPos' then y = call[2][2]; end;
        if call[1] == 'SetNextWindowSize' then height = call[2][2]; end;
    end;
    local pitch = icons[2] and icons[2][1] - icons[1][1];
    return shown, icons, pitch, y + height;
end;
-- A drawn countdown inside its cell: not clipped on either side and above the next row of icons.
local function clipped(shown)
    for _, entry in ipairs(shown) do
        local width = ink(entry.text);
        if entry.x < entry.clip[1] - 0.001 or entry.x + width > entry.clip[3] + 0.001 then return entry.text; end;
    end;
    return false;
end;
local function spilled(shown, icons, bottom)
    for _, entry in ipairs(shown) do
        local below = bottom - 4;
        for _, top in ipairs(icons) do if top[2] > entry.y then below = math.min(below, top[2] - s.style.gap); end; end;
        if entry.y + 12 > below + 0.001 then return entry.text; end;
    end;
    return false;
end;

-- A font where '1' has a wide advance and little ink, '7' a narrow advance and ink reaching far right, 's'
-- almost none. '17s' is wider than any text made of the widest digit for each place ('11s').
local function font(map)
    glyphs = {other={8, 1, 7}, [' ']={8, 0, 0}};
    for character, glyph in pairs(map) do glyphs[character] = glyph; end;
    imgui.CalcTextSize = function(text) return #tostring(text) * 8 + #map, 18; end;
end;
font({['0']={8, 1, 7}, ['1']={14, 1, 3}, ['7']={4, 0, 20}, s={6, 1, 2}, m={6, 1, 2}, h={6, 1, 2}});
s.style.icon_size, s.style.gap = 8, 4;
p.width, p.auto_width, p.icon_countdown_size, p.icon_countdown_gap = 600, false, 0, 0;
local shown, _, pitch = frame({17, 17.4}, 1000);
assert(#shown == 2 and shown[1].text == '17s' and not clipped(shown),
    'A 17s countdown fits its cell: ' .. tostring(clipped(shown)) .. ' in ' .. tostring(pitch and pitch - s.style.gap));
-- The widest text of each shape under an hour, by trying every digit in every place.
local function widest(shape)
    local best = 0;
    local function fill(prefix, rest)
        local at = rest:find('#', 1, true);
        if not at then best = math.max(best, (ink(prefix .. rest))); return; end;
        for digit = 0, 9 do fill(prefix .. rest:sub(1, at - 1) .. digit, rest:sub(at + 1)); end;
    end;
    fill('', shape);
    return best;
end;
local function compact_cell()
    return math.max(s.style.icon_size, widest('#s'), widest('##s'), widest('#m'), widest('##m'));
end;
assert(pitch and math.abs(pitch - s.style.gap - compact_cell()) < 0.001,
    'The cell is the widest compact countdown under an hour, exactly: ' .. tostring(pitch and pitch - s.style.gap) .. ' vs ' .. compact_cell());
-- A glyph whose ink starts past the next glyph and reaches far beyond it: in '81s' the 8 sets the right edge
-- and the 1 after it the left, so no text of one digit is as wide.
font({['8']={2, 10, 30}, ['1']={2, 0, 1}, s={2, 0, 1}, m={2, 0, 1}});
shown, _, pitch = frame({81, 18}, 1000);
assert(not clipped(shown) and pitch and math.abs(pitch - s.style.gap - compact_cell()) < 0.001,
    'Ink that starts past the next glyph is measured exactly too: ' .. tostring(pitch and pitch - s.style.gap) .. ' vs ' .. compact_cell());

-- Text not measured yet throws before drawing. A probe interrupted that way keeps nothing half measured, so
-- the next try measures it whole.
font({['0']={8, 1, 7}, ['1']={14, 1, 3}, ['7']={4, 0, 20}, s={6, 1, 3}, m={6, 1, 3}, h={6, 1, 3}});
local measured, refuse = metrics.countdown, true;
metrics.countdown = function(name, value, size, compact)
    if refuse and tostring(value):find(' ', 1, true) then error('Text width is not available before drawing.', 0); end;
    return measured(name, value, size, compact);
end;
local refused = pcall(frame, {17, 17.4}, 1000);
refuse = false;
local retried, again, _, again_pitch = pcall(frame, {17, 17.4}, 1000);
metrics.countdown = measured;
assert(not refused and retried and not clipped(again) and math.abs(again_pitch - s.style.gap - compact_cell()) < 0.001,
    'An interrupted probe is measured whole on the next try.');

-- Property: random glyph metrics, with ink starting before or after its advance and reaching past the glyphs
-- after it, and every countdown style. A panel with room has cells exactly as wide as the widest text of every
-- shape its timers can still show (each digit any digit), so no countdown is clipped or wrapped; none spills below
-- its row, and cells never widen as timers count down. Every countdown has the one time format.
local reached = { 9, 59, 99, 599, 999, 3599, 5999, 9999, 35999, 59999, 99999, 359999 };
local function shape(seconds, format) return (hud.time(seconds, format):gsub('%d', '#')); end;
local function shapes(left, format, into)
    into[shape(left, format)] = true;
    for _, value in ipairs(reached) do if value < left then into[shape(value, format)] = true; end; end;
end;
math.randomseed(20261018);
local bad_clip, bad_spill, widened, inexact, frames, exact_frames = 0, 0, 0, 0, 0, 0;
for round = 1, 120 do
    local map = {};
    for _, character in ipairs({'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'm', 's', 'h', ':', '-'}) do
        local advance = math.random(2, 12);
        local left = math.random(0, advance + 3);
        map[character] = {advance, left, math.random(left + 1, advance + 9)};
    end;
    font(map);
    local memo = {};
    local function cached(text) memo[text] = memo[text] or widest(text); return memo[text]; end;
    s.style.icon_size, s.style.gap, s.style.scale = math.random(4, 24), math.random(0, 6), ({1, 1.25, 1.5})[math.random(3)];
    local wide = round % 3 ~= 0;
    p.auto_width, p.width, p.max_width = wide and math.random(2) == 1, wide and 900 or math.random(24, 70), 1400;
    p.icon_countdown_size = math.random(3) == 1 and 0 or math.random(8, 20);
    p.icon_countdown_gap = math.random(0, 4);
    p.countdown_bold, p.countdown_outline, p.countdown_shadow = math.random(2) == 1, math.random(2) == 1, math.random(2) == 1;
    local left_pad, _, right_pad = countdown.padding({countdown_bold=p.countdown_bold, countdown_shadow=p.countdown_shadow,
        countdown_outline=p.countdown_outline});
    local format = 'compact';
    local lefts = {};
    for index = 1, math.random(2, 5) do
        -- Half start a little above where a shape changes, so they cross it while drawn.
        local edge = reached[math.random(4)];
        lefts[index] = math.random(2) == 1 and edge + math.random(1, 3000) / 100
            or math.random(1, 359999) / 10;
    end;
    local previous;
    for step = 0, 30 do
        local now = 1000 + step * 37.3;
        local this_shown, icons, this_pitch, bottom = frame(lefts, now);
        -- A cell narrower than its text wraps it by character rather than clipping it, so each piece would still
        -- fit: each row draws its whole countdown once, in a cell at least as wide as it.
        local whole = {};
        for _, left in ipairs(lefts) do whole[hud.timer_text({effect=41, status='server', deadline=1000 + left}, now)] = true; end;
        local clipped_frame = wide and #this_shown ~= #lefts;
        for _, entry in ipairs(this_shown) do
            local width = ink(entry.text) + left_pad + right_pad;
            if not whole[entry.text] or entry.clip[3] - entry.clip[1] < width - 0.001
                or entry.x < entry.clip[1] - 0.001 or entry.x + width > entry.clip[3] + 0.001 then clipped_frame = clipped_frame or wide; end;
        end;
        if clipped_frame then bad_clip = bad_clip + 1; end;
        if spilled(this_shown, icons, bottom) then bad_spill = bad_spill + 1; end;
        -- Each icon is centered in its cell, so the first icon moves right when cells widen.
        local width = icons[1] and icons[1][1];
        if previous and width and width > previous + 0.001 then widened = widened + 1; end;
        previous = width or previous;
        if wide and not p.auto_width and this_pitch then
            local reach, want = {}, s.style.icon_size * s.style.scale;
            shapes(format == 'compact' and 3599 or 0, format, reach);
            for _, left in ipairs(lefts) do shapes(math.max(0, left + 1000 - now), format, reach); end;
            for text in pairs(reach) do want = math.max(want, cached(text) + left_pad + right_pad); end;
            if math.abs(this_pitch - s.style.gap * s.style.scale - want) > 0.001 then inexact = inexact + 1; end;
            exact_frames = exact_frames + 1;
        end;
        frames = frames + 1;
    end;
end;
assert(frames > 3000 and bad_clip == 0, bad_clip .. ' frames clip or wrap a countdown in a panel with room for it.');
assert(bad_spill == 0, bad_spill .. ' frames spill a countdown below its row.');
assert(widened == 0, widened .. ' frames widened a cell as timers counted down.');
assert(exact_frames > 1000 and inexact == 0, inexact .. ' of ' .. exact_frames .. ' frames are not the exact widest cell.');
