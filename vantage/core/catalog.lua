local catalog = {};
local entries = require('data.catalog');
local durations = require('data.effects');
local actions = require('data.actions');
-- Phalanx II lasts 90 seconds plus 30 per merit (modules/phoenix/lua/globals/spells/enhancing_spell.lua :121), which the
-- exported data leaves at its first rank.
durations.merits.phalanx_ii = { id = 2310, base = 90, per_rank = 30, most = 3 };
durations.spells[107].merit = 'phalanx_ii';
-- Diaga II and III are tier 3 and 5, as Dia II and III are (actions/spells/white/diaga_ii.lua :14, diaga_iii.lua :14).
-- The exported data leaves them with no tier.
durations.spells[34].tier, durations.spells[35].tier = 3, 5;
-- Third Eye lasts 30 seconds and Seigan 300 (globals/job_utils/samurai.lua :115, :156), with nothing to change either, so
-- both are exact. Utsusemi takes Third Eye off (globals/spells/enhancing_ninjutsu.lua :111-114), and Third Eye has no
-- effect while Copy Image or Blink is up (samurai.lua :108-113), so one seen to land means neither is there. The exported
-- data has both lengths but not that they're exact, and those drops are in the scripts.
durations.abilities[62] = { effect = 67, seconds = 30, exact = true };
durations.abilities[174] = { effect = 354, seconds = 300, exact = true };
local copy_image = durations.effects[66].drops;
copy_image[#copy_image + 1] = 67;
durations.effects[67] = { drops = { 36, 66 } };
-- Hundred Fists lasts 45 seconds, Counterstance 300 and Formless Strikes 180 (globals/job_utils/monk.lua :173, :107,
-- :160). The blue magic buffs last the time each spell's script passes to globals/bluemagic.lua :1211: Metallic Body,
-- Refueling, Diamondhide and Zephyr Mantle 300, Cocoon 90, Feather Barrier 30, Memento Mori and Triumphant Roar 60,
-- Reactor Cool 120, Saline Coat and Warm-Up 180, Plasma Charge 60 and Amplification 90
-- (actions/spells/blue/metallic_body.lua :26, refueling.lua :25, diamondhide.lua :26, zephyr_mantle.lua :26, cocoon.lua
-- :25, feather_barrier.lua :25, memento_mori.lua :24, triumphant_roar.lua :24, reactor_cool.lua :24, saline_coat.lua
-- :26, warm-up.lua :24, plasma_charge.lua :25, amplification.lua :24). Reactor Cool, Warm-Up and Amplification each
-- put on two effects for that time. Only Diffusion makes it longer, and only on the caster's own copy, which is made
-- first (bluemagic.lua :1212-1219, src/map/ai/helpers/targetfind.cpp :132-136).
-- How much longer goes by the caster's Diffusion merits (modules/era/data/merits.yaml :374-375, src/map/merit.cpp :380),
-- which Vantage can't read for another player, so their own copy is left with no time when their cast shows it was made
-- under Diffusion (core/observer.lua). Yours goes by the game's timer. The exported data has none of these lengths.
for id, seconds in pairs({ [17] = 45, [40] = 300, [152] = 180 }) do durations.abilities[id].seconds = seconds; end
local blue_buffs = { [517] = 300, [530] = 300, [632] = 300, [647] = 300, [547] = 90, [574] = 30, [538] = 60, [655] = 60,
    [613] = 120, [614] = 180, [615] = 60, [636] = 180, [642] = 90 };
for id, seconds in pairs(blue_buffs) do
    local row = durations.spells[id];
    row.seconds = seconds;
    for _, part in pairs(row.by_effect or {}) do part.seconds = seconds; end
end
-- Whether another player's cast of one of these was made under Diffusion: their party listing shows Diffusion (356), or
-- with no listing to read, as for an alliance member, the cast reached more than one target. Eleven of them reach more
-- than the caster only under Diffusion (sql/spell_list.sql :687, :699, :707, :716, :778-780, :800, :806, :811, :819,
-- combat/basic/magic_aoe.lua :148-154, src/map/entities/battle_entity.cpp :2429-2451). Feather Barrier never does and
-- Diamondhide (632) can without it (spell_list.sql :741, :796), so only a listing tells for those two. Phoenix sends
-- the listing once the action is done (src/map/ai/states/magic_state.cpp :327, src/map/ai/ai_container.cpp :564,
-- src/map/entities/char_entity.cpp :1190-1200), so the one read with the cast still shows Diffusion.
function catalog.diffused(action, snapshot)
    if action.category ~= 4 or not blue_buffs[action.id] then return false; end
    local effects;
    for _, member in ipairs(snapshot.party or {}) do
        if member.id == action.actor then effects = member.valid and member.effects; break; end
    end
    if effects then
        for _, status in ipairs(effects) do
            if status.effect == 356 then return true; end
        end
        return false;
    end
    if action.id == 632 then return false; end
    for _, row in ipairs(action.rows) do
        if row.target ~= action.actor then return true; end
    end
    return false;
end
-- Bindga binds for 13 to 60 seconds, as Bind does (globals/spells/enfeebling_spell.lua :329-330, which
-- modules/phoenix/lua/globals/spells/enfeebling_spell.lua :117 keeps for both), and Charm binds a monster it can't
-- charm for 1 to 5 (globals/job_utils/beastmaster.lua :172). The exported data gives each only its longest.
durations.spells[362].seconds, durations.spells[362].top = 13, 60;
durations.abilities[52].seconds, durations.abilities[52].top = 1, 5;
-- A player's bar-element spell lasts 150 seconds and 0.8 more for each point of the caster's Enhancing Magic skill past
-- 180 (modules/phoenix/lua/globals/spells/enhancing_spell.lua :49-66). Vantage reads only your own skill, so anyone
-- else's counts from 150 up to a level 75 RDM's skill cap. Barfira to Barwatera are WHM spells, but a RDM with WHM as
-- support job casts them with the RDM's skill (sql/spell_list.sql :235-240, src/map/spell.cpp :809,
-- src/map/utils/charutils.cpp :3608-3655), so the top for every bar spell is a RDM's B+ 256, 210.8, counted as 211
-- (data/skills.yaml :30, :118). Enhancing Magic Skill merits (data/merits.yaml :234-239) and gear can take a caster
-- past it. A mob's stays 150 (globals/spells/enhancing_spell.lua :449-456), the low end. The
-- details say the range goes by the caster's skill.
for id = 60, 71 do
    durations.spells[id].top, durations.spells[id].range_basis = 211, 'Duration range by the caster\'s Enhancing Magic skill';
