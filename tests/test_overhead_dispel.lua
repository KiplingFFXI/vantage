-- When you can take a mob's buff off right now, by Phoenix's checks: Dispel (RDM 32, or a RDM sub at sub level 32),
-- Magic Finale (BRD 33, or a BRD sub at 33), both learned; Blank Gaze (BLU 38 main), learned and set in 0x044; Dark
-- Shot (COR 40 main) with a Dark Card or Trump Card in the inventory and a Marksmanship weapon and ammo. The levels
-- are the ones the client shows, so Level Sync counts. data/dispelable.lua is Phoenix's dispelable list.
local dispel = require('core.dispel');
local P = { main = 1, main_level = 75, sub = 0, sub_level = 0, spells = {}, real_level = 75 };
local player = {
    GetMainJob = function() return P.main; end, GetMainJobLevel = function() return P.main_level; end,
    GetSubJob = function() return P.sub; end, GetSubJobLevel = function() return P.sub_level; end,
    -- The job's own level, which Level Sync leaves alone; dispel must not read it.
    GetJobLevel = function() return P.real_level; end,
    HasSpell = function(_, id) return P.spells[id] == true; end,
};
-- Inventory: container 0 slot index -> item id; the equipped ranged weapon and ammo by item id.
local I = { items = {}, ranged = 0, ammo = 0, max = 80 };
local resources = { [17000] = { Skill = 26 }, [17001] = { Skill = 26 }, [17002] = { Skill = 25 } };
local inventory = {
    GetContainerCountMax = function(_, container) return container == 0 and I.max or 0; end,
    GetContainerItem = function(_, container, index)
        if container == 9 then return { Id = index == 1 and I.ranged or I.ammo, Count = 1 }; end
        local id = container == 0 and I.items[index];
        return { Id = id or 0, Count = id and 1 or 0 };
    end,
    -- Slots 2 and 3 are the ranged weapon and the ammo, held in container 9 at 1 and 2.
    GetEquippedItem = function(_, slot)
        if slot == 2 and I.ranged > 0 then return { Index = 9 * 256 + 1 }; end
        if slot == 3 and I.ammo > 0 then return { Index = 9 * 256 + 2 }; end
        return { Index = 0 };
    end,
};
AshitaCore.GetMemoryManager = function() return { GetPlayer = function() return player; end, GetInventory = function() return inventory; end }; end;
AshitaCore.GetResourceManager = function() return { GetItemById = function(_, id) return resources[id]; end }; end;

local now = 100;
local function ready()
    -- Past the quarter second it keeps an answer, and past the second it keeps the cards.
    now = now + 1.5;
    return dispel.ready(now);
end
local function job(main, main_level, sub, sub_level, spells)
    P.main, P.main_level, P.sub, P.sub_level, P.real_level = main, main_level, sub or 0, sub_level or 0, main_level;
    P.spells = {};
    for _, id in ipairs(spells or {}) do P.spells[id] = true; end
end
local function set_packet(job_id, sub, spells)
    local bytes = MOCK.bytes(0x9C);
    bytes[0x04], bytes[0x05] = job_id, sub;
    for index, spell in ipairs(spells) do bytes[0x07 + index] = spell; end
    return MOCK.packet(0x044, bytes);
end

-- The list is Phoenix's, at its revision, less what can't exist there: 128 effects, buffs such as Haste, Protect and
-- Stoneskin, no 2-hours.
local count = 0;
for id, on in pairs(dispel.buffs) do assert(on == true and type(id) == 'number', 'Plain ids'); count = count + 1; end
assert(count == 128, 'Phoenix flags 180 effects dispelable, and 52 of them can\'t exist there: ' .. count);
assert(dispel.buffs[33] and dispel.buffs[40] and dispel.buffs[37] and dispel.buffs[43] and dispel.buffs[310],
    'Haste, Protect, Stoneskin, Refresh and the rolls are on it.');
assert(not dispel.buffs[600] and not dispel.buffs[277], 'An effect the catalog dropped is not.');
for id in pairs(dispel.buffs) do assert(require('data.catalog')[id], 'A dispelable effect is in the catalog: ' .. id); end
assert(not dispel.buffs[44] and not dispel.buffs[113] and not dispel.buffs[13] and not dispel.buffs[2],
    'Mighty Strikes, Reraise, Slow and Sleep are not.');

-- Dispel: RDM 32 main, learned.
job(5, 32, 0, 0, { 260 }); assert(ready() == true, 'RDM 32 with Dispel lights.');
job(5, 31, 0, 0, { 260 }); assert(ready() == false, 'RDM 31 does not.');
job(5, 75, 0, 0, {}); assert(ready() == false, 'A RDM without the Dispel scroll learned does not.');
-- From the sub job at sub level 32, which a level 64 main gives.
job(1, 64, 5, 32, { 260 }); assert(ready() == true, 'WAR 64 / RDM 32 lights.');
job(1, 63, 5, 31, { 260 }); assert(ready() == false, 'WAR 63 / RDM 31 does not.');
job(1, 75, 5, 37, {}); assert(ready() == false, 'A RDM sub without the spell learned does not.');
-- Level Sync: the client shows the synced level, and that is what counts, not the job's own 75.
job(5, 30, 1, 15, { 260 }); P.real_level = 75;
assert(player:GetJobLevel(5) == 75 and ready() == false, 'A RDM 75 synced to 30 does not light.');
job(1, 60, 5, 30, { 260 }); P.real_level = 75;
assert(ready() == false, 'Nor a RDM sub synced under 32.');

