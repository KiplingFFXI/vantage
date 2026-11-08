-- A timer panel drag reports an edit only on frames that moved or resized the panel.
local imgui, hud = require('imgui'), require('ui.hud');
local defaults, copy, equal = require('ui.defaults'), require('core.store').copy, require('core.customization').equal;
local mx, my, down, pressed = -1, -1, false, false;
local position, size, current, cursor, item, rects = {}, {}, nil, {}, nil, {};
imgui.SetNextWindowPos = function(value) position = value; end;
imgui.SetNextWindowSize = function(value) size = value; end;
imgui.Begin = function(name)
    current = { x = position[1], y = position[2], width = size[1], height = size[2] };
    rects[name] = current;
    return true;
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

local settings, view, callbacks, changes, saves;
local function layout(p) return { p.x, p.y, p.width, p.height_limit, p.wrap, p.auto_width, p.auto_height }; end;
local function render() hud.draw(view, settings, 100, callbacks); end;
local function fresh()
    hud.cancel_gesture();
    settings, view = defaults.make(), hud.sample(100);
    for key, panel in pairs(settings.panels) do panel.enabled = key == 'self_buffs'; end;
    local p = settings.panels.self_buffs;
    p.locked, p.auto_width, p.auto_height, p.width, p.height_limit, p.x, p.y = false, false, false, 300, 200, 200, 150;
    changes, saves = 0, 0;
    callbacks = { shift = true, save = function() saves = saves + 1; end,
        changed = function(stage) if stage ~= 'before' then changes = changes + 1; end; end };
    mx, my, down, pressed, item, rects = -1, -1, false, false, nil, {};
    MOCK.screen = { 1600, 900 };
    render();
    return p;
end;
local function start(edge)
    local first = rects['##vantage_self_buffs'];
    mx = edge == 'right' and first.x + first.width - 1 or first.x + first.width / 2;
    my = edge == 'bottom' and first.y + first.height - 1 or first.y + first.height / 2;
    down, pressed = true, true; render(); pressed = false;
end;

for _, edge in ipairs({ 'center', 'right', 'bottom' }) do
    local p = fresh();
    start(edge);
    mx, my = mx + 30, my + 20; render();
    for _ = 1, 5 do render(); end;
    assert(changes == 1, edge .. ': a move then holding still mid-drag is one edit.');
    mx, my = mx + 7, my + 9; render();
    assert(changes == 2, edge .. ': moving again is one more edit.');
    local held = copy(p);
    render(); render();
    assert(changes == 2 and equal(p, held), edge .. ': still frames keep the dragged layout.');
    down = false; render();
    assert(saves == 1 and changes == 2, edge .. ': release saves the gesture once.');
end;

-- Property: across random mouse paths, edits are reported on exactly the frames whose layout changed.
math.randomseed(20261016);
for _ = 1, 60 do
    local p = fresh();
    start(({ 'center', 'right', 'bottom' })[math.random(3)]);
    local expected, previous = 0, layout(p);
    for _ = 1, 40 do
        if math.random(3) == 1 then mx, my = mx + math.random(-12, 12), my + math.random(-12, 12); end;
        render();
        local now = layout(p);
        if not equal(now, previous) then expected = expected + 1; end;
        previous = now;
    end;
    assert(changes == expected, 'Edits match the frames that changed the panel layout.');
    down = false; render();
end;
