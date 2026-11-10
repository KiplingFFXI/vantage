-- Turns complete incoming outcomes into observations. It never requests state.
local observer = {};
local client = require('core.client');
local catalog = require('core.catalog');
local bit = require('bit');
local packets = { [0x00A]=true, [0x00B]=true, [0x00E]=true, [0x028]=true, [0x029]=true, [0x037]=true, [0x063]=true, [0x068]=true,
    [0x076]=true, [0x08C]=true };
local wanted = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [11] = true, [13] = true };
local sources = { [4] = 'spells', [6] = 'abilities', [11] = 'skills', [13] = 'pacts' };
local landed = { [127] = true, [186] = true, [230] = true, [236] = true, [237] = true, [242] = true,
    [243] = true, [266] = true, [267] = true, [268] = true, [271] = true, [277] = true, [278] = true,
    [319] = true, [320] = true };
local ability_message = { [127] = true, [277] = true, [319] = true, [320] = true };
-- Job abilities name the buff they give in the param (Phoenix CCharEntity::OnAbility). These messages say
-- the target gained it: Berserk and Last Resort, Warcry and Boost, Defender, Aggressor, Focus, Dodge, the
-- circles on their user and on others, and Warcry on a party member. One with no message of its own is
-- sent as 'uses' (100), which only counts for a buff on its user.
local ability_buffs = { [115] = true, [116] = true, [117] = true, [118] = true, [120] = true, [121] = true,
    [131] = true, [134] = true, [148] = true, [150] = true, [149] = true, [151] = true, [285] = true,
    [286] = true, [287] = true };
local removed = { [83] = true, [123] = true, [159] = true, [168] = true, [321] = true, [341] = true,
    [343] = true, [378] = true };
local damage = { [1] = true, [2] = true, [67] = true, [110] = true, [163] = true, [185] = true,
    [229] = true, [252] = true, [264] = true, [317] = true, [352] = true, [353] = true, [576] = true, [577] = true };
-- A hit for more than 0 wakes a mob in Phoenix: melee, ranged and counters (battleutils.cpp TakePhysicalDamage
-- :2196), weapon and monster skills (TakeWeaponskillDamage :2358), damaging spells and Drain (TakeSpellDamage
-- :2451), and abilities, blood pacts and HP drains through Lua takeDamage (lua_base_entity.cpp :10803). These are
-- their messages in scripts/enum/msg.lua: hit 1, magic 2, critical 67, ability 110 and 317, skill 185, skill and
-- magic HP drain 187 and 227, magic burst 252, area 264, ranged 352, 353, 576 and 577, and the pet magic bursts
-- 379 and 747; added damage 163 and 229 too. Barrage and Sange shots are ranged hits whose rows take the ability's
-- message (battle_entity.cpp :3393-3398, :3485-3490): Sange 77 and Barrage 157 (src/map/enums/msg_basic.h :83, :113).
local wakes = { [1] = true, [2] = true, [67] = true, [77] = true, [110] = true, [157] = true, [163] = true, [185] = true,
    [187] = true, [227] = true, [229] = true, [252] = true, [264] = true, [317] = true, [352] = true, [353] = true,
    [379] = true, [576] = true, [577] = true, [747] = true };
