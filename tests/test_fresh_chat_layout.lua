-- Fresh layouts keep clear of the game's chat log. The chat log is the client's chat window when Vantage can read
-- it, otherwise where it usually sits, at the bottom left, scaled to the screen. A fresh install's first frame
-- places the timer panels and the alert notices where they keep clear of the chat log, the game's own party list and
-- target window, and each other; Apply size and Apply setup place them again while they are still there. Saved
-- layouts are never moved.
local layout = require('ui.layout');
local defaults, presets, setup = require('ui.defaults'), require('setup_fixture'), require('ui.setup_defaults');
local hud = require('ui.hud');

local function overlap(a, b)
    return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height;
end;

-- The usual spot: Chat 1 at L 16, T 821, R 1086, B 1044 on a 1920 x 1080 screen, scaled.
local usual = layout.chat_area(1920, 1080);
assert(usual.x == 16 and usual.y == 821 and usual.width == 1070 and usual.height == 223 and usual.usual,
    'Without the client chat window, the chat log is at its usual spot.');
local small = layout.chat_area(1280, 720);
assert(math.abs(small.x - 16 * 2 / 3) < 0.01 and math.abs(small.y - 821 * 2 / 3) < 0.01
    and math.abs(small.width - 1070 * 2 / 3) < 0.01 and math.abs(small.height - 223 * 2 / 3) < 0.01,
    'It scales with the screen.');
local tall = layout.chat_area(1920, 1200);
assert(tall.x == 16 and math.abs(tall.y - 821 * 1200 / 1080) < 0.01 and tall.width == 1070
    and math.abs(tall.height - 223 * 1200 / 1080) < 0.01, 'Across and down it scales with each side of the screen.');
local read = { x = 600, y = 500, width = 400, height = 200, windows = {} };
assert(layout.chat_area(1920, 1080, read) == read, 'The client chat window is used when it can be read.');
assert(layout.chat_area(1920, 1080, { x = 0, y = 0, width = 0, height = 0 }).usual, 'An empty one is not a chat log.');
assert(layout.chat_area(0, 0) == nil, 'Without a screen there is no chat log.');

-- A fresh install's first frame: the notices and the timer panels keep clear of the timer row, the chat log, the
-- game's own party list and target window (the bottom right corner) and each other.
local function placed(width, height, chat)
    local s = defaults.make();
    setup.place_fresh(s, { width = width, height = height, chat = chat });
    return s;
end;
-- A panel with room for one more row, as it fills.
local function two_rows(p, s, width, height)
    local per_row = hud.bounds(p, s.style, 1000, width, height).columns;
    return hud.bounds(p, s.style, per_row + 1, width, height).height;
end;
local function notice_box(s, width)
    local box_width = math.min(s.alerts.notice_width, width);
    return { x = math.max(0, math.min(s.alerts.notice_x, width - box_width)), y = s.alerts.notice_y,
        width = box_width, height = (2 * s.alerts.max_notices + 1) * (s.style.font_size + 3) };
