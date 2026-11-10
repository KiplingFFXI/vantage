-- The strips beside the game's party list make nothing per frame once running, while no countdown's text changes: six
-- members with countdowns, each strip's window and paint, and the samples, which are made once and run on from frame to
-- frame as new ones would. Measured as test_hud_draw_allocation.lua does, with the collector stopped and the compiler
-- off, on an ImGui whose calls keep nothing, time moving within one second. A table made ten times a second shows.
local bit = require('bit');
local imgui = require('imgui');
local function nothing() end
local function yes() return true; end
local function no() return false; end
local io = { DisplaySize = { x = 2400, y = 1600 } };
local list = { AddImage = nothing, AddRect = nothing, AddRectFilled = nothing, AddText = nothing, AddLine = nothing,
    PushClipRect = nothing, PopClipRect = nothing, AddImageQuad = nothing, AddPolyline = nothing,
    GetClipRectMin = function() return 0, 0; end, GetClipRectMax = function() return 2400, 1600; end };
for name, fn in pairs({ GetWindowDrawList = function() return list; end, GetForegroundDrawList = function() return list; end,
    col32 = function(a, r, g, b) return bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r); end,
    CalcTextSize = function(text) return #tostring(text) * 7, 14; end, PushFont = nothing, PopFont = nothing, GetFont = function() return 1; end,
    PushStyleVar = nothing, PopStyleVar = nothing, SetNextWindowPos = nothing, SetNextWindowSize = nothing, Begin = yes, End = nothing,
    SetCursorPos = nothing, SetCursorScreenPos = nothing, Dummy = nothing, InvisibleButton = no, IsItemHovered = no, IsItemActive = no,
    IsItemActivated = no, IsMouseClicked = no, IsMouseDown = no, IsWindowHovered = no, GetScrollY = function() return 0; end,
    GetIO = function() return io; end, GetMousePos = function() return -1, -1; end, IsPopupOpen = no }) do rawset(imgui, name, fn); end
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);

local hud, party, native = require('ui.party_hud'), require('ui.party_defaults'), require('ui.native_party_hud');
-- A kept set of samples runs as new ones would: moved on 13.5 seconds, each countdown is where a new set has it.
local _, kept = hud.sample(18, 100);
hud.sample_time(kept, 113.5);
local _, fresh = hud.sample(18, 113.5);
for id, subject in pairs(fresh) do
    for index, effect in ipairs(subject.effects) do
        assert(kept[id].effects[index].remaining == effect.remaining, 'A kept sample runs on as a new one would: ' .. effect.key);
    end
end

local p = party.make();
p.enabled, p.locked, p.show_solo, p.effects.timers = true, true, true, true;
local roster, subjects = hud.sample(6, 100);
local geometry = { available = true, groups = { [1] = { x = 1800, y = 100, width = 116, height = 240, rows = {} } } };
for _, member in ipairs(roster.members) do
    geometry.groups[1].rows[member.slot] = { x = 1800, y = 100 + member.slot * 40, width = 116, height = 40, slot = member.slot };
end
-- The settings revision, as the frame passes it, keeps the strips' look from frame to frame.
local callbacks = { native_geometry = geometry, revision = 1 };
local metrics = require('ui.text_metrics');

-- Each frame moves on by step, and time starts over at 100.3 once it reaches 100.9, so no countdown's text changes.
local now, leak, made = 100.3, false, nil;
local function frames(count, step)
    for i = 1, count do
        now = now + (step or 1 / 12000);
        if now >= 100.9 then now = 100.3; end
        metrics.begin_frame();
        native.draw(roster, subjects, p, now, callbacks);
        metrics.end_frame();
        if leak and i % 6 == 0 then made = {}; end
    end
end
-- A full collection shrinks the Lua stack, and the next frames grow it back once, which is LuaJIT's and not a frame's,
-- so a few frames run after the collection, with the collector stopped, before counting starts.
local function measure(count)
    jit.off(); jit.flush();
    frames(60);
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    frames(6);
    local before = collectgarbage('count');
    frames(count);
    local each = (collectgarbage('count') - before) / count;
    collectgarbage('restart');
    jit.on();
    return each;
end
-- Warm.
frames(600);
local each = measure(600);
assert(each < 0.002, ('The strips make %.4f KB a frame; nothing expected'):format(each));
leak = true;
each = measure(600);
leak = false;
assert(each >= 0.002 and made, ('One table made ten times a second shows as %.4f KB a frame'):format(each));
-- The samples, with their outline.
p.preview = true;
frames(600);
each = measure(600);
assert(each < 0.002, ('The samples make %.4f KB a frame; nothing expected'):format(each));
-- A strip on a panel of its own, with its members' names over their rows.
p.preview = false;
local own = p.groups[1];
own.native_detached, own.detached_x, own.detached_y, own.detached_width, own.detached_height = true, 300, 200, 260, 500;
frames(600);
each = measure(600);
assert(each < 0.002, ('A strip on a panel of its own makes %.4f KB a frame; nothing expected'):format(each));
