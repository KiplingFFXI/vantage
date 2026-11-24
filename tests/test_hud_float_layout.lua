-- Panel sizes worked out from a whole number of cells must lay out that many. A scale set on the Overall
-- scale slider (float32) and saved to settings.json (14 digits) reads back as a double whose products round,
-- so the counts in hud.bounds allow for float error. A vertical auto-width icon panel taller than the game
-- window sizes its columns for the height it is drawn at.
package.loaded['ui.icons'] = {status=function() return 123; end};
local hud, defaults, visible = require('ui.hud'), require('ui.defaults'), require('visible_icons');
-- The slider's float32 value, as the next load reads it back.
local function float32(value)
    local mantissa, exponent = math.frexp(value);
    return math.ldexp(math.floor(mantissa * 2 ^ 24 + 0.5) / 2 ^ 24, exponent);
end;
local function reloaded(value) return tonumber(string.format('%.14g', float32(value))); end;
local function setup(scale, gap, icon)
    local s = defaults.make();
    s.style.font, s.style.font_size, s.style.scale, s.style.gap, s.style.icon_size = 'Ashita', 14, reloaded(scale), gap, icon;
    for id, p in pairs(s.panels) do p.enabled = id == 'self_buffs' or id == 'self_debuffs'; end;
    return s, s.panels.self_buffs;
end;
local function draw(s, count)
    local rows = {};
    for i = 1, count do
        rows[i] = {key='r'..i, effect=40+i, slot=i-1, scope='self', entity_id=1001, kind='buff', status='unknown', present=true, name='E'..i};
    end;
    MOCK.imgui_calls = {};
    hud.draw({valid=true, context={id=1001, valid=true}, rows=rows}, s, 1000, {});
    local tops = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddImage' and call[2] == 123 then tops[#tops + 1] = call[3][2]; end;
    end;
    return tops, #visible(function(texture) return texture == 123; end);
end;
local function one_line(tops)
    for _, y in ipairs(tops) do if y ~= tops[1] then return false; end; end;
    return #tops > 0;
end;
assert(reloaded(0.9) ~= float32(0.9) and float32(0.9) ~= 0.9, 'Fixture: a saved slider value reads back as another double.');

-- An auto-width icon panel sized for its columns lays them out on one line.
MOCK.screen = {1600, 1000};
for _, case in ipairs({{0.9, 6}, {1.6, 3}, {0.99, 5}}) do
    local s, p = setup(case[1], 4, 28);
    p.mode, p.auto_width, p.stack_direction = 'icons', true, 'horizontal';
    local tops, covered = draw(s, case[2]);
    assert(#tops == case[2] and one_line(tops) and covered == case[2],
        ('Auto-width icons at scale %s lay out the %d columns they were sized for.'):format(case[1], case[2]));
