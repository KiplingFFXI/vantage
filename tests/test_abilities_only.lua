-- Only effects from job abilities, on Party members' timers and Party list buffs, through vantage.lua as the game drives
-- it. A row goes by the action seen to put it on, and blood pacts and rolls count as abilities. A row whose action
-- wasn't seen goes by data/ability_effects.lua, which leaves out what a spell gives too. Bob (1002) and Dave (1003) are
-- in your party.
local L = require('live_fixture');
local app = L.start();
local hud, layout = require('ui.hud'), require('ui.party_layout');
local BOB, DAVE, GARUDA = 1002, 1003, 0x1000702;
local BERSERK, HASTE, PROTECT, FOCUS, FIGHTERS_ROLL, BUST = 56, 33, 40, 59, 310, 309;
L.listing({ { BOB, 0x401, {} }, { DAVE, 0x402, {} } });
L.frame();

-- Bob uses Berserk, Dave casts Haste on Bob, and Garuda's Hastega lands on Dave.
L.action(6, 31, BOB, { { id = BOB, rows = { { message = 100, param = BERSERK } } } });
L.action(4, 57, DAVE, { { id = BOB, rows = { { message = 230, param = HASTE } } } });
L.action(13, 595, GARUDA, { { id = DAVE, rows = { { message = 319, param = HASTE } } } });
-- Dave rolls Fighter's Roll on himself and Bob, then busts.
L.action(6, 98, DAVE, { { id = DAVE, rows = { { message = 420, param = 5 } } }, { id = BOB, rows = { { message = 421, param = 5 } } } });
L.action(6, 98, DAVE, { { id = DAVE, rows = { { message = 426, param = 12 } } } });
L.frame();
local function kind(id, effect) local row = L.row(id, effect); return row and row.action_kind; end
assert(kind(BOB, BERSERK) == 'abilities', 'Berserk came from a job ability: ' .. tostring(kind(BOB, BERSERK)));
assert(kind(BOB, HASTE) == 'spells', 'Dave\'s Haste came from a spell: ' .. tostring(kind(BOB, HASTE)));
assert(kind(DAVE, HASTE) == 'pacts', 'Hastega\'s Haste came from a blood pact: ' .. tostring(kind(DAVE, HASTE)));
assert(kind(BOB, FIGHTERS_ROLL) == 'rolls' and kind(DAVE, BUST) == 'rolls', 'The roll and the bust came from rolls.');
assert(L.row(DAVE, FIGHTERS_ROLL) == nil, 'Fixture: the bust took Dave\'s roll off.');

local settings = app.state.settings;
local panel = settings.panels.party;
assert(panel.abilities_only == false, 'It starts off.');
local function shown(id)
    local out = {};
    for _, row in ipairs(hud.filter_rows(app.state.view, panel, 'party', settings)) do
        if row.entity_id == id then out[row.effect] = true; end
    end
    return out;
end
local bob, dave = shown(BOB), shown(DAVE);
assert(bob[BERSERK] and bob[HASTE] and bob[FIGHTERS_ROLL] and dave[HASTE] and dave[BUST], 'Off, everything shows.');
panel.abilities_only = true;
bob, dave = shown(BOB), shown(DAVE);
assert(bob[BERSERK] and bob[FIGHTERS_ROLL] and not bob[HASTE], 'On, Bob keeps Berserk and the roll, and not Dave\'s Haste spell.');
assert(dave[HASTE] and dave[BUST], 'Haste from Hastega and the bust stay, as pacts and rolls are abilities.');

-- What the party list draws: each member's effects, through the same check.
local function drawn(id, options)
    local out = {};
    local subject = app.state.party_subjects[id];
    for _, effect in ipairs((layout.effects(subject, options))) do out[effect.effect] = true; end
    return out;
end
local effects = settings.party_ui.effects;
assert(effects.abilities_only == false, 'It starts off on the party list too.');
assert(drawn(BOB, effects)[HASTE], 'Off, the party list shows Dave\'s Haste on Bob.');
effects.abilities_only = true;
bob = drawn(BOB, effects);
assert(bob[BERSERK] and bob[FIGHTERS_ROLL] and not bob[HASTE], 'On, the party list keeps Berserk and the roll, and not the Haste spell.');
assert(drawn(DAVE, effects)[HASTE], 'Haste from Hastega stays on the party list.');

-- Bob's listing names Focus and Protect, which nothing was seen to put on. Focus only comes from a job ability, and a
-- spell gives Protect.
L.listing({ { BOB, 0x401, { BERSERK, HASTE, FIGHTERS_ROLL, FOCUS, PROTECT } }, { DAVE, 0x402, { HASTE, BUST } } });
L.frame(); L.frame();
assert(L.row(BOB, FOCUS) and kind(BOB, FOCUS) == nil and L.row(BOB, PROTECT), 'Fixture: Focus and Protect, with no action seen.');
assert(kind(BOB, BERSERK) == 'abilities', 'The listing keeps what put Berserk on.');
bob = shown(BOB);
assert(bob[FOCUS] and not bob[PROTECT] and bob[BERSERK], 'Not seen, Focus shows and Protect doesn\'t.');
bob = drawn(BOB, effects);
assert(bob[FOCUS] and not bob[PROTECT], 'The same on the party list.');

-- A job ability is reported to every target even when a stronger copy refuses it, so another caster's copy it names
-- becomes nobody's in particular (core/tracker.lua), and what put it on isn't known either. No job ability gives
-- Haste, so Dave's report of it here stands in for one that does.
L.action(6, 31, DAVE, { { id = DAVE, rows = { { message = 100, param = HASTE } } } });
L.frame();
local haste = L.row(DAVE, HASTE);
assert(haste and haste.source == nil and haste.action_kind == nil, 'Nobody\'s Haste has no caster and no action.');
assert(not shown(DAVE)[HASTE] and not drawn(DAVE, effects)[HASTE], 'So it goes by the list, which leaves Haste out.');

-- The samples keep an effect from a job ability on each display, so the tick never leaves them empty: the party
-- member's Divine Seal on Party members' timers, and on the party list a Berserk, a Souleater and a Fighter's Roll, one
-- in each party, besides the Always show effects.
local sampled = {};
for _, row in ipairs(hud.filter_rows(hud.sample(10), panel, 'party', settings)) do sampled[row.effect] = true; end
assert(sampled[78] and not sampled[42] and not sampled[3], 'The timer samples keep Divine Seal and not Regen or Poison.');
local _, members = require('ui.party_hud').sample(18, 10);
local kept = {};
for _, subject in pairs(members) do
    for _, effect in ipairs((layout.effects(subject, effects))) do kept[effect.effect] = (kept[effect.effect] or 0) + 1; end
end
assert(kept[BERSERK] == 1 and kept[63] == 1 and kept[FIGHTERS_ROLL] == 1 and not kept[PROTECT] and not kept[HASTE] and not kept[4],
    'The party list samples keep one effect from a job ability in each party, and not Protect, Haste or Paralysis.');

-- Off again, everything is back.
panel.abilities_only, effects.abilities_only = false, false;
assert(shown(BOB)[PROTECT] and shown(BOB)[HASTE] and drawn(BOB, effects)[PROTECT], 'Off, everything shows again.');
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return 'Only effects from job abilities goes by the action seen, and by the list for one not seen';
