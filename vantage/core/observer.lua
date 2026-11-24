-- Turns complete incoming outcomes into observations. It never requests state.
local observer = {};
local client = require('core.client');
local catalog = require('core.catalog');
local bit = require('bit');
local packets = { [0x00A]=true, [0x00B]=true, [0x00E]=true, [0x028]=true, [0x029]=true, [0x037]=true, [0x044]=true, [0x063]=true,
    [0x068]=true, [0x076]=true, [0x08C]=true };
local wanted = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [11] = true, [13] = true };
-- A move being readied (7) and a spell being cast (8) are read only from your own pet, for the pet display. own_pet is
-- its id while a 0x028 is decoded. What your pet finishes that the display names: a ranged attack, a weapon skill, a
-- spell, a monster skill and a pet ability. A start's action id is a four letter code (src/map/enums/four_cc.h
-- :28-53): its low half is "ca" as a move or a spell of any kind begins and "sp", STOPPED, as it is stopped.
local starts = { [7] = true, [8] = true };
local finishes = { [2] = true, [3] = true, [4] = true, [11] = true, [13] = true };
local STOPPED = 0x7073;
local own_pet;
local sources = { [4] = 'spells', [6] = 'abilities', [11] = 'skills', [13] = 'pacts' };
-- Absorb-STR to Absorb-CHR that took say so with 329 to 335 and name the Down they put on (Phoenix
-- globals/spells/absorb_spell.lua :70, :79).
local landed = { [127] = true, [186] = true, [230] = true, [236] = true, [237] = true, [242] = true,
    [243] = true, [266] = true, [267] = true, [268] = true, [271] = true, [277] = true, [278] = true,
    [319] = true, [320] = true, [329] = true, [330] = true, [331] = true, [332] = true, [333] = true,
    [334] = true, [335] = true };
local ability_message = { [127] = true, [277] = true, [319] = true, [320] = true };
-- Job abilities name the buff they give in the param (Phoenix CCharEntity::OnAbility). These messages say
-- the target gained it: Berserk and Last Resort, Warcry and Boost, Defender, Aggressor, Focus, Dodge, the
-- circles on their user and on others, Warcry on a party member, Mantra on its user and on others, and Flee (126,
-- which Chocobo Jig sends too, but it came after Phoenix's era, sql/abilities.sql :62, :216, :389). One
-- with no message of its own and one target is sent as 'uses' (100), which only counts for a buff on its user.
-- One that reaches everyone around its user keeps 0 on every row (src/map/entities/char_entity.cpp :2038-2075,
-- :2099-2101). That counts on its user's row, and on the others' only for one that puts itself on each of them
-- (core/catalog.lua).
local ability_buffs = { [115] = true, [116] = true, [117] = true, [118] = true, [120] = true, [121] = true,
    [131] = true, [134] = true, [148] = true, [150] = true, [149] = true, [151] = true, [285] = true,
    [286] = true, [287] = true, [421] = true, [441] = true, [126] = true };
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
-- (CBattleEntity::takeDamage, battleutils.cpp :928, :966, :973, :1068, :1121).
local COUNTERED = 33;
-- On every path above, Phoenix takes Stoneskin's share out of the damage before the damage is shown (battleutils.cpp
-- HandleStoneskin :4719, utils.handleStoneskin in utils/combat_utils.lua :243), so a hit for more than 0 says a Stoneskin
-- had none left. Two kinds of hit say nothing about it. Weapon Bash, ability 77, deals its damage straight to HP
-- (globals/job_utils/dark_knight.lua :144), and an absorbed skillchain heals the mob (modules/era/lua/combat/skillchain.lua
-- :110-121).
local WEAPON_BASH = 77;
-- Spikes from a spell, a roll or a mob's script show what's left of their damage after the attacker's Stoneskin took its
-- share, message 44 in the reaction slot, or 132 when Dread Spikes drains it (battleutils.cpp HandleSpikesDamage
-- :895-919, :962, src/map/enums/msg_basic.h :69, :104), so spike damage says a Stoneskin is gone, as a hit does. Spikes
-- from gear show the item's number from before Stoneskin (:1018, HandleSpikesEquip :1105-1119). Only a player's gear has
-- them, and only while no spikes effect is on the player (:895, :1000-1002). So spikes on a mob or a pet count, and on
-- you or a party member only while the listing shows Blaze, Ice or Shock Spikes (34, 35, 38), Dread Spikes (173) or
-- Gallant's Roll (316), which has spikes in Phoenix's era (modules/era/lua/globals/job_utils/corsair.lua :241-255).
local SPIKES = { [44] = true, [132] = true };
local SPIKE_EFFECTS = { [34] = true, [35] = true, [38] = true, [173] = true, [316] = true };
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
-- weaponskills.lua :677), until the user's next melee round drops both (battle_entity.cpp :3965-3969). A mob's or an
-- alliance member's Blink is counted too. It gives 2 (globals/spells/enhancing_spell.lua :70), or 4 from Zephyr Mantle
-- (actions/spells/blue/zephyr_mantle.lua :24), and goes with the last one the same way (battleutils.cpp :3142-3143),
-- but a fifth of hits get past it (:3106-3114), so one that lands says nothing of it.
local COPY_IMAGE, SHADOWS, NI, NINJA = 66, { [53] = 2, [338] = 3, [339] = 4, [340] = 5, [647] = 4 }, 339, 13;
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
-- The two-hours, key job abilities and spells the party cooldown watch counts (data/party_cooldowns.lua). A job ability
-- finishes as category 6 with its ability id (Phoenix CCharEntity::OnAbility, char_entity.cpp :2014-2016); one with
-- its own category names it there, with the messages that tell it from what else has its id. A spell finishes as
-- category 4 with its spell id and the recast the game gave it. One stopped by Paralysis (84) or Intimidate (106) also
-- sends 2 seconds, which the game never puts on the caster (src/map/action/interrupts.cpp :299-370,
-- src/map/ai/states/magic_state.cpp :264-289), so it isn't a cast.
local watched = require('core.party_cooldowns').WATCHED;
local watched_spells = require('core.party_cooldowns').SPELLS;
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
-- The action a decode hands back, its list of results and the rows they are read into, made once and filled again by
-- each decode. observer.read reads them within the packet's callback and keeps none of them.
local decoded, result_rows = { rows = {} }, {};

