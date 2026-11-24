-- The pet display's optional lines and alerts (settings.pet), each behind a tick on its Show tab that starts off: what
-- your pet is fighting and doing, how far off it is and how long it has been out; for an automaton its attachments'
-- recasts, its own cooldowns and its build; for an avatar what it takes from your MP; for a wyvern whether Healing
-- Breath would fire; for a BST what Reward would heal; and notices for low pet HP, pet TP at 1000 and a charm or jug
-- about to end. core/pet.lua owns one of these, hands it what the observer saw and asks it for the lines at each
-- refresh. ui/pet_display.lua draws a line as a name with a value or the time until its deadline. Nothing here sends
-- anything.
--
-- What the game gives: the 0x044 for a PUP holds the automaton's head, frame and twelve attachments (core/client.lua);
-- the 0x068 names what your pet attacks; a 0x028 from your pet says what it starts and finishes (core/observer.lua).
-- The recasts and cooldowns are Phoenix's (data/pets.lua), counted from what Vantage saw, so one that started before
-- Vantage loaded isn't known until it is used again.
local lines = {};
local numbers = require('ui.numbers');
local finite = numbers.finite;
local DATA = require('data.pets');
local AUTO = DATA.automaton;
local EMPTY = {};
-- A move being readied or a spell being cast shows this long with no word of its end, and the last one used this long.
local DOING, LAST = 30, 60;
-- A charm or a jug is about to end at this many seconds left.
local ENDING = 60;
-- An avatar counts as costing nothing after this long with no step down of your MP: four of the game's 3 second ticks.
local QUIET = 12;
-- The message of a start whose id is a pet ability's. Any other start of a move holds a monster skill's id (Phoenix
-- src/map/ai/states/petskill_state.cpp :90-91, mobskill_state.cpp :119-120).
local READIES_ABILITY = 326;
-- The avatars and spirits, by a key that leaves out how the client spells a name, as core/pet.lua keeps the jugs.
local function summon_key(name) return type(name) == 'string' and (name:gsub('[%s_]', '')):lower() or ''; end
local SUMMONS = {};
for _, name in ipairs(DATA.summons) do SUMMONS[summon_key(name)] = true; end
-- The jugs by the same key.
local JUGS = {};
for name in pairs(DATA.jugs) do JUGS[summon_key(name)] = true; end
-- What your pet is, told by the pet itself, for the lines that are for one kind alone: Healing Breath comes only from
-- the wyvern (scripts/globals/pets/wyvern.lua :164-189), Repair is only for the automaton
-- (scripts/globals/job_utils/puppetmaster.lua :209-210) and Reward heals only a jug pet or a charmed mob
-- (scripts/globals/job_utils/beastmaster.lua :279-288), the pets Fight and Sic command too. The automaton is the pet
-- the server's PUP status names
-- (core/client.lua). An avatar, a spirit or a jug pet goes by its name. A charmed mob keeps its own place, under 0x700,
-- and the server puts every pet it makes at 0x700 or past it (src/map/zone_entities.cpp :77, :320-324, :660-702).
-- Any other pet is a DRG main's wyvern, or the automaton of a PUP, main or support, before that status came.
local function kind_of(mine, snapshot)
    if mine.automaton then return 'automaton'; end
    local key = summon_key(mine.name);
    if SUMMONS[key] then return 'avatar'; end
    if JUGS[key] then return 'jug'; end
    if finite(mine.index) and mine.index < 0x700 then return 'charm'; end
    if snapshot.job == 14 then return 'wyvern'; end
    if snapshot.job == 18 or snapshot.sub_job == 18 then return 'automaton'; end
end
lines.kind_of = kind_of;

local field, call = require('core.guard').field, require('core.guard').call;
local function memory() return call(AshitaCore, 'GetMemoryManager'); end
local function resources() return call(AshitaCore, 'GetResourceManager'); end

-- A resource's English name, or nil.
local function name_of(resource)
    local value = field(field(resource, 'Name'), 1);
    if type(value) ~= 'string' then return nil; end
    value = value:gsub('%c', ''):match('^%s*(.-)%s*$');
    if value ~= '' and value ~= '.' then return value:sub(1, 60); end
