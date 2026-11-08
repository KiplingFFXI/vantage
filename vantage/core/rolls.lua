-- The Phantom Roll display (settings.rolls). While you or a party member rolls, it shows the roll, its total, what it
-- gives you at that total, its lucky and unlucky numbers, the chance that one more Double-Up busts, the time left to
-- Double-Up, the time left on a bust, and who in the party got the roll. It reads what the game sent
-- (core/observer.lua), the roll table (data/rolls.lua) and the client's party list; it sends nothing and never says
-- what to do. ui/roll_display.lua draws it.
local rolls = {};
local numbers = require('ui.numbers');
local finite = numbers.finite;
local DATA = require('data.rolls');
-- Double-Up Chance lasts 45 s from the Phantom Roll and a Double-Up doesn't put it on again, so the window runs from
-- the roll (scripts/globals/job_utils/corsair.lua corsairSetup :432-444; modules/era/lua/globals/job_utils/corsair.lua
-- useDoubleUp :310-362). A bust takes it off (:334-337), and so does a new roll, which puts on its own.
rolls.WINDOW = 45;
local DOUBLE_UP_CHANCE, BUST, SNAKE_EYE, COR = 308, 309, 357, 17;
-- A bust lasts 300 s less 10 s for each Bust Duration rank (corsair.lua :498-513), so a bust Vantage can't time
-- leaves after that.
local BUST_TIME = 300;
local JOBS = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP' };
local MAX_ROLLS = 8;

function rolls.make()
    return { enabled = false, preview = false, x = 1300, y = 300, width = 320, height = 0, locked = true, show_heading = true,
        max_rolls = 4, show_effect = true, show_numbers = true, show_odds = true, show_members = true,
        countdown_bold = false, countdown_shadow = true, countdown_outline = false,
        countdown_outline_color = { 0, 0, 0, 1 }, lucky_color = { 0.45, 0.9, 0.45, 1 }, unlucky_color = { 1, 0.45, 0.4, 1 },
        missed_color = { 0.6, 0.6, 0.6, 1 } };
end

local function table_of(value) return type(value) == 'table' and value or {}; end

local function number(value, low, high, fallback)
    return numbers.clamp_round(value, low, high, fallback);
end

local function rgba(value, fallback)
    local color, saved = {}, table_of(value);
    for i = 1, 4 do color[i] = numbers.clamp(saved[i] or saved[tostring(i)], 0, 1, fallback[i]); end
    return color;
end

-- Keys this doesn't know are kept, as the rest of the settings keep them.
function rolls.tidy(value)
    value = table_of(value);
    local fresh = rolls.make();
    for _, key in ipairs({ 'enabled', 'locked', 'show_heading', 'show_effect', 'show_numbers', 'show_odds', 'show_members',
        'countdown_bold', 'countdown_shadow', 'countdown_outline' }) do
        if type(value[key]) ~= 'boolean' then value[key] = fresh[key]; end
    end
    value.x = number(value.x, 0, 16000, fresh.x);
    value.y = number(value.y, 0, 16000, fresh.y);
    value.width = number(value.width, 200, 1400, fresh.width);
    value.height = number(value.height, 0, 16000, 0);
    if value.height > 0 then value.height = math.max(60, value.height); end
    value.max_rolls = number(value.max_rolls, 1, MAX_ROLLS, fresh.max_rolls);
    for _, key in ipairs({ 'countdown_outline_color', 'lucky_color', 'unlucky_color', 'missed_color' }) do
        value[key] = rgba(value[key], fresh[key]);
    end
    -- The samples show in the display, so they are kept only while it is on.
    value.preview = value.preview == true and value.enabled;
    return value;
end