end
-- These roll their length, and the exported data gives the longest for both ends: a Bottle of Psychoanima's Intimidate
-- and a Bottle of Hysteroanima's Hysteria 25 to 32 seconds (items/bottle_of_psychoanima.lua :22,
-- items/bottle_of_hysteroanima.lua :24), Shield Bash's stun 4.2 to 6.2 (modules/era/lua/globals/job_utils/paladin.lua
-- :156), Weapon Bash's 2 to 8 (globals/job_utils/dark_knight.lua :163), and Head Butt's 2 to 7, a time from 2 up to 8
-- with the part of a second dropped (actions/spells/blue/head_butt.lua :52, globals/bluemagic.lua :1361).
durations.items[5261].seconds, durations.items[5262].seconds = 25, 25;
durations.abilities[46].seconds, durations.abilities[77].seconds = 4.2, 2;
durations.spells[623].seconds, durations.spells[623].top = 2, 7;
-- Light of Penance puts Blindness and Bind on before it checks that the caster and the target face each other, and when
-- they don't, its message is 75, that it had no effect (actions/spells/blue/light_of_penance.lua :41-45, :58). Both are
-- on all the same, so 75 counts as it landing, as 236 does.
local penance = durations.spells[634];
for _, info in ipairs({ penance, penance.by_effect[5], penance.by_effect[11] }) do
    info.success_messages[#info.success_messages + 1] = 75;
end
-- Enervation reaches each monster around its target. The first gets 236 and each one after it 277, the area form of 236
-- (src/map/entities/battle_entity.cpp :2511-2518, src/map/utils/messageutils.h :37), so 277 counts as it landing too.
local enervation = durations.spells[633];
for _, info in ipairs({ enervation, enervation.by_effect[149], enervation.by_effect[167] }) do
    info.success_messages[#info.success_messages + 1] = 277;
end
-- Feral Howl's result is 100, that it was used, with Terror as its param, whether or not the Terror took
-- (sql/abilities.sql :180, src/map/entities/char_entity.cpp :2093-2104, modules/era/lua/globals/job_utils/beastmaster.lua
-- :28-55), as Tomahawk's is. Terror lasts 10 seconds times the resist rate, and it takes only at a rate of 1/4 or more,
-- so 2.5 to 10 (scripts/data/status_effect_tables.lua :73, :229-236).
durations.abilities[161].infer, durations.abilities[161].success_messages = 'success', { 100 };
durations.abilities[161].seconds, durations.abilities[161].top = 2.5, 10;
-- A monster move timed by TP lasts its shortest at 1000 TP or less and its longest at 3000 (globals/mobskills.lua
-- :1724-1728). A mob uses one at any TP from 1000 to 3000 (src/map/ai/controllers/mob_controller.cpp :197,
-- src/map/entities/mob_entity.cpp :528-539), and the game doesn't send the TP. Other moves roll their length. The
-- exported data gives each move only its longest, so each of these counts down from its shortest to its longest. The
-- times are the ones in the move's script in actions/mobskills, at the line beside it. Phoenix's _pre_wotg scripts in
-- modules/phoenix/lua/actions/mobskills and modules/era/lua/actions/mobskills/era_jugpet_mobskills.lua replace the base
-- ones. A move that puts on more than one effect lists the ones whose time goes by TP or a roll. A charmed monster's or
-- a jug pet's move has the same id, so its row gets the same times.
local moves = {
    [2] = { 2, 10 },  -- shoulder_tackle.lua :29
    [15] = { 18, 30 },  -- shijin_spiral.lua :30
    [52] = { 60, 300 }, [987] = { 60, 300 },  -- shockwave.lua :15
    [58] = { 60, 300 },  -- herculean_slash.lua :15
    [129] = { 30, 210 },  -- blade_retsu.lua :32
    [219] = { 60, 300 },  -- numbing_shot.lua :31
    [240] = { [2] = { 60, 300 }, [167] = { 60, 300 }, [404] = { 60, 300 } },  -- tartarus_torpor.lua :14
    [284] = { 10, 70 },  -- cold_stare.lua :14
    [301] = { 15, 60 },  -- dream_flower.lua :13
    [305] = { 115, 180 }, [1587] = { 115, 180 },  -- leaf_dagger_pre_wotg.lua :33
    [310] = { 90, 120 },  -- queasyshroom_pre_wotg.lua :30
    [314] = { 15, 60 },  -- silence_gas.lua :32
    [320] = { 15, 60 }, [728] = { 15, 60 },  -- sweet_breath.lua :31
    [341] = { 180, 540 },  -- rhino_guard.lua :15
    [343] = { 180, 540 },  -- spoil.lua :14
    [344] = { 180, 540 },  -- sticky_thread.lua :13
    [345] = { 60, 300 },  -- poison_breath_crawler_pre_wotg.lua :31
    [348] = { 120, 180 },  -- numbing_breath.lua :30
    [356] = { 180, 540 },  -- sharp_strike.lua :19
    [371] = { 90, 120 },  -- plague_breath_pre_wotg.lua :31
    [391] = { 30, 90 },  -- aura_of_persistence.lua :17
    [393] = { 180, 540 },  -- sonic_boom.lua :16
    [402] = { 180, 1020 }, [1660] = { 180, 1020 },  -- feather_barrier.lua :21
    [459] = { 180, 540 }, [1672] = { 180, 540 }, [3547] = { 180, 540 },  -- hard_membrane.lua :22
    [479] = { 60, 300 },  -- horror_cloud.lua :18
    [484] = { 60, 480 },  -- black_cloud.lua :28
    [504] = { 30, 90 },  -- gas_shell.lua :19
    [508] = { 30, 90 }, [1575] = { 30, 90 },  -- suctorial_tentacle.lua :16
    [514] = { 6, 10 },  -- whirl_of_rage.lua :28
    [517] = { 5, 10 }, [1596] = { 5, 10 },  -- numbing_noise.lua :16
    [522] = { 30, 60 },  -- spectral_barrier.lua :17
    [535] = { 10, 15 },  -- blitzstrahl.lua :28
    [541] = { 240, 420 },  -- gravity_field.lua :15
    [550] = { 45, 135 }, [1138] = { 45, 135 },  -- hypnosis.lua :13
    [552] = { 30, 90 }, [1140] = { 30, 90 },  -- binding_wave.lua :13
    [557] = { 15, 105 }, [1144] = { 15, 105 },  -- level_5_petrify.lua :17
    [560] = { 60, 120 }, [1146] = { 60, 120 },  -- hecatomb_wave.lua :31
    [563] = { 180, 540 }, [1147] = { 180, 540 },  -- demonic_howl.lua :15
    [577] = { 10, 15 }, [2828] = { 10, 15 },  -- jettatura.lua :17
    [588] = { [10] = { 10, 15 } }, [729] = { [10] = { 10, 15 } },  -- death_trap.lua :17
    [605] = { 5, 10 }, [1057] = { 5, 10 },  -- aerial_wheel.lua :37
    [607] = { 30, 60 }, [1059] = { 30, 60 },  -- slam_dunk.lua :29
    [608] = { 600, 1020 },  -- arm_block.lua :17
    [612] = { 5, 10 }, [1076] = { 5, 10 },  -- head_butt_quadav.lua :28
    [613] = { 5, 10 }, [1077] = { 5, 10 },  -- shell_bash.lua :28
    [614] = { 600, 1560 },  -- shell_guard.lua :13
    [618] = { 5, 10 }, [1069] = { 5, 10 },  -- double_kick.lua :28
    [619] = { 600, 1440 },  -- parry.lua :13
    [620] = { 8, 10 }, [1071] = { 8, 10 },  -- sweep.lua :28
    [629] = { 8, 14 },  -- thunderbolt_behemoth.lua :28
    [638] = { 30, 90 },  -- blastbomb.lua :28
    [643] = { 120, 180 },  -- poison_breath_dragon_1.lua :32
    [676] = { 120, 240 }, [1650] = { 120, 240 },  -- ice_break.lua :29
    [677] = { 10, 20 }, [1651] = { 10, 20 },  -- thunder_break.lua :28
    [723] = { 10, 15 },  -- earthbreaker.lua :29
    [780] = { 8, 10 },  -- spinning_fin.lua :28
    [798] = { 30, 60 },  -- tail_swing.lua :29
    [799] = { 30, 60 },  -- tail_smash.lua :29
    [805] = { 120, 180 },  -- head_butt_turtle.lua :28
    [806] = { 120, 180 },  -- tortoise_stomp.lua :31
    [807] = { 60, 180 },  -- harden_shell.lua :18
    [815] = { 15, 105 },  -- wind_wall.lua :22
    [817] = { 30, 60 },  -- dread_shriek.lua :30
    [932] = { 30, 60 }, [3717] = { 30, 60 },  -- havoc_spiral.lua :30
    [1102] = { 10, 15 },  -- dice_stun.lua :28
    [1110] = { 5, 10 }, [1112] = { 5, 10 }, [1114] = { 5, 10 }, [1116] = { 5, 10 },  -- seismostomp.lua :29
    [1148] = { 10, 15 },  -- condemnation.lua :41
    [1152] = { 60, 120 },  -- hecatomb_wave_ra.lua :32
    [1157] = { 120, 240 },  -- slipstream.lua :13
    [1161] = { 10, 15 }, [1445] = { 10, 15 },  -- damnation_dive.lua :41
    [1179] = { 120, 180 },  -- poison_breath_dragon_2.lua :32
    [1349] = { 15, 45 },  -- mantle_pierce.lua :30
    [1350] = { 30, 60 },  -- ink_cloud.lua :17
    [1353] = { 45, 75 },  -- aerial_collision.lua :34
    [1365] = { 30, 60 },  -- tail_thrust.lua :29
    [1366] = { 8, 10 },  -- temporal_shift.lua :17
    [1371] = { 45, 90 },  -- primal_drill.lua :28
    [1376] = { 5, 25 },  -- luminous_drape.lua :22
    [1378] = { 30, 60 },  -- wing_thrust.lua :31
    [1380] = { [10] = { 8, 10 } },  -- impact_stream.lua :35
    [1383] = { 30, 60 },  -- glacier_splitter.lua :30
    [1385] = { 30, 60 },  -- biotic_boomerang.lua :30
    [1386] = { 30, 60 },  -- medusa_javelin.lua :30
    [1448] = { [5] = { 10, 30 }, [6] = { 10, 30 } },  -- efflorescent_foetor.lua :16, :17
    [1449] = { 15, 60 },  -- stupor_spores.lua :29
    [1452] = { 30, 60 },  -- axial_bloom.lua :17
    [1465] = { 15, 60 },  -- optic_induration.lua :31
    [1468] = { 30, 60 },  -- reactor_overheat.lua :28
    [1469] = { 15, 60 },  -- reactor_overload.lua :28
    [1562] = { 5, 10 },  -- stomping_dynamis.lua :31
    [1568] = { 30, 60 },  -- dust_cloud_dynamis.lua :30
    [1580] = { 10, 15 },  -- damnation_dive_nm.lua :32
    [1585] = { 10, 45 },  -- dream_flower_dynamis.lua :16
    [1588] = { [28] = { 2, 5 } },  -- scream_dynamis.lua :16
    [1615] = { 15, 45 },  -- soporific_dynamis.lua :28
    [1623] = { 60, 120 },  -- venom_dynamis.lua :28
    [1634] = { 10, 30 },  -- sheep_song_dynamis.lua :13
    [1638] = { 10, 15 },  -- lightning_roar_dynamis.lua :29
    [1671] = { 30, 120 },  -- ink_jet_dynamis.lua :29
    [1680] = { 3, 8 },  -- predatory_glare_dynamis.lua :15
    [1686] = { 10, 15 },  -- thunderbolt_dynamis.lua :31
    [1688] = { 2, 5 },  -- scythe_tail_dynamis.lua :28
    [1694] = { [6] = { 30, 90 }, [31] = { 15, 75 } },  -- vile_belch.lua :15, :16
    [1695] = { 120, 240 },  -- hypnic_lamp.lua :19
    [1697] = { 30, 60 },  -- seaspray.lua :31
    [1713] = { 60, 120 },  -- yawn.lua :13
    [1716] = { 60, 120 },  -- frigid_shuffle.lua :21
    [1721] = { 15, 20 },  -- obfuscate.lua :16
    [1759] = { 30, 90 },  -- hypnotic_sway.lua :16
    [1780] = { 15, 45 },  -- leaping_cleave.lua :34
    -- Animating Wail times its Haste by the mob's TP as the move goes off, not by the TP the move used. The move used
    -- all the mob's TP as it began (src/map/ai/states/mobskill_state.cpp :133, :179-180), so the Haste lasts its
    -- shortest, 90 seconds (globals/mobskills.lua :1724-1728).
    [1782] = { 90 },  -- animating_wail.lua :19
    [1783] = { 120, 240 },  -- fortifying_wail.lua :19
    [1814] = { 60, 180 },  -- gorgon_dance.lua :23
    [1817] = { 30, 150 },  -- thermal_pulse.lua :33
    [1963] = { 15, 75 },  -- mind_blast.lua :31
    [1978] = { [4] = { 30, 90 }, [6] = { 30, 90 }, [31] = { 15, 75 } },  -- abominable_belch.lua :15, :17
    [2023] = { 6, 10 },  -- thunderstrike.lua :28
    [2024] = { 20, 100 },  -- tourbillion.lua :31
    [2028] = { [10] = { 6, 10 } },  -- fulmination.lua :30
    [2097] = { 60, 120 }, [2103] = { 60, 120 },  -- granite_skin.lua :15
    [2101] = { 30, 150 },  -- demoralizing_roar.lua :18
    [2104] = { 30, 90 },  -- crippling_slam.lua :32
    [2128] = { 120, 240 },  -- ice_break_2128.lua :31
    [2161] = { [13] = { 60, 180 }, [33] = { 60, 180 } },  -- cimicine_discharge.lua :15
    [2165] = { [146] = { 90, 150 }, [174] = { 90, 150 } },  -- rotten_stench.lua :14
    [2183] = { [12] = { 30, 45 }, [177] = { 30, 45 } },  -- fuscous_ooze.lua :14
    [2329] = { 3, 15 },  -- di_horn_attack.lua :30
    [2330] = { 3, 15 },  -- di_bite_attack.lua :30
    [2334] = { 30, 90 },  -- wrath_of_zeus.lua :28
    [2335] = { 30, 210 },  -- lightning_spear.lua :29
    [2770] = { [31] = { 60, 180 }, [149] = { 60, 180 }, [167] = { 60, 180 } },  -- booming_bombination.lua :16
    [2952] = { [4] = { 60, 180 }, [5] = { 60, 180 }, [6] = { 60, 180 } },  -- blackout.lua :16
    [3844] = { 15, 60 },  -- dream_flower_jugpet, era_jugpet_mobskills.lua :119
    [3873] = { 15, 60 },  -- silence_gas_jugpet, era_jugpet_mobskills.lua :736
    [3878] = { 180, 540 },  -- rhino_guard_jugpet, era_jugpet_mobskills.lua :839
    [3879] = { 180, 540 },  -- spoil_jugpet, era_jugpet_mobskills.lua :851
    [3890] = { 5, 10 },  -- numbing_noise_jugpet, era_jugpet_mobskills.lua :1031
    [3916] = { 10, 15 },  -- jettatura_jugpet, era_jugpet_mobskills.lua :1615
    [3919] = { 120, 180 },  -- tortoise_stomp_jugpet, era_jugpet_mobskills.lua :1682
    [3920] = { 60, 180 },  -- harden_shell_jugpet, era_jugpet_mobskills.lua :1695
    [3960] = { 3, 8 },  -- predatory_glare_jugpet, era_jugpet_mobskills.lua :2057
};
for id, time in pairs(moves) do
    for _, kind in ipairs({ 'skills', 'charmed_skills', 'pet_moves' }) do
        local row = durations[kind][id];
        if row and row.by_effect then
            for effect, each in pairs(time) do
                row.by_effect[effect].seconds, row.by_effect[effect].top = each[1], each[2];
            end
        elseif row then
            row.seconds, row.top = time[1], time[2];
        end
    end
end
-- These jug pet moves each have a pact row too, the copy Ready would use. sql/pet_skills.sql gives each pact the id of
-- its move and category 11 (:197, :226, :231, :232, :243, :269, :272, :273, :316), and the pact runs that move's
-- script (actions/abilities/pets/spoil.lua :7, :14). Ready isn't loaded in era (sql/abilities.sql :269,
-- src/map/ability.cpp :331-335), and even a Ready move is sent as its move's id in category 11
-- (src/map/entities/pet_entity.cpp :423-428), so these rows never come up. They get the move's times all the same.
for pact, id in pairs({ [676] = 3844, [705] = 3873, [710] = 3878, [711] = 3879, [722] = 3890, [750] = 3916,
    [753] = 3919, [754] = 3920, [796] = 3960 }) do
    durations.pacts[pact].seconds, durations.pacts[pact].top = moves[id][1], moves[id][2];
end
-- What the exported data has no row for, or has other than Phoenix plays it, from data/pets.lua: Glittering Ruby, the
-- least length of Slowga and of each of Lunar Cry's effects, the automaton's attachments, and the mob Nightmares a hit
-- doesn't end.
local pets = require('data.pets');
durations.pacts[515] = pets.glittering_ruby;
for pact, rule in pairs(pets.skill_debuffs) do
    for _, part in pairs(durations.pacts[pact].by_effect or { durations.pacts[pact] }) do part.seconds = rule.base; end
end
for id, row in pairs(pets.attachments) do durations.skills[id] = row; end
for _, id in ipairs(pets.deep_sleeps) do durations.skills[id].by_effect[2].deep = true; end
local gear = require('data.gear');
local names = {};
-- How many rows catalog.get has given the client's name since load, so a list of them can tell it changed without
-- walking it.
local renamed = 0;
local sleeps = { [2] = true, [19] = true, [193] = true };
-- The client names 119 to 125 as it names 80 to 86, and a list shows only the name.
for id, name in pairs({ [119] = 'STR Boost II', [120] = 'DEX Boost II', [121] = 'VIT Boost II', [122] = 'AGI Boost II',
    [123] = 'INT Boost II', [124] = 'MND Boost II', [125] = 'CHR Boost II' }) do
    entries[id].name, names[id] = name, true;
end

-- The client has no name for an effect that only ever sits on a monster. Each of those keeps the name Phoenix gives it
-- and takes the picture of the item that puts it there (item, drawn by ui/icons.lua).
for id, entry in pairs(entries) do
    if entry.item then names[id] = true; end
end

local function client_name(id)
    return AshitaCore:GetResourceManager():GetString('buffs.names', id);
end
-- The client spells many debuffs all in lowercase, such as paralysis, slow and silence. Each word of such a name gets
-- a capital, so it reads like the rest. A name with a capital of its own is left as the client has it.
local function proper(name)
    if name:find('%u') then return name; end
    return (name:gsub('^%l', string.upper):gsub(' %l', string.upper));
end

-- The rows for effects nothing names, kept so a lookup makes none.
local unnamed = {};

function catalog.get(id)
    local row = entries[id];
    if not names[id] and AshitaCore then
        local ok, text = pcall(client_name, id);
        if ok and type(text) == 'string' and text ~= '' and text ~= '.' then
            row = row or { id = id, kind = 'other', group = 'Other', priority = 0 };
            entries[id], row.name, names[id] = row, proper(text), true;
            renamed = renamed + 1;
        end
    end
    if row then return row; end
    -- What nothing names doesn't exist on Phoenix, and core/tracker.lua gives it no row. Only the settings can hold its id.
    row = unnamed[id];
    if not row then
        row = { id = id, name = 'An effect with no name', kind = 'other', group = 'Other', priority = 0, unnamed = true };
        unnamed[id] = row;
    end
    return row;
end

-- Goes up each time catalog.get gives a row the client's name.
function catalog.revision() return renamed; end

-- What an effect does, in the game's own words: the description on the status record ui/icons.lua draws its picture
-- from. A catalog row's own description comes first, for the two the game says nothing of and the two whose words
-- don't fit Phoenix (tools/export_catalog.py DESCRIPTIONS). Each is read once, and an effect with none gives nil. A
-- record the game doesn't give is asked for again the next time.
local described = {};
local function client_description(id)
    local record = AshitaCore:GetResourceManager():GetStatusIconByIndex(id);
    if record == nil then return nil; end
    local text = record.Description and record.Description[1];
    return type(text) == 'string' and text or '';
end
function catalog.description(id)
    if type(id) ~= 'number' or id ~= id then return nil; end
    local said = described[id];
    if said == nil then
        local row = entries[id];
        said = row and row.description;
        if not said and AshitaCore then
            local ok, text = pcall(client_description, id);
            said = ok and text or nil;
        end
        if said == nil then return nil; end
        -- Only plain text, with no space at either end.
        said = said:gsub('[^ -~]', ''):match('^%s*(.-)%s*$');
        described[id] = said;
    end
    return said ~= '' and said or nil;
end

function catalog.list()
    local list = {};
    -- Copy Image's icons for 2, 3 and 4 or more shadows (444 to 446) are Copy Image itself.
    for id in pairs(entries) do if id < 444 or id > 446 then list[#list + 1] = catalog.get(id); end end
    -- Without regard to case, so AGI Boost comes after Accuracy Boost.
    table.sort(list, function (a, b)
        local first, second = a.name:lower(), b.name:lower();
        return first == second and a.id < b.id or first < second;
    end);
    return list;
end

-- One empty list for every effect with no drops and every sample with no gear. Its readers only read it.
local NONE = {};
function catalog.drops(id)
    return durations.effects[id] and durations.effects[id].drops or NONE;
end

function catalog.roll(action) return actions.rolls[action]; end

-- Whether a job ability put this effect on, with blood pacts and rolls counted as abilities. It goes by the action
-- seen to put it on (core/observer.lua). One that wasn't seen goes by data/ability_effects.lua, which leaves out the
-- effects a spell gives too.
local ability_kinds = { abilities = true, pacts = true, rolls = true };
local ability_effects = require('data.ability_effects');
function catalog.from_ability(row)
    if row.action_kind ~= nil then return ability_kinds[row.action_kind] == true; end
    return ability_effects[row.effect] == true;
end

local function matching(info, effect)
    if not info then return nil; end
    if info.by_effect then return info.by_effect[effect]; end
    if info.effect == effect or sleeps[info.effect] and sleeps[effect] then return info; end
end

function catalog.source(kind, action, effect)
    local table_ = durations[kind];
    local info = matching(table_ and table_[action], effect);
    if not info and kind == 'skills' then info = matching(durations.pacts[action], effect); end
    return info;
end

-- Occultation and Seal of Quiescence name another status in their result than the one they put on: Blink (36) for Copy
-- Image and Mute (29) for Silence (scripts/actions/mobskills/occultation.lua :21-22, seal_of_quiescence.lua :12-14).
-- Their rows hold what they put on.
local named_as = { [1255] = { [36] = 66 }, [1507] = { [29] = 6 } };
-- The status a monster's move put on, for the one its result names.
function catalog.applied(kind, action, effect)
    local put_on = kind == 'skills' and named_as[action];
    return put_on and put_on[effect] or effect;
end

function catalog.action(kind, action)
    return durations[kind] and durations[kind][action];
end

-- Mantra lasts 180 seconds (globals/job_utils/monk.lua :215), which the exported data leaves out. An ability that reaches
-- everyone around its user sends 0 on each row when it has no message of its own (src/map/entities/char_entity.cpp
-- :2038-2075). Killer Instinct puts itself on each of them for 60 (modules/era/lua/globals/job_utils/beastmaster.lua
-- :59-71), so its 0 counts on every row (core/observer.lua). Diffusion sends 0 too but goes on its user alone
-- (globals/job_utils/blue_mage.lua :76-78).
durations.abilities[151].seconds = 180;
durations.abilities[162].everyone = true;
-- Flee lasts 30 seconds plus its user's Flee duration gear (globals/job_utils/thief.lua :275), which the exported data
-- leaves out. Rogue's Poulaines and their +1 give 15 (sql/item_mods.sql :20215, :27168). Vantage reads no Flee
-- gear, yours or anyone else's, so it counts 30 to 45.
durations.abilities[42].seconds, durations.abilities[42].top = 30, 45;
durations.abilities[42].range_basis = 'Duration range by the user\'s gear';

-- The monster moves that take every erasable effect off: Depuration (1381), Rapid Molt (1368) and Voidsong (649) off
-- their user, and Benediction (689) off each mob it reaches (actions/mobskills/depuration.lua :25, rapid_molt.lua :24,
-- voidsong.lua :21, benediction.lua :12, sql/mob_skills.sql :720). Benediction's other ids are Maat's, a fight for one,
-- and Prishe's, who fights beside you, so neither has the party's effects to take. Erasable is what data/cleansable.lua
-- gives to Erase (143), and only an effect with a time goes (src/map/status_effect_container.cpp :930-945).
-- Wild Carrot (1570), which a Nightmare Bunny in Dynamis - Buburimu uses, erases its user too, then takes off
-- Petrification, Plague, Disease, Poison, both Curses, Silence, Paralysis and Blindness (mobskills/wild_carrot_dynamis.lua
-- :24-41, sql/mob_skills.sql :1601, zones/Dynamis-Buburimu/mobs/Nightmare_Bunny.lua :15-25, which Phoenix's Dynamis
-- module leaves as it is, modules/phoenix/dynamis/lua/dynamis_overrides.lua :1229-1239). No monster on Phoenix uses
-- Daybreak's only row (sql/mob_skills.sql :3684), and qn_aern_whm.lua and whispers_of_ire_self.lua have no row there at
-- all, so nothing uses them (a move's script goes by its name there, src/map/utils/battleutils.cpp :247-248).
local erases = { [1381] = 'user', [1368] = 'user', [649] = 'user', [689] = 'targets', [1570] = 'user' };
local erasable, carrot = {}, { 7, 31, 8, 3, 9, 20, 6, 4, 5 };
for effect, spell in pairs(require('data.cleansable')) do
    if spell == 143 then erasable[#erasable + 1], carrot[#carrot + 1] = effect, effect; end
end
local lists = { [1570] = carrot };
-- Whom a monster's move erases, 'user' or 'targets', and the effects it takes, or nil for a move that erases nothing.
function catalog.erases_all(id)
    if erases[id] then return erases[id], lists[id] or erasable; end
end

-- Another player's buff song lasts 120 seconds times 1 and a tenth of their instrument's bonus to it, with the part of a
-- second dropped, then twice that under Troubadour, and twice again under Soul Voice for Hymnus and Mazurka
-- (globals/spells/enhancing_song.lua :223-257, :269). Their gear isn't read, so it counts from none up to +2, the most an
-- instrument or Gjallarhorn gives a level 75 bard (sql/item_mods.sql). Their party listing says whether Troubadour or Soul
-- Voice is up. An alliance member has no listing, so theirs counts as with neither.
-- Their Requiem, Elegy, Threnody and Lullaby go the same way from each song's own base, doubled under Troubadour alone
-- (globals/spells/enfeebling_song.lua :111, :135-136). The most an instrument gives a level 75 bard is Requiem +4
-- (Requiem Flute), Threnody +3 (Sorrowful Harp), Elegy +2 (Horn +1) and Lullaby +2 (Nursemaid's Harp, Cradle Horn)
-- (sql/item_mods.sql :35874, :35837, :34178, :35834, :35882).
local NO_LISTING = {};
local SONG_MOST = { requiem = 4, threnody = 3, elegy = 2, lullaby = 2 };
function catalog.song_range(action, actor, snapshot, seconds)
    local song = actions.songs[action];
    local most = song and 2 or durations.spells[action] and SONG_MOST[durations.spells[action].song];
    if not most then return nil; end
    local multiplier = 1;
    for _, member in ipairs(snapshot.party or NO_LISTING) do
        if member.id == actor then
            for _, status in ipairs(member.valid and member.effects or NO_LISTING) do
                if status.effect == durations.troubadour or song and status.effect == 52 and song.soul_voice_duration then multiplier = multiplier * 2; end
            end
            break;
        end
    end
    return math.floor(seconds * (1 + most / 10)) * multiplier, seconds * multiplier, 'Duration range by the singer\'s instrument';
end

-- Every row of one kind, by its key.
local NO_ROWS = {};
function catalog.kind(kind) return durations[kind] or NO_ROWS; end

local function sum_items(items, list)
    local total = 0;
    for _, item in pairs(items or {}) do total = total + (list and list[item] or 0); end
    return total;
end

local function modifiers(sample)
    if not sample then return NONE; end
    local out = {};
    for _, item in pairs(sample.items or NONE) do
        for key, value in pairs(gear[item] or NONE) do out[key] = (out[key] or 0) + value; end
    end
    return out;
end

function catalog.roll_duration(sample)
    local rule = actions.merits.winning_streak;
    local rank = sample and sample.merits and sample.merits[rule.id];
    if sample and ((sample.level and sample.level < 75) or (sample.job and sample.job ~= 17)) then rank = 0; end
    local extra = modifiers(sample).phantom_duration or 0;
    return 300 + (rank or rule.most) * rule.value + extra, 300 + (rank or 0) * rule.value + extra;
end

function catalog.bust_duration(sample)
    local rule = actions.merits.bust_duration;
    local rank = sample and sample.merits and sample.merits[rule.id];
    if sample and ((sample.level and sample.level < 75) or (sample.job and sample.job ~= 17)) then rank = 0; end
    return 300 - (rank or 0) * rule.value, 300 - (rank or rule.most) * rule.value;
end

-- The slots an additional effect is read from, made once.
local RANGED_SLOTS, MELEE_SLOTS = { 2, 3 }, { 0, 1 };
-- The observed action must identify the duration rule.
function catalog.duration(kind, action, effect, sample)
    local info = catalog.source(kind, action, effect);
    if kind == 'procs' then
        if sample and sample.complete == false then return nil, nil, 'Equipment snapshot incomplete; no additional-effect duration'; end
        if sample then
            -- action is the 0x028 category here: 2 is a ranged attack, whose additional effects come from the range and
            -- ammo slots (2 and 3), and anything else from main and sub (0 and 1).
            local slots = action == 2 and RANGED_SLOTS or MELEE_SLOTS;
            local value;
            for _, slot in ipairs(slots) do
                local item = (sample.items or {})[slot];
                if item and durations.proc_effects[item] == effect then
                    local candidate = durations.procs[item];
                    if value and candidate ~= value then return nil, nil, 'Additional-effect item is ambiguous'; end
                    value = candidate;
                end
            end
            return value, value, value and 'Equipped item; duration can vary' or 'No duration for this additional effect';
        end
        return nil, nil, 'No duration for this additional effect';
    end
    if not info then return nil, nil, 'No duration reported for this action'; end
    local upper, lower = info.top or info.seconds, info.seconds;
    local basis = info.top and (info.range_basis or 'Duration range; resists may shorten it')
        or 'Phoenix base duration; modifiers and resists may change it';
    if info.merit then
        local rule = durations.merits[info.merit];
        local rank = sample and sample.merits and sample.merits[rule.id];
        if rank ~= nil and sample.level and sample.level < 75 then rank = 0; end
        if rank ~= nil then
            upper, lower = rule.base + rule.per_rank * rank, rule.base + rule.per_rank * rank;
            basis = 'Observed merit rank; resists may shorten it';
        else
            upper, lower = rule.base + rule.per_rank * rule.most, rule.base + rule.per_rank;
            basis = 'Merit rank not read; resists may shorten it';
        end
    end
    if not upper or upper <= 0 then return nil, nil, 'No duration for this action'; end
    local mods = modifiers(sample);
    if sample then
        if info.song then
            local bonus = sum_items(sample.items, durations.gear[info.song]) + sum_items(sample.items, durations.gear.songs);
            local extra = info.song == 'lullaby' and (mods.song_duration_bonus or 0) / 100 or 0;
            local multiplier = 1 + bonus / 10 + extra;
            -- Phoenix drops the part of a second before Troubadour doubles it (globals/spells/enfeebling_song.lua :111,
            -- :135-136).
            local double = (sample.buffs or {})[durations.troubadour] and 2 or 1;
            upper, lower = math.floor(upper * multiplier) * double, math.floor((lower or upper) * multiplier) * double;
            basis = 'Observed song gear and Troubadour; resists may shorten it';
        elseif kind == 'spells' and actions.songs[action] then
            local multiplier = 1 + ((mods[actions.songs[action].modifier] or 0) + (mods.all_songs_effect or 0)) / 10
                + (mods.song_duration_bonus or 0) / 100;
            -- And before Soul Voice and Troubadour double it (globals/spells/enhancing_song.lua :227, :245-253).
            local double = 1;
            if (sample.buffs or {})[durations.troubadour] then double = double * 2; end
            if actions.songs[action].soul_voice_duration and (sample.buffs or {})[52] then double = double * 2; end
            upper, lower = math.floor(upper * multiplier) * double, math.floor((lower or upper) * multiplier) * double;
            basis = 'Observed song gear and Troubadour; other bonuses may change it';
        elseif kind == 'spells' and actions.enhancing[action] then
            local stealth = effect == 69 or effect == 70 or effect == 71;
            local extra = effect == 42 and mods.regen_duration or sample.target_self and effect == 69 and mods.invisible_duration
                or sample.target_self and effect == 71 and mods.sneak_duration or 0;
            local multiplier = stealth and 1 or 1 + (mods.enh_magic_duration or 0) / 100;
            if effect >= 100 and effect <= 105 and sample.enhancing_skill then
                upper, lower = 150 + math.max(sample.enhancing_skill - 180, 0) * .8, 150 + math.max(sample.enhancing_skill - 180, 0) * .8;
            end
            upper, lower = upper * multiplier + (extra or 0), (lower or upper) * multiplier + (extra or 0);
            if actions.enhancing[action].composure and sample.target_self and (sample.buffs or {})[419] then
                upper, lower = upper * 3, lower * 3;
            end
            if sample.target_self and sample.level and sample.level < actions.enhancing[action].level then
                upper, lower = upper * sample.level / actions.enhancing[action].level, lower * sample.level / actions.enhancing[action].level;
            end
            basis = 'Observed base item modifiers; other bonuses may change it';
        elseif kind == 'spells' and action < 320 and (mods.enf_mag_duration or 0) ~= 0 then
            local multiplier = 1 + mods.enf_mag_duration / 100;
            upper, lower = upper * multiplier, (lower or upper) * multiplier;
        end
        if info.gear then
            local extra = sum_items(sample.items, durations.gear[info.gear]);
            upper, lower = upper + extra, (lower or upper) + extra;
        end
    end
    if sample and sample.complete == false then basis = basis .. '; equipment snapshot incomplete'; end
    return math.floor(upper), math.floor(lower or upper), basis, info;
end

return catalog;
