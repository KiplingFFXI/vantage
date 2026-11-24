-- A display that draws in the shared box (ui/element_box.lua) keeps no old settings table once it stops drawing. The
-- Phantom Roll display and the party cooldown list draw with one settings table, then the settings are swapped, as a
-- profile switch, Undo or an import does, for one with the display off. The old table must then go with the next collect.
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);
local defaults, resize, elements = require('ui.defaults'), require('ui.resize'), require('ui.elements');
local moving = { shift = false, chat_open = false, over_settings = false, mx = -1, my = -1, down = false,
    screen_width = 1600, screen_height = 900, hover = false, editing = false };
local callbacks = {};

local function make(on)
    local s = defaults.tidy(defaults.make());
    for _, p in pairs(s.panels) do p.enabled = false; end
    s.rolls.enabled, s.rolls.preview = on, on;
    s.party_cooldowns.enabled, s.party_cooldowns.preview = true, true;
    s.party_cooldowns.list.enabled = on;
    return s;
end

for _, case in ipairs({ { 'Phantom Roll display', require('ui.roll_display') }, { 'party cooldown list', require('ui.cooldown_list') } }) do
    local name, display = case[1], case[2];
    local probe = setmetatable({}, { __mode = 'v' });
    local old = make(true);
    probe[1] = old;
    for i = 1, 3 do resize.frame(); elements.frame(); display.draw({}, old, 100 + i, callbacks, moving); end
    old = nil;
    local new = make(false);
    for i = 1, 3 do resize.frame(); elements.frame(); display.draw({}, new, 200 + i, callbacks, moving); end
    collectgarbage('collect');
    collectgarbage('collect');
    assert(probe[1] == nil, 'The ' .. name .. ' keeps no old settings table once it stops drawing.');
end
