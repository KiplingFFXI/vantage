-- Edit mode (/vg edit, or Edit mode on the main page): every display on the screen gets an outline with its name, and a bar at
-- the top of the screen holds the picked display's lock, what it moves with and the way to its Size and place tab. Click a
-- display to pick it; hold Shift and drag to move it.
-- While Grid mode is on, a display ticked for it snaps to the grid, the screen's center and edges, the other displays,
-- the game's party list and the chat log, as settings.edit_mode chooses, and the grid shows while it is dragged if
-- Show the grid is on (ui/snap.lua, which every Shift drag uses); the bar then holds its tick and the grid's switches. While the bar or a
-- picked display has focus, the arrow keys move it 1 px, 10 with Shift, and Escape ends edit mode; Escape in the Grid
-- box only puts its number back, and the next Escape ends edit mode. Typed numbers for a spot are on the display's
-- Size and place tab, which the bar's button opens. A locked display can
-- be picked and looked at, but nothing moves it until it is unlocked in the bar; Shift never moves it. An anchored
-- display keeps its anchor and moves away from it. Each move is one Undo step: a drag or a run of arrow presses. Ending
-- edit mode leaves every display where it is. Overhead icons sit over heads in the world, so they aren't here. Only the
-- bar and the outlines take the mouse, and the keys only while one has focus.
local edit = {};
local elements = require('ui.elements');
local anchors = require('core.anchors');
local conditions = require('core.conditions');
local theme = require('ui.theme');
local controls = require('ui.controls');
local fonts = require('ui.fonts');
local snap = require('ui.snap');
local bit = require('bit');
local floor = math.floor;

local active, selected, gesture = false, nil, nil;
local message, message_at = nil, 0;
local bar = { x = 0, y = 0, width = 0, height = 0 };
-- Tables each frame refills: the window place and size, line ends, a move's start and the box's value.
local at, size, from, to, label_at, ZERO = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };
local start = {};
local grid_value = { 16 };
local TOP = { 0.5, 0 };
local ARROWS = { { 'ImGuiKey_LeftArrow', -1, 0 }, { 'ImGuiKey_RightArrow', 1, 0 }, { 'ImGuiKey_UpArrow', 0, -1 }, { 'ImGuiKey_DownArrow', 0, 1 } };
-- What a ticked display lines up with: the switches the bar shows, the keys they set and their Undo steps.
local SWITCHES = { { 'Grid', 'snap_grid', 'Line up with the grid' }, { 'Screen edges', 'snap_screen', 'Line up with the screen edges' },
    { 'Other displays', 'snap_elements', 'Line up with other displays' }, { 'Party list', 'snap_party', 'Line up with the party list' },
    { 'Chat log', 'snap_chat', 'Line up with the chat log' } };

local function say(text) message, message_at = text, os.clock(); end

function edit.active() return active; end

function edit.cancel_gesture()
    local prior = gesture;
    gesture = nil;
    if prior and prior.dirty and prior.callbacks.save then prior.callbacks.save(); end
end

function edit.start() active = true; end

-- Ending leaves every display where it is: a drag under way is kept as it stands.
function edit.stop()
    edit.cancel_gesture();
    active = false;
end

function edit.blocks_input(x, y)
    return active and x >= bar.x and y >= bar.y and x < bar.x + bar.width and y < bar.y + bar.height;
end

local function clamp(value, low, high) return math.max(low, math.min(high, value)); end

-- What a move of id starts from: the offsets its strip is drawn at, its anchor while the anchor placed it, or its spot
-- on the screen.
local function capture(settings, id, rect, into)
    local element, config = elements.by_id[id], elements.config(settings, id);
    into.id, into.width, into.height = id, rect.width, rect.height;
    if element.strip then
        into.kind = config.native_detached and 'detached' or 'strip';
        if config.native_detached then
            into.x, into.y = rect.x, rect.y;
        else
            into.x, into.y = require('ui.native_party_hud').drawn_offsets(element.strip, config.native_x or 0, config.native_y or 0);
        end
    elseif elements.anchored(id) then
        local anchor = elements.anchor(settings, id);
        into.kind, into.dx, into.dy, into.gap, into.offset = 'anchor', anchor.dx, anchor.dy, anchor.gap, anchor.offset;
    else
        into.kind, into.x, into.y = 'free', rect.x, rect.y;
    end
    return into;
