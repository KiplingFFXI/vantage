local observer = require('core.observer');
local client = require('core.client');
local self_id, mob, mob2, ally = 1001, 0x1000010, 0x1000011, 1002;
local snapshot = { valid = true, id = self_id, zone = 102, name = 'Tester', level = 75,
    self_effects = {}, party = { { id = ally, name = 'Ally' } }, entities = {
        [self_id] = { name = 'Tester' }, [mob] = { name = 'Crab' }, [mob2] = { name = 'Crawler' }, [ally] = { name = 'Ally' },
    } };
local native = ashita.bits.unpack_be;
ashita.bits.unpack_be = function (raw, offset, start, width)
    assert(start + width <= raw.n * 8, 'A native bit read crossed the packet boundary.');
    return native(raw, offset, start, width);
end;
local function putbits(bytes, offset, length, value)
    for i = 0, length - 1 do
        local at = offset + i;
        if math.floor(value / 2 ^ i) % 2 == 1 then bytes[math.floor(at / 8)] = bytes[math.floor(at / 8)] + 2 ^ (at % 8); end
    end
end
local function action(category, id, targets, actor)
    local bytes, at = MOCK.bytes(2048), 150;
    putbits(bytes, 40, 32, actor or self_id); putbits(bytes, 72, 6, #targets);
    putbits(bytes, 82, 4, category); putbits(bytes, 86, 32, id);
    for _, target in ipairs(targets) do
        putbits(bytes, at, 32, target.id); putbits(bytes, at + 32, 4, #target.rows); at = at + 36;
        for _, row in ipairs(target.rows) do
            putbits(bytes, at + 27, 17, row.param or 0); putbits(bytes, at + 44, 10, row.message or 0); at = at + 85;
            putbits(bytes, at, 1, row.added and 1 or 0); at = at + 1;
            if row.added then putbits(bytes, at + 10, 17, row.added_param or 0); putbits(bytes, at + 27, 10, row.added); at = at + 37; end
            putbits(bytes, at, 1, row.reaction and 1 or 0); at = at + 1;
            if row.reaction then
                putbits(bytes, at + 10, 14, row.reaction_param or 0);
                putbits(bytes, at + 24, 10, type(row.reaction) == 'number' and row.reaction or 0); at = at + 34;
            end
        end
    end
    bytes.n = math.ceil(at / 8);
    return MOCK.packet(0x028, bytes);
end
local packet = action(4, 58, {
    { id = mob, rows = { { message = 236, param = 4, reaction = true } } },
    { id = mob2, rows = { { message = 267, param = 4 } } },
});
local events = observer.read(packet, 1, snapshot);
assert(#events == 2 and events[1].entity_id == mob and events[2].entity_id == mob2);
assert(events[1].duration == 120 and events[1].duration_min == 30 and events[1].source_name == 'Tester');
assert(events[1].tier == 1);
assert(events[1].category == 'debuff' and events[1].action_category == 4);
assert(not packet.blocked, 'Read-only observation never changes packet flags.');
snapshot.party[1].scope='alliance';snapshot.party[1].group=2;
local alliance_action=action(4,57,{{id=ally,rows={{message=230,param=33}}}});
local alliance_events=observer.read(alliance_action,1,snapshot);
assert(#alliance_events==1 and alliance_events[1].scope=='alliance','Roster identity determines alliance scope for observed actions.');
snapshot.party[1].scope=nil;snapshot.party[1].group=nil;
for length = 0, packet.size - 1 do
    local truncated = { id = packet.id, data = packet.data:sub(1, length), size = length, data_raw = packet.data_raw };
    assert(#observer.read(truncated, 2, snapshot) == 0, 'Every truncated action is atomic.');
end
packet = action(1, 0, {
    { id = self_id, rows = { { message = 1, param = 20, added = 160, added_param = 3 } } },
    { id = mob, rows = { { message = 1, param = 20, added = 164, added_param = 5 } } },
}, mob2);
events = observer.read(packet, 3, snapshot);
assert(#events == 2 and events[1].scope == 'self' and events[2].effect == 5);
assert(events[1].duration == nil and events[2].duration == nil, 'Unknown weapon identity stays untimed.');
packet = action(1, 0, { { id = mob, rows = { { message = 1, param = 20, reaction = 374, reaction_param = 9 } } } });
events = observer.read(packet, 3, snapshot);
assert(#events == 1 and events[1].entity_id == self_id and events[1].source == mob and events[1].effect == 9,
    'Status spikes affect the attacker, with the defender as source.');
packet = action(4, 58, { { id = mob, rows = { { message = 85, param = 4 } } } });
assert(#observer.read(packet, 4, snapshot) == 0, 'A resist result does not apply the parameter as a status.');
packet = action(4, 57, { { id = ally, rows = { { message = 230, param = 33 } } } });
events = observer.read(packet, 5, snapshot);
assert(events[1].scope == 'party' and events[1].duration == 180);
packet = action(4, 9999, { { id = mob, rows = { { message = 236, param = 999 } } } });
events = observer.read(packet, 5, snapshot);
assert(events[1].effect == 999 and events[1].duration == nil, 'Unlisted effects are still observed.');
packet = action(4, 23, { { id = mob, rows = { { message = 2, param = 0 } } } });
events = observer.read(packet, 6, snapshot);
assert(events[1].effect == 134 and events[1].duration == 60, 'Dia damage result confirms Dia even for zero damage.');
packet = action(6, 125, { { id = mob, rows = { { message = 2, param = 120 } } } });
assert(#observer.read(packet, 7, snapshot) == 0, 'Quick Draw damage cannot restart an existing debuff.');
packet = action(6, 131, { { id = mob, rows = { { message = 127, param = 2 } } } });
assert(observer.read(packet, 8, snapshot)[1].duration == 90, 'A successful Light Shot is a real Sleep application.');
-- A roll also gives the Phantom Roll display its own observation (test_rolls.lua); the status events are these.
local function statuses(list)
    local out = {};
    for _, event in ipairs(list) do if event.kind ~= 'roll' then out[#out + 1] = event; end end
    return out;
end
packet = action(6, 98, {
    { id = self_id, rows = { { message = 424, param = 9 } } },
    { id = ally, rows = { { message = 421, param = 9 } } },
});
events = statuses(observer.read(packet, 9, snapshot));
assert(#events == 2 and events[1].effect == 310 and events[2].effect == 310);
assert(events[1].duration == 360 and events[2].duration == 360 and events[2].duration_min == 300, 'A Double-Up renews the roll to its full time.');
packet = action(6, 98, {
    { id = self_id, rows = { { message = 420, param = 4 } } },
    { id = ally, rows = { { message = 421, param = 4 } } },
});
events = statuses(observer.read(packet, 10, snapshot));
assert(events[2].duration == 360 and events[2].duration_min == 300);
packet = action(6, 98, { { id = self_id, rows = { { message = 426, param = 12 } } } });
events = statuses(observer.read(packet, 11, snapshot));
assert(#events == 2 and events[1].kind == 'remove' and events[1].effect == 310 and events[2].effect == 309);
packet = action(4, 260, { { id = ally, rows = { { message = 341, param = 13 } } } });
events = observer.read(packet, 12, snapshot);
assert(events[1].kind == 'remove' and events[1].source == nil, 'The remover is not necessarily the status origin.');
local bytes = MOCK.bytes(28);
MOCK.put(bytes, 4, 4, self_id); MOCK.put(bytes, 8, 4, mob); MOCK.put(bytes, 12, 4, 4); MOCK.put(bytes, 24, 2, 206);
events = observer.read(MOCK.packet(0x029, bytes), 13, snapshot);
assert(events[1].kind == 'remove' and events[1].source == self_id and events[1].entity_id == mob);
MOCK.put(bytes, 24, 2, 6);
assert(observer.read(MOCK.packet(0x029, bytes), 14, snapshot)[1].kind == 'death');
local despawn = MOCK.bytes(12); MOCK.put(despawn, 4, 4, mob); despawn[10] = 0x20;
assert(observer.read(MOCK.packet(0x00E, despawn), 15, snapshot)[1].kind == 'despawn');
packet.injected = true;
assert(#observer.read(packet, 16, snapshot) == 0);
packet.injected, packet.blocked = false, true;
assert(#observer.read(packet, 17, snapshot) == 0);
assert(#observer.read({}, 18, snapshot) == 0 and #observer.read(nil, 18, snapshot) == 0);
for _,id in ipairs({0x00A,0x00E,0x028,0x029,0x063,0x076,0x08C}) do
    assert(observer.interested(id), 'The fast packet filter retains status observations and client cache updates');
end
assert(not observer.interested(0x017) and not observer.interested(nil));
