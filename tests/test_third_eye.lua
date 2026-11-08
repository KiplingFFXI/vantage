-- Third Eye and Seigan on Phoenix: Third Eye lasts 30 seconds and Seigan 300 (globals/job_utils/samurai.lua :115, :156), and
-- Utsusemi takes Third Eye off (enhancing_ninjutsu.lua :111-114). Its wear-off reaches only its owner, so on a mob or an
-- alliance member it goes when Vantage sees it anticipate an attack (message 30) with no Seigan up, sees a melee swing land
-- on them, or sees them cast Utsusemi. Your party is read from your listings, and other players aren't followed. Real
-- 0x028s through observer.read.
local observer = require('core.observer');
local catalog = require('core.catalog');
local SELF, ALLY, FRIEND, STRANGER, MOB = 1001, 1002, 1007, 1009, 0x1000123;
-- Friend is a NIN in the alliance's second party.
local party = { GetMemberMainJob = function() return 13; end, GetMemberZone2 = function() return 0; end,
    GetMemberLastUpdatedTimestamp = function() return 1700000000; end };
AshitaCore.GetMemoryManager = function() return { GetParty = function() return party; end }; end;
local function snapshot(listed, revision)
    return { valid = true, id = SELF, name = 'Tester', zone = 151, job = 12, level = 75, self_known = true, self_revision = 1,
        self_timer_revision = 1, self_effects = {},
        party = { { id = ALLY, name = 'Ally', scope = 'party', group = 1, slot = 1, zone = 151, valid = true, revision = revision or 1,
                effects = listed or {} },
            { id = FRIEND, name = 'Friend', scope = 'alliance', group = 2, slot = 6, zone = 151, valid = false, effects = {} } },
        entities = { [SELF] = { id = SELF, name = 'Tester', kind = 'player' }, [ALLY] = { id = ALLY, name = 'Ally', kind = 'player' },
            [FRIEND] = { id = FRIEND, name = 'Friend', kind = 'player' }, [STRANGER] = { id = STRANGER, name = 'Stranger', kind = 'player' },
            [MOB] = { id = MOB, name = 'Yagudo Conquistador', kind = 'monster' } } };
end;
local function putbits(bytes, offset, length, value)
    for i = 0, length - 1 do
        local at = offset + i;
        if math.floor(value / 2 ^ i) % 2 == 1 then bytes[math.floor(at / 8)] = bytes[math.floor(at / 8)] + 2 ^ (at % 8); end
    end