end
local function spell_name(id) return name_of(call(resources(), 'GetSpellById', id)); end
local function ability_name(id) return name_of(call(resources(), 'GetAbilityById', id + 512)); end
local function item_name(id) return name_of(call(resources(), 'GetItemById', id)); end
-- A monster skill's name: the client lists them from 256.
local function skill_name(id)
    local text = id >= 256 and call(resources(), 'GetString', 'monsters.abilities', id - 256) or nil;
    if type(text) == 'string' then
        text = text:gsub('%c', ''):match('^%s*(.-)%s*$');
        if text ~= '' and text ~= '.' then return text:sub(1, 60); end
    end
end

-- Each attachment skill's recast, at use and at spawn, and each of the automaton's spells by kind.
local RECAST, SPAWN, SPELL_KIND = {}, {}, {};
for _, info in pairs(DATA.attachment_skills) do
    RECAST[info.skill] = info.recast;
    SPAWN[info.skill] = info.spawn or SPAWN[info.skill] or info.recast;
end
for kind, list in pairs(AUTO.spells) do
    for _, spell in ipairs(list) do SPELL_KIND[spell] = kind; end
end
-- Each attachment skill's tooltip, the one it has before its recast is known, and what it says with no maneuver up,
-- made once.
local DETAILS, UNKNOWN, NEEDS = {}, {}, {};
for _, info in pairs(DATA.attachment_skills) do
    local element = DATA.elements[info.element];
    DETAILS[info] = info.waits .. ' It fires while the automaton fights, with a ' .. element .. ' maneuver up, every ' .. info.recast .. ' seconds at most.';
    UNKNOWN[info] = DETAILS[info] .. ' Vantage loaded with the automaton out, so it knows this one once it fires or ' .. info.recast .. ' seconds have passed.';
    NEEDS[info] = 'Needs ' .. element;
end

local methods = {};
methods.__index = methods;

function lines.new()
    return setmetatable({ looked = false, seen_none = false, ready = {}, casts = {}, edges = {}, list = {}, count = 0 }, methods);
end

-- A zone change: the server makes your pet anew, so every recast it had starts over when it is seen again. Vantage
-- also clears as it loads, before this has looked for a pet, and that says nothing about one already out.
function methods:clear()
    self.id, self.seen_none = nil, self.looked;
    self.ready, self.casts, self.edges = {}, {}, {};
    self.doing, self.last, self.bash, self.ranged, self.spawned, self.loaded, self.samples = nil, nil, nil, nil, nil, nil, nil;
end

-- At each refresh, whatever is ticked: follows which pet is out. One that comes out while this watched starts every
-- attachment recast (scripts/globals/pets/automaton.lua :682-694). One already out when Vantage loaded may be part
-- way through any of them, so each is unknown until its longest has passed or it is used.
function methods:track(now, snapshot)
    self.looked = true;
    local mine = snapshot.pet;
    local id = mine and mine.id or nil;
    if id ~= self.id then
        self.id = id;
        self.ready, self.casts, self.edges = {}, {}, {};
        self.doing, self.last, self.bash, self.ranged, self.samples = nil, nil, nil, nil, nil;
        self.spawned, self.loaded = nil, nil;
        if id then
            if self.seen_none then self.spawned = now; else self.loaded = now; end
        end
    end
    if not id then self.seen_none = true; end
end

-- What the observer saw your pet start ('pet_start') or finish ('pet_action'). The server counts a cooldown from the
-- start of a spell, whether or not it is stopped later, and an attachment's recast from its use.
function methods:observe(observation, now)
    if observation.entity_id ~= self.id then return; end
    if observation.kind == 'pet_start' then
        if observation.category == 8 and not observation.stopped then
            self.casts.global = now;
            local kind = SPELL_KIND[observation.id];
            if kind then self.casts[kind] = now; end
        end
        self.doing = not observation.stopped and { category = observation.category, id = observation.id, at = now,
            ability = observation.category == 7 and observation.message == READIES_ABILITY } or nil;
    elseif observation.kind == 'pet_action' then
        self.doing = nil;
        self.last = { category = observation.category, id = observation.id, amount = observation.amount, at = now };
        if observation.category == 11 then
            if RECAST[observation.id] then self.ready[observation.id] = now + RECAST[observation.id]; end
            if observation.id == AUTO.bash_skill then self.bash = now; elseif observation.id == AUTO.ranged_skill then self.ranged = now; end
        end
    end
end

