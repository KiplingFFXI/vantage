-- The box the Phantom Roll and pet displays draw in, placed and moved like the party cooldown list: at its saved spot or
-- where its anchor puts it, kept on the screen, and moved or resized only when it is unlocked and Shift is held, by a
-- drag inside or on an edge that is one Undo step. Otherwise its window takes no input, so the mouse goes to the game.
-- Each display makes one with box.new and keeps it; every table a frame uses is kept and refilled.
local box = {};
local theme = require('ui.theme');
local resize = require('ui.resize');
local skin = require('ui.client_skin');
local elements = require('ui.elements');
local snap = require('ui.snap');
local bit = require('bit');
local floor = math.floor;
local ZERO, ONE = { 0, 0 }, { 1, 1 };

local methods = {};
methods.__index = methods;

-- label names the display on its size label and lock note; id is its window's; step names its Undo step; element is its
-- id in ui/elements.lua.
function box.new(label, id, step, element)
    return setmetatable({ label = label, id = id, step = step, element = element, button = id .. '_layout',
        rect = { x = 0, y = 0, width = 0, height = 0 }, corner = { 0, 0 }, far = { 0, 0 }, at = { 0, 0 }, extent = { 0, 0 } }, methods);
end

function methods:cancel()
    local prior = self.gesture;
    self.gesture = nil;
    if prior and prior.dirty and prior.callbacks.save then prior.callbacks.save(); end
end

-- Whether the box can be moved now: Shift held, not typing, unlocked and not under the settings window.
function box.movable(options, moving)
    return moving.shift and not moving.chat_open and not options.locked and not moving.over_settings;
end

-- Where the box goes this frame, after any move or resize under way: options are its saved x, y, width and height
-- (0 to fit wanted); moving holds what hud.draw worked out. Returns its rect and whether it is movable, or nil when
-- there is nothing to draw and it isn't movable. Edit mode always draws it.
function methods:place(options, settings, callbacks, moving, wanted, shown, min_width)
    local movable = box.movable(options, moving);
    local g = self.gesture;
    if g and (g.settings ~= settings or not movable or not moving.down or g.sw ~= moving.screen_width
        or g.sh ~= moving.screen_height) then self:cancel(); g = nil; end
    if not shown and not movable and not moving.editing then resize.keep(self.label); return nil; end
    local screen_width, screen_height = moving.screen_width, moving.screen_height;
    local height = options.height > 0 and math.min(options.height, screen_height) or math.min(wanted, screen_height);
    local width = math.min(options.width, screen_width);
    if g then
        local dx, dy = moving.mx - g.mx, moving.my - g.my;
        local pulled_x, pulled_y = resize.axes(g.edge);
        -- A press that hasn't moved yet changes nothing, as a timer panel's drag.
        if g.dirty or pulled_x and dx ~= 0 or pulled_y and dy ~= 0 or not g.edge and (dx ~= 0 or dy ~= 0) then
            g.active_edge = resize.active_edge(g.edge, dx, dy, g.active_edge);
            local moved = snap.resize(settings, self.element, g.rect, g.active_edge, dx, dy, { min_width = min_width, min_height = 60,
                max_width = 1400, max_height = 16000, screen_width = screen_width, screen_height = screen_height });
            if not g.edge then
                local shift_x, shift_y = snap.move(settings, self.element, g.rect.x + dx, g.rect.y + dy, moved.width, moved.height,
                    screen_width, screen_height);
                moved.x = math.max(0, math.min(g.rect.x + dx + shift_x, screen_width - moved.width));
                moved.y = math.max(0, math.min(g.rect.y + dy + shift_y, screen_height - moved.height));
            end
            local horizontal, vertical = resize.axes(g.active_edge);
            local x, y = floor(moved.x), floor(moved.y);
            local new_width = horizontal and floor(moved.width) or options.width;
            local new_height = vertical and floor(moved.height) or options.height;
            if x ~= options.x or y ~= options.y or new_width ~= options.width or new_height ~= options.height then
                if not g.dirty and callbacks.changed then callbacks.changed('before', self.step); end
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
    local rect = self.rect;
    rect.x, rect.y, rect.width, rect.height = options.x, options.y, width, height;
    if self.element then elements.place(settings, self.element, rect, screen_width, screen_height); end
    rect.x = math.max(0, math.min(rect.x, screen_width - width));
    rect.y = math.max(0, math.min(rect.y, screen_height - height));
    if g then snap.show(settings, self.element, screen_width, screen_height, rect); end
    resize.occupy(self.label, rect);
    if self.element then elements.record(self.element, rect); end
    self.settings, self.callbacks, self.moving = settings, callbacks, moving;
    return rect, movable;
end

