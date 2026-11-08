-- The party list strips are the only party display: only the strips beside the game's party list draw, and the game
-- windows stay shown. /vg party show turns them on as one Undo step, and profiles and shared layouts carry the strip
-- places.
local store, defaults = require('core.store'), require('ui.defaults');
local equal = require('core.customization').equal;
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 1, job_name = 'WAR',
    self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['ui.hud'] = { draw = function() end, draw_notices = function() end, cancel_gesture = function() end };
package.loaded['ui.settings_window'] = { draw = function() end };
local roster = { valid = true, id = 1001, zone = 102,
    members = { { id = 1001, slot = 0, group = 1, name = 'Tester', active = true, available = true } } };
package.loaded['core.roster'] = { read = function() return store.copy(roster); end };
local events, native_draws, draw_error = {}, 0, false;
local overlay_cancels = 0;
-- Vantage hides no game party window, so the game windows stay shown whatever the settings say.
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end,
    status = function() return { available = true }; end,
};
package.loaded['ui.native_party_hud'] = {
    draw = function()
        native_draws = native_draws + 1;
        events[#events + 1] = 'native';
        if draw_error then error('Fixture native overlay error'); end
        return false, {}, {};
    end,
    cancel_layout_gesture = function() overlay_cancels = overlay_cancels + 1; end,
};
assert(store.write(require('core.identity').root():gsub('[\\/]+$', '') .. '/Tester_1001/settings.json', defaults.make()), 'Fixture: the save.');
local app = dofile(ADDON_DIR .. '/vantage.lua');
local function command(text) local event = { command = text }; MOCK.fire('command', event); return event; end
local function frame() events = {}; MOCK.frame(0.2); end
MOCK.fire('load'); app.refresh(0);
local before_show = store.copy(app.state.settings.party_ui);
command('/vg party show');
local p = app.state.settings.party_ui;
assert(p.enabled and not p.preview, '/vg party show turns the strips on.');
assert(overlay_cancels > 0, 'Turning the strips on ends a strip layout gesture.');
local persisted = assert(store.read(app.state.path));
assert(persisted.party_ui.enabled, 'The saved file holds the strips on.');
frame();
assert(#events == 1 and events[1] == 'native', 'Only the strips draw.');
command('/vg undo');
assert(equal(before_show, app.state.settings.party_ui), 'One undo restores the prior party settings.');
command('/vg redo'); frame();
assert(app.state.settings.party_ui.enabled and events[1] == 'native');
draw_error = true; frame();
assert(events[#events] == 'native' and app.state.problem and app.state.problem:find('Fixture native overlay error', 1, true),
    'A strip exception is reported and draws nothing else in its place.');
draw_error = false; frame(); assert(events[1] == 'native');

local invalid_before = store.copy(app.state.settings.party_ui);
command('/vg party show extra');
assert(equal(invalid_before, app.state.settings.party_ui), 'Unexpected arguments cannot partially apply show.');
assert(MOCK.printed[#MOCK.printed]:find('Usage: /vg party [config|show|hide|preview|live|lock|unlock]', 1, true),
    'The usage line says what to type.');
command('/vg party hide'); command('/vg alliance show');
assert(app.state.settings.party_ui.enabled, '/vg alliance show turns the strips on too.');
MOCK.fire('unload');
assert(#MOCK.commands == 0, 'Mode and layout commands issue no gameplay commands');

local profiles = require('core.profiles');
local saved = profiles.new(MOCK_INSTALL_PATH .. '/config/addons/vantage');
local source = defaults.make();
source.party_ui.native = { side = 'right', gap = 12, width = 385, snap = true };
for i = 1, 3 do source.party_ui.groups[i].native_x, source.party_ui.groups[i].native_y = -20 * i, 15 * i; end
assert(saved:save_new('Native fitted', source));
local named = defaults.make(); assert(saved:load('Native fitted', named));
assert(named.party_ui.groups[3].native_x == -60 and named.party_ui.native.side == 'right', 'Named profiles retain the native offsets.');

for _, scope in ipairs({ 'placement', 'presentation' }) do
    local captured = profiles.capture_layout(source, scope);
    local content = scope == 'presentation' and captured.presentation.party_ui or captured.party_ui;
    assert(content.native.side == 'right' and content.groups[2].native_x == -40 and content.groups[2].native_y == 30);
    local receiver = defaults.make();
    receiver.party_ui.enabled = true;
    assert(saved:save_layout(source, scope) and saved:load_layout(receiver, scope));
    assert(receiver.party_ui.enabled, 'Shared ' .. scope .. ' keeps the receiving character display switch');
    assert(receiver.party_ui.native.side == 'right' and receiver.party_ui.native.width == 385
        and receiver.party_ui.native.gap == 12);
    for i = 1, 3 do assert(receiver.party_ui.groups[i].native_x == -20 * i and receiver.party_ui.groups[i].native_y == 15 * i); end
    receiver.party_ui.native.width = 200;
    receiver.party_ui.groups[1].native_x = 999;
    assert(source.party_ui.native.width == 385 and source.party_ui.groups[1].native_x == -20, 'Shared settings do not alias their source');
end
return 'Only the party list strips draw, /vg party show undo, and strip places in shared layouts';
