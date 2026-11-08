-- A real panel dragged under the see-through settings window, frame by frame in the app's order: settings, then the
-- displays. The drag goes on across the window's title bar and edge, the window stays see-through for all of it, and
-- the panel lands where the pointer took it. A locked panel doesn't move for any of this, and Shift let go ends the drag.
local imgui, hud = require('imgui'), require('ui.hud');
local defaults = require('ui.defaults');
local app = dofile(ADDON_DIR .. '/vantage.lua');
local window = require('ui.settings_window');
MOCK.fire('load'); app.refresh(0);

local BOX = { x = 300, y = 100, width = 800, height = 600 };
local mx, my, down, pressed = -1, -1, false, false;
local position, size, current, cursor, item, rects, shows = {}, {}, nil, {}, nil, {}, {};
local set_pos, set_size, begin = imgui.SetNextWindowPos, imgui.SetNextWindowSize, imgui.Begin;
imgui.SetNextWindowPos = function(value, ...) position = value; return set_pos(value, ...); end;
imgui.SetNextWindowSize = function(value, ...) size = value; return set_size(value, ...); end;
imgui.Begin = function(name, open, flags)
    current = { x = position[1], y = position[2], width = size[1], height = size[2] };
    rects[name] = current;
    return begin(name, open, flags);
end;
imgui.GetMousePos = function() return mx, my; end;
imgui.IsMouseDown = function() return down; end;
imgui.IsMouseClicked = function() return pressed; end;
imgui.SetCursorPos = function(value) cursor = { current.x + value[1], current.y + value[2] }; end;
imgui.InvisibleButton = function(_, dimensions)
    item = { x = cursor[1], y = cursor[2], width = dimensions[1], height = dimensions[2] };
end;
imgui.IsItemHovered = function()
    return item and mx >= item.x and mx < item.x + item.width and my >= item.y and my < item.y + item.height;
end;
-- A panel's press is an active item from the next frame on, as in the game.
local active = false;
rawset(imgui, 'IsAnyItemActive', function() return active; end);

local settings, view, callbacks, saves;
local plain = { rows = {}, context = { valid = true, job = 3, entities = {} } };
local shift = true;
local function fresh(locked)
    hud.cancel_gesture();
    settings, view, saves, active, shift = defaults.make(), hud.sample(100), 0, false, true;
    settings.window.open, settings.window.tab = true, 'Home';
    settings.window.x, settings.window.y, settings.window.width, settings.window.height = BOX.x, BOX.y, BOX.width, BOX.height;
    for key, panel in pairs(settings.panels) do panel.enabled = key == 'self_buffs'; end;
    local p = settings.panels.self_buffs;
    p.locked, p.auto_width, p.auto_height, p.width, p.height_limit, p.x, p.y = locked, false, false, 300, 200, 400, 300;
    app.state.settings = settings;
    callbacks = setmetatable({ save = function() saves = saves + 1; end, changed = function() end,
        settings_blocks_input = function(x, y, held, typing) return window.blocks_input(settings, x, y, held, typing); end }, { __index = function(_, key)
            if key == 'shift' then return shift; end;
            return app.callbacks[key];
        end });
    MOCK.window_size, MOCK.window_pos['Vantage##settings'] = { BOX.width, BOX.height }, { BOX.x, BOX.y };
    mx, my, down, pressed, item = -1, -1, false, false, nil;
end;
-- One frame at the pointer: whether the window was see-through.
local function frame(x, y)
    if x then mx, my = x, y; end;
    MOCK.imgui_calls = {};
    window.draw(settings, plain, callbacks);
    local solid = false;
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Checkbox' or call[1] == 'Button' then solid = true; end; end;
    hud.draw(view, settings, 100, callbacks);
    return not solid;
end;
local function press(x, y)
    down, pressed = true, true;
    local through = frame(x, y);
    pressed = false;
    active = true;
    return through;
end;
local function release()
    down, active = false, false;
    frame();
end;

-- Under the window, across its title bar and out over the top: every frame see-through, and the panel keeps up.
fresh(false);
shift = false; frame(1400, 800);
shift = true;
assert(frame(550, 400), 'Fixture: over the panel, under the window, it is see-through.');
assert(press(550, 400), 'The press.');
assert(frame(550, 350), 'Dragging under the window.');
assert(frame(550, 110), 'Over the title bar.');
assert(frame(550, 40), 'Past it.');
assert(frame(300, 40), 'Along the edge.');
release();
local p = settings.panels.self_buffs;
assert(p.x == 150 and p.y == 0, 'The panel lands where the pointer took it, kept on screen: ' .. p.x .. ', ' .. p.y);
assert(saves == 1, 'One saved drag: ' .. saves);

-- Across the side edge, ending over the window's title: the drag ends only when the button comes up.
fresh(false);
shift = false; frame(1400, 800);
shift = true;
frame(550, 400);
press(550, 400);
frame(300, 400);
frame(250, 400);
frame(320, 112);
release();
p = settings.panels.self_buffs;
assert(p.x == 170 and p.y == 12, 'Over the edge and onto the title bar: ' .. p.x .. ', ' .. p.y);

-- Shift let go ends the drag where it was.
fresh(false);
shift = false; frame(1400, 800);
shift = true;
frame(550, 400);
press(550, 400);
frame(560, 400);
shift = false;
assert(not frame(600, 400), 'Shift let go, the window is back.');
release();
assert(settings.panels.self_buffs.x == 410, 'The drag stopped with Shift: ' .. settings.panels.self_buffs.x);

-- A saved lock holds under a see-through window, however the press goes.
fresh(true);
shift = false; frame(1400, 800);
shift = true;
frame(550, 400);
assert(press(550, 400), 'The press on a locked panel.');
frame(550, 110);
frame(550, 40);
release();
p = settings.panels.self_buffs;
assert(p.x == 400 and p.y == 300 and saves == 0, 'A locked panel stays: ' .. p.x .. ', ' .. p.y);
