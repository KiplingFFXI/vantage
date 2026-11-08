-- The party strips turned on after the displays opened, with the Original look (warmup_fixture.lua): the game's party
-- list is not asked for at load, so its steps are still to run. The strips and their Treasure Pool check ask for them
-- in the Present they are turned on in and wait for them, so no draw searches; the strips draw once they have run,
-- and the other displays go on drawing meanwhile.
local F = require('warmup_fixture');
local warmup = require('core.warmup');
F.save('Original FFXI');
local waiting = {};
-- The strips' draw is called on every Present and draws only while they are on.
local strips = require('ui.native_party_hud');
local strips_off = strips.draw;
F.watch('ui.hud', 'draw', 'panels');
for _, display in ipairs({ { 'ui.native_party_hud', 'draw', 'party strips' }, { 'core.native_party_ui', 'treasure_open', 'Treasure Pool check' } }) do
    F.watch(display[1], display[2], display[3]);
    local owner = require(display[1]);
    local watched = owner[display[2]];
    owner[display[2]] = function(...)
        if owner == strips and not select(3, ...).enabled then return strips_off(...); end
        if warmup.pending('party') then waiting[#waiting + 1] = display[3] .. ' at ' .. F.presents; end
        return watched(...);
    end;
end

local app = F.load();
while app.state.ready == false do
    assert(F.presents < 60, 'Fixture: the displays open.');
    F.present();
end
F.present();
assert(F.first['panels'] and not F.first['party strips'] and not warmup.wanted('party'),
    'Fixture: the panels draw, the strips are off and the party list is not asked for.');

-- Turned on, as the settings window does inside a Present before the strips draw.
app.state.settings.party_ui.enabled = true;
local panels = F.draws['panels'];
local _, ran = F.present();
assert(#ran == 0 and warmup.wanted('party') and warmup.pending('party') and not F.first['party strips'],
    'The strips ask for the party list and wait for its steps; none runs in that Present.');
assert(F.draws['panels'] == panels + 1, 'The other displays go on drawing.');
while warmup.pending('party') do
    assert(F.presents < 60, 'Fixture: the party list\'s steps run.');
    F.present();
end
F.present();
assert(F.first['party strips'], 'Once its steps have run the strips draw.');
assert(#waiting == 0, 'Nothing used the party list while its steps were still to run: ' .. table.concat(waiting, ', '));
assert(#F.during == 0, 'Drawing reads, uploads and searches nothing: ' .. table.concat(F.during, ', '));
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return 'Party strips turned on later wait for the party list\'s steps';
