-- A whole addon over the mock with a working mouse, for drags and for reading where each window really went.
local store = require('core.store');
local copy = store.copy;
return function(screen, options)
    options = options or {};
    MOCK.screen = screen or { 1600, 900 };
    local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 17, level = 75, self_known = true, self_effects = {},
        party = {}, entities = { [1001] = { id = 1001, index = 0x400, name = 'Tester', kind = 'player' } } };
    package.loaded['core.client'] = { load = function() end, read = function() return copy(snapshot); end,
        visibility = function() return copy(snapshot); end, resolve = function(id) return { id = id }; end };
    package.loaded['core.observer'] = { read = function() return {}; end };
    local game = options.game or { available = true, groups = { { x = 1300, y = 600, width = 200, height = 40,
        rows = { [0] = { x = 1300, y = 600, width = 200, height = 40, slot = 0 } } } } };
    package.loaded['core.native_party_ui'] = { status = function() return { available = true }; end,
        treasure_open = function() return false; end, geometry = function() return game; end };
    local imgui = require('imgui');
    local mouse = { x = -1, y = -1, down = false, pressed = false };
    local function inside(rect)
        return mouse.x >= rect.x and mouse.x < rect.x + rect.width and mouse.y >= rect.y and mouse.y < rect.y + rect.height;
    end;
    local begin, next_pos, next_size = imgui.Begin, imgui.SetNextWindowPos, imgui.SetNextWindowSize;
    local place, size, window, cursor, item, active = { 0, 0 }, { 0, 0 }, { x = 0, y = 0 }, { 0, 0 }, nil, nil;
    local items, windows = {}, {};
    rawset(imgui, 'SetNextWindowPos', function(value, ...) place = { value[1], value[2] }; return next_pos(value, ...); end);
    rawset(imgui, 'SetNextWindowSize', function(value, ...) size = { value[1], value[2] }; return next_size(value, ...); end);
    local frame_no = 0;
    rawset(imgui, 'Begin', function(name, a, flags, ...)
        window = { x = place[1], y = place[2] };
        windows[name] = { x = place[1], y = place[2], width = size[1], height = size[2], frame = frame_no, flags = flags };
        return begin(name, a, flags, ...);
    end);
    rawset(imgui, 'SetCursorPos', function(value) cursor = { window.x + value[1], window.y + value[2] }; end);
    rawset(imgui, 'SetCursorScreenPos', function(value) cursor = { value[1], value[2] }; end);
    rawset(imgui, 'InvisibleButton', function(id, extent)
        item = { id = id, x = cursor[1], y = cursor[2], width = extent[1], height = extent[2], frame = frame_no };
        items[id] = item;
        if mouse.pressed and inside(item) then active = id; end;
        return false;
    end);
    rawset(imgui, 'IsItemHovered', function() return item ~= nil and inside(item); end);
    rawset(imgui, 'IsItemActivated', function() return mouse.pressed and item ~= nil and active == item.id; end);
    rawset(imgui, 'IsItemActive', function() return mouse.down and item ~= nil and active == item.id; end);
    rawset(imgui, 'IsMouseClicked', function() return mouse.pressed; end);
    rawset(imgui, 'IsMouseDown', function() return mouse.down; end);
    rawset(imgui, 'GetMousePos', function() return mouse.x, mouse.y; end);
    local keys = {};
    rawset(imgui, 'IsKeyPressed', function(key) return keys[key] == true; end);
    rawset(imgui, 'IsWindowFocused', function() return true; end);
    rawset(imgui, 'SetNextFrameWantCaptureKeyboard', function() end);
    if not imgui.IsAnyItemActive then rawset(imgui, 'IsAnyItemActive', function() return false; end); end;
    local function lines()
        local list = setmetatable({ lines = {} }, { __index = function() return function() end; end });
        list.AddLine = function(self, from, to) self.lines[#self.lines + 1] = { from[1], from[2], to[1], to[2] }; end;
        list.GetClipRectMin = function() return 0, 0; end;
        list.GetClipRectMax = function() return MOCK.screen[1], MOCK.screen[2]; end;
        return list;
    end;
    local back, front = lines(), lines();
    rawset(imgui, 'GetBackgroundDrawList', function() return back; end);
    rawset(imgui, 'GetForegroundDrawList', function() return front; end);
    local w = { imgui = imgui, mouse = mouse, items = items, windows = windows, snapshot = snapshot, game = game, keys = keys, back = back, front = front };
    function w.frame(seconds)
        frame_no = frame_no + 1;
        back.lines, front.lines = {}, {};
        MOCK.frame(seconds or 1 / 60);
        mouse.pressed = false;
    end;
    function w.settle(count) for _ = 1, count or 6 do w.frame(0.2); end; end;
    local app = dofile(ADDON_DIR .. '/vantage.lua');
    MOCK.fire('load'); app.refresh(0);
    w.app = app;
    w.s = function() return app.state.settings; end;
    -- Whether an item or window was made in the latest frame.
    function w.current(id) local it = items[id]; return it and it.frame == frame_no and it or nil; end;
    function w.window(name) local it = windows[name]; return it and it.frame == frame_no and it or nil; end;
    -- A press at x, y, moved by dx, dy in steps, then let go.
    function w.press(x, y) active, mouse.x, mouse.y, mouse.down, mouse.pressed = nil, x, y, true, true; w.frame(); end;
    function w.to(x, y) mouse.x, mouse.y = x, y; w.frame(); end;
    function w.release() mouse.down = false; w.frame(); w.frame(); end;
    function w.drag(x, y, dx, dy)
        w.press(x, y);
        w.to(x + dx, y + dy);
        w.frame();
        w.release();
    end;
    return w;
end;
