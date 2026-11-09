-- Who gets an overhead block and in what order: the target, subtarget, mobs the party claimed (0x00E claimer), watched
-- and debuffed mobs, the party, your pet, the alliance and others, by priority up to max_units, nearest first
-- within a priority; every hide state, show conditions with their own reason; the distance cap and fade; the city rule
-- with Sealion's Den; SpawnFlags first; a member with party cooldowns over heads keeps a block for them.
-- The client's hide-UI, event and map flags, each at an address its pattern scan finds.
local event_scan, interface_scan, focus_scan = 0x110000, 0x120000, 0x130000;
local interface, event_flag, menu, header = 0x210000, 0x220000, 0x230000, 0x240000;
local memory = { [event_scan + 1] = event_flag, [interface_scan + 10] = interface, [focus_scan] = interface + 0x54,
    [interface + 0xB4] = 0, [event_flag] = 0, [interface + 0x54] = 0, [menu + 4] = header, [header + 0x4E] = 0x2070616D };
ashita.memory.find = function(_, _, pattern)
    return pattern:sub(1, 2) == 'A0' and event_scan or pattern:sub(1, 8) == '8B442404' and interface_scan or focus_scan;
end;
local function read(address) return memory[address]; end
ashita.memory.read_uint8, ashita.memory.read_uint32 = read, read;
require('core.client')._set_pages(function() return true; end);

local W = require('overhead_fixture');
local overhead = require('core.overhead');
local plan = overhead.plan;
local function update_packet(id, index, flags, claimer)
    local bytes = MOCK.bytes(0x48);
    MOCK.put(bytes, 4, 4, id); MOCK.put(bytes, 8, 2, index); bytes[0x0A] = flags; MOCK.put(bytes, 0x2C, 4, claimer or 0);
    return MOCK.packet(0x00E, bytes);
end

local settings = W.settings();
-- Mobs at Y = -d are d yalms from you and d + 10 deep. Each has an effect to show.
local target = W.unit(0x100, 0x1000100, 'mob', 0, -5, { name = 'Target' });
W.unit(0x101, 0x1000101, 'mob', 1, -6, { name = 'Subtarget' });
W.unit(0x102, 0x1000102, 'mob', 2, -7, { name = 'Claimed' });
W.unit(0x103, 0x1000103, 'mob', -1, -8, { name = 'Watched' });
W.unit(0x104, 0x1000104, 'mob', -2, -9, { name = 'Debuffed' });
W.unit(0x401, 1002, 'player', 1, -3, { name = 'Member', race = 3 });
W.unit(0x105, 0x1000105, 'pet', -1, -2, { name = 'Pet' });
W.entities[W.self].pet = 0x105;
W.unit(0x402, 1003, 'player', -2, -10, { name = 'Ally', race = 7 });
W.unit(0x403, 1004, 'player', 3, -11, { name = 'Stranger' });
W.target = 0x100;
local members = { { id = 1002, index = 0x401, scope = 'party' }, { id = 1003, index = 0x402, scope = 'alliance' } };
local snapshot = W.snapshot(members);
local view = W.view({ 0x1000100, 0x1000101, 0x1000102, 0x1000103, { entity_id = 0x1000104, kind = 'debuff', scope = 'enemy', source = 1002 },
    1002, 0x1000105, 1003, { entity_id = 1004, kind = 'debuff', scope = 'other' } });
settings.watch_ids = { 0x1000103 };
overhead.packet(update_packet(0x1000102, 0x102, 0x07, 1001));
assert(overhead._claimer(0x1000102) == 1001, 'An 0x00E with its claim bit names the claimer at 0x2C.');

W.frame(view, settings, snapshot);
assert(plan.valid and plan.hidden == nil, 'The plan is placed: ' .. tostring(plan.hidden));
assert(W.ids(plan) == table.concat({ 0x1000100, 0x1000102, 0x1000103, 0x1000104, 1002, 0x1000105, 1003 }, ' '),
    'Target, claimed, watched, debuffed, party, pet, alliance; others are off: ' .. W.ids(plan));