end

-- Moves id dx, dy from where from_state left it, calling begin just before it writes. Returns whether anything changed.
local probe = {};
local function apply(settings, from_state, dx, dy, screen, begin)
    local id = from_state.id;
    local element, config = elements.by_id[id], elements.config(settings, id);
    -- A strip or an anchor moves by a whole offset. A display placed on the screen lands on the whole pixel nearest
    -- where the move puts it, so from a half pixel one arrow press moves its number on Size and place by exactly one.
    if from_state.kind == 'strip' or from_state.kind == 'anchor' then dx, dy = floor(dx + 0.5), floor(dy + 0.5); end
    local x_key, y_key, x, y = element.x, element.y, nil, nil;
    if from_state.kind == 'strip' then
        -- No further than still moves the strip on the screen, so a move back moves it at once.
        x_key, y_key = 'native_x', 'native_y';
        x, y = require('ui.native_party_hud').drawn_offsets(element.strip, from_state.x + dx, from_state.y + dy);
    elseif from_state.kind == 'detached' then
        x_key, y_key = 'detached_x', 'detached_y';
        x = clamp(floor(from_state.x + dx + 0.5), 0, floor(math.max(0, screen.x - from_state.width)));
        y = clamp(floor(from_state.y + dy + 0.5), 0, floor(math.max(0, screen.y - from_state.height)));
    elseif from_state.kind == 'anchor' then
        local anchor = elements.anchor(settings, id);
        probe.to, probe.side = anchor.to, anchor.side;
        probe.dx, probe.dy, probe.gap, probe.offset = from_state.dx, from_state.dy, from_state.gap, from_state.offset;
        anchors.move(probe, dx, dy);
        if anchor.to ~= 'screen' and (math.abs(probe.gap) >= 300 or math.abs(probe.offset) >= 2000) then
            say(elements.label(id) .. ' follows something, so it goes no further. Set Moves with to Nothing to place it freely.');
        end
        if probe.gap == anchor.gap and probe.offset == anchor.offset and probe.dx == anchor.dx and probe.dy == anchor.dy then return false; end
        if begin then begin(); end
        anchor = elements.anchor(settings, id);
        anchor.dx, anchor.dy, anchor.gap, anchor.offset = probe.dx, probe.dy, probe.gap, probe.offset;
        return true;
    else
        x = clamp(floor(from_state.x + dx + 0.5), 0, floor(math.max(0, screen.x - from_state.width)));
        y = clamp(floor(from_state.y + dy + 0.5), 0, floor(math.max(0, screen.y - from_state.height)));
    end
    if x == config[x_key] and y == config[y_key] then return false; end
    if begin then begin(); end
    config = elements.config(settings, id);
    config[x_key], config[y_key] = x, y;
    return true;
end

-- One step of a drag under way: from where it started, by the mouse, snapped. A press that hasn't moved yet moves
-- nothing, as each display's own Shift drag.
local function drag(settings, callbacks, mx, my, screen)
    local g = gesture;
    if not g.dirty and mx == g.mx and my == g.my then return; end
    local x, y = g.rect_x + mx - g.mx, g.rect_y + my - g.my;
    local shift_x, shift_y = snap.move(settings, g.from.id, x, y, g.from.width, g.from.height, screen.x, screen.y);
    if apply(settings, g.from, x + shift_x - g.rect_x, y + shift_y - g.rect_y, screen, not g.dirty and g.begin or nil) then
        g.dirty = true;
        if callbacks.changed then callbacks.changed('after'); end
    end
end