end;
local function shown_panels(s, width, height)
    local out = {};
    for _, id in ipairs(defaults.panel_order) do
        if defaults.panel_enabled(s, id) then
            local p = s.panels[id];
            out[#out + 1] = { id = id, x = p.x, y = p.y, width = p.width, height = hud.bounds(p, s.style, 1, width, height).height };
        end;
    end;
    return out;
end;
local spots = {};
for _, screen in ipairs({ { 1920, 1080 }, { 1600, 900 }, { 1440, 900 }, { 1366, 768 }, { 1280, 720 } }) do
    local width, height = screen[1], screen[2];
    local chat, corner = layout.chat_area(width, height), layout.native_corner(width, height);
    local s = placed(width, height);
    spots[width] = { s.alerts.notice_x, s.alerts.notice_y };
    local notices = notice_box(s, width);
    local label = width .. ' x ' .. height;
    assert(not overlap(notices, chat) and not overlap(notices, corner),
        'Up to ' .. s.alerts.max_notices .. ' notices keep clear of the chat log and the game\'s windows on a ' .. label .. ' screen.');
    for _, panel in ipairs(shown_panels(s, width, height)) do
        assert(not overlap(panel, notices), panel.id .. ' keeps clear of the notices on a ' .. label .. ' screen.');
        assert(not overlap(panel, chat) and not overlap(panel, corner), panel.id .. ' keeps clear of the chat log and the game\'s windows on a '
            .. label .. ' screen.');
        -- The notices leave a panel above them room to fill a row more (Self buffs with 10 or more buffs).
        local filled = { x = panel.x, y = panel.y, width = panel.width, height = two_rows(s.panels[panel.id], s, width, height) };
        assert(not overlap(filled, notices), panel.id .. ' filling a row more stays clear of the notices on a ' .. label .. ' screen.');
    end;
end;
assert(spots[1920][1] == 985 and spots[1920][2] == 10, 'On 1920 x 1080 the fresh notice spot stays.');
-- The client's own chat window is used when it can be read: moved to the top right, the displays keep clear of it.
local read_chat = { x = 700, y = 0, width = 580, height = 100 };
local moved_chat = placed(1280, 720, { x = 700, y = 0, width = 580, height = 100, windows = {} });
assert(not overlap(notice_box(moved_chat, 1280), read_chat), 'The notices keep clear of it there.');
for _, panel in ipairs(shown_panels(moved_chat, 1280, 720)) do
    assert(not overlap(panel, read_chat), panel.id .. ' keeps clear of a chat log read from the client.');
end;
-- Only the starting spots move: notices or a panel already elsewhere stay.
local kept = defaults.make();
kept.alerts.notice_x, kept.alerts.notice_y, kept.panels.self_buffs.x, kept.panels.self_buffs.y = 300, 300, 600, 600;
setup.place_fresh(kept, { width = 1280, height = 720 });
assert(kept.alerts.notice_x == 300 and kept.alerts.notice_y == 300 and kept.panels.self_buffs.x == 600
    and kept.panels.self_buffs.y == 600, 'What is not at its start stays.');

-- Apply size places the panels again while they are still where the fresh choice put them, keeping clear of the
-- chat log at the new size; a panel the player moved stays.
local function applied(s, size, width, height)
    assert(presets.apply(s, { size = size, skin = 'keep', matching = false, window_type = 1,
        screen_width = width, screen_height = height }));
    return s;
end;
for _, size in ipairs({ 'minimal', 'minimal_1_5x' }) do
    local s = applied(placed(1600, 900), size, 1600, 900);
    for _, panel in ipairs(shown_panels(s, 1600, 900)) do
        assert(not overlap(panel, layout.chat_area(1600, 900)), size .. ' keeps ' .. panel.id .. ' clear of the chat log.');
    end;
end;
local player = placed(1600, 900);
player.panels.self_buffs.x, player.panels.self_buffs.y = 500, 600;
applied(player, 'minimal_2x', 1600, 900);
assert(player.panels.self_buffs.x == 500 and player.panels.self_buffs.y == 600, 'A panel the player moved stays where it was put.');

-- At 1.5x and 2x on 1920 x 1080 the notices, the panels and the chat log keep clear of each other.
local function scaled_notices(s, width)
    local k = s.style.scale;
    local box_width = math.min(s.alerts.notice_width * k, width);
    return { x = math.max(0, math.min(s.alerts.notice_x, width - box_width)), y = s.alerts.notice_y,
        width = box_width, height = (2 * s.alerts.max_notices + 1) * (s.style.font_size + 3) * k };
end;
for _, size in ipairs({ 'minimal_1_5x', 'minimal_2x' }) do
    local s = placed(1920, 1080);
    applied(s, size, 1920, 1080);
    local notices, chat = scaled_notices(s, 1920), layout.chat_area(1920, 1080);
    assert(not overlap(notices, chat), size .. ' on 1920 x 1080: the notices and the chat log keep clear of each other.');
    local panels = shown_panels(s, 1920, 1080);
    for index, panel in ipairs(panels) do
        assert(not overlap(panel, notices) and not overlap(panel, chat),
            size .. ' on 1920 x 1080: ' .. panel.id .. ' keeps clear of the notices and the chat log.');
        for other = index + 1, #panels do
            assert(not overlap(panel, panels[other]), size .. ' on 1920 x 1080: ' .. panel.id .. ' keeps clear of ' .. panels[other].id .. '.');
        end;
    end;
end;

-- Panels the first frame moved are placed again by an apply, as where a fresh install put them: the same spots as an
-- apply to an install whose first frame moved nothing.
for _, size in ipairs({ 'minimal' }) do
    local first = placed(1280, 720);
    local untouched = defaults.make();
    applied(first, size, 1280, 720);
    applied(untouched, size, 1280, 720);
    for _, id in ipairs(defaults.panel_order) do
        assert(first.panels[id].x == untouched.panels[id].x and first.panels[id].y == untouched.panels[id].y,
            size .. ': ' .. id .. ', moved by the first frame, is placed again by an apply.');
    end;
    assert(first.alerts.notice_x == untouched.alerts.notice_x and first.alerts.notice_y == untouched.alerts.notice_y,
        size .. ': so are the notices.');
end;

-- With every timer panel on, the ones that flow past the first row keep clear of the chat log and the game's windows
-- too.
for _, screen in ipairs({ { 1600, 900 }, { 1366, 768 }, { 1280, 720 } }) do
    local width, height = screen[1], screen[2];
    for _, size in ipairs({ 'minimal', 'minimal_1_5x' }) do
        local s = placed(width, height);
        for _, id in ipairs(defaults.panel_order) do s.panels[id].enabled = true; end;
        applied(s, size, width, height);
        for _, panel in ipairs(shown_panels(s, width, height)) do
            assert(not overlap(panel, layout.chat_area(width, height)) and not overlap(panel, layout.native_corner(width, height)),
                size .. ' on ' .. width .. ' x ' .. height .. ': ' .. panel.id .. ' keeps clear of the chat log and the game\'s windows.');
        end;
    end;
end;

-- Every timer panel turned on after the first frame the way Home does it (only enabled changes), with the party list
-- strips on. Each panel that was off has its own spot from the first frame where the screen has room: one whose
-- row has none from where it starts looks again from the top of the first row. 1280 x 720 and 1366 x 768 have no
-- room for every panel: the ones left keep their fresh spots, and the rest keep clear. Party timers, the first of
-- the second row, has a spot clear of the chat log, the notices and the game's windows on each of them.
for _, screen in ipairs({ { 1920, 1080 }, { 1600, 900 }, { 1440, 900 }, { 1366, 768 }, { 1280, 720 } }) do
    local width, height = screen[1], screen[2];
    local label = width .. ' x ' .. height;
    local s, start = placed(width, height), defaults.make().panels;
    s.party_ui.enabled = true;
    local fixed = { notice_box(s, width), layout.chat_area(width, height), layout.native_corner(width, height) };
    local own, kept = {}, {};
    -- The combined recast panel doesn't show while the recast panels are separate.
    for _, id in ipairs(defaults.panel_order) do
        local p = s.panels[id];
        if id ~= 'recasts' then
            local was_off = not defaults.panel_enabled(s, id);
            p.enabled = true;
            -- Without the party frames the start can be a panel's own spot on a screen with room for every panel.
            if was_off and p.x == start[id].x and p.y == start[id].y and width < 1440 then kept[#kept + 1] = id;
            else
                own[#own + 1] = { id = id, x = p.x, y = p.y, width = p.width,
                    height = hud.bounds(p, s.style, 1, width, height).height };
            end;
        end;
    end;
    for index, panel in ipairs(own) do
        for _, other in ipairs(fixed) do
            assert(not overlap(panel, other), panel.id .. ' turned on keeps clear of the notices, the chat log and '
                .. 'the game\'s windows on a ' .. label .. ' screen.');
        end;
        for next_index = index + 1, #own do
            assert(not overlap(panel, own[next_index]), panel.id .. ' and ' .. own[next_index].id .. ' turned on keep apart on a '
                .. label .. ' screen.');
        end;
    end;
    if width >= 1440 then assert(#kept == 0, 'On a ' .. label .. ' screen every panel has a spot of its own.'); end;
    if width <= 1366 then
        local p = s.panels.party;
        local party_timers = { x = p.x, y = p.y, width = p.width, height = hud.bounds(p, s.style, 1, width, height).height };
        for _, other in ipairs(fixed) do
            assert(not overlap(party_timers, other), 'On a ' .. label .. ' screen Party timers finds a spot clear of the rest.');
        end;
    end;
end;

return 'Fresh layouts keep clear of the chat log; saved ones stay';
