-- Through vantage.lua as the game drives it, with userdata events: a zone-in (0x00A) into a Mog House holds the
-- snapshot until the 0x063 that ends zoning and then puts you in a Mog House for the show conditions; leaving it is
-- the town again. A command event goes through.
local L = require('live_fixture');
local W = L.W;
local conditions = require('core.conditions');
local app = L.start();
assert(conditions.place.kind == 'field', 'La Theine Plateau is a field: ' .. conditions.place.kind);

local function arrive(zone, mog_house)
    W.party_zone, MOCK.player.zone = zone, zone;
    L.zone_in(zone, mog_house);
    L.frame();
    assert(not app.state.snapshot.valid, 'While zoning there is no snapshot: the 0x00A was taken.');
    L.self_timers();
    L.frame();
    assert(app.state.snapshot.valid and app.state.snapshot.zone == zone, 'The 0x063 ends zoning.');
end
arrive(245, true);
assert(conditions.place.kind == 'mog_house', 'Its login state puts you in a Mog House: ' .. conditions.place.kind);
arrive(245, false);
assert(conditions.place.kind == 'town', 'Out of it, Lower Jeuno is a town: ' .. conditions.place.kind);

-- A command: Vantage takes its own and sets blocked on it.
local said = #MOCK.printed;
local set = L.command('/vg set overhead.max_units 4');
assert(set.blocked == true and app.state.settings.overhead.max_units == 4 and #MOCK.printed == said + 1
    and MOCK.printed[said + 1]:find('overhead.max_units is now 4.', 1, true), 'The command is taken and runs.');
local other = L.command('/echo hello');
assert(other.blocked == false and #MOCK.printed == said + 1, 'A command that isn\'t ours is left alone.');
L.frame();
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return true;
