local imgui, hud = require('imgui'), require('ui.hud');
local defaults, copy, equal = require('ui.defaults'), require('core.store').copy, require('core.customization').equal;
local bit = require('bit');
local mx, my, down, pressed = -1, -1, false, false;
local position, size, current, cursor, item, rects, window_flags = {}, {}, nil, {}, nil, {}, {};
imgui.SetNextWindowPos = function(value) position = value; end;
imgui.SetNextWindowSize = function(value) size = value; end;
imgui.Begin = function(name, _, flags)
    current = { x = position[1], y = position[2], width = size[1], height = size[2] };
    rects[name], window_flags[name] = current, flags;
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

local settings, view, callbacks, saves, changes, before, render, name;
local function fresh(kind)
    hud.cancel_gesture(); hud.cancel_notice_gesture();
    settings, view = defaults.make(), hud.sample(100);
    settings.alerts.notice_locked = false;
    for key, panel in pairs(settings.panels) do panel.enabled = kind == 'timer' and key == 'self_buffs'; end;
    local p = settings.panels.self_buffs;
    p.locked, p.auto_width, p.auto_height, p.width, p.height_limit, p.x, p.y = false, false, false, 300, 200, 200, 150;
    settings.alerts.notice_x, settings.alerts.notice_y = 200, 150;
    settings.alerts.notice_width, settings.alerts.notice_height = 300, 200;
    view.notices = kind == 'notice' and { { visual = true, message = 'Protect is ending soon.', ends = 200 } } or {};
    name = kind == 'timer' and '##vantage_self_buffs' or '##vantage_notices';
    saves, changes, before = 0, 0, nil;
    callbacks = { shift = true, save = function() saves = saves + 1; end,
        changed = function(stage)
            if stage == 'before' then before = copy(settings); else changes = changes + 1; end;
        end };
    mx, my, down, pressed, item, rects = -1, -1, false, false, nil, {};
    MOCK.screen = { 1600, 900 };
    render = function()
        if kind == 'timer' then hud.draw(view, settings, 100, callbacks);
        else hud.draw_notices(view, settings, 100, callbacks); end;
    end;
    render();
    return settings.panels.self_buffs;
end;
local function start(edge)
    local first = rects[name];
    mx = edge:find('left', 1, true) and first.x + 1 or edge:find('right', 1, true) and first.x + first.width - 1 or first.x + first.width / 2;
    my = edge:find('top', 1, true) and first.y + 1 or edge:find('bottom', 1, true) and first.y + first.height - 1 or first.y + first.height / 2;
    down, pressed = true, true; render(); pressed = false;
    return first;
end;
local function release() down, pressed = false, false; render(); end;

