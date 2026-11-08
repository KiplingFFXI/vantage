local defaults, hud = require('ui.defaults'), require('ui.hud');
local icons = require('ui.icons');
icons.status = function() return 1234; end;
MOCK.screen = { 1600, 1200 };

-- overflow is any text a panel draws for effects past its last icon or row: a '+N' count, 'more' or an ellipsis.
local function marker(text)
    return text:find('%+%d') or text:lower():find('more', 1, true) or text:find('...', 1, true) or text:find('\226\128\166', 1, true);
end;
local function paint(settings, rows)
    MOCK.imgui_calls = {};
    local view = { valid = true, context = { id = 1001 }, rows = rows };
    hud.draw(view, settings, 100, {});
    local count, overflow = 0, nil;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddImage' and call[2] == 1234 then count = count + 1; end;
        if call[1] == 'draw:AddText' and type(call[6]) == 'string' and marker(call[6]) then overflow = call[6]; end;
    end;
    return count, overflow, hud.copy_text(view, settings, 'self_buffs', false, 100);
end;

for _, mode in ipairs({ 'bars', 'expanded', 'icons' }) do
    for _, scale in ipairs({ 0.75, 1, 1.5, 2 }) do
        for _, minimal in ipairs({ false, true }) do
            local settings = defaults.make();
            for key, panel in pairs(settings.panels) do panel.enabled = key == 'self_buffs'; end;
            local panel, style = settings.panels.self_buffs, settings.style;
            style.scale, style.minimal, style.icon_size, style.bar_height = scale, minimal, 32, 36;
            style.font_size, style.gap, style.font = 12, 4, 'Ashita';
            panel.mode, panel.show_time, panel.show_fill, panel.wrap = mode, false, false, false;
            panel.width, panel.auto_height, panel.max_rows = 300, false, 32;
            if mode=='icons' then panel.width,panel.stack_direction=(style.icon_size+8)*scale,'vertical'; end;
            panel.x, panel.y, panel.height_limit = 0, 0, 1000;
            local rows = {};
            for index = 1, 6 do
                rows[index] = { key = tostring(index), effect = 39 + index, name = 'Buff ' .. index,
                    scope = 'self', entity_id = 1001, kind = 'buff', status = 'server', deadline = 200, present = true };
                if mode=='icons' then rows[index].status,rows[index].deadline='unknown',nil; end;
            end;
            local baseline = hud.bounds(panel, style, #rows, 1600, 1200);
            local lines = math.ceil(#rows / baseline.columns);
            panel.height_limit = math.ceil(baseline.heading + lines * baseline.row_height
                + (lines - 1) * style.gap * scale + 5 * scale);
            local rect = hud.bounds(panel, style, #rows, 1600, 1200);
            assert(rect.shown == #rows, mode .. ' fits all rows in the room they take');
            local count, overflow, copied = paint(settings, rows);
            assert(count == #rows and not overflow, mode .. ' painter agrees with the available row capacity');
            assert(not copied:find(' more', 1, true), 'Copy shown never reports an effect that fits as hidden');
            panel.height_limit = panel.height_limit - math.ceil(baseline.row_height + style.gap * scale);
            rect = hud.bounds(panel, style, #rows, 1600, 1200);
            count, overflow, copied = paint(settings, rows);
            assert(count == rect.shown and count < #rows, 'A genuinely smaller viewport still limits visible rows');
            assert(overflow == nil, mode .. ' cut by its height draws nothing after its last row: ' .. tostring(overflow));
            assert(not copied:find('more', 1, true) and not copied:find('+', 1, true) and not copied:find('...', 1, true),
                'Copy shown lists only the shown rows: ' .. copied);
            panel.height_limit, panel.max_rows = 1000, 2;
            count, overflow = paint(settings, rows);
            assert(count == 2 and overflow == nil, 'The explicit effect limit remains available and is cut silently');
        end;
    end;
end;

local settings = defaults.make();
for key, panel in pairs(settings.panels) do panel.enabled = key == 'self_buffs'; end;
settings.style.minimal, settings.style.icon_size, settings.style.bar_height = true, 32, 36;
settings.panels.self_buffs.auto_height, settings.panels.self_buffs.height_limit = false, 80;
local single = { { key = 'one', effect = 40, name = 'Protect', scope = 'self', entity_id = 1001,
    kind = 'buff', status = 'server', present = true, deadline = 200 } };
local count, overflow = paint(settings, single);
assert(count == 1 and not overflow, 'One live buff never produces an invented overflow count');
local observed = { context = { id = 1001 }, rows = {} };
for _, effect in ipairs({ {40,'Protect','buff'}, {253,'Signet','buff'}, {148,'Evasion Down','debuff'},
    {251,'Food','buff'}, {269,'Level Sync','other'}, {42,'Regen','buff'} }) do
    observed.rows[#observed.rows + 1] = { key = tostring(effect[1]), effect = effect[1], name = effect[2],
        kind = effect[3], scope = 'self', entity_id = 1001, present = true,
        status = effect[1] == 269 and 'unknown' or 'server', deadline = effect[1] ~= 269 and 200 or nil };
end;
local buffs = hud.filter_rows(observed, settings.panels.self_buffs, 'self_buffs', settings);
local debuffs = hud.filter_rows(observed, settings.panels.self_debuffs, 'self_debuffs', settings);
assert(#buffs == 5 and #debuffs == 1, 'Known neutral icons remain buffs; debuffs never inflate the buff count');
settings.panels.self_buffs.auto_height, settings.panels.self_buffs.height_limit = true, 1200;
count, overflow = paint(settings, observed.rows);
assert(count == 5 and not overflow, 'Automatic height shows all five observed buffs including untimed Level Sync');
return 'Status timer rows use the actual drawable row space and a cut panel draws nothing past its last row';
