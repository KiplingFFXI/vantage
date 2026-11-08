local defaults, hud, imgui = require('ui.defaults'), require('ui.hud'), require('imgui');
local fonts, icons, recast_icons = require('ui.fonts'), require('ui.icons'), require('ui.recast_icons');
local copy, equal = require('core.store').copy, require('core.customization').equal;
imgui.CalcTextSize = function(value) return #tostring(value) * imgui.GetFontSize() * 0.6, imgui.GetFontSize(); end;
icons._set_loader_for_tests(function() return 777; end);
recast_icons.draw = function(list, _, _, x, y, size) list:AddImage(777, { x, y }, { x + size, y + size }); return true; end;
local position, dimensions, current, rects = {}, {}, {}, {};
imgui.SetNextWindowPos = function(value) position = value; end;
imgui.SetNextWindowSize = function(value) dimensions = value; end;
imgui.Begin = function(name)
    current = { x = position[1], y = position[2], width = dimensions[1], height = dimensions[2] };
    rects[name] = current; return true;
end;
MOCK.screen = { 1600, 2000 };
for _, key in ipairs(defaults.panel_order) do
    local s = defaults.make();
    for id, panel in pairs(s.panels) do panel.enabled = id == key; end;
    s.recast_display = key == 'recasts' and 'combined' or 'separate';
    s.watch_ids = { 1001 };
    local p = s.panels[key];
    p.x, p.y, p.width, p.height_limit, p.wrap = 30, 40, 160, 1900, true;
    p.show_heading, p.show_target, p.show_time = false, false, false;
    local kind = defaults.recast_panels[key];
    local row = { key = 'review', effect = kind and 10057 or 33, name = 'WMWM', entity_id = 1001,
        domain = kind and 'recast' or nil, scope = key == 'party' and 'party' or 'self',
        kind = kind and (kind == 'all' and 'spell' or kind) or key == 'self_debuffs' and 'debuff' or 'buff',
        status = 'unknown', present = true };
    local view = { valid = true, context = { target = { id = 1001 } }, rows = { row } };
    for _, mode in ipairs({ 'bars', 'expanded', 'icons' }) do
        p.mode = mode;
        s.style.icon_size, s.style.scale, s.style.font_size, s.style.text_shadow = 64, 2.5, 48, false;
        local before = copy(s);
        MOCK.imgui_calls = {}; hud.draw(view, s, 100, {});
        local box, pictures = rects['##vantage_' .. key], 0;
        assert(box and box.width >= 160 and box.width <= 1600);
        for _, call in ipairs(MOCK.imgui_calls) do
            if call[1] == 'draw:AddImage' and call[2] == 777 then
                pictures = pictures + 1;
                assert(call[4][1] - call[3][1] == 160 and call[4][2] - call[3][2] == 160,
                    'Selected fixed artwork stays square at the requested scale: ' .. key .. '/' .. mode);
                assert(call[3][1] >= box.x and call[4][1] <= box.x + box.width,
                    'The viewport minimum reserves the full fixed icon width.');
            elseif call[1] == 'draw:AddText' and call[6]:find('W', 1, true) then
                assert(call[3] == 120, 'Wrapping does not reduce selected text size.');
            end;
        end;
        assert(pictures == 1 and equal(s, before), 'Rendering neither loses the only row nor rewrites saved dimensions.');
        assert(row.status == 'unknown' and row.deadline == nil, 'Wrapping does not invent a source or duration.');
    end;
    p.mode, p.show_icon, p.show_name, p.show_text = 'bars', false, false, false;
    local bounds = hud.bounds(p, s.style, 1, 1600, 2000);
    assert(bounds.width == 160 and bounds.icon_width == 0, 'Hidden artwork and text do not reserve their former sizes.');
end;

local s = defaults.make();
for key, panel in pairs(s.panels) do panel.enabled = key == 'self_buffs'; end;
local p = s.panels.self_buffs;
p.mode, p.stack_direction = 'bars', 'vertical';
p.x, p.y, p.width, p.height_limit, p.wrap, p.show_icon = 30, 40, 240, 1900, true, false;
s.style.text_shadow = false;
p.show_source, p.show_target, p.show_time = true, true, true;
p.labels[33], p.field_labels.name = 'ABCDEFGHIJKLMNOPQRSTUVWX', 'Effect';
p.field_labels.source, p.field_labels.time = 'Caster', 'Remaining';
s.style.font_size = 20;
local row = { key = 'long', effect = 33, name = 'Haste', entity_id = 1001, entity_name = 'Alexandriaverylongname',
    source_name = 'Longcastersample', scope = 'self', kind = 'buff', status = 'unknown', present = true };
local view = { valid = true, context = {}, rows = { row } };
local before = copy(s);
MOCK.imgui_calls = {}; hud.draw(view, s, 100, {});
local text = {};
for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'draw:AddText' then text[#text + 1] = call[6]; end; end;
local drawn = table.concat(text):gsub('%s', '');
for _, value in ipairs({ 'ABCDEFGHIJKLMNOPQRSTUVWX', 'Alexandriaverylongname', 'Longcastersample' }) do
    assert(drawn:find(value, 1, true), 'Wrapped custom fields retain complete text: ' .. value);
end;
assert(not drawn:lower():find('unknown', 1, true) and not drawn:find('?', 1, true),
    'A row with no timer says nothing unknown.');
assert(equal(s, before), 'Real rendering leaves nested labels, filters and colors unchanged.');
hud.copy_text(view, s, 'self_buffs', false, 100);
assert(equal(s, before), 'Copy leaves nested working maps unchanged.');
assert(#MOCK.font_stack == 0);
