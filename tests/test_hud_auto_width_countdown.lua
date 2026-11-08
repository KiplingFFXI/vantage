-- An auto-width bar panel fits its widest row, countdown included. A countdown changes its text every second,
-- and digits differ in width, so the panel is sized for the widest text each countdown can still show, as
-- icon cells are, and holds its width while it counts down.
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
local function widths(times, left)
    local s = defaults.make();
    s.style.font, s.style.font_size, s.style.scale = 'Ashita', 14, 1;
    for id, panel in pairs(s.panels) do panel.enabled = id == 'self_buffs'; end;
    local p = s.panels.self_buffs;
    p.mode, p.auto_width, p.min_width, p.max_width, p.stack_direction = 'bars', true, 60, 700, 'vertical';
    p.show_heading = false;
    local row = {key='r1', effect=125, slot=0, scope='self', entity_id=1001, kind='buff', status='server', present=true,
        name='Protectra and Shellra V', deadline=1000 + (left or 70.5)};
    local out, names = {}, {};
    for _, step in ipairs(times) do
        MOCK.imgui_calls = {};
        hud.draw({valid=true, context={id=1001, valid=true}, rows={row}}, s, 1000 + step, {});
        local size, clips;
        for _, call in ipairs(MOCK.imgui_calls) do
            if call[1] == 'SetNextWindowSize' then size = call[2];
            elseif call[1] == 'Begin' and call[2] == '##vantage_self_buffs' then out[#out + 1], clips = size[1], 0;
            elseif call[1] == 'draw:PushClipRect' and clips then
                -- The window's inside, then the name.
                clips = clips + 1;
                local drawn = MOCK.drawn[call];
                if clips == 2 then names[#names + 1] = drawn[3][1] - drawn[2][1]; end;
            end;
        end;
    end;
    return out, names;
end;
local function steady(list)
    for _, value in ipairs(list) do if value ~= list[1] then return false; end; end;
    return #list > 0;
end;
-- 71s down to 6s left, through the minute and the ten-second marks and seconds with ones in them.
local times = {0, 1, 11, 15, 59.6, 60, 61, 65};
local compact, names = widths(times);
assert(#compact == #times and steady(compact), 'A compact countdown keeps the panel width: ' .. table.concat(compact, ','));
local name = text_size('Protectra and Shellra V');
for _, width in ipairs(names) do assert(width >= name, 'The name still has its whole width beside the countdown.'); end;
-- Hours left: every digit still counts as the widest one.
_, names = widths({0, 0.6}, 7000.5);
for _, width in ipairs(names) do assert(width >= name, 'A long countdown leaves the name its whole width too.'); end;
