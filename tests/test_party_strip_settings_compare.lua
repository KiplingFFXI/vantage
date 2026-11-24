-- The strips compare their effect settings with the ones their rows' options were made from once a draw for all of
-- their rows, not once a row: a frame of an 18 member alliance where nothing changed walks the settings once. A
-- setting changed in place is still seen at the next draw, by every row.
local imgui = require('imgui');
local overlay, hud = require('ui.native_party_hud'), require('ui.party_hud');
imgui.GetMousePos = function() return -1, -1; end;
imgui.IsMouseDown = function() return false; end;
MOCK.screen = { 1920, 1080 };

local p = require('ui.party_defaults').make();
p.enabled, p.locked = true, true;
local roster, subjects = hud.sample(18, 100);
local geometry = { available = true, groups = {} };
for group = 1, 3 do
    local frame = { x = 1700, y = 60 + (group - 1) * 300, width = 116, height = 132, rows = {} };
    for _, member in ipairs(roster.members) do
        if member.group == group then
            frame.rows[member.slot] = { x = 1700, y = frame.y + member.slot % 6 * 22, width = 116, height = 22, slot = member.slot };
        end;
    end;
    geometry.groups[group] = frame;
end;
-- The settings revision stays the same, as it does for a setting changed in place.
local callbacks = { native_geometry = geometry, revision = 1 };
-- Counts each walk over the strips' effect settings.
local walks, real_pairs = 0, pairs;
pairs = function(value) if value == p.effects then walks = walks + 1; end; return real_pairs(value); end;
local function draw()
    walks, MOCK.imgui_calls = 0, {};
    overlay.draw(roster, subjects, p, 100, callbacks);
    return walks;
end;

draw(); draw();
local rows = 0;
for _, plan in ipairs(overlay._kept.plans) do rows = rows + #plan.rows; end;
assert(#overlay._kept.plans == 3 and rows == 18, 'Fixture: three strips of six rows.');
local held = {};
for _, plan in ipairs(overlay._kept.plans) do for _, item in ipairs(plan.rows) do held[item] = item.options; end; end;
local walked = draw();
assert(walked == 1, 'A frame where nothing changed walks the effect settings once: ' .. walked);
for _, plan in ipairs(overlay._kept.plans) do
    for _, item in ipairs(plan.rows) do assert(held[item] == item.options, 'Each row keeps its options.'); end;
end;
-- Changed in place, as the settings change a value: every row's options have it at the next draw.
p.effects.blink_seconds = 20;
draw();
for _, plan in ipairs(overlay._kept.plans) do
    for _, item in ipairs(plan.rows) do
        assert(held[item] and item.options ~= held[item] and item.options.blink_seconds == 20, 'Every row sees the change.');
    end;
end;
walked = draw();
assert(walked == 1, 'and walks them once a frame again after: ' .. walked);
pairs = real_pairs;
return 'The strips compare their effect settings once a draw';
