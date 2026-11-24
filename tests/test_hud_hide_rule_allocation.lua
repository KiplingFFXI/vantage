-- A hide rule makes the panels check every row against it each frame. A row on a unit the recipients don't list, as a
-- mob's are, is checked through one kept table, so with a rule on drawing the panels still makes nothing a frame. Measured
-- as tests/test_hud_draw_allocation.lua does.
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

local hud, defaults, effect_filters = require('ui.hud'), require('ui.defaults'), require('core.effect_filters');
local s = defaults.tidy(defaults.make());
local view = hud.sample(100);
local callbacks = {};
for _, id in ipairs(defaults.panel_order) do
    local p = s.panels[id];
    p.enabled, p.mode, p.auto_width = true, 'bars', false;
end
local enemy = 0;
for _, row in ipairs(view.rows) do if row.scope == 'enemy' then enemy = enemy + 1; end end
assert(enemy > 0, 'Fixture: the samples have rows on a mob.');

-- Within one second of every countdown, so no text changes.
local now, start, limit = 100.3, 100.3, 100.9;
local function frames(count, step)
    for _ = 1, count do
        now = now + step;
        if now >= limit then now = start; end
        hud.draw(view, s, now, callbacks);
    end
end
local function regrow(n) if n > 0 then return 1 + regrow(n - 1); end return 0; end
local function measure()
    now, start, limit = 100.3, 100.3, 100.9;
    jit.off(); jit.flush();
    frames(60, 1 / 12000);
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    regrow(300);
    frames(60, 1 / 12000);
    local least = math.huge;
    for _ = 1, 2 do
        local before = collectgarbage('count');
        frames(600, 1 / 12000);
        least = math.min(least, (collectgarbage('count') - before) / 600);
    end
    collectgarbage('restart');
    jit.on();
    return least;
end

local off = measure();
assert(off < 0.002, ('Fixture: with no rule the panels make %.4f KB a frame'):format(off));
-- Hide Haste on the party: the rule is on, and the mob's rows are checked against it too.
s.effect_filters = effect_filters.tidy({ enabled = true, rules = { { enabled = true, effect = 33, scope = 'party' } } });
local on = measure();
assert(on < 0.002, ('With a hide rule on, the panels make %.4f KB a frame (%.4f with none); nothing expected'):format(on, off));
