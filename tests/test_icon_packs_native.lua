-- The icons folder is listed over the real ffi and kernel32 (ui/client_assets.lua api.list): its folders and files by
-- their UTF-8 names, which is a folder and how big each file is. On a folder this test makes in its own install folder
-- and removes again.
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
pcall(ffi.cdef, 'int __stdcall CreateDirectoryW(const unsigned short*, void*);')
pcall(ffi.cdef, 'int __stdcall RemoveDirectoryW(const unsigned short*);')
local kernel = ffi.load('kernel32')
local function wide(text)
    local count = kernel.MultiByteToWideChar(65001, 0, text, #text, nil, 0)
    local out = ffi.new('unsigned short[?]', count + 1)
    assert(kernel.MultiByteToWideChar(65001, 0, text, #text, out, count) == count)
    return out
end

-- A set named with an e acute, holding one picture and a text file.
local root = MOCK_INSTALL_PATH .. '/icons-native'
local set = root .. '/Caf\195\169 set'
local made = {}
assert(kernel.CreateDirectoryW(wide(root), nil) ~= 0 and kernel.CreateDirectoryW(wide(set), nil) ~= 0, 'Fixture: the folders are made.')
for _, entry in ipairs({ { '33.png', 'PNG bytes here' }, { 'readme.txt', 'Hi' } }) do
    local name = set .. '/' .. entry[1]
    local handle = kernel.CreateFileW(wide(name), 0x40000000, 0, nil, 2, 0x80, nil)
    assert(handle ~= nil and tonumber(ffi.cast('intptr_t', handle)) ~= -1, 'Fixture: the file is made.')
    local written = ffi.new('unsigned long[1]')
    kernel.WriteFile(handle, entry[2], #entry[2], written, nil)
    kernel.CloseHandle(handle)
    made[#made + 1] = name
end

local ok, problem = pcall(function()
    local top = assert(api.list(root), 'The icons folder is listed.')
    assert(#top == 1 and top[1].name == 'Caf\195\169 set' and top[1].folder == true, 'A set\'s folder comes back by its UTF-8 name.')
    local files = assert(api.list(set), 'A set\'s folder is listed.')
    local by_name = {}
    for _, entry in ipairs(files) do by_name[entry.name] = entry end
    assert(#files == 2 and by_name['33.png'] and by_name['33.png'].folder == false and by_name['33.png'].size == 14,
        'Each file comes back with its size, and . and .. don\'t.')
    assert(api.read(set .. '/33.png', 1024) == 'PNG bytes here', 'A picture in it is read by its path.')
    local missing, why = api.list(root .. '/None')
    assert(missing == nil and why, 'A folder that isn\'t there says so.')
end)
for _, name in ipairs(made) do kernel.DeleteFileW(wide(name)) end
kernel.RemoveDirectoryW(wide(set))
kernel.RemoveDirectoryW(wide(root))
assert(ok, problem)
return 'The icons folder listed by UTF-8 name, over kernel32'
