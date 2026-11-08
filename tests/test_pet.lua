-- The pet display (core/pet.lua, ui/pet_display.lua). While you have a pet it shows the pet the client shows: its
-- name, HP, MP once the client gives some, TP, the effects Vantage saw on it through its own filters and the shared
-- hide rules, as icons that wrap and blink near their end or as a list with names, your pet command recasts named by
-- Vantage (Sic, never Ready), soonest first, and for a pet you charmed an estimate of the charm's time left from
-- Phoenix's formula, lengthened by Familiar, shown as estimated, or with no countdown when the mob's level wasn't
-- checked. It moves only unlocked with Shift held and truncates silently.
local observer, pet, defaults = require('core.observer'), require('core.pet'), require('ui.defaults');
local client = require('core.client');
local display, theme = require('ui.pet_display'), require('ui.theme');
local self_id, crab, wolf, pet_index = 1001, 0x1000123, 0x1000124, 0x123;
local snapshot = { valid = true, id = self_id, zone = 102, name = 'Tester', level = 75, job = 9, self_known = true, self_effects = {}, party = {},
    entities = { [self_id] = { id = self_id, index = 0x400, name = 'Tester', kind = 'player' }, [crab] = { name = 'Crab', kind = 'monster' },
        [wolf] = { name = 'Wolf', kind = 'monster' } } };
-- The client: your pet at pet_index, its HP, MP and TP, your CHR and what you have on.
local game = { pet = 0, id = crab, name = 'Crab', hpp = 76, mpp = 0, tp = 1250, chr = 60, chr_bonus = 10, items = {} };
local entity = { GetPetTargetIndex = function(_, index) return index == 0x400 and game.pet or 0; end,
    GetServerId = function(_, index) return game.pet ~= 0 and index == game.pet and game.id or 0; end,
    GetName = function() return game.name; end, GetHPPercent = function() return game.hpp; end };
local player = { GetPetMPPercent = function() return game.mpp; end, GetPetTP = function() return game.tp; end,
    GetStat = function(_, index) return index == 6 and game.chr or 0; end, GetStatModifier = function(_, index) return index == 6 and game.chr_bonus or 0; end };
local inventory = { GetEquippedItem = function(_, slot) return { Index = game.items[slot] and 0x100 + slot or 0 }; end,
    GetContainerItem = function(_, _, index) return { Id = game.items[index] }; end };
local memory = { GetEntity = function() return entity; end, GetPlayer = function() return player; end, GetInventory = function() return inventory; end };
AshitaCore.GetMemoryManager = function() return memory; end;
-- A snapshot with your pet as core/client.lua reads it from the client, whatever the client shows at the time.
local function with_pet(view)
    return setmetatable(view, { __index = function(_, key)
        if key == 'pet' and game.pet ~= 0 then return { id = game.id, index = game.pet, name = game.name, kind = 'pet' }; end
    end });
end
with_pet(snapshot);
local function putbits(bytes, offset, length, value)
    for i = 0, length - 1 do
        local at = offset + i;
        if math.floor(value / 2 ^ i) % 2 == 1 then bytes[math.floor(at / 8)] = bytes[math.floor(at / 8)] + 2 ^ (at % 8); end
    end
end
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
-- A 0x029 battle message: actor, target, param and message.
local function message(actor, target, param, number)
    local bytes = MOCK.bytes(28);
    MOCK.put(bytes, 4, 4, actor); MOCK.put(bytes, 8, 4, target); MOCK.put(bytes, 12, 4, param); MOCK.put(bytes, 24, 2, number);
    return MOCK.packet(0x029, bytes);
end
local function kind_of(events, kind)
    for _, event in ipairs(events) do if event.kind == kind then return event; end end
end

-- The charm formula (scripts/globals/job_utils/beastmaster.lua getCharmDuration :30-61).
assert(pet.charm_seconds(70, 75, 70) == 711 and pet.charm_seconds(70, 75, 72) == 518 and pet.charm_seconds(70, 75, 75) == 236,
    'CHR 70 at 75 on a 70, a 72 and a 75.');
