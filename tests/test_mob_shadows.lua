-- A mob's Utsusemi shows how many shadows it has, as Vantage counts them: Ichi 3, Ni 4 and San 5, Ni 3 for Ark Angel HM and
-- Shikaree X, then one less for each shadow seen taking a hit, and none once a hit gets through. A Sneak or Trick Attack's
-- hits say nothing until its user's next melee round. You and your party are read from your listings, and the alliance
-- has test_alliance_shadows.lua. At every count the row is Copy Image (66) with the count's icon, so it lights for Dispel.
-- Real 0x028s through observer.read.
local observer = require('core.observer');
local dispel = require('core.dispel');
local SELF, ALLY, MOB, ARK, SHIKAREE = 1001, 1002, 0x1000123, 0x1000125, 0x1000126;
local function snapshot()
    return { valid = true, id = SELF, name = 'Tester', zone = 151, job = 6, level = 75, self_known = true, self_revision = 1,
        self_timer_revision = 1, self_effects = {}, party = { { id = ALLY, name = 'Ally', scope = 'party' } },
        entities = { [SELF] = { id = SELF, name = 'Tester', kind = 'player' }, [ALLY] = { id = ALLY, name = 'Ally', kind = 'player' },
            [MOB] = { id = MOB, name = 'Yagudo Conquistador', kind = 'monster' },
            [ARK] = { id = ARK, name = 'Ark Angel HM', kind = 'monster' }, [SHIKAREE] = { id = SHIKAREE, name = 'Shikaree X', kind = 'monster' } },
        target = { id = MOB, name = 'Yagudo Conquistador', kind = 'monster' } };
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
-- Utsusemi lands with 230 and names Copy Image (enhancing_ninjutsu.lua :118-123); a lower tier over a higher has no effect, 75.
local function utsusemi(who, spell, message) return action(who, 4, spell, { { who, message or 230, 66 } }); end
local function first(events, kind)
    for _, event in ipairs(events) do if event.kind == kind then return event; end end
end

-- The count each cast starts.
for spell, count in pairs({ [338] = 3, [339] = 4, [340] = 5 }) do
    local cast = first(observer.read(utsusemi(MOB, spell), 1, snapshot()), 'apply');
    assert(cast and cast.effect == 66 and cast.shadows == count and cast.scope == 'enemy', 'Spell ' .. spell .. ' gives ' .. count .. '.');
end;
for _, who in ipairs({ ARK, SHIKAREE }) do
    assert(first(observer.read(utsusemi(who, 339), 1, snapshot()), 'apply').shadows == 3, 'Ni gives a WAR or BST main one less.');
    assert(first(observer.read(utsusemi(who, 338), 1, snapshot()), 'apply').shadows == 3, 'Ichi has no such penalty.');
end;
assert(first(observer.read(utsusemi(MOB, 338, 75), 1, snapshot()), 'apply') == nil, 'A cast with no effect changes nothing.');
local yours = first(observer.read(utsusemi(ALLY, 339), 1, snapshot()), 'apply');
assert(yours and yours.scope == 'party' and yours.shadows == nil, 'A party member\'s count is their listing\'s.');

-- What the shadows took: message 31 with how many, and the counter to the mob's own attack (reaction 14).
local taken = first(observer.read(action(ALLY, 1, 0, { { MOB, 31, 1 } }), 1, snapshot()), 'shadows');
assert(taken and taken.entity_id == MOB and taken.lost == 1 and taken.scope == 'enemy', 'A swing a shadow took.');
assert(first(observer.read(action(ALLY, 2, 0, { { MOB, 31, 2 } }), 1, snapshot()), 'shadows').lost == 2, 'Two shots the shadows took.');
local countered = first(observer.read(action(MOB, 1, 0, { { ALLY, 0, 0, nil, nil, 14, 1 } }), 1, snapshot()), 'shadows');
assert(countered and countered.entity_id == MOB and countered.lost == 1, 'A counter the mob\'s shadow took.');
assert(first(observer.read(action(MOB, 1, 0, { { ALLY, 31, 1 } }), 1, snapshot()), 'shadows') == nil, 'Your party\'s shadows are your listing\'s.');