for _, kind in ipairs({ 'timer', 'notice' }) do
    for _, edge in ipairs({ 'left', 'right', 'top', 'bottom', 'top_left', 'top_right', 'bottom_left', 'bottom_right' }) do
        fresh(kind);
        local first = start(edge);
        local horizontal, vertical = require('ui.resize').axes(edge);
        mx, my = mx + (edge:find('left', 1, true) and -30 or 30), my + (edge:find('top', 1, true) and -20 or 20);
        render(); release();
        local last = rects[name];
        if kind == 'timer' then assert(settings.panels.self_buffs.wrap, 'Every resize direction enables text wrapping.'); end;
        assert(last.width == first.width + (horizontal and 30 or 0), kind .. ':' .. edge .. ' changes only the selected horizontal axis');
        assert(last.height == first.height + (vertical and 20 or 0), kind .. ':' .. edge .. ' changes only the selected vertical axis');
        assert(last.x + last.width == first.x + first.width + (edge:find('right', 1, true) and 30 or 0), kind .. ':' .. edge .. ' preserves the opposite horizontal edge');
        assert(last.y + last.height == first.y + first.height + (edge:find('bottom', 1, true) and 20 or 0), kind .. ':' .. edge .. ' preserves the opposite vertical edge');
        assert(saves == 1 and before, kind .. ':' .. edge .. ' is one saved edit with a pre-edit snapshot');
    end;

    local p = fresh(kind);
    if kind == 'timer' then p.auto_width, p.auto_height, p.anchor.to, p.anchor.element = true, true, 'element', 'target';
    else settings.alerts.notice_x, settings.alerts.notice_height = -1, 0; end;
    render();
    local original = copy(settings);
    start('top_left'); render(); render(); release();
    assert(equal(settings, original) and changes == 0 and saves == 0, kind .. ' click without movement preserves automatic dimensions, anchors and history');

    p = fresh(kind);
    if kind == 'timer' then p.auto_width, p.auto_height = true, true;
    else settings.alerts.notice_x, settings.alerts.notice_height = -1, 0; end;
    render(); original = copy(settings);
    start('right'); my = my + 50; render(); release();
    assert(equal(settings, original) and changes == 0 and saves == 0, kind .. ' movement perpendicular to an edge does not change settings');

    fresh(kind); local first = start('top_left');
    local ox, oy = mx, my;
    mx, my = mx - 40, my - 30; render(); mx, my = ox, oy; render(); release();
    assert(equal(rects[name], first), kind .. ' pointer reversal restores the starting rectangle');
    assert(saves == 1, kind .. ' reversal remains one saved gesture');

    fresh(kind); first = start('top_left'); mx, my = -5000, -5000; render(); release();
    assert(rects[name].x == 0 and rects[name].y == 0 and rects[name].x + rects[name].width == first.x + first.width
        and rects[name].y + rects[name].height == first.y + first.height, kind .. ' growing top/left stays on screen with fixed far edges');
    fresh(kind); start('bottom_right'); mx, my = 9999, 9999; render(); release();
    assert(rects[name].x + rects[name].width <= 1600 and rects[name].y + rects[name].height <= 900, kind .. ' growing bottom/right stays on screen');

    for _, block in ipairs({ 'shift', 'typing', 'lock', 'peek_lock', 'settings' }) do
        p = fresh(kind);
        if block == 'shift' then callbacks.shift = false;
        elseif block == 'typing' then view.context.chat_open = true;
        elseif block == 'lock' then p.locked, settings.alerts.notice_locked = true, true;
        elseif block == 'peek_lock' then
            -- Seeing through settings doesn't get past a lock.
            p.locked, settings.alerts.notice_locked, settings.window.open, settings.window.peek = true, true, true, true;
            settings.window.x, settings.window.y, settings.window.width, settings.window.height = 0, 0, 1600, 900;
        else settings.window.open, settings.window.peek = true, false;
            settings.window.x, settings.window.y, settings.window.width, settings.window.height = 0, 0, 1600, 900; end;
        original = copy(settings); start('right'); mx = mx + 50; render(); release();
        assert(equal(settings, original) and not before and saves == 0, kind .. ':' .. block .. ' blocks gesture activation');
        assert(bit.band(window_flags[name], ImGuiWindowFlags_NoInputs) ~= 0, kind .. ':' .. block .. ' keeps the overlay from capturing input');
        -- A fixed overlay that never scrolls; a timer panel ignores the wheel too.
        local fixed = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoMove,
            ImGuiWindowFlags_NoCollapse, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoSavedSettings,
            ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav,
            kind == 'timer' and ImGuiWindowFlags_NoScrollWithMouse or 0);
        assert(bit.band(window_flags[name], fixed) == fixed, kind .. ':' .. block .. ' is a fixed overlay window');
    end;
    fresh(kind); settings.window.open, settings.window.peek = true, true;
    settings.window.x, settings.window.y, settings.window.width, settings.window.height = 0, 0, 1600, 900;
    start('right'); mx = mx + 50; render(); release();
    assert(saves == 1 and rects[name].width == 350, kind .. ' Shift peek permits adjustment below the settings window');

    for _, reason in ipairs({ 'shift', 'typing', 'cancel', 'screen', 'replace', 'lock', 'settings', 'settings_callback' }) do
        fresh(kind); start('right'); mx = mx + 30; render();
        if reason == 'shift' then callbacks.shift = false;
        elseif reason == 'typing' then view.context.chat_open = true;
        elseif reason == 'cancel' then if kind == 'timer' then hud.cancel_gesture(); else hud.cancel_notice_gesture(); end;
        elseif reason == 'screen' then MOCK.screen = { 1280, 720 };
        elseif reason == 'replace' then settings = defaults.make();
        elseif reason == 'lock' then settings.panels.self_buffs.locked, settings.alerts.notice_locked = true, true;
        elseif reason == 'settings' then
            settings.window.open, settings.window.peek = true, false;
            settings.window.x, settings.window.y, settings.window.width, settings.window.height = 0, 0, 1600, 900;
        elseif reason == 'settings_callback' then callbacks.settings_blocks_input = function() return true; end; end;
        local prior = copy(settings);
        if reason == 'lock' or reason == 'settings' or reason == 'settings_callback' then mx = mx + 50; end;
        render(); render();
        assert(saves == 1, kind .. ':' .. reason .. ' closes the changed gesture exactly once');
        if reason == 'replace' then assert(equal(settings, defaults.make()), kind .. ' a replacement settings table is not edited by an old gesture');
        elseif reason ~= 'screen' then assert(equal(settings, prior), kind .. ':' .. reason .. ' preserves completed changes'); end;
    end;
