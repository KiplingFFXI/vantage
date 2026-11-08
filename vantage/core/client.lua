-- Reads only the state the client already has.
local client = {};
local bit = require('bit');
local finder = require('core.patterns');
local jobs = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM',
    'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP' };
local party_cache, merit_cache, entity_cache, deadline_cache = {}, {}, {}, {};
local owner, zone, expected_id, expected_zone, waiting, revision = nil, nil, nil, nil, false, 0;
-- Counts lifecycle resets only; status packets move revision, not this.
local epoch = 0;
-- Counts the 0x063 status timer updates taken, so an observation can tell whether one came after it.
local timer_revision = 0;
-- clock is core/clock.lua once it has looked for the game clock, false without one, nil before it has looked.
local clock, event_flag, interface, focus_slot = nil, 0, 0, 0;
local cached_entities = 0;
local party_revision = 0;
local native_blocked, native_bootstrap = {}, true;
local pending_party, party_window;
local party_awaiting_ready = false;
local roster_snapshot;
-- Your pet: pet_known as the last read left it, held while it is out of your view (away); pet_sync what the last 0x068
-- said of it; pet_gone the one a 0x068 said left, which the client can still name for a moment.
local pet_known, pet_sync, pet_gone;
-- Your status icons as the last 0x037 gave them, and whether they changed since the last ask.
local icons_low, icons_high, icons_changed = nil, nil, false;
-- Ids no index answered, kept until the next read: an observation about someone out of view, or a watched id out of
-- range, would otherwise be looked for again and again.
local unresolved, unresolved_count = {}, 0;
-- Inside a Present the UI flags are read once and held, for the refresh, the check between refreshes and the overhead
-- icons alike. Outside one, every read is fresh.
local in_frame, flags_held, held_hidden, held_event, held_map = false, false, nil, nil, nil;

-- pcall(index_of, object, key) guards a lookup without making a closure for it.
local function index_of(object, key) return object[key]; end

local function call(object, name, ...)
    if object == nil then return nil; end
    local ok, fn = pcall(index_of, object, name);
    if not ok or type(fn) ~= 'function' then return nil; end
    local success, result = pcall(fn, object, ...);
    if success then return result; end;
end

local function finite(n)
    return type(n) == 'number' and n == n and math.abs(n) < math.huge;
end

local function positive(n) return finite(n) and n > 0 and n == math.floor(n); end
local function truth(value) return value == true or value == 1; end
local function character_name(value)
    if type(value)~='string' or value=='' or #value>40 or value:find('[%c]')
        or value:gsub('[^%w_-]','')=='' then return nil;end;
    return value;
end;
local function array_base(array)
    if array == nil then return nil; end
    local kind = type(array);
    if kind == 'cdata' then return 0; end
    if kind == 'table' then
        if rawget(array, 0) ~= nil then return 0; end
        if rawget(array, 32) ~= nil then return 1; end
    elseif kind == 'userdata' then
        local first_ok, first = pcall(index_of, array, 0);
        if first_ok and first ~= nil then return 0; end
        local last_ok, last = pcall(index_of, array, 32);
        if last_ok and last ~= nil then return 1; end
    end
    return nil;
end
local function at(array, index)
    if array == nil then return nil, nil, false; end
    local ok, value = pcall(index_of, array, index);
    if not ok then return nil, nil, false; end
    return tonumber(value), value, true;
end
-- The client lists your buffs from the 0x037 array (GetBuffs), where an empty slot is 0xFFFF.
-- Returns the effect (0 when empty) or nil when the value isn't a valid slot.
local function self_id(value)
    if value == -1 or value == 65535 then return 0; end
    if finite(value) and value >= 0 and value <= 1023 and value == math.floor(value) then return value; end
end
-- The 0x063 icons list the same effects as the 0x037 buff array, slot by slot. When a 0x037 arrives
-- without its 0x063 (a split send) the old icons and timers describe slots that have moved, so no slot
-- timer is trusted until both agree again. A 0x037 that changes nothing (Phoenix sends one after HP, MP
-- or TP changes) keeps them in agreement.
local function icons_agree(ids, id_base, icons, icon_base)
    if ids == icons then return true; end
    if id_base == nil or icon_base == nil then return false; end
    for slot = 0, 31 do
        local effect = self_id(at(ids, slot + id_base));
        local icon = at(icons, slot + icon_base);
        if effect == 255 then effect = 0; end
        if icon == 255 or icon == -1 or icon == 65535 then icon = 0; end
        if effect == nil or effect ~= icon then return false; end
    end
    return true;
end
local function diagnostic_value(value, number)
    if finite(number) then return number; end
    if type(value) == 'string' then return value:sub(1, 64); end
    if type(value) == 'boolean' then return value; end
    if type(value) == 'number' then return tostring(value); end
    return type(value);