-- Opens the box's window and draws its panel in the timer panels' look. Returns its draw list, or nil. sample says it
-- shows samples, which go over an open settings window (resize.sample_list).
function methods:open(rect, movable, s, sample)
    local imgui = require('imgui');
    self.at[1], self.at[2], self.extent[1], self.extent[2] = rect.x, rect.y, rect.width, rect.height;
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, ZERO);
    imgui.PushStyleVar(ImGuiStyleVar_WindowMinSize, ONE);
    imgui.SetNextWindowPos(self.at, ImGuiCond_Always);
    imgui.SetNextWindowSize(self.extent, ImGuiCond_Always);
    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar or 0, ImGuiWindowFlags_NoResize or 0, ImGuiWindowFlags_NoMove or 0,
        ImGuiWindowFlags_NoCollapse or 0, ImGuiWindowFlags_NoScrollbar or 0, ImGuiWindowFlags_NoScrollWithMouse or 0,
        ImGuiWindowFlags_NoSavedSettings or 0, ImGuiWindowFlags_NoBackground or 0, ImGuiWindowFlags_NoFocusOnAppearing or 0,
        ImGuiWindowFlags_NoNav or 0, ImGuiWindowFlags_NoDocking or 0);
    if not movable then flags = bit.bor(flags, ImGuiWindowFlags_NoInputs or 0); end
    self.opened = imgui.Begin(self.id, true, flags);
    if not self.opened then return nil; end
    if self.element then elements.opened(self.element, imgui.GetWindowDrawList()); end
    local moving, list = self.moving, nil;
    list, self.on_top = resize.sample_list(imgui, sample and self.settings.window.open and not moving.editing, rect, moving.mx, moving.my, true);
    if not skin.panel(list, rect, s, nil, nil, s.background, s.border) and not s.minimal then
        local corner, far = self.corner, self.far;
        corner[1], corner[2], far[1], far[2] = rect.x, rect.y, rect.x + rect.width, rect.y + rect.height;
        if s.background then list:AddRectFilled(corner, far, theme.u32(skin.fallback_background(s), s.opacity), s.rounding); end
        if s.border then list:AddRect(corner, far, theme.u32(s.border_color, s.opacity), s.rounding, 0, 1); end
    end
    return list;
end

-- Closes the window: the SAMPLE tag while sample is set, the move and resize grips while movable, and the lock note
-- while Shift is held on a locked box.
function methods:close(list, rect, movable, s, sample, options)
    local imgui = require('imgui');
    local moving, g = self.moving, self.gesture;
    if self.opened and list then
        if sample then resize.sample(list, rect, s, true); end
        if movable then
            imgui.SetCursorPos(ZERO);
            imgui.InvisibleButton(self.button, self.extent);
            local grip;
            if g then grip = g.edge;
            elseif imgui.IsItemHovered() then grip = resize.grip(rect, moving.mx, moving.my); end
            resize.hint(list, rect, theme.u32(s.accent_color), grip, self.label, s);
            if imgui.IsItemHovered() then
                resize.cursor(imgui, grip);
                if not g and imgui.IsMouseClicked(ImGuiMouseButton_Left or 0) then
                    self.gesture = { settings = self.settings, callbacks = self.callbacks, mx = moving.mx, my = moving.my, edge = grip,
                        rect = { x = rect.x, y = rect.y, width = rect.width, height = rect.height },
                        sw = moving.screen_width, sh = moving.screen_height };
                end
            elseif g and imgui.IsItemActive() then resize.cursor(imgui, g.edge); end
        elseif moving.shift and not moving.chat_open and options.locked and not moving.over_settings then
            resize.locked(list, rect, s, self.label);
        end
        if self.on_top then list:PopClipRect(); end
    end
    imgui.End();
    imgui.PopStyleVar(2);
end

-- Whether the mouse is over a part of the box, for a tooltip: never while it can be moved.
function box.over(moving, movable, x, y, width, height)
    return moving.hover and not movable and moving.mx >= x and moving.mx < x + width and moving.my >= y and moving.my < y + height;
end

-- Text in a look's font, cut at width: the bitmap font, else ImGui's, as fonts.paint draws it but with a kept point.
local fonts = require('ui.fonts');
local point, clip_corner, clip_far = { 0, 0 }, { 0, 0 }, { 0, 0 };
function box.text(list, look, value, x, y, size, ink, width)
    if width < 3 or value == '' then return; end
    clip_corner[1], clip_corner[2], clip_far[1], clip_far[2] = floor(x), floor(y), math.ceil(x + width), math.ceil(y + size + 4);
    list:PushClipRect(clip_corner, clip_far, true);
    if not fonts.draw(list, look.font, value, x, y, size, ink) then
        point[1], point[2] = x, y;
        list:AddText(fonts.face(look.font), size, point, ink, value);
    end
    list:PopClipRect();
end

-- A countdown's text, made once for each value it shows (whole seconds under a minute, then minutes, then hours), so a
-- ticking timer makes nothing. A time that isn't a finite number shows nothing, as countdown_text.time says, and isn't
-- kept, since NaN can't be a key.
local texts, text_count = {}, 0;
local finite = require('ui.numbers').finite;
function box.time(left)
    if not finite(left) then return ''; end
    local key = left >= 3600 and 20000 + math.floor(left / 3600) or left >= 60 and 10000 + math.floor(left / 60) or math.ceil(left);
    local text = texts[key];
    if not text then
        text = require('ui.countdown_text').time(left);
        if text_count < 16384 then texts[key], text_count = text, text_count + 1; end
    end
    return text;
end
box.point = point;

return box;
