-- A self effect's end time is worked out once from its raw timer and kept while that raw timer stays, wherever it is
-- listed: effects coming and going before it shift its slot, and Copy Image changes its icon as shadows go, and
-- neither moves its countdown. Worked out again it lands on the game clock's whole second, up to one off.
local now = 10.0;
package.preload['core.clock'] = function () return { available = function() return true; end, get_game_time_raw = function () return math.floor(now + 990.3); end }; end
local client = require('core.client');
local mm = AshitaCore:GetMemoryManager();
local stats, party = mm:GetPlayer(), mm:GetParty();
local icons, timers = {}, {};
for i = 0, 31 do icons[i], timers[i] = 255, 0; end
stats.GetStatusIcons = function () return icons; end;
stats.GetStatusTimers = function () return timers; end;
stats.GetBuffs = function () return icons; end;
AshitaCore.GetMemoryManager = function () return mm; end;
party.GetMemberServerId = function (_, slot) return slot == 0 and 1001 or 0; end;
party.GetMemberZone = function () return 102; end;
party.GetMemberTargetIndex = function (_, slot) return slot == 0 and 0x400 or 0; end;
party.GetMemberName = function (_, slot) return slot == 0 and 'Tester' or nil; end;
local function find(snapshot, effect)
    for _, entry in ipairs(snapshot.self_effects) do if entry.effect == effect then return entry; end; end;
end;

-- Haste ahead of Protect wears off; Protect moves to slot 0 on the same raw timer.
local PROTECT = (1000 + 300) * 60;
icons[0], timers[0], icons[1], timers[1] = 33, (1000 + 100) * 60, 40, PROTECT;
local first = find(client.read(now), 40);
now = 10.8;
local same = find(client.read(now), 40);
assert(first.slot == 1 and same.deadline == first.deadline, 'Fixture: the same slot and raw timer keep the end time.');
icons[0], timers[0], icons[1], timers[1] = 40, PROTECT, 255, 0;
local shifted = find(client.read(now), 40);
assert(shifted.slot == 0 and shifted.raw_timer == PROTECT, 'Fixture: Protect moved up a slot.');
assert(shifted.deadline == first.deadline, string.format('A slot shift keeps the end time: %.2f then %.2f', first.deadline, shifted.deadline));
-- A restamped timer is a new end, worked out again.
timers[0] = PROTECT + 60;
now = 11.5;
local restamped = find(client.read(now), 40);
assert(restamped.deadline ~= first.deadline and math.abs(restamped.deadline - (first.deadline + 1)) <= 1,
    'A new raw timer is worked out again.');

-- Copy Image loses a shadow: its icon goes 446 to 445 on the same timer.
for i = 0, 31 do icons[i], timers[i] = 255, 0; end
local RAW = (1000 + 900) * 60;
icons[0], timers[0] = 446, RAW;
now = 20.0;
local before = client.read(now).self_effects[1];
now = 20.8;
icons[0] = 445;
local after = client.read(now).self_effects[1];
assert(after.effect == 445 and before.effect == 446, 'Fixture: the icon changed.');
assert(after.deadline == before.deadline, string.format('A lost shadow keeps the countdown: %.2f then %.2f', before.deadline, after.deadline));

-- A copy listed later on a raw timer another copy has ends with it; an unknown timer has none.
icons[0], timers[0], icons[1], timers[1] = 40, PROTECT + 600, 255, 0;
now = 21.3;
local alone = find(client.read(now), 40);
now = 21.9;
icons[1], timers[1] = 41, PROTECT + 600;
local pair = client.read(now);
assert(find(pair, 40).deadline == alone.deadline and find(pair, 41).deadline == alone.deadline,
    'Equal raw timers end together, whenever each was listed.');
timers[1] = 0;
local unknown = find(client.read(now), 41);
assert(unknown.deadline == nil, 'An unknown timer has no end time.');
