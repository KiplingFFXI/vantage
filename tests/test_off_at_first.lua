-- The ready pulse, the recast tints, the party cooldown watch and the Target and Watched enemies panels' buff light
-- are off at first, like the overhead icons. Fresh settings have them off, and a save without their keys loads them
-- off, through the real vantage.lua. A save, a profile, shared presentation or an export that holds one on keeps
-- it on, and one that holds it off keeps it off. The watch starts with its strips on and the light with its glow on,
-- so turning either on shows them.
local defaults, store = require('ui.defaults'), require('core.store');
local profiles, share = require('core.profiles'), require('core.share');

-- Each switch of the four, by name.
local function switches(s)
    return { pulse = s.ready_pulse.enabled, mp = s.recast_tints.mp, spell_lock = s.recast_tints.spell_lock,
        ability_lock = s.recast_tints.ability_lock, watch = s.party_cooldowns.enabled,
        target_light = s.panels.target.dispel_light, watch_light = s.panels.watch.dispel_light };
end;
local function all(s, value, message)
    local count = 0;
    for name, held in pairs(switches(s)) do
        assert(held == value, message .. ': ' .. name .. ' is ' .. tostring(held));
        count = count + 1;
    end;
    assert(count == 7, 'Fixture: seven switches.');
end;
local function set_all(s, value)
    s.ready_pulse.enabled, s.party_cooldowns.enabled = value, value;
    s.recast_tints.mp, s.recast_tints.spell_lock, s.recast_tints.ability_lock = value, value, value;
    s.panels.target.dispel_light, s.panels.watch.dispel_light = value, value;
    return s;
end;

-- Fresh settings, as made, as tidied and from an empty save.
all(defaults.make(), false, 'Fresh settings have each one off');
all(defaults.tidy(defaults.make()), false, 'Tidied fresh settings have each one off');
all(defaults.tidy({}), false, 'An empty save has each one off');
local fresh = defaults.tidy(defaults.make());
assert(fresh.party_cooldowns.strips == true and fresh.party_cooldowns.overhead == false and fresh.party_cooldowns.list.enabled == false
    and fresh.party_cooldowns.preview == false, 'The watch starts with its strips on, so turning it on shows the strip cells.');
assert(fresh.panels.target.dispel_glow == true and fresh.panels.watch.dispel_glow == true, 'The light starts with its glow on.');
-- Each one's own tidy fills a missing switch with off.
assert(require('core.ready_pulse').tidy({}).enabled == false, 'A pulse saved with no switch is off.');
local tints = require('core.recast_tints').tidy({});
assert(tints.mp == false and tints.spell_lock == false and tints.ability_lock == false, 'Tints saved with no switches are off.');
local watch = require('core.party_cooldowns').tidy({ list = {} });
assert(watch.enabled == false and watch.strips == true, 'A watch saved with no switch is off, with its strips on.');

-- A save without them: everything else a save holds, with none of their keys.
local function without_them(s)
    s.ready_pulse, s.recast_tints, s.party_cooldowns = nil, nil, nil;
    for _, id in ipairs({ 'target', 'watch' }) do
        s.panels[id].dispel_light, s.panels[id].dispel_glow, s.panels[id].dispel_color = nil, nil, nil;
    end;
    return s;
end;
all(defaults.tidy(without_them(store.copy(defaults.make()))), false, 'A save without them loads each one off');
-- A hand edit that gives a switch another type loads it off too.
local odd = without_them(store.copy(defaults.make()));
odd.ready_pulse, odd.recast_tints, odd.party_cooldowns = { enabled = 'yes' }, { mp = 1, spell_lock = 'on', ability_lock = {} }, { enabled = 1 };
odd.panels.target.dispel_light, odd.panels.watch.dispel_light = 'true', 1;
all(defaults.tidy(odd), false, 'A switch saved as another type loads off');

-- Saved on, each stays on; saved off, each stays off: in the settings file, read back and tidied as a load does.
local folder = MOCK_INSTALL_PATH .. '/config/addons/vantage';
local path = folder .. '/four.json';
for _, value in ipairs({ true, false }) do
    local saved = set_all(defaults.tidy(defaults.make()), value);
    assert(store.write(path, saved), 'Fixture: the settings write.');
    all(defaults.tidy(assert(store.read(path))), value, 'Saved ' .. tostring(value) .. ', each loads ' .. tostring(value));
    -- A named profile, loaded over settings with each the other way.
    local named = profiles.new(folder);
    local name = value and 'Four on' or 'Four off';
    assert(named:save_new(name, saved), 'Fixture: the profile saves.');
    local receiver = set_all(defaults.tidy(defaults.make()), not value);
    assert(named:load(name, receiver), 'The profile loads.');
    all(receiver, value, 'A profile saved ' .. tostring(value) .. ' loads each ' .. tostring(value));
    -- Shared presentation.
    receiver = set_all(defaults.tidy(defaults.make()), not value);
    assert(profiles.apply_layout(receiver, profiles.capture_layout(saved, 'presentation'), 'presentation'), 'The presentation applies.');
    all(receiver, value, 'Shared presentation saved ' .. tostring(value) .. ' gives each ' .. tostring(value));
    -- A whole profile export, read and put in place of settings with each the other way.
    local exported, why = share.export(saved, 'profile', nil, 'Tester');
    assert(exported, 'The profile exports: ' .. tostring(why));
    local candidate = share.candidate(set_all(defaults.tidy(defaults.make()), not value), assert(share.read(exported)), 'replace');
    all(defaults.tidy(candidate), value, 'An export made ' .. tostring(value) .. ' gives each ' .. tostring(value));
end;

-- Through the real vantage.lua: a save without them in the character's folder loads each one off, and saves them
-- off.
local snapshot = { valid = true, id = 2002, name = 'Fixture', zone = 102, job = 5, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
require('ui.native_party_hud').draw = function() return false, {}; end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, status = function() return { available = false }; end };
local character = folder .. '/Fixture_2002';
MOCK_MKDIR(character);
local file = assert(io.open(character .. '/settings.json', 'wb'), 'Fixture: the settings file opens.');
file:write(store.encode(without_them(store.copy(defaults.make())))); file:close();
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
assert(app.state.path == character .. '/settings.json' and not app.state.unread, 'Fixture: the saved settings load.');
all(app.state.settings, false, 'The app loads a save without them with each one off');
app.state.dirty = true;
assert(app.callbacks.save(), 'The settings save.');
local disk = assert(store.read(app.state.path), 'The settings file reads.');
assert(disk.ready_pulse.enabled == false and disk.recast_tints.mp == false and disk.recast_tints.spell_lock == false
    and disk.recast_tints.ability_lock == false and disk.party_cooldowns.enabled == false
    and disk.panels.target.dispel_light == false and disk.panels.watch.dispel_light == false, 'They are saved off.');
MOCK.fire('unload');
return 'The pulse, the tints, the party cooldown watch and the panels\' light start off and keep a saved choice';
