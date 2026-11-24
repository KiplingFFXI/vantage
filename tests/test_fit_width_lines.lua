-- Fit the width sizes a panel to its rows' widest line, measured as the rows are laid out. Expanded bars put Who cast
-- it, Time elapsed and Full length on a second line at the smaller detail size, and a part that starts a line has no
-- separator before it.
package.loaded['ui.icons'] = {status=function() return 123; end};
rawset(require('imgui'), 'CalcTextSize', function(text) return #tostring(text) * 8, 18; end);
local hud, defaults = require('ui.hud'), require('ui.defaults');
MOCK.screen = {1600, 1000};
-- Protect from Ashleigh, a minute in with a minute left.
local row = {key='r1', effect=40, slot=0, scope='self', entity_id=1001, kind='buff', status='server', present=true,
    name='Protect', source_name='Ashleigh', start=940, deadline=1060, total=120};
-- The width and height hud.draw gives the panel's window, and how many texts it drew.
local function drawn(mode, options)
    local s = defaults.make();
    s.style.font, s.style.font_size, s.style.scale = 'Ashita', 14, 1;
    for id, panel in pairs(s.panels) do panel.enabled = id == 'self_buffs'; end;
    local p = s.panels.self_buffs;
    p.mode, p.auto_width, p.min_width, p.max_width, p.stack_direction = mode, true, 60, 900, 'vertical';
    p.show_heading, p.show_source, p.show_elapsed, p.show_total = false, true, true, true;
    for name, value in pairs(options or {}) do
        if name == 'newline' then p.field_newlines[value] = true; else p[name] = value; end;
    end;
    MOCK.imgui_calls = {};
    hud.draw({valid=true, context={id=1001, valid=true}, rows={row}}, s, 1000, {});
    local size, texts;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'SetNextWindowSize' then size = MOCK.copy_vector(call[2]);
        elseif call[1] == 'Begin' and call[2] == '##vantage_self_buffs' then texts = 0;
        elseif texts and call[1] == 'draw:AddText' then texts = texts + 1; end;
    end;
    assert(size and texts, 'Fixture: the panel drew.');
    return size[1], size[2], texts;
end;
-- 8 px a character at Text size 14. The row's text room is the panel's width less 61 px: the padding, its icon and
-- the gap after it. The countdown measures as '00s' with a pixel of outline each side.
local function at(size, characters) return characters * 8 * size / 14; end;
local edges, countdown = 61, 24 + 2;

-- Bars: every part on one line, 'Protect  by Ashleigh  Elapsed 0m  Total 2m  00s'.
local bars = drawn('bars');
assert(math.abs(bars - (edges + at(14, 7 + 2 + 11 + 2 + 10 + 2 + 8 + 2) + countdown)) < 1e-6,
    'Bars fit their one line: ' .. bars);
-- Expanded: 'Protect' and the countdown, then 'by Ashleigh  Elapsed 0m  Total 2m' at size 13, which is the wider line.
local expanded = drawn('expanded');
local detail = at(13, 11 + 2 + 10 + 2 + 8);
assert(detail > at(14, 7 + 2) + countdown, 'Fixture: the detail line is the wider one.');
assert(math.abs(expanded - (edges + detail)) < 1e-6 and expanded < bars,
    'Expanded bars fit their wider line, the detail line at size 13: ' .. expanded .. ', not ' .. (edges + detail));
-- That room lays the row out as it was measured, so wrapping or dropping parts changes nothing.
local width, height, texts = drawn('expanded');
for _, option in ipairs({'wrap', 'priority_overflow'}) do
    local other_width, other_height, other_texts = drawn('expanded', {[option] = true});
    assert(other_width == width and math.abs(other_height - height) < 1e-6 and other_texts == texts,
        option .. ' leaves a fitted Expanded panel as it was.');
end;
-- A line break of the player's own: 'Protect', then 'by Ashleigh  Elapsed 0m  Total 2m  00s' with no separator
-- before 'by'.
local broken = drawn('bars', {newline = 'source'});
assert(math.abs(broken - (edges + at(14, 11 + 2 + 10 + 2 + 8 + 2) + countdown)) < 1e-6,
    'A part that starts a line has no separator before it: ' .. broken);
-- Expanded with a break of the player's own lays the parts out as bars do, at the full size.
assert(math.abs(drawn('expanded', {newline = 'source'}) - broken) < 1e-6, 'Expanded with a line break of its own fits as bars do.');
