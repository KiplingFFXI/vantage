local imgui = require('imgui');
local hud, overlay = require('ui.party_hud'), require('ui.native_party_hud');
local defaults, store = require('ui.party_defaults'), require('core.store');
local equal = require('core.customization').equal;
local roster, subjects = hud.sample(18, 100);
MOCK.screen = { 2560, 2160 };
local mx, my, pressed, down, cursor, active, item = -1, -1, false, false, {}, nil, nil;
local rects, position, size = {}, {}, {};
imgui.GetMousePos = function() return mx, my; end;
imgui.IsMouseDown = function() return down; end;
imgui.SetCursorScreenPos = function(value) cursor = value; end;
imgui.SetNextWindowPos = function(value) position = value; end;
imgui.SetNextWindowSize = function(value) size = value; end;
imgui.Begin = function(name)
    rects[name] = { x = position[1], y = position[2], width = size[1], height = size[2] };
    return true;
end;
imgui.InvisibleButton = function(id, dimensions)
    item = { id = id, x = cursor[1], y = cursor[2], width = dimensions[1], height = dimensions[2] };
    if pressed and mx >= item.x and mx < item.x + item.width and my >= item.y and my < item.y + item.height then active = id; end;
end;
imgui.IsItemActivated = function() return pressed and item and item.id == active; end;
imgui.IsItemActive = function() return down and item and item.id == active; end;
imgui.IsItemHovered = function()
    return item and mx >= item.x and mx < item.x + item.width and my >= item.y and my < item.y + item.height;
end;
local starts, ends, saves, targets, before = 0, 0, 0, 0;
local config;
local callbacks = {
    shift = true,
    begin_edit = function() starts = starts + 1; before = store.copy(config); end,
    end_edit = function() ends = ends + 1; end,
    changed = function() saves = saves + 1; end,
    target = function() targets = targets + 1; end,
};
local function fresh()
    overlay.cancel_layout_gesture();
    config = defaults.make();
    config.locked = false;
    config.enabled, config.native.snap = true, false;
    mx, my, pressed, down, active = -1, -1, false, false, nil;
    starts, ends, saves, targets, before = 0, 0, 0, 0, nil;
    callbacks.shift, roster.typing, callbacks.input_blocked = true, false, false;
end;
local function point(rect, edge)
    local x = edge:find('left', 1, true) and rect.x + 1 or edge:find('right', 1, true) and rect.x + rect.width - 1 or rect.x + rect.width / 2;
    local y = edge:find('top', 1, true) and rect.y + 1 or edge:find('bottom', 1, true) and rect.y + rect.height - 1 or rect.y + rect.height / 2;
    return x, y;
end;
local function start(rect, edge, render)
    mx, my = point(rect, edge); pressed, down, active = true, true, nil;
    render(); pressed = false;
end;
local function release(render) down, pressed = false, false; render(); end;
local function near(a, b) return math.abs(a - b) < 0.001; end;

local geometry = { available = true, groups = {} };
for group = 1, 3 do
    local frame = { x = 1100, y = 60 + (group - 1) * 200, width = 116, height = 132, rows = {} };
    for _, member in ipairs(roster.members) do if member.group == group then
        frame.rows[member.slot] = { x = frame.x, y = frame.y + member.slot % 6 * 22, width = 116, height = 22 };
    end end;
    geometry.groups[group] = frame;
