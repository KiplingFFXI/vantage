-- The hide rule scopes enemy, other and pet: they are kept by tidy and match only their own units, in the panels as
-- on overhead icons, and the other scopes match theirs. A rule with a trust scope drops.
package.loaded['ui.icons'] = { status = function(id) return 5000 + id; end };
local filters = require('core.effect_filters');
local defaults, hud = require('ui.defaults'), require('ui.hud');

local function rule(effect, scope)
    local result = filters.rule();
    result.effect, result.scope = effect, scope;
    return result;
end
-- tidy keeps each of these scopes, and drops a scope it doesn't know. Trust is one: the rule goes, so it can't
-- widen into a rule for everyone.
local kept = filters.tidy({ rules = { rule(4, 'enemy'), rule(4, 'other'), rule(4, 'pet'), rule(4, 'trust'), rule(4, 'mobs') } });
assert(#kept.rules == 3 and kept.rules[1].scope == 'enemy' and kept.rules[2].scope == 'other' and kept.rules[3].scope == 'pet',
    'The three scopes are kept, and a trust rule or an unknown one is not.');
kept = filters.tidy({ enabled = true, rules = { rule(4, 'trust') } });
assert(#kept.rules == 0 and not filters.compile(kept).active, 'A save with only a trust rule hides nothing.');

-- You, a party member, an alliance member, another player, a pet and a mob, as the tracker scopes them.
local snapshot = { valid = true, id = 1001, zone = 102, name = 'Tester', job = 1, party = {
    { id = 1002, name = 'Member', group = 1, slot = 1, scope = 'party' },
    { id = 1003, name = 'Ally', group = 2, slot = 6, scope = 'alliance' },
}, entities = { [1004] = { id = 1004, name = 'Stranger', kind = 'player' } }, target = { id = 0x1000100, name = 'Goblin', kind = 'monster' } };
local units = { [1001] = 'self', [1002] = 'party', [1003] = 'alliance', [1004] = 'other',
    [0x1000105] = 'pet', [0x1000100] = 'enemy' };
local names = { [1001] = 'self', [1002] = 'member', [1003] = 'ally', [1004] = 'stranger',
    [0x1000105] = 'pet', [0x1000100] = 'mob' };
local rows = {};
for id, scope in pairs(units) do
    rows[#rows + 1] = { key = tostring(id), effect = 4, name = 'Paralysis', kind = 'debuff', present = true, status = 'unknown',
        entity_id = id, entity_name = names[id], scope = scope };
end
local recipients = filters.recipients(snapshot);
assert(recipients[1002].trust == nil and recipients[1001].trust == nil, 'A unit carries no trust field.');
assert(recipients[1004].scope == 'other', 'Another player the client sees is one of the others: ' .. tostring(recipients[1004].scope));

-- Who a rule with each scope hides Paralysis on.
local function hidden(scope)
    local compiled = filters.compile({ enabled = true, rules = { rule(4, scope) } });
    local out = {};
    for _, row in ipairs(rows) do
        if filters.hide(compiled, row, filters.context(recipients, row.entity_id, row)) then out[#out + 1] = names[row.entity_id]; end
    end
    table.sort(out);
    return table.concat(out, ' ');
end
assert(hidden('enemy') == 'mob', 'enemy: ' .. hidden('enemy'));
assert(hidden('other') == 'stranger', 'other: ' .. hidden('other'));
assert(hidden('pet') == 'pet', 'pet: ' .. hidden('pet'));
-- The other scopes.
assert(hidden('all') == 'ally member mob pet self stranger', 'all: ' .. hidden('all'));
assert(hidden('self') == 'self', 'self: ' .. hidden('self'));
assert(hidden('party') == 'member self', 'party: ' .. hidden('party'));
assert(hidden('alliance') == 'ally', 'alliance: ' .. hidden('alliance'));
assert(hidden('alliance1') == 'ally' and hidden('alliance2') == '', 'alliance1 and alliance2');

-- In the panels: the target panel loses its mob's Paralysis to an enemy rule, and keeps it for an other rule; the
-- party panel keeps the member's.
local settings = defaults.make();
local view = { valid = true, context = snapshot, rows = rows, effect_recipients = recipients };
local function shown(key, scope)
    settings.effect_filters = { enabled = true, rules = { rule(4, scope) } };
    local out = {};
    for _, row in ipairs(hud.filter_rows(view, settings.panels[key], key, settings)) do out[#out + 1] = names[row.entity_id]; end
    table.sort(out);
    return table.concat(out, ' ');
end
assert(shown('target', 'other') == 'mob' and shown('target', 'enemy') == '', 'The target panel follows enemy rules.');
assert(shown('party', 'enemy') == 'member', 'An enemy rule leaves the party panel alone: ' .. shown('party', 'enemy'));
-- The hide rule page offers them.
local page = io.open(ADDON_DIR .. '/ui/filter_settings.lua'):read('*a');
for _, scope in ipairs({ 'enemy', 'other', 'pet' }) do
    assert(page:find("'" .. scope .. "'", 1, true), 'The page lists ' .. scope);
end
assert(not page:lower():find('trust', 1, true), 'The page has no trust scope and no word of one.');