end;
-- The same for a horizontal auto-width bar panel.
local s, p = setup(0.7, 4, 28);
p.mode, p.auto_width, p.min_width, p.max_width, p.stack_direction = 'bars', true, 160, 700, 'horizontal';
local tops, covered = draw(s, 3);
assert(#tops == 3 and one_line(tops) and covered == 3, 'Auto-width bars at scale 0.7 lay out the three columns they were sized for.');
-- An icon panel at its minimum height, one row, still shows that row.
for _, case in ipairs({{0.65, 42}, {0.9, 28}, {0.91, 28}}) do
    s, p = setup(case[1], 4, case[2]);
    p.mode, p.auto_width, p.width, p.stack_direction = 'icons', false, 300, 'horizontal';
    p.height_limit, p.auto_height = 24, false;
    tops, covered = draw(s, 3);
    assert(#tops == 3 and covered == 3, ('An icon panel at its minimum height shows its row at scale %s.'):format(case[1]));
    local rect = hud.bounds(p, s.style, 3, 1600, 1000);
    assert(rect.shown == 3 and rect.height == rect.min_height,
        ('That row fits in the minimum height at scale %s.'):format(case[1]));
end;
-- A vertical auto-width icon panel taller than the game window adds a column instead of dropping icons.
MOCK.screen = {1600, 500};
s, p = setup(1, 4, 28);
p.mode, p.auto_width, p.min_width, p.max_width, p.stack_direction, p.height_limit = 'icons', true, 24, 700, 'vertical', 700;
tops, covered = draw(s, 20);
assert(#tops == 20 and covered == 20, 'A vertical auto-width icon panel taller than the screen shows every icon.');
-- A bar panel dragged or set to its 80 px floor still shows a row, whatever the scale. A second effect with no room
-- is left out.
MOCK.screen = {1600, 1000};
for _, mode in ipairs({'bars', 'expanded'}) do
    for _, scale in ipairs({1, 1.25, 1.5, 2}) do
        for _, count in ipairs({1, 2}) do
            s, p = setup(scale, 4, 28);
            p.mode, p.show_icon, p.auto_width, p.width, p.stack_direction = mode, true, false, 300, 'vertical';
            p.height_limit, p.auto_height = 80, false;
            tops, covered = draw(s, count);
            assert(#tops >= 1 and covered >= 1, ('A %s panel at its floor shows a row at scale %s with %d listed.'):format(mode, scale, count));
            local rect = hud.bounds(p, s.style, count, 1600, 1000);
            assert(rect.shown >= 1 and rect.shown <= count and #tops == rect.shown and rect.height >= rect.min_height,
                ('Its rows fit the height it is drawn at: %s at scale %s with %d listed.'):format(mode, scale, count));
        end;
    end;
end;
-- An auto-width icon panel one cell wide gets its cell back as room only up to float error: at Size 0.85 read back,
-- a 26 px cell comes back as 25.999999999999996. A countdown as wide as the cell still shows on one line, so each row
-- is its icon and one line of countdown. '25m' is 26 px wide here, with a pixel of outline each side. Each case has
-- its own countdown size, so no wrap is kept from the one before.
local countdown = require('ui.countdown_text');
local shown = {};
countdown.draw = function(_, _, text) shown[#shown + 1] = text; return true; end;
for _, case in ipairs({{'horizontal', 1, 12}, {'vertical', 3, 13}}) do
    s, p = setup(0.85, 4, 28);
    p.mode, p.auto_width, p.min_width, p.max_width, p.stack_direction = 'icons', true, 24, 700, case[1];
    p.icon_countdown_size = case[3];
    local rows = {};
    for i = 1, case[2] do
        rows[i] = {key='t'..i, effect=40+i, slot=i-1, scope='self', entity_id=1001, kind='buff', status='server',
            present=true, name='E'..i, deadline=2500, total=36000};
    end;
    shown, MOCK.imgui_calls = {}, {};
    hud.draw({valid=true, context={id=1001, valid=true}, rows=rows}, s, 1000, {});
    local size;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'SetNextWindowSize' then size = call[2];
        elseif call[1] == 'Begin' and call[2] == '##vantage_self_buffs' then break; end;
    end;
    local scale = s.style.scale;
    local _, wide, tall = countdown.icon_values(s.style.font, '25m', 28, p, scale);
    assert(math.abs(wide * scale - 26) < 1e-9 and size[1] - 8 * scale < 26,
        'Fixture: the cell comes back a hair short of the countdown at ' .. case[1]);
    local whole = #shown == case[2];
    for _, text in ipairs(shown) do whole = whole and text == '25m'; end;
    assert(whole, ('A fitted %s icon panel shows each countdown whole: %s'):format(case[1], table.concat(shown, ' | ')));
    -- 4 px of padding above and below, and the gap between rows.
    local height = 8 * scale + case[2] * (28 * scale + tall * scale + 4 * scale) - 4 * scale;
    assert(math.abs(size[2] - height) < 1e-6,
        ('A fitted %s icon panel is no taller than one line of countdown makes it: %s, not %s'):format(case[1], size[2], height));
end;
