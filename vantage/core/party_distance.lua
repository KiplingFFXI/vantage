-- How far each party and alliance member is from you, for Party list (party_ui.distance). The members are
-- marked at the refresh, only while Party list and the distance are on, and ui/native_party_hud.lua draws the
-- number. It's worked out from the client's X, Y and Z positions, not the game's own distance value the Pet display
-- reads (core/pet_lines.lua), so it counts height whatever that value does. Display only.
--
-- Phoenix at revision 9785020970:
-- - Range is the straight line between two positions, height included (src/common/utils.h :90-101).
-- - A spell on one member reaches its range plus the target's hitbox and the caster's
--   (src/map/ai/states/magic_state.cpp :425 and :435). Cure, Raise, Haste, Protect, Shell, Regen, Refresh and the
--   -na spells have a range of 20 (sql/spell_list.sql :170, :181, :226, :212, :217, :277, :278 and :183,
--   spell_range 200 read in tenths at src/map/spell.cpp :536).
-- - A player's hitbox comes from their race: 0.3 for a Tarutaru, 0.8 for a Galka and 0.4 for anyone else
--   (src/map/utils/charutils.cpp :1248-1263, races in src/map/entities/char_entity.h :300-310).
-- - An area effect reaches a member within its radius (src/map/ai/helpers/targetfind.cpp :646-649), but not one 8 or
--   more yalms above or below its center (:546-550). It takes your own party only, as nothing asks for the alliance
--   (:155-166, FINDFLAGS_ALLIANCE is never passed). Songs, Protectra, Shellra and the Circles have a radius of 10
--   (sql/spell_list.sql :294, :299 and :548, sql/abilities.sql :67, :70, :84 and :85). Phantom Roll has 8
--   (sql/abilities.sql :118), and Luzaf's Ring adds 8 more (sql/item_mods.sql :29481,
--   scripts/combat/basic/ability_aoe.lua :35-41). A Bard with a string instrument stretches songs up to twice as far
--   (scripts/combat/basic/magic_aoe.lua :13-43), which isn't counted here.
-- - The game shows another player within 50 yalms and 20 above or below you (src/map/zone_entities.cpp :78-96). A
--   member it isn't showing gets no number, like one in another zone.
local distance = {};
local bit = require('bit');
local finite = require('ui.numbers').finite;
local band, floor, sqrt, abs = bit.band, math.floor, math.sqrt, math.abs;

-- Spell range and each race's hitbox, in tenths of a yalm, so the color goes by the number you see.
local REACH = 200;
local SIZES = { [5] = 3, [6] = 3, [8] = 8 };
local SIZE = 4;
-- The area picks' radius in tenths, and the height an area effect stops at.
local AREAS = { ten = 100, eight = 80, sixteen = 160 };
local HEIGHT = 8;
-- The samples by slot, in tenths, colored as if both of you were Hume.
local SAMPLES = { 42, 96, 143, 204, 219, 306 };
local HUME_REACH = REACH + SIZE * 2;

local call = require('core.guard').call;

local function entity_index(value)
    return type(value) == 'number' and value > 0 and value <= 0x8FF and value == floor(value);
end

local function position(entities, index)
    local x, y, z = call(entities, 'GetLocalPositionX', index), call(entities, 'GetLocalPositionY', index),
        call(entities, 'GetLocalPositionZ', index);
    if finite(x) and finite(y) and finite(z) then return x, y, z; end
end

-- The Overhead icons' drawn test for a party member (core/overhead.lua place), without its KO check, so a member who
-- is KO'd keeps their number for a Raise: the client still holds them at that index, has their model and draws them.
local function drawn(entities, index, id)
    if call(entities, 'GetServerId', index) ~= id then return false; end
    local actor = call(entities, 'GetActorPointer', index);
    if type(actor) ~= 'number' or actor == 0 then return false; end
    local flags = call(entities, 'GetRenderFlags0', index);
    return type(flags) == 'number' and band(flags, 0x200) ~= 0 and band(flags, 0x4000) == 0;
end

local function size_of(entities, index)
    local race = call(entities, 'GetRace', index);
    if type(race) ~= 'number' or race < 1 or race > 8 or race ~= floor(race) then return nil; end
    return SIZES[race] or SIZE;
end