assert(pet.charm_seconds(70, 75, 66) == 1422 and pet.charm_seconds(70, 75, 60) == 1422, 'Nine levels or more over it caps at 6 times.');
assert(pet.charm_seconds(70, 62, 72) == 9 and pet.charm_seconds(70, 75, 82) == 9, 'Seven or more under it is 1/24.');
assert(pet.charm_seconds(70, 75, 70, 5) == 889, 'CHARM_TIME 5 adds a quarter.');

-- What the observer sees.
local seen = kind_of(observer.read(message(self_id, crab, 70, 174), 1, snapshot), 'check');
assert(seen and seen.entity_id == crab and seen.level == 70, 'Your /check of a mob gives its level.');
assert(kind_of(observer.read(message(self_id, crab, 70, 170), 1, snapshot), 'check') and kind_of(observer.read(message(self_id, crab, 70, 178), 1, snapshot), 'check'),
    'and so do the messages either side of 174.');
assert(not kind_of(observer.read(message(self_id, crab, 0, 249), 1, snapshot), 'check'), 'Impossible to gauge gives no level.');
assert(not kind_of(observer.read(message(1002, crab, 70, 174), 1, snapshot), 'check'), 'Someone else\'s check is not yours.');
assert(not kind_of(observer.read(message(self_id, 1002, 70, 174), 1, snapshot), 'check'), 'A player is not a mob to charm.');
game.items[2] = 15080;
seen = kind_of(observer.read(action(self_id, 6, 52, { { crab, 136, 0 } }), 1, snapshot), 'charm');
assert(seen and seen.entity_id == crab and seen.items[2] == 15080, 'Your Charm that took, with what you had on.');
assert(not kind_of(observer.read(action(self_id, 6, 52, { { crab, 137, 0 } }), 1, snapshot), 'charm'), 'A charm that failed is none.');
assert(not kind_of(observer.read(action(1002, 6, 52, { { crab, 136, 0 } }), 1, snapshot), 'charm'), 'Someone else\'s charm is not yours.');
seen = kind_of(observer.read(action(self_id, 6, 24, { { crab, 108, 0 } }), 1, snapshot), 'familiar');
assert(seen and seen.entity_id == crab, 'Your Familiar.');
game.items[2] = nil;

-- The watch.
local s = defaults.tidy(defaults.make());
assert(not s.pet.enabled and s.pet.locked, 'The display starts off and locked.');
s.pet.enabled = true;
local watch = pet.new();
assert(watch:refresh(10, s, snapshot, {}, {}) == nil, 'No pet, nothing to show.');
watch:observe({ kind = 'check', entity_id = crab, level = 70 }, 10, snapshot);
watch:observe({ kind = 'charm', entity_id = crab, items = {} }, 20, snapshot);
game.pet = pet_index;
local subjects = { [crab] = { effects = { { effect = 33, kind = 'buff', name = 'Haste', remaining = 100, first_seen = 2 },
    { effect = 4, kind = 'debuff', name = 'Paralysis', remaining = 30, first_seen = 3 } } } };
local recasts = { { kind = 'ability', recast_id = 102, remaining = 50, total = 120 }, { kind = 'ability', recast_id = 103, remaining = 20 },
    { kind = 'ability', recast_id = 0, remaining = 3000 }, { kind = 'ability', recast_id = 10, remaining = 5 }, { kind = 'spell', recast_id = 102, remaining = 9 } };
local shown = watch:refresh(21, s, snapshot, subjects, recasts);
assert(shown and shown.valid and shown.id == crab and shown.name == 'Crab' and shown.hpp == 76 and shown.tp == 1250 and not shown.has_mp,
    'Your pet as the client shows it; no MP yet.');
assert(shown.charm and shown.charm.seconds == 711 and shown.charm.deadline == 731, 'The charm\'s estimate: CHR 70, level 75, a 70.');
assert(shown.effects == subjects[crab].effects, 'Its effects are the tracker\'s rows.');
assert(shown.recast_count == 3 and shown.recasts[1].info.name == 'Reward' and shown.recasts[2].info.name == 'Sic'
    and shown.recasts[3].info.name == 'Familiar', 'Your pet recasts, soonest first, the two-hour your main job\'s.');
