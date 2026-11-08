-- The member labels a panel of its own shows: Full name, Short name or Job, and the short name's length. They load
-- bounded, travel with profiles and shared presentation, not with shared placement, and Apply setup keeps them.
local defaults = require('ui.defaults');
local profiles, custom = require('core.profiles'), require('core.customization');
local s = defaults.make();
assert(s.party_ui.name_display == 'full' and s.party_ui.name_length == 8);
for _, mode in ipairs({ 'full', 'short', 'job' }) do
    s.party_ui.name_display = mode;
    assert(defaults.tidy(s).party_ui.name_display == mode);
end;
s.party_ui.name_display, s.party_ui.name_length = 'bad', 0 / 0;
s = defaults.tidy(s);
assert(s.party_ui.name_display == 'full' and s.party_ui.name_length == 8);
for _, entry in ipairs({ { 1, 3 }, { 99, 16 }, { 6.9, 6 } }) do
    s.party_ui.name_length = entry[1];
    s = defaults.tidy(s);
    assert(s.party_ui.name_length == entry[2]);
end;
s.party_ui.name_display, s.party_ui.name_length = 'short', 5;
local capture = profiles.capture(s).party_ui;
assert(capture.name_display == 'short' and capture.name_length == 5);
local presentation = profiles.capture_layout(s, 'presentation').presentation.party_ui;
assert(presentation.name_display == 'short' and presentation.name_length == 5);
local placement = profiles.capture_layout(s, 'placement').party_ui;
assert(placement.name_display == nil and placement.name_length == nil, 'Placement sharing does not change member wording choices.');
local saved = profiles.new(MOCK_INSTALL_PATH .. '/config/addons/vantage');
assert(saved:save_new('Short members', s));
local target = defaults.make();
assert(saved:load('Short members', target));
assert(target.party_ui.name_display == 'short' and target.party_ui.name_length == 5);
target = defaults.make();
assert(saved:save_layout(s, 'presentation') and saved:load_layout(target, 'presentation'));
assert(target.party_ui.name_display == 'short' and target.party_ui.name_length == 5);
for _, size in ipairs({ 'minimal', 'minimal_2x' }) do
    assert(require('setup_fixture').apply(target, { skin = 'keep', size = size }));
    assert(target.party_ui.name_display == 'short' and target.party_ui.name_length == 5, 'Apply setup keeps the member labels: ' .. size);
end;
custom.reset(target, 'party_ui');
assert(target.party_ui.name_display == 'full' and target.party_ui.name_length == 8);
local window = require('ui.settings_window');
local function finds(query, label)
    for _, result in ipairs(window.search(query)) do if result.panel == 'party_ui' and result.label == label then return true; end; end;
    return false;
end;
-- Before the window is opened it goes by a fresh save, where no group is in a panel of its own, and that's where the
-- wording choices show. Their names and search words find each group's switch for that, and not themselves.
for _, query in ipairs({ 'Member names', 'Member name display', 'Short name length', 'Abbreviated name length' }) do
    assert(finds(query, 'Your party in a panel of its own') and not finds(query, 'Member names') and not finds(query, 'Short name length'),
        'Before opening the panel, ' .. query .. ' finds the switches.');
end;
-- With a group in a panel of its own they are found by their names and keywords.
local shown = defaults.tidy(defaults.make());
shown.window.open, shown.party_ui.groups[1].native_detached = true, true;
window.draw(shown, require('ui.hud').sample(100), { changed = function() end, save = function() return true; end });
for _, entry in ipairs({ { 'Member name display', 'Member names' }, { 'Abbreviated name length', 'Member names' },
    { 'replace member name job', 'Member names' } }) do
    assert(finds(entry[1], entry[2]), 'With a group in a panel of its own, ' .. entry[1] .. ' finds ' .. entry[2]);
end;
assert(not finds('Abbreviated name length', 'Short name length'), 'Full names draw no length, so it is not found.');
shown.party_ui.name_display = 'short';
window.draw(shown, require('ui.hud').sample(100), { changed = function() end, save = function() return true; end, settings_revision = function() return 2; end });
assert(finds('Abbreviated name length', 'Short name length'), 'Short names draw it, and it is found.');
