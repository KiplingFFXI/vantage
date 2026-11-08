-- A section's saved open state is kept under its name, or its key after ## when it has one: Member order is saved as
-- Detached panel members, and one saved open comes back open.
local defaults, hud = require('ui.defaults'), require('ui.hud');
local window, imgui = require('ui.settings_window'), require('imgui');
local s = defaults.tidy(defaults.make());
s.window.open, s.window.tab = true, 'Display';
s.window.sections['Party & alliance/Detached panel members'] = true;
s.party_ui.enabled, s.party_ui.groups[1].native_detached = true, true;
require('ui.panel_frame').open('party_ui', 'place');
local next_open, open = false, {};
imgui.SetNextItemOpen = function(value) next_open = value; end;
imgui.CollapsingHeader = function(label) open[label:match('^(.-)##') or label] = next_open; return next_open; end;
local view = hud.sample(100);
view.context = { valid = true, job = 3, party = {}, entities = {} };
local cb = { now = function() return 100; end, save = function() return true; end, editor_changed = function() end,
    changed = function() end, reset = function() return true; end, sound_files = function() return {}; end };
window.draw(s, view, cb);
assert(open['Member order'] == true, 'Member order opens from its key: ' .. tostring(open['Member order']));
return 'A section saved open comes back open';
