-- The strips read the game's party windows once for each roster and screen size, not every frame. The host makes a
-- new roster at each refresh, so a new one reads them again, and so does another screen size. DisplaySize goes in as
-- whole pixels, so a screen of a fraction of a pixel still finds the windows. The game menu's size comes from the chat
-- log's last read once there is one, and is read with the windows only before it.
local native = require('core.native_party_ui');
local mem, reads = {}, 0;
local function put16(at, value) value = value % 65536; mem[at], mem[at + 1] = value % 256, math.floor(value / 256); end
local function row(group, index, x, y, w, h)
    local node, item = 0x60000 + group * 0x1000 + index * 0x40, 0x80000 + group * 0x1000 + index * 0x80;
    mem[node], mem[node + 0x10], mem[node + 0x14] = 0, item, 0;
    if index == 1 then mem[0x40000 + group * 0x100 + 0x14] = node; else mem[node - 0x40] = node; end
    put16(item, 1); put16(item + 0x3A, index);
    put16(item + 0x2A, x); put16(item + 0x2C, y); put16(item + 0x2E, w); put16(item + 0x30, h);
end
mem[0x10019], mem[0x11001], mem[0x11007] = 0x20100, 0x20200, 0x20300;
for group = 1, 3 do
    local container, ptr = 0x30000 + group * 0x100, 0x40000 + group * 0x100;
    mem[0x20000 + group * 0x100], mem[container], mem[container + 8] = container, 0x50000, ptr;
    mem[ptr + 0x0C], mem[ptr + 0x69], mem[ptr + 0x6A] = container, 1, 1;
    require('native_menu_fixture')(mem, container, ptr, group);
    for i = 1, 6 do row(group, i, 1700, 950 - (group - 1) * 140 - (6 - i) * 20, 200, 20); end
end
native._set_platform({
    valid = function(ptr, _, write) return not write and mem[ptr] ~= false; end,
    read32 = function(ptr) reads = reads + 1; return mem[ptr]; end,
    read8 = function(ptr) reads = reads + 1; return mem[ptr]; end,
    find = function(pattern, usage)
        return usage == 1 and 0 or pattern:sub(1, 2) == '6D' and 0x12000 or pattern:sub(1, 2) == '66' and 0x10000 or 0x11000;
    end,
});
require('core.chat').menu_dimensions = function() return { width = 1920, height = 1080 }; end;
local imgui = require('imgui');
imgui.GetMousePos = function() return -1, -1; end;
imgui.IsMouseDown = function() return false; end;

local overlay, hud = require('ui.native_party_hud'), require('ui.party_hud');
local p = require('ui.party_defaults').make();
p.enabled, p.locked = true, true;
local roster, subjects = hud.sample(18, 100);
local function draw(members)
    reads, MOCK.imgui_calls = 0, {};
    overlay.draw(members, subjects, p, 100, {});
    return reads, #overlay._kept.plans;
end;
local function refreshed()
    local copy = {};
    for key, value in pairs(roster) do copy[key] = value; end;
    return copy;
end;

MOCK.screen = { 1920, 1080 };
local first, strips = draw(roster);
assert(first > 0 and strips == 3, 'The first frame reads the windows and draws three strips.');
local again;
again, strips = draw(roster);
assert(again == 0 and strips == 3, 'The next frame with the same roster reads nothing and draws them still: ' .. again);
roster = refreshed();
assert(draw(roster) > 0, 'A new roster reads them again.');
MOCK.screen = { 1600, 900 };
again, strips = draw(roster);
assert(again > 0 and strips == 3, 'So does another screen size.');
MOCK.screen = { 1600.5, 900.25 };
again, strips = draw(refreshed());
assert(again > 0 and strips == 3 and native.status().geometry.available, 'A screen a fraction of a pixel wider finds them too.');
local chat, asked = require('core.chat'), 0;
local menu_size, menu_dimensions = chat.menu_size, chat.menu_dimensions;
chat.menu_size = function() return 1920, 1080; end;
chat.menu_dimensions = function() asked = asked + 1; return { width = 1920, height = 1080 }; end;
MOCK.screen = { 1920, 1080 };
again, strips = draw(refreshed());
assert(again > 0 and strips == 3 and asked == 0, 'With the chat log read, its menu size is the one used: ' .. asked);
chat.menu_size, chat.menu_dimensions = menu_size, menu_dimensions;
native._set_platform(nil);
return 'The strips read the game\'s party windows once a roster';
