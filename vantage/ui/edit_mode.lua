-- Edit mode, called Arrange on screen (/vg edit, or Arrange on screen on the main page): every display on the screen gets
-- an outline with its name, and a bar at the top of the screen holds what the picked display moves with and the way to
-- its Size and place tab. Click a display to pick it. Hold Shift and drag to move it. While the open settings window
-- reaches the bar's spot, the bar goes to the bottom of the screen, and where it reaches that too the bar comes in front
-- of it and stays there.
-- While Snap while moving (grid_mode) is on, a display ticked for it snaps to the grid, the screen's center and edges, the
-- other displays, the game's party list and the chat log, as settings.edit_mode chooses, and the grid shows while it is
-- dragged if Show the grid is on (ui/snap.lua, which every Shift drag uses). The bar holds the Snap while moving tick, and
-- while it is on the Snapping section: the picked display's tick, the grid and what a display snaps to. While the bar or a
-- picked display has focus, the arrow keys move it 1 px, 10 with Shift, and Escape ends edit mode; Escape in the Grid
-- box only puts its number back, Escape on the Pick a display list only closes it, and the next Escape ends edit mode. Typed numbers for a spot are on the display's
-- Size and place tab, which the bar's button opens. A lock only stops a Shift drag outside edit mode, so here a locked
-- display moves as any other does. An anchored
-- display keeps its anchor and moves away from it. Each move is one Undo step: a drag or a run of arrow presses. Ending
-- edit mode leaves every display where it is. Overhead icons sit over heads in the world, so they aren't here. Only the
-- bar and the outlines take the mouse, and the keys only while one has focus.
local edit = {};
local elements = require('ui.elements');
local anchors = require('core.anchors');
local conditions = require('core.conditions');
local theme = require('ui.theme');
local steady = require('core.steady');
local controls = require('ui.controls');
local fonts = require('ui.fonts');
local snap = require('ui.snap');
local resize = require('ui.resize');
local bit = require('bit');
local floor = math.floor;

local active, selected, gesture = false, nil, nil;
-- Whether the bar's Pick a display list is open this frame, and was the frame before. ImGui closes it on Escape before
-- edit mode sees the key, so that Escape ends nothing else.
local listing, listed = false, false;
local message, message_at = nil, 0;
-- Where the bar was drawn last, and the most room it has taken since edit mode started.
local bar = { x = 0, y = 0, width = 0, height = 0, wide = 0, tall = 0 };
-- Tables each frame refills: the window place and size, line ends, a move's start and the box's value.
local at, size, from, to, label_at, ZERO = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };
local start = {};
local grid_value, distance_value = { 16 }, { 8 };
local TOP, BOTTOM = { 0.5, 0 }, { 0.5, 1 };
local HELP = 'Click a display to pick it. Hold Shift and drag to move it. Arrow keys move it 1 pixel, 10 with Shift. Esc ends.';
local ARROWS = { { 'ImGuiKey_LeftArrow', -1, 0 }, { 'ImGuiKey_RightArrow', 1, 0 }, { 'ImGuiKey_UpArrow', 0, -1 }, { 'ImGuiKey_DownArrow', 0, 1 } };
-- What a ticked display lines up with: the switches the bar shows, the keys they set and their Undo steps.
local SNAP_HELP = 'A display you move or resize lines up with the grid, the screen\'s edges and the other displays. Arrange on screen\'s bar picks which ones snap and to what.';
local SWITCHES = { { 'Grid', 'snap_grid', 'Line up with the grid' }, { 'Screen edges', 'snap_screen', 'Line up with the screen edges' },
    { 'Other displays', 'snap_elements', 'Line up with other displays' }, { 'Party list', 'snap_party', 'Line up with the party list' },
    { 'Chat log', 'snap_chat', 'Line up with the chat log' } };

local function say(text) message, message_at = text, steady(); end

function edit.active() return active; end

function edit.cancel_gesture()
    local prior = gesture;
    gesture = nil;
    if prior and prior.dirty and prior.callbacks.save then prior.callbacks.save(); end
end

