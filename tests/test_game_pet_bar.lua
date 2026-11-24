-- Replace the game's pet bar (core/game_pet_bar.lua), over a made-up client. While it is in effect the party list's one
-- call to the pet line's routine is skipped. Out of effect and at unload the call is back. Nothing is written unless
-- both pieces are found once, their bytes are the ones this was written for, and the call still goes to the pet
-- line's routine.
local game_pet_bar = require('core.game_pet_bar');
local SKIP, patterns, bodies = game_pet_bar._SKIP, game_pet_bar._patterns, game_pet_bar._bodies;
local STAYS = ', so the game\'s pet bar stays as it is.';
local CANT_REACH = 'Vantage can\'t reach this game client\'s drawing code' .. STAYS;
local CANT_PUT_BACK = 'Vantage could not put the game\'s pet bar back. Restart the game to get it back.';
local SOMETHING_ELSE = 'Something else already changed how the game draws its pet bar, so Vantage leaves it alone.';

-- In the tests the real client is never reached: with no platform set, nothing is replaced, and nothing asks ffi for
-- anything.
do
    local asked, real = 0, package.loaded.ffi;
    package.loaded.ffi = setmetatable({}, { __index = function(_, key) asked = asked + 1; error('ffi.' .. tostring(key) .. ' was asked for', 0); end });
    local reason = game_pet_bar.update(true);
    package.loaded.ffi = real;
    assert(reason == CANT_REACH and asked == 0, ('A test never builds the real platform: %s, %d asked'):format(tostring(reason), asked));
    assert(game_pet_bar.problem() == CANT_REACH and not game_pet_bar.status().on, 'The page can say why.');
end

