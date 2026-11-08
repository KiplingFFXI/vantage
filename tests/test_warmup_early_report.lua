-- /vg report after /load but before the first Present, with the party strips and overhead icons on (warmup_fixture.lua):
-- its own refresh is the first, and its settings ask for the game's party list and the name point, so the report runs
-- those steps too before it is written. Nothing it lists is still to run, its flags are found ones, and the first
-- Present draws with nothing left to make and nothing searched while drawing.
local F = require('warmup_fixture');
local L = F.L;
local warmup = require('core.warmup');
local store = require('core.store');
F.save('Original FFXI', function(settings) settings.party_ui.enabled, settings.overhead.enabled = true, true; end);
F.watch('ui.hud', 'draw', 'panels');
F.watch('ui.native_party_hud', 'draw', 'party strips');

local app = F.load();
assert(L.command('/vg report').blocked == true, 'Fixture: the report is Vantage\'s.');
local report = store.read(MOCK_INSTALL_PATH .. '/config/addons/vantage/reports/latest.json');
local startup = report and report.startup;
assert(startup and startup.ready == true and #startup.failed == 0, 'The report is written and the displays may draw.');
for _, later in ipairs(startup.later) do
    assert(later.note ~= 'Still to run.' and later.group ~= 'party' and later.group ~= 'names',
        'Nothing the report lists is still to run: ' .. tostring(later.group));
end
assert(not warmup.pending('party') and not warmup.pending('names') and warmup.wanted('names'),
    'The party list and the name point were asked for and have run.');
assert(report.capabilities.timers == true and report.capabilities.hidden == true, 'The report\'s flags are found ones.');
local finds = F.finds;
local _, ran = F.present();
assert(#ran == 0 and F.first['panels'] == 1 and F.first['party strips'] == 1 and F.finds == finds,
    'The first Present draws with nothing left to run or search.');
assert(#F.during == 0 and app.state.problem == nil, 'Nothing went wrong: ' .. table.concat(F.during, ', ') .. tostring(app.state.problem));
return '/vg report before the first Present runs what its refresh asks for';
