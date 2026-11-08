-- A bars panel with a fixed height (Fit panel height to contents off) keeps that height whatever the row
-- count: a second effect doesn't grow the panel and its leaving doesn't shrink it. An effect with no room is left
-- out with nothing drawn in its place.
package.loaded['ui.icons'] = {status=function() return 123; end};
local hud, defaults = require('ui.hud'), require('ui.defaults');
MOCK.screen = {1600, 1000};
local s = defaults.make();
s.style.font, s.style.font_size, s.style.scale = 'Ashita', 14, 1;
for id, p in pairs(s.panels) do p.enabled = id == 'self_buffs'; end;
local p = s.panels.self_buffs;
p.mode, p.show_icon, p.width, p.auto_width, p.auto_height, p.wrap = 'bars', true, 300, false, false, false;
local function row(n) return {key='r' .. n, effect=40 + n, slot=n - 1, scope='self', entity_id=1001, kind='buff', status='server', present=true, deadline=1600, name='Effect ' .. n}; end;
local function frame(count, limit)
    p.height_limit = limit;
    local rows = {};
    for n = 1, count do rows[n] = row(n); end;
    MOCK.imgui_calls = {};
    hud.draw({valid=true, context={id=1001, valid=true}, rows=rows}, s, 1000, {});
    local height, footer, images = nil, nil, 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'SetNextWindowSize' then height = call[2][2]; end;
        if call[1] == 'draw:AddText' and (tostring(call[6]):find('more', 1, true) or tostring(call[6]):find('%+%d')) then footer = call[6]; end;
        if call[1] == 'draw:AddImage' then images = images + 1; end;
    end;
    return height, footer, images;
end;
local cut = 0;
for _, limit in ipairs({80, 86, 99, 105}) do
    local one, _, one_images = frame(1, limit);
    local two, footer, two_images = frame(2, limit);
    local back = frame(1, limit);
    assert(one_images >= 1 and two_images >= 1, 'Fixture: a row draws at height limit ' .. limit .. '.');
    if two_images < 2 then cut = cut + 1; end;
    assert(footer == nil, 'A row left out draws no count or more line at height limit ' .. limit .. ': ' .. tostring(footer));
    assert(one == two and two == back, 'A fixed height stays as saved (' .. limit .. '): one row ' .. tostring(one) .. ', two rows ' .. tostring(two) .. ', one again ' .. tostring(back) .. '.');
end;
assert(cut > 0, 'Fixture: at least one height has room for only one of the two rows.');
assert(p.height_limit == 105 and p.auto_height == false, 'The saved height and fit choice are untouched.');