-- What a roll gives at a total: the table's power, the job bonus when the rules Vantage can see give it, and less
-- when the Corsair's Corsair level is below the level of who gets it, rounded up (corsair.lua applyRoll :766-841).
-- The bonus comes on a total of 11 or less with that job as a main job in the party, the Corsair's too
-- (src/map/lua/lua_base_entity.cpp hasPartyJob :11965-11996); gear can also give it at random (corsair.lua :757-760),
-- which Vantage can't see. A bust has no bonus and lands on the Corsair alone, at the Corsair's own level.
function rolls.power(info, total, bonus, cor_level, level)
    local value = total >= 12 and info.bust or info.powers[total];
    if not value then return nil; end
    if bonus and total <= 11 then value = value + info.bonus; end
    if finite(cor_level) and finite(level) and cor_level > 0 and cor_level < level then
        value = math.ceil(value * cor_level / level);
    end
    return value;
end

-- The chance, in whole percent, that one more Double-Up busts: it adds 1 to 6, and 12 or more busts (era
-- corsair.lua :331-337). With Snake Eye it adds exactly 1 (:322-329), so only 11 busts.
function rolls.odds(total, snake_eye)
    if snake_eye then return total >= 11 and 100 or 0; end
    return math.floor(math.max(0, math.min(6, total - 5)) * 100 / 6 + 0.5);
end

local methods = {};
methods.__index = methods;

-- rollers: by id, each roller's rolls by ability, as last seen. shown: the entries the display draws, newest first,
-- refilled. Each entry keeps its member list and refills it.
function rolls.new()
    return setmetatable({ rollers = {}, shown = {}, version = 0 }, methods);
end

function methods:clear()
    self.rollers = {};
    for index = #self.shown, 1, -1 do self.shown[index] = nil; end
    self.version = self.version + 1;
end

-- One 'roll' observation from core/observer.lua: a Phantom Roll, a Double-Up or a bust.
function methods:observe(observation, now)
    local id, ability, total = observation.entity_id, observation.ability, observation.total;
    local info = DATA[ability];
    if observation.kind ~= 'roll' or not info or not finite(id) or not finite(now) or not finite(total) or total < 1 then return; end
    local roller = self.rollers[id];
    if not roller then roller = { id = id, rolls = {} }; self.rollers[id] = roller; end
    if type(observation.entity_name) == 'string' and observation.entity_name ~= '' then roller.name = observation.entity_name; end
    local fresh = not observation.double_up and not observation.bust;
    local entry = roller.rolls[ability];
    if not entry or fresh then
        entry = { ability = ability, info = info, roller = id, members = {} };
        roller.rolls[ability] = entry;
    end
    if fresh then
        -- A new roll takes the Double-Up chance from the roller's other rolls.
        for other, held in pairs(roller.rolls) do
            if other ~= ability and held.window_end and held.window_end > now then held.window_end = now; end
        end
        entry.started, entry.window_end = now, now + rolls.WINDOW;
    elseif not entry.started then
        -- A Double-Up of a roll Vantage didn't see start: its window has no known end, so it stays no longer than one.
        entry.keep_until = now + rolls.WINDOW;
    end
    entry.total, entry.bust, entry.updated = math.min(12, total), observation.bust == true or total >= 12, now;
    if entry.bust then
        entry.busted_at = now;
        if entry.window_end and entry.window_end > now then entry.window_end = now; end
        entry.keep_until = nil;
    end
    entry.targets, entry.results = observation.targets or {}, observation.results or {};
    self.version = self.version + 1;
end

-- A unit's row of one effect in the view: its Double-Up Chance, Bust or Snake Eye.
local function row_of(rows, id, effect)
    for _, row in ipairs(rows) do
        if row.entity_id == id and row.effect == effect and row.domain ~= 'recast' and row.present ~= false then return row; end
    end
end

-- A Corsair main can hold two busts; the newest is the one that ends last.
local function newest_bust(rows, id)
    local found;
    for _, row in ipairs(rows) do
        if row.entity_id == id and row.effect == BUST and row.domain ~= 'recast' and row.present ~= false
            and (not found or (row.deadline or math.huge) > (found.deadline or math.huge)) then found = row; end
    end
    return found;
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
local function small(value) return finite(value) and value >= 1 and value <= 99 and math.floor(value) == value and value or nil; end