-- A move by the arrow keys: one Undo step, which a quick run of presses shares.
local function nudge(settings, callbacks, id, dx, dy, screen)
    local rect = elements.drawn(id);
    if not rect then return; end
    if elements.locked(settings, id) then say(elements.label(id) .. ' is locked. Unlock it here to move it.'); return; end
    -- A press toward an edge it already sits on would change a number and nothing on the screen.
    if dx > 0 and rect.x + rect.width >= screen.x or dx < 0 and rect.x <= 0 then dx = 0; end
    if dy > 0 and rect.y + rect.height >= screen.y or dy < 0 and rect.y <= 0 then dy = 0; end
    if dx == 0 and dy == 0 then return; end
    local moved = apply(settings, capture(settings, id, rect, start), dx, dy, screen, function()
        if callbacks.changed then callbacks.changed('before', 'Nudge ' .. elements.label(id)); end
    end);
    if moved and callbacks.changed then callbacks.changed('after'); end
end

local function outline(list, rect, ink, thickness)
    from[1], from[2], to[1], to[2] = rect.x, rect.y, rect.x + rect.width, rect.y + rect.height;
    list:AddRect(from, to, 0xC0000000, 0, 0, thickness + 2);
    list:AddRect(from, to, ink, 0, 0, thickness);
end

-- The name is drawn at 14 px in the window's font, so its box is measured at that size, not the font's own.
local function tag(imgui, list, rect, text, ink)
    local width = imgui.CalcTextSize(text) * 14 / imgui.GetFontSize();
    label_at[1], label_at[2] = rect.x + 3, rect.y + 2;
    from[1], from[2], to[1], to[2] = rect.x + 1, rect.y + 1, rect.x + math.min(rect.width - 1, width + 7), rect.y + 18;
    list:AddRectFilled(from, to, 0xD0171717, 2);
    list:AddText(imgui.GetFont(), 14, label_at, ink, text);
end

local HIT_FLAGS;
local function hit_flags(inputs)
    if not HIT_FLAGS then
        HIT_FLAGS = bit.bor(ImGuiWindowFlags_NoTitleBar or 0, ImGuiWindowFlags_NoResize or 0, ImGuiWindowFlags_NoMove or 0,
            ImGuiWindowFlags_NoCollapse or 0, ImGuiWindowFlags_NoScrollbar or 0, ImGuiWindowFlags_NoScrollWithMouse or 0,
            ImGuiWindowFlags_NoSavedSettings or 0, ImGuiWindowFlags_NoBackground or 0, ImGuiWindowFlags_NoFocusOnAppearing or 0,
            ImGuiWindowFlags_NoNav or 0, ImGuiWindowFlags_NoBringToFrontOnFocus or 0, ImGuiWindowFlags_NoDocking or 0);
    end
    return inputs and HIT_FLAGS or bit.bor(HIT_FLAGS, ImGuiWindowFlags_NoInputs or 0);
end

-- Each display's outline and name in a window of its own, which takes the click that picks it and the Shift drag
-- that moves it. Returns whether one of them has focus.
local function outlines(imgui, settings, callbacks, mx, my, shift, blocked, accent, screen)
    local focused = false;
    for _, element in ipairs(elements.movable) do
        local id = element.id;
        local rect = elements.on(settings, id) and elements.drawn(id);
        if rect and rect.width > 0 and rect.height > 0 then
            at[1], at[2], size[1], size[2] = rect.x, rect.y, math.max(8, rect.width), math.max(8, rect.height);
            imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, ZERO);
            imgui.PushStyleVar(ImGuiStyleVar_WindowMinSize, ZERO);
            imgui.SetNextWindowPos(at, ImGuiCond_Always);
            imgui.SetNextWindowSize(size, ImGuiCond_Always);
            if imgui.Begin('##vantage_edit_' .. id, true, hit_flags(not blocked)) then
                local list = imgui.GetWindowDrawList();
                local picked = selected == id;
                local locked = elements.locked(settings, id);
                outline(list, rect, picked and accent or (locked and 0xFF8C8C8C or 0xFFE6D5A8), picked and 2 or 1);
                local name = element.label .. (locked and '  (locked)' or '');
                if not conditions.shown(element.strip and 'party_ui' or id) then name = name .. '  (hidden here now)'; end
                tag(imgui, list, rect, name, picked and accent or 0xFFFFFFFF);
                if not blocked then
                    imgui.SetCursorPos(ZERO);
                    imgui.InvisibleButton('##edit_hit_' .. id, size);
                    if imgui.IsItemActivated() then
                        selected = id;
                        if gesture == nil and shift then
                            if locked then say(element.label .. ' is locked. Unlock it here to move it.');
                            else
                                local label = 'Move ' .. element.label;
                                gesture = { settings = settings, callbacks = callbacks, mx = mx, my = my, rect_x = rect.x, rect_y = rect.y,
                                    from = capture(settings, id, rect, {}),
                                    begin = function() if callbacks.changed then callbacks.changed('before', label); end end };
                            end
                        elseif not shift then say(locked and element.label .. ' is locked. Unlock it here to move it.' or 'Hold Shift and drag to move it.'); end
                    end
                end
                if imgui.IsWindowFocused and imgui.IsWindowFocused() then focused = true; end
            end
            imgui.End();
            imgui.PopStyleVar(2);
        end
    end
    return focused;
