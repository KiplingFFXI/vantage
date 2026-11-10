-- While Shift is held each display draws its resize hint with its name and size, and a locked one under the pointer
-- its lock note. None of that makes anything a frame, with an edge dragged or not, and with the space above taken by
-- another display. Measured as test_hud_draw_allocation.lua does, with the collector stopped and the compiler off, on a
-- draw list that keeps nothing. A table made every tenth frame shows.
local imgui = require('imgui');
local function nothing() end
local list = { AddRect = nothing, AddRectFilled = nothing, PushClipRect = nothing, PopClipRect = nothing, AddText = nothing,
    AddLine = nothing, AddImage = nothing };
local io = { DisplaySize = { x = 1600, y = 900 } };
rawset(imgui, 'GetIO', function() return io; end);
rawset(imgui, 'GetFont', function() return 1; end);
rawset(imgui, 'GetMousePos', function() return 400, 300; end);
rawset(imgui, 'CalcTextSize', function(text) return #tostring(text) * 8, 18; end);
rawset(imgui, 'PushFont', nothing);
rawset(imgui, 'PopFont', nothing);
local resize, metrics = require('ui.resize'), require('ui.text_metrics');
local look = require('ui.defaults').make().style;
local rect, above = { x = 300, y = 200, width = 320, height = 193 }, { x = 300, y = 120, width = 320, height = 70 };
local lines = 0;
list.AddLine = function() lines = lines + 1; end;
local leak, made = false, nil;
local function frames(count)
    for i = 1, count do
        metrics.begin_frame();
        resize.frame();
        resize.occupy('Party list buffs', above);
        resize.hint(list, rect, 0xFF80FF80, nil, 'Phantom Roll', look);
        resize.hint(list, rect, 0xFF80FF80, 'bottom_right', 'Phantom Roll', look);
        resize.hint(list, rect, 0xFF80FF80, 'left', nil, look, true);
        resize.locked(list, rect, look, 'Phantom Roll');
        metrics.end_frame();
        if leak and i % 10 == 0 then made = {}; end
    end
end
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
frames(1);
assert(lines == 3, 'Fixture: a dragged corner draws its two edges, and a dragged side its one: ' .. lines .. ' lines.');
frames(600);
local each = measure(600);
assert(each < 0.002, ('Resize hints, size labels and a lock note make %.4f KB a frame; nothing expected'):format(each));
leak = true;
each = measure(600);
leak = false;
assert(each >= 0.002 and made, ('A table made every tenth frame shows as %.4f KB'):format(each));
