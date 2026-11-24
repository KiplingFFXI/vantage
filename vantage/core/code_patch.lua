-- Reading and writing the client's own code, for the two parts that change the game's drawing (core/game_buffs.lua
-- and core/game_pet_bar.lua). Each passes its own platform, so the tests' platforms stand in for the client here too.
local code_patch = {};
local address = require('core.memory').address;

-- kernel32's write into the client's code: makes the bytes writable, writes them, puts the protection back and tells
-- the processor the code changed. True only when the bytes read back as written.
function code_patch.writer(ffi)
    pcall(ffi.cdef, 'int __stdcall VirtualProtect(void*, size_t, unsigned long, unsigned long*);');
    pcall(ffi.cdef, 'int __stdcall FlushInstructionCache(void*, const void*, size_t);');
    pcall(ffi.cdef, 'void* __stdcall GetCurrentProcess(void);');
    local old, ignored = ffi.new('unsigned long[1]'), ffi.new('unsigned long[1]');
    return function(at, bytes)
        local where = ffi.cast('void*', at);
        if ffi.C.VirtualProtect(where, #bytes, 0x40, old) == 0 then return false; end
        ffi.copy(where, bytes, #bytes);
        local restored = ffi.C.VirtualProtect(where, #bytes, old[0], ignored) ~= 0;
        local flushed = ffi.C.FlushInstructionCache(ffi.C.GetCurrentProcess(), where, #bytes) ~= 0;
        return restored and flushed and ffi.string(ffi.cast('const char*', at), #bytes) == bytes;
    end;
end

-- The client's bytes at an address, or nothing where they can't be read.
function code_patch.code(platform, at, size)
    if not address(at) then return nil; end
    local ok, good = pcall(platform.readable, at, size);
    if not ok or good ~= true then return nil; end
    local read_ok, text = pcall(platform.bytes, at, size);
    if read_ok and type(text) == 'string' and #text == size then return text; end
end

-- Whether the bytes at an address are a body's, ?? aside.
function code_patch.matches(platform, at, body)
    local size = #body / 2;
    local text = code_patch.code(platform, at, size);
    if not text then return false; end
    for index = 1, size do
        local pair = body:sub(index * 2 - 1, index * 2);
        if pair ~= '??' and tonumber(pair, 16) ~= text:byte(index) then return false; end
    end
    return true;
end

-- The five bytes of a call from at to a routine.
function code_patch.call(at, to)
    local value = (to - at - 5) % 4294967296;
    local bytes = { 0xE8 };
    for index = 2, 5 do bytes[index] = value % 256; value = math.floor(value / 256); end
    return string.char(unpack(bytes));
end

return code_patch;
