-- Real ImGui input against simulated native anchors; no game windows are changed.
local frames = require('ui.party_hud');
local overlay = require('ui.native_party_hud');
local config = PREVIEW.settings.party_ui;
config.locked = false;
config.enabled = true;
config.effects.max, config.native.width = 32, 420;
local roster, subjects = frames.sample(18, 100);
-- The game's three party windows at x 1000, each row 32 px.
local geometry = { available = true, groups = {} };
for _, top in ipairs({ { 1, 60, 204, 70 }, { 2, 300, 203, 309 }, { 3, 540, 203, 549 } }) do
    local bounds = { x = 1000, y = top[2], width = 116, height = top[3], rows = {} };
    for _, member in ipairs(roster.members) do
        if member.group == top[1] then
            bounds.rows[member.slot] = { x = 1002, y = top[4] + member.slot % 6 * 32, width = 112, height = 32, slot = member.slot };
        end;
    end;
    geometry.groups[top[1]] = bounds;
end;
PREVIEW.native_saves, PREVIEW.native_starts, PREVIEW.native_targets = 0, 0, 0;
PREVIEW.native_plan = function() return overlay.plan(roster, subjects, config, geometry, 1920, 1080)[1]; end;
return function()
    overlay.draw(roster, subjects, config, 100, {
        native_geometry = geometry, shift = MOCK.key_shift == true,
        begin_edit = function() PREVIEW.native_starts = PREVIEW.native_starts + 1; end,
        changed = function() PREVIEW.native_saves = PREVIEW.native_saves + 1; end,
        target = function() PREVIEW.native_targets = PREVIEW.native_targets + 1; end,
    });
end;
