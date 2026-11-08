-- The party cooldown list (settings.party_cooldowns.list): one row for each estimate the party cooldown watch holds
-- (core/party_cooldowns.lua), the ability's icon, the member, the ability and its estimated time left, in the timer
-- panels' font and colors. Rows past the limit or the room are left out with nothing in their place. It moves and
-- resizes like the alert notices: unlock it, then hold Shift and drag inside to move it or an edge to resize it. It
-- takes no clicks otherwise. Every table a frame uses is kept and refilled.
local cooldown_list = {};
local theme = require('ui.theme');
local fonts = require('ui.fonts');
local resize = require('ui.resize');
local skin = require('ui.client_skin');
local metrics = require('ui.text_metrics');
local countdown = require('ui.countdown_text');
local recast_icons = require('ui.recast_icons');
local cooldowns = require('core.party_cooldowns');
local elements = require('ui.elements');
local conditions = require('core.conditions');
local snap = require('ui.snap');
local bit = require('bit');
local floor = math.floor;
local LABEL = 'Party cooldowns';
local gesture;
local empty = {};
-- The rectangle drawn, and the corners and clips, refilled for each use.
local rect, corner, far = { x = 0, y = 0, width = 0, height = 0 }, { 0, 0 }, { 0, 0 };
local ZERO, ONE, place, extent = { 0, 0 }, { 1, 1 }, { 0, 0 }, { 0, 0 };

-- Each watched ability's icon, as recast_icons draws an ability recast: its resource is 512 plus its Phoenix id.
local icons_by_ability = {};
function cooldown_list.icon(ability)
    local metadata = require('core.recasts').preview_icon('ability', 512 + ability);
    local held = icons_by_ability[ability];
    if not held or held.source ~= metadata then
        held = { kind = 'ability', source = metadata, recast_id = 0 };
        for key, value in pairs(metadata or empty) do if key ~= 'name' then held[key] = value; end end
        -- Named as its own candidate, a status it gives is looked up without a list made for each draw.
        if held.ability_id then held.action_icons = { { ability_id = held.ability_id } }; end
        icons_by_ability[ability] = held;
    end
    return held;
end

function cooldown_list.cancel_gesture()
    local prior = gesture;
    gesture = nil;
    if prior and prior.dirty and prior.callbacks.save then prior.callbacks.save(); end
