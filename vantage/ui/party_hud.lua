local layout = require('ui.party_layout');
local labels = require('ui.party_labels');
local theme = require('ui.party_theme');
local countdown = require('ui.countdown_text');
local effect_blink = require('ui.effect_blink');
local icons = require('ui.icons');
-- How the party list strips paint each member's buff and debuff icons, their tooltip and the sample members.
local hud = {};
-- Icons share these. The binding copies them when it is called, and theme.u32 reads the tint without keeping it.
local UV0, white = { 0, 0 }, { 1, 1, 1, 1 };
-- A cell's clip, an icon's corners and where a countdown's text goes, refilled for each.
local clip_min, clip_max, icon_min, icon_max, text_at = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };
-- The recast icons and the cooldown list's icons, loaded the first time party cooldowns draw.
local recast_icons, cooldown_list;

local finite = require('ui.numbers').finite;

local function intersects(rect, clip)
    return not clip or rect.x < clip.x + clip.width and rect.x + rect.width > clip.x
        and rect.y < clip.y + clip.height and rect.y + rect.height > clip.y;
end

-- The draw list's clip, refilled for each paint_effects that reads it.
local clip_bounds = {};
local function draw_clip(list)
    if not list.GetClipRectMin or not list.GetClipRectMax then return nil; end;
    local left,top = list:GetClipRectMin();
    local right,bottom = list:GetClipRectMax();
    if finite(left) and finite(top) and finite(right) and finite(bottom) then
        clip_bounds.x, clip_bounds.y, clip_bounds.width, clip_bounds.height = left, top, right-left, bottom-top;
        return clip_bounds;
    end;
end

-- Where a cell's icon goes: on whole pixels, so it isn't blurred by half a pixel. Returns its left, top, size and the
-- width of its column.
local function icon_box(options, cell)
    local icon_width = cell.icon_size or math.min(options.icon_size or cell.height, cell.height, cell.width);
    local icon_column = cell.icon_column_width or icon_width;
    return math.floor(cell.x + math.max(0, (icon_column - icon_width) / 2) + 0.5), math.floor(cell.y + 0.5), icon_width, icon_column;
end

-- One effect cell; paint_cells keeps the clip and rethrows an error after popping it.
local function paint_cell(list, look, options, cell, effect, now)
    local icon_x, icon_y, icon_width, icon_column = icon_box(options, cell);
    -- Made at the size it is drawn where the art allows, and drawn from its texture's top left corner.
    local texture, corner = icons.status_at(effect.icon or effect.effect, look.icon_art, icon_width);
    if texture then
        white[4] = look.opacity;
        icon_min[1], icon_min[2], icon_max[1], icon_max[2] = icon_x, icon_y, icon_x + icon_width, icon_y + icon_width;
        list:AddImage(texture, icon_min, icon_max, UV0, corner, effect_blink.tint(effect, options, now, theme.u32(white)));
    end
    local timer_plan = cell.countdown;
    if timer_plan then
        local width = timer_plan.below and icon_column or icon_width;
        local left = timer_plan.below and cell.x or icon_x;
        local top = timer_plan.below and icon_width + timer_plan.gap or math.max(0, icon_width - timer_plan.height);
        for _, line in ipairs(timer_plan.lines) do
            countdown.draw(list,look.font,line.text,left+math.max(0,(width-line.width)/2),cell.y+top+line.y,
                timer_plan.size,theme.u32(look.gauge_text_color,look.opacity),options,true,text_at);
        end;
    end
end

local function paint_cells(list, look, options, cells, clip, mx, my, now)
    local hovered;
    for _, cell in ipairs(cells) do
        if intersects(cell,clip) then
            local effect = cell.effect;
            clip_min[1], clip_min[2], clip_max[1], clip_max[2] = cell.x, cell.y, cell.x + cell.width, cell.y + cell.height;
            list:PushClipRect(clip_min, clip_max, true);
            local painted, paint_error = pcall(paint_cell, list, look, options, cell, effect, now);
            list:PopClipRect();
            if not painted then error(paint_error, 0); end
            if mx and layout.inside(cell, mx, my) then hovered = effect; end
        end;
    end
    return hovered;
