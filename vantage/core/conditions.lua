-- When to show: when each display shows (ui/elements.lua names them). Each condition set holds your main and sub
-- jobs, a level range, Level Sync, the kinds of zone, solo or party or alliance, engaged and a pet out. Every condition
-- that is set must hold; one that names several choices holds for any of them. A display with none always shows.
-- They change only what shows: tracking and alerts go on. update reads where you are at each refresh and keeps each
-- display's result; shown answers the draws. It reads the client and sends nothing.
local conditions = {};
local numbers = require('ui.numbers');
local finite = numbers.finite;
local ZONES = require('data.zones');

conditions.jobs = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP' };
conditions.zone_kinds = { 'town', 'field', 'dungeon', 'battlefield', 'dynamis', 'limbus', 'assault', 'salvage', 'nyzul', 'ashu_talif',
    'mog_house', 'other' };
conditions.zone_names = { town = 'Towns', field = 'Fields', dungeon = 'Dungeons', battlefield = 'Battlefields', dynamis = 'Dynamis',
    limbus = 'Limbus', assault = 'Assault', salvage = 'Salvage', nyzul = 'Nyzul Isle', ashu_talif = 'The Ashu Talif',
    mog_house = 'Mog House', other = 'Other zones' };
conditions.groups = { 'solo', 'party', 'alliance' };
conditions.group_names = { solo = 'Solo', party = 'In a party', alliance = 'In an alliance' };
conditions.states = { 'any', 'yes', 'no' };
-- The Battlefield status, on from registering for a battlefield until leaving it (src/map/battlefield.cpp), and
-- Level Sync (Phoenix data/status_effects.yaml).
local BATTLEFIELD, LEVEL_SYNC = 254, 269;

local kind_of = {};
for kind, ids in pairs(ZONES) do for _, id in ipairs(ids) do kind_of[id] = kind; end end
if VANTAGE_TEST_MODE then conditions.kind_of = kind_of; end

function conditions.make()
    return { main_jobs = {}, sub_jobs = {}, level_min = 1, level_max = 99, level_sync = 'any', zones = {}, group = {},
        engaged = 'any', pet = 'any' };
end

local function table_of(value) return type(value) == 'table' and value or {}; end

local function choice(value, choices, fallback)
    for _, item in ipairs(choices) do if value == item then return value; end end
    return fallback;
end

-- Job ids kept as a map, from a map (keys may be text after a save) or a list.
local function jobs(value)
    local out = {};
    for key, on in pairs(table_of(value)) do
        local id = tonumber(key);
        if on == true and finite(id) and id >= 1 and id <= #conditions.jobs and id == math.floor(id) then out[id] = true; end
    end
    for _, id in ipairs(table_of(value)) do
        if finite(id) and id >= 1 and id <= #conditions.jobs and id == math.floor(id) then out[id] = true; end
    end
    return out;
end

local function names(value, allowed)
    local out = {};
    for _, name in ipairs(allowed) do
        if table_of(value)[name] == true then out[name] = true; end
    end
    for _, name in ipairs(table_of(value)) do
        if choice(name, allowed) then out[name] = true; end
    end
    return out;
end

function conditions.tidy(value)
    value = table_of(value);
    local out = conditions.make();
    out.main_jobs, out.sub_jobs = jobs(value.main_jobs), jobs(value.sub_jobs);
    out.level_min = numbers.clamp_round(value.level_min, 1, 99, 1);
    out.level_max = numbers.clamp_round(value.level_max, 1, 99, 99);
    if out.level_max < out.level_min then out.level_min, out.level_max = out.level_max, out.level_min; end
    out.level_sync = choice(value.level_sync, conditions.states, 'any');
    out.zones = names(value.zones, conditions.zone_kinds);
    out.group = names(value.group, conditions.groups);
    out.engaged = choice(value.engaged, conditions.states, 'any');
    out.pet = choice(value.pet, conditions.states, 'any');
    return out;
