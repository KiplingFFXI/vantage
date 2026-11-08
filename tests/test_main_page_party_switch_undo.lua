-- The main page's Party list buffs switch through the real settings window and vantage.lua: it turns the buffs beside
-- the game party list on and, with every group off, shows Your party only, as one named Undo step.
local store = require('core.store');
local custom = require('core.customization');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 1, self_known = true,
    self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local timer_hud = require('ui.hud');
timer_hud.draw, timer_hud.draw_notices = function() end, function() end;
require('ui.native_party_hud').draw = function() return 0, {}; end;
local app = dofile(ADDON_DIR .. '/vantage.lua');
local function command(value) MOCK.fire('command', { command = value }); end;
local function frame(click)
    if click then MOCK.clicks[click] = true; end;
    MOCK.imgui_calls = {};
    MOCK.frame(0.11);
    assert(#MOCK.font_stack == 0);
    if click then assert(not MOCK.clicks[click], 'The control is on screen: ' .. click); end;
end;
app.refresh(0);
app.state.settings.window.open, app.state.settings.window.tab = true, 'Home';
frame(); frame();

app.callbacks.changed('before', 'Hide party strips');
local p = app.state.settings.party_ui;
p.enabled, p.preview = false, true;
for key in pairs(p.strips) do p.strips[key] = false; end;
app.callbacks.changed('after'); assert(app.callbacks.save()); frame();
local hidden_party, edits = store.copy(app.state.settings.party_ui), #app.state.history;
frame('Party list buffs##main_party_ui');
local visible_party = store.copy(app.state.settings.party_ui);
assert(visible_party.enabled and visible_party.preview
    and visible_party.strips.party and not visible_party.strips.alliance1 and not visible_party.strips.alliance2,
    'The switch shows Your party without turning on every group.');
assert(#app.state.history == edits + 1 and app.callbacks.history_status().undo_label == 'Party list buffs',
    'The switch is one named Undo step.');
command('/vg undo'); assert(custom.equal(app.state.settings.party_ui, hidden_party), 'One Undo restores the prior party selection and display.');
command('/vg redo'); assert(custom.equal(app.state.settings.party_ui, visible_party), 'One Redo shows them again.');
MOCK.fire('unload');
assert(#MOCK.commands == 0, 'The party switch issues no gameplay commands.');
