-- Two readings the pet display's optional lines take from the game (core/pet_lines.lua): a readied move is named
-- from the list its start says it is from, and the MP cost line is for an avatar or a spirit, not for whatever pet a
-- SMN has out. An automaton's stat bonus under zero is in test_pet_automaton_lines.lua.
local lines, pet = require('core.pet_lines'), require('core.pet');
local config = pet.make();
local function named(shown, name)
    for index = 1, shown.line_count do
        if shown.lines[index].name == name then return shown.lines[index]; end
    end
end
-- Pet ability 300 and monster skill 300 are different moves, and each list has ids the other doesn't.
local abilities, skills = { [300] = 'Pet Ability', [310] = 'Ability Only' }, { [300] = 'Monster Skill', [320] = 'Skill Only' };
AshitaCore.GetResourceManager = function()
    return {
        GetSpellById = function() return nil; end,
        GetAbilityById = function(_, id) return abilities[id - 512] and { Name = { abilities[id - 512] } } or nil; end,
        GetItemById = function() return nil; end,
        GetString = function(_, list, id) return list == 'monsters.abilities' and skills[id + 256] or nil; end,
    };
end;

-- A start says which list its id is from by its message: 326 a pet ability, 43 a monster skill (Phoenix
-- src/map/ai/states/petskill_state.cpp :90-91). A monster's own move starts with 43 or with no message
-- (mobskill_state.cpp :119-120).
local snapshot = { valid = true, id = 1001, job = 15, sub_job = 0, self_effects = {}, pet = { id = 82, index = 7, name = 'Ifrit' } };
local watch, shown = lines.new(), {};
watch:track(100, snapshot);
config.show_action = true;
local function readies(message, id, at)
    watch:observe({ kind = 'pet_start', entity_id = 82, category = 7, id = id or 300, message = message }, at);
    watch:fill(shown, at + 1, config, snapshot);
    return named(shown, 'Readies') and named(shown, 'Readies').value;
end
assert(readies(326, 300, 100) == 'Pet Ability', 'A start with message 326 names a pet ability, before any move has finished: ' .. tostring(readies(326, 300, 100)));
assert(readies(43, 300, 102) == 'Monster Skill', 'A start with message 43 names a monster skill: ' .. tostring(readies(43, 300, 102)));
assert(readies(0, 300, 104) == 'Monster Skill', 'A start with no message is a monster\'s own move: ' .. tostring(readies(0, 300, 104)));
-- What finished before doesn't change it, either way round.
watch:observe({ kind = 'pet_action', entity_id = 82, category = 13, id = 300 }, 110);
assert(readies(43, 300, 111) == 'Monster Skill', 'After a pet ability finished, a start with 43 is still a monster skill: ' .. tostring(readies(43, 300, 111)));
watch:observe({ kind = 'pet_action', entity_id = 82, category = 11, id = 300 }, 120);
assert(readies(326, 300, 121) == 'Pet Ability', 'After a monster skill finished, a start with 326 is still a pet ability: ' .. tostring(readies(326, 300, 121)));
-- An id its own list has no name for takes the other list's, as before, and one neither has is still a move.
assert(readies(326, 320, 130) == 'Skill Only' and readies(43, 310, 132) == 'Ability Only', 'A name missing from its own list comes from the other.');
assert(readies(326, 999, 134) == 'a move', 'A move with no name anywhere is still shown.');
-- A finished move goes by its category, as it did.
watch:observe({ kind = 'pet_action', entity_id = 82, category = 13, id = 300, amount = 40 }, 140);
watch:fill(shown, 141, config, snapshot);
assert(named(shown, 'Last move').value == 'Pet Ability 40', 'A finished pet ability: ' .. named(shown, 'Last move').value);
watch:observe({ kind = 'pet_action', entity_id = 82, category = 11, id = 300, amount = 41 }, 142);
watch:fill(shown, 143, config, snapshot);
assert(named(shown, 'Last move').value == 'Monster Skill 41', 'A finished monster skill: ' .. named(shown, 'Last move').value);
config.show_action = false;

-- The observer hands the start's message on.
local observer = require('core.observer');
local function start(actor, target, message, param)
    return MOCK.packet(0x028, MOCK.action_bytes(actor, 7, 0x65746163, { { id = target, rows = { { message = message, param = param } } } }));
end
local world = { valid = true, id = 1001, zone = 102, name = 'Tester', job = 15, self_known = true, self_effects = {}, party = {},
    pet = { id = 82, index = 7, name = 'Ifrit' }, entities = { [1001] = { name = 'Tester', kind = 'player' }, [82] = { name = 'Ifrit', kind = 'pet' } } };
for _, message in ipairs({ 326, 43, 0 }) do
    local seen = observer.read(start(82, 0x1000301, message, 300), 1, world);
    assert(#seen == 1 and seen[1].kind == 'pet_start' and seen[1].id == 300 and seen[1].message == message,
        'The start carries its message ' .. message .. ': ' .. tostring(seen[1] and seen[1].message));
end

-- The MP cost line is for an avatar or a spirit. A SMN, main or support, can have another pet out: a wyvern, a jug
-- pet, a charmed mob or an automaton. Those cost no MP, so they have no line and nothing is measured for them.
config.show_upkeep = true;
local function cost_for(name, job, sub, automaton)
    snapshot = { valid = true, id = 1001, job = job, sub_job = sub, self_effects = {}, mp = 500,
        pet = { id = 91, index = 9, name = name, automaton = automaton } };
    watch = lines.new();
    watch:track(300, snapshot);
    watch:fill(shown, 300, config, snapshot);
    snapshot.mp = 493;
    watch:fill(shown, 303, config, snapshot);
    snapshot.mp = 486;
    watch:fill(shown, 306, config, snapshot);
    return named(shown, 'MP cost') and named(shown, 'MP cost').value, watch.samples ~= nil;
end
for _, name in ipairs({ 'Carbuncle', 'Fenrir', 'Ifrit', 'Titan', 'Leviathan', 'Garuda', 'Shiva', 'Ramuh', 'Diabolos', 'FireSpirit', 'IceSpirit',
    'AirSpirit', 'EarthSpirit', 'ThunderSpirit', 'WaterSpirit', 'LightSpirit', 'DarkSpirit', 'Fire Spirit', 'Light Spirit' }) do
    local value = cost_for(name, 15, 0);
    assert(value == '7 a tick, 3:28 left', name .. ' has its MP cost: ' .. tostring(value));
end
assert(cost_for('Ifrit', 14, 15) == '7 a tick, 3:28 left', 'A /SMN\'s avatar has it too.');
for _, other in ipairs({ { 'Azure', 14, 15 }, { 'SheepFamiliar', 9, 15 }, { 'Land Crab', 15, 9 }, { 'CourierCarrie', 15, 9 },
    { 'Ironsides', 18, 15, { head = 2, frame = 0x21, attachments = {} } }, { 'Ifrit', 15, 18, { head = 2, frame = 0x21, attachments = {} } } }) do
    local value, measured = cost_for(other[1], other[2], other[3], other[4]);
    assert(value == nil and not measured, other[1] .. ' is no avatar, so it has no MP cost line: ' .. tostring(value));
end
assert(cost_for('Ifrit', 5, 0) == nil, 'Another job has no MP cost line, as before.');
return 'Pet lines read the move list and the kind of pet';
