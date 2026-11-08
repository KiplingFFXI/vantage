-- Runs a driver in a plain x86 LuaJIT (luajit.exe), the 32-bit LuaJIT the game's Ashita runs addons in, with the
-- same mock the test runtime uses. Nothing here sets LuaJIT's options: vantage.lua sets its own, as it does in the
-- game. Used by benchmark_frame.py --runtime x86 and jit_flush_guard.py.
-- usage: luajit.exe tests/x86_runtime.lua <driver.lua> <install folder> <addon folder> <ASHITA_LIBS> <tests folder>
local driver, install, addon, libs, tests = ...;
assert(driver and install and addon and libs and tests, 'usage: x86_runtime.lua <driver> <install> <addon> <libs> <tests>');
local ffi = require('ffi');
ffi.cdef[[
    unsigned long __stdcall GetFullPathNameA(const char*, unsigned long, char*, char**);
    int __stdcall CreateDirectoryA(const char*, void*);
]];

local function full(path)
    local out = ffi.new('char[1024]');
    local length = ffi.C.GetFullPathNameA(path, 1024, out, nil);
    if length == 0 or length >= 1024 then error('fixture path could not be resolved', 2); end
    return ffi.string(out, length);
end
local root = full(install);

-- Folders only inside the temporary install, as tests/run.py allows.
function MOCK_MKDIR(path)
    local resolved = full(path);
    local head = resolved:sub(1, #root);
    local after = resolved:sub(#root + 1, #root + 1);
    if head:lower() ~= root:lower() or after ~= '' and after ~= '\\' then error('fixture folder escapes its temporary install', 2); end
    local at = 0;
    repeat
        at = resolved:find('\\', at + 1, true) or #resolved + 1;
        ffi.C.CreateDirectoryA(resolved:sub(1, at - 1), nil);
    until at > #resolved;
    return true;
end

MOCK_INSTALL_PATH, ADDON_DIR, ASHITA_LIBS, TESTS_DIR = install, addon, libs, tests;
VANTAGE_TEST_MODE = true;
MOCK_MKDIR(install .. '/config/addons/vantage');
package.path = table.concat({ addon .. '/?.lua', tests .. '/?.lua', libs .. '/?.lua', package.path }, ';');
package.preload.json = function() return dofile(addon .. '/core/json.lua'); end;
dofile(tests .. '/mock_ashita.lua');
MOCK.fs[install .. '/config/addons/vantage/'] = true;
dofile(driver);