-- Bounds are checked before every native read. Nothing is emitted from a partial action.
-- 0x028 is read by bit: actor at 40, target count at 72, category at 82, action id at 86, recast at 118, first target
-- at 150. A target is a 32 bit id and a 4 bit result count. A result is 85 bits, param at +27 and message at +44, then
-- an added effect block of 37 bits and a reaction block of 34, each behind a 1 bit flag. The recast is in seconds and
-- only a finished spell sends one (src/map/packets/s2c/0x028_battle2.cpp :40-46, src/map/action/action.cpp :103-107).
local function decode_action(total)
    local category = read(82, 4);
    if not wanted[category] and not (starts[category] and own_pet and read(40, 32) == own_pet) then return nil; end
    local count = read(72, 6);
    if count < 1 or count > 15 then return nil; end
    local action, used = decoded, 0;
    for i = #action.rows, 1, -1 do action.rows[i] = nil; end
    action.actor, action.id, action.category, action.recast = read(40, 32), read(86, 32), category, nil;
    if category == 4 then action.recast = read(118, 32); end
    local at = 150;
    for _ = 1, count do
        if at + 36 > total then return nil; end
        local target, results = read(at, 32), read(at + 32, 4);
        if results < 1 or results > 8 then return nil; end
        at = at + 36;
        for _ = 1, results do
            local start = at;
            if at + 86 > total then return nil; end
            used = used + 1;
            local row = result_rows[used];
            if not row then row = {}; result_rows[used] = row; end
            row.target, row.param, row.message = target, read(start + 27, 17), read(start + 44, 10);
            -- What the last packet read into this row, which this one may not have.
            row.added, row.added_param, row.reaction_param, row.reaction, row.reaction_kind = nil, nil, nil, nil, nil;
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
                row.reaction_param, row.reaction, row.reaction_kind = read(at + 10, 14), read(at + 24, 10), read(at, 6);
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

-- Whether your listing, or a party member's, shows a spikes effect on them.
local function spiked(snapshot, id)
    local effects = id == snapshot.id and snapshot.self_effects;
    if not effects then
        for _, member in ipairs(snapshot.party or NONE) do
            if member.id == id then effects = member.effects; break; end
        end
    end
    for _, status in ipairs(effects or NONE) do
        if SPIKE_EFFECTS[status.effect] then return true; end
    end
    return false;
end

-- A status the game never reports. A player's weapon skill, a pet's move and a few spells, abilities, pacts and items
-- put a status on a monster with no word of it: the server sends the action's own result and nothing else (Phoenix
-- scripts/globals/weaponskills.lua handleWeaponskillEffect :1108-1118 is a bare addStatusEffect). data/effects.lua says
-- what each such action may put on and by what in its result (infer): 'damage' is a hit for more than 0, 'success' one
-- of the row's messages. A resist or an immune monster looks the same, so each is a guess (guessed), which the tracker
-- never lets renew what a monster already shows or go on over what keeps it off (core/tracker.lua refused).
-- The table a player's action is looked up in, by its category.
local GUESS_KINDS = { [4] = 'spells', [5] = 'items', [6] = 'abilities', [13] = 'pacts' };
-- The job that has each merit two of them need, by the name the data gives the merit (Phoenix data/merits.yaml
-- :454, :510).
local MERIT_JOBS = { tomahawk = 1, penance = 2 };
-- A melee swing that connects.
local CONNECTS = { [1] = true, [67] = true, [352] = true, [353] = true };
-- A player's finishing move with one of these messages is a job ability, as Jump and Shield Bash are, and any other a
-- weapon skill: the two that say an ability did damage (Phoenix src/map/enums/msg_basic.h :101, :182) beside the ones
-- that name its effect, and the one that says only that an ability was used (:96), which an ability with no message of
-- its own gets (src/map/entities/char_entity.cpp :2099-2102), as Tomahawk does. A weapon skill's id can be an ability's
-- too.
local ABILITY_RESULT = { [100] = true, [110] = true, [317] = true };
-- Who has an effect that goes on with their next melee hit, as Feint does (data/effects.lua reactive), and until when.
local armed, armed_count = {}, 0;