-- How many maneuvers of an element (1 fire to 8 dark) are up, at most 3, and 3 with any up under Overdrive
-- (scripts/globals/automaton.lua :531-546).
local function maneuvers(snapshot, element, raw)
    local effect, count, overdrive = 299 + element, 0, false;
    for _, held in ipairs(snapshot.self_effects or EMPTY) do
        if held.effect == effect then count = count + 1; elseif held.effect == AUTO.overdrive then overdrive = true; end
    end
    if raw then return count; end
    if count > 0 and overdrive then return 3; end
    return math.min(count, 3);
end

-- The seconds the attachments on take off (or add to) one of the automaton's cooldowns, with the maneuvers up now.
local function shift(build, snapshot, kind)
    local total, seen = 0, nil;
    for _, byte in ipairs(build.attachments or EMPTY) do
        local mod = AUTO.mods[kind] and AUTO.mods[kind][byte];
        if mod and not (mod.once and seen == mod.once) then
            seen = mod.once or seen;
            total = total + mod.sign * mod[maneuvers(snapshot, mod.element) + 1];
        end
    end
    return total;
end

local function add(self, name, value, deadline, total, warn, details)
    self.count = self.count + 1;
    local line = self.list[self.count] or {};
    self.list[self.count] = line;
    line.name, line.value, line.deadline, line.total, line.warn, line.details = name, value, deadline, total, warn, details;
end

-- The name of what a start or a finish holds: a spell, a pet ability or a monster skill. ability says a readied move's
-- id is a pet ability's, as its start said (READIES_ABILITY).
local function move_name(category, id, ability)
    if category == 8 or category == 4 then return spell_name(id); end
    if category == 13 or ability then return ability_name(id) or skill_name(id); end
    if category == 3 then return ability_name(id); end
    return skill_name(id) or ability_name(id);
end

local function fighting(self, now, mine, snapshot)
    local target = mine.target_id;
    if not target then return; end
    local unit = snapshot.entities and snapshot.entities[target] or require('core.client').resolve(target);
    local name = unit and unit.name or 'A mob';
    local hpp = unit and unit.index and call(call(memory(), 'GetEntity'), 'GetHPPercent', unit.index);
    local yours = snapshot.target and snapshot.target.id == target;
    add(self, 'Fighting', finite(hpp) and name .. ' ' .. math.floor(hpp) .. '%' or name, nil, nil, not yours,
        yours and 'What your pet is attacking, and its HP. It is your target too.'
            or 'What your pet is attacking, and its HP. It isn\'t your target.');
end

-- Each start and finish has its name looked up once, the first time its line shows.
local function doing(self, now)
    local busy, last = self.doing, self.last;
    if busy and now - busy.at < DOING then
        busy.text = busy.text or move_name(busy.category, busy.id, busy.ability) or (busy.category == 8 and 'a spell' or 'a move');
        add(self, busy.category == 8 and 'Casting' or 'Readies', busy.text, nil, nil, false,
            'What your pet has started. It shows until the game says it finished or was stopped.');
    elseif last and now - last.at < LAST then
        if not last.text then
            local name = move_name(last.category, last.id) or 'A move';
            last.text = last.amount and last.amount > 0 and name .. ' ' .. last.amount or name;
        end
        add(self, 'Last move', last.text, nil, nil, false,
            'The last spell or move your pet finished, with its damage on the first target when it did any.');
    end
end

local function distance(self, mine, snapshot, kind)
    if mine.away then
        add(self, 'Distance', 'Out of view', nil, nil, true, 'Your pet is too far off for the game to show it.');
        return;
    end
    local squared = call(call(memory(), 'GetEntity'), 'GetDistance', mine.index);
    if not finite(squared) or squared < 0 then return; end
    local yalms = math.sqrt(squared);
    -- A PUP's pet that isn't the automaton has no Repair to reach, and a DRG's that isn't the wyvern no Healing Breath.
    -- A BST's avatar or automaton has no Fight, which commands only a jug pet or a charmed mob (sql/abilities.sql :89,
    -- src/map/utils/charutils.cpp :6393-6400).
    local range = DATA.ranges[snapshot.job];
    if snapshot.job == 18 and kind ~= 'automaton' or snapshot.job == 14 and kind ~= 'wyvern'
        or snapshot.job == 9 and (kind == 'avatar' or kind == 'automaton') then range = nil; end
    local far = range and yalms > range[1] or false;
    add(self, 'Distance', ('%.1f'):format(yalms), nil, nil, far,
        range and ('How far your pet is from you, in yalms. %s needs it within about %d.'):format(range[2], range[1])
            or 'How far your pet is from you, in yalms.');