function edit.start() active, listing, listed, bar.wide, bar.tall, bar.covered, bar.forward = true, false, false, 0, 0, false, false; end

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
local function capture(settings, id, rect, into, screen)
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
        -- Where it is drawn, and where its anchor puts it, which is past the edge when it is drawn at the edge.
        into.x, into.y = rect.x, rect.y;
        into.ax, into.ay = elements.spot(settings, id, rect.width, rect.height, screen.x, screen.y);
        if not into.ax then into.ax, into.ay = rect.x, rect.y; end
    else
        into.kind, into.x, into.y = 'free', rect.x, rect.y;
        -- Its Across and Down as they are, which a move keeps on an axis it doesn't go along.
        into.kept_x, into.kept_y = config[element.x], config[element.y];
    end
    return into;
end

-- Moves id dx, dy from where from_state left it, calling begin just before it writes. Returns whether anything changed.
local probe = {};
local function apply(settings, from_state, dx, dy, screen, begin)
    local id = from_state.id;
    local element, config = elements.by_id[id], elements.config(settings, id);
    -- An anchored display moves from where it is drawn and no further than the screen's edges, as one placed on the
    -- screen does, so its numbers never run on past an edge where nothing on the screen moves.
    if from_state.kind == 'anchor' then
        dx = clamp(from_state.x + dx, 0, math.max(0, screen.x - from_state.width)) - from_state.ax;
        dy = clamp(from_state.y + dy, 0, math.max(0, screen.y - from_state.height)) - from_state.ay;
    end
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
        -- An axis the move doesn't go along keeps its number, so Across at Centered, or a number typed past the
        -- screen's edge for a bigger screen, stays. A drag back to where it started puts it back.
        if dx == 0 then x = from_state.kept_x; end
        if dy == 0 then y = from_state.kept_y; end
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
    -- The move is the mouse's move plus the snap's shift. The mouse's move is worked out first, so along an axis the
    -- mouse hasn't moved, the display snaps from exactly where it was drawn, even at a fraction of a pixel. When the
    -- snap doesn't shift it, the move along that axis is then exactly 0, so a display that isn't anchored keeps that
    -- axis's number. A party list strip saves where it is drawn.
    local x, y = g.rect_x + (mx - g.mx), g.rect_y + (my - g.my);
    local shift_x, shift_y = snap.move(settings, g.from.id, x, y, g.from.width, g.from.height, screen.x, screen.y);
    if apply(settings, g.from, mx - g.mx + shift_x, my - g.my + shift_y, screen, not g.dirty and g.begin or nil) then
        g.dirty = true;
        if callbacks.changed then callbacks.changed('after', nil, 'place'); end
    end
end

-- Opens an Undo step. vantage.lua closes a step at the save 0.6 s after the last change, so a quick run of arrow
-- presses on one display, or of a box's steps, shares one. A step still open with another name, a nudge's or one from
-- the settings window, is closed first, so this change is a step of its own. alone closes it whatever its name, as a
-- drag does.
local function begin_step(callbacks, label, alone)
    local history = callbacks.history_status and callbacks.history_status();
    local open = history and history.open_label;
    if (alone or open and open ~= label) and callbacks.save then callbacks.save(); end
    if callbacks.changed then callbacks.changed('before', label); end
end

-- A move by the arrow keys: one Undo step, which a quick run of presses shares.
local function nudge(settings, callbacks, id, dx, dy, screen)
    local rect = elements.drawn(id);
    if not rect then return; end
    -- A press toward an edge it already sits on would change a number and nothing on the screen.
    if dx > 0 and rect.x + rect.width >= screen.x or dx < 0 and rect.x <= 0 then dx = 0; end
    if dy > 0 and rect.y + rect.height >= screen.y or dy < 0 and rect.y <= 0 then dy = 0; end
    if dx == 0 and dy == 0 then return; end
    local moved = apply(settings, capture(settings, id, rect, start, screen), dx, dy, screen, function()
        begin_step(callbacks, 'Nudge ' .. elements.label(id));
    end);
    if moved and callbacks.changed then callbacks.changed('after', nil, 'place'); end
