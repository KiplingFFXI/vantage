-- Duration overrides and learned durations (core/durations.lua), through real 0x028 and 0x029 packets, the observer
-- and the tracker. An override sets an estimate's time: fixed, seconds added or taken away, a percent, or a count up
-- that shows the time since it landed; a spell or ability rule goes before an effect rule, a named one before an
-- unnamed one. Your own effects and renewals that keep their time are left alone. Learning keeps the time from a cast
-- of yours landing to its wear-off and, past the number of casts asked for, uses their middle one for that spell on
-- that mob name. A removal Vantage saw, a removal with no wear-off (death, Dispel, a zone change), a sleep woken by
-- a hit or beside a damage tick, a hit on Bind and another caster's overwrite teach nothing; an overwrite of your own
-- starts the clock again. Phoenix sends the caster's wear-off before the 0x028 of the hit, removal or new copy that
-- ended it, so a wear-off waits a second before it is learned.
local durations = require('core.durations');
local observer = require('core.observer');
local hud = require('ui.hud');
local layout = require('ui.party_layout');
local SELF, ALLY, MOB, MOB2, BLM = 1001, 1002, 0x1000123, 0x1000124, 1004;
-- Your listing, when a test gives one.
local function snapshot(own)
    return { valid = true, id = SELF, name = 'Tester', zone = 102, job = 4, level = 75, self_known = true, self_revision = 1,
        self_timer_revision = 1, self_effects = own or {}, party = { { id = ALLY, name = 'Ally', scope = 'party' } },
        entities = { [SELF] = { id = SELF, name = 'Tester', kind = 'player' }, [ALLY] = { id = ALLY, name = 'Ally', kind = 'player' },
            [BLM] = { id = BLM, name = 'Blm', kind = 'player' }, [MOB] = { id = MOB, name = 'Goblin Smithy', kind = 'monster' },
            [MOB2] = { id = MOB2, name = 'Goblin Tinkerer', kind = 'monster' } },
        target = { id = MOB, name = 'Goblin Smithy', kind = 'monster' } };
end;
local function putbits(bytes, offset, length, value)
    for i = 0, length - 1 do
        local at = offset + i;
        if math.floor(value / 2 ^ i) % 2 == 1 then bytes[math.floor(at / 8)] = bytes[math.floor(at / 8)] + 2 ^ (at % 8); end
    end
end
local function action(actor, category, id, target, message, param)
    local bytes, at = MOCK.bytes(256), 150;
    putbits(bytes, 40, 32, actor); putbits(bytes, 72, 6, 1); putbits(bytes, 82, 4, category); putbits(bytes, 86, 32, id);
    putbits(bytes, at, 32, target); putbits(bytes, at + 32, 4, 1); at = at + 36;
    putbits(bytes, at + 27, 17, param); putbits(bytes, at + 44, 10, message); at = at + 87;
    bytes.n = math.ceil(at / 8);
    return MOCK.packet(0x028, bytes);
end
local function wearoff(actor, target, icon, message)
    local bytes = MOCK.bytes(28);
    MOCK.put(bytes, 4, 4, actor); MOCK.put(bytes, 8, 4, target); MOCK.put(bytes, 12, 4, icon); MOCK.put(bytes, 24, 2, message or 204);
    return MOCK.packet(0x029, bytes);
end
local function death(target)
    local bytes = MOCK.bytes(28);
    MOCK.put(bytes, 4, 4, ALLY); MOCK.put(bytes, 8, 4, target); MOCK.put(bytes, 24, 2, 6);
    return MOCK.packet(0x029, bytes);