local kinds = {};
for i = 1, plan.count do kinds[i] = plan.units[i].kind; end
assert(table.concat(kinds, ' ') == 'mob mob mob mob party pet alliance', table.concat(kinds, ' '));
assert(plan.units[1].target and not plan.units[2].target, 'Only the target is marked as the target.');
-- The subtarget, while its cursor is up: then the main target is slot 1 and the subtarget slot 0.
W.sub_active, W.sub = 1, 0x101;
W.frame(view, settings, snapshot);
assert(plan.units[1].id == 0x1000100 and plan.units[1].target and plan.units[2].id == 0x1000101 and plan.units[2].subtarget,
    'The subtarget comes second: ' .. W.ids(plan));
assert(plan.count == 8, 'Eight of ten units.');
-- Draw order: far to near, then the target last, so its block is on top of a nearer one.
assert(plan.units[plan.order[plan.count]].target and plan.units[plan.order[plan.count - 1]].depth < plan.units[1].depth,
    'The target is drawn last, after a nearer unit.');
for i = 2, plan.count - 1 do
    assert(plan.units[plan.order[i - 1]].depth >= plan.units[plan.order[i]].depth, 'order runs far to near');
end
-- max_units keeps the best.
settings.overhead.max_units = 4;
W.frame(view, settings, snapshot);
assert(W.ids(plan) == table.concat({ 0x1000100, 0x1000101, 0x1000102, 0x1000103 }, ' ') and plan.units[5] == nil,
    'Four units, best first, nothing after them: ' .. W.ids(plan));
settings.overhead.max_units = 10;
W.sub_active, W.sub = 0, 0;
-- Others when turned on, last. A player outside the party is found by the index its 0x00D gave.
settings.overhead.units.other = true;
local pc = update_packet(1004, 0x403, 0x01);
pc.id = 0x00D;
overhead.packet(pc);
W.frame(view, settings, snapshot);
assert(plan.units[plan.count].id == 1004 and plan.units[plan.count].kind == 'other', 'Other players come last.');
settings.overhead.units.other = false;
-- Each switch takes its units out.
settings.overhead.units.claimed, settings.overhead.units.party = false, false;
W.frame(view, settings, snapshot);
assert(W.ids(plan) == table.concat({ 0x1000100, 0x1000103, 0x1000104, 0x1000105, 1003 }, ' '), W.ids(plan));
settings.overhead.units.claimed, settings.overhead.units.party = true, true;
-- A mob claimed by someone outside the party isn't one of the party's, and an unclaim (claimer 0) forgets it.
overhead.packet(update_packet(0x1000102, 0x102, 0x02, 5555));
W.frame(view, settings, snapshot);
assert(not W.ids(plan):find(tostring(0x1000102), 1, true), 'A mob another player claimed gets no block for the claim.');
overhead.packet(update_packet(0x1000102, 0x102, 0x02, 1001));
overhead.packet(update_packet(0x1000102, 0x102, 0x02, 0));
assert(overhead._claimer(0x1000102) == nil, 'Claimer 0 is unclaimed.');
overhead.packet(update_packet(0x1000102, 0x102, 0x02, 1001));
overhead.packet(update_packet(0x1000102, 0x102, 0x20, 0));
assert(overhead._claimer(0x1000102) == nil, 'A despawn forgets it.');
overhead.packet(update_packet(0x1000102, 0x102, 0x02, 1001));
overhead.packet({ id = 0x00A, data = '', size = 0 });
assert(overhead._claimer(0x1000102) == nil, 'A zone change forgets every claim.');
W.spawns();
overhead.packet(update_packet(0x1000102, 0x102, 0x02, 1001));
-- Packets are read while overhead icons are off too, so icons turned on mid-fight know the claims made meanwhile.
settings.overhead.enabled = false;
overhead.packet(update_packet(0x1000102, 0x102, 0x02, 0));
assert(overhead._claimer(0x1000102) == nil, 'An unclaim is read while the icons are off.');
overhead.packet(update_packet(0x1000102, 0x102, 0x02, 1001));
assert(overhead._claimer(0x1000102) == 1001, 'So is a claim.');
settings.overhead.enabled = true;
W.frame(view, settings, snapshot);
assert(W.ids(plan):find(tostring(0x1000102), 1, true), 'Turned on, the mob claimed while they were off has its block: ' .. W.ids(plan));
-- A unit with no effects to show takes no block; the target does.
W.frame(W.view({ 1002 }), settings, snapshot);
assert(W.ids(plan) == table.concat({ 0x1000100, 1002 }, ' '), 'Only the target and the member with an effect: ' .. W.ids(plan));
-- Nor does one whose effects its type's filters all leave out, so it takes no place from a unit with icons to draw: with
-- room for two, a near member with only Protect (one of the usual long effects) or only a Haste someone else cast
-- (party blocks show the buffs you cast) leaves the second place to a farther alliance member with Paralysis.
settings.overhead.max_units = 2;
local function second(row)
    row.entity_id, row.kind, row.scope = 1002, 'buff', 'party';
    W.frame(W.view({ row, { entity_id = 1003, kind = 'debuff', scope = 'alliance', effect = 4 } }), settings, snapshot);
    return W.ids(plan);
