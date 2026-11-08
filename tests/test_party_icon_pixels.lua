-- Party icons land on whole pixels (ui/party_hud.lua paint_cell, ui/native_party_hud.lua plan): beside the game's rows
-- with the game menu at 1.5 times, where the game's rows sit on half pixels, each inside the strip's window, and in a
-- panel of its own, where a countdown column wider than the icon by an odd number of pixels would centre the icon on
-- half a pixel.
local overlay, defaults = require('ui.native_party_hud'), require('ui.party_defaults');
local hud, layout, icons = require('ui.party_hud'), require('ui.party_layout'), require('ui.icons');
local imgui = require('imgui');
local status = icons.status;
icons.status = function(effect) return effect; end;
local function whole(value) return value == math.floor(value); end;

-- The game's party list with the menu at 1920x1080 on a 2880x1620 screen: rows 21 px tall and 30 px apart, the last at
-- y 1555.5, and the list at x 2692.5.
MOCK.screen = { 2880, 1620 };
local roster, subjects = hud.sample(6, 100);
local frame = { x = 1795 * 1.5, y = (1037 - 5 * 20) * 1.5, width = 106 * 1.5, height = 5 * 30 + 21, rows = {}, row_height = 21,
    pitch = 30, measured_by = 'rows' };
for _, member in ipairs(roster.members) do
    frame.rows[member.slot] = { x = frame.x, y = frame.y + member.slot * 30, width = frame.width, height = 21,
        slot = member.slot };
    local subject = subjects[member.id];
    subject.effects, subject.known = {}, true;
    for effect = 1, 6 do
        subject.effects[effect] = { effect = effect, name = 'Effect ' .. effect, kind = 'buff', remaining = 30, total = 60,
            status = 'estimated' };
    end;
end;
local geometry = { available = true, groups = { frame } };
assert(not whole(frame.x) and not whole(frame.y), 'Fixture: the game\'s rows are on half pixels.');
local p = defaults.make();
p.enabled, p.effects.icon_size = true, 37;
-- ImGui drops the fractions of a window's place and size and clips what it draws to that, so every icon must lie
-- inside the strip's window taken that way, or its last row or column of pixels is cut off.
local function inside_window()
    local count, left, top, right, bottom = 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'SetNextWindowPos' then
            left, top = math.floor(call[2][1]), math.floor(call[2][2]);
        elseif call[1] == 'SetNextWindowSize' then
            right, bottom = left + math.floor(call[2][1]), top + math.floor(call[2][2]);
        elseif call[1] == 'draw:AddImage' then
            local drawn = MOCK.drawn[call];
            local first, last = drawn[3], drawn[4];
            assert(first[1] >= left and first[2] >= top and last[1] <= right and last[2] <= bottom,
                'Every icon is inside the strip\'s window.');
            count = count + 1;
        end;
    end;
    return count;
end;
-- The icons fill the whole 30 px step and the rows touch.
local size = 30;
local plan = overlay.plan(roster, subjects, p, geometry, 2880, 1620)[1];
for index, item in ipairs(plan.rows) do
    assert(whole(item.area.x) and whole(item.area.y) and item.options.icon_size == size,
        'Each row\'s strip starts on a whole pixel.');
    local above = plan.rows[index - 1];
    if above then
        assert(item.area.y == above.area.y + above.area.height, 'Touching rows still touch on whole pixels.');
    end;
end;
MOCK.imgui_calls = {};
overlay.draw(roster, subjects, p, 100, { native_geometry = geometry });
local count = 0;
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'draw:AddImage' then
        local drawn = MOCK.drawn[call];
        local first, last = drawn[3], drawn[4];
        assert(whole(first[1]) and whole(first[2]) and whole(last[1]) and whole(last[2]) and last[1] - first[1] == size
            and last[2] - first[2] == size, 'Every icon corner is a whole pixel.');
        count = count + 1;
    end;
end;
assert(count == 36 and inside_window() == 36, 'Fixture: six icons for each of six members.');
overlay.cancel_layout_gesture();

-- A panel of its own with countdowns under the icons: some countdown columns are wider than the icon by an odd number
-- of pixels, and each icon still goes on whole pixels, within half a pixel of its column's centre.
imgui.CalcTextSize = function(text) return #text * imgui.GetFontSize() / 2, imgui.GetFontSize(); end;
local effects = {
    { effect = 40, name = 'Protect', kind = 'buff', remaining = 16800, present = true },
    { effect = 41, name = 'Shell', kind = 'buff', remaining = 60, present = true },
    { effect = 43, name = 'Long duration', kind = 'buff', remaining = 360000, present = true },
};
local images;
local list = {
    PushClipRect = function() end, PopClipRect = function() end,
    AddImage = function(_, _, first, last) images[#images + 1] = { first[1], first[2], last[1], last[2] }; end,
    AddText = function() end, AddRectFilled = function() end,
};
local odd = 0;
for _, font in ipairs({ 'Original FFXI', 'XI View' }) do
    for _, size in ipairs({ 16, 17, 24, 32 }) do
        local options = { timers = true, fit_all = true, wrap_text = true,
            icon_size = size, countdown_font = font, icon_countdown_size = 0, icon_countdown_gap = 0,
            icon_countdown_position = 'below', growth = 'right', font_size = 16, blink_icons = false };
        local area = { x = 100, y = 200, width = 400, height = 400 };
        local cells = layout.effect_cells(effects, options, area);
        local look = require('ui.party_theme').resolve(defaults.make());
        look.font = font;
        images = {};
        hud.paint_effects(list, look, { effects = effects }, options, area, -1, -1, {}, 100);
        assert(#images == #effects, 'Fixture: every icon draws.');
        for index, image in ipairs(images) do
            local cell = cells[index];
            if (cell.icon_column_width - size) % 2 == 1 then odd = odd + 1; end;
            assert(whole(image[1]) and whole(image[2]) and whole(image[3]) and whole(image[4]),
                'A panel icon lands on whole pixels: ' .. font .. ' at ' .. size);
            assert(math.abs(image[1] + size / 2 - (cell.x + cell.icon_column_width / 2)) <= 0.5, 'Centred to the nearest pixel.');
        end;
    end;
end;
assert(odd > 0, 'Fixture: a countdown column wider than its icon by an odd number of pixels.');

-- With no art from the client, a cell leaves nothing in its place: no tile, no edge and no number.
icons.status = function() end;
local marks = 0;
local function mark() marks = marks + 1; end;
local bare = { PushClipRect = function() end, PopClipRect = function() end, AddImage = mark, AddRect = mark, AddRectFilled = mark,
    AddText = mark };
hud.paint_effects(bare, require('ui.party_theme').resolve(defaults.make()), { effects = effects },
    { timers = false, fit_all = true, icon_size = 16, growth = 'right', font_size = 16, blink_icons = false },
    { x = 100, y = 200, width = 400, height = 400 }, -1, -1, {}, 100);
assert(marks == 0, 'A cell with no art draws nothing: ' .. marks);
icons.status = status;
return 'Party icons land on whole pixels beside scaled game rows and in panels with odd countdown columns';
