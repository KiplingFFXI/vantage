-- /vg recasts show resumes paused timer panels in the same Undo step, as the main page's recast ticks do. /vg recasts
-- hide leaves a pause as it is.
local defaults = require('ui.defaults');
local SNAP = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 1, self_known = true, self_effects = {}, party = {}, entities = {} };
require('app_fixture')(SNAP);
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, update = function() end,
    status = function() return { active = false }; end, restore = function() return true; end, suspend = function() return true; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
local function command(text) local event = { command = text }; MOCK.fire('command', event); assert(event.blocked); end;
MOCK.fire('load'); app.refresh(0);

for _, display in ipairs({ 'separate', 'combine' }) do
    command('/vg recasts ' .. display);
    command('/vg recasts hide');
    command('/vg set enabled false');
    assert(not app.state.settings.enabled, 'Fixture: the timer panels are paused.');
    local steps = app.callbacks.history_status().undo;
    command('/vg recasts show');
    local s = app.state.settings;
    assert(s.enabled and defaults.any_timer_on(s), '/vg recasts show resumes the timer panels (' .. display .. ').');
    for _, key in ipairs(defaults.recast_panel_order(s)) do assert(defaults.panel_enabled(s, key), 'Fixture: ' .. key .. ' is on.'); end;
    assert(app.callbacks.history_status().undo == steps + 1, 'As one Undo step.');
    command('/vg undo');
    s = app.state.settings;
    assert(not s.enabled and not defaults.panel_enabled(s, defaults.recast_panel_order(s)[1]), 'Undo pauses them again, with the recasts off.');
end;

-- With the recasts already on, the resume is what the command changes, as its own step.
command('/vg recasts show');
command('/vg set enabled false');
local steps = app.callbacks.history_status().undo;
command('/vg recasts show');
assert(app.state.settings.enabled and app.callbacks.history_status().undo == steps + 1, 'Showing recasts already on resumes them too.');

-- Hiding them leaves the pause alone.
command('/vg set enabled false');
command('/vg recasts hide');
assert(not app.state.settings.enabled, '/vg recasts hide keeps the timer panels paused.');
MOCK.fire('unload');
return '/vg recasts show resumes paused timer panels';