end
assert(second({ effect = 40, mine = true }) == table.concat({ 0x1000100, 1003 }, ' '), 'Only Protect: ' .. W.ids(plan));
assert(second({ effect = 33, source = 1004 }) == table.concat({ 0x1000100, 1003 }, ' '), 'Only another\'s Haste: ' .. W.ids(plan));
assert(second({ effect = 33, mine = true }) == table.concat({ 0x1000100, 1002 }, ' '), 'Your own Haste shows: ' .. W.ids(plan));
settings.overhead.types.party.exclude = { 33 };
assert(second({ effect = 33, mine = true }) == table.concat({ 0x1000100, 1003 }, ' '), 'An excluded Haste: ' .. W.ids(plan));
settings.overhead.types.party.exclude = {};
-- A member with party cooldown estimates (core/party_cooldowns.lua) takes a block for their line while they go over
-- heads, though the filters leave none of the member's effects: only Protect, and a Benediction estimate.
local benediction = { ability = 18, name = 'Benediction', job = 3, recast = 7200, special = true, start = W.now, deadline = W.now + 7000,
    member = 1002, member_name = 'Member' };
local function cooling()
    local view = W.view({ { entity_id = 1002, kind = 'buff', scope = 'party', effect = 40, mine = true },
        { entity_id = 1003, kind = 'debuff', scope = 'alliance', effect = 4 } });
    view.member_cooldowns = { [1002] = { benediction } };
    W.frame(view, settings, snapshot);
    return W.ids(plan);
end
-- The party cooldown watch is off at first, and its line shows only while it is on.
settings.party_cooldowns.enabled = true;
assert(cooling() == table.concat({ 0x1000100, 1003 }, ' '), 'With the line off, Protect alone takes no block: ' .. W.ids(plan));
settings.party_cooldowns.overhead = true;
assert(cooling() == table.concat({ 0x1000100, 1002 }, ' '), 'With it on, the member\'s estimate takes a block: ' .. W.ids(plan));
local member = plan.units[2];
local slots = require('ui.overhead_icons')._slots;
local imgui = require('imgui');
rawset(imgui, 'GetBackgroundDrawList', function() return imgui.GetWindowDrawList(); end);
require('ui.overhead_icons').draw(plan, { [1002] = { effects = { { entity_id = 1002, kind = 'buff', scope = 'party', effect = 40, mine = true } },
    cooldowns = { benediction } } }, settings, W.now);
rawset(imgui, 'GetBackgroundDrawList', nil);
assert(member.id == 1002 and slots[2].count == 1 and slots[2].cooldown[1] and slots[2].effect[1] == benediction,
    'Its block draws the cooldown line and nothing else.');
settings.party_cooldowns.enabled = false;
assert(cooling() == table.concat({ 0x1000100, 1003 }, ' '), 'With the watch off, no block for it: ' .. W.ids(plan));
settings.party_cooldowns.enabled, settings.party_cooldowns.overhead, settings.overhead.max_units = true, false, 10;
-- Within a priority, the nearest first: two debuffed mobs, the far one listed first.
W.unit(0x107, 0x1000107, 'mob', 0, -12, { name = 'Far' });
W.unit(0x108, 0x1000108, 'mob', 0, -4, { name = 'Near' });
local two = W.view({ { entity_id = 0x1000107, kind = 'debuff', scope = 'enemy', source = 1001 },
    { entity_id = 0x1000108, kind = 'debuff', scope = 'enemy', source = 0x1000105 } });
