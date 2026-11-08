-- The pet display (settings.pet). While you have a pet it shows the pet's name, HP, MP once the client has given it
-- some, TP, the buffs and debuffs Vantage saw on it with their timers, the recasts of your pet commands, for a pet you
-- charmed an estimate of the charm's time left from Phoenix's formula, for a jug the time until it leaves, and for a
-- PUP your maneuvers and the overload chance they reported. The pet and its HP, MP and TP come from the client, which
-- the game keeps up to date (0x068 at most every 250 ms, src/map/entities/pet_entity.cpp :212-227); no packet lists a
-- pet's effects, so they are only what Vantage saw land on it, as on any other unit, and when an effect on a pet ends,
-- only the player it came from is told, so only effects from you end exactly. It shows the pet the client shows,
-- whether or not a jug pet stays through a zone change on the server. Nothing here sends anything. ui/pet_display.lua
-- draws it.
--
-- A jug's clock and a charm's estimate are also kept for the life of the game process in a process environment variable
-- (core/patterns.lua's store, VANTAGE_PET), so an /addon reload doesn't lose them. Nothing goes on disk.
local pet = {};
local numbers = require('ui.numbers');
local finite = numbers.finite;
local DATA = require('data.pets');
pet.kinds = { 'all', 'buff', 'debuff' };
pet.effect_styles = { 'icons', 'list' };
-- The timers by id, and each pet job's two-hour on timer 0.
local TIMERS, SPECIALS = {}, {};
for _, info in ipairs(DATA.timers) do
    if info.special then SPECIALS[info.job] = info; else TIMERS[info.timer] = info; end
end
-- Familiar adds 25 to 30 minutes to a charmed pet, once, and a minute more for each FAMILIAR_BONUS
-- (scripts/globals/pets.lua :150-172, src/map/utils/petutils.cpp ExtendCharm :1738-1754). The estimate counts 25.
pet.FAMILIAR = 25 * 60;
local LEVELS, MAX_EFFECTS, MAX_RECASTS = 64, 32, 16;
local EMPTY = {};
-- The jugs by a key that leaves out how the client spells a name, should it show SheepFamiliar as Sheep Familiar.
local function jug_key(name) return (name:gsub('[%s_]', '')):lower(); end
local JUGS = {};
for name, seconds in pairs(DATA.jugs) do JUGS[jug_key(name)] = seconds; end
-- A Call Beast and its pet arrive within this of each other, in either order. A jug that zones comes back within 30
-- seconds or not at all, and what a reload kept waits as long for its pet. Five wards are enough for /vg report.
local CALL_WINDOW, RETURN_WINDOW, WARDS, WARD_WAIT = 10, 30, 5, 15;
-- The maneuver effects in element order.
local MANEUVERS = {};
for _, effect in pairs(DATA.maneuvers) do MANEUVERS[#MANEUVERS + 1] = effect; end
table.sort(MANEUVERS);
-- Burden falls by at least 1 every 3 seconds (src/map/entities/automaton_entity.cpp :80-89, zone_entities.cpp :1919).
local BURDEN_TICK = 3;

function pet.make()
    return { enabled = false, preview = false, x = 1300, y = 520, width = 280, height = 0, locked = true,
        show_vitals = true, show_charm = true, show_effects = true, show_recasts = true, show_countdowns = true,
        show_maneuvers = true, effects_as = 'icons', blink_icons = true, blink_seconds = 15,
        max_effects = 8, max_recasts = 6, kinds = 'all', include = {}, exclude = {}, shared_rules = true,
        countdown_bold = false, countdown_shadow = true, countdown_outline = false,
        countdown_outline_color = { 0, 0, 0, 1 }, hp_color = { 0.4, 0.8, 0.35, 1 }, mp_color = { 0.35, 0.6, 0.95, 1 },
        tp_color = { 0.95, 0.75, 0.3, 1 } };
end

local function table_of(value) return type(value) == 'table' and value or {}; end

local function number(value, low, high, fallback)
    return numbers.clamp_round(value, low, high, fallback);
end

local function choice(value, choices, fallback)
    for _, item in ipairs(choices) do if value == item then return value; end end
    return fallback;
end

local function rgba(value, fallback)
    local color, saved = {}, table_of(value);
    for i = 1, 4 do color[i] = numbers.clamp(saved[i] or saved[tostring(i)], 0, 1, fallback[i]); end
    return color;
end

-- Effect ids 1 to 1023 as a sorted list without repeats, from a list or from a set. At most 256 are kept.
local function effect_list(value)
    local seen, result = {}, {};
    value = table_of(value);
    local function add(id)
        id = tonumber(id);
        if finite(id) and id >= 1 and id <= 1023 and id == math.floor(id) and not seen[id] then seen[id], result[#result + 1] = true, id; end
    end
    for key, on in pairs(value) do if on == true then add(key); end end
    for _, id in ipairs(value) do add(id); end
    table.sort(result);
    for index = #result, 257, -1 do result[index] = nil; end
    return result;
end

-- Keys this doesn't know are kept, as the rest of the settings keep them.
function pet.tidy(value)
    value = table_of(value);
    local fresh = pet.make();
    for _, key in ipairs({ 'enabled', 'locked', 'show_vitals', 'show_charm', 'show_effects', 'show_recasts', 'show_countdowns',
        'show_maneuvers', 'blink_icons', 'shared_rules', 'countdown_bold', 'countdown_shadow', 'countdown_outline' }) do
        if type(value[key]) ~= 'boolean' then value[key] = fresh[key]; end
    end
    value.x = number(value.x, 0, 16000, fresh.x);
    value.y = number(value.y, 0, 16000, fresh.y);
    value.width = number(value.width, 160, 1400, fresh.width);
    value.height = number(value.height, 0, 16000, 0);
    if value.height > 0 then value.height = math.max(60, value.height); end
    value.max_effects = number(value.max_effects, 1, MAX_EFFECTS, fresh.max_effects);
    value.max_recasts = number(value.max_recasts, 1, MAX_RECASTS, fresh.max_recasts);
    value.blink_seconds = number(value.blink_seconds, 1, 300, fresh.blink_seconds);
    value.kinds = choice(value.kinds, pet.kinds, 'all');
    value.effects_as = choice(value.effects_as, pet.effect_styles, 'icons');
    value.include, value.exclude = effect_list(value.include), effect_list(value.exclude);
    for _, key in ipairs({ 'countdown_outline_color', 'hp_color', 'mp_color', 'tp_color' }) do value[key] = rgba(value[key], fresh[key]); end
    -- The samples show in the display, so they are kept only while it is on.
    value.preview = value.preview == true and value.enabled;
    return value;
end

-- How long a charm lasts on Phoenix, in whole seconds, from the charmer's CHR, the charmer's main level whatever the
-- main job, the mob's main level and the charmer's CHARM_TIME gear (scripts/globals/job_utils/beastmaster.lua
-- getCharmDuration :30-61).
function pet.charm_seconds(chr, level, mob_level, charm_time)
    local base = math.floor(1.25 * chr + 150);
    local d = level - mob_level;
    local mult = 1 / 24;
    if d >= -6 and d < 9 then
        mult = 0.9997336 + 0.3652882 * d + 0.02097742 * d ^ 2 - 0.004106429 * d ^ 3 + 0.000007231037 * d ^ 4 + 0.00005102634 * d ^ 5;
    elseif d >= 9 then mult = 6; end
    local seconds = base * mult;
    seconds = seconds + seconds * ((charm_time or 0) * 0.5 / 10);
    return math.floor(seconds);
end

-- The total of one gear mod on the items you had on, by item id (data/pets.lua).
local function gear(items, table)
    local total = 0;
    for _, item in pairs(items or EMPTY) do total = total + (table[item] or 0); end
    return total;
end

-- pcall(index_of, object, key) guards a lookup without making a closure for it.
local function index_of(object, key) return object[key]; end
local function call(object, name, ...)
    if object == nil then return nil; end
    local ok, fn = pcall(index_of, object, name);
    if not ok or type(fn) ~= 'function' then return nil; end
    local done, value = pcall(fn, object, ...);
    if done then return value; end
end
local function memory() return call(AshitaCore, 'GetMemoryManager'); end

-- Your CHR as the status screen shows it: the base and what gear, food and effects add (0x061,
-- src/map/packets/s2c/0x061_clistatus.cpp :45, :61; CHR is stat 6). Phoenix's charm reads the same total
-- (src/map/entities/battle_entity.cpp :1184-1187).
local function charisma()
    local player = call(memory(), 'GetPlayer');
    local base, bonus = call(player, 'GetStat', 6), call(player, 'GetStatModifier', 6);
    if finite(base) and finite(bonus) and base + bonus >= 0 and base + bonus <= 999 then return base + bonus; end
end

local methods = {};
methods.__index = methods;

-- What a reload left in the store, or nil.
local function kept_text(text)
    if type(text) ~= 'string' then return nil; end
    local fields = {};
    for field in (text .. ';'):gmatch('([^;]*);') do fields[#fields + 1] = field; end
    if fields[1] ~= '1' or #fields ~= 13 then return nil; end
    return { owner = tonumber(fields[2]), name = fields[3], jug_end = tonumber(fields[4]), jug_seconds = tonumber(fields[5]), charm = fields[6] == '1',
        charm_end = tonumber(fields[7]), chr = tonumber(fields[8]), level = tonumber(fields[9]), mob_level = tonumber(fields[10]),
        charm_time = tonumber(fields[11]) or 0, familiar = fields[12] == '1' or nil, familiar_bonus = tonumber(fields[13]) or 0 };
end

-- levels: the level each mob's /check gave, by id. charms: each charm of yours that took, by the mob's id. jug: the
-- clock of the jug out now; held: one that left with a zone change, until it comes back. percents: the overload chance
-- each maneuver last reported, by its effect. wards: the last few of your avatar's, for /vg report. shown: what the
-- display draws, refilled: the pet, its effects (the tracker's rows), its recasts and your maneuvers. store is what keeps
-- a jug and a charm through a reload (core/patterns.lua): { read, write }, or nil for none.
function pet.new(store)
    local kept;
    if store then
        local ok, text = pcall(store.read);
        kept = ok and kept_text(text) or nil;
    end
    return setmetatable({ levels = {}, level_count = 0, charms = {}, version = 0, store = store, kept = kept, percents = {}, wards = {},
        shown = { valid = false, effects = EMPTY, recasts = {}, recast_count = 0, maneuvers = {}, maneuver_count = 0 } }, methods);
end

-- A zone change: charms and /check levels stay in the zone they were seen in. A jug can come along, so with now
-- its clock waits to see the pet again; each clear of one zone change starts that wait over, the last when you arrive.
function methods:clear(now)
    local jug = finite(now) and (self.jug or self.held);
    self.held = jug and { name = jug.name, seconds = jug.seconds, deadline = jug.deadline, owner = jug.owner, until_at = now + RETURN_WINDOW } or nil;
    self.jug, self.called, self.ward_waiting, self.percents = nil, nil, nil, {};
    self.levels, self.level_count, self.charms = {}, 0, {};
    self.shown.valid, self.current = false, nil;
    self.dirty = true;
    self.version = self.version + 1;
end

-- What the observer gives this watch.
methods.takes = { check = true, charm = true, familiar = true, call_beast = true, maneuver = true, ward = true };

-- One observation from core/observer.lua: a /check of a mob ('check'), your Charm that took ('charm'), your Familiar
-- ('familiar'), your Call Beast ('call_beast'), the overload chance your maneuver reported ('maneuver') or a ward of your
-- avatar ('ward').
function methods:observe(observation, now, snapshot)
    local id = observation.entity_id;
    if not finite(id) or not finite(now) then return; end
    if observation.kind == 'check' and finite(observation.level) then
        if not self.levels[id] then
            if self.level_count >= LEVELS then self.levels, self.level_count = {}, 0; end
            self.level_count = self.level_count + 1;
        end
        self.levels[id] = observation.level;
    elseif observation.kind == 'charm' then
        local record = { id = id, at = now, chr = charisma(), level = snapshot and snapshot.level,
            mob_level = self.levels[id], charm_time = gear(observation.items, DATA.charm_time) };
        if finite(record.chr) and finite(record.level) and finite(record.mob_level) then
            record.seconds = pet.charm_seconds(record.chr, record.level, record.mob_level, record.charm_time);
            record.deadline = now + record.seconds;
        end
        self.charms[id], self.dirty = record, true;
    elseif observation.kind == 'familiar' then
        -- Familiar lengthens a charm once (pets.lua :153-160); a jug pet keeps its time.
        local record = self.charms[self.current or id] or self.charms[id];
        if record and not record.familiar then
            record.familiar, record.familiar_bonus = true, gear(observation.items, DATA.familiar_bonus);
            if record.deadline then record.deadline = record.deadline + pet.FAMILIAR + record.familiar_bonus * 60; end
            self.dirty = true;
        end
    elseif observation.kind == 'call_beast' then
        -- You can't call a pet with one out, so any clock from before is over.
        self.called, self.jug, self.held, self.dirty = { at = now, item = observation.item }, nil, nil, true;
    elseif observation.kind == 'maneuver' and finite(observation.percent) then
        self.percents[observation.maneuver] = { percent = observation.percent, at = now };
    elseif observation.kind == 'ward' then
        local ward = { pact = observation.pact, name = observation.name, skill = observation.skill, level = observation.level,
            seconds = observation.seconds, at = now };
        if #self.wards >= WARDS then table.remove(self.wards, 1); end
        self.wards[#self.wards + 1] = ward;
        self.ward_waiting = observation.own and ward or nil;
    else return; end
    self.version = self.version + 1;
end

-- What /vg report says of the pet: the last few wards, with the skill and level read, the length worked out from them
-- and the length your own copy had, so the one can be checked against the other.
function methods:report()
    return { wards = self.wards };
end

-- The full recast of a pet timer: what Vantage saw it start with, else its era recast less the merits that count on
-- your main job at 75. A merit that unlocks its ability takes nothing off at its first rank.
local function full(info, row, snapshot)
    if finite(row.total) and row.total > 0 then return row.total; end
    local recast = info.recast;
    local client = require('core.client');
    if info.merit and client.merit and snapshot and snapshot.job == info.job and (snapshot.level or 0) >= 75 then
        local ranks = client.merit(info.merit) or 0;
        if info.free_rank then ranks = math.max(ranks - 1, 0); end
        recast = recast - ranks * info.per_rank;
    end
    return math.max(1, recast);
end

local function sooner(a, b)
    local left, right = a.row.remaining or math.huge, b.row.remaining or math.huge;
    if left ~= right then return left < right; end
    return a.info.timer < b.info.timer;
end

-- What a reload needs of the jug and charm you have now, as text, or nil with neither. Times are the wall clock's, which
-- is the one a new load can read them by.
local function memory_text(self, now, snapshot)
    local jug = self.jug or self.held;
    local charm = self.current and self.charms[self.current];
    if not jug and not (charm and charm.linked) then return nil; end
    local clock = os.time();
    local function wall(deadline) return deadline and tostring(math.floor(clock + deadline - now + 0.5)) or ''; end
    local function text(value) return value ~= nil and tostring(value) or ''; end
    charm = charm and charm.linked and charm or nil;
    return table.concat({ '1', tostring(snapshot.id), jug and jug.name or self.current_name or '', wall(jug and jug.deadline), text(jug and jug.seconds),
        charm and '1' or '0', wall(charm and charm.deadline), text(charm and charm.chr), text(charm and charm.level),
        text(charm and charm.mob_level), text(charm and charm.charm_time), charm and charm.familiar and '1' or '0',
        text(charm and charm.familiar_bonus) }, ';');
end

-- Puts back what a reload kept, once the pet it was for is out. A deadline that passed in the meantime is gone with it.
local function restore(self, kept, now, id, name, owner)
    local left = kept.jug_end and kept.jug_end - os.time();
    if left and left > 0 and finite(kept.jug_seconds) then
        self.jug = { id = id, name = name, owner = owner, seconds = kept.jug_seconds, deadline = now + left };
    end
    if kept.charm then
        self.charms[id] = { id = id, at = now, linked = true, chr = kept.chr, level = kept.level, mob_level = kept.mob_level, charm_time = kept.charm_time,
            familiar = kept.familiar, familiar_bonus = kept.familiar_bonus, deadline = kept.charm_end and now + kept.charm_end - os.time() or nil };
    end
end

-- At each refresh, with the display on or off: follows your pet, so a jug's clock and a charm start, end, cross a zone
-- and come back after a reload whenever it is turned on.
function methods:watch(now, snapshot, subjects)
    if not snapshot or not snapshot.valid then return; end
    local mine = snapshot.pet;
    local id, name = mine and mine.id, mine and mine.name;
    local dirty = self.dirty == true;
    if id ~= self.current then
        self.shown.has_mp = false;
        self.current, self.current_at, self.percents, dirty = id, now, {}, true;
    end
    self.current_name = name or id and self.current_name or nil;
    local kept = self.kept;
    if kept then
        self.kept_until = self.kept_until or now + RETURN_WINDOW;
        if kept.owner ~= snapshot.id or now > self.kept_until then self.kept, dirty = nil, true;
        elseif id and name == kept.name then
            restore(self, kept, now, id, name, snapshot.id);
            self.kept, dirty = nil, true;
        end
    end
    -- A charm that took ties to the pet it made; one whose pet never came, or went, is dropped.
    for key, record in pairs(self.charms) do
        if key == id then
            if not record.linked then record.linked, dirty = true, true; end
        elseif record.linked or now - record.at > CALL_WINDOW then
            self.charms[key], dirty = nil, dirty or record.linked == true;
        end
    end
    local jug = self.jug;
    if jug and (jug.id ~= id or now >= jug.deadline) then self.jug, jug, dirty = nil, nil, true; end
    if jug and name and jug.name ~= name then jug.name, dirty = name, true; end
    local held = self.held;
    if held then
        if now > held.until_at or now >= held.deadline or held.owner ~= snapshot.id then
            self.held, dirty = nil, true;
        elseif id and name == held.name then
            self.jug = { id = id, name = name, owner = held.owner, seconds = held.seconds, deadline = held.deadline };
            self.held, dirty = nil, true;
        end
    end
    -- A jug's clock starts at your Call Beast. With a jug already out when this loaded there was none to start from, so
    -- it has no clock.
    local called = self.called;
    if called and now - called.at > CALL_WINDOW then self.called, called = nil, nil; end
    if called and id and not self.jug and math.abs(self.current_at - called.at) <= CALL_WINDOW then
        local seconds = name and JUGS[jug_key(name)] or DATA.jugs[DATA.jug_items[called.item]];
        if seconds then
            self.jug, dirty = { id = id, name = name or DATA.jug_items[called.item], owner = snapshot.id, seconds = seconds, deadline = called.at + seconds }, true;
        end
        if seconds or name then self.called = nil; end
    end
    -- A ward you were in: your own copy's length, once the server has given it.
    local waiting = self.ward_waiting;
    if waiting then
        local subject = subjects and subjects[snapshot.id];
        for _, row in ipairs(subject and subject.effects or EMPTY) do
            if row.spell == waiting.pact and row.status == 'server' and finite(row.total) then
                waiting.own_seconds, self.ward_waiting = row.total, nil;
                break;
            end
        end
        if now - waiting.at > WARD_WAIT then self.ward_waiting = nil; end
    end
    self.dirty = dirty;
    -- Nothing is written over what a reload left until that has found its pet or given up.
    if dirty and self.store and not self.kept then
        self.dirty = false;
        pcall(self.store.write, memory_text(self, now, snapshot));
    end
end

-- Fills the maneuver lines: each element with a maneuver up or an overload chance to show, its maneuvers, the soonest to
-- end, and the chance, which falls no faster than the server can lower it, so it is never below the real one. Your
-- maneuvers' times are your own 0x063's.
local function fill_maneuvers(self, shown, now, snapshot, on)
    local lines, count = shown.maneuvers, 0;
    for index, effect in ipairs(on and MANEUVERS or EMPTY) do
        local up, soonest = 0, nil;
        for _, held in ipairs(snapshot.self_effects or EMPTY) do
            if held.effect == effect then
                up = up + 1;
                if finite(held.deadline) and (not soonest or held.deadline < soonest) then soonest = held.deadline; end
            end
        end
        local saved = self.percents[effect];
        local percent = saved and saved.percent - math.floor((now - saved.at) / BURDEN_TICK) or 0;
        if up > 0 or percent > 0 then
            count = count + 1;
            local line = lines[count] or {};
            lines[count] = line;
            line.effect, line.name, line.count, line.deadline, line.status = effect, DATA.elements[index], up, soonest, 'server';
            line.percent, line.at = percent > 0 and percent or nil, saved and saved.at;
        end
    end
    for at = #lines, count + 1, -1 do lines[at] = nil; end
    shown.maneuver_count = count;
end

-- At each refresh: follows your pet and gathers what the display shows. subjects are the tracker's rows by unit
-- (state.party_subjects); recast_rows are your recasts (core/recasts.lua). Returns shown, or nil with no pet.
function methods:refresh(now, settings, snapshot, subjects, recast_rows)
    self:watch(now, snapshot, subjects);
    local config = settings and settings.pet;
    local shown = self.shown;
    shown.valid = false;
    if type(config) ~= 'table' or not config.enabled or not snapshot or not snapshot.valid then return nil; end
    local mine = snapshot.pet;
    if not mine then return nil; end
    local id, index = mine.id, mine.index;
    local entities, player = call(memory(), 'GetEntity'), call(memory(), 'GetPlayer');
    shown.valid, shown.id, shown.index = true, id, index;
    shown.name = type(mine.name) == 'string' and mine.name ~= '' and mine.name or 'Pet';
    -- Out of your view the client has no unit to read its HP from, so its last 0x068 says.
    local hpp = mine.hpp;
    if not mine.away then hpp = call(entities, 'GetHPPercent', index); end
    local mpp, tp = call(player, 'GetPetMPPercent'), call(player, 'GetPetTP');
    shown.hpp = finite(hpp) and math.max(0, math.min(100, hpp)) or nil;
    shown.mpp = finite(mpp) and math.max(0, math.min(100, mpp)) or nil;
    shown.tp = finite(tp) and math.max(0, math.min(3000, tp)) or nil;
    -- A pet with no MP sends 0 (src/map/entities/battle_entity.cpp GetMPP :328-336), so MP shows once it is above 0.
    shown.has_mp = shown.has_mp or (shown.mpp or 0) > 0;
    shown.charm, shown.jug = self.charms[id], self.jug;
    local subject = subjects and subjects[id];
    shown.effects = subject and subject.effects or EMPTY;
    local list, count = shown.recasts, 0;
    for _, row in ipairs(recast_rows or EMPTY) do
        local info = row.kind == 'ability' and (row.recast_id == 0 and SPECIALS[snapshot.job] or TIMERS[row.recast_id]);
        if info and count < MAX_RECASTS then
            count = count + 1;
            local entry = list[count] or {};
            list[count] = entry;
            entry.row, entry.info, entry.full = row, info, full(info, row, snapshot);
        end
    end
    for at = #list, count + 1, -1 do list[at] = nil; end
    table.sort(list, sooner);
    shown.recast_count = count;
    fill_maneuvers(self, shown, now, snapshot, config.show_maneuvers and (snapshot.job == 18 or snapshot.sub_job == 18));
    return shown;
end

-- The tooltip of the charm line.
function pet.charm_details(record, now)
    local countdown = require('ui.countdown_text');
    if not record.deadline then
        return 'Charmed. A charm\'s time is estimated from the mob\'s level, which the game gives with a /check before the charm.';
    end
    local lines = { record.deadline > now and 'Charm estimated to end in ' .. countdown.time(record.deadline - now) .. '.'
        or 'The estimated charm time has passed.' };
    lines[#lines + 1] = 'From Phoenix\'s charm formula with your CHR ' .. tostring(record.chr) .. ', your level ' .. tostring(record.level)
        .. ', the level your /check gave, ' .. tostring(record.mob_level) .. (record.charm_time > 0 and ', and charm time gear +' .. record.charm_time or '') .. '.';
    if record.familiar then
        lines[#lines + 1] = 'Familiar added 25 to 30 minutes' .. (record.familiar_bonus > 0 and ' and ' .. record.familiar_bonus .. ' more' or '')
            .. '; the estimate counts the least.';
    end
    lines[#lines + 1] = 'A /check gives a few mobs\' levels a little off, and gear Vantage doesn\'t know of can change it.';
    return table.concat(lines, '\n');
end

-- The tooltip of a jug's clock.
function pet.jug_details(jug)
    return 'Your jug pet leaves when its time is up: ' .. math.floor(jug.seconds / 60) .. ' minutes for ' .. tostring(jug.name)
        .. ' on Phoenix, counted from your Call Beast.';
end

-- The tooltip of one maneuver line.
function pet.maneuver_details(line, now)
    local countdown = require('ui.countdown_text');
    local lines = {};
    if line.count > 0 then
        lines[1] = line.name .. ' maneuvers up: ' .. line.count .. '.';
        if line.deadline and line.deadline > now then lines[2] = 'The next to end has ' .. countdown.time(line.deadline - now) .. ' left.'; end
    end
    if line.percent then
        lines[#lines + 1] = 'Overload risk ' .. line.percent .. '%. At most this. Reported by your last ' .. line.name .. ' maneuver '
            .. countdown.time(now - line.at) .. ' ago.';
    end
    return table.concat(lines, '\n');
end

-- The tooltip of one recast row.
function pet.recast_details(entry, now)
    local countdown = require('ui.countdown_text');
    local left = entry.row.remaining;
    return entry.info.name .. (finite(left) and left > 0 and ' - ready in ' .. countdown.time(left) or '')
        .. '\nFrom your recast timer. Full recast ' .. countdown.time(entry.full) .. '.';
end

-- What Sample displays show, by your main job: one of its pets with a few effects and recasts, and for any other job a
-- charmed pet. Each is made once and refilled, as a frame draws it.
local sample_record = { chr = 70, level = 75, mob_level = 72, charm_time = 0, linked = true };
local sample_jug = { name = 'SheepFamiliar', seconds = 3600 };
local function sample_pet(name, effects, recasts, lines)
    local out = { valid = true, sample = true, id = 0x1000F00, name = name, title = name .. '  /  Sample', effects = {}, made_effects = effects,
        recasts = {}, made_recasts = recasts, recast_count = #recasts, maneuvers = {}, made_lines = lines or EMPTY, maneuver_count = lines and #lines or 0,
        has_mp = true };
    for index in ipairs(effects) do out.effects[index] = { key = 'pet_sample_' .. index }; end
    for index, made in ipairs(recasts) do out.recasts[index] = { row = {}, info = TIMERS[made[1]] }; end
    for index in ipairs(out.made_lines) do out.maneuvers[index] = {}; end
    return out;
end
local charmed = sample_pet('Sample pet', { { 33, 'Haste', 'buff', 140 }, { 43, 'Refresh', 'buff', 1500 }, { 4, 'Paralysis', 'debuff', 50 }, { 134, 'Dia', 'debuff', nil } },
    { { 102, 74 }, { 103, 152 }, { 104, 260 } });
charmed.charm = sample_record;
local SAMPLES = {
    [9] = sample_pet('Sample jug', { { 42, 'Regen', 'buff', 140 }, { 4, 'Paralysis', 'debuff', 50 } }, { { 102, 74 }, { 103, 152 }, { 104, 260 } }),
    [14] = sample_pet('Sample wyvern', { { 190, 'Magic Atk. Boost', 'buff', 140 } }, { { 162, 74 }, { 164, 500 }, { 163, 900 } }),
    [15] = sample_pet('Sample avatar', { { 33, 'Haste', 'buff', 140 }, { 80, 'STR Boost', 'buff', 170 }, { 81, 'DEX Boost', 'buff', 170 }, { 82, 'VIT Boost', 'buff', 170 },
        { 83, 'AGI Boost', 'buff', 170 }, { 84, 'INT Boost', 'buff', 170 }, { 85, 'MND Boost', 'buff', 170 }, { 86, 'CHR Boost', 'buff', 170 } },
        { { 173, 40 }, { 174, 52 }, { 170, 3 } }),
    [18] = sample_pet('Sample automaton', { { 166, 'Overdrive', 'buff', 40 } }, { { 206, 74 }, { 210, 6 }, { 205, 800 } },
        { { 300, 'Fire', 2, 40, 23 }, { 304, 'Thunder', 1, 52 } }),
};
SAMPLES[9].jug = sample_jug;
function pet.samples(now, job)
    local sample = SAMPLES[job] or charmed;
    sample.hpp, sample.mpp, sample.tp = 76, 40, 1250;
    sample_record.deadline, sample_jug.deadline = now + 754, now + 2400;
    for index, made in ipairs(sample.made_effects) do
        local row = sample.effects[index];
        row.instance, row.effect, row.name, row.kind, row.group = index, made[1], made[2], made[3], made[3];
        row.entity_id, row.entity_name, row.scope, row.sample = sample.id, sample.name, 'pet', true;
        row.status = made[4] and 'estimated' or 'unknown';
        row.deadline, row.remaining, row.total = made[4] and now + made[4] or nil, made[4], made[4] and made[4] + 40;
        row.observed_at, row.first_seen = now - 8, index;
    end
    for index, made in ipairs(sample.made_recasts) do
        local entry = sample.recasts[index];
        entry.row.remaining, entry.row.deadline, entry.row.kind = made[2], now + made[2], 'ability';
        entry.full = entry.info.recast;
    end
    for index, made in ipairs(sample.made_lines) do
        local line = sample.maneuvers[index];
        line.effect, line.name, line.count, line.status = made[1], made[2], made[3], 'server';
        line.deadline, line.percent, line.at = now + made[4], made[5], now - 12;
    end
    return sample;
end

return pet;