assert(shown.recasts[2].full == 120 and shown.recasts[1].full == 180, 'The full recast: what was seen, else the era recast.');
for _, entry in ipairs(shown.recasts) do assert(entry.info.name ~= 'Ready', 'Ready is not in era.'); end
-- Merits shorten the era recast only on the main job at 75.
local merits = MOCK.bytes(12);
MOCK.put(merits, 4, 2, 1); MOCK.put(merits, 8, 2, 902); MOCK.put(merits, 11, 1, 5);
client.accept(MOCK.packet(0x08C, merits), 21, snapshot);
recasts[1].total = nil;
shown = watch:refresh(22, s, snapshot, subjects, recasts);
assert(shown.recasts[2].full == 100, 'Five Sic merits take 20 s off: ' .. shown.recasts[2].full);
local young = with_pet({ valid = true, id = self_id, zone = 102, name = 'Tester', level = 74, job = 9, party = {}, entities = snapshot.entities });
shown = watch:refresh(22, s, young, subjects, recasts);
assert(shown.recasts[2].full == 120, 'Below 75 the merits don\'t count: ' .. shown.recasts[2].full);
local sub = with_pet({ valid = true, id = self_id, zone = 102, name = 'Tester', level = 75, job = 1, party = {}, entities = snapshot.entities });
shown = watch:refresh(22, s, sub, subjects, recasts);
assert(shown.recast_count == 2 and shown.recasts[2].full == 120, 'On /BST the merits don\'t count and the two-hour is not a pet one.');
-- MP once the client gives some, and kept.
game.mpp = 40;
shown = watch:refresh(23, s, snapshot, subjects, recasts);
assert(shown.has_mp and shown.mpp == 40, 'MP shows once it is above 0.');
game.mpp = 0;
assert(watch:refresh(24, s, snapshot, subjects, recasts).has_mp, 'and stays when it runs out.');
-- Familiar adds 25 minutes once, and its gear a minute more for each point.
watch:observe({ kind = 'familiar', entity_id = crab, items = { [0] = 10718 } }, 30, snapshot);
shown = watch:refresh(31, s, snapshot, subjects, recasts);
assert(shown.charm.deadline == 731 + 1500 + 600 and shown.charm.familiar, 'Familiar adds 25 minutes and 10 more from its gear.');
watch:observe({ kind = 'familiar', entity_id = crab, items = {} }, 40, snapshot);
assert(watch:refresh(41, s, snapshot, subjects, recasts).charm.deadline == 2831, 'Only once.');
-- The pet goes: nothing to show, and its charm is dropped.
game.pet = 0;
assert(watch:refresh(50, s, snapshot, subjects, recasts) == nil and next(watch.charms) == nil, 'No pet, no charm.');
-- A charm with no /check before it has no estimate.
watch:observe({ kind = 'charm', entity_id = wolf, items = {} }, 60, snapshot);
game.pet, game.id, game.name = pet_index, wolf, 'Wolf';
shown = watch:refresh(61, s, snapshot, {}, {});
assert(shown.charm and shown.charm.deadline == nil and shown.effects and #shown.effects == 0, 'Charmed, with no estimate.');
assert(not shown.has_mp, 'A new pet shows MP only once it has some, whatever the pet before had.');
local text = pet.charm_details(shown.charm, 61);
assert(text:find('/check', 1, true) and not text:find('?', 1, true) and not text:lower():find('unknown', 1, true), text);
-- The pet changes with no gap between them: MP starts over too.
game.mpp = 40;
assert(watch:refresh(61.5, s, snapshot, {}, {}).has_mp, 'The wolf has MP.');
game.mpp, game.id = 0, 0x1000201;
assert(not watch:refresh(61.6, s, snapshot, {}, {}).has_mp, 'The next pet doesn\'t yet.');
-- A jug pet: no charm.
game.id, game.name = 0x1000200, 'Sheep Familiar';
shown = watch:refresh(62, s, snapshot, {}, {});
assert(shown.name == 'Sheep Familiar' and shown.charm == nil, 'A jug pet has no charm.');
-- Off, nothing.
s.pet.enabled = false;
assert(watch:refresh(63, s, snapshot, {}, {}) == nil, 'Off, nothing.');
s.pet.enabled = true;
-- A level and a charm from a zone before are gone after a clear.
watch:observe({ kind = 'check', entity_id = crab, level = 70 }, 70, snapshot);
watch:clear();
assert(next(watch.levels) == nil and next(watch.charms) == nil, 'A zone change clears them.');
-- The charm time gear you had on at the charm lengthens the estimate.
watch:observe({ kind = 'check', entity_id = crab, level = 70 }, 71, snapshot);
watch:observe({ kind = 'charm', entity_id = crab, items = { [2] = 15080 } }, 72, snapshot);
local geared = watch.charms[crab];
assert(geared.charm_time == 5 and geared.seconds == 889 and geared.deadline == 961
    and pet.charm_details(geared, 72):find('charm time gear +5', 1, true), 'CHARM_TIME 5 adds a quarter: ' .. tostring(geared.seconds));

-- Tidy.
local tidied = pet.tidy({ enabled = true, max_effects = 99, kinds = 'odd', include = { 33, 33, '4', 2000 }, exclude = { [41] = true },
    hp_color = { 1, 'x', 0, 1 }, extra = 'kept' });
assert(tidied.max_effects == 32 and tidied.kinds == 'all' and #tidied.include == 2 and tidied.include[1] == 4 and tidied.include[2] == 33
    and #tidied.exclude == 1 and tidied.exclude[1] == 41 and tidied.hp_color[2] == pet.make().hp_color[2]
    and tidied.extra == 'kept' and tidied.locked == true, 'Tidy clamps, sorts and keeps.');
-- A save without these options gets them on, and a save with them keeps what it has.
tidied = pet.tidy({ enabled = true, locked = false, show_charm = false });
assert(tidied.blink_icons == true and tidied.blink_seconds == 15 and tidied.effects_as == 'icons' and tidied.show_maneuvers == true,
    'These options start on in a save without them.');
assert(tidied.locked == false and tidied.show_charm == false and tidied.enabled == true, 'and what it holds stays.');
tidied = pet.tidy({ blink_icons = false, blink_seconds = 40, effects_as = 'list', show_maneuvers = false });
assert(tidied.blink_icons == false and tidied.blink_seconds == 40 and tidied.effects_as == 'list' and tidied.show_maneuvers == false, 'A saved choice stays.');
tidied = pet.tidy({ blink_icons = 'yes', blink_seconds = 4000, effects_as = 'bars', show_maneuvers = 1 });
assert(tidied.blink_icons == true and tidied.blink_seconds == 300 and tidied.effects_as == 'icons' and tidied.show_maneuvers == true, 'A bad value doesn\'t.');
assert(not pet.make().enabled and pet.make().locked, 'A fresh display is off and locked.');

-- Drawing.
game.id, game.name, game.mpp = crab, 'Crab', 40;
watch = pet.new();
watch:observe({ kind = 'check', entity_id = crab, level = 70 }, 100, snapshot);
watch:observe({ kind = 'charm', entity_id = crab, items = {} }, 100, snapshot);
local view = { pet = watch:refresh(101, s, snapshot, subjects, recasts) };
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
    return table.concat(texts(), '|'), hovered;
end
-- Each time in the one format every countdown has: hours, then minutes, then seconds.
local list = drawn(101.5);
for _, part in ipairs({ 'Crab', 'Charm', '|11m|', 'HP 76%', 'MP 40%', 'TP 1250', '30s', '|1m|', 'Reward', 'Sic', 'Familiar' }) do
    assert(list:find(part, 1, true), 'The display draws ' .. part .. ': ' .. list);
end
assert(not list:find('Ready', 1, true), 'Never Ready.');
-- The display's filters, and the shared hide rules with a Pets rule.
s.pet.kinds = 'buff';
list = drawn(101.5);
assert(not list:find('30s', 1, true) and list:find('|1m|', 1, true), 'Buffs only: ' .. list);
s.pet.kinds, s.pet.exclude = 'all', { 33 };
list = drawn(101.5);
assert(list:find('30s', 1, true) and not list:find('|1m|', 1, true), 'Haste hidden on the pet display: ' .. list);
s.pet.exclude, s.pet.include = {}, { 4 };
list = drawn(101.5);
assert(list:find('30s', 1, true) and not list:find('|1m|', 1, true), 'Only Paralysis included: ' .. list);
s.pet.include = {};
local filters = require('core.effect_filters');
local rule = filters.rule();
rule.effect, rule.scope = 4, 'pet';
local hiding = { enabled = true, rules = { rule } };
callbacks.effect_filters = filters.compile(hiding);
list = drawn(101.5);
assert(not list:find('30s', 1, true) and list:find('|1m|', 1, true), 'A shared rule for pets hides Paralysis: ' .. list);
s.pet.shared_rules = false;
assert(drawn(101.5):find('30s', 1, true), 'unless the display leaves the shared rules out.');
s.pet.shared_rules = true;
rule.scope = 'enemy';
callbacks.effect_filters = filters.compile({ enabled = true, rules = { rule } });
assert(drawn(101.5):find('30s', 1, true), 'A rule for enemies isn\'t one for your pet, though it is a mob.');
callbacks.effect_filters = nil;
-- Limits cut silently.
s.pet.max_effects, s.pet.max_recasts = 1, 1;
list = drawn(101.5);
assert(list:find('30s', 1, true) and not list:find('|1m|', 1, true) and list:find('Reward', 1, true) and not list:find('Sic', 1, true)
    and not list:find('+', 1, true), 'One effect, one recast, nothing after them: ' .. list);
s.pet.max_effects, s.pet.max_recasts = 8, 6;
-- No countdowns, no vitals.
s.pet.show_countdowns, s.pet.show_vitals = false, false;
list = drawn(101.5);
assert(not list:find('30s', 1, true) and not list:find('HP', 1, true), 'Each part has its switch: ' .. list);
s.pet.show_countdowns, s.pet.show_vitals = true, true;
-- A charm whose estimate ran out shows with no countdown.
list = drawn(900);
assert(list:find('Charmed', 1, true) and not list:find('Charm|', 1, true), 'An ended estimate shows no countdown: ' .. list);
for _, value in ipairs(texts()) do
    assert(not tostring(value):find('?', 1, true) and not tostring(value):lower():find('unknown', 1, true), 'Nothing reads ? or unknown: ' .. tostring(value));
end
-- What is under the mouse: the charm, an effect or a recast, only with Hover details.
moving.hover, moving.mx, moving.my = true, 1560, 530;
local _, hovered = drawn(101.5);
assert(hovered and hovered.kind == 'charm' and display.details(hovered, 101.5):find('estimated', 1, true), 'The charm under the mouse.');
moving.hover = false;
-- No pet: nothing drawn while locked; the samples show one.
view.pet = nil;
assert(drawn(102) == '', 'No pet, nothing.');
s.pet.preview = true;
list = drawn(102);
assert(list:find('Sample pet', 1, true) and list:find('Sic', 1, true) and list:find('Charm', 1, true), 'Sample displays show a pet: ' .. list);
s.pet.preview = false;
-- Locked, Shift moves nothing; unlocked with Shift held it can be dragged.
view.pet = watch:refresh(103, s, snapshot, subjects, recasts);
local function buttons()
    local count = 0;
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'InvisibleButton' then count = count + 1; end end
    return count;
end
moving.shift = true;
drawn(103);
assert(buttons() == 0, 'A locked display takes no drag.');
s.pet.locked = false;
drawn(103);
assert(buttons() == 1, 'Unlocked with Shift held it can be dragged.');
s.pet.locked, moving.shift = true, false;

-- The status pictures drawn, by the effect's id, with their corners and tints.
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);
local function images(wanted)
    local out, count = {}, 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        local args = MOCK.drawn[call];
        if call[1] == 'draw:AddImage' and type(args[2]) == 'number' and wanted[args[2] - 5000] then
            count = count + 1;
            out[args[2] - 5000] = { x = args[3][1], y = args[3][2], right = args[4][1], tint = args[7] };
        end
    end
    return out, count;