-- Your party's jobs and levels from the client's party list, by id, into jobs (refilled), and the main jobs in it into
-- mains. Yours come from the player. Returns whether anyone else is in your party, as a job bonus needs.
local mains = {};
local function read_party(snapshot, jobs)
    for key in pairs(mains) do mains[key] = nil; end
    local memory = call(AshitaCore, 'GetMemoryManager');
    local party, player = call(memory, 'GetParty'), call(memory, 'GetPlayer');
    local others = false;
    for slot = 0, 5 do
        local id = call(party, 'GetMemberServerId', slot);
        local active = slot == 0 or call(party, 'GetMemberIsActive', slot);
        if finite(id) and id > 0 and (active == nil or active == true or active == 1) then
            local member = jobs[id] or {};
            jobs[id] = member;
            member.seen = true;
            if slot == 0 or id == snapshot.id then
                member.job = small(call(player, 'GetMainJob')) or small(snapshot.job);
                member.level = small(call(player, 'GetMainJobLevel')) or small(snapshot.level);
                member.subjob, member.sublevel = small(call(player, 'GetSubJob')), small(call(player, 'GetSubJobLevel'));
            else
                others = true;
                member.job, member.level = small(call(party, 'GetMemberMainJob', slot)), small(call(party, 'GetMemberMainJobLevel', slot));
                member.subjob, member.sublevel = small(call(party, 'GetMemberSubJob', slot)), small(call(party, 'GetMemberSubJobLevel', slot));
            end
            if member.job then mains[member.job] = true; end
        end
    end
    for id, member in pairs(jobs) do
        if member.seen then member.seen = nil; else jobs[id] = nil; end
    end
    return others;
end

-- A member's Corsair level: their main level on COR, their sub level on /COR (scripts/utils/utils.lua :500-510).
local function cor_level(member)
    if not member then return nil; end
    if member.job == COR then return member.level; end
    if member.subjob == COR then return member.sublevel; end
end

local function newest(a, b)
    if a.updated ~= b.updated then return a.updated > b.updated; end
    if a.roller ~= b.roller then return a.roller < b.roller; end
    return a.ability < b.ability;
end
local function by_slot(a, b) return (a.slot or 0) < (b.slot or 0); end

