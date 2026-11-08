-- The catalog holds what can exist on Phoenix (docs/VALIDATION.md has the audit): 271 effects, all of them in the pickers but
-- Copy Image's icons for 2, 3 and 4 or more shadows, which list as Copy Image.
-- The Utsusemi shadow icons and the others the game can send stay. An effect left out isn't lost: if the server ever sends
-- one the game names, it tracks and draws under that name, and one nothing names shows nowhere. The Timer durations lists
-- hold the spells and abilities players can have, and the samples name their effects right.
local entries = require('data.catalog');
local catalog = require('core.catalog');
local actions = require('data.actions');

local rows = 0;
for _ in pairs(entries) do rows = rows + 1; end;
assert(rows == 271, 'The catalog has 271 effects: ' .. rows);
local list, listed, groups = catalog.list(), {}, {};
assert(#list == 268, 'The pickers list 268 effects: ' .. #list);
for _, entry in ipairs(list) do listed[entry.id], groups[entry.group] = true, (groups[entry.group] or 0) + 1; end;
for name, count in pairs({ Buffs = 133, Debuffs = 61, Other = 13, Rolls = 20, Songs = 24, Protection = 7, Travel = 6, Recovery = 3, Food = 1 }) do
    assert(groups[name] == count, name .. ' lists ' .. count .. ': ' .. tostring(groups[name]));
end;
-- The client has no name or icon for these, and nothing can show them.
for _, id in ipairs({ 791, 792, 793, 794, 795, 797, 799, 800, 801, 802, 803, 804, 805, 806 }) do
    assert(entries[id] == nil and not listed[id], 'Effect ' .. id .. ' is gone.');
end;
-- Nothing names an effect at 640 or over, so no move gives one. An effect's row is only what it drops.
local durations = require('data.effects');
for id, row in pairs(durations.effects) do
    assert(id < 640 and next(row) == 'drops' and next(row, 'drops') == nil and #row.drops > 0, 'Effect ' .. id .. ' holds only its drops.');
end;
for _, kind in ipairs({ 'spells', 'abilities', 'skills', 'pacts' }) do
    for id, row in pairs(durations[kind]) do
        assert((row.effect or 0) < 640, kind .. ' ' .. id .. ' gives an effect nothing names.');
        for effect in pairs(row.by_effect or {}) do
            assert(effect < 640, kind .. ' ' .. id .. ' gives ' .. effect .. ', which nothing names.');
        end;
    end;
end;
-- Utsusemi's shadow counts arrive as the icons 444 to 446, which stay to be drawn and list as Copy Image, and an item's
-- enchantment as 162 or 169.
for _, id in ipairs({ 444, 445, 446 }) do assert(entries[id] and not listed[id], 'Effect ' .. id .. ' must stay, listed as Copy Image.'); end;
for _, id in ipairs({ 169, 162 }) do assert(listed[id], 'Effect ' .. id .. ' must stay.'); end;
-- The undecided ids kept: the staged ToAU effects and Commitment.
for _, id in ipairs({ 119, 120, 121, 122, 123, 124, 125, 171, 172, 259, 260, 261, 262, 263, 265, 266, 283, 574, 579 }) do
    assert(listed[id], 'Effect ' .. id .. ' was kept.');
end;
-- The undecided ids taken out, Sigil, the Trust auras, and one of each other reason.
for _, id in ipairs({ 277, 278, 279, 280, 281, 282, 404, 581, 268, 807, 808, 809, 810, 811, 812, 813,
    23, 17, 222, 575, 275, 19, 270, 255, 603 }) do
    assert(entries[id] == nil, 'Effect ' .. id .. ' can\'t exist on Phoenix.');
end;
local rolls = 0;
for _, effect in pairs(actions.rolls) do
    rolls = rolls + 1;
    assert(entries[effect], 'A roll\'s effect is in the catalog: ' .. effect);
end;
assert(rolls == 18, 'The 18 era rolls: ' .. rolls);

-- What the Timer durations picker offers: 436 spells and 355 abilities, in id order, and no Helix, Waltz or Trust.
assert(#actions.spells == 436 and #actions.abilities == 355, 'The durations lists: ' .. #actions.spells .. ', ' .. #actions.abilities);
local function has(values, id)
    for _, value in ipairs(values) do if value == id then return true; end; end;
    return false;
end;
for id = 278, 285 do assert(not has(actions.spells, id), 'No Helix: ' .. id); end;
for id = 896, 1019 do assert(not has(actions.spells, id), 'No Trust: ' .. id); end;
for id = 190, 195 do assert(not has(actions.abilities, id), 'No Waltz: ' .. id); end;
assert(has(actions.spells, 57) and has(actions.spells, 143) and has(actions.abilities, 16), 'Haste, Erase and Mighty Strikes stay.');

-- The server sends an effect left out: the game names it, and it tracks and draws under that name.
AshitaCore.GetResourceManager = function() return { GetString = function(_, table_name, id)
    assert(table_name == 'buffs.names');
    return id == 280 and 'Enstone II' or nil;
end }; end;
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 1, job = 1, self_known = true,
    self_effects = { { effect = 280, slot = 0, deadline = 1060, raw_timer = 3600 } }, party = {}, entities = {} };
local tracker = require('core.tracker').new();
tracker:reconcile(snapshot, 1000);
local view = tracker:view(1000, {}, snapshot);
assert(#view.rows == 1 and view.rows[1].effect == 280 and view.rows[1].name == 'Enstone II' and view.rows[1].kind == 'other',
    'An effect left out tracks under the game\'s name.');

-- The server sends one nothing names, in your listing, a member's or a message: it leaves no row, so nothing shows it.
local quiet = require('core.tracker').new();
local nameless = { valid = true, id = 1001, name = 'Tester', zone = 1, job = 1, self_known = true,
    self_effects = { { effect = 803, slot = 0, deadline = 1060, raw_timer = 3600 }, { effect = 40, slot = 1, deadline = 1060, raw_timer = 3600 } },
    party = { { id = 1002, name = 'Friend', zone = 1, valid = true, revision = 1, effects = { { effect = 804, slot = 0 }, { effect = 999, slot = 1 } } } },
    entities = {} };
quiet:reconcile(nameless, 1000);
quiet:observe({ { kind = 'apply', entity_id = 1002, effect = 806, source = 1001 } }, 1000, nameless);
local shown = quiet:view(1000, {}, nameless).rows;
assert(#shown == 1 and shown[1].effect == 40, 'Only Protect has a row: ' .. #shown);
package.loaded['ui.icons'] = { status = function() return 123; end };
local hud, defaults = require('ui.hud'), require('ui.defaults');
MOCK.screen = { 1600, 1000 };
local s = defaults.make();
for id, p in pairs(s.panels) do p.enabled = id == 'self_buffs'; end;
s.panels.self_buffs.mode, s.panels.self_buffs.show_name = 'bars', true;
MOCK.imgui_calls = {};
hud.draw({ valid = true, context = { id = 1001, valid = true }, rows = view.rows }, s, 1000, {});
local drawn = false;
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'draw:AddText' then
        for _, value in ipairs(call) do drawn = drawn or value == 'Enstone II'; end;
    end;
end;
assert(drawn, 'An effect left out draws under the game\'s name.');

-- The samples call each effect by its name: Refresh is 43 and Shell 41, whatever the row's icon.
local seen = {};
for _, row in ipairs(hud.sample(1000).rows) do
    if row.domain ~= 'recast' then seen[row.effect] = row.name; end;
end;
assert(seen[41] == 'Shell' and catalog.get(41).name == 'Shell', 'Sample 41 is Shell: ' .. tostring(seen[41]));
for _, row in ipairs(require('core.pet').samples(1000).effects) do
    if row.effect == 43 then assert(row.name == 'Refresh', 'The pet sample\'s 43 is Refresh: ' .. tostring(row.name)); end;
end;
