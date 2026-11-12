-- Replace the game's buff icons (core/game_buffs.lua) on the decoded clients, and on the new one loaded at another
-- base: every piece is found once by core/patterns.lua, each routine is the one this was written for, the registry
-- and the icon paint name the same buff window slot, and the two final drawing calls are where it says. In effect,
-- only those ten bytes change, and out of effect the client is byte for byte as it was. A client changed in any of
-- those places is left alone.
local fixture = require('client_image_fixture');
local finder = require('core.patterns');
local game_buffs = require('core.game_buffs');
local RULE = { unique = true, within = true };
-- Where the two calls are in both known clients, from the client's base.
local ICON, TIMER = 0x228070, 0x22819B;

local writes, moves;
local function over(image)
    image:install();
    writes, moves = {}, 0;
    game_buffs._set_platform({
        -- The image is the client's code and data. Nothing of a buff window is in it, so nothing here can be written.
        valid = function(at, size, writable) return not writable and image:contains(at, size); end,
        readable = function(at, size) return image:contains(at, size); end,
        find = function(name) return finder.find('game_buffs', name, game_buffs._patterns[name], RULE); end,
        bytes = function(at, size) return image:bytes(at, size); end,
        read8 = ashita.memory.read_uint8, read16 = ashita.memory.read_uint16, read32 = ashita.memory.read_uint32,
        write_code = function(at, bytes) writes[#writes + 1] = at; image:write(at, bytes); return true; end,
        move = function() moves = moves + 1; end,
    });
end

local count = 0;
for name, pattern in pairs(game_buffs._patterns) do
    count = count + 1;
    local body = game_buffs._bodies[name];
    if name == 'menu_move_later' then
        assert(pattern == game_buffs._bodies.menu_move:sub(35, 130) and #pattern == 96,
            'The mover\'s later bytes are its own: 48 of them, 17 on from its start.');
    else
        assert(name == 'registry' and body == nil or body:sub(1, #pattern) == pattern and #pattern == 64, name .. ' starts its routine.');
    end
end
assert(count == 8, 'Seven pieces and the mover\'s later bytes: ' .. count);

for _, case in ipairs({ { 'new', 0x10000000 }, { 'old', 0x10000000 }, { 'new', 0x0F300000 } }) do
    local image = fixture.load(case[1], case[2]);
    local label = ('%s at 0x%08X'):format(case[1], case[2]);
    local original = image.data;
    over(image);
    for name, pattern in pairs(game_buffs._patterns) do
        assert(image:find(image.base, #image.data, pattern, 0) ~= 0 and image:find(image.base, #image.data, pattern, 1) == 0,
            label .. ': ' .. name .. ' once');
    end
    assert(image:find(image.base, #image.data, game_buffs._patterns.menu_move_later, 0)
        == image:find(image.base, #image.data, game_buffs._patterns.menu_move, 0) + 17, label .. ': the later bytes are the mover\'s.');
    local pick, why = game_buffs.update(true);
    assert(pick == nil and why == nil and game_buffs.status().on, label .. ': ' .. tostring(why));
    assert(#writes == 2 and writes[1] == image.base + ICON and writes[2] == image.base + TIMER, label .. ': the two calls are written.');
    local expected = original:sub(1, ICON) .. game_buffs._ICON_SKIP .. original:sub(ICON + 6, TIMER) .. game_buffs._TIMER_SKIP
        .. original:sub(TIMER + 6);
    assert(#expected == #original and image.data == expected, label .. ': only the two calls change.');
    -- The client's own bytes there are calls, to the icon draw and the timer draw.
    assert(original:byte(ICON + 1) == 0xE8 and original:byte(TIMER + 1) == 0xE8, label .. ': both were calls.');
    -- What stands in for each call follows from the client's own code. The icon draw ends in ret 0x14, so its skip
    -- steps the stack over 0x14 bytes: lea esp, [esp + 0x14], nop. The timer paint clears the timer draw's
    -- arguments itself right after the call (add esp, 0x1C), so its skip is five nops.
    local icon_draw = image:find(image.base, #image.data, game_buffs._patterns.icon_draw, 0);
    assert(image:bytes(icon_draw + 0x19B, 3) == string.char(0xC2, 0x14, 0x00) and #game_buffs._bodies.icon_draw / 2 == 0x19E,
        label .. ': the icon draw ends in ret 0x14.');
    assert(game_buffs._ICON_SKIP == string.char(0x8D, 0x64, 0x24, 0x14, 0x90), label .. ': the icon skip steps over 0x14 bytes.');
    assert(original:sub(TIMER + 6, TIMER + 8) == string.char(0x83, 0xC4, 0x1C), label .. ': the timer paint clears the stack itself.');
    assert(game_buffs._TIMER_SKIP == string.rep(string.char(0x90), 5), label .. ': the timer skip is five nops.');
    -- The image has no buff window open, so there is nothing to move.
    assert(game_buffs.update(true) == nil and moves == 0 and game_buffs.status().on, label .. ': no buff window, no move.');
    assert(select(2, game_buffs.update(false)) == nil and image.data == original, label .. ': out of effect, the client is as it was.');
    assert(#writes == 4, label .. ': two writes back.');
end

-- Clients changed in one place each: the new one, with nothing written to any of them.
local new = fixture.load('new');
local function at(image, name) return image:find(image.base, #image.data, game_buffs._patterns[name], 0); end
local function refused(name, change, wanted)
    local image = new:copy();
    change(image);
    local changed = image.data;
    over(image);
    local pick, why = game_buffs.update(true);
    assert(pick == nil and type(why) == 'string' and why:find(wanted, 1, true), name .. ': ' .. tostring(why));
    assert(#writes == 0 and image.data == changed and not game_buffs.status().on, name .. ': nothing is written.');
end
refused('an icon paint changed past its start', function(image) image:write(at(image, 'icon_paint') + 0x80, '\204'); end,
    'This game client\'s buff icon painting is not the code Vantage knows');
refused('an icon draw that clears another count', function(image) image:write(at(image, 'icon_draw') + 0x19C, '\24'); end,
    'This game client\'s icon drawing is not the code Vantage knows');
refused('a timer paint that clears another count', function(image) image:write(at(image, 'timer_paint') + 0x122, '\32'); end,
    'This game client\'s buff timer painting is not the code Vantage knows');
refused('a timer call to somewhere else', function(image)
    image:write(image.base + TIMER + 1, fixture.le32(image:read32(image.base + TIMER + 1) + 16));
end, 'Something else already changed the game\'s buff drawing, so Vantage leaves it alone.');
refused('a registry that names another slot', function(image)
    local registry = at(image, 'registry');
    image:write(registry + 0x4C, fixture.le32(image:read32(registry + 0x4C) + 4));
end, 'This game client\'s buff window was not found where Vantage looks');
refused('a rebuild that isn\'t there', function(image) image:write(at(image, 'rebuild'), '\204'); end,
    'This game client\'s buff list rebuild is missing, so the game\'s buff icons stay as they are.');
-- A hook from another addon or plugin: a jump written over the mover's first bytes, alone or with the rest of the
-- instructions it cut through filled in. The mover's later bytes are still there, so Vantage says what happened.
local CHANGED = 'Something else in the game, such as another addon or plugin, has changed this game client\'s menu mover, so the game\'s buff icons stay as they are.';
refused('a menu mover with a jump over its start', function(image)
    image:write(at(image, 'menu_move'), '\233' .. fixture.le32(0x1000));
end, CHANGED);
refused('a menu mover with a longer jump over its start', function(image)
    image:write(at(image, 'menu_move'), '\233' .. fixture.le32(0x1000) .. '\144\144\144');
end, CHANGED);
refused('a menu mover with a jump through an address over its start', function(image)
    image:write(at(image, 'menu_move'), '\255\37' .. fixture.le32(image.base + 0x2000) .. '\144\144');
end, CHANGED);
-- Changed further in, it is simply not the code Vantage knows. Changed at its start and further in, it isn't found.
refused('a menu mover changed past its start', function(image) image:write(at(image, 'menu_move') + 0x40, '\204'); end,
    'This game client\'s menu mover is not the code Vantage knows');
refused('a menu mover changed at its start and further in', function(image)
    local mover = at(image, 'menu_move');
    image:write(mover, '\233' .. fixture.le32(0x1000));
    image:write(mover + 0x18, '\204');
end, 'This game client\'s menu mover is missing, so the game\'s buff icons stay as they are.');
refused('a menu mover found twice', function(image)
    local pattern = game_buffs._patterns.menu_move;
    assert(not pattern:find('?', 1, true), 'Fixture: the menu mover\'s start has no wildcard.');
    image:write(image.base + #image.data - 64, (pattern:gsub('..', function(pair) return string.char(tonumber(pair, 16)); end)));
end, 'This game client\'s menu mover matches more than once, so the game\'s buff icons stay as they are.');
return 'Replace the game\'s buff icons on the decoded clients';
