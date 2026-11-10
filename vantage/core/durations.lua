-- Duration overrides and learned durations (settings.durations). An override sets the time of an estimate: a fixed
-- number of seconds, seconds added or taken away, a percent of it, or a count up from when the effect landed, for a
-- spell, an ability or an effect, and only on one unit name when it has one. Learning keeps the times from landing to
-- wear-off of your own casts, and once a spell has enough of them on a mob name it is counted with their middle one.
-- Both change estimates only: effects on you follow the game's own timers. Nothing here reads or sends a packet.
local durations = {};
local numbers = require('ui.numbers');
local finite = numbers.finite;

durations.kinds = { 'spell', 'ability', 'effect' };
durations.modes = { 'fixed', 'add', 'percent', 'count_up' };
-- The Undo step that clears the learned times. Undo and Redo keep what was learned since a step, except this one's.
durations.CLEAR = 'Clear learned durations';
local MAX_OVERRIDES, MAX_LEARNED, MAX_SAMPLES = 128, 128, 9;
-- What made the effect, by the 0x028 category its observation names: spells 4, job abilities 6, monster skills 11 and
-- pet skills 13. Anything else, such as an added effect or an item, is known by its effect alone.
local SOURCES = { [4] = 'spell', [6] = 'ability', [11] = 'skill', [13] = 'pact' };
local LEARNED_KINDS = { spell = true, ability = true, skill = true, pact = true, effect = true };
-- Copy Image (66) shows its shadows as icons 444, 445 and 446, and every copy leaves the tracker as 66, so an effect
-- override for one of them reads as 66 too, or it would never match.
local COPY_IMAGE = { [444] = 66, [445] = 66, [446] = 66 };

function durations.override()
    return { enabled = true, kind = 'spell', id = 0, name = '', mode = 'fixed', seconds = 60, offset = 0, percent = 100 };
end

function durations.make()
    return { overrides = {}, learn = false, learn_samples = 3, learned = {} };
end

local function table_of(value) return type(value) == 'table' and value or {}; end

local function number(value, low, high, fallback, integer)
    return (integer and numbers.clamp_round or numbers.clamp)(value, low, high, fallback);
end

local function choice(value, choices, fallback)
    for _, item in ipairs(choices) do if value == item then return value; end end
    return fallback;
end

-- A unit name as the game shows one: 1 to 40 characters with no control characters, without the spaces around it.
-- Anything else is no name.
function durations.unit_name(value)
    -- Past 256 it is no name, and the trim below takes seconds on a long run of spaces.
    if type(value) ~= 'string' or #value > 256 then return ''; end
    value = value:match('^%s*(.-)%s*$');
    if #value > 40 or value:find('[%c]') then return ''; end
    return value;
end

-- The highest id each kind can name: spells and effects up to 1023, job and pet abilities up to 2047.
function durations.highest(kind) return kind == 'ability' and 2047 or 1023; end

