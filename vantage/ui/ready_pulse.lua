-- Draws the ready pulses (core/ready_pulse.lua): each recast's icon grows and fades over the pulse's length, ringed
-- in the pulse color, on its row where a recast panel drew it when ready, or at the spot you placed on the screen. The
-- pulses take no clicks. With the screen spot unlocked, holding Shift shows the spot to drag it, as the alert notices
-- move; locked, holding Shift outlines it and it stays where it is. Every table a frame uses is kept and refilled.
local ready_pulse = {};
local theme = require('ui.theme');
local resize = require('ui.resize');
local recast_icons = require('ui.recast_icons');
local elements = require('ui.elements');
local conditions = require('core.conditions');
local snap = require('ui.snap');
local layout = require('ui.layout');
local policy = require('ui.frame_policy');
local floor = math.floor;
local LABEL = 'Ready pulse';
local MOST = 8;
-- An action icon draws no bigger than 512 pixels (ui/action_icons.lua), so a pulse, its ring and its screen spot stop
-- there too, whatever Pulse size and Size make.
local LARGEST = 512;
local gesture;
-- Each pulse's center, start and end size and how far it is, by its place in the list.
local centers_x, centers_y, starts, ends, progress, drawn = {}, {}, {}, {}, {}, {};
local spot, bounds, corner, far, ink = { x = 0, y = 0, width = 0, height = 0 }, { x = 0, y = 0, width = 0, height = 0 }, { 0, 0 }, { 0, 0 }, { 0, 0, 0, 0 };
local ZERO, ONE, place, extent, EMPTY = { 0, 0 }, { 1, 1 }, { 0, 0 }, { 0, 0 }, {};
-- Where the spot's handle goes in the window, and its size.
local handle_at, handle_size = { 0, 0 }, { 0, 0 };

function ready_pulse.cancel_gesture()
    local prior = gesture;
    gesture = nil;
    if prior and prior.dirty and prior.callbacks.save then prior.callbacks.save(); end
end

-- How big a pulse grows on screen.
local function full_size(config, scale) return math.min(config.size * scale, LARGEST); end

-- The screen spot for this size: centered across the screen when x is -1, or where its anchor puts it.
local function screen_spot(settings, config, scale, width, height)
    local size = full_size(config, scale);
    spot.width, spot.height = size, size;
    spot.x = config.x < 0 and floor((width - size) / 2) or config.x;
    spot.y = config.y;
    local own_x = spot.x;
    elements.place(settings, 'pulse', spot, width, height);
    spot.x = math.max(0, math.min(spot.x, width - size));
    spot.y = math.max(0, math.min(spot.y, height - size));
    -- On a side of the chat log with no room, it is at its own spot.
    layout.off_chat(settings, 'pulse', spot, own_x, config.y, elements.chat, width, height);
    return spot;
end

-- Any row spot drawn this frame, for a test pulse while Pulse spot is On its row: a test pulse has no row of its own.
local function any_spot(spots, frame)
    for _, held in pairs(spots) do if held.frame == frame then return held; end end
end

