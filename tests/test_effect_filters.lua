local filters = require('core.effect_filters');
local copy, equal = require('core.store').copy, require('core.customization').equal;

local function same(left, right)
    if type(left) == 'number' and left ~= left then return type(right) == 'number' and right ~= right; end;
    if type(left) ~= 'table' or type(right) ~= 'table' then return left == right; end;
    for key, value in pairs(left) do if not same(value, right[key]) then return false; end; end;
    for key in pairs(right) do if left[key] == nil then return false; end; end;
    return true;
end;

local function rule(values)
    local result = filters.rule();
    for key, value in pairs(values or {}) do result[key] = value; end;
    return result;
end;

local function config(...)
    return { enabled = true, rules = { ... } };
end;

local buff = { effect = 33, kind = 'buff', remaining = 90, caster_name = 'Fennel' };
local debuff = { effect = 4, kind = 'debuff' };
local other = { effect = 269, kind = 'other' };
local self = filters.context(nil, 100, { name = 'Rowan', job = 1, scope = 'self', subjob = 3 });
local member = filters.context(nil, 101, { name = 'Fennel', job = 3, group = 1, slot = 1 });
local allied1 = filters.context(nil, 102, { name = 'Aster', job = 3, group = 2, slot = 6 });
local allied2 = filters.context(nil, 103, { name = 'Bramble', job = 2, group = 3, slot = 12 });
local outsider = filters.context(nil, 200, { name = 'Visitor', job = 3, kind = 'player' });
local npc = filters.context(nil, 300, { name = 'Fennel', job = 3, kind = 'npc' });
local monster = filters.context(nil, 301, { name = 'Fennel', job = 3, kind = 'monster' });

assert(not filters.compile(nil).active and not filters.compile(filters.make()).active);
assert(not filters.hide(config(rule({ enabled = false })), buff, member));
assert(not filters.hide({ enabled = false, rules = { rule() } }, buff, member));
assert(filters.hide(config(rule()), buff, member), 'An intentional Any effect/Everyone rule matches.');
assert(filters.hide(config(rule({ effect = 33 })), buff, member));
assert(not filters.hide(config(rule({ effect = 4 })), buff, member));

-- Corrupt restrictions must not silently become a broader rule.
local malformed = {
    false, 42, 'rule',
    { effect = false }, { effect = '33' }, { effect = -1 }, { effect = 1024 }, { effect = 1.5 },
    { effect = math.huge }, { effect = 0 / 0 },
    { job = false }, { job = '3' }, { job = -1 }, { job = 23 }, { job = 1.5 },
    { kind = false }, { kind = 'typo' }, { kind = {} },
    { scope = false }, { scope = 'typo' }, { scope = {} },
    { name = false }, { name = 101 }, { name = string.rep('a', 33) },
    { name = 'Fennel\0' }, { name = '\n' }, { name = '\tFennel' },
    { enabled = 'false' }, { enabled = 0 },
};
for index, invalid in ipairs(malformed) do
    local value = config(invalid);
    local before = copy(value);
    local clean = filters.tidy(value);
    assert(not filters.compile(clean).active and not filters.hide(value, buff, member),
        'Malformed rule ' .. index .. ' fails open.');
    assert(same(value, before), 'Normalization never rewrites its source settings.');
end;
for _, enabled in ipairs({ 'false', 0, {} }) do
    assert(not filters.hide({ enabled = enabled, rules = { rule() } }, buff, member), 'Invalid master enable values pause visibility rules.');
