-- A world for the overhead icon tests: entities by index, the party, your target, the camera and the screen. Every
-- getter reads tables made here, so a frame allocates nothing of the fixture's own.
-- The camera sits 2 yalms up at Y = 10 and looks along -Y, so a unit at Y = -d is d + 10 yalms deep.
local W = { entities = {}, self = 0x400, target = 0, sub = 0, sub_active = 0, zoning = 0, first_person = 0, party_zone = 102 };
local function at(index) return W.entities[index]; end
local entity = {
    GetServerId = function(_, i) local e = at(i); return e and e.id or 0; end,
    GetName = function(_, i) local e = at(i); return e and e.name or ''; end,
    GetLocalPositionX = function(_, i) local e = at(i); return e and e.x or 0; end,
    GetLocalPositionZ = function(_, i) local e = at(i); return e and e.z or 0; end,
    GetLocalPositionY = function(_, i) local e = at(i); return e and e.y or 0; end,
    GetActorPointer = function(_, i) local e = at(i); return e and e.actor or 0; end,
    GetRenderFlags0 = function(_, i) local e = at(i); return e and e.flags or 0; end,
    GetStatus = function(_, i) local e = at(i); return e and e.status or 0; end,
    GetHPPercent = function(_, i) local e = at(i); return e and e.hpp or 0; end,
    GetSpawnFlags = function(_, i) local e = at(i); return e and e.spawn or 0; end,
    GetType = function(_, i) local e = at(i); return e and e.type or 0; end,
    GetRace = function(_, i) local e = at(i); return e and e.race or 0; end,
    GetModelHitboxSize = function(_, i) local e = at(i); return e and e.hitbox or 0; end,
    GetModelSize = function(_, i) local e = at(i); return e and e.model or -1; end,
    -- The flags the game picks a name's icons from, all clear unless a unit sets them.
    GetRenderFlags1 = function(_, i) local e = at(i); return e and e.flags1 or 0; end,
    GetRenderFlags2 = function(_, i) local e = at(i); return e and e.flags2 or 0; end,
    GetRenderFlags3 = function(_, i) local e = at(i); return e and e.flags3 or 0; end,
    GetRenderFlags4 = function(_, i) local e = at(i); return e and e.flags4 or 0; end,
    GetRenderFlags7 = function(_, i) local e = at(i); return e and e.flags7 or 0; end,
    GetRenderFlags8 = function(_, i) local e = at(i); return e and e.flags8 or 0; end,
    GetCampaignNameFlag = function(_, i) local e = at(i); return e and e.campaign or 0; end,
    GetBallistaFlags = function(_, i) local e = at(i); return e and e.ballista or 0; end,
    GetMonstrosityFlag = function(_, i) local e = at(i); return e and e.monstrosity or 0; end,
    GetPetTargetIndex = function(_, i) local e = at(i); return e and e.pet or 0; end,
    -- Squared, as Ashita's is.
    GetDistance = function(_, i)
        local e, me = at(i), at(W.self);
        if not e or not me then return 0; end
        return (e.x - me.x) ^ 2 + (e.y - me.y) ^ 2 + (e.z - me.z) ^ 2;
    end,
};
-- The mock's own player and party (you are 1001 at index 0x400 in zone 102), with zoning and your zone settable here.
local base = AshitaCore:GetMemoryManager();
local party, player = base:GetParty(), base:GetPlayer();
local zone, zoning = party.GetMemberZone, player.GetIsZoning;
party.GetMemberZone = function(self, slot) if slot == 0 then return W.party_zone; end return zone(self, slot); end;
player.GetIsZoning = function(self) return W.zoning == 1 or zoning(self); end;
local targets = {
    GetTargetIndex = function(_, which) if which == 0 then return W.sub_active == 1 and W.sub or W.target; end; return W.target; end,
    GetIsSubTargetActive = function() return W.sub_active; end,
};
local follow = { GetIsFirstPersonCamera = function() return W.first_person; end };
local manager = { GetEntity = function() return entity; end, GetParty = function() return party; end,
    GetPlayer = function() return player; end, GetTarget = function() return targets; end, GetAutoFollow = function() return follow; end };
AshitaCore.GetMemoryManager = function() return manager; end;
local io_table = { DisplaySize = { x = 1920, y = 1080 } };
W.io = io_table;
rawset(require('imgui'), 'GetIO', function() return io_table; end);

-- The view and projection the camera reads: see the top. P22 1.7, 16:9, near 0.5, far 200.
local q = 200 / (200 - 0.5);
W.view_matrix = { 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, -1, 0, 0, -2, 10, 1 };
W.projection_matrix = { 1.7 * 9 / 16, 0, 0, 0, 0, 1.7, 0, 0, 0, 0, q, 1, 0, 0, -0.5 * q, 0 };
W.reads = 0;
local camera = require('core.camera');
camera._set_reader(function(view, projection)
    W.reads = W.reads + 1;
    if W.unreadable then return false; end
    for i = 1, 16 do view[i], projection[i] = W.view_matrix[i], W.projection_matrix[i]; end
    return true;
end);

-- A unit at world X, Y (Z, the height, 0), drawn and alive. kind: 'mob', 'player', 'pet' or 'npc'.
function W.unit(index, id, kind, x, y, fields)
    local e = { id = id, name = 'Unit ' .. index, x = x, y = y, z = 0, actor = 0x2000000, flags = 0x200, status = 0, hpp = 100,
        spawn = kind == 'mob' and 0x10 or kind == 'player' and 0x01 or 0x02, type = kind == 'npc' and 2 or (kind == 'player' and 0 or 1),
        race = kind == 'player' and 1 or 0, hitbox = kind == 'player' and 0.4 or 1.5, model = -1 };
    for key, value in pairs(fields or {}) do e[key] = value; end
    W.entities[index] = e;
    return e;
end
W.unit(W.self, 1001, 'player', 0, 0, { name = 'Tester' });

-- The frames here call overhead.update with no BeginScene before them, so these settings read the camera at present.
-- Scene reading, the default, has tests of its own.
function W.settings()
    local settings = require('ui.defaults').make();
    settings.overhead.enabled, settings.overhead.camera.capture = true, 'present';
    return settings;
end

function W.snapshot(members)
    local snapshot = { valid = true, id = 1001, zone = 102, entities = { [1001] = { id = 1001, index = W.self } }, party = {} };
    for _, member in ipairs(members or {}) do snapshot.party[#snapshot.party + 1] = member; end
    return snapshot;
end

-- A view with one debuff row on each entity id given, which every type shows at first, or the rows given.
function W.view(rows)
    local view = { rows = {}, subjects = {} };
    for _, row in ipairs(rows or {}) do
        if type(row) == 'number' then row = { entity_id = row, kind = 'debuff', scope = 'other' }; end
        view.rows[#view.rows + 1] = row;
    end
    return view;
end

-- The ids in the plan, best first, as a string.
function W.ids(plan)
    local out = {};
    for i = 1, plan.count do out[i] = tostring(plan.units[i].id); end
    return table.concat(out, ' ');
end

-- Frames are 0.125 s apart unless a test says (exact in binary), so each one makes the unit list again.
W.now = 100;
function W.frame(view, settings, snapshot, hidden, seconds)
    W.now = W.now + (seconds or 0.125);
    return require('core.overhead').update(view, settings, snapshot, W.now, hidden);
end

return W;