end

local function out_for(self, now, mine)
    if not finite(mine.since) then return; end
    local seconds = math.max(0, now - mine.since);
    local minutes = math.floor(seconds / 60);
    add(self, 'Out for', minutes >= 60 and ('%dh %02dm'):format(math.floor(minutes / 60), minutes % 60) or ('%d:%02d'):format(minutes, math.floor(seconds % 60)),
        nil, nil, false, 'How long your pet has been out, counted from when Vantage first saw it in this zone.');
end

-- One line for each attachment skill on the automaton: the time until it can fire again, then Ready, or the maneuver
-- it waits for. seen_skills is emptied and filled again at each call.
local seen_skills = {};
local function attachments(self, now, build, snapshot)
    local seen = seen_skills;
    for skill in pairs(seen) do seen[skill] = nil; end
    for _, byte in ipairs(build.attachments or EMPTY) do
        local info = DATA.attachment_skills[byte];
        if info and not seen[info.skill] then
            seen[info.skill] = true;
            local deadline = self.ready[info.skill] or self.spawned and self.spawned + SPAWN[info.skill] or nil;
            local unknown = not deadline and self.loaded and now < self.loaded + info.recast;
            local details = DETAILS[info];
            if deadline and deadline > now then
                add(self, info.name, nil, deadline, deadline == self.ready[info.skill] and info.recast or SPAWN[info.skill], false, details);
            elseif unknown then
                add(self, info.name, 'Not known yet', nil, nil, false, UNKNOWN[info]);
            elseif maneuvers(snapshot, info.element, true) > 0 then
                add(self, info.name, 'Ready', nil, nil, false, details);
            else
                add(self, info.name, NEEDS[info], nil, nil, true, details);
            end
        end
    end
end

local function cooldown(self, name, last, seconds, now, details)
    local deadline = last and last + seconds or nil;
    if deadline and deadline > now then add(self, name, nil, deadline, seconds, false, details);
    else add(self, name, last and 'Ready' or 'Not seen yet', nil, nil, false, details); end
end

-- The automaton's own cooldowns: its spells on a frame that casts, its shot on a Sharpshot frame and Shield Bash on a
-- Valoredge one, each less what the attachments on take off with the maneuvers up now. It acts on a tick of its own
-- of up to 3 seconds, so each is the soonest it can go.
local function cooldowns(self, now, build, snapshot)
    local about = ' An estimate: the automaton acts on a tick of up to 3 seconds, so this is the soonest it can.';
    if AUTO.casting_frames[build.frame] then
        local head = AUTO.magic[build.head];
        if head then
            cooldown(self, AUTO.kind_names.global, self.casts.global, head.global + shift(build, snapshot, 'global'), now,
                'The time between any two of the automaton\'s spells with this head, counted from when it started the last one.' .. about);
            for _, kind in ipairs(AUTO.kinds) do
                if head[kind] then
                    cooldown(self, AUTO.kind_names[kind], self.casts[kind], head[kind] + (kind == 'healing' and shift(build, snapshot, 'healing') or 0), now,
                        'The time between two of the automaton\'s spells of this kind with this head.' .. about);
                end
            end
        end
    elseif build.frame == AUTO.ranged_frame then
        local base = AUTO.ranged[build.head] or AUTO.ranged_other;
        cooldown(self, 'Ranged attack', self.ranged, base + shift(build, snapshot, 'ranged'), now,
            'The time between the automaton\'s shots with this head, less what a Drum Magazine takes off.' .. about);
    elseif build.frame == AUTO.bash_frame then
        cooldown(self, 'Shield Bash', self.bash, AUTO.bash + shift(build, snapshot, 'bash'), now,
            'The time between the automaton\'s Shield Bashes, less what a Barrier Module takes off.' .. about);
    end
end

local SKILLS, STATS = { 'Melee skill', 'Ranged skill', 'Magic skill' }, { 'STR', 'DEX', 'VIT', 'AGI', 'INT', 'MND', 'CHR' };
local FROM = 'From the automaton status the server sends you as a PUP.';
local BUILD_DETAILS, SKILL_DETAILS = 'The automaton\'s head, then its frame. ' .. FROM, 'The automaton\'s skill and its cap. ' .. FROM;
local STAT_DETAILS, PAIR_DETAILS = 'The automaton\'s stats with their bonuses. ' .. FROM, 'Two of the automaton\'s attachments. ' .. FROM;

