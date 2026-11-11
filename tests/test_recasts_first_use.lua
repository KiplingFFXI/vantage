-- A cooldown the client didn't list before starts only with your own use of an ability on its timer, from 3 seconds
-- before its first reading to 3 seconds after. Phoenix lists only the abilities on cooldown (0x119), so the first use
-- of one since you zoned adds a timer with no reading before it, and so does a zone's list that comes after the first
-- read. That one starts nothing. A use paralysis stops counts by your request for it.
local slots = {};
local manager = {
    GetSpellTimer = function() return 0; end,
    GetAbilityTimerId = function(_, slot) return slots[slot] and slots[slot].id or 0; end,
    GetAbilityTimer = function(_, slot) return slots[slot] and slots[slot].timer or 0; end,
};
-- An ability's resource id is its own plus 512: Provoke 35 on timer 5, Berserk 31 on timer 1, Jump 66 on timer 158,
-- Boost 88 on timer 16, and the pact Punch 544 on timer 173.
local abilities = { [547] = { Name = { [1] = 'Provoke' }, RecastTimerId = 5 }, [543] = { Name = { [1] = 'Berserk' }, RecastTimerId = 1 },
    [578] = { Name = { [1] = 'Jump' }, RecastTimerId = 158 }, [600] = { Name = { [1] = 'Boost' }, RecastTimerId = 16 },
    [1056] = { Name = { [1] = 'Punch' }, RecastTimerId = 173 } };
local resources = {
    GetSpellById = function() return nil; end,
    GetAbilityById = function(_, id) return abilities[id]; end,
    GetAbilityByTimerId = function() return nil; end,
    GetItemById = function() return nil; end,
};
local memory = { GetRecast = function() return manager; end };
AshitaCore.GetMemoryManager = function() return memory; end;
AshitaCore.GetResourceManager = function() return resources; end;
local model = require('core.recasts').new();
local snapshot = { valid = true, id = 1001, zone = 230, job = 1, name = 'Aster' };
local now = 100;
local function update(delta) now = now + (delta or 0.1); model:update(snapshot, now, { items = false }); return model:view(now); end
local function get(view, timer)
    for _, row in ipairs(view.rows) do if row.kind == 'ability' and row.recast_id == timer then return row; end end
end
local function started()
    local count = 0;
    for _, event in ipairs(model:drain_events()) do if event.kind == 'started' then count = count + 1; end end
    return count;
end

-- The first read, then one more. Slot 0, the job special, reads ready.
update(); update();
assert(started() == 0, 'Nothing has started.');

-- Your Provoke comes just before its timer is read.
model:used(35, now + 0.05);
slots[1] = { id = 5, timer = 30 * 60 };
local view = update();
local provoke = get(view, 5);
assert(started() == 1 and provoke.total == 30 and provoke.start == now, 'A use just before starts it, with its full length.');

-- Jump's timer is read first, and your use comes after.
slots[2] = { id = 158, timer = 60 * 60 };
view = update();
assert(started() == 0 and get(view, 158).total == nil and get(view, 158).start == nil, 'Read with no use yet, it waits.');
model:used(66, now + 0.05);
slots[2].timer = 59.8 * 60;
view = update();
assert(started() == 1 and math.abs(get(view, 158).total - 59.8) < 1e-9 and get(view, 158).start == now,
    'The use just after starts it.');
update();
assert(started() == 0, 'It starts once.');

-- Berserk's timer comes with no use, as a zone's list after the first read does. It starts nothing, and a use more
-- than 3 seconds after its first reading doesn't start it either.
slots[3] = { id = 1, timer = 100 * 60 };
update();
for _ = 1, 31 do update(); end
model:used(31, now);
view = update();
assert(started() == 0 and get(view, 1).total == nil and get(view, 1).start == nil, 'A timer that came with no use starts nothing.');

-- A use more than 3 seconds before a timer's first reading doesn't start it.
model:used(88, now);
for _ = 1, 31 do update(); end
slots[4] = { id = 16, timer = 180 * 60 };
view = update();
assert(started() == 0 and get(view, 16).total == nil, 'A use long before starts nothing.');

-- Your use of an ability on another timer starts nothing.
slots[4] = nil;
for _ = 1, 3 do update(); end
model:used(35, now);
slots[4] = { id = 16, timer = 180 * 60 };
view = update();
assert(started() == 0 and get(view, 16).total == nil, 'Provoke starts no other timer.');

-- What the reader is given that names no ability is left out.
model:used(nil, now); model:used(-1, now); model:used(1024, now); model:used(35.5, now); model:used(35, 0 / 0);
model:used(35, math.huge);
update();
assert(started() == 0, 'Nothing starts from an id or time that is no use.');

-- Paralysis stops a use with an action that names no ability, though its cooldown still starts. Your request for the
-- ability, made in the 10 seconds before, says which it was. Every use before is forgotten by now.
slots[4] = nil;
for _ = 1, 61 do update(); end
model:requested(88, now);
slots[4] = { id = 16, timer = 180 * 60 };
view = update();
assert(started() == 0 and get(view, 16).total == nil, 'A request alone starts nothing.');
model:paralyzed(now + 0.05);
view = update();
assert(started() == 1 and get(view, 16).total == 180 and get(view, 16).start == now, 'A paralysis just after starts it, with its full length.');
-- A lag spike can hold the paralysis back for seconds after your request. The timer comes with it.
slots[4] = nil;
for _ = 1, 61 do update(); end
model:requested(88, now);
for _ = 1, 50 do update(); end
slots[4] = { id = 16, timer = 180 * 60 };
model:paralyzed(now + 0.05);
view = update();
assert(started() == 1 and get(view, 16).total == 180, 'A paralysis 5 seconds after your request still starts it, with its full length.');
-- A paralysis with no request, or with one from more than 10 seconds before, starts nothing.
slots[4] = nil;
for _ = 1, 61 do update(); end
slots[4] = { id = 16, timer = 180 * 60 };
update();
model:paralyzed(now);
view = update();
assert(started() == 0 and get(view, 16).total == nil, 'A paralysis with no request starts nothing.');
slots[4] = nil;
for _ = 1, 31 do update(); end
model:requested(88, now);
for _ = 1, 101 do update(); end
slots[4] = { id = 16, timer = 180 * 60 };
update();
model:paralyzed(now);
view = update();
assert(started() == 0 and get(view, 16).total == nil, 'A request long before starts nothing.');

-- A pact's cooldown starts when the avatar's move goes off, which can be more than 3 seconds after you used the pact
-- when the avatar has far to go. The move is a use of the pact too (core/observer.lua), so its timer starts with its
-- full length.
for _ = 1, 61 do update(); end
started();
model:used(544, now);
for _ = 1, 50 do update(); end
model:used(544, now + 0.05);
slots[5] = { id = 173, timer = 45 * 60 };
view = update();
assert(started() == 1 and get(view, 173).total == 45, 'A pact that went off 5 seconds after you used it starts with its full length.');
slots[5] = nil;

-- A job change reads everything again quietly, even with a use just before.
slots[4] = nil;
update();
assert(started() == 0, 'Fixture: Boost\'s timer is gone.');
snapshot.job = 2;
model:used(88, now + 0.05);
slots[4] = { id = 16, timer = 180 * 60 };
update();
assert(started() == 0, 'The first read after a job change starts nothing.');
update();
assert(started() == 0, 'Nor does the read after it.');

-- A timer that rises from a reading of zero still starts with no use, as before.
slots[0] = { id = 0, timer = 3600 * 60 };
view = update();
assert(started() == 1 and get(view, 0).total == 3600, 'The job special starts from its ready reading.');
return true;
