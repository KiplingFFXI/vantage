-- A character switch while the displays draw, to a character whose self buffs panel follows the game's party list
-- (warmup_fixture.lua, Original look, strips off). The first character never needed the list, so its steps are still
-- to run: the login's refresh asks for them, and the refresh after their last step reads the list, so the panel
-- leaves its fallback spot in that Present, not at the next timed refresh. Nothing reads the list before its steps ran.
local F = require('warmup_fixture');
local L, W = F.L, F.W;
local warmup = require('core.warmup');
local store, defaults, appearance = require('core.store'), require('ui.defaults'), require('ui.appearance');
local anchors, elements = require('core.anchors'), require('ui.elements');
F.save('Original FFXI');
do
    local settings = defaults.make();
    assert(appearance.apply(settings, 'Original FFXI', { matching = true }), 'Fixture: the look.');
    local anchor = anchors.make();
    anchor.to, anchor.side = 'party', 'below';
    settings.panels.self_buffs.anchor = anchor;
    assert(store.write(MOCK_INSTALL_PATH .. '/config/addons/vantage/Other_2002/settings.json', settings), 'Fixture: Other\'s settings.');
end
F.watch('ui.hud', 'draw', 'panels');
-- The game's party window, there once the party list's steps have run; a read while they are still to run is counted.
local native = require('core.native_party_ui');
local early = 0;
native.geometry = function()
    if warmup.pending('party') or not warmup.wanted('party') then early = early + 1; end
    return { available = true, groups = { { x = 1700, y = 600, width = 200, height = 120, rows = {} } } };
end;

local app = F.load();
while app.state.ready == false do
    assert(F.presents < 60, 'Fixture: the displays open.');
    F.present();
end
for _ = 1, 3 do F.present(); end
assert(F.first['panels'] and not warmup.wanted('party'), 'Fixture: the panels draw and the party list is not asked for.');

-- The switch: the title screen, then Other's zone-in packet and login.
L.members[0], MOCK.zoning = nil, true;
for _ = 1, 6 do F.present(); end
local bytes = MOCK.bytes(0x100);
MOCK.put(bytes, 4, 4, 2002); MOCK.put(bytes, 0x30, 2, 102); MOCK.put(bytes, 0x80, 4, 2);
for i = 1, #'Other' do bytes[0x83 + i] = ('Other'):byte(i); end
L.receive(0x00A, bytes);
L.members[0] = { id = 2002, index = W.self, name = 'Other' };
MOCK.player.server_id, MOCK.player.name = 2002, 'Other';
W.entities[W.self].id = 2002;
MOCK.zoning = nil;
L.self_timers();
F.present();
assert(app.state.path and app.state.path:find('Other_2002', 1, true) and warmup.pending('party') and app.state.ready,
    'The login\'s refresh reads Other\'s settings and asks for the party list; the displays go on drawing.');
assert(elements.party_list == nil, 'Fixture: the party list is not read yet.');
while warmup.pending('party') do
    assert(F.presents < 60, 'Fixture: the party list\'s steps run.');
    F.present();
end
assert(elements.party_list ~= nil, 'The refresh in the Present the party list\'s last step ran in reads the list.');
assert(early == 0, 'Nothing read the party list before its steps ran: ' .. early);
assert(#F.during == 0, 'Drawing reads, uploads and searches nothing: ' .. table.concat(F.during, ', '));
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return 'The party list asked for after a switch is read once its steps have run';
