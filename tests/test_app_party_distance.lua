-- Through vantage.lua as the game drives it: with Party list and the distance on, each refresh marks how far Bob
-- and Dave are from you from the client's positions (core/party_distance.lua), and /vg report carries it. A member the
-- game stops drawing gets none, and with the distance or the buffs off nothing is measured.
local store = require('core.store');
local L = require('live_fixture');
local W = L.W;
local app = L.start();
local s = app.state.settings;
s.party_ui.enabled, s.party_ui.distance = true, true;
L.frame(); L.frame();
local function member(id)
    for _, row in ipairs(app.state.roster.members or {}) do if row.id == id then return row; end end
end
assert(app.state.roster.valid and member(1002) and member(1003), 'Fixture: you, Bob and Dave on the roster.');
local bob, dave = member(1002), member(1003);
assert(bob.tenths == 22 and bob.reach == 208 and bob.far == false and bob.steep == false, 'Bob is 2.2 away: ' .. tostring(bob.tenths));
assert(dave.tenths == 22 and dave.reach == 208, 'So is Dave: ' .. tostring(dave.tenths));
assert(member(1001).tenths == nil, 'You get none.');

-- Bob walks 25 across and 3 up: 25.2 counting height, past Spell range between two Humes.
W.entities[0x401].x, W.entities[0x401].z = 25, -3;
L.frame();
bob = member(1002);
assert(bob.tenths == 252 and bob.far == true, 'Bob is 25.2 away and past Spell range: ' .. tostring(bob.tenths));
L.command('/vg report');
local report = assert(store.read(MOCK_INSTALL_PATH .. '/config/addons/vantage/reports/latest.json'));
local listed;
for _, row in ipairs(report.party_roster.members) do if row.id == 1002 then listed = row; end end
assert(listed and listed.tenths == 252 and listed.reach == 208 and listed.far == true, '/vg report carries the distance.');
assert(report.party_display.distance == true and report.party_display.distance_warn == 'spell'
    and report.party_display.distance_size == 'small', 'And the settings.');

-- The game stops drawing Bob: no number, as for a member in another zone.
W.entities[0x401].flags = 0;
L.frame();
assert(member(1002).tenths == nil and member(1003).tenths == 22, 'Bob gets none while the game isn\'t showing him.');
W.entities[0x401].flags = 0x200;
L.frame();
assert(member(1002).tenths == 252, 'He has one again once he shows.');

-- With the distance off, or the buffs off, nothing is measured.
s.party_ui.distance = false;
L.frame();
assert(member(1002).tenths == nil and member(1003).tenths == nil, 'Distance off, no numbers.');
-- Party cooldowns still read the roster, so the members are there to check.
s.party_ui.enabled, s.party_ui.distance, s.party_cooldowns.enabled = false, true, true;
L.frame();
assert(app.state.roster.valid and member(1002) and member(1003), 'Fixture: the roster is still read.');
for _, row in ipairs(app.state.roster.members) do assert(row.tenths == nil, 'Buffs off, no numbers.'); end
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return true;
