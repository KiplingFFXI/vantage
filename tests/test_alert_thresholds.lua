-- A rule keeps the thresholds it was given: reading the settings adds none, so a rule with one threshold still has one
-- after a reload.
local alerts, defaults, json = require('core.alerts'), require('ui.defaults'), require('core.json');
local share, store = require('core.share'), require('core.store');
local custom = require('core.customization');

local function saved(list, unit)
    local s = defaults.make();
    local rule = defaults.rule('saved');
    rule.thresholds, rule.unit = list, unit or 'seconds';
    s.alerts.rules = { rule };
    return s;
end;
local function read(s) return defaults.tidy(s).alerts.rules[1].thresholds; end;
local function shown(list) return table.concat(list, ', '); end;
local function check(list, want, unit, what)
    local got = read(saved(store.copy(list), unit));
    assert(custom.equal(got, want), what .. ': ' .. shown(list) .. ' reads ' .. shown(got) .. ', not ' .. shown(want) .. '.');
end;

-- What the player wrote stays, however few, in the order they fire.
check({ 5 }, { 5 }, nil, 'One threshold under 10');
check({ 10 }, { 10 }, nil, 'One threshold at 10');
check({ 30 }, { 30 }, nil, 'One threshold over 10');
check({ 3600 }, { 3600 }, nil, 'One long threshold');
check({ 30, 10 }, { 30, 10 }, nil, 'The default two');
check({ 5, 15 }, { 15, 5 }, nil, 'Two without a 10');
check({ 5, 60, 20 }, { 60, 20, 5 }, nil, 'Three');
check({ 5, 5 }, { 5 }, nil, 'A repeat');
check({ 50 }, { 50 }, 'percent', 'One percent threshold');

-- Past their limits they go, and with nothing left the rule falls back on a single 10.
check({ 86401, 5 }, { 5 }, nil, 'One past a day');
check({ 101, 50 }, { 50 }, 'percent', 'One past 100 percent');
check({ -5 }, { 10 }, nil, 'Nothing usable');
check({}, { 10 }, nil, 'An empty list');

-- A rule with no thresholds, or a hand edit that isn't a list, has the default's two.
local s = saved({ 5 });
s.alerts.rules[1].thresholds = nil;
assert(custom.equal(read(s), { 30, 10 }), 'A rule with none has the default two.');
s = saved({ 5 });
s.alerts.rules[1].thresholds = 'five';
assert(custom.equal(read(s), { 30, 10 }), 'Thresholds that aren\'t a list are the default two.');

-- The rest of a rule is still filled in around them.
s = saved({ 5 });
s.alerts.rules[1].cooldown, s.alerts.rules[1].chat = nil, nil;
local rule = defaults.tidy(s).alerts.rules[1];
assert(rule.cooldown == 10 and rule.chat == false and custom.equal(rule.thresholds, { 5 }), 'A rule\'s other fields are filled in.');

-- Every road a save takes: read again, through JSON and through an export, added or replacing.
s = defaults.tidy(saved({ 5 }));
assert(custom.equal(read(s), { 5 }), 'Reading it again keeps it.');
assert(custom.equal(read(json.decode(json.encode(s))), { 5 }), 'A save and a load keep it.');
local text = assert(share.export(s, 'alerts', nil, 'Tester'));
local payload = assert(share.read(text));
for _, mode in ipairs({ 'replace', 'add' }) do
    local into = defaults.tidy(defaults.make());
    local candidate = assert(share.candidate(into, payload, mode));
    assert(custom.equal(candidate.alerts.rules[1].thresholds, { 5 }), 'An export keeps it: ' .. mode .. '.');
end;

-- And so it fires once, at its own threshold, with no warning at 10.
local engine = alerts.new();
local made = defaults.tidy(saved({ 5 })).alerts.rules[1];
made.event, made.effect, made.scope, made.cooldown = 'remaining', 33, 'self', 0;
local row = { key = '10:33', instance = 1, effect = 33, name = 'Haste', scope = 'self', entity_id = 10, status = 'server', remaining = 40, total = 180, present = true };
local view = { valid = true, rows = { row }, subjects = { { id = 10, scope = 'self', known = true } }, context = { id = 10, zone = 1, job = 1 } };
engine:update(view, {}, { made }, 0, {});
row.remaining = 9;
engine:update(view, {}, { made }, 1, {});
assert(#engine:drain(1) == 0, 'Nothing at 9 seconds, with only a threshold at 5.');
row.remaining = 4;
engine:update(view, {}, { made }, 2, {});
local notices = engine:drain(2);
assert(#notices == 1 and notices[1].threshold == 5, 'One notice at 5 seconds.');

return 'A rule keeps the thresholds it was given';
