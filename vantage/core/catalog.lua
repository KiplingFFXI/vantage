local catalog = {};
local entries = require('data.catalog');
local durations = require('data.effects');
local actions = require('data.actions');
-- Phalanx II lasts 90 seconds plus 30 per merit (modules/phoenix/lua/globals/spells/enhancing_spell.lua :121), which the
-- exported data leaves at its first rank.
durations.merits.phalanx_ii = { id = 2310, base = 90, per_rank = 30, most = 3 };
durations.spells[107].merit = 'phalanx_ii';
-- Third Eye lasts 30 seconds and Seigan 300 (globals/job_utils/samurai.lua :115, :156), with nothing to change either, so
-- both are exact. Utsusemi takes Third Eye off (globals/spells/enhancing_ninjutsu.lua :111-114), and Third Eye has no
-- effect while Copy Image or Blink is up (samurai.lua :108-113), so one seen to land means neither is there. The exported
-- data has neither length, and those drops are in the scripts.
durations.abilities[62] = { effect = 67, seconds = 30, exact = true };
durations.abilities[174] = { effect = 354, seconds = 300, exact = true };
local copy_image = durations.effects[66].drops;
copy_image[#copy_image + 1] = 67;
durations.effects[67] = { drops = { 36, 66 } };
-- What the exported data has no row for, or has other than Phoenix plays it, from data/pets.lua: Glittering Ruby, Slowga's
-- least length, the automaton's attachments, and the mob Nightmares a hit doesn't end.
local pets = require('data.pets');
durations.pacts[515] = pets.glittering_ruby;
durations.pacts[pets.slowga.pact].seconds = pets.slowga.base;
for id, row in pairs(pets.attachments) do durations.skills[id] = row; end
for _, id in ipairs(pets.deep_sleeps) do durations.skills[id].by_effect[2].deep = true; end
local gear = require('data.gear');
local names = {};
-- How many rows catalog.get has given the client's name since load, so a list of them can tell it changed without
-- walking it.
local renamed = 0;
local sleeps = { [2] = true, [19] = true, [193] = true };
-- The client names 119 to 125 as it names 80 to 86, and a list shows only the name.
for id, name in pairs({ [119] = 'STR Boost II', [120] = 'DEX Boost II', [121] = 'VIT Boost II', [122] = 'AGI Boost II',
    [123] = 'INT Boost II', [124] = 'MND Boost II', [125] = 'CHR Boost II' }) do
    entries[id].name, names[id] = name, true;
end

function catalog.get(id)
    local row = entries[id];
    if not names[id] and AshitaCore then
        local ok, text = pcall(function () return AshitaCore:GetResourceManager():GetString('buffs.names', id); end);
        if ok and type(text) == 'string' and text ~= '' and text ~= '.' then
            row = row or { id = id, kind = 'other', group = 'Other', priority = 0 };
            entries[id], row.name, names[id] = row, text, true;
            renamed = renamed + 1;
        end
    end
    -- What nothing names doesn't exist on Phoenix, and core/tracker.lua gives it no row. Only the settings can hold its id.
    return row or { id = id, name = 'An effect with no name', kind = 'other', group = 'Other', priority = 0, unnamed = true };
end

-- Goes up each time catalog.get gives a row the client's name.
function catalog.revision() return renamed; end

function catalog.list()
    local list = {};
    -- Copy Image's icons for 2, 3 and 4 or more shadows (444 to 446) are Copy Image itself.
    for id in pairs(entries) do if id < 444 or id > 446 then list[#list + 1] = catalog.get(id); end end
    -- Without regard to case, as the client names debuffs in lowercase.
    table.sort(list, function (a, b)
        local first, second = a.name:lower(), b.name:lower();
        return first == second and a.id < b.id or first < second;
    end);
    return list;
end

function catalog.drops(id)
    return durations.effects[id] and durations.effects[id].drops or {};
end

function catalog.roll(action) return actions.rolls[action]; end

-- Whether a job ability put this effect on, with blood pacts and rolls counted as abilities. It goes by the action
-- seen to put it on (core/observer.lua). One that wasn't seen goes by data/ability_effects.lua, which leaves out the
-- effects a spell gives too.
local ability_kinds = { abilities = true, pacts = true, rolls = true };
local ability_effects = require('data.ability_effects');
function catalog.from_ability(row)
    if row.action_kind ~= nil then return ability_kinds[row.action_kind] == true; end
    return ability_effects[row.effect] == true;
end

local function matching(info, effect)
    if not info then return nil; end
    if info.by_effect then return info.by_effect[effect]; end
    if info.effect == effect or sleeps[info.effect] and sleeps[effect] then return info; end
end

function catalog.source(kind, action, effect)
    local table_ = durations[kind];
    local info = matching(table_ and table_[action], effect);
    if not info and kind == 'skills' then info = matching(durations.pacts[action], effect); end
    return info;
end

function catalog.action(kind, action)
    return durations[kind] and durations[kind][action];
end

local function sum_items(items, list)
    local total = 0;
    for _, item in pairs(items or {}) do total = total + (list and list[item] or 0); end
    return total;
end

local function modifiers(sample)
    local out = {};
    for _, item in pairs(sample and sample.items or {}) do
        for key, value in pairs(gear[item] or {}) do out[key] = (out[key] or 0) + value; end
    end
    return out;
end

function catalog.roll_duration(sample)
    local rule = actions.merits.winning_streak;
    local rank = sample and sample.merits and sample.merits[rule.id];
    if sample and ((sample.level and sample.level < 75) or (sample.job and sample.job ~= 17)) then rank = 0; end
    local extra = modifiers(sample).phantom_duration or 0;
    return 300 + (rank or rule.most) * rule.value + extra, 300 + (rank or 0) * rule.value + extra;
end

function catalog.bust_duration(sample)
    local rule = actions.merits.bust_duration;
    local rank = sample and sample.merits and sample.merits[rule.id];
    if sample and ((sample.level and sample.level < 75) or (sample.job and sample.job ~= 17)) then rank = 0; end
    return 300 - (rank or 0) * rule.value, 300 - (rank or rule.most) * rule.value;
end

-- The observed action must identify the duration rule.
function catalog.duration(kind, action, effect, sample)
    local info = catalog.source(kind, action, effect);
    if kind == 'procs' then
        if sample and sample.complete == false then return nil, nil, 'Equipment snapshot incomplete; no additional-effect duration'; end
        if sample then
            -- action is the 0x028 category here: 2 is a ranged attack, whose additional effects come from the range and
            -- ammo slots (2 and 3), and anything else from main and sub (0 and 1).
            local slots = action == 2 and { 2, 3 } or { 0, 1 };
            local value;
            for _, slot in ipairs(slots) do
                local item = (sample.items or {})[slot];
                if item and durations.proc_effects[item] == effect then
                    local candidate = durations.procs[item];
                    if value and candidate ~= value then return nil, nil, 'Additional-effect item is ambiguous'; end
                    value = candidate;
                end
            end
            return value, value, value and 'Equipped item; duration can vary' or 'No duration for this additional effect';
        end
        return nil, nil, 'No duration for this additional effect';
    end
    if not info then return nil, nil, 'No duration reported for this action'; end
    local upper, lower = info.top or info.seconds, info.seconds;
    local basis = info.top and 'Random duration range; resists may shorten it' or 'Phoenix base duration; modifiers and resists may change it';
    if info.merit then
        local rule = durations.merits[info.merit];
        local rank = sample and sample.merits and sample.merits[rule.id];
        if rank ~= nil and sample.level and sample.level < 75 then rank = 0; end
        if rank ~= nil then
            upper, lower = rule.base + rule.per_rank * rank, rule.base + rule.per_rank * rank;
            basis = 'Observed merit rank; resists may shorten it';
        else
            upper, lower = rule.base + rule.per_rank * rule.most, rule.base + rule.per_rank;
            basis = 'Merit rank not read; resists may shorten it';
        end
    end
    if not upper or upper <= 0 then return nil, nil, 'No duration for this action'; end
    local mods = modifiers(sample);
    if sample then
        if info.song then
            local bonus = sum_items(sample.items, durations.gear[info.song]) + sum_items(sample.items, durations.gear.songs);
            local extra = info.song == 'lullaby' and (mods.song_duration_bonus or 0) / 100 or 0;
            local multiplier = 1 + bonus / 10 + extra;
            if (sample.buffs or {})[durations.troubadour] then multiplier = multiplier * 2; end
            upper, lower = upper * multiplier, (lower or upper) * multiplier;
            basis = 'Observed song gear and Troubadour; resists may shorten it';
        elseif kind == 'spells' and actions.songs[action] then
            local multiplier = 1 + ((mods[actions.songs[action].modifier] or 0) + (mods.all_songs_effect or 0)) / 10
                + (mods.song_duration_bonus or 0) / 100;
            if (sample.buffs or {})[durations.troubadour] then multiplier = multiplier * 2; end
            if actions.songs[action].soul_voice_duration and (sample.buffs or {})[52] then multiplier = multiplier * 2; end
            upper, lower = upper * multiplier, (lower or upper) * multiplier;
            basis = 'Observed song gear and Troubadour; other bonuses may change it';
        elseif kind == 'spells' and actions.enhancing[action] then
            local stealth = effect == 69 or effect == 70 or effect == 71;
            local extra = effect == 42 and mods.regen_duration or sample.target_self and effect == 69 and mods.invisible_duration
                or sample.target_self and effect == 71 and mods.sneak_duration or 0;
            local multiplier = stealth and 1 or 1 + (mods.enh_magic_duration or 0) / 100;
            if effect >= 100 and effect <= 105 and sample.enhancing_skill then
                upper, lower = 150 + math.max(sample.enhancing_skill - 180, 0) * .8, 150 + math.max(sample.enhancing_skill - 180, 0) * .8;
            end
            upper, lower = upper * multiplier + (extra or 0), (lower or upper) * multiplier + (extra or 0);
            if actions.enhancing[action].composure and sample.target_self and (sample.buffs or {})[419] then
                upper, lower = upper * 3, lower * 3;
            end
            if sample.target_self and sample.level and sample.level < actions.enhancing[action].level then
                upper, lower = upper * sample.level / actions.enhancing[action].level, lower * sample.level / actions.enhancing[action].level;
            end
            basis = 'Observed base item modifiers; other bonuses may change it';
        elseif kind == 'spells' and action < 320 and (mods.enf_mag_duration or 0) ~= 0 then
            local multiplier = 1 + mods.enf_mag_duration / 100;
            upper, lower = upper * multiplier, (lower or upper) * multiplier;
        end
        if info.gear then
            local extra = sum_items(sample.items, durations.gear[info.gear]);
            upper, lower = upper + extra, (lower or upper) + extra;
        end
    end
    if sample and sample.complete == false then basis = basis .. '; equipment snapshot incomplete'; end
    return math.floor(upper), math.floor(lower or upper), basis, info;
end

return catalog;
