-- A bitmap font measures countdowns with fallback metrics until its countdown atlas is uploaded, then by its ink.
-- Its font token stays the same, so everything measured or wrapped before then is keyed on that readiness too:
-- cached wraps are measured again, and countdowns stay inside the rows they are drawn in.
package.loaded['ui.icons'] = {status=function() return 123; end};
local imgui = require('imgui');
local fonts, metrics, countdown = require('ui.fonts'), require('ui.text_metrics'), require('ui.countdown_text');
local ready = false;
fonts.countdown_renderer = function(name) return ready and fonts.is_bitmap(name) and function() return true; end or nil; end;

-- The token, and the wraps cached under it, change when the atlas comes up; an ordinary font's never do.
local loading = metrics.token('Original FFXI', 16);
local agave = metrics.token('Agave', 16);
assert(metrics.token('Original FFXI', 16) == loading, 'A loading bitmap font keeps its token.');
local scale = 8;
local function measure(text) return #tostring(text) * scale; end;
local before = metrics.lines('1 2', 30, measure, loading);
ready, scale = true, 14;
local loaded = metrics.token('Original FFXI', 16);
local after = metrics.lines('1 2', 30, measure, loaded);
assert(loaded ~= loading, 'A bitmap font gets a new token once its countdown atlas is up.');
assert(#before == 1 and #after == 2, 'Wraps cached while it loaded are measured again: ' .. #before .. ' then ' .. #after .. ' lines.');
assert(metrics.token('Agave', 16) == agave, 'An ordinary font keeps its token.');

-- An icon cell too narrow for its countdown wraps it by character. While the atlas loads '45m' takes two lines;
-- once loaded every character is wider and it takes three, and the row grows to hold them.
ready = false;
metrics.countdown = function(_, value) return #tostring(value or '') * (ready and 14 or 8), 12; end;
local drawn = {};
countdown.draw = function(_, _, text, x, y) drawn[#drawn + 1] = {text=text, x=x, y=y}; return true; end;
local hud, defaults = require('ui.hud'), require('ui.defaults');
MOCK.screen = {1600, 1000};
local s = defaults.make();
s.style.font, s.style.font_size, s.style.scale, s.style.icon_size, s.style.gap = 'Original FFXI', 14, 1, 16, 4;
for id, panel in pairs(s.panels) do panel.enabled = id == 'self_buffs'; end;
local p = s.panels.self_buffs;
p.mode, p.width, p.auto_width, p.auto_height, p.height_limit, p.max_rows, p.stack_direction = 'icons', 30, false, true, 600, 32, 'horizontal';
p.icon_countdown_position, p.icon_countdown_size, p.icon_countdown_gap = 'below', 0, 0;
p.countdown_bold, p.countdown_outline, p.countdown_shadow = false, false, false;
local function frame(left)
    local rows = {{key='row1', effect=41, slot=0, scope='self', entity_id=1001, kind='buff', status='server', present=true,
        deadline=1000 + left, total=36000, name='Effect'}};
    MOCK.imgui_calls, drawn = {}, {};
    hud.draw({valid=true, context={id=1001, valid=true}, rows=rows}, s, 1000, {});
    local y, height;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'SetNextWindowPos' then y = call[2][2]; end;
        if call[1] == 'SetNextWindowSize' then height = call[2][2]; end;
    end;
    local inside = true;
    for _, line in ipairs(drawn) do if line.y + 12 > y + height - 4 + 0.001 then inside = false; end; end;
    return #drawn, inside;
end;
local lines, inside = frame(2700);
assert(lines == 2 and inside, 'While loading the countdown takes two lines inside its row: ' .. lines);
ready = true;
lines, inside = frame(2640);
assert(lines == 3 and inside, 'Once loaded it takes three, all inside its row: ' .. lines .. ' lines, inside ' .. tostring(inside));