W.target = 0;
W.frame(two, settings, snapshot);
assert(W.ids(plan) == table.concat({ 0x1000108, 0x1000107 }, ' '), 'Nearest first within a priority, a pet\'s debuff counts: ' .. W.ids(plan));
W.target = 0x100;

-- Every hide state, one unit at a time: not drawn, hidden in a cutscene or menu, no model, dead, a mob at 0 HP,
-- off screen and behind the camera.
local function shown(id)
    W.frame(view, settings, snapshot);
    for i = 1, plan.count do if plan.units[i].id == id then return plan.units[i]; end end
end
assert(shown(0x1000100));
for key, value in pairs({ flags = 0, actor = 0, status = 2, hpp = 0 }) do
    local kept = target[key];
    target[key] = value;
    assert(not shown(0x1000100), 'The target is hidden with ' .. key .. ' ' .. value);
    target[key] = kept;
end
target.flags = 0x4200;
assert(not shown(0x1000100), 'Render flag 0x4000 hides it.');
target.flags, target.status = 0x200, 3;
assert(not shown(0x1000100), 'Status 3 is dead.');
target.status = 0;
local member = W.entities[0x401];
member.hpp = 0;
assert(shown(1002), 'Only a mob hides at 0 HP; a member\'s HPP comes from the party.');
member.hpp = 100;
target.x = 25;
assert(not shown(0x1000100), 'Off screen to the side, inside the distance cap.');
target.x, target.y = 0, 15;
assert(not shown(0x1000100), 'Behind the camera.');
target.y = -5;
assert(shown(0x1000100));
-- Whole-plan hides, each with its reason.
local function hidden(reason)
    W.frame(view, settings, snapshot);
    assert(plan.count == 0 and plan.units[1] == nil and plan.hidden == reason, ('%s, not %s'):format(reason, tostring(plan.hidden)));
end
W.entities[W.self].status = 4; hidden('In an event.'); W.entities[W.self].status = 0;
memory[event_flag] = 1; hidden('In an event.'); memory[event_flag] = 0;
memory[interface + 0xB4] = 1; hidden('The game interface is hidden.'); memory[interface + 0xB4] = 0;
memory[interface + 0x54] = menu; hidden('The map is open.');
memory[header + 0x4E] = 0x20756E65; assert(shown(0x1000100), 'Another menu hides nothing.'); memory[interface + 0x54] = 0;
W.zoning = 1; hidden('Changing zones.'); W.zoning = 0;
W.party_zone = 103; hidden('Changing zones.'); W.party_zone = 102;
W.frame(view, settings, snapshot, true);
assert(plan.count == 0 and plan.hidden == 'Vantage displays are hidden.', 'Hidden with Vantage\'s displays.');
-- Their show conditions hide them with a reason of their own, for /vg report.
W.now = W.now + 0.125;
overhead.update(view, settings, snapshot, W.now, false, true);
assert(plan.count == 0 and plan.hidden == 'Its When to show choices hide it here.', 'Hidden by its show conditions: ' .. tostring(plan.hidden));
W.frame(view, settings, { valid = false });
assert(plan.count == 0 and plan.hidden == 'No character is in the game.');
assert(shown(0x1000100));
-- A camera that can't be read is held 250 ms, then hides everything.
W.unreadable = true;
assert(shown(0x1000100), 'Held for this frame.');
W.frame(view, settings, snapshot, false, 0.3);
assert(plan.count == 0 and plan.hidden == 'The camera can\'t be used.', tostring(plan.hidden));
W.unreadable = false;
assert(shown(0x1000100));
-- In scene mode a hidden stretch reads no camera, and the first frame shown again reads its own: here the game's camera
-- turns bad (500 yalms away) while the blocks are hidden, so that frame places nothing.
local camera = require('core.camera');
settings.overhead.camera.capture = 'scene';
local function scene_frame(hide)
    camera.scene(true); camera.scene(true);
    W.frame(view, settings, snapshot, hide);
