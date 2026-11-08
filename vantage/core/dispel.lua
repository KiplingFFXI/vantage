-- Whether you can take a buff off a mob right now, by the checks Phoenix makes (revision 730ac619c0), so the
-- overhead icons and the target and watched enemy panels can light the mob buffs you can remove, and which debuffs
-- your spells can take off you and your allies, for the same light. It reads the client and one packet; it casts
-- nothing and sends nothing. The buffs and debuffs themselves are in data/dispelable.lua and data/cleansable.lua.
local dispel = {};
local client = require('core.client');
dispel.buffs = require('data.dispelable');
local DEBUFFS = require('data.cleansable');

-- Dispel, Magic Finale and Blank Gaze are spells you have to learn (src/map/spell.cpp:759 and :807, hasSpell in
-- src/map/entities/char_entity.cpp:1440). Their job levels are the jobs bytes of sql/spell_list.sql: Dispel RDM 32
-- (:429), Magic Finale BRD 33 (:632), Blank Gaze BLU 38 (:759). Dispel and Finale work from the sub job at that sub
-- level, so at 64 and 66 with Phoenix's usual half-level sub job. Dark Shot is COR 40 (sql/abilities.sql:152) and
-- learned with the level.
local RDM, BRD, BLU, COR = 5, 10, 16, 17;
local DISPEL, FINALE, BLANK_GAZE = 260, 462, 592;
local DISPEL_LEVEL, FINALE_LEVEL, BLANK_GAZE_LEVEL, DARK_SHOT_LEVEL = 32, 33, 38, 40;
-- Dark Shot needs a Dark Card or a Trump Card in the inventory (scripts/enum/item.lua:1549, :2105) and a
-- Marksmanship weapon and ammo (scripts/globals/job_utils/corsair.lua:899-911).
local DARK_CARD, TRUMP_CARD, MARKSMANSHIP = 2183, 2974, 26;
local RANGED, AMMO, INVENTORY = 2, 3, 0;

-- The blue magic set on your main job, from 0x044: Job at 0x04 (16 for BLU), IsSubJob at 0x05, then 20 set spells
-- from 0x08, each its spell id - 0x200 (src/map/packets/s2c/0x044_extended_job_blu.h:38-41,
-- src/map/utils/blueutils.cpp:71). Phoenix sends it at every zone-in and when the set changes.
local set_spells, set_seen = {}, false;

-- pcall(index_of, object, key) guards a lookup without making a closure for it.
local function index_of(object, key) return object[key]; end
local function call(object, method, a, b)
    if not object then return nil; end
    local ok, fn = pcall(index_of, object, method);
    if not ok or type(fn) ~= 'function' then return nil; end
    local done, value = pcall(fn, object, a, b);
    if done then return value; end
end
local function number(value) return type(value) == 'number' and value == value and value or 0; end
local function truth(value) return value == true or value == 1; end

-- Ashita hands it userdata, the tests a table.
function dispel.packet(e)
    local kind = type(e);
    if kind ~= 'userdata' and kind ~= 'table' or e.id ~= 0x044 or e.injected or e.blocked then return; end
    local data = e.data;
    if client.packet_size(e) < 0x1C or data:byte(0x05) ~= BLU or data:byte(0x06) ~= 0 then return; end
    for key in pairs(set_spells) do set_spells[key] = nil; end
    for offset = 0x08, 0x1B do
        local spell = data:byte(offset + 1);
        if spell ~= 0 then set_spells[spell] = true; end
    end
    set_seen = true;
end

-- One of the cards in the inventory, and a Marksmanship weapon and ammo equipped. Read at most once a second.
local cards_at, cards = -1, false;
local function marksmanship(inventory, resources, slot)
    local equipped = call(inventory, 'GetEquippedItem', slot);
    local index = equipped and number(equipped.Index) or 0;
    if index <= 0 then return false; end
    local item = call(inventory, 'GetContainerItem', math.floor(index / 256), index % 256);
    local resource = item and call(resources, 'GetItemById', number(item.Id));
    return resource ~= nil and resource.Skill == MARKSMANSHIP;
end
local function dark_shot_ready(manager, now)
    if now - cards_at < 1 and now >= cards_at then return cards; end
    cards_at, cards = now, false;
    local inventory, resources = call(manager, 'GetInventory'), call(AshitaCore, 'GetResourceManager');
    if not inventory or not marksmanship(inventory, resources, RANGED) or not marksmanship(inventory, resources, AMMO) then return false; end
    for index = 1, number(call(inventory, 'GetContainerCountMax', INVENTORY)) do
        local item = call(inventory, 'GetContainerItem', INVENTORY, index);
        local id = item and number(item.Id) or 0;
        if (id == DARK_CARD or id == TRUMP_CARD) and number(item.Count) > 0 then cards = true; break; end
    end
    return cards;