end
-- One target row: { target, message, param, added, added_param, reaction, reaction_param }.
local function action(actor, category, id, rows)
    local bytes, at = MOCK.bytes(2048), 150;
    putbits(bytes, 40, 32, actor); putbits(bytes, 72, 6, #rows); putbits(bytes, 82, 4, category); putbits(bytes, 86, 32, id);
    for _, row in ipairs(rows) do
        putbits(bytes, at, 32, row[1]); putbits(bytes, at + 32, 4, 1); at = at + 36;
        putbits(bytes, at + 27, 17, row[3] or 0); putbits(bytes, at + 44, 10, row[2] or 0); at = at + 85;
        putbits(bytes, at, 1, row[4] and 1 or 0); at = at + 1;
        if row[4] then putbits(bytes, at + 10, 17, row[5] or 0); putbits(bytes, at + 27, 10, row[4]); at = at + 37; end
        putbits(bytes, at, 1, row[6] and 1 or 0); at = at + 1;
        if row[6] then putbits(bytes, at + 10, 14, row[7] or 0); putbits(bytes, at + 24, 10, row[6]); at = at + 34; end
    end
    bytes.n = math.ceil(at / 8);
    return MOCK.packet(0x028, bytes);
end
-- A job ability on its user: 100 names the effect it put on, and 156 is one that had no effect.
local function ability(who, id, effect, message) return action(who, 6, id, { { who, message or 100, effect } }); end
local function first(events, kind)
    for _, event in ipairs(events) do if event.kind == kind then return event; end end
end

-- The lengths, and Utsusemi's drop.
assert(catalog.duration('abilities', 62, 67) == 30, 'Third Eye lasts 30 seconds.');
assert(catalog.duration('abilities', 174, 354) == 300, 'Seigan lasts 300.');
local drops = {};
for _, id in ipairs(catalog.drops(66)) do drops[id] = true; end;
assert(drops[67], 'Utsusemi takes Third Eye off.');

-- An alliance member's Third Eye and Seigan, and a Third Eye that had no effect, as Copy Image was up.
local used = first(observer.read(ability(FRIEND, 62, 67), 1, snapshot()), 'apply');
assert(used and used.effect == 67 and used.duration == 30 and used.scope == 'alliance', 'Third Eye for 30 seconds.');
local seigan = first(observer.read(ability(FRIEND, 174, 354), 1, snapshot()), 'apply');
assert(seigan and seigan.effect == 354 and seigan.duration == 300, 'Seigan for 300.');
assert(first(observer.read(ability(FRIEND, 62, 67, 156), 1, snapshot()), 'apply') == nil, 'One with no effect puts nothing on.');

-- Message 30 on a mob's or an alliance member's row, from a swing or a mob skill. You and your party are read from your
-- listings, and other players aren't followed.
local seen = first(observer.read(action(MOB, 1, 0, { { FRIEND, 30, 0 } }), 1, snapshot()), 'anticipated');
assert(seen and seen.entity_id == FRIEND and seen.scope == 'alliance', 'An alliance member\'s Third Eye anticipated a swing.');
seen = first(observer.read(action(MOB, 11, 500, { { FRIEND, 30, 0 } }), 1, snapshot()), 'anticipated');
assert(seen and seen.entity_id == FRIEND, 'And a mob skill.');
seen = first(observer.read(action(ALLY, 1, 0, { { MOB, 30, 0 } }), 1, snapshot()), 'anticipated');
assert(seen and seen.entity_id == MOB and seen.scope == 'enemy', 'A mob\'s Third Eye anticipated a swing.');
for _, who in ipairs({ SELF, ALLY, STRANGER }) do
    assert(first(observer.read(action(MOB, 1, 0, { { who, 30, 0 } }), 1, snapshot()), 'anticipated') == nil, 'Not followed for ' .. who .. '.');
end;

-- The tracker.
local tracker = require('core.tracker').new();
local function step(now, packets, listed, revision)
    local snap, observations = snapshot(listed, revision), {};
    for _, packet in ipairs(packets) do for _, o in ipairs(observer.read(packet, now, snap)) do observations[#observations + 1] = o; end end
    tracker:observe(observations, now, snap); tracker:reconcile(snap, now);
    return tracker:view(now, {}, snap).rows, tracker:drain_events();
end;
local function find(rows, id, effect)
    for _, row in ipairs(rows) do if row.entity_id == id and row.effect == effect then return row; end end
end;
local function removed(events, id, effect)
    for _, event in ipairs(events) do
        if event.kind == 'removed' and event.entity_id == id and event.effect == effect then return event; end
    end
end;
-- An alliance member's Third Eye counts down its 30 seconds, and goes when it anticipates an attack.
local rows, events = step(10, { ability(FRIEND, 62, 67) });
local row = find(rows, FRIEND, 67);
assert(row and row.total == 30 and row.remaining == 30 and row.scope == 'alliance', 'Third Eye counts down 30 seconds.');
rows, events = step(12, { action(MOB, 1, 0, { { FRIEND, 30, 0 } }) });
local gone = removed(events, FRIEND, 67);
assert(not find(rows, FRIEND, 67) and gone and gone.reason == 'It anticipated an attack.', 'It anticipated a swing.');
-- Seigan may keep it, which can't be seen, so it stays until its time is up or a swing lands.
rows = step(20, { ability(FRIEND, 174, 354), ability(FRIEND, 62, 67) });
assert(find(rows, FRIEND, 354) and find(rows, FRIEND, 354).total == 300 and find(rows, FRIEND, 67), 'Seigan, then Third Eye.');
rows = step(22, { action(MOB, 1, 0, { { FRIEND, 30, 0 } }) });
assert(find(rows, FRIEND, 67), 'Seigan kept it.');
rows = step(24, { action(MOB, 4, 144, { { FRIEND, 2, 300 } }) });
assert(find(rows, FRIEND, 67), 'A spell isn\'t an attack it anticipates.');
rows, events = step(26, { action(MOB, 1, 0, { { FRIEND, 1, 40 } }) });
gone = removed(events, FRIEND, 67);
assert(not find(rows, FRIEND, 67) and gone and gone.reason == 'A swing landed, so nothing anticipated it.' and find(rows, FRIEND, 354),
    'A swing landed, so it was gone. Seigan stays.');
-- Utsusemi takes it off.
rows = step(30, { ability(FRIEND, 62, 67) });
assert(find(rows, FRIEND, 67), 'Third Eye again.');
rows = step(31, { action(FRIEND, 4, 339, { { FRIEND, 230, 66 } }) });
assert(not find(rows, FRIEND, 67) and find(rows, FRIEND, 66) and find(rows, FRIEND, 66).icon == 446, 'Utsusemi took it off.');

-- A mob's goes the same ways. A Sneak Attack round goes past shadows but not Third Eye, and a swing for nothing says nothing.
rows = step(40, { ability(MOB, 62, 67) });
assert(find(rows, MOB, 67) and find(rows, MOB, 67).total == 30, 'A mob\'s Third Eye.');
rows, events = step(41, { action(ALLY, 1, 0, { { MOB, 30, 0 } }) });
assert(not find(rows, MOB, 67) and removed(events, MOB, 67), 'It anticipated a swing.');
step(42, { ability(MOB, 62, 67) });
rows = step(43, { action(ALLY, 1, 0, { { MOB, 1, 0 } }) });
assert(find(rows, MOB, 67), 'A swing for nothing.');
rows, events = step(44, { action(ALLY, 6, 44, { { ALLY, 100, 0 } }), action(ALLY, 1, 0, { { MOB, 67, 300 } }) });
gone = removed(events, MOB, 67);
assert(not find(rows, MOB, 67) and gone and gone.reason == 'A swing landed, so nothing anticipated it.', 'A Sneak Attack hit landed.');

-- Your party's Third Eye is read from their listing, and counts down its 30 seconds.
step(50, {}, {}, 1);
rows = step(51, { ability(ALLY, 62, 67) }, { { effect = 67, slot = 0 } }, 2);
row = find(rows, ALLY, 67);
assert(row and row.total == 30 and row.remaining == 30 and row.scope == 'party', 'A party member\'s Third Eye counts down 30 seconds.');

-- Nothing changes either length, so an alliance member's goes when its time is up, with no wear-off to see.
rows = step(60, { ability(FRIEND, 174, 354), ability(FRIEND, 62, 67) });
assert(find(rows, FRIEND, 67).exact and find(rows, FRIEND, 354).exact, 'Both lengths are exact.');
rows = step(89.9, {});
assert(find(rows, FRIEND, 67) and find(rows, FRIEND, 67).remaining < 0.2, 'Third Eye a moment before its time is up.');
rows = step(90, {});
assert(not find(rows, FRIEND, 67) and find(rows, FRIEND, 354), 'Third Eye is gone at 30 seconds, and Seigan stays.');
rows = step(359.9, {});
assert(find(rows, FRIEND, 354), 'Seigan a moment before its time is up.');
rows = step(360, {});
assert(not find(rows, FRIEND, 354), 'Seigan is gone at 300 seconds.');

-- Third Eye has no effect while Blink or Copy Image is up (samurai.lua :108-113), so one that lands takes both off,
-- Copy Image at any icon, the one for a last shadow (66) too.
drops = {};
for _, id in ipairs(catalog.drops(67)) do drops[id] = true; end;
assert(drops[36] and drops[66], 'Third Eye takes Blink and Copy Image off.');
rows = step(400, { action(MOB, 4, 53, { { MOB, 230, 36 } }) });
assert(find(rows, MOB, 36), 'A mob\'s Blink.');
rows = step(401, { ability(MOB, 62, 67) });
assert(find(rows, MOB, 67) and not find(rows, MOB, 36), 'Third Eye took Blink off.');
rows = step(402, { action(MOB, 4, 339, { { MOB, 230, 66 } }) });
assert(find(rows, MOB, 66) and find(rows, MOB, 66).icon == 446 and not find(rows, MOB, 67), 'Utsusemi took Third Eye off.');
rows = step(403, { action(ALLY, 2, 0, { { MOB, 31, 3 } }) });
assert(find(rows, MOB, 66) and find(rows, MOB, 66).icon == nil, 'One shadow left.');
rows = step(404, { ability(MOB, 62, 67) });
assert(find(rows, MOB, 67) and not find(rows, MOB, 66), 'Third Eye took Copy Image off at its last shadow.');
return 'Third Eye counts down 30 seconds and goes when it anticipates an attack, a swing lands, Utsusemi goes on or its time is up';
