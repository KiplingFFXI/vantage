-- The settings window prepares each dropdown and tooltip it opens (skin.prepare_menu in ui/client_skin.lua), every
-- frame, so preparing makes no table or function. Its answers and calls stay as they were in each state.
local available = true
local textures = {}
for _, name in ipairs({ 'newtex', 'corner', 'hfr1', 'vfr1' }) do
    local size = name == 'newtex' and 128 or 32
    textures[name] = { id = name, width = size, height = size }
end
package.loaded['ui.client_assets'] = {
    texture = function(_, name) return available and textures[name] or nil end,
    status = function() return { available = available, reason = 'Test assets missing.' } end,
}
local skin, theme, defaults = require('ui.client_skin'), require('ui.theme'), require('ui.defaults')
local s = defaults.make()
require('original_skin_fixture')(s)
local original = theme.window(s)
theme.apply(s, 'Mint')
local mint = theme.window(s)
assert(original.theme == 'Original FFXI' and mint.theme ~= 'Original FFXI', 'Fixture: one stock skin look and one other.')

local alpha, alpha_value = 0, nil
local clip_max = 1600
local probe = {
    GetClipRectMin = function() return 0, 0 end,
    GetClipRectMax = function() return clip_max, 1200 end,
}
for _, name in ipairs({ 'PushClipRect', 'PopClipRect', 'AddImage', 'AddRectFilled', 'AddTriangleFilled' }) do
    probe[name] = function() error('The global drawlist is inspected only; it must not be painted.') end
end
local function set_alpha(value) alpha, alpha_value = alpha + 1, value end
local gui = { SetNextWindowBgAlpha = set_alpha, GetBackgroundDrawList = function() return probe end }

-- Each state: what prepare_menu answers and whether it sets the next background's opacity.
local states = {
    { name = 'Stock skin ready', look = original, answer = true, alpha = 1 },
    { name = 'No look', look = nil, answer = false, alpha = 0 },
    { name = 'Another theme', look = mint, answer = false, alpha = 0 },
    { name = 'Artwork missing', look = original, answer = false, alpha = 0, before = function() available = false end,
        after = function() available = true end },
    { name = 'Draw list unreadable', look = original, answer = false, alpha = 0, before = function() clip_max = 0 / 0 end,
        after = function() clip_max = 1600 end },
    { name = 'No opacity setter', look = original, answer = false, alpha = 0,
        before = function() gui.SetNextWindowBgAlpha = nil end, after = function() gui.SetNextWindowBgAlpha = set_alpha end },
}
local function run(state, count)
    if state.before then state.before() end
    for _ = 1, count do
        local before = alpha
        local answer = skin.prepare_menu(gui, state.look)
        assert(answer == state.answer and alpha - before == state.alpha, state.name)
    end
    if state.after then state.after() end
end
for _, state in ipairs(states) do
    run(state, 1)
    assert(state.alpha == 0 or alpha_value == 0, state.name .. ': only the next plain background is hidden.')
end

local function measure(state, count)
    jit.off(); jit.flush()
    run(state, 60)
    collectgarbage('collect'); collectgarbage('collect')
    collectgarbage('stop')
    run(state, 6)
    local before = collectgarbage('count')
    run(state, count)
    local each = (collectgarbage('count') - before) / count
    collectgarbage('restart')
    jit.on()
    return each
end
for _, state in ipairs(states) do
    local each = measure(state, 2000)
    assert(each < 0.0005, ('%s: preparing a menu makes %.4f KB each time; nothing expected'):format(state.name, each))
end
-- The count sees one small table made each time.
local made
local each = measure({ name = 'A table each time', look = original, answer = true, alpha = 1,
    before = function() gui.SetNextWindowBgAlpha = function(value) made = { value }; set_alpha(value) end end,
    after = function() gui.SetNextWindowBgAlpha = set_alpha end }, 2000)
assert(each >= 0.02 and made, ('One table each time shows as %.4f KB'):format(each))
return true
