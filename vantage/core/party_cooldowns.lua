-- The party cooldown watch (settings.party_cooldowns). When Vantage sees a party or alliance member use a two-hour, a
-- key job ability or Utsusemi (data/party_cooldowns.lua), it counts down its recast for them: on their strip beside
-- the game's party list, over their head when the overhead option is on, and in the list display. Phoenix sends 0x028
-- only to those within 30 yalms of the user (src/map/zone_entities.cpp :1547, :1553), so a use farther off is never
-- seen. It zeroes the packet's recast for everything but spells (src/map/action/action.cpp :103-107), so an ability's
-- time is an estimate from its base recast, and the merits that shorten some of them are not known. A spell's is the
-- recast the game sent with it (src/map/entities/battle_entity.cpp :2462, :2693), haste and Fast Cast and all. Pets'
-- moves are not the members' own and are not watched. Nothing here sends anything.
local cooldowns = {};
local numbers = require('ui.numbers');
local finite = numbers.finite;

-- Each one watched by its id, and the spells by their own ids too. Ability ids go to 2047 and spells' after them.
local WATCHED, SPELLS = {}, {};
for _, info in ipairs(require('data.party_cooldowns')) do
    WATCHED[info.id] = info;
    if info.spell then SPELLS[info.spell] = info; end
end
cooldowns.WATCHED, cooldowns.SPELLS = WATCHED, SPELLS;
cooldowns.list = require('data.party_cooldowns');
local LAST_ID = 2048 + 1023;
-- Wild Card resets the job abilities of every party member it lands on, and on a roll of 5 or 6 their two-hour too,
-- unless their main job is COR (src/map/utils/battleutils.cpp DoWildCardToEntity :5104-5145, :5127, :5142, from
-- scripts/globals/job_utils/corsair.lua :929). A job change keeps only the two-hour
-- (src/map/char_recast_container.cpp :137-148). Both reset only abilities, so a spell's time stays through either
-- (src/map/recast_container.cpp :305-316).
cooldowns.WILD_CARD = 96;
local COR = 17;
cooldowns.sorts = { 'remaining', 'name' };
local MAX_ROWS = 64;
-- The list's least width, for its tidy, its Width row and its drag.
cooldowns.MIN_WIDTH = 160;

-- The watch is off at first, like the overhead icons, and keeps nothing until it is on. Turned on, it shows on the
-- strips.
function cooldowns.make()
    return { enabled = false, strips = true, overhead = false, ignore = {}, preview = false,
        list = { enabled = false, x = 40, y = 700, width = 300, height = 0, locked = true, max_rows = 12, sort = 'remaining',
            show_heading = true, jobs = {}, abilities = {} } };
end

-- Whether beside the party list has anywhere to draw: Party list on, with a group ticked.
function cooldowns.beside_list(settings)
    local config = settings.party_ui;
    local strips = config.strips;
    return config.enabled and (strips.party or strips.alliance1 or strips.alliance2);
end

-- Whether over heads has anyone to show them on: Overhead icons on, set to show party or alliance members.
function cooldowns.over_heads(settings)
    local config = settings.overhead;
    return config.enabled and (config.units.party or config.units.alliance);
end

-- Whether the estimates show anywhere with the displays as they are.
function cooldowns.shown(settings)
    local watch = settings.party_cooldowns;
    return watch.list.enabled or watch.strips and cooldowns.beside_list(settings) or watch.overhead and cooldowns.over_heads(settings);
end

-- Turns the watch on or off, which ends its samples. Beside the party list comes off while the party list has nowhere
-- to draw them, so turning the watch on never starts with a problem, and with nowhere to show them the list shows them.
function cooldowns.switch(settings, on)
    local watch = settings.party_cooldowns;
    watch.enabled = on;
    if not on then watch.preview = false; return; end
    if watch.strips and not cooldowns.beside_list(settings) then watch.strips = false; end
    if not cooldowns.shown(settings) then watch.list.enabled = true; end
end

