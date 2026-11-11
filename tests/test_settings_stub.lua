-- The settings window loads the first time it opens (ui/settings_stub.lua). Until then nothing loads it, and the
-- addon draws, takes the mouse, ends gestures and tells the edit mode bar where the window is as it does with the window
-- loaded. It loads once, and a window that can't load is reported once and stopped, as a page that fails is.
local loads, broken = 0, nil
local source = ADDON_DIR .. '/ui/settings_window.lua'
package.preload['ui.settings_window'] = function(...)
    loads = loads + 1
    if broken then error(broken, 0) end
    return assert(loadfile(source))(...)
end
local app = dofile(ADDON_DIR .. '/vantage.lua')
local state, callbacks = app.state, app.callbacks
local function command(text) local e = { command = text }; MOCK.fire('command', e); assert(e.blocked); end
local function frames(count) for _ = 1, count or 3 do MOCK.frame(0.2) end end
local function said(text)
    local count = 0
    for _, line in ipairs(MOCK.printed) do if line:find(text, 1, true) then count = count + 1 end end
    return count
end

MOCK.fire('load'); app.refresh(0)
command('/vantage show')
frames()
assert(state.ready ~= false and not state.settings.window.open, 'Fixture: the displays are up with the window shut.')
-- Points inside, on the title, on the corner grip and outside the window, with and without Shift, typing and peeking.
local s = state.settings
local w = s.window
local points = { { w.x + w.width / 2, w.y + w.height / 2 }, { w.x + 40, w.y + 4 }, { w.x + w.width - 2, w.y + w.height - 2 },
    { w.x - 50, w.y - 50 }, { w.x + w.width + 400, w.y + 10 } }
local function each_case(fn)
    s = state.settings
    for _, peek in ipairs({ false, true }) do
        for _, point in ipairs(points) do
            for _, shift in ipairs({ false, true }) do
                for _, typing in ipairs({ false, true }) do
                    s.window.peek = peek
                    fn(point[1], point[2], shift, typing, peek)
                end
            end
        end
    end
    s.window.peek = false
end
each_case(function(x, y, shift, typing)
    assert(callbacks.settings_blocks_input(x, y, shift, typing) == false, 'A shut window takes no mouse.')
end)
assert(loads == 0 and package.loaded['ui.settings_window'] == nil, 'Drawing, the mouse and gestures with the window shut load nothing.')

-- The same answers as the window's own, from a copy loaded outside the addon.
local stub = require('ui.settings_stub')
local shut_copy = assert(loadfile(source))()
assert(stub.blocks_input(nil, 1, 1, false, false) == shut_copy.blocks_input(nil, 1, 1, false, false))
each_case(function(x, y, shift, typing)
    assert(stub.blocks_input(s, x, y, shift, typing) == shut_copy.blocks_input(s, x, y, shift, typing))
end)
assert(stub.draw(s, state.view, callbacks) == nil and stub.cancel_resize() == nil)
assert(stub.area(s) == nil and shut_copy.area(s) == nil and callbacks.settings_area() == nil, 'A shut window has no place.')
assert(stub.lists_recasts(s) == false and shut_copy.lists_recasts(s) == false, 'A shut window lists no recasts.')
assert(loads == 0, 'Asking a shut window loads nothing.')

-- Opened and not yet drawn, the window answers from its saved place, as a window loaded with the addon does.
command('/vg')
assert(s == state.settings and s.window.open and not state.settings_window_shown)
local open_copy = assert(loadfile(source))()
local inside = 0
each_case(function(x, y, shift, typing)
    local answer = stub.blocks_input(s, x, y, shift, typing)
    assert(answer == open_copy.blocks_input(s, x, y, shift, typing), 'Before its first draw the window answers as its own copy.')
    if answer then inside = inside + 1 end
end)
assert(inside > 0 and loads == 1, 'The first open loads the window once.')
assert(stub.area(s) == open_copy.area(s) and callbacks.settings_area() == s.window, 'Before its first draw the window is at its saved place.')
local window = package.loaded['ui.settings_window']
assert(type(window) == 'table')
frames()
assert(state.settings_window_shown and loads == 1 and package.loaded['ui.settings_window'] == window, 'Drawing it loads nothing more.')

-- Loaded, every call goes to the window.
local trues, falses = 0, 0
each_case(function(x, y, shift, typing)
    local answer = callbacks.settings_blocks_input(x, y, shift, typing)
    assert(answer == window.blocks_input(s, x, y, shift, typing) and answer == stub.blocks_input(s, x, y, shift, typing))
    if answer then trues = trues + 1 else falses = falses + 1 end
end)
assert(trues > 0 and falses > 0, 'Fixture: the open window takes some points and not others.')
local area = callbacks.settings_area()
assert(area and area == window.area(s) and area == stub.area(s) and area.width == s.window.width, 'Drawn, it is where it was drawn.')
local real_draw, real_cancel = window.draw, window.cancel_resize
local draws, cancels = {}, 0
window.draw = function(settings, ...) draws[#draws + 1] = settings.window.open; return real_draw(settings, ...) end
window.cancel_resize = function(...) cancels = cancels + 1; return real_cancel(...) end
stub.cancel_resize()
assert(cancels == 1, 'Ending a gesture goes to the window.')
command('/vg')
frames(2)
assert(not s.window.open and #draws == 2 and draws[1] == false and draws[2] == false, 'Once loaded, a shut window is drawn as before.')
assert(cancels >= 3, 'A shut window that is drawn ends its resize, as before.')
each_case(function(x, y, shift, typing) assert(callbacks.settings_blocks_input(x, y, shift, typing) == false) end)
window.draw, window.cancel_resize = real_draw, real_cancel

-- A window that can't load is said once and stopped, takes no mouse, and a command that opens it tries it again.
package.loaded['ui.settings_window'] = nil
local broken_text = 'The settings window file is broken.'
broken = broken_text
local before = loads
command('/vg')
frames(4)
assert(said(broken_text) == 1 and said('The display could not update.') == 1, 'A window that cannot load is said once.')
assert(state.settings_stopped == true and loads > before, 'It is stopped after the load is tried.')
local tried = loads
frames(3)
each_case(function(x, y, shift, typing) assert(callbacks.settings_blocks_input(x, y, shift, typing) == false) end)
assert(stub.blocks_input(s, w.x + 20, w.y + 20, false, false) == false, 'A window that cannot load takes no mouse.')
assert(stub.area(s) == nil and callbacks.settings_area() == nil, 'Nor does it have a place.')
assert(loads == tried and said(broken_text) == 1, 'The stopped window is not loaded or said again.')
broken = nil
command('/vg')
assert(s.window.open == false, 'Fixture: /vg closes the stopped window.')
command('/vg')
frames(3)
assert(state.settings_window_shown and state.settings_stopped == nil, 'Opening it again loads and draws it.')
assert(type(package.loaded['ui.settings_window']) == 'table' and loads == tried + 1 and said(broken_text) == 1)
return true