-- Whether a distance of tenths is past the pick: spell (Spell range, reach in tenths), ten, eight, sixteen or none. The
-- area picks also take a member steep above or below you, and never an alliance member (group past 1).
function distance.past(tenths, reach, steep, pick, group)
    if pick == 'spell' then return reach ~= nil and tenths > reach; end
    local radius = AREAS[pick];
    if not radius or group ~= 1 then return false; end
    return steep == true or tenths > radius;
end

-- Each member in your zone the game is showing gets tenths (the distance in tenths of a yalm), reach (Spell range in
-- tenths, nil when a race can't be read), steep (8 or more yalms above or below you) and far (past config's pick).
-- Everyone else, you included, gets none.
function distance.mark(roster, snapshot, config)
    local members = type(roster) == 'table' and roster.members;
    if type(members) ~= 'table' then return; end
    for _, member in ipairs(members) do member.tenths, member.reach, member.steep, member.far = nil, nil, nil, nil; end
    if roster.valid ~= true or type(snapshot) ~= 'table' or type(snapshot.entities) ~= 'table' then return; end
    local own = snapshot.entities[snapshot.id];
    local index = own and own.index;
    if not entity_index(index) then return; end
    local entities = call(call(AshitaCore, 'GetMemoryManager'), 'GetEntity');
    if not entities or call(entities, 'GetServerId', index) ~= snapshot.id then return; end
    local x, y, z = position(entities, index);
    if not x then return; end
    local own_size, pick = size_of(entities, index), type(config) == 'table' and config.distance_warn or nil;
    for _, member in ipairs(members) do
        local entry = member.id ~= snapshot.id and member.available and snapshot.entities[member.id];
        local at = entry and entry.index;
        if entity_index(at) and drawn(entities, at, member.id) then
            local mx, my, mz = position(entities, at);
            if mx then
                local dx, dy, dz = mx - x, my - y, mz - z;
                local tenths = floor(sqrt(dx * dx + dy * dy + dz * dz) * 10 + 0.5);
                if tenths < 1000 then
                    local size = own_size and size_of(entities, at);
                    -- Z is the height (core/overhead.lua world_point).
                    member.tenths, member.steep = tenths, abs(dz) >= HEIGHT;
                    member.reach = size and REACH + own_size + size or nil;
                    member.far = distance.past(tenths, member.reach, member.steep, pick, member.group);
                end
            end
        end
    end
end

-- The text for a distance in tenths, like 20.4, made once for each tenth and kept, so drawing it makes nothing.
local texts = {};
function distance.text(tenths)
    if type(tenths) ~= 'number' or tenths < 0 or tenths >= 1000 or tenths ~= floor(tenths) then return ''; end
    local text = texts[tenths];
    if not text then
        text = ('%.1f'):format(tenths / 10);
        texts[tenths] = text;
    end
    return text;
end

-- A slot's sample in tenths and whether it's past the pick.
function distance.sample(slot, group, pick)
    local tenths = SAMPLES[(type(slot) == 'number' and floor(slot) or 0) % 6 + 1];
    return tenths, distance.past(tenths, HUME_REACH, false, pick, group);
end

local AREA_LINES = {
    ten = 'Songs, Protectra, Shellra and the Circles reach 10 yalms around you.',
    eight = 'Phantom Roll reaches 8 yalms around you.',
    sixteen = 'Phantom Roll with Luzaf\'s Ring reaches 16 yalms around you.',
};

-- The tooltip for a member's number, made only while you point at it. config is party_ui's.
function distance.details(member, config)
    local sample = config.preview == true;
    local tenths, reach, steep = member.tenths, member.reach, member.steep;
    if sample then tenths, reach, steep = distance.sample(member.slot, member.group), HUME_REACH, false; end
    local lines = { member.name or 'Member' };
    if tenths then lines[2] = distance.text(tenths) .. ' yalms from you, counting height.'; end
    local pick = config.distance_warn;
    if pick == 'spell' and reach then
        lines[#lines + 1] = 'Spells you cast on one member, such as Cure, reach them up to ' .. distance.text(reach) .. ' yalms away.';
    elseif AREA_LINES[pick] then
        lines[#lines + 1] = AREA_LINES[pick];
        if member.group ~= 1 then lines[#lines + 1] = 'They\'re in another party of the alliance, so these don\'t reach them.';
        elseif steep then lines[#lines + 1] = 'They\'re 8 or more yalms above or below you, so these miss them.'; end
    end
    if sample then lines[#lines + 1] = 'This is a sample.'; end
    return table.concat(lines, '\n');
end

return distance;