-- Puts value at its place in seen, and says whether something else was there.
local function differs(seen, at, value)
    if seen[at] == value then return false; end
    seen[at] = value;
    return true;
end

-- Whether the build differs from the one kept in seen, and keeps this one there: the head and frame, each skill with
-- its cap, each stat with its bonus and the attachments. It goes by what the build holds, not by its table. A PUP gets
-- the page each time the automaton changes, its HP too (src/map/entities/automaton_entity.cpp :140-151), so most
-- pages bring the same build.
local function build_changed(seen, build)
    local changed = differs(seen, 1, build.head);
    changed = differs(seen, 2, build.frame) or changed;
    for index = 1, 7 do
        local skill, stat = build.skills and build.skills[index], build.stats and build.stats[index];
        changed = differs(seen, index * 4 - 1, skill and skill[1]) or changed;
        changed = differs(seen, index * 4, skill and skill[2]) or changed;
        changed = differs(seen, index * 4 + 1, stat and stat[1]) or changed;
        changed = differs(seen, index * 4 + 2, stat and stat[2]) or changed;
    end
    local count = 0;
    for slot, byte in ipairs(build.attachments or EMPTY) do
        changed = differs(seen, 30 + slot, byte) or changed;
        count = slot;
    end
    return differs(seen, 'count', count) or changed;
end

-- The automaton as the server last sent it to you: head and frame, its skills with their caps, its stats and its
-- attachments, two to a line. Their texts are kept in self.build_texts and made again only when the build changes.
-- stat_parts is filled again each time.
local stat_parts = {};
local function build_lines(self, build)
    local texts = self.build_texts or { seen = {}, skills = {}, names = {}, name_count = 0 };
    self.build_texts = texts;
    if build_changed(texts.seen, build) then
        texts.build = (DATA.heads[build.head] or 'None') .. ' / ' .. (DATA.frames[build.frame] or 'None');
        for index = 1, #SKILLS do
            local skill = build.skills and build.skills[index];
            texts.skills[index] = skill and skill[2] > 0 and skill[1] .. ' / ' .. skill[2] or nil;
        end
        local parts, count = stat_parts, 0;
        for index, name in ipairs(STATS) do
            local stat = build.stats and build.stats[index];
            if stat then count = count + 1; parts[count] = name .. ' ' .. (stat[1] + stat[2]); end
        end
        texts.low_stats = count == 7 and table.concat(parts, '  ', 1, 4) or nil;
        texts.high_stats = count == 7 and table.concat(parts, '  ', 5, 7) or nil;
        local names, at = texts.names, 0;
        for _, byte in ipairs(build.attachments or EMPTY) do
            if byte ~= 0 then
                local info = DATA.attachment_skills[byte];
                at = at + 1;
                names[at] = info and info.name or item_name(0x2100 + byte) or ('Attachment ' .. byte);
            end
        end
        for index = #names, at + 1, -1 do names[index] = nil; end
        texts.name_count = at;
    end
    add(self, 'Build', texts.build, nil, nil, false, BUILD_DETAILS);
    for index, name in ipairs(SKILLS) do
        if texts.skills[index] then add(self, name, texts.skills[index], nil, nil, false, SKILL_DETAILS); end
    end
    if texts.low_stats then
        add(self, texts.low_stats, nil, nil, nil, false, STAT_DETAILS);
        add(self, texts.high_stats, nil, nil, nil, false, STAT_DETAILS);
    end
    local names = texts.names;
    for at = 1, texts.name_count, 2 do
        add(self, names[at], names[at + 1], nil, nil, false, PAIR_DETAILS);
    end
end