local jobs, present, order, results = {}, {}, {}, {};
-- At each refresh: drops what ended, and the rolls of anyone who left the party, then works out what each roll shows.
-- rows are the view's rows. Nobody is dropped while the snapshot can't be read (zoning).
function methods:refresh(now, settings, snapshot, rows)
    local config = settings and settings.rolls;
    local shown = self.shown;
    for index = #shown, 1, -1 do shown[index] = nil; end
    if type(config) ~= 'table' or not config.enabled then
        if next(self.rollers) then self.rollers = {}; self.version = self.version + 1; end
        return shown;
    end
    local valid = snapshot and snapshot.valid and finite(snapshot.id);
    for key in pairs(present) do present[key] = nil; end
    if valid then
        present[snapshot.id] = snapshot;
        for _, member in ipairs(snapshot.party or {}) do
            if member.scope == 'party' then present[member.id] = member; end
        end
    end
    rows = rows or {};
    for id, roller in pairs(self.rollers) do
        local here = not valid or present[id] ~= nil;
        local own = valid and id == snapshot.id;
        for ability, entry in pairs(roller.rolls) do
            entry.own = own;
            -- Your own Double-Up Chance and Bust are on your buff list with the game's time. A Double-Up Chance is this
            -- roll's when it ends 45 s from it; one from the roll before can still be listed for a moment.
            local chance = own and not entry.bust and row_of(rows, id, DOUBLE_UP_CHANCE);
            if chance and chance.deadline and entry.started and math.abs(chance.deadline - entry.started - rolls.WINDOW) <= 3 then
                entry.chance_seen = true;
                if entry.window_end then entry.window_end = math.min(entry.window_end, chance.deadline); end
            elseif not chance and own and entry.chance_seen and entry.window_end and entry.window_end > now then entry.window_end = now; end
            local ends;
            if entry.bust then
                -- Shown while the bust lasts: while its row is there, or for a whole bust when Vantage never saw one.
                local bust = newest_bust(rows, id);
                entry.bust_deadline = bust and bust.deadline or nil;
                if bust then entry.bust_seen = true; end
                ends = bust and entry.busted_at + BUST_TIME + 60 or entry.bust_seen and now or entry.busted_at + BUST_TIME;
            else ends = entry.window_end or entry.keep_until or now; end
            if not here or ends <= now then
                roller.rolls[ability] = nil;
            elseif #shown < 64 then
                local member = valid and present[id];
                if member and type(member.name) == 'string' and member.name ~= '' then roller.name = member.name; end
                entry.roller_name = roller.name or 'Corsair';
                entry.snake_eye = not entry.bust and row_of(rows, id, SNAKE_EYE) ~= nil;
                shown[#shown + 1] = entry;
            end
        end
        if next(roller.rolls) == nil then self.rollers[id] = nil; end
    end
    if #shown == 0 then return shown; end
    table.sort(shown, newest);
    local party = valid and read_party(snapshot, jobs);
    for _, entry in ipairs(shown) do rolls.describe(entry, snapshot, valid and present or nil, valid and jobs or nil, party, now); end
    return shown;
end

-- Fills what an entry shows: what it gives you, the bust chance, the time left to Double-Up and who in the party got
-- it. here lists you and your party by id; party_jobs, when read, each one's jobs and levels; party, whether anyone
-- else is in your party.
function rolls.describe(entry, snapshot, here, party_jobs, party, now)
    local info, total = entry.info, entry.total;
    local you = snapshot and snapshot.id;
    local roller, own = party_jobs and party_jobs[entry.roller], party_jobs and you and party_jobs[you];
    local cor, level = cor_level(roller), nil;
    if entry.bust then
        -- A bust lands on the Corsair, at the Corsair's own main level.
        level = roller and roller.level;
        local value = rolls.power(info, 12, false, cor, level);
        entry.gives = info.busts and info.busts:format(value) or nil;
        entry.bonus, entry.odds = false, nil;
    else
        level = own and own.level;
        -- Corsair's Roll's bonus is 0, so it never counts as one.
        entry.bonus = party == true and info.bonus > 0 and mains[info.job] == true and total <= 11;
        entry.gives = info.gives:format(rolls.power(info, total, entry.bonus, cor, level));
        entry.odds = rolls.odds(total, entry.snake_eye);
    end
    entry.corrected = finite(cor) and finite(level) and cor > 0 and cor < level;
    entry.cor_level = cor;
    entry.window_deadline = not entry.bust and entry.window_end and entry.window_end > now and entry.window_end or nil;
    -- Who in the party got it, in party order: got it, no effect (another Corsair's roll is on them), lost to a bust,
    -- or not reached.
    local list = entry.members;
    for key in pairs(results) do results[key] = nil; end
    for index, id in ipairs(entry.targets or {}) do results[id] = entry.results[index]; end
    for index = #order, 1, -1 do order[index] = nil; end
    entry.yours = nil;
    for _, member in pairs(here or {}) do
        if member == snapshot or not member.zone or member.zone == snapshot.zone then order[#order + 1] = member; end
    end
    table.sort(order, by_slot);
    for index, member in ipairs(order) do
        local result = results[member.id];
        local row = list[index] or {};
        list[index] = row;
        row.id = member.id;
        row.name = member == snapshot and (snapshot.name or 'You') or member.name or 'Member';
        row.state = result == 'got' and 'got' or result == 'none' and 'none' or result == 'bust' and 'lost' or 'missed';
        if member == snapshot then entry.yours = row.state; end
    end
    for index = #list, #order + 1, -1 do list[index] = nil; end
end

-- The tooltip of one entry.
function rolls.details(entry, now)
    local countdown = require('ui.countdown_text');
    local info = entry.info;
    local lines = { info.name .. ' ' .. tostring(entry.total) .. ' - ' .. (entry.roller_name or '') };
    if entry.bust then
        lines[#lines + 1] = 'Bust.' .. (entry.gives and ' ' .. entry.gives .. ' on the Corsair'
            .. (entry.corrected and ', lowered for their level.' or '.') or ' No penalty.');
        if entry.bust_deadline and entry.bust_deadline > now then
            lines[#lines + 1] = 'The bust wears off in ' .. countdown.time(entry.bust_deadline - now)
                .. (entry.own and '.' or ', estimated.');
        end
    else
        -- A roll that didn't reach you, or found another Corsair's on you, gives you nothing.
        lines[#lines + 1] = entry.gives .. (entry.yours == 'got' and ' for you' or ' at this total')
            .. (entry.bonus and ', with ' .. info.bonus .. ' added for the ' .. JOBS[info.job] .. ' in the party' or '')
            .. (entry.corrected and '. Lowered for your level: the Corsair\'s Corsair level is ' .. tostring(entry.cor_level) or '') .. '.';
        lines[#lines + 1] = 'Lucky ' .. info.lucky .. ', unlucky ' .. info.unlucky .. '.';
        lines[#lines + 1] = 'One more Double-Up busts ' .. tostring(entry.odds) .. '% of the time'
            .. (entry.snake_eye and ', with Snake Eye on.' or '.');
        if entry.window_deadline then
            lines[#lines + 1] = 'Double-Up for ' .. countdown.time(entry.window_deadline - now)
                .. (entry.own and entry.chance_seen and '.' or ', estimated from the roll.');
        end
    end
    local got, none, missed = {}, {}, {};
    for _, member in ipairs(entry.members) do
        local into = member.state == 'got' and got or member.state == 'none' and none or missed;
        into[#into + 1] = member.name;
    end
    if #got > 0 then lines[#lines + 1] = 'Got it: ' .. table.concat(got, ', ') .. '.'; end
    if #none > 0 then lines[#lines + 1] = 'No effect, another Corsair\'s roll is on them: ' .. table.concat(none, ', ') .. '.'; end
    if #missed > 0 then lines[#lines + 1] = (entry.bust and 'Lost it or not reached: ' or 'Not reached: ') .. table.concat(missed, ', ') .. '.'; end
    lines[#lines + 1] = 'A roll reaches party members within 8 yalms of the Corsair, 16 with Luzaf\'s Ring. A roll more than 30 yalms from you is not seen.';
    return table.concat(lines, '\n');
end

-- What Sample displays show: a Chaos Roll on its lucky number and a bust, from made-up Corsairs.
local samples = {};
local made = { { 105, 4, false, 'Aster', 31, { 'got', 'got', 'none', 'missed' } },
    { 108, 12, true, 'Bramble', 240, { 'lost', 'lost', 'lost', 'missed' } } };
local sample_names = { 'You', 'Aster', 'Bramble', 'Cinder' };
function rolls.samples(now)
    for index, sample in ipairs(made) do
        local entry = samples[index] or { members = {} };
        samples[index] = entry;
        local info = DATA[sample[1]];
        entry.ability, entry.info, entry.total, entry.bust = sample[1], info, sample[2], sample[3];
        entry.roller, entry.roller_name, entry.sample = 2000 + index, sample[4], true;
        entry.updated = now - 4 * index;
        entry.window_deadline = not entry.bust and now + sample[5] or nil;
        entry.bust_deadline = entry.bust and now + sample[5] or nil;
        entry.gives = entry.bust and info.busts:format(info.bust) or info.gives:format(info.powers[entry.total]);
        entry.odds, entry.bonus, entry.corrected, entry.snake_eye = not entry.bust and rolls.odds(entry.total) or nil, false, false, false;
        for at, state in ipairs(sample[6]) do
            local member = entry.members[at] or {};
            entry.members[at] = member;
            member.id, member.name, member.state = 2100 + at, sample_names[at], state;
        end
        entry.yours = sample[6][1];
    end
    return samples;
end

return rolls;
