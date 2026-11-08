-- /vantage at the title screen, after Vantage loaded there, for a saved XI View look with the party strips and
-- overhead icons on (warmup_fixture.lua). No settings can be read before a login, so the settings window shows with
-- the defaults in use. At the login the zone-in packet loads XI View, the settings read
-- then ask for the party list and the name point, and the displays wait again for the party list's steps and start
-- again together: nothing draws while they are still to run, and nothing searches inside a draw.
local F = require('warmup_fixture');
local L = F.L;
local warmup = require('core.warmup');
local assets, client_fonts = require('ui.client_assets'), require('ui.client_fonts');
local appearance = require('ui.appearance');
F.save('XI View', function(settings) settings.party_ui.enabled, settings.overhead.enabled = true, true; end);
local missing, waiting = {}, {};
-- The strips' draw is called on every Present and draws only while they are on.
local strips = require('ui.native_party_hud');
local strips_off = strips.draw;
for _, display in ipairs({ { 'ui.settings_window', 'draw', 'settings window' }, { 'ui.hud', 'draw', 'panels' },
    { 'ui.native_party_hud', 'draw', 'party strips' }, { 'core.native_party_ui', 'treasure_open', 'Treasure Pool check' } }) do
    F.watch(display[1], display[2], display[3]);
    local owner = require(display[1]);
    local watched = owner[display[2]];
    owner[display[2]] = function(...)
        if owner == strips and not select(3, ...).enabled then return strips_off(...); end
        if warmup.pending('party') then waiting[#waiting + 1] = display[3] .. ' at ' .. F.presents; end
        return watched(...);
    end;
end
local hud = require('ui.hud');
local draw = hud.draw;
hud.draw = function(...)
    if F.app and appearance.uses_xiview(F.app.state.settings) and (not client_fonts.current('XI View') or not assets.icons_loaded('xiview')) then
        missing[#missing + 1] = 'panels at ' .. F.presents;
    end
    return draw(...);
end;

-- The title screen.
local you = L.members[0];
L.members[0], MOCK.zoning = nil, true;
local app = F.load();
for _ = 1, 12 do F.present(); end
assert(app.state.ready == false and next(F.first) == nil, 'Fixture: at the title screen nothing draws.');
assert(L.command('/vantage').blocked == true, 'Fixture: the command is Vantage\'s.');
F.present(); F.present();
assert(app.state.ready and F.first['settings window'] and not app.state.path,
    'The settings window shows at the title screen, with no settings read.');

-- The login.
L.zone_in(102);
assert(warmup.wanted('xiview') and not warmup.pending('xiview'), 'The zone-in packet loads XI View inside the loading screen.');
L.members[0], MOCK.zoning = you, nil;
L.self_timers();
F.present();
assert(app.state.path and warmup.wanted('party') and warmup.wanted('names'),
    'The first refresh in the game reads the settings and asks for the party list and the name point.');
assert(app.state.ready == false, 'The displays wait again for the party list\'s steps.');
local before, again = {}, {};
for label, count in pairs(F.draws) do before[label] = count; end
while not (again['panels'] and again['party strips']) do
    assert(F.presents < 80, 'Fixture: the displays draw again.');
    F.present();
    for label, count in pairs(F.draws) do
        if count > (before[label] or 0) and not again[label] then again[label] = F.presents; end
    end
end
assert(again['panels'] == again['party strips'] and again['panels'] == again['settings window'],
    'The panels, the strips and the settings window start again in the same Present.');
assert(#waiting == 0, 'Nothing drew while the party list\'s steps were still to run: ' .. table.concat(waiting, ', '));
assert(#missing == 0, 'No panel drew the XI View look without its art: ' .. table.concat(missing, ', '));
assert(#F.during == 0, 'Drawing reads, uploads and searches nothing: ' .. table.concat(F.during, ', '));
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return 'A command at the title screen shows the settings window';
