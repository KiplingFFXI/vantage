-- Simulated native anchors, where the game's party windows sit; the real ImGui renderer and mouse input are exercised.
local frames = require('ui.party_hud');
local overlay = require('ui.native_party_hud');
local config = PREVIEW.settings.party_ui;
config.locked = false;
config.enabled = true;
config.style.icon_art, config.effects.max, config.native.width = 'XI View', 32, 420;
config.effects.icon_size = 18;
local roster, subjects = frames.sample(18, 100);
-- The game's three party windows at x 900, each row 32 px.
local geometry = { available = true, groups = {} };
for _, top in ipairs({ { 1, 40, 198, 44 }, { 2, 260, 203, 269 }, { 3, 480, 203, 489 } }) do
    local bounds = { x = 900, y = top[2], width = 116, height = top[3], rows = {} };
    for _, member in ipairs(roster.members) do
        if member.group == top[1] then
            bounds.rows[member.slot] = { x = 902, y = top[4] + member.slot % 6 * 32, width = 112, height = 32, slot = member.slot };
        end;
    end;
    geometry.groups[top[1]] = bounds;
end;
require('ui.icons').prepare();
PREVIEW.native_saves, PREVIEW.native_targets, PREVIEW.native_roster = 0, 0, roster;
return function()
    overlay.draw(roster, subjects, config, 100, {
        native_geometry = geometry, shift = MOCK.key_shift == true,
        changed = function() PREVIEW.native_saves = PREVIEW.native_saves + 1; end,
        target = function() PREVIEW.native_targets = PREVIEW.native_targets + 1; end,
    });
end;
