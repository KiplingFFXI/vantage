-- Vantage loading with an automaton already out, as /addon reload does in the middle of a fight. The clear Vantage
-- does on its first look at the game isn't a zone change, so the automaton may be part way through any recast: each
-- attachment reads Not known yet until it fires or its recast's length has passed. A zone change after that makes
-- the automaton anew, and every recast is known from there.
local PUPPET, index = 0x1000703, 0x703;
local fx = require('pet_fixture')(function(game)
    game.job = 18;
    game.pet = { index = index, id = PUPPET, name = 'Ironsides', flags = 0x02, hpp = 78 };
end);
local game, config = fx.game, fx.settings.pet;
config.show_attachments = true;
local function line(name)
    local shown = fx.app.state.view.pet;
    for at = 1, shown and shown.line_count or 0 do
        if shown.lines[at].name == name then return shown.lines[at]; end
    end
end
-- The 0x044 of a Valoredge automaton with Strobe and Shock Absorber.
local function page()
    local bytes = MOCK.bytes(0xA0);
    MOCK.put(bytes, 4, 1, 18); MOCK.put(bytes, 8, 1, 2); MOCK.put(bytes, 9, 1, 0x21); MOCK.put(bytes, 0x0A, 1, 1); MOCK.put(bytes, 0x0B, 1, 97);
    for i = 1, #'Ironsides' do bytes[0x57 + i] = ('Ironsides'):byte(i); end
    MOCK.put(bytes, 0x68, 2, 780); MOCK.put(bytes, 0x6A, 2, 1000);
    MOCK.fire('packet_in', MOCK.packet(0x044, bytes));
end

page();
fx.step();
assert(line('Strobe') and line('Strobe').value == 'Not known yet' and line('Strobe').deadline == nil,
    'An automaton found out when Vantage loads has no known recast: ' .. tostring(line('Strobe') and (line('Strobe').value or line('Strobe').deadline)));
assert(line('Shock Absorber').value == 'Not known yet', 'Nor has its other attachment.');
-- Strobe's 30 seconds pass, so its recast can only be over. Shock Absorber's 180 haven't.
fx.step(30);
assert(line('Strobe').value == 'Needs Fire' and line('Shock Absorber').value == 'Not known yet', 'Each is known once its own recast\'s length has passed.');
-- One that fires is known from then.
fx.action(PUPPET, 11, 1946, { { PUPPET, 0, 0 } });
fx.step();
assert(line('Shock Absorber').deadline and math.abs(line('Shock Absorber').deadline - MOCK.now - 180) < 0.5, 'One that fires counts from its use.');

-- A zone change: the automaton is made anew there, so every recast starts as it comes into view.
game.pet = nil;
fx.zone(103);
fx.step();
game.pet = { index = 0x704, id = 0x1000704, name = 'Ironsides', flags = 0x02, hpp = 100 };
page();
fx.step();
assert(line('Strobe').deadline and math.abs(line('Strobe').deadline - MOCK.now - 30) < 0.5, 'After a zone change Strobe counts its 30 seconds from the spawn.');
assert(line('Shock Absorber').deadline and math.abs(line('Shock Absorber').deadline - MOCK.now - 180) < 0.5, 'And Shock Absorber its 180.');
return 'Vantage loading with an automaton out';
