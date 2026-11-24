-- Files and behavior on Help names every setting that changes the game itself: where it is, what the game stops
-- drawing while it is on, and that Vantage puts it back.
local app = dofile(ADDON_DIR .. '/vantage.lua')
local window = require('ui.settings_window')
local s = app.state.settings
s.window.open, s.window.tab = true, 'Help'
MOCK.imgui_calls = {}
window.draw(s, app.state.view, app.callbacks)
local lines = {}
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'TextWrapped' then lines[#lines + 1] = call[2] end
end
local help = table.concat(lines, '\n')
assert(help:find('Vantage reads what the game client has', 1, true), 'Fixture: Files and behavior is drawn.')
assert(not help:find('is the one setting that changes the game', 1, true), 'Help doesn\'t say only one setting changes the game.')

local line
for _, text in ipairs(lines) do
    if text:find('change the game itself', 1, true) then line = text end
end
assert(line, 'Help says which settings change the game itself.')
for _, words in ipairs({
    'Replace the game\'s buff icons and Replace the game\'s pet bar, both under While playing on the main page',
    'the game doesn\'t draw its own buff icons and its + menu sits off screen',
    'the game doesn\'t draw your pet\'s name, HP bar and TP above the party list',
    'when you turn it off or unload Vantage',
}) do
    assert(line:find(words, 1, true), 'Help says: ' .. words .. '\n' .. line)
end

-- Each part of Vantage that writes the game's code says on its first line which setting it is for, and Help names
-- that setting. The write itself is shared in core/code_patch.lua, so a part that writes is one that uses it.
local listing = assert(io.popen('dir /b "' .. (ADDON_DIR .. '/core'):gsub('/', '\\') .. '\\*.lua" 2>nul'))
local writers = 0
for name in listing:lines() do
    name = name:gsub('\r', '')
    local file = assert(io.open(ADDON_DIR .. '/core/' .. name, 'rb'))
    local text = file:read('*a')
    file:close()
    if name ~= 'code_patch.lua' and (text:find('VirtualProtect', 1, true) or text:find('require(\'core.code_patch\')', 1, true)) then
        local setting = text:match('^%-%- [^\n]-for (Replace the game\'s .-) on ')
        assert(setting, 'Fixture: core/' .. name .. ' says on its first line which setting it is for.')
        assert(line:find(setting, 1, true), 'Help names ' .. setting .. ', as core/' .. name .. ' changes the game.')
        writers = writers + 1
    end
end
listing:close()
assert(writers >= 2, 'Fixture: the scan finds the parts that write the game\'s code: ' .. writers)
return 'Help names both settings that change the game, what each hides and that Vantage puts it back'
