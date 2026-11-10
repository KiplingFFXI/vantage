-- The six starter profiles: what each one turns on and off, what it leaves alone, the alert rules it adds, the samples
-- Apply shows, the mark for the one in use, /vg starter, and Watched enemies' Also list enemies I
-- debuff, which Crowd control turns on.
local defaults, starters, alerts = require('ui.defaults'), require('core.starters'), require('core.alerts');
local custom, hud, store = require('core.customization'), require('ui.hud'), require('core.store');
local function fresh() return defaults.tidy(defaults.make()); end;

-- The chart as the player was shown it.
local chart = {
    melee = { target = true, party = false, watch = false, list = false, mobs = true, party_icons = false, alliance = false, pet_icons = false },
    tank = { target = true, party = false, watch = false, list = 'debuff', mobs = true, party_icons = false, alliance = false, pet_icons = false },
    healer = { target = false, party = true, watch = false, list = 'all', mobs = false, party_icons = true, alliance = true, pet_icons = false },
    support = { target = false, party = false, watch = false, list = 'all', mobs = false, party_icons = true, alliance = false, pet_icons = false },
    ['crowd control'] = { target = true, party = false, watch = true, list = 'debuff', mobs = true, party_icons = false, alliance = false, pet_icons = false },
    pet = { target = true, party = false, watch = false, list = false, mobs = true, party_icons = false, alliance = false, pet_icons = true },
};
assert(#starters.ids == 6 and #starters.list == 6, 'There are six.');
for _, entry in ipairs(starters.list) do
    local want = assert(chart[entry.id], entry.id);
    local s = assert(starters.apply(fresh(), entry.name));
    assert(s.panels.self_buffs.enabled and s.panels.self_debuffs.enabled and s.panels.spell_recasts.enabled
        and s.panels.ability_recasts.enabled and s.pet.enabled and s.overhead.enabled, entry.name .. ' turns on what all six do.');
    assert(s.panels.target.enabled == want.target and s.panels.party.enabled == want.party and s.panels.watch.enabled == want.watch,
        entry.name .. ' sets its timer panels.');
    assert(s.party_ui.enabled == (want.list ~= false) and s.party_ui.effects.kind == (want.list or 'all'), entry.name .. ' sets the party list buffs.');
    local u = s.overhead.units;
    assert(u.target and u.subtarget, entry.name .. ' keeps icons on your target.');
    assert(u.claimed == want.mobs and u.watched == want.mobs and u.debuffed == want.mobs, entry.name .. ' sets the mobs.');
    assert(u.party == want.party_icons and u.alliance == want.alliance and u.pet == want.pet_icons, entry.name .. ' sets who else gets icons.');
    assert(s.party_cooldowns.list.enabled == (entry.id == 'tank') and s.party_cooldowns.enabled == (entry.id == 'tank'), entry.name .. ': the cooldown list.');
    assert(s.rolls.enabled == (entry.id == 'support'), entry.name .. ': the Phantom Roll display.');
    assert(s.overhead.types.party.show_protect_shell == (entry.id == 'healer'), entry.name .. ': Protect and Shell over heads.');
    assert(s.party_ui.effects.cleanse_light == (entry.id == 'healer') and s.panels.self_debuffs.dispel_light == (entry.id == 'healer'),
        entry.name .. ': debuff lights.');
    assert(s.panels.target.dispel_light == (entry.id == 'crowd control'), entry.name .. ': dispel lights.');
    -- Party timers and Watched enemies keep only what you cast there, so a light would have nothing to show.
    assert(s.panels.party.dispel_light == false and s.panels.watch.dispel_light == false, entry.name .. ': no light that cannot light.');
    assert(s.panels.party.mine_only == (entry.id == 'healer') and s.panels.watch.mine_only == (entry.id == 'crowd control'), entry.name .. ': only what you cast.');
    assert(s.panels.watch.list_debuffed == (entry.id == 'crowd control'), entry.name .. ': enemies you debuff.');
    local pet_type = s.overhead.types.pet;
    assert(pet_type.buffs_mine_only == (entry.id ~= 'pet') and pet_type.show_protect_shell == (entry.id == 'pet')
        and pet_type.show_food == (entry.id == 'pet') and pet_type.show_signet == (entry.id == 'pet'), entry.name .. ': everything on your pet.');
    assert(type(entry.about) == 'string' and entry.about:find('^For '), entry.name .. ' says who it suits.');
end;

-- Each turns off Only effects from job abilities, so the party displays show what the chart says.
for _, entry in ipairs(starters.list) do
    local s = fresh();
    s.panels.party.abilities_only, s.party_ui.effects.abilities_only = true, true;
    s = starters.apply(s, entry.name);
    assert(s.panels.party.abilities_only == false and s.party_ui.effects.abilities_only == false, entry.name .. ' turns it off.');
end;

-- Pet makes sure every part of its display is on. The others leave those ticks alone.
local parts = fresh();
for _, key in ipairs({ 'show_vitals', 'show_charm', 'show_effects', 'show_countdowns', 'show_recasts' }) do parts.pet[key] = false; end;
local whole = starters.apply(parts, 'Pet');
assert(whole.pet.show_vitals and whole.pet.show_charm and whole.pet.show_effects and whole.pet.show_countdowns and whole.pet.show_recasts);
assert(not starters.apply(parts, 'Melee').pet.show_recasts, 'Melee leaves them alone.');

-- Each of the 18 jobs has its starter. A job Phoenix doesn't have goes by Melee.
local jobs = { [1] = 'melee', [2] = 'melee', [3] = 'healer', [4] = 'crowd control', [5] = 'crowd control', [6] = 'melee', [7] = 'tank',
    [8] = 'melee', [9] = 'pet', [10] = 'support', [11] = 'melee', [12] = 'melee', [13] = 'tank', [14] = 'pet', [15] = 'pet',
    [16] = 'melee', [17] = 'support', [18] = 'pet' };
for job, id in pairs(jobs) do assert(starters.for_job(job) == id, 'Job ' .. job); end;
assert(starters.for_job(19) == 'melee' and starters.for_job(nil) == 'melee');
local counted = 0;
for _, entry in ipairs(starters.list) do counted = counted + #entry.jobs; end;
assert(counted == 18, 'Every job is on one list.');

-- Names go by any case, and the answer to any other name lists them.
assert(starters.apply(fresh(), 'CROWD CONTROL') and starters.apply(fresh(), 'healer'));
for _, name in ipairs({ 'Solo', 'Compact icons', '', 'nothing' }) do
    local made, why = starters.apply(fresh(), name);
    assert(made == nil and why == 'Choose Melee, Tank, Healer, Support, Crowd control or Pet.', name);
end;
assert(starters.apply(fresh(), nil) == nil);

-- Everything a starter doesn't own stays: the settings of a varied save, walked key by key.
local owned = { 'enabled', 'preview', 'panels.self_buffs.enabled', 'panels.self_debuffs.enabled', 'panels.self_debuffs.dispel_light',
    'panels.target.enabled', 'panels.target.dispel_light', 'panels.party.enabled', 'panels.party.mine_only', 'panels.party.dispel_light',
    'panels.party.abilities_only',
    'panels.watch.enabled', 'panels.watch.mine_only', 'panels.watch.dispel_light', 'panels.watch.list_debuffed',
    'panels.spell_recasts.enabled', 'panels.ability_recasts.enabled', 'party_ui.enabled', 'party_ui.preview', 'party_ui.effects.kind',
    'party_ui.effects.cleanse_light', 'party_ui.effects.abilities_only', 'overhead.enabled', 'overhead.preview', 'overhead.units.target', 'overhead.units.subtarget',
    'overhead.units.claimed', 'overhead.units.watched', 'overhead.units.debuffed', 'overhead.units.party', 'overhead.units.alliance',
    'overhead.units.pet', 'overhead.types.party.show_protect_shell', 'overhead.types.party.cleanse_light', 'overhead.types.alliance.cleanse_light',
    'overhead.types.self.cleanse_light', 'overhead.types.pet.buffs_mine_only', 'overhead.types.pet.show_protect_shell', 'overhead.types.pet.show_food',
    'overhead.types.pet.show_signet', 'overhead.types.party.debuffs_party_only', 'party_cooldowns.enabled', 'party_cooldowns.list.enabled',
    'party_cooldowns.preview', 'rolls.enabled', 'rolls.preview', 'pet.enabled', 'pet.preview', 'pet.show_vitals', 'pet.show_charm', 'pet.show_effects',
    'pet.show_countdowns', 'pet.show_recasts', 'party_ui.strips.party' };
local allowed = {};
for _, path in ipairs(owned) do allowed[path] = true; end;
local function differences(a, b, path, out)
    for key, value in pairs(a) do
        local here = (path == '' and '' or path .. '.') .. tostring(key);
        if type(value) == 'table' and type(b[key]) == 'table' then differences(value, b[key], here, out);
        elseif value ~= b[key] then out[#out + 1] = here; end;
    end;
    for key in pairs(b) do
        if a[key] == nil then out[#out + 1] = (path == '' and '' or path .. '.') .. tostring(key); end;
    end;
    return out;
end;
local function varied()
    local s = fresh();
    s.style.font, s.style.scale = 'Arial', 1.3;
    s.panels.self_buffs.mode, s.panels.self_buffs.x, s.panels.self_buffs.locked = 'expanded', 411, false;
    s.panels.target.y, s.panels.watch.mode, s.panels.party.sort = 222, 'icons', 'name';
    s.panels.item_recasts.enabled = true;
    s.party_ui.effects.timers, s.party_ui.locked = true, false;
    s.panels.party.abilities_only, s.party_ui.effects.abilities_only = true, true;
    s.overhead.units.other, s.overhead.units.other_pet, s.overhead.units.self = true, true, true;
    s.overhead.types.party.limit, s.overhead.types.mob.layout = 5, 'lines';
    s.effect_filters.rules[1] = { enabled = true, effect = 33, scope = 'all' };
    s.rolls.width, s.pet.x = 333, 77;
    s.job_profiles[3] = 'Mine';
    s.active_profile = 'Mine';
    return defaults.tidy(s);
end;
for _, entry in ipairs(starters.list) do
    local before = varied();
    local kept = store.copy(before);
    local after = assert(starters.apply(before, entry.name));
    assert(custom.equal(before, kept), entry.name .. ' leaves the settings it was given as they are.');
    -- The rules are checked below.
    local rules = before.alerts.rules; before = store.copy(before); before.alerts.rules = {};
    after = store.copy(after); after.alerts.rules = {};
    for _, path in ipairs(differences(before, after, '', {})) do
        assert(allowed[path], entry.name .. ' changes only what it owns, not ' .. path .. '.');
    end;
    assert(rules);
end;

-- One applied after another is the same as the second alone, on fresh settings and on a save with the party icons'
-- debuff filter on.
local function filtered_save()
    local s = fresh();
    s.overhead.types.party.debuffs_party_only = true;
    return s;
end;
for _, start in ipairs({ fresh, filtered_save }) do
    for _, first in ipairs(starters.ids) do
        for _, second in ipairs(starters.ids) do
            local through = starters.apply(starters.apply(start(), first), second);
            local direct = starters.apply(start(), second);
            through.alerts.rules, direct.alerts.rules = {}, {};
            assert(custom.equal(through, direct), first .. ' then ' .. second .. ' is the same as ' .. second .. '.');
        end;
    end;
end;

-- A paused panel set resumes, as turning a panel on does on Home.
local paused = fresh();
paused.enabled = false;
assert(starters.apply(paused, 'Melee').enabled == true);

-- The strip switches stay as they are, but turning the party list on with every strip off shows the Party strip.
local strips = fresh();
strips.party_ui.strips.party, strips.party_ui.strips.alliance1, strips.party_ui.strips.alliance2 = false, false, false;
assert(starters.apply(strips, 'Healer').party_ui.strips.party == true, 'The list has a strip to show.');
assert(starters.apply(strips, 'Melee').party_ui.strips.party == false, 'With the list off, nothing moves.');
local chosen = fresh();
chosen.party_ui.strips.alliance1 = false;
assert(starters.apply(chosen, 'Healer').party_ui.strips.alliance1 == false, 'A strip you turned off stays off.');

-- Recasts go in the layout you chose.
local combined = fresh();
combined.recast_display = 'combined';
combined.panels.recasts.enabled, combined.panels.recasts.recast_categories.spell, combined.panels.recasts.recast_categories.item = false, false, false;
combined.panels.spell_recasts.enabled = false;
local applied = starters.apply(combined, 'Melee');
assert(applied.recast_display == 'combined' and applied.panels.recasts.enabled and applied.panels.recasts.recast_categories.spell
    and applied.panels.recasts.recast_categories.ability and not applied.panels.recasts.recast_categories.item, 'The combined panel takes spells and abilities.');
assert(applied.panels.spell_recasts.enabled == false, 'The separate panels stay as they were.');
assert(starters.matching(applied) == 'melee');
applied.panels.recasts.recast_categories.ability = false;
assert(starters.matching(applied) == nil, 'Without abilities it is not a starter.');

-- Rules: added, once, and only added.
local function names_of(s)
    local out = {};
    for _, rule in ipairs(s.alerts.rules) do out[#out + 1] = rule.name; end;
    return table.concat(out, '|');
end;
assert(names_of(starters.apply(fresh(), 'Melee')) == '', 'Melee adds none.');
for _, name in ipairs({ 'Tank', 'Healer', 'Support', 'Pet' }) do assert(names_of(starters.apply(fresh(), name)) == 'Silenced', name); end;
local sleeper = starters.apply(fresh(), 'Crowd control');
assert(names_of(sleeper) == 'Silenced|Sleep ending');
assert(sleeper.alerts.rules[1].id ~= sleeper.alerts.rules[2].id, 'Each rule has its own id.');
local rule = sleeper.alerts.rules[2];
assert(rule.effect == 2 and rule.scope == 'all' and rule.event == 'remaining' and #rule.thresholds == 1
    and rule.thresholds[1] == 10 and rule.enabled and rule.visual and rule.sound == '', 'Sleep ending warns 10 seconds out, with no sound.');
local again = starters.apply(sleeper, 'Crowd control');
assert(names_of(again) == 'Silenced|Sleep ending', 'Applying it again adds nothing.');
assert(names_of(starters.apply(again, 'Melee')) == 'Silenced|Sleep ending', 'A starter never takes a rule away.');
-- A rule you have for that effect and event counts, on or off and whatever it's called, and stays as it is.
local own = fresh();
own.alerts.rules[1] = defaults.rule('mine');
own.alerts.rules[1].name, own.alerts.rules[1].effect, own.alerts.rules[1].enabled = 'Wake up', 2, false;
own.alerts.rules[1].scope, own.alerts.rules[1].thresholds = 'target', { 20, 5 };
own = defaults.tidy(own);
local joined = starters.apply(own, 'Crowd control');
assert(names_of(joined) == 'Wake up|Silenced', names_of(joined));
assert(joined.alerts.rules[1].enabled == false and joined.alerts.rules[1].thresholds[2] == 5 and joined.alerts.rules[1].scope == 'target', 'Your rule stays as it is.');
-- A full list keeps its 128.
local full = fresh();
for index = 1, 128 do full.alerts.rules[index] = defaults.rule('rule_' .. index); end;
full = defaults.tidy(full);
assert(#starters.apply(full, 'Healer').alerts.rules == 128);

-- Sleep ending, and the rows it reads. Sleep II and Lullaby put the same effect on a mob on Phoenix.
local function fires(rule_table, row, options)
    local engine = alerts.new();
    local view = { valid = true, rows = { row }, subjects = { { id = 7, scope = row.scope, known = true } }, context = { id = 10, zone = 1, job = 1 } };
    local opts = { watch_ids = {} };
    for key, value in pairs(options or {}) do opts[key] = value; end;
    engine:update(view, {}, { rule_table }, 0, opts);
    row.remaining = 9;
    engine:update(view, {}, { rule_table }, 1, opts);
    return #engine:drain(1) == 1;
end;
local function sleep_row(effect, scope, mine)
    return { key = '7:' .. effect, instance = 1, effect = effect, kind = 'debuff', name = 'A sleep', scope = scope or 'enemy', entity_id = 7,
        status = 'estimated', remaining = 40, total = 60, present = true, mine = mine };
end;
assert(fires(store.copy(rule), sleep_row(2)), 'Sleep ending goes for Sleep.');
assert(not fires(store.copy(rule), sleep_row(3)), 'It does not go for Poison.');

-- Watched enemies: Also list enemies I debuff.
local function watched(option, row, ids)
    local s = fresh();
    s.panels.watch.list_debuffed, s.watch_ids = option, ids or {};
    return #hud.filter_rows({ rows = { row }, context = {} }, s.panels.watch, 'watch', s) == 1;
end;
assert(fresh().panels.watch.list_debuffed == false, 'It starts off.');
assert(fresh().panels.party.list_debuffed == nil, 'It is on Watched enemies only.');
assert(watched(true, sleep_row(2, 'enemy', true)), 'It lists an enemy you debuffed.');
assert(not watched(false, sleep_row(2, 'enemy', true)), 'Off, it does not.');
assert(not watched(true, sleep_row(2, 'enemy', false)), 'Someone else\'s debuff does not list it.');
assert(not watched(true, sleep_row(2, 'party', true)), 'Nor does a debuff on the party.');
local buff = sleep_row(33, 'enemy', true);
buff.kind = 'buff';
assert(not watched(true, buff), 'Nor does a buff.');
assert(watched(false, sleep_row(2, 'enemy', false), { 7 }), 'An enemy you watch stays listed.');
-- A rule scoped to Watched enemies follows the list.
local scoped = store.copy(rule);
scoped.scope = 'watch';
assert(fires(store.copy(scoped), sleep_row(2, 'enemy', true), { list_debuffed = true }), 'Alerts follow the list.');
assert(not fires(store.copy(scoped), sleep_row(2, 'enemy', true), { list_debuffed = false }), 'Off, they do not.');
assert(not fires(store.copy(scoped), sleep_row(2, 'enemy', false), { list_debuffed = true }), 'Nor for someone else\'s.');
-- The same through the real tracker, for gained and removed too: their events say debuff in category, not kind.
local function told(event, option, ids)
    local tracked, engine, heard = require('core.tracker').new(), alerts.new(), 0;
    local made = defaults.rule('told');
    made.event, made.scope, made.effect, made.thresholds, made.cooldown = event, 'watch', 2, { 10 }, 0;
    local opts = { watch_ids = ids or {}, list_debuffed = option };
    local function frame(now, observations)
        local snap = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 4, self_known = true, self_revision = 1, self_effects = {}, party = {},
            entities = { { id = 7001, kind = 'monster', name = 'Goblin', index = 100, hp = 100, valid = true } } };
        tracked:observe(observations or {}, now, snap);
        tracked:reconcile(snap, now);
        local view = tracked:view(now, {}, snap);
        engine:update(view, tracked:drain_events(), { made }, now, opts);
        heard = heard + #engine:drain(now);
    end;
    for now = 0, 3 do frame(now); end;
    frame(4, { { kind = 'apply', entity_id = 7001, entity_name = 'Goblin', effect = 2, scope = 'enemy', source = 1001, source_name = 'Tester',
        spell = 253, duration = 30, category = 'debuff', group = 'Debuffs' } });
    for now = 5, 26 do frame(now); end;
    frame(27, { { kind = 'remove', entity_id = 7001, effect = 2, scope = 'enemy', reason = 'Observed wearoff' } });
    frame(28);
    return heard;
end;
for _, event in ipairs({ 'gain', 'remaining', 'removed' }) do
    assert(told(event, true) == 1, event .. ' follows the list: ' .. told(event, true));
    assert(told(event, false) == 0, event .. ': off, it does not.');
    assert(told(event, false, { 7001 }) == 1, event .. ': a watched enemy still tells you.');
end;
-- It keeps through a reset of filters going back, and resets with them.
local option = fresh();
option.panels.watch.list_debuffed = true;
assert(custom.reset(option, 'effects').panels.watch.list_debuffed == false, 'Reset effects and groups turns it off.');
-- A saved value that isn't true reads as off.
local odd = fresh();
odd.panels.watch.list_debuffed = 'yes';
assert(defaults.tidy(odd).panels.watch.list_debuffed == false);

-- A setup keeps what a starter set: the lights and the option, with the rest it always kept.
local setup = require('setup_fixture');
for _, name in ipairs({ 'Healer', 'Crowd control' }) do
    local s = starters.apply(fresh(), name);
    assert(setup.apply(s, { skin = 'keep', size = 'minimal', matching = false }));
    assert(starters.matching(defaults.tidy(s)) == starters.by_id[name:lower()].id, 'Apply size keeps ' .. name .. ' in use.');
end;

-- Which one is in use.
assert(starters.matching(fresh()) == nil, 'Fresh settings are none of them.');
for _, id in ipairs(starters.ids) do
    local s = starters.apply(fresh(), id);
    assert(starters.matching(s) == id, id .. ' is in use.');
    -- It goes by what shows, not by the look or the rules.
    s.style.font, s.panels.target.x, s.alerts.rules = 'Arial', 5, {};
    assert(starters.matching(s) == id, id .. ' stays in use.');
    s.panels.self_buffs.enabled = false;
    assert(starters.matching(s) == nil, 'Turning a display off leaves it.');
end;

-- Samples: only for Apply, on the displays that are on. A display going off ends its own.
for _, entry in ipairs(starters.list) do
    local s = starters.apply(fresh(), entry.name, true);
    assert(s.preview == true and s.overhead.preview == true and s.pet.preview == true, entry.name .. ' shows samples.');
    assert(s.party_ui.preview == s.party_ui.enabled and s.rolls.preview == s.rolls.enabled
        and s.party_cooldowns.preview == s.party_cooldowns.list.enabled, entry.name .. ' shows samples on what is on.');
    local plain = starters.apply(fresh(), entry.name);
    assert(not plain.preview and not plain.overhead.preview and not plain.pet.preview and not plain.party_ui.preview, entry.name .. ': no samples unasked.');
end;
-- Every timer panel a starter turns on has a sample to show, the ones that keep only what you cast too.
for _, entry in ipairs(starters.list) do
    local s = starters.apply(fresh(), entry.name, true);
    local view = hud.sample(100);
    for _, id in ipairs(defaults.panel_order) do
        if s.panels[id].enabled then
            assert(#hud.filter_rows(view, s.panels[id], id, s) > 0, entry.name .. ' shows a sample on ' .. id .. '.');
        end;
    end;
end;
-- The icons go by what the chart says, whatever the type's filters were.
local overhead = require('core.overhead');
local function kept(s, id, effect, kind, mine)
    return overhead.keeps(s.overhead.types[id], { effect = effect, kind = kind, mine = mine, present = true }) == true;
end;
local pet = starters.apply(fresh(), 'Pet');
for _, effect in ipairs({ 33, 42, 40, 41, 251, 113, 253 }) do
    assert(kept(pet, 'pet', effect, 'buff', false), 'Everything on your pet: ' .. effect);
    assert(not kept(fresh(), 'pet', effect, 'buff', false), 'Off Pet, someone else\'s stays hidden: ' .. effect);
end;
local healer = starters.apply(fresh(), 'Healer');
assert(kept(healer, 'party', 40, 'buff', true) and kept(healer, 'party', 41, 'buff', true), 'The Protect and Shell you cast.');
assert(not kept(healer, 'party', 40, 'buff', false), 'Only buffs I cast stays your pick.');
local own = fresh();
own.overhead.types.party.buffs_mine_only, own.overhead.types.party.debuffs_party_only = false, true;
local filtered = starters.apply(own, 'Healer');
assert(kept(filtered, 'party', 40, 'buff', false), 'With that off, anyone\'s.');
assert(filtered.overhead.types.party.debuffs_party_only == false, 'A mob\'s debuffs show over your party.');
assert(starters.matching(filtered) == 'healer');
local on = fresh();
on.rolls.enabled, on.rolls.preview, on.party_ui.enabled, on.party_ui.preview = true, true, true, true;
on.party_cooldowns.enabled, on.party_cooldowns.list.enabled, on.party_cooldowns.preview = true, true, true;
local ended = starters.apply(on, 'Melee');
assert(ended.rolls.preview == false and ended.party_ui.preview == false and ended.party_cooldowns.preview == false, 'Its display going off ends a sample.');
return true;
