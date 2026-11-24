-- A recast that a whole group of abilities shares is named for the group, as the game's menu names it: the eight
-- maneuvers, the rolls, the Quick Draw shots and each kind of blood pact. Its first two names would read as the two
-- you used. A timer two or three other abilities share keeps the names of its first two. Sic's timer is Sic, though the
-- jug pets' moves are on it too (Phoenix sql/abilities.sql :92, :528 on).
local abilities = {};
local function add(id, name, timer) abilities[id] = { Name = { [1] = name }, RecastTimerId = timer, ListIconId = 30, Element = 0 }; end
for index, element in ipairs({ 'Fire', 'Ice', 'Wind', 'Earth', 'Thunder', 'Water', 'Light', 'Dark' }) do add(700 + index, element .. ' Maneuver', 210); end
add(720, 'Phantom Roll', 193); add(721, 'Corsair\'s Roll', 193); add(722, 'Chaos Roll', 193);
add(730, 'Fire Shot', 195); add(731, 'Ice Shot', 195); add(732, 'Light Shot', 195);
add(740, 'Poison Nails', 173); add(741, 'Meteorite', 173);
add(750, 'Healing Ruby', 174);
add(760, 'Alpha', 20); add(761, 'Beta', 20);
add(770, 'One', 21); add(771, 'Two', 21); add(772, 'Three', 21);
add(584, 'Sic', 102); add(1184, 'Foot Kick', 102); add(1185, 'Dust Cloud', 102);
-- You know Fire Maneuver and Light Maneuver, Alpha and Beta, Two and Three, and Sic, and the game has eight recasts
-- running.
local known = { [701] = true, [707] = true, [760] = true, [761] = true, [771] = true, [772] = true, [584] = true };
local active = { 210, 193, 195, 173, 174, 20, 21, 102 };
local player = {
    GetMainJob = function() return 18; end, GetSubJob = function() return 1; end, GetMainJobLevel = function() return 75; end,
    GetSubJobLevel = function() return 37; end, HasAbilityData = function() return true; end,
    HasAbility = function(_, id) return known[id] == true; end, HasPetCommand = function() return false; end,
};
local manager = {
    GetSpellTimer = function() return 0; end,
    GetAbilityTimerId = function(_, slot) return active[slot + 1] or 255; end,
    GetAbilityTimer = function(_, slot) return active[slot + 1] and 600 or 0; end,
};
local memory = { GetPlayer = function() return player; end, GetRecast = function() return manager; end };
AshitaCore.GetMemoryManager = function() return memory; end;
AshitaCore.GetResourceManager = function()
    return { GetAbilityById = function(_, id) return abilities[id]; end, GetSpellById = function() return nil; end, GetString = function() return nil; end };
end;
local recasts = require('core.recasts');

-- What the pickers list.
local listed = {};
for _, entry in ipairs(recasts.catalog('ability')) do listed[entry.recast_id] = entry; end
assert(listed[210].name == 'Maneuvers', 'The maneuvers\' recast is Maneuvers: ' .. tostring(listed[210].name));
assert(listed[210].shared == true, 'It is still a shared recast.');
assert(listed[193].name == 'Phantom Roll' and listed[195].name == 'Quick Draw', 'The rolls and the shots go by the game\'s names for them: '
    .. tostring(listed[193].name) .. ', ' .. tostring(listed[195].name));
assert(listed[173].name == 'Blood Pact: Rage' and listed[174].name == 'Blood Pact: Ward', 'Each kind of blood pact has its own: '
    .. tostring(listed[173].name) .. ', ' .. tostring(listed[174].name));
assert(listed[20].name == 'Alpha / Beta (shared)', 'Two abilities on one recast keep both names: ' .. tostring(listed[20].name));
assert(listed[21].name == 'One / Three (shared)', 'Any other shared recast keeps its first two names: ' .. tostring(listed[21].name));
assert(listed[102].name == 'Sic', 'Sic\'s recast is Sic, not two jug moves: ' .. tostring(listed[102].name));

-- The live rows, where only the abilities you know count: the group's name stays.
local model = recasts.new();
model:update({ valid = true, id = 1001, zone = 230, job = 18, name = 'Aster' }, 100);
local view = model:view(100.1);
local rows = {};
for _, row in ipairs(view.rows) do if row.kind == 'ability' then rows[row.recast_id] = row; end end
assert(rows[210] and rows[210].name == 'Maneuvers', 'Knowing two maneuvers, the row is still Maneuvers: ' .. tostring(rows[210] and rows[210].name));
assert(rows[193].name == 'Phantom Roll' and rows[195].name == 'Quick Draw' and rows[173].name == 'Blood Pact: Rage' and rows[174].name == 'Blood Pact: Ward',
    'The other groups read the same on their rows.');
assert(rows[20].name == 'Alpha / Beta (shared)', 'And a pair you know keeps both names: ' .. tostring(rows[20].name));
assert(rows[21].name == 'Three / Two (shared)', 'Any other shared recast names the two of its abilities you know: ' .. tostring(rows[21].name));
assert(rows[102].name == 'Sic', 'Its row reads the same: ' .. tostring(rows[102].name));
return 'Recasts a group of abilities shares are named for the group';
