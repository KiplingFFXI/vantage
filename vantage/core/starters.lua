-- The starter profiles: which displays a role wants. They choose what shows, never how it looks, so skins, fonts,
-- colors, sizes, positions, locks, hide rules, your own alert rules and saved profiles stay as they are.
local defaults = require('ui.defaults');
local party_defaults = require('ui.party_defaults');
local starters = {};

-- Every starter sets these, with its own changes over them, so one applied after another turns off what the last one
-- turned on. Item recasts, party list Countdowns and the overhead Other players, Other players' pets and You ticks
-- aren't here, as they're the player's own picks whatever the role. Nor are the parts of the Pet display, the icon
-- lights or the party list's strip: a starter turns those on, and the next one leaves them.
local BASE = {
    panels = {
        self_buffs = { enabled = true },
        self_debuffs = { enabled = true, dispel_light = false },
        target = { enabled = false, dispel_light = false },
        party = { enabled = false, mine_only = false, dispel_light = false },
        watch = { enabled = false, mine_only = false, dispel_light = false, list_debuffed = false },
    },
    party_ui = { enabled = false, effects = { kind = 'all', cleanse_light = false } },
    overhead = {
        enabled = true,
        units = { target = true, subtarget = true, claimed = true, watched = true, debuffed = true,
            party = false, alliance = false, pet = false },
        types = { party = { show_protect_shell = false, debuffs_party_only = false },
            pet = { buffs_mine_only = true, show_protect_shell = false, show_food = false, show_signet = false } },
    },
    party_cooldowns = { enabled = false, list = { enabled = false } },
    rolls = { enabled = false },
    pet = { enabled = true },
};
-- Spell and ability recasts, in the recast layout the player chose.
local RECASTS = {
    separate = { panels = { spell_recasts = { enabled = true }, ability_recasts = { enabled = true } } },
    combined = { panels = { recasts = { enabled = true, recast_categories = { spell = true, ability = true } } } },
};

-- The rules a starter adds. The Alerts page's Silence notice is the same rule, so it finds one a starter added.
starters.silenced = { name = 'Silenced', effect = 6, event = 'gain', scope = 'self' };
local SLEEP_ENDING = { name = 'Sleep ending', effect = 2, thresholds = { 10 }, scope = 'all' };

starters.list = {
    { id = 'melee', name = 'Melee', jobs = { 1, 2, 6, 8, 11, 12, 16 }, rules = {},
        about = 'For WAR, MNK, THF, DRK, SAM, RNG and BLU. Timers on your target and icons over mobs.',
        changes = { panels = { target = { enabled = true } } } },
    { id = 'tank', name = 'Tank', jobs = { 7, 13 }, rules = { starters.silenced },
        about = 'For PLD and NIN. Timers on your target, debuffs on the party list, icons over mobs, the party cooldown list'
            .. ' for Provoke and two-hours, and a Silenced alert.',
        changes = { panels = { target = { enabled = true } }, party_ui = { enabled = true, effects = { kind = 'debuff' } },
            party_cooldowns = { enabled = true, list = { enabled = true } } } },
    { id = 'healer', name = 'Healer', jobs = { 3 }, rules = { starters.silenced },
        about = 'For WHM. Timers for what you cast on the party, party list buffs, icons over your party with the Protect'
            .. ' and Shell you cast, debuffs you can remove light up, and a Silenced alert.',
        changes = {
            panels = { self_debuffs = { dispel_light = true }, party = { enabled = true, mine_only = true } },
            party_ui = { enabled = true, effects = { cleanse_light = true } },
            overhead = {
                units = { claimed = false, watched = false, debuffed = false, party = true, alliance = true },
                types = { party = { show_protect_shell = true, cleanse_light = true },
                    alliance = { cleanse_light = true },
                    self = { cleanse_light = true } },
            },
        } },
    { id = 'support', name = 'Support', jobs = { 10, 17 }, rules = { starters.silenced },
        about = 'For BRD and COR. Party list buffs, icons over your party and your target, the Phantom Roll display, and a'
            .. ' Silenced alert.',
        changes = { party_ui = { enabled = true },
            overhead = { units = { claimed = false, watched = false, debuffed = false, party = true } },
            rolls = { enabled = true } } },
    { id = 'crowd control', name = 'Crowd control', jobs = { 4, 5 }, rules = { starters.silenced, SLEEP_ENDING },
        about = 'For BLM and RDM. Timers on your target and on every enemy you debuff, debuffs on the party list, icons over'
            .. ' mobs, buffs you can dispel light up, and Silenced and Sleep ending alerts.',
        changes = {
            panels = { target = { enabled = true, dispel_light = true },
                watch = { enabled = true, mine_only = true, list_debuffed = true } },
            party_ui = { enabled = true, effects = { kind = 'debuff' } },
        } },
    { id = 'pet', name = 'Pet', jobs = { 9, 14, 15, 18 }, rules = { starters.silenced },
        about = 'For BST, SMN, PUP and DRG. Timers on your target, icons over mobs and your pet, all of the Pet display, and a'
            .. ' Silenced alert.',
        changes = {
            panels = { target = { enabled = true } },
            overhead = { units = { pet = true },
                types = { pet = { buffs_mine_only = false, show_protect_shell = true, show_food = true, show_signet = true } } },
            pet = { show_vitals = true, show_charm = true, show_effects = true, show_countdowns = true, show_recasts = true, show_maneuvers = true },
        } },
};