-- A hit for damage that got through: melee, ranged, Barrage and Sange, a weapon skill, and a counter. A spell or a hit for 0
-- says nothing.
local function through(events)
    local hit = first(events, 'damage');
    return hit ~= nil and hit.entity_id == MOB and hit.through == true;
end;
for category, messages in pairs({ [1] = { 1, 67 }, [2] = { 77, 157, 352, 353, 576, 577 }, [3] = { 185 } }) do
    for _, message in ipairs(messages) do
        assert(through(observer.read(action(ALLY, category, 0, { { MOB, message, 40 } }), 1, snapshot())),
            'Category ' .. category .. ' message ' .. message .. ' got through.');
    end;
end;
assert(through(observer.read(action(MOB, 1, 0, { { ALLY, 0, 0, nil, nil, 33, 20 } }), 1, snapshot())), 'A counter that hit the mob.');
assert(not through(observer.read(action(SELF, 4, 144, { { MOB, 2, 300 } }), 1, snapshot())), 'A spell can go past shadows.');
assert(first(observer.read(action(ALLY, 1, 0, { { MOB, 1, 0 } }), 1, snapshot()), 'damage') == nil, 'A deflected swing is a hit for nothing.');
local after = observer.read(action(ALLY, 1, 0, { { MOB, 31, 1 }, { MOB, 1, 40 } }), 1, snapshot());
assert(after[1].kind == 'shadows' and after[2].kind == 'damage' and after[2].through, 'A loss, then the hit that got through, in order.');

-- A Sneak or Trick Attack: its user's weapon skills say nothing until their next melee round, which says nothing either.
for _, ability in ipairs({ 44, 76 }) do
    observer.read(action(ALLY, 6, ability, { { ALLY, 100, 0 } }), 1, snapshot());
    assert(not through(observer.read(action(ALLY, 3, 0, { { MOB, 185, 900 } }), 1, snapshot())), 'A weapon skill after ' .. ability .. '.');
    assert(through(observer.read(action(SELF, 1, 0, { { MOB, 1, 40 } }), 1, snapshot())), 'Someone else\'s hits still count.');
    assert(not through(observer.read(action(ALLY, 1, 0, { { MOB, 1, 40 }, { MOB, 1, 40 } }), 1, snapshot())), 'The round after ' .. ability .. '.');
    assert(through(observer.read(action(ALLY, 1, 0, { { MOB, 1, 40 } }), 1, snapshot())), 'The round after that.');
end;
observer.read(action(ALLY, 6, 44, { { ALLY, 100, 0 } }), 1, snapshot());
local zone = MOCK.bytes(0x100);
MOCK.put(zone, 4, 4, SELF); MOCK.put(zone, 0x30, 2, 151);
observer.read(MOCK.packet(0x00A, zone), 1, snapshot());
assert(through(observer.read(action(ALLY, 1, 0, { { MOB, 1, 40 } }), 1, snapshot())), 'A zone change forgets it.');

