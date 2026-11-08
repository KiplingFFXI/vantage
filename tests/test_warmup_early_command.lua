-- A Vantage command after /load but before the first Present, for a saved XI View look with the party strips and
-- overhead icons on (warmup_fixture.lua): the command runs the warmup's steps wanted so far, but the displays still
-- wait for the first refresh, whose settings ask for XI View, the game's party list and the name point. Nothing draws
-- until those have run, the first draw finds XI View's art, and no draw reads, uploads or searches.
local F = require('warmup_fixture');
local L = F.L;
local warmup = require('core.warmup');
local assets, client_fonts = require('ui.client_assets'), require('ui.client_fonts');
F.save('XI View', function(settings) settings.party_ui.enabled, settings.overhead.enabled = true, true; end);
local missing = {};
local function art(label)
    if not client_fonts.current('XI View') then missing[#missing + 1] = label .. ': the XI View face'; end
    if not assets.icons_loaded('xiview') or not assets.action_loaded('xiview', 'common') then
        missing[#missing + 1] = label .. ': the XI View icons';
    end
end
F.watch('ui.hud', 'draw', 'panels', art);
F.watch('ui.native_party_hud', 'draw', 'party strips', art);
F.watch('ui.overhead_icons', 'draw', 'overhead icons', art);

local app = F.load();
local command = L.command('/vg show');
assert(command.blocked == true and not warmup.pending('start') and not warmup.pending('assets'),
    'The command runs the steps wanted so far.');
assert(app.state.ready == false and not app.state.path and not warmup.wanted('xiview'),
    'The displays still wait: no refresh has read the settings yet.');

-- The first Present's refresh reads them and asks for the rest. Nothing draws in it.
local _, ran = F.present();
assert(#ran == 0 and app.state.path and warmup.wanted('xiview') and warmup.wanted('party') and warmup.wanted('names'),
    'The first refresh asks for XI View, the game\'s party list and the name point.');
assert(app.state.ready == false and next(F.first) == nil, 'Nothing draws in the first Present.');
while warmup.pending('xiview') or warmup.pending('party') do
    assert(F.presents < 40, 'Fixture: the warmup ends.');
    F.present();
end
assert(next(F.first) == nil, 'Nothing draws in the Present that ran their last step.');
_, ran = F.present();
assert(#ran == 0 and F.first['panels'] == F.presents and F.first['party strips'] == F.presents,
    'The panels and the party strips draw in the next Present, which runs no step.');
assert(#F.early == 0, 'Nothing drew before the warmup let it: ' .. table.concat(F.early, ', '));
assert(#missing == 0, 'The first draw finds XI View\'s art: ' .. table.concat(missing, ', '));
assert(#F.during == 0, 'Drawing reads, uploads and searches nothing: ' .. table.concat(F.during, ', '));
return 'A command before the first Present does not let the displays draw early';
