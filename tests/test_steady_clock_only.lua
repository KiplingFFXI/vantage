-- The game's os.clock stops counting after about 24.86 days with the game open, so only core/steady.lua reads it, as
-- the fallback for the frame timings' counter. Everything else times on the steady clock.
local listing = io.popen('dir /b /s "' .. ADDON_DIR:gsub('/', '\\') .. '\\*.lua" 2>nul');
local files = {};
if listing then
    for line in listing:lines() do files[#files + 1] = line:gsub('\\', '/'):gsub('\r', ''); end;
    listing:close();
end;
assert(#files > 50, 'Fixture: the scan finds the addon files: ' .. #files);
local steady = false;
for _, path in ipairs(files) do
    local name = path:sub(#ADDON_DIR + 2);
    local file = assert(io.open(path, 'rb'));
    local text = file:read('*a');
    file:close();
    if name == 'core/steady.lua' then
        steady = text:find('os.clock', 1, true) ~= nil;
    else
        local at = text:find('os.clock', 1, true);
        assert(not at, name .. ' reads os.clock at line ' .. (at and select(2, text:sub(1, at):gsub('\n', '')) + 1 or 0));
    end;
end;
assert(steady, 'Fixture: core/steady.lua is the one that reads it.');
return 'Only the steady clock reads os.clock';
