-- A unit whose every effect the shared hide rules hide has nothing to draw over its head, so it takes none of the
-- Most units at once places: those go to units that do have something to show. The rules are the ones the drawing
-- uses (ui/overhead_icons.lua), for the same unit, so a unit that gets a place has an icon. The target keeps its
-- place whatever it shows, as before, and a unit type with Use the shared hide rules off isn't touched by them.
local W = require('overhead_fixture');
local overhead, filters = require('core.overhead'), require('core.effect_filters');
local plan = overhead.plan;
local settings = W.settings();
settings.overhead.max_units = 2;
-- Three mobs the party debuffed, nearest first. Sleep (2) is on the two nearest, Slow (13) on the far one.
W.unit(0x100, 0x1000100, 'mob', 0, -5, { name = 'Near' });
W.unit(0x101, 0x1000101, 'mob', 0, -6, { name = 'Middle' });
W.unit(0x102, 0x1000102, 'mob', 0, -7, { name = 'Far' });
local snapshot = W.snapshot();
local function row(id, effect) return { entity_id = id, effect = effect, kind = 'debuff', scope = 'enemy', source = 1001, mine = true }; end
local view = W.view({ row(0x1000100, 2), row(0x1000101, 2), row(0x1000102, 13) });
local function frame(rules, recipients)
    W.now = W.now + 0.125;
    overhead.update(view, settings, snapshot, W.now, false, false, rules, recipients);
    assert(plan.valid and plan.hidden == nil, 'Fixture: the plan is placed: ' .. tostring(plan.hidden));
    return W.ids(plan);
end

-- No rules: the two nearest.
assert(frame() == '16777472 16777473', 'Fixture: with no rules the two nearest mobs take the places: ' .. frame());

-- Sleep hidden everywhere: the two nearest have nothing left to show, so the far one takes a place.
local function hide(effect, scope, name)
    local rule = filters.rule();
    rule.effect, rule.scope, rule.name = effect, scope or 'all', name or '';
    settings.effect_filters.rules[#settings.effect_filters.rules + 1] = rule;
end
hide(2);
assert(frame() == '16777474', 'A unit with every effect hidden everywhere takes no place: ' .. frame());
-- The compiled rules the frame hands over give the same.
assert(frame(filters.compile(settings.effect_filters)) == '16777474', 'The frame\'s own compiled rules do the same.');
-- One of them gets an effect the rules leave: it takes a place again, with the far one.
view = W.view({ row(0x1000100, 2), row(0x1000101, 2), row(0x1000101, 13), row(0x1000102, 13) });
assert(frame() == '16777473 16777474', 'A unit with one effect the rules leave has a place: ' .. frame());
view = W.view({ row(0x1000100, 2), row(0x1000101, 2), row(0x1000102, 13) });

-- The target keeps its place with nothing to show.
W.target = 0x100;
assert(frame() == '16777472 16777474', 'The target keeps its place: ' .. frame());
W.target = 0;

-- A rule for enemies only hides it on a mob, and one for the party doesn't.
settings.effect_filters.rules = {};
hide(2, 'party');
assert(frame() == '16777472 16777473', 'A rule for your party hides nothing on a mob: ' .. frame());
settings.effect_filters.rules = {};
hide(2, 'enemy');
assert(frame() == '16777474', 'A rule for enemies does: ' .. frame());

-- With the mob type's Use the shared hide rules off, the rules don't count for mobs.
settings.overhead.types.mob.shared_rules = false;
assert(frame() == '16777472 16777473', 'A unit type that ignores the shared rules keeps its places: ' .. frame());
settings.overhead.types.mob.shared_rules = true;
-- Rules switched off as a whole hide nothing.
settings.effect_filters.enabled = false;
assert(frame() == '16777472 16777473', 'Rules that are off hide nothing: ' .. frame());
settings.effect_filters.enabled = true;

-- A rule by player name: a party member the roster names. Their one effect hidden for them alone leaves them out,
-- and the other member, with the same effect, stays.
settings.effect_filters.rules = {};
settings.overhead.max_units = 10;
W.unit(0x401, 1002, 'player', 1, -3, { name = 'Bob' });
W.unit(0x402, 1003, 'player', 2, -4, { name = 'Dave' });
local members = { { id = 1002, index = 0x401, scope = 'party' }, { id = 1003, index = 0x402, scope = 'party' } };
snapshot = W.snapshot(members);
view = W.view({ { entity_id = 1002, effect = 3, kind = 'debuff', scope = 'party' }, { entity_id = 1003, effect = 3, kind = 'debuff', scope = 'party' } });
assert(frame() == '1002 1003', 'Fixture: both members show their Poison: ' .. frame());
hide(3, 'all', 'Bob');
local recipients = { [1002] = { id = 1002, name = 'bob', player = true, scope = 'party', group = 1 },
    [1003] = { id = 1003, name = 'dave', player = true, scope = 'party', group = 1 } };
assert(frame(nil, recipients) == '1003', 'A rule for one player leaves that player out: ' .. frame(nil, recipients));
-- With no roster to name them, the unit's own name is used, as the drawing does.
assert(frame() == '1003', 'The unit\'s own name stands in for the roster\'s: ' .. frame());
-- A rule by job goes by the roster, which is all that knows a member's job.
settings.effect_filters.rules = {};
local by_job = filters.rule();
by_job.effect, by_job.job = 3, 3;
settings.effect_filters.rules[1] = by_job;
recipients[1002].job, recipients[1003].job = 3, 5;
assert(frame(nil, recipients) == '1003', 'A rule for one job leaves that job out: ' .. frame(nil, recipients));
assert(frame() == '1002 1003', 'With no roster nobody has a job, so the rule hides nothing: ' .. frame());
-- A mob is an enemy to the rules whatever the roster calls it.
settings.effect_filters.rules = {};
settings.overhead.max_units = 2;
view = W.view({ row(0x1000100, 2), row(0x1000101, 2), row(0x1000102, 13) });
snapshot = W.snapshot();
hide(2, 'enemy');
local misnamed = { [0x1000100] = { id = 0x1000100, name = 'near', player = false, scope = 'other' },
    [0x1000101] = { id = 0x1000101, name = 'middle', player = false, scope = 'other' } };
assert(frame(nil, misnamed) == '16777474', 'A rule for enemies covers a mob the roster calls something else: ' .. frame(nil, misnamed));
return 'Units the shared rules leave nothing on take no over-heads place';