-- Turns one place on or off: list, strips or overhead. Ticked while the watch is off, the estimates show there alone,
-- and with no place left the watch goes off. Unticking the list ends its samples. Over heads ticked while Overhead
-- icons shows no one in your party shows your party there (ui/overhead_defaults.lua show_party).
function cooldowns.place(settings, key, on)
    local watch = settings.party_cooldowns;
    if on and not watch.enabled then watch.list.enabled, watch.strips, watch.overhead = false, false, false; end
    if on and key == 'overhead' and not cooldowns.over_heads(settings) then require('ui.overhead_defaults').show_party(settings.overhead, true); end
    if key == 'list' then
        watch.list.enabled = on;
        if not on then watch.preview = false; end
    else watch[key] = on; end
    if on then watch.enabled = true; return; end
    if not (watch.list.enabled or watch.strips or watch.overhead) then cooldowns.switch(settings, false); end
end

local table_of, number, choice = numbers.table_of, numbers.clamp_round, numbers.choice;

-- Ids saved as a map or a list, kept as a map of the ones from low to high.
local function selection(value, low, high)
    local result = {};
    for key, on in pairs(table_of(value)) do
        local id = tonumber(key);
        if on == true and finite(id) and id >= low and id <= high and id == math.floor(id) then result[id] = true; end
    end
    for _, id in ipairs(table_of(value)) do
        if finite(id) and id >= low and id <= high and id == math.floor(id) then result[id] = true; end
    end
    return result;
end

-- Keys this doesn't know are kept, as the rest of the settings keep them.
function cooldowns.tidy(value)
    value = table_of(value);
    local fresh = cooldowns.make();
    for _, key in ipairs({ 'enabled', 'strips', 'overhead' }) do
        if type(value[key]) ~= 'boolean' then value[key] = fresh[key]; end
    end
    value.preview = value.preview == true;
    value.ignore = selection(value.ignore, 0, LAST_ID);
    local list = table_of(value.list);
    for _, key in ipairs({ 'enabled', 'locked', 'show_heading' }) do
        if type(list[key]) ~= 'boolean' then list[key] = fresh.list[key]; end
    end
    list.x = number(list.x, 0, 16000, fresh.list.x);
    list.y = number(list.y, 0, 16000, fresh.list.y);
    list.width = number(list.width, cooldowns.MIN_WIDTH, 1400, fresh.list.width);
    list.height = number(list.height, 0, 16000, 0);
    if list.height > 0 then list.height = math.max(60, list.height); end
    list.max_rows = number(list.max_rows, 1, MAX_ROWS, fresh.list.max_rows);
    list.sort = choice(list.sort, cooldowns.sorts, 'remaining');
    list.jobs = selection(list.jobs, 1, 18);
    -- The list kept abilities picked of its own once, with no way in the window to see or change them. What to count
    -- is the watch's alone now, so a save that has them shows every one again. The key stays, always empty, as share
    -- strings are read against fresh settings (core/share.lua).
    list.abilities = {};
    value.list = list;
    -- The samples show in the list, so they are kept only while it is on.
    value.preview = value.preview and value.enabled and list.enabled;
    return value;
end

-- Whether the list display shows an entry: the jobs it is filtered to, or all when none are picked.
function cooldowns.listed(list, entry)
    return next(list.jobs) == nil or list.jobs[entry.job] == true;
end

local function sooner(a, b)
    if a.deadline ~= b.deadline then return a.deadline < b.deadline; end
    if a.member_name ~= b.member_name then return a.member_name < b.member_name; end
    return a.ability < b.ability;
end
local function by_name(a, b)
    if a.member_name ~= b.member_name then return a.member_name < b.member_name; end
    return sooner(a, b);
end

local methods = {};
methods.__index = methods;

-- members: each watched member's uses by ability id, with the name and jobs last seen. shown: the entries of the
-- list display, sorted; each member's own sorted list is member.shown. estimates: member.shown by member id, for those
-- with any, for the strips and overhead blocks. The lists and the map are refilled, not made again.
function cooldowns.new()
    return setmetatable({ members = {}, shown = {}, estimates = {}, in_party = {}, job_of = {} }, methods);
