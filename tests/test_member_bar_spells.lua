-- A player's bar-element spell lasts 150 seconds and 0.8 more for each point of the caster's Enhancing Magic skill past
-- 180 (Phoenix modules/phoenix/lua/globals/spells/enhancing_spell.lua :49-66). Vantage reads only your own skill, so
-- anyone else's counts from 150 up to a level 75 RDM's skill cap. Barfira to Barwatera are WHM spells, but a RDM with
-- WHM as support job casts them with the RDM's skill (sql/spell_list.sql :235-240, src/map/spell.cpp :809,
-- src/map/utils/charutils.cpp :3608-3655), so the top for every bar spell is a RDM's B+ 256, 210.8 (data/skills.yaml
-- :30, :118). Merits and gear can take a caster past it. Through vantage.lua as the game drives it (live_fixture.lua).
local L = require('live_fixture');
local catalog = require('core.catalog');
local BOB, DAVE, BARFIRE = 1002, 1003, 100;

local app = L.start();
L.listing({ { BOB, 0x401, {} }, { DAVE, 0x402, {} } });
L.frame();
-- Dave, a RDM with WHM as support job, casts Barfira on the party: 230 on him and 266 on Bob. Their listing shows it.
L.action(4, 66, DAVE, { { id = DAVE, rows = { { message = 230, param = BARFIRE } } },
    { id = BOB, rows = { { message = 266, param = BARFIRE } } } });
L.listing({ { BOB, 0x401, { BARFIRE } }, { DAVE, 0x402, { BARFIRE } } });
L.frame();
local row = L.row(BOB, BARFIRE);
assert(row and row.source == DAVE and row.spell == 66, 'Fixture: Bob\'s Barfire is Dave\'s Barfira.');
-- 200 seconds on, inside a level 75 RDM's 210.8, Bob's listing still shows it, and it still counts down.
L.frame(200);
row = L.row(BOB, BARFIRE);
assert(row and row.status == 'estimated' and row.remaining and row.remaining > 5,
    'Bob\'s Barfire still counts down 200 seconds on: status ' .. tostring(row and row.status) .. ', remaining '
    .. tostring(row and row.remaining) .. ', ' .. tostring(row and row.reason));
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));

-- No resist shortens a bar spell on a member. The range is the caster's skill.
for _, spell in ipairs({ 60, 66 }) do
    local max, min, basis = catalog.duration('spells', spell, BARFIRE);
    assert(min == 150 and max == 211 and basis == 'Duration range by the caster\'s Enhancing Magic skill',
        'Someone else\'s bar spell ' .. spell .. ' counts 150 to 211 seconds by their skill: ' .. tostring(min) .. ' to '
        .. tostring(max) .. ', ' .. tostring(basis));
end
-- Your own still goes by your skill, read with the cast.
local max, min = catalog.duration('spells', 66, BARFIRE, { items = {}, buffs = {}, merits = {}, level = 75, enhancing_skill = 230 });
assert(max == 190 and min == 190, 'Your own Barfira at skill 230 is 190 seconds: ' .. tostring(min) .. ' to ' .. tostring(max));
return 'Someone else\'s bar-element spell counts up to a level 75 caster\'s time';
