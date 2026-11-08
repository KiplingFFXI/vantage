-- Overhead icons drawn: the three layouts at their default limits, silent truncation, the crowd control slot, the
-- order, countdowns on small icons, no '?' and no special look without a time, the per-type filters and the hide
-- rule scopes, dispellable mob buffs lit (and nothing else), overlapping blocks that keep their spots with the nearer
-- on top and the target on top of all, and that drawing opens no ImGui window or item: everything goes on the
-- background draw list.
local event_scan, interface_scan, focus_scan = 0x110000, 0x120000, 0x130000;
local interface, event_flag = 0x210000, 0x220000;
local memory = { [event_scan + 1] = event_flag, [interface_scan + 10] = interface, [focus_scan] = interface + 0x54,
    [interface + 0xB4] = 0, [event_flag] = 0, [interface + 0x54] = 0 };
ashita.memory.find = function(_, _, pattern)
    return pattern:sub(1, 2) == 'A0' and event_scan or pattern:sub(1, 8) == '8B442404' and interface_scan or focus_scan;
end;
local function read(address) return memory[address]; end
ashita.memory.read_uint8, ashita.memory.read_uint32 = read, read;
require('core.client')._set_pages(function() return true; end);

local W = require('overhead_fixture');
local overhead = require('core.overhead');
local draw = require('ui.overhead_icons');
local dispel = require('core.dispel');
local effect_filters = require('core.effect_filters');
local plan, slots = overhead.plan, draw._slots;
-- Status art is texture 5000 + id; 999 has none.
require('ui.icons')._set_loader_for_tests(function(id) return id ~= 999 and 5000 + id or false; end);