end
local settings = { durations = durations.tidy({}) };
local config = settings.durations;
local tracker = require('core.tracker').new();
-- One refresh as vantage.lua runs it: prepare, the tracker, then learning from the wear-offs it let through.
local function step(now, packets, own)
    local snap, observations = snapshot(own), {};
    for _, packet in ipairs(packets) do for _, o in ipairs(observer.read(packet, now, snap)) do observations[#observations + 1] = o; end end
    durations.prepare(observations, settings, snap);
    tracker:observe(observations, now, snap); tracker:reconcile(snap, now);
    local view = tracker:view(now, {}, snap);
    tracker:drain_events();
    local learned = durations.learn(settings, tracker:samples(now));
    local rows = {};
    for _, row in ipairs(view.rows) do rows[row.entity_id .. ':' .. row.effect] = row; end
    return rows, learned, observations;
end;
local function sleep(now) return step(now, { action(SELF, 4, 253, MOB, 236, 2) }); end;
-- A wear-off, then the refresh a second and a half later that lets it through.
local function wear(now, packets, own) step(now, packets, own); return step(now + 1.5, {}, own); end;
local function key(spell, effect, name) return 'spell:' .. spell .. ':' .. effect .. ':' .. (name or 'goblin smithy'); end;
assert(require('core.tracker').WEAR_OFF == observer.wear_off, 'Learning reads the reason the observer gives a wear-off.');

-- Defaults: no overrides, learning off, and then nothing changes.
assert(#config.overrides == 0 and config.learn == false and config.learn_samples == 3 and next(config.learned) == nil);
local rows, _, seen = sleep(1);
assert(rows[MOB .. ':2'].total == 60 and rows[MOB .. ':2'].timing == nil and seen[1].learn_key == nil, 'Sleep is 60 s, untouched.');

-- Overrides.
local function rule(fields)
    local value = durations.override();
    for name, item in pairs(fields) do value[name] = item; end
    return value;
end;
config.overrides = { rule({ kind = 'spell', id = 253, mode = 'fixed', seconds = 45 }) };
rows = sleep(2);
local row = rows[MOB .. ':2'];
assert(row.total == 45 and row.deadline == 2 + 45 and row.duration_min == 45 and row.timing == 'override', 'A fixed time: 45 s.');
assert(hud.details(row, 3, { horizon = 300 }):find('Estimated from your duration override', 1, true), 'Its details say it is estimated from the override.');
rows = step(3, { action(SELF, 4, 259, MOB, 236, 2) });
assert(rows[MOB .. ':2'].total == 90, 'Sleep II is another spell: 90 s.');
config.overrides = { rule({ kind = 'spell', id = 253, mode = 'add', offset = -10 }) };
assert(sleep(4)[MOB .. ':2'].total == 50, 'Ten seconds taken away: 50.');
config.overrides = { rule({ kind = 'spell', id = 253, mode = 'add', offset = -100 }) };
assert(sleep(5)[MOB .. ':2'].total == 1, 'Never under 1 second.');
-- With no estimate to change, seconds added and a percent leave it without a countdown.
for _, mode in ipairs({ 'add', 'percent' }) do
    config.overrides = { rule({ kind = 'effect', id = 250, mode = mode, offset = 30, percent = 200 }) };
    row = step(5.5, { action(SELF, 4, 9999, MOB, 236, 250) })[MOB .. ':250'];
    assert(row and row.total == nil and row.deadline == nil and row.timing == nil, mode .. ' with no estimate shows no countdown.');
end;
config.overrides = { rule({ kind = 'spell', id = 253, mode = 'percent', percent = 150 }) };
assert(sleep(6)[MOB .. ':2'].total == 90, '150 percent: 90.');
-- A range keeps both ends.
config.overrides = { rule({ kind = 'spell', id = 58, mode = 'percent', percent = 50 }) };
rows = step(7, { action(SELF, 4, 58, MOB, 236, 4) });
assert(rows[MOB .. ':4'].total == 60 and rows[MOB .. ':4'].duration_min == 15, 'Paralyze 30 to 120 at half: 15 to 60.');
-- Effect rules, names and ranks.
config.overrides = { rule({ kind = 'effect', id = 2, mode = 'fixed', seconds = 20 }) };
assert(step(8, { action(SELF, 6, 131, MOB, 127, 2) })[MOB .. ':2'].total == 20, 'An effect rule takes Light Shot\'s Sleep too.');
config.overrides = { rule({ kind = 'effect', id = 2, mode = 'fixed', seconds = 20 }), rule({ kind = 'spell', id = 253, mode = 'fixed', seconds = 30 }) };
assert(sleep(9)[MOB .. ':2'].total == 30, 'A spell rule goes before an effect rule.');
config.overrides = { rule({ kind = 'spell', id = 253, mode = 'fixed', seconds = 30 }),
    rule({ kind = 'spell', id = 253, mode = 'fixed', seconds = 70, name = '  goblin SMITHY ' }) };
assert(sleep(10)[MOB .. ':2'].total == 70, 'A named rule goes before an unnamed one, by name in any case.');
assert(step(11, { action(SELF, 4, 253, MOB2, 236, 2) })[MOB2 .. ':2'].total == 30, 'Another mob takes the unnamed rule.');
config.overrides[2].enabled = false;
assert(sleep(12)[MOB .. ':2'].total == 30, 'A rule turned off is skipped.');
config.overrides = { rule({ kind = 'ability', id = 253, mode = 'fixed', seconds = 5 }) };
assert(sleep(13)[MOB .. ':2'].total == 60, 'An ability rule never takes a spell of the same number.');
-- Your own effects follow the game's timers.
local own = { { kind = 'apply', entity_id = SELF, effect = 2, spell = 253, action_category = 4, source = MOB, duration = 60 } };
config.overrides = { rule({ kind = 'spell', id = 253, mode = 'fixed', seconds = 45 }) };
durations.prepare(own, settings, snapshot());
assert(own[1].duration == 60 and own[1].timing == nil, 'Your own Sleep is untouched.');

-- Count up: no time left, the time since it landed in every display, and its details say so.
config.overrides = { rule({ kind = 'spell', id = 253, mode = 'count_up' }) };
rows = sleep(20);
row = rows[MOB .. ':2'];
assert(row.count_up and row.deadline == nil and row.total == nil and row.status == 'unknown', 'Counting up, with no time left.');
rows = step(95, {});
row = rows[MOB .. ':2'];
-- In the one time format every countdown has, whatever format a caller still names.
assert(row and hud.timer_text(row, 95) == '1m' and hud.timer_text(row, 95, 'seconds') == '1m', 'The panels show 75 s since it landed.');
assert(layout.effect_time(row, 'auto') == '1m' and layout.effect_time(row, 'seconds') == '1m', 'The party list strips do too.');
assert(hud.details(row, 95, { horizon = 300 }):find('counts up from when it landed', 1, true), 'Its details say it counts up.');
local _, said = hud.details(row, 95, { horizon = 300 }):gsub('counts up from when it landed', '');
assert(said == 1 and not hud.details(row, 95, { horizon = 300 }):find('Elapsed', 1, true), 'Its details say so once, with one time since it landed.');
for _, word in ipairs({ 'unknown', 'Unknown', '?' }) do assert(not hud.details(row, 95, { horizon = 300 }):find(word, 1, true), 'No ' .. word); end;
local plain = { effect = 2, status = 'unknown', start = 20, elapsed = 75, domain = nil };
assert(hud.timer_text(plain, 95) == '' and layout.effect_time(plain, 'auto') == '', 'Without a count up, no time shows no countdown.');
-- A count up stays as long as the estimate it hides would: Protect on another player is still listed long after the
-- 180 s an untimed row lives, and leaves 180 s after its estimate ends. One with no estimate leaves after 180 s.
config.overrides = {};
local estimate = step(100, { action(SELF, 4, 43, BLM, 230, 40) })[BLM .. ':40'].total;
assert(estimate and estimate > 600, 'Fixture: Protect has a long estimate.');
config.overrides = { rule({ kind = 'effect', id = 40, mode = 'count_up' }), rule({ kind = 'effect', id = 250, mode = 'count_up' }) };
step(101, { action(SELF, 4, 43, BLM, 230, 40), action(SELF, 4, 9999, MOB, 236, 250) });
rows = step(500, {});
assert(rows[BLM .. ':40'] and rows[BLM .. ':40'].count_up and rows[BLM .. ':40'].deadline == nil, 'A count-up Protect is still listed at 400 s.');
assert(not rows[MOB .. ':250'], 'A count up with no estimate leaves after 180 s, as an untimed row does.');
assert(step(101 + estimate + 170, {})[BLM .. ':40'] and not step(101 + estimate + 190, {})[BLM .. ':40'], 'It leaves 180 s after its estimate.');
config.overrides = {};

-- Learning: off, nothing is kept.
tracker = require('core.tracker').new();
rows = sleep(100);
local learned;
rows, learned = wear(158.4, { wearoff(SELF, MOB, 2) });
assert(not learned and next(config.learned) == nil, 'With learning off nothing is learned.');
-- On: each wear-off of your own cast is a sample, to a tenth of a second, once a second has passed with nothing
-- behind it to spoil it.
config.learn = true;
local _, _, marks = sleep(200);
assert(marks[1].learn_key == key(253, 2), 'Your cast is marked: ' .. tostring(marks[1].learn_key));
rows, learned = step(258.44, { wearoff(SELF, MOB, 2) });
assert(not learned and config.learned[key(253, 2)] == nil, 'The wear-off waits.');
rows, learned = step(259.2, {});
assert(not learned and config.learned[key(253, 2)] == nil, 'For a second.');
rows, learned = step(259.5, {});
assert(learned and config.learned[key(253, 2)].samples[1] == 58.4 and config.learned[key(253, 2)].unit == 'Goblin Smithy', 'One sample: 58.4 s.');
sleep(300); wear(359, { wearoff(SELF, MOB, 2) });
rows = sleep(400);
assert(rows[MOB .. ':2'].total == 60 and rows[MOB .. ':2'].timing == nil, 'Two samples are not enough of three.');
wear(461, { wearoff(SELF, MOB, 2) });
rows = sleep(500);
row = rows[MOB .. ':2'];
assert(row.total == 59 and row.duration_min == 59 and row.timing == 'learned', 'Three: the middle one, 59 s: ' .. tostring(row.total));
assert(row.reason == 'Learned from 3 of your casts.', 'Its reason says how many.');
assert(hud.details(row, 501, { horizon = 300 }):find('Estimated from the times learned from your casts', 1, true), 'Its details say learned and estimated.');
wear(560, { wearoff(SELF, MOB, 2) });
-- Only your own casts use them: another caster's Sleep on the same mob keeps the Phoenix time.
rows = step(565, { action(BLM, 4, 253, MOB, 236, 2) });
assert(rows[MOB .. ':2'].total == 60 and rows[MOB .. ':2'].timing == nil, "Another caster's Sleep keeps 60 s.");
-- Another mob name has none of these, and an override goes before them.
assert(step(600, { action(SELF, 4, 253, MOB2, 236, 2) })[MOB2 .. ':2'].total == 60, 'Learned by mob name: another name has its own.');
config.overrides = { rule({ kind = 'spell', id = 253, mode = 'add', offset = 5 }) };
assert(sleep(700)[MOB .. ':2'].total == 65, 'An override goes on the learned time: 60 and 5.');
config.overrides = {};
-- Fewer casts asked for.
config.learn_samples = 1;
rows = step(800, { action(SELF, 4, 253, MOB2, 236, 2) });
assert(rows[MOB2 .. ':2'].total == 60, 'Fixture: none learned on the other mob yet.');

-- What teaches nothing.
local function samples(spell, effect, name) local entry = config.learned[key(spell, effect, name)]; return entry and #entry.samples or 0; end;
tracker = require('core.tracker').new();
local before = samples(253, 2);
-- A sleep woken by a hit: it leaves at the hit, and the caster's wear-off after it finds nothing.
sleep(1000); step(1010, { action(ALLY, 1, 0, MOB, 1, 30) }); wear(1010.1, { wearoff(SELF, MOB, 2) });
assert(samples(253, 2) == before, 'A woken sleep is no sample.');
-- A sleep beside a damage tick (your Dia), and one that a later Poison joins.
step(1100, { action(SELF, 4, 23, MOB, 2, 4) }); sleep(1101); wear(1130, { wearoff(SELF, MOB, 2) });
assert(samples(253, 2) == before, 'A sleep beside Dia is no sample.');
tracker = require('core.tracker').new();
sleep(1200); step(1201, { action(BLM, 4, 220, MOB, 236, 3) }); wear(1240, { wearoff(SELF, MOB, 2) });
assert(samples(253, 2) == before, 'A sleep a Poison joined is no sample.');
-- The same sleep with no tick beside it teaches.
tracker = require('core.tracker').new();
sleep(1250); wear(1290, { wearoff(SELF, MOB, 2) });
assert(samples(253, 2) == before + 1, 'Fixture: a clean sleep is a sample.');
before = before + 1;
-- A removal seen on the unit: no time running there is learned.
tracker = require('core.tracker').new();
step(1300, { action(SELF, 4, 58, MOB, 236, 4) }); sleep(1301);
step(1310, { action(MOB, 4, 143, MOB, 83, 2) });
wear(1330, { wearoff(SELF, MOB, 4) });
assert(samples(58, 4) == 0, 'Paralysis running when a removal was seen is no sample.');
-- Death, then nothing: no sample. A wear-off sent with no row (another zone) neither.
tracker = require('core.tracker').new();
sleep(1400); step(1420, { death(MOB) }); wear(1460, { wearoff(SELF, MOB, 2) });
assert(samples(253, 2) == before, 'A mob that died teaches nothing.');
-- Bind hit before its wear-off.
tracker = require('core.tracker').new();
step(1500, { action(SELF, 4, 258, MOB, 236, 11) }); step(1505, { action(ALLY, 1, 0, MOB, 1, 30) }); wear(1508, { wearoff(SELF, MOB, 11) });
assert(samples(258, 11) == 0, 'A Bind that took a hit is no sample.');
-- An unhurt Bind teaches.
step(1600, { action(SELF, 4, 258, MOB, 236, 11) }); wear(1630, { wearoff(SELF, MOB, 11) });
assert(samples(258, 11) == 1 and config.learned[key(258, 11)].samples[1] == 30, 'An unhurt Bind is a sample.');
-- Another caster's Paralysis over yours: theirs, not yours.
tracker = require('core.tracker').new();
step(1700, { action(SELF, 4, 58, MOB, 236, 4) }); step(1710, { action(BLM, 4, 58, MOB, 236, 4) }); wear(1750, { wearoff(BLM, MOB, 4) });
assert(samples(58, 4) == 0, 'Another caster\'s overwrite teaches nothing.');
-- Your own overwrite starts the clock again.
step(1800, { action(SELF, 4, 58, MOB, 236, 4) }); step(1820, { action(SELF, 4, 58, MOB, 236, 4) }); wear(1900, { wearoff(SELF, MOB, 4) });
assert(samples(58, 4) == 1 and config.learned[key(58, 4)].samples[1] == 80, 'Your own overwrite starts again: 80 s.');
-- Your buff on a party member: learned by spell for every player.
step(2000, { action(SELF, 4, 57, ALLY, 230, 33) }); wear(2178, { wearoff(SELF, ALLY, 33) });
assert(config.learned['spell:57:33:'] and config.learned['spell:57:33:'].samples[1] == 178 and config.learned['spell:57:33:'].unit == '',
    'Haste on a party member is learned for every player.');
-- Phoenix sends the caster's wear-off before the 0x028 that ended it (status_effect_container.cpp :654-670,
-- attack_state.cpp :92-100), in the same refresh or the next. A hit behind a sleep's or Bind's wear-off, a removal
-- behind any, or another caster's Bio behind your Dia's: none is a sample. A hit behind a Paralysis wear-off is.
local function hit() return action(ALLY, 1, 0, MOB, 1, 30); end;
tracker = require('core.tracker').new();
sleep(2200); wear(2210, { wearoff(SELF, MOB, 2), hit() });
assert(samples(253, 2) == before, 'A sleep woken by a hit sent behind its wear-off is no sample.');
sleep(2220); step(2230, { wearoff(SELF, MOB, 2) }); wear(2230.3, { hit() });
assert(samples(253, 2) == before, 'Nor with the hit in the next refresh.');
step(2240, { action(SELF, 4, 258, MOB, 236, 11) }); wear(2244, { wearoff(SELF, MOB, 11), hit() });
step(2250, { action(SELF, 4, 258, MOB, 236, 11) }); step(2254, { wearoff(SELF, MOB, 11) }); wear(2254.3, { hit() });
assert(samples(258, 11) == 1, 'A Bind broken by a hit is no sample, in either refresh.');
-- Spikes don't break Bind, so the bound mob's swing into your Blaze Spikes behind its wear-off spoils nothing. The swing
-- hits you for 30 and the spikes deal 12 back (message 44 in the reaction slot).
local function spikes()
    local bytes, at = MOCK.bytes(256), 150;
    putbits(bytes, 40, 32, MOB); putbits(bytes, 72, 6, 1); putbits(bytes, 82, 4, 1);
    putbits(bytes, at, 32, SELF); putbits(bytes, at + 32, 4, 1); at = at + 36;
    putbits(bytes, at + 27, 17, 30); putbits(bytes, at + 44, 10, 1); at = at + 86;
    putbits(bytes, at, 1, 1); putbits(bytes, at + 11, 14, 12); putbits(bytes, at + 25, 10, 44); at = at + 35;
    bytes.n = math.ceil(at / 8);
    return MOCK.packet(0x028, bytes);
end;
local BLAZE = { { effect = 34, slot = 0 } };
step(2256, { action(SELF, 4, 258, MOB, 236, 11) }, BLAZE); wear(2258, { wearoff(SELF, MOB, 11), spikes() }, BLAZE);
assert(samples(258, 11) == 2 and config.learned[key(258, 11)].samples[2] == 2, 'Spikes behind a Bind\'s wear-off spoil nothing.');
step(2260, { action(SELF, 4, 58, MOB, 236, 4) }); step(2268, { wearoff(SELF, MOB, 4) }); wear(2268.2, { action(MOB, 4, 15, MOB, 83, 4) });
assert(samples(58, 4) == 1, 'A wear-off with a removal behind it is no sample.');
step(2280, { action(SELF, 4, 58, MOB, 236, 4) }); wear(2290, { wearoff(SELF, MOB, 4), hit() });
assert(samples(58, 4) == 2 and config.learned[key(58, 4)].samples[2] == 10, 'A hit behind a Paralysis wear-off spoils nothing.');
local DIA = function(name) return key(23, 134, name or 'goblin tinkerer'); end;
step(2300, { action(SELF, 4, 23, MOB2, 2, 12) }); wear(2320, { wearoff(SELF, MOB2, 134, 206) });
assert(config.learned[DIA()] and #config.learned[DIA()].samples == 1 and config.learned[DIA()].samples[1] == 20, 'Fixture: a Dia left alone is a sample.');
step(2330, { action(SELF, 4, 23, MOB2, 2, 12) }); step(2340, { wearoff(SELF, MOB2, 134, 206) }); wear(2340.2, { action(BLM, 4, 230, MOB2, 2, 10) });
assert(#config.learned[DIA()].samples == 1, "Your Dia taken off by another caster's Bio is no sample.");
-- A zone change while one waits drops it, as the hit behind it may never come.
step(2350, { action(SELF, 4, 58, MOB, 236, 4) }); step(2360, { wearoff(SELF, MOB, 4) });
tracker:clear('Zone changed', 2360.5);
step(2362, {});
assert(samples(58, 4) == 2, 'A wear-off waiting at a zone change is no sample.');

-- The caps: nine samples a key, newest kept; 128 keys, the newest kept; tidy keeps them that way.
config.learned = {};
for index = 1, 12 do step(3000 + index * 100, { action(SELF, 4, 253, MOB, 236, 2) }); wear(3000 + index * 100 + 50 + index, { wearoff(SELF, MOB, 2) }); end;
local list = config.learned[key(253, 2)].samples;
assert(#list == 9 and list[1] == 54 and list[9] == 62, 'Nine samples, the newest: ' .. #list .. ' ' .. list[1]);
local many = {};
for index = 1, 140 do many['spell:253:2:mob ' .. index] = { samples = { 60 }, unit = 'Mob ' .. index, at = index }; end;
local tidy = durations.tidy({ learned = many });
local count = 0;
for name in pairs(tidy.learned) do count = count + 1; assert(tonumber(name:match('mob (%d+)$')) > 12, 'The oldest go: ' .. name); end;
assert(count == 128, '128 kept: ' .. count);
-- Tidy: bad entries go, rules are rebuilt and clamped, unknown keys stay.
tidy = durations.tidy({ extra = 1, learn = 'yes', learn_samples = 40, overrides = { { kind = 'magic', id = 5000, mode = 'odd', seconds = 0, percent = 5000,
    name = 'A\tB' }, 'bad' }, learned = { ['nonsense'] = { samples = { 60 } }, ['spell:253:2:'] = { samples = { 0, 'x', 70 } },
    ['spell:253:2:x'] = { samples = {} } } });
assert(tidy.extra == 1 and tidy.learn == false and tidy.learn_samples == 9, 'Switches and counts.');
local r = tidy.overrides[1];
assert(#tidy.overrides == 1 and r.kind == 'spell' and r.id == 1023 and r.mode == 'fixed' and r.seconds == 1 and r.percent == 1000 and r.name == '',
    'A rule is rebuilt within its ranges.');
assert(tidy.learned['spell:253:2:'] and #tidy.learned['spell:253:2:'].samples == 1 and tidy.learned.nonsense == nil
    and tidy.learned['spell:253:2:x'] == nil, 'Learned times keep their good samples only.');
assert(durations.median({ 3, 1, 2 }) == 2 and durations.median({ 4, 1, 3, 2 }) == 2.5 and durations.median({}) == nil, 'The middle one.');
return 'Duration overrides change estimates and learning keeps only clean samples of your own casts';
