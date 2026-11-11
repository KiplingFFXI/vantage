local app, imgui = assert(PREVIEW.addon), require('imgui');
local copy, equal = require('core.store').copy, require('core.customization').equal;
local history_value = require('core.customization').history_value;
local s = app.state.settings;
s.window.tab, s.window.open, s.window.x, s.window.y = 'Recasts', true, 40, 40;
s.style.font, s.window_style.font_size = 'Agave', 36;
s.enabled, s.recast_display = true, 'combined';
s.panels.recasts.enabled, s.panels.recasts.locked = true, true;
local begin_child, checkbox = imgui.BeginChild, imgui.Checkbox;
imgui.BeginChild = function(label, ...)
    local visible = begin_child(label, ...);
    if label == '##settings_page' then
        local x, y = imgui.GetWindowPos(); local width, height = imgui.GetWindowSize();
        PREVIEW.body = { x=x, y=y, width=width, height=height, scroll=imgui.GetScrollY() };
    end;
    return visible;
end;
imgui.Checkbox = function(label, ...)
    local changed = checkbox(label, ...);
    if label == 'Locked##frame' then PREVIEW.lock_visible = imgui.IsItemVisible(); end;
    return changed;
end;
-- Taken once a fresh install has placed its displays (its first refresh with a screen), before any click.
local baseline;
local TABS, FIRST_ROW = 'When to show##frame_tab', 'A panel for each kind##frame_Show as_separate';
local function fits(label)
    local bounds = PREVIEW_PY.item_bounds(label);
    local win = app.state.settings.window;
    return bounds[2] >= math.max(win.y, PREVIEW.body.y) and bounds[4] <= math.min(win.y+win.height, PREVIEW.body.y+PREVIEW.body.height),
        table.concat(bounds, ',');
end;
function PREVIEW.compact_capture()
    app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
    assert(PREVIEW.body.height >= 80, 'Short menus retain a usable scroll area.');
    -- The page ends a line of text above the window's bottom edge, clear of the resize corners, so at this size the
    -- tabs' second line starts with its bottom cut off.
    local tabs = PREVIEW_PY.item_bounds(TABS);
    assert(tabs[2] >= PREVIEW.body.y and tabs[2] < PREVIEW.body.y+PREVIEW.body.height, 'The tabs start in view: '..table.concat(tabs, ','));
    local inside, bounds = fits(FIRST_ROW);
    assert(not inside, 'The first row starts below the fold, so only scrolling can bring it into view: '..bounds);
end;
function PREVIEW.compact_visible()
    assert(baseline, 'The fresh placement is done before the lock control is clicked.');
    assert(PREVIEW.body.scroll > 0, 'Wheel input scrolls the compact controls.');
    local inside, bounds = fits(FIRST_ROW);
    assert(inside, 'Scrolling brings the first row into view: '..bounds);
end;
function PREVIEW.compact_back()
    assert(PREVIEW.body.scroll == 0 and PREVIEW.lock_visible, 'The wheel goes back up to the lock control.');
    local inside, bounds = fits('Locked##frame');
    assert(inside, 'The whole lock control must fit before clicking: '..bounds);
end;
function PREVIEW.compact_check(locked, edits)
    local expected = copy(baseline);
    expected.panels.recasts.locked = locked;
    assert(equal(history_value(app.state.settings), expected), 'Compact layout and scrolling preserve every other choice, including preview docking.');
    assert(#app.state.history == edits and not app.state.transaction, 'Only explicit lock clicks create edits.');
end;
return function()
    MOCK.frame(1/60);
    if not baseline and not app.state.place_fresh then baseline = history_value(app.state.settings); end;
    PREVIEW.settings = app.state.settings;
    if PREVIEW.frame == PREVIEW.last_frame then
        PREVIEW.compact_check(true, 2);
        assert(#MOCK.commands == 0);
        PREVIEW.log('Compact settings scroll, lock and customization checks passed');
    end;
end;
