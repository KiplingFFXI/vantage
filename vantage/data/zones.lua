-- The kind of each zone in era, for the show conditions (core/conditions.lua). From Phoenix: the type list of each
-- data/zones/<name>/zone.yaml (city, outdoors, dungeon, dynamis, instanced; data/enums/zone_type.yaml) with the zone
-- ids of data/enums/zone.yaml. Zones of later content (the [S] zones, Abyssea, Adoulin) are left out and read as other
-- zones, as do the ferries to Selbina and Mhaura (220, 221) and the battlefield arenas, which have no type. Limbus,
-- Assault, Salvage and Nyzul Isle are named by their zones. A battlefield is the Battlefield status (254) and a Mog
-- House the zone-in packet's login state, both in core/conditions.lua.
local function range(list, from, to) for id = from, to do list[#list + 1] = id; end return list; end

local town = range({ 26, 32, 48, 50, 70, 71 }, 230, 252);
local field = { 1, 2, 3, 4, 5, 7, 24, 25, 33, 46, 47, 51, 52, 53, 54, 58, 59, 61, 79, 130 };
range(field, 100, 128); range(field, 223, 228);
local dungeon = { 9, 11, 12, 14, 16, 18, 20, 22, 27, 28, 29, 30, 34, 35, 62, 65, 68, 72, 131, 140, 141, 142, 143, 145,
    157, 158, 159, 160, 161, 162, 166, 167, 169, 172, 173, 174, 176, 177, 178, 184, 200, 204, 205, 208, 212, 213 };
range(dungeon, 147, 154); range(dungeon, 190, 198);

return {
    town = town,
    field = field,
    dungeon = dungeon,
    dynamis = { 39, 40, 41, 42, 134, 135, 185, 186, 187, 188 },
    limbus = { 37, 38 },
    assault = { 55, 56, 63, 66, 69 },
    salvage = { 73, 74, 75, 76 },
    nyzul = { 77 },
    ashu_talif = { 60 },
};
