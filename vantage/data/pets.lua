-- What the pet display (core/pet.lua) knows of pets on Phoenix ed41f351f6, with the era SQL (modules/init.txt :48-53).
--
-- timers: the recast timers of pet commands and the abilities that call, heal or release a pet, by the timer id the
-- client reads (core/recasts.lua), with the ability that names and draws it, its job and its full recast in seconds.
-- The display shows the client's own time left; the full recast is the bar's length when Vantage didn't see the
-- recast start. merit and per_rank take a merit's ranks off it, as Phoenix does for an ability that isn't a merit
-- ability itself (src/map/entities/char_entity.cpp :1889-1891), and only on that main job at 75 (src/map/merit.cpp
-- :366-367). Timer 0 is the main job's two-hour (special). Ready (WotG, sql/abilities.sql :269) isn't loaded in era,
-- and Sic isn't on charges (char_entity.cpp :1904), so timer 102 is Sic alone. The era SQL loads whatever the server's
-- settings; Ready's absence (a content tag) and Repair's flat 180 (an era Lua module) need RESTRICT_CONTENT on
-- (src/map/lua/luautils.cpp :2560-2565, modules/module_utils.lua :79-96).
--
-- charm_time and familiar_bonus: the gear with CHARM_TIME (mod 360) and FAMILIAR_BONUS (mod 1169), by item id, from
-- sql/item_mods.sql :2482-82042 (no module changes these rows). CHARM_TIME adds 5% of a charm for each point
-- (scripts/globals/job_utils/beastmaster.lua :56-58); FAMILIAR_BONUS adds a minute to Familiar's 25 to 30 for each
-- point (scripts/globals/pets.lua :162-172).
--
-- own: what your job abilities do to your pet, by ability id. Each comes as a category 6 action aimed at the pet, but
-- for Deep Breathing, whose row is on you (on_you). effect and seconds: what it puts on the pet. cures: what it takes
-- off. coats, oils and repair say the same by the item you have on.
--
-- From wards down: what data/effects.lua has no row for, kept here by hand so the export stays as built. core/catalog.lua
-- and core/observer.lua read them.
return {
    timers = {
        { timer = 0, ability = 24, name = 'Familiar', job = 9, recast = 7200, special = true },        -- abyssea revert_two_hours.sql :7-30
        { timer = 97, ability = 52, name = 'Charm', job = 9, recast = 15 },                            -- abilities.sql :72
        { timer = 100, ability = 69, name = 'Fight', job = 9, recast = 5 },                            -- :89
        { timer = 102, ability = 72, name = 'Sic', job = 9, recast = 120, merit = 902, per_rank = 4 }, -- soa job_adjustments.sql :28; era merits.yaml :233-234
        { timer = 103, ability = 78, name = 'Reward', job = 9, recast = 180, merit = 898, per_rank = 6 }, -- wotg job_adjustments.sql :21; era merits.yaml :231-232
        { timer = 104, ability = 85, name = 'Call Beast', job = 9, recast = 300, merit = 900, per_rank = 10 }, -- abilities.sql :105; data/merits.yaml :848-851
        { timer = 152, ability = 70, name = 'Heel', job = 9, recast = 10 },                            -- wotg job_adjustments.sql :29, :38
        { timer = 153, ability = 71, name = 'Leave', job = 9, recast = 10 },                           -- :35, :39
        { timer = 154, ability = 73, name = 'Stay', job = 9, recast = 10 },                            -- :32, :40
        { timer = 0, ability = 29, name = 'Spirit Surge', job = 14, recast = 7200, special = true },   -- revert_two_hours.sql :7-30
        { timer = 163, ability = 61, name = 'Call Wyvern', job = 14, recast = 1200 },                  -- abilities.sql :81
        { timer = 162, ability = 80, name = 'Spirit Link', job = 14, recast = 180, merit = 1224, per_rank = 6 }, -- abyssea job_adjustments.sql :148; era merits.yaml :347-348
        { timer = 161, ability = 87, name = 'Dismiss', job = 14, recast = 300 },                       -- abilities.sql :107
        -- Its merit is what unlocks it, so the first rank takes nothing off (modules/era/lua/globals/job_utils/dragoon.lua
        -- :370-371; 150 a rank, modules/era/data/merits.yaml :353-355).
        { timer = 164, ability = 169, name = 'Deep Breathing', job = 14, recast = 900, merit = 2880, per_rank = 150, free_rank = true }, -- abyssea job_adjustments.sql :154; data/merits.yaml :1123
        { timer = 0, ability = 30, name = 'Astral Flow', job = 15, recast = 7200, special = true },    -- revert_two_hours.sql :7-30
        -- Blood pacts start their timer when the pact goes off, 60 s less up to 30 s of Blood Pact delay gear
        -- (char_entity.cpp :1935-1958), which Vantage can't see; Rage and Ward are separate timers.
        { timer = 173, ability = 91, name = 'Blood Pact: Rage', job = 15, recast = 60 },               -- abilities.sql :111
        { timer = 174, ability = 172, name = 'Blood Pact: Ward', job = 15, recast = 60 },              -- :191
        { timer = 170, ability = 88, name = 'Assault', job = 15, recast = 5 },                         -- :108
        { timer = 171, ability = 89, name = 'Retreat', job = 15, recast = 5 },                         -- :109
        { timer = 172, ability = 90, name = 'Release', job = 15, recast = 5 },                         -- :110
        { timer = 0, ability = 135, name = 'Overdrive', job = 18, recast = 7200, special = true },     -- revert_two_hours.sql :7-30
        { timer = 205, ability = 136, name = 'Activate', job = 18, recast = 1200, merit = 1478, per_rank = 40 }, -- abilities.sql :155; data/merits.yaml :1309-1312
        -- Repair is a flat 180 s in era (modules/era/lua/globals/job_utils/puppetmaster.lua :22-31), less its merit
        -- (ability_state.cpp :125, :296; char_entity.cpp :1889-1891).
        { timer = 206, ability = 137, name = 'Repair', job = 18, recast = 180, merit = 1480, per_rank = 3 }, -- data/merits.yaml :1313-1316
        { timer = 207, ability = 138, name = 'Deploy', job = 18, recast = 5 },                         -- abilities.sql :157
        { timer = 208, ability = 139, name = 'Deactivate', job = 18, recast = 60 },                    -- :158
        { timer = 209, ability = 140, name = 'Retrieve', job = 18, recast = 5 },                       -- :159
        { timer = 210, ability = 141, name = 'Maneuvers', job = 18, recast = 10 },                     -- :160-167
        { timer = 211, ability = 179, name = 'Role Reversal', job = 18, recast = 120 },                -- :198
        { timer = 212, ability = 180, name = 'Ventriloquy', job = 18, recast = 60 },                   -- :199
    },
    charm_time = { [10658] = 6, [10678] = 8, [10698] = 5, [10718] = 3, [10738] = 4, [12517] = 4, [12646] = 5, [13969] = 3,
        [14097] = 2, [14222] = 6, [14481] = 6, [14508] = 7, [14898] = 3, [14917] = 4, [15080] = 5, [15095] = 6, [15110] = 4,
        [15125] = 2, [15140] = 3, [15233] = 4, [15253] = 5, [15360] = 2, [15569] = 6, [15588] = 2, [15673] = 3, [17936] = 1,
        [23048] = 30, [23071] = 12, [23138] = 14, [23205] = 11, [23272] = 9, [23339] = 10, [23383] = 35, [23674] = 12,
        [26640] = 8, [26641] = 10, [26816] = 8, [26817] = 12, [26992] = 7, [26993] = 9, [27168] = 5, [27169] = 7,
        [27344] = 6, [27345] = 8, [27671] = 5, [27692] = 5, [27815] = 7, [27836] = 7, [27951] = 4, [27972] = 5,
        [28098] = 7, [28119] = 7, [28231] = 3, [28252] = 3 },
    familiar_bonus = { [10718] = 10, [23272] = 10, [27168] = 10, [27169] = 10 },                     -- :2954, :51830, :69522, :69539
    own = {
        -- Reward: Regen for 180 s from you, after taking off the old one; it wakes the pet, and a Jackcoat in the body slot
        -- cures its list (scripts/globals/job_utils/beastmaster.lua :534, :556-589, :608-613). Sleep, Sleep II and Lullaby
        -- are what a wake-up takes off (src/map/status_effect_container.cpp :2252).
        [78] = { name = 'Reward', effect = 42, seconds = 180, cures = { 2, 19, 193 }, coats = {
            [12646] = { 4, 3, 5 }, [14481] = { 4, 3, 5, 12, 13, 6 }, [15095] = { 12, 13, 6 }, [14508] = { 4, 3, 5, 12, 13, 6 } } },
        -- Repair: Regen from you for as long as the oil in your ammo slot gives, the first effects of this list your
        -- REPAIR_EFFECT gear says, then a wake-up (modules/era/lua/globals/job_utils/puppetmaster.lua :33-90, :95, :110-116,
        -- :138-141; gear at sql/item_mods.sql :6827, :28858).
        [137] = { name = 'Repair', effect = 42, cures = { 2, 19, 193 }, oils = { [18731] = 30, [18732] = 60, [18733] = 90, [19185] = 120 },
            repair_gear = { [11387] = 1, [15686] = 1 }, repair = { 194, 192, 217, 5, 4, 6, 9, 20, 8, 31, 12, 11, 21, 13, 7, 135, 134, 3,
                128, 129, 130, 131, 132, 133, 136, 137, 138, 139, 140, 141, 142, 146, 147, 148, 149, 174, 175, 404, 167, 189, 145, 144 } },
        -- Deep Breathing: Magic Atk. Boost on the wyvern for 180 s from you, until a breath uses it (era dragoon.lua :376, :385-390).
        [169] = { name = 'Deep Breathing', effect = 190, seconds = 180, on_you = true },
        -- Overdrive: yours and the automaton's start together for the same time; its copy is its own, so nothing tells you
        -- when it ends (era puppetmaster.lua :12-19).
        [135] = { name = 'Overdrive', effect = 166, follows = true },
        -- Spirit Link: its cures (scripts/globals/job_utils/dragoon.lua :248-272, called from era dragoon.lua :146) and
        -- Empathy's copies: each effect of yours flagged empathy, up to your merit's ranks, with the time it has left
        -- (era dragoon.lua :399-434, src/map/lua/lua_base_entity.cpp copyStatusEffect :14375-14407). With more flagged
        -- effects than ranks the server picks at random, so no copy can be known.
        [80] = { name = 'Spirit Link', cures = { 3, 135, 134, 192, 128, 129, 130, 131, 132, 133, 15, 2, 19, 193 }, empathy = 2884 }, -- data/merits.yaml :1130-1133
    },
    -- The effects data/status_effects.yaml flags empathy, by id (155, :331-5345).
    empathy = { 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 45, 56, 59, 60, 63, 64, 67, 68, 74, 75, 80, 81, 82, 83, 84, 85, 86, 88, 89, 90,
        91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 117, 118, 119, 120, 121,
        122, 123, 124, 125, 150, 152, 153, 154, 169, 170, 171, 172, 173, 176, 190, 191, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205,
        206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 220, 221, 222, 274, 277, 278, 279, 280, 281, 282, 286, 288, 310, 311,
        312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338,
        339, 353, 354, 368, 369, 370, 573, 600, 605, 606, 607, 615, 619, 622 },
    -- The maneuvers by ability, the effect each gives you (sql/abilities.sql :160-167) and their elements' names, in the
    -- order of those effects. Message 798 reports the chance of overload, 799 that you overloaded; overload is that effect,
    -- on you and the automaton, for the number reported less 5 (scripts/globals/automaton.lua :588-606).
    maneuvers = { [141] = 300, [142] = 301, [143] = 302, [144] = 303, [145] = 304, [146] = 305, [147] = 306, [148] = 307 },
    elements = { 'Fire', 'Ice', 'Wind', 'Earth', 'Thunder', 'Water', 'Light', 'Dark' },
    overload = 299,
    -- Call Beast's ability id (sql/abilities.sql :105).
    call_beast = 85,
    -- How long each jug pet stays, in seconds, by its name in sql/pet_list.sql :54-80. Familiar leaves this alone
    -- (scripts/globals/pets.lua :162-172).
    jugs = { SheepFamiliar = 3600, HareFamiliar = 5400, CrabFamiliar = 1800, CourierCarrie = 1800, Homunculus = 3600, FlytrapFamiliar = 3600,
        TigerFamiliar = 3600, FlowerpotBill = 3600, EftFamiliar = 3600, LizardFamiliar = 3600, MayflyFamiliar = 3600, FunguarFamiliar = 3600,
        BeetleFamiliar = 3600, AntlionFamiliar = 3600, MiteFamiliar = 3600, LullabyMelodia = 3600, KeenearedSteffi = 5400, FlowerpotBen = 3600,
        SaberSiravarde = 3600, ColdbloodComo = 3600, ShellbusterOrob = 3600, VoraciousAudrey = 3600, AmbusherAllie = 3600, LifedrinkerLars = 3600,
        PanzerGalahad = 3600, ChopsueyChucky = 3600, AmigoSabotender = 1800 },
    -- The pet each jug calls: its subskill in sql/item_weapon.sql :1497-1529 is the pet's id in pet_list
    -- (scripts/globals/job_utils/beastmaster.lua :63-86). For a pet whose name the client spells some other way.
    jug_items = { [17860] = 'HareFamiliar', [17861] = 'KeenearedSteffi', [17862] = 'MayflyFamiliar', [17863] = 'ShellbusterOrob',
        [17864] = 'SheepFamiliar', [17865] = 'LullabyMelodia', [17866] = 'LizardFamiliar', [17867] = 'ColdbloodComo', [17868] = 'FlowerpotBill',
        [17869] = 'FlowerpotBen', [17870] = 'TigerFamiliar', [17871] = 'SaberSiravarde', [17872] = 'BeetleFamiliar', [17873] = 'PanzerGalahad',
        [17876] = 'CrabFamiliar', [17877] = 'CourierCarrie', [17880] = 'FunguarFamiliar', [17882] = 'Homunculus', [17884] = 'AmigoSabotender',
        [17885] = 'FlytrapFamiliar', [17886] = 'VoraciousAudrey', [17887] = 'EftFamiliar', [17888] = 'AmbusherAllie', [17889] = 'MiteFamiliar',
        [17890] = 'LifedrinkerLars', [17891] = 'AntlionFamiliar', [17892] = 'ChopsueyChucky' },
    -- Your avatar's wards, by pact, from modules/era/lua/actions/abilities/pets/bloodpact_ward.lua: base seconds, and
    -- with per the seconds for each point of summoning skill over the cap, up to top. A flat one has no per. Aerial Armor
    -- and Earthen Ward keep their base scripts (scripts/actions/abilities/pets/aerial_armor.lua :17, earthen_ward.lua
    -- :17). Rolling Thunder reports a gain whether or not it took (:220-226), so your own copy says nothing about it.
    wards = {
        [514] = { name = 'Shining Ruby', base = 180 },                                 -- :28
        [515] = { name = 'Glittering Ruby', base = 90, per = 3, top = 180 },           -- :176-178
        [532] = { name = 'Ecliptic Growl', base = 180 },                               -- :267
        [533] = { name = 'Ecliptic Howl', base = 180 },                                -- :320
        [548] = { name = 'Crimson Howl', base = 30, per = 1, top = 180 },              -- :104-106
        [564] = { name = 'Earthen Ward', base = 900 },
        [595] = { name = 'Hastega', base = 90, per = 3, top = 180 },                   -- :76-78
        [596] = { name = 'Aerial Armor', base = 900 },
        [610] = { name = 'Frost Armor', base = 90, per = 3, top = 180 },               -- :134-136
        [626] = { name = 'Rolling Thunder', base = 60, per = 2, top = 180, always_reports = true }, -- :207-209
        [628] = { name = 'Lightning Armor', base = 90, per = 3, top = 180 },           -- :237-239
        [660] = { name = 'Noctoshield', base = 180 },                                  -- :415
        [661] = { name = 'Dream Shroud', base = 180 },                                 -- :439
    },
    -- The wards that give several effects and name none: they report with messages of their own and param 0 (:304-306,
    -- :347-349, :452-454; scripts/enum/msg.lua :150-151, :271-272, :292-293).
    ward_effects = { [532] = { 80, 81, 82, 83, 84, 85, 86 }, [533] = { 90, 92 }, [661] = { 190, 191 } },
    -- Glittering Ruby gives one of the seven stat boosts at random, named in its param (:157-186).
    glittering_ruby = { effect = 80, by_effect = { [80] = { effect = 80 }, [81] = { effect = 81 }, [82] = { effect = 82 }, [83] = { effect = 83 },
        [84] = { effect = 84 }, [85] = { effect = 85 }, [86] = { effect = 86 } } },
    -- Slowga: 180 s, plus a second for each point of summoning skill over 300, up to 200 (scripts/actions/abilities/pets/slowga.lua
    -- :16-18), before resists.
    slowga = { pact = 580, base = 180, from = 300, most = 200 },
    -- The summoning magic cap at each level, 1 to 75: SMN's rank A (data/skills.yaml :34, :44-118). Over it is what wards
    -- count (scripts/globals/summon.lua :21-27).
    summoning_caps = { 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 39, 42, 45, 48, 51, 54, 57, 60, 63, 66, 69, 72, 75, 78, 81, 84, 87, 90, 93, 96, 99,
        102, 105, 108, 111, 114, 117, 120, 123, 126, 129, 132, 135, 138, 141, 144, 147, 150, 153, 158, 163, 168, 173, 178, 183, 188, 193, 198, 203,
        207, 211, 215, 219, 223, 227, 231, 235, 239, 244, 249, 254, 259, 264, 269 },
    -- Automaton attachment skills as Phoenix plays them, by mob skill id (scripts/enum/mob_skill.lua :1242-1244, :1295, :1313).
    attachments = {
        [1946] = { effect = 37, seconds = 180 }, -- shock_absorber: modules/era/lua/actions/abilities/pets/automaton/attachments.lua :213
        [1947] = { effect = 156, seconds = 12 }, -- flashbulb: scripts/actions/abilities/pets/automaton/flashbulb.lua :16
        [1948] = { effect = 43, seconds = 30 },  -- mana_converter: mana_converter.lua :26
        [2031] = { effect = 34, seconds = 60 },  -- reactive_shield: reactive_shield.lua :22
        [2132] = { effect = 36, seconds = 300 }, -- replicator: era attachments.lua :193
    },
    -- A mob's Nightmare (tier 11) isn't taken off by hits, as tier 5 or more isn't (src/map/status_effect_container.cpp
    -- :856-864); your avatar's (tier 4) is. Mob skill ids.
    deep_sleeps = { 558, 1908 },
}