local function put(target, changes)
    for key, value in pairs(changes) do
        if type(value) == 'table' then
            target[key] = target[key] or {};
            put(target[key], value);
        else target[key] = value; end
    end
end

local function holds(target, wanted)
    for key, value in pairs(wanted) do
        if type(value) == 'table' then
            if type(target[key]) ~= 'table' or not holds(target[key], value) then return false; end
        elseif target[key] ~= value then return false; end
    end
    return true;
end

local names, by_job = {}, {};
starters.ids, starters.by_id = {}, {};
for index, entry in ipairs(starters.list) do
    names[index], starters.ids[index], starters.by_id[entry.id] = entry.name, entry.id, entry;
    for _, job in ipairs(entry.jobs) do by_job[job] = entry.id; end
    entry.full = {};
    put(entry.full, BASE);
    put(entry.full, entry.changes);
end
local CHOOSE = 'Choose ' .. table.concat(names, ', ', 1, #names - 1) .. ' or ' .. names[#names] .. '.';

-- The starter that suits a main job. A job that isn't open on Phoenix goes by Melee.
function starters.for_job(job) return by_job[job] or 'melee'; end

-- Which starter settings match, by what the starters set, or nothing. Rules don't count, as a starter never takes one
-- away.
function starters.matching(settings)
    if not holds(settings, RECASTS[settings.recast_display] or RECASTS.separate) then return nil; end
    for _, entry in ipairs(starters.list) do if holds(settings, entry.full) then return entry.id; end end
    return nil;
end

-- Starters only add rules, and skip one you have for the same effect and event, on or off, whatever it's called.
local function add_rules(result, rules)
    local held = result.alerts.rules;
    for index, template in ipairs(rules) do
        local made, found = defaults.rule('alert_' .. os.time() .. '_starter_' .. index), false;
        for key, value in pairs(template) do made[key] = defaults.copy(value); end
        for _, rule in ipairs(held) do
            found = found or rule.domain == made.domain and rule.effect == made.effect and rule.event == made.event;
        end
        if not found then held[#held + 1] = made; end
    end
end

-- A display going off ends its samples. With samples set, every display that's on shows its own, as Apply on the main page does.
local function sample(config, on, samples) config.preview = on and (samples or config.preview) == true; end

-- Settings with a starter applied, as a new table. The ones given stay as they are.
function starters.apply(settings, name, samples)
    local entry = starters.by_id[tostring(name or ''):lower()];
    if not entry then return nil, CHOOSE; end
    local result = defaults.copy(settings);
    put(result, entry.full);
    put(result, RECASTS[result.recast_display] or RECASTS.separate);
    -- Turning a timer panel on resumes them, as it does on the main page.
    result.enabled = true;
    if result.party_ui.enabled then party_defaults.ensure_strip(result.party_ui); end
    add_rules(result, entry.rules);
    -- A rule does nothing while Alerts is off.
    if #entry.rules > 0 then result.alerts.enabled = true; end
    sample(result, true, samples);
    sample(result.party_ui, result.party_ui.enabled, samples);
    sample(result.overhead, result.overhead.enabled, samples);
    sample(result.party_cooldowns, result.party_cooldowns.list.enabled, samples);
    sample(result.rolls, result.rolls.enabled, samples);
    sample(result.pet, result.pet.enabled, samples);
    return defaults.tidy(result);
end

return starters;