end
scene_frame(false); scene_frame(false);
assert(plan.valid and plan.count > 0, 'Scene mode places the blocks: ' .. tostring(plan.hidden));
scene_frame(true);
local good_view = W.view_matrix;
W.view_matrix = { 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, -1, 0, 0, -2, 500, 1 };
for _ = 1, 20 do scene_frame(true); end
scene_frame(false);
assert(not plan.valid and plan.hidden == 'The camera can\'t be used.' and not camera.valid(),
    'The first frame back uses no camera read before it: ' .. tostring(plan.hidden));
W.view_matrix = good_view;
scene_frame(false);
assert(plan.valid and plan.count > 0, 'A good camera places them again.');
settings.overhead.camera.capture = 'present';
-- Your own block hides in first person.
settings.overhead.units.self = true;
local mine = W.view({ 1001 });
W.frame(mine, settings, snapshot);
assert(W.ids(plan):find('1001', 1, true), 'Your own block when turned on.');
W.first_person = 1;
W.frame(mine, settings, snapshot);
assert(not W.ids(plan):find('1001', 1, true), 'Not in first person.');
W.first_person, settings.overhead.units.self = 0, false;
-- Off turns everything off and reads nothing.
settings.overhead.enabled = false;
local reads = W.reads;
W.frame(view, settings, snapshot);
assert(plan.count == 0 and plan.units[1] == nil and plan.hidden == 'Off.' and W.reads == reads, 'Off reads no camera.');
settings.overhead.enabled = true;

-- The distance cap, default 30, and the fade from 20 yalms down to half at the cap. The target never fades.
local far = W.unit(0x109, 0x1000109, 'mob', 0, -25, { name = 'Fading' });
local reach = W.view({ { entity_id = 0x1000109, kind = 'debuff', scope = 'enemy', source = 1001 } });
local function unit_for(id) for i = 1, plan.count do if plan.units[i].id == id then return plan.units[i]; end end end
W.target = 0;
W.frame(reach, settings, snapshot);
assert(math.abs(unit_for(0x1000109).alpha - 0.75) < 1e-9, 'Three quarters at 25 of 30 yalms.');
far.y = -31;
W.frame(reach, settings, snapshot, false, 0.2);
assert(not unit_for(0x1000109), 'Beyond the 30 yalm cap.');
settings.overhead.distance_cap = 50;
W.frame(reach, settings, snapshot, false, 0.2);
assert(math.abs(unit_for(0x1000109).alpha - (1 - 11 / 30 * 0.5)) < 1e-9, 'A cap of 50 fades over 20 to 50.');
far.y = -45;
W.target = 0x109;
W.frame(reach, settings, snapshot, false, 0.2);
assert(unit_for(0x1000109).alpha == 1 and unit_for(0x1000109).target, 'The target is not faded.');
settings.overhead.distance_cap, W.target = 30, 0x100;
W.entities[0x109] = nil;

-- Towns: only the target and the party. Sealion's Den is typed city but keeps every block.
snapshot.zone, W.party_zone = 230, 230;
W.frame(view, settings, snapshot, false, 0.2);
assert(W.ids(plan) == table.concat({ 0x1000100, 1002 }, ' '), 'Southern San d\'Oria: target and party: ' .. W.ids(plan));
settings.overhead.hide_in_cities = false;
W.frame(view, settings, snapshot, false, 0.2);
assert(plan.count == 7, 'With the city rule off, everything.');
settings.overhead.hide_in_cities = true;
snapshot.zone, W.party_zone = 32, 32;
W.frame(view, settings, snapshot, false, 0.2);
assert(plan.count == 7, 'Sealion\'s Den keeps every block.');
for _, zone in ipairs({ 80, 87, 94, 256, 257, 280, 284, 285, 189, 70, 71, 0 }) do
    assert(not overhead._cities[zone], 'Zone ' .. zone .. ' is out of era and not a town here.');
end
for _, zone in ipairs({ 26, 48, 50, 230, 243, 246, 252 }) do assert(overhead._cities[zone], 'Zone ' .. zone .. ' is a town.'); end
snapshot.zone, W.party_zone = 102, 102;

