local textures = {}
for _, name in ipairs({ 'newtex', 'corner', 'hfr1', 'vfr1' }) do
    textures[name] = { id = name, width = name == 'newtex' and 128 or 32, height = name == 'newtex' and 128 or 32 }
end
local available = false
package.loaded['ui.client_assets'] = {
    texture = function(kind, name) return available and kind == 'window' and textures[name] or nil end,
}
local hud, defaults, appearance = require('ui.hud'), require('ui.defaults'), require('ui.appearance')
local s = defaults.make()
s.alerts.notice_x, s.alerts.notice_y, s.alerts.notice_width, s.alerts.notice_height = 51, 73, 420, 200
s.style.text_shadow = false
local view = { context = {}, notices = {
    { message = 'Haste ends soon', visual = true, ends = 60 },
    { message = 'This is not a visual notice', visual = false, ends = 60 },
} }
local function draw()
    MOCK.imgui_calls = {}
    hud.draw_notices(view, s, 1, {})
    local result = { fills = 0, images = 0, text = {} }
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddRectFilled' then result.fills = result.fills + 1 end
        if call[1] == 'draw:AddImage' then result.images = result.images + 1 end
        if call[1] == 'draw:AddText' then result.text[#result.text + 1] = call[#call] end
        if call[1] == 'SetNextWindowPos' then result.x, result.y = call[2][1], call[2][2] end
        if call[1] == 'SetNextWindowSize' then result.width, result.height = call[2][1], call[2][2] end
    end
    result.caption = table.concat(result.text, '|')
    return result
end
local framed = draw()
assert(framed.fills == 2 and framed.images == 0, 'A custom theme retains its notice background and warning accent')
assert(framed.caption == 'Haste ends soon', 'Notice filtering is unchanged')
appearance.apply(s, 'Minimal', { matching = false })
local minimal = draw()
assert(minimal.fills == 0 and minimal.images == 0, 'Minimal notices do not retain a background or accent')
assert(minimal.caption == framed.caption and minimal.x == framed.x and minimal.y == framed.y
    and minimal.width == framed.width and minimal.height == framed.height, 'Frameless styling preserves notice text and geometry')
assert(s.alerts.notice_x == 51 and s.alerts.notice_y == 73 and s.alerts.notice_width == 420 and s.alerts.notice_height == 200)
assert(view.notices[1].ends == 60 and view.notices[2].visual == false, 'Drawing never alters alert lifetime or visibility')
-- Across on Centered puts them in the middle of the screen, and a load keeps it.
s.alerts.notice_x = -1
local centered = draw()
assert(centered.x == math.floor((1600 - centered.width) / 2), 'Centered is the middle of the screen: ' .. tostring(centered.x))
assert(s.alerts.notice_x == -1 and defaults.tidy(defaults.copy(s)).alerts.notice_x == -1, 'Drawing and a load keep Centered.')
s.alerts.notice_x = 51
appearance.apply(s, 'Ember', { matching = false })
assert(draw().fills == 2, 'A later framed preset restores both background and accent')
s.style.background = false
assert(draw().fills == 0, 'The independent background toggle also hides notice background and accent')
appearance.apply(s, 'Original FFXI', { matching = false })
assert(draw().fills == 2, 'Missing native textures retain the framed theme fallback')
available = true
local original = draw()
assert(original.images > 0 and original.fills == 1, 'Available native textures paint the notice frame and retain the warning accent')
s.style.background = false
local border_only = draw()
assert(border_only.images > 0 and border_only.fills == 0, 'Disabling the background keeps a separately enabled native border')
s.style.minimal = true
assert(draw().images == 0 and draw().fills == 0, 'Minimal also suppresses available native frame artwork')
s.alerts.muted = true
assert(draw().caption == '', 'Muted notices remain hidden')
assert(#MOCK.commands == 0 and MOCK.saved == 0, 'Appearance drawing does not issue commands or save settings')
