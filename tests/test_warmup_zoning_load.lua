-- /load while a zone is loading, for a saved XI View look with the party strips on (warmup_fixture.lua): the
-- refreshes during the loading screen read no settings, so the displays wait. In the zone the first refresh reads
-- them and asks for XI View and the game's party list, and the displays draw once those steps have run: nothing draws
-- while either is still to run, the first draw finds XI View's art, and no draw reads, uploads or searches.
local F = require('warmup_fixture');
local W = F.W;
local warmup = require('core.warmup');
local assets, client_fonts = require('ui.client_assets'), require('ui.client_fonts');
F.save('XI View', function(settings) settings.party_ui.enabled = true; end);
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
    { 'ui.settings_window', 'draw', 'settings window' }, { 'core.native_party_ui', 'treasure_open', 'Treasure Pool check' } }) do
    F.watch(display[1], display[2], display[3], art);
    local owner = require(display[1]);
    local watched = owner[display[2]];
    owner[display[2]] = function(...)
        if owner == strips and not select(3, ...).enabled then return strips_off(...); end
        if warmup.pending('xiview') or warmup.pending('party') then waiting[#waiting + 1] = display[3] .. ' at ' .. F.presents; end
        return watched(...);
    end;
end

W.zoning = 1;
local app = F.load();
for _ = 1, 10 do F.present(); end
assert(not app.state.path and app.state.ready == false and next(F.first) == nil,
    'During the loading screen no refresh reads the settings, and nothing draws.');
assert(not warmup.pending('start') and not warmup.pending('assets') and not warmup.wanted('xiview'),
    'The steps every display needs have run; XI View is not asked for yet.');

W.zoning = 0;
while not app.state.path do
    assert(F.presents < 30, 'Fixture: a refresh reads the settings in the zone.');
    F.present();
end
assert(warmup.wanted('xiview') and warmup.wanted('party') and app.state.ready == false and next(F.first) == nil,
    'In the zone the first refresh reads the settings and asks for XI View and the party list; the displays wait.');
while app.state.ready == false do
    assert(F.presents < 60, 'Fixture: the displays open.');
    F.present();
end
for _ = 1, 3 do F.present(); end
assert(F.first['panels'] and F.first['panels'] == F.first['party strips'], 'The panels and the strips first draw together.');
assert(#waiting == 0, 'Nothing draws while XI View or the party list is still to run: ' .. table.concat(waiting, ', '));
assert(#F.early == 0, 'Nothing drew before the warmup let it: ' .. table.concat(F.early, ', '));
assert(#missing == 0, 'The first draw finds XI View\'s art: ' .. table.concat(missing, ', '));
assert(#F.during == 0, 'Drawing reads, uploads and searches nothing: ' .. table.concat(F.during, ', '));
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return 'A load during a loading screen waits for the settings the zone brings';
