-- Rampart (623) is a buff a PLD puts on the party around them (Phoenix sql/abilities.sql :112,
-- modules/era/lua/globals/job_utils/paladin.lua :10-32). Phoenix sends 319 on the PLD and 266 on each other member,
-- each naming 623. So Party list on Buffs only shows it as it shows Protect, and a hide rule for buffs hides it.
-- Through vantage.lua as the game drives it (live_fixture.lua): Bob uses Rampart, and Dave's Protect on Bob is the buff
-- to compare with.
local L = require('live_fixture');
local app = L.start();
local layout, filters = require('ui.party_layout'), require('core.effect_filters');
local BOB, DAVE = 1002, 1003;
local RAMPART, PROTECT = 623, 40;
L.listing({ { BOB, 0x401, {} }, { DAVE, 0x402, {} } });
L.frame();
L.action(6, 92, BOB, { { id = BOB, rows = { { message = 319, param = RAMPART } } },
    { id = DAVE, rows = { { message = 266, param = RAMPART } } } });
L.action(4, 43, DAVE, { { id = BOB, rows = { { message = 230, param = PROTECT } } } });
L.frame();
assert(L.row(BOB, RAMPART) and L.row(DAVE, RAMPART) and L.row(BOB, PROTECT), 'Fixture: Rampart on Bob and Dave, and Protect on Bob.');

-- What Party list draws for a member, with its own effect settings (ui/party_layout.lua).
local effects = app.state.settings.party_ui.effects;
local function drawn(id)
    local out = {};
    for _, effect in ipairs((layout.effects(app.state.party_subjects[id], effects))) do out[effect.effect] = true; end
    return out;
end
effects.kind = 'buff';
local bob, dave = drawn(BOB), drawn(DAVE);
assert(bob[PROTECT], 'Fixture: Buffs only shows Protect.');
assert(bob[RAMPART] and dave[RAMPART], 'Buffs only shows Rampart on Bob and Dave: ' .. tostring(bob[RAMPART]) .. ', '
    .. tostring(dave[RAMPART]));
effects.kind = 'all';

-- A hide rule for any effect that is a buff, on your party.
app.state.settings.effect_filters.rules = { { enabled = true, effect = 0, kind = 'buff', name = '', job = 0, scope = 'party' } };
L.frame();
local compiled = app.callbacks.effect_filters;
assert(compiled and compiled.active, 'Fixture: the rule is on.');
local shown = filters.subjects(compiled, app.state.party_subjects, app.callbacks.effect_recipients);
local function has(subject, effect)
    for _, held in ipairs(subject.effects) do if held.effect == effect then return true; end end
    return false;
end
assert(not has(shown[BOB], PROTECT), 'Fixture: the rule hides Protect.');
assert(not has(shown[BOB], RAMPART), 'The rule hides Rampart too.');
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return 'Rampart is a buff';