local function sample_list(value)
    local result = {};
    for _, seconds in ipairs(table_of(value)) do
        if finite(seconds) and seconds >= 1 and seconds <= 86400 then result[#result + 1] = math.floor(seconds * 10 + 0.5) / 10; end
    end
    for index = 1, #result - MAX_SAMPLES do table.remove(result, 1); end
    return result;
end

-- Keys this doesn't know are kept, as the rest of the settings keep them.
function durations.tidy(value)
    value = table_of(value);
    value.learn = value.learn == true;
    value.learn_samples = number(value.learn_samples, 1, MAX_SAMPLES, 3, true);
    local overrides = {};
    for _, source in ipairs(table_of(value.overrides)) do
        if #overrides >= MAX_OVERRIDES then break; end
        if type(source) == 'table' then
            local rule = durations.override();
            rule.enabled = source.enabled ~= false;
            rule.kind = choice(source.kind, durations.kinds, 'spell');
            rule.id = number(source.id, 0, durations.highest(rule.kind), 0, true);
            if rule.kind == 'effect' then rule.id = COPY_IMAGE[rule.id] or rule.id; end
            rule.name = durations.unit_name(source.name);
            rule.mode = choice(source.mode, durations.modes, 'fixed');
            rule.seconds = number(source.seconds, 1, 86400, 60, true);
            rule.offset = number(source.offset, -3600, 3600, 0, true);
            rule.percent = number(source.percent, 1, 1000, 100, true);
            overrides[#overrides + 1] = require('core.store').keep_unknown(rule, source);
        end
    end
    value.overrides = overrides;
    -- Learned times by key (durations.key): up to nine samples each, newest last, and at most 128 keys, the newest kept.
    local learned, keys = {}, {};
    for key, entry in pairs(table_of(value.learned)) do
        local kind, id, effect, name;
        if type(key) == 'string' then kind, id, effect, name = key:match('^(%l+):(%d+):(%d+):(.*)$'); end
        if kind and LEARNED_KINDS[kind] and tonumber(id) <= 2047 and tonumber(effect) <= 1023 and #name <= 40
            and not name:find('[%c]') and type(entry) == 'table' then
            local samples = sample_list(entry.samples);
            if #samples > 0 then
                learned[key] = { samples = samples, unit = durations.unit_name(entry.unit),
                    at = number(entry.at, 0, 4294967295, 0, true) };
                keys[#keys + 1] = key;
            end
        end
    end
    if #keys > MAX_LEARNED then
        table.sort(keys, function(a, b) if learned[a].at ~= learned[b].at then return learned[a].at > learned[b].at; end return a < b; end);
        for index = MAX_LEARNED + 1, #keys do learned[keys[index]] = nil; end
    end
    value.learned = learned;
    return value;
end

-- Where an observation's learned times are kept: what made it, its action id, its effect and, on a mob, the mob's
-- name in lower case. Learning goes by mob name, as the client can't tell a mob's family, so a mob the game hasn't
-- named yet has no key.
function durations.key(observation)
    local kind = SOURCES[observation.action_category] or 'effect';
    local id = kind ~= 'effect' and tonumber(observation.spell) or 0;
    if not finite(id) or id < 0 or id > 2047 or id ~= math.floor(id) then return nil; end
    local name = observation.scope == 'enemy' and durations.unit_name(observation.entity_name):lower() or '';
    if observation.scope == 'enemy' and name == '' then return nil; end
    return kind .. ':' .. id .. ':' .. observation.effect .. ':' .. name;
end

-- The middle of the samples, or the mean of the middle two.
function durations.median(samples)
    local sorted = {};
    for index, seconds in ipairs(samples) do sorted[index] = seconds; end
    table.sort(sorted);
    local count = #sorted;
    if count == 0 then return nil; end
    if count % 2 == 1 then return sorted[(count + 1) / 2]; end
    return (sorted[count / 2] + sorted[count / 2 + 1]) / 2;
end

-- The learned time for an observation's key, once it has enough samples, and how many.
function durations.learned_time(config, key)
    local entry = key and table_of(config.learned)[key];
    if type(entry) ~= 'table' or type(entry.samples) ~= 'table' or #entry.samples < (config.learn_samples or 3) then return nil; end
    return durations.median(entry.samples), #entry.samples;
end

-- The override for an observation: a rule for its spell or ability goes before one for its effect, and a rule
-- with a unit name before one without; among equals the first in the list.
local function matches(rule, observation, name)
    if not rule.enabled or rule.id == 0 then return false; end
    local wanted = durations.unit_name(rule.name);
    if wanted ~= '' and wanted:lower() ~= name then return false; end
    if rule.kind == 'effect' then return observation.effect == rule.id; end
    return SOURCES[observation.action_category] == rule.kind and observation.spell == rule.id;
end
function durations.match(overrides, observation)
    local best, rank;
    local name = durations.unit_name(observation.entity_name):lower();
    for _, rule in ipairs(overrides) do
        if matches(rule, observation, name) then
            local score = (rule.kind ~= 'effect' and 2 or 0) + (durations.unit_name(rule.name) ~= '' and 1 or 0);
            if not rank or score > rank then best, rank = rule, score; end
        end
    end
    return best;
end

local function at_least_one(seconds) return math.max(1, math.floor(seconds + 0.5)); end

-- Sets the duration of each application to someone else before the tracker takes it: for a cast of yours the learned
-- time when learning has one, then the override. A cast of yours is also marked for learning. Your own effects are
-- left to the game's timers.
function durations.prepare(observations, settings, snapshot)
    local config = type(settings) == 'table' and settings.durations;
    if type(config) ~= 'table' or type(observations) ~= 'table' then return; end
    local overrides, learning = table_of(config.overrides), config.learn == true;
    if #overrides == 0 and not learning then return; end
    local self_id = type(snapshot) == 'table' and snapshot.id;
    for _, observation in ipairs(observations) do
        local kind = observation.kind;
        if kind == 'apply' and observation.entity_id ~= nil
            and observation.entity_id ~= self_id and type(observation.effect) == 'number' then
            -- The times were learned from your casts, so only your casts use them.
            -- A length Vantage already knows exactly has nothing to teach.
            local key = learning and not observation.exact and observation.source ~= nil and observation.source == self_id and durations.key(observation);
            local seconds, count = nil, nil;
            if key then seconds, count = durations.learned_time(config, key); end
            if seconds then
                observation.duration, observation.duration_min = at_least_one(seconds), at_least_one(seconds);
                observation.basis, observation.timing = 'Learned from ' .. count .. ' of your casts.', 'learned';
            end
            local rule = #overrides > 0 and durations.match(overrides, observation);
            if rule then
                local upper, lower = observation.duration, observation.duration_min or observation.duration;
                if rule.mode == 'fixed' then upper, lower = rule.seconds, rule.seconds;
                elseif rule.mode == 'add' and finite(upper) then upper, lower = at_least_one(upper + rule.offset), at_least_one(lower + rule.offset);
                elseif rule.mode == 'percent' and finite(upper) then
                    upper, lower = at_least_one(upper * rule.percent / 100), at_least_one(lower * rule.percent / 100);
                end
                if rule.mode == 'count_up' then
                    -- The estimate it hides still says how long the row stays.
                    observation.retain_for = finite(observation.duration) and observation.duration or nil;
                    observation.duration, observation.duration_min, observation.count_up = nil, nil, true;
                    observation.basis, observation.timing = 'Your duration override counts up from when it landed.', 'override';
                elseif finite(upper) then
                    -- Seconds added or a percent need an estimate to change; with none it stays without a countdown.
                    observation.duration, observation.duration_min = upper, lower;
                    observation.basis, observation.timing = 'Your duration override sets this time.', 'override';
                end
            end
            -- Learning takes the true time, whatever the override shows.
            if key then observation.learn_key = key; end
        end
    end
end

local function record(config, key, seconds, unit)
    local learned = config.learned;
    local entry = learned[key];
    if type(entry) ~= 'table' or type(entry.samples) ~= 'table' then
        entry = { samples = {}, unit = durations.unit_name(unit), at = 0 };
        learned[key] = entry;
    end
    local samples = entry.samples;
    samples[#samples + 1] = seconds;
    while #samples > MAX_SAMPLES do table.remove(samples, 1); end
    entry.at = os.time();
    local count, oldest, oldest_at = 0, nil, nil;
    for name, saved in pairs(learned) do
        count = count + 1;
        if name ~= key and (not oldest_at or saved.at < oldest_at or saved.at == oldest_at and name < oldest) then oldest, oldest_at = name, saved.at; end
    end
    if count > MAX_LEARNED and oldest then learned[oldest] = nil; end
end

-- The tracker's samples (tracker:samples): each wear-off of a row marked for learning that nothing spoiled adds its
-- time from landing, to a tenth of a second. The time ends at the wear-off's arrival, which Phoenix sends at its
-- next 400 ms check, so it reads up to 0.4 s long. Returns whether anything was learned.
function durations.learn(settings, samples)
    local config = type(settings) == 'table' and settings.durations;
    if type(config) ~= 'table' or config.learn ~= true or type(samples) ~= 'table' then return false; end
    if type(config.learned) ~= 'table' then config.learned = {}; end
    local changed = false;
    for _, sample in ipairs(samples) do
        if type(sample.learn_key) == 'string' and finite(sample.learn_start) and finite(sample.time) then
            local seconds = math.floor((sample.time - sample.learn_start) * 10 + 0.5) / 10;
            if seconds >= 1 and seconds <= 86400 then
                -- A mob's name is kept as the game shows it, for the settings page.
                local named = sample.learn_key:match('^%l+:%d+:%d+:(.*)$') ~= '';
                record(config, sample.learn_key, seconds, named and sample.entity_name or '');
                changed = true;
            end
        end
    end
    return changed;
end

return durations;