end

local function outline(list, rect, ink, thickness)
    from[1], from[2], to[1], to[2] = rect.x, rect.y, rect.x + rect.width, rect.y + rect.height;
    list:AddRect(from, to, 0xC0000000, 0, 0, thickness + 2);
    list:AddRect(from, to, ink, 0, 0, thickness);
end

-- The name sits just above the display, so it covers none of the display's own heading or icons, and above a SAMPLE
-- tag it would touch there. Near the top of the screen it sits just below instead. It is drawn at 14 px in the
-- window's font, so its box is measured at that size, not the font's own.
local function tag(imgui, list, rect, text, ink, screen)
    local width = imgui.CalcTextSize(text) * 14 / imgui.GetFontSize() + 7;
    local x, y = floor(math.max(0, math.min(rect.x, screen.x - width))), floor(rect.y - 20);
    local top = resize.sample_tag(x, y, width, 18);
    if top then y = floor(top - 20); end
    if y < 0 then
        y = floor(rect.y + rect.height + 2);
        local _, bottom = resize.sample_tag(x, y, width, 18);
        if bottom then y = floor(bottom + 2); end
    end
    from[1], from[2], to[1], to[2] = x, y, x + width, y + 18;
    label_at[1], label_at[2] = x + 3, y + 2;
    list:AddRectFilled(from, to, 0xD0171717, 2);
    list:AddText(imgui.GetFont(), 14, label_at, ink, text);
end

local policy = require('ui.frame_policy');

-- Each display gets a window of edit mode's own, which takes the click that picks it and the Shift drag that moves it,
-- and an outline with its name. Those go on the display's own window when it opened one, as edit mode's windows sit
-- behind the displays, and after every window has ended, so no window cuts the outline at its edge. Returns whether
-- one of edit mode's windows has focus.
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
            local list;
            if imgui.Begin('##vantage_edit_' .. id, true, policy.flags(policy.HIT, not blocked)) then
                list = imgui.GetWindowDrawList();
                if not blocked then
                    imgui.SetCursorPos(ZERO);
                    imgui.InvisibleButton('##edit_hit_' .. id, size);
                    if imgui.IsItemActivated() then
                        selected = id;
                        if gesture == nil and shift then
                            local label = 'Move ' .. element.label;
                            -- A drag is an Undo step of its own, so as it starts it closes the one a quick run of
                            -- arrow presses still has open.
                            gesture = { settings = settings, callbacks = callbacks, mx = mx, my = my, rect_x = rect.x, rect_y = rect.y,
                                from = capture(settings, id, rect, {}, screen),
                                begin = function()
                                    begin_step(callbacks, label, true);
                                end };
                        elseif not shift then say('Hold Shift and drag to move it.'); end
                    end
                end
                if imgui.IsWindowFocused and imgui.IsWindowFocused() then focused = true; end
            end
            imgui.End();
            imgui.PopStyleVar(2);
            list = elements.window_list(id) or list;
            if list then
                local picked = selected == id;
                outline(list, rect, picked and accent or 0xFFE6D5A8, picked and 2 or 1);
                local name = element.label;
                if not conditions.shown(element.strip and 'party_ui' or id) then name = name .. '  (hidden here now)'; end
                tag(imgui, list, rect, name, picked and accent or 0xFFFFFFFF, screen);
            end
        end
    end
    return focused;
end

-- The settings window's look for the bar. theme.window keeps it until the settings count a change that may change a
-- look, so a frame doesn't build it, nor a frame of a drag.
local look_cache = { look = nil };

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
-- box had the keys the frame before. Returns whether value takes this frame, and whether it was typed. A step button
-- repeats while it is held, so its value is saved after the mouse comes up, as one Undo step.
-- typing_in is the box that was the active item the frame before, active_box this frame's; draw_bar moves them on.
local typing_in, active_box;
-- A box's width: room for its biggest number, 256, and its two step buttons at the bar's text size.
local function number_width(imgui) return math.max(90, imgui.CalcTextSize('256') + 2 * imgui.GetFrameHeight() + 24); end
-- The bar sizes to what it holds, so the next item, width wide, goes on below where it would run past the screen's edge,
-- where the help line wraps.
local function beside(imgui, screen, width)
    imgui.SameLine();
    if imgui.GetCursorPosX() + width > screen.x - 12 - bar.left then imgui.NewLine(); end
