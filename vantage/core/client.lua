-- Reads only the state the client already has.
local client = {};
local bit = require('bit');
local finder = require('core.patterns');
local jobs = require('data.shared_ids').jobs;
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
-- said of it; pet_gone the one a 0x068 said left, which the client can still name for a moment. automaton is what the
-- last 0x044 for PUP said of your automaton: its name, HP and max HP, and from a whole page its MP, head, frame,
-- attachments, skills and stats. automaton_page is the part of that 0x044 it was read from.
local pet_known, pet_sync, pet_gone, automaton, automaton_page;
-- Your status icons as the last 0x037 gave them, and whether they changed since the last ask.
local icons_low, icons_high, icons_changed = nil, nil, false;
-- Ids no index answered, kept until the next read: an observation about someone out of view, or a watched id out of
-- range, would otherwise be looked for again and again.
local unresolved, unresolved_count = {}, 0;
-- Inside a Present the UI flags are read once and held, for the refresh, the check between refreshes and the overhead
-- icons alike. Outside one, every read is fresh.
local in_frame, flags_held, held_hidden, held_event, held_map = false, false, nil, nil, nil;

local index_of, call = require('core.guard').index_of, require('core.guard').call;

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
-- the game. A run of reads checks its whole range once and reads it with checked. readable also says whether the
-- range lies in a loaded image, the client's own code and data, whose pages stay as long as the game runs.
local pages;
local function readable(address, size)
    if pages == nil then
        local ok, value = pcall(require('core.memory').pages);
        pages = ok and type(value) == 'table' and value.valid or false;
    end
    if pages == false then return false; end
    local ok, _, _, image = pages(address, size, false);
    return ok == true, image == true;
end

local function native_read(name, address, checked)
    if not positive(address) or not ashita or not ashita.memory then return nil; end
    if not checked and not readable(address, name == 'read_uint8' and 1 or 4) then return nil; end
    local ok, value = pcall(ashita.memory[name], address);
    return ok and value or nil;
end

-- A read at a fixed address the client's code holds, such as a flag: once its page is found in the client's image,
-- it is read with no check again. Anywhere else each read checks it.
local in_image = {};
local function image_read(name, address)
    if not in_image[address] then
        if not positive(address) then return nil; end
        local ok, image = readable(address, name == 'read_uint8' and 1 or 4);
        if not ok then return nil; end
        in_image[address] = image or nil;
    end
    return native_read(name, address, true);
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
    pet_known, pet_sync, pet_gone, automaton, automaton_page = nil, nil, nil, nil, nil;
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