end

-- Debuffs you can remove, lit on the strips as they are over heads: a glow behind the icon, when light asks for one,
-- then a bright border over it, each past the cell's clip. The corners and the glow's color are refilled for each use.
local light_min, light_max, glow = { 0, 0 }, { 0, 0 }, { 0, 0, 0, 0 };
local function light_cells(list, look, options, cells, clip, removable, light, behind)
    if behind and not light.dispel_glow then return; end;
    local color = light.dispel_color;
    glow[1], glow[2], glow[3], glow[4] = color[1], color[2], color[3], color[4] * 0.35;
    local ink = theme.u32(behind and glow or color, look.opacity);
    for _, cell in ipairs(cells) do
        if removable[cell.effect.effect] and intersects(cell, clip) then
            local x, y, size = icon_box(options, cell);
            if behind then
                local reach = math.max(2, math.floor(size / 8 + 0.5));
                light_min[1], light_min[2], light_max[1], light_max[2] = x - reach, y - reach, x + size + reach, y + size + reach;
                list:AddRectFilled(light_min, light_max, ink, reach);
            else
                local thickness = math.max(1, math.floor(size / 12 + 0.5));
                light_min[1], light_min[2] = x - thickness * 0.5, y - thickness * 0.5;
                light_max[1], light_max[2] = x + size + thickness * 0.5, y + size + thickness * 0.5;
                list:AddRect(light_min, light_max, ink, 0, 0, thickness);
            end;
        end;
    end;
end

-- effects, when given, are the row's effects its plan already worked out, and kept holds its cells from the frame
-- before (layout.kept_cells). removable, when given, is the debuffs a strip lights, in light's look.
local function paint_effects(list, look, subject, options, area, mx, my, cache, now, effects, kept, removable, light)
    local clip = draw_clip(list);
    if not intersects(area,clip) then return nil; end;
    effects = effects or layout.effects(subject, options, cache);
    -- Effects past the limit or the room are left out with nothing in their place.
    local cells = kept and layout.kept_cells(kept, effects, options, area) or layout.effect_cells(effects, options, area);
    if not removable then return paint_cells(list, look, options, cells, clip, mx, my, now); end;
    light_cells(list, look, options, cells, clip, removable, light, true);
    local hovered = paint_cells(list, look, options, cells, clip, mx, my, now);
    light_cells(list, look, options, cells, clip, removable, light, false);
    return hovered;
end

local function tooltip(imgui, effect, member, subject)
    if not effect then return; end
    imgui.BeginTooltip();
    imgui.PushTextWrapPos(360);
    if effect.unknown_subject then
        imgui.TextUnformatted((member.name or 'Member') .. ' - Buffs and debuffs');
        local zone = labels.full_zone_name(member);
        if zone ~= '' then imgui.TextUnformatted(zone); end;
        imgui.TextUnformatted(effect.reason);
    else
        imgui.TextUnformatted(effect.name .. ' - ' .. (member.name or 'Member'));
        if countdown.indefinite(effect) then
            imgui.TextUnformatted('Level Sync is active without a fixed countdown.');
        else
            local timer = layout.effect_time(effect);
            local source = effect.status == 'server' and 'Supplied timer' or effect.status == 'estimated' and 'Estimated timer';
            if source and timer ~= '' then imgui.TextUnformatted(source .. ': ' .. timer); end
            if effect.reason and effect.reason ~= '' then imgui.TextUnformatted(effect.reason); end
        end
        if subject and subject.complete == false then imgui.TextUnformatted('Vantage may not see every effect on this member.'); end
    end
    imgui.PopTextWrapPos();
    imgui.EndTooltip();
end