-- SpawnFlags first: a mob read as Type 2 still counts as a mob; a non-mob of Type 2 or 3 gets nothing, even as target.
W.unit(0x10A, 0x100010A, 'mob', 0, -6, { name = 'Troll', type = 2 });
W.unit(0x10B, 0x100010B, 'npc', 0, -6, { name = 'Statue', type = 2 });
W.unit(0x10C, 0x100010C, 'npc', 0, -6, { name = 'Door', type = 3 });
local mixed = W.view({ { entity_id = 0x100010A, kind = 'debuff', scope = 'enemy', source = 1001 },
    { entity_id = 0x100010B, kind = 'debuff', scope = 'enemy', source = 1001 } });
W.target = 0x10C;
W.frame(mixed, settings, snapshot, false, 0.2);
assert(W.ids(plan) == tostring(0x100010A) and plan.units[1].kind == 'mob', 'Only the Type 2 mob: ' .. W.ids(plan));
W.target = 0x10B;
W.frame(mixed, settings, snapshot, false, 0.2);
assert(W.ids(plan) == tostring(0x100010A), 'A Type 2 non-mob target gets nothing.');
-- An NPC of Type 1 as the target gets a block as another unit.
W.entities[0x10B].type = 1;
W.frame(mixed, settings, snapshot, false, 0.2);
assert(plan.units[1].id == 0x100010B and plan.units[1].kind == 'other', 'An NPC target is an other unit.');

-- The block's anchor above the name: a mob's name is centered on its head point. At depth 15, 61.2 px a yalm, the name
-- is 0.33 yalm, 20.2 px, under its 24 px cap, and the target cursor over it 0.4 yalm, held at its 16 px; the edge sits
-- half the name, the cursor and the 3 px gap over the head point, the type's screen offsets after. below_name puts it
-- under the head point.
W.target = 0x100;
settings.overhead.types.mob.screen_x, settings.overhead.types.mob.screen_y = 5, -7;
W.frame(view, settings, snapshot, false, 0.2);
local aimed = plan.units[1];
local name_top = 540 + (2 - 2.1) * 1.7 * 1080 / 30 - 0.33 * 1.7 * 1080 / 30 / 2;
assert(math.abs(aimed.name_px - 0.33 * 1.7 * 1080 / 30) < 1e-9 and aimed.arrow_px == 16, 'The name and the cursor at depth 15.');
assert(aimed.id == 0x1000100 and aimed.anchor_x == aimed.x + 5 and aimed.anchor_y == math.floor(name_top - 16 - 3 - 7 + 0.5)
    and aimed.anchor_y == 498, 'Above the name: ' .. aimed.anchor_y);
settings.overhead.layout.placement = 'below_name';
W.frame(view, settings, snapshot, false, 0.2);
assert(not plan.above and aimed.anchor_y == aimed.y + 3 - 7, 'Below the head point.');
-- The head point is the projection of (X, Z - H, Y): at depth 15 a 2.1 yalm mob's head sits 2.1 * px per yalm above
-- its feet, the feet 2 yalms under the camera's eye line.
local ppy = 1.7 * 1080 / 30;
assert(math.abs(aimed.depth - 15) < 1e-9 and math.abs(aimed.ppy - ppy) < 1e-9 and math.abs(aimed.head - 2.1) < 1e-9);
assert(aimed.y == math.floor(540 + (2 - 2.1) * ppy + 0.5), 'The head point, up negative.');
assert(aimed.size == 22, 'The target at depth 15: 18.0 px times 1.2 is 22 px; got ' .. aimed.size);