-- What your avatar takes from your MP: the game takes it every 3 seconds, less your Refresh, so the step your MP most
-- often went down by lately is the cost as you play it. samples holds the last few changes of your MP. step_counts is
-- emptied and filled again at each call.
local step_counts = {};
local function upkeep(self, now, snapshot)
    local samples = self.samples;
    if not samples or not finite(snapshot.mp) then return; end
    local counts, best, most = step_counts, nil, 0;
    for step in pairs(counts) do counts[step] = nil; end
    for _, sample in ipairs(samples) do
        if now - sample.at <= 45 then
            counts[sample.step] = (counts[sample.step] or 0) + 1;
            if counts[sample.step] > most then best, most = sample.step, counts[sample.step]; end
        end
    end
    local details = 'What your MP goes down by each 3 seconds with your avatar out, measured from your own MP, so your Refresh is already taken off. Spells and pacts aren\'t counted.';
    -- Four ticks with no step down: it costs nothing now, whatever it cost before.
    if now - samples.stepped_at >= QUIET then
        add(self, 'MP cost', 'None', nil, nil, false, details);
        return;
    end
    if not best or most < 2 then
        add(self, 'MP cost', 'Measuring', nil, nil, false, details);
        return;
    end
    local seconds = snapshot.mp / best * DATA.upkeep_tick;
    local minutes = math.floor(seconds / 60);
    add(self, 'MP cost', ('%d a tick, %d:%02d left'):format(best, minutes, math.floor(seconds % 60)), nil, nil, seconds <= ENDING, details);
end

