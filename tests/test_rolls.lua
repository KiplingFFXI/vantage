-- The Phantom Roll display (core/rolls.lua, ui/roll_display.lua). A roll from you or a party member (a 0x028 category 6
-- with the roll's id) becomes a 'roll' observation with its total, whether it was a Double-Up or a bust, and each
-- target's result. The display shows the roll, its total, what it gives you at that total from the era table, with the
-- job bonus only for a job seen in the party and less for a Corsair level below yours, its lucky and unlucky numbers,
-- the chance one more Double-Up busts, the Double-Up window (45 s from the roll, not moved by a Double-Up) or the bust's
-- time, and who in the party got it. It moves only unlocked with Shift held and truncates silently.
local observer, rolls, defaults = require('core.observer'), require('core.rolls'), require('ui.defaults');
local display = require('ui.roll_display');
local self_id, ally, friend, stranger, mob = 1001, 1002, 1003, 1500, 0x1000001;
local snapshot = { valid = true, id = self_id, zone = 102, name = 'Tester', level = 75, job = 17, self_known = true, self_effects = {},
    party = { { id = ally, name = 'Ally', scope = 'party', zone = 102, slot = 1 }, { id = friend, name = 'Friend', scope = 'alliance', zone = 102, slot = 6 } },
    entities = { [self_id] = { name = 'Tester', kind = 'player' }, [ally] = { name = 'Ally', kind = 'player' },
        [friend] = { name = 'Friend', kind = 'player' }, [stranger] = { name = 'Stranger', kind = 'player' }, [mob] = { name = 'Crab', kind = 'monster' } } };
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
local function roll_of(events)
    local found;
    for _, event in ipairs(events) do if event.kind == 'roll' then assert(not found, 'One roll observation an action.'); found = event; end end
    return found;
end

-- What the observer sees.
local seen = roll_of(observer.read(action(self_id, 6, 105, { { self_id, 420, 4 }, { ally, 421, 4 } }), 1, snapshot));
assert(seen and seen.entity_id == self_id and seen.ability == 105 and seen.total == 4 and not seen.double_up and not seen.bust
    and seen.scope == 'self', 'Your Chaos Roll of 4 is a roll.');
assert(#seen.targets == 2 and seen.targets[1] == self_id and seen.results[1] == 'got' and seen.targets[2] == ally and seen.results[2] == 'got',
    'Each target and what it got.');
seen = roll_of(observer.read(action(self_id, 6, 105, { { self_id, 424, 9 }, { ally, 421, 9 } }), 1, snapshot));
assert(seen.double_up and not seen.bust and seen.total == 9, 'A Double-Up to 9, the action named for the roll.');
seen = roll_of(observer.read(action(self_id, 6, 105, { { self_id, 426, 12 }, { ally, 427, 12 } }), 1, snapshot));
assert(seen.bust and seen.total == 12 and seen.results[1] == 'bust' and seen.results[2] == 'bust', 'A bust takes the roll from everyone.');
seen = roll_of(observer.read(action(ally, 6, 108, { { ally, 420, 3 }, { self_id, 283, 0 } }), 1, snapshot));
assert(seen and seen.entity_id == ally and seen.scope == 'party' and seen.total == 3 and seen.results[2] == 'none',
    'A party member\'s roll; you already had it from another Corsair, so no effect.');
assert(roll_of(observer.read(action(friend, 6, 105, { { friend, 420, 4 } }), 1, snapshot)) == nil, 'An alliance member\'s roll is not your party\'s.');
assert(roll_of(observer.read(action(stranger, 6, 105, { { stranger, 420, 4 } }), 1, snapshot)) == nil, 'Nor is a stranger\'s.');
assert(roll_of(observer.read(action(self_id, 6, 116, { { self_id, 420, 4 } }), 1, snapshot)) == nil, 'Dancer\'s Roll is WotG, out of era.');
assert(roll_of(observer.read(action(self_id, 6, 105, { { mob, 1, 40 } }), 1, snapshot)) == nil, 'An action of that id with no roll message is none.');

-- The roll table.
local DATA = require('data.rolls');
for id, info in pairs(DATA) do
    assert(#info.powers == 11 and require('core.catalog').roll(id), 'Each roll has eleven powers and a status: ' .. info.name);
    if id ~= 112 then
        local high, low = 0, math.huge;
        for total = 1, 10 do high, low = math.max(high, info.powers[total]), math.min(low, info.powers[total]); end
        assert(info.powers[info.lucky] == high and info.powers[info.unlucky] == low, 'Lucky and unlucky are where the table spikes and dips: ' .. info.name);
    end
end
assert(DATA[112].lucky == 5 and DATA[112].unlucky == 9, 'Evoker\'s Roll ties, so it takes the script header\'s 5 and 9.');
assert(DATA[111].powers[3] == 18 and DATA[111].lucky == 3 and DATA[115].powers[4] == 40 and DATA[115].lucky == 4,
    'Drachen and Puppet Roll take their era tables, swapped from the base ones.');
assert(DATA[110].powers[4] == 25 and DATA[110].bonus == 10, 'Ninja Roll takes the table from before SoA.');
local count = 0;
for _ in pairs(DATA) do count = count + 1; end
assert(count == 18, 'Eighteen rolls in era: ' .. count);

-- What a roll gives and its chance to bust.
local chaos = DATA[105];
assert(rolls.power(chaos, 4) == 25 and rolls.power(chaos, 4, true) == 35, 'Chaos Roll 4 gives 25, 35 with a Dark Knight.');
assert(rolls.power(chaos, 11, false, 37, 75) == 16 and rolls.power(chaos, 11, true, 37, 75) == 21, 'A /COR 37 on a 75 gives less, rounded up.');
assert(rolls.power(chaos, 12, true) == 10 and rolls.power(chaos, 12, false, 37, 75) == 5, 'A bust has no bonus and the Corsair\'s own correction.');
assert(rolls.power(chaos, 11, false, 75, 75) == 31, 'No correction at the same level.');
local odds = {};
for total = 1, 11 do odds[total] = rolls.odds(total); end
assert(table.concat(odds, ' ') == '0 0 0 0 0 17 33 50 67 83 100', 'The bust chance from the total: ' .. table.concat(odds, ' '));
assert(rolls.odds(9, true) == 0 and rolls.odds(11, true) == 100, 'With Snake Eye a Double-Up adds 1, so only 11 busts.');

-- The watch.
local function fresh() local s = defaults.tidy(defaults.make()); s.rolls.enabled = true; return s; end;
local s = fresh();
assert(not defaults.make().rolls.enabled and defaults.make().rolls.locked, 'The display starts off and locked.');
-- The client's party: you a 75 COR/NIN, and Ally a 75 DRK/WAR in slot 1.
local slots = { [0] = { id = self_id, job = 17, level = 75, subjob = 13, sublevel = 37 }, [1] = { id = ally, job = 8, level = 75, subjob = 1, sublevel = 37 } };
local player = { GetMainJob = function() return slots[0].job; end, GetMainJobLevel = function() return slots[0].level; end,
    GetSubJob = function() return slots[0].subjob; end, GetSubJobLevel = function() return slots[0].sublevel; end };
local party = { GetMemberServerId = function(_, slot) return slots[slot] and slots[slot].id or 0; end,
    GetMemberIsActive = function(_, slot) return slots[slot] and 1 or 0; end,
    GetMemberMainJob = function(_, slot) return slots[slot] and slots[slot].job; end, GetMemberMainJobLevel = function(_, slot) return slots[slot] and slots[slot].level; end,
    GetMemberSubJob = function(_, slot) return slots[slot] and slots[slot].subjob; end, GetMemberSubJobLevel = function(_, slot) return slots[slot] and slots[slot].sublevel; end };
local memory = { GetParty = function() return party; end, GetPlayer = function() return player; end };
AshitaCore.GetMemoryManager = function() return memory; end;
local watch = rolls.new();
local function roll(actor, ability, total, double_up, bust, targets, results, at)
    watch:observe({ kind = 'roll', entity_id = actor, ability = ability, total = total, double_up = double_up, bust = bust,
        targets = targets or { actor }, results = results or { bust and 'bust' or 'got' } }, at);
end
roll(self_id, 105, 4, false, false, { self_id, ally }, { 'got', 'got' }, 100);
local shown = watch:refresh(101, s, snapshot, {});
local entry = shown[1];
assert(#shown == 1 and entry.total == 4 and entry.window_deadline == 145 and entry.odds == 0, 'Your roll, its window 45 s from the roll.');
assert(entry.gives == 'Attack and ranged attack +35%' and entry.bonus, 'It gives 25 and 10 for the Dark Knight in the party.');
assert(#entry.members == 2 and entry.members[1].name == 'Tester' and entry.members[1].state == 'got' and entry.members[2].name == 'Ally'
    and entry.members[2].state == 'got', 'You and your party, in party order; the alliance is not your party.');
roll(self_id, 105, 9, true, false, { self_id, ally }, { 'got', 'none' }, 110);
shown = watch:refresh(111, s, snapshot, {});
entry = shown[1];
assert(entry.total == 9 and entry.window_deadline == 145 and entry.odds == 67, 'A Double-Up keeps the window the roll started.');
assert(entry.members[2].state == 'none', 'Ally had it from another Corsair.');
shown = watch:refresh(111, s, snapshot, { { entity_id = self_id, effect = 357, present = true } });
assert(shown[1].odds == 0, 'With Snake Eye on you, 9 can\'t bust.');
-- Your Double-Up Chance gives the window's time, and its leaving closes it.
shown = watch:refresh(112, s, snapshot, { { entity_id = self_id, effect = 308, deadline = 144, present = true } });
assert(shown[1].window_deadline == 144, 'Your own Double-Up Chance times the window.');
shown = watch:refresh(113, s, snapshot, {});
assert(#shown == 0, 'When it leaves, the window is over and the roll leaves the display.');
-- The Double-Up Chance of the roll before, still listed when a new roll lands, is not the new one's.
watch = rolls.new();
roll(self_id, 105, 4, false, false, nil, nil, 150);
roll(self_id, 108, 4, false, false, nil, nil, 170);
shown = watch:refresh(170.1, s, snapshot, { { entity_id = self_id, effect = 308, deadline = 195, present = true } });
assert(#shown == 1 and shown[1].ability == 108 and shown[1].window_deadline == 215, 'A stale Double-Up Chance leaves the new window alone.');
shown = watch:refresh(170.2, s, snapshot, { { entity_id = self_id, effect = 308, deadline = 214.5, present = true } });
assert(shown[1].window_deadline == 214.5, 'and the new one times it once it is listed.');
-- With two busts on you, the newest is this bust's.
watch = rolls.new();
roll(self_id, 105, 12, true, true, nil, nil, 180);
shown = watch:refresh(181, s, snapshot, { { entity_id = self_id, effect = 309, deadline = 300, present = true },
    { entity_id = self_id, effect = 309, deadline = 478, present = true } });
assert(shown[1].bust_deadline == 478, 'The newest bust is this one: ' .. tostring(shown[1].bust_deadline));
-- A bust: no window, the bust's time while it lasts.
watch = rolls.new();
roll(self_id, 105, 4, false, false, nil, nil, 200);
roll(self_id, 105, 12, true, true, { self_id, ally }, { 'bust', 'bust' }, 205);
shown = watch:refresh(206, s, snapshot, { { entity_id = self_id, effect = 309, deadline = 505, present = true } });
entry = shown[1];
assert(entry.bust and entry.window_deadline == nil and entry.bust_deadline == 505 and entry.odds == nil, 'A bust shows its time and no window.');
assert(entry.gives == 'Attack and ranged attack -10%' and entry.members[1].state == 'lost', 'A bust takes 10% from the Corsair.');
shown = watch:refresh(210, s, snapshot, {});
assert(#shown == 0, 'The bust leaves with its row.');
-- A /COR: what it gives you is lowered to your level, and so is its bust.
slots[0].job, slots[0].subjob = 1, 17;
watch = rolls.new();
roll(self_id, 105, 11, false, false, nil, nil, 300);
entry = watch:refresh(301, s, snapshot, {})[1];
assert(entry.gives == 'Attack and ranged attack +21%' and entry.corrected and entry.cor_level == 37, 'A /COR 37 rolls 11 for 21% with the bonus.');
roll(self_id, 105, 12, true, true, nil, nil, 302);
entry = watch:refresh(303, s, snapshot, { { entity_id = self_id, effect = 309, present = true } })[1];
assert(entry.gives == 'Attack and ranged attack -5%', 'Its bust takes 5% from the Corsair.');
slots[0].job, slots[0].subjob = 17, 13;
-- A party member's bust is lowered for the Corsair's own level, not yours.
slots[1] = { id = ally, job = 1, level = 60, subjob = 17, sublevel = 30 };
watch = rolls.new();
roll(ally, 105, 12, true, true, { ally, self_id }, { 'bust', 'bust' }, 304);
entry = watch:refresh(305, s, snapshot, {})[1];
assert(entry.gives == 'Attack and ranged attack -5%' and entry.corrected, 'A WAR 60/COR 30 bust takes 5%, at their 60: ' .. entry.gives);
slots[1] = { id = ally, job = 17, level = 70, subjob = 1, sublevel = 35 };
watch = rolls.new();
roll(ally, 108, 12, true, true, { ally, self_id }, { 'bust', 'bust' }, 306);
entry = watch:refresh(307, s, snapshot, {})[1];
assert(entry.gives == 'Accuracy and ranged accuracy -15' and not entry.corrected, 'A COR 70 bust is not lowered for your 75: ' .. entry.gives);
slots[1] = { id = ally, job = 8, level = 75, subjob = 1, sublevel = 37 };
-- A party member's roll; the bonus only for a job seen in the party, none when you are alone.
watch = rolls.new();
roll(ally, 108, 4, false, false, { ally, self_id }, { 'got', 'got' }, 400);
entry = watch:refresh(401, s, snapshot, {})[1];
assert(entry.roller_name == 'Ally' and entry.gives == 'Accuracy and ranged accuracy +40' and not entry.bonus, 'No Ranger in the party: no bonus.');
-- Corsair's Roll's bonus adds nothing, so it never counts as one, though a COR is always in the party.
watch = rolls.new();
roll(self_id, 114, 5, false, false, { self_id, ally }, { 'got', 'got' }, 402);
entry = watch:refresh(403, s, snapshot, {})[1];
assert(entry.gives == 'Experience +20%' and not entry.bonus and not rolls.details(entry, 403):find('added', 1, true),
    'Corsair\'s Roll has no bonus to add: ' .. rolls.details(entry, 403));
slots[1] = nil;
local solo = { valid = true, id = self_id, zone = 102, name = 'Tester', level = 75, job = 17, party = {}, entities = {} };
watch = rolls.new();
roll(self_id, 114, 4, false, false, nil, nil, 410);
entry = watch:refresh(411, s, solo, {})[1];
assert(entry.gives == 'Experience +12%' and not entry.bonus, 'Alone there is no party, so no bonus.');
slots[1] = { id = ally, job = 8, level = 75, subjob = 1, sublevel = 37 };
-- A new roll takes the window from the last one; one Vantage didn't see start stays no longer than a window.
watch = rolls.new();
roll(self_id, 105, 4, false, false, nil, nil, 500);
roll(self_id, 108, 5, false, false, nil, nil, 520);
shown = watch:refresh(521, s, snapshot, {});
assert(#shown == 1 and shown[1].ability == 108 and shown[1].window_deadline == 565, 'The new roll holds the window.');
watch = rolls.new();
roll(self_id, 105, 7, true, false, nil, nil, 600);
shown = watch:refresh(601, s, snapshot, {});
assert(#shown == 1 and shown[1].window_deadline == nil, 'A Double-Up of a roll not seen starting has no window time.');
assert(#watch:refresh(646, s, snapshot, {}) == 0, 'and leaves after a window.');
-- A member who leaves the party takes their roll; zoning drops nobody; off clears it.
watch = rolls.new();
roll(ally, 105, 4, false, false, nil, nil, 700);
assert(#watch:refresh(701, s, { valid = false }, {}) == 1, 'Zoning drops nobody.');
local alone = { valid = true, id = self_id, zone = 102, name = 'Tester', level = 75, job = 17, party = {}, entities = {} };
assert(#watch:refresh(702, s, alone, {}) == 0, 'A member who left takes their roll.');
roll(self_id, 105, 4, false, false, nil, nil, 703);
s.rolls.enabled = false;
assert(#watch:refresh(704, s, snapshot, {}) == 0 and next(watch.rollers) == nil, 'Off, nothing is kept.');
s.rolls.enabled = true;

-- The tooltip says what Vantage knows and gives no advice.
watch = rolls.new();
roll(self_id, 105, 4, false, false, { self_id, ally }, { 'got', 'none' }, 800);
entry = watch:refresh(801, s, snapshot, {})[1];
local text = rolls.details(entry, 801);
assert(text:find('Lucky 4, unlucky 8.', 1, true) and text:find('busts 0%', 1, true) and text:find('Got it: Tester.', 1, true)
    and text:find('No effect, another Corsair\'s roll is on them: Ally.', 1, true) and text:find('estimated from the roll', 1, true), text);
assert(text:find('Attack and ranged attack +35% for you, with 10 added for the DRK in the party.', 1, true), text);
-- A roll that didn't reach you, or found another Corsair's on you, gives you nothing, so it isn't "for you".
for _, result in ipairs({ 'missed', 'none' }) do
    local other = rolls.new();
    other:observe({ kind = 'roll', entity_id = ally, ability = 108, total = 3, targets = result == 'none' and { ally, self_id } or { ally },
        results = result == 'none' and { 'got', 'none' } or { 'got' } }, 800);
    local said = rolls.details(other:refresh(801, s, snapshot, {})[1], 801);
    assert(said:find('Accuracy and ranged accuracy +15 at this total.', 1, true) and not said:find('for you', 1, true), said);
end
for _, word in ipairs({ '?', 'unknown', 'safe', 'should', 'press', 'use ' }) do
    assert(not text:lower():find(word, 1, true), 'No ' .. word .. ' in the tooltip: ' .. text);
end
local bust_text;
roll(self_id, 105, 12, true, true, { self_id }, { 'bust' }, 802);
bust_text = rolls.details(watch:refresh(803, s, snapshot, {})[1], 803);
assert(bust_text:find('Bust. Attack and ranged attack -10% on the Corsair.', 1, true) and not bust_text:find('?', 1, true), bust_text);

-- Tidy: out-of-range values are clamped, what's missing gets its default, unknown keys stay.
local tidied = rolls.tidy({ enabled = true, preview = true, x = -5, width = 99999, max_rolls = 0,
    lucky_color = { 2, 0, 0, 1 }, extra = 'kept' });
assert(tidied.enabled and tidied.preview and tidied.x == 0 and tidied.width == 1400 and tidied.max_rolls == 1
    and tidied.lucky_color[1] == 1 and tidied.extra == 'kept' and tidied.locked == true, 'Tidy clamps and keeps.');
assert(not rolls.tidy({ enabled = false, preview = true }).preview, 'Samples need the display on.');

-- Drawing.
local view = { rolls = {} };
local moving = { shift = false, over_settings = false, mx = -1, my = -1, down = false, screen_width = 1600, screen_height = 900, hover = false };
local callbacks = { changed = function() end };
local function texts()
    local out = {};
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'draw:AddText' then out[#out + 1] = call[6]; end end
    return out;
end
local function drawn(now)
    MOCK.imgui_calls = {};
    local hovered = display.draw(view, s, now, callbacks, moving);
    return texts(), hovered;
end
watch = rolls.new();
roll(self_id, 105, 4, false, false, { self_id, ally }, { 'got', 'none' }, 900);
view.rolls = watch:refresh(901, s, snapshot, {});
local list = table.concat(drawn(901.5), '|');
for _, part in ipairs({ 'Phantom Roll', 'Chaos Roll', '|4|', 'Double-Up', '44s', 'Attack and ranged attack +35%', 'Lucky 4  Unlucky 8  Bust chance 0%', 'Tester', 'Ally' }) do
    assert(('|' .. list .. '|'):find(part, 1, true), 'The display draws ' .. part .. ': ' .. list);
end
s.rolls.show_members, s.rolls.show_numbers, s.rolls.show_odds, s.rolls.show_effect, s.rolls.show_heading = false, false, false, false, false;
list = table.concat(drawn(901.5), '|');
assert(not list:find('Ally', 1, true) and not list:find('Lucky', 1, true) and not list:find('Attack', 1, true) and not list:find('Phantom Roll', 1, true),
    'Each line has its switch: ' .. list);
s.rolls.show_members, s.rolls.show_numbers, s.rolls.show_odds, s.rolls.show_effect, s.rolls.show_heading = true, true, true, true, true;
-- Past the limit nothing is drawn, not even a count.
roll(ally, 108, 5, false, false, { ally }, { 'got' }, 902);
view.rolls = watch:refresh(903, s, snapshot, {});
s.rolls.max_rolls = 1;
-- No drawn text is a count of what was left out.
local function counted(values)
    for _, value in ipairs(values) do if tostring(value):match('^%+%d+$') or tostring(value):find('more', 1, true) then return true; end end
    return false;
end
local values = drawn(903);
list = table.concat(values, '|');
assert(list:find("Hunter's Roll", 1, true) and not list:find('Chaos Roll', 1, true) and not counted(values),
    'Only the newest roll fits the limit, with nothing after it: ' .. list);
s.rolls.max_rolls = 4;
-- Members past the width are left out with nothing after the last.
local crowd = { valid = true, id = self_id, zone = 102, name = 'Tester', level = 75, job = 17, party = {}, entities = {} };
for slot = 1, 5 do crowd.party[slot] = { id = ally + slot * 10, name = 'Longnamedmember' .. slot, scope = 'party', zone = 102, slot = slot }; end
local crowded = rolls.new();
crowded:observe({ kind = 'roll', entity_id = self_id, ability = 105, total = 4, targets = { self_id }, results = { 'got' } }, 904);
view.rolls = crowded:refresh(905, s, crowd, {});
s.rolls.width = 200;
values = drawn(905);
list = table.concat(values, '|');
assert(list:find('Tester', 1, true) and not list:find('Longnamedmember5', 1, true)
    and not list:find('...', 1, true) and not counted(values), 'A narrow display cuts its members silently: ' .. list);
s.rolls.width = 1400;
list = table.concat(drawn(905), '|');
assert(list:find('Longnamedmember5', 1, true), 'A wide one has room for them all: ' .. list);
s.rolls.width = 320;
view.rolls = watch:refresh(903, s, snapshot, {});
for _, value in ipairs(texts()) do
    assert(not tostring(value):find('?', 1, true) and not tostring(value):lower():find('unknown', 1, true), 'Nothing reads ? or unknown: ' .. tostring(value));
end
-- The roll under the mouse, for its tooltip, only with Hover details and never while it can move.
moving.hover, moving.mx, moving.my = true, 1290, 330;
local _, hovered = drawn(903);
assert(hovered and hovered.ability == 108, 'The roll under the mouse.');
moving.hover = false;
-- Off draws nothing; a roll ends, and an empty locked display draws nothing.
s.rolls.enabled = false;
assert(#drawn(903) == 0, 'Off, nothing.');
s.rolls.enabled = true;
view.rolls = {};
assert(#drawn(903) == 0, 'With no roll and locked, nothing.');
-- Samples show without a roll.
s.rolls.preview = true;
list = table.concat(drawn(903), '|');
assert(list:find('Chaos Roll', 1, true) and list:find('Bust', 1, true) and list:find('Sample', 1, true), 'Sample displays show sample rolls: ' .. list);
assert(rolls.details(rolls.samples(903)[1], 903):find('Attack and ranged attack +25% for you.', 1, true), 'The sample roll reached you.');
s.rolls.preview = false;
-- Locked, Shift moves nothing; unlocked with Shift held a drag moves it, as one Undo step.
local function buttons()
    local count = 0;
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'InvisibleButton' then count = count + 1; end end
    return count;
end
moving.shift = true;
drawn(903);
assert(buttons() == 0, 'A locked display takes no drag, Shift held or not.');
s.rolls.locked = false;
drawn(903);
assert(buttons() == 1, 'Unlocked with Shift held it can be dragged.');
moving.shift = false;
drawn(903);
assert(buttons() == 0, 'Without Shift it takes no input.');
return 'The Phantom Roll display';
