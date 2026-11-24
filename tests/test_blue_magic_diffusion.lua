-- A blue magic buff lasts the base time its script passes, but under Diffusion the first copy made, the caster's own,
-- lasts longer by the caster's merits, and every copy after it gets the base (Phoenix globals/bluemagic.lua :1211-1219,
-- src/map/ai/helpers/targetfind.cpp :132-136). Vantage can't read another player's merits, so that copy gets no time:
-- when the caster's party listing shows Diffusion, or with no listing to read, when the cast reached more than one
-- target and the spell spreads only under Diffusion. Your own copy goes by the game's timer. Real 0x028s through
-- observer.read.
local observer = require('core.observer');
local SELF, ALLY, MEMBER, FRIEND, OTHER = 1001, 1002, 1003, 1007, 1008;
local DIFFUSION, HASTE, STONESKIN, EVASION_BOOST = 356, 33, 37, 92;
local REFUELING, FEATHER_BARRIER, DIAMONDHIDE = 530, 574, 632;
local NO_DURATION = 'No duration for this action';
-- Ally is the party's BLU and Member is in the party too. Friend is a BLU in the alliance's other party, and Other is in
-- that party. The game lists only your own party's effects (src/map/party.cpp :1219-1246). listed holds each party
-- member's effects, by id.
local function snapshot(listed, revision, self_effects)
    listed = listed or {};
    return { valid = true, id = SELF, name = 'Tester', zone = 151, job = 16, level = 75, self_known = true, self_revision = 1,
        self_timer_revision = 1, self_effects = self_effects or {},
        party = { { id = ALLY, name = 'Ally', scope = 'party', group = 1, slot = 1, zone = 151, valid = true,
                revision = revision or 1, effects = listed[ALLY] or {} },
            { id = MEMBER, name = 'Member', scope = 'party', group = 1, slot = 2, zone = 151, valid = true,
                revision = revision or 1, effects = listed[MEMBER] or {} },
            { id = FRIEND, name = 'Friend', scope = 'alliance', group = 2, slot = 6, zone = 151, valid = false, effects = {} },
            { id = OTHER, name = 'Other', scope = 'alliance', group = 2, slot = 7, zone = 151, valid = false, effects = {} } },
        entities = { [SELF] = { id = SELF, name = 'Tester', kind = 'player' }, [ALLY] = { id = ALLY, name = 'Ally', kind = 'player' },
            [MEMBER] = { id = MEMBER, name = 'Member', kind = 'player' }, [FRIEND] = { id = FRIEND, name = 'Friend', kind = 'player' },
            [OTHER] = { id = OTHER, name = 'Other', kind = 'player' } } };
end
-- A spell of actor's, one row for each target: { target, message, param }. The first target, the caster for these, gets
-- the spell's own message, 230, and each one after it the area form, 266 (src/map/entities/battle_entity.cpp
-- :2503-2517). The param is the effect.
local function cast(actor, spell, rows)
    local targets = {};
    for i, row in ipairs(rows) do targets[i] = { id = row[1], rows = { { message = row[2], param = row[3] } } }; end
    return MOCK.packet(0x028, MOCK.action_bytes(actor, 4, spell, targets));
end
-- What the observer gives each target's copy, by target.
local function copies(packet, snap)
    local out = {};
    for _, seen in ipairs(observer.read(packet, 1, snap)) do
        if seen.kind == 'apply' then out[seen.entity_id] = seen; end
    end
    return out;
end
local function seconds(copy) return copy and tostring(copy.duration) or 'no copy'; end
local DIFFUSED = { [ALLY] = { { effect = DIFFUSION, slot = 0 } } };

-- A party BLU's Refueling under Diffusion reaches the party. Their own copy gets no time, and the member's copy gets the
-- base.
local seen = copies(cast(ALLY, REFUELING, { { ALLY, 230, HASTE }, { MEMBER, 266, HASTE } }), snapshot(DIFFUSED));
assert(seen[ALLY] and seen[ALLY].duration == nil and seen[ALLY].duration_min == nil and seen[ALLY].basis == NO_DURATION,
    'A party BLU\'s own Refueling under Diffusion gets no time: ' .. seconds(seen[ALLY]));
assert(seen[MEMBER] and seen[MEMBER].duration == 300, 'The member\'s copy is the base 300: ' .. seconds(seen[MEMBER]));
-- Feather Barrier never spreads (sql/spell_list.sql :741), so only the listing tells it was cast under Diffusion.
seen = copies(cast(ALLY, FEATHER_BARRIER, { { ALLY, 230, EVASION_BOOST } }), snapshot(DIFFUSED));
assert(seen[ALLY] and seen[ALLY].duration == nil, 'Their own Feather Barrier under Diffusion gets no time: ' .. seconds(seen[ALLY]));