-- Other players' pets: the tracker's pet scope says what they are, and the other pets switch takes them.
settings.overhead.layout.placement, settings.overhead.types.mob.screen_x, settings.overhead.types.mob.screen_y = 'above_name', 0, 0;
W.unit(0x10D, 0x100010D, 'pet', 1, -5, { name = 'Their pet' });
local pets = W.view({ { entity_id = 0x100010D, kind = 'debuff', scope = 'pet' } });
local alone = W.snapshot({ members[1] });
W.target = 0;
settings.overhead.units.other = true;
W.frame(pets, settings, alone, false, 0.2);
assert(plan.count == 0, 'Other pets off: their pet gets no block, with other players on or not: ' .. W.ids(plan));
settings.overhead.units.other_pet = true;
W.frame(pets, settings, alone, false, 0.2);
assert(W.ids(plan) == tostring(0x100010D) and plan.units[1].kind == 'other_pet', 'Other pets on: ' .. W.ids(plan));
settings.overhead.units.other, settings.overhead.units.other_pet = false, false;
-- Phoenix has no trusts, so the client's trust owner field isn't read, and an NPC with it set is a unit like any other.
local owner_read = false;
AshitaCore:GetMemoryManager():GetEntity().GetTrustOwnerTargetIndex = function() owner_read = true; return W.self; end;
W.unit(0x10E, 0x100010E, 'npc', 2, -6, { name = 'Helper', type = 1, race = 5 });
local helper = W.view({ { entity_id = 0x100010E, kind = 'debuff', scope = 'party' } });
local with_helper = W.snapshot({ members[1], { id = 0x100010E, index = 0x10E, scope = 'party' } });
W.frame(helper, settings, with_helper, false, 0.2);
assert(plan.count == 0, 'Other players off: it gets no block: ' .. W.ids(plan));
settings.overhead.units.other = true;
W.frame(helper, settings, with_helper, false, 0.2);
assert(plan.count == 1 and plan.units[1].kind == 'other', 'It goes by Other players: ' .. tostring(plan.units[1] and plan.units[1].kind));
assert(not owner_read, 'The trust owner field is never read.');
settings.overhead.units.other = false;

-- Whole pixels hold through a slow bob of under 0.6 px, across the lists made ten times a second, and still follow a
-- real change.
local bobbing = W.unit(0x10F, 0x100010F, 'mob', 0, -0.4706, { name = 'Bob', hitbox = 1.5 });
local bob = W.view({ { entity_id = 0x100010F, kind = 'debuff', scope = 'enemy', source = 1001 } });
local flips, last = 0, nil;
for frame = 1, 600 do
    -- 21.46 to 21.54 px.
    bobbing.y = -0.4706 + 0.04 * math.sin(frame / 30);
    W.frame(bob, settings, snapshot, false, 1 / 60);
    local size = unit_for(0x100010F).size;
    if last and size ~= last then flips = flips + 1; end
    last = size;
end
assert(flips == 0 and last == 22, ('A slow bob changed the size %d times, ending at %d px'):format(flips, last));
bobbing.y = -5;
W.frame(bob, settings, snapshot, false, 1 / 60);
assert(unit_for(0x100010F).size == 18, 'At depth 15 the size moves to 18 px.');

-- known counts the entities kept: a despawn takes its entity off, and one never seen takes nothing off. So a long
-- camp's respawns never wipe the claims, while more than 1024 entities at once still do.
overhead.packet({ id = 0x00A, data = '', size = 0 });
overhead.packet(update_packet(0x1000102, 0x102, 0x02, 1001));
for n = 1, 1100 do
    local index = 0x200 + n % 0x600;
    overhead.packet(update_packet(0x1100000 + n, index, 0x20));
    overhead.packet(update_packet(0x1200000 + n, index, 0x01));
    overhead.packet(update_packet(0x1200000 + n, index, 0x20));
end
assert(overhead._claimer(0x1000102) == 1001, 'Respawns never wipe the claims.');
for n = 1, 1023 do overhead.packet(update_packet(0x1300000 + n, 0x200 + n % 0x600, 0x01)); end
assert(overhead._claimer(0x1000102) == 1001, 'Up to 1024 entities at once are kept.');
overhead.packet(update_packet(0x1400000, 0x7FF, 0x01));
assert(overhead._claimer(0x1000102) == nil, 'One more forgets them all.');
-- Each mob's next 0x00E brings its icons back.
W.spawns();

-- A unit the client gives no distance for between two lists gets no block.
W.frame(bob, settings, snapshot, false, 0.2);
assert(unit_for(0x100010F), 'Fixture: Bob has a block.');
local entities = AshitaCore:GetMemoryManager():GetEntity();
local distance = entities.GetDistance;
entities.GetDistance = function(self, index) if index == 0x10F then return nil; end return distance(self, index); end;
W.frame(bob, settings, snapshot, false, 1 / 60);
entities.GetDistance = distance;
assert(plan.valid and not unit_for(0x100010F), 'No distance, no block.');
