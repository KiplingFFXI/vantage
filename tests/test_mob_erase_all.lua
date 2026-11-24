-- A monster's move that takes every erasable effect off: Depuration (1381), Rapid Molt (1368) and Voidsong (649) off its
-- user, and Benediction (689) off each mob it reaches (Phoenix actions/mobskills/depuration.lua, rapid_molt.lua,
-- voidsong.lua, benediction.lua, status_effect_container.cpp EraseAllStatusEffect :930-945). Each erased effect's wear-off
-- goes only to whoever cast it (:657-669), so a party member's Slow ends with the move itself. What isn't erasable stays.
-- Real 0x028s through observer.read and the tracker.
local observer = require('core.observer');
local SELF, ALLY, AERN, HPEMDE, DRAGON, MOB2 = 1001, 1002, 0x1000123, 0x1000124, 0x1000125, 0x1000126;
local function snapshot()
    return { valid = true, id = SELF, name = 'Tester', zone = 33, job = 5, level = 75, self_known = true, self_revision = 1,
        self_timer_revision = 1, self_effects = {}, party = { { id = ALLY, name = 'Ally', scope = 'party' } },
        entities = { [SELF] = { id = SELF, name = 'Tester', kind = 'player' }, [ALLY] = { id = ALLY, name = 'Ally', kind = 'player' },
            [AERN] = { id = AERN, name = 'Aern', kind = 'monster' }, [HPEMDE] = { id = HPEMDE, name = 'Hpemde', kind = 'monster' },
            [DRAGON] = { id = DRAGON, name = 'Wyrm', kind = 'monster' }, [MOB2] = { id = MOB2, name = 'Aern', kind = 'monster' } } };
end;
-- One target row: { target, message, param }.
local function action(actor, category, id, rows)
    local targets = {};
    for i, row in ipairs(rows) do targets[i] = { id = row[1], rows = { { message = row[2], param = row[3] } } }; end
    return MOCK.packet(0x028, MOCK.action_bytes(actor, category, id, targets));
end
local tracker = require('core.tracker').new();
-- The effects each mob's rows show after the packets, sorted, and the removals they made.
local function step(now, packets)
    local snap, observations = snapshot(), {};
    for _, packet in ipairs(packets) do for _, o in ipairs(observer.read(packet, now, snap)) do observations[#observations + 1] = o; end end
    tracker:observe(observations, now, snap); tracker:reconcile(snap, now);
    local shown = {};
    for _, row in ipairs(tracker:view(now, {}, snap).rows) do
        shown[row.entity_id] = shown[row.entity_id] or {};
        table.insert(shown[row.entity_id], row.effect);
    end
    for _, list in pairs(shown) do table.sort(list); end
    return shown, tracker:drain_events();
end;
local function list(shown, id) return table.concat(shown[id] or {}, ','); end
-- Slow (56) by a party member, Gravity (216) by you, and Paralyze (58), which no erase takes.
local function debuffs(mob) return { action(ALLY, 4, 56, { { mob, 236, 13 } }), action(SELF, 4, 216, { { mob, 236, 12 } }),
    action(ALLY, 4, 58, { { mob, 236, 4 } }) }; end

local shown = step(10, debuffs(AERN));
assert(list(shown, AERN) == '4,12,13', 'Fixture: Paralysis, Weight and Slow on the Aern: ' .. list(shown, AERN));
local events;
shown, events = step(12, { action(AERN, 11, 1381, { { AERN, 231, 2 } }) });
local reason;
for _, event in ipairs(events) do if event.kind == 'removed' and event.effect == 13 then reason = event.reason; end end
assert(list(shown, AERN) == '4', 'Depuration took Slow and Weight off and left Paralysis: ' .. list(shown, AERN));
assert(reason == 'A monster\'s move took it off.', 'Its removal says why: ' .. tostring(reason));
-- The wear-off of your Weight that the server sends you finds nothing left to take off.
local wearoff = MOCK.bytes(28);
MOCK.put(wearoff, 4, 4, SELF); MOCK.put(wearoff, 8, 4, AERN); MOCK.put(wearoff, 12, 4, 12); MOCK.put(wearoff, 24, 2, 206);
shown, events = step(12.2, { MOCK.packet(0x029, wearoff) });
for _, event in ipairs(events) do assert(event.kind ~= 'removed', 'Your Weight was taken off once.'); end

-- Rapid Molt erases, then puts Regen (42) on, which isn't erasable.
step(20, debuffs(HPEMDE));
shown = step(22, { action(HPEMDE, 11, 1368, { { HPEMDE, 186, 42 } }) });
assert(list(shown, HPEMDE) == '4,42', 'Rapid Molt left Paralysis and its own Regen: ' .. list(shown, HPEMDE));

-- Voidsong's rows name the players it hits, and it erases its user too.
step(30, debuffs(DRAGON));
shown = step(32, { action(DRAGON, 11, 649, { { SELF, 231, 1 }, { ALLY, 189, 0 } }) });
assert(list(shown, DRAGON) == '4', 'Voidsong erased the dragon: ' .. list(shown, DRAGON));

-- Benediction erases each mob it reaches.
step(40, debuffs(AERN));
step(40, debuffs(MOB2));
shown = step(42, { action(AERN, 11, 689, { { AERN, 238, 900 }, { MOB2, 238, 400 } }) });
assert(list(shown, AERN) == '4' and list(shown, MOB2) == '4', 'Benediction erased both mobs: ' .. list(shown, AERN) .. ' | ' .. list(shown, MOB2));

-- A Nightmare Bunny's Wild Carrot (1570) erases its user, and takes its Paralysis off too (wild_carrot_dynamis.lua
-- :24-41).
step(45, debuffs(MOB2));
shown = step(47, { action(MOB2, 11, 1570, { { MOB2, 238, 300 } }) });
assert(list(shown, MOB2) == '', 'Wild Carrot took Slow, Weight and Paralysis off: ' .. list(shown, MOB2));

-- Another move leaves them, and so does a player's category 11 with one of those ids.
step(50, debuffs(MOB2));
shown = step(52, { action(MOB2, 11, 1380, { { MOB2, 186, 42 } }), action(ALLY, 11, 1381, { { MOB2, 231, 2 } }) });
assert(list(shown, MOB2) == '4,12,13,42', 'Another move took nothing off: ' .. list(shown, MOB2));
return 'A monster\'s erase-all move takes the erasable effects off its rows';