end

-- Your main or sub job is id at level or above.
local function job(id, level, main, main_level, sub, sub_level)
    return main == id and main_level >= level or sub == id and sub_level >= level;
end

-- The job levels are the ones the client shows now: Level Sync lowers both (Phoenix sends GetMLevel and GetSLevel
-- in 0x061, src/map/packets/s2c/0x061_clistatus.cpp:39-41), and that is what it checks a cast against.
local function check(now)
    local manager = call(AshitaCore, 'GetMemoryManager');
    local player = call(manager, 'GetPlayer');
    if not player then return false; end
    local main, main_level = number(call(player, 'GetMainJob')), number(call(player, 'GetMainJobLevel'));
    local sub, sub_level = number(call(player, 'GetSubJob')), number(call(player, 'GetSubJobLevel'));
    if job(RDM, DISPEL_LEVEL, main, main_level, sub, sub_level) and truth(call(player, 'HasSpell', DISPEL)) then return true; end
    if job(BRD, FINALE_LEVEL, main, main_level, sub, sub_level) and truth(call(player, 'HasSpell', FINALE)) then return true; end
    -- Blank Gaze and Dark Shot are past what a sub job reaches at level 75, so only your main job counts.
    if main == BLU and main_level >= BLANK_GAZE_LEVEL and set_seen and set_spells[BLANK_GAZE - 0x200]
        and truth(call(player, 'HasSpell', BLANK_GAZE)) then return true; end
    if main == COR and main_level >= DARK_SHOT_LEVEL and dark_shot_ready(manager, now) then return true; end
    return false;
end

-- Worked out at most four times a second.
local checked_at, ready = -1, false;
function dispel.ready(now)
    if now - checked_at < 0.25 and now >= checked_at then return ready; end
    checked_at, ready = now, check(now);
    return ready;
end

-- The White Mage levels of the spells in data/cleansable.lua, by spell id: the jobs bytes of sql/spell_list.sql:183-189
-- and :312 at phoenix/live (ed41f351f6). No other job that's open on Phoenix has them. They work from the sub job at
-- that sub level, which stops Stona at 37. Like Dispel they have to be learned.
local WHM, ERASE = 3, 143;
local CLEANSE_LEVEL = { [14] = 6, [15] = 9, [16] = 14, [17] = 19, [20] = 29, [143] = 32, [19] = 34, [18] = 39 };

-- What you can take off now, by effect id: near on you and your party, far on the alliance. Erase reaches your party
-- only (validTargets 3 in that file), and the others any player (91). Samples light whatever your job, with the same
-- reach.
local near, far, learned = {}, {}, {};
local sample_near, sample_far = {}, {};
for effect, spell in pairs(DEBUFFS) do sample_near[effect], sample_far[effect] = true, spell ~= ERASE; end

local function cleanse_check()
    local player = call(call(AshitaCore, 'GetMemoryManager'), 'GetPlayer');
    local main, main_level = number(call(player, 'GetMainJob')), number(call(player, 'GetMainJobLevel'));
    local sub, sub_level = number(call(player, 'GetSubJob')), number(call(player, 'GetSubJobLevel'));
    for spell, level in pairs(CLEANSE_LEVEL) do
        learned[spell] = job(WHM, level, main, main_level, sub, sub_level) and truth(call(player, 'HasSpell', spell));
    end
    for effect, spell in pairs(DEBUFFS) do near[effect], far[effect] = learned[spell], learned[spell] and spell ~= ERASE; end
end

-- Hands back the two sets, worked out at most four times a second into the same tables, so a draw looks an effect up
-- and asks the game nothing.
local cleansed_at = -1;
function dispel.cleansable(now, sample)
    if sample then return sample_near, sample_far; end
    if now - cleansed_at >= 0.25 or now < cleansed_at then
        cleansed_at = now;
        cleanse_check();
    end
    return near, far;
end

if VANTAGE_TEST_MODE then
    function dispel._reset()
        for key in pairs(set_spells) do set_spells[key] = nil; end
        for key in pairs(near) do near[key], far[key] = nil, nil; end
        for key in pairs(learned) do learned[key] = nil; end
        set_seen, checked_at, ready, cards_at, cards, cleansed_at = false, -1, false, -1, false, -1;
    end
end

return dispel;