-- One member's icon low bytes as native_party_effects last read them, by slot from 1. Each read fills it again.
local native_low = {};
-- A member's effects from the client's party icons, with what they were read from: the icons' low bytes as text and the
-- mask of their top bits. saved is the member's entry from the last read, whose list is handed back when both read the
-- same, as nothing changes a list once it is made.
local function native_party_effects(party, entry, saved)
    local icons, mask = call(party,'GetStatusIcons',entry), call(party,'GetStatusIconsBitMask',entry);
    local base=array_base(icons);
    local pointer=positive(icons) and icons>=65536 and icons<=4294967295 and icons or nil;
    if base==nil and not pointer then return nil; end
    if pointer and not readable(pointer, 32) then return nil; end
    if type(mask)~='cdata' and (not finite(mask) or mask<0 or mask>9007199254740991 or mask~=math.floor(mask)) then return nil; end
    for slot=0,31 do
        local low;
        if pointer then low=native_read('read_uint8',pointer+slot,true); else low=at(icons,slot+base); end
        if not finite(low) or low<0 or low>255 or low~=math.floor(low) then return nil; end
        native_low[slot+1]=low;
    end
    local signature=table.concat(native_low,',');
    -- The same low bytes and mask are the same effects. A 64-bit mask compares by its value.
    if saved and saved.signature==signature and saved.mask==mask then return saved.effects,signature,mask; end
    local effects={};
    for slot=0,31 do
        local high;
        if type(mask)=='cdata' then
            local ok,value=pcall(function() return tonumber(bit.band(bit.rshift(mask,slot*2),3)); end);
            if ok then high=value; end
        else high=math.floor(mask/2^(slot*2))%4; end
        if high==nil then return nil; end
        local effect=native_low[slot+1]+high*256;
        if effect>0 and effect~=255 then effects[#effects+1]={effect=effect,slot=slot}; end
    end
    return effects,signature,mask;
end

-- The members bootstrap_party read icons for, emptied by each call.
local native_seen = {};
local function bootstrap_party(party, members, here, now)
    if not native_bootstrap then return; end
    local readable=native_seen;
    for id in pairs(readable) do readable[id]=nil; end
    for entry=0,4 do
        local id,index=call(party,'GetStatusIconsServerId',entry),call(party,'GetStatusIconsTargetIndex',entry);
        local member=members[id];
        if member and member.slot<=5 and member.zone==here and member.index==index and not native_blocked[id] then
            local saved=party_cache[id];
            -- Packets remain authoritative once this load has received them.
            if not saved or saved.source=='native' then
                local effects,signature,mask=native_party_effects(party,entry,saved);
                if effects then
                    readable[id]=true;
                    if saved and effects==saved.effects then
                        -- The same icons keep the entry, its list and the time they were first read, and only where they
                        -- were read moves on.
                        saved.zone,saved.index=here,index;
                    else
                        party_revision=party_revision+1;
                        party_cache[id]={zone=here,index=index,effects=effects,at=now,revision=party_revision,
                            source='native',signature=signature,mask=mask};
                    end
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
-- Your pet's row from the last read. A read hands it on while every field reads the same, and never changes it, so a
-- reader that kept the last snapshot still reads what that read gave.
local pet_row;
local function read_pet(out, entities, now)
    local index = call(entities, 'GetPetTargetIndex', out.entities[out.id].index);
    local id = finite(index) and index > 0 and index <= 0x8FF and call(entities, 'GetServerId', index) or nil;
    if pet_gone and now - pet_gone.at > 2 then pet_gone = nil; end
    if positive(id) and not (pet_gone and pet_gone.id == id) then
        if not pet_known or pet_known.id ~= id then pet_known = { id = id, at = now, since = now }; end
        pet_known.index = index;
        pet_known.name = unit_name(entities, index) or pet_known.name;
        if not pet_known.away then pet_known.at = now; end
    elseif pet_known and not pet_known.away then
        pet_known = nil;
    end
    if pet_known and pet_known.away and now - pet_known.at > PET_AWAY then pet_known = nil; end
    if not pet_known then return; end
    local sync = pet_sync and pet_sync.index == pet_known.index and pet_sync or nil;
    local name, hpp, mpp, tp = pet_known.name or sync and sync.name, sync and sync.hpp, sync and sync.mpp, sync and sync.tp;
    -- What it is fighting, which the 0x068 names only while it attacks.
    local target = sync and sync.target or nil;
    -- Where it is, while the game shows it at its index: core/tracker.lua takes a pet that moves as awake.
    local x, y, z;
    if positive(id) and id == pet_known.id and not pet_known.away then
        x, y, z = call(entities, 'GetLocalPositionX', index), call(entities, 'GetLocalPositionY', index),
            call(entities, 'GetLocalPositionZ', index);
        if not (finite(x) and finite(y) and finite(z)) then x, y, z = nil, nil, nil; end
    end
    -- The 0x044 tells of your automaton whatever your pet is, so only a pet with its name takes its HP. The server names
    -- the automaton from the same field (src/map/utils/petutils.cpp :641).
    local made = automaton and (automaton.name == name or sync and automaton.name == sync.name) and automaton or nil;
    -- Nothing changes an automaton once it is read, so the same one has the same HP and MP.
    local row = pet_row;
    if not row or row.id ~= pet_known.id or row.index ~= pet_known.index or row.name ~= name or row.away ~= pet_known.away
        or row.hpp ~= hpp or row.mpp ~= mpp or row.tp ~= tp or row.target_id ~= target or row.since ~= pet_known.since
        or row.x ~= x or row.y ~= y or row.z ~= z or row.automaton ~= made then
        row = { id = pet_known.id, index = pet_known.index, name = name, kind = 'pet', away = pet_known.away, hpp = hpp,
            mpp = mpp, tp = tp, target_id = target, since = pet_known.since, x = x, y = y, z = z };
        if made then row.hp, row.max_hp, row.mp, row.max_mp, row.automaton = made.hp, made.max_hp, made.mp, made.max_mp, made; end
        pet_row = row;
    end
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

-- Whose pet a unit is: the id of the player whose pet it is, or nil. A pet the game made for its owner sits 0x100
-- under the place its id names, and a charmed monster keeps its own. The players' places are looked through for one
-- whose pet is at the unit's place. What is found is kept and checked again each time. A unit found with no owner, such
-- as a mob fighting a pet, isn't looked for again for half a minute, or until an update of it marks a player as its
-- master (client.accept). A charm sends that update: it gives the mob's HP part (src/map/utils/battleutils.cpp :4217),
-- which marks a mob a player is master of (src/map/packets/entity_update.cpp :406-410), so one charmed since is found
-- by its next move. now is the caller's clock.
local OWNER_RETRY = 30;
local owners, owner_count = {}, 0;
function client.pet_owner(id, now, entities)
    if not positive(id) or id < 0x1000000 then return nil; end
    entities = entities or call(memory(), 'GetEntity');
    local index = id % 0x1000;
    if index >= 0x800 then index = index - 0x100; end
    if index <= 0 or index > 0x8FF or call(entities, 'GetServerId', index) ~= id then return nil; end
    local kept = owners[id];
    if kept then
        if kept.at then
            if call(entities, 'GetServerId', kept.at) == kept.owner and call(entities, 'GetPetTargetIndex', kept.at) == index then return kept.owner; end
        elseif finite(now) and finite(kept.missed) and now >= kept.missed and now - kept.missed < OWNER_RETRY then return nil; end
    else
        if owner_count >= 128 then owners, owner_count = {}, 0; end
        owner_count = owner_count + 1;
    end
    for at = 0x400, 0x6FF do
        if call(entities, 'GetPetTargetIndex', at) == index then
            local owner = call(entities, 'GetServerId', at);
            if positive(owner) then
                owners[id] = { at = at, owner = owner };
                return owner;
            end
        end
    end
    owners[id] = { missed = now };
    return nil;
end

function client.resolve(id, index, entities)
    entities = entities or call(memory(), 'GetEntity');
    if positive(index) and index <= 0x8FF and call(entities, 'GetServerId', index) == id then
        local flags = call(entities, 'GetSpawnFlags', index) or 0;
        local name = unit_name(entities, index);
        local kind = id < 0x1000000 and 'player' or bit.band(flags, 0x10) ~= 0 and 'monster' or 'pet';
        -- A named unit as it was keeps its row. Nothing changes a row once it has its name, and one with none yet can be
        -- named in place below, so it isn't handed on.
        local row = entity_cache[id];
        if not (name and row and row.name == name and row.index == index and row.kind == kind) then
            row = { id = id, index = index, name = name, kind = kind };
        end
        cache_entity(row);
        return row;
    end
    local saved = entity_cache[id];
    if saved and positive(saved.index) and saved.index <= 0x8FF and call(entities, 'GetServerId', saved.index) == id then
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
        if low > 0 and low <= 0x8FF and call(entities, 'GetServerId', low) == id then return client.resolve(id, low, entities); end
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
    local hidden = interface ~= 0 and image_read('read_uint8', interface + 0xB4) or nil;
    local event = event_flag ~= 0 and image_read('read_uint8', event_flag) or nil;
    local menu = image_read('read_uint32', focus_slot);
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

-- Your effects' rows from the last read, by slot. A read hands on the row of a slot whose effect, raw timer and deadline
-- are the same, and never changes a row, so a reader that kept the last snapshot still reads what that read gave.
local self_rows = {};
-- The deadlines the next read fills, emptied first. It and deadline_cache trade places at each read.
local next_deadlines = {};
-- The effects of a member with no listing. Nothing writes into it.
local NO_EFFECTS = {};
-- The slots of your buff array the last read couldn't use, for /vg report: each one's row by slot, the ones this read
-- found in order, and the diagnostics it handed on. A read hands on a row, and the diagnostics, when it finds the same
-- again, and never changes either, as with your effects' rows.
local diagnosed = { rows = {}, found = {} };
-- What a read finds of your party and alliance: each member by id and in slot order, the ids it lists, and one table a
-- slot for them. Only client.read and bootstrap_party read these, within the read, so each read empties them and fills
-- them again.
local party_read = { members = {}, ordered = {}, active = {}, slots = {} };
-- What client.roster_members hands roster.read: your own row at 0 and each member's row by slot, with the read they
-- came from. roster.read reads them only in the refresh that made them, so each read fills them again.
local roster_held = { members = { [0] = {} } };
-- Each member's row and unit row from the last read by slot, and your own unit row at 0. A read hands on the row of a
-- slot that reads the same, and never changes a row, as with your effects' rows. A unit row with no name yet is new each
-- read, as client.resolve can name one in place.
local member_rows, member_units = {}, {};

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
        pet_known, pet_sync, pet_gone, automaton, automaton_page = nil, nil, nil, nil, nil;
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
    local rejected_count = 0;
    local current_deadlines = next_deadlines;
    for raw in pairs(current_deadlines) do current_deadlines[raw] = nil; end
    for slot = 0, 31 do
        local number, value, readable;
        if id_base ~= nil then number, value, readable = at(ids, slot + id_base); end
        local effect = self_id(number);
        local valid = effect ~= nil;
        if not valid then
            out.self_known = false;
            if id_base ~= nil then
                local index, raw_type, raw_value = slot + id_base, type(value), diagnostic_value(value, number);
                local rejected = diagnosed.rows[slot];
                if not rejected or rejected.index ~= index or rejected.readable ~= readable or rejected.raw_type ~= raw_type
                    or rejected.raw_value ~= raw_value then
                    rejected = { slot = slot, index = index, readable = readable, raw_type = raw_type, raw_value = raw_value };
                    diagnosed.rows[slot] = rejected;
                end
                rejected_count = rejected_count + 1;
                diagnosed.found[rejected_count] = rejected;
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
            local row = self_rows[slot];
            if not row or row.effect ~= effect or row.raw_timer ~= raw or row.deadline ~= deadline then
                row = { effect = effect, slot = slot, raw_timer = raw, deadline = deadline };
                self_rows[slot] = row;
            end
            out.self_effects[#out.self_effects + 1] = row;
        end
    end
    next_deadlines, deadline_cache = deadline_cache, current_deadlines;
    local last = diagnosed.last;
    local same = last and last.source == icon_source and last.icon_type == type(ids) and last.timer_type == type(timers)
        and last.icon_base == id_base and last.timer_base == timer_base and last.clock_available == (clock_now ~= nil)
        and #last.rejected_slots == rejected_count;
    for n = 1, same and rejected_count or 0 do same = same and last.rejected_slots[n] == diagnosed.found[n]; end
    if not same then
        local rejected = {};
        for n = 1, rejected_count do rejected[n] = diagnosed.found[n]; end
        diagnosed.last = { source = icon_source, icon_type = type(ids), timer_type = type(timers), icon_base = id_base,
            timer_base = timer_base, clock_available = clock_now ~= nil, index_base_known = id_base ~= nil, rejected_slots = rejected };
    end
    out.self_diagnostics = diagnosed.last;
    local active,members,ordered,roster_members = party_read.active,party_read.members,party_read.ordered,roster_held.members;
    for key in pairs(active) do active[key]=nil; end
    for key in pairs(members) do members[key]=nil; end
    for n=#ordered,1,-1 do ordered[n]=nil; end
    for slot=1,17 do roster_members[slot]=nil; end
    for slot = 1, 17 do
        local member_id = call(party, 'GetMemberServerId', slot);
        local member_active=call(party,'GetMemberIsActive',slot);
        if positive(member_id) and member_id ~= id and not members[member_id] and (member_active==nil or truth(member_active)) then
            local member_zone = call(party, 'GetMemberZone', slot);
            local index = call(party, 'GetMemberTargetIndex', slot);
            local member=party_read.slots[slot] or {};
            party_read.slots[slot]=member;
            member.id,member.index,member.zone,member.slot=member_id,index,member_zone,slot;
            members[member_id]=member;
            ordered[#ordered+1]=member;
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
            local name = type(member_name) == 'string' and member_name ~= '' and member_name or nil;
            local hpp, effects = call(party,'GetMemberHPPercent',slot), valid and cached.effects or NO_EFFECTS;
            local observed_at, listed = valid and cached.at or nil, valid and cached.revision or nil;
            local row = member_rows[slot];
            if not row or row.id ~= member_id or row.index ~= index or row.zone ~= member_zone or row.name ~= name
                or row.hpp ~= hpp or row.valid ~= valid or row.effects ~= effects or row.observed_at ~= observed_at
                or row.revision ~= listed then
                row = { id = member_id, index = index, zone = member_zone, name = name,
                    slot=slot,group=math.floor(slot/6)+1,scope=slot<=5 and 'party' or 'alliance',hpp=hpp,
                    valid = valid, effects = effects, observed_at = observed_at, revision = listed };
                member_rows[slot] = row;
            end
            out.party[#out.party + 1] = row;
            roster_members[slot] = row;
            active[member_id] = true;
            local unit = member_units[slot];
            if not (name and unit and unit.id == member_id and unit.index == index and unit.name == name) then
                unit = { id = member_id, index = index, name = name, kind = 'player' };
                member_units[slot] = unit;
            end
            out.entities[member_id] = unit;
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
    local own_index, own = call(party, 'GetMemberTargetIndex', 0), member_units[0];
    if not (out.name and own and own.id == id and own.index == own_index and own.name == out.name) then
        own = { id = id, index = own_index, name = out.name, kind = 'player' };
        member_units[0] = own;
    end
    out.entities[id] = own;
    local mine = roster_members[0];
    mine.id,mine.name,mine.zone = id,out.name,here;
    roster_held.snapshot,roster_held.at,roster_held.id,roster_held.zone = out,now,id,here;
    roster_snapshot = roster_held;
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
                -- Phoenix sends the row of each member in your zone when any member's effects change (src/map/party.cpp
                -- :1219-1247), so most read as they did. The same 40 bytes at the same index and zone keep the member's last
                -- list, as nothing changes a list once it is made.
                local bytes, saved = data:sub(start + 9, start + 48), party_cache[id];
                local effects = saved and saved.bytes == bytes and saved.index == index and saved.zone == snapshot.zone and saved.effects;
                if not effects then
                    effects = {};
                    for slot = 0, 31 do
                        local high = math.floor(data:byte(start + 8 + math.floor(slot / 4) + 1) / 2 ^ ((slot % 4) * 2)) % 4;
                        local effect = data:byte(start + 16 + slot + 1) + high * 256;
                        if effect ~= 255 and effect > 0 then effects[#effects + 1] = { effect = effect, slot = slot }; end
                    end
                end
                next_cache[id] = { zone = snapshot.zone, index = index, effects = effects, at = now, revision = party_revision,source='packet',
                    bytes = bytes };
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
            local target = u32(data, 0x14);
            pet_sync = { index = index, hpp = data:byte(0x0F), mpp = data:byte(0x10), tp = u16(data, 0x10), name = name ~= '' and name or nil,
                target = target ~= 0 and target or nil };
            if pet_known and pet_known.index == index then pet_known.at = now; end
        end
    elseif id == 0x044 and size >= 0x6C and data:byte(5) == 18 then
        -- Your automaton, on the job extra's PUP page (src/map/packets/s2c/0x044_extended_job_pup.h :53-55): its name in
        -- 16 bytes at 0x58, then its HP and max HP. A PUP, main or support, gets it each time the automaton changes
        -- (src/map/entities/automaton_entity.cpp :140-151), in the same tick as its HP percent.
        -- A step it walks is a change too (src/map/ai/helpers/pathfind/entity_path_owner.cpp :61), and any change of your
        -- own effects sends the page as well (src/map/entities/char_entity.cpp :1190-1196), so in a fight it comes again
        -- and again, often with what is read below as it was. A page whose bytes after the header, up to the last one
        -- read below, are the same as the last keeps the automaton read from it, which nothing changes once made.
        local page = data:sub(5, size >= 0x9C and 0x9C or 0x6C);
        if page == automaton_page then return; end
        automaton_page = page;
        local name = data:sub(0x59, 0x68):match('^[^%z]*');
        automaton = name ~= '' and { name = name, hp = u16(data, 0x68), max_hp = u16(data, 0x6A) } or nil;
        -- The rest of the page (0x044_extended_job_pup.h :44-78): the head and frame at 0x08 and 0x09, the twelve
        -- attachments from 0x0A, MP and max MP after the HP, the three skills each with its cap from 0x70, and the seven
        -- stats each with its bonus from 0x80.
        if automaton and size >= 0x9C then
            automaton.mp, automaton.max_mp = u16(data, 0x6C), u16(data, 0x6E);
            automaton.head, automaton.frame = data:byte(0x09), data:byte(0x0A);
            local attachments, skills, stats = {}, {}, {};
            for slot = 1, 12 do attachments[slot] = data:byte(0x0A + slot); end
            for index = 1, 3 do skills[index] = { u16(data, 0x6C + index * 4), u16(data, 0x6E + index * 4) }; end
            -- A stat's bonus is a signed number in its two bytes (0x044_extended_job_pup.cpp :98-111, getMod).
            for index = 1, 7 do
                local bonus = u16(data, 0x7E + index * 4);
                stats[index] = { u16(data, 0x7C + index * 4), bonus >= 0x8000 and bonus - 0x10000 or bonus };
            end
            automaton.attachments, automaton.skills, automaton.stats = attachments, skills, stats;
        end
    elseif id == 0x00E and size >= 11 then
        local unit = u32(data, 4);
        -- Any other update of it says it is back in view.
        if pet_known and unit == pet_known.id then pet_known.away = bit.band(data:byte(11), 0x20) ~= 0 or nil; end
        -- An update with the HP part (0x04 at 0x0A) marks a unit a player is master of with 0x08 at 0x27. Then
        -- pet_owner looks again for the owner of a unit it found none for.
        local kept = owners[unit];
        if kept and kept.missed and size >= 0x28 and bit.band(data:byte(11), 0x04) ~= 0 and bit.band(data:byte(0x28), 0x08) ~= 0 then
            kept.missed = nil;
        end
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

-- A party or alliance member's pet's HP percent as the client last had it, or nil while it can't be read: a member the
-- client has at no place, no pet out, or a pet at a place nobody holds. A pet's entity update gives the percent Phoenix
-- rounds down (src/map/packets/entity_update.cpp :400, src/map/entities/battle_entity.cpp :290-298).
function client.member_pet_hpp(snapshot, id)
    for _, member in ipairs(snapshot and snapshot.party or {}) do
        if member.id == id then
            local entities, index = call(memory(), 'GetEntity'), member.index;
            if not positive(index) or index > 0x8FF or call(entities, 'GetServerId', index) ~= id then return nil; end
            local pet = call(entities, 'GetPetTargetIndex', index);
            if not positive(pet) or pet > 0x8FF or not positive(call(entities, 'GetServerId', pet)) then return nil; end
            local hpp = call(entities, 'GetHPPercent', pet);
            return finite(hpp) and hpp or nil;
        end
    end
end

-- The id of the item in each equipment slot, by slot, into out, a table the caller keeps. False when a slot couldn't
-- be read.
function client.worn_items(out)
    local inventory, complete = call(memory(), 'GetInventory'), true;
    for slot = 0, 15 do
        out[slot] = nil;
        local equipped = call(inventory, 'GetEquippedItem', slot);
        if equipped == nil then complete = false;
        elseif finite(equipped.Index) and equipped.Index ~= 0 then
            local item = call(inventory, 'GetContainerItem', bit.rshift(equipped.Index, 8), bit.band(equipped.Index, 0xFF));
            if item and positive(item.Id) then out[slot] = item.Id; else complete = false; end
        end
    end
    return complete;
end

-- Capture equipment and buffs at the action, before the player swaps gear again. merits are the client's own, with no
-- copy: their readers look one up within the packet's callback, and a reset gives the client new ones.
function client.sample_modifiers(snapshot)
    local out = { items = {}, buffs = {}, merits = merit_cache, level = snapshot and snapshot.level, job = snapshot and snapshot.job, complete = true };
    for _, row in ipairs(snapshot and snapshot.self_effects or {}) do out.buffs[row.effect] = true; end
    out.enhancing_skill = call(call(call(memory(), 'GetPlayer'), 'GetCombatSkill', 34), 'GetSkill');
    out.summoning_skill = call(call(call(memory(), 'GetPlayer'), 'GetCombatSkill', 38), 'GetSkill');
    out.complete = client.worn_items(out.items);
    return out;
end

if VANTAGE_TEST_MODE then
    -- valid(address, size, writable) stands in for the page check, as core.memory's does in the game.
    function client._set_pages(valid) pages, in_image = valid or nil, {}; end
end

return client;
