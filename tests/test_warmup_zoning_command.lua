-- /load while a zone is loading, for a saved XI View look with the party strips on (warmup_fixture.lua), on a client
-- that reads no character while it zones, then a Vantage command typed on the loading screen. With no character to
-- read, the command can't tell that screen from the title screen, so the displays draw with the defaults in use. In
-- the zone the first refresh reads the settings and asks for XI View and the party list, and the displays wait again
-- for their steps: none draws while those are still to run, they start again together with XI View's art, and no
-- draw reads, uploads or searches.
local F = require('warmup_fixture');
local L, W = F.L, F.W;
local warmup = require('core.warmup');
local assets, client_fonts = require('ui.client_assets'), require('ui.client_fonts');
local appearance = require('ui.appearance');
F.save('XI View', function(settings) settings.party_ui.enabled = true; end);
local missing, waiting = {}, {};
-- The strips' draw is called on every Present and draws only while they are on.
local strips = require('ui.native_party_hud');
local strips_off = strips.draw;
for _, display in ipairs({ { 'ui.hud', 'draw', 'panels' }, { 'ui.native_party_hud', 'draw', 'party strips' },
    { 'ui.settings_window', 'draw', 'settings window' }, { 'core.native_party_ui', 'treasure_open', 'Treasure Pool check' } }) do
    F.watch(display[1], display[2], display[3]);
    local owner = require(display[1]);
    local watched = owner[display[2]];
    owner[display[2]] = function(...)
        if owner == strips and not select(3, ...).enabled then return strips_off(...); end
        if warmup.pending('xiview') or warmup.pending('party') then waiting[#waiting + 1] = display[3] .. ' at ' .. F.presents; end
        if display[3] == 'panels' and F.app and appearance.uses_xiview(F.app.state.settings)
            and (not client_fonts.current('XI View') or not assets.icons_loaded('xiview')) then
            missing[#missing + 1] = 'panels at ' .. F.presents;
        end
        return watched(...);
    end;
end

-- The loading screen, where this client reads no character.
local you = L.members[0];
W.zoning, L.members[0] = 1, nil;
local app = F.load();
for _ = 1, 10 do F.present(); end
assert(app.state.ready == false and next(F.first) == nil, 'Fixture: on the loading screen nothing draws.');
assert(L.command('/vg chatsample').blocked == true, 'Fixture: the command is Vantage\'s.');
F.present();
assert(app.state.ready and not app.state.path, 'Fixture: with no character to read, the command let the displays draw.');

-- The zone.
W.zoning, L.members[0] = 0, you;
while not app.state.path do
    assert(F.presents < 40, 'Fixture: a refresh reads the settings in the zone.');
    F.present();
end
assert(warmup.wanted('xiview') and warmup.wanted('party') and app.state.ready == false,
    'The first refresh that reads the settings asks for XI View and the party list, and the displays wait again.');
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
assert(#waiting == 0, 'Nothing draws while XI View or the party list is still to run: ' .. table.concat(waiting, ', '));
assert(#missing == 0, 'No panel draws the XI View look without its art: ' .. table.concat(missing, ', '));
assert(#F.early == 0, 'Nothing drew while the warmup held the displays: ' .. table.concat(F.early, ', '));
assert(#F.during == 0, 'Drawing reads, uploads and searches nothing: ' .. table.concat(F.during, ', '));
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return 'A command on a loading screen with no character lets the displays wait again for the zone\'s settings';
