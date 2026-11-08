-- What the game doesn't send Pet, Party cooldowns or Phantom Roll is said once, under What can be tracked on Help, and not
-- on their tabs.
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

-- Every limit those paragraphs gave stands once on Help.
draw('Help')
local help = table.concat(wrapped(), '\n')
local function once(text)
    local at, count = 1, 0
    while true do
        local found, ends = help:find(text, at, true)
        if not found then break end
        count, at = count + 1, ends + 1
    end
    assert(count == 1, ('Help says %q %d times.'):format(text, count))
end
for _, text in ipairs({
    'within 30 yalms of whoever acts',
    'A wear-off message goes only to its caster, so debuffs others put on a mob run on an estimate.',
    'estimated from the ability\'s base recast',
    'Merits can make some of them end sooner',
    'Vantage can\'t see a member\'s merits',
    'Pets\' moves are not counted',
    'it shows only what the game sent',
    'within 8 yalms of the Corsair, 16 with Luzaf\'s Ring',
    'Another Corsair\'s Double-Up time is estimated from their roll',
    'A job bonus is added only for a job Vantage sees in the party; gear can also add it at random',
    'the game sends no list of a pet\'s effects',
    'the ones Vantage saw land on it, and most of their times are estimates',
    'MP shows once the game gives the pet some',
    'your CHR, your level, the mob\'s level from a /check before the charm, and charm time gear',
    'Ready isn\'t in this era, so Sic shows on its own',
}) do once(text) end
print('page intros passed')
return true
