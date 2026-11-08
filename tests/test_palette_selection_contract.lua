local defaults, common, party_theme = require('ui.defaults'), require('ui.theme'), require('ui.party_theme');
local custom, copy = require('core.customization'), require('core.store').copy;
assert(custom.equal(party_theme.names, common.names), 'Local palettes share the canonical catalog values.');
assert(party_theme.names ~= common.names, 'Catalog consolidation preserves the existing independent table.');
local original = common.names[1]; party_theme.names[1] = 'Temporary test palette';
assert(common.names[1] == original and party_theme.names[1] == 'Temporary test palette');
party_theme.names[1] = original;
for _, name in ipairs(party_theme.names) do assert(name ~= 'XI View', 'XI View artwork does not invent a second Original FFXI palette.'); end;

-- The party list buffs wear the timer panels' look, so neither the party nor a group has a palette of its own to pick,
-- on any tab of their page with every section open, and search names none.
local app, window, imgui = dofile(ADDON_DIR .. '/vantage.lua'), require('ui.settings_window'), require('imgui');
local s = defaults.make();
s.window.open = true;
s.party_ui.enabled = true;
app.state.settings = defaults.tidy(s);
setmetatable(app.state.settings.window.sections, { __index = function() return true; end });
local begun = {};
imgui.BeginCombo = function(label) begun[label] = true; return false; end;
local panels = require('ui.panel_frame');
for _, tab in ipairs(panels.tabs) do
    local current = app.state.settings;
    current.window.open, current.window.tab = true, 'Display';
    panels.open('party_ui', tab.key);
    window.draw(current, { rows={}, context={} }, app.callbacks);
    assert(#MOCK.font_stack == 0);
end;
assert(begun['##frame_Party buff icons'], 'Fixture: the page draws its choices.');
assert(not begun['##frame_Party skin'] and not begun['##frame_Group skin'], 'The party list buffs have no palette of their own to pick.');
local explained = {};
for _, result in ipairs(window.search('palette artwork')) do explained[result.label] = true; end;
assert(not explained['Party skin'] and not explained['Group skin'] and not explained['Spell information skin'],
    'Search names no party or group palette.');
assert(#MOCK.commands == 0);
return 'Shared palette catalogs stay one, and the party list buffs have no palette of their own.';