end

-- Whether any condition is set.
function conditions.any(value)
    if type(value) ~= 'table' then return false; end
    return next(value.main_jobs or {}) ~= nil or next(value.sub_jobs or {}) ~= nil or (value.level_min or 1) > 1
        or (value.level_max or 99) < 99 or value.level_sync ~= 'any' or next(value.zones or {}) ~= nil
        or next(value.group or {}) ~= nil or value.engaged ~= 'any' or value.pet ~= 'any';
end

-- Where you are, kept and refilled at each refresh. A Mog House is known from the zone-in packet that brings you there.
local place = { valid = false, job = 0, sub_job = 0, level = 0, synced = false, kind = 'other', battlefield = false,
    group = 'solo', engaged = false, pet = false };
conditions.place = place;
local in_mog_house = false;

local function index_of(object, key) return object[key]; end
local function call(object, name, ...)
    if object == nil then return nil; end
    local ok, fn = pcall(index_of, object, name);
    if not ok or type(fn) ~= 'function' then return nil; end
    local done, value = pcall(fn, object, ...);
    if done then return value; end
end
local function memory() return call(AshitaCore, 'GetMemoryManager'); end

-- The zone-in packet's login state (0x00A at 0x80, src/map/packets/s2c/0x00a_login.h) is 1 in a Mog House
-- (src/map/packets/s2c/0x00a_login.cpp :196-198).
-- Ashita hands it userdata, the tests a table.
function conditions.packet(e)
    local kind = type(e);
    if kind ~= 'userdata' and kind ~= 'table' or e.id ~= 0x00A or e.injected == true or e.blocked == true then return; end
    local data = e.data;
    if type(data) ~= 'string' or #data < 0x84 then return; end
    in_mog_house = data:byte(0x81) == 1;
end

local function has(effects, id)
    for _, effect in ipairs(effects or {}) do if effect.effect == id then return true; end end
    return false;
end

-- Fills place from a refresh's snapshot. A snapshot of no one, while zoning, keeps the last place.
function conditions.read(snapshot)
    if not snapshot or not snapshot.valid then return place; end
    place.valid = true;
    place.job, place.level = snapshot.job or 0, snapshot.level or 0;
    local player = call(memory(), 'GetPlayer');
    local sub = call(player, 'GetSubJob');
    place.sub_job = finite(sub) and sub or 0;
    place.synced = has(snapshot.self_effects, LEVEL_SYNC);
    place.battlefield = has(snapshot.self_effects, BATTLEFIELD);
    place.kind = in_mog_house and 'mog_house' or kind_of[snapshot.zone] or 'other';
    local party, alliance = false, false;
    for _, member in ipairs(snapshot.party or {}) do
        if member.scope == 'alliance' then alliance = true; else party = true; end
    end
    place.group = alliance and 'alliance' or party and 'party' or 'solo';
    place.engaged = snapshot.combat == true;
    place.pet = snapshot.pet ~= nil;
    return place;
end

local function state_holds(state, value)
    return state == 'any' or (state == 'yes') == value;
end

-- Whether a condition set holds at place.
function conditions.holds(value, at)
    at = at or place;
    if type(value) ~= 'table' then return true; end
    if not at.valid then return true; end
    if next(value.main_jobs) ~= nil and not value.main_jobs[at.job] then return false; end
    if next(value.sub_jobs) ~= nil and not value.sub_jobs[at.sub_job] then return false; end
    if (value.level_min > 1 or value.level_max < 99) and (at.level < value.level_min or at.level > value.level_max) then return false; end
    if not state_holds(value.level_sync, at.synced) then return false; end
    if next(value.zones) ~= nil and not value.zones[at.kind] and not (at.battlefield and value.zones.battlefield) then return false; end
    if next(value.group) ~= nil and not value.group[at.group] then return false; end
    if not state_holds(value.engaged, at.engaged) then return false; end
    if not state_holds(value.pet, at.pet) then return false; end
    return true;
