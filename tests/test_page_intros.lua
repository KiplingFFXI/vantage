-- What the game doesn't send Pet, Party cooldowns or Phantom Roll is said in the guide, which What can be tracked on Help
-- points to, and not on their tabs.
local app = dofile(ADDON_DIR .. '/vantage.lua')
local window, callbacks = require('ui.settings_window'), app.callbacks
local s = app.state.settings
s.window.open = true
local function draw(tab)
    s.window.tab = tab
    MOCK.imgui_calls = {}
    window.draw(app.state.settings, app.state.view, callbacks)
end
local function wrapped()
    local lines = {}
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'TextWrapped' then lines[#lines + 1] = call[2] end
    end
    return lines
end
local LIMITS = { 'yalms', 'Merits', 'merits', 'base recast', 'Luzaf', 'Double-Up time', 'job bonus', 'no list of a pet', 'MP shows once', 'CHR', 'Ready isn\'t' }
local panels = require('ui.panel_frame')
for _, id in ipairs({ 'cooldown_list', 'rolls', 'pet' }) do
    for _, tab in ipairs(panels.tabs) do
        panels.open(id, tab.key)
        draw('Display')
        for _, line in ipairs(wrapped()) do
            for _, word in ipairs(LIMITS) do
                assert(not line:find(word, 1, true), id .. ' leaves ' .. word .. ' to Help: ' .. line)
            end
        end
    end
end

-- Every limit those paragraphs gave stands in the guide, and Help points there.
local file = assert(io.open(ADDON_DIR .. '/../docs/GUIDE.md', 'rb'))
local guide = file:read('*a')
file:close()
for _, text in ipairs({
    'within 30 yalms of whoever acts',
    'it sends a wear-off message only to whoever cast the effect',
    'estimate from its base recast',
    'Merits can make some of them end sooner',
    'Vantage doesn\'t count pets\' moves',
    'A roll reaches party members within 8 yalms of the Corsair, or 16 with Luzaf\'s Ring',
    'estimates another Corsair\'s from their roll',
    'Vantage adds the job bonus only for a main job it sees in your party',
    'Gear can also add it at random',
    'The game sends no list of a pet\'s effects',
    'MP shows once the game gives the pet some',
    'with your CHR, your main level, the mob\'s level and the charm time gear',
    'Ready isn\'t in this era',
}) do assert(guide:find(text, 1, true), 'The guide says: ' .. text) end
draw('Help')
local help = table.concat(wrapped(), '\n')
assert(help:find('within 30 yalms of whoever acts', 1, true), 'Help keeps the 30 yalm limit.')
assert(help:find('Recasts, Party cooldowns, Phantom Roll and Pet each say what they can\'t see under their own heading in the guide.', 1, true),
    'Help points to the guide for the rest.')
print('page intros passed')
return true
