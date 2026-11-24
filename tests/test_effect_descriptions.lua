-- An effect's tooltip says what it does, in the game's own words: the description on its status record, the same
-- record its picture comes from. Hysteria and Tomahawk have none, and Fast Cast's and Sange's don't fit Phoenix, so
-- the catalog gives those four theirs.
local reads, records = 0, {
    [33] = { Description = { 'Attack speed is increased.' } },
    [40] = { Description = { '  Defense is\1 enhanced. ' } },
    [50] = { Description = { '' } },
};
AshitaCore.GetResourceManager = function()
    return { GetStatusIconByIndex = function(_, id) reads = reads + 1; return records[id]; end };
end;
local catalog = require('core.catalog');
assert(catalog.description(33) == 'Attack speed is increased.', 'The game\'s text for Haste.');
assert(catalog.description(33) == 'Attack speed is increased.' and reads == 1, 'Each is read once.');
assert(catalog.description(40) == 'Defense is enhanced.', 'Only plain text, with no space at either end: '
    .. tostring(catalog.description(40)));
assert(catalog.description(50) == nil, 'An empty description is none.');
reads = 0;
assert(catalog.description(50) == nil and reads == 0, 'And it is kept as none.');
-- A record the game doesn't give yet is asked for again.
assert(catalog.description(60) == nil and reads == 1, 'Fixture: no record yet.');
records[60] = { Description = { 'You are frozen with fear.' } };
assert(catalog.description(60) == 'You are frozen with fear.' and reads == 2, 'Asked for again, it is there.');
-- The two the game says nothing of, and the two whose words don't fit Phoenix.
reads = 0;
assert(catalog.description(804):find('^The monster\'s TP moves are cut off before they go off')
    and catalog.description(805):find('a quarter weaker%.$') and reads == 0, 'The catalog gives Hysteria and Tomahawk theirs.');
assert(catalog.description(574) == 'Spells take longer to cast and recast, by 30% of their base cast time and 15% of their base recast.'
    and catalog.description(352):find('^Your next ranged attack throws an extra shuriken for each Utsusemi shadow you have, until one misses')
    and reads == 0, 'The catalog gives Fast Cast and Sange theirs.');
assert(catalog.description(nil) == nil and catalog.description('33') == nil and catalog.description(0 / 0) == nil
    and reads == 0, 'Only an effect id is looked up.');

-- The timer panels' tooltip, which the Pet display uses too: right under the name.
local hud = require('ui.hud');
local lines = {};
for line in hud.details({ effect = 33, name = 'Haste', kind = 'buff', status = 'observed' }, 100, { horizon = 300 }):gmatch('[^\n]+') do
    lines[#lines + 1] = line;
end
assert(lines[1] == 'Haste  (#33)' and lines[2] == 'Attack speed is increased.', 'Under the name: ' .. table.concat(lines, ' | '));
local plain = hud.details({ effect = 70, name = 'Deodorize', kind = 'buff', status = 'observed' }, 100, { horizon = 300 });
assert(not plain:find('\n\n') and plain:find('^Deodorize  %(#70%)\nThe effect was observed'), 'With none, no line: ' .. plain);

-- The buffs beside the game's party list.
local imgui = require('imgui');
local party = require('ui.party_hud');
MOCK.imgui_calls = {};
party.effect_tooltip(imgui, { effect = 33, name = 'Haste', status = 'server' }, { name = 'Ally' }, nil);
local said = {};
for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'TextUnformatted' then said[#said + 1] = call[2]; end end
assert(said[1] == 'Haste - Ally' and said[2] == 'Attack speed is increased.', 'Under the name: ' .. table.concat(said, ' | '));
return 'An effect\'s tooltip says what it does';