-- Whether your own listing shows an effect, or with id another player's. A party member's is read as spiked() reads it,
-- once core/client.lua has one for them (valid). With no listing to read, as for a stranger or an alliance member, it is
-- taken as there.
local function holds(snapshot, effect, id)
    local effects;
    if id == nil or id == snapshot.id then
        effects = snapshot.self_known and (snapshot.self_effects or NONE);
    else
        for _, member in ipairs(snapshot.party or NONE) do
            if member.id == id then effects = member.valid and member.effects; break; end
        end
    end
    if not effects then return true; end
    for _, status in ipairs(effects) do
        if status.effect == effect then return true; end
    end
    return false;
end

-- Whether your automaton has an attachment on, by the byte the 0x044 gives for it (core/client.lua). With none read yet,
-- it is taken as there.
local function fitted(snapshot, attachment)
    local parts = snapshot.pet and snapshot.pet.automaton and snapshot.pet.automaton.attachments;
    if not parts then return true; end
    for _, part in ipairs(parts) do
        if part == attachment then return true; end
    end
    return false;
end

-- The two forms of a drain's result that the damage list above leaves out: a draining spell's magic burst, and a
-- draining move on its targets after the first (Phoenix src/map/spell.cpp :218, src/map/utils/messageutils.h :42).
local DRAINED = { [274] = true, [281] = true };

-- Whether a result says the action's unreported status went on.
local function unsaid(info, row)
    if info.infer == 'damage' then return (wakes[row.message] == true or DRAINED[row.message] == true) and row.param > 0; end
    if info.infer == 'success' then
        for _, message in ipairs(info.success_messages or NONE) do
            if row.message == message then return true; end
        end
    end
    return false;
end

-- What a guess needs that can be checked: the user's own effect for their action, your merit for yours, and your effect
-- for your pet's, with the Hammermill your automaton needs to slow with Shield Bash.
local function may(info, snapshot, action, my_pet)
    local mine = action.actor == snapshot.id;
    if info.requires_effect and not holds(snapshot, info.requires_effect, action.actor) then return false; end
    if mine and info.requires_merit then
        local rule, job = catalog.kind('merits')[info.requires_merit], MERIT_JOBS[info.requires_merit];
        local on, level = snapshot.job, snapshot.level;
        local read = type(on) == 'number' and on > 0 and type(level) == 'number' and level > 0;
        -- A merit does nothing on another job or under level 75. With your job or level not read, it is taken as there.
        if rule and job and read and (on ~= job or level < 75 or client.merit(rule.id) == 0) then return false; end
    end
    if my_pet and info.requires_owner_effect and not holds(snapshot, info.requires_owner_effect) then return false; end
    local auto = pets.automaton;
    if my_pet and action.id == auto.bash_skill and info.effect == auto.bash_slow.effect and not fitted(snapshot, auto.bash_slow.hammermill) then
        return false;
    end
    return true;
end

-- The table that says what an action may put on with no word of it, or nil. A player's finishing move that isn't an
-- ability is a weapon skill. A monster counts only as someone's pet: one the game made for its owner (its id ends
-- 0x800 or over) has the automatons' and the jug pets' moves, and any owned one a charmed monster's.
local function guess_kind(action, from_pet, now)
    local actor, category = action.actor, action.category;
    if actor < 0x1000000 then
        if category == 3 then
            local message = action.rows[1].message;
            return (ability_message[message] or ABILITY_RESULT[message]) and 'abilities' or 'weaponskills';
        end
        return GUESS_KINDS[category];
    end
    if category == 13 then return 'pacts'; end
    if category ~= 3 and category ~= 11 then return nil; end
    local made = actor % 0x1000 >= 0x800;
    local kind = made and (catalog.action('automatons', action.id) and 'automatons' or catalog.action('pet_moves', action.id) and 'pet_moves')
        or catalog.action('charmed_skills', action.id) and 'charmed_skills' or nil;
    if kind and (from_pet or client.pet_owner(actor, now)) then return kind; end
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