end

-- The settings window's look for the bar, worked out again for other settings and each half second, so a frame
-- doesn't build it.
local look_cache = { settings = nil, at = -1, look = nil };

-- Each checkbox's value, kept by its label so a frame makes no table for one.
local checks = {};
local function check(imgui, label, value, help)
    local state = checks[label];
    if not state then state = {}; checks[label] = state; end
    state[1] = value == true;
    local changed = controls.checkbox(imgui, look_cache.look, label, state);
    if help and imgui.IsItemHovered() then imgui.SetTooltip(help); end
    return changed, state[1];
end

-- A number box. A value typed in it takes once, when Enter is pressed or the box loses focus, so typing alone changes
-- nothing; its step buttons take at once, held down too. A click inside the box while typing in it is no step: this
-- box had the keys the frame before. Returns whether value takes this frame.
-- typing_in is the box that was the active item the frame before, active_box this frame's; draw_bar moves them on.
local typing_in, active_box;
local function box(imgui, label, value, step, fast)
    local typing = typing_in == label and imgui.GetIO().WantTextInput == true;
    local changed = imgui.InputInt(label, value, step, fast);
    if imgui.IsItemActive() then active_box = label; end
    if imgui.IsItemDeactivatedAfterEdit() then return true; end
    return changed and not typing and imgui.IsMouseDown(ImGuiMouseButton_Left or 0);
end

-- Opens a display's Size and place tab. A party group's is the party list buffs', and the pulse's is the Recasts panel's.
local function place_settings(element, callbacks)
    require('ui.panel_frame').open(element.strip and 'party_ui' or element.id == 'pulse' and 'recasts' or element.id, 'place');
    callbacks.open_page('Display');
end