-- Follows your MP while an avatar is out, for upkeep. A step down of 30 or more is a spell or a pact, not upkeep.
local function sample_mp(self, now, snapshot)
    local mp = snapshot.mp;
    if not finite(mp) then return; end
    local samples = self.samples;
    if not samples then
        samples = { last = mp, stepped_at = now };
        self.samples = samples;
        return;
    end
    if mp ~= samples.last then
        local step = samples.last - mp;
        samples.last = mp;
        if step > 0 and step < 30 then
            if #samples >= 12 then table.remove(samples, 1); end
            samples[#samples + 1] = { step = step, at = now };
            samples.stepped_at = now;
        end
    end
end

-- The gear slots that can hold what Breath and Reward look for (data/pets.lua), so only those are read. A Drachen
-- Armet goes on the head (Phoenix sql/item_equipment.sql :2279, :4995). Reward's gear goes on the hands (:3463, :3814),
-- on the feet (:3854, :4897, :5117, :5430), in the sub slot (:5923) or in either hand (:7680). The slot column is a mask
-- of the slots by number (src/map/utils/charutils.cpp :2103): 0 main, 1 sub, 4 head, 6 hands and 8 feet
-- (src/map/entities/battle_entity.h :79-99), as the client numbers them too.
local BREATH_SLOTS, REWARD_SLOTS = { 4 }, { 0, 1, 6, 8 };
-- The item ids in the slots listed, by slot, into items, a table kept from one refresh to the next. A slot is read as
-- core/client.lua worn_items reads one.
local function worn(items, slots)
    for slot in pairs(items) do items[slot] = nil; end
    local inventory = call(memory(), 'GetInventory');
    for _, slot in ipairs(slots) do
        local index = field(call(inventory, 'GetEquippedItem', slot), 'Index');
        if finite(index) and index ~= 0 then
            local id = field(call(inventory, 'GetContainerItem', math.floor(index / 256), index % 256), 'Id');
            if finite(id) and id > 0 then items[slot] = id; end
        end
    end
end

-- Whether a spell of yours would make your wyvern use Healing Breath now, and on whom.
local function breath(self, snapshot, mine, items)
    local rules = DATA.breath;
    local kind = rules.defensive[snapshot.sub_job] and 'defensive' or rules.multipurpose[snapshot.sub_job] and 'multipurpose' or nil;
    if not kind then
        add(self, 'Breath', 'Not with this sub job', nil, nil, false,
            'A wyvern uses Healing Breath only with a sub job that casts: WHM, BLM, RDM, SMN or BLU, or PLD, DRK, BRD or NIN for you alone.');
        return;
    end
    local divisor = rules.divisor[kind];
    for _, item in pairs(items or EMPTY) do
        if rules.armets[item] then divisor = divisor - 1; break; end
    end
    local share = math.floor(100 / divisor);
    local details = ('Your wyvern uses Healing Breath when a spell of yours goes off while you are at %d%% HP or less and within %d yalms of it'):format(share, rules.range)
        .. (kind == 'defensive' and ', or else a party member is. You come first.' or '. With this sub job it heals only you.');
    local party, entities, player = call(memory(), 'GetParty'), call(memory(), 'GetEntity'), call(memory(), 'GetPlayer');
    -- You: Phoenix goes by your HP against that share of your max HP, so those are used when the game gives them, and
    -- the percent when it doesn't.
    local own, hp, most = call(party, 'GetMemberHPPercent', 0), call(party, 'GetMemberHP', 0), call(player, 'GetHPMax');
    local low;
    if finite(hp) and finite(most) and most > 0 then low = hp > 0 and hp * divisor <= most;
    else low = finite(own) and own > 0 and own <= share; end
    local squared = call(entities, 'GetDistance', mine.index);
    local reach = not mine.away and (not finite(squared) or squared <= rules.range ^ 2);
    if low and reach then
        add(self, 'Breath', 'Ready for you', nil, nil, false, details);
        return;
    end
    if kind == 'defensive' and not mine.away then
        local px, py, pz = call(entities, 'GetLocalPositionX', mine.index), call(entities, 'GetLocalPositionY', mine.index), call(entities, 'GetLocalPositionZ', mine.index);
        local placed = finite(px) and finite(py) and finite(pz);
        for slot = 1, 5 do
            local hpp, index = call(party, 'GetMemberHPPercent', slot), call(party, 'GetMemberTargetIndex', slot);
            if call(party, 'GetMemberIsActive', slot) == 1 and finite(hpp) and hpp > 0 and hpp <= share and finite(index) and index > 0 then
                local x, y, z = call(entities, 'GetLocalPositionX', index), call(entities, 'GetLocalPositionY', index), call(entities, 'GetLocalPositionZ', index);
                local near = not (placed and finite(x) and finite(y) and finite(z)) or (px - x) ^ 2 + (py - y) ^ 2 + (pz - z) ^ 2 <= rules.range ^ 2;
                if near then
                    local name = call(party, 'GetMemberName', slot);
                    add(self, 'Breath', 'Ready for ' .. (type(name) == 'string' and name ~= '' and name or 'a member'), nil, nil, false, details);
                    return;
                end
            end
        end
    end
    if low then
        add(self, 'Breath', 'Too far', nil, nil, true, details);
        return;
    end
    add(self, 'Breath', 'At ' .. share .. '% HP', nil, nil, false, details);
end

-- What Reward would heal with the pet food and gear you have on.
local function reward(self, snapshot, items)
    local food = DATA.reward.foods[snapshot.ammo or 0];
    if not food then
        add(self, 'Reward', 'No pet food', nil, nil, true, 'Reward needs pet food in your ammo slot.');
        return;
    end
    local player = call(memory(), 'GetPlayer');
    local base, bonus = call(player, 'GetStat', 5), call(player, 'GetStatModifier', 5);
    if not finite(base) or not finite(bonus) then return; end
    local heal = math.floor(food.least + food.per * (base + bonus - food.from));
    local percent = 0;
    for _, item in pairs(items or EMPTY) do percent = percent + (DATA.reward.bonus[item] or 0); end
    if percent > 0 then heal = heal + math.floor(heal * percent / 100); end
    add(self, 'Reward', 'Heals ' .. math.max(0, heal), nil, nil, false,
        'What Reward would heal with this pet food, your MND ' .. (base + bonus) .. (percent > 0 and ' and gear that adds ' .. percent .. '%' or '')
            .. ', by Phoenix\'s formula. It never heals more than your pet has lost.');
end

-- Whether a notice's line was just crossed: on now, and off when edges last had it.
local function crossed(edges, key, on)
    local was = edges[key];
    edges[key] = on;
    return on and was == false;
end

-- The notices: each fires once as its line is crossed, and again only after the pet is back on the other side.
local function alerts(self, now, config, shown, announce)
    local edges = self.edges;
    local name = shown.name or 'Your pet';
    if config.alert_hp and finite(shown.hpp) then
        if crossed(edges, 'hp', shown.hpp > 0 and shown.hpp <= config.alert_hp_percent) then
            announce('pet_hp', name .. ' is at ' .. math.floor(shown.hpp) .. '% HP', now);
        end
    end
    if config.alert_tp and finite(shown.tp) then
        if crossed(edges, 'tp', shown.tp >= DATA.sic_tp) then announce('pet_tp', name .. ' has ' .. math.floor(shown.tp) .. ' TP', now); end
    end
    if config.alert_ending then
        local charm, jug = shown.charm, shown.jug;
        local ends = charm and charm.deadline or jug and jug.deadline;
        if ends then
            if crossed(edges, 'ending', ends - now <= ENDING and ends > now) then
                announce('pet_ending', charm and 'Your charm is about to end' or name .. ' is about to leave', now);
            end
        end
    end
end

-- Whether any tick that adds a line or a notice is on.
function lines.wanted(config)
    return config.show_target or config.show_action or config.show_distance or config.show_time_out or config.show_attachments
        or config.show_cooldowns or config.show_build or config.show_upkeep or config.show_breath or config.show_reward
        or config.alert_hp or config.alert_tp or config.alert_ending or false;
end

-- At each refresh with the display on and a pet out: fills shown.lines and shown.line_count from what is ticked, and
-- raises the notices that are due through announce(key, message, now).
function methods:fill(shown, now, config, snapshot, announce)
    self.count = 0;
    shown.lines, shown.line_count = self.list, 0;
    local mine = snapshot.pet;
    if not mine or not lines.wanted(config) then return; end
    local build = mine.automaton;
    -- Breath is for the wyvern alone, and Reward for any pet but an avatar, a wyvern or an automaton.
    local kind = (config.show_distance or config.show_breath or config.show_reward) and kind_of(mine, snapshot);
    local breathes = config.show_breath and snapshot.job == 14 and kind == 'wyvern';
    local rewards = config.show_reward and (snapshot.job == 9 or snapshot.sub_job == 9) and kind ~= 'avatar' and kind ~= 'wyvern' and kind ~= 'automaton';
    -- What you have on, for a Drachen Armet and for gear that adds to Reward.
    local items;
    if breathes or rewards then
        items = self.items or {};
        self.items = items;
        worn(items, breathes and BREATH_SLOTS or REWARD_SLOTS);
    end
    if config.show_target then fighting(self, now, mine, snapshot); end
    if config.show_action then doing(self, now); end
    if config.show_distance then distance(self, mine, snapshot, kind); end
    if config.show_time_out then out_for(self, now, mine); end
    if build and build.attachments then
        if config.show_attachments then attachments(self, now, build, snapshot); end
        if config.show_cooldowns then cooldowns(self, now, build, snapshot); end
        if config.show_build then build_lines(self, build); end
    end
    if config.show_upkeep and (snapshot.job == 15 or snapshot.sub_job == 15) and not build and SUMMONS[summon_key(mine.name)] then
        sample_mp(self, now, snapshot);
        upkeep(self, now, snapshot);
    else self.samples = nil; end
    if breathes then breath(self, snapshot, mine, items); end
    if rewards then reward(self, snapshot, items); end
    shown.line_count = self.count;
    if announce then alerts(self, now, config, shown, announce); end
end

-- The lines Sample displays show for a job, by what is ticked: made-up values of the same shape.
function lines.samples(shown, now, config, job)
    local self = lines.sample_state or lines.new();
    lines.sample_state = self;
    self.count = 0;
    shown.lines, shown.line_count = self.list, 0;
    if config.show_target then add(self, 'Fighting', 'Training Crab 63%', nil, nil, false, 'Sample.'); end
    if config.show_action then add(self, 'Last move', 'Sample move 312', nil, nil, false, 'Sample.'); end
    if config.show_distance then add(self, 'Distance', '8.4', nil, nil, false, 'Sample.'); end
    if config.show_time_out then add(self, 'Out for', '12:34', nil, nil, false, 'Sample.'); end
    if job == 18 then
        if config.show_attachments then
            add(self, 'Strobe', nil, now + 12, 30, false, 'Sample.');
            add(self, 'Shock Absorber', 'Needs Earth', nil, nil, true, 'Sample.');
            add(self, 'Flashbulb', 'Ready', nil, nil, false, 'Sample.');
        end
        if config.show_cooldowns then add(self, 'Shield Bash', nil, now + 95, 180, false, 'Sample.'); end
        if config.show_build then
            add(self, 'Build', 'Valoredge / Valoredge', nil, nil, false, 'Sample.');
            add(self, 'Melee skill', '245 / 269', nil, nil, false, 'Sample.');
        end
    end
    if job == 15 and config.show_upkeep then add(self, 'MP cost', '7 a tick, 4:20 left', nil, nil, false, 'Sample.'); end
    if job == 14 and config.show_breath then add(self, 'Breath', 'At 33% HP', nil, nil, false, 'Sample.'); end
    if job == 9 and config.show_reward then add(self, 'Reward', 'Heals 412', nil, nil, false, 'Sample.'); end
    shown.line_count = self.count;
end

return lines;
