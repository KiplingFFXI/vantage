local catalog = require('core.catalog');
local new_table = require('table.new');
local clear = require('table.clear');
local tracker = {};
local methods = {};
methods.__index = methods;

local function copy(value)
    if type(value) ~= 'table' then return value; end
    local result = {};
    for k, v in pairs(value) do result[k] = type(v) == 'table' and copy(v) or v; end
    return result;
end

local function finite(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge;
end

-- An effect nothing names doesn't exist on Phoenix, and the client has no icon for it either: with no row, nothing shows it.
-- A named one stays named, so a refresh doesn't ask again.
local named = {};
local function effect_id(value)
    if named[value] then return true; end
    if not finite(value) or value < 0 or value > 65534 or value ~= math.floor(value) or value == 255
        or catalog.get(value).unnamed then return false; end
    named[value] = true;
    return true;
end

local function locate(snapshot, id)
    if snapshot and snapshot.id == id then
        return 'self', snapshot.name or 'You';
    end
    for _, member in ipairs(snapshot and snapshot.party or {}) do
        if member.id == id then return member.scope=='alliance' and 'alliance' or 'party', member.name; end
    end
    local entity = snapshot and snapshot.entities and snapshot.entities[id];
    local selected = snapshot and snapshot.target;
    entity = entity or (selected and selected.id == id and selected);
    if entity then
        local kind = entity.kind;
        return (kind == 'monster' or kind == 'mob' or kind == 'enemy') and 'enemy'
            or (kind == 'pet' and 'pet' or 'other'), entity.name;
    end
    return 'other', nil;
end

-- The reason core/observer.lua gives a 0x029 wear-off, the only end that makes a time to learn.
tracker.WEAR_OFF = 'Observed wearoff';

function tracker.new()
    return setmetatable({ entities = {}, pending = {}, events = {}, held_samples = {}, sequence = 0,
        session = nil, valid = false, version = 0, records = {}, spare_records = {} }, methods);
end

-- Copy Image (66) shows its shadows as icons 444 (2), 445 (3) and 446 (4 or more) of the same effect. A copy that leaves the
-- tracker reads as 66 whatever icon it shows, so every list, rule, color and order knows Copy Image once. It keeps the icon
-- to draw it by.
local function as_copy_image(row)
    local icon = row.effect;
    if icon == 444 or icon == 445 or icon == 446 then
        local info = catalog.get(66);
        row.icon, row.effect, row.name = icon, 66, info.name;
        row.kind, row.group, row.priority = info.kind or row.kind, info.group or row.group, info.priority or row.priority;
    end
end

function methods:queue(kind, row, now, reason)
    local event = copy(row);
    as_copy_image(event);
    event.kind, event.time, event.reason = kind, now, reason or row.reason;
    event.category = row.kind;
    if #self.events >= 512 then table.remove(self.events, 1); end
    self.events[#self.events + 1] = event;
    self.version = self.version + 1;
    -- The wear-off of a cast of yours waits before it is a time to learn (methods:samples).
    if kind == 'removed' and event.reason == tracker.WEAR_OFF and type(row.learn_key) == 'string' and finite(row.learn_start) then
        local held = self.held_samples;
        if #held >= 64 then table.remove(held, 1); end
        held[#held + 1] = { entity_id = row.entity_id, entity_name = row.entity_name, effect = row.effect,
            learn_key = row.learn_key, learn_start = row.learn_start, time = now };
    end
end

function methods:entity(id, scope, name, now)
    if not finite(id) or id <= 0 then return nil; end
    local entity = self.entities[id];
    if not entity then
        -- A unit the game hasn't named yet has no name, until a later call brings it.
        entity = { id = id, scope = scope or 'other', name = name ~= '' and name or nil,
            entries = {}, known = false, baseline = false, seen = now, tombstones = {} };
        self.entities[id] = entity;
    end
    local renamed = scope and entity.scope ~= scope or name and name ~= '' and entity.name ~= name;
    if scope then entity.scope = scope; end
    if name and name ~= '' then entity.name = name; end
    if renamed then
        for _,row in ipairs(entity.entries) do row.scope,row.entity_name=entity.scope,entity.name; end
    end
    entity.seen = now;
    return entity;
end

function methods:create(entity, effect, now)
    local info = catalog.get(effect);
    if #entity.entries >= 64 then self:erase(entity,1,now,'The observation limit was reached.',true); end
    self.sequence = self.sequence + 1;
    local row = { key = tostring(entity.id) .. ':' .. tostring(self.sequence), instance = 1,
        effect = effect, name = info.name, kind = info.kind or 'other',
        group = info.group or 'Other', priority = info.priority or 0,
        entity_id = entity.id, entity_name = entity.name, scope = entity.scope,
        status = 'unknown', first_seen = now, first_sequence = self.sequence, observed_at = now, reason = 'The duration was not supplied.' };
    entity.entries[#entity.entries + 1] = row;
    self.version = self.version + 1;
    return row;
end

function methods:erase(entity, index, now, reason, quiet)
    local row = entity.entries[index];
    if not quiet then self:queue('removed', row, now, reason); end
    table.remove(entity.entries, index);
    self.version = self.version + 1;
end

-- Phoenix (status_effect_container.cpp ApplyBardEffect) replaces a song of the same ID and tier in its slot,
-- whoever sang it. Effects status_effects.yaml marks ignore_duplicate keep every copy. Any other effect has
-- one copy, and a new one from anyone replaces it.
local function song(effect) return effect >= 192 and effect <= 223; end
local DUPLICATES = { [162] = true, [233] = true, [234] = true, [287] = true, [309] = true };
for id = 300, 307 do DUPLICATES[id] = true; end
for id = 523, 530 do DUPLICATES[id] = true; end
local function single(effect) return not song(effect) and not DUPLICATES[effect]; end
-- Utsusemi keeps one Copy Image (66) and shows its shadows by icon, 446, 445, 444 then 66, on the same
-- timer (battleutils.cpp SetIcon). The 0x028 names 66. Applications are kept by this one key.
local COPY_IMAGE = { [66] = true, [444] = true, [445] = true, [446] = true };
local function key(effect) return COPY_IMAGE[effect] and 66 or effect; end
-- An icon change keeps the row. In here it reads as the effect the icon now shows, as the listings name it.
local function relabel(row, effect)
    if row.effect == effect then return; end
    local info = catalog.get(effect);
    row.effect, row.name = effect, info.name;
    row.kind, row.group, row.priority = info.kind or row.kind, info.group or row.group, info.priority or row.priority;
end
-- The game lists those icons only for your party. On a mob or an alliance member the icon shows Vantage's own count
-- (core/observer.lua), for 1, 2, 3, and 4 or more shadows.
local SHADOW_ICONS = { 66, 444, 445, 446 };

-- A zone change, character change or lost snapshot clears everything. Phoenix keeps an effect without
-- on_zone through a zone change as the same copy, so the player's own rows of effects with one copy leave a note of
-- who cast them, and the first listing after it gives that back to a copy it lists that nothing recast.
function methods:clear(reason, now)
    local own = self.self_id and self.entities[self.self_id];
    if own then
        local labels = {};
        for _, row in ipairs(own.entries) do
            if single(row.effect) and row.source ~= nil and row.present and not row.departing and not self.pending[key(row.effect)] then
                labels[row.effect] = { source = row.source, source_name = row.source_name, spell = row.spell, tier = row.tier,
                    mine = row.mine, by_pet = row.by_pet };
            end
        end
        self.carried = { id = self.self_id, labels = labels };
    end
    -- A wear-off still waiting may have lost the hit that came behind it.
    self.entities, self.pending, self.events, self.held_samples = {}, {}, {}, {};
    self.valid, self.session, self.pet_id, self.pet_index = false, nil, nil, nil;
    self.version = self.version + 1;
    self.events[1] = { kind = 'reset', quiet = true, reason = reason, time = now };
end
local WEAKNESS, RERAISE, HYMNUS = 1, 113, 218;
-- Spells Phoenix's enhancing_spell.lua marks Always_Overwrite: Aquaveil, the bar-spells and their -ra
-- forms, the storms, Refresh I to III and Embrava.
local OVERWRITES = { [55] = true, [99] = true, [109] = true, [473] = true, [478] = true, [894] = true };
for id = 60, 78 do OVERWRITES[id] = true; end
for id = 84, 92 do OVERWRITES[id] = true; end
for id = 113, 119 do OVERWRITES[id] = true; end
-- A gain sent as message 205 (Lua messageBasic): no action names a spell for it. Phoenix item scripts put an
-- effect back that way after taking it off with a message (reraise_earring.lua: delStatusEffect, then
-- addStatusEffect, then messageBasic 205), so a removal just before one, on the same 0x063 count, is a recast.
local function reported(observation) return observation.message == 205 and observation.spell == nil; end
-- The effects Phoenix items take off with a message and put back, with a 205 or none: Reraise (the earrings,
-- Reraisers, Raphael's Rod, the feathers, Reraise Gorget and Hairpin, White Rarab Cap +1), Flee (Hermes Quencher,
-- Powder Boots), both shields (item_utils.lua addItemShield), Invisible (Prism and Rainbow Powder), Sneak
-- (Sneaking Boots), Blaze Spikes (Blaze Hose) and Max HP and MP Boost (Body Boost, Giant's Drink, Mana Boost,
-- Wizard's Drink). Casting takes Invisible off with a message before the spell too (OnCastFinished).
local REUSED = { [32] = true, [34] = true, [69] = true, [71] = true, [88] = true, [89] = true, [113] = true,
    [150] = true, [152] = true };

-- ApplyBardEffect compares the status ID and the tier, and spells share tiers: all eight Carols, both
-- Mazurkas, seven Etudes a tier (enhancing_song.lua songPTable). Without both tiers, the spell decides.
local function same_tier(a, b)
    if a.tier ~= nil and b.tier ~= nil then return a.tier == b.tier; end
    return a.spell ~= nil and a.spell == b.spell;
end

-- Whether an application lands on that listed copy in place: any one with a spell replaces a single copy, as
-- does a 205 that puts back the single copy a removal just took, a song replaces the copy of its tier, and a
-- copy that stacks takes only its own caster's recast.
local function lands_on(row, pending)
    if pending.spell == nil then return pending.renewal == true and single(row.effect); end
    if single(row.effect) then return true; end
    if song(row.effect) then return same_tier(row, pending); end
    return row.spell == pending.spell and row.source == pending.source;
end

-- The server sends an application's 0x028 before the status packets that show it, so a listing shows only
-- those counted before its own 0x063.
local function shown(pending, timer_revision)
    return not finite(pending.timer_revision) or not finite(timer_revision) or timer_revision > pending.timer_revision;
end

-- An application that lands on another listed copy is that copy's, even when it moved the timer too
-- little to see. A row takes the newest that lands on it, else the oldest that is no other listed row's.
-- A new copy with nothing else replaced the listed copy the application lands on, which is leaving, so a
-- created row then takes the oldest owned one. A renewed row with nothing else takes the newest one a
-- copy that did not move seems to own: one copy holds a song's tier, so that copy's labels were the
-- renewed row's, and the copy that holds them is returned to take its old ones. A later cast of a single
-- effect, or of a song of the same tier, replaced the copy in place, so a row takes the latest of those.
local function take_pending(self, row, listed, now, created, timer_revision, moving)
    local list = self.pending[key(row.effect)];
    if not list then return nil; end
    for n = #list, 1, -1 do
        if now - list[n].at > 3 then table.remove(list, n); end
    end
    local pick, own, replaced, still, holder;
    for n, pending in ipairs(list) do
        if shown(pending, timer_revision) then
            if not created and lands_on(row, pending) then own = n; end
            local owner;
            for held in pairs(listed) do
                if held ~= row and key(held.effect) == key(row.effect) and not held.departing and lands_on(held, pending)
                    and (not owner or (held.slot or math.huge) < (owner.slot or math.huge)) then
                    owner = held;
                end
            end
            if not pick and not owner then pick = n; end
            if owner and not replaced then replaced = n; end
            if owner and not created and moving and not moving[owner] and song(row.effect)
                and (pending.source == nil or pending.source ~= self.self_id) then
                still, holder = n, owner;
            end
        end
    end
    if not own and not pick and still then return table.remove(list, still), holder; end
    pick = own or pick or created and replaced;
    if not pick then return nil; end
    local first = list[pick];
    for n = #list, pick + 1, -1 do
        local later = list[n];
        if later.spell ~= nil and shown(later, timer_revision) and (single(row.effect) or song(row.effect) and same_tier(later, first)) then
            pick = n;
            break;
        end
    end
    return table.remove(list, pick);
end

-- A copy first listed alone (its 0x037 before its 0x063) took the application waiting then. A later cast of a
-- single effect, or of a song of that tier, that its first timer's 0x063 shows and that lands on no other listed
-- copy replaced that copy in place, so the copy is the latest of those, as take_pending picks, with settle's
-- guard: a job ability counts only if it started the timer the copy has. The cast it held goes back to wait, in
-- arrival order, for settle to retire.
local function fresh_cast(self, row, held, listed, now, timer_revision)
    local list = self.pending[key(row.effect)];
    if not list then return held; end
    local pick;
    for n, later in ipairs(list) do
        local owned = false;
        for other in pairs(listed) do
            if other ~= row and key(other.effect) == key(row.effect) and not other.departing and lands_on(other, later) then owned = true; end
        end
        if not owned and later ~= held and later.at >= held.at and now - later.at <= 3 and later.spell ~= nil and shown(later, timer_revision)
            and not (later.action_category == 6 and not (finite(row.start) and math.abs(later.at - row.start) <= 2))
            and (single(row.effect) or song(row.effect) and same_tier(later, held)) then
            pick = n;
        end
    end
    if not pick then return held; end
    local cast = table.remove(list, pick);
    local at = #list + 1;
    for m, other in ipairs(list) do if other.at > held.at then at = m; break; end end
    table.insert(list, at, held);
    return cast;
end

local function credit(self, row, pending)
    row.source, row.source_name, row.spell, row.tier = pending.source, pending.source_name, pending.spell, pending.tier;
    row.mine, row.by_pet = pending.source == self.self_id, pending.by_pet;
    row.start = pending.at;
    row.total = row.deadline and math.max(0, row.deadline - row.start) or nil;
end

-- What a row holds for the cast behind its copy.
local CAST = { 'source', 'source_name', 'spell', 'tier', 'mine', 'by_pet', 'start', 'total', 'estimated_until', 'duration_min',
    'instance', 'observed_at' };
local LABELS = { 'source', 'source_name', 'spell', 'tier', 'mine', 'by_pet', 'start', 'total' };

-- Whether copy a ends after copy b; on the same timer, whether it has the later slot.
local function ends_after(a, b)
    local x, y = finite(a.deadline), finite(b.deadline);
    if x ~= y then return x; end
    if x and a.raw_timer ~= nil and b.raw_timer ~= nil and a.raw_timer ~= b.raw_timer then
        return (a.raw_timer - b.raw_timer + 2147483648) % 4294967296 - 2147483648 > 0;
    end
    return (a.slot or -1) > (b.slot or -1);
end

-- The copy an application went to on Phoenix: the one it lands on in place (its own caster's first); else,
-- for a song over its caster's cap, that caster's copy that ends first, the first slot on a tie
-- (ApplyBardEffect); else the copy no application named that ends last, now that it holds the new timer.
local function landed(rows, pending, credited, effect)
    local found;
    for _, row in ipairs(rows) do
        if lands_on(row, pending) and (not found or row.source == pending.source and found.source ~= pending.source) then found = row; end
    end
    if found or not song(effect) then return found; end
    for _, row in ipairs(rows) do
        if not credited[row] and row.spell ~= nil and row.source == pending.source and (not found or ends_after(found, row)) then found = row; end
    end
    if found then return found; end
    for _, row in ipairs(rows) do
        if not credited[row] and row.spell == nil and (not found or ends_after(row, found)) then found = row; end
    end
    return found;
end

-- A complete listing whose timers agree, read after a 0x063 that came after an application, already shows
-- it. One no row took moved its copy too little to see: it recast a copy, or replaced one with no message.
-- Newest first, so a copy keeps the last cast on it; an older one whose copy a later cast took was
-- overwritten, as was one with no copy left. A recast by the copy's own caster is no new instance. Any
-- left waiting could go to a later row.
local function settle(self, entity, listed, credited, now, revision)
    for effect, list in pairs(self.pending) do
        local rows;
        for n = #list, 1, -1 do
            local pending = list[n];
            if pending.spell ~= nil and finite(pending.timer_revision) and revision > pending.timer_revision
                and now - pending.at <= 3 then
                if not rows then
                    rows = {};
                    for _, row in ipairs(entity.entries) do
                        if key(row.effect) == effect and listed[row] and row.present and not row.departing then rows[#rows + 1] = row; end
                    end
                end
                if #rows == 0 then break; end
                local target = landed(rows, pending, credited, effect);
                if target and credited[target] then
                    target = nil;
                elseif target and (target.spell ~= pending.spell or target.source ~= pending.source) then
                    -- A job ability is reported to every target even when a stronger copy refuses it
                    -- (CanGainStatusEffect). One that took restarted the timer, so a copy that didn't move took it
                    -- only if that copy started with it.
                    if pending.action_category == 6 and not (finite(target.start) and math.abs(pending.at - target.start) <= 2) then
                        target = nil;
                    else
                        target.instance = target.instance + 1;
                        target.observed_at = now;
                        credit(self, target, pending);
                        if entity.baseline then self:queue('refresh', target, now); end
                    end
                end
                -- The copy it went to is a new one, so its timer may read either value beside the one shown.
                if target then credited[target], target.raw_other = true, nil; end
                table.remove(list, n);
            end
        end
        if #list == 0 then self.pending[effect] = nil; end
    end
end

local function signed(value) return (value + 2147483648) % 4294967296 - 2147483648; end

-- The server rebuilds each 0x063 timer from two truncated clocks, so an untouched effect reads one of two
-- values 60 apart (0x063_miscdata_status_icons.cpp).
local function same_deadline(row, incoming, exact)
    local a, b = row.raw_timer, incoming.raw_timer;
    if a ~= nil and b ~= nil then
        return a == b or not exact and finite(a) and finite(b) and math.abs(signed(a - b)) <= 60;
    end
    if finite(row.deadline) and finite(incoming.deadline) then
        return math.abs(row.deadline - incoming.deadline) <= 1.5;
    end
    return row.deadline == nil and incoming.deadline == nil;
end

-- A timer showing up for a row that never had one is not a new application. Phoenix's raw timers are 60
-- to a second and move an untouched copy by 60 at most, so a bigger move of whole seconds is a new timer,
-- whatever the deadlines read: the client works them out from whole seconds, so the same timer can read a
-- second apart. A move of part of a second is no Phoenix restamp; the deadlines decide it.
local function renewed(row, incoming)
    if row.raw_timer == nil or same_deadline(row, incoming) or not finite(incoming.deadline) then return false; end
    if finite(row.raw_timer) and finite(incoming.raw_timer) and signed(incoming.raw_timer - row.raw_timer) % 60 == 0 then return true; end
    return not finite(row.deadline) or math.abs(incoming.deadline - row.deadline) > 1.5;
end

-- A row whose removal was seen can't take a new timer, unless that removal came with another caster's
-- recast of a spell that always overwrites.
local function stuck(row, renewal) return row.departing and renewal and not (row.recast and row.recast.other); end

local function listed(snapshot, row, taken)
    for n, status in ipairs(snapshot.self_effects or {}) do
        if type(status) == 'table' and key(status.effect) == key(row.effect) and not taken[n] and not renewed(row, status) then
            taken[n] = true;
            return true;
        end
    end
    return false;
end

-- How many copies of that effect the player's listing holds.
local function copies(snapshot, effect)
    local count = 0;
    for _, status in ipairs(snapshot.self_effects or {}) do
        if type(status) == 'table' and key(status.effect) == key(effect) then count = count + 1; end
    end
    return count;
end

-- Phoenix only marks the copy the player's own action replaces deleted (OverwriteStatusEffect,
-- ApplyBardEffect) and erases it at the next CheckEffectsExpiry, so that action's PostTick still lists it.
-- The new copy comes right after it (statusOrdering keeps equal keys in insertion order), or, for a song
-- over the player's cap, beside the player's song whose slot it took. Other casters' copies are erased
-- before the player's status packets. So a complete listing can hold one copy more than the server keeps:
-- the copy a row reads that the player's cast lands on; one no listing showed, made by an earlier cast of
-- that tier; or, with nothing waiting, the old copy of an effect with one copy that the player's action
-- renewed with no message (each Phantom Roll re-adds Double-Up Chance). Returns, by position in the
-- listing, those old copies with the labels they show, the new copies with the row that moves to each and
-- the cast it takes, and the rows these take.
local EMPTY = {};
local function arrival(a, b)
    if a.cast.at ~= b.cast.at then return a.cast.at < b.cast.at; end
    return a.order < b.order;
end
-- The player's cast, or the 205 of an item they used that put an effect back, if this listing is its tick's:
-- the first 0x063 after its 0x028 or 205 is that PostTick's, and the next tick has dropped the old copy.
local function current(self, cast, timer_revision)
    return (cast.spell ~= nil or cast.renewal) and cast.source ~= nil and cast.source == self.self_id
        and (not finite(cast.timer_revision) or not finite(timer_revision) or timer_revision == cast.timer_revision + 1);
end
local function replaced(self, entity, incoming, counts, now, timer_revision)
    local ghost, pin, kept;
    local function mine(cast) return current(self, cast, timer_revision); end
    for effect, count in pairs(counts) do
        -- Only the player's cast, or for an effect with one copy nothing at all, waiting makes a pair. Songs
        -- have a copy a tier, so more than eight copies is no listing Phoenix sends.
        local own, any = false, false;
        if count > 1 and count <= 8 and (single(effect) or song(effect)) then
            for _, pending in ipairs(self.pending[effect] or EMPTY) do
                if now - pending.at <= 3 and shown(pending, timer_revision) then any, own = true, own or mine(pending); end
            end
            for _, row in ipairs(entity.entries) do
                local held = key(row.effect) == effect and row.fresh and row.fresh_pending;
                if held and now - held.at <= 3 then any, own = true, own or mine(held); end
            end
        end
        if own or count > 1 and count <= 8 and not any and single(effect) then
            local rows, fresh, waiting = {}, {}, {};
            for _, row in ipairs(entity.entries) do
                if key(row.effect) == effect then
                    if row.fresh then fresh[#fresh + 1] = row; else rows[#rows + 1] = row; end
                end
            end
            -- A copy only a 0x037 listed holds the application it took; it came in before the ones still waiting.
            for n, row in ipairs(fresh) do
                local held = row.fresh_pending;
                if held and now - held.at <= 3 then waiting[#waiting + 1] = { cast = held, holder = row, order = n - #fresh - 1 }; end
            end
            for n, pending in ipairs(self.pending[effect] or EMPTY) do
                if now - pending.at <= 3 and shown(pending, timer_revision) then waiting[#waiting + 1] = { cast = pending, order = n }; end
            end
            if #waiting > 1 then table.sort(waiting, arrival); end
            own = nil;
            for i, item in ipairs(waiting) do if mine(item.cast) then own = i; end end
            local at = {};
            for n, status in ipairs(incoming) do if key(status.effect) == effect then at[#at + 1] = n; end end
            local function reads(row, n) return row.raw_timer ~= nil and same_deadline(row, incoming[n]); end
            local function movable(row) return not row.departing or row.recast ~= nil; end
            -- Whether no row other than except reads copy n. With loose, a row that does read it is let through if it
            -- also reads a copy other than n and old, or a waiting cast lands on it.
            local function free(n, except, loose, old)
                for _, row in ipairs(rows) do
                    if row ~= except and reads(row, n) then
                        if not loose then return false; end
                        local elsewhere = false;
                        for i, item in ipairs(waiting) do
                            if i ~= own and lands_on(row, item.cast) then elsewhere = true; end
                        end
                        for _, m in ipairs(at) do
                            if m ~= n and m ~= old and reads(row, m) then elsewhere = true; end
                        end
                        if not elsewhere then return false; end
                    end
                end
                return true;
            end
            -- An effect with one copy has no other copy to lose that tick, so each other row still reads one.
            local function placed(except, k)
                for _, row in ipairs(single(effect) and rows or EMPTY) do
                    if row ~= except and not row.departing then
                        local holds = false;
                        for _, m in ipairs(at) do if m ~= k and m ~= k + 1 and reads(row, m) then holds = true; end end
                        if not holds then return false; end
                    end
                end
                return true;
            end
            local found;
            -- Copies keep their slots, so as many copies of the effect are listed before row's old copy as there
            -- are rows before it in slot order that hold one.
            local function ordered(row, k)
                local before, ahead = 0, 0;
                for _, m in ipairs(at) do if m < k then before = before + 1; end end
                for _, other in ipairs(rows) do
                    if other ~= row and (other.slot or math.huge) < (row.slot or math.huge) then
                        local holds = not other.departing;
                        for _, m in ipairs(holds and EMPTY or at) do if reads(other, m) then holds = true; end end
                        if holds then ahead = ahead + 1; end
                    end
                end
                return before == ahead;
            end
            -- The old copy first, the new one next: one no other row reads, else, for a cast, one read by a row
            -- with a copy left. With in_order set, only a pair that keeps the rows' order.
            local function in_place(cast, in_order)
                for _, loose in ipairs(cast and { false, true } or { false }) do
                    for j = 1, found and 0 or #at - 1 do
                        local k = at[j];
                        for _, row in ipairs(at[j + 1] == k + 1 and rows or EMPTY) do
                            if not found and movable(row) and (cast == nil or lands_on(row, cast)) and reads(row, k)
                                and free(k + 1, row, loose, k) and placed(row, k)
                                and (not in_order or ordered(row, k)) then
                                found = { old = k, new = k + 1, row = row };
                            end
                        end
                    end
                end
            end
            if own then
                local cast = waiting[own].cast;
                -- Over the player's cap the new song takes the slot of the player's song that ends first (the old copy
                -- of its tier counts if it was the player's) and is listed beside it, by status ID in that slot (after
                -- it on the same ID); the old copy of its tier is listed where it was. That needs two songs of the
                -- player's own up, the cap a bard with an instrument has. First, since a new copy that reads like the
                -- old one also reads as a pair in place.
                local up, first = 0, nil;
                for _, other in ipairs(song(effect) and entity.entries or EMPTY) do
                    if song(other.effect) and other.source ~= nil and other.source == self.self_id and not other.departing
                        and not other.fresh then
                        up = up + 1;
                        if not first or ends_after(first, other) then first = other; end
                    end
                end
                local function beside(m, row)
                    for side = m - 1, m + 1, 2 do
                        local status = incoming[side];
                        if first and first ~= row and status and first.effect == status.effect and reads(first, side)
                            and (side < m and status.effect <= effect or side > m and status.effect > effect) then return true; end
                    end
                    return false;
                end
                for _, row in ipairs(song(effect) and rows or EMPTY) do
                    for _, m in ipairs(not found and movable(row) and lands_on(row, cast) and at or EMPTY) do
                        if not found and up >= 2 and free(m, row, true) and beside(m, row) then
                            -- Of copies that read alike, the rows that read them keep their order.
                            local seen, rank, counted = {}, 1, {};
                            for _, n in ipairs(at) do
                                if n ~= m and reads(row, n) then
                                    seen[#seen + 1] = n;
                                    for _, other in ipairs(rows) do
                                        if other ~= row and not counted[other] and not other.departing and reads(other, n)
                                            and (other.slot or -1) < (row.slot or -1) then counted[other], rank = true, rank + 1; end
                                    end
                                end
                            end
                            if #seen > 0 then found = { old = seen[math.min(rank, #seen)], new = m, row = row }; end
                        end
                    end
                end
                if not found then in_place(cast, true); end
                if not found then in_place(cast, false); end
                -- Two copies no row reads: the first was another cast's of that tier, which the player's replaced; a
                -- later one would come behind this listing's 0x063. The copy the player's cast lands on is that one
                -- if no listed copy reads like it.
                local label, row;
                for i = found and 0 or #waiting, 1, -1 do
                    if not label and i ~= own and (single(effect) or same_tier(waiting[i].cast, cast)) then label = i; end
                end
                for _, held in ipairs(label and rows or EMPTY) do
                    if not row and movable(held) and lands_on(held, cast) then
                        local seen = false;
                        for _, m in ipairs(at) do if reads(held, m) then seen = true; end end
                        if not seen then row = held; end
                    end
                end
                for j = 1, label and #at - 1 or 0 do
                    local k = at[j];
                    if (not found or not found.ordered) and at[j + 1] == k + 1 and free(k, nil, true) and free(k + 1, nil, true)
                        and placed(row, k) then
                        local order = row == nil or ordered(row, k);
                        if not found or order then found = { old = k, new = k + 1, row = row, label = label, ordered = order }; end
                    end
                end
                -- Over the cap the new song sits beside the player's song that ends first, and the old copy
                -- of its tier stays where it was, wherever that is.
                for _, m in ipairs(not found and label and up >= 2 and at or EMPTY) do
                    for _, k in ipairs(not found and free(m, nil, true) and beside(m, row) and at or EMPTY) do
                        if not found and k ~= m and free(k, nil, true) then found = { old = k, new = m, row = row, label = label }; end
                    end
                end
            else
                -- With nothing waiting, the player's own action renewed it with no message.
                in_place(nil, true);
                if not found then in_place(nil, false); end
            end
            if found then
                ghost, pin, kept = ghost or {}, pin or {}, kept or {};
                local function take(item)
                    if item.holder then item.holder.fresh_pending = nil; return; end
                    local list = self.pending[effect];
                    for n = #list, 1, -1 do if list[n] == item.cast then table.remove(list, n); end end
                end
                if found.old then
                    local labels = { first_seen = now };
                    if found.label then
                        local cast = waiting[found.label].cast;
                        labels.source, labels.source_name, labels.spell, labels.tier = cast.source, cast.source_name, cast.spell, cast.tier;
                        labels.mine, labels.by_pet, labels.start, labels.instance, labels.observed_at = cast.source == self.self_id, cast.by_pet, cast.at, 1, now;
                    elseif found.row then
                        for _, key in ipairs(CAST) do labels[key] = found.row[key]; end
                        labels.first_seen, labels.first_sequence = found.row.first_seen, found.row.first_sequence;
                    end
                    -- A copy only a 0x037 listed was the old one, unless it holds the new copy's cast.
                    local holder;
                    for pass = 1, 2 do
                        for _, row in ipairs(fresh) do
                            local holds = row.fresh_pending;
                            if not holder and (pass == 2 or found.label and holds == waiting[found.label].cast)
                                and (found.row or not own or holds ~= waiting[own].cast) then holder = row; end
                        end
                    end
                    if holder then kept[holder] = true; end
                    ghost[found.old] = { row = holder, labels = labels };
                end
                if found.row then
                    pin[found.new], kept[found.row] = { row = found.row, cast = own and waiting[own].cast }, true;
                    if own then take(waiting[own]); end
                end
                if found.label then take(waiting[found.label]); end
            end
        end
    end
    return ghost, pin, kept;
end

-- Rows taken as a set of bits: a row's bit, whether a set holds the row, 512 for each row in the set after
-- it, and how many rows the set holds. Same-ID pairing takes six copies at most. LEAST is assign's
-- working table, kept to save building one every refresh; it only reads what it wrote that call.
local BIT, HAS, AFTER, SIZE, LEAST = {}, {}, {}, {}, {};
for r = 1, 6 do BIT[r] = 2 ^ (r - 1); end
for set = 0, 63 do
    SIZE[set] = 0;
    for r = 1, 6 do
        local after = 0;
        for q = r + 1, 6 do if set % (2 * BIT[q]) >= BIT[q] then after = after + 512; end end
        HAS[set * 8 + r], AFTER[set * 8 + r] = set % (2 * BIT[r]) >= BIT[r], after;
        if HAS[set * 8 + r] then SIZE[set] = SIZE[set] + 1; end
    end
end
for key = 0, 7 * 64 + 63 do LEAST[key] = 0; end

-- Same-ID instances (two songs) keep their order in the server's list, and two timers 60 apart can trade
-- places in a restamp. Pair as many as can be with the fewest renewals and departing rows kept, then in
-- that order; a timer one of the two values a row reads, then an exact one, only settles what is left. Of
-- equal pairings the first in slot order wins. A song's cast lands on the copy of its tier, so of two
-- renewals the one an application lands on is the copy renewed; and a caster's new song over their cap
-- drops their song that ends first, so of copies that read alike one of theirs is the one gone. Songs keep
-- their slots, so a copy also keeps its order against the other songs. explains says whether an
-- application lands on a row, capped whether its caster has a new song waiting, crossing how many other
-- songs a row would trade places with on a slot.
local function assign(entries, incoming, rows, statuses, used, matches, explains, capped, crossing)
    local function by_slot(list, at)
        table.sort(list, function(a, b)
            local x, y = at(a).slot or math.huge, at(b).slot or math.huge;
            if x ~= y then return x < y; end
            return a < b;
        end);
    end
    by_slot(rows, function(i) return entries[i]; end);
    by_slot(statuses, function(n) return incoming[n]; end);
    -- A cost: unpaired slots, rows a 0x037 alone listed kept, renewals, renewals no application explains,
    -- departing rows kept, places traded with other songs (seven a row at most), order changes, rows a cap
    -- may have dropped kept, timers neither of the two a row has read, raw timers that differ. Six copies
    -- make at most 15 order changes and six of anything else, and each count sits in its own digits, so
    -- comparing costs compares those counts in turn. A row only a 0x037 without its 0x063 has listed may be
    -- the old copy of a stray listing; one with a timer is kept before it.
    local ns, nr, adds = #statuses, #rows, {};
    for s = 1, ns do
        local status = incoming[statuses[s]];
        adds[s] = {};
        for r = 1, nr do
            local row = entries[rows[r]];
            local renewal, raw = renewed(row, status), status.raw_timer;
            adds[s][r] = not stuck(row, renewal) and (row.fresh and 268435456 or 0)
                + (renewal and 33554432 + (explains(row) and 0 or 4194304) or 0) + (row.departing and 524288 or 0)
                + math.min(7, crossing(row, status)) * 8192 + (capped(row) and 64 or 0)
                + ((row.raw_other ~= nil and raw ~= row.raw_timer and raw ~= row.raw_other) and 8 or 0)
                + ((row.raw_timer == nil or row.raw_timer ~= raw) and 1 or 0);
        end
    end
    -- The least the slots from s on can cost given the rows earlier slots took, in six by 64 by six steps at
    -- most. Earlier slots took fewer than s rows. Taking a row before one an earlier slot took is an order
    -- change.
    local last, least = 2 ^ nr - 1, LEAST;
    for set = 0, last do least[(ns + 1) * 64 + set] = 0; end
    for s = ns, 1, -1 do
        local add_s, here, after = adds[s], s * 64, (s + 1) * 64;
        for set = 0, last do
            if SIZE[set] < s then
                local best, at = 2147483648 + least[after + set], set * 8;
                for r = 1, nr do
                    local add = add_s[r];
                    if add and not HAS[at + r] then
                        add = add + AFTER[at + r] + least[after + set + BIT[r]];
                        if add < best then best = add; end
                    end
                end
                least[here + set] = best;
            end
        end
    end
    -- Follow the cheapest pairing, each slot taking the first row in slot order that keeps it.
    local set = 0;
    for s = 1, ns do
        for r = 1, nr do
            local add = adds[s][r];
            if add and not HAS[set * 8 + r]
                and add + AFTER[set * 8 + r] + least[(s + 1) * 64 + set + BIT[r]] == least[s * 64 + set] then
                used[rows[r]], matches[statuses[s]] = true, entries[rows[r]];
                set = set + BIT[r];
                break;
            end
        end
    end
end

-- Copy Image's icon moves with its shadows. A listed icon of it that no row has takes the row whose icon the
-- listing lost, when that row reads the same timer, or with no timer listed (a split send) is the only one.
local function relabel_icons(entity, incoming, ghost, pin, kept, timed)
    local status, row;
    for n, listed in ipairs(incoming) do
        if COPY_IMAGE[listed.effect] and not ghost[n] and not pin[n] then
            if status then return; end
            status = listed;
        end
    end
    if not status then return; end
    for _, held in ipairs(entity.entries) do
        if COPY_IMAGE[held.effect] and not kept[held] and not held.departing then
            if row then return; end
            row = held;
        end
    end
    if not row or row.effect == status.effect or timed and status.raw_timer ~= nil and not same_deadline(row, status) then return; end
    relabel(row, status.effect);
end

-- Which copies of a party member's effect left, when their listing holds fewer than their rows and nothing
-- said which: after a singer's new song, that singer's song from before it that ends first (Phoenix drops
-- it over their cap, ApplyBardEffect); or the copies whose estimated time is up. A singer's cap depends on
-- their instrument, so any recent singer may have dropped one. nil unless every way it could have gone
-- names the same copies.
local function decided(entity, effect, drop, now)
    -- An effect with one copy keeps the row its latest application landed on: a labelled row over a copy only a
    -- listing made, then the newest. The rest left, however a stale listing put them there.
    if single(effect) then
        local keep, best;
        for _, row in ipairs(entity.entries) do
            if row.effect == effect and not row.departing then
                local labelled, at = row.source ~= nil or row.spell ~= nil, row.start or row.first_seen or 0;
                if not keep or labelled and not best.labelled or labelled == best.labelled and at > best.at then
                    keep, best = row, { labelled = labelled, at = at };
                end
            end
        end
        local gone, count = {}, 0;
        for _, row in ipairs(entity.entries) do
            if row.effect == effect and not row.departing and row ~= keep then gone[row], count = true, count + 1; end
        end
        if count == drop then return gone; end
    end
    local found;
    for source, sung in pairs(drop == 1 and song(effect) and entity.sung or EMPTY) do
        if now - sung.at <= 3 then
            local first;
            for _, row in ipairs(entity.entries) do
                if song(row.effect) and row.source == source and row ~= sung.row and not row.departing
                    and (row.start or row.first_seen) < sung.at and finite(row.estimated_until)
                    and (not first or row.estimated_until < first.estimated_until) then first = row; end
            end
            if first and first.effect == effect then
                if found and not found[first] then return nil; end
                found = { [first] = true };
            end
        end
    end
    local due, count = {}, 0;
    for _, row in ipairs(entity.entries) do
        if row.effect == effect and not row.departing and finite(row.estimated_until) and row.estimated_until <= now + 1.5 then
            due[row], count = true, count + 1;
        end
    end
    if count ~= drop then return found; end
    for row in pairs(found or EMPTY) do if not due[row] then return nil; end end
    return due;
end

-- The copy a song whose gain waits (held_gain) may have replaced: one of the copies of its effect no 0x028
-- labelled when it came, all alike, and the song's row.
local function blind_copy(entity, effect)
    for _, row in ipairs(entity.entries) do
        local held = row.held_gain;
        if held and row.effect == effect then
            for _, copy in ipairs(entity.entries) do
                if held.keys[copy.key] and not copy.departing then return copy, row; end
            end
        end
    end
end

-- A party member whose effects come from a listing (alliance members have none).
local function member(snapshot, id)
    for _, held in ipairs(snapshot and snapshot.party or EMPTY) do if held.id == id then return held.valid == true; end end
    return false;
end

-- A new application waits for a listing that came after it: one stamped no later than the application can be
-- the member's icons from before the cast.
local function awaiting_presence(row, entity, now, revision)
    local stamp = row.application_revision;
    return not row.present and finite(stamp)
        and (not revision or revision <= stamp) and (revision ~= nil or now - row.observed_at <= 3);
end

function methods:snapshot(entity, effects, now, timed, revision, complete, timers_pending, timer_revision)
    complete = complete ~= false;
    -- The player's listing changed with no status packet since the last one, its icons no longer matching: the client
    -- cleared an entry itself, as a Confirm on its + menu does.
    local cleared = timed and timers_pending and revision ~= nil and revision == entity.revision;
    local used, matches, incoming, counts, ambiguous, solved, unsettled = {}, {}, {}, {}, {}, {}, {};
    local stale_presence = entity.pending_presence == true
        and (revision == nil or finite(entity.pending_revision) and revision <= entity.pending_revision);
    if not stale_presence then entity.pending_presence, entity.pending_revision = nil, nil; end
    local twice, keyed = false, {};
    for _, status in ipairs(effects or {}) do
        if type(status) == 'table' and effect_id(status.effect) and #incoming < 32 then
            incoming[#incoming + 1] = status;
            counts[status.effect] = (counts[status.effect] or 0) + 1;
            local id = key(status.effect);
            keyed[id] = (keyed[id] or 0) + 1;
            twice = twice or keyed[id] > 1;
        end
    end
    -- Copies the player's own action replaced, listed once more, and the new copies their rows move to,
    -- are placed before the rest is paired.
    local ghost, pin, kept = EMPTY, EMPTY, EMPTY;
    if timed and complete and not timers_pending then
        -- The listing of the player's own recast's tick never came whole: the next tick dropped the old copy,
        -- so this one lists the new copy alone, as for another caster's.
        for _, row in ipairs(finite(timer_revision) and entity.entries or EMPTY) do
            local held = row.recast;
            if held and not held.other and finite(held.stamp) and timer_revision > held.stamp + 1 then
                row.recast = { reason = held.reason, other = true, stamp = held.stamp };
            end
            -- A 0x063 came before the 205 a removal waited for. Listing the copy beside a new one, it was put back
            -- with no 205, and the pair below is that renewal; else nothing put it back.
            if held and held.waiting and timer_revision > held.stamp then
                if timer_revision == held.stamp + 1 and keyed[key(row.effect)] and keyed[key(row.effect)] > 1 then
                    row.recast = { reason = held.reason, other = true, stamp = held.stamp };
                else
                    row.recast = nil;
                    if entity.baseline then self:queue('removed', row, now, held.reason); end
                end
            end
        end
        local old, new, taken;
        if twice then old, new, taken = replaced(self, entity, incoming, keyed, now, timer_revision); end
        if old then
            ghost, pin, kept = old, new, taken;
            for n, status in ipairs(incoming) do
                if ghost[n] or pin[n] then counts[status.effect] = counts[status.effect] > 1 and counts[status.effect] - 1 or nil; end
                if pin[n] then matches[n] = pin[n].row; end
            end
            for i, row in ipairs(entity.entries) do if kept[row] then used[i] = true; end end
        end
    end
    relabel_icons(entity, incoming, ghost, pin, kept, timed);
    local dropped, spare, merged, waiting = {}, {}, {}, {};
    if not timed then
        -- A copy whose removal was seen is the one a listing lacks.
        local held = {};
        for _, row in ipairs(entity.entries) do
            if not row.departing then held[row.effect] = (held[row.effect] or 0) + 1; end
            waiting[row.effect] = waiting[row.effect] or awaiting_presence(row, entity, now, revision);
            -- The listings after an application that landed on a copy can still list the copy it replaced, from
            -- the member's cache before their next tick: Phoenix sends one 0x076 per member PostTick in between.
            if row.landed_at ~= nil and revision ~= row.landed_at then
                spare[key(row.effect)] = (spare[key(row.effect)] or 0) + 1;
            end
        end
        for effect, count in pairs(held) do
            if count > 1 and counts[effect] and counts[effect] < count and not waiting[effect] then
                local gone = decided(entity, effect, count - counts[effect], now);
                -- A waiting song that left the count as it was replaced the copy of its tier, which only one of
                -- the copies nobody labelled can be. That copy goes quietly and the song's row is its renewal.
                local copy, by;
                if count - counts[effect] == 1 then copy, by = blind_copy(entity, effect); end
                if copy and by.held_gain.listed then
                    -- A second copy only a listing showed, gone again: it goes quietly and the row beside it stays as
                    -- it was. Nothing the party sees says who renewed it, or for how long.
                    gone, merged[by] = { [by] = true }, copy;
                elseif copy then
                    if not gone then gone, merged[copy] = { [copy] = true }, by;
                    elseif not gone[copy] then gone = nil; end
                end
                if gone then for row in pairs(gone) do dropped[row] = true; end
                else ambiguous[effect] = true; end
            end
        end
    end
    local first, tail, following = {}, {}, {};
    for i, row in ipairs(entity.entries) do
        if not kept[row] then
            if tail[row.effect] then following[tail[row.effect]] = i;
            else first[row.effect] = i; end
            tail[row.effect] = i;
        end
    end
    if timed then
        local held = {};
        for _, row in ipairs(entity.entries) do if not kept[row] then held[row.effect] = (held[row.effect] or 0) + 1; end end
        -- An application a copy listed only by a 0x037 holds is still waiting to be placed.
        local function explains(row)
            for _, pending in ipairs(self.pending[key(row.effect)] or {}) do
                if now - pending.at <= 3 and shown(pending, timer_revision) and lands_on(row, pending) then return true; end
            end
            for _, other in ipairs(entity.entries) do
                local pending = other ~= row and key(other.effect) == key(row.effect) and other.fresh and other.fresh_pending;
                if pending and lands_on(row, pending) then return true; end
            end
            return false;
        end
        local function capped(row)
            if not song(row.effect) or row.source == nil then return false; end
            for effect, list in pairs(self.pending) do
                if song(effect) then
                    for _, pending in ipairs(list) do
                        if pending.source == row.source and not (effect == row.effect and same_tier(row, pending))
                            and now - pending.at <= 3 and shown(pending, timer_revision) then return true; end
                    end
                end
            end
            return false;
        end
        -- Single copies first, then same-ID copies once without and once with the order the other songs
        -- keep, taken from the first try.
        local anchors, groups = {}, {};
        for n, status in ipairs(incoming) do
            local effect, i = status.effect, not ghost[n] and not pin[n] and first[status.effect];
            if i and not solved[effect] and held[effect] <= 6 and counts[effect] <= 6 then
                solved[effect] = true;
                if held[effect] == 1 and counts[effect] == 1 then
                    local row = entity.entries[i];
                    if not stuck(row, renewed(row, status)) then
                        used[i], matches[n] = true, row;
                        if song(effect) and row.slot then anchors[#anchors + 1] = { row.slot, status.slot, effect }; end
                    end
                else
                    local rows, statuses = {}, {};
                    while i do rows[#rows + 1] = i; i = following[i]; end
                    for m = n, #incoming do
                        if incoming[m].effect == effect and not ghost[m] and not pin[m] then statuses[#statuses + 1] = m; end
                    end
                    groups[#groups + 1] = { rows, statuses, effect };
                end
            end
        end
        local trial, ignore, songs = {}, {}, 0;
        local function none() return 0; end
        for _, group in ipairs(groups) do if song(group[3]) then songs = songs + 1; end end
        for _, group in ipairs(songs > 1 and groups or {}) do
            if song(group[3]) then
                local rows, statuses = {}, {};
                for k, v in ipairs(group[1]) do rows[k] = v; end
                for k, v in ipairs(group[2]) do statuses[k] = v; end
                assign(entity.entries, incoming, rows, statuses, ignore, trial, explains, capped, none);
            end
        end
        for n, row in pairs(trial) do
            if song(row.effect) and row.slot then anchors[#anchors + 1] = { row.slot, incoming[n].slot, row.effect }; end
        end
        -- A copy only a 0x037 listed has its place from a listing that may hold copies already gone.
        local function crossing(row, status)
            if not song(row.effect) or row.fresh or not row.slot or not status.slot then return 0; end
            local flips = 0;
            for _, anchor in ipairs(anchors) do
                if anchor[3] ~= row.effect and (row.slot < anchor[1]) ~= (status.slot < anchor[2]) then flips = flips + 1; end
            end
            return flips;
        end
        for _, group in ipairs(groups) do
            assign(entity.entries, incoming, group[1], group[2], used, matches, explains, capped, crossing);
        end
    end
    -- A party row whose removal was seen stays listed only by a newer listing, or for a moment by the one from
    -- before the removal, read again until the next one comes.
    local function stale(row)
        return not timed and row.departing and revision ~= nil and revision == row.departing_revision and now - row.departing_at > 3;
    end
    -- Party rows and larger groups: match unchanged deadlines before slot order or refreshes, exact timers first,
    -- and rows whose removal was seen last.
    for pass = 1, 2 do
        for n, status in ipairs(incoming) do
            local i = not matches[n] and not ghost[n] and not solved[status.effect] and first[status.effect];
            while i do
                local row = entity.entries[i];
                if not ambiguous[row.effect] and not used[i] and not dropped[row]
                    and (timed and same_deadline(row, status, pass == 1) or not timed and (pass == 2 or not row.departing) and not stale(row)) then
                    used[i], matches[n] = true, row;
                    break;
                end
                i = following[i];
            end
        end
    end
    for n, status in ipairs(incoming) do
        if not matches[n] and not ghost[n] and not solved[status.effect] then
            local candidate;
            local i = first[status.effect];
            while i do
                local row = entity.entries[i];
                if not ambiguous[row.effect] and not used[i] and not dropped[row] and not stuck(row, renewed(row, status)) and not stale(row) then
                    candidate = candidate or i;
                    if row.slot == status.slot then candidate = i; break; end
                end
                i = following[i];
            end
            if candidate then used[candidate], matches[n] = true, entity.entries[candidate]; end
        end
    end
    for i = #entity.entries, 1, -1 do
        local row = entity.entries[i];
        local waiting = not timed and awaiting_presence(row, entity, now, revision) and not ambiguous[row.effect];
        if waiting and not used[i] then stale_presence = true; end
        if not used[i] and not waiting then
            if complete and timers_pending and timed and counts[row.effect] and not row.departing then
                -- Without timers the 0x037 can't say which same-ID instance went; its 0x063 decides.
                row.present = false;
                unsettled[row.effect] = true;
            elseif complete and cleared and not row.departing and not row.fresh then
                -- The server's removal follows, and a status packet it sent before can still list the copy, so the
                -- row stays out of sight, leaving, until a newer listing drops it.
                if entity.baseline then self:queue('removed', row, now, 'The status is no longer present.'); end
                row.present, row.departing, row.departing_at, row.departing_revision = false, true, now, revision;
            elseif complete then
                -- A copy only a 0x037 listed was the old one; the row its copy went to takes its application.
                local held = row.fresh and row.fresh_pending;
                if held and now - held.at <= 3 then
                    local list = self.pending[key(row.effect)] or {};
                    self.pending[key(row.effect)] = list;
                    local at = #list + 1;
                    for m, other in ipairs(list) do if other.at > held.at then at = m; break; end end
                    table.insert(list, at, held);
                end
                if row.recast and entity.baseline then self:queue('removed', row, now, row.recast.reason); end
                -- A copy a 205 replaced goes quietly, with no message, a tick after it.
                local over = row.overwritten;
                self:erase(entity, i, now, 'The status is no longer present.',
                    not entity.baseline or ambiguous[row.effect] or row.departing or row.fresh or merged[row] ~= nil
                    or over ~= nil and now - over.at <= 3);
            else
                row.unavailable_at = row.unavailable_at or now;
                row.present, row.deadline, row.status = nil, nil, 'unknown';
                row.reason = 'This status was not readable in the incomplete snapshot.';
            end
        end
    end
    local listed, credited, queued, moving = {}, {}, {}, {};
    for n, row in pairs(matches) do
        listed[row] = true;
        if timed and not row.fresh and renewed(row, incoming[n]) then moving[row] = true; end
        -- A later listing that still has it says no 205 replaced it.
        local over = row.overwritten;
        if over and not timers_pending and finite(timer_revision) and timer_revision > over.count then row.overwritten = nil; end
    end
    for n, status in ipairs(incoming) do
        local suppressed = false;
        for i = #entity.tombstones, 1, -1 do
            local gone = entity.tombstones[i];
            if (gone.revision == nil and now - gone.at > 5) or (revision and gone.revision and revision > gone.revision) then
                table.remove(entity.tombstones, i);
            elseif key(gone.effect) == key(status.effect) and (gone.raw_timer == nil or gone.raw_timer == status.raw_timer) then
                suppressed = not ghost[n] and not pin[n];
            end
        end
        -- The copy an application replaced, listed once more: no row of its own.
        if not suppressed and not timed and not matches[n] and (spare[key(status.effect)] or 0) > 0 then
            spare[key(status.effect)], suppressed = spare[key(status.effect)] - 1, true;
        end
        if not suppressed and ghost[n] then
            -- The copy the player's action replaced: it shows the cast it had and leaves at the next tick
            -- with no message. It is back, quietly, if a later 0x063 still lists it.
            local labels = ghost[n].labels;
            local row = ghost[n].row or self:create(entity, status.effect, now);
            for _, key in ipairs(CAST) do row[key] = labels[key]; end
            row.first_seen, row.first_sequence = labels.first_seen or row.first_seen, labels.first_sequence or row.first_sequence;
            row.fresh, row.fresh_pending, row.raw_other, row.recast = nil, nil, nil, nil;
            row.slot, row.present, row.unavailable_at = status.slot, true, nil;
            row.scope, row.entity_name = entity.scope, entity.name;
            row.raw_timer, row.deadline = status.raw_timer, finite(status.deadline) and status.deadline or nil;
            row.status = row.deadline and 'server' or 'unknown';
            row.reason = row.status == 'server' and 'The server supplied this timer.'
                or 'The status is present, but no current timer is available.';
            row.total = row.start and row.deadline and math.max(0, row.deadline - row.start) or nil;
            row.departing, row.departing_at, row.departing_revision = true, now, revision;
            row.superseded = finite(timer_revision) and timer_revision or -1;
            listed[row] = true;
        elseif not suppressed and pin[n] then
            -- The new copy the player's action made: the row moves to it with that cast, one refresh. An action
            -- with no message renewed it with a cast nobody named.
            local row, cast = pin[n].row, pin[n].cast;
            relabel(row, status.effect);
            row.departing, row.departing_at, row.departing_revision, row.recast, row.superseded = nil, nil, nil, nil, nil;
            row.slot, row.present, row.unavailable_at = status.slot, true, nil;
            row.scope, row.entity_name = entity.scope, entity.name;
            row.raw_timer, row.raw_other = status.raw_timer, nil;
            row.deadline = finite(status.deadline) and status.deadline or nil;
            row.status = row.deadline and 'server' or 'unknown';
            row.reason = row.status == 'server' and 'The server supplied this timer.'
                or 'The status is present, but no current timer is available.';
            row.instance, row.observed_at, row.estimated_until, row.duration_min = row.instance + 1, now, nil, nil;
            if cast then credit(self, row, cast);
            else row.source, row.source_name, row.spell, row.tier, row.mine, row.by_pet, row.start, row.total = nil, nil, nil, nil, nil, nil, nil, nil; end
            if entity.baseline then queued[#queued + 1] = { 'refresh', row }; end
            credited[row], listed[row] = true, true;
        elseif not suppressed then
            local row = matches[n];
            local created = not row;
            row = row or self:create(entity, status.effect, now);
            listed[row] = true;
            -- A copy first listed by a 0x037 without its 0x063 shows the application it seems to have, but is
            -- gained once its timer comes, so a copy that replaced another can be told from a new one.
            local first = timed and not timers_pending and (created or row.fresh and complete);
            local split = created and timed and timers_pending;
            local changed = timed and not created and not row.fresh and renewed(row, status);
            -- The server lists a removed effect until its next effect tick, so only a full listing well
            -- after the message means it is back. Its removal was reported, so it comes back as a gain;
            -- a KO or partial listing can't report one, so the mark waits for a listing that can. A copy
            -- taken for one a recast replaced is back quietly once a later 0x063 still lists it.
            local back, quiet = false, false;
            if row.departing and complete and entity.baseline and not timers_pending then
                local over = row.superseded;
                if over ~= nil and over >= 0 and finite(timer_revision) then back, quiet = timer_revision > over, true;
                elseif over ~= nil or row.recast then back, quiet = now - row.departing_at > 5, true;
                else
                    back = now - row.departing_at > 5
                        and (revision == nil or row.departing_revision == nil or revision > row.departing_revision);
                end
            end
            if back then
                row.departing, row.departing_revision, row.departing_at, row.superseded, row.recast = nil, nil, nil, nil, nil;
                if not quiet then row.instance = row.instance + 1; end
            end
            -- Another caster's recast that moved the timer too little to see: a 0x063 after it still lists
            -- the copy, so it stays, and the application waiting goes to it like any other.
            local held = row.recast;
            if held and held.other and timed and complete and not timers_pending
                and (not finite(held.stamp) or not finite(timer_revision) or timer_revision > held.stamp) then
                row.departing, row.departing_revision, row.departing_at, row.recast = nil, nil, nil, nil;
            end
            local pending, holder;
            if first and row.fresh and row.fresh_pending then pending = fresh_cast(self, row, row.fresh_pending, listed, now, timer_revision); end
            if split then pending = take_pending(self, row, listed, now, true, nil);
            elseif not pending and (first or changed) then
                pending, holder = take_pending(self, row, listed, now, first, timer_revision, moving);
            end
            -- What a zone change left of the player's own effect with one copy, if nothing recast it.
            local carried = first and not pending and self.carried;
            local labels = carried and carried.id == entity.id and carried.labels[status.effect];
            if labels then
                for _, name in ipairs(LABELS) do if labels[name] ~= nil then row[name] = labels[name]; end end
            end
            -- Raised from a KO, Weakness and Arise's Reraise come with the raise (OnRaise), still listed as KO.
            local raised = entity.raised;
            if not pending and created and raised and (status.effect == WEAKNESS or status.effect == RERAISE and raised.level == 4) then
                pending = { source = raised.source, source_name = raised.source_name, spell = raised.spell, at = now };
            end
            if holder then
                for _, key in ipairs(LABELS) do holder[key] = row[key]; end
                holder.total = holder.start and holder.deadline and math.max(0, holder.deadline - holder.start) or nil;
            end
            if split then row.fresh, row.fresh_pending = true, pending; end
            if first then row.fresh, row.fresh_pending = nil, nil; end
            if created and timers_pending then unsettled[status.effect] = true; end
            if changed then
                row.instance = row.instance + 1;
                row.start, row.total = nil, nil;
                row.departing, row.departing_revision, row.departing_at, row.recast = nil, nil, nil, nil;
                row.source, row.source_name, row.spell, row.tier, row.mine, row.by_pet = nil, nil, nil, nil, nil, nil;
                row.observed_at = now;
            end
            row.slot, row.present = status.slot, true;
            row.unavailable_at = nil;
            row.scope, row.entity_name = entity.scope, entity.name;
            if timed then
                -- An icon can show before its 0x063 timer; keep the last known timer until one comes.
                -- A timer that already ran out reads with no deadline once its slot or raw value moves;
                -- the same timer stays known at zero until the slot clears.
                local expired = row.status == 'server' and finite(row.deadline) and not finite(status.deadline)
                    and status.raw_timer ~= nil and row.raw_timer ~= nil and same_deadline(row, status);
                local raw = status.raw_timer;
                if raw ~= nil and raw ~= row.raw_timer then
                    row.raw_other = not changed and finite(raw) and finite(row.raw_timer)
                        and math.abs(signed(raw - row.raw_timer)) == 60 and row.raw_timer or nil;
                end
                if expired then
                    row.raw_timer = status.raw_timer;
                elseif status.raw_timer ~= nil or row.raw_timer == nil then
                    row.raw_timer = status.raw_timer;
                    row.deadline = finite(status.deadline) and status.deadline or nil;
                    row.status = row.deadline and 'server' or 'unknown';
                    row.reason = row.status == 'server' and 'The server supplied this timer.'
                        or 'The status is present, but no current timer is available.';
                end
                if pending then
                    credit(self, row, pending);
                    credited[row] = true;
                elseif row.start and not row.total and row.deadline then
                    row.total = math.max(0, row.deadline - row.start);
                end
            elseif row.deadline and row.deadline <= now then
                row.deadline, row.status = nil, 'unknown';
                row.reason = 'The estimated time ended, but the status is still present.';
            end
            -- A copy whose removal came before its first timer was never gained: its removal is what to tell.
            if ((timed and first and not row.departing or not timed and created) or back and not quiet) and complete and entity.baseline
                and not ambiguous[status.effect] then
                -- A member's second copy of an effect that keeps one, with nothing applied, is the copy a renewal
                -- replaced, listed once more until their next tick drops it (an item they used sends the party no
                -- message), or another effect wearing its icon. The next listing tells, so its gain waits.
                local beside;
                if not timed and created and single(status.effect) and not waiting[status.effect] then
                    for _, other in pairs(matches) do
                        if other.effect == status.effect and not other.departing then beside = other; end
                    end
                end
                if beside then row.held_gain = { keys = { [beside.key] = true }, at = now, listed = true };
                else queued[#queued + 1] = { 'gain', row }; end
            end
            -- A 205 with no removal before it that made a second copy of an effect with one copy replaced the listed
            -- one with no message (protect_earring.lua, OverwriteStatusEffect), or wears the same icon beside it
            -- (haste_belt.lua). A replaced copy leaves with no message at the next tick, a logic update later.
            if first and pending and reported(pending) and single(status.effect) and finite(timer_revision) then
                for _, other in pairs(matches) do
                    if other ~= row and key(other.effect) == key(status.effect) and not other.departing then
                        other.overwritten = { count = timer_revision, at = now };
                    end
                end
            end
            if changed and complete and entity.baseline then queued[#queued + 1] = { 'refresh', row }; end
        end
    end
    -- A listing that had no use for a spare says the member's old copy is gone; so does 3 s.
    if not timed then
        for _, row in ipairs(entity.entries) do
            if row.landed_at ~= nil and revision ~= row.landed_at
                and ((spare[key(row.effect)] or 0) > 0 or now - (row.landed_now or now) > 3) then
                row.landed_at, row.landed_now = nil, nil;
            end
        end
    end
    for _, item in ipairs(queued) do self:queue(item[1], item[2], now); end
    for i = #entity.tombstones, 1, -1 do
        local found = false;
        for _, status in ipairs(incoming) do
            if key(status.effect) == key(entity.tombstones[i].effect) then found = true; break; end
        end
        if complete and not found then table.remove(entity.tombstones, i); end
    end
    if timed and complete then
        if not timers_pending and finite(timer_revision) then settle(self, entity, listed, credited, now, timer_revision); end
        -- Until the 0x063 of a split send comes, the copy of an effect that kept a slot may be the one that
        -- left, so no copy of an effect whose count changed is settled.
        for _, row in ipairs(entity.entries) do
            if not timers_pending then row.unsettled = nil;
            elseif unsettled[row.effect] then row.unsettled = true; end
        end
    end
    for _, by in pairs(merged) do
        if by.held_gain then by.held_gain = nil; self:queue('refresh', by, now); end
    end
    -- No listing showed the count stay within a tick or two: the song was a new copy.
    for _, row in ipairs(entity.entries) do
        if row.held_gain and now - row.held_gain.at > 1.5 then row.held_gain = nil; self:queue('gain', row, now); end
    end
    entity.known, entity.baseline, entity.seen, entity.revision = complete and not stale_presence, complete, now, revision;
end

-- The self half of reconcile. Returns false when the snapshot is not valid.
local function reconcile_self(self, snapshot, now)
    self.context = snapshot or {};
    if not snapshot or not snapshot.valid then
        if self.valid then self:clear('unavailable', now); end
        return false;
    end
    local session = tostring(snapshot.id) .. ':' .. tostring(snapshot.zone);
    if self.session and self.session ~= session then self:clear('zone or character changed', now); end
    self.session, self.valid, self.self_id = session, true, snapshot.id;
    local own = self:entity(snapshot.id, 'self', snapshot.name or 'You', now);
    local split = snapshot.self_timers_pending == true;
    local revision, timers = snapshot.self_revision or snapshot.self_epoch, snapshot.self_timer_revision;
    if snapshot.dead then
        -- Some effects survive a KO, so keep following the slots, quietly. A raise accepted later is the first
        -- one cast while none is held, and a Reraise or Goddess's Hymnus up at the KO holds one already, the
        -- Reraise first (sendRaise, Die, hymnus.lua). No Raise lands while one is held, so one that does
        -- means the held one was declined.
        if not own.dead then
            self.pending, own.raised = {}, nil;
            for _, effect in ipairs({ RERAISE, HYMNUS }) do
                for _, row in ipairs(own.raised == nil and own.entries or EMPTY) do
                    if row.effect == effect and row.present and not row.departing then
                        own.raised = { source = row.source, source_name = row.source_name, spell = row.spell, level = 0, held = true };
                    end
                end
            end
        end
        own.baseline=false;
        self:snapshot(own, snapshot.self_effects, now, true, revision, snapshot.self_known == true, split, timers);
        own.known,own.baseline,own.dead=false,false,true;
    else
        own.dead=false;
        self:snapshot(own, snapshot.self_effects, now, true, revision, snapshot.self_known == true, split, timers);
        own.raised = nil;
    end
    if snapshot.self_known == true and not split then self.carried = nil; end
    return true;
end

-- Your pet has gone. A mob you charmed goes back with what it has on, as the server leaves it (src/map/utils/petutils.cpp
-- :1420-1486), and it is a mob by its index; a pet you called goes with everything.
local CALLED = 0x700;
function methods:release_pet(now)
    local id, index = self.pet_id, self.pet_index;
    self.pet_id, self.pet_index = nil, nil;
    if not id or not self.entities[id] then return; end
    if finite(index) and index < CALLED then
        self:entity(id, 'enemy', nil, now);
    else
        self.entities[id] = nil;
        self.version = self.version + 1;
        self.events[#self.events + 1] = {kind='forget', entity_id=id, quiet=true, time=now};
    end
end

-- A level restriction or Level Sync that changes your level clears what is on a pet you called, with no word of it
-- (src/map/lua/lua_base_entity.cpp levelRestriction :7585, :7642). An ordinary level up clears nothing, and a charmed
-- mob keeps its effects (:7632). The effect and the level can reach the client a moment apart.
local RESTRICTED, SYNCED, RESTRICT_WINDOW = 143, 269, 5;
local function restricted(snapshot)
    for _, row in ipairs(snapshot.self_effects or EMPTY) do
        if row.effect == RESTRICTED or row.effect == SYNCED then return true; end
    end
    return false;
end

local function follow_restriction(self, snapshot, now)
    local index = self.pet_index;
    if not self.pet_id or not finite(index) or index < CALLED then self.pet_restricted = nil; return; end
    local on, level = restricted(snapshot), snapshot.level;
    if self.pet_restricted == nil then self.pet_restricted, self.pet_level = on, level; return; end
    if on ~= self.pet_restricted then self.pet_restricted, self.restricted_at = on, now; end
    if level ~= self.pet_level then self.pet_level, self.level_at = level, now; end
    if not self.restricted_at or not self.level_at or math.abs(self.restricted_at - self.level_at) > RESTRICT_WINDOW then return; end
    self.restricted_at, self.level_at = nil, nil;
    local entity = self.entities[self.pet_id];
    if entity then
        entity.entries, entity.tombstones, entity.baseline = {}, {}, false;
        self.version = self.version + 1;
    end
end

function methods:reconcile(snapshot, now)
    if not reconcile_self(self, snapshot, now) then return; end
    local pet = snapshot.pet;
    if self.pet_id and (not pet or pet.id ~= self.pet_id) then self:release_pet(now); end
    if pet then
        self.pet_id, self.pet_index = pet.id, pet.index;
        if self.entities[pet.id] then self:entity(pet.id, 'pet', pet.name, now); end
    end
    follow_restriction(self, snapshot, now);
    local members = {};
    for _, member in ipairs(snapshot.party or {}) do
        if member.id and member.id ~= snapshot.id and member.id > 0 then
            members[member.id] = true;
            local entity = self:entity(member.id, member.scope=='alliance' and 'alliance' or 'party', member.name, now);
            if entity.zone and entity.zone~=member.zone then
                entity.entries,entity.tombstones,entity.baseline={},{},false;
                self.version=self.version+1;
            end
            entity.zone,entity.group,entity.slot=member.zone,member.group,member.slot;
            if member.valid and member.zone == snapshot.zone then
                -- A member's KO drops what goes with it from their listing with no message, as for the
                -- player, so that listing is read quietly while they are down. The drop can come before
                -- their HP does.
                local down = member.hpp == 0 or entity.died_at ~= nil and now - entity.died_at <= 3;
                if not down and member.hpp ~= nil then entity.died_at = nil; end
                if down then entity.baseline = false; end
                self:snapshot(entity, member.effects, now, false, member.revision);
                if down then entity.known, entity.baseline = false, false; end
            else
                entity.known, entity.baseline = false, false;
                for _, row in ipairs(entity.entries) do row.present = nil; end
            end
        end
    end
    for id, entity in pairs(self.entities) do
        if (entity.scope == 'party' or entity.scope=='alliance') and not members[id] then
            self.entities[id] = nil;
            self.version = self.version + 1;
        end
    end
    local target = snapshot.target;
    if target and target.id and target.id > 0 and target.id ~= snapshot.id then
        local scope, name = locate(snapshot, target.id);
        self:entity(target.id, scope, name, now);
    end
end

-- Each Always_Overwrite application or 205 gain in a batch, in order, by entity then effect. A 205 names its owner
-- whoever used the item (the script's target:messageBasic), so it never says the player's own tick lists both copies.
local function recasts(observations)
    local out = EMPTY;
    for index, observation in ipairs(observations or EMPTY) do
        local id = observation.entity_id;
        local item = observation.kind == 'apply' and reported(observation);
        if (item or observation.kind == 'apply' and OVERWRITES[observation.spell]
            and (observation.action_category == nil or observation.action_category == 4))
            and id ~= nil and effect_id(observation.effect) then
            if out == EMPTY then out = {}; end
            out[id] = out[id] or {};
            local list = out[id][observation.effect];
            if not list then list = {}; out[id][observation.effect] = list; end
            list[#list + 1] = { index = index, stamp = observation.timer_revision,
                other = item or observation.source == nil or observation.source ~= id };
        end
    end
    return out;
end

-- The application that replaced the copy a removal took away: Phoenix sends the old copy's 0x029 and the new
-- copy's 0x028 back to back (enhancing_spell.lua), so it is the first one after the removal on the same 0x063
-- count. Two casters' recasts in one reply each pair with their own.
local function recast_after(recast, id, observation, index)
    for _, cast in ipairs(recast[id] and recast[id][observation.effect] or EMPTY) do
        if cast.index > index and not (finite(cast.stamp) and finite(observation.timer_revision)
            and cast.stamp ~= observation.timer_revision) then return cast; end
    end
end

-- What a hit for more than 0 takes off a mob on every damage path: sleep_i 2, sleep_ii 19 and lullaby 193, marked
-- damage in Phoenix's data/status_effects.yaml (:31, :228, :1799). Melee, ranged, weapon skills, spells and skillchains take off
-- everything marked damage (DelStatusEffectsByFlag, battleutils.cpp :2198, :2360, :2453, :3567); Lua takeDamage and
-- damage ticks take off these three (WakeUp, status_effect_container.cpp :2255-2260). The other effects marked damage
-- (Quickening, Mazurka, Illusion, Bolter's Roll, Healing, Leavegame) are a player's. Phoenix lands every player sleep
-- and lullaby as sleep_i.
local WAKES = { [2] = true, [19] = true, [193] = true };
-- Bind isn't marked damage: each hit for more than 0 breaks it 95 times in 100 (BindBreakCheck, battleutils.cpp
-- :4668-4685), so once one is seen its time can't be known.
local BIND = 11;
-- Third Eye, and Seigan, which can keep it past an attack it anticipates (core/observer.lua).
local THIRD_EYE, SEIGAN = 67, 354;
-- The effects whose ticks deal damage (scripts/effects with REGEN_DOWN): poison 3, kaustra 23, burn to drown 128 to 133,
-- dia 134, bio 135 and requiem 192. A tick wakes a sleeper without a message to anyone but its caster
-- (status_effect_container.cpp :2047-2064), so a sleep beside one teaches nothing.
local DOTS = { [3] = true, [23] = true, [128] = true, [129] = true, [130] = true, [131] = true, [132] = true,
    [133] = true, [134] = true, [135] = true, [192] = true };

-- A mob or a pet took damage: what Phoenix takes off at a hit leaves, and Bind keeps its icon with no time. A mob's
-- Nightmare is the sleep a hit doesn't end (status_effect_container.cpp :856-864). A hit that got through says Copy Image
-- had no shadows left, and a melee swing that landed says nothing anticipated it, so Third Eye was gone. An alliance
-- member's hits are read for those two only.
function methods:hurt(entity, now, through, melee)
    local mob_or_pet = entity.scope ~= 'alliance';
    for i = #entity.entries, 1, -1 do
        local row = entity.entries[i];
        if mob_or_pet and WAKES[row.effect] and not row.deep then
            row.learn_key, row.learn_start = nil, nil;
            self:erase(entity, i, now, 'Damage was observed.');
        elseif through and COPY_IMAGE[row.effect] then
            self:erase(entity, i, now, 'A hit got through, so it had no shadows left.');
        elseif melee and row.effect == THIRD_EYE then
            self:erase(entity, i, now, 'A swing landed, so nothing anticipated it.');
        elseif mob_or_pet and row.effect == BIND then
            row.learn_key, row.learn_start = nil, nil;
            if row.deadline or row.status ~= 'unknown' then
                row.deadline, row.status = nil, 'unknown';
                row.reason = 'A hit was observed. Bind can break at any hit, so it has no countdown.';
                self.version = self.version + 1;
            end
        end
    end
end

-- Phoenix sends a caster's wear-off from inside the hit or removal that ended it (RemoveStatusEffect,
-- status_effect_container.cpp :654-670), before the 0x028 that shows it (attack_state.cpp :92-100, magic_state.cpp
-- :305-327), and with 32 packets at most in a datagram (map_constants.h :79) that 0x028 can come in the next one. So
-- a wear-off of a cast of yours waits a second before it is learned, and these spoil it: a hit on the mob for a
-- sleep or Bind, a removal Vantage saw on that unit, and a copy of the effect or one that drops it, as Bio does
-- Dia (bio.lua :17-22).
local SAMPLE_HOLD = 1;
local function spoils(sample, observation)
    local kind = observation.kind;
    if kind == 'damage' then return WAKES[sample.effect] == true or sample.effect == BIND; end
    if kind == 'remove' or kind == 'removed' then return observation.reason == 'Observed removal'; end
    if kind ~= 'apply' then return false; end
    if effect_id(observation.effect) and key(observation.effect) == key(sample.effect) then return true; end
    for _, dropped in ipairs(observation.drops or EMPTY) do if dropped == sample.effect then return true; end end
    return false;
end

-- Whether an entity has an effect that ticks damage, one row aside.
local function ticking(entity, except)
    for _, row in ipairs(entity.entries) do
        if row ~= except and DOTS[row.effect] and not row.departing then return true; end
    end
    return false;
end

-- Dia or Bio read from its damage message (observation.inferred). Phoenix adds either only over no Dia or Bio of
-- its tier or higher (dia.lua, bio.lua; AddStatusEffect refuses Dia over Dia, and Bio over Bio, of the same tier),
-- so a current copy of a tier as high, or of no known tier, means nothing changed. A copy whose time is up is
-- gone. The player's own effects are read from their listing.
local DIA_BIO = { [134] = true, [135] = true };
local function refused(entity, observation, scope, now)
    if not observation.inferred or scope == 'self' or not DIA_BIO[observation.effect] or not finite(observation.tier) then
        return false;
    end
    for _, row in ipairs(entity.entries) do
        if DIA_BIO[row.effect] and not row.departing then
            local ends = finite(row.estimated_until) and row.estimated_until or row.deadline;
            if (not finite(ends) or ends > now) and (not finite(row.tier) or row.tier >= observation.tier) then return true; end
        end
    end
    return false;
end

-- Whether an application to someone else is the copy of a row with those labels. A song replaces the copy
-- of its tier, whoever sang it (ApplyBardEffect); without tiers a copy that stacks is the instance the
-- observation names, or its caster's spell.
local function lands(observation, source, spell, hint, tier)
    if observation.stackable and song(observation.effect) and observation.tier ~= nil and tier ~= nil then return tier == observation.tier; end
    if observation.instance_hint then return hint == observation.instance_hint; end
    return not observation.stackable or source == observation.source and spell == observation.spell;
end

function methods:observe(observations, now, snapshot)
    snapshot = snapshot or self.context or {};
    if not snapshot.valid then return; end
    -- A spell that always overwrites takes its old copy off with a wear-off message just before the new
    -- copy's application, with no status packet between (Phoenix enhancing_spell.lua: delStatusEffect, then
    -- addStatusEffect). The message goes to the owner and to the old copy's caster. An effect that expired
    -- on the player is sent off with the status packets of that tick, so a cast after it comes behind a
    -- 0x063, except the player's own in that tick. The player's recast lists the old copy beside the new
    -- one; another caster's lists the new one alone. So a removal of the player's effect with such an
    -- application of it later in the batch, on the same 0x063 count, holds its event: another caster's
    -- renews the row, and the player's waits for the listing to show both copies. Anyone else's effect has
    -- no listing to wait for, so the application renews its row and the removal is dropped. An item that
    -- puts an effect back the same way sends a 205 for it instead of the action, which is held alike.
    local recast = recasts(observations);
    for index, observation in ipairs(observations or {}) do
        local id, kind = observation.entity_id, observation.kind;
        local held = self.held_samples;
        if id and #held > 0 then
            for i = #held, 1, -1 do
                if held[i].entity_id == id and spoils(held[i], observation) then table.remove(held, i); end
            end
        end
        if kind == 'raise' then
            local own = id ~= nil and id == snapshot.id and self.entities[id];
            if own and own.dead and (not own.raised or own.raised.held) then
                own.raised = { source = observation.source, source_name = observation.source_name, spell = observation.spell,
                    level = observation.level };
            end
        elseif kind == 'death' and id and id ~= snapshot.id and member(snapshot, id) then
            -- A party member's KO is read from their listing, as the player's own.
            local entity = self.entities[id];
            if entity then entity.died_at = now; end
        elseif kind == 'damage' and id then
            local entity = self.entities[id];
            if entity and (entity.scope == 'enemy' or entity.scope == 'pet' or entity.scope == 'alliance') then
                self:hurt(entity, now, observation.through, observation.melee);
            end
        elseif kind == 'shadows' and id then
            -- Shadows a mob or an alliance member lost come off the count their Utsusemi started, and the icon shows what's
            -- left.
            local entity = self.entities[id];
            for i = #(entity and (entity.scope == 'enemy' or entity.scope == 'alliance') and entity.entries or EMPTY), 1, -1 do
                local row = entity.entries[i];
                if row.shadows then
                    row.shadows = row.shadows - observation.lost;
                    if row.shadows > 0 then
                        row.observed_at = now;
                        relabel(row, SHADOW_ICONS[math.min(row.shadows, 4)]);
                        self.version = self.version + 1;
                    else
                        self:erase(entity, i, now, 'Its last shadow took a hit.');
                    end
                end
            end
        elseif kind == 'anticipated' and id then
            -- Third Eye anticipated an attack and went, unless Seigan kept it. That chance falls over its 30 seconds
            -- (physical_hit_rate.lua checkAnticipated) and can't be seen, so beside Seigan it stays until its time is up
            -- or a swing lands.
            local entity = self.entities[id];
            local kept = false;
            for _, row in ipairs(entity and entity.entries or EMPTY) do
                if row.effect == SEIGAN then kept = true; break; end
            end
            for i = #(entity and not kept and entity.entries or EMPTY), 1, -1 do
                if entity.entries[i].effect == THIRD_EYE then self:erase(entity, i, now, 'It anticipated an attack.'); end
            end
        elseif kind == 'pet_gone' then
            self:release_pet(now);
        elseif kind == 'cure' and id then
            -- What your job ability took off your pet: all of its list, or the first count Vantage holds, in that order.
            local entity = self.entities[id];
            local left = observation.count or math.huge;
            for _, effect in ipairs(entity and observation.effects or EMPTY) do
                for i = #entity.entries, 1, -1 do
                    if left > 0 and entity.entries[i].effect == effect then
                        self:erase(entity, i, now, 'Your ability took it off.');
                        left = left - 1;
                    end
                end
            end
        elseif id and (kind == 'despawn' and not (snapshot.pet and snapshot.pet.id == id) or kind == 'death' and id ~= snapshot.id) then
            -- A despawn of your pet says only that it is out of your view, past 50 yalms; the rows stay until it goes.
            -- The player's own KO is read from the status packets, which still list everything and then drop
            -- what goes with it with no message, so the rows stay and what survives it keeps its own.
            self.entities[id] = nil;
            self.version = self.version + 1;
            self.events[#self.events + 1] = {kind='forget', entity_id=id, quiet=true, time=now};
        elseif id and effect_id(observation.effect) and not (snapshot.dead and id==snapshot.id) then
            local scope, name = locate(snapshot, id);
            scope = observation.scope or scope;
            local entity = self:entity(id, scope, observation.entity_name or name, now);
            if entity and (kind == 'remove' or kind == 'removed') then
                -- A removal Vantage saw (Erase and the -na spells) sends its wear-off as an expiry does, so the times
                -- running on that unit teach nothing.
                if observation.reason == 'Observed removal' then
                    for _, row in ipairs(entity.entries) do row.learn_key, row.learn_start = nil, nil; end
                end
                local candidates = {};
                for i, row in ipairs(entity.entries) do
                    -- A copy that leaves with a message is no copy a 205 replaced.
                    if row.overwritten and key(row.effect) == key(observation.effect) then row.overwritten = nil; end
                    -- Reward and Repair take the old Regen off with a message just before the new one, and a wear-off
                    -- behind its action is the old copy's.
                    local old = observation.reason == tracker.WEAR_OFF and row.exact and row.mine and finite(row.start) and now - row.start < 1;
                    if not old and not row.departing and key(row.effect) == key(observation.effect) and (not observation.source or not row.source or row.source == observation.source) then
                        candidates[#candidates + 1] = i;
                    end
                end
                local cast = recast_after(recast, id, observation, index);
                -- A shared icon is not enough evidence to choose a removed instance.
                if #candidates == 1 and (scope == 'self' or not cast) then
                    local taken = {};
                    for c = #candidates, 1, -1 do
                        local at = candidates[c];
                        local row = entity.entries[at];
                        local reason = observation.reason or 'The removal was observed.';
                        local seen = scope == 'self' and listed(snapshot, row, taken);
                        -- A party member's listing can still copy their icons from before it until their next
                        -- tick, so their row also stays, leaving, until a listing drops it.
                        local party = (scope == 'party' or scope == 'alliance') and row.present == true;
                        -- The player's own recast read with a listing already past its two-copy tick (both ticks came
                        -- in one reply) lists the new copy alone, as another caster's does. Only a copy whose time
                        -- was up left before it.
                        local past = cast and not cast.other and not seen and finite(row.deadline) and row.deadline > now + 1;
                        -- An item's Lua sends the removal and the 205 that puts the effect back before the tick's status
                        -- packets, and a datagram can end between them. So with no 0x063 after it yet, the removal of an
                        -- effect items put back waits for that 205. Phoenix erases a deleted copy as the player's tick
                        -- starts (CheckEffectsExpiry), so a 0x063 lists it only after the player's own action in that tick:
                        -- one that lists it beside a new copy of an effect with one copy says that action put it back, as
                        -- an item with no 205 (hi-reraiser.lua), a spell or an ability does. That one waits too.
                        local stamp, count = observation.timer_revision, snapshot.self_timer_revision;
                        local waits = not cast and seen and finite(stamp) and finite(count) and (count == stamp and REUSED[key(row.effect)]
                            or count == stamp + 1 and single(row.effect) and copies(snapshot, row.effect) > 1);
                        if seen or party or cast and (cast.other or past) then
                            -- The message comes before the icons; keep the row drawn until its slot clears.
                            if cast then row.recast = { reason = reason, other = cast.other or past, stamp = observation.timer_revision };
                            elseif waits then row.recast = { reason = reason, other = true, stamp = observation.timer_revision, waiting = true };
                            else self:queue('removed', row, now, reason); end
                            row.departing, row.departing_at = true, now;
                            row.departing_revision = scope == 'self' and (snapshot.self_revision or snapshot.self_epoch) or entity.revision;
                            -- The listing from before the removal still lists it; only a newer one keeps it.
                            if party then
                                entity.tombstones[#entity.tombstones + 1] = {effect=row.effect,raw_timer=row.raw_timer,revision=entity.revision,at=now};
                            end
                        else
                            if scope == 'self' or scope == 'party' then
                                entity.tombstones[#entity.tombstones + 1] = {effect=row.effect,raw_timer=row.raw_timer,revision=entity.revision,at=now};
                            end
                            self:erase(entity, at, now, reason);
                        end
                    end
                end
            elseif entity and kind == 'apply' and not refused(entity, observation, scope, now) then
                if scope == 'self' then
                    self.pending[key(observation.effect)] = self.pending[key(observation.effect)] or {};
                    local pending = copy(observation);
                    pending.at = now;
                    -- A 205 after a removal of that effect on the same 0x063 count puts the copy back: the row the
                    -- removal holds is renewed by it.
                    for _, row in ipairs(reported(observation) and entity.entries or EMPTY) do
                        local held = row.recast;
                        if held and row.departing and key(row.effect) == key(observation.effect)
                            and not (finite(held.stamp) and finite(observation.timer_revision) and held.stamp ~= observation.timer_revision) then
                            pending.renewal = true;
                            if held.waiting then row.recast = { reason = held.reason, other = true, stamp = held.stamp }; end
                        end
                    end
                    local list = self.pending[key(observation.effect)];
                    list[#list + 1] = pending;
                    if #list > 8 then table.remove(list, 1); end
                else
                    -- The listings the application came after: the 0x076 count at its arrival.
                    local stamp = finite(observation.party_revision) and observation.party_revision or entity.revision;
                    if scope == 'party' then
                        entity.pending_presence, entity.pending_revision, entity.known = true, stamp, false;
                    end
                    -- A drop of Copy Image takes it at any icon, the one for a last shadow (66) too. The effect that
                    -- lands keeps its own row, to renew below.
                    for i = #entity.entries, 1, -1 do
                        for _, dropped in ipairs(observation.drops or {}) do
                            if entity.entries[i] and key(entity.entries[i].effect) == key(dropped) and key(dropped) ~= key(observation.effect) then
                                if scope == 'party' then
                                    local held = entity.entries[i];
                                    entity.tombstones[#entity.tombstones + 1] = {effect=held.effect,revision=entity.revision,at=now};
                                end
                                self:erase(entity, i, now, 'A replacement effect was observed.');
                                break;
                            end
                        end
                    end
                    local row;
                    for _, held in ipairs(entity.entries) do
                        if key(held.effect) == key(observation.effect) and lands(observation, held.source, held.spell, held.instance_hint, held.tier) then
                            row = held;
                            break;
                        end
                    end
                    local created = not row;
                    -- A song on a member whose copies of it no 0x028 labelled (sung out of range, or up when this
                    -- loaded) may have replaced one of them, of its tier, or be a new copy. Their listing tells, so
                    -- its gain waits.
                    local blind;
                    if created and scope == 'party' and observation.stackable and song(observation.effect) and finite(observation.tier) then
                        for _, held in ipairs(entity.entries) do
                            if held.effect == observation.effect and not held.departing and held.tier == nil and held.spell == nil then
                                blind = blind or {};
                                blind[held.key] = true;
                            end
                        end
                    end
                    -- A job ability is reported to every target even when a stronger copy refuses it, and nothing
                    -- here has a timer to show which: another caster's copy it names becomes nobody's in particular.
                    if not created and not row.departing and observation.action_category == 6 and row.source ~= observation.source
                        and not observation.exact then
                        row.source, row.source_name, row.spell, row.tier, row.instance_hint, row.mine, row.by_pet = nil, nil, nil, nil, nil, nil, nil;
                        row.learn_key, row.learn_start = nil, nil;
                    else
                        row = row or self:create(entity, observation.effect, now);
                        -- A copy whose removal was seen is back.
                        local back = row.departing == true;
                        row.departing, row.departing_revision, row.departing_at = nil, nil, nil;
                        if not created then row.instance, row.landed_at, row.landed_now = row.instance + 1, entity.revision, now; end
                        -- Over a singer's cap Phoenix drops their song that ends first, with no message.
                        if song(observation.effect) and observation.source ~= nil then
                            entity.sung = entity.sung or {};
                            entity.sung[observation.source] = { row = row, at = now };
                        end
                        row.source, row.source_name = observation.source, observation.source_name;
                        row.spell, row.tier, row.instance_hint = observation.spell, observation.tier, observation.instance_hint;
                        row.mine, row.by_pet = observation.source == snapshot.id, observation.by_pet;
                        -- A length Vantage knows exactly, the copy of yours it ends with, and the sleep a hit doesn't end.
                        row.exact, row.follow, row.follow_spell, row.deep = observation.exact, observation.follow, observation.follow_spell, observation.deep;
                        row.kind = observation.category or row.kind;
                        row.group = observation.group or row.group;
                        -- A mob's or an alliance member's Utsusemi starts the count of their shadows.
                        row.shadows = observation.shadows;
                        if row.shadows then relabel(row, SHADOW_ICONS[math.min(row.shadows, 4)]); end
                        row.observed_at = now;
                        row.application_revision = stamp;
                        row.start = now;
                        row.total = finite(observation.duration) and observation.duration > 0 and observation.duration or nil;
                        row.deadline = row.total and now + row.total or nil;
                        row.estimated_until = row.deadline;
                        -- A count up keeps the estimate it hides, so its row stays as long as that one would.
                        if not row.deadline and finite(observation.retain_for) and observation.retain_for > 0 then
                            row.estimated_until = now + observation.retain_for;
                        end
                        row.duration_min = finite(observation.duration_min) and observation.duration_min or nil;
                        row.status = row.deadline and 'estimated' or 'unknown';
                        row.reason = observation.reason or observation.basis or
                            (row.deadline and 'The application was observed. Its duration is estimated.' or 'The application was observed. Vantage has no duration for it.');
                        -- A duration override or a learned time (core/durations.lua), and the clock of a cast of
                        -- yours to learn from. A new copy starts its clock again (status_effect_container.cpp :516).
                        row.count_up, row.timing = observation.count_up or nil, observation.timing;
                        row.learn_key = observation.learn_key;
                        if row.learn_key and WAKES[row.effect] and ticking(entity, row) then row.learn_key = nil; end
                        row.learn_start = row.learn_key and now or nil;
                        -- A tick of damage wakes a sleeper, so a sleep already running when one lands teaches nothing.
                        if DOTS[row.effect] then
                            for _, held in ipairs(entity.entries) do
                                if WAKES[held.effect] then held.learn_key, held.learn_start = nil, nil; end
                            end
                        end
                        if blind then
                            row.held_gain = { keys = blind, at = now };
                        elseif created or back then
                            self:queue('gain', row, now);
                        else
                            self:queue('refresh', row, now);
                        end
                    end
                end
            end
        end
    end
end

-- A row that ends with your own copy takes your copy's time, once the server has given it. With follow_spell only your
-- copy from the same action counts: an older one a ward didn't replace says nothing of it.
local function follow(own, row)
    for _, held in ipairs(own.entries) do
        if held.effect == row.follow and held.status == 'server' and finite(held.deadline) and not held.departing
            and (not row.follow_spell or held.spell == row.follow_spell and finite(held.start) and math.abs(held.start - row.start) <= 3) then
            if row.deadline ~= held.deadline then
                row.deadline, row.estimated_until, row.status = held.deadline, held.deadline, 'estimated';
                row.total = math.max(0, held.deadline - row.start);
            end
            return;
        end
    end
end

-- A view hands out a row's copy again while the row holds just what it did when the copy was made: a refresh then makes
-- nothing for it. Each row's record keeps those fields, and under COPIED and FIELDS the copy and how many fields there were.
local COPIED, FIELDS = {}, {};
local function by_key(a, b) return a.key < b.key; end
local function by_id(a, b) return a.id < b.id; end

-- Whether held has the fields record kept, and no others. A field that holds a table is the same table: the tracker puts
-- a new one in and never changes one in place.
local function same_fields(record, held)
    local count = 0;
    for field, value in pairs(held) do
        if record[field] ~= value then return false; end
        count = count + 1;
    end
    return count == record[FIELDS];
end

function methods:view(now, settings, snapshot)
    local config = settings and settings.tracking or {};
    local stale = math.max(10, math.min(3600, tonumber(config.stale_seconds) or 180));
    local max_entities = math.max(8, math.min(256, tonumber(config.max_entities) or 64));
    local result = {rows={},subjects={},valid=self.valid,self_known=false,context=snapshot or self.context or {},version=self.version};
    for effect,list in pairs(self.pending) do
        for i=#list,1,-1 do if now-list[i].at>3 then table.remove(list,i); end end
        if #list==0 then self.pending[effect]=nil; end
    end
    local count = 0;
    local own = self.self_id and self.entities[self.self_id];
    for id, entity in pairs(self.entities) do
        for i = #entity.entries, 1, -1 do
            local row = entity.entries[i];
            if row.follow and own and finite(row.start) then follow(own, row); end
            -- A length known exactly leaves at its deadline, with no listing to wait for.
            local ended = row.exact and row.present == nil and row.deadline and row.deadline <= now;
            -- A server timer at zero stays until the server clears its slot, also on a row a split holds.
            if not ended and row.deadline and row.deadline <= now and not (row.present ~= nil and row.status == 'server') then
                row.deadline, row.status = nil, 'unknown';
                row.reason = row.present and 'The status is still present. Its timer needs an update.'
                    or 'The estimated time ended. No wear-off was seen.';
            end
            local retained_until = math.max(row.observed_at, row.estimated_until or row.observed_at, row.unavailable_at or row.observed_at);
            -- A row a split send held back (present false) waits for its 0x063, however old it is.
            if row.present == nil and (ended or now - retained_until > stale) then
                self:erase(entity, i, now, 'The observation is too old.', true);
            end
        end
        if not entity.known and #entity.entries == 0 and now - entity.seen > stale then
            self.entities[id] = nil;
        else
            count = count + 1;
        end
    end
    if count > max_entities then
        local oldest = {};
        for id, entity in pairs(self.entities) do
            if entity.scope ~= 'self' and entity.scope ~= 'party' and entity.scope~='alliance' and id ~= self.pet_id then
                oldest[#oldest + 1] = {id=id,at=entity.seen};
            end
        end
        table.sort(oldest, function(a,b) return a.at < b.at; end);
        for _, item in ipairs(oldest) do
            if count <= max_entities then break; end
            self.entities[item.id], count = nil, count - 1;
        end
    end
    local records, kept = self.records, self.spare_records;
    for _, entity in pairs(self.entities) do
        result.subjects[#result.subjects + 1] = {id=entity.id,name=entity.name,scope=entity.scope,known=entity.known,
            group=entity.group,slot=entity.slot,zone=entity.zone};
        if entity.scope == 'self' then result.self_known = entity.known; end
        for _, held in ipairs(entity.entries) do
            local record = records[held];
            local row = record and same_fields(record, held) and record[COPIED];
            if row then
                -- What was written on the copy since, as a projection that marked it ended, goes back to what the row
                -- holds. Its tables are its own copies, and stay.
                for field, value in pairs(row) do
                    local own = held[field];
                    if value ~= own and type(own) ~= 'table' then row[field] = own; end
                end
                as_copy_image(row);
            else
                -- Rows hold about two dozen fields. The copy starts with room for 32 instead of growing as it fills, and
                -- so does the record, which holds them and its two marks.
                row = new_table(0, 32);
                for key, value in pairs(held) do row[key] = type(value) == 'table' and copy(value) or value; end
                as_copy_image(row);
                if record then clear(record); else record = new_table(0, 32); end
                local fields = 0;
                for key, value in pairs(held) do record[key], fields = value, fields + 1; end
                record[COPIED], record[FIELDS] = row, fields;
            end
            kept[held] = record;
            row.remaining = row.deadline and math.max(0,row.deadline-now) or nil;
            row.elapsed = row.start and math.max(0,now-row.start) or nil;
            result.rows[#result.rows + 1] = row;
        end
    end
    -- The records of rows that are gone go with the old map, emptied for the next view to fill.
    clear(records);
    self.records, self.spare_records = kept, records;
    table.sort(result.rows, by_key);
    table.sort(result.subjects, by_id);
    return result;
end

local function project_rows(rows, now)
    for _, row in ipairs(rows or {}) do
        if row.domain ~= 'recast' then
            local expired = row.deadline and row.deadline <= now and not (row.present ~= nil and row.status == 'server');
            row.remaining = row.deadline and not expired and math.max(0, row.deadline - now) or nil;
            row.elapsed = row.start and math.max(0, now - row.start) or nil;
            if expired then
                row.status = 'unknown';
                row.reason = row.present and 'The status is still present. Its timer needs an update.'
                    or 'The estimated time ended. No wear-off was seen.';
            end
        end
    end
end

function methods:project(view, now, remapped_rows)
    if not view or not finite(now) then return; end
    project_rows(view.rows, now);
    if remapped_rows then project_rows(remapped_rows, now); end
end

function methods:drain_events()
    local events = self.events;
    self.events = {};
    return events;
end

-- The wear-offs of your casts that nothing spoiled for SAMPLE_HOLD, oldest first: the times core/durations.lua
-- learns.
function methods:samples(now)
    local held = self.held_samples;
    if #held == 0 or not finite(now) then return EMPTY; end
    local ready, i = EMPTY, 1;
    while held[i] do
        if now - held[i].time >= SAMPLE_HOLD then
            if ready == EMPTY then ready = {}; end
            ready[#ready + 1] = table.remove(held, i);
        else
            i = i + 1;
        end
    end
    return ready;
end

return tracker;
