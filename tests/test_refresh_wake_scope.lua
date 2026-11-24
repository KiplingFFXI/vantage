-- Through vantage.lua's packet handler: an effect landing wakes a refresh at once only when it is about a unit the
-- player is looking at or has a hand in: you, your pet, your party and alliance, your target, the Watch list, or
-- anything you or your pet did. In a crowd most effects land on strangers from strangers, and waking a whole refresh
-- for each one runs it every frame. Those wait for the next refresh, at most a tenth of a second on, and show then.
local SELF, BOB, ALLY, PET, STRANGER, OTHER, MOB, CRAB = 1001, 1002, 1010, 0x1000700, 1500, 1501, 0x1000123, 0x1000124;
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
-- Sleep (spell 253) landing on one target: message 236 with the effect, 2, as its param.
local function sleep(actor, target)
    return MOCK.packet(0x028, MOCK.action_bytes(actor, 4, 253, { { id = target, rows = { { message = 236, param = 2 } } } }));
end
assert(app.state.snapshot.valid and app.state.snapshot.id == SELF, 'Fixture: the player is in the game.');
local snapshot = app.state.snapshot;
snapshot.entities = snapshot.entities or {};
for id, unit in pairs({ [MOB] = { name = 'Goblin', kind = 'monster' }, [CRAB] = { name = 'Crab', kind = 'monster' },
    [STRANGER] = { name = 'Stranger', kind = 'player' }, [OTHER] = { name = 'Other', kind = 'player' },
    [BOB] = { name = 'Bob', kind = 'player' }, [ALLY] = { name = 'Ally', kind = 'player' }, [PET] = { name = 'Pet', kind = 'pet' } }) do
    unit.id = id;
    snapshot.entities[id] = unit;
end
snapshot.party = { { id = BOB, name = 'Bob', scope = 'party', zone = snapshot.zone, slot = 1 },
    { id = ALLY, name = 'Ally', scope = 'alliance', zone = snapshot.zone, slot = 6 } };
snapshot.pet = { id = PET, index = 0x700, name = 'Pet', kind = 'pet' };
snapshot.target = nil;
-- Whether a packet woke a refresh, and what it queued.
local function wakes(e)
    app.state.wake, app.state.queue = false, {};
    MOCK.fire('packet_in', e);
    assert(#app.state.queue == 1 and app.state.queue[1].kind == 'apply', 'Fixture: the landing was read: ' .. #app.state.queue);
    return app.state.wake == true;
end

-- A stranger's effect on a stranger, and on a mob nobody here is looking at: no early refresh.
assert(not wakes(sleep(STRANGER, OTHER)), 'A stranger\'s effect on a stranger waits for the next refresh.');
assert(not wakes(sleep(STRANGER, MOB)), 'So does one on a mob that is nobody\'s here.');
-- Anything of yours shows at once.
assert(wakes(sleep(STRANGER, SELF)), 'An effect landing on you wakes a refresh.');
assert(wakes(sleep(SELF, MOB)), 'Your effect landing on a mob wakes one.');
assert(wakes(sleep(SELF, OTHER)), 'Your effect landing on a stranger wakes one.');
assert(wakes(sleep(STRANGER, BOB)), 'An effect on a party member wakes one.');
assert(wakes(sleep(STRANGER, ALLY)), 'An effect on an alliance member wakes one.');
-- Your pet acts before it is put to sleep: one that acts after is seen to be awake, which is a second thing read
-- (tests/test_acted_wakes.lua).
assert(wakes(sleep(PET, MOB)), 'Your pet\'s effect on a mob wakes one.');
assert(wakes(sleep(STRANGER, PET)), 'An effect on your pet wakes one.');
-- Your target, and the Watch list.
snapshot.target = snapshot.entities[CRAB];
assert(wakes(sleep(STRANGER, CRAB)), 'An effect on your target wakes one.');
assert(not wakes(sleep(STRANGER, MOB)), 'One on a mob that isn\'t your target still waits.');
snapshot.target = nil;
assert(not wakes(sleep(STRANGER, CRAB)), 'Fixture: off your target it waits again.');
app.state.settings.watch_ids = { CRAB };
assert(wakes(sleep(STRANGER, CRAB)), 'An effect on a unit you watch wakes one.');
app.state.settings.watch_ids = {};

-- What waited is on the next refresh all the same.
local function sleeping(id)
    for _, row in ipairs(app.state.view.rows) do if row.entity_id == id and row.effect == 2 then return true; end end
    return false;
end
assert(not wakes(sleep(STRANGER, OTHER)), 'Fixture: a landing that waits.');
MOCK.frame(0.11);
assert(sleeping(OTHER), 'It shows at the next refresh, a tenth of a second on.');
return 'Only effects the player has a hand in wake a refresh early';