end;
fresh('timer');
start('center'); mx = mx + 20; render();
settings = defaults.make();
local replacement = copy(settings);
release();
assert(equal(settings, replacement), 'Releasing a drag while replacing settings leaves the new profile as it is.');
assert(saves == 1, 'Replacing settings at mouse release saves the original gesture once.');

fresh('timer'); start('right');
local filter, filtered, row_count = hud.filter_rows, 0, nil;
hud.filter_rows = function(...)
    filtered = filtered + 1;
    local rows = filter(...); row_count = #rows; return rows;
end;
mx = mx + 30; render();
assert(filtered == 1 and row_count > 0, 'Resizing rebuilds geometry without filtering and sorting the same rows twice.');
view.rows, filtered = {}, 0; render();
assert(filtered == 1 and row_count == 0, 'Row selection is refreshed next frame; the optimization retains no stale observations.');
hud.filter_rows = filter; release();

local p = fresh('timer');
p.labels[33], p.effect_colors[33], p.field_colors.name = 'My Haste', { .1, .2, .3, 1 }, { .4, .5, .6, 1 };
p.include, p.exclude, p.pinned, p.order = { [33] = true }, { [40] = true }, { [33] = true }, { 33, 40 };
local nested, observations = copy(p), copy(view);
render(); start('bottom_right'); mx, my = mx + 40, my + 30; render(); release();
for key, value in pairs(nested) do
    if type(value) == 'table' then assert(equal(p[key], value), 'Resizing does not mutate nested working maps: ' .. key); end;
end;
assert(equal(view, observations), 'Working display copies never mutate the observations they render.');

for _, mode in ipairs({ 'bars', 'expanded', 'icons' }) do
    p = fresh('timer');
    p.mode, p.width, p.height_limit, p.show_text = mode, 500, 600, false;
    settings.style.icon_size, settings.style.scale = 64, 2.5;
    render();
    local initial = start('right');
    mx = mx - 1000; render(); release();
    local expected = hud.bounds(p, settings.style, 1, 1600, 900).min_width;
    assert(rects[name].width == expected and p.width == expected,
        'Manual shrinking stops at the full fixed-art minimum: ' .. mode);
    assert(rects[name].x == initial.x and settings.style.icon_size == 64 and settings.style.scale == 2.5,
        'The fixed-art minimum preserves the opposite edge and selected artwork scale: ' .. mode);
    assert(saves == 1 and p.wrap, 'A constrained fixed-art resize is one wrapped edit: ' .. mode);