function ready_pulse.draw(pulses, settings, now, callbacks, moving, spots, frame)
    local config = settings.ready_pulse;
    if type(config) ~= 'table' or not config.enabled then ready_pulse.cancel_gesture(); return; end
    local s = settings.style;
    local scale = s.scale;
    local on_screen = config.spot == 'screen';
    local movable = on_screen and moving.shift and not moving.chat_open and not config.locked and not moving.over_settings;
    if gesture and (gesture.settings ~= settings or not movable or not moving.down
        or gesture.sw ~= moving.screen_width or gesture.sh ~= moving.screen_height) then ready_pulse.cancel_gesture(); end
    -- A press that hasn't moved yet changes nothing, as a timer panel's drag.
    if gesture and (gesture.dirty or moving.mx ~= gesture.mx or moving.my ~= gesture.my) then
        local size = full_size(config, scale);
        -- The mouse's move is worked out first, so along an axis the mouse hasn't moved, the spot snaps from exactly
        -- where it was drawn, even at a fraction of a pixel.
        local x, y = gesture.x + (moving.mx - gesture.mx), gesture.y + (moving.my - gesture.my);
        local shift_x, shift_y = snap.move(settings, 'pulse', x, y, size, size, moving.screen_width, moving.screen_height);
        x = floor(math.max(0, math.min(x + shift_x, moving.screen_width - size)));
        y = floor(math.max(0, math.min(y + shift_y, moving.screen_height - size)));
        -- An axis the drag doesn't go along keeps its number, so Across at Centered, or a number typed past the
        -- screen's edge for a bigger screen, stays. A drag back to where it started puts it back.
        if moving.mx - gesture.mx + shift_x == 0 then x = gesture.kept_x; end
        if moving.my - gesture.my + shift_y == 0 then y = gesture.kept_y; end
        if x ~= config.x or y ~= config.y then
            if not gesture.dirty and callbacks.changed then callbacks.changed('before', 'Ready pulse spot'); end
            config.x, config.y, gesture.dirty = x, y, true;
            -- A Shift drag detaches an anchored display.
            if config.anchor then config.anchor.to = 'none'; end
            if callbacks.changed then callbacks.changed('after', nil, 'place'); end
        end
    end
    local target = screen_spot(settings, config, scale, moving.screen_width, moving.screen_height);
    if gesture then snap.show(settings, 'pulse', moving.screen_width, moving.screen_height, target); end
    if on_screen then elements.record('pulse', target); end
    local count, top = 0, full_size(config, scale);
    local left_edge, top_edge, right_edge, bottom_edge;
    pulses = pulses or EMPTY;
    -- Its show conditions hold back every pulse but a test one; edit mode shows the spot to place it.
    local held_back = not moving.editing and not conditions.shown('pulse');
    for index = 1, math.min(#pulses, MOST) do
        local entry = pulses[index];
        local t = (held_back and not entry.test) and -1 or (now - entry.started) / entry.length;
        local cx, cy, from, to;
        if t >= 0 and t < 1 then
            local held = entry.spot ~= 'screen' and (spots[entry.key] or entry.test and any_spot(spots, frame));
            -- A panel draws a row until about when the recast reader sees it ready, and a gap of over 2 seconds
            -- between its samples sends no ready (core/recasts.lua). So a row last drawn over 2 seconds before its
            -- pulse began was hidden by then, by When to show, Most shown or its panel turned off, and its pulse
            -- doesn't play there.
            if held and not (held.at and held.at >= entry.started - 2) then held = nil; end
            if held then cx, cy, from = held.x + held.size / 2, held.y + held.size / 2, math.min(held.size, LARGEST); to = math.max(from, top);
            -- A test pulse with no recast row on screen plays at the screen spot.
            elseif entry.spot == 'screen' or entry.test then
                cx, cy, from, to = target.x + target.width / 2, target.y + target.height / 2, top * 0.6, top;
            end
        end
        if cx then
            count = count + 1;
            centers_x[count], centers_y[count], starts[count], ends[count], progress[count], drawn[count] = cx, cy, from, to, t, entry;
            local reach = to / 2 + 4 * scale;
            left_edge = math.min(left_edge or cx - reach, cx - reach);
            top_edge = math.min(top_edge or cy - reach, cy - reach);
            right_edge = math.max(right_edge or cx + reach, cx + reach);
            bottom_edge = math.max(bottom_edge or cy + reach, cy + reach);
        end
    end
    -- Nothing marks the screen spot between pulses, so with it locked, holding Shift outlines it, with its lock note
    -- over it.
    local marked = on_screen and not movable and (moving.editing or moving.shift and not moving.chat_open and config.locked and not moving.over_settings);
    if count == 0 and not movable and not marked then
        if not on_screen then return; end
        resize.keep(LABEL);
        return;
    end
    if movable or marked then
        left_edge = math.min(left_edge or target.x, target.x);
        top_edge = math.min(top_edge or target.y, target.y);
        right_edge = math.max(right_edge or target.x + target.width, target.x + target.width);
        bottom_edge = math.max(bottom_edge or target.y + target.height, target.y + target.height);
    end
    bounds.x, bounds.y, bounds.width, bounds.height = left_edge, top_edge, right_edge - left_edge, bottom_edge - top_edge;
    if on_screen then resize.occupy(LABEL, target); end
    local imgui = require('imgui');
    place[1], place[2], extent[1], extent[2] = bounds.x, bounds.y, bounds.width, bounds.height;
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, ZERO);
    imgui.PushStyleVar(ImGuiStyleVar_WindowMinSize, ONE);
    imgui.SetNextWindowPos(place, ImGuiCond_Always);
    imgui.SetNextWindowSize(extent, ImGuiCond_Always);
    if imgui.Begin('##vantage_pulse', true, policy.flags(policy.BOX, movable)) then
        local list = imgui.GetWindowDrawList();
        if on_screen then elements.opened('pulse', list); end
        local art, status_art, color = s.recast_icon_art, recast_icons.status_art(s), config.color;
        local thickness = math.max(2, floor(3 * scale + 0.5));
        for index = 1, count do
            local t = progress[index];
            -- Quick to grow, slow to settle, fading as it goes.
            local grown = 1 - (1 - t) * (1 - t);
            local size = starts[index] + (ends[index] - starts[index]) * grown;
            local alpha = 1 - t;
            local x, y = centers_x[index] - size / 2, centers_y[index] - size / 2;
            recast_icons.draw(list, drawn[index], art, x, y, size, alpha, status_art);
            ink[1], ink[2], ink[3], ink[4] = color[1], color[2], color[3], color[4] * alpha;
            corner[1], corner[2], far[1], far[2] = x - thickness, y - thickness, x + size + thickness, y + size + thickness;
            list:AddRect(corner, far, theme.u32(ink), size * 0.18, 0, thickness);
        end
        for index = count + 1, #drawn do drawn[index] = nil; end
        if movable then
            -- Only the spot takes the drag, not a pulse playing elsewhere in the window.
            handle_at[1], handle_at[2], handle_size[1], handle_size[2] = target.x - bounds.x, target.y - bounds.y, target.width, target.height;
            imgui.SetCursorPos(handle_at);
            imgui.InvisibleButton('##ready_pulse_spot', handle_size);
            resize.hint(list, target, theme.u32(s.accent_color), nil, LABEL, s);
            if imgui.IsItemHovered() then
                resize.cursor(imgui, nil);
                if not gesture and imgui.IsMouseClicked(ImGuiMouseButton_Left or 0)
                    and moving.mx >= target.x and moving.mx < target.x + target.width
                    and moving.my >= target.y and moving.my < target.y + target.height then
                    -- What the drag keeps on an axis it doesn't go along: the spot's own Across and Down, or where its
                    -- anchor drew it, as the drag ends the anchor.
                    local anchored = elements.anchored('pulse');
                    gesture = { settings = settings, callbacks = callbacks, mx = moving.mx, my = moving.my, x = target.x, y = target.y,
                        sw = moving.screen_width, sh = moving.screen_height,
                        kept_x = anchored and floor(target.x) or config.x, kept_y = anchored and floor(target.y) or config.y };
                end
            end
        elseif marked then
            corner[1], corner[2], far[1], far[2] = target.x, target.y, target.x + target.width, target.y + target.height;
            list:AddRect(corner, far, theme.u32(s.accent_color, 0.5), 0, 0, 1);
            if not moving.editing then resize.locked(list, target, s, LABEL); end
        end
    end
    imgui.End();
    imgui.PopStyleVar(2);
end

return ready_pulse;
