-- Party list's look on parchment (the Original FFXI skin on Window Type 7) in a game font is kept for a
-- settings revision while the answer to whether that font is there stays the same. It is made again when that answer
-- changes, with light text once the font is there. So the strips make nothing a frame on parchment either, measured as
-- test_party_strip_allocation.lua does.
local bit = require('bit');
local imgui = require('imgui');
local theme = require('ui.party_theme');
local fonts = require('ui.fonts');
local failed = fonts.failed;
local config = require('ui.party_defaults').make();

for _, font in ipairs({ 'Original FFXI', 'XI View' }) do
    local style = { theme = 'Original FFXI', window_type = 7, font = font, font_size = 14 };
    fonts.failed = function() return true; end;
    local waiting = theme.party(config, style, 1);
    assert(waiting.colors.text[1] < 0.15, 'Dark text until the game font is there.');
    assert(theme.party(config, style, 1) == waiting, 'The look is kept while the ' .. font .. ' font is still not there.');
    fonts.failed = function() return false; end;
    local ready = theme.party(config, style, 1);
    assert(ready ~= waiting and ready.colors.text[1] == 1, 'A new look with light text on the next frame the font is there.');
    assert(theme.party(config, style, 1) == ready, 'That look is kept too.');
    fonts.failed = function() return true; end;
    assert(theme.party(config, style, 1).colors.text[1] < 0.15, 'Dark text again if the font goes.');
end
fonts.failed = failed;
-- A look off parchment never asks.
local asked = 0;
fonts.failed = function() asked = asked + 1; return false; end;
local plain = { theme = 'Original FFXI', window_type = 1, font = 'Original FFXI', font_size = 14 };
local kept = theme.party(config, plain, 1);
asked = 0;
assert(theme.party(config, plain, 1) == kept and asked == 0, 'A look off parchment is kept without asking about the font.');
fonts.failed = failed;

local alloc = require('alloc_fixture');

-- The look alone, asked each frame with the game's own answer.
local parchment = { theme = 'Original FFXI', window_type = 7, font = 'Original FFXI', font_size = 14 };
local each = alloc.measure(function(count) for _ = 1, count do theme.party(config, parchment, 2); end end, 600);
assert(each < 0.002, ('The parchment look makes %.4f KB each time it is asked; nothing expected'):format(each));

-- The strips on parchment.
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
local hud, native, metrics = require('ui.party_hud'), require('ui.native_party_hud'), require('ui.text_metrics');
local p = require('ui.party_defaults').make();
p.enabled, p.locked, p.show_solo, p.effects.timers = true, true, true, true;
local roster, subjects = hud.sample(6, 100);
local geometry = { available = true, groups = { [1] = { x = 1800, y = 100, width = 116, height = 240, rows = {} } } };
for _, member in ipairs(roster.members) do
    geometry.groups[1].rows[member.slot] = { x = 1800, y = 100 + member.slot * 40, width = 116, height = 40, slot = member.slot };
end
local callbacks = { native_geometry = geometry, revision = 1, global_style = parchment };
local now = 100.3;
local function frames(count)
    for _ = 1, count do
        now = now + 1 / 12000;
        if now >= 100.9 then now = 100.3; end
        metrics.begin_frame();
        native.draw(roster, subjects, p, now, callbacks);
        metrics.end_frame();
    end
end
frames(600);
each = alloc.measure(frames, 600);
assert(each < 0.002, ('The strips on parchment make %.4f KB a frame; nothing expected'):format(each));
return 'The parchment party look is kept while its font stays the same';