end

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
    if not options or not config.enabled or not options.enabled then cooldown_list.cancel_gesture(); return nil; end
    -- When to show hides it, unless samples or edit mode show it.
    if not config.preview and not moving.editing and not conditions.shown('cooldown_list') then cooldown_list.cancel_gesture(); return nil; end
    local imgui = require('imgui');
    local rows = config.preview and cooldowns.list_samples(config, now) or view and view.cooldowns or empty;
    local movable = moving.shift and not moving.chat_open and not options.locked and not moving.over_settings;
    if gesture and (gesture.settings ~= settings or not movable or not moving.down
        or gesture.sw ~= moving.screen_width or gesture.sh ~= moving.screen_height) then cooldown_list.cancel_gesture(); end
    if #rows == 0 and not movable and not moving.editing then resize.keep(LABEL); return nil; end
    local s = settings.style;
    local scale, screen_width, screen_height = s.scale, moving.screen_width, moving.screen_height;
    local font_size = s.font_size * scale;
    local row_height = math.max(font_size + 6 * scale, floor(s.icon_size * 0.75 + 0.5) * scale);
    local heading = options.show_heading and not s.minimal
        and ((s.title_size > 0 and s.title_size or s.font_size) + 10) * scale or 4 * scale;
    local count = math.min(#rows, options.max_rows);
    local wanted = heading + math.max(1, count) * (row_height + 2 * scale) + 4 * scale;
    local height = options.height > 0 and math.min(options.height, screen_height) or math.min(wanted, screen_height);
    local width = math.min(options.width, screen_width);
    if gesture then
        local g = gesture;
        local dx, dy = moving.mx - g.mx, moving.my - g.my;
        local pulled_x, pulled_y = resize.axes(g.edge);
        -- A press that hasn't moved yet changes nothing, as a timer panel's drag.
        if g.dirty or pulled_x and dx ~= 0 or pulled_y and dy ~= 0 or not g.edge and (dx ~= 0 or dy ~= 0) then
            g.active_edge = resize.active_edge(g.edge, dx, dy, g.active_edge);
            local moved = snap.resize(settings, 'cooldown_list', g.rect, g.active_edge, dx, dy, { min_width = 160, min_height = 60,
                max_width = 1400, max_height = 16000, screen_width = screen_width, screen_height = screen_height });
            if not g.edge then
                local shift_x, shift_y = snap.move(settings, 'cooldown_list', g.rect.x + dx, g.rect.y + dy, moved.width, moved.height,
                    screen_width, screen_height);
                moved.x = math.max(0, math.min(g.rect.x + dx + shift_x, screen_width - moved.width));
                moved.y = math.max(0, math.min(g.rect.y + dy + shift_y, screen_height - moved.height));
            end
            local horizontal, vertical = resize.axes(g.active_edge);
            local x, y = floor(moved.x), floor(moved.y);
            local new_width = horizontal and floor(moved.width) or options.width;
            local new_height = vertical and floor(moved.height) or options.height;
            if x ~= options.x or y ~= options.y or new_width ~= options.width or new_height ~= options.height then
                if not g.dirty and callbacks.changed then callbacks.changed('before', 'Party cooldown list layout'); end
                options.x, options.y, options.width, options.height = x, y, new_width, new_height;
                -- A Shift drag detaches an anchored display.
                if options.anchor then options.anchor.to = 'none'; end
                g.dirty = true;
                if callbacks.changed then callbacks.changed('after'); end
            end
        end
        width = math.min(options.width, screen_width);
        height = options.height > 0 and math.min(options.height, screen_height) or math.min(wanted, screen_height);
    end
    rect.width, rect.height = width, height;
    rect.x, rect.y = options.x, options.y;
    elements.place(settings, 'cooldown_list', rect, screen_width, screen_height);
    rect.x = math.max(0, math.min(rect.x, screen_width - width));
    rect.y = math.max(0, math.min(rect.y, screen_height - height));
    if gesture then snap.show(settings, 'cooldown_list', screen_width, screen_height, rect); end
    resize.occupy(LABEL, rect);
    elements.record('cooldown_list', rect);
    place[1], place[2], extent[1], extent[2] = rect.x, rect.y, width, height;
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, ZERO);
    imgui.PushStyleVar(ImGuiStyleVar_WindowMinSize, ONE);
    imgui.SetNextWindowPos(place, ImGuiCond_Always);
    imgui.SetNextWindowSize(extent, ImGuiCond_Always);
    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar or 0, ImGuiWindowFlags_NoResize or 0, ImGuiWindowFlags_NoMove or 0,
        ImGuiWindowFlags_NoCollapse or 0, ImGuiWindowFlags_NoScrollbar or 0, ImGuiWindowFlags_NoScrollWithMouse or 0,
        ImGuiWindowFlags_NoSavedSettings or 0, ImGuiWindowFlags_NoBackground or 0, ImGuiWindowFlags_NoFocusOnAppearing or 0,
        ImGuiWindowFlags_NoNav or 0, ImGuiWindowFlags_NoDocking or 0);
    if not movable then flags = bit.bor(flags, ImGuiWindowFlags_NoInputs or 0); end
    fonts.push(s.font, font_size);
    local hovered;
    if imgui.Begin('##vantage_cooldowns', true, flags) then
        elements.opened('cooldown_list', imgui.GetWindowDrawList());
        -- Its samples go over an open settings window.
        local list, on_top = resize.sample_list(imgui, config.preview and settings.window.open and not moving.editing, rect, moving.mx, moving.my, true);
        local x, y = rect.x, rect.y;
        if not skin.panel(list, rect, s, nil, nil, s.background, s.border) and not s.minimal then
            corner[1], corner[2], far[1], far[2] = x, y, x + width, y + height;
            if s.background then list:AddRectFilled(corner, far, theme.u32(skin.fallback_background(s), s.opacity), s.rounding); end
            if s.border then list:AddRect(corner, far, theme.u32(s.border_color, s.opacity), s.rounding, 0, 1); end
        end
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
        if config.preview then resize.sample(list, rect, s, true); end
        if movable then
            imgui.SetCursorPos(ZERO);
            imgui.InvisibleButton('##cooldown_list_layout', extent);
            local grip;
            if gesture then grip = gesture.edge;
            elseif imgui.IsItemHovered() then grip = resize.grip(rect, moving.mx, moving.my); end
            resize.hint(list, rect, theme.u32(s.accent_color), grip, LABEL, s);
            if imgui.IsItemHovered() then
                resize.cursor(imgui, grip);
                if not gesture and imgui.IsMouseClicked(ImGuiMouseButton_Left or 0) then
                    gesture = { settings = settings, callbacks = callbacks, mx = moving.mx, my = moving.my, edge = grip,
                        rect = { x = rect.x, y = rect.y, width = width, height = height },
                        sw = moving.screen_width, sh = moving.screen_height };
                end
            elseif gesture and imgui.IsItemActive() then resize.cursor(imgui, gesture.edge); end
        elseif moving.shift and not moving.chat_open and options.locked and not moving.over_settings then
            resize.locked(list, rect, s, LABEL);
        end
        if on_top then list:PopClipRect(); end
    end
    imgui.End();
    imgui.PopStyleVar(2);
    fonts.pop();
    return hovered;
end

return cooldown_list;