-- Magic Finale: BRD 33 main, or a BRD sub at 33 (main 66).
job(10, 33, 0, 0, { 462 }); assert(ready() == true, 'BRD 33 with Magic Finale lights.');
job(10, 32, 0, 0, { 462 }); assert(ready() == false, 'BRD 32 does not.');
job(10, 75, 0, 0, {}); assert(ready() == false, 'A BRD without the song does not.');
job(3, 66, 10, 33, { 462 }); assert(ready() == true, 'WHM 66 / BRD 33 lights.');
job(3, 65, 10, 32, { 462 }); assert(ready() == false, 'WHM 65 / BRD 32 does not.');
job(10, 30, 0, 0, { 462 }); P.real_level = 75; assert(ready() == false, 'A BRD synced to 30 does not.');

-- Blank Gaze: BLU 38 main, learned and set. 0x044 lists the set spells as spell id - 0x200, 80 for Blank Gaze.
job(16, 75, 0, 0, { 592 }); assert(ready() == false, 'Before any 0x044 the set is not known, so it does not light.');
dispel.packet(set_packet(16, 0, { 80, 3 })); assert(ready() == true, 'BLU 75 with Blank Gaze set lights.');
job(16, 38, 0, 0, { 592 }); assert(ready() == true, 'BLU 38 too.');
job(16, 37, 0, 0, { 592 }); assert(ready() == false, 'BLU 37 does not.');
job(16, 75, 0, 0, {}); assert(ready() == false, 'Set but not learned does not.');
job(16, 75, 0, 0, { 592 });
dispel.packet(set_packet(16, 0, { 3, 7 })); assert(ready() == false, 'Learned but not set does not.');
dispel.packet(set_packet(16, 1, { 80 })); assert(ready() == false, 'A sub job set list is not the main one.');
dispel.packet(set_packet(18, 0, { 80 })); assert(ready() == false, 'An automaton 0x044 is not a BLU set.');
dispel.packet(set_packet(16, 0, { 80 }));
job(1, 75, 16, 38, { 592 }); assert(ready() == false, 'Blank Gaze counts on the main job only.');
job(16, 30, 0, 0, { 592 }); P.real_level = 75; assert(ready() == false, 'A BLU synced to 30 does not.');

-- Dark Shot: COR 40 main, a Dark Card (2183) or Trump Card (2974) in the inventory, and a Marksmanship gun and ammo.
I.ranged, I.ammo = 17000, 17001;
job(17, 40); assert(ready() == false, 'COR 40 without a card does not light.');
I.items[12] = 2183; assert(ready() == true, 'COR 40 with a Dark Card lights.');
job(17, 39); assert(ready() == false, 'COR 39 does not.');
I.items[12] = 2974; job(17, 75); assert(ready() == true, 'A Trump Card works too.');
I.items[12] = 2176; assert(ready() == false, 'A Fire Card does not.');
I.items[30] = 2183;
I.ammo = 17002; assert(ready() == false, 'Arrows are not Marksmanship ammo.');
I.ammo = 0; assert(ready() == false, 'Nor is no ammo.');
I.ammo = 17001; assert(ready() == true, 'With bullets again it lights.');
job(1, 75, 17, 37); assert(ready() == false, 'Dark Shot counts on the main job only.');
job(17, 35); P.real_level = 75; assert(ready() == false, 'A COR synced to 35 does not.');

-- Any other job never lights.
for _, id in ipairs({ 1, 2, 3, 4, 6, 7, 8, 9, 11, 12, 13, 14, 15, 18 }) do
    job(id, 75, 5, 31, { 260, 462, 592 });
    assert(ready() == false, 'Job ' .. id .. ' has no tool.');
end

-- The answer is kept a quarter second, so a frame reads the client at most four times a second.
job(5, 75, 0, 0, { 260 });
now = now + 10;
assert(dispel.ready(now) == true);
job(1, 75);
assert(dispel.ready(now + 0.1) == true, 'Within a quarter second the last answer stands.');
assert(dispel.ready(now + 0.3) == false, 'After it the client is read again.');
-- Packets that are not a BLU 0x044 are left alone.
dispel.packet({ id = 0x00E, data = '', size = 0 });
dispel.packet(set_packet(16, 0, { 80 }));
local injected = set_packet(16, 0, {});
injected.injected = true;
dispel.packet(injected);
job(16, 75, 0, 0, { 592 });
assert(dispel.ready(now + 1) == true, 'An injected 0x044 changes nothing.');