end
local function box(imgui, label, value, step, fast)
    local typing = typing_in == label and imgui.GetIO().WantTextInput == true;
    local changed = imgui.InputInt(label, value, step, fast);
    if imgui.IsItemActive() then active_box = label; end
    if imgui.IsItemDeactivatedAfterEdit() then return true, true; end
    return changed and not typing and imgui.IsMouseDown(ImGuiMouseButton_Left or 0), false;
end

-- Opens a display's Size and place tab. A party group's is Party list's. Back in the window comes to where it was.
local function place_settings(element, callbacks, settings)
    local frame = require('ui.panel_frame');
    if settings.window.open then frame.remember(settings); end
    frame.open(element.strip and 'party_ui' or element.id, 'place');
    callbacks.open_page('Display');
end

-- Whether the settings window's area reaches a bar that size at that spot.
local function reaches(area, left, top, wide, tall)
    return area and area.x < left + wide and area.x + area.width > left and area.y < top + tall and area.y + area.height > top;
end

-- The bar's spot: the top middle of the screen, or the bottom middle while the open settings window reaches it, so the
-- window's title and first row stay clear. The spot is the most room the bar has taken since edit mode started, so a line
-- that comes and goes doesn't move it. It is never less than the help line and three rows, which every bar has: ImGui
-- sizes a new window only after its first frame. bar.covered says the window reaches the bottom middle too.
local function bar_spot(imgui, screen, area)
    local wide = math.min(screen.x - 12, math.max(bar.wide, (imgui.CalcTextSize(HELP))));
    local tall = math.max(bar.tall, 3 * imgui.GetFrameHeight());
    local left = (screen.x - wide) / 2;
    if reaches(area, left, 6, wide, tall) then
        at[1], at[2] = screen.x / 2, screen.y - 6;
        bar.covered = reaches(area, left, screen.y - 6 - tall, wide, tall) and true or false;
        bar.top = screen.y - 6 - tall;
        return BOTTOM;
    end
    at[1], at[2], bar.covered = screen.x / 2, 6, false;
    return TOP;
end

-- Whether the bar is where the open settings window reaches it, so the window stays behind the bar when clicked.
function edit.covered() return active and bar.covered == true; end

-- The top of the bar while it covers the settings window's foot, so the window's page can end above it.
function edit.covered_top() return active and bar.covered == true and bar.top or nil; end

-- The settings window asks for this as it appears, which brings it in front of the bar.
function edit.bring_bar_forward() bar.forward = true; end

