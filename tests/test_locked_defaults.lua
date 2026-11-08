-- The displays Vantage draws start locked and keep a saved lock.
local defaults, party = require('ui.defaults'), require('ui.party_defaults');
local store, profiles, custom = require('core.store'), require('core.profiles'), require('core.customization');
local function set_locks(settings, value)
    settings.party_ui.locked, settings.alerts.notice_locked = value, value;
    for _, panel in pairs(settings.panels) do panel.locked = value; end;
end;
local function check_locks(settings, expected, message)
    assert(settings.party_ui.locked == expected and settings.alerts.notice_locked == expected, message);
    for _, panel in pairs(settings.panels) do assert(panel.locked == expected, message); end;
end;

check_locks(defaults.make(), true, 'Every new persistent display starts locked.');
check_locks(defaults.tidy({}), true, 'Missing display settings start locked.');
assert(party.make().locked and party.tidy({}).locked);
local settings = defaults.make();
set_locks(settings, nil);
local tidied = defaults.tidy(settings);
check_locks(tidied, true, 'Missing lock keys inherit the locked default.');
for _, invalid in ipairs({ 'false', 0, 1, {} }) do
    settings = defaults.make();
    set_locks(settings, invalid);
    tidied = defaults.tidy(settings);
    check_locks(tidied, true, 'Invalid lock types inherit the locked default.');
    assert(party.tidy({ locked = invalid }).locked);
end;

local saved = profiles.new(MOCK_INSTALL_PATH .. '/config/addons/vantage');
for _, lock in ipairs({ false, true }) do
    settings = defaults.make();
    set_locks(settings, lock);
    settings.party_ui.groups[1].native_x, settings.panels.self_buffs.x, settings.alerts.notice_x = 33, 612, 513;
    check_locks(defaults.tidy(store.copy(settings)), lock, 'Explicit saved booleans survive normalization.');
    assert(party.tidy({ locked = lock }).locked == lock);
    local path = MOCK_INSTALL_PATH .. '/config/addons/vantage/locks.json';
    assert(store.write(path, settings));
    check_locks(defaults.tidy(assert(store.read(path))), lock, 'Character settings retain explicit locks after a save/read.');
    check_locks(profiles.capture(settings), lock, 'Named profile capture retains explicit lock choices.');
    local name = lock and 'Locked layout' or 'Unlocked layout';
    assert(saved:save_new(name, settings));
    local receiver = defaults.make();
    set_locks(receiver, not lock);
    assert(saved:load(name, receiver));
    check_locks(receiver, lock, 'Named profile load retains its saved lock choices.');
    for _, scope in ipairs({ 'placement', 'presentation' }) do
        receiver = defaults.make();
        set_locks(receiver, not lock);
        assert(saved:save_layout(settings, scope) and saved:load_layout(receiver, scope));
        check_locks(receiver, not lock, 'Shared ' .. scope .. ' keeps recipient lock choices.');
        assert(receiver.party_ui.groups[1].native_x == 33 and receiver.panels.self_buffs.x == 612,
            'Shared layouts still apply their intended geometry.');
    end;
    for _, size in ipairs({ 'minimal', 'minimal_2x' }) do
        local config = store.copy(settings);
        assert(require('setup_fixture').apply(config, { size = size, skin = 'keep' }));
        check_locks(config, lock, 'Setup sizes preserve explicit lock choices.');
    end;
end;

for _, scope in ipairs({ 'party_ui', 'alerts', 'all' }) do
    settings = defaults.make();
    set_locks(settings, false);
    settings = assert(custom.reset(settings, scope));
    assert(settings.party_ui.locked == (scope == 'party_ui' or scope == 'all'));
    assert(settings.alerts.notice_locked == (scope == 'alerts' or scope == 'all'));
    for _, panel in pairs(settings.panels) do assert(panel.locked == (scope == 'all')); end;
end;
local reset_ok, reset_why = custom.reset(defaults.make(), 'typo');
assert(not reset_ok and reset_why:find('was not found', 1, true) and not reset_why:lower():find('unknown', 1, true),
    'A reset of something that isn\'t there says so plainly.');
assert(#MOCK.commands == 0, 'Default and profile normalization send no game commands.');
