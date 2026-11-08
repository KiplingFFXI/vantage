-- Drawing the panels makes nothing per frame once running: icons, bars, expanded and text panels of your buffs and
-- debuffs, the target, the party, the watch list and the recasts, Auto width, two alerts and the samples, their recasts
-- locked and combined. A bars, expanded or text row works its lines out again only when its countdown's text changes,
-- at most once a second, never each frame. Measured as test_overhead_draw_allocation.lua does, with the collector
-- stopped and the compiler off, on an ImGui whose calls keep nothing, after the stack has grown back. A table made ten
-- times a second shows.
local bit = require('bit');
local imgui = require('imgui');
local function nothing() end
local function yes() return true; end
local function no() return false; end
local io = { DisplaySize = { x = 1920, y = 1080 }, KeyShift = false };
local list = { AddImage = nothing, AddRect = nothing, AddRectFilled = nothing, AddRectFilledMultiColor = nothing, AddText = nothing,
    AddLine = nothing, PushClipRect = nothing, PopClipRect = nothing, AddImageQuad = nothing, AddPolyline = nothing };
for name, fn in pairs({ GetWindowDrawList = function() return list; end, GetForegroundDrawList = function() return list; end,
    col32 = function(a, r, g, b) return bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r); end,
    CalcTextSize = function(text) return #tostring(text) * 7, 14; end, PushFont = nothing, PopFont = nothing, GetFont = function() return 1; end,
    PushStyleVar = nothing, PopStyleVar = nothing, SetNextWindowPos = nothing, SetNextWindowSize = nothing, Begin = yes, End = nothing,
    SetCursorPos = nothing, InvisibleButton = no, IsItemHovered = no, IsItemActive = no, IsMouseClicked = no, IsMouseDown = no,
    GetIO = function() return io; end, GetMousePos = function() return -1, -1; end }) do rawset(imgui, name, fn); end
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);


local hud, defaults, fields = require('ui.hud'), require('ui.defaults'), require('ui.fields');
local s = defaults.tidy(defaults.make());
-- The samples' rows three times over, so the panels have rows to cut. Every deadline falls on a whole second.
local view = hud.sample(100);
local originals = #view.rows;
for set = 1, 2 do
    for index = 1, originals do
        local extra = defaults.copy(view.rows[index]);
        extra.key, extra.instance = 'extra_' .. set .. '_' .. index, 100 * set + index;
        view.rows[#view.rows + 1] = extra;
    end
end
local callbacks = {};
local function panels(mode, extra)
    for _, id in ipairs(defaults.panel_order) do
        local p = s.panels[id];
        p.enabled, p.mode, p.auto_width = true, mode, false;
        if extra then extra(p); end
    end
end

-- Each frame moves on by step, and time starts over at start once it reaches limit.
local now, start, limit, leak, made = 100, 100, 140, false, nil;
local function frames(count, step)
    for i = 1, count do
        now = now + step;
        if now >= limit then now = start; end
        hud.draw(view, s, now, callbacks);
        if leak and i % 6 == 0 then made = {}; end
    end
end
-- Calls n deep, so the Lua stack is grown back past what the deepest frame needs.
local function regrow(n) if n > 0 then return 1 + regrow(n - 1); end return 0; end
local function measure(count, step)
    jit.off(); jit.flush();
    frames(60, step);
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    -- The collection shrinks the Lua stack, and the next call deep enough grows it back once, which is LuaJIT's and not
    -- a frame's. So it grows back first, and the smaller of two windows counts.
    regrow(300);
    frames(60, step);
    local least = math.huge;
    for _ = 1, 2 do
        local before = collectgarbage('count');
        frames(count, step);
        least = math.min(least, (collectgarbage('count') - before) / count);
    end
    collectgarbage('restart');
    jit.on();
    return least;
end
-- Within one second of every countdown, so no text changes and nothing is worked out again.
local function still(name)
    now, start, limit = 100.3, 100.3, 100.9;
    local each = measure(600, 1 / 12000);
    assert(each < 0.002, ('%s make %.4f KB a frame; nothing expected'):format(name, each));
end

-- Icons keep each countdown's lines by its text, so once every text has been made once, ticking makes nothing.
panels('icons');
now, start, limit = 100, 100, 140;
frames(2460, 1 / 60);
local each = measure(600, 1 / 60);
assert(each < 0.002, ('Icon panels make %.4f KB a frame; nothing expected'):format(each));
leak = true;
each = measure(600, 1 / 60);
leak = false;
assert(each >= 0.002 and made, ('One table made ten times a second shows as %.4f KB a frame'):format(each));

-- By panel, then by row key and second: how many times a row's fields were worked out in that second. A row two panels
-- show, as an enemy's effect is on the Target and Watch panels, is each panel's own.
local build, built = fields.build, nil;
fields.build = function(row, panel, ...)
    if built then
        local key, rows = tostring(row.key) .. '@' .. math.floor(now), built[panel] or {};
        built[panel], rows[key] = rows, (rows[key] or 0) + 1;
    end
    return build(row, panel, ...);
end;
for _, mode in ipairs({ 'bars', 'expanded', 'text' }) do
    panels(mode);
    still(mode .. ' panels');
    -- Ten seconds ticking: each row's lines are worked out again when its text changes, once in a second at most.
    built, now, start, limit = {}, 100.5, 100.5, 140.5;
    frames(600, 1 / 60);
    local most, longest = 0, 0;
    for _, rows in pairs(built) do
        local seconds = {};
        for key, count in pairs(rows) do
            most = math.max(most, count);
            local row = key:match('^(.*)@');
            seconds[row] = (seconds[row] or 0) + 1;
            longest = math.max(longest, seconds[row]);
        end
    end
    built = nil;
    assert(longest >= 10, 'Fixture: a ' .. mode .. ' countdown ticks each second: ' .. longest);
    assert(most == 1, mode .. ' rows are worked out once a second at most, not each frame: ' .. most);
end
fields.build = build;

panels('bars', function(p) p.auto_width = true; end);
still('Auto width');
panels('icons');
view.notices = { { visual = true, ends = 1e9, message = 'Haste wears off in 10s' },
    { visual = true, ends = 1e9, estimated = true, message = 'Dia on Goblin Bandit wears off in 30s, a longer line that wraps' } };
still('Icon panels with two alerts');
view.notices = nil;
s.preview = true;
still('The icon samples');
panels('bars');
still('The bar samples');
-- The samples' recasts combined in one panel, their locks shown beside the countdowns.
local tints = s.recast_tints;
tints.mp, tints.spell_lock, tints.ability_lock = true, true, true;
s.recast_display = 'combined';
panels('bars', function(p) p.show_icon = false; end);
still('The combined recast samples with their locks');
s.preview, s.recast_display = false, 'separate';

return 'Drawing the panels makes nothing per frame';
