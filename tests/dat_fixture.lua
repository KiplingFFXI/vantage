-- What the font tests build client DATs with, and a function's upvalue by name. Requiring it changes nothing else.
local D = {}
-- Little-endian numbers.
function D.u16(value) return string.char(value % 256, math.floor(value / 256) % 256) end
function D.u32(value) return D.u16(value % 65536) .. D.u16(math.floor(value / 65536)) end
-- A chunk of the given kind holding payload, padded to a whole number of 16-byte rows.
function D.chunk(kind, payload)
    local length = math.ceil((16 + #payload) / 16) * 16
    return 'TEST' .. D.u32(length / 16 * 128 + kind) .. string.rep('\0', 8) .. payload .. string.rep('\0', length - 16 - #payload)
end
-- A DXT3 texture chunk named name, width by height, every 4x4 block the same 16 bytes.
function D.texture(name, width, height)
    local data = string.rep(string.rep('\255', 8) .. '\255\255\0\0\0\0\0\0', math.ceil(width / 4) * math.ceil(height / 4))
    return D.chunk(0x20, string.char(0xA1) .. name .. D.u32(40) .. D.u32(width) .. D.u32(height)
        .. string.rep('\0', 28) .. '3TXD' .. D.u32(#data) .. D.u32(0) .. data)
end
-- fn's upvalue named wanted, or nil when it has none by that name.
function D.upvalue(fn, wanted)
    for index = 1, 200 do
        local name, value = debug.getupvalue(fn, index)
        if name == wanted then return value end
        if not name then break end
    end
end
return D