-- The tracker: the row is Copy Image (66), and its icon shows the count, 446 for 4 or more, 445 for 3, 444 for 2 and 66 for 1.
local tracker = require('core.tracker').new();
local function step(now, packets)
    local snap, observations = snapshot(), {};
    for _, packet in ipairs(packets) do for _, o in ipairs(observer.read(packet, now, snap)) do observations[#observations + 1] = o; end end
    tracker:observe(observations, now, snap); tracker:reconcile(snap, now);
    local rows = {};
    for _, row in ipairs(tracker:view(now, {}, snap).rows) do if row.entity_id == MOB then rows[#rows + 1] = row; end end
    return rows[1], #rows, tracker:drain_events();
end;
local function removed(events)
    for _, event in ipairs(events) do if event.kind == 'removed' then return event; end end
end;
local function icon(row) return row.icon or row.effect; end;
local row, count, events = step(10, { utsusemi(MOB, 339) });
assert(count == 1 and row.effect == 66 and row.icon == 446 and row.shadows == 4 and row.name == 'Copy Image'
    and dispel.buffs[row.effect], 'Ni shows four, as Copy Image, which Dispel can take.');
for at, wanted in ipairs({ 445, 444, 66 }) do
    row = step(10 + at, { action(ALLY, 1, 0, { { MOB, 31, 1 } }) });
    assert(row.effect == 66 and icon(row) == wanted and row.shadows == 4 - at, 'A shadow goes: ' .. wanted .. '.');
end;
row, count, events = step(20, { action(ALLY, 1, 0, { { MOB, 31, 1 } }) });
local gone = removed(events);
assert(count == 0 and gone and gone.reason == 'Its last shadow took a hit.' and gone.effect == 66, 'The last one goes with the icon.');
-- A recast starts again. Ichi over Ni has no effect, and over its last shadow Ichi starts three.
row = step(30, { utsusemi(MOB, 339) });
row = step(31, { action(ALLY, 2, 0, { { MOB, 31, 3 } }) });
assert(row.effect == 66 and icon(row) == 66 and row.shadows == 1, 'Three shots the shadows took.');
row = step(32, { utsusemi(MOB, 338, 75) });
assert(row.effect == 66 and icon(row) == 66 and row.shadows == 1, 'Ichi over Ni changed nothing.');
row = step(33, { utsusemi(MOB, 338) });
assert(row.effect == 66 and row.icon == 445 and row.shadows == 3, 'Ichi after the last shadow starts three.');
-- A hit that got through ends it, whatever was counted.
row, count, events = step(34, { action(SELF, 1, 0, { { MOB, 1, 52 } }) });
gone = removed(events);
assert(count == 0 and gone and gone.reason == 'A hit got through, so it had no shadows left.' and gone.effect == 66 and gone.icon == 445,
    'A hit got through, and the removal reads as Copy Image at its icon.');
-- San's five show as four or more until the fifth goes.
row = step(40, { utsusemi(MOB, 340) });
assert(row.effect == 66 and row.icon == 446 and row.shadows == 5, 'San shows four or more.');
row = step(41, { action(ALLY, 1, 0, { { MOB, 31, 1 } }) });
assert(row.effect == 66 and row.icon == 446 and row.shadows == 4, 'Four left still shows four or more.');
row = step(42, { action(MOB, 1, 0, { { ALLY, 0, 0, nil, nil, 14, 1 } }) });
assert(row.effect == 66 and row.icon == 445 and row.shadows == 3, 'The counter its shadow took.');
-- A Sneak Attack round goes through shadows without taking one, and the count stays.
row = step(43, { action(ALLY, 6, 44, { { ALLY, 100, 0 } }), action(ALLY, 1, 0, { { MOB, 67, 300 }, { MOB, 1, 80 } }) });
assert(row and row.effect == 66 and row.icon == 445 and row.shadows == 3, 'A Sneak Attack round left it.');
-- Each shadow lost keeps the icon three minutes from then, as anything seen does.
row = step(150, { action(ALLY, 1, 0, { { MOB, 31, 1 } }) });
assert(row.effect == 66 and row.icon == 444 and row.observed_at == 150, 'A shadow seen going.');
row, count = step(300, {});
assert(count == 1, 'Still there two and a half minutes on.');
row, count = step(340, {});
assert(count == 0, 'Gone over three minutes after the last thing seen.');

-- Dispel's list is Phoenix's and names the effect only, which every count's row is.
assert(dispel.buffs[66] and not dispel.buffs[444] and not dispel.buffs[445] and not dispel.buffs[446], 'The list names the effect only.');

-- Blink takes Copy Image off at any icon, the one for a last shadow (66) too.
step(400, { utsusemi(MOB, 339) });
row = step(401, { action(ALLY, 2, 0, { { MOB, 31, 3 } }) });
assert(row.effect == 66 and icon(row) == 66 and row.shadows == 1, 'One shadow left.');
row, count = step(402, { action(MOB, 4, 53, { { MOB, 230, 36 } }) });
assert(count == 1 and row.effect == 36, 'Blink took Copy Image off at its last shadow.');