end;

fresh('notice'); settings.style.scale = 1.5; render();
local scaled = start('bottom_right'); mx, my = mx + 30, my + 30; render(); release();
assert(settings.alerts.notice_width == 320 and settings.alerts.notice_height == 220,
    'Notice resizing stores logical dimensions at a non-default scale.');
assert(rects[name].width == scaled.width + 30 and rects[name].height == scaled.height + 30,
    'Scaled notice resize follows the pointer in display pixels.');

for _, kind in ipairs({ 'timer', 'notice' }) do
    local p = fresh(kind);
    if kind == 'timer' then p.auto_height = true; else settings.alerts.notice_height = 0; end;
    render();
    local initial = rects[name].height;
    start('bottom_right'); mx = mx + 30; render(); release();
    assert(rects[name].height == initial, 'Horizontal corner movement preserves content height: ' .. kind);
    assert(kind == 'timer' and p.auto_height or kind == 'notice' and settings.alerts.notice_height == 0,
        'A corner changes automatic sizing only after that axis actually moves.');
end;
fresh('notice'); settings.alerts.notice_width = 900; render();
local constrained = copy(settings);
start('right'); mx = mx + 50; render(); release();
assert(equal(settings, constrained) and not before and changes == 0 and saves == 0,
    'Dragging a notice beyond its width limit cannot leave a pending history transaction.');
-- A resize snaps only the edge it pulls, here to another display's edge 3 pixels away; the edges across stay put.
local snap, elements = require('ui.snap'), require('ui.elements');
fresh('timer');
-- Self buffs ticked for Grid mode, which is on, snapping to the other displays only.
settings.edit_mode.grid_mode = true;
snap.tick(settings, 'self_buffs', true);
for _, switch in ipairs({ 'snap_grid', 'snap_screen', 'snap_party', 'snap_chat' }) do settings.edit_mode[switch] = false; end;
settings.edit_mode.snap_elements, settings.edit_mode.snap_distance = true, 6;
settings.panels.self_debuffs.enabled = true;
elements.frame(); elements.frame();
elements.record('self_debuffs', { x = 200, y = 150, width = 300, height = 200 });
for _, edge in ipairs({ 'left', 'right', 'top', 'bottom', 'top_left', 'top_right', 'bottom_left', 'bottom_right' }) do
    local rect = { x = 203, y = 153, width = 294, height = 194 };
    local snapped = snap.resize(settings, 'self_buffs', rect, edge, 0, 0, { screen_width = 1600, screen_height = 900 });
    if edge:find('left', 1, true) then assert(snapped.x == 200 and snapped.x + snapped.width == 497);
    elseif edge:find('right', 1, true) then assert(snapped.x == 203 and snapped.x + snapped.width == 500);
    else assert(snapped.x == 203 and snapped.width == 294); end;
    if edge:find('top', 1, true) then assert(snapped.y == 150 and snapped.y + snapped.height == 347);
    elseif edge:find('bottom', 1, true) then assert(snapped.y == 153 and snapped.y + snapped.height == 350);
    else assert(snapped.y == 153 and snapped.height == 194); end;
end;
-- A held drag keeps the resize cursor while the pointer runs past the display, as the party frame's does.
local cursors, active = 0, imgui.IsItemActive;
imgui.SetMouseCursor = function() cursors = cursors + 1; end;
imgui.IsItemActive = function() return down and item ~= nil; end;
for _, kind in ipairs({ 'timer', 'notice' }) do
    fresh(kind); render();
    start('right');
    mx, cursors = mx + 2000, 0;
    render();
    assert(cursors > 0, 'The resize cursor stays through a held drag past the edge: ' .. kind);
    release();
end;
imgui.IsItemActive = active;
assert(#MOCK.font_stack == 0, 'Resize drawing leaves the font stack balanced.');