-- The bar: Done, Undo and Redo, the picked display with its lock, what it moves with and the way to its Size and place tab, and
-- while Grid mode is on the picked display's tick for it, the grid size and the snapping switches. It doesn't take focus
-- as it opens, so the keys stay with the game until the bar or an outline is clicked. Returns whether it has focus.
local function draw_bar(imgui, settings, callbacks, screen)
    local e = settings.edit_mode;
    at[1], at[2] = screen.x / 2, 6;
    imgui.SetNextWindowPos(at, ImGuiCond_Always, TOP);
    local flags = bit.bor(ImGuiWindowFlags_NoSavedSettings or 0, ImGuiWindowFlags_NoCollapse or 0, ImGuiWindowFlags_NoMove or 0,
        ImGuiWindowFlags_NoResize or 0, ImGuiWindowFlags_AlwaysAutoResize or 0, ImGuiWindowFlags_NoFocusOnAppearing or 0,
        ImGuiWindowFlags_NoDocking or 0);
    local focused = false;
    if imgui.Begin('Vantage edit mode##vantage_edit_bar', true, flags) then
        typing_in, active_box = active_box, nil;
        focused = imgui.IsWindowFocused and imgui.IsWindowFocused(ImGuiFocusedFlags_RootAndChildWindows or 0) or false;
        local wx, wy = imgui.GetWindowPos();
        local ww, wh = imgui.GetWindowSize();
        bar.x, bar.y, bar.width, bar.height = wx, wy, ww, wh;
        if imgui.Button('Done##edit_done') then edit.stop(); end
        if imgui.IsItemHovered() then imgui.SetTooltip('Ends edit mode. Every display stays where it is.'); end
        imgui.SameLine();
        if imgui.Button('Undo##edit_undo') and callbacks.undo then callbacks.undo(); end
        imgui.SameLine();
        if imgui.Button('Redo##edit_redo') and callbacks.redo then callbacks.redo(); end
        local shown = selected and elements.by_id[selected] and elements.on(settings, selected) and elements.drawn(selected);
        imgui.SameLine();
        imgui.TextUnformatted('Display');
        imgui.SameLine();
        imgui.SetNextItemWidth(220);
        if imgui.BeginCombo('##edit_pick', selected and elements.label(selected) or 'Pick a display') then
            for _, element in ipairs(elements.movable) do
                if elements.on(settings, element.id) and elements.drawn(element.id) then
                    if imgui.Selectable(element.label .. '##edit_pick_' .. element.id, selected == element.id) then selected = element.id; end
                end
            end
            imgui.EndCombo();
        end
        if shown then
            local id = selected;
            local element = elements.by_id[id];
            local holder = elements.lock_holder(settings, id);
            local locked = elements.locked(settings, id);
            imgui.SameLine();
            local changed, value = check(imgui, 'Locked##edit_lock', locked,
                element.strip and 'Locks the party list buffs. Unlocked, each group can be moved here.' or 'Unlock to move it here. Locked, nothing moves it.');
            if changed then
                if callbacks.changed then callbacks.changed('before', (value and 'Lock ' or 'Unlock ') .. element.label); end
                holder[element.lock] = value;
                if callbacks.changed then callbacks.changed('after'); end
                if callbacks.save then callbacks.save(); end
            end
            imgui.SameLine();
            imgui.TextUnformatted('Moves with: ' .. elements.moves_with(settings, id));
            imgui.SameLine();
            if imgui.Button('Size and place##edit_place') and callbacks.open_page then place_settings(element, callbacks); end
            if imgui.IsItemHovered() then imgui.SetTooltip('Opens its Size and place tab, to type its spot or pick what it moves with.'); end
            if not conditions.shown(element.strip and 'party_ui' or id) then
                imgui.TextUnformatted('Its When to show rules hide it right now. Edit mode shows it anyway.');
            end
        elseif selected then
            imgui.TextUnformatted(elements.label(selected) .. ' is not on the screen now.');
        end
        if e.grid_mode then
            -- Its tick for Grid mode is the one on the main page. It moves nothing, so a locked display has it too.
            if shown then
                local ticked_now, ticked = check(imgui, 'Use Grid mode##edit_grid_tick', snap.ticked(settings, selected),
                    'Snaps while you drag it, and the grid shows. The same tick as its own on the main page.');
                if ticked_now then
                    if callbacks.changed then callbacks.changed('before', (ticked and 'Tick ' or 'Untick ') .. elements.label(selected) .. ' for Grid mode'); end
                    snap.tick(settings, selected, ticked);
                    if callbacks.changed then callbacks.changed('after'); end
                    if callbacks.save then callbacks.save(); end
                end
                imgui.SameLine();
            end
            local grid_shown, show_grid = check(imgui, 'Show the grid##edit_show_grid', e.show_grid);
            if grid_shown then
                if callbacks.changed then callbacks.changed('before', 'Show the grid'); end
                e.show_grid = show_grid;
                if callbacks.changed then callbacks.changed('after'); end
                if callbacks.save then callbacks.save(); end
            end
            imgui.SameLine();
            imgui.TextUnformatted('Grid');
            imgui.SameLine();
            grid_value[1] = e.grid;
            imgui.SetNextItemWidth(90);
            if box(imgui, '##edit_grid', grid_value, 1, 8) then
                local value = floor(clamp(tonumber(grid_value[1]) or e.grid, 4, 256));
                if value ~= e.grid then
                    if callbacks.changed then callbacks.changed('before', 'Grid size'); end
                    e.grid = value;
                    if callbacks.changed then callbacks.changed('after'); end
                    if callbacks.save then callbacks.save(); end
                end
            end
            imgui.SameLine();
            imgui.TextUnformatted('Line up with');
            for _, entry in ipairs(SWITCHES) do
                imgui.SameLine();
                local changed, value = check(imgui, entry[1] .. '##edit_' .. entry[2], e[entry[2]]);
                if changed then
                    if callbacks.changed then callbacks.changed('before', entry[3]); end
                    e[entry[2]] = value;
                    if callbacks.changed then callbacks.changed('after'); end
                    if callbacks.save then callbacks.save(); end
                end
            end
        end
        imgui.TextUnformatted('Click a display to pick it. Hold Shift and drag to move it. Arrow keys move it 1 pixel, 10 with Shift. Esc ends.');
        if message and os.clock() - message_at < 6 then imgui.TextUnformatted(message); end
    end
    imgui.End();
    return focused;
