-- Replace the game's pet bar (core/game_pet_bar.lua) on the decoded clients, and on the new one loaded at another
-- base: both pieces are found once by core/patterns.lua, each is the code this was written for, and the party list's
-- layout calls the pet line's routine where it says. In effect, only those five bytes change, and out of effect the
-- client is byte for byte as it was. A client changed in any of those places is left alone.
local fixture = require('client_image_fixture');
local finder = require('core.patterns');
local game_pet_bar = require('core.game_pet_bar');
-- The module's own rule for a search: one match, inside the client.
local RULE = game_pet_bar._RULE;
-- Where the pet line's routine and the call to it are in both known clients, from the client's base.
local ROUTINE, SITE = 0x202960, 0x20456A;
local STAYS = ', so the game\'s pet bar stays as it is.';

local writes;
local function over(image)
    image:install();
    writes = {};
    game_pet_bar._set_platform({
        readable = function(at, size) return image:contains(at, size); end,
        find = function(name) return finder.find('game_pet_bar', name, game_pet_bar._patterns[name], RULE); end,
        bytes = function(at, size) return image:bytes(at, size); end,
        write_code = function(at, bytes) writes[#writes + 1] = at; image:write(at, bytes); return true; end,
    });
end

for _, case in ipairs({ { 'new', 0x10000000 }, { 'old', 0x10000000 }, { 'new', 0x0F300000 } }) do
    local image = fixture.load(case[1], case[2]);
    local label = ('%s at 0x%08X'):format(case[1], case[2]);
    local original = image.data;
    over(image);
    for name, pattern in pairs(game_pet_bar._patterns) do
        assert(image:find(image.base, #image.data, pattern, 0) ~= 0 and image:find(image.base, #image.data, pattern, 1) == 0,
            label .. ': ' .. name .. ' once');
    end
    assert(image:find(image.base, #image.data, game_pet_bar._patterns.pet_line, 0) == image.base + ROUTINE + 0x3D, label .. ': the pet line is where it was read.');
    assert(image:find(image.base, #image.data, game_pet_bar._patterns.layout, 0) == image.base + SITE - 0x15, label .. ': and the layout.');
    -- The client's own bytes there are a call to the pet line's routine, which reads your pet from your own entity's
    -- pet index (0x1FA), ends in ret 8 and is called from nowhere else.
    assert(original:byte(SITE + 1) == 0xE8, label .. ': it was a call.');
    local target = image.base + SITE + 5 + image:read32(image.base + SITE + 1);
    assert(target % 4294967296 == image.base + ROUTINE, label .. ': to the pet line\'s routine.');
    assert(image:bytes(image.base + ROUTINE + 0xDD, 3) == string.char(0xC2, 0x08, 0x00), label .. ': which ends in ret 8.');
    -- Every call in the client's code whose target is the routine: an E8 and the distance from the byte after it.
    local calls, from = 0, 0x1000;
    while case[2] == 0x10000000 do
        local hit = original:find('\232', from + 1, true);
        if not hit or hit > 0x330000 then break; end
        local a, b, c, d = original:byte(hit + 1, hit + 4);
        if (hit + 4 + a + b * 256 + c * 65536 + d * 16777216) % 4294967296 == ROUTINE then calls = calls + 1; end
        from = hit;
    end
    assert(calls == 1 or case[2] ~= 0x10000000, label .. ': nothing else calls the pet line: ' .. calls);
    assert(game_pet_bar.update(true) == nil and game_pet_bar.status().on, label .. ': it starts.');
    assert(#writes == 1 and writes[1] == image.base + SITE, label .. ': the one call is written.');
    local expected = original:sub(1, SITE) .. game_pet_bar._SKIP .. original:sub(SITE + 6);
    assert(#expected == #original and image.data == expected, label .. ': only the call changes.');
    assert(game_pet_bar.update(true) == nil and #writes == 1, label .. ': staying in effect writes nothing.');
    assert(game_pet_bar.update(false) == nil and image.data == original and #writes == 2, label .. ': out of effect, the client is as it was.');
end

-- Clients changed in one place each: the new one, with nothing written to any of them.
local new = fixture.load('new');
local function refused(name, change, wanted)
    local image = new:copy();
    change(image);
    local changed = image.data;
    over(image);
    local why = game_pet_bar.update(true);
    assert(type(why) == 'string' and why:find(wanted, 1, true), name .. ': ' .. tostring(why));
    assert(#writes == 0 and image.data == changed and not game_pet_bar.status().on, name .. ': nothing is written.');
end
refused('a pet line changed at its start', function(image) image:write(image.base + ROUTINE, '\204'); end,
    'This game client\'s pet bar drawing is not the code Vantage knows' .. STAYS);
refused('a pet line that clears another count', function(image) image:write(image.base + ROUTINE + 0xDE, '\12'); end,
    'This game client\'s pet bar drawing is not the code Vantage knows' .. STAYS);
refused('a pet line that isn\'t there', function(image) image:write(image.base + ROUTINE + 0x3D, '\204'); end,
    'This game client\'s pet bar drawing is missing' .. STAYS);
refused('a layout changed before the call', function(image) image:write(image.base + SITE - 0x20, '\204'); end,
    'This game client\'s party list layout is not the code Vantage knows' .. STAYS);
refused('a layout that isn\'t there', function(image) image:write(image.base + SITE - 0x15, '\204'); end,
    'This game client\'s party list layout is missing' .. STAYS);
refused('a call to somewhere else', function(image)
    image:write(image.base + SITE + 1, fixture.le32(image:read32(image.base + SITE + 1) + 0xE0));
end, 'Something else already changed how the game draws its pet bar, so Vantage leaves it alone.');
-- A client with a second copy of the pet line's bytes somewhere else in its code: neither is taken.
refused('a pet line found twice', function(image)
    local copy = image:bytes(image.base + ROUTINE + 0x3D, #game_pet_bar._patterns.pet_line / 2);
    image:write(image.base + 0x300000, copy);
end, 'This game client\'s pet bar drawing matches more than once' .. STAYS);
-- The fellow's line, 0xE0 on, has the same first bytes as the pet's and is not it: its pattern doesn't match there.
assert(new:bytes(new.base + ROUTINE, 4) == new:bytes(new.base + ROUTINE + 0xE0, 4), 'Fixture: the next routine starts as the pet line does.');
assert(new:find(new.base + ROUTINE + 0xE0, 0xE0, game_pet_bar._patterns.pet_line, 0) == 0, 'The pet line\'s pattern is not in the fellow\'s line.');
game_pet_bar._set_platform(nil);
return 'Replace the game\'s pet bar on the decoded clients';
