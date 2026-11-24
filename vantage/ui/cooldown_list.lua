-- The party cooldown list (settings.party_cooldowns.list): one row for each estimate the party cooldown watch holds
-- (core/party_cooldowns.lua), its icon, the member, the ability or spell and its time left, in the timer
-- panels' font and colors. Rows past the limit or the room are left out with nothing in their place. It moves and
-- resizes like the alert notices: unlock it, then hold Shift and drag inside to move it or an edge to resize it. It
-- takes no clicks otherwise. Every table a frame uses is kept and refilled.
local cooldown_list = {};
local theme = require('ui.theme');
local fonts = require('ui.fonts');
local metrics = require('ui.text_metrics');
local countdown = require('ui.countdown_text');
local recast_icons = require('ui.recast_icons');
local cooldowns = require('core.party_cooldowns');
local conditions = require('core.conditions');
local box = require('ui.element_box');
local floor = math.floor;
local LABEL = 'Party cooldowns';
local empty = {};
-- The box it draws in, placed and moved as the Phantom Roll and pet displays are, and the clips, refilled for each use.
local frame = box.new(LABEL, '##vantage_cooldowns', 'Party cooldown list layout', 'cooldown_list');
frame.button = '##cooldown_list_layout';
local corner, far = { 0, 0 }, { 0, 0 };

-- Each watched ability's or spell's icon, as recast_icons draws its recast: an ability's resource is 512 plus its Phoenix
-- id, and a spell's is its own id.
local icons_by_ability = {};
function cooldown_list.icon(ability)
    local info = cooldowns.WATCHED[ability];
    local spell = info and info.spell;
    local metadata = require('core.recasts').preview_icon(spell and 'spell' or 'ability', spell or 512 + ability);
    local held = icons_by_ability[ability];
    if not held or held.source ~= metadata then
        held = { kind = spell and 'spell' or 'ability', source = metadata, recast_id = spell or 0 };
        for key, value in pairs(metadata or empty) do if key ~= 'name' then held[key] = value; end end
        -- Named as its own candidate, a status it gives is looked up without a list made for each draw.
        if held.ability_id then held.action_icons = { { ability_id = held.ability_id } }; end
        icons_by_ability[ability] = held;
    end
    return held;
end

function cooldown_list.cancel_gesture() frame:cancel(); end

local function text(imgui, list, style, value, x, y, size, color, width)
    if width < 3 or value == '' then return; end
    corner[1], corner[2], far[1], far[2] = floor(x), floor(y), math.ceil(x + width), math.ceil(y + size + 4);
    list:PushClipRect(corner, far, true);
    fonts.paint(imgui, list, style, value, x, y, size, theme.u32(color));
    list:PopClipRect();
end

-- Draws the list and returns the estimate under the mouse, for its tooltip. moving holds what hud.draw worked out:
-- Shift, the mouse, whether the settings window is under it and the screen.
function cooldown_list.draw(view, settings, now, callbacks, moving)
    local config = settings.party_cooldowns;
    local options = type(config) == 'table' and config.list;
    if not options or not config.enabled or not options.enabled then frame:cancel(); return nil; end
    -- When to show hides it, unless samples or edit mode show it.
    if not config.preview and not moving.editing and not conditions.shown('cooldown_list') then frame:cancel(); return nil; end
    local imgui = require('imgui');
    local rows = config.preview and cooldowns.list_samples(config, now) or view and view.cooldowns or empty;
    local s = settings.style;
    local scale = s.scale;
    local font_size = s.font_size * scale;
    local row_height = math.max(font_size + 6 * scale, floor(s.icon_size * 0.75 + 0.5) * scale);
    local heading = options.show_heading and not s.minimal
        and ((s.title_size > 0 and s.title_size or s.font_size) + 10) * scale or 4 * scale;
    local count = math.min(#rows, options.max_rows);
    local wanted = heading + math.max(1, count) * (row_height + 2 * scale) + 4 * scale;
    local rect, movable = frame:place(options, settings, callbacks, moving, wanted, #rows > 0, cooldowns.MIN_WIDTH);
    if not rect then return nil; end
    local x, y, width, height = rect.x, rect.y, rect.width, rect.height;
    fonts.push(s.font, font_size);
    local hovered;
    local list = frame:open(rect, movable, s, config.preview);
    if list then
        if options.show_heading and not s.minimal then
            local size = (s.title_size > 0 and s.title_size or s.font_size) * scale;
            text(imgui, list, s, LABEL .. (config.preview and '  /  Sample' or ''), x + 8 * scale, y + 4 * scale, size, s.title_color, width - 16 * scale);
        end
        local art, status_art = s.recast_icon_art, recast_icons.status_art(s);
        local icon = row_height - 2 * scale;
        local top = y + heading;
        for index = 1, count do
            if top + row_height > y + height + 0.001 then break; end
            local entry = rows[index];
            local left = entry.deadline - now;
            local clock = left > 0 and countdown.time(left) or '';
            local icon_x = x + 6 * scale;
            recast_icons.draw(list, cooldown_list.icon(entry.ability), art, icon_x, top + scale, icon, 1, status_art);
            local text_x = icon_x + icon + 6 * scale;
            local clock_width = clock ~= '' and metrics.width(s.font, clock, font_size, font_size) or 0;
            local room = x + width - 6 * scale - text_x;
            local text_y = top + math.max(0, (row_height - font_size) / 2);
            local name = metrics.width(s.font, entry.member_name, font_size, font_size);
            text(imgui, list, s, entry.member_name, text_x, text_y, font_size, s.label_color or s.text_color, room - clock_width - 6 * scale);
            text(imgui, list, s, entry.name, text_x + name + 8 * scale, text_y, font_size, s.detail_color or s.text_color,
                room - clock_width - name - 14 * scale);
            if clock ~= '' then text(imgui, list, s, clock, x + width - 6 * scale - clock_width, text_y, font_size, s.value_color or s.text_color, clock_width + 2); end
            if moving.hover and not movable and moving.mx >= x and moving.mx < x + width and moving.my >= top
                and moving.my < top + row_height then hovered = entry; end
            top = top + row_height + 2 * scale;
        end
    end
    frame:close(list, rect, movable, s, config.preview, options);
    fonts.pop();
    return hovered;
end

return cooldown_list;
