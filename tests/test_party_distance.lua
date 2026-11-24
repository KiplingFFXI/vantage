-- The distance to each member (core/party_distance.lua), from the client's positions as Phoenix measures range: the
-- straight line with height, Spell range from both races, the area picks with their height and alliance rules, the
-- members that get none, the kept text, the samples by slot and the tooltip.
local W = require('overhead_fixture');
local distance = require('core.party_distance');

-- You (1001, a Hume at 0x400, at 0, 0, 0) and members at the indexes given, all in your zone and drawn.
local function roster(rows)
    local out = { valid = true, id = 1001, members = { { id = 1001, slot = 0, group = 1, same_zone = true, available = true } } };
    local snapshot = { valid = true, id = 1001, entities = { [1001] = { id = 1001, index = W.self } } };
    for _, row in ipairs(rows) do
        local slot = row.slot or #out.members;
        out.members[#out.members + 1] = { id = row.id, slot = slot, group = math.floor(slot / 6) + 1, name = row.name,
            same_zone = row.same_zone ~= false, available = row.available ~= false };
        snapshot.entities[row.id] = { id = row.id, index = row.index };
    end
    return out, snapshot;
end
local function member(list, id)
    for _, row in ipairs(list.members) do if row.id == id then return row; end end
end
local function mark(rows, pick)
    local list, snapshot = roster(rows);
    distance.mark(list, snapshot, { distance_warn = pick or 'spell' });
    return list;
end

-- Height counts: 4 across and 3 up is 5.0. Z is the height in the client.
W.unit(0x401, 1002, 'player', 4, 0, { z = -3 });
local list = mark({ { id = 1002, index = 0x401, name = 'Bob' } });
local bob = member(list, 1002);
assert(bob.tenths == 50 and distance.text(bob.tenths) == '5.0', 'Height counts: ' .. tostring(bob.tenths));
assert(member(list, 1001).tenths == nil, 'Your own row gets none.');

-- Spell range between two Humes is 20 + 0.4 + 0.4, and the color goes by the tenth you see.
for _, case in ipairs({ { 20.84, 208, false }, { 20.86, 209, true }, { 30, 300, true }, { 3, 30, false } }) do
    W.unit(0x401, 1002, 'player', case[1], 0);
    bob = member(mark({ { id = 1002, index = 0x401 } }), 1002);
    assert(bob.tenths == case[2] and bob.reach == 208 and bob.far == case[3], 'Two Humes at ' .. case[1] .. ': ' .. tostring(bob.tenths));
end
-- A Galka adds 0.8 and a Tarutaru 0.3, once for each of you.
W.unit(0x401, 1002, 'player', 21.1, 0, { race = 8 });
bob = member(mark({ { id = 1002, index = 0x401 } }), 1002);
assert(bob.reach == 212 and bob.far == false, 'A Hume and a Galka reach 21.2: ' .. tostring(bob.reach));
W.entities[W.self].race = 5;
W.unit(0x401, 1002, 'player', 20.7, 0, { race = 6 });
bob = member(mark({ { id = 1002, index = 0x401 } }), 1002);
assert(bob.reach == 206 and bob.tenths == 207 and bob.far == true, 'Two Tarutaru reach 20.6: ' .. tostring(bob.reach));
W.entities[W.self].race = 1;
-- A race the client doesn't give leaves Spell range off.
W.unit(0x401, 1002, 'player', 30, 0, { race = 0 });
bob = member(mark({ { id = 1002, index = 0x401 } }), 1002);
assert(bob.tenths == 300 and bob.reach == nil and bob.far == false, 'No race, no Spell range color.');

-- The area picks: a radius, anyone 8 or more above or below, and never an alliance row.
W.unit(0x401, 1002, 'player', 0, 0, { z = -8 });
W.unit(0x402, 1003, 'player', 0, 0, { z = 7.9 });
W.unit(0x403, 1004, 'player', 15, 0);
W.unit(0x404, 1005, 'player', 30, 0);
local rows = { { id = 1002, index = 0x401 }, { id = 1003, index = 0x402 }, { id = 1004, index = 0x403 },
    { id = 1005, index = 0x404, slot = 6 } };
local expect = {
    spell = { [1002] = false, [1003] = false, [1004] = false, [1005] = true },
    ten = { [1002] = true, [1003] = false, [1004] = true, [1005] = false },
    eight = { [1002] = true, [1003] = false, [1004] = true, [1005] = false },
    sixteen = { [1002] = true, [1003] = false, [1004] = false, [1005] = false },
    none = { [1002] = false, [1003] = false, [1004] = false, [1005] = false },
};
for pick, wanted in pairs(expect) do
    list = mark(rows, pick);
    for id, far in pairs(wanted) do
        assert(member(list, id).far == far, pick .. ': ' .. id .. ' should be ' .. tostring(far));
    end
end
assert(member(list, 1002).steep == true and member(list, 1003).steep == false, 'Steep is 8 or more above or below.');
assert(member(list, 1002).tenths == 80 and member(list, 1005).tenths == 300, 'The alliance member still gets a number.');

-- Members the game isn't showing, in another zone or in their Mog House get none, nor does anyone while your own
-- position can't be read.
local function none(fields, row, text)
    W.unit(0x401, 1002, 'player', 5, 0, fields);
    row = row or {};
    row.id, row.index = row.id or 1002, row.index or 0x401;
    assert(member(mark({ row }), 1002).tenths == nil, text);
