-- Vantage loaded at the title screen (no player and no party member yet), then a login, for a saved XI View look with
-- the party strips and overhead icons on (warmup_fixture.lua). The title screen's refreshes read no settings, so the
-- displays wait there however long it lasts. The zone-in packet loads XI View inside the loading screen; the first
-- refresh in the game reads the settings and asks for the party list and the name point, and the displays draw once
-- the party list's steps have run. Nothing draws while they are still to run, and no Present after the login searches,
-- reads or uploads inside a draw.
local F = require('warmup_fixture');
local L, W = F.L, F.W;
local warmup = require('core.warmup');
local assets, client_fonts = require('ui.client_assets'), require('ui.client_fonts');
W.unit(0x100, 0x1000100, 'mob', 0, -5, { name = 'Goblin Mugger', hitbox = 1.2 });
W.target = 0x100;
F.save('XI View', function(settings) settings.party_ui.enabled, settings.overhead.enabled = true, true; end);
local missing, waiting = {}, {};
local function art(label)
    if not client_fonts.current('XI View') then missing[#missing + 1] = label .. ': the XI View face'; end
    if not assets.icons_loaded('xiview') or not assets.action_loaded('xiview', 'common') then
        missing[#missing + 1] = label .. ': the XI View icons';
    end
end
-- The strips' draw is called on every Present and draws only while they are on.
local strips = require('ui.native_party_hud');
local strips_off = strips.draw;
for _, display in ipairs({ { 'ui.hud', 'draw', 'panels' }, { 'ui.native_party_hud', 'draw', 'party strips' },
    { 'ui.settings_window', 'draw', 'settings window' }, { 'core.native_party_ui', 'treasure_open', 'Treasure Pool check' },
    { 'ui.overhead_icons', 'draw', 'overhead icons' } }) do
    F.watch(display[1], display[2], display[3], art);
    local owner = require(display[1]);
    local watched = owner[display[2]];
    owner[display[2]] = function(...)
        if owner == strips and not select(3, ...).enabled then return strips_off(...); end
        if warmup.pending('xiview') or warmup.pending('party') then waiting[#waiting + 1] = display[3] .. ' at ' .. F.presents; end
        return watched(...);
    end;
end

-- The title screen.
local you = L.members[0];
L.members[0], MOCK.zoning = nil, true;
local app = F.load();
for _ = 1, 24 do F.present(); end
assert(not app.state.path and app.state.ready == false and next(F.first) == nil,
    'At the title screen no refresh reads the settings, and nothing draws.');
assert(not warmup.pending('start') and not warmup.pending('assets') and not warmup.wanted('party'),
    'The steps every display needs have run meanwhile; nothing else is asked for.');

-- The login: the zone-in packet, then you are in the zone.
local uploads = F.uploads;
L.zone_in(102);
assert(warmup.wanted('xiview') and not warmup.pending('xiview') and F.uploads > uploads,
    'The zone-in packet loads XI View inside the loading screen.');
L.members[0], MOCK.zoning = you, nil;
L.self_timers();
local searched = #F.during;
F.present();
assert(app.state.path and warmup.wanted('party') and warmup.wanted('names') and app.state.ready == false,
    'The first refresh in the game reads the settings and asks for the party list and the name point; the displays wait.');
while warmup.pending('party') or warmup.pending('names') or app.state.ready == false do
    assert(F.presents < 80, 'Fixture: the warmup ends.');
    F.present();
end
for _ = 1, 3 do F.present(); end
assert(F.first['panels'] and F.first['panels'] == F.first['party strips'], 'The panels and the strips first draw together.');
assert(F.first['overhead icons'], 'Fixture: the overhead icons draw.');
assert(#waiting == 0, 'Nothing draws while the party list is still to run: ' .. table.concat(waiting, ', '));
assert(#F.during == searched and searched == 0, 'No draw reads, uploads or searches: ' .. table.concat(F.during, ', '));
assert(#F.early == 0, 'Nothing drew before the warmup let it: ' .. table.concat(F.early, ', '));
assert(#missing == 0, 'The first draw finds XI View\'s art: ' .. table.concat(missing, ', '));
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return 'A load at the title screen waits for the login\'s settings';
