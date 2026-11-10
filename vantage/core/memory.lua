-- Guarded access to the client's memory for the client, party list and chat readers. Nothing here keeps what it finds,
-- and no reader keeps a page check past the frame it made it in, as the client frees memory between frames. The one
-- exception is a page of a loaded image, the client's own code and data, which stays as long as the game runs.
local memory = {};

function memory.address(value)
    return type(value) == 'number' and value == math.floor(value) and value >= 65536 and value < 0xFFF00000;
end

-- Page checks through VirtualQuery. valid(ptr, length, writable): the range lies in one committed region with
-- no guard page that can be read, or written with writable, and then where that region starts and stops and whether
-- it's part of a loaded image.
-- readable(at, size): the range can be read, across up to 64 regions. Each reader keeps its own rule by which of
-- these it calls. Errors when this ffi can't query pages; the readers build their platforms under pcall.
function memory.pages()
    local ffi, bit = require('ffi'), require('bit');
    if not pcall(ffi.typeof, 'vg_client_region') then ffi.cdef[[
        typedef struct { void* BaseAddress; void* AllocationBase; unsigned long AllocationProtect;
            size_t RegionSize; unsigned long State; unsigned long Protect; unsigned long Type; } vg_client_region;
        size_t __stdcall VirtualQuery(const void*, void*, size_t);
    ]]; end
    local region = ffi.new('vg_client_region[1]');
    -- Where the region holding at ends and where it starts from at's page, when it is committed with no guard page and
    -- allows the access.
    local function region_end(at, writable)
        if ffi.C.VirtualQuery(ffi.cast('const void*', at), region, ffi.sizeof(region[0])) == 0 then return nil; end
        local info = region[0];
        if info.State ~= 0x1000 or bit.band(info.Protect, 0x100) ~= 0 then return nil; end
        local p = bit.band(info.Protect, 0xFF);
        local allowed = writable and (p == 4 or p == 8 or p == 0x40 or p == 0x80)
            or not writable and (p == 2 or p == 4 or p == 8 or p == 0x20 or p == 0x40 or p == 0x80);
        if not allowed then return nil; end
        local first = tonumber(ffi.cast('uintptr_t', info.BaseAddress));
        return first + tonumber(info.RegionSize), first, info.Type == 0x1000000;
    end
    return {
        valid = function(ptr, length, writable)
            if not memory.address(ptr) or ptr + length >= 0xFFF00000 then return false; end
            local stop, first, image = region_end(ptr, writable);
            return stop ~= nil and ptr + length <= stop, first, stop, image == true;
        end,
        readable = function(at, size)
            local finish = at + size;
            for _ = 1, 64 do
                local stop = region_end(at, false);
                if not stop then return false; end
                if finish <= stop then return true; end
                at = stop;
            end
            return false;
        end,
    };
end

-- A copy of size bytes at an address through ReadProcessMemory on this process: nil when the pages can't be
-- read. Errors when the binding can't be made here.
function memory.copier()
    local ffi = require('ffi');
    ffi.cdef[[
        int __stdcall ReadProcessMemory(void*, const void*, void*, size_t, size_t*);
        void* __stdcall GetCurrentProcess(void);
    ]];
    local kernel = ffi.load('kernel32');
    local process = kernel.GetCurrentProcess();
    -- One buffer, grown to the largest copy asked for, and one count serve every copy.
    local buffer, room, count = nil, 0, ffi.new('size_t[1]');
    return function(at, size)
        if size > room then buffer, room = ffi.new('uint8_t[?]', size), size; end
        count[0] = 0;
        local result = kernel.ReadProcessMemory(process, ffi.cast('const void*', at), buffer, size, count);
        if result == 0 or tonumber(count[0]) ~= size then return nil; end
        return ffi.string(buffer, size);
    end;
end

return memory;