end;
local nil_defaults = filters.tidy({ rules = { {} } });
assert(nil_defaults.enabled and nil_defaults.rules[1].enabled and nil_defaults.rules[1].effect == 0);
assert(nil_defaults.rules[1].kind == 'all' and nil_defaults.rules[1].scope == 'all');
local mixed = config({ effect = 'bad' }, rule({ effect = 4 }), false, rule({ effect = 33, enabled = false }));
assert(filters.hide(mixed, debuff, member) and not filters.hide(mixed, buff, member));
local many = filters.make();
for index = 1, 129 do many.rules[index] = rule({ effect = index }); end;
assert(#filters.tidy(many).rules == 128);
assert(filters.hide(many, { effect = 128 }, member) and not filters.hide(many, { effect = 129 }, member));

for _, kind in ipairs({ 'buff', 'debuff', 'neutral' }) do
    local value = config(rule({ kind = kind }));
    assert(filters.hide(value, buff, member) == (kind == 'buff'));
    assert(filters.hide(value, debuff, member) == (kind == 'debuff'));
    for _, effect in ipairs({ other, { effect = 269, kind = 'neutral' }, { effect = 269 } }) do
        assert(filters.hide(value, effect, member) == (kind == 'neutral'), 'Other and unclassified statuses share the neutral category.');
    end;
end;
for _, effect in ipairs({ false, 33, {}, { effect = 0 }, { effect = 1024 }, { effect = '33' } }) do
    assert(not filters.hide(config(rule()), effect, member));
end;
for _, kind in ipairs({ 'buff', 'debuff', 'neutral' }) do
    assert(not filters.hide(config(rule()), { effect = 33, kind = kind, domain = 'recast' }, member), 'Recasts always ignore status hide rules.');
end;

local named = config(rule({ name = '  fEnNeL  ' }));
assert(filters.hide(named, buff, member));
assert(not filters.hide(named, buff, self), 'The affected name, never its caster name, decides visibility.');
for _, value in ipairs({ 'Fenneler', 'Fenn', 'NotFennel', '' }) do
    assert(not filters.hide(named, buff, filters.context(nil, 201, { kind = 'player', name = value })));
end;
assert(not filters.hide(named, buff, npc) and not filters.hide(named, buff, monster), 'NPCs and monsters never satisfy affected player-name conditions.');
assert(filters.hide(config(rule()), buff, npc), 'Unrestricted status rules can still apply to nonplayers.');
local job_rule = config(rule({ job = 3 }));
assert(filters.compile(job_rule).needs_jobs and not filters.compile(named).needs_jobs);
assert(filters.hide(job_rule, buff, member) and filters.hide(job_rule, buff, outsider));
assert(not filters.hide(job_rule, buff, self), 'A matching subjob never substitutes for main job.');
assert(not filters.hide(job_rule, buff, npc) and not filters.hide(job_rule, buff, monster));
for _, invalid_job in ipairs({ 0, -1, 23, 1.5, '3', false, math.huge, 0 / 0 }) do
    assert(not filters.hide(job_rule, buff, filters.context(nil, 201, { kind = 'player', name = 'Fennel', job = invalid_job })));
end;
assert(not filters.hide(job_rule, buff, filters.context(nil, 201, { kind = 'player', name = 'Fennel' })));

local recipients = { self, member, allied1, allied2, outsider, npc };
local expected_scopes = {
    all = { true, true, true, true, true, true },
    self = { true, false, false, false, false, false },
    party = { true, true, false, false, false, false },
    alliance = { false, false, true, true, false, false },
    alliance1 = { false, false, true, false, false, false },
    alliance2 = { false, false, false, true, false, false },
};
for scope, expected in pairs(expected_scopes) do
    for index, affected in ipairs(recipients) do
        assert(not not filters.hide(config(rule({ scope = scope })), buff, affected) == expected[index], scope .. ' recipient ' .. index);
    end;
end;
assert(filters.hide(config(rule({ scope = 'alliance1' })), buff, filters.context(nil, 201, { name = 'Slot', slot = 8 })));
assert(not filters.hide(config(rule({ scope = 'alliance1' })), buff, filters.context(nil, 201, { name = 'Slot', slot = 18 })));
local combined = config(rule({ effect = 33, kind = 'buff', name = 'Fennel', job = 3, scope = 'party' }));
assert(filters.hide(combined, buff, member));
for _, value in ipairs({ self, allied1, outsider, npc }) do assert(not filters.hide(combined, buff, value)); end;
assert(not filters.hide(combined, debuff, member));
assert(not filters.hide(combined, { effect = 33, kind = 'debuff' }, member));
assert(not filters.hide(combined, buff, filters.context(nil, 101, { name = 'Fennel', job = 2, group = 1 })));
combined.rules[2] = rule({ effect = 4, scope = 'alliance2' });
assert(filters.hide(combined, debuff, allied2) and not filters.hide(combined, debuff, allied1), 'Enabled rules combine with OR.');

-- Current roster data augments names/groups with client-known main jobs.
local snapshot = { valid = true, id = 100, zone = 230, name = 'Rowan', job = 1,
    entities = { [101] = { id = 101, name = 'Fennel', kind = 'player' },
        [200] = { id = 200, name = 'Visitor', kind = 'player', job = 3 },
        [300] = { id = 300, name = 'Fennel', kind = 'npc', job = 3 } },
    party = { { id = 101, name = 'Fennel', group = 1, slot = 1 }, { id = 102, name = 'Aster', group = 2, slot = 6 } } };
local roster = { valid = true, id = 100, zone = 230, members = {
    { id = 100, name = 'Rowan', job = 1, group = 1, slot = 0 },
    { id = 101, name = 'Fennel', job = 3, group = 1, slot = 1 },
    { id = 102, name = 'Aster', group = 2, slot = 6, available = false, same_zone = false },
    { id = 103, name = 'Bramble', job = 2, group = 3, slot = 12 },
} };
local snapshot_before, roster_before = copy(snapshot), copy(roster);
local contexts = filters.recipients(snapshot, roster);
assert(contexts[100].is_self and contexts[100].job == 1 and contexts[100].group == 1);
assert(contexts[101].job == 3 and contexts[101].scope == 'party');
assert(contexts[102].group == 2 and contexts[102].job == nil and not filters.hide(job_rule, buff, contexts[102]));
assert(contexts[103].group == 3 and contexts[200].player and not contexts[300]);
assert(filters.context(contexts, 101, { name = 'Wrong' }) == contexts[101]);
assert(equal(snapshot, snapshot_before) and equal(roster, roster_before));
local sample_contexts = filters.recipients(nil, roster);
assert(sample_contexts[100].is_self and sample_contexts[100].job == 1 and sample_contexts[100].group == 1);
assert(sample_contexts[101].job == 3 and sample_contexts[102].group == 2 and sample_contexts[103].group == 3);
for _, change in ipairs({ function(r) r.id = 999; end, function(r) r.zone = 231; end, function(r) r.valid = false; end }) do
    local stale = copy(roster); change(stale);
    local current = filters.recipients(snapshot, stale);
    assert(current[100].job == 1 and current[101].job == nil and current[103] == nil, 'Stale roster identity/zone cannot supply cached main jobs or members.');
    assert(not filters.hide(job_rule, buff, current[101]));
end;
local invalid_snapshot = copy(snapshot); invalid_snapshot.valid = false;
assert(next(filters.recipients(invalid_snapshot, roster)) == nil);
assert(next(filters.recipients(nil, { valid = false, id = 100, members = roster.members })) == nil);

-- Filtering only copies the affected containers and retains each effect object.
local status = { id = 101, name = 'Fennel', known = true, complete = false, effects = { buff, debuff, other }, observed_at = 77 };
local status_before = copy(status);
local no_match = config(rule({ effect = 253 }));
assert(filters.subject(no_match, status, member) == status);
assert(filters.subject(filters.make(), status, member) == status);
for _, id in ipairs({ 33, 4, 269 }) do
    local filtered = filters.subject(config(rule({ effect = id })), status, member);
    assert(filtered ~= status and filtered.effects ~= status.effects and #filtered.effects == 2);
    assert(filtered.id == status.id and filtered.name == status.name and filtered.known == status.known
        and filtered.complete == status.complete and filtered.observed_at == status.observed_at);
    local index = 1;
    for _, original in ipairs(status.effects) do
        if original.effect ~= id then assert(filtered.effects[index] == original); index = index + 1; end;
    end;
    assert(equal(status, status_before), 'Visibility filtering never alters tracked effects or alert evidence.');
end;
local all_hidden = filters.subject(config(rule()), status, member);
assert(#all_hidden.effects == 0 and all_hidden.complete == false and #status.effects == 3);
local untouched = { id = 102, effects = { other }, complete = true };
local subjects = { [101] = status, [102] = untouched };
assert(filters.subjects(no_match, subjects, contexts) == subjects);
local visible = filters.subjects(config(rule({ effect = 33 })), subjects, contexts);
assert(visible ~= subjects and visible[101] ~= status and visible[102] == untouched);
assert(visible[101].effects[1] == debuff and subjects[101].effects[1] == buff);
assert(filters.subjects(filters.make(), subjects, contexts) == subjects and filters.subjects(config(rule()), nil) == nil);

-- Editing in place, Undo and profile replacement cannot leave compiled rules stale.
local mutable = config(rule({ effect = 33 }));
local first = filters.compile(mutable);
assert(filters.compile(mutable) == first and filters.compile(first) == first);
assert(filters.hide(mutable, buff, member));
mutable.rules[1].effect = 4;
assert(filters.compile(mutable) ~= first and not filters.hide(mutable, buff, member) and filters.hide(mutable, debuff, member));
mutable.rules[1].enabled = false;
assert(not filters.compile(mutable).active);
mutable.rules[1].enabled, mutable.rules[1].effect = true, 33;
mutable.rules[1].name = 'Other'; assert(not filters.hide(mutable, buff, member));
mutable.rules[1].name = 'FENNEL'; assert(filters.hide(mutable, buff, member));
mutable.rules[1].job = 2; assert(filters.compile(mutable).needs_jobs and not filters.hide(mutable, buff, member));
mutable.rules[1].job = 3; assert(filters.hide(mutable, buff, member));
mutable.rules[1].scope = 'alliance'; assert(not filters.hide(mutable, buff, member));
mutable.rules[1].scope = 'party'; assert(filters.hide(mutable, buff, member));
mutable.rules[1].kind = 'debuff'; assert(not filters.hide(mutable, buff, member));
mutable.rules[1].kind = 'buff'; assert(filters.hide(mutable, buff, member));
local undo = copy(mutable);
mutable.enabled = false; assert(not filters.hide(mutable, buff, member));
mutable.enabled = true; assert(filters.hide(mutable, buff, member));
mutable.rules = { rule({ effect = 4 }) };
assert(not filters.hide(mutable, buff, member));
mutable.rules = copy(undo.rules); assert(filters.hide(mutable, buff, member), 'Undo replaces the rule table without stale compilation.');
local profile = copy(mutable);
profile.rules[1].effect = 4;
assert(not filters.hide(profile, buff, member) and filters.hide(mutable, buff, member), 'Separate profile settings have independent compiled state.');
mutable.rules[2] = rule({ effect = 253 });
assert(filters.hide(mutable, { effect = 253 }, member));
table.remove(mutable.rules, 2);
assert(not filters.hide(mutable, { effect = 253 }, member));
mutable.rules = {};
assert(not filters.compile(mutable).active);

-- Cached field snapshots still notice edits when the array length stays the same.
local cached = config(false, rule({ effect = 33 }), { name = 123 });
local cached_before = copy(cached);
local compiled = filters.compile(cached);
for index=1,10 do assert(filters.compile(cached)==compiled); end;
assert(same(cached,cached_before), 'Checking unchanged rules leaves saved settings untouched.');
cached.rules[1] = rule({ effect = 4 });
assert(filters.hide(cached,debuff,member), 'Replacing an invalid entry recompiles at the same array length.');
cached.rules[1] = false;
assert(not filters.hide(cached,debuff,member), 'Replacing a valid entry with an invalid entry clears its rule.');
cached.rules[3].name = 'Fennel';
assert(filters.hide(cached,debuff,member), 'Repairing an invalid field in place recompiles immediately.');
cached.rules[3].name = 123;
assert(not filters.hide(cached,debuff,member), 'Changing a field type cannot reuse its previous compiled rule.');
cached.rules[2],cached.rules[3] = cached.rules[3],cached.rules[2];
assert(filters.hide(cached,buff,member) and not filters.hide(cached,debuff,member));
local bounded = filters.compile(many);
many.rules[129].effect = 33;
assert(filters.compile(many)==bounded, 'Rules beyond the supported limit do not invalidate the active rules.');
many.rules[128].effect = 253;
assert(filters.compile(many)~=bounded and filters.hide(many,{effect=253},member)
    and not filters.hide(many,{effect=128},member), 'The last supported rule still invalidates in place.');

-- The same rules, units and effects give back the same filtered subjects and map, so a display kept from frame to
-- frame stays kept under rules. A change to any of them is seen on the next call.
local kept_rules = config(rule({ effect = 33 }));
local function listing(group, slot)
    return filters.recipients(nil, { valid = true, id = 100, members = { { id = 101, name = 'Fennel', job = 3, group = group, slot = slot } } });
end;
local listed = listing(1, 1);
local mob_buff = { effect = 33, kind = 'buff' };
local tracked = { [101] = { known = true, effects = { buff, debuff } }, [301] = { known = true, effects = { mob_buff, other } } };
local shown = filters.subjects(kept_rules, tracked, listed);
assert(shown ~= tracked and #shown[101].effects == 1 and #shown[301].effects == 1, 'Haste is hidden on the member and the mob.');
local member_view, mob_view = shown[101], shown[301];
assert(filters.subjects(kept_rules, tracked, listed) == shown and shown[101] == member_view and shown[301] == mob_view,
    'Asked again, the same map and subjects come back.');
assert(filters.subjects(kept_rules, tracked, listing(1, 1))[101] == member_view, 'Recipients worked out again for the same member keep it.');
jit.off(); collectgarbage('collect'); collectgarbage('stop');
local counted = collectgarbage('count');
for _ = 1, 100 do filters.subjects(kept_rules, tracked, listed); end;
local grown = collectgarbage('count') - counted;
collectgarbage('restart'); jit.on();
assert(grown == 0, 'Asking again makes nothing, the mob the recipients do not list too: ' .. grown .. ' KB');
mob_buff.effect = 34;
assert(filters.subjects(kept_rules, tracked, listed)[301] == tracked[301], 'An effect changed in place is filtered again.');
mob_buff.effect = 33;
kept_rules.rules[1].scope = 'party';
local edited = filters.subjects(kept_rules, tracked, listed);
assert(#edited[101].effects == 1 and edited[301] == tracked[301], 'Edited rules are seen.');
assert(filters.subjects(kept_rules, tracked, listing(2, 7)) == tracked, 'A member now in another party is seen.');
tracked[101].known = false;
assert(filters.subjects(kept_rules, tracked, listed)[101].known == false, 'The subject\'s own fields are copied as they are now.');
tracked[101].known, tracked[101].effects = true, { buff, debuff, other };
assert(#filters.subjects(kept_rules, tracked, listed)[101].effects == 2, 'A new effects list is filtered again.');
kept_rules.rules[1].scope = 'all';
tracked[301] = nil;
assert(filters.subjects(kept_rules, tracked, listed)[301] == nil, 'A unit gone from the map is gone from what comes back.');

return 'Shared effect visibility: safe rules, affected-player evidence, scopes, immutable views and mutable settings invalidation';
