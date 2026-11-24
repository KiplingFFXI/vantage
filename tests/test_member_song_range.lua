-- Another player's buff song lasts 120 seconds times 1 and a tenth of their instrument's bonus to it, doubled under
-- Troubadour, and under Soul Voice for Hymnus and Mazurka (Phoenix globals/spells/enhancing_song.lua :223-257, :269).
-- Only your own gear is read, so theirs counts from 120 up to 144, the most a level 75 bard's instrument gives (+2 from
-- Cornette +1 and the like, or Gjallarhorn's All songs +2, sql/item_mods.sql). Their party listing says whether Troubadour
-- or Soul Voice was up. Real 0x028s through observer.read, then the party's listings through client.read and the tracker.
local observer = require('core.observer');
local SELF, BOB, DAVE, FRIEND, MOB = 1001, 1002, 1003, 1007, 0x1000123;
local function snapshot(dave)
    return { valid = true, id = SELF, name = 'Tester', zone = 102, job = 1, level = 75, self_known = true, self_effects = {},
        party = { { id = BOB, name = 'Bob', scope = 'party', valid = true, effects = {} },
            { id = DAVE, name = 'Dave', scope = 'party', valid = true, effects = dave or {} },
            { id = FRIEND, name = 'Friend', scope = 'alliance' } },
        entities = { [SELF] = { name = 'Tester' }, [BOB] = { name = 'Bob', kind = 'player' }, [DAVE] = { name = 'Dave', kind = 'player' },
            [FRIEND] = { name = 'Friend', kind = 'player' }, [MOB] = { name = 'Goblin Bard', kind = 'monster' } } };
end
-- A song from actor that lands on the singer (230) and on Bob (266), naming effect.
local function sing(actor, spell, effect)
    return MOCK.packet(0x028, MOCK.action_bytes(actor, 4, spell, { { id = actor, rows = { { message = 230, param = effect } } },
        { id = BOB, rows = { { message = 266, param = effect } } } }));
end
local function on_bob(events)
    for _, event in ipairs(events) do if event.kind == 'apply' and event.entity_id == BOB then return event; end end
end
local function range(event) return event and (tostring(event.duration_min) .. ' to ' .. tostring(event.duration)) or 'nothing'; end

-- Valor Minuet IV (397, Minuet 198) and Goddess's Hymnus (464, Hymnus 218).
local minuet = on_bob(observer.read(sing(DAVE, 397, 198), 1, snapshot()));
assert(minuet and minuet.duration == 144 and minuet.duration_min == 120 and minuet.basis == 'Duration range by the singer\'s instrument',
    'A party bard\'s Minuet counts 120 to 144 seconds: ' .. range(minuet));
minuet = on_bob(observer.read(sing(DAVE, 397, 198), 1, snapshot({ { effect = 348 } })));
assert(minuet and minuet.duration == 288 and minuet.duration_min == 240, 'Under Troubadour, 240 to 288: ' .. range(minuet));
minuet = on_bob(observer.read(sing(DAVE, 397, 198), 1, snapshot({ { effect = 52 } })));
assert(minuet and minuet.duration == 144 and minuet.duration_min == 120, 'Soul Voice makes Minuet stronger, not longer: ' .. range(minuet));
local hymnus = on_bob(observer.read(sing(DAVE, 464, 218), 1, snapshot({ { effect = 52 } })));
assert(hymnus and hymnus.duration == 288 and hymnus.duration_min == 240, 'Soul Voice makes Hymnus longer: ' .. range(hymnus));
hymnus = on_bob(observer.read(sing(DAVE, 464, 218), 1, snapshot({ { effect = 52 }, { effect = 348 } })));
assert(hymnus and hymnus.duration == 576 and hymnus.duration_min == 480, 'And Troubadour again: ' .. range(hymnus));
-- An alliance bard has no listing to read. A monster's song is the base alone.
minuet = on_bob(observer.read(sing(FRIEND, 397, 198), 1, snapshot()));
assert(minuet and minuet.duration == 144 and minuet.duration_min == 120, 'An alliance bard\'s Minuet: ' .. range(minuet));
minuet = on_bob(observer.read(sing(MOB, 397, 198), 1, snapshot()));
assert(minuet and minuet.duration == 120 and minuet.duration_min == 120, 'A monster\'s Minuet: ' .. range(minuet));

-- Through the party's listings: Bob's row still counts down 130 seconds after Dave's song, as the listing keeps it.
local client = require('core.client');
local tracker = require('core.tracker').new();
local mm = AshitaCore:GetMemoryManager();
AshitaCore.GetMemoryManager = function() return mm; end;
local party = mm:GetParty();
MOCK.player.server_id = SELF; MOCK.player.zone = 102; MOCK.player.index = 0x400;
local members = { [0] = { id = SELF, index = 0x400, zone = 102 }, [1] = { id = BOB, index = 0x401, zone = 102 }, [2] = { id = DAVE, index = 0x402, zone = 102 } };
for name, field in pairs({ GetMemberServerId = 'id', GetMemberTargetIndex = 'index', GetMemberZone = 'zone' }) do
    party[name] = function(_, slot) return members[slot] and members[slot][field] or 0; end;
end
party.GetMemberName = function(_, slot) return ({ [0] = 'Tester', 'Bob', 'Dave' })[slot] or ''; end;
party.GetMemberIsActive = function(_, slot) return members[slot] and 1 or 0; end;
party.GetMemberHPPercent = function() return 100; end;
party.GetStatusIconsServerId = function() return 0; end;
party.GetStatusIconsTargetIndex = function() return 0; end;
mm.GetEntity = function() return { GetServerId = function() return 0; end, GetName = function() return ''; end, GetSpawnFlags = function() return 0; end }; end;
-- A 0x076 listing Bob and Dave with their effects.
local function listing(bob, dave)
    local bytes = MOCK.bytes(244);
    for at, info in ipairs({ { BOB, 0x401, bob }, { DAVE, 0x402, dave } }) do
        local start = 4 + (at - 1) * 48;
        MOCK.put(bytes, start, 4, info[1]); MOCK.put(bytes, start + 4, 2, info[2]);
        for i = 0, 31 do bytes[start + 16 + i] = 255; end
        for i, effect in ipairs(info[3]) do bytes[start + 16 + i - 1] = effect; end
    end
    return MOCK.packet(0x076, bytes);
end
local queue, snap = {}, nil;
local function packet(e, now) for _, o in ipairs(observer.read(e, now, snap)) do queue[#queue + 1] = o; end end
local function refresh(now)
    snap = client.read(now);
    tracker:observe(queue, now, snap); queue = {};
    tracker:reconcile(snap, now);
    local found;
    for _, row in ipairs(tracker:view(now, {}, snap).rows) do if row.entity_id == BOB and row.effect == 198 then found = row; end end
    tracker:drain_events();
    return found;
end
refresh(0);
packet(listing({}, {}), 0.1);
refresh(0.2);
packet(sing(DAVE, 397, 198), 1.0);
packet(listing({ 198 }, { 198 }), 1.4);
local row = refresh(1.5);
assert(row and row.source == DAVE and row.spell == 397 and row.total == 144 and row.duration_min == 120, 'Fixture: Bob\'s Minuet is Dave\'s.');
packet(listing({ 198 }, { 198 }), 131.0);
row = refresh(131.1);
assert(row and row.remaining and row.remaining > 0 and row.status == 'estimated',
    'Bob\'s Minuet still counts down at 131 seconds: ' .. tostring(row and row.status) .. ', ' .. tostring(row and row.reason));
return 'Another player\'s buff song counts the range their instrument can give';