-- A draw list that keeps a copy of each call.
local calls = {};
local list = setmetatable({}, { __index = function(_, name)
    return function(_, ...) calls[#calls + 1] = MOCK.copy_arguments(name, ...); end;
end });
local imgui = require('imgui');
rawset(imgui, 'GetBackgroundDrawList', function() return list; end);
-- Text half as wide as its font size for each character, and as tall, so countdowns can shrink to fit.
rawset(imgui, 'CalcTextSize', function(text)
    local size = MOCK.font_stack[#MOCK.font_stack] or 18;
    return #tostring(text) * size * 0.5, size;
end);
local function named(name)
    local out = {};
    for _, call in ipairs(calls) do if call[1] == name then out[#out + 1] = call; end end
    return out;
end

-- The player: WAR 75, no tool to take a buff off, until a test makes them a RDM.
local player = AshitaCore:GetMemoryManager():GetPlayer();
local learned = {};
player.HasSpell = function(_, id) return learned[id] == true; end;
local function rdm(on)
    MOCK.player.main_job, MOCK.player.main_level, learned[260] = on and 5 or 1, 75, on;
    dispel._reset();
end
rdm(false);

local settings = W.settings();
settings.overhead.units.other = true;
local sequence = 0;
-- An effect row as the tracker gives it. kind is 'buff' or 'debuff'; fields add mine, source, remaining, priority.
local function effect(entity, id, kind, fields)
    sequence = sequence + 1;
    local row = { entity_id = entity, effect = id, kind = kind, name = 'Effect ' .. id, present = true, status = 'server',
        priority = 0, first_seen = sequence, first_sequence = sequence, key = entity .. ':' .. sequence, remaining = 300,
        scope = entity >= 0x1000000 and 'enemy' or 'party' };
    for key, value in pairs(fields or {}) do row[key] = value; end
    -- false stands for no time known.
    if row.remaining == false then row.remaining = nil; end
    return row;
end
local subjects, rows = {}, {};
local function give(entity, effects)
    subjects[entity] = { effects = effects };
    for _, row in ipairs(effects) do rows[#rows + 1] = row; end
end
local function reset() subjects, rows, sequence = {}, {}, 0; end
local snapshot;
local function frame(recipients)
    calls = {};
    W.frame(W.view(rows), settings, snapshot);
    return draw.draw(plan, subjects, settings, W.now, nil, recipients);
end
local function slot_of(id)
    for index = 1, plan.count do if plan.units[index].id == id then return slots[index], plan.units[index]; end end
end
local function ids(slot)
    local out = {};
    for n = 1, slot.count do out[n] = tostring(slot.effect[n].effect); end
    return table.concat(out, ' ');
end

-- The world: the target mob ahead, a party member, an alliance member, another player and your pet.
W.unit(0x100, 0x1000100, 'mob', 0, -5, { name = 'Target' });
W.unit(0x401, 1002, 'player', 3, -3, { name = 'Member', race = 3 });
W.unit(0x402, 1003, 'player', -3, -3, { name = 'Ally', race = 7 });
W.unit(0x403, 1004, 'player', 4, -6, { name = 'Stranger' });
W.unit(0x105, 0x1000105, 'pet', -4, -2, { name = 'Pet' });
W.entities[W.self].pet = 0x105;
W.target = 0x100;
snapshot = W.snapshot({ { id = 1002, index = 0x401, scope = 'party' }, { id = 1003, index = 0x402, scope = 'alliance' } });
local pc = MOCK.bytes(0x48);
MOCK.put(pc, 4, 4, 1004); MOCK.put(pc, 8, 2, 0x403); pc[0x0A] = 0x01;
overhead.packet(MOCK.packet(0x00D, pc));

-- Single bar, the default: 8 for mobs and the party, 6 for everyone else. Each unit has 12 to show.
local function twelve(entity, kind, fields)
    local out = {};
    for i = 1, 12 do out[i] = effect(entity, 100 + i, kind, fields); end
    return out;
end
give(0x1000100, twelve(0x1000100, 'debuff', { source = 1001, mine = true }));
give(1002, twelve(1002, 'debuff'));
give(1003, twelve(1003, 'debuff'));
give(1004, twelve(1004, 'debuff', { scope = 'other' }));
give(0x1000105, twelve(0x1000105, 'debuff', { scope = 'pet' }));
local drawn = frame();
local limits = { [0x1000100] = 8, [1002] = 8, [1003] = 6, [1004] = 6, [0x1000105] = 6 };
local total = 0;
for id, limit in pairs(limits) do
    local slot, unit = slot_of(id);
    assert(slot and unit, 'Unit ' .. id .. ' has a block');
    assert(slot.count == limit, unit.kind .. ' shows ' .. limit .. ', not ' .. slot.count);
    -- The oldest come first and the row just ends: the rest are left out.
    assert(ids(slot) == table.concat({ 101, 102, 103, 104, 105, 106, 107, 108 }, ' ', 1, limit), ids(slot));
    total = total + limit;
end
assert(drawn == total and #named('AddImage') == total, 'One image for each icon shown and nothing for the rest: '
    .. drawn .. ' ' .. #named('AddImage'));
-- Truncated silently: no text but countdowns, no box, no line, nothing after the last icon.
for _, call in ipairs(calls) do
    assert(call[1] == 'AddImage' or call[1] == 'AddText', 'Only icons and countdowns are drawn: ' .. call[1]);
    if call[1] == 'AddText' then
        assert(call[6]:match('^%d+[smh]$'), 'Countdown text only: ' .. call[6]);
    end
end
for id in pairs(limits) do
    local slot = slot_of(id);
    local right = -math.huge;
    for n = 1, slot.count do right = math.max(right, slot.x[n] + slot.size[n]); end
    assert(slot.right == right, 'The block ends at its last icon');
end
-- Centered on the anchor, in one row, the gap about 8% of the icon.
local slot, unit = slot_of(0x1000100);
local size = unit.size;
local gap = math.max(1, math.floor(size * 0.08 + 0.5));
for n = 1, slot.count do
    assert(slot.size[n] == size and slot.y[n] == slot.y[1], 'One row of one size');
    if n > 1 then assert(slot.x[n] == slot.x[n - 1] + size + gap, 'Spaced by the gap'); end
end
assert(math.abs(slot.left + slot.right) <= 1, 'Centered: ' .. slot.left .. ' ' .. slot.right);
assert(slot.bottom == 0 and slot.top < 0, 'The block stands on its anchor above the name.');
-- A user limit.
settings.overhead.types.mob.limit = 3;
frame();
assert(slot_of(0x1000100).count == 3, 'Three when the limit is three.');
settings.overhead.types.mob.limit = 8;

-- The order: on a mob crowd control, lit buffs, your debuffs, other debuffs, other buffs, each oldest first; the
-- single bar puts the debuffs it took left of the buffs.
reset();
give(0x1000100, {
    effect(0x1000100, 40, 'buff'),                                   -- Protect, dispelable: lit for a RDM
    effect(0x1000100, 44, 'buff'),                                   -- Mighty Strikes, not dispelable
    effect(0x1000100, 4, 'debuff', { source = 1002 }),              -- a party member's Paralysis
    effect(0x1000100, 13, 'debuff', { source = 1001, mine = true }), -- your Slow
    effect(0x1000100, 2, 'debuff', { source = 1002, priority = 80 }), -- Sleep
});
frame();
assert(ids(slot_of(0x1000100)) == '2 13 4 40 44', 'WAR: Sleep, your Slow, their Paralysis, then the buffs: ' .. ids(slot_of(0x1000100)));
rdm(true);
settings.overhead.types.mob.limit = 3;
frame();
assert(ids(slot_of(0x1000100)) == '2 13 40', 'RDM, three: Sleep, your Slow, and the lit Protect before the debuffs of others: '
    .. ids(slot_of(0x1000100)));
settings.overhead.types.mob.limit = 8;
-- Players: crowd control, other debuffs, your buffs, other buffs.
give(1002, {
    effect(1002, 40, 'buff'), effect(1002, 33, 'buff', { mine = true }), effect(1002, 4, 'debuff'),
    effect(1002, 6, 'debuff', { priority = 80 }),
});
settings.overhead.types.party.buffs_mine_only, settings.overhead.types.party.exclude = false, {};
settings.overhead.types.party.limit = 3;
frame();
assert(ids(slot_of(1002)) == '6 4 33', 'Silence, Paralysis, your Haste: ' .. ids(slot_of(1002)));
settings.overhead.types.party.limit = 8;

-- Dispellable mob buffs light up, for a RDM: a glow behind the icon and a border in the light's color around it.
frame();
local lit_ink = require('ui.theme').u32(settings.overhead.dispel_color, 1);
local function lit_count()
    local borders = 0;
    for _, call in ipairs(named('AddRect')) do if call[4] == lit_ink then borders = borders + 1; end end
    return borders;
end
slot = slot_of(0x1000100);
local lit = {};
for n = 1, slot.count do if slot.lit[n] then lit[#lit + 1] = slot.effect[n].effect; end end
assert(table.concat(lit, ' ') == '40', 'Only the mob\'s Protect is lit: ' .. table.concat(lit, ' '));
assert(lit_count() == 1 and #named('AddRectFilled') == 1, 'One border and one glow');
-- In every layout.
for _, mode in ipairs({ 'lines', 'split' }) do
    settings.overhead.types.mob.layout = mode;
    frame();
    assert(lit_count() == 1, 'Lit in ' .. mode);
end
settings.overhead.types.mob.layout = 'single';
-- The member's Haste is a buff Dispel can take, but not off a party member: only mob buffs light.
assert(not slot_of(1002).lit[3], 'A member\'s buff never lights.');
-- A debuff never lights, even one on the dispelable list.
give(0x1000100, { effect(0x1000100, 33, 'debuff', { source = 1001 }), effect(0x1000100, 13, 'debuff', { source = 1001 }) });
frame();
assert(lit_count() == 0 and not slot_of(0x1000100).lit[1] and not slot_of(0x1000100).lit[2], 'Debuffs never light.');
-- Without the light switch, or without a tool, nothing lights.
give(0x1000100, { effect(0x1000100, 40, 'buff') });
settings.overhead.dispel_light = false;
frame();
assert(lit_count() == 0, 'The light can be turned off.');
settings.overhead.dispel_light = true;
settings.overhead.dispel_glow = false;
frame();
assert(lit_count() == 1 and #named('AddRectFilled') == 0, 'The glow can be turned off and the border stays.');
settings.overhead.dispel_glow = true;
-- A mob's Copy Image is one effect at every count: it lights as Copy Image and draws the icon of the shadows left.
give(0x1000100, { effect(0x1000100, 66, 'buff', { icon = 445 }) });
frame();
local pictures = {};
for _, call in ipairs(named('AddImage')) do pictures[call[2]] = true; end
assert(slot_of(0x1000100).lit[1] and lit_count() == 1, 'Copy Image at three shadows lights for Dispel.');
assert(pictures[5445] and not pictures[5066], 'It draws the icon of three shadows.');
give(0x1000100, { effect(0x1000100, 40, 'buff') });
rdm(false);
frame();
assert(lit_count() == 0 and not slot_of(0x1000100).lit[1], 'A WAR lights nothing.');

-- Two lines: debuffs nearest the name, buffs above, each with its limit (mobs 8 and 4).
reset();
local mixed = {};
for i = 1, 10 do mixed[#mixed + 1] = effect(0x1000100, 100 + i, 'debuff', { source = 1001 }); end
for i = 1, 6 do mixed[#mixed + 1] = effect(0x1000100, 200 + i, 'buff'); end
give(0x1000100, mixed);
settings.overhead.types.mob.layout = 'lines';
frame();
slot = slot_of(0x1000100);
local debuff_y, buff_y, debuffs, buffs;
debuffs, buffs = 0, 0;
for n = 1, slot.count do
    if slot.effect[n].kind == 'debuff' then debuffs, debuff_y = debuffs + 1, slot.y[n]; else buffs, buff_y = buffs + 1, slot.y[n]; end
end
assert(debuffs == 8 and buffs == 4, 'Mobs: 8 debuffs and 4 buffs: ' .. debuffs .. ' ' .. buffs);
assert(buff_y < debuff_y, 'The buff line is above the debuff line.');
local bottom_line = debuff_y;
settings.overhead.types.mob.swap_lines = true;
frame();
slot = slot_of(0x1000100);
for n = 1, slot.count do
    if slot.effect[n].kind == 'debuff' then debuff_y = slot.y[n]; else buff_y = slot.y[n]; end
end
assert(buff_y > debuff_y, 'Swapped, the buffs sit nearest the name.');
settings.overhead.types.mob.swap_lines = false;
-- An empty line takes no room.
give(0x1000100, { effect(0x1000100, 201, 'buff'), effect(0x1000100, 202, 'buff') });
frame();
slot, unit = slot_of(0x1000100);
assert(slot.count == 2 and slot.y[1] == bottom_line and slot.y[2] == bottom_line and slot.top == bottom_line,
    'Buffs alone sit on the bottom line.');
-- The party: debuffs 6, buffs 8.
local member = {};
for i = 1, 9 do member[#member + 1] = effect(1002, 100 + i, 'debuff'); end
for i = 1, 9 do member[#member + 1] = effect(1002, 200 + i, 'buff', { mine = true }); end
give(1002, member);
settings.overhead.types.party.layout = 'lines';
frame();
slot = slot_of(1002);
debuffs, buffs = 0, 0;
for n = 1, slot.count do if slot.effect[n].kind == 'debuff' then debuffs = debuffs + 1; else buffs = buffs + 1; end end
assert(debuffs == 6 and buffs == 8, 'Party: 6 debuffs and 8 buffs: ' .. debuffs .. ' ' .. buffs);
settings.overhead.types.party.layout = 'single';

-- Split: buffs left of the anchor and debuffs right (mobs 4 and 6), growing out from the gap; lit buffs nearest it.
reset();
rdm(true);
local split = {};
-- 44 to 48 (Mighty Strikes and the other 2-hours) are not dispelable.
for i = 1, 5 do split[#split + 1] = effect(0x1000100, 43 + i, 'buff'); end
split[#split + 1] = effect(0x1000100, 33, 'buff');   -- Haste, newest, lit
for i = 1, 7 do split[#split + 1] = effect(0x1000100, 100 + i, 'debuff', { source = 1001 }); end
give(0x1000100, split);
settings.overhead.types.mob.layout = 'split';
settings.overhead.types.mob.cc_slot = true;
frame();
slot, unit = slot_of(0x1000100);
size = unit.size;
debuffs, buffs = 0, 0;
local nearest_buff, nearest_x = nil, -math.huge;
for n = 1, slot.count do
    if slot.effect[n].kind == 'debuff' then
        debuffs = debuffs + 1;
        assert(slot.x[n] >= 0, 'Debuffs on the right');
    else
        buffs = buffs + 1;
        assert(slot.x[n] + slot.size[n] <= 0, 'Buffs on the left');
        if slot.x[n] > nearest_x then nearest_x, nearest_buff = slot.x[n], slot.effect[n].effect; end
    end
end
assert(buffs == 4 and debuffs == 6, 'Mobs: 4 buffs and 6 debuffs: ' .. buffs .. ' ' .. debuffs);
assert(nearest_buff == 33, 'The lit buff sits nearest the center: ' .. tostring(nearest_buff));
local middle = settings.overhead.layout.split_gap;
local first_debuff = math.huge;
for n = 1, slot.count do if slot.effect[n].kind == 'debuff' then first_debuff = math.min(first_debuff, slot.x[n]); end end
assert(first_debuff - (nearest_x + size) == middle, 'The center gap is split_gap wide: ' .. (first_debuff - nearest_x - size));
settings.overhead.types.mob.swap_sides = true;
frame();
slot = slot_of(0x1000100);
for n = 1, slot.count do
    if slot.effect[n].kind == 'debuff' then assert(slot.x[n] + slot.size[n] <= 0, 'Swapped, debuffs go left');
    else assert(slot.x[n] >= 0, 'and buffs right'); end
end
settings.overhead.types.mob.swap_sides = false;
rdm(false);

-- The crowd control slot: in Split on a mob, the highest priority debuff of 80 or more, at 1.4 times the size, next
-- to the gap and on the bottom line. It counts against the debuff limit, and its countdown shows with countdowns off.
reset();
local control = {};
for i = 1, 7 do control[#control + 1] = effect(0x1000100, 100 + i, 'debuff', { source = 1001 }); end
control[#control + 1] = effect(0x1000100, 2, 'debuff', { source = 1001, priority = 80 });   -- Sleep
control[#control + 1] = effect(0x1000100, 15, 'debuff', { source = 1001, priority = 100, remaining = 50 }); -- Doom
give(0x1000100, control);
settings.overhead.types.mob.countdown = false;
frame();
slot, unit = slot_of(0x1000100);
size = unit.size;
local big = math.floor(size * settings.overhead.layout.cc_scale + 0.5);
local cc;
debuffs = 0;
for n = 1, slot.count do
    if slot.effect[n].kind == 'debuff' then debuffs = debuffs + 1; end
    if slot.size[n] == big then assert(not cc, 'One crowd control slot'); cc = n; end
end
assert(cc and slot.effect[cc].effect == 15, 'Doom, priority 100, takes the slot over Sleep');
assert(debuffs == 6, 'It counts against the limit of 6: ' .. debuffs);
local leftmost = math.huge;
for n = 1, slot.count do if slot.effect[n].kind == 'debuff' then leftmost = math.min(leftmost, slot.x[n]); end end
assert(slot.x[cc] == leftmost, 'Next to the center gap');
for n = 1, slot.count do
    if n ~= cc then
        assert(slot.y[n] + slot.size[n] == slot.y[cc] + big, 'Bottoms on one line');
        assert(slot.text[n] == '', 'Countdowns off for the rest');
    end
end
assert(slot.text[cc] == '50s', 'The slot shows its countdown: ' .. tostring(slot.text[cc]));
settings.overhead.types.mob.countdown = true;
settings.overhead.types.mob.cc_slot = false;
frame();
slot = slot_of(0x1000100);
for n = 1, slot.count do assert(slot.size[n] == unit.size, 'Without the slot every icon is one size'); end
settings.overhead.types.mob.cc_slot = true;
-- Not in the other layouts.
settings.overhead.types.mob.layout = 'single';
frame();
slot = slot_of(0x1000100);
for n = 1, slot.count do assert(slot.size[n] == unit.size, 'The slot is for Split only'); end

-- No time known: the icon in its normal look, with no countdown, no mark and no '?'.
reset();
give(0x1000100, { effect(0x1000100, 101, 'debuff', { source = 1001, remaining = 200 }),
    effect(0x1000100, 102, 'debuff', { source = 1001, remaining = false, status = 'unknown' }),
    effect(0x1000100, 103, 'debuff', { source = 1001, remaining = false, status = 'estimated' }) });
frame();
local images = named('AddImage');
assert(#images == 3 and images[1][7] == images[2][7] and images[2][7] == images[3][7], 'The same tint with or without a time');
local texts = named('AddText');
assert(#texts >= 1, 'The timed one has a countdown');
for _, call in ipairs(texts) do assert(call[6] == '200s' or call[6] == '3m', 'Only its countdown: ' .. call[6]); end
assert(#named('AddRect') == 0 and #named('AddRectFilled') == 0, 'No mark on the untimed ones');
for _, call in ipairs(calls) do
    for _, value in ipairs(call) do
        if type(value) == 'string' then assert(not value:find('?', 1, true) and not value:lower():find('unknown'), value); end
    end
end
-- A picture that fails leaves nothing in its place: no tile, no edge and no text.
give(0x1000100, { effect(0x1000100, 999, 'debuff', { source = 1001, remaining = false }) });
frame();
assert(#named('AddImage') == 0 and #named('AddRectFilled') == 0 and #named('AddRect') == 0 and #named('AddText') == 0,
    'Nothing in its place');

-- Countdowns on small icons: 18 px and up below the icon, half its size from 9 to 16 px; 14 to 17 px inside, shrunk as
-- far as 8 px; under 14 none.
give(0x1000100, { effect(0x1000100, 101, 'debuff', { source = 1001, remaining = 45 }) });
local function at_size(px)
    settings.overhead.size.min_px, settings.overhead.size.max_px = px, px;
    frame();
    return slot_of(0x1000100);
end
slot = at_size(24);
assert(slot.size[1] == 24 and slot.text[1] == '45s' and slot.text_size[1] == 12 and slot.text_y[1] == slot.y[1] + 24,
    'Below a 24 px icon at 12 px');
slot = at_size(40);
assert(slot.text_size[1] == 16, 'Never over 16 px');
slot = at_size(18);
assert(slot.text_size[1] == 9 and slot.text_y[1] == slot.y[1] + 18, 'Below an 18 px icon at 9 px');
slot = at_size(16);
assert(slot.text[1] == '45s' and slot.text_size[1] >= 8 and slot.text_size[1] <= 9 and slot.text_y[1] < slot.y[1] + 16,
    'Inside a 16 px icon');
local width, height = require('ui.countdown_text').measure(settings.style.font, '45s', slot.text_size[1], settings.overhead, true);
assert(width <= 16 and slot.text_y[1] + height == slot.y[1] + 16, 'At its bottom, fitting');
slot = at_size(12);
assert(slot.text[1] == '', 'No text under 14 px');
settings.overhead.size.min_px, settings.overhead.size.max_px = 14, 40;
settings.overhead.types.mob.countdown = false;
frame();
assert(slot_of(0x1000100).text[1] == '' and #named('AddText') == 0, 'The type\'s countdown switch');
settings.overhead.types.mob.countdown = true;
-- A duration override that counts up (core/durations.lua) shows the time since the effect landed, with no time left.
give(0x1000100, { effect(0x1000100, 101, 'debuff', { source = 1001, remaining = false, count_up = true, elapsed = 75, status = 'unknown' }) });
slot = at_size(24);
assert(slot.text[1] == '1m', 'A count up shows its time since it landed: ' .. tostring(slot.text[1]));
give(0x1000100, { effect(0x1000100, 101, 'debuff', { source = 1001, remaining = false, elapsed = 75, status = 'unknown' }) });
slot = at_size(24);
assert(slot.text[1] == '', 'With no count up and no time left there is no countdown.');
settings.overhead.size.min_px, settings.overhead.size.max_px = 14, 40;

-- Filters for each type: kinds, mine only, buffs you cast, debuffs from the party, include, exclude.
reset();
give(0x1000100, { effect(0x1000100, 101, 'debuff', { source = 1001, mine = true }), effect(0x1000100, 102, 'debuff', { source = 1002 }),
    effect(0x1000100, 103, 'debuff', { source = 5555 }), effect(0x1000100, 104, 'debuff'), effect(0x1000100, 201, 'buff') });
local mob = settings.overhead.types.mob;
frame();
assert(ids(slot_of(0x1000100)) == '101 102 104 201', 'Mobs: debuffs from you and the party (or unseen casters) and their buffs: '
    .. ids(slot_of(0x1000100)));
mob.debuffs_party_only = false;
frame();
assert(ids(slot_of(0x1000100)) == '101 102 103 104 201', 'Everyone\'s debuffs');
mob.kinds = 'buff';
frame();
assert(ids(slot_of(0x1000100)) == '201', 'Buffs only');
mob.kinds = 'debuff';
frame();
assert(ids(slot_of(0x1000100)) == '101 102 103 104', 'Debuffs only');
mob.kinds, mob.mine_only = 'all', true;
frame();
assert(ids(slot_of(0x1000100)) == '101', 'Mine only');
mob.mine_only = false;
mob.include = { 102, 201 };
frame();
assert(ids(slot_of(0x1000100)) == '102 201', 'Include');
mob.include, mob.exclude = {}, { 101, 104 };
frame();
assert(ids(slot_of(0x1000100)) == '102 103 201', 'Exclude');
mob.exclude, mob.debuffs_party_only = {}, true;
-- The party at first: every debuff, the buffs you cast, and not Signet or Protect.
give(1002, { effect(1002, 4, 'debuff'), effect(1002, 33, 'buff', { mine = true }), effect(1002, 43, 'buff'),
    effect(1002, 253, 'buff', { mine = true }), effect(1002, 40, 'buff', { mine = true }) });
settings.overhead.types.party = require('ui.overhead_defaults').make().types.party;
frame();
assert(ids(slot_of(1002)) == '4 33', 'Party: debuffs and your buffs, without Signet or Protect: ' .. ids(slot_of(1002)));
-- The alliance shows debuffs only.
give(1003, { effect(1003, 4, 'debuff'), effect(1003, 33, 'buff', { mine = true }) });
frame();
assert(ids(slot_of(1003)) == '4', 'Alliance: debuffs only');

-- The shared hide rules: enemy, other and pet each hide on their own units only, and party, alliance and all on theirs.
reset();
local tracked = { [1004] = 'other', [0x1000105] = 'pet' };
for _, id in ipairs({ 0x1000100, 1002, 1003, 1004, 0x1000105 }) do
    local scope = tracked[id];
    give(id, { effect(id, 4, 'debuff', { source = 1001, scope = scope }), effect(id, 5, 'debuff', { source = 1001, scope = scope }) });
end
local recipients = effect_filters.recipients(snapshot);
local function hiding(scope)
    local rule = effect_filters.rule();
    rule.effect, rule.scope = 4, scope;
    settings.effect_filters = { enabled = true, rules = { rule } };
    frame(recipients);
    local out = {};
    for _, id in ipairs({ 0x1000100, 1002, 1003, 1004, 0x1000105 }) do
        local held, owner = slot_of(id);
        if held and held.count == 1 then out[#out + 1] = owner.kind; end
    end
    table.sort(out);
    return table.concat(out, ' ');
end
assert(hiding('enemy') == 'mob', 'enemy: ' .. hiding('enemy'));
assert(hiding('other') == 'other', 'other: ' .. hiding('other'));
assert(hiding('pet') == 'pet', 'pet: ' .. hiding('pet'));
assert(hiding('party') == 'party', 'party: ' .. hiding('party'));
assert(hiding('alliance') == 'alliance', 'alliance: ' .. hiding('alliance'));
assert(hiding('all') == 'alliance mob other party pet', 'all: ' .. hiding('all'));
-- A type can leave the shared rules out.
settings.overhead.types.mob.shared_rules = false;
assert(hiding('enemy') == '', 'With shared rules off for mobs the rule hides nothing there.');
settings.overhead.types.mob.shared_rules = true;
settings.effect_filters = { enabled = true, rules = {} };

-- Overlapping blocks keep their own spots: each block's icons are drawn at its own anchor, far to near, so the
-- nearest, the target, is on top.
reset();
W.unit(0x110, 0x1000110, 'mob', 0, -5.2, { name = 'Behind' });
W.unit(0x111, 0x1000111, 'mob', 0, -5.4, { name = 'Further' });
for _, id in ipairs({ 0x1000100, 0x1000110, 0x1000111 }) do
    give(id, { effect(id, 4, 'debuff', { source = 1001 }), effect(id, 5, 'debuff', { source = 1001 }) });
end
settings.overhead.size.min_px, settings.overhead.size.max_px = 20, 20;
frame();
-- Where a block is on screen, from its own anchor.
local function box(id)
    local held, owner = slot_of(id);
    return { owner.anchor_x + held.left, owner.anchor_y + held.top, owner.anchor_x + held.right, owner.anchor_y + held.bottom };
end
local function apart(a, b)
    return a[3] <= b[1] or b[3] <= a[1] or a[4] <= b[2] or b[4] <= a[2];
end
local target_box, behind_box, further_box = box(0x1000100), box(0x1000110), box(0x1000111);
assert(not apart(target_box, behind_box) and not apart(target_box, further_box) and not apart(behind_box, further_box),
    'The three blocks overlap.');
local _, target_unit = slot_of(0x1000100);
local _, behind_unit = slot_of(0x1000110);
local _, further_unit = slot_of(0x1000111);
assert(target_unit.depth < behind_unit.depth and behind_unit.depth < further_unit.depth, 'The target is nearest, Further furthest.');
-- Each block's icons are drawn at its own anchor, block by block in the order given.
local function drawn_in(order, what)
    local images, at = named('AddImage'), 0;
    for _, id in ipairs(order) do
        local held, owner = slot_of(id);
        assert(held.count == 2, 'Each block has its two icons.');
        for n = 1, held.count do
            at = at + 1;
            local image = images[at];
            assert(image and image[3][1] == owner.anchor_x + held.x[n] and image[3][2] == owner.anchor_y + held.y[n],
                ('%s icon %d is drawn in its own block at its own spot, %s'):format(owner.name, n, what));
        end
    end
    assert(at == #images, 'Nothing else is drawn.');
end
drawn_in({ 0x1000111, 0x1000110, 0x1000100 }, 'furthest block first');
-- A block nearer than the target and over it is drawn before the target's, so the target's stays on top; neither
-- moves.
W.unit(0x112, 0x1000112, 'mob', 0, -4.8, { name = 'Nearer' });
give(0x1000112, { effect(0x1000112, 4, 'debuff', { source = 1001 }), effect(0x1000112, 5, 'debuff', { source = 1001 }) });
frame();
local _, nearer_unit = slot_of(0x1000112);
assert(nearer_unit.depth < select(2, slot_of(0x1000100)).depth and not apart(box(0x1000112), box(0x1000100)),
    'Nearer is in front of the target and over its block.');
drawn_in({ 0x1000111, 0x1000110, 0x1000112, 0x1000100 }, 'furthest block first and the target last');
settings.overhead.size.min_px, settings.overhead.size.max_px = 14, 40;

-- Drawing opens no window and no item and reads no mouse: the only ImGui call is for the background draw list.
reset();
give(0x1000100, { effect(0x1000100, 4, 'debuff', { source = 1001, remaining = 30 }), effect(0x1000100, 40, 'buff') });
rdm(true);
W.frame(W.view(rows), settings, snapshot);
MOCK.imgui_calls = {};
calls = {};
local background = 0;
rawset(imgui, 'GetBackgroundDrawList', function() background = background + 1; return list; end);
assert(draw.draw(plan, subjects, settings, W.now) == 2, 'Two icons drawn');
assert(background == 1, 'One background draw list');
local allowed = { col32 = true, GetFont = true, PushFont = true, PopFont = true, CalcTextSize = true, GetFontSize = true };
for _, call in ipairs(MOCK.imgui_calls) do
    assert(allowed[call[1]], 'Overhead drawing called ImGui ' .. tostring(call[1]));
end
assert(#named('AddImage') == 2 and #named('AddRect') == 1, 'Drawn on the list it got');
rdm(false);