end

local function look_of(settings)
    local at = os.clock();
    if look_cache.settings ~= settings or at - look_cache.at > 0.5 or at < look_cache.at then
        look_cache.settings, look_cache.at = settings, at;
        look_cache.look = theme.window(settings);
    end
    return look_cache.look;
end

-- Drawn after every display each frame while edit mode is on. callbacks gives shift, focused, typing, settings_blocks_input,
-- changed, save, undo, redo and open_page.
function edit.draw(settings, callbacks)
    if not active then return; end
    local imgui = require('imgui');
    local screen = imgui.GetIO().DisplaySize;
    if screen.x <= 0 or screen.y <= 0 then edit.cancel_gesture(); return; end
    local shift = callbacks.shift == true;
    local typing = callbacks.typing == true;
    local mx, my = imgui.GetMousePos();
    local down = imgui.IsMouseDown(ImGuiMouseButton_Left or 0);
    if gesture and (gesture.settings ~= settings or not down or not shift or typing or not elements.drawn(gesture.from.id)) then edit.cancel_gesture(); end
    if gesture then drag(settings, callbacks, mx, my, screen); end
    local accent = bit.bor(theme.u32(settings.style.accent_color), 0xFF000000);
    -- Over the settings window or the bar, the outlines leave the mouse to them.
    local blocked = callbacks.settings_blocks_input and callbacks.settings_blocks_input(mx, my, shift, typing) or false;
    if gesture then blocked = false; end
    local look = look_of(settings);
    fonts.push_window(look.font, look.font_size);
    local focused = outlines(imgui, settings, callbacks, mx, my, shift, blocked, accent, screen);
    -- While a display ticked for Grid mode is dragged, the grid and the line it snapped to, as a Shift drag shows them.
    if gesture then snap.show(settings, gesture.from.id, screen.x, screen.y, elements.drawn(gesture.from.id)); end
    local colors = theme.push(settings, look);
    focused = draw_bar(imgui, settings, callbacks, screen) or focused;
    theme.pop(colors);
    fonts.pop();
    -- The keys go to edit mode only while the bar or a display's outline has focus, through ImGui's own capture.
    if not active or not focused or typing or callbacks.focused == false then return; end
    if imgui.SetNextFrameWantCaptureKeyboard then imgui.SetNextFrameWantCaptureKeyboard(true); end
    -- A value being typed in a box keeps its own keys. Escape there lets go of the box before this check, so the box
    -- that had the keys the frame before keeps them one frame more: that Escape only puts its number back.
    if imgui.IsAnyItemActive() or typing_in then return; end
    if ImGuiKey_Escape and imgui.IsKeyPressed(ImGuiKey_Escape, false) then edit.stop(); return; end
    if not selected or gesture then return; end
    local dx, dy = 0, 0;
    local step = shift and 10 or 1;
    for _, arrow in ipairs(ARROWS) do
        local key = _G[arrow[1]];
        if key and imgui.IsKeyPressed(key, true) then dx, dy = dx + arrow[2] * step, dy + arrow[3] * step; end
    end
    if dx ~= 0 or dy ~= 0 then nudge(settings, callbacks, selected, dx, dy, screen); end
end

if VANTAGE_TEST_MODE then
    edit._apply, edit._capture = apply, capture;
    function edit._message() return message; end
    function edit._gesture() return gesture; end
    function edit.selected() return selected; end
end

return edit;