end;
callbacks.native_geometry = geometry;
local original_geometry = store.copy(geometry);
local function native_draw() return overlay.draw(roster, subjects, config, 100, callbacks); end;
local function native_panel(id) native_draw(); return rects['##vantage_native_' .. id]; end;
for _, side in ipairs({ 'left', 'right' }) do
    for _, edge in ipairs({ 'left', 'right' }) do
        fresh(); config.native.side = side;
        local native_before = store.copy(config.native);
        local adjacent_before = native_panel(1);
        local first = native_panel(2);
        start(first, edge, native_draw);
        local dx = edge:find('left', 1, true) and -40 or 40;
        mx, my = mx + dx, my + 20; native_draw(); release(native_draw);
        local last = native_panel(2);
        -- A strip beside the game's rows only moves from its edges; a panel of its own comes from its switch.
        assert(last.width == first.width and last.height == first.height and near(last.x, first.x + dx) and near(last.y, first.y + 20),
            'An attached strip\'s edge moves it at its size');
        assert(not config.groups[2].native_detached and config.groups[2].native_x == dx and config.groups[2].native_y == 20
            and equal(config.native, native_before), 'The strip stays beside the game\'s rows and keeps attachment preferences');
        local adjacent = native_panel(1);
        assert(adjacent.width == adjacent_before.width and not config.groups[1].native_detached and not config.groups[3].native_detached
            and config.groups[1].native_x == 0 and config.groups[3].native_x == 0, 'Other groups retain their attachment, width and offsets');
        assert(saves == 1 and starts == 1 and ends == 1 and targets == 0, 'A strip move saves once and never targets');
        assert(equal(geometry, original_geometry), 'Moving never modifies native game geometry');
    end;
end;
fresh(); local first = native_panel(1);
start(first, 'left', native_draw); my = my + 60; native_draw(); release(native_draw);
assert(config.native.width == 420 and saves == 1 and config.groups[1].native_x == 0 and config.groups[1].native_y == 60
    and not config.groups[1].native_detached, 'Down from a side edge moves the strip down and keeps its maximum width');
first = native_panel(1); start(first, 'left', native_draw); local origin = mx; mx = mx - 60; native_draw(); mx = origin; native_draw(); release(native_draw);
assert(near(native_panel(1).width, first.width), 'Native width returns to its starting value when the pointer reverses');
local count = saves;
first = native_panel(1); start(first, 'right', native_draw); mx = mx + 30; native_draw(); config.locked = true; native_draw(); native_draw();
assert(saves == count + 1 and ends == starts, 'Locking closes native resize once');
assert(equal(geometry, original_geometry) and #MOCK.font_stack == 0);
assert(roster.members[1].zone_name == "Southern San d'Oria", 'Preview uses the installed DAT name for zone 230');
fresh(); first = native_panel(1);
callbacks.input_blocked = true; start(first, 'left', native_draw); mx = mx - 40; native_draw(); release(native_draw);
assert(starts == 0 and saves == 0 and config.native.width == 420, 'Settings input blocks an underlying strip resize');

-- Exercise the actual settings history callbacks, not a local imitation of Undo.
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 230, job = 1, job_name = 'WAR',
    self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.roster'] = { read = function() return roster; end, target = function() error('Resize must never target'); end };
package.loaded['ui.hud'] = { draw = function() end, draw_notices = function() end, cancel_gesture = function() end };
package.loaded['ui.settings_window'] = { draw = function() end };
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, status = function() return {}; end,
    geometry = function() return geometry; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0); MOCK.key_shift = true;
local function entry_draw() config = app.state.settings.party_ui; MOCK.frame(0.2); config = app.state.settings.party_ui; end;
local function command(text) MOCK.fire('command', { command = text }); config = app.state.settings.party_ui; end;
-- The strip is what draws and resizes.
fresh();
app.state.settings.party_ui = config;
app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
entry_draw();
local id = '##vantage_native_1';
local previous = store.copy(config);
first = rects[id]; start(first, 'right', entry_draw); release(entry_draw);
assert(app.state.transaction == nil and #app.state.history == 0, 'A click without movement does not leave a stale transaction');
first = rects[id]; start(first, 'right', entry_draw); mx, my = mx + 60, my + 30; entry_draw(); release(entry_draw);
local edited = store.copy(app.state.settings.party_ui);
local transaction = app.state.transaction or app.state.history[#app.state.history];
assert(not equal(edited, previous) and transaction and transaction.label == 'Party layout', 'A resize enters the real party layout transaction: ' .. tostring(equal(edited, previous)) .. ':' .. tostring(transaction and transaction.label));
command('/vg undo');
assert(equal(config, previous) and #app.state.history == 0 and #app.state.redo == 1, 'Undo restores width, offsets and automatic sizing');
command('/vg redo');
assert(equal(config, edited) and #app.state.history == 1 and #app.state.redo == 0, 'Redo restores the completed resize');
entry_draw();
MOCK.fire('unload');
return 'Strip edge grips that only move, transaction boundaries and offsets';