end
local function effects_of(rows)
    local wanted = {};
    for _, row in ipairs(rows) do wanted[row.effect] = true; end
    return wanted;
end
local function showing(rows, at)
    view.pet = watch:refresh(at, s, snapshot, { [crab] = { effects = rows } }, {});
    return drawn(at);
end
-- Icons wrap onto more rows when they don't fit the width, up to the limit, and what is past it leaves no mark.
local many = {};
for i = 1, 12 do
    many[i] = { effect = 100 + i, kind = 'buff', name = 'Boost', status = 'estimated', deadline = 500, remaining = 396, total = 500, first_seen = i, instance = i };
end
local wanted = effects_of(many);
s.pet.width, s.pet.max_effects = 160, 12;
showing(many, 104);
local found, count = images(wanted);
local rows_at, row_count = {}, 0;
for _, image in pairs(found) do
    if not rows_at[image.y] then rows_at[image.y], row_count = true, row_count + 1; end
    assert(image.right <= s.pet.x + s.pet.width, 'Every icon inside the width.');
end
assert(count == 12 and row_count >= 2, 'Twelve icons on rows of their own: ' .. count .. ' on ' .. row_count);
assert(found[102].y == found[101].y and found[112].y > found[101].y, 'They keep their order, row by row.');
s.pet.max_effects = 5;
list = showing(many, 104);
found, count = images(wanted);
assert(count == 5 and found[105] and not found[106] and not list:find('+', 1, true), 'The limit counts rows and all, and leaves no mark: ' .. count);
-- A height set by hand cuts the rows that don't fit, with no mark either.
s.pet.max_effects, s.pet.height = 12, 150;
list = showing(many, 104);
found, count = images(wanted);
assert(count > 0 and count < 12 and not list:find('+', 1, true), 'A short display shows what fits: ' .. count);
s.pet.height, s.pet.width, s.pet.max_effects = 0, 280, 8;

