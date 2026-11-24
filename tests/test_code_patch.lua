-- The one write into the client's code (core/code_patch.lua), over a stand-in ffi, and both parts that change the
-- game's drawing using it. The write makes the bytes writable, writes them, puts the old protection back and tells the
-- processor the code changed. It says true only when all of that worked and the bytes read back as written.
local code_patch = require('core.code_patch');

-- A stand-in ffi over made-up memory, keeping every call in order.
local function stand_in(fail)
    local mem, log, declared = {}, {}, {};
    local protection = 0x20;
    local ffi = { C = {} };
    function ffi.cdef(text)
        if declared[text] then error('already declared', 0); end
        declared[text] = true;
        log[#log + 1] = 'cdef';
    end
    function ffi.new(kind)
        assert(kind == 'unsigned long[1]', 'Only the two protection slots are made: ' .. tostring(kind));
        return { [0] = 0 };
    end
    function ffi.cast(kind, at)
        if kind == 'void*' then return { at = at }; end
        assert(kind == 'const char*', 'Read back as bytes: ' .. tostring(kind));
        return { at = at };
    end
    function ffi.copy(where, bytes, size)
        log[#log + 1] = ('copy %X %d'):format(where.at, size);
        for index = 1, size do mem[where.at + index - 1] = bytes:byte(index); end
    end
    function ffi.string(pointer, size)
        local out = {};
        for index = 1, size do
            local byte = mem[pointer.at + index - 1];
            if fail.read_back and index == 1 then byte = (byte or 0) + 1; end
            out[index] = string.char(byte or 0);
        end
        return table.concat(out);
    end
    function ffi.C.VirtualProtect(where, size, wanted, old)
        log[#log + 1] = ('protect %X %d %X'):format(where.at, size, wanted);
        if fail.protect and wanted == 0x40 then return 0; end
        if fail.restore and wanted ~= 0x40 then return 0; end
        old[0], protection = protection, wanted;
        return 1;
    end
    function ffi.C.GetCurrentProcess() return 'process'; end
    function ffi.C.FlushInstructionCache(process, where, size)
        log[#log + 1] = ('flush %s %X %d'):format(process, where.at, size);
        return fail.flush and 0 or 1;
    end
    return ffi, mem, log, function() return protection; end;
end

local AT, BYTES = 0x10204558, string.char(0x83, 0xC4, 0x08, 0x32, 0xC0);
local function writes(fail)
    local ffi, mem, log, protection = stand_in(fail);
    local write_code = code_patch.writer(ffi);
    local result = write_code(AT, BYTES);
    return result, mem, log, protection(), write_code, ffi;
end

do
    local result, mem, log, protection, write_code, ffi = writes({});
    assert(result == true, 'A write that worked says true.');
    local expected = { 'cdef', 'cdef', 'cdef', 'protect 10204558 5 40', 'copy 10204558 5', 'protect 10204558 5 20', 'flush process 10204558 5' };
    assert(table.concat(log, ', ') == table.concat(expected, ', '), 'The write runs in order: ' .. table.concat(log, ', '));
    assert(protection == 0x20, 'The old protection is put back: ' .. protection);
    for index = 1, #BYTES do assert(mem[AT + index - 1] == BYTES:byte(index), 'Every byte is written.'); end
    -- A second writer on the same ffi finds its three declarations already made, and still works.
    local again = code_patch.writer(ffi);
    assert(again(AT, BYTES) == true, 'Declarations already made are fine.');
    assert(write_code(AT, BYTES) == true, 'A writer can write again.');
end

do
    local result, mem, log = writes({ protect = true });
    assert(result == false and next(mem) == nil, 'Bytes that can\'t be made writable are left alone.');
    assert(log[#log] == 'protect 10204558 5 40', 'Nothing more is done after that: ' .. log[#log]);
end

for _, fail in ipairs({ 'restore', 'flush', 'read_back' }) do
    local result, mem, log = writes({ [fail] = true });
    assert(result == false, 'A write says false when ' .. fail .. ' fails.');
    assert(mem[AT] == BYTES:byte(1), 'The bytes were written before ' .. fail .. '.');
    assert(log[#log] == 'flush process 10204558 5' and log[#log - 1] == 'protect 10204558 5 20', 'The protection is put back and the code flushed even when ' .. fail .. ' fails.');
end

-- The bytes of a call, and reading and matching code through a platform.
assert(code_patch.call(0x1000, 0x2000) == string.char(0xE8, 0xFB, 0x0F, 0, 0), 'A call forward.');
assert(code_patch.call(0x2000, 0x1000) == string.char(0xE8, 0xFB, 0xEF, 0xFF, 0xFF), 'A call back.');
local BASE = 0x10001000;
local platform = {
    readable = function(at, size) return at >= BASE and at + size <= BASE + 4; end,
    bytes = function(at, size) return ('\1\2\3\4'):sub(at - BASE + 1, at - BASE + size); end,
};
assert(code_patch.code(platform, BASE, 4) == '\1\2\3\4', 'Readable code reads.');
assert(code_patch.code(platform, BASE + 1, 4) == nil, 'Code that can\'t be read is nothing.');
assert(code_patch.code(platform, 0, 4) == nil, 'No address is nothing.');
assert(code_patch.matches(platform, BASE, '01??0304') and not code_patch.matches(platform, BASE, '01020305'), '?? matches any byte.');

-- Both parts that change the game's drawing go through it: neither writes code of its own, and the checks of both go
-- through the shared reader.
for _, name in ipairs({ 'game_buffs', 'game_pet_bar' }) do
    local file = assert(io.open(ADDON_DIR .. '/core/' .. name .. '.lua', 'rb'));
    local text = file:read('*a');
    file:close();
    assert(not text:find('VirtualProtect', 1, true), 'core/' .. name .. '.lua writes no code of its own.');
    assert(text:find('write_code = code_patch.writer(ffi)', 1, true), 'core/' .. name .. '.lua writes with the shared writer.');
end
local matched = 0;
local real = code_patch.matches;
code_patch.matches = function(...) matched = matched + 1; return real(...); end
local everywhere = {
    valid = function() return false; end, readable = function() return false; end,
    find = function() return 0x10001000; end, bytes = function() return nil; end,
};
local game_pet_bar, game_buffs = require('core.game_pet_bar'), require('core.game_buffs');
game_pet_bar._set_platform(everywhere);
game_pet_bar.update(true);
assert(matched == 1, 'The pet bar checks its code through the shared reader: ' .. matched);
game_buffs._set_platform(everywhere);
game_buffs.update(true);
assert(matched == 2, 'The buff icons check their code through the shared reader: ' .. matched);
code_patch.matches = real;
return 'The one write into the client\'s code, and both parts that change the game using it';