-- What stands in for the call follows from the client's own code: the pet line's routine clears its two arguments
-- itself (it ends in ret 8) and says in al whether it drew, and the layout tests al right after the call.
assert(SKIP == string.char(0x83, 0xC4, 0x08, 0x32, 0xC0), 'The skip steps the stack over 8 bytes and says nothing was drawn.');
assert(bodies.pet_line:sub(-16) == 'B0015B5F5EC20800', 'The pet line ends by saying it drew and clearing 8 bytes.');
assert(bodies.pet_line:sub(0x3D * 2 + 1, 0x3D * 2 + #patterns.pet_line) == patterns.pet_line, 'The pet line\'s pattern is 0x3D into its routine.');
assert(bodies.layout:sub(0x12 * 2 + 1, 0x12 * 2 + #patterns.layout) == patterns.layout, 'The layout\'s pattern is 0x12 into its body.');
assert(bodies.layout:sub((0x12 + 0x15) * 2 + 1, (0x12 + 0x15) * 2 + 18) == '??????????84C07407', 'The call is 0x15 on, and al is tested after it.');
assert(#bodies.pet_line / 2 == 0xE0 and #bodies.layout / 2 == 0x59, 'Both bodies are whole.');

-- Memory as bytes by address. Only what a test maps can be read.
local mem = {};
local function put(at, bytes) for index = 1, #bytes do mem[at + index - 1] = bytes:byte(index); end end
local function get(at, size)
    local out = {};
    for index = 0, size - 1 do
        local byte = mem[at + index];
        if byte == nil then return nil; end
        out[index + 1] = string.char(byte);
    end
    return table.concat(out);
end
local function le(value)
    value = value % 4294967296;
    local out = {};
    for index = 1, 4 do out[index] = string.char(value % 256); value = math.floor(value / 256); end
    return table.concat(out);
end
local function plant(at, pattern, filler)
    put(at, (pattern:gsub('..', function(pair) return string.char(pair == '??' and filler or tonumber(pair, 16)); end)));
end
local function call(at, to) return string.char(0xE8) .. le(to - at - 5); end

local CODE = 0x10000000;
local ROUTINE, LAYOUT = CODE + 0x202960, CODE + 0x204543;
local SITE = LAYOUT + 0x12 + 0x15;
local finds, writes, missing, fails, reads;
-- A client with both pieces as this was written for them, and the call from one to the other.
local function client(filler)
    mem, finds, writes, missing, fails, reads = {}, {}, {}, {}, false, 0;
    plant(ROUTINE, bodies.pet_line, filler or 0);
    plant(LAYOUT, bodies.layout, filler or 0);
    put(SITE, call(SITE, ROUTINE));
    game_pet_bar._set_platform({
        readable = function(at, size) return get(at, size) ~= nil; end,
        find = function(name)
            finds[#finds + 1] = name;
            if missing[name] then return nil, missing[name]; end
            return name == 'pet_line' and ROUTINE + 0x3D or LAYOUT + 0x12;
        end,
        bytes = function(at, size) reads = reads + 1; return get(at, size); end,
        write_code = function(at, bytes)
            writes[#writes + 1] = at;
            if fails then return false; end
            put(at, bytes);
            return true;
        end,
    });
end
local function snapshot()
    local out = {};
    for at, byte in pairs(mem) do out[at] = byte; end
    return out;
end
local function same_but_site(before)
    for at, byte in pairs(before) do
        if (at < SITE or at >= SITE + 5) and mem[at] ~= byte then return false; end
    end
    return true;
end

-- In effect: the one call is skipped, and nothing else changes.
client();
local before = snapshot();
assert(game_pet_bar.update(true) == nil and game_pet_bar.status().on and game_pet_bar.problem() == nil, 'It starts with nothing to say.');
assert(#writes == 1 and writes[1] == SITE and get(SITE, 5) == SKIP and same_but_site(before), 'Only the call changes, to the skip.');
assert(#finds == 2 and finds[1] == 'pet_line' and finds[2] == 'layout', 'Each piece is looked for once.');
-- While it stays in effect nothing more is read or written: a frame only asks whether it still is.
local read_so_far = reads;
for _ = 1, 3 do assert(game_pet_bar.update(true) == nil); end
assert(#writes == 1 and #finds == 2 and reads == read_so_far, 'Staying in effect reads, writes and looks for nothing more.');
-- Out of effect: the call is back, byte for byte.
assert(game_pet_bar.update(false) == nil and not game_pet_bar.status().on, 'It stops with nothing to say.');
assert(#writes == 2 and get(SITE, 5) == call(SITE, ROUTINE) and same_but_site(before), 'The call is back.');
assert(game_pet_bar.update(false) == nil and #writes == 2, 'Out of effect it writes nothing more.');
-- In effect again without another search, and unload puts it back.
assert(game_pet_bar.update(true) == nil and get(SITE, 5) == SKIP and #finds == 2, 'In effect again, with what was found before.');
local clean, why = game_pet_bar.release();
assert(clean == true and why == nil and get(SITE, 5) == call(SITE, ROUTINE) and not game_pet_bar.status().on, 'Unload puts the call back.');
assert(game_pet_bar.release() == true and #writes == 4, 'A second unload has nothing to put back.');
-- Something else changes the call while the tick is out of effect: asked again, Vantage writes nothing over it.
client();
assert(game_pet_bar.update(true) == nil and game_pet_bar.update(false) == nil and #writes == 2, 'Fixture: in effect, then out.');
put(SITE, '\233' .. le(0x3000));
assert(game_pet_bar.update(true) == 'Something else changed how the game draws its pet bar, so Vantage leaves it alone.',
    'A call something else changed since is left alone.');
assert(#writes == 2 and get(SITE, 5) == '\233' .. le(0x3000) and not game_pet_bar.status().on, 'And nothing is written over it.');
-- The addresses the client fills in can be anything.
client(0xAB);
assert(game_pet_bar.update(true) == nil and get(SITE, 5) == SKIP, 'Other addresses in the client\'s code change nothing.');

-- A client changed in one place each is left alone, with nothing written.
local function refused(name, change, wanted)
    client();
    change();
    local changed = snapshot();
    local notice = game_pet_bar.update(true);
    assert(notice == wanted, name .. ': ' .. tostring(notice));
    assert(#writes == 0 and not game_pet_bar.status().on and game_pet_bar.problem() == wanted, name .. ': nothing is written, and the page can say why.');
    for at, byte in pairs(changed) do assert(mem[at] == byte, name .. ': the client is as it was.'); end
    -- It says so once, and tries again only after the tick has been out of effect.
    assert(game_pet_bar.update(true) == nil and game_pet_bar.problem() == wanted, name .. ': it doesn\'t say it again.');
    assert(game_pet_bar.update(false) == nil and game_pet_bar.problem() == nil, name .. ': out of effect there is nothing to say.');
    assert(game_pet_bar.update(true) == wanted and #writes == 0, name .. ': asked again, it says why again.');
end
refused('no pet line', function() missing.pet_line = 'is missing'; end, 'This game client\'s pet bar drawing is missing' .. STAYS);
refused('two pet lines', function() missing.pet_line = 'matches more than once'; end, 'This game client\'s pet bar drawing matches more than once' .. STAYS);
refused('no layout', function() missing.layout = 'is missing'; end, 'This game client\'s party list layout is missing' .. STAYS);
refused('a pet line changed before its pattern', function() put(ROUTINE + 2, '\204'); end, 'This game client\'s pet bar drawing is not the code Vantage knows' .. STAYS);
refused('a pet line that clears another count', function() put(ROUTINE + 0xDE, '\12'); end, 'This game client\'s pet bar drawing is not the code Vantage knows' .. STAYS);
refused('a layout changed before the call', function() put(LAYOUT + 4, '\204'); end, 'This game client\'s party list layout is not the code Vantage knows' .. STAYS);
refused('a layout that doesn\'t test what the call says', function() put(SITE + 5, '\144'); end, 'This game client\'s party list layout is not the code Vantage knows' .. STAYS);
refused('a call to somewhere else', function() put(SITE, call(SITE, ROUTINE + 0x10)); end, SOMETHING_ELSE);
refused('a jump over the call', function() put(SITE, '\233' .. le(0x1000)); end, SOMETHING_ELSE);
refused('a pet line that can\'t be read', function() mem[ROUTINE + 0x80] = nil; end, 'This game client\'s pet bar drawing is not the code Vantage knows' .. STAYS);
-- A search that raises is one more refusal, not an error in the frame.
client();
game_pet_bar._set_platform({ find = function() error('Search failed', 0); end, readable = function() return true; end, bytes = get,
    write_code = function() error('Never written'); end });
assert(game_pet_bar.update(true) == 'Vantage could not check this game client\'s pet bar drawing' .. STAYS, 'A search that fails is said plainly.');

-- The skip already there, as after a load that could not put it back: it counts as in effect with nothing written,
-- and going out of effect puts the client's own call back, worked out from where the routine is.
client();
put(SITE, SKIP);
assert(game_pet_bar.update(true) == nil and game_pet_bar.status().on and #writes == 0, 'A skip already there is taken as it is.');
assert(game_pet_bar.update(false) == nil and #writes == 1 and get(SITE, 5) == call(SITE, ROUTINE), 'And the call goes back where it was.');

-- A write that fails changes nothing and says so.
client();
fails = true;
assert(game_pet_bar.update(true) == 'Vantage could not change the game\'s pet bar drawing' .. STAYS, 'A write that fails is said.');
assert(not game_pet_bar.status().on and get(SITE, 5) == call(SITE, ROUTINE), 'And nothing changed.');
-- A put back that fails is said, at the tick and at unload.
client();
assert(game_pet_bar.update(true) == nil and get(SITE, 5) == SKIP, 'Fixture: in effect.');
fails = true;
assert(game_pet_bar.update(false) == CANT_PUT_BACK and game_pet_bar.problem() == CANT_PUT_BACK, 'A call that can\'t be put back is said.');
client();
assert(game_pet_bar.update(true) == nil, 'Fixture: in effect.');
fails = true;
clean, why = game_pet_bar.release();
assert(clean == false and why == CANT_PUT_BACK, 'And at unload.');
-- Something else wrote over the skip meanwhile: Vantage writes nothing over it.
client();
assert(game_pet_bar.update(true) == nil, 'Fixture: in effect.');
put(SITE, '\233' .. le(0x2000));
assert(game_pet_bar.update(false) == CANT_PUT_BACK and #writes == 1 and get(SITE, 5) == '\233' .. le(0x2000), 'What something else wrote there is left alone.');
-- The client put its own call back meanwhile: nothing to do.
client();
assert(game_pet_bar.update(true) == nil, 'Fixture: in effect.');
put(SITE, call(SITE, ROUTINE));
assert(game_pet_bar.update(false) == nil and #writes == 1, 'A call that is already back needs no write.');

-- The searches are warmup steps, one a pattern, each asking the client once.
client();
local steps = game_pet_bar.warmup_steps();
assert(#steps == 2 and steps[1].name == 'game_pet_bar.pet_line' and steps[2].name == 'game_pet_bar.layout', 'Two steps, in the order they are looked for.');
for _, step in ipairs(steps) do step.run(); step.run(); end
assert(#finds == 2 and finds[1] == 'pet_line' and finds[2] == 'layout', 'Each step looks for its pattern once.');
game_pet_bar._set_platform(nil);
for _, step in ipairs(game_pet_bar.warmup_steps()) do step.run(); end
assert(game_pet_bar.update(true) == CANT_REACH, 'With no client to reach the steps do nothing, and the replacement says why it is off.');
game_pet_bar._set_platform(nil);
return 'Replace the game\'s pet bar skips one call and puts it back';
