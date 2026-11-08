local addon = assert(PREVIEW.addon, 'This fixture needs the full entrypoint.');
local settings = addon.state.settings;
settings.enabled, settings.preview, settings.party_ui.enabled = false, false, false;
settings.window.x, settings.window.y, settings.window.width, settings.window.height = 100, 100, 800, 600;
settings.window.tab, settings.window.peek = 'Help', true;
settings.window.sections['Help/Kept section'] = true;
addon.state.history, addon.state.redo, addon.state.transaction, addon.state.dirty = {}, {}, nil, false;
local before, after, saves = 0, 0, 0;
local changed, save = addon.callbacks.changed, addon.callbacks.save;
local imgui = require('imgui');
local begin = imgui.Begin;
imgui.Begin = function(name, open, flags, ...)
    if name == 'Vantage##settings' then PREVIEW.settings_flags = flags; end;
    return begin(name, open, flags, ...);
end;
-- Forwards every argument: a settings window resize passes the window geometry flag after the scope.
addon.callbacks.changed = function(stage, label, ...)
    if stage == 'before' then
        before = before + 1;
        PREVIEW.resize_label = label;
    else after = after + 1; end;
    return changed(stage, label, ...);
end;
addon.callbacks.save = function(...)
    saves = saves + 1;
    return save(...);
end;
PREVIEW.resize_counts = function() return before, after, saves; end;
PREVIEW.expect_geometry = function(x, y, width, height, context)
    local actual = addon.state.settings.window;
    assert(actual.x == x and actual.y == y and actual.width == width and actual.height == height,
        (context or 'Settings geometry') .. ': ' .. actual.x .. ',' .. actual.y .. ',' .. actual.width .. ',' .. actual.height);
end;
PREVIEW.expect_window = function(width, height)
    assert(PREVIEW_PY.window_width('Vantage##settings') == width and PREVIEW_PY.window_height('Vantage##settings') == height,
        'The visible settings window did not follow the drag.');
end;
return function()
    MOCK.frame(1 / 60);
    PREVIEW.settings = addon.state.settings;
    if PREVIEW.frame == PREVIEW.last_frame then
        assert(#MOCK.commands == 0, 'Resizing must not send game commands.');
        PREVIEW.log('All settings edges, Shift peek, typing, ordinary resizing and Undo/Redo passed.');
    end;
end;