end

local function memory()
    return call(AshitaCore, 'GetMemoryManager');
end

-- Every raw read checks its pages first, so memory the client has freed reads as nothing instead of faulting
-- the game. A run of reads checks its whole range once and reads it with checked.
local pages;
local function readable(address, size)
    if pages == nil then
        local ok, value = pcall(require('core.memory').pages);
        pages = ok and type(value) == 'table' and value.valid or false;
    end
    return pages ~= false and pages(address, size, false) == true;
end

local function native_read(name, address, checked)
    if not positive(address) or not ashita or not ashita.memory then return nil; end
    if not checked and not readable(address, name == 'read_uint8' and 1 or 4) then return nil; end
    local ok, value = pcall(ashita.memory[name], address);
    return ok and value or nil;
end

-- The first match of the pattern, with no second search, and the address its operand holds; 0 without one.
local function pointer(pattern, offset, operand)
    if not ashita or not ashita.memory or not ashita.memory.find then return 0; end
    local found = finder.find('client', 'pointer', pattern, { offset = offset, accept = positive });
    if not found then return 0; end
    return native_read('read_uint32', found + operand) or 0;
end

-- The event, interface and map focus flags, found by one warmup step. The game clock has steps of its own in
-- core/clock.lua.
local done = {};
local STEP = finder.step('client.pointers', done, function()
    event_flag = pointer('A0????????84C0741AA1????????85C0741166A1????????663B05????????0F94C0C3', 0, 1);
    interface = pointer('8B4424046A016A0050B9????????E8????????F6D81BC040C3', 0, 10);
    focus_slot = pointer('8B480C85C974??8B510885D274??3B05', 16, 0);
    -- The focus slot sits 0x54 past the interface flags. Anywhere else means one of the two patterns matched the wrong
    -- code, so neither is used.
    if focus_slot ~= 0 and focus_slot ~= interface + 0x54 then interface, focus_slot = 0, 0; end
end);

-- The client reader's warmup steps, in order, as { name, run }: the flags only.
function client.warmup_steps() return { STEP }; end

-- The flags' step, which the first read runs when nothing ran it before. A read never looks for the clock.
local function pointers()
    if not done['client.pointers'] then STEP.run(); end
end

-- Finds the flags and the game clock: the flags' step and core/clock.lua's steps, those not run.
function client.load()
    pointers();
    local ok, value = pcall(require, 'core.clock');
    if ok and type(value) == 'table' and type(value.load) == 'function' then pcall(value.load); end
end

-- core/clock.lua once it has looked for the game clock, or nil. Looking scans the client, so a read never starts it:
-- the clock's warmup steps, client.capabilities and /vg report do. A clock module without loaded() is taken as it is.
local function game_clock()
    if clock ~= nil then return clock or nil; end
    local ok, value = pcall(require, 'core.clock');
    if not ok or type(value) ~= 'table' or type(value.get_game_time_raw) ~= 'function' or type(value.available) ~= 'function' then
        clock = false;
        return nil;
    end
    if type(value.loaded) == 'function' and not value.loaded() then return nil; end
    clock = value.available() and value or false;
    return clock or nil;
end

function client.reset()
    roster_snapshot = nil;
    party_cache, merit_cache, entity_cache, deadline_cache = {}, {}, {}, {};
    owner, zone, expected_id, expected_zone, waiting = nil, nil, nil, nil, false;
    revision = revision + 1;
    epoch = epoch + 1;
    cached_entities = 0;
    native_blocked, native_bootstrap = {}, true;
    pending_party, party_window = nil, nil;
    party_awaiting_ready = false;
    pet_known, pet_sync, pet_gone = nil, nil, nil;
    icons_low, icons_high = nil, nil;
    if unresolved_count > 0 then unresolved, unresolved_count = {}, 0; end
end

local function cache_entity(row)
    if not entity_cache[row.id] then cached_entities=cached_entities+1; end;
    if cached_entities>128 then entity_cache,cached_entities={},1; end;
    entity_cache[row.id]=row;
end

-- What the client patterns found. Through client.load it finishes looking for the game clock when nothing has yet, so
-- timers is never a guess for a caller that keeps this table (core/overhead.lua does).
function client.capabilities()
    client.load();
    return { timers = game_clock() ~= nil, map = focus_slot ~= 0, hidden = interface ~= 0, event = event_flag ~= 0 };
end

-- Whether self timers have the game clock, for /vg report.
function client.clock_status()
    local ok, value = pcall(require, 'core.clock');
    if ok and type(value) == 'table' and type(value.status) == 'function' then
        local read, status = pcall(value.status);
        if read and type(status) == 'table' then return status; end
    end
    local found = game_clock();
    return { available = found ~= nil, reason = found and 'Your own buffs and debuffs count down with the game clock.'
        or 'The game clock is unavailable, so your own buffs and debuffs show without a countdown.' };