-- The same BLU with no Diffusion: Refueling reaches only them, for the base. Diamondhide reaches the party all the same
-- (sql/spell_list.sql :699, :796), and their listing says Diffusion wasn't up, so every copy gets the base.
seen = copies(cast(ALLY, REFUELING, { { ALLY, 230, HASTE } }), snapshot());
assert(seen[ALLY] and seen[ALLY].duration == 300, 'Their own Refueling with no Diffusion is the base 300: ' .. seconds(seen[ALLY]));
seen = copies(cast(ALLY, DIAMONDHIDE, { { ALLY, 230, STONESKIN }, { MEMBER, 266, STONESKIN } }), snapshot());
assert(seen[ALLY] and seen[ALLY].duration == 300 and seen[MEMBER] and seen[MEMBER].duration == 300,
    'Diamondhide with no Diffusion is the base 300 on both: ' .. seconds(seen[ALLY]) .. ', ' .. seconds(seen[MEMBER]));

-- An alliance BLU has no listing to read. Their Refueling that reached two targets was cast under Diffusion.
seen = copies(cast(FRIEND, REFUELING, { { FRIEND, 230, HASTE }, { OTHER, 266, HASTE } }), snapshot());
assert(seen[FRIEND] and seen[FRIEND].duration == nil and seen[FRIEND].duration_min == nil and seen[FRIEND].basis == NO_DURATION,
    'An alliance BLU\'s own Refueling that reached two targets gets no time: ' .. seconds(seen[FRIEND]));
assert(seen[OTHER] and seen[OTHER].duration == 300, 'The other copy is the base 300: ' .. seconds(seen[OTHER]));
-- One that reached only them says nothing of Diffusion, and Diamondhide can spread without it, so both keep the base.
seen = copies(cast(FRIEND, REFUELING, { { FRIEND, 230, HASTE } }), snapshot());
assert(seen[FRIEND] and seen[FRIEND].duration == 300, 'Their Refueling on themselves alone is the base 300: ' .. seconds(seen[FRIEND]));
seen = copies(cast(FRIEND, DIAMONDHIDE, { { FRIEND, 230, STONESKIN }, { OTHER, 266, STONESKIN } }), snapshot());
assert(seen[FRIEND] and seen[FRIEND].duration == 300, 'Their Diamondhide is the base 300: ' .. seconds(seen[FRIEND]));

-- Your own cast under Diffusion is left as it was: the game's timer gives your copy its time.
seen = copies(cast(SELF, REFUELING, { { SELF, 230, HASTE }, { ALLY, 266, HASTE } }),
    snapshot(nil, nil, { { effect = DIFFUSION, slot = 0 } }));
assert(seen[SELF] and seen[SELF].duration == 300 and seen[ALLY] and seen[ALLY].duration == 300,
    'Your own Refueling under Diffusion is left as it was: ' .. seconds(seen[SELF]) .. ', ' .. seconds(seen[ALLY]));

-- The tracker. A 0x028 is read with the listing from before it, which still shows Diffusion, as Phoenix sends the
-- listing once the action is done (src/map/ai/states/magic_state.cpp :327, src/map/ai/ai_container.cpp :564,
-- src/map/entities/char_entity.cpp :1190-1200). The next refresh's listing shows Haste.
local tracker = require('core.tracker').new();
local function step(now, packets, before, after)
    local observations = {};
    for _, packet in ipairs(packets) do
        for _, observation in ipairs(observer.read(packet, now, before)) do observations[#observations + 1] = observation; end
    end
    after = after or before;
    tracker:observe(observations, now, after);
    tracker:reconcile(after, now);
    return tracker:view(now, {}, after).rows;
end
local function find(rows, id, effect)
    for _, row in ipairs(rows) do if row.entity_id == id and row.effect == effect then return row; end end
end
local HASTED = { [ALLY] = { { effect = HASTE, slot = 0 } }, [MEMBER] = { { effect = HASTE, slot = 0 } } };
step(50, {}, snapshot(DIFFUSED));
local rows = step(51, { cast(ALLY, REFUELING, { { ALLY, 230, HASTE }, { MEMBER, 266, HASTE } }) }, snapshot(DIFFUSED),
    snapshot(HASTED, 2));
local own, member = find(rows, ALLY, HASTE), find(rows, MEMBER, HASTE);
assert(own and own.status == 'unknown' and own.total == nil and own.reason == NO_DURATION,
    'The BLU\'s own Haste shows with no countdown: ' .. tostring(own and own.status) .. ', ' .. tostring(own and own.total));
assert(member and member.status == 'estimated' and member.total == 300,
    'The member\'s Haste counts down 300: ' .. tostring(member and member.status) .. ', ' .. tostring(member and member.total));
return 'A BLU\'s own blue magic buff cast under Diffusion gets no time, and every other copy the base';
