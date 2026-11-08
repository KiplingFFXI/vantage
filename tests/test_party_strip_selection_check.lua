-- The strips check the effect selection settings once a draw for all of its rows, not once a row: a frame of an 18
-- member alliance where nothing changed makes one check. A setting changed in place is still seen at the next draw.
local render_cache = require('ui.render_cache');
local revisions, checks = render_cache.revisions, 0;
render_cache.revisions = function(...)
    local revision = revisions(...);
    return function(...) checks = checks + 1; return revision(...); end;
end;
local layout = require('ui.party_layout');
render_cache.revisions = revisions;
local imgui = require('imgui');
local overlay, hud = require('ui.native_party_hud'), require('ui.party_hud');
assert(require('ui.party_layout') == layout, 'Fixture: the strips use the counted layout.');
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
local callbacks = { native_geometry = geometry };
local function draw()
    checks, MOCK.imgui_calls = 0, {};
    overlay.draw(roster, subjects, p, 100, callbacks);
    return checks;
end;

draw();
local rows = 0;
for _, plan in ipairs(overlay._kept.plans) do rows = rows + #plan.rows; end;
assert(#overlay._kept.plans == 3 and rows == 18, 'Fixture: three strips of six rows.');
assert(draw() == 1, 'A frame where nothing changed checks the selection settings once: ' .. checks);
-- Excluded in place, as the settings edit the list: the next draw drops it from every row.
local first = subjects[roster.members[1].id].effects[1].effect;
p.effects.exclude[first] = true;
draw();
for _, plan in ipairs(overlay._kept.plans) do
    for _, item in ipairs(plan.rows) do
        for _, effect in ipairs(item.effects) do assert(effect.effect ~= first, 'The excluded effect is gone from every row.'); end;
    end;
end;
p.effects.exclude[first] = nil;
return 'The strips check their selection settings once a draw';
