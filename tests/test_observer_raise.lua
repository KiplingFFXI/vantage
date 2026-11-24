-- Raise, Raise II, Raise III and Arise finish with message 309 ('casts ... on') and give the raise level the
-- target accepts later (Phoenix raise*.lua, arise.lua: sendRaise). The observer reports who cast it.
local observer = require('core.observer');
local self_id, ally = 1001, 1002;
local snapshot = { valid = true, id = self_id, zone = 102, name = 'Tester', level = 75,
    self_effects = {}, party = { { id = ally, name = 'Ally' } }, entities = {
        [self_id] = { name = 'Tester' }, [ally] = { name = 'Ally' } } };
local function action(id, target, actor, message, param)
    return MOCK.packet(0x028, MOCK.action_bytes(actor, 4, id, { { id = target, rows = { { message = message, param = param } } } }));
end

for spell, level in pairs({ [12] = 1, [13] = 2, [140] = 3, [494] = 4 }) do
    local out = observer.read(action(spell, self_id, ally, 309, level), 1, snapshot);
    assert(#out == 1 and out[1].kind == 'raise' and out[1].entity_id == self_id and out[1].source == ally
        and out[1].source_name == 'Ally' and out[1].spell == spell and out[1].level == level, 'A raise cast is reported: ' .. spell);
end
local out = observer.read(action(264, self_id, ally, 309, 1), 1, snapshot);
assert(#out == 0, 'Tractor gives no raise.');
out = observer.read(action(12, ally, self_id, 309, 1), 1, snapshot);
assert(#out == 1 and out[1].entity_id == ally and out[1].source == self_id, 'A raise on someone else names them.');

-- Reraise, Reraise II and Reraise III have no message of their own, so they finish with 0 and name Reraise (113), which
-- they put on for an hour (Phoenix sql/spell_list.sql :304, :310, :311, actions/spells/white/reraise.lua).
local function reraise(events)
    for _, event in ipairs(events) do if event.kind == 'apply' then return event; end end
end
for _, spell in ipairs({ 135, 141, 142 }) do
    for _, who in ipairs({ self_id, ally }) do
        local seen = reraise(observer.read(action(spell, who, who, 0, 113), 1, snapshot));
        assert(seen and seen.entity_id == who and seen.effect == 113 and seen.source == who and seen.spell == spell and seen.duration == 3600,
            'Spell ' .. spell .. ' by ' .. who .. ' puts Reraise on for an hour: '
            .. (seen and (tostring(seen.effect) .. ' for ' .. tostring(seen.duration)) or 'nothing'));
    end
end
assert(reraise(observer.read(action(135, ally, ally, 0, 0), 1, snapshot)) == nil, 'A 0 that names no status puts nothing on.');
