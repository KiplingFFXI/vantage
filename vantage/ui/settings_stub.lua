-- What vantage.lua calls on the settings window: draw, blocks_input, area, cancel_resize and lists_recasts. The window
-- itself (ui/settings_window.lua, with the code it loads) is loaded the first time it opens, not when the addon loads.
-- Every call gives the answer the window would: while it is shut and not yet loaded it has nothing to draw, takes no
-- mouse, has no place, has no resize to end and lists no recasts, and once it is loaded every call goes to it.
local stub = {}
-- The window's name in package.loaded. The requires below spell it out, so the release check
-- (tools/release_files.py) reaches what the window loads.
local NAME = 'ui.settings_window'
-- Why the window could not load. blocks_input then leaves it be, and the next draw tries again.
local failed

-- The window once it is loaded. A load that failed leaves require's own mark there, which is not the window.
local function loaded()
    local window = package.loaded[NAME]
    if type(window) == 'table' then return window end
end

function stub.draw(s, view, cb)
    local window = loaded()
    if not window then
        if not s.window.open then return end
        -- An error here stops the window and is said once, as a page error is (vantage.lua runs this in pcall).
        -- The mark a failed load left is cleared, so a command that opens the window again tries the load again.
        if package.loaded[NAME] ~= nil then package.loaded[NAME] = nil end
        local ok, value = pcall(require, 'ui.settings_window')
        if not ok then failed = value; error(value, 0) end
        failed, window = nil, value
    end
    return window.draw(s, view, cb)
end

function stub.blocks_input(s, x, y, shift, typing)
    local window = loaded()
    if not window then
        -- A shut window takes no mouse, so it isn't loaded for that. One that could not load isn't drawn either.
        if not s or not s.window.open or failed then return false end
        local ok, value = pcall(require, 'ui.settings_window')
        if not ok then failed = value; return false end
        window = value
    end
    if not window.blocks_input then return false end
    return window.blocks_input(s, x, y, shift, typing)
end

-- Where the open window is, for the edit mode bar. Opened and not yet loaded, it is at its saved place, as the window
-- would say before its first draw. One that could not load isn't drawn.
function stub.area(s)
    local window = loaded()
    if window then return window.area and window.area(s) end
    if s and s.window.open and not failed then return s.window end
end

function stub.cancel_resize()
    local window = loaded()
    if window and window.cancel_resize then return window.cancel_resize() end
end

-- Whether the window's last draw listed your recasts to pick from.
function stub.lists_recasts(s)
    local window = loaded()
    return window ~= nil and window.lists_recasts ~= nil and window.lists_recasts(s)
end

return stub