hud.paint_effects = paint_effects;
hud.effect_tooltip = tooltip;

-- A member's party cooldown estimates (core/party_cooldowns.lua) in cells, the soonest ready nearest the game's
-- window: each the ability's icon, as the recast panels draw it, with its estimated time left at its bottom, also while
-- the strip's buffs show no countdowns. cells is where they go (ui/native_party_hud.lua); scroll moves a detached
-- strip's rows.
-- Returns the estimate under the mouse.
function hud.paint_cooldowns(list, look, options, entries, cells, now, mx, my, style, scroll)
    recast_icons, cooldown_list = recast_icons or require('ui.recast_icons'), cooldown_list or require('ui.cooldown_list');
    local size, hovered = cells.cell, nil;
    local art, status_art = style and style.recast_icon_art or 'Original FFXI', style and recast_icons.status_art(style) or nil;
    local font_size = math.max(8, math.floor(size * 0.5 + 0.5));
    local y = cells.y - (scroll or 0);
    for index = 1, cells.count do
        local entry = entries[index];
        local x = cells.align_right and cells.x + cells.width - index * (size + 3) + 3 or cells.x + (index - 1) * (size + 3);
        recast_icons.draw(list, cooldown_list.icon(entry.ability), art, x, y, size, look.opacity, status_art);
        local left = entry.deadline - now;
        if left > 0 then
            local value = countdown.time(left);
            local width, height = countdown.measure(look.font, value, font_size, options, true);
            countdown.draw(list, look.font, value, x + math.max(0, (size - width) / 2), y + math.max(0, size - height), font_size,
                theme.u32(look.gauge_text_color, look.opacity), options, true, text_at);
        end
        if mx and mx >= x and mx < x + size and my >= y and my < y + size then hovered = entry; end
    end
    return hovered;
end

function hud.sample(count, now)
    count = count == 6 and 6 or 18;
    local names = { 'Aster', 'Bramble', 'Cinder', 'Dawn', 'Elm', 'Fable', 'Gale', 'Hazel', 'Iris', 'Juniper', 'Kestrel', 'Lark', 'Moss', 'Nettle', 'Orchid', 'Pine', 'Quill', 'Reed' };
    local subjobs = { 13, 1, 10, 3, 4, 13 };
    local roster = { valid = true, id = 1001, zone = 230, members = {}, typing = false };
    local subjects = {};
    for i = 1, count do
        local member = { id = 1000 + i, slot = i - 1, group = math.floor((i - 1) / 6) + 1, name = names[i], zone = 230, zone_name = "Southern San d'Oria",
            active = true, job = (i - 1) % 18 + 1, subjob = subjobs[(i - 1) % 6 + 1], available = true };
        roster.members[i] = member;
        subjects[member.id] = { known = true, complete = i <= 6, source = 'sample', effects = {
            { effect = 40, name = 'Protect', kind = 'buff', status = 'server', remaining = 950 - (now or 0) % 30, total = 1800, present = true, key = 'p' .. i },
            { effect = 33, name = 'Haste', kind = 'buff', status = 'estimated', remaining = 110 - (now or 0) % 30, total = 180, present = true, key = 'h' .. i, reason = 'Observed application; remaining time is estimated.' },
            { effect = 4, name = 'Paralysis', kind = 'debuff', status = 'unknown', present = true, key = 'd' .. i, reason = 'Present icon without a supplied timer.' },
        } };
        -- In each party, one with each Always show effect, so the ticks move the samples.
        local always = i % 6 == 5 and { 66, 'Copy Image' } or i % 6 == 0 and { 67, 'Third Eye' };
        if always then
            local effects = subjects[member.id].effects;
            effects[#effects + 1] = { effect = always[1], name = always[2], kind = 'buff', status = 'unknown', present = true, key = 'a' .. i,
                reason = 'Present icon without a supplied timer.' };
        end
    end
    return roster, subjects;
end

return hud;