end
none({ flags = 0 }, nil, 'Not drawn, no number.');
none({ flags = 0x4200 }, nil, 'Hidden in a cutscene, no number.');
none({ actor = 0 }, nil, 'No model, no number.');
none({ id = 1099 }, nil, 'Someone else at that index, no number.');
none({ x = 0 / 0 }, nil, 'A position that isn\'t a number, no number.');
none({}, { same_zone = false, available = false }, 'Another zone, no number.');
none({}, { available = false }, 'Their Mog House, no number.');
none({}, { index = 0 }, 'No index, no number.');
none({ x = 2000 }, nil, 'Past 99.9, no number.');
W.unit(0x401, 1002, 'player', 5, 0, { status = 3 });
assert(member(mark({ { id = 1002, index = 0x401 } }), 1002).tenths == 50, 'A KO\'d member keeps their number for a Raise.');
W.entities[W.self].y = 0 / 0;
W.unit(0x401, 1002, 'player', 5, 0);
assert(member(mark({ { id = 1002, index = 0x401 } }), 1002).tenths == nil, 'Your own position unread, no numbers.');
W.entities[W.self].y = 0;
local snap;
list, snap = roster({ { id = 1002, index = 0x401 } });
list.valid = false;
distance.mark(list, snap, { distance_warn = 'spell' });
assert(member(list, 1002).tenths == nil, 'A roster that isn\'t valid gets none.');
-- Marking again clears what the last mark gave.
list, snap = roster({ { id = 1002, index = 0x401 } });
distance.mark(list, snap, { distance_warn = 'spell' });
assert(member(list, 1002).tenths == 50, 'Marked.');
W.entities[0x401].flags = 0;
distance.mark(list, snap, { distance_warn = 'spell' });
assert(member(list, 1002).tenths == nil and member(list, 1002).far == nil, 'A second mark clears a member gone from view.');

-- The text for a tenth is made once and kept, so drawing it makes nothing.
assert(distance.text(0) == '0.0' and distance.text(204) == '20.4' and distance.text(999) == '99.9', 'One decimal.');
assert(distance.text(1000) == '' and distance.text(-1) == '' and distance.text(2.5) == '' and distance.text(nil) == '', 'Nothing else.');
-- With the compiler off, as test_party_strip_allocation.lua measures, since a trace it makes counts too.
jit.off(); jit.flush();
for tenths = 0, 999 do distance.text(tenths); end
collectgarbage(); collectgarbage(); collectgarbage('stop');
for tenths = 0, 99 do distance.text(tenths); end
local before = collectgarbage('count');
for _ = 1, 50 do for tenths = 0, 999 do distance.text(tenths); end end
local made = collectgarbage('count') - before;
collectgarbage('restart'); jit.on();
assert(made < 1, 'Kept text makes nothing: ' .. made .. ' KB');

-- The samples by slot, colored as if both of you were Hume.
local samples = { 42, 96, 143, 204, 219, 306 };
for slot = 0, 11 do
    local tenths, far = distance.sample(slot, math.floor(slot / 6) + 1, 'spell');
    assert(tenths == samples[slot % 6 + 1], 'Slot ' .. slot .. ' samples ' .. tostring(tenths));
    assert(far == (tenths > 208), 'Spell range colors 21.9 and 30.6 only.');
    local _, area = distance.sample(slot, math.floor(slot / 6) + 1, 'ten');
    assert(area == (slot < 6 and tenths > 100), 'Area picks color the party past 10, never the alliance.');
    assert(select(2, distance.sample(slot, 1, 'none')) == false, 'Never colors none.');
end
local shown = {};
for slot = 0, 5 do shown[#shown + 1] = distance.text((distance.sample(slot, 1, 'spell'))); end
assert(table.concat(shown, ' ') == '4.2 9.6 14.3 20.4 21.9 30.6', 'Samples: ' .. table.concat(shown, ' '));

-- The tooltip: the name, the distance and what the pick reaches, in plain words.
local function plain(text)
    assert(not text:find('[^\n -~]') and not text:find('--', 1, true) and not text:find(';', 1, true), 'Plain: ' .. text);
    assert(not text:lower():find('unknown', 1, true) and not text:lower():find('unconfirmed', 1, true), 'Plain: ' .. text);
    return text;
end
local near = { id = 1002, name = 'Bob', slot = 1, group = 1, tenths = 204, reach = 208, steep = false };
local text = plain(distance.details(near, { distance_warn = 'spell' }));
assert(text == 'Bob\n20.4 yalms from you, counting height.\nSpells you cast on one member, such as Cure, reach them up to 20.8 yalms away.', text);
text = plain(distance.details(near, { distance_warn = 'ten' }));
assert(text:find('Songs, Protectra, Shellra and the Circles reach 10 yalms around you.', 1, true), text);
near.steep = true;
text = plain(distance.details(near, { distance_warn = 'eight' }));
assert(text:find('Phantom Roll reaches 8 yalms', 1, true) and text:find('8 or more yalms above or below you', 1, true), text);
near.group = 2;
text = plain(distance.details(near, { distance_warn = 'sixteen' }));
assert(text:find('Luzaf', 1, true) and text:find('another party of the alliance', 1, true), text);
text = plain(distance.details(near, { distance_warn = 'none' }));
assert(text == 'Bob\n20.4 yalms from you, counting height.', text);
text = plain(distance.details({ id = 1003, slot = 3, group = 1 }, { distance_warn = 'spell', preview = true }));
assert(text == 'Member\n20.4 yalms from you, counting height.\nSpells you cast on one member, such as Cure, reach them up to'
    .. ' 20.8 yalms away.\nThis is a sample.', text);
return 'Distances measure as Phoenix does, and the text, samples and tooltip read plainly';