-- What the action_events call under way is reading, for the helpers below, so a call makes no closure: the action, the
-- snapshot, whether your pet did it, what it found (out), each unit it hit (struck) and your gear and merits, sampled once
-- for it when a time needs them (sample). out and struck are made once and emptied at the start of each call. out is the
-- list observer.read hands back for an action, so a caller reads it before the next packet and keeps only its entries.
local reading = { out = {}, struck = {} };
function reading.apply(row, effect, rule, action_id)
    if not status(effect) or row.target == 0 then return; end
    local action, snapshot, out = reading.action, reading.snapshot, reading.out;
    -- Capture once in this packet callback, only when a duration needs it.
    if reading.sample==nil and action.actor==snapshot.id then reading.sample=client.sample_modifiers(snapshot); end;
    local sample = reading.sample;
    local entry = event(snapshot, 'apply', row.target, effect, action.actor);
    entry.action_category, entry.spell = action.category, action_id;
    -- The kind of action that put it on, which Only effects from job abilities goes by.
    entry.action_kind = rule;
    if sample then sample.target_self = row.target == snapshot.id; end
    entry.duration, entry.duration_min, entry.basis, entry.metadata = catalog.duration(rule, action_id, effect, sample);
    -- Another player's song counts the range their instrument can give (core/catalog.lua). A monster's is its base.
    if rule == 'spells' and action.actor ~= snapshot.id and action.actor < 0x1000000 and entry.duration then
        local upper, lower, basis = catalog.song_range(action_id, action.actor, snapshot, entry.duration);
        if upper then entry.duration, entry.duration_min, entry.basis = upper, lower, basis; end
    end
    entry.tier = entry.metadata and entry.metadata.tier;
    -- A pact's Nightmare is tier 4, which a hit ends. Only a mob's isn't.
    entry.deep = rule == 'skills' and entry.metadata and entry.metadata.deep or nil;
    -- A length that never changes, as Third Eye's and Seigan's (core/catalog.lua), ends when its time is up.
    entry.exact = entry.metadata and entry.metadata.exact or nil;
    entry.metadata = nil;
    entry.by_pet = reading.from_pet or nil;
    entry.drops = catalog.drops(effect);
    local definition = catalog.get(effect);
    entry.group, entry.category = definition.group, definition.kind;
    if definition.group == 'Songs' and rule == 'spells' and definition.kind ~= 'debuff' then
        entry.stackable, entry.instance_hint = true, tostring(action.actor) .. ':' .. tostring(action_id);
    end
    out[#out + 1] = entry;
    return entry;
end
function reading.remove(row, effect)
    if status(effect) and row.target ~= 0 then
        local entry = event(reading.snapshot, 'remove', row.target, effect);
        entry.reason = 'Observed removal';
        local out = reading.out;
        out[#out + 1] = entry;
    end
end
-- A status taken as put on a monster with no word of it (see GUESS_KINDS above), by actor. Its time is the action's
-- own, with your merits and gear in it for an action of yours, as for one the game reports.
function reading.possible(target, effect, rule, id, actor)
    if target < 0x1000000 or not status(effect) then return; end
    local action, snapshot, out = reading.action, reading.snapshot, reading.out;
    local own = actor == snapshot.id and actor == action.actor;
    if own and reading.sample == nil then reading.sample = client.sample_modifiers(snapshot); end
    local entry = event(snapshot, 'apply', target, effect, actor);
    entry.action_category, entry.spell, entry.action_kind, entry.guessed = action.category, id, rule, true;
    entry.duration, entry.duration_min = catalog.duration(rule, id, effect, own and reading.sample or nil);
    entry.basis = 'Taken from what the action did. The game sends no word of this effect, so a resist looks the same.';
    entry.by_pet = actor == action.actor and reading.from_pet or nil;
    entry.drops = catalog.drops(effect);
    local definition = catalog.get(effect);
    entry.group, entry.category = definition.group, definition.kind;
    out[#out + 1] = entry;
end
-- A mob, your pet or an alliance member that took damage: the tracker takes off what Phoenix takes off at a hit. A
-- mob's and a pet's ids start at 0x1000000. The player's and the party's own effects are read from their listings, and
-- a stranger's aren't followed. It comes before anything the same row puts on, as Phoenix deals the damage first, and
-- once for each one an action hits, saying whether a hit got through their shadows, whether a melee swing landed,
-- whether damage that Stoneskin soaks first got through and whether spikes were all that hurt it.
function reading.hit(id, from, through, melee, unsoaked, spikes)
    local struck = reading.struck;
    local entry = struck[id];
    if not entry then
        local snapshot, out = reading.snapshot, reading.out;
        if id < 0x1000000 and not ally(snapshot, id) then return; end
        entry = event(snapshot, 'damage', id, nil, from);
        if entry.scope ~= 'enemy' and entry.scope ~= 'pet' and entry.scope ~= 'alliance' then return; end
        struck[id], out[#out + 1] = entry, entry;
        entry.spikes_only = spikes or nil;
    elseif not spikes then
        entry.spikes_only = nil;
    end
    if through then entry.through = true; end
    if melee then entry.melee = true; end
    if unsoaked then entry.unsoaked = true; end
end
-- Shadows a mob or an alliance member lost.
function reading.lost(id, count)
    local snapshot, out = reading.snapshot, reading.out;
    if count <= 0 or id < 0x1000000 and not ally(snapshot, id) then return; end
    local entry = event(snapshot, 'shadows', id);
    if entry.scope == 'enemy' or entry.scope == 'alliance' then entry.lost = count; out[#out + 1] = entry; end
end
-- A monster's move that takes every erasable effect off its user, or off each mob Benediction reaches (core/catalog.lua).
-- Phoenix sends each one's wear-off only to whoever put it on (status_effect_container.cpp :657-669), so the move is all
-- that says a party member's has gone.
function reading.erase_all(action, snapshot)
    local reach, effects = catalog.erases_all(action.id);
    if not reach then return; end
    local out = reading.out;
    for i = 1, reach == 'targets' and #action.rows or 1 do
        local entry = event(snapshot, 'cure', reach == 'targets' and action.rows[i].target or action.actor);
        entry.effects, entry.reason = effects, 'A monster\'s move took it off.';
        out[#out + 1] = entry;
    end
end

local function action_events(action, snapshot, now)
    local out, struck = reading.out, reading.struck;
    for i = #out, 1, -1 do out[i] = nil; end
    for id in pairs(struck) do struck[id] = nil; end
    local apply, remove, possible, hit, lost = reading.apply, reading.remove, reading.possible, reading.hit, reading.lost;
    local source = sources[action.category];
    if action.category == 3 then source = ability_message[action.rows[1].message] and 'abilities' or 'skills'; end
    local roll = action.category == 6 and catalog.roll(action.id);
    local pet = snapshot.pet;
    local from_pet = pet ~= nil and action.actor == pet.id;
    reading.action, reading.snapshot, reading.from_pet, reading.sample = action, snapshot, from_pet, nil;
    -- What your pet starts and finishes, for the pet display. A start names the move or spell in its first result, and
    -- its own id says whether it began or was stopped (src/map/ai/states/magic_state.cpp, mobskill_state.cpp,
    -- src/map/action/interrupts.cpp). Nothing else is learned from a start.
    if from_pet then
        local first = action.rows[1];
        if starts[action.category] then
            return { { kind = 'pet_start', entity_id = pet.id, category = action.category, id = first.param, target = first.target,
                stopped = action.id % 0x10000 == STOPPED or nil, message = first.message } };
        elseif action.category == 4 and (action.id == 0 or first.message == 84 or first.message == 106) then
            -- What failed comes as category 4 too, so it isn't taken for a finish: a swing, a pact, a breath or a move with
            -- no action id (Paralysis 84, Intimidate 106, out of reach 328 or 78, no target in its area 76), and a spell
            -- with its id and 84 or 106 (src/map/action/interrupts.cpp :39-128, :193-233, :299-422). It ends what the
            -- pet was readying, as a move that failed for range sends no stop of its own
            -- (src/map/ai/states/mobskill_state.cpp :244-256).
            out[#out + 1] = { kind = 'pet_start', entity_id = pet.id, category = action.category, stopped = true };
        elseif finishes[action.category] then
            out[#out + 1] = { kind = 'pet_action', entity_id = pet.id, category = action.category, id = action.id, target = first.target,
                amount = damage[first.message] and first.param or nil, message = first.message };
        end
    end
    -- A party or alliance member's use of a watched ability, for the party cooldown watch. Only players, whose ids are
    -- below 0x1000000, and not you: your own recasts are read from the client. A Wild Card from you or a member also
    -- resets what each member it lands on has, by its roll (the param, corsair.lua useWildCard :920-933).
    local info = (action.category == 6 or action.category == 3) and watched[action.id];
    local spell = action.category == 4 and watched_spells[action.id];
    if spell and action.rows[1].message ~= 84 and action.rows[1].message ~= 106 then
        local actor = action.actor;
        if actor ~= snapshot.id and actor < 0x1000000 then
            local entry = event(snapshot, 'cooldown', actor);
            if entry.scope == 'party' or entry.scope == 'alliance' then entry.ability, entry.recast = spell.id, action.recast; out[#out + 1] = entry; end
        end
    end
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
    -- A member's Dismiss or Deactivate with the pet at full HP resets their Call Wyvern or Activate (data/pets.lua). Only
    -- the pet's HP percent as the client has it says so, and Phoenix rounds that down, so 100 is full. With it unread, the
    -- estimate stays.
    local resets = action.category == 6 and action.actor ~= snapshot.id and action.actor < 0x1000000 and pets.full_hp_resets[action.id];
    if resets then
        local entry = event(snapshot, 'cooldown_reset', action.actor);
        if (entry.scope == 'party' or entry.scope == 'alliance') and client.member_pet_hpp(snapshot, action.actor) == 100 then
            entry.ability = resets;
            out[#out + 1] = entry;
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
                if reading.sample == nil then reading.sample = client.sample_modifiers(snapshot); end
                local entry = event(snapshot, action.id == CHARM and 'charm' or 'familiar', row.target);
                entry.items = reading.sample and reading.sample.items;
                out[#out + 1] = entry;
                break;
            end
        end
    end
    -- A monster's move that takes every erasable effect off, before what it puts on.
    if action.category == 11 and action.actor >= 0x1000000 then reading.erase_all(action, snapshot); end
    -- Whether the actor's Sneak or Trick Attack may still be up, which their next melee round uses.
    local sneak = sneaking[action.actor] == true;
    if action.category == 1 then sneaking[action.actor] = nil; end
    if action.category == 6 and (action.id == SNEAK_ATTACK or action.id == TRICK_ATTACK) then sneaking[action.actor] = true; end
    local landing = not sneak and passed[action.category];
    for _, row in ipairs(action.rows) do
        local message, param = row.message, row.param;
        local hurt = wakes[message] == true and param > 0;
        -- Damage that went through Stoneskin first: the row's, unless it's Weapon Bash, added damage, or a skillchain the mob
        -- didn't absorb.
        local unsoaked = hurt and not (action.category == 6 and action.id == WEAPON_BASH)
            or row.added and row.added_param > 0 and (added_wakes[row.added] == true or row.added >= 288 and row.added <= 303);
        if not hurt and row.added then hurt = added_wakes[row.added] == true and row.added_param > 0 or skillchain(row.added); end
        if hurt then
            hit(row.target, action.actor, param > 0 and landing and landing[message], action.category == 1 and param > 0 and passed[1][message],
                unsoaked);
        end
        -- A mob whose attack was countered took the counter's damage, through any shadows it had. Stoneskin soaks it
        -- first, as it does a swing.
        if row.reaction == COUNTERED and row.reaction_param > 0 then hit(action.actor, row.target, true, nil, true); end
        -- An attacker that spikes hurt after its Stoneskin took its share.
        if SPIKES[row.reaction] and row.reaction_param > 0 and (row.target >= 0x1000000 or spiked(snapshot, row.target)) then
            hit(action.actor, row.target, nil, nil, true, true);
        end
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
                entry.duration, entry.duration_min = catalog.roll_duration(reading.sample);
                entry.basis = 'Phoenix roll duration; other bonuses may change it';
                -- An alliance member has no listing to read, so their rows go by how many of one Corsair's rolls Phoenix
                -- keeps on them (core/tracker.lua): 2 for a COR main and 1 for a COR sub. A Corsair the client has no job
                -- for counts as a COR main.
                if entry.scope == 'alliance' then entry.roll_cap = (client.member_job(snapshot, action.actor) or 17) == 17 and 2 or 1; end
            end
        elseif roll and (message == 426 or message == 427) then
            remove(row, roll);
            if row.target == action.actor then
                local entry = apply(row, 309, nil, action.id);
                if entry then
                    entry.duration, entry.duration_min = catalog.bust_duration(reading.sample);
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
        elseif landed[message] or message == 101 and action.category == 11 and row.target == action.actor
            -- Reraise, Reraise II and Reraise III have no message of their own, so they finish with 0 and name the Reraise
            -- they put on (sql/spell_list.sql :304, :310, :311, actions/spells/white/reraise.lua). One weaker than the
            -- Reraise already on says the same and changes nothing, which can't be told apart.
            or message == 0 and action.category == 4 and param > 0 and (catalog.action(source, action.id) or NONE).effect == param then
            -- A move whose result names another status than it put on shows as the one it put on (core/catalog.lua).
            local entry = apply(row, catalog.applied(source, action.id, param), source, action.id);
            -- Blink names 36.
            if entry and (entry.scope == 'enemy' or entry.scope == 'alliance') and action.category == 4 and (param == COPY_IMAGE or param == 36)
                and SHADOWS[action.id] then
                entry.shadows = SHADOWS[action.id] - (action.id == NI and short_of_ni(entry, snapshot) and 1 or 0);
            end
            -- Another player's own copy of a blue magic buff cast under Diffusion lasts longer by their merits, which
            -- Vantage can't read (core/catalog.lua), so it gets no time. Yours goes by the game's timer.
            if entry and row.target == action.actor and action.actor ~= snapshot.id and catalog.diffused(action, snapshot) then
                entry.duration, entry.duration_min, entry.basis = nil, nil, 'No duration for this action';
            end
            -- Nightmare's sleep comes with a Bio of its own (data/pets.lua), which takes the place of a Bio row and drops a
            -- Dia, as any Bio does. At tier 11 it keeps out every Dia and Bio cast after it (core/tracker.lua).
            local bio = entry and action.category == 13 and action.id == pets.nightmare.pact
                and apply(row, pets.nightmare.effect, source, action.id);
            if bio then
                bio.duration, bio.duration_min, bio.tier = entry.duration, entry.duration_min, pets.nightmare.tier;
                bio.basis = 'Nightmare put it on with its sleep, for the same time. A hit that ends the sleep leaves it on, and no Dia or Bio goes on over it.';
            end
        elseif action.category == 6 and (ability_buffs[message] or (message == 100 or message == 0) and row.target == action.actor
            or message == 0 and (catalog.action(source, action.id) or NONE).everyone) and status(param) and catalog.get(param).kind == 'buff' then
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
        -- Spikes that hurt the monster that hit them may put their status on it too, with no word of it: Ice Spikes'
        -- Paralysis, by the kind of spikes the reaction names. It is the spiked player's.
        local spikes = row.reaction and (SPIKES[row.reaction] or row.reaction == 383) and row.target < 0x1000000
            and catalog.action('spikes', row.reaction_kind);
        if spikes and spikes.infer == 'reaction' then possible(action.actor, spikes.effect, 'spikes', row.reaction_kind, row.target); end
    end
    -- What the action may have put on a monster with no word of it, after what its results did say.
    -- Only an action that reaches a monster is looked up, as finding a pet's owner goes through the players' places.
    local reaches = false;
    for _, row in ipairs(action.rows) do
        if row.target >= 0x1000000 then reaches = true; break; end
    end
    local kind = reaches and guess_kind(action, from_pet, now);
    local unreported = kind and catalog.action(kind, action.id);
    if unreported then
        for _, row in ipairs(action.rows) do
            -- An effect the result itself names, as Angon's does, was put on above.
            local named = landed[row.message] and row.param or nil;
            if unreported.by_effect then
                for effect, part in pairs(unreported.by_effect) do
                    if effect ~= named and unsaid(part, row) and may(part, snapshot, action, from_pet) then
                        possible(row.target, effect, kind, action.id, action.actor);
                    end
                end
            elseif unreported.effect and unreported.effect ~= named and unsaid(unreported, row) and may(unreported, snapshot, action, from_pet) then
                possible(row.target, unreported.effect, kind, action.id, action.actor);
            end
        end
    end
    -- An automaton's Shield Bash Slow lasts by its owner's Earth Maneuvers (data/pets.lua), which are counted only for
    -- yours. Anyone else's, and yours before your listing is read, gets the range from one of them to three.
    local slow = kind == 'automatons' and action.id == pets.automaton.bash_skill and pets.automaton.bash_slow;
    if slow then
        local count, overdrive = 0, false;
        for _, held in ipairs(from_pet and snapshot.self_known and snapshot.self_effects or NONE) do
            if held.effect == slow.maneuver then count = count + 1; elseif held.effect == pets.automaton.overdrive then overdrive = true; end
        end
        local seconds = slow.seconds[count > 0 and overdrive and 3 or math.min(count, 3)];
        for _, entry in ipairs(out) do
            if entry.kind == 'apply' and entry.guessed and entry.effect == slow.effect then
                entry.duration, entry.duration_min = seconds or slow.seconds[3], seconds or slow.seconds[1];
            end
        end
    end
    -- An effect a player armed with an ability goes on with their next melee hit that connects, once: Feint's Evasion
    -- Down. It is armed by the ability's own result and lasts as long as the data says.
    if action.actor < 0x1000000 then
        for key, info in pairs(catalog.kind('reactive')) do
            if action.category == 6 and action.id == info.arm_ability then
                for _, message in ipairs(info.arm_messages or NONE) do
                    if action.rows[1].message == message then
                        if not armed[action.actor] then
                            if armed_count >= 64 then armed, armed_count = {}, 0; end
                            armed_count = armed_count + 1;
                        end
                        armed[action.actor] = { key = key, ends = now + (info.arm_seconds or 60) };
                    end
                end
            elseif action.category == 1 and armed[action.actor] and armed[action.actor].key == key then
                if armed[action.actor].ends <= now then
                    armed[action.actor], armed_count = nil, armed_count - 1;
                else
                    for _, row in ipairs(action.rows) do
                        -- A swing the monster deflects reads as a hit for nothing, and leaves the effect armed
                        -- (Phoenix src/map/entities/battle_entity.cpp :3681-3683, :3837).
                        if row.target >= 0x1000000 and CONNECTS[row.message] and row.param > 0 then
                            possible(row.target, info.effect, 'reactive', key, action.actor);
                            if info.consume then armed[action.actor], armed_count = nil, armed_count - 1; break; end
                        end
                    end
                end
            end
        end
    end
    if from_pet and action.category == 13 then
        local ward, debuff = pets.wards[action.id], pets.skill_debuffs[action.id];
        if ward or debuff then
            -- Your skill is all that counts here. Your gear stays out of what else your pet does.
            if reading.sample == nil then reading.sample = client.sample_modifiers(snapshot); end
            local skill = reading.sample.summoning_skill;
            if debuff then
                local seconds = debuff.base + math.max(0, math.min(debuff.most, (skill or 0) - debuff.from));
                for _, entry in ipairs(out) do
                    if entry.kind == 'apply' and entry.spell == action.id then
                        entry.duration, entry.duration_min = seconds, seconds;
                        -- Lunar Cry's effects are guesses, and keep the note that says a resist looks the same.
                        if not entry.guessed then entry.basis = 'Phoenix\'s length at your summoning skill. A resist can shorten it.'; end
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
        if reading.sample == nil then reading.sample = client.sample_modifiers(snapshot); end
        local sample = reading.sample;
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
        if reading.sample == nil then reading.sample = client.sample_modifiers(snapshot); end
        local entry = event(snapshot, 'call_beast', snapshot.id);
        entry.item = reading.sample.items[3] or snapshot.ammo;
        out[#out + 1] = entry;
    end
    -- Your own job ability, which starts a cooldown the client didn't list before (core/recasts.lua). Jump, Steal, Shield
    -- Bash and a few others finish as category 3, as weapon skills do. A weapon skill's id can match an ability's, but
    -- it never starts a cooldown. A Double-Up comes with the id of the roll it doubles (Phoenix
    -- modules/era/lua/globals/job_utils/corsair.lua :349), and only a Double-Up gives your own row 424, or 426 on a
    -- bust. Its cooldown is Double-Up's own, timer 194 (src/map/entities/char_entity.cpp :2130,
    -- sql/abilities.sql :143), so it is a use of Double-Up, ability 123.
    if action.actor == snapshot.id and (action.category == 6 or action.category == 3) then
        local ability = action.id;
        if action.category == 6 and in_era_rolls[ability] then
            for _, row in ipairs(action.rows) do
                if row.target == action.actor and (row.message == 424 or row.message == 426) then ability = 123; break; end
            end
        end
        out[#out + 1] = { kind = 'used', ability = ability };
    end
    -- Your avatar's pact going off is a use of it too. Phoenix starts a pact's cooldown when the move goes off, not
    -- when you use the pact (scripts/globals/job_utils/summoner.lua onUseBloodPact), and the move has the pact's own id
    -- (src/map/entities/pet_entity.cpp OnPetSkillFinished). When the avatar has far to run, that's more than 3 seconds
    -- after your use. A wyvern's breath is category 13 too but has no cooldown, and a jug pet's move is category 11.
    if from_pet and action.category == 13 then
        out[#out + 1] = { kind = 'used', ability = action.id };
    end
    -- Your action that paralysis stopped: category 4 with no action id, and message 84 (src/map/action/interrupts.cpp
    -- AbilityParalyzed). A paralyzed ranged attack looks the same, so core/recasts.lua takes it as a use only of a job
    -- ability you asked for just before.
    if action.actor == snapshot.id and action.category == 4 and action.id == 0 then
        for _, row in ipairs(action.rows) do
            if row.message == 84 then out[#out + 1] = { kind = 'paralyzed' }; break; end
        end
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
-- The effects no unit can act under (the same list as STOPS in core/tracker.lua), and the mobs and pets seen to take
-- one, whose next finished action says it is over (acting, below). A unit that dies or leaves view is forgotten, and
-- a zone change forgets them all. At most 64: past that they are all forgotten, and the ones still under an effect keep
-- it on the displays until it is too old, as before this.
local STOPS = { [2] = true, [19] = true, [193] = true, [7] = true, [10] = true, [28] = true };
local halted, halted_count = {}, 0;
local function stamp(out, snapshot)
    local count, listing = client.self_timer_revision(), client.party_revision();
    for _, entry in ipairs(out) do
        if entry.kind == 'apply' or entry.kind == 'remove' then
            if entry.entity_id == snapshot.id then entry.timer_revision = count;
            else entry.party_revision = listing; end
        end
        if entry.kind == 'apply' and STOPS[entry.effect] and entry.entity_id >= 0x1000000 and not halted[entry.entity_id] then
            if halted_count >= 64 then halted, halted_count = {}, 0; end
            halted[entry.entity_id], halted_count = true, halted_count + 1;
        end
    end
    return out;
end

-- A mob or a pet that finishes an action has nothing on it that stops a unit acting (Phoenix HasPreventActionEffect,
-- src/map/status_effect_container.cpp :2176-2186), which core/tracker.lua takes off. The game sends no wear-off for
-- what a monster put on your pet, so its next swing, spell or move is the sign. A start isn't read for this: a unit
-- put to sleep in the middle of one sends the same packet as it is cut short. Players go by their listings.
-- Only a unit seen to take such an effect is read for it (halted, kept by stamp), so every other action costs one
-- lookup.
local function unhalt(id)
    if halted[id] then halted[id], halted_count = nil, halted_count - 1; end
end
-- Three packets come from a unit that still can't act, and count for nothing: a cast begun before the effect landed
-- can end in "is paralyzed" (84) or "is intimidated" (106), as those rolls come before the check for it (Phoenix
-- src/map/ai/states/magic_state.cpp :264-293), and a mob's script sends packets of its own with no message, whatever
-- the mob's state (CLuaBaseEntity::injectActionPacket, as Promyvion's Wailers do).
local STILL = { [0] = true, [84] = true, [106] = true };
local function acting(action, snapshot)
    if not halted[action.actor] or not wanted[action.category] or STILL[action.rows[1].message] then return nil; end
    local entry = event(snapshot, 'acted', action.actor);
    if entry.scope ~= 'enemy' and entry.scope ~= 'pet' then return nil; end
    -- Forgotten only once the tracker is told.
    unhalt(action.actor);
    return entry;
end

-- Ashita hands it userdata, the tests a table. size and data are the packet's, when the caller has read them already.
-- A packet with nothing to report gives NONE, which callers only read. An action's list is one table, emptied for the
-- next action (reading, above), so callers read it before the next packet and keep only its entries.
function observer.read(e, now, snapshot, size, data)
    local kind = type(e);
    if kind ~= 'userdata' and kind ~= 'table' or e.injected == true or e.blocked == true then return NONE; end
    if size == nil then size, data = client.packet_size(e); end
    local id = e.id;
    client.accept(e, now, snapshot, size, data);
    if id == 0x00A and size >= 50 then
        sneaking = {};
        halted, halted_count = {}, 0;
        return { { kind = 'reset', reason = 'Zone changed' } };
    end
    if not snapshot or not snapshot.valid then return NONE; end
    if id == 0x028 then
        own_pet = snapshot.pet and snapshot.pet.id or nil;
        local action = observer.decode(e, size);
        own_pet = nil;
        if action then
            local out = action_events(action, snapshot, now);
            -- Before what the action itself did, so an effect it put on its own user stays.
            local awake = acting(action, snapshot);
            if awake then table.insert(out, 1, awake); end
            return stamp(out, snapshot);
        end
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
            unhalt(target);
            -- Phoenix takes Feint off at a KO with no word of it (src/map/ai/states/death_state.cpp :55,
            -- data/status_effects.yaml :3299-3303), so an armed one goes too.
            if armed[target] then armed[target], armed_count = nil, armed_count - 1; end
            return { entry };
        end
    elseif id == 0x00E and size >= 11 and bit.band(data:byte(11), 0x20) ~= 0 then
        local target = u32(data, 4);
        if target > 0 then
            local entry = event(snapshot, 'despawn', target); entry.reason = 'Entity left view';
            unhalt(target);
            return { entry };
        end
    elseif id == 0x068 and size >= 0x0E and u32(data, 8) == snapshot.id and u16(data, 0x0C) == 0 then
        -- The server says your pet has gone.
        return { { kind = 'pet_gone' } };
    end
    return NONE;
end

return observer;
