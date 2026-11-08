-- Hold Shift to see through settings is on for a new profile, and a saved choice stays as it is, off or on. Seeing
-- through only lets the mouse reach what is under the window: it needs Shift, typing stops it, and a lock still holds.
local defaults = require('ui.defaults');
assert(defaults.make().window.peek == true, 'A new profile sees through the window while Shift is held.');
assert(defaults.tidy(defaults.make()).window.peek == true, 'Tidying a new profile keeps it on.');
local saved = defaults.make();
saved.window.peek = false;
assert(defaults.tidy(saved).window.peek == false, 'A saved off stays off.');
saved.window.peek = true;
assert(defaults.tidy(saved).window.peek == true, 'A saved on stays on.');

dofile(ADDON_DIR .. '/vantage.lua');
local window = require('ui.settings_window');
local s = defaults.tidy(defaults.make());
s.window.open, s.window.x, s.window.y, s.window.width, s.window.height = true, 100, 100, 800, 600;
assert(window.blocks_input(s, 500, 400, false, false), 'Without Shift the window takes the mouse.');
assert(window.blocks_input(s, 500, 400, true, true), 'While typing it takes the mouse too.');
assert(not window.blocks_input(s, 500, 400, true, false), 'With Shift the mouse reaches what is under it.');
s.window.peek = false;
assert(window.blocks_input(s, 500, 400, true, false), 'Turned off, Shift does nothing.');

-- The resets that take in the window's navigation give the default back. The others leave a choice alone.
local custom = require('core.customization');
local function reset(scope)
    local changed = defaults.tidy(defaults.make());
    changed.window.peek = false;
    return assert(custom.reset(changed, scope)).window.peek;
end;
for _, scope in ipairs({ 'navigation', 'all' }) do assert(reset(scope) == true, 'Reset ' .. scope .. ' turns it back on.'); end;
for _, scope in ipairs({ 'appearance', 'panels', 'effects', 'party_ui', 'overhead' }) do
    assert(reset(scope) == false, 'Reset ' .. scope .. ' leaves it alone.');
end;
return true;