-- Added effects that deal damage, each through takeDamage: damage 163 and 229, and the HP, MP and TP drains 161, 162
-- and 165 (combat/action_additional_effect_damage.lua :212, globals/additional_effects.lua :101).
local added_wakes = { [161] = true, [162] = true, [163] = true, [165] = true, [229] = true };
-- A skillchain wakes its target whatever it deals, even when absorbed (battleutils.cpp TakeSkillchainDamage :3567). Its
-- message is 287 plus its kind, or 384 plus its kind when absorbed (action/action.cpp :27-42), kinds 1 to 16.
local function skillchain(message) return message ~= nil and (message >= 288 and message <= 303 or message >= 385 and message <= 400); end
-- A counter hits the attacker back through TakePhysicalDamage (battle_entity.cpp :3781-3783), message 33 in the
-- reaction slot with the damage. Spikes don't wake or break Bind: they deal their damage without either
-- (CBattleEntity::takeDamage, battleutils.cpp :952, :990, :997, :1092, :1145).
local COUNTERED = 33;
-- A mob's or an alliance member's Utsusemi, whose shadows the tracker counts, as the game lists only your party's. Ichi
-- gives 3, Ni 4 and San 5 (globals/spells/enhancing_ninjutsu.lua :28-30), and Ni one less to a caster whose main job isn't
-- NIN (:51-57): the mobs that cast it are NINs but Ark Angel HM, a WAR, and Shikaree X, a BST
-- (data/zones/laloff_amphitheater/mobs.yaml, data/zones/boneyard_gully/mobs.yaml). The gear that adds a shadow came after
-- Phoenix's era. A shadow that takes a hit says so on its owner's row, message 31 with how many went, and one that takes a
-- counter to its owner's own attack is reaction 14 (battle_entity.cpp :3698-3701, :3716-3720). Utsusemi takes every hit while it has a shadow
-- (battleutils.cpp IsAbsorbByShadow :3104-3175), so a hit for damage that got through says none are left: melee 1 and 67,
-- ranged 352, 353, 576 and 577, Barrage 157 and Sange 77, a weapon skill 185, and a counter (battle_entity.cpp :3265-3270,
-- :3686-3698, weaponskills.lua :150-158, :864). A deflected swing reads as a hit for nothing (battle_entity.cpp
-- :3681-3683). A Sneak or Trick Attack round goes through shadows, as may a weapon skill's first hit (:3686-3698,
-- weaponskills.lua :677), until the user's next melee round drops both (battle_entity.cpp :3965-3969).
local COPY_IMAGE, SHADOWS, NI, NINJA = 66, { [338] = 3, [339] = 4, [340] = 5 }, 339, 13;
local NOT_NIN = { ['Ark Angel HM'] = true, ['Shikaree X'] = true };
-- Whether Ni gives this caster one shadow less. An alliance member's main job is the client's; while it has none they
-- count as a NIN, and a shadow too many goes at the next hit that lands.
local function short_of_ni(entry, snapshot)
    if entry.scope == 'enemy' then return NOT_NIN[entry.entity_name] == true; end
    local job = client.member_job(snapshot, entry.entity_id);
    return job ~= nil and job ~= NINJA;
end
-- Third Eye anticipates the next attack and goes, message 30 on its owner's row, unless Seigan keeps it
-- (physical_hit_rate.lua checkAnticipated, battle_entity.cpp :3704-3710, mobskills.lua :620). A melee swing meets the
-- shadows and then Third Eye (battle_entity.cpp :3686-3704), so one that lands for damage says it was gone, also in a Sneak
-- or Trick Attack round, which goes past shadows but not Third Eye. Its wear-off reaches only its owner
-- (status_effect_container.cpp :611-670), so for a mob or an alliance member these are all there is to see.
local ANTICIPATED = 30;
local ABSORBED, COUNTER_ABSORBED = 31, 14;
local passed = { [1] = { [1] = true, [67] = true }, [2] = { [77] = true, [157] = true, [352] = true, [353] = true,
    [576] = true, [577] = true }, [3] = { [185] = true } };
local SNEAK_ATTACK, TRICK_ATTACK = 44, 76;
local sneaking = {};
-- The reason a 0x029 wear-off gives its removal. core/tracker.lua holds these for learning.
observer.wear_off = 'Observed wearoff';
-- Raise, Raise II, Raise III and Arise, and the raise level each gives (Phoenix raise*.lua and arise.lua,
-- sendRaise). They finish with message 309, 'casts ... on'.
local raises = { [12] = 1, [13] = 2, [140] = 3, [494] = 4 };
-- The two-hours and key job abilities the party cooldown watch counts (data/party_cooldowns.lua). A job ability
-- finishes as category 6 with its ability id (Phoenix CCharEntity::OnAbility, char_entity.cpp :2014-2016); one with
-- its own category names it there, with the messages that tell it from what else has its id.
local watched = require('core.party_cooldowns').WATCHED;
local WILD_CARD = require('core.party_cooldowns').WILD_CARD;
-- A Phantom Roll or Double-Up from you or a party member, for the Phantom Roll display (core/rolls.lua). The Corsair is
-- the first target and keeps the roll's own message: 420 a roll, 424 a Double-Up, 426 a bust. The others get 421, or
-- 427 on a bust, and 283 when they already have the roll from another Corsair (scripts/globals/job_utils/corsair.lua
-- applyRoll :766-841, src/map/entities/char_entity.cpp :2074-2085, scripts/enum/msg.lua :223, :297-304). The param is
-- the total, 12 on a bust.
local in_era_rolls = require('data.rolls');
local roll_results = { [420] = 'got', [421] = 'got', [424] = 'got', [426] = 'bust', [427] = 'bust', [283] = 'none',
    [422] = 'none', [423] = 'none', [425] = 'none' };