end

-- One observation from core/observer.lua: a use ('cooldown', with the recast the game sent when it's a spell), a Wild
-- Card that landed on a member ('cooldown_reset', with its roll), or a Dismiss or Deactivate with the pet at full HP
-- ('cooldown_reset', with the one ability it resets).
function methods:observe(observation, now)
    local id = observation.entity_id;
    if not finite(id) or not finite(now) then return; end
    if observation.kind == 'cooldown' then
        local info = WATCHED[observation.ability];
        if not info then return; end
        local recast = info.recast;
        if info.spell then
            recast = observation.recast;
            if not finite(recast) or recast < 0 then return; end
        end
        local member = self.members[id];
        -- A spell sent with no recast is ready again, as one cast under Chainspell is
        -- (src/map/ai/states/magic_state.cpp :514-522).
        if recast == 0 then
            if member and member.uses[info.id] then member.uses[info.id] = nil; end
            return;
        end
        if not member then member = { id = id, uses = {}, shown = {} }; self.members[id] = member; end
        if type(observation.entity_name) == 'string' and observation.entity_name ~= '' then member.name = observation.entity_name; end
        member.uses[info.id] = { ability = info.id, name = info.name, job = info.job, recast = recast, special = info.special == true,
            spell = info.spell, start = now, deadline = now + recast, member = id, member_name = member.name };
    elseif observation.kind == 'cooldown_reset' and observation.ability ~= nil then
        local member = self.members[id];
        if member and member.uses[observation.ability] then
            member.uses[observation.ability] = nil;
        end
    elseif observation.kind == 'cooldown_reset' then
        local member, roll = self.members[id], observation.roll;
        if not member or not finite(roll) then return; end
        -- By the main job the party list last gave; without one, a Corsair is told by the Wild Card they used.
        for ability, use in pairs(member.uses) do
            local corsair = member.job == COR or member.job == nil and ability == cooldowns.WILD_CARD;
            if not use.spell and (not use.special or roll >= 5 and not corsair) then member.uses[ability] = nil; end
        end
    end
end

-- At each refresh: drops what ran out and what a member who left the party or changed job no longer has, then
-- refills each member's list and the list display's. party is the snapshot's party and alliance, or nil while it
-- can't be read (zoning), when nobody is dropped for being absent; roster, when it was read, gives their jobs.
function methods:refresh(now, settings, party, roster)
    local config = settings and settings.party_cooldowns;
    local shown, estimates = self.shown, self.estimates;
    for index = #shown, 1, -1 do shown[index] = nil; end
    for id in pairs(estimates) do estimates[id] = nil; end
    -- Who is in the party now and each one's jobs, by id, in tables kept from one refresh to the next.
    local present, jobs = self.in_party, self.job_of;
    for id in pairs(present) do present[id] = nil; end
    for id in pairs(jobs) do jobs[id] = nil; end
    if type(config) ~= 'table' or not config.enabled then
        if next(self.members) then self.members = {}; end
        return shown;
    end
    if party then
        for _, member in ipairs(party) do present[member.id] = member; end
    else
        present = nil;
    end
    if roster and roster.valid and roster.members then
        for _, member in ipairs(roster.members) do jobs[member.id] = member; end
    end
    local ignore, list = config.ignore, config.list;
    for id, member in pairs(self.members) do
        local here = present and present[id] or not present and member;
        local seen = jobs[id];
        if seen and finite(seen.job) and seen.job > 0 then
            -- A job change keeps only the two-hour of the abilities, and every spell. A support job that reads as none is
            -- no change. Phoenix sends none under SJ Restriction (src/map/entities/battle_entity.cpp GetSJob :1764-1772),
            -- which leaves recasts alone (scripts/effects/sj_restriction.lua), so the last one known is kept.
            if member.job and (member.job ~= seen.job or seen.subjob and member.subjob and member.subjob ~= seen.subjob) then
                for ability, use in pairs(member.uses) do if not use.special and not use.spell then member.uses[ability] = nil; end end
            end
            member.job, member.subjob = seen.job, seen.subjob or member.subjob;
        end
        local own = member.shown;
        for index = #own, 1, -1 do own[index] = nil; end
        local any = false;
        for ability, use in pairs(member.uses) do
            if use.deadline <= now or not here then member.uses[ability] = nil;
            else
                any = true;
                if here.name and here.name ~= '' then use.member_name, member.name = here.name, here.name; end
                -- One whose name hasn't come yet waits for it, as the list is sorted and labelled by name.
                if not ignore[ability] and use.member_name then
                    own[#own + 1] = use;
                    if cooldowns.listed(list, use) and #shown < 256 then shown[#shown + 1] = use; end
                end
            end
        end
        table.sort(own, sooner);
        if #own > 0 then estimates[id] = own; end
        if not any then self.members[id] = nil; end
    end
    table.sort(shown, list.sort == 'name' and by_name or sooner);
    return shown;
end

-- A member's estimates for their strip and overhead block, soonest ready first, or nil.
function methods:of(id) return self.estimates[id]; end

-- Dismiss with the wyvern at full HP makes Call Wyvern ready again, and Deactivate with the automaton at full HP makes
-- Activate ready again (data/pets.lua full_hp_resets). Their tooltips say so.
local SENT_AWAY = { [61] = 'A Dismiss with the wyvern at full HP makes it ready again, and Vantage ends the estimate when it sees one.',
    [136] = 'A Deactivate with the automaton at full HP makes it ready again, and Vantage ends the estimate when it sees one.' };

-- The tooltip of one estimate. A spell's time is the game's own, so it isn't called an estimate.
function cooldowns.details(entry, now)
    local left = math.max(0, entry.deadline - now);
    local info = WATCHED[entry.ability];
    if info and info.spell then
        local time = require('ui.countdown_text').time;
        return entry.name .. ' - ' .. (entry.member_name or '') .. '\nReady in ' .. time(left) .. '\nThe game sent its recast of '
            .. time(entry.recast) .. ' with the cast. A cast more than 30 yalms from you is not seen.';
    end
    return table.concat({ entry.name .. ' - ' .. (entry.member_name or ''),
        'Estimated ready in ' .. require('ui.countdown_text').time(left),
        'Estimated from the base recast of ' .. require('ui.countdown_text').time(entry.recast)
            .. (info and info.merits and '. Merits can make it shorter, and a use' or '. A use')
            .. ' more than 30 yalms from you is not seen.', SENT_AWAY[entry.ability] }, '\n');
end

-- What Sample displays show: a few estimates on made-up members, named as the first sample members of the party list
-- strips (ui/party_hud.lua hud.sample). The strips' samples give each member their own; an overhead sample shows all.
local samples = {};
local made = { { 'Aster', 18, 5400 }, { 'Bramble', 22, 1830 }, { 'Cinder', 74, 420 }, { 'Dawn', 61, 75 }, { 'Elm', 35, 12 } };
function cooldowns.samples(now)
    for index, entry in ipairs(made) do
        local info = WATCHED[entry[2]];
        local use = samples[index] or {};
        samples[index] = use;
        use.ability, use.name, use.job, use.recast, use.special = info.id, info.name, info.job, info.recast, info.special == true;
        use.member, use.member_name = 2000 + index, entry[1];
        use.deadline = now + entry[3];
        use.start = use.deadline - info.recast;
    end
    return samples;
end

-- The samples the list shows: those its picks let through, in its order. With none through, all of them, as a list with
-- no rows has nothing to place.
local passed = {};
function cooldowns.list_samples(config, now)
    local list = config.list;
    for index = #passed, 1, -1 do passed[index] = nil; end
    for _, use in ipairs(cooldowns.samples(now)) do
        if not config.ignore[use.ability] and cooldowns.listed(list, use) then passed[#passed + 1] = use; end
    end
    local rows = #passed > 0 and passed or samples;
    table.sort(rows, list.sort == 'name' and by_name or sooner);
    return rows;
end

return cooldowns;
