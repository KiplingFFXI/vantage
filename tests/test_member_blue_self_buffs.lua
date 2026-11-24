-- Reactor Cool, Saline Coat, Plasma Charge, Warm-Up and Amplification each pass a set time to the same Phoenix
-- calculateDurationWithDiffusion as Cocoon: 120, 180, 60, 180 and 90 seconds (actions/spells/blue/reactor_cool.lua :24,
-- saline_coat.lua :26, plasma_charge.lua :25, warm-up.lua :24, amplification.lua :24, cocoon.lua :25). So a party BLU's
-- cast of one counts down its time, as their Cocoon does, and under Diffusion their own copy gets no time, as their
-- Refueling's does (tests/test_blue_magic_diffusion.lua). Real 0x028s through observer.read.
local observer = require('core.observer');
local catalog = require('core.catalog');
local SELF, ALLY, MEMBER, DIFFUSION = 1001, 1002, 1003, 356;
local function snapshot(ally_effects)
    return { valid = true, id = SELF, name = 'Tester', zone = 151, job = 16, level = 75, self_known = true, self_revision = 1,
        self_timer_revision = 1, self_effects = {},
        party = { { id = ALLY, name = 'Ally', scope = 'party', group = 1, slot = 1, zone = 151, valid = true,
                revision = 1, effects = ally_effects or {} },
            { id = MEMBER, name = 'Member', scope = 'party', group = 1, slot = 2, zone = 151, valid = true,
                revision = 1, effects = {} } },
        entities = { [SELF] = { id = SELF, name = 'Tester', kind = 'player' }, [ALLY] = { id = ALLY, name = 'Ally', kind = 'player' },
            [MEMBER] = { id = MEMBER, name = 'Member', kind = 'player' } } };
end
-- A spell of actor's, one row for each target: { target, message, param }.
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

-- { spell, the effect its result names, its seconds, name }. Warm-Up and Amplification each put on two effects, and the
-- result names the second when only that one took.
for _, case in ipairs({ { 547, 93, 90, 'Cocoon' }, { 613, 93, 120, 'Reactor Cool' },
    { 614, 191, 180, 'Saline Coat' }, { 615, 38, 60, 'Plasma Charge' }, { 636, 90, 180, 'Warm-Up' }, { 636, 92, 180, 'Warm-Up' },
    { 642, 190, 90, 'Amplification' }, { 642, 191, 90, 'Amplification' } }) do
    local copy = copies(cast(ALLY, case[1], { { ALLY, 230, case[2] } }), snapshot())[ALLY];
    assert(copy and copy.duration == case[3] and copy.duration_min == case[3],
        'A party BLU\'s ' .. case[4] .. ' (' .. case[2] .. ') counts down ' .. case[3] .. ' seconds: ' .. tostring(copy and copy.duration)
        .. ', ' .. tostring(copy and copy.basis));
    -- Under Diffusion, their own copy gets no time.
    local action = { category = 4, id = case[1], actor = ALLY, rows = { { target = ALLY }, { target = MEMBER } } };
    assert(catalog.diffused(action, snapshot({ { effect = DIFFUSION, slot = 0 } })) == true,
        case[4] .. ' cast under Diffusion is read as that.');
end
return 'A party BLU\'s blue magic self buffs count down their Phoenix time';
