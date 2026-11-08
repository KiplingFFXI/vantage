-- Where and how big the overhead icons go each frame: which units get a block, the screen point above each head, the
-- icon size and the fade. Every table is made once and refilled, so the drawing reads overhead.plan and nothing is
-- made per frame. It reads the client and sends nothing; ui/overhead_icons.lua draws from the plan. Above the name a
-- block sits on the game's own name point (core/name_anchor.lua), or on the guessed heights when that can't be read.
-- Sizes and heights: docs/OVERHEAD.md.
local overhead = {};
local bit = require('bit');
local camera = require('core.camera');
local client = require('core.client');
local name_anchor = require('core.name_anchor');
local warmup = require('core.warmup');
local band, floor, ceil, sqrt, abs, huge, min = bit.band, math.floor, math.ceil, math.sqrt, math.abs, math.huge, math.min;
-- /vg report compares the client's own camera at the scene read with Vantage's.
camera.set_scene_hook(name_anchor.scene);

-- Priority for max_units, best first. A unit takes the best of the reasons it has.
local TARGET, SUBTARGET, CLAIMED, WATCHED, DEBUFFED, PARTY, PET, ALLIANCE, OTHER = 1, 2, 3, 4, 5, 6, 7, 8, 9;
local LEVELS = { self = PARTY, party = PARTY, pet = PET, alliance = ALLIANCE, other = OTHER, other_pet = OTHER };
-- Units looked at each frame, from the list rebuilt ten times a second.
local CANDIDATES = 24;
-- Era towns: Phoenix data/zones/*/zone.yaml typed city, without the zones of later expansions. Only the target, the
-- subtarget and the party get blocks in them. Sealion's Den is typed city too, but its CoP fights need every block, so
-- it isn't here.
local CITIES = { [26] = true, [48] = true, [50] = true, [199] = true, [214] = true, [219] = true };
for zone = 230, 252 do CITIES[zone] = true; end
-- How big a player is on the mob hitbox scale, by race. Phoenix gives players a hitbox of 0.3, 0.4 or 0.8
-- that can't be compared with a mob's, and mob families of these races don't agree on their order (Ark Angels: Galka
-- 1.5 below Hume 1.6), so this table is a design choice to settle in game.
local RACE_SIZES = { 1.7, 1.7, 1.7, 1.7, 1.2, 1.2, 1.5, 2.0 };

local plan = { count = 0, units = {}, order = {}, valid = false, hidden = 'Off.', considered = 0, ui = 1, k = 1, above = true };
-- units[1] to units[count] get a block, best first; order[1] to order[count] index them in draw order: far to near, the
-- target last. Each one: id, index, kind (a type in settings.overhead.types), target, subtarget, x and y (the point it is
-- placed from on screen: the game's name point above the name, or the middle of the guessed name, the head under it),
-- anchor_x and anchor_y (the middle of the block's bottom edge, or of its top edge under the head), name_px and arrow_px
-- (on the guess, the name's and the target cursor's height it leaves room for), size (icon px), alpha, depth (view
-- depth), distance (yalms), ppy (px per yalm at that point), head (yalms) and head_source. path is 'name point' or
-- 'guess', why the reason a unit took the guess above the name; the np_ fields keep its name point's skeleton values
-- between list rebuilds and this frame's placement for /vg report. ui is DisplaySize height / 1080 times the style
-- scale, k the same without the style scale, as the game's own names don't follow it.
overhead.plan = plan;

local pool, pool_count, by_id = {}, 0, {};
-- Each unit's id and settled size in the list before, so the 0.6 px hold outlasts the list made again.
local last_ids, last_sizes, last_count = {}, {}, 0;
for i = 1, CANDIDATES do
    last_ids[i], last_sizes[i] = 0, 0;
    pool[i] = { id = 0, index = 0, kind = 'mob', level = OTHER, target = false, subtarget = false, name = '', race = 0,
        hitbox = 0, model_size = 0, spawn_flags = 0, type = 0, status = 0, head = 0, head_source = 'hitbox', rows = 0,
        distance = 0, x = 0, y = 0, depth = 0, size = 0, alpha = 1, anchor_x = 0, anchor_y = 0, ppy = 0, name_px = 0, arrow_px = 0,
        visible = false, player = false, path = 'guess', why = false, np_node = 0, np_gen = -1, np_bad = false, np_gx = 0,
        np_gy = 0, np_gz = 0, np_bone = 0, np_count = 0, np_rise = 0, np_ai = 0, np_ax = 0, np_ay = 0, np_ndc = 0, np_s = 0,
        np_t = 0, np_name_top = 0, np_icon_top = 0, np_arrow_top = 0, np_arrow = false };
end
-- Your own name point's values for the preview sample, kept as a unit's are.
local sample_cache = { np_node = 0, np_gen = -1, np_bad = false, np_gx = 0, np_gy = 0, np_gz = 0, np_bone = 0, np_count = 0,
    np_rise = 0, np_ai = 0, np_ax = 0, np_ay = 0, np_ndc = 0, np_s = 0, np_t = 0, np_name_top = 0, np_icon_top = 0,
    np_arrow_top = 0, np_arrow = false };
local picked = {};
local party_ids, party_scope, rows_of, scope_of, debuffed = {}, {}, {}, {}, {};
-- Each unit's rows in the view the list was made from: first_row[id] is one of them, next_row[i] the next (0 ends).
local first_row, next_row, survey_rows = {}, {}, {};
-- The party cooldown estimates by member id (core/party_cooldowns.lua) while they go over heads, or none.
local cooling;
-- The key of the switch each effect has on a unit type, by its id, and of the Always show tick of those that have one.
local SWITCH, ALWAYS = {}, {};
local overhead_defaults = require('ui.overhead_defaults');
for _, switch in ipairs(overhead_defaults.switches) do
    for _, id in ipairs(switch.ids) do SWITCH[id] = switch.key; end
end
for _, tick in ipairs(overhead_defaults.always) do
    for _, id in ipairs(tick.ids) do SWITCH[id], ALWAYS[id] = tick.key, tick.key; end
end
-- From 0x00D and 0x00E: each entity's index, and each mob's claimer.
local index_of, claimer_of, known = {}, {}, 0;
local memory = { zone = nil };
local rebuilt_at, rebuilt_view, rebuilt_settings, main_seen, sub_seen = -1, nil, nil, 0, 0;
-- Counts list rebuilds and tenths of a second (ticked_at), so the name points read their skeletons, icons and the
-- cursor's box again ten times a second, also while show conditions hide the blocks and only the sample shows.
-- pointed: this frame places blocks above the name from the game's name points.
local generation, ticked_at, pointed = 0, -1, false;
local self_index, pet_index = 0, 0;
local capabilities;
local calibrate_pending = false;
-- Where this frame's preview sample can go: 'head' when blocks are placed, 'fixed' when only the camera stops them,
-- nil while they are off or hidden.
local spot;
local NONE = {};

local function wipe(t) for key in pairs(t) do t[key] = nil; end end
local function clamp(value, low, high) return value < low and low or value > high and high or value; end
local function truth(value) return value == true or value == 1; end
local function u16(data, pos) return data:byte(pos + 1) + data:byte(pos + 2) * 256; end
local function u32(data, pos) return u16(data, pos) + u16(data, pos + 2) * 65536; end

local function forget()
    wipe(index_of); wipe(claimer_of); known = 0;
end

-- 0x00D and 0x00E carry each entity's server id at 0x04 and index at 0x08. An 0x00E with its claim bit (0x02 at 0x0A)
-- carries the claimer at 0x2C, 0 when unclaimed; one with its despawn bit (0x20) forgets the entity (Phoenix
-- entity_update.cpp). A zone change forgets them all. They are read while overhead icons are off too, so icons turned
-- on mid-fight know the claims already made. known counts the entities kept, so it takes more than 1024 at once to
-- forget them all, not a long run of respawns. size and data are the packet's, when the caller has read them already.
function overhead.packet(e, size, data)
    local id = e.id;
    if id == 0x00A or id == 0x00B then forget(); return; end
    if id ~= 0x00D and id ~= 0x00E or e.injected or e.blocked then return; end
    if data == nil then size, data = client.packet_size(e); end
    if size < 0x0B then return; end
    local unit, index, flags = u32(data, 4), u16(data, 8), data:byte(0x0B);
    if unit == 0 or index == 0 or index > 0x8FF then return; end
    if band(flags, 0x20) ~= 0 then
        if index_of[unit] then known = known - 1; end
        index_of[unit], claimer_of[unit] = nil, nil;
        return;
    end
    if not index_of[unit] then
        known = known + 1;
        if known > 1024 then forget(); known = 1; end
    end
    index_of[unit] = index;
    if id == 0x00E and band(flags, 0x02) ~= 0 and size >= 0x30 then
        local claimer = u32(data, 0x2C);
        claimer_of[unit] = claimer ~= 0 and claimer or nil;
    end
end

-- The client objects, taken again only when the character or zone changes.
local function interfaces(snapshot)
    if memory.entities and memory.zone == snapshot.zone and memory.id == snapshot.id then return memory.entities; end
    local manager = AshitaCore:GetMemoryManager();
    memory.entities, memory.party, memory.player = manager:GetEntity(), manager:GetParty(), manager:GetPlayer();
    memory.targets, memory.follow = manager:GetTarget(), manager.GetAutoFollow and manager:GetAutoFollow() or nil;
    memory.zone, memory.id = snapshot.zone, snapshot.id;
    return memory.entities;
end

-- Ashita keeps positions as X, Z, Y with Z the height, and up is negative (Phoenix raises a point by subtracting
-- from it). So the render-space point height yalms above an entity is (X, Z - height, Y). Of the projection this is
-- the one part not proven from code: /vg overhead calibrate checks it on the current target.
local function world_point(entities, index, height)
    return entities:GetLocalPositionX(index), entities:GetLocalPositionZ(index) - height, entities:GetLocalPositionY(index);
end

-- Head height in yalms above the entity's position, and where it came from. Players by race, standing, then by
-- posture; mobs and pets from their hitbox. heights[name] replaces the standing height or the hitbox line;
-- offsets[name] and the type's world_offset are added.
function overhead.head_height(player, race, status, hitbox, name, head, world_offset)
    local height, source = head.heights[name], 'name';
    if not height then
        if player then height, source = head.race_heights[race] or head.default_height, 'race';
        else
            local r = hitbox > 0 and hitbox or head.default_hitbox;
            height, source = clamp(head.mob_height_base + head.mob_height_per_hitbox * r, head.mob_height_min, head.mob_height_max), 'hitbox';
        end
    end
    if player then
        -- Mounted (chocobo 5, mount 85), sitting or healing (33, 47), and in a chair (63 to 73).
        if status == 5 or status == 85 then height = head.mounted_base + head.mounted_factor * height;
        elseif status == 33 or status == 47 then height = height * head.sit_factor;
        elseif status >= 63 and status <= 73 then height = height * head.chair_factor; end
    end
    return height + (head.offsets[name] or 0) + (world_offset or 0), source;
end

-- Icon size in px before it settles on whole pixels: base, times the perspective (ref_depth / depth) ^ alpha, the
-- unit's size class clamp((R / ref_hitbox) ^ beta), the name's own factor, target_scale on the target and the type's
-- size_scale, clamped to min_px and max_px, then times ui (DisplaySize height / 1080 times the style scale).
function overhead.icon_size(player, race, hitbox, name, depth, target, config, ui, type_scale)
    local size, head = config.size, config.head;
    local r;
    if player then r = RACE_SIZES[race] or size.ref_hitbox;
    else r = hitbox > 0 and hitbox or head.default_hitbox; end
    local class = clamp((r / size.ref_hitbox) ^ size.beta, size.s_min, size.s_max) * (head.sizes[name] or 1);
    local px = size.base * (size.ref_depth / depth) ^ size.alpha * class * (target and size.target_scale or 1) * (type_scale or 1);
    return clamp(px, size.min_px, size.max_px) * ui;
end

-- Whole pixels, kept while the raw size moves 0.6 px or less, so slow camera bob doesn't flicker them.
local function settle(previous, raw)
    if previous > 0 and abs(raw - previous) <= 0.6 then return previous; end
    return floor(raw + 0.5);
end

-- Full until fade_start yalms, then down to fade_alpha at the distance cap. The target never fades.
function overhead.fade(distance, target, config)
    if target then return 1; end
    local start, cap = config.fade_start, config.distance_cap;
    if distance > start and cap > start then return 1 - clamp((distance - start) / (cap - start), 0, 1) * (1 - config.fade_alpha); end
    return 1;
end

-- The index of a server id: from the packets, the snapshot, or a mob's id, whose low 12 bits are its index.
local function index_for(entities, snapshot, id)
    local index = index_of[id];
    if index and entities:GetServerId(index) == id then return index; end
    local entity = snapshot.entities and snapshot.entities[id];
    if entity and entity.index and entity.index > 0 and entities:GetServerId(entity.index) == id then return entity.index; end
    if id >= 0x1000000 then
        index = id % 4096;
        if entities:GetServerId(index) == id then return index; end
        if index > 0x100 and entities:GetServerId(index - 0x100) == id then return index - 0x100; end
    end
end

-- What kind of unit an entity is: you, your pet, a mob (SpawnFlags 0x10, whatever its Type), a player in the party,
-- alliance or not, another pet, or nothing for a non-mob of Type 2 (fixed models) or 3 (doors).
local function classify(entities, index, id)
    if index == self_index then return 'self'; end
    if index == pet_index then return 'pet'; end
    if band(entities:GetSpawnFlags(index), 0x10) ~= 0 then return 'mob'; end
    if id < 0x1000000 then return party_scope[id] or 'other'; end
    local kind = entities:GetType(index);
    if kind == 2 or kind == 3 then return nil; end
    return scope_of[id] == 'pet' and 'other_pet' or 'other';
end

-- Whether a sorted list of effect ids holds id.
local function listed(list, id)
    local low, high = 1, #list;
    while low <= high do
        local middle = floor((low + high) / 2);
        local value = list[middle];
        if value == id then return true; end
        if value < id then low = middle + 1; else high = middle - 1; end
    end
    return false;
end

-- Whether a unit type has an effect's Always show tick on.
function overhead.ticked(kind, id) return kind[ALWAYS[id]] == true; end

-- Whether a unit type's own filters keep an effect: shown, not a recast, of the kinds it shows, mine only, buffs you
-- cast, debuffs from the party, its effect switches and its include and exclude lists. The include list beats a switch
-- that's off, and with debuffs only the switches aren't listed, so they decide nothing. An Always show tick beats what
-- the unit shows and who cast it, as far as the two lists let it. The shared hide rules are left to the drawing.
function overhead.keeps(kind, effect)
    local debuff, id, include = effect.kind == 'debuff', effect.effect, kind.include;
    if effect.present == false or effect.domain == 'recast' or listed(kind.exclude, id) then return false; end
    if overhead.ticked(kind, id) and (#include == 0 or listed(include, id)) then return true; end
    return not (kind.kinds == 'buff' and debuff or kind.kinds == 'debuff' and not debuff)
        and not (kind.mine_only and not effect.mine and not effect.by_pet)
        and not (kind.buffs_mine_only and not debuff and not effect.mine and not effect.by_pet)
        and not (kind.debuffs_party_only and debuff and effect.source and not party_ids[effect.source])
        and (#include > 0 and listed(include, id) or #include == 0 and (kind.kinds == 'debuff' or kind[SWITCH[id]] ~= false));
end

-- Whether a unit has a row its type's filters keep.
local function showing(kind, id)
    local at = first_row[id];
    while at and at > 0 do
        if overhead.keeps(kind, survey_rows[at]) then return true; end
        at = next_row[at];
    end
    return false;
end

local function better(level, distance, than) return level < than.level or level == than.level and distance < than.distance; end

local function fill(unit, entities, config, index, id, kind, level, distance)
    by_id[id] = unit;
    unit.id, unit.index, unit.kind, unit.level, unit.distance = id, index, kind, level, distance;
    unit.target, unit.subtarget, unit.size, unit.visible = false, false, 0, false;
    for i = 1, last_count do if last_ids[i] == id then unit.size = last_sizes[i]; break; end end
    unit.player = id < 0x1000000;
    unit.name = entities:GetName(index) or '';
    unit.race, unit.hitbox, unit.model_size = entities:GetRace(index) or 0, entities:GetModelHitboxSize(index) or 0, entities:GetModelSize(index) or 0;
    unit.spawn_flags, unit.type, unit.status = entities:GetSpawnFlags(index) or 0, entities:GetType(index) or 0, entities:GetStatus(index) or 0;
    unit.head, unit.head_source = overhead.head_height(unit.player, unit.race, unit.status, unit.hitbox, unit.name, config.head,
        config.types[kind].world_offset);
    unit.rows = rows_of[id] or 0;
end

-- Takes a unit as a candidate for a reason: the target, the subtarget and a watched unit (any unit), a mob claimed or
-- debuffed by the party (switch named by reason), or by what it is (reason nil). One its type's filters leave nothing to show
-- is left out, except the target, the subtarget and a member with party cooldowns over heads; so is one beyond the
-- distance cap. A full list keeps the best.
local function add(entities, snapshot, config, index, id, reason, level, city)
    if not index or index <= 0 or index > 0x8FF or not id or id <= 0 then return; end
    local unit = by_id[id];
    local flagged = level == TARGET or level == SUBTARGET;
    if unit then
        if level < unit.level then unit.level = level; end
        if level == TARGET then unit.target = true; elseif level == SUBTARGET then unit.subtarget = true; end
        return;
    end
    if entities:GetServerId(index) ~= id then return; end
    local kind = classify(entities, index, id);
    if not kind then return; end
    if not reason then
        if not config.units[kind] then return; end
        level = LEVELS[kind];
    elseif reason ~= 'target' and reason ~= 'subtarget' and reason ~= 'watched' and kind ~= 'mob' then return; end
    if city and not flagged and kind ~= 'party' and kind ~= 'self' then return; end
    -- A party or alliance member with party cooldowns over heads takes a block for that line.
    if not flagged and not showing(config.types[kind], id) and not ((kind == 'party' or kind == 'alliance') and cooling[id]) then
        return;
    end
    local squared = entities:GetDistance(index);
    local distance = type(squared) == 'number' and squared >= 0 and sqrt(squared) or huge;
    if distance > config.distance_cap then return; end
    if pool_count < CANDIDATES then
        pool_count = pool_count + 1;
        unit = pool[pool_count];
    else
        local worst = pool[1];
        for i = 2, pool_count do if better(worst.level, worst.distance, pool[i]) then worst = pool[i]; end end
        if not better(level, distance, worst) then return; end
        by_id[worst.id] = nil;
        unit = worst;
    end
    fill(unit, entities, config, index, id, kind, level, distance);
    if level == TARGET then unit.target = true; elseif level == SUBTARGET then unit.subtarget = true; end
end

-- Who is in the party (and so whose claims and debuffs count), each unit's effect rows and how many, which mobs
-- the party has debuffed, and who has party cooldowns to show over heads, from the frame's tracker view.
local function survey(entities, view, snapshot, settings)
    wipe(party_ids); wipe(party_scope); wipe(rows_of); wipe(scope_of); wipe(debuffed); wipe(first_row);
    local watch = settings.party_cooldowns;
    cooling = type(watch) == 'table' and watch.enabled and watch.overhead and view and view.member_cooldowns or NONE;
    party_ids[snapshot.id] = true;
    for _, member in ipairs(snapshot.party or NONE) do
        party_ids[member.id], party_scope[member.id] = true, member.scope == 'alliance' and 'alliance' or 'party';
    end
    pet_index = self_index > 0 and entities:GetPetTargetIndex(self_index) or 0;
    local pet = pet_index > 0 and entities:GetServerId(pet_index) or 0;
    if pet > 0 then party_ids[pet] = true; end
    survey_rows = view and view.rows or NONE;
    for index, row in ipairs(survey_rows) do
        local id = row.entity_id;
        if row.domain ~= 'recast' and id then
            rows_of[id], scope_of[id] = (rows_of[id] or 0) + 1, row.scope;
            next_row[index], first_row[id] = first_row[id] or 0, index;
            if row.kind == 'debuff' and row.scope == 'enemy' and row.source and party_ids[row.source] then debuffed[id] = true; end
        end
    end
end

local function rebuild(entities, view, settings, snapshot, main, sub)
    local config = settings.overhead;
    for i = 1, pool_count do
        local unit = pool[i];
        by_id[unit.id], last_ids[i], last_sizes[i] = nil, unit.id, unit.size;
    end
    last_count, pool_count = pool_count, 0;
    survey(entities, view, snapshot, settings);
    local units, city = config.units, config.hide_in_cities and CITIES[snapshot.zone] == true;
    if units.target and main > 0 then add(entities, snapshot, config, main, entities:GetServerId(main), 'target', TARGET, city); end
    if units.subtarget and sub > 0 then add(entities, snapshot, config, sub, entities:GetServerId(sub), 'subtarget', SUBTARGET, city); end
    if units.claimed then
        for id, claimer in pairs(claimer_of) do
            if party_ids[claimer] then add(entities, snapshot, config, index_for(entities, snapshot, id), id, 'claimed', CLAIMED, city); end
        end
    end
    if units.watched then
        for _, id in ipairs(settings.watch_ids or NONE) do add(entities, snapshot, config, index_for(entities, snapshot, id), id, 'watched', WATCHED, city); end
    end
    if units.debuffed then
        for id in pairs(debuffed) do add(entities, snapshot, config, index_for(entities, snapshot, id), id, 'debuffed', DEBUFFED, city); end
    end
    add(entities, snapshot, config, self_index, snapshot.id, nil, PARTY, city);
    for _, member in ipairs(snapshot.party or NONE) do add(entities, snapshot, config, member.index, member.id, nil, PARTY, city); end
    if pet_index > 0 then add(entities, snapshot, config, pet_index, entities:GetServerId(pet_index), nil, PET, city); end
    if units.other or units.other_pet then
        for id, scope in pairs(scope_of) do
            if (scope == 'other' or scope == 'pet') and not by_id[id] then
                add(entities, snapshot, config, index_for(entities, snapshot, id), id, nil, OTHER, city);
            end
        end
    end
end

-- Hidden for every unit, and why: Vantage's displays hidden, no character, a zone change, the game's interface
-- hidden, an event or the map. A flag whose client pattern wasn't found is skipped, so it never hides for good. Show
-- conditions are left to overhead.update, as they never hide the samples.
local function hidden_reason(entities, snapshot, displays_hidden)
    if displays_hidden then return 'Vantage displays are hidden.'; end
    if not snapshot or not snapshot.valid then return 'No character is in the game.'; end
    if not capabilities then capabilities = client.capabilities(); end
    local waiting, interface, event, map = client.world_flags();
    if waiting or truth(memory.player:GetIsZoning()) or memory.party:GetMemberServerId(0) ~= snapshot.id
        or memory.party:GetMemberZone(0) ~= snapshot.zone then return 'Changing zones.'; end
    if capabilities.hidden and interface == 1 then return 'The game interface is hidden.'; end
    if capabilities.event and event == 1 or self_index > 0 and entities:GetStatus(self_index) == 4 then return 'In an event.'; end
    if capabilities.map and map == true then return 'The map is open.'; end
end

-- Above the name, the bottom edge of a block over a name whose middle is at sy on screen, with ppy px per yalm there.
-- The game's names are taken as things in the world, name_height yalms tall but never more than name_cap px (times
-- k), and the target cursor just over the target's name the same way. The block goes the gap over both. Returns the
-- edge's y in whole pixels, the name's height and the cursor's.
function overhead.above_name(sy, ppy, target, layout, ui, k, screen_y)
    local name = math.min(layout.name_cap * k, layout.name_height * ppy);
    local arrow = target and math.min(layout.target_cap * k, layout.target_height * ppy) or 0;
    return floor(sy - name / 2 - arrow - layout.gap * ui + screen_y + 0.5), name, arrow;
end

-- How far above the head the point a block is placed from sits: the middle of the game's name above it, the head
-- itself under it.
local function lift(kind) return plan.above and kind.name_lift or 0; end

-- The point on screen in whole pixels, and the block's anchor from it: the middle of its bottom edge above the name,
-- or of its top edge under the head.
local function anchor(unit, sx, sy, kind, layout, ui)
    unit.x, unit.y = floor(sx + 0.5), floor(sy + 0.5);
    unit.anchor_x = floor(sx + kind.screen_x + 0.5);
    if plan.above then
        unit.anchor_y, unit.name_px, unit.arrow_px = overhead.above_name(sy, unit.ppy, unit.target, layout, ui, plan.k, kind.screen_y);
    else unit.anchor_y, unit.name_px, unit.arrow_px = floor(sy + layout.gap * ui + kind.screen_y + 0.5), 0, 0; end
end

-- The name's size on screen: the client draws a font texel DisplaySize height * 0.00234375 px tall, times s, which
-- shrinks it once the NDC depth passes 4020 / 4096. Returns s and the texel in px.
function overhead.name_scale(depth, height)
    local zi = floor(depth * 4096);
    local s = zi < 4020 and 1 or clamp((4100 - zi) / 80, 0, 1);
    return s, height * 0.00234375 * s;
end

-- Above the name from the game's name point, at ax, ay on screen with NDC depth ndc (px, py, pz in render space).
-- The name hangs down from that point, half a pixel up as the client draws it; an icon in front of the name reaches
-- rise font texels over it, and the target cursor over the unit carrying it from the cursor's own box. The block
-- goes the gap over the highest of them. The type's world_offset and offsets[name] raise the point in yalms, and its
-- screen_x and screen_y move the block. Fills out's placement and cache's values for /vg report.
local function on_name(out, cache, index, name, ax, ay, ndc, px, py, pz, kind, config, ui)
    local s, t = overhead.name_scale(ndc, plan.height);
    local name_top = ay - 0.5;
    local icon_top = name_top - ceil(cache.np_rise * t);
    local arrow_top, arrow = name_anchor.arrow_top(index, ay, cache.np_ai);
    local clear = min(name_top, icon_top, arrow_top);
    local raise, dx, dy = kind.world_offset + (config.head.offsets[name] or 0), 0, 0;
    if raise ~= 0 then
        local rx, ry = camera.project(px, py - raise, pz);
        if rx then dx, dy = rx - ax, ry - ay; end
    end
    out.x, out.y = floor(ax + 0.5), floor(ay + 0.5);
    out.anchor_x = floor(ax + dx + kind.screen_x + 0.5);
    out.anchor_y = floor(clear + dy - config.layout.gap * ui + kind.screen_y + 0.5);
    out.name_px, out.arrow_px = 0, arrow and name_top - arrow_top or 0;
    cache.np_ax, cache.np_ay, cache.np_ndc, cache.np_s, cache.np_t = ax, ay, ndc, s, t;
    cache.np_name_top, cache.np_icon_top, cache.np_arrow_top, cache.np_arrow = name_top, icon_top, arrow_top, arrow or false;
end

-- The game's name point of a unit, or nil and why not. An error reading it turns name points off until the addon
-- loads again, and the blocks keep the guess.
local function name_point(cache, entities, index, id, actor)
    local ok, x, y, z = pcall(name_anchor.point, cache, entities, index, id, actor, generation);
    if ok then return x, y, z; end
    pointed = false;
    name_anchor.fail(x);
    return nil, 'Reading the name point failed.';
end

-- Draw tests, the point it is placed from on screen, the size and the fade for one candidate. Returns whether it
-- gets a block.
local function place(unit, entities, config, ui, cap, first_person)
    local index = unit.index;
    if entities:GetServerId(index) ~= unit.id then return false, true; end
    local actor = entities:GetActorPointer(index);
    if actor == 0 then return false; end
    -- Drawn: 0x200 set and 0x4000 (hidden in a cutscene or menu) clear.
    local flags = entities:GetRenderFlags0(index);
    if band(flags, 0x200) == 0 or band(flags, 0x4000) ~= 0 then return false; end
    local status = entities:GetStatus(index);
    if status == 2 or status == 3 or unit.kind == 'mob' and entities:GetHPPercent(index) == 0 then return false; end
    if unit.kind == 'self' and first_person then return false; end
    -- A unit the client gives no distance for gets no block, as when the list is made.
    local squared = entities:GetDistance(index);
    local distance = type(squared) == 'number' and squared >= 0 and sqrt(squared) or huge;
    if distance > cap then return false; end
    if status ~= unit.status then
        unit.status = status;
        unit.head, unit.head_source = overhead.head_height(unit.player, unit.race, status, unit.hitbox, unit.name, config.head,
            config.types[unit.kind].world_offset);
    end
    local kind = config.types[unit.kind];
    local px, py, pz;
    unit.path, unit.why = 'guess', false;
    if pointed then
        px, py, pz = name_point(unit, entities, index, unit.id, actor);
        if not px then unit.why = py; end
    elseif plan.above then unit.why = name_anchor.problem() or false; end
    local sx, sy, depth, ndc;
    if px then sx, sy, depth, ndc = camera.project(px, py, pz);
    else sx, sy, depth = camera.project(world_point(entities, index, unit.head + lift(kind))); end
    if not sx then return false; end
    local size = settle(unit.size, overhead.icon_size(unit.player, unit.race, unit.hitbox, unit.name, depth, unit.target,
        config, ui, kind.size_scale));
    -- Off screen once the point is further out than about half a bar of icons.
    local margin, width, height = size * 4, plan.width, plan.height;
    if sx < -margin or sx > width + margin or sy < -margin or sy > height + margin then return false; end
    unit.distance, unit.depth, unit.size, unit.ppy = distance, depth, size, camera.pixels_per_yalm(depth);
    if px then
        unit.path = 'name point';
        on_name(unit, unit, index, unit.name, sx, sy, ndc, px, py, pz, kind, config, ui);
    else anchor(unit, sx, sy, kind, config.layout, ui); end
    unit.alpha = overhead.fade(distance, unit.target, config);
    return true;
end

local function clear()
    local units, order = plan.units, plan.order;
    for i = #units, 1, -1 do units[i], order[i] = nil, nil; end
end

local function first(a, b) return a.level < b.level or a.level == b.level and a.depth < b.depth; end

-- Picks up to max_units of the placed candidates, best first, and the draw order: far to near, then the target, so
-- its block is on top of any nearer one.
local function choose(config)
    local count = 0;
    for i = 1, pool_count do
        local unit = pool[i];
        if unit.visible then
            -- An insertion sort over a list of at most 24.
            local at = count + 1;
            while at > 1 and first(unit, picked[at - 1]) do picked[at] = picked[at - 1]; at = at - 1; end
            picked[at], count = unit, count + 1;
        end
    end
    local kept, units, order = math.min(count, config.max_units), plan.units, plan.order;
    for i = 1, kept do
        units[i] = picked[i];
        local at = i;
        -- The target is best, so it goes in first; every unit after it goes before it.
        while at > 1 and (units[order[at - 1]].target or units[order[at - 1]].depth < picked[i].depth) do
            order[at] = order[at - 1]; at = at - 1;
        end
        order[at] = i;
    end
    for i = kept + 1, #units do units[i], order[i] = nil, nil; end
    for i = count, 1, -1 do picked[i] = nil; end
    plan.count = kept;
end

local function target_indexes(targets)
    local sub = truth(targets:GetIsSubTargetActive());
    return targets:GetTargetIndex(sub and 1 or 0) or 0, sub and targets:GetTargetIndex(0) or 0;
end

local function calibration(entities, snapshot, config, ui)
    local lines = {};
    local main = target_indexes(memory.targets);
    if main <= 0 or entities:GetServerId(main) == 0 then
        lines[1] = 'Target a unit, then use /vg overhead calibrate again.';
        return lines;
    end
    local id = entities:GetServerId(main);
    local kind = classify(entities, main, id) or 'other';
    local race, hitbox, status, name = entities:GetRace(main) or 0, entities:GetModelHitboxSize(main) or 0, entities:GetStatus(main) or 0,
        entities:GetName(main) or tostring(id);
    local head, source = overhead.head_height(id < 0x1000000, race, status, hitbox, name, config.head, config.types[kind].world_offset);
    local sources = { race = 'its race', hitbox = 'its hitbox', name = 'your height for this name' };
    lines[1] = ('%s: %s, SpawnFlags 0x%02X, Type %d, race %d, hitbox %.1f, ModelSize %.2f, head %.2f yalms from %s.'):format(name, kind,
        entities:GetSpawnFlags(main) or 0, entities:GetType(main) or 0, race, hitbox, entities:GetModelSize(main) or 0, head, sources[source]);
    local report = camera.report();
    -- The problem can name a matrix entry such as P34, so only its first letter is lowered.
    local problem = (report.problem or 'its checks failed'):gsub('%.$', ''):gsub('^%u', string.lower);
    local text = ('Camera read at %s: %s.'):format(report.capture, report.valid and 'in use' or 'not in use, ' .. problem);
    -- Where this frame's view puts the camera under each mapping, read even when its checks failed: with the wrong
    -- mapping only X,Y,Z is near you.
    if report.read then
        local own_x, own_z, own_y = world_point(entities, self_index, 0);
        local eye_x, eye_y, eye_z = camera.eye();
        local here = sqrt((eye_x - own_x) ^ 2 + (eye_y - own_z) ^ 2 + (eye_z - own_y) ^ 2);
        local swapped = sqrt((eye_x - own_x) ^ 2 + (eye_y - own_y) ^ 2 + (eye_z - own_z) ^ 2);
        local reach = config.camera.max_distance;
        local near = here <= reach and (swapped <= reach and 'Both are' or 'Only X,Z,Y is')
            or swapped <= reach and 'Only X,Y,Z is' or 'Neither is';
        text = text .. (' It sits %.1f yalms from you as X,Z,Y (%.1f as X,Y,Z). %s within %g yalms.'):format(here, swapped, near, reach);
    end
    if report.valid then
        local hx, hy, depth = camera.project(world_point(entities, main, head));
        local _, fy = camera.project(world_point(entities, main, 0));
        if hx and fy then
            local size = floor(overhead.icon_size(id < 0x1000000, race, hitbox, name, depth, true, config, ui, config.types[kind].size_scale) + 0.5);
            text = text .. (' The head is %d px above the feet, icons %d px at depth %.1f.'):format(floor(fy - hy + 0.5), size, depth);
        else text = text .. ' The target is behind the camera.'; end
    end
    local back = report.backbuffer;
    lines[2] = text .. (' Display %dx%d%s.'):format(report.display.width, report.display.height,
        back and (', back buffer %dx%d'):format(back.width, back.height) or '');
    return lines;
end

-- Asks the next frame to read the current target and the camera, for /vg overhead calibrate. It only reads.
function overhead.calibrate(settings)
    calibrate_pending = true;
    camera.wake(settings.overhead.camera);
end

-- Works out this frame's plan. displays_hidden is /vg hide or Ashita's hidden interface; conditions_hidden is the
-- overhead icons' show conditions failing here, which hides the blocks but not the samples. Returns the calibrate
-- lines on the frame that reads them, for the caller to print and keep in the report.
function overhead.update(view, settings, snapshot, now, displays_hidden, conditions_hidden)
    plan.count, plan.valid, pointed = 0, false, false;
    local config = settings.overhead;
    if not config.enabled and not calibrate_pending then
        clear();
        plan.hidden, plan.considered, spot = 'Off.', 0, nil;
        camera.idle();
        return;
    end
    -- The client patterns for the name points are warmup steps after a load (core/warmup.lua). Until they have run no
    -- block or sample shows, so each appears on its name point and never at a guessed height first. Without the
    -- warmup they are looked for here, once, the first time overhead icons are on.
    local loading = config.enabled and warmup.need('names');
    if config.enabled and not loading then name_anchor.load(); end
    local entities = snapshot and snapshot.valid and interfaces(snapshot);
    local own = entities and snapshot.entities and snapshot.entities[snapshot.id];
    self_index = own and own.index or 0;
    local reason = loading and 'Still loading.' or hidden_reason(entities, snapshot, displays_hidden);
    local screen = require('imgui').GetIO().DisplaySize;
    plan.width, plan.height = screen.x, screen.y;
    plan.k = plan.height / 1080;
    local ui = plan.k * (settings.style.scale or 1);
    plan.ui, plan.above = ui, config.layout.placement ~= 'below_name';
    local unusable = false;
    if reason then camera.skip();
    elseif not camera.frame(now, config.camera, plan.width, plan.height, world_point(entities, self_index, 0)) then
        reason, unusable = 'The camera can\'t be used.', true;
    end
    spot = config.enabled and (not reason and 'head' or unusable and 'fixed') or nil;
    local lines;
    if calibrate_pending then
        calibrate_pending = false;
        -- A camera that fails its checks still calibrates, to show which position mapping puts it near you.
        lines = entities and (not reason or unusable) and calibration(entities, snapshot, config, ui)
            or { 'Overhead icons can\'t calibrate now. ' .. (reason or 'No character is in the game.') };
        overhead.last_calibrate = lines;
    end
    if not config.enabled or reason then
        clear();
        plan.hidden = config.enabled and reason or 'Off.';
        return lines;
    end
    local main, sub = target_indexes(memory.targets);
    local ticked = now - ticked_at >= 0.1 or now < ticked_at;
    if ticked then ticked_at, generation = now, generation + 1; end
    -- Where the target cursors are this frame, for the blocks and the samples alike.
    pointed = plan.above and name_anchor.usable();
    if pointed then name_anchor.arrows(memory.targets, plan.height, generation, main, sub); end
    if conditions_hidden then
        clear();
        plan.hidden, plan.considered = 'Its When to show choices hide it here.', 0;
        return lines;
    end
    plan.hidden = nil;
    if now - rebuilt_at >= 0.1 or now < rebuilt_at or view ~= rebuilt_view or settings ~= rebuilt_settings or main ~= main_seen or sub ~= sub_seen then
        rebuild(entities, view, settings, snapshot, main, sub);
        rebuilt_at, rebuilt_view, rebuilt_settings, main_seen, sub_seen = now, view, settings, main, sub;
        -- Once a frame: a list made between ticks starts the next tenth of a second.
        if not ticked then ticked_at, generation = now, generation + 1; end
    end
    local first_person = false;
    if by_id[snapshot.id] and memory.follow then first_person = truth(memory.follow:GetIsFirstPersonCamera()); end
    local stale = false;
    for i = 1, pool_count do
        local unit = pool[i];
        local shown, moved = place(unit, entities, config, ui, config.distance_cap, first_person);
        unit.visible, stale = shown, stale or moved == true;
    end
    -- An index now holds another entity: the list is made again next frame.
    if stale then rebuilt_at = -1; end
    plan.considered, plan.valid = pool_count, true;
    choose(config);
    return lines;
end

-- The preview's sample block (ui/overhead_preview.lua), read after overhead.update: a unit of type kind, the target
-- when it is a mob, above your own head as a block of that type would sit there. It takes your head height with the
-- type's offsets, over your own name, and that type's size at your depth: players at your race's size, mobs and
-- pets at the median hitbox. With you off screen (the camera can't be used, or you are behind it, off the
-- screen, not drawn or in first person) it sits a third of the way down the middle of the screen, sized at
-- ref_depth. Its size holds through 0.6 px as a block's does; the preview sets unit.size to 0 for a new type. Fills
-- unit and returns true, or false while every block is off or hidden.
function overhead.sample(unit, settings, snapshot, kind)
    if not spot then return false; end
    local config, entities = settings.overhead, memory.entities;
    local types, ui = config.types[kind], plan.ui;
    local player = kind == 'self' or kind == 'party' or kind == 'alliance' or kind == 'other';
    unit.kind, unit.target, unit.subtarget, unit.player, unit.hitbox, unit.name = kind, kind == 'mob', false, player, 0, '';
    unit.race, unit.alpha, unit.distance = 0, 1, 0;
    local sx, sy, depth, ndc, px, py, pz;
    if self_index > 0 and entities:GetServerId(self_index) == snapshot.id then
        unit.race = entities:GetRace(self_index) or 0;
        local flags, actor = entities:GetRenderFlags0(self_index), entities:GetActorPointer(self_index);
        if spot == 'head' and actor ~= 0 and band(flags, 0x200) ~= 0 and band(flags, 0x4000) == 0
            and not (memory.follow and truth(memory.follow:GetIsFirstPersonCamera())) then
            -- Above the name, from your own name point as your own block would sit.
            if pointed then px, py, pz = name_point(sample_cache, entities, self_index, snapshot.id, actor); end
            if px then sx, sy, depth, ndc = camera.project(px, py, pz);
            else
                local head = overhead.head_height(true, unit.race, entities:GetStatus(self_index) or 0, 0, '', config.head, types.world_offset);
                -- The name under it is yours, so above the name it takes your own type's name height.
                sx, sy, depth = camera.project(world_point(entities, self_index, head + lift(config.types.self)));
            end
            if sx and (sx < 0 or sx > plan.width or sy < 0 or sy > plan.height) then sx = nil; end
        end
    end
    -- The fixed spot has no name under it, and leaves the room of a near one, at its largest: px per yalm so large
    -- the caps win, but not huge, as 0 yalms times huge is not 0.
    if sx then unit.ppy = camera.pixels_per_yalm(depth);
    else sx, sy, depth, unit.ppy, px = plan.width * 0.5, plan.height / 3, config.size.ref_depth, 1e6, nil; end
    unit.depth = depth;
    unit.size = settle(unit.size, overhead.icon_size(player, unit.race, 0, '', depth, unit.target, config, ui, types.size_scale));
    if px then on_name(unit, sample_cache, self_index, '', sx, sy, ndc, px, py, pz, types, config, ui);
    else anchor(unit, sx, sy, types, config.layout, ui); end
    return true;
end

-- A report value to places decimals, or in words when JSON can't hold it.
local function rounded(value, places)
    if type(value) ~= 'number' then return value; end
    if value ~= value or value == huge or value == -huge then return tostring(value); end
    local scale = 10 ^ (places or 2);
    return floor(value * scale + 0.5) / scale;
end

-- Where the client's own cameras put a render-space point on the display, against where Vantage's camera puts it:
-- the client's copies (app), the wrapper's cache at the scene read (scene) and now (now), with Vantage minus each.
local function cross(cameras, x, y, z)
    local vx, vy = camera.project(x, y, z);
    local out = { vantage_x = rounded(vx), vantage_y = rounded(vy) };
    for _, key in ipairs({ 'app', 'scene', 'now' }) do
        local gx, gy = name_anchor.game_point(cameras[key], cameras.scene_target, x, y, z, plan.width, plan.height);
        if gx then
            out[key .. '_x'], out[key .. '_y'] = rounded(gx), rounded(gy);
            if vx then out[key .. '_dx'], out[key .. '_dy'] = rounded(vx - gx), rounded(vy - gy); end
        end
    end
    return out;
end

-- The name point part of /vg report: the client patterns and offsets, the target window and its cursors, the client
-- cameras against Vantage's, and for each unit with a block or a cursor every value its name point is made from, how
-- its block was placed this frame and where the guess would have put it.
local function point_report(settings, snapshot)
    local config, entities = settings.overhead, interfaces(snapshot);
    local out = name_anchor.status(memory.targets);
    out.display, out.placement = { width = plan.width, height = plan.height }, config.layout.placement;
    local cameras = name_anchor.cameras();
    out.cameras = { usable = cameras.usable, problem = cameras.problem, window = cameras.window, scene_target = cameras.scene_target,
        viewport = cameras.viewport, app = cameras.app ~= nil, scene = cameras.scene ~= nil, now = cameras.now ~= nil };
    out.units = {};
    local seen, main = {}, target_indexes(memory.targets);
    local a, b = name_anchor.arrow_units();
    local function add_row(index, unit)
        if not index or index <= 0 or seen[index] then return; end
        seen[index] = true;
        local id = entities:GetServerId(index);
        if id == 0 then return; end
        unit = unit or by_id[id];
        local row = name_anchor.detail(entities, index, id, entities:GetActorPointer(index));
        local kind = unit and unit.kind or classify(entities, index, id) or 'other';
        local types = config.types[kind];
        -- The guess: the head height and name lift, and the name centred on that point.
        local race, status, hitbox, name = entities:GetRace(index) or 0, entities:GetStatus(index) or 0,
            entities:GetModelHitboxSize(index) or 0, entities:GetName(index) or '';
        local head = overhead.head_height(id < 0x1000000, race, status, hitbox, name, config.head, types.world_offset)
            + (types.name_lift or 0);
        local ox, oy, oz = world_point(entities, index, head);
        local _, hy, depth = camera.project(ox, oy, oz);
        if hy then
            row.guess_y = rounded(hy);
            row.guess_anchor_y = overhead.above_name(hy, camera.pixels_per_yalm(depth), unit and unit.target or index == main, config.layout,
                plan.ui, plan.k, types.screen_y);
        end
        if cameras.usable and row.x then
            row.check = { game = cross(cameras, row.x, row.y, row.z), guess = cross(cameras, ox, oy, oz),
                root = cross(cameras, row.root_x, row.root_y, row.root_z) };
        end
        row.race, row.status, row.hitbox, row.model_size = race, status, hitbox, entities:GetModelSize(index);
        for key, value in pairs(row) do if type(value) == 'number' then row[key] = rounded(value, 4); end end
        for _, key in ipairs({ 'actor', 'entity', 'node', 'handle', 'data', 'actor_88', 'flags0', 'flags1', 'flags2', 'flags3', 'flags4',
            'flags7', 'flags8' }) do
            if type(row[key]) == 'number' then row[key] = ('0x%08X'):format(row[key]); end
        end
        row.id, row.index, row.name, row.kind = id, index, name, kind;
        row.arrow = (index == a and 'A' or '') .. (index == b and 'B' or '');
        row.placed = unit and unit.visible or false;
        if unit and unit.visible then
            row.path, row.reason, row.anchor_x, row.anchor_y = unit.path, unit.why or nil, unit.anchor_x, unit.anchor_y;
            if unit.path == 'name point' then
                -- ax and ay unrounded, as the frame placed it, with its clip w and NDC x and y.
                row.ax, row.ay, row.ndc_z, row.zi = unit.np_ax, unit.np_ay, unit.np_ndc, floor(unit.np_ndc * 4096);
                row.w, row.ndc_x, row.ndc_y = rounded(unit.depth, 4), rounded(unit.np_ax * 2 / plan.width - 1, 6),
                    rounded(1 - unit.np_ay * 2 / plan.height, 6);
                row.s, row.t, row.name_top, row.icon_top = rounded(unit.np_s, 4), rounded(unit.np_t, 4), rounded(unit.np_name_top),
                    rounded(unit.np_icon_top);
                row.arrow_top = unit.np_arrow and rounded(unit.np_arrow_top) or nil;
                -- Under the main cursor on its name's point, display px per menu px as its stored point gives it, to set
                -- against window.ky.
                local ank = out.window.ank_y;
                if index == a and not out.window.a_stored and row.arrow_index == 2 and type(ank) == 'number' and ank > 0 then
                    row.ky_sample = rounded(unit.np_ay / ank, 4);
                end
            end
        end
        out.units[#out.units + 1] = row;
    end
    for i = 1, plan.count do add_row(plan.units[i].index, plan.units[i]); end
    add_row(a);
    add_row(b);
    return out;
end

-- The overhead part of /vg report: the camera (capture point, checks, matrices, DisplaySize against the back buffer
-- and viewport, the client's boot sizes), units considered and kept, and for the target what its block is sized from
-- and where it went, then the name points.
function overhead.report(settings, snapshot)
    local out = { enabled = settings.overhead.enabled == true, camera = camera.report(settings.overhead.camera), hidden = plan.hidden,
        considered = plan.considered, kept = plan.count, calibrate = overhead.last_calibrate, boot = {} };
    for _, key in ipairs({ '0001', '0002', '0003', '0004' }) do
        local ok, value = pcall(function() return AshitaCore:GetConfigurationManager():GetUInt32('boot', 'ffxi.registry', key, 0); end);
        out.boot[key] = ok and value or nil;
    end
    local ok, target = pcall(function()
        local entities = interfaces(snapshot);
        local main = target_indexes(memory.targets);
        local id = main > 0 and entities:GetServerId(main) or 0;
        if id == 0 then return nil; end
        local kind = classify(entities, main, id) or 'other';
        local row = { id = id, index = main, name = entities:GetName(main), kind = kind, type = entities:GetType(main),
            spawn_flags = entities:GetSpawnFlags(main), race = entities:GetRace(main), status = entities:GetStatus(main),
            hitbox = entities:GetModelHitboxSize(main), model_size = entities:GetModelSize(main),
            render_flags = entities:GetRenderFlags0(main), claimer = claimer_of[id] };
        row.head, row.head_source = overhead.head_height(id < 0x1000000, row.race or 0, row.status or 0, row.hitbox or 0,
            row.name or '', settings.overhead.head, settings.overhead.types[kind].world_offset);
        local unit = by_id[id];
        if unit and unit.visible then
            row.depth, row.ppy, row.size = unit.depth, unit.ppy, unit.size;
            -- Where its block went, in pixels from the top of the display, to check against a screenshot: its feet,
            -- the block's edge and above the name the name's middle, and the name's and the cursor's height.
            local _, feet = camera.project(world_point(entities, main, 0));
            row.feet_y, row.anchor_y = feet and floor(feet + 0.5), unit.anchor_y;
            if plan.above then
                row.name_y, row.name_px, row.arrow_px = unit.y, floor(unit.name_px * 10 + 0.5) / 10, floor(unit.arrow_px * 10 + 0.5) / 10;
            end
        end
        return row;
    end);
    if ok then out.target = target; end
    local read, points = pcall(point_report, settings, snapshot);
    out.name_point = read and points or { problem = 'The name points could not be reported. ' .. tostring(points) };
    return out;
end

if VANTAGE_TEST_MODE then
    function overhead._reset()
        for i = 1, pool_count do by_id[pool[i].id] = nil; end
        pool_count, last_count, rebuilt_at, rebuilt_view, rebuilt_settings, main_seen, sub_seen = 0, 0, -1, nil, nil, 0, 0;
        generation, ticked_at, pointed = 0, -1, false;
        memory.entities, capabilities, calibrate_pending, overhead.last_calibrate, spot = nil, nil, false, nil, nil;
        forget();
    end
    overhead._claimer = function(id) return claimer_of[id]; end
    overhead.world_point = world_point;
    overhead._cities = CITIES;
end

return overhead;