end

-- Both values use the client's wrapping 60 Hz status clock.
function client.remaining(raw, current)
    if not finite(raw) or not finite(current) or raw <= 0 or raw == 0x7FFFFFFF then return nil; end
    local ticks = (raw - current + 2147483648) % 4294967296 - 2147483648;
    if ticks < 0 or ticks > 366 * 86400 * 60 then return nil; end
    return ticks / 60;
end

local function current_time()
    local source = game_clock();
    if not source then return nil; end
    local ok, raw = pcall(source.get_game_time_raw);
    if ok and finite(raw) and raw > 0 then return (raw * 60) % 4294967296; end
end

local function native_party_effects(party, entry)
    local icons, mask = call(party,'GetStatusIcons',entry), call(party,'GetStatusIconsBitMask',entry);
    local base=array_base(icons);
    local pointer=positive(icons) and icons>=65536 and icons<=4294967295 and icons or nil;
    if base==nil and not pointer then return nil; end
    if pointer and not readable(pointer, 32) then return nil; end
    if type(mask)~='cdata' and (not finite(mask) or mask<0 or mask>9007199254740991 or mask~=math.floor(mask)) then return nil; end
    local effects, signature={},{};
    for slot=0,31 do
        local low;
        if pointer then low=native_read('read_uint8',pointer+slot,true); else low=at(icons,slot+base); end
        local high;
        if type(mask)=='cdata' then
            local ok,value=pcall(function() return tonumber(bit.band(bit.rshift(mask,slot*2),3)); end);
            if ok then high=value; end
        else high=math.floor(mask/2^(slot*2))%4; end
        if not finite(low) or low<0 or low>255 or low~=math.floor(low) or high==nil then return nil; end
        local effect=low+high*256;
        signature[#signature+1]=tostring(effect);
        if effect>0 and effect~=255 then effects[#effects+1]={effect=effect,slot=slot}; end
    end
    return effects,table.concat(signature,',');
end

local function bootstrap_party(party, members, here, now)
    if not native_bootstrap then return; end
    local readable={};
    for entry=0,4 do
        local id,index=call(party,'GetStatusIconsServerId',entry),call(party,'GetStatusIconsTargetIndex',entry);
        local member=members[id];
        if member and member.slot<=5 and member.zone==here and member.index==index and not native_blocked[id] then
            local saved=party_cache[id];
            -- Packets remain authoritative once this load has received them.
            if not saved or saved.source=='native' then
                local effects,signature=native_party_effects(party,entry);
                if effects then
                    readable[id]=true;
                    if not saved or saved.signature~=signature then party_revision=party_revision+1; end
                    local changed=not saved or saved.signature~=signature;
                    party_cache[id]={zone=here,index=index,effects=effects,at=now,revision=changed and party_revision or saved.revision,
                        source='native',signature=signature};
                end
            end
        end
    end
    for id,saved in pairs(party_cache) do
        if saved.source=='native' and not readable[id] then party_cache[id]=nil; end
    end
end

-- What the game calls a unit, or nothing until it gives it a name.
local function unit_name(entities, index)
    local name = call(entities, 'GetName', index);
    if name ~= '' then return name; end
end

-- A pet past 50 yalms leaves your spawn list with a despawn 0x00E, and the client may then forget it, but it is still
-- out: the server says when a pet ends, with an empty 0x068 from DetachPet (src/map/entities/pet_entity.cpp :248,
-- mob_entity.cpp :1491, utils/petutils.cpp :1518). So it stays until that, another pet, a zone or 90 minutes without a
-- word of it, the longest a jug lasts, as a pet left on Stay sends nothing while it is idle. It has kind 'pet' here
-- whatever its spawn flags say, as a charmed mob can keep the Monster flag.
local PET_AWAY = 5400;
local function read_pet(out, entities, now)
    local index = call(entities, 'GetPetTargetIndex', out.entities[out.id].index);
    local id = finite(index) and index > 0 and index <= 0x8FF and call(entities, 'GetServerId', index) or nil;
    if pet_gone and now - pet_gone.at > 2 then pet_gone = nil; end
    if positive(id) and not (pet_gone and pet_gone.id == id) then
        if not pet_known or pet_known.id ~= id then pet_known = { id = id, at = now }; end
        pet_known.index = index;
        pet_known.name = unit_name(entities, index) or pet_known.name;
        if not pet_known.away then pet_known.at = now; end
    elseif pet_known and not pet_known.away then
        pet_known = nil;
    end
    if pet_known and pet_known.away and now - pet_known.at > PET_AWAY then pet_known = nil; end
    if not pet_known then return; end
    local sync = pet_sync and pet_sync.index == pet_known.index and pet_sync or nil;
    local row = { id = pet_known.id, index = pet_known.index, name = pet_known.name or sync and sync.name, kind = 'pet',
        away = pet_known.away, hpp = sync and sync.hpp, mpp = sync and sync.mpp, tp = sync and sync.tp };
    out.pet, out.entities[row.id] = row, row;
end

-- What is in your ammo slot: Repair's oil and Call Beast's jug are taken from it before their action's packet comes.
local function read_ammo()
    local inventory = call(memory(), 'GetInventory');
    local equipped = call(inventory, 'GetEquippedItem', 3);
    if equipped and finite(equipped.Index) and equipped.Index ~= 0 then
        local item = call(inventory, 'GetContainerItem', bit.rshift(equipped.Index, 8), bit.band(equipped.Index, 0xFF));
        if item and positive(item.Id) then return item.Id; end
    end
end

function client.resolve(id, index, entities)
    entities = entities or call(memory(), 'GetEntity');
    if positive(index) and index <= 0x8FF and call(entities, 'GetServerId', index) == id then
        local flags = call(entities, 'GetSpawnFlags', index) or 0;
        local row = { id = id, index = index, name = unit_name(entities, index),
            kind = id < 0x1000000 and 'player' or bit.band(flags, 0x10) ~= 0 and 'monster' or 'pet' };
        cache_entity(row);
        return row;
    end
    local saved = entity_cache[id];
    if saved and call(entities, 'GetServerId', saved.index) == id then
        saved.name = saved.name or unit_name(entities, saved.index);
        return saved;
    end
    local missed = id ~= nil and unresolved[id];
    if missed then return missed; end
    if positive(id) and id >= 0x1000000 then
        -- A mob's or NPC's index is the low 12 bits of its id, or 0x100 under them.
        local low = id % 4096;
        if low > 0 and low <= 0x8FF and call(entities, 'GetServerId', low) == id then return client.resolve(id, low, entities); end
        low = low - 0x100;
        if low > 0 and call(entities, 'GetServerId', low) == id then return client.resolve(id, low, entities); end
    end
    local row = { id = id, kind = id and id >= 0x1000000 and 'monster' or 'player' };
    if positive(id) then
        if unresolved_count >= 256 then unresolved, unresolved_count = {}, 0; end
        unresolved[id], unresolved_count = row, unresolved_count + 1;
    end
    return row;
end

function client.roster_members(snapshot, now)
    local held = roster_snapshot;
    if held and held.snapshot == snapshot and held.at == now and held.id == snapshot.id and held.zone == snapshot.zone then
        return held.members;
    end
end

-- The client's hide-UI flag, event flag and whether the map is the focused menu, as read. Each is nil when it
-- can't be read (hidden and event also when their address wasn't found); map is false while no menu has focus.
local function window_flags()
    local hidden = interface ~= 0 and native_read('read_uint8', interface + 0xB4) or nil;
    local event = event_flag ~= 0 and native_read('read_uint8', event_flag) or nil;
    local menu = native_read('read_uint32', focus_slot);
    if menu == 0 then return hidden, event, false; end
    local header = menu and native_read('read_uint32', menu + 4);
    local title = header and header ~= 0 and native_read('read_uint32', header + 0x4E);
    if not title then return hidden, event, nil; end
    -- A menu's name is at +0x46, as 'menu    map...': +0x4E skips the 'menu    ', and 0x70616D is 'map', low byte first.
    return hidden, event, bit.band(title, 0xFFFFFF) == 0x70616D;
end

-- The flags as this Present first read them, or a fresh read outside a Present.
local function frame_flags()
    if in_frame and flags_held then return held_hidden, held_event, held_map; end
    local hidden, event, map = window_flags();
    if in_frame then flags_held, held_hidden, held_event, held_map = true, hidden, event, map; end
    return hidden, event, map;
end

-- The Present handler brackets each frame with these.
function client.frame_begin() in_frame, flags_held = true, false; end
function client.frame_end() in_frame, flags_held = false, false; end

-- What client.visibility hands back, refilled by each call: its callers read it at once and keep nothing.
local visible = { valid = true };

-- Reads the visibility flags alone, between refreshes, without scanning effects or the roster.
function client.visibility(snapshot)
    if not snapshot or not snapshot.valid or waiting then return nil; end
    pointers();
    if interface == 0 or focus_slot == 0 or event_flag == 0 then return nil; end
    local mm = memory();
    local party, stats = call(mm, 'GetParty'), call(mm, 'GetPlayer');
    local id, here = call(party, 'GetMemberServerId', 0), call(party, 'GetMemberZone', 0);
    local zoning = call(stats, 'GetIsZoning');
    if id ~= snapshot.id or here ~= snapshot.zone or not positive(id) or not positive(here)
        or zoning == nil or truth(zoning) or expected_id and expected_id ~= id
        or expected_zone and expected_zone ~= here then return nil; end
    local hidden, event, map = frame_flags();
    if hidden == nil or event == nil or map == nil then return nil; end
    local chat = call(call(AshitaCore, 'GetChatManager'), 'IsInputOpen');
    visible.id, visible.zone, visible.hidden, visible.in_event, visible.map = id, here, hidden == 1, event == 1, map;
    visible.chat_open = chat == true or finite(chat) and bit.band(chat, 1) ~= 0;
    return visible;
end

-- For the overhead icons, read every frame with no table made: whether a zone change is still loading, then the
-- hide-UI, event and map flags as frame_flags reads them. A flag whose pattern wasn't found reads nothing and is nil.
function client.world_flags()
    pointers();
    local hidden, event, map = frame_flags();
    return waiting, hidden, event, map;
end

-- The logged-in character's server id and name, or nothing before one is in the game. Reads nothing else.
function client.identity()
    local party = call(memory(), 'GetParty');
    local id, name = call(party, 'GetMemberServerId', 0), character_name(call(party, 'GetMemberName', 0));
    if positive(id) and name then return id, name; end
end

function client.read(now, settings)
    roster_snapshot = nil;
    if unresolved_count > 0 then unresolved, unresolved_count = {}, 0; end
    pointers();
    local mm = memory();
    local party, stats, targets, entity_memory = call(mm, 'GetParty'), call(mm, 'GetPlayer'), call(mm, 'GetTarget'), call(mm, 'GetEntity');
    local id, here = call(party, 'GetMemberServerId', 0), call(party, 'GetMemberZone', 0);
    local job = call(stats, 'GetMainJob');
    local entity;
    if type(GetPlayerEntity) == 'function' then local ok, value = pcall(GetPlayerEntity); if ok then entity = value; end end
    local out = { valid = false, self_known = false, self_effects = {}, party = {}, entities = {}, self_revision = revision,
        self_epoch = epoch, self_timer_revision = timer_revision };
    if not entity or waiting or truth(call(stats, 'GetIsZoning')) or not positive(id) or not positive(here)
        or not positive(job) or (expected_id and expected_id ~= id) or (expected_zone and expected_zone ~= here) then
        if party_window and ((positive(id) and id~=party_window.id) or (positive(here) and here~=party_window.zone)) then
            pending_party,party_window=nil,nil;
        end;
        return out;
    end
    if owner and (id ~= owner or here ~= zone) then
        party_cache, merit_cache, entity_cache, deadline_cache = {}, {}, {}, {};
        cached_entities=0;
        native_blocked,native_bootstrap={},false;
        pet_known, pet_sync, pet_gone = nil, nil, nil;
    end
    owner, zone, expected_id, expected_zone = id, here, nil, nil;
    local status = entity.StatusServer;
    out.valid, out.id, out.zone, out.job, out.job_name = true, id, here, job, jobs[job] or tostring(job);
    local deferred=pending_party;
    pending_party,party_window=nil,nil;
    if deferred and deferred.owner==id and deferred.zone==here then client.accept(deferred,deferred.at,out); end;
    out.name = character_name(call(party, 'GetMemberName', 0));
    if not out.name and entity.ServerId==id and (not positive(entity.ZoneId) or entity.ZoneId==here) then
        out.name=character_name(entity.Name);
    end;
    out.level = call(stats, 'GetMainJobLevel');
    out.sub_job, out.sub_level = call(stats, 'GetSubJob'), call(stats, 'GetSubJobLevel');
    if job == 9 or job == 18 or out.sub_job == 9 or out.sub_job == 18 then out.ammo = read_ammo(); end
    -- Your MP, for the recast tint of spells you can't afford.
    local mp = call(party, 'GetMemberMP', 0);
    out.mp = finite(mp) and mp >= 0 and mp or nil;
    out.dead, out.combat = status == 2 or status == 3, status == 1;
    local hidden, event, map = frame_flags();
    out.in_event = event == 1 or event_flag == 0 and status == 4;
    out.hidden = hidden == 1;
    out.map = map == true;
    local chat = call(call(AshitaCore, 'GetChatManager'), 'IsInputOpen');
    out.chat_open = chat == true or finite(chat) and bit.band(chat, 1) ~= 0;
    -- Effects come from the array the client builds its own buff list from; the 0x063 array
    -- supplies a slot's timer only while it lists the same effect, as the client does.
    local ids, icons, timers = call(stats, 'GetBuffs'), call(stats, 'GetStatusIcons'), call(stats, 'GetStatusTimers');
    local clock_now = current_time();
    local icon_source = 'GetBuffs';
    if ids == nil then ids = icons; icon_source = 'GetStatusIcons'; end
    local id_base, icon_base, timer_base = array_base(ids), array_base(icons), array_base(timers);
    local agree = id_base ~= nil and icons_agree(ids, id_base, icons, icon_base);
    -- The tracker must not read instance identity from a listing whose timers are still pending.
    out.self_timers_pending = id_base ~= nil and not agree;
    out.self_known = id_base ~= nil;
    out.self_diagnostics = { source = icon_source, icon_type = type(ids), timer_type = type(timers),
        icon_base = id_base, timer_base = timer_base, clock_available = clock_now ~= nil,
        index_base_known = id_base ~= nil, rejected_slots = {} };
    local current_deadlines = {};
    for slot = 0, 31 do
        local number, value, readable;
        if id_base ~= nil then number, value, readable = at(ids, slot + id_base); end
        local effect = self_id(number);
        local valid = effect ~= nil;
        if not valid then
            out.self_known = false;
            if id_base ~= nil then
                local rejected = out.self_diagnostics.rejected_slots;
                rejected[#rejected + 1] = { slot = slot, index = slot + id_base, readable = readable,
                    raw_type = type(value), raw_value = diagnostic_value(value, number) };
            end
        end
        if valid and effect > 0 and effect ~= 255 then
            local raw = agree and timer_base ~= nil
                and (ids == icons or icon_base ~= nil and at(icons, slot + icon_base) == effect)
                and at(timers, slot + timer_base) or nil;
            local seconds = client.remaining(raw, clock_now);
            -- The same raw timer is the same end, so a slot shift or a new icon (Copy Image losing a shadow)
            -- keeps it. Worked out again, it would land on the game clock's whole second, up to one off.
            local deadline = finite(raw) and deadline_cache[raw] or seconds and now + seconds or nil;
            if finite(raw) then current_deadlines[raw] = deadline; end
            out.self_effects[#out.self_effects + 1] = { effect = effect, slot = slot, raw_timer = raw,
                deadline = deadline };
        end
    end
    deadline_cache = current_deadlines;
    local active,members,ordered,roster_members = {},{},{},{};
    for slot = 1, 17 do
        local member_id = call(party, 'GetMemberServerId', slot);
        local member_active=call(party,'GetMemberIsActive',slot);
        if positive(member_id) and member_id ~= id and not members[member_id] and (member_active==nil or truth(member_active)) then
            local member_zone = call(party, 'GetMemberZone', slot);
            local index = call(party, 'GetMemberTargetIndex', slot);
            members[member_id]={id=member_id,index=index,zone=member_zone,slot=slot};
            ordered[#ordered+1]=members[member_id];
        end
    end
    bootstrap_party(party,members,here,now);
    for _,member in ipairs(ordered) do
        if members[member.id] == member then
            local member_id,slot=member.id,member.slot;
            local member_zone,index=member.zone,member.index;
            local cached = party_cache[member_id];
            local valid = slot<=5 and member_zone == here and cached ~= nil and cached.zone == here and cached.index == index;
            -- A member whose name hasn't come yet has none, never the id.
            local member_name = call(party, 'GetMemberName', slot);
            local row = { id = member_id, index = index, zone = member_zone,
                name = type(member_name) == 'string' and member_name ~= '' and member_name or nil,
                slot=slot,group=math.floor(slot/6)+1,scope=slot<=5 and 'party' or 'alliance',hpp=call(party,'GetMemberHPPercent',slot),
                valid = valid, effects = valid and cached.effects or {}, observed_at = valid and cached.at or nil,
                revision = valid and cached.revision or nil };
            out.party[#out.party + 1] = row;
            roster_members[slot] = row;
            active[member_id] = true;
            out.entities[member_id] = { id = member_id, index = index, name = row.name, kind = 'player' };
            if member_zone ~= here or (cached and cached.index~=index) then party_cache[member_id],native_blocked[member_id] = nil,true; end
        end
    end
    for member_id in pairs(party_cache) do if not active[member_id] then party_cache[member_id],native_blocked[member_id] = nil,true; end end
    local index = call(targets, 'GetTargetIndex', 0);
    if settings and settings.tracking and settings.tracking.follow_subtarget == false and truth(call(targets, 'GetIsSubTargetActive')) then
        index = call(targets, 'GetTargetIndex', 1) or index;
    end
    if positive(index) then
        local target_id = call(entity_memory, 'GetServerId', index);
        if positive(target_id) then out.target = client.resolve(target_id, index, entity_memory); out.entities[target_id] = out.target; end
    end
    out.entities[id] = { id = id, index = call(party, 'GetMemberTargetIndex', 0), name = out.name, kind = 'player' };
    roster_members[0] = {id=id,name=out.name,zone=here};
    roster_snapshot = {snapshot=out,at=now,id=id,zone=here,members=roster_members};
    for _, row in pairs(out.entities) do cache_entity(row); end
    -- After those, so a charmed mob you release is known by its flags again.
    read_pet(out, entity_memory, now);
    return out;
end

local function u16(data, pos) return data:byte(pos + 1) + data:byte(pos + 2) * 256; end
local function u32(data, pos) return u16(data, pos) + u16(data, pos + 2) * 65536; end
-- Ashita hands an addon's callbacks each event as userdata, not a table; a table is what some tests hand them.
-- Either is an event.
local function event(e)
    local kind = type(e);
    return kind == 'userdata' or kind == 'table';
end
-- An event's size and data. Each read of an Ashita event's data copies the packet, so a caller reads both here once and
-- hands them on.
function client.packet_size(e)
    if not event(e) then return 0; end
    local data = e.data;
    if type(data) ~= 'string' then return 0; end
    return math.min(#data, finite(e.size) and math.max(0, e.size) or #data), data;
end

-- The character a zone-in packet (0x00A) brings in: its server id (at 0x04) and name (16 bytes at 0x84), or nothing.
function client.zone_in_identity(e)
    if not event(e) or e.id ~= 0x00A or e.injected == true or e.blocked == true or client.packet_size(e) < 0x94 then return; end
    local id, name = u32(e.data, 4), e.data:sub(0x85, 0x94):match('^[^%z]*');
    name = character_name(name);
    if positive(id) and name then return id, name; end
end

-- Called once for each ordinary incoming packet, before observations are returned. size and data are the packet's, when
-- the caller has read them already.
function client.accept(e, now, snapshot, size, data)
    if not event(e) or e.injected==true or e.blocked==true then return; end
    if size == nil then size, data = client.packet_size(e); end
    local id = e.id;
    if id == 0x00A and size >= 50 then
        client.reset(); expected_id, expected_zone, waiting = u32(data, 4), u16(data, 0x30), true;
        native_bootstrap=false;
        party_awaiting_ready=true;
    elseif id == 0x00B and size >= 5 then
        pending_party,party_window=nil,nil;
        party_awaiting_ready=false;
    elseif id == 0x037 and size >= 0x50 then
        revision = revision + 1;
        -- Your 32 status icons: their low bytes at 0x04 and their top two bits at 0x4C (Phoenix char_status.cpp). Phoenix
        -- sends a 0x037 after any HP, MP or TP change too, so only a change here says your effects changed.
        local low, high = data:sub(5, 36), data:sub(0x4D, 0x54);
        if low ~= icons_low or high ~= icons_high then icons_low, icons_high, icons_changed = low, high, true; end
    elseif id == 0x063 and size >= 200 and u16(data, 4) == 9 then
        if waiting and party_awaiting_ready and positive(expected_id) and positive(expected_zone) then
            party_window={id=expected_id,zone=expected_zone};
        end;
        party_awaiting_ready=false;
        waiting = false; revision = revision + 1; timer_revision = timer_revision + 1;
    elseif id == 0x076 and size >= 244 and not waiting and party_window then
        local party=call(memory(),'GetParty');
        local id,here=call(party,'GetMemberServerId',0),call(party,'GetMemberZone',0);
        if id==party_window.id and here==party_window.zone then
            -- Keep one post-zone update until the first usable frame can validate its members.
            pending_party={id=0x076,data=data:sub(1,244),size=244,owner=party_window.id,zone=party_window.zone,at=now};
        elseif (positive(id) and id~=party_window.id) or (positive(here) and here~=party_window.zone) then
            pending_party,party_window=nil,nil;
        end;
    elseif id == 0x076 and size >= 244 and snapshot and snapshot.valid and not waiting
        and snapshot.id==owner and snapshot.zone==zone then
        party_revision = party_revision + 1;
        local next_cache = {};
        local party=call(memory(),'GetParty');
        if call(party,'GetMemberServerId',0)~=snapshot.id or call(party,'GetMemberZone',0)~=snapshot.zone then return; end
        local members={};
        for slot=1,5 do
            local id=call(party,'GetMemberServerId',slot);
            local active=call(party,'GetMemberIsActive',slot);
            if positive(id) and id~=snapshot.id and (active==nil or truth(active)) and call(party,'GetMemberZone',slot)==snapshot.zone then
                members[id]=call(party,'GetMemberTargetIndex',slot);
                native_blocked[id]=true;
            end
        end
        -- Five member rows of 48 bytes: id at +0, target index at +4, the top 2 bits of each of 32 effect ids packed four
        -- to a byte at +8, then each id's low byte at +16.
        for row = 0, 4 do
            local start = 4 + row * 48;
            local id, index = u32(data, start), u16(data, start + 4);
            if id ~= 0 and positive(index) and index<=0x8FF and members[id]==index then
                local effects = {};
                for slot = 0, 31 do
                    local high = math.floor(data:byte(start + 8 + math.floor(slot / 4) + 1) / 2 ^ ((slot % 4) * 2)) % 4;
                    local effect = data:byte(start + 16 + slot + 1) + high * 256;
                    if effect ~= 255 and effect > 0 then effects[#effects + 1] = { effect = effect, slot = slot }; end
                end
                next_cache[id] = { zone = snapshot.zone, index = index, effects = effects, at = now, revision = party_revision,source='packet' };
                native_blocked[id]=false;
            end
        end
        party_cache = next_cache;
    elseif id == 0x068 and size >= 0x0E and snapshot and u32(data, 8) == snapshot.id then
        -- Your pet, at any distance (src/map/packets/pet_sync.cpp): its index, then HP, MP, TP and name, or no index
        -- once it has gone.
        local index = u16(data, 0x0C);
        if index == 0 then
            pet_gone = pet_known and { id = pet_known.id, at = now } or pet_gone;
            pet_known, pet_sync = nil, nil;
        elseif size >= 0x18 then
            local name = data:sub(0x19, size):match('^[^%z]*');
            pet_sync = { index = index, hpp = data:byte(0x0F), mpp = data:byte(0x10), tp = u16(data, 0x10), name = name ~= '' and name or nil };
            if pet_known and pet_known.index == index then pet_known.at = now; end
        end
    elseif id == 0x00E and size >= 11 and pet_known and u32(data, 4) == pet_known.id then
        -- Any other update of it says it is back in view.
        pet_known.away = bit.band(data:byte(11), 0x20) ~= 0 or nil;
    elseif id == 0x08C and size >= 8 then
        local count = u16(data, 4);
        if 8 + count * 4 <= size then
            for pos = 8, 8 + (count - 1) * 4, 4 do merit_cache[u16(data, pos)] = data:byte(pos + 4); end
        end
    end
end

-- A merit's ranks as the last 0x08C gave them, or nil.
function client.merit(id) return merit_cache[id]; end

-- Whether a 0x037 changed your status icons since the last ask.
function client.icons_changed()
    local changed = icons_changed;
    icons_changed = false;
    return changed;
end

-- The 0x063 count as a packet arrives; the snapshot carries it as self_timer_revision.
function client.self_timer_revision() return timer_revision; end
-- The 0x076 count as a packet arrives; each member's listing carries the count it came with as revision.
function client.party_revision() return party_revision; end

-- A party or alliance member's main job, or nil while the client has none for them. As core/roster.lua reads it, only for
-- someone in your zone whose slot the client has filled, as another can hold an old job.
function client.member_job(snapshot, id)
    for _, member in ipairs(snapshot and snapshot.party or {}) do
        if member.id == id then
            local party = call(memory(), 'GetParty');
            local zone2, updated = call(party, 'GetMemberZone2', member.slot), call(party, 'GetMemberLastUpdatedTimestamp', member.slot);
            if member.zone ~= snapshot.zone or zone2 ~= nil and zone2 ~= 0 or updated ~= nil and not positive(updated) then return nil; end
            local job = call(party, 'GetMemberMainJob', member.slot);
            return positive(job) and job <= 18 and job or nil;
        end
    end
end

-- Capture equipment and buffs at the action, before the player swaps gear again.
function client.sample_modifiers(snapshot)
    local out = { items = {}, buffs = {}, merits = {}, level = snapshot and snapshot.level, job = snapshot and snapshot.job, complete = true };
    for _, row in ipairs(snapshot and snapshot.self_effects or {}) do out.buffs[row.effect] = true; end
    for id, value in pairs(merit_cache) do out.merits[id] = value; end
    local inventory = call(memory(), 'GetInventory');
    out.enhancing_skill = call(call(call(memory(), 'GetPlayer'), 'GetCombatSkill', 34), 'GetSkill');
    out.summoning_skill = call(call(call(memory(), 'GetPlayer'), 'GetCombatSkill', 38), 'GetSkill');
    for slot = 0, 15 do
        local equipped = call(inventory, 'GetEquippedItem', slot);
        if equipped == nil then out.complete = false;
        elseif finite(equipped.Index) and equipped.Index ~= 0 then
            local item = call(inventory, 'GetContainerItem', bit.rshift(equipped.Index, 8), bit.band(equipped.Index, 0xFF));
            if item and positive(item.Id) then out.items[slot] = item.Id; else out.complete = false; end
        end
    end
    return out;
end

if VANTAGE_TEST_MODE then
    -- valid(address, size, writable) stands in for the page check, as core.memory's does in the game.
    function client._set_pages(valid) pages = valid or nil; end
end

return client;