-- Your Charm that took (message 136, scripts/enum/msg.lua :144) and your Familiar, for the pet display's charm estimate
-- (core/pet.lua). Both are category 6 with the ability's id.
local CHARM, CHARMED, FAMILIAR = 52, 136, 24;
-- What you and your pet do to each other (data/pets.lua). Your avatar's wards report 319 or 266, Rolling Thunder 320 or
-- 267, and those that give several effects a message of their own; 323 is a ward that took no effect on that target.
local pets = require('data.pets');
local EMPATHY = {};
for _, effect in ipairs(pets.empathy) do EMPATHY[effect] = true; end
local several = { [146] = true, [147] = true, [364] = true, [365] = true, [414] = true, [415] = true };
local ward_gains = { [266] = true, [267] = true, [319] = true, [320] = true };
for message in pairs(several) do ward_gains[message] = true; end
local CHANCE, OVERLOADED = 798, 799;
local FOLLOWS = 'Ends when your own copy does.';
local NONE = {};
local function status(id) return type(id) == 'number' and id > 0 and id <= 1023 and id ~= 255; end
local function u16(data, pos) return data:byte(pos + 1) + data:byte(pos + 2) * 256; end
local function u32(data, pos) return u16(data, pos) + u16(data, pos + 2) * 65536; end

-- The 0x028 being decoded and the bit reader, held for one decode so read makes no closure.
local raw, unpack;
local function read(at, length) return unpack(raw, 0, at, length); end

