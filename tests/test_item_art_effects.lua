-- Two effects sit only on a monster and the client has no name or picture for either: Hysteria, from a Bottle of
-- Hysteroanima, and Tomahawk, from a Throwing Tomahawk. The catalog names each itself and gives it its item
-- (data/catalog.lua item), and it draws with that item's picture, whatever the artwork.
package.preload.d3d8 = function() return { get_device = function() return nil; end }; end;
local asked = {};
AshitaCore.GetResourceManager = function() return { GetString = function(_, table_name, id)
    assert(table_name == 'buffs.names');
    asked[#asked + 1] = id;
    return id == 10 and 'stun' or nil;
end }; end;
local entries, catalog = require('data.catalog'), require('core.catalog');
local HYSTERIA, TOMAHAWK, HYSTEROANIMA, THROWING_TOMAHAWK = 804, 805, 5262, 18258;
assert(entries[HYSTERIA].item == HYSTEROANIMA and entries[TOMAHAWK].item == THROWING_TOMAHAWK, 'Each has its item.');
local with_item = 0;
for _, entry in pairs(entries) do if entry.item then with_item = with_item + 1; end end
assert(with_item == 2, 'Only those two take an item\'s picture: ' .. with_item);

-- Each keeps its own name, a debuff, and the client is never asked for one it doesn't have.
local tomahawk, hysteria = catalog.get(TOMAHAWK), catalog.get(HYSTERIA);
assert(tomahawk.name == 'Tomahawk' and tomahawk.kind == 'debuff' and tomahawk.group == 'Debuffs' and not tomahawk.unnamed, 'Tomahawk is a named debuff.');
assert(hysteria.name == 'Hysteria' and hysteria.kind == 'debuff' and hysteria.group == 'Debuffs' and not hysteria.unnamed, 'Hysteria is a named debuff.');
assert(#asked == 0, 'The client is asked for neither name: ' .. #asked);
assert(catalog.get(10).name == 'Stun' and #asked == 1, 'Fixture: an effect the client names is asked for.');
local listed = {};
for _, entry in ipairs(catalog.list()) do listed[entry.id] = entry.name; end
assert(listed[TOMAHAWK] == 'Tomahawk' and listed[HYSTERIA] == 'Hysteria', 'Both are in the pickers.');

-- The picture: the item's, from the item loader, for every artwork. Any other effect still takes its status picture.
local icons, items = require('ui.icons'), require('ui.item_icons');
local status_loads, item_loads = {}, {};
icons._set_loader_for_tests(function(id) status_loads[#status_loads + 1] = id; return 1000 + id; end);
items._set_loader_for_tests(function(item) item_loads[#item_loads + 1] = item; return 50000 + item; end);
for _, artwork in ipairs({ 'Original FFXI', 'XI View' }) do
    assert(icons.status(TOMAHAWK, artwork) == 50000 + THROWING_TOMAHAWK, 'Tomahawk draws the Throwing Tomahawk with ' .. artwork .. ' art.');
    assert(icons.status(HYSTERIA, artwork) == 50000 + HYSTEROANIMA, 'Hysteria draws the bottle with ' .. artwork .. ' art.');
end
assert(#item_loads == 2 and #status_loads == 0, 'Each item picture is made once, and no status picture is asked for: ' .. #item_loads .. ', ' .. #status_loads);
local texture, corner = icons.status_at(TOMAHAWK, 'XI View', 24);
assert(texture == 50000 + THROWING_TOMAHAWK and corner[1] == 1 and corner[2] == 1, 'A sized icon is the whole item picture.');
assert(icons.status(10, 'Original FFXI') == 1010 and status_loads[1] == 10 and #item_loads == 2, 'An effect with art of its own keeps it.');
-- An item picture that can't be made draws nothing, with no status picture in its place.
items.clear();
items._set_loader_for_tests(function() return false; end);
assert(icons.status(TOMAHAWK, 'Original FFXI') == nil and #status_loads == 1, 'With no item picture nothing is drawn.');
icons._set_loader_for_tests(nil); items._set_loader_for_tests(nil);
icons.clear(); items.clear();

-- In the tracker a guessed Tomahawk is a row under its name, on the monster.
local tracker = require('core.tracker').new();
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 1, job = 1, level = 75, self_known = true, self_effects = {}, party = {},
    entities = { [0x1000301] = { id = 0x1000301, name = 'Goblin', kind = 'monster' } } };
tracker:reconcile(snapshot, 100);
tracker:observe({ { kind = 'apply', entity_id = 0x1000301, effect = TOMAHAWK, source = 1001, guessed = true, duration = 60, category = 'debuff', group = 'Debuffs',
    action_category = 6, spell = 150, action_kind = 'abilities' } }, 100, snapshot);
local rows = tracker:view(101, {}, snapshot).rows;
assert(#rows == 1 and rows[1].effect == TOMAHAWK and rows[1].name == 'Tomahawk' and rows[1].kind == 'debuff' and rows[1].deadline == 160,
    'A guessed Tomahawk is a row under its name: ' .. #rows);
assert(#tracker:view(160, {}, snapshot).rows == 0, 'It goes when its time is up.');
return 'Hysteria and Tomahawk are named here and draw their items';