-- A list: each effect's icon, name and time, over a fill of how much is left; one with no time shows only its name.
local named = { { effect = 37, kind = 'buff', name = 'Stoneskin', status = 'estimated', deadline = 204, remaining = 100, total = 200, first_seen = 1, instance = 1 },
    { effect = 135, kind = 'debuff', name = 'Bio', status = 'unknown', first_seen = 2, instance = 2 } };
s.pet.effects_as = 'list';
list = showing(named, 104);
assert(list:find('Stoneskin', 1, true) and list:find('Bio', 1, true) and list:find('|1m|', 1, true), 'The list has names and the time: ' .. list);
found, count = images(effects_of(named));
assert(count == 2 and found[135].y < found[37].y, 'Debuffs first, as the icons are.');
local fill = theme.u32(s.style.accent_color, 0.35);
local fills = {};
for _, call in ipairs(MOCK.imgui_calls) do
    local args = MOCK.drawn[call];
    if call[1] == 'draw:AddRectFilled' and args[4] == fill then fills[#fills + 1] = args[3][1] - args[2][1]; end
end
local inner = s.pet.width - 12 * s.style.scale;
assert(#fills == 1 and math.abs(fills[1] / inner - 0.5) < 0.01, 'Half the time left fills half the line, and the row with no time has none.');
s.pet.max_effects = 1;
list = showing(named, 104);
assert(list:find('Bio', 1, true) and not list:find('Stoneskin', 1, true) and not list:find('+', 1, true), 'The limit holds in a list too: ' .. list);
s.pet.max_effects = 8;
s.pet.show_countdowns = false;
list = showing(named, 104);
assert(list:find('Stoneskin', 1, true) and not list:find('|1m|', 1, true), 'No countdowns, just the name: ' .. list);
s.pet.show_countdowns = true;
s.pet.effects_as = 'icons';

-- Copy Image draws the icon its shadows show, 445 for three, as the other displays do, not Copy Image's own.
showing({ { effect = 66, icon = 445, kind = 'buff', name = 'Copy Image', status = 'unknown', first_seen = 1, instance = 1 } }, 104);
found, count = images({ [66] = true, [445] = true });
assert(count == 1 and found[445] and not found[66], 'Copy Image shows its shadows\' icon.');

-- Blink: an effect near its end dims at the display's seconds; one with time to go or none to show doesn't.
local ending = { { effect = 101, kind = 'buff', status = 'estimated', deadline = 110, remaining = 6, total = 60, first_seen = 1, instance = 1 },
    { effect = 102, kind = 'buff', status = 'server', deadline = 204, remaining = 100, total = 300, first_seen = 2, instance = 2 },
    { effect = 103, kind = 'buff', status = 'unknown', first_seen = 3, instance = 3 } };
wanted = effects_of(ending);
showing(ending, 104);
found = images(wanted);
assert(found[101].tint ~= found[102].tint and found[102].tint == found[103].tint, 'Only the timed effect near its end blinks.');
s.pet.blink_seconds = 5;
showing(ending, 104);
found = images(wanted);
assert(found[101].tint == found[102].tint, 'Six seconds left isn\'t within five.');
s.pet.blink_seconds, s.pet.blink_icons = 15, false;
showing(ending, 104);
found = images(wanted);
assert(found[101].tint == found[102].tint, 'Blink off, nothing blinks.');
s.pet.blink_icons = true;
s.pet.effects_as = 'list';
showing(ending, 104);
found = images(wanted);
assert(found[101].tint ~= found[102].tint, 'The icons in a list blink too.');
s.pet.effects_as = 'icons';

-- A jug's clock: Leaves in on the title row, in the warning color for its last minute, and gone with Show charm and jug time off.
game.id, game.name = 0x1000300, 'SheepFamiliar';
game.pet = 0;
watch = pet.new();
watch:refresh(198, s, snapshot, {}, {});
watch:observe({ kind = 'call_beast', entity_id = self_id, item = 17016 }, 200, snapshot);
game.pet = pet_index;
view.pet = watch:refresh(200.5, s, snapshot, {}, {});
assert(view.pet.jug and view.pet.jug.deadline == 3800 and view.pet.jug.seconds == 3600, 'SheepFamiliar stays an hour from your Call Beast.');
list = drawn(210);
assert(list:find('Leaves in', 1, true) and list:find('|59m|', 1, true), 'The title row: ' .. list);
local function clock_ink(text)
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddText' and call[6] == text and call[5] == theme.u32(s.style.warning_color) then return true; end
    end
    return false;
end
assert(not clock_ink('59m'), 'With time to go it isn\'t a warning.');
list = drawn(3790);
assert(list:find('|10s|', 1, true) and clock_ink('10s'), 'Its last minute is: ' .. list);
s.pet.show_charm = false;
list = drawn(210);
assert(not list:find('Leaves in', 1, true) and not list:find('59m', 1, true), 'Show charm and jug time off: ' .. list);
s.pet.show_charm = true;
local _, spot;
moving.hover, moving.mx, moving.my = true, 1560, 530;
_, spot = drawn(210);
assert(spot and spot.kind == 'jug' and display.details(spot, 210):find('60 minutes for SheepFamiliar on Phoenix', 1, true), 'Its tooltip says how long and whose.');
moving.hover = false;

-- Each job's sample: a pet of its own, drawn from the same tables a real one is.
view.pet, s.pet.preview = nil, true;
for job, parts in pairs({ [9] = { 'Sample jug', 'Leaves in', 'Sic' }, [14] = { 'Sample wyvern', 'Deep Breathing' }, [15] = { 'Sample avatar', 'Blood Pact' },
    [18] = { 'Sample automaton', 'Fire', 'Thunder', '23%' }, [3] = { 'Sample pet', 'Charm' } }) do
    view.context = { job = job };
    list = drawn(300);
    for _, part in ipairs(parts) do assert(list:find(part, 1, true), 'The sample for job ' .. job .. ' has ' .. part .. ': ' .. list); end
    assert(not list:find('Sample jug', 1, true) or job == 9, 'One job\'s sample isn\'t another\'s.');
end
local sample = pet.samples(300, 15);
assert(#sample.effects == 8, 'An avatar with Hastega and the seven boosts of Ecliptic Growl.');
assert(pet.samples(300, 14).effects[1].effect == 190, 'A wyvern with Deep Breathing\'s Magic Atk. Boost.');
assert(pet.samples(300, 18).effects[1].effect == 166 and pet.samples(300, 18).maneuver_count == 2, 'An automaton with Overdrive and two lines of maneuvers.');
assert(pet.samples(300, nil).name == 'Sample pet', 'No job yet, the charmed sample.');
s.pet.preview, view.context = false, nil;
return 'The pet display';