-- Bounds are checked before every native read. Nothing is emitted from a partial action.
-- 0x028 is read by bit: actor at 40, target count at 72, category at 82, action id at 86, first target at 150. A target
-- is a 32 bit id and a 4 bit result count. A result is 85 bits, param at +27 and message at +44, then an added effect
-- block of 37 bits and a reaction block of 34, each behind a 1 bit flag.
local function decode_action(total)
    local category = read(82, 4);
    if not wanted[category] then return nil; end
    local count = read(72, 6);
    if count < 1 or count > 15 then return nil; end
    local action = { actor = read(40, 32), id = read(86, 32), category = category, rows = {} };
    local at = 150;
    for _ = 1, count do
        if at + 36 > total then return nil; end
        local target, results = read(at, 32), read(at + 32, 4);
        if results < 1 or results > 8 then return nil; end
        at = at + 36;
        for _ = 1, results do
            local start = at;
            if at + 86 > total then return nil; end
            local row = { target = target, param = read(start + 27, 17), message = read(start + 44, 10) };
            at = at + 85;
            local added = read(at, 1) == 1;
            at = at + 1;
            if added then
                if at + 37 > total then return nil; end
                row.added, row.added_param = read(at + 27, 10), read(at + 10, 17);
                at = at + 37;
            end
            if at + 1 > total then return nil; end
            local reaction = read(at, 1) == 1;
            at = at + 1;
            if reaction then
                if at + 34 > total then return nil; end
                row.reaction_param, row.reaction = read(at + 10, 14), read(at + 24, 10);
                at = at + 34;
            end
            action.rows[#action.rows + 1] = row;
        end
    end
    return action;
end

-- size is the packet's, when the caller has read it already.
function observer.decode(e, size)
    local total = (size or client.packet_size(e)) * 8;
    if total < 150 then return nil; end
    raw = e.data_raw;
    if not raw or not ashita or not ashita.bits then raw = nil; return nil; end
    unpack = ashita.bits.unpack_be;
    local ok, result = pcall(decode_action, total);
    raw = nil;
    return ok and result or nil;
end

local function identity(snapshot, id)
    local entity = snapshot.entities and snapshot.entities[id];
    if entity then return entity; end
    return client.resolve(id);
end

-- Whether id is in your alliance's other parties.
local function ally(snapshot, id)
    for _, member in ipairs(snapshot.party or NONE) do
        if member.id == id then return member.scope == 'alliance'; end
    end
    return false;
end

local function event(snapshot, kind, id, effect, actor)
    local entity = identity(snapshot, id);
    local from = actor and identity(snapshot, actor);
    local scope = id == snapshot.id and 'self' or entity.kind == 'monster' and 'enemy' or entity.kind == 'pet' and 'pet' or 'other';
    for _, member in ipairs(snapshot.party or {}) do
        if member.id == id then scope = member.scope=='alliance' and 'alliance' or 'party'; break; end
    end
    return { kind = kind, entity_id = id, effect = effect, entity_name = entity.name,
        source = actor, source_name = from and from.name, scope = scope };
end

-- The seconds a ward of your avatar lasts with this summoning skill, or nil with no skill or level to work it out from.
-- Over is your skill past the cap of the avatar's level: your main level as SMN main, your sub level as SMN sub
-- (src/map/utils/petutils.cpp :792-816).
local function ward_seconds(ward, skill, level)
    if not ward.per then return ward.base; end
    local cap = level and pets.summoning_caps[level];
    if not cap or type(skill) ~= 'number' then return nil; end
    return math.min(ward.top, ward.base + ward.per * math.max(skill - cap, 0));
end

local function action_events(action, snapshot, now)
    local out, sample = {}, nil;
    local source = sources[action.category];
    if action.category == 3 then source = ability_message[action.rows[1].message] and 'abilities' or 'skills'; end
    local roll = action.category == 6 and catalog.roll(action.id);
    local pet = snapshot.pet;
    local from_pet = pet ~= nil and action.actor == pet.id;
    local function apply(row, effect, rule, action_id)
        if not status(effect) or row.target == 0 then return; end
        -- Capture once in this packet callback, only when a duration needs it.
        if sample==nil and action.actor==snapshot.id then sample=client.sample_modifiers(snapshot); end;
        local entry = event(snapshot, 'apply', row.target, effect, action.actor);
        entry.action_category, entry.spell = action.category, action_id;
        -- The kind of action that put it on, which Only effects from job abilities goes by.
        entry.action_kind = rule;
        if sample then sample.target_self = row.target == snapshot.id; end
        entry.duration, entry.duration_min, entry.basis, entry.metadata = catalog.duration(rule, action_id, effect, sample);
        entry.tier = entry.metadata and entry.metadata.tier;
        -- A pact's Nightmare is tier 4, which a hit ends; only a mob's isn't.
        entry.deep = rule == 'skills' and entry.metadata and entry.metadata.deep or nil;
        -- A length that never changes, as Third Eye's and Seigan's (core/catalog.lua), ends when its time is up.
        entry.exact = entry.metadata and entry.metadata.exact or nil;
        entry.metadata = nil;
        entry.by_pet = from_pet or nil;
        entry.drops = catalog.drops(effect);
        local definition = catalog.get(effect);
        entry.group, entry.category = definition.group, definition.kind;
        if definition.group == 'Songs' and rule == 'spells' and definition.kind ~= 'debuff' then
            entry.stackable, entry.instance_hint = true, tostring(action.actor) .. ':' .. tostring(action_id);
        end
        out[#out + 1] = entry;
        return entry;
    end
    local function remove(row, effect)
        if status(effect) and row.target ~= 0 then
            local entry = event(snapshot, 'remove', row.target, effect);
            entry.reason = 'Observed removal';
            out[#out + 1] = entry;
        end
    end
    -- A party or alliance member's use of a watched ability, for the party cooldown watch. Only players, whose ids are
    -- below 0x1000000, and not you: your own recasts are read from the client. A Wild Card from you or a member also
    -- resets what each member it lands on has, by its roll (the param, corsair.lua useWildCard :920-933).
    local info = (action.category == 6 or action.category == 3) and watched[action.id];
    if info and (info.category or 6) == action.category and (not info.messages or info.messages[action.rows[1].message]) then
        local actor = action.actor;
        if actor ~= snapshot.id and actor < 0x1000000 then
            local entry = event(snapshot, 'cooldown', actor);
            if entry.scope == 'party' or entry.scope == 'alliance' then entry.ability = action.id; out[#out + 1] = entry; end
        end
        if action.id == WILD_CARD and (actor == snapshot.id or out[#out] and out[#out].kind == 'cooldown') then
            for _, row in ipairs(action.rows) do
                if row.target ~= snapshot.id and row.target ~= 0 and row.target < 0x1000000 and row.param >= 1 and row.param <= 6 then
                    local reset = event(snapshot, 'cooldown_reset', row.target);
                    if reset.scope == 'party' or reset.scope == 'alliance' then reset.roll = row.param; out[#out + 1] = reset; end
                end
            end
        end
    end
    -- A roll from you or a party member: its total, whether it was a Double-Up or a bust, and what each target's row
    -- says. Anyone else's roll doesn't reach your party.
    if roll and in_era_rolls[action.id] then
        local entry = event(snapshot, 'roll', action.actor);
        if entry.scope == 'self' or entry.scope == 'party' then
            local targets, results = {}, {};
            for _, row in ipairs(action.rows) do
                local result = roll_results[row.message];
                if result and row.target ~= 0 then
                    targets[#targets + 1], results[#results + 1] = row.target, result;
                    if result ~= 'none' and not entry.total and row.param >= 1 and row.param <= 12 then entry.total = row.param; end
                    if row.target == action.actor then entry.double_up, entry.bust = row.message == 424, result == 'bust'; end
                end
            end
            if entry.total then
                entry.ability, entry.targets, entry.results = action.id, targets, results;
                entry.bust = entry.bust == true or entry.total >= 12;
                out[#out + 1] = entry;
            end
        end
    end
    -- Your Charm that took and your Familiar, with the gear on you then, which can lengthen a charm.
    if action.actor == snapshot.id and action.category == 6 and (action.id == CHARM or action.id == FAMILIAR) then
        for _, row in ipairs(action.rows) do
            if row.target ~= 0 and (action.id == FAMILIAR or row.message == CHARMED) then
                if sample == nil then sample = client.sample_modifiers(snapshot); end
                local entry = event(snapshot, action.id == CHARM and 'charm' or 'familiar', row.target);
                entry.items = sample and sample.items;
                out[#out + 1] = entry;
                break;
            end
        end
    end
    -- A mob, your pet or an alliance member that took damage: the tracker takes off what Phoenix takes off at a hit. A
    -- mob's and a pet's ids start at 0x1000000; the player's and the party's own effects are read from their listings, and
    -- a stranger's aren't followed. It comes before anything the same row puts on, as Phoenix deals the damage first, and
    -- once for each one an action hits, saying whether a hit got through their shadows and whether a melee swing landed.
    local struck;
    local function hit(id, from, through, melee)
        local entry = struck and struck[id];
        if not entry then
            if id < 0x1000000 and not ally(snapshot, id) then return; end
            entry = event(snapshot, 'damage', id, nil, from);
            if entry.scope ~= 'enemy' and entry.scope ~= 'pet' and entry.scope ~= 'alliance' then return; end
            struck = struck or {};
            struck[id], out[#out + 1] = entry, entry;
        end
        if through then entry.through = true; end
        if melee then entry.melee = true; end
    end
    -- Shadows a mob or an alliance member lost.
    local function lost(id, count)
        if count <= 0 or id < 0x1000000 and not ally(snapshot, id) then return; end
        local entry = event(snapshot, 'shadows', id);
        if entry.scope == 'enemy' or entry.scope == 'alliance' then entry.lost = count; out[#out + 1] = entry; end
    end
    -- Whether the actor's Sneak or Trick Attack may still be up, which their next melee round uses.
    local sneak = sneaking[action.actor] == true;
    if action.category == 1 then sneaking[action.actor] = nil; end
    if action.category == 6 and (action.id == SNEAK_ATTACK or action.id == TRICK_ATTACK) then sneaking[action.actor] = true; end
    local landing = not sneak and passed[action.category];
    for _, row in ipairs(action.rows) do
        local message, param = row.message, row.param;
        local hurt = wakes[message] == true and param > 0;
        if not hurt and row.added then hurt = added_wakes[row.added] == true and row.added_param > 0 or skillchain(row.added); end
        if hurt then
            hit(row.target, action.actor, param > 0 and landing and landing[message], action.category == 1 and param > 0 and passed[1][message]);
        end
        -- A mob whose attack was countered took the counter's damage, through any shadows it had.
        if row.reaction == COUNTERED and row.reaction_param > 0 then hit(action.actor, row.target, true); end
        if message == ABSORBED then lost(row.target, param); end
        if row.reaction == COUNTER_ABSORBED then lost(action.actor, row.reaction_param); end
        if message == ANTICIPATED and (row.target >= 0x1000000 or ally(snapshot, row.target)) then
            local entry = event(snapshot, 'anticipated', row.target);
            if entry.scope == 'enemy' or entry.scope == 'alliance' then out[#out + 1] = entry; end
        end
        if roll and (message == 420 or message == 421 or message == 424) then
            -- A Double-Up renews the roll to its full time too (scripts/globals/job_utils/corsair.lua :544-551).
            local entry = apply(row, roll, 'rolls', action.id);
            if entry then
                entry.duration, entry.duration_min = catalog.roll_duration(sample);
                entry.basis = 'Phoenix roll duration; other bonuses may change it';
            end
        elseif roll and (message == 426 or message == 427) then
            remove(row, roll);
            if row.target == action.actor then
                local entry = apply(row, 309, nil, action.id);
                if entry then
                    entry.duration, entry.duration_min = catalog.bust_duration(sample);
                    entry.basis = 'Bust duration depends on merits';
                    entry.action_kind = 'rolls';
                end
            end
        elseif message == 309 and action.category == 4 and raises[action.id] and row.target ~= 0 then
            local entry = event(snapshot, 'raise', row.target, nil, action.actor);
            entry.spell, entry.level = action.id, raises[action.id];
            out[#out + 1] = entry;
        elseif action.category == 13 and several[message] and pets.ward_effects[action.id] then
            for _, effect in ipairs(pets.ward_effects[action.id]) do apply(row, effect, source, action.id); end
        elseif landed[message] or message == 101 and action.category == 11 and row.target == action.actor then
            local entry = apply(row, param, source, action.id);
            if entry and (entry.scope == 'enemy' or entry.scope == 'alliance') and action.category == 4 and param == COPY_IMAGE
                and SHADOWS[action.id] then
                entry.shadows = SHADOWS[action.id] - (action.id == NI and short_of_ni(entry, snapshot) and 1 or 0);
            end
        elseif action.category == 6 and (ability_buffs[message] or message == 100 and row.target == action.actor)
            and status(param) and catalog.get(param).kind == 'buff' then
            apply(row, param, 'abilities', action.id);
        elseif removed[message] then
            remove(row, param);
        elseif damage[message] and action.category == 4 then
            -- Dia and Bio report damage whether or not their effect went on (Phoenix dia.lua, bio.lua), so the
            -- tracker decides from the copies the target holds. One that goes on takes the other off.
            local info = catalog.action('spells', action.id);
            if info and (info.effect == 134 or info.effect == 135) then
                local entry = apply(row, info.effect, source, action.id);
                if entry then entry.inferred, entry.drops = true, { info.effect == 134 and 135 or 134 }; end
            end
        end
        if row.added == 160 or row.added == 164 then apply(row, row.added_param, 'procs', action.category);
        elseif removed[row.added] then remove(row, row.added_param); end
        if row.reaction == 374 and status(row.reaction_param) then
            local entry = event(snapshot, 'apply', action.actor, row.reaction_param, row.target);
            local definition = catalog.get(row.reaction_param);
            entry.category, entry.group = definition.kind, definition.group;
            entry.basis = 'Status spikes reported without a duration';
            out[#out + 1] = entry;
        end
    end
    if from_pet and action.category == 13 then
        local ward, slowga = pets.wards[action.id], action.id == pets.slowga.pact and pets.slowga;
        if ward or slowga then
            -- Your skill is all that counts here. Your gear stays out of what else your pet does.
            local skill = client.sample_modifiers(snapshot).summoning_skill;
            if slowga then
                local seconds = slowga.base + math.max(0, math.min(slowga.most, (skill or 0) - slowga.from));
                for _, entry in ipairs(out) do
                    if entry.kind == 'apply' and entry.spell == action.id then
                        entry.duration, entry.duration_min = seconds, seconds;
                        entry.basis = 'Phoenix\'s length at your summoning skill. A resist can shorten it.';
                    end
                end
            else
                -- A ward's length depends only on you, so your own copy of it, which the server times, is everyone's.
                -- One that took no effect on you left your older copy, and Rolling Thunder reports a gain either way.
                local own = false;
                for _, row in ipairs(action.rows) do
                    if row.target == snapshot.id and ward_gains[row.message] and not ward.always_reports then own = true; end
                end
                local level = snapshot.job == 15 and snapshot.level or snapshot.sub_job == 15 and snapshot.sub_level or nil;
                local seconds = ward_seconds(ward, skill, level);
                for _, entry in ipairs(out) do
                    if entry.kind == 'apply' and entry.spell == action.id and entry.entity_id ~= snapshot.id then
                        entry.duration, entry.duration_min, entry.exact = seconds, seconds, (seconds or own) and true or nil;
                        if own then
                            entry.timing, entry.follow, entry.follow_spell, entry.basis = 'follow', entry.effect, action.id, FOLLOWS;
                        elseif seconds then
                            entry.timing = 'fixed';
                            entry.basis = 'Phoenix\'s length for ' .. ward.name .. ' at your summoning skill. It ends sooner only if it\'s taken off.';
                        end
                    end
                end
                local note = event(snapshot, 'ward', snapshot.id);
                note.pact, note.name, note.skill, note.level, note.seconds, note.own = action.id, ward.name, skill, level, seconds, own;
                out[#out + 1] = note;
            end
        end
    end
    -- Your job abilities on your pet. What they cure goes first, as Phoenix takes it off before it puts anything on.
    local own = pet and action.category == 6 and action.actor == snapshot.id and pets.own[action.id];
    local target;
    for _, row in ipairs(own and action.rows or NONE) do
        if row.target == (own.on_you and snapshot.id or pet.id) then target = row; break; end
    end
    if target then
        if sample == nil then sample = client.sample_modifiers(snapshot); end
        local function cure(list, count)
            local entry = event(snapshot, 'cure', pet.id);
            entry.effects, entry.count = list, count;
            out[#out + 1] = entry;
        end
        if own.repair then
            local count = 0;
            for _, item in pairs(sample.items) do count = count + (own.repair_gear[item] or 0); end
            if count > 0 then cure(own.repair, count); end
        end
        if own.cures then cure(own.cures); end
        if own.coats and own.coats[sample.items[5]] then cure(own.coats[sample.items[5]]); end
        local entry = own.effect and apply({ target = pet.id }, own.effect, 'abilities', action.id);
        if entry then
            local seconds = own.seconds or own.oils and own.oils[sample.items[3] or snapshot.ammo];
            entry.duration, entry.duration_min, entry.exact = seconds, seconds, true;
            if own.follows then
                entry.timing, entry.follow, entry.basis = 'follow', own.effect, FOLLOWS;
            elseif seconds then
                entry.timing = 'fixed';
                entry.basis = 'Phoenix\'s fixed length for your ' .. own.name .. '. It ends sooner only if the pet loses it.';
            end
        end
        -- Empathy copies your effects as they are at the link, so each keeps the end it has now and never moves with
        -- yours. Its merit needs DRG main at 75 (src/map/merit.cpp :366-367).
        local ranks = own.empathy and snapshot.job == 14 and (snapshot.level or 0) >= 75 and sample.merits[own.empathy] or 0;
        if ranks > 0 then
            local flagged = {};
            for _, held in ipairs(snapshot.self_effects or NONE) do
                if EMPATHY[held.effect] then flagged[#flagged + 1] = held; end
            end
            for _, held in ipairs(#flagged <= ranks and flagged or NONE) do
                local copied = apply({ target = pet.id }, held.effect, 'abilities', action.id);
                local left = copied and held.deadline and held.deadline - now;
                if left and left > 0 then
                    copied.duration, copied.duration_min, copied.exact, copied.timing = left, left, true, 'fixed';
                    copied.basis = 'Copied from you by Spirit Link, with the time yours had left. It ends sooner only if the pet loses it.';
                end
            end
        end
    end
    -- Your maneuver: the chance of overload it reports, and an overload's copy on the automaton.
    if action.category == 6 and action.actor == snapshot.id and pets.maneuvers[action.id] then
        for _, row in ipairs(action.rows) do
            if row.message == CHANCE or row.message == OVERLOADED then
                local entry = event(snapshot, 'maneuver', snapshot.id);
                entry.maneuver, entry.percent = pets.maneuvers[action.id], row.param;
                out[#out + 1] = entry;
                local copy = row.message == OVERLOADED and pet and apply({ target = pet.id }, pets.overload, 'abilities', action.id);
                if copy then
                    -- Phoenix reports the chance as the burden over the limit plus 5, and the overload lasts that burden
                    -- in seconds (src/map/entities/automaton_entity.cpp addBurden, overloadChance), so the chance less 5
                    -- is its length.
                    local seconds = row.param > 5 and row.param - 5 or nil;
                    copy.duration, copy.duration_min, copy.exact = seconds, seconds, true;
                    copy.timing, copy.follow, copy.basis = 'follow', pets.overload, FOLLOWS;
                end
                break;
            end
        end
    end
    -- Your Call Beast, with the jug it took from your ammo slot, for the pet display's clock.
    if action.category == 6 and action.actor == snapshot.id and action.id == pets.call_beast then
        if sample == nil then sample = client.sample_modifiers(snapshot); end
        local entry = event(snapshot, 'call_beast', snapshot.id);
        entry.item = sample.items[3] or snapshot.ammo;
        out[#out + 1] = entry;
    end
    return out;
end

function observer.interested(id)
    return packets[id] == true;
end

-- A self application or removal carries the 0x063 count at its packet's arrival, so the tracker can tell a
-- listing read after a later 0x063 already shows it, and a wear-off sent with a recast from one sent with
-- the status packets of an expiry. Anyone else's carries the 0x076 count: a listing that came before it
-- (another member's tick sends everyone's icons) can't show it yet.
local function stamp(out, snapshot)
    local count, listing = client.self_timer_revision(), client.party_revision();
    for _, entry in ipairs(out) do
        if entry.kind == 'apply' or entry.kind == 'remove' then
            if entry.entity_id == snapshot.id then entry.timer_revision = count;
            else entry.party_revision = listing; end
        end
    end
    return out;
end

-- Ashita hands it userdata, the tests a table. size and data are the packet's, when the caller has read them already.
-- A packet with nothing to report gives NONE, which callers only read.
function observer.read(e, now, snapshot, size, data)
    local kind = type(e);
    if kind ~= 'userdata' and kind ~= 'table' or e.injected == true or e.blocked == true then return NONE; end
    if size == nil then size, data = client.packet_size(e); end
    local id = e.id;
    client.accept(e, now, snapshot, size, data);
    if id == 0x00A and size >= 50 then
        sneaking = {};
        return { { kind = 'reset', reason = 'Zone changed' } };
    end
    if not snapshot or not snapshot.valid then return NONE; end
    if id == 0x028 then
        local action = observer.decode(e, size);
        if action then return stamp(action_events(action, snapshot, now), snapshot); end
    elseif id == 0x029 and size >= 26 then
        local actor, target, param, message = u32(data, 4), u32(data, 8), u32(data, 12), bit.band(u16(data, 24), 0x7FFF);
        if target == 0 then return NONE; end
        if (message == 204 or message == 206) and status(param) then
            local entry = event(snapshot, 'remove', target, param, actor);
            -- Wearoff identifies the origin for other entities. On self the icon snapshot resolves duplicates.
            if actor == target then entry.source, entry.source_name = nil, nil; end
            entry.reason = observer.wear_off;
            return stamp({ entry }, snapshot);
        elseif message == 205 and status(param) then
            -- An entity's own message (an item used on yourself, Phoenix messageBasic) names it as the caster.
            local entry = event(snapshot, 'apply', target, param, actor == target and actor or nil);
            -- No action names a spell for it, so the tracker knows it by its message.
            entry.basis, entry.message = 'Status reported without a duration', message;
            return stamp({ entry }, snapshot);
        elseif message >= 170 and message <= 178 and actor == snapshot.id and target >= 0x1000000 and param >= 1 and param <= 255 then
            -- Your /check of a mob gives its level (src/map/packets/c2s/0x0dd_equip_inspect.cpp :97, :133; 174 and the
            -- messages either side, src/map/enums/msg_basic.h :118), for the charm estimate.
            local entry = event(snapshot, 'check', target);
            entry.level = param;
            return { entry };
        elseif message == 6 or message == 20 or message == 97 then
            -- 97 is a player defeated by the actor (Phoenix CCharEntity::Die), 20 one with no attacker.
            local entry = event(snapshot, 'death', target, nil, actor); entry.reason = 'Observed defeat';
            return { entry };
        end
    elseif id == 0x00E and size >= 11 and bit.band(data:byte(11), 0x20) ~= 0 then
        local target = u32(data, 4);
        if target > 0 then
            local entry = event(snapshot, 'despawn', target); entry.reason = 'Entity left view'; return { entry };
        end
    elseif id == 0x068 and size >= 0x0E and u32(data, 8) == snapshot.id and u16(data, 0x0C) == 0 then
        -- The server says your pet has gone.
        return { { kind = 'pet_gone' } };
    end
    return NONE;
end

return observer;