-- The bar: Done, Undo and Redo, the picked display, what it moves with and the way to its Size and place tab, Snap while
-- moving, and while it is on the Snapping section with the picked display's tick, the grid and the snapping switches. It doesn't take focus
-- as it opens, so the keys stay with the game until the bar or an outline is clicked. Where the settings window covers
-- both its spots it does, as that's what brings it in front of the window: as it opens, when the window comes to cover
-- them and when the window appears. That waits for the mouse button to come up, so a drag on the window goes on.
-- Returns whether it has focus.
local function draw_bar(imgui, settings, callbacks, screen)
    local e = settings.edit_mode;
    local was = bar.covered;
    imgui.SetNextWindowPos(at, ImGuiCond_Always, bar_spot(imgui, screen, callbacks.settings_area and callbacks.settings_area()));
    if not bar.covered then bar.forward = false; elseif not was then bar.forward = true; end;
    if bar.forward and imgui.SetNextWindowFocus and not imgui.IsMouseDown(ImGuiMouseButton_Left or 0) then imgui.SetNextWindowFocus(); bar.forward = false; end;
    local flags = bit.bor(ImGuiWindowFlags_NoSavedSettings or 0, ImGuiWindowFlags_NoCollapse or 0, ImGuiWindowFlags_NoMove or 0,
        ImGuiWindowFlags_NoResize or 0, ImGuiWindowFlags_AlwaysAutoResize or 0, ImGuiWindowFlags_NoFocusOnAppearing or 0,
        ImGuiWindowFlags_NoDocking or 0);
    local focused = false;
    if imgui.Begin('Arrange on screen##vantage_edit_bar', true, flags) then
        typing_in, active_box = active_box, nil;
        focused = imgui.IsWindowFocused and imgui.IsWindowFocused(ImGuiFocusedFlags_RootAndChildWindows or 0) or false;
        local wx, wy = imgui.GetWindowPos();
        local ww, wh = imgui.GetWindowSize();
        bar.x, bar.y, bar.width, bar.height = wx, wy, ww, wh;
        bar.wide, bar.tall, bar.left = math.max(bar.wide, ww), math.max(bar.tall, wh), imgui.GetCursorPosX();
        if imgui.Button('Done##edit_done') then edit.stop(); end
        if imgui.IsItemHovered() then imgui.SetTooltip('Ends Arrange on screen. Every display stays where it is.'); end
        -- Greyed with no step to take, as the settings window's are.
        local history = callbacks.history_status and callbacks.history_status();
        local undo_steps, redo_steps = history and history.undo or 0, history and history.redo or 0;
        imgui.SameLine();
        if imgui.BeginDisabled then imgui.BeginDisabled(undo_steps == 0); end
        if imgui.Button('Undo##edit_undo') and callbacks.undo then callbacks.undo(); end
        if imgui.EndDisabled then imgui.EndDisabled(); end
        imgui.SameLine();
        if imgui.BeginDisabled then imgui.BeginDisabled(redo_steps == 0); end
        if imgui.Button('Redo##edit_redo') and callbacks.redo then callbacks.redo(); end
        if imgui.EndDisabled then imgui.EndDisabled(); end
        local shown = selected and elements.by_id[selected] and elements.on(settings, selected) and elements.drawn(selected);
        imgui.SameLine();
        imgui.TextUnformatted('Display');
        imgui.SameLine();
        local picked = selected and elements.label(selected) or 'Pick a display';
        imgui.SetNextItemWidth(math.max(220, imgui.CalcTextSize(picked) + imgui.GetFrameHeight() + 16));
        listed, listing = listing, imgui.BeginCombo('##edit_pick', picked) == true;
        if listing then
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
            local moves = 'Moves with: ' .. elements.moves_with(settings, id);
            beside(imgui, screen, (imgui.CalcTextSize(moves)));
            imgui.TextUnformatted(moves);
            beside(imgui, screen, imgui.CalcTextSize('Size and place') + imgui.GetFrameHeight());
            if imgui.Button('Size and place##edit_place') and callbacks.open_page then place_settings(element, callbacks, settings); end
            if imgui.IsItemHovered() then imgui.SetTooltip('Opens its Size and place tab, to type its spot or pick what it moves with.'); end
            -- These lines wrap where the screen ends, like the help line.
            if not conditions.shown(element.strip and 'party_ui' or id) then
                imgui.PushTextWrapPos(screen.x - 12 - imgui.GetCursorPosX());
                imgui.TextUnformatted('Its When to show rules hide it right now. Arrange on screen shows it anyway.');
                imgui.PopTextWrapPos();
            end
        elseif selected then
            imgui.PushTextWrapPos(screen.x - 12 - imgui.GetCursorPosX());
            imgui.TextUnformatted(elements.label(selected) .. ' is not on the screen now.');
            imgui.PopTextWrapPos();
        end
        -- The same tick as the main page's.
        local switched, snapping = check(imgui, 'Snap while moving##edit_grid_mode', e.grid_mode, SNAP_HELP);
        if switched then
            begin_step(callbacks, 'Snap while moving');
            snap.switch(settings, snapping);
            if callbacks.changed then callbacks.changed('after'); end
            if callbacks.save then callbacks.save(); end
        end
        if e.grid_mode and imgui.CollapsingHeader('Snapping##edit_snapping') then
            if shown then
                local ticked_now, ticked = check(imgui, 'This display snaps##edit_grid_tick', snap.ticked(settings, selected),
                    'Whether the display picked snaps while you move it.');
                if ticked_now then
                    begin_step(callbacks, (ticked and 'Snap ' or 'Stop snapping ') .. elements.label(selected));
                    snap.tick(settings, selected, ticked);
                    if callbacks.changed then callbacks.changed('after'); end
                    if callbacks.save then callbacks.save(); end
                end
                imgui.SameLine();
            end
            local grid_shown, show_grid = check(imgui, 'Show the grid##edit_show_grid', e.show_grid);
            if grid_shown then
                begin_step(callbacks, 'Show the grid');
                e.show_grid = show_grid;
                if callbacks.changed then callbacks.changed('after'); end
                if callbacks.save then callbacks.save(); end
            end
            imgui.SameLine();
            imgui.TextUnformatted('Grid');
            imgui.SameLine();
            grid_value[1] = e.grid;
            imgui.SetNextItemWidth(number_width(imgui));
            local takes, typed = box(imgui, '##edit_grid', grid_value, 1, 8);
            if takes then
                local value = floor(clamp(tonumber(grid_value[1]) or e.grid, 4, 256));
                if value ~= e.grid then
                    begin_step(callbacks, 'Grid size');
                    e.grid = value;
                    if callbacks.changed then callbacks.changed('after'); end
                    if typed and callbacks.save then callbacks.save(); end
                end
            end
            imgui.TextUnformatted('Line up with');
            for _, entry in ipairs(SWITCHES) do
                beside(imgui, screen, imgui.CalcTextSize(entry[1]) + imgui.GetFrameHeight() + 8);
                local changed, value = check(imgui, entry[1] .. '##edit_' .. entry[2], e[entry[2]]);
                if changed then
                    begin_step(callbacks, entry[3]);
                    e[entry[2]] = value;
                    if callbacks.changed then callbacks.changed('after'); end
                    if callbacks.save then callbacks.save(); end
                end
            end
            -- How close a display, or the edge pulled, comes to a line to snap to it, as the Grid box takes its number.
            imgui.TextUnformatted('Snap distance');
            imgui.SameLine();
            distance_value[1] = e.snap_distance;
            imgui.SetNextItemWidth(number_width(imgui));
            local near, typed_near = box(imgui, '##edit_snap_distance', distance_value, 1, 4);
            if near then
                local value = floor(clamp(tonumber(distance_value[1]) or e.snap_distance, 1, 32));
                if value ~= e.snap_distance then
                    begin_step(callbacks, 'Snap distance');
                    e.snap_distance = value;
                    if callbacks.changed then callbacks.changed('after'); end
                    if typed_near and callbacks.save then callbacks.save(); end
                end
            end
        end
        -- The help line wraps where the screen ends, at a big text size.
        imgui.PushTextWrapPos(screen.x - 12 - imgui.GetCursorPosX());
        imgui.TextUnformatted(HELP);
        if message and steady() - message_at < 6 then imgui.TextUnformatted(message); end
        imgui.PopTextWrapPos();
    end
    imgui.End();
    return focused;
end

local function look_of(settings, callbacks)
    look_cache.look = theme.window(settings, callbacks.look_revision and callbacks.look_revision()
        or callbacks.settings_revision and callbacks.settings_revision());
    return look_cache.look;
end

-- Drawn after every display each frame while edit mode is on. callbacks gives shift, focused, typing, settings_blocks_input,
-- settings_area, settings_revision, look_revision, changed, save, undo, redo and open_page.
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
    local look = look_of(settings, callbacks);
    fonts.push_window(look.font, look.font_size);
    local focused = outlines(imgui, settings, callbacks, mx, my, shift, blocked, accent, screen);
    -- While a display ticked to snap is dragged, the grid and the line it snapped to, as a Shift drag shows them.
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
    if ImGuiKey_Escape and imgui.IsKeyPressed(ImGuiKey_Escape, false) then
        if not (listing or listed) then edit.stop(); end
        return;
    end
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
