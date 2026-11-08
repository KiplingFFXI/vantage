-- A client path with letters outside ASCII reaches the art's file reads as UTF-8 or in the system's ANSI code page,
-- and both open the same file. Over the real ffi and kernel32, on a file this test makes in its own install folder and
-- removes again.
local function upvalue(fn, wanted)
    for index = 1, 200 do
        local name, value = debug.getupvalue(fn, index)
        if name == wanted then return value end
        if not name then break end
    end
    error('Missing upvalue: ' .. wanted)
end
local assets = require('ui.client_assets')
local mocked = package.loaded.ffi
package.loaded.ffi = nil
local ffi = require('ffi')
package.loaded.ffi = ffi
local api = upvalue(upvalue(assets.prepare_icons, 'art_roots'), 'native')()
package.loaded.ffi = mocked
pcall(ffi.cdef, 'int __stdcall WriteFile(void*, const void*, unsigned long, unsigned long*, void*);')
pcall(ffi.cdef, 'int __stdcall DeleteFileW(const unsigned short*);')
pcall(ffi.cdef, 'unsigned int __stdcall GetACP(void);')
local kernel = ffi.load('kernel32')
local function wide(text)
    local count = kernel.MultiByteToWideChar(65001, 0, text, #text, nil, 0)
    local out = ffi.new('unsigned short[?]', count + 1)
    assert(kernel.MultiByteToWideChar(65001, 0, text, #text, out, count) == count)
    return out
end

-- The file, named with an e acute, written through its UTF-8 name.
local folder = MOCK_INSTALL_PATH .. '/'
local utf8_name, contents = folder .. 'Caf\195\169 art.dat', 'Vantage path test'
local handle = kernel.CreateFileW(wide(utf8_name), 0x40000000, 0, nil, 2, 0x80, nil)
assert(handle ~= nil and tonumber(ffi.cast('intptr_t', handle)) ~= -1, 'Fixture: the file is made.')
local written = ffi.new('unsigned long[1]')
local wrote = kernel.WriteFile(handle, contents, #contents, written, nil)
kernel.CloseHandle(handle)
assert(wrote ~= 0 and tonumber(written[0]) == #contents, 'Fixture: the file is written.')

local ok, problem = pcall(function()
    assert(api.read(utf8_name, 1024) == contents, 'A UTF-8 path opens the file.')
    -- Bytes that aren't UTF-8 are read in the ANSI code page, never refused: a missing file is just missing.
    local _, why = api.read(folder .. 'Caf\233 none.dat', 1024)
    assert(why == 'The asset file could not be opened.', 'A path that isn\'t UTF-8 is converted, not refused: ' .. tostring(why))
    -- The same name in the ANSI code page, where that page has an e acute, opens the same file.
    local unit, bytes, used = ffi.new('unsigned short[1]', 0xE9), ffi.new('char[8]'), ffi.new('int[1]')
    local length = kernel.GetACP() ~= 65001 and kernel.WideCharToMultiByte(0, 0, unit, 1, bytes, 8, nil, used) or 0
    if length == 1 and used[0] == 0 then
        local ansi_name = folder .. 'Caf' .. ffi.string(bytes, 1) .. ' art.dat'
        assert(ansi_name ~= utf8_name and api.read(ansi_name, 1024) == contents, 'The ANSI name opens the same file.')
    end
end)
kernel.DeleteFileW(wide(utf8_name))
assert(ok, problem)
return 'Client paths outside ASCII, as UTF-8 or in the ANSI code page'
