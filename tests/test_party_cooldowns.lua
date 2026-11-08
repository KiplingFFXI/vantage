-- The party cooldown watch (core/party_cooldowns.lua): a party or alliance member seen using a two-hour or a key job
-- ability (a 0x028 category 6 with its id, Eagle Eye Shot a category 3 told by its messages) counts down that
-- ability's base recast for them. Not you, not other players, not pets. Wild Card resets what it lands
-- on by its roll, a job change keeps only the two-hour, and a member who leaves is dropped. The estimates show on the
-- member's strip, nearest the game's window, over their head when that option is on, and in the list display,
-- which moves only unlocked with Shift held, filters by job and ability, sorts by time left and truncates silently.
-- The strips' samples show sample estimates in the normal look.
local observer, cooldowns, defaults = require('core.observer'), require('core.party_cooldowns'), require('ui.defaults');
local imgui = require('imgui');
local self_id, ally, friend, stranger, npc = 1001, 1002, 1003, 1500, 0x1000123;
local snapshot = { valid = true, id = self_id, zone = 102, name = 'Tester', level = 75, job = 1, self_known = true, self_effects = {},
    party = { { id = ally, name = 'Ally', scope = 'party', zone = 102, slot = 1 }, { id = friend, name = 'Friend', scope = 'alliance', zone = 102, slot = 6 },
        { id = npc, name = 'Trion', scope = 'party', zone = 102, slot = 2 } },
    entities = { [self_id] = { name = 'Tester', kind = 'player' }, [ally] = { name = 'Ally', kind = 'player' },
        [friend] = { name = 'Friend', kind = 'player' }, [stranger] = { name = 'Stranger', kind = 'player' },
        [npc] = { name = 'Trion', kind = 'npc' }, [0x1000001] = { name = 'Crab', kind = 'monster' } } };
local function fresh() return defaults.tidy(defaults.make()); end;
local function putbits(bytes, offset, length, value)
    for i = 0, length - 1 do
        local at = offset + i;
        if math.floor(value / 2 ^ i) % 2 == 1 then bytes[math.floor(at / 8)] = bytes[math.floor(at / 8)] + 2 ^ (at % 8); end
    end
