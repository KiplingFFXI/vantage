-- An auto-width bar panel holds its width while its elapsed field counts up, as it does for its countdown: the
-- elapsed time is measured as the widest text it can reach before the total, each digit the widest.
package.loaded['ui.icons'] = {status=function() return 123; end};
-- A face whose 1 is much narrower than its other digits.
local function text_size(text)
    local width = 0;
    for character in tostring(text):gmatch('.') do
        width = width + (character == '1' and 2 or character:find('%d') and 12 or 8);
    end;
    return width, 18;
end;
rawset(require('imgui'), 'CalcTextSize', text_size);
local hud, defaults = require('ui.hud'), require('ui.defaults');
MOCK.screen = {1600, 1000};
local function widths(key)
    local s = defaults.make();
    s.style.font, s.style.font_size, s.style.scale = 'Ashita', 14, 1;
    for id, panel in pairs(s.panels) do panel.enabled = id == key; end;
    local p = s.panels[key];
    p.mode, p.auto_width, p.min_width, p.max_width, p.stack_direction = 'bars', true, 60, 900, 'vertical';
    p.show_heading, p.show_elapsed = false, true;
    local row = {key='r1', effect=40, slot=0, scope='self', entity_id=1001, kind='buff', status='server', present=true,
        name='Protect IV', start=999.5, deadline=2800.5, total=1801};
    local out = {};
    for step = 0, 70 do
        MOCK.imgui_calls = {};
        hud.draw({valid=true, context={id=1001, valid=true}, rows={row}}, s, 1000 + step, {});
        local size;
        for _, call in ipairs(MOCK.imgui_calls) do
            if call[1] == 'SetNextWindowSize' then size = call[2];
            elseif call[1] == 'Begin' and call[2] == '##vantage_' .. key then out[#out + 1] = size[1]; end;
        end;
    end;
    return out;
end;
local function changes(list)
    local count = 0;
    for index = 2, #list do if list[index] ~= list[index - 1] then count = count + 1; end; end;
    return count;
end;
local list = widths('self_buffs');
assert(#list == 71 and changes(list) == 0, ('Elapsed time keeps the panel width: %d changes, %s'):format(
    changes(list), table.concat(list, ',', 1, 12)));