end

-- Each display's result from the last refresh, by id; one never worked out shows.
local hidden = {};
conditions.hidden = hidden;

function conditions.update(settings, snapshot)
    conditions.read(snapshot);
    local elements = require('ui.elements');
    for _, element in ipairs(elements.list) do
        local value = element.conditions and elements.conditions(settings, element.id);
        hidden[element.id] = value ~= nil and conditions.any(value) and not conditions.holds(value) or nil;
    end
end

function conditions.shown(id)
    return not hidden[id];
end

local function list(words)
    if #words <= 1 then return words[1] or ''; end
    return table.concat(words, ', ', 1, #words - 1) .. ' or ' .. words[#words];
end

local function job_names(set)
    local out = {};
    for id, name in ipairs(conditions.jobs) do if set[id] then out[#out + 1] = name; end end
    return list(out);
end

-- The conditions in plain words: what must hold, one line each, or that it always shows.
function conditions.describe(value)
    if not conditions.any(value) then return { 'always shows.' }; end
    local out = {};
    if next(value.main_jobs) ~= nil then out[#out + 1] = 'Main job ' .. job_names(value.main_jobs) .. '.'; end
    if next(value.sub_jobs) ~= nil then out[#out + 1] = 'Support job ' .. job_names(value.sub_jobs) .. '.'; end
    if value.level_min > 1 or value.level_max < 99 then
        out[#out + 1] = value.level_min == value.level_max and 'Level ' .. value.level_min .. '.'
            or 'Level ' .. value.level_min .. ' to ' .. value.level_max .. '.';
    end
    if value.level_sync ~= 'any' then out[#out + 1] = value.level_sync == 'yes' and 'While Level Synced.' or 'While not Level Synced.'; end
    if next(value.zones) ~= nil then
        local words = {};
        for _, kind in ipairs(conditions.zone_kinds) do if value.zones[kind] then words[#words + 1] = conditions.zone_names[kind]; end end
        out[#out + 1] = 'In ' .. list(words) .. '.';
    end
    if next(value.group) ~= nil then
        local words = {};
        for _, kind in ipairs(conditions.groups) do if value.group[kind] then words[#words + 1] = conditions.group_names[kind]:lower(); end end
        out[#out + 1] = 'While ' .. list(words) .. '.';
    end
    if value.engaged ~= 'any' then out[#out + 1] = value.engaged == 'yes' and 'While engaged.' or 'While not engaged.'; end
    if value.pet ~= 'any' then out[#out + 1] = value.pet == 'yes' and 'With a pet out.' or 'With no pet out.'; end
    return out;
end

-- Where you are now, in plain words, for the settings page.
local in_zone = { town = 'in a town', field = 'in a field', dungeon = 'in a dungeon', dynamis = 'in Dynamis', limbus = 'in Limbus',
    assault = 'in Assault', salvage = 'in Salvage', nyzul = 'in Nyzul Isle', ashu_talif = 'on The Ashu Talif', mog_house = 'in a Mog House',
    other = 'in another zone' };
function conditions.where()
    if not place.valid then return 'Waiting for your character.'; end
    local job, sub = conditions.jobs[place.job] or tostring(place.job), conditions.jobs[place.sub_job];
    local words = { job .. ' ' .. tostring(place.level) .. (sub and ' / ' .. sub or ''), in_zone[place.kind] or in_zone.other };
    if place.battlefield then words[#words + 1] = 'in a battlefield'; end
    if place.synced then words[#words + 1] = 'Level Synced'; end
    words[#words + 1] = conditions.group_names[place.group]:lower();
    words[#words + 1] = place.engaged and 'engaged' or 'not engaged';
    words[#words + 1] = place.pet and 'pet out' or 'no pet';
    return 'Now: ' .. table.concat(words, ', ') .. '.';
end

return conditions;
