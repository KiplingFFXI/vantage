-- Auto width fits the rows a panel shows: in every layout a row past Most shown leaves the width alone, and it counts
-- once Most shown takes it in.
package.loaded['ui.icons'] = {status=function() return 123; end};
rawset(require('imgui'), 'CalcTextSize', function(text) return #tostring(text) * 8, 18; end);
local hud, defaults = require('ui.hud'), require('ui.defaults');
MOCK.screen = {1600, 1000};
local function row(index, name)
    return {key='r' .. index, effect=40 + index, slot=index - 1, scope='self', entity_id=1001, kind='buff',
        status='server', present=true, name=name, deadline=1000 + 60 * index};
end;
local two_rows = {row(1, 'Protect'), row(2, 'Shell')};
-- Sorted by time left, the long name comes last.
local three_rows = {row(1, 'Protect'), row(2, 'Shell'), row(3, 'An effect with a much longer name than the rest')};
-- The width hud.draw gives the panel's window.
local function width(mode, rows, most)
    local s = defaults.make();
    s.style.font, s.style.font_size, s.style.scale = 'Ashita', 14, 1;
    for id, panel in pairs(s.panels) do panel.enabled = id == 'self_buffs'; end;
    local p = s.panels.self_buffs;
    p.mode, p.auto_width, p.min_width, p.max_width, p.sort = mode, true, 60, 900, 'remaining';
    p.stack_direction = mode == 'icons' and 'horizontal' or 'vertical';
    p.show_heading, p.max_rows, p.height_limit = false, most, 2000;
    MOCK.imgui_calls = {};
    hud.draw({valid=true, context={id=1001, valid=true}, rows=rows}, s, 1000, {});
    local size;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'SetNextWindowSize' then size = call[2];
        elseif call[1] == 'Begin' and call[2] == '##vantage_self_buffs' then return size[1]; end;
    end;
end;
for _, mode in ipairs({'bars', 'expanded', 'text', 'icons'}) do
    local two, past, three = width(mode, two_rows, 2), width(mode, three_rows, 2), width(mode, three_rows, 3);
    assert(two ~= nil and past == two, ('%s: a row past Most shown leaves the width alone (%s, %s)'):format(
        mode, tostring(two), tostring(past)));
    assert(three ~= nil and three > two, ('%s: the row counts once Most shown takes it in (%s, %s)'):format(
        mode, tostring(two), tostring(three)));
end;