end
-- One action: its actor, category and id, and each target with its message and param.
local function action(actor, category, id, targets)
    local bytes, at = MOCK.bytes(2048), 150;
    putbits(bytes, 40, 32, actor); putbits(bytes, 72, 6, #targets); putbits(bytes, 82, 4, category); putbits(bytes, 86, 32, id);
    for _, target in ipairs(targets) do
        putbits(bytes, at, 32, target[1]); putbits(bytes, at + 32, 4, 1); at = at + 36;
        putbits(bytes, at + 27, 17, target[3]); putbits(bytes, at + 44, 10, target[2]); at = at + 87;
    end
    bytes.n = math.ceil(at / 8);
    return MOCK.packet(0x028, bytes);
end
local function uses(events)
    local out = {};
    for _, event in ipairs(events) do if event.kind == 'cooldown' or event.kind == 'cooldown_reset' then out[#out + 1] = event; end end
    return out;
end

-- What the observer sees.
local seen = uses(observer.read(action(ally, 6, 18, { { ally, 102, 0 }, { self_id, 102, 0 } }), 1, snapshot));
assert(#seen == 1 and seen[1].kind == 'cooldown' and seen[1].entity_id == ally and seen[1].ability == 18 and seen[1].scope == 'party'
    and seen[1].entity_name == 'Ally', 'A party member\'s Benediction is a use.');
seen = uses(observer.read(action(friend, 6, 22, { { friend, 100, 0 } }), 1, snapshot));
assert(#seen == 1 and seen[1].scope == 'alliance', 'An alliance member\'s Invincible is a use.');
assert(#uses(observer.read(action(self_id, 6, 18, { { self_id, 102, 0 } }), 1, snapshot)) == 0, 'Your own use is read from the client instead.');
assert(#uses(observer.read(action(stranger, 6, 18, { { stranger, 102, 0 } }), 1, snapshot)) == 0, 'Someone outside the party is not watched.');
assert(#uses(observer.read(action(npc, 6, 35, { { 0x1000001, 119, 0 } }), 1, snapshot)) == 0, 'Only a player is watched.');
assert(#uses(observer.read(action(ally, 6, 34, { { ally, 118, 58 } }), 1, snapshot)) == 0, 'Aggressor is not on the list.');
assert(#uses(observer.read(action(ally, 13, 18, { { ally, 100, 0 } }), 1, snapshot)) == 0, 'A pet move with the same id is not a use.');
assert(#uses(observer.read(action(ally, 11, 35, { { ally, 100, 0 } }), 1, snapshot)) == 0, 'A jug pet\'s move is not a use either.');
seen = uses(observer.read(action(ally, 3, 26, { { 0x1000001, 110, 900 } }), 1, snapshot));
assert(#seen == 1 and seen[1].ability == 26, 'Eagle Eye Shot hits as a category 3 with message 110.');
assert(#uses(observer.read(action(ally, 3, 26, { { 0x1000001, 324, 0 } }), 1, snapshot)) == 1, 'and misses with 324.');
assert(#uses(observer.read(action(ally, 3, 26, { { 0x1000001, 185, 900 } }), 1, snapshot)) == 0, 'Mercy Stroke, the weapon skill with its id, is not.');
assert(#uses(observer.read(action(ally, 6, 26, { { 0x1000001, 110, 900 } }), 1, snapshot)) == 0, 'Eagle Eye Shot is never a category 6.');
-- A Wild Card from a member, then from you: a use (only from the member) and a reset for each member it lands on.
seen = uses(observer.read(action(ally, 6, 96, { { ally, 435, 5 }, { self_id, 435, 5 }, { friend, 435, 5 } }), 1, snapshot));
assert(#seen == 3 and seen[1].kind == 'cooldown' and seen[2].kind == 'cooldown_reset' and seen[2].entity_id == ally and seen[2].roll == 5
    and seen[3].entity_id == friend, 'A member\'s Wild Card is a use and resets each member it lands on, never you.');
seen = uses(observer.read(action(self_id, 6, 96, { { self_id, 435, 2 }, { ally, 435, 2 } }), 1, snapshot));
assert(#seen == 1 and seen[1].kind == 'cooldown_reset' and seen[1].roll == 2, 'Your own Wild Card resets the members it lands on.');

-- The watch.
local s = fresh();
-- The watch is off at first, so the checks of what it counts turn it on.
s.party_cooldowns.enabled = true;
local watch = cooldowns.new();
watch:observe({ kind = 'cooldown', entity_id = ally, ability = 18, entity_name = 'Ally' }, 100);
watch:observe({ kind = 'cooldown', entity_id = ally, ability = 74, entity_name = 'Ally' }, 100);
watch:observe({ kind = 'cooldown', entity_id = friend, ability = 35, entity_name = 'Friend' }, 110);
watch:observe({ kind = 'cooldown', entity_id = friend, ability = 999, entity_name = 'Friend' }, 110);
local shown = watch:refresh(120, s, snapshot.party);
assert(#shown == 3, 'Three estimates, the unknown ability left out: ' .. #shown);
assert(shown[1].ability == 35 and shown[1].deadline == 140 and shown[2].ability == 74 and shown[2].deadline == 700
    and shown[3].ability == 18 and shown[3].deadline == 7300, 'Sorted soonest ready: Provoke 30 s, Divine Seal 600 s, Benediction 7200 s.');
local own = watch:of(ally);
assert(#own == 2 and own[1].ability == 74 and own[2].ability == 18, 'A member\'s own list, soonest first.');
shown = watch:refresh(141, s, snapshot.party);
assert(#shown == 2 and watch:of(friend) == nil, 'An estimate that ran out is gone.');
-- Wild Card: a roll of 1 to 4 resets job abilities, 5 or 6 the two-hour too.
watch:observe({ kind = 'cooldown_reset', entity_id = ally, roll = 3 }, 150);
shown = watch:refresh(150, s, snapshot.party);
assert(#shown == 1 and shown[1].ability == 18, 'Wild Card 3 resets Divine Seal and keeps Benediction.');
watch:observe({ kind = 'cooldown_reset', entity_id = ally, roll = 6 }, 151);
assert(#watch:refresh(151, s, snapshot.party) == 0, 'Wild Card 6 resets Benediction.');
watch:observe({ kind = 'cooldown', entity_id = ally, ability = 96, entity_name = 'Ally' }, 160);
watch:observe({ kind = 'cooldown', entity_id = ally, ability = 133, entity_name = 'Ally' }, 160);
watch:observe({ kind = 'cooldown_reset', entity_id = ally, roll = 6 }, 160);
shown = watch:refresh(160, s, snapshot.party);
assert(#shown == 1 and shown[1].ability == 96, 'With no job read, a Corsair is told by their Wild Card, which a 6 keeps; Random Deal goes.');
-- A job change keeps only the two-hour.
watch:observe({ kind = 'cooldown', entity_id = ally, ability = 74, entity_name = 'Ally' }, 170);
local roster = { valid = true, members = { { id = ally, job = 17, subjob = 3 } } };
watch:refresh(170, s, snapshot.party, roster);
roster.members[1].job = 3;
shown = watch:refresh(171, s, snapshot.party, roster);
assert(#shown == 1 and shown[1].ability == 96, 'After a job change only the two-hour is left.');
-- With the job read, a 5 or 6 keeps the two-hour only of a member whose main job is COR, whichever two-hour it is.
watch:observe({ kind = 'cooldown_reset', entity_id = ally, roll = 6 }, 171);
assert(#watch:refresh(171, s, snapshot.party, roster) == 0, 'A Corsair who changed to WHM loses their Wild Card to a 6.');
watch:observe({ kind = 'cooldown', entity_id = ally, ability = 18, entity_name = 'Ally' }, 171);
watch:refresh(171, s, snapshot.party, roster);
roster.members[1].job = 17;
watch:refresh(171, s, snapshot.party, roster);
watch:observe({ kind = 'cooldown_reset', entity_id = ally, roll = 6 }, 171);
shown = watch:refresh(171, s, snapshot.party, roster);
assert(#shown == 1 and shown[1].ability == 18, 'A WHM who changed to COR keeps their Benediction through a 6.');
-- While zoning the snapshot lists no one, and nobody is dropped.
assert(#watch:refresh(171.5, s, nil) == 1 and watch.members[ally], 'While zoning nobody is dropped.');
-- A member who leaves the party is dropped.
local alone = { { id = friend, name = 'Friend', scope = 'alliance' } };
assert(#watch:refresh(172, s, alone) == 0 and watch.members[ally] == nil, 'A member who left is dropped.');
-- The ignore list and the list's own filters; off keeps nothing.
watch:observe({ kind = 'cooldown', entity_id = ally, ability = 18, entity_name = 'Ally' }, 200);
watch:observe({ kind = 'cooldown', entity_id = friend, ability = 35, entity_name = 'Friend' }, 200);
s.party_cooldowns.ignore[35] = true;
shown = watch:refresh(201, s, snapshot.party);
assert(#shown == 1 and shown[1].ability == 18 and watch:of(friend) == nil, 'An ability off the watch list shows nowhere.');
s.party_cooldowns.ignore = {};
s.party_cooldowns.list.jobs = { [1] = true };
shown = watch:refresh(202, s, snapshot.party);
assert(#shown == 1 and shown[1].ability == 35 and #watch:of(ally) == 1, 'The list shows the jobs picked; the strips show everything.');
s.party_cooldowns.list.jobs, s.party_cooldowns.list.abilities = {}, { [18] = true };
shown = watch:refresh(203, s, snapshot.party);
assert(#shown == 1 and shown[1].ability == 18, 'and the abilities picked.');
s.party_cooldowns.list.abilities, s.party_cooldowns.list.sort = {}, 'name';
shown = watch:refresh(204, s, snapshot.party);
assert(shown[1].member_name == 'Ally' and shown[2].member_name == 'Friend', 'Sorted by member name.');
s.party_cooldowns.enabled = false;
assert(#watch:refresh(205, s, snapshot.party) == 0 and next(watch.members) == nil, 'Turned off, nothing is kept.');
s.party_cooldowns.enabled = true;
-- The tooltip says estimated, with the base recast, and never what to do. Its times read like every countdown.
local tip = cooldowns.details({ ability = 18, name = 'Benediction', member_name = 'Ally', recast = 7200, deadline = 1300 }, 100);
assert(tip:find('Estimated ready in 20m', 1, true) and tip:find('base recast of 2h', 1, true) and tip:find('30 yalms', 1, true),
    'The tooltip says it is an estimate: ' .. tip);
assert(not tip:lower():find('unknown', 1, true) and not tip:find('?', 1, true), 'No unknown and no question mark.');
-- Only the abilities merits shorten on Phoenix say so, and gear shortens none of them.
local berserk = cooldowns.details({ ability = 31, name = 'Berserk', member_name = 'Ally', recast = 300, deadline = 400 }, 100);
assert(berserk:find('Merits can make it shorter', 1, true) and not tip:find('Merits', 1, true)
    and not (tip .. berserk):lower():find('gear', 1, true), 'Merits only where they count: ' .. tip .. ' / ' .. berserk);
local merited = {};
for _, info in ipairs(cooldowns.list) do if info.merits then merited[#merited + 1] = info.id; end end
table.sort(merited);
assert(table.concat(merited, ',') == '31,32,48,63,74,75,83,85,92,133,136,153,154,157,158',
    'Merits shorten Berserk, Warcry, the seals, Convert, Sentinel, Rampart, Call Beast, Meditate, Random Deal, Activate, Martyr, Devotion, Fealty and Chivalry: '
    .. table.concat(merited, ','));

-- Settings: fresh saves and saves without it get the watch off, the strips on, over heads off and the list off and locked.
local old = defaults.tidy({ style = {}, panels = {} });
for _, value in ipairs({ fresh().party_cooldowns, old.party_cooldowns }) do
    assert(value.enabled == false and value.strips and not value.overhead and not value.list.enabled and value.list.locked and not value.preview,
        'The watch starts off, on the strips once on, with its list off and locked.');
end;
local kept = cooldowns.tidy({ list = { max_rows = 900, sort = 'odd', jobs = { 3, 99 }, height = 10 }, ignore = { ['18'] = true }, preview = true, extra = 1 });
assert(kept.list.max_rows == 64 and kept.list.sort == 'remaining' and kept.list.jobs[3] and not kept.list.jobs[99] and kept.list.height == 60
    and kept.ignore[18] and not kept.preview and kept.extra == 1, 'Tidy keeps choices in range, samples only with the list on, and unknown keys.');

-- The list display.
local hud = require('ui.hud');
local now = 1000;
local function entry(ability, member, left)
    local info = cooldowns.WATCHED[ability];
    return { ability = ability, name = info.name, job = info.job, recast = info.recast, member = 1, member_name = member, deadline = now + left };
end;
local function draw_list(settings, rows, callbacks, hidden)
    for _, panel in pairs(settings.panels) do panel.enabled = false; end;
    MOCK.imgui_calls = {};
    hud.draw({ valid = true, rows = {}, context = { valid = true, id = self_id, hidden = hidden }, cooldowns = rows }, settings, now, callbacks or {});
    local inside, texts, flags = false, {}, nil;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Begin' then inside = call[2] == '##vantage_cooldowns'; if inside then flags = call[4]; end;
        elseif call[1] == 'End' then inside = false;
        elseif inside and call[1] == 'draw:AddText' then texts[#texts + 1] = MOCK.drawn[call][#MOCK.drawn[call]]; end;
    end;
    return flags, texts;
end;
local listing = fresh();
-- The watch is off at first, and the list shows only while it is on.
listing.party_cooldowns.enabled = true;
local rows = { entry(35, 'Ally', 20), entry(74, 'Friend', 300), entry(18, 'Ally', 5000) };
assert(draw_list(listing, rows) == nil, 'The list is off at first.');
listing.party_cooldowns.list.enabled = true;
local flags, texts = draw_list(listing, rows);
local all = table.concat(texts, '|');
assert(flags and bit.band(flags, ImGuiWindowFlags_NoMouseInputs) ~= 0, 'Locked, the list takes no clicks.');
assert(all:find('Ally', 1, true) and all:find('Provoke', 1, true) and all:find('20s', 1, true) and all:find('Divine Seal', 1, true)
    and all:find('Benediction', 1, true) and all:find('|1h', 1, true), 'Each row shows its member, ability and time left: ' .. all);
listing.party_cooldowns.list.max_rows = 2;
flags, texts = draw_list(listing, rows);
all = table.concat(texts, '|');
assert(not all:find('Benediction', 1, true) and not all:find('+', 1, true) and not all:find('more', 1, true), 'Past the limit rows are left out silently.');
assert(draw_list(listing, {}) == nil, 'With nothing to show, the list hides.');
-- Samples show without any use seen.
listing.party_cooldowns.preview = true;
flags, texts = draw_list(listing, {});
assert(flags and table.concat(texts, '|'):find('Sample', 1, true), 'Sample displays show sample rows.');
listing.party_cooldowns.preview = false;
-- Paused timer panels, or panels their own rules hide, don't take the list with them, as they don't take the notices.
listing.enabled = false;
assert(draw_list(listing, rows), 'The list shows while the timer panels are paused.');
listing.enabled = true;
assert(draw_list(listing, rows, nil, true), 'and while their rule for the game\'s interface hides them.');
-- Unlocked, a Shift drag moves it; locked it stays.
local changes = 0;
local callbacks = { shift = true, changed = function(stage) if stage == 'after' then changes = changes + 1; end end, save = function() end };
local clicked = false;
rawset(imgui, 'IsItemHovered', function() return true; end);
rawset(imgui, 'IsMouseClicked', function() return not clicked; end);
local list_config = listing.party_cooldowns.list;
local x, y = list_config.x, list_config.y;
MOCK.mouse_down, MOCK.mouse_x, MOCK.mouse_y = true, x + 50, y + 50;
draw_list(listing, rows, callbacks);
MOCK.mouse_x = x + 150; draw_list(listing, rows, callbacks);
assert(list_config.x == x and changes == 0, 'A locked list stays put under Shift.');
list_config.locked = false;
MOCK.mouse_x = x + 50;
flags = draw_list(listing, rows, callbacks);
assert(bit.band(flags, ImGuiWindowFlags_NoMouseInputs) == 0, 'Unlocked with Shift held, the list can be dragged.');
clicked = true;
MOCK.mouse_x, MOCK.mouse_y = x + 150, y + 80;
draw_list(listing, rows, callbacks);
assert(list_config.x == x + 100 and list_config.y == y + 30 and changes == 1, 'The drag moves it: ' .. list_config.x .. ', ' .. list_config.y);
MOCK.mouse_down = false;
flags = draw_list(listing, rows, {});
assert(bit.band(flags, ImGuiWindowFlags_NoMouseInputs) ~= 0, 'Without Shift it takes no clicks.');
rawset(imgui, 'IsItemHovered', nil); rawset(imgui, 'IsMouseClicked', nil);

-- The strips: a member's estimates go first, nearest the game's window, and their effects after.
local overlay, party_hud = require('ui.native_party_hud'), require('ui.party_hud');
local p = require('ui.party_defaults').make();
local r, subjects = party_hud.sample(6, 100);
local geometry = { available = true, groups = {} };
local frame = { x = 900, y = 40, width = 116, height = 132, rows = {} };
for _, member in ipairs(r.members) do
    frame.rows[member.slot] = { x = 900, y = 40 + member.slot * 22, width = 116, height = 22, slot = member.slot };
end;
geometry.groups[1] = frame;
-- The buffs' countdowns start off; each cell still shows its time left.
assert(p.effects.timers == false, 'Fixture: fresh party buffs have no countdowns.');
p.enabled = true;
local before = overlay.plan(r, subjects, p, geometry, 1280, 720)[1].rows[2].area.x;
subjects[1002].cooldowns = { entry(18, 'Bramble', 600), entry(74, 'Bramble', 900) };
local function strips(on)
    local draws, images = {}, {};
    MOCK.imgui_calls = {};
    overlay.draw(r, subjects, p, now, { global_style = fresh().style, native_geometry = geometry, cooldowns = on });
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'draw:AddText' then draws[#draws + 1] = MOCK.drawn[call][#MOCK.drawn[call]]; end end;
    return table.concat(draws, '|');
end;
local text = strips({ enabled = true, strips = true });
local plans = overlay.plan(r, subjects, p, geometry, 1280, 720);
local row = plans[1].rows[2];
assert(row.cooldown_area and row.cooldown_area.count == 2 and row.cooldown_area.align_right, 'Bramble\'s strip holds two estimate cells.');
assert(row.cooldown_area.x + row.cooldown_area.width == frame.x - p.native.gap or row.cooldown_area.x + row.cooldown_area.width <= frame.x,
    'The cells sit nearest the game\'s window.');
assert(row.area.x + row.area.width <= row.cooldown_area.x + 0.001, 'Bramble\'s effects come after them.');
assert(text:find('10m', 1, true) and text:find('15m', 1, true), 'Each cell shows its time left: ' .. text);
-- The cells take the room, the whole step: rows 22 px tall and 30 px apart give 30 px cells from 4 px above.
for _, member in ipairs(r.members) do frame.rows[member.slot].y = 40 + member.slot * 30; end;
frame.height, frame.pitch = 172, 30;
strips({ enabled = true, strips = true });
row = overlay.plan(r, subjects, p, geometry, 1280, 720)[1].rows[2];
assert(row.cooldown_area.cell == 30 and row.cooldown_area.y == row.row.y - 4 and row.area.height == 30 and row.cooldown_area.count == 2,
    'The cells grow with the room.');
-- The cells keep 3 px between them and before the buffs, though the icons beside them touch.
assert(row.cooldown_area.width == 2 * (30 + 3) and row.area.x + row.area.width == row.cooldown_area.x, 'The cells keep 3 px.');
for _, member in ipairs(r.members) do frame.rows[member.slot].y = 40 + member.slot * 22; end;
frame.height, frame.pitch = 132, nil;
-- In a panel of its own the effects go after the estimates while a whole icon fits beside them, and on the rows
-- under them when not, so the icons never shrink.
local own = p.groups[1];
own.native_detached, own.detached_x, own.detached_y, own.detached_width, own.detached_height = true, 200, 200, 110, 400;
strips({ enabled = true, strips = true });
row = overlay.plan(r, subjects, p, geometry, 1280, 720)[1].rows[2];
local size = p.effects.icon_size;
assert(row.cooldown_area.count == 2 and row.area.x == row.cooldown_area.x and row.area.y == row.cooldown_area.y + size + 3,
    'With no room for an icon beside the estimates, the effects go under them.');
local under = require('ui.party_layout').effect_cells(row.effects, row.options, row.area);
assert(#under > 0 and under[1].width == size and under[1].height == size, 'At their whole size.');
own.detached_width = 420;
row = overlay.plan(r, subjects, p, geometry, 1280, 720)[1].rows[2];
assert(row.area.y == row.cooldown_area.y and row.area.x == row.cooldown_area.x + row.cooldown_area.width, 'With room, beside them.');
own.native_detached = false;
strips({ enabled = true, strips = false });
plans = overlay.plan(r, subjects, p, geometry, 1280, 720);
assert(not plans[1].rows[2].cooldown_area and plans[1].rows[2].area.x == before, 'With the strips option off, the row is as before.');
-- None on Party list buffs leaves the rows to the estimates.
p.effects.kind = 'none';
text = strips({ enabled = true, strips = true });
row = overlay.plan(r, subjects, p, geometry, 1280, 720)[1].rows[2];
assert(#row.effects == 0 and row.cooldown_area and row.cooldown_area.count == 2 and text:find('10m', 1, true) and text:find('15m', 1, true),
    'With None the estimates still show, with their times: ' .. text);
p.effects.kind = 'all';
-- The strips' samples give the first sample members a sample estimate each, so the cells show in their normal look.
p.preview = true;
local sampled = strips({ enabled = true, strips = true });
local kept_rows = overlay._kept.plans[1].rows;
local cells, first = 0, nil;
for _, item in ipairs(kept_rows) do
    if item.cooldown_area then cells, first = cells + 1, first or item; end
end;
assert(cells == 5 and first.cooldowns[1].member_name == 'Aster' and first.cooldowns[1].ability == 18,
    'Sample members Aster to Elm show their sample estimates: ' .. cells);
assert(sampled:find('7m', 1, true), 'With their times left: ' .. sampled);
strips({ enabled = true, strips = false });
for _, item in ipairs(overlay._kept.plans[1].rows) do assert(not item.cooldown_area, 'With the strips option off, the samples show none.'); end;
p.preview = false;

-- Over heads: a party member's block gains a line of their estimates when that option is on.
local slots = require('ui.overhead_icons')._slots;
rawset(imgui, 'GetBackgroundDrawList', function() return imgui.GetWindowDrawList(); end);
local heads = fresh();
-- The watch is off at first, and its line over heads shows only while it is on.
heads.party_cooldowns.enabled = true;
local plan = { valid = true, count = 1, order = { 1 }, ui = 1, above = true,
    units = { { kind = 'party', id = 1002, name = 'Bramble', size = 24, anchor_x = 400, anchor_y = 300, alpha = 1, player = true } } };
local function heads_count(on)
    heads.party_cooldowns.overhead = on;
    require('ui.overhead_icons').draw(plan, subjects, heads, now, nil, nil);
    local cooldown = 0;
    for n = 1, slots[1].count do if slots[1].cooldown[n] then cooldown = cooldown + 1; end end;
    return slots[1].count, cooldown;
end;
local total, line = heads_count(false);
assert(line == 0, 'Off, no estimates over heads.');
local with, cooldown = heads_count(true);
assert(cooldown == 2 and with == total + 2, 'On, the block gains its two estimates: ' .. with .. ' ' .. cooldown);
-- A member whose name hasn't come yet shows no estimate until it has, and never their id.
do
    local unnamed, settings = cooldowns.new(), fresh();
    settings.party_cooldowns.enabled = true;
    unnamed:observe({ kind = 'cooldown', entity_id = 1004, ability = 35 }, 10);
    local party = { { id = 1004, scope = 'party', zone = 102, slot = 3 } };
    assert(#unnamed:refresh(11, settings, party) == 0 and unnamed:of(1004) == nil, "An unnamed member's estimate waits for their name.");
    party[1].name = 'Late';
    local listed = unnamed:refresh(12, settings, party);
    assert(#listed == 1 and listed[1].member_name == 'Late', 'It shows once the name comes.');
end;
return 'The party cooldown watch counts, shows and moves as its settings say';
