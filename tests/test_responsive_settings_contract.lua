local defaults, profiles = require('ui.defaults'), require('core.profiles');
local s = defaults.make();
local p = s.party_ui;
assert(p.native.snap, 'Fresh strips snap.');
for _, group in ipairs(p.groups) do
    assert(not group.native_detached and group.native_side == 'default');
    assert(group.detached_width == 420 and group.detached_height == 240);
end;
p.native.snap = 'bad';
p.groups[1].native_detached, p.groups[1].native_side = 'bad', 'up';
p.groups[1].detached_x, p.groups[1].detached_y = 0 / 0, -50;
p.groups[1].detached_width, p.groups[1].detached_height = 0, 20000;
s = defaults.tidy(s); p = s.party_ui;
assert(p.native.snap, 'A value that is no switch loads as snapping.');
assert(not p.groups[1].native_detached and p.groups[1].native_side == 'default');
assert(p.groups[1].detached_x == 40 and p.groups[1].detached_y == 0);
assert(p.groups[1].detached_width == 40 and p.groups[1].detached_height == 16000);
p.native.snap = false;
for i, group in ipairs(p.groups) do
    group.native_detached, group.native_side = true, i == 2 and 'left' or 'right';
    group.detached_x, group.detached_y = 100 * i, 80 * i;
    group.detached_width, group.detached_height = 300 + i, 250 + i;
end;
local named = profiles.capture(s);
local full = profiles.capture_layout(s, 'presentation').presentation.party_ui;
local placement = profiles.capture_layout(s, 'placement').party_ui;
for _, source in ipairs({ named.party_ui, full, placement }) do
    assert(not source.native.snap);
    for i, group in ipairs(source.groups) do
        assert(group.native_detached and group.native_side == p.groups[i].native_side);
        assert(group.detached_x == 100 * i and group.detached_y == 80 * i);
        assert(group.detached_width == 300 + i and group.detached_height == 250 + i);
    end;
end;
local saved = profiles.new(MOCK_INSTALL_PATH .. '/config/addons/vantage');
local target = defaults.make();
target.party_ui.locked, target.party_ui.name_display = true, 'job';
assert(saved:save_layout(s, 'placement') and saved:load_layout(target, 'placement'));
assert(target.party_ui.locked and target.party_ui.name_display == 'job', 'Placement imports preserve local lock and content.');
assert(target.party_ui.groups[3].detached_height == 253);
assert(not target.party_ui.native.snap);
local window = require('ui.settings_window');
local function finds(query, label)
    for _, result in ipairs(window.search(query)) do if result.tab == 'Display' and result.label == label then return true; end; end;
    return false;
end;
local SNAP, BACK = "Snap back beside the game's list when released", 'Put party buffs back beside the party list';
-- Before the window opens there are no settings to go by, so no group counts as in a panel of its own, and what only
-- a panel of its own uses isn't drawn. Its names and other words find each group's switch for that, not the controls.
local only_panels = { { SNAP, SNAP }, { 'Snap panels of their own to game windows', SNAP }, { 'Snap buff panels to game windows', SNAP },
    { BACK, BACK }, { 'Reattach panels of their own', BACK }, { 'Reattach buff panels', BACK } };
for _, entry in ipairs(only_panels) do
    assert(finds(entry[1], 'Your party in a panel of its own') and not finds(entry[1], entry[2]), 'Before opening, ' .. entry[1] .. ' finds the switches.');
end;
assert(not finds('native detached wrap', SNAP), 'Before opening, their keywords find nothing hidden.');
assert(#window.search('settings move title') > 0, 'Controls are searchable before opening: settings move title');
-- Opened on Home with every group in a panel of its own, they are found before their page is opened, by their names
-- and keywords.
target.window.open, target.window.tab = true, 'Home';
window.draw(target, require('ui.hud').sample(100), { changed = function() end, save = function() return true; end });
only_panels[#only_panels + 1] = { 'native detached wrap', SNAP };
for _, entry in ipairs(only_panels) do
    assert(finds(entry[1], entry[2]), 'With the groups in panels of their own, ' .. entry[1] .. ' finds ' .. entry[2] .. ' before its page is opened.');
end;
target.window.open, target.window.tab, target.party_ui.locked = true, 'Display', false;
require('ui.panel_frame').open('party_ui', 'place');
local function draw() window.draw(target, require('ui.hud').sample(100), { changed = function() end, save = function() return true; end }); end;
MOCK.clicks[SNAP .. '##frame'] = true;
draw(); assert(target.party_ui.native.snap);
MOCK.clicks[BACK .. '##frame'] = true;
MOCK.clicks['Put moved groups back##frame'] = true;
draw();
for i, group in ipairs(target.party_ui.groups) do
    assert(not group.native_detached and group.native_side == 'default' and group.native_x == 0 and group.native_y == 0);
    assert(group.detached_width == 300 + i and group.detached_height == 250 + i, 'Reattaching retains the chosen detached dimensions.');
end;
assert(#MOCK.commands == 0);
