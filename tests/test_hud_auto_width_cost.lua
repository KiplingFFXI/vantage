-- An auto-width bar panel fits each row for the widest text its countdown can reach. Once a frame has measured
-- that text, later frames read its width back with the row's countdown, measuring nothing, and each row's
-- countdown text is read once: the steady-width fit adds no per-row work to every frame and to every BeginScene
-- layout.
package.loaded['ui.icons'] = {status=function() return 123; end};
local countdown, hud, defaults = require('ui.countdown_text'), require('ui.hud'), require('ui.defaults');
MOCK.screen = {1600, 1000};
local measure, timer_text = countdown.measure, hud.timer_text;
local measures, timers = 0, 0;
countdown.measure = function(...) measures = measures + 1; return measure(...); end;
hud.timer_text = function(...) timers = timers + 1; return timer_text(...); end;
local function cost(count, auto)
    local s = defaults.make();
    s.style.font, s.style.font_size, s.style.scale = 'Ashita', 14, 1;
    for id, panel in pairs(s.panels) do panel.enabled = id == 'self_buffs'; end;
    local p = s.panels.self_buffs;
    p.mode, p.auto_width, p.stack_direction, p.max_rows, p.height_limit = 'bars', auto, 'vertical', 32, 2000;
    local rows = {};
    for index = 1, count do
        rows[index] = {key='r' .. index, effect=30 + index, slot=index - 1, scope='self', entity_id=1001, kind='buff',
            status='server', present=true, name='Effect ' .. index, deadline=1000 + 30 * index};
    end;
    hud.draw({valid=true, context={id=1001, valid=true}, rows=rows}, s, 1000, {});
    measures, timers = 0, 0;
    hud.draw({valid=true, context={id=1001, valid=true}, rows=rows}, s, 1000.5, {});
    return measures, timers;
end;
local auto_measures_2, auto_timers_2 = cost(2, true);
local auto_measures_16, auto_timers_16 = cost(16, true);
local fixed_measures_2, fixed_timers_2 = cost(2, false);
local fixed_measures_16, fixed_timers_16 = cost(16, false);
assert(auto_measures_16 - auto_measures_2 <= fixed_measures_16 - fixed_measures_2,
    ('A steady frame measures no countdown for the fit: %d more for 14 rows, %d without the fit.'):format(
    auto_measures_16 - auto_measures_2, fixed_measures_16 - fixed_measures_2));
assert(auto_timers_16 - auto_timers_2 <= 2 * (fixed_timers_16 - fixed_timers_2),
    ('It reads each countdown once, for the row it measures: %d more for 14 rows, %d without the fit.'):format(
    auto_timers_16 - auto_timers_2, fixed_timers_16 - fixed_timers_2));
