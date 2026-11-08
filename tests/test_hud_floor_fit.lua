-- A bars panel at its lowest height fits one row exactly. That row's icon must show in full wherever the panel sits
-- and at any scale, with the same allowance for float error the panel's row count has.
local function f32(v)
    local m, e = math.frexp(v);
    local t = m * 2 ^ 24;
    local r = math.floor(t);
    local d = t - r;
    if d > 0.5 or d == 0.5 and r % 2 == 1 then r = r + 1; end;
    return math.ldexp(r, e - 24);
end;
local scales = {};
for hundredths = 105, 200, 5 do
    local exact = hundredths / 100;
    scales[#scales + 1] = exact;
    if f32(exact) ~= exact then scales[#scales + 1] = f32(exact); end;
end;
package.loaded['ui.icons'] = {status=function() return 123; end};
local hud, defaults, visible = require('ui.hud'), require('ui.defaults'), require('visible_icons');
MOCK.screen = {1600, 1000};
local function settings()
    local s = defaults.make();
    s.style.font, s.style.font_size, s.style.scale = 'Ashita', 14, 1;
    for id, panel in pairs(s.panels) do panel.enabled = id == 'self_buffs' or id == 'self_debuffs'; end;
    return s;
end;

-- 1. A free floor panel with one buff: font 16, scale 1.2, at y 100 drew only '+1 more'.
local function floor_rows(scale, font, mode, y)
    local s = settings();
    s.style.font, s.style.font_size, s.style.scale = 'Ashita', font, scale;
    local p = s.panels.self_buffs;
    p.mode, p.show_icon, p.auto_width, p.width, p.stack_direction = mode, true, false, 300, 'vertical';
    p.height_limit, p.auto_height, p.x, p.y = 1, false, 10, y;
    local row = {key='r1', effect=33, slot=0, scope='self', entity_id=1001, kind='buff', status='server', present=true,
        name='Haste', entity_name='You', deadline=1100};
    MOCK.imgui_calls = {};
    hud.draw({valid=true, context={id=1001, valid=true, self_effects={{effect=33, slot=0}}}, rows={row}}, s, 1000, {});
    local shown = #visible(function(texture) return texture == 123; end);
    return shown, shown == 1;
end;
local drawn, covered33 = floor_rows(1.2, 16, 'bars', 100);
assert(drawn == 1 and covered33, 'A floor panel at scale 1.2 draws its one row.');
local lost, tried, example = 0, 0, nil;
for _, scale in ipairs(scales) do
    for _, mode in ipairs({'bars', 'expanded'}) do
        for _, y in ipairs({37, 100, 333, 427, 430, 478}) do
            tried = tried + 1;
            if floor_rows(scale, 16, mode, y) ~= 1 then lost = lost + 1; example = example or ('%s at scale %.17g, y %d'):format(mode, scale, y); end;
        end;
    end;
end;
assert(lost == 0, lost .. ' of ' .. tried .. ' floor panels drew no row, e.g. ' .. tostring(example));
