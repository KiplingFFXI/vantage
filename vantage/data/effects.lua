-- Action effects, with Phoenix durations before resists.
-- An absent duration stays untimed. by_effect names each status of a move with several.
-- Built from phoenix/live ed41f351f6 by tools/export_catalog.py.
-- It assumes RESTRICT_CONTENT on, rotz cop toau on, the rest off.
-- Don't edit this file by hand.
return {
    -- What an effect removes.
    effects = {
        [2] = { drops = { 19, 193 } },  -- sleep_i
        [7] = { drops = { 18, 28 } },  -- petrification
        [8] = { drops = { 31 } },  -- disease
        [9] = { drops = { 20 } },  -- curse_i
        [12] = { drops = { 32 } },  -- weight
        [13] = { drops = { 33 } },  -- slow
        [18] = { drops = { 7, 28 } },  -- gradual_petrification
        [19] = { drops = { 2, 193 } },  -- sleep_ii
        [20] = { drops = { 9 } },  -- curse_ii
        [23] = { drops = { 228 } },  -- kaustra
        [28] = { drops = { 7, 18 } },  -- terror
        [29] = { drops = { 6 } },  -- mute
        [30] = { drops = { 9 } },  -- bane
        [31] = { drops = { 8 } },  -- plague
        [32] = { drops = { 12 } },  -- flee
        [33] = { drops = { 13 } },  -- haste
        [34] = { drops = { 35, 38, 153, 173, 403, 573, 605, 606, 607 } },  -- blaze_spikes
        [35] = { drops = { 34, 38, 153, 173, 403, 573, 605, 606, 607 } },  -- ice_spikes
        [36] = { drops = { 444, 445, 446 } },  -- blink
        [38] = { drops = { 34, 35, 153, 173, 403, 573, 605, 606, 607 } },  -- shock_spikes
        [51] = { -- blood_weapon
            drops = { 94, 95, 96, 97, 98, 99, 274, 275, 277, 278, 279, 280, 281, 282, 288, 487, 488 },
        },
        [66] = { drops = { 36 } },  -- copy_image
        [68] = { drops = { 460 } },  -- warcry
        [73] = { drops = { 115, 352 } },  -- barrage
        [80] = { drops = { 136 } },  -- str_boost
        [81] = { drops = { 137 } },  -- dex_boost
        [82] = { drops = { 138 } },  -- vit_boost
        [83] = { drops = { 139 } },  -- agi_boost
        [84] = { drops = { 140 } },  -- int_boost
        [85] = { drops = { 141 } },  -- mnd_boost
        [86] = { drops = { 142 } },  -- chr_boost
        [88] = { drops = { 144 } },  -- max_hp_boost
        [89] = { drops = { 145 } },  -- max_mp_boost
        [90] = { drops = { 146 } },  -- accuracy_boost
        [91] = { drops = { 147 } },  -- attack_boost
        [92] = { drops = { 148 } },  -- evasion_boost
        [93] = { drops = { 149 } },  -- defense_boost
        [94] = { -- enfire
            drops = { 51, 95, 96, 97, 98, 99, 274, 275, 277, 278, 279, 280, 281, 282, 288, 487, 488 },
        },
        [95] = { -- enblizzard
            drops = { 51, 94, 96, 97, 98, 99, 274, 275, 277, 278, 279, 280, 281, 282, 288, 487, 488 },
        },
        [96] = { -- enaero
            drops = { 51, 94, 95, 97, 98, 99, 274, 275, 277, 278, 279, 280, 281, 282, 288, 487, 488 },
        },
        [97] = { -- enstone
            drops = { 51, 94, 95, 96, 98, 99, 274, 275, 277, 278, 279, 280, 281, 282, 288, 487, 488 },
        },
        [98] = { -- enthunder
            drops = { 51, 94, 95, 96, 97, 99, 274, 275, 277, 278, 279, 280, 281, 282, 288, 487, 488 },
        },
        [99] = { -- enwater
            drops = { 51, 94, 95, 96, 97, 98, 274, 275, 277, 278, 279, 280, 281, 282, 288, 487, 488 },
        },
        [100] = { drops = { 101, 102, 103, 104, 105 } },  -- barfire
        [101] = { drops = { 100, 102, 103, 104, 105 } },  -- barblizzard
        [102] = { drops = { 100, 101, 103, 104, 105 } },  -- baraero
        [103] = { drops = { 100, 101, 102, 104, 105 } },  -- barstone
        [104] = { drops = { 100, 101, 102, 103, 105 } },  -- barthunder
        [105] = { drops = { 100, 101, 102, 103, 104 } },  -- barwater
        [106] = { drops = { 107, 108, 109, 110, 111, 112, 286 } },  -- barsleep
        [107] = { drops = { 106, 108, 109, 110, 111, 112, 286 } },  -- barpoison
        [108] = { drops = { 106, 107, 109, 110, 111, 112, 286 } },  -- barparalyze
        [109] = { drops = { 106, 107, 108, 110, 111, 112, 286 } },  -- barblind
        [110] = { drops = { 106, 107, 108, 109, 111, 112, 286 } },  -- barsilence
        [111] = { drops = { 106, 107, 108, 109, 110, 112, 286 } },  -- barpetrify
        [112] = { drops = { 106, 107, 108, 109, 110, 111, 286 } },  -- barvirus
        [115] = { drops = { 73, 352 } },  -- unlimited_shot
        [128] = { drops = { 129 } },  -- burn
        [129] = { drops = { 130 } },  -- frost
        [130] = { drops = { 131 } },  -- choke
        [131] = { drops = { 132 } },  -- rasp
        [132] = { drops = { 133 } },  -- shock
        [133] = { drops = { 128 } },  -- drown
        [135] = { drops = { 134 } },  -- bio
        [136] = { drops = { 80 } },  -- str_down
        [137] = { drops = { 81 } },  -- dex_down
        [138] = { drops = { 82 } },  -- vit_down
        [139] = { drops = { 83 } },  -- agi_down
        [140] = { drops = { 84 } },  -- int_down
        [141] = { drops = { 85 } },  -- mnd_down
        [142] = { drops = { 86 } },  -- chr_down
        [144] = { drops = { 88 } },  -- max_hp_down
        [145] = { drops = { 89 } },  -- max_mp_down
        [146] = { drops = { 90 } },  -- accuracy_down
        [147] = { drops = { 91 } },  -- attack_down
        [148] = { drops = { 92 } },  -- evasion_down
        [149] = { drops = { 93 } },  -- defense_down
        [153] = { drops = { 34, 35, 38, 173, 403, 573, 605, 606, 607 } },  -- damage_spikes
        [173] = { drops = { 34, 35, 38, 153, 403, 573, 605, 606, 607 } },  -- dread_spikes
        [193] = { drops = { 2, 19 } },  -- lullaby
        [228] = { drops = { 23 } },  -- embrava
        [235] = { drops = { 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248 } },  -- fishing_imagery
        [236] = { -- woodworking_imagery
            drops = { 235, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248 },
        },
        [237] = { -- smithing_imagery
            drops = { 235, 236, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248 },
        },
        [238] = { -- goldsmithing_imagery
            drops = { 235, 236, 237, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248 },
        },
        [239] = { -- clothcraft_imagery
            drops = { 235, 236, 237, 238, 240, 241, 242, 243, 244, 245, 246, 247, 248 },
        },
        [240] = { -- leathercraft_imagery
            drops = { 235, 236, 237, 238, 239, 241, 242, 243, 244, 245, 246, 247, 248 },
        },
        [241] = { -- bonecraft_imagery
            drops = { 235, 236, 237, 238, 239, 240, 242, 243, 244, 245, 246, 247, 248 },
        },
        [242] = { drops = { 235, 236, 237, 238, 239, 240, 241, 243, 244, 245, 246, 247, 248 } },  -- alchemy_imagery
        [243] = { drops = { 235, 236, 237, 238, 239, 240, 241, 242, 244, 245, 246, 247, 248 } },  -- cooking_imagery
        [244] = { drops = { 235, 236, 237, 238, 239, 240, 241, 242, 243, 245, 246, 247, 248 } },  -- imagery_1
        [245] = { drops = { 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 246, 247, 248 } },  -- imagery_2
        [246] = { drops = { 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 247, 248 } },  -- imagery_3
        [247] = { drops = { 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 248 } },  -- imagery_4
        [248] = { drops = { 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247 } },  -- imagery_5
        [274] = { -- enlight
            drops = { 51, 94, 95, 96, 97, 98, 99, 275, 277, 278, 279, 280, 281, 282, 288, 487, 488 },
        },
        [275] = { -- auspice
            drops = { 51, 94, 95, 96, 97, 98, 99, 274, 277, 278, 279, 280, 281, 282, 288, 487, 488 },
        },
        [277] = { -- enfire_ii
            drops = { 51, 94, 95, 96, 97, 98, 99, 274, 275, 278, 279, 280, 281, 282, 288, 487, 488 },
        },
        [278] = { -- enblizzard_ii
            drops = { 51, 94, 95, 96, 97, 98, 99, 274, 275, 277, 279, 280, 281, 282, 288, 487, 488 },
        },
        [279] = { -- enaero_ii
            drops = { 51, 94, 95, 96, 97, 98, 99, 274, 275, 277, 278, 280, 281, 282, 288, 487, 488 },
        },
        [280] = { -- enstone_ii
            drops = { 51, 94, 95, 96, 97, 98, 99, 274, 275, 277, 278, 279, 281, 282, 288, 487, 488 },
        },
        [281] = { -- enthunder_ii
            drops = { 51, 94, 95, 96, 97, 98, 99, 274, 275, 277, 278, 279, 280, 282, 288, 487, 488 },
        },
        [282] = { -- enwater_ii
            drops = { 51, 94, 95, 96, 97, 98, 99, 274, 275, 277, 278, 279, 280, 281, 288, 487, 488 },
        },
        [286] = { drops = { 106, 107, 108, 109, 110, 111, 112 } },  -- baramnesia
        [288] = { -- endark
            drops = { 51, 94, 95, 96, 97, 98, 99, 274, 275, 277, 278, 279, 280, 281, 282, 487, 488 },
        },
        [352] = { drops = { 73, 115 } },  -- sange
        [353] = { drops = { 354 } },  -- hasso
        [354] = { drops = { 353 } },  -- seigan
        [368] = { drops = { 369, 370 } },  -- drain_samba
        [369] = { drops = { 368, 370 } },  -- aspir_samba
        [370] = { drops = { 368, 369 } },  -- haste_samba
        [403] = { drops = { 34, 35, 38, 153, 173, 573, 605, 606, 607 } },  -- reprisal
        [420] = { drops = { 421 } },  -- yonin
        [421] = { drops = { 420 } },  -- innin
        [444] = { drops = { 36, 445, 446 } },  -- copy_image_2
        [445] = { drops = { 36, 444, 446 } },  -- copy_image_3
        [446] = { drops = { 36, 444, 445 } },  -- copy_image_4
        [460] = { drops = { 68 } },  -- blood_rage
        [482] = { drops = { 628 } },  -- decoy_shot
        [487] = { -- endrain
            drops = { 51, 94, 95, 96, 97, 98, 99, 274, 275, 277, 278, 279, 280, 281, 282, 288, 488 },
        },
        [488] = { -- enaspir
            drops = { 51, 94, 95, 96, 97, 98, 99, 274, 275, 277, 278, 279, 280, 281, 282, 288, 487 },
        },
        [573] = { drops = { 34, 35, 38, 153, 173, 403, 605, 606, 607 } },  -- deluge_spikes
        [605] = { drops = { 34, 35, 38, 153, 173, 403, 573, 606, 607 } },  -- gale_spikes
        [606] = { drops = { 34, 35, 38, 153, 173, 403, 573, 605, 607 } },  -- clod_spikes
        [607] = { drops = { 34, 35, 38, 153, 173, 403, 573, 605, 606 } },  -- glint_spikes
        [628] = { drops = { 482 } },  -- hover_shot
    },
    -- Spell IDs, filtered by enabled content.
    spells = {
        [1] = { effect = 37, seconds = 25 },  -- cure
        [2] = { effect = 37, seconds = 25 },  -- cure_ii
        [3] = { effect = 37, seconds = 25 },  -- cure_iii
        [4] = { effect = 37, seconds = 25 },  -- cure_iv
        [5] = { effect = 37, seconds = 25 },  -- cure_v
        [23] = { effect = 134, tier = 1, seconds = 60 },  -- dia
        [24] = { effect = 134, tier = 3, seconds = 120 },  -- dia_ii
        [25] = { effect = 134, tier = 5, merit = 'dia_iii' },  -- dia_iii
        [26] = { effect = 134, seconds = 180 },  -- dia_iv
        [27] = { effect = 134, seconds = 180 },  -- dia_v
        [33] = { effect = 134, tier = 1, seconds = 60 },  -- diaga
        [34] = { effect = 134, seconds = 120 },  -- diaga_ii
        [35] = { effect = 134, seconds = 180 },  -- diaga_iii
        [36] = { effect = 134, seconds = 180 },  -- diaga_iv
        [37] = { effect = 134, seconds = 180 },  -- diaga_v
        [43] = { effect = 40, seconds = 1800, tier = 1 },  -- protect
        [44] = { effect = 40, seconds = 1800, tier = 2 },  -- protect_ii
        [45] = { effect = 40, seconds = 1800, tier = 3 },  -- protect_iii
        [46] = { effect = 40, seconds = 1800, tier = 4 },  -- protect_iv
        [48] = { effect = 41, seconds = 1800, tier = 1 },  -- shell
        [49] = { effect = 41, seconds = 1800, tier = 2 },  -- shell_ii
        [50] = { effect = 41, seconds = 1800, tier = 3 },  -- shell_iii
        [51] = { effect = 41, seconds = 1800, tier = 4 },  -- shell_iv
        [53] = { effect = 36, seconds = 300, tier = 1 },  -- blink
        [54] = { effect = 37, seconds = 300, tier = 1 },  -- stoneskin
        [55] = { effect = 39, seconds = 600, tier = 1 },  -- aquaveil
        [56] = { effect = 13, seconds = 180, tier = 3 },  -- slow
        [57] = { effect = 33, seconds = 180, tier = 5 },  -- haste
        [58] = { effect = 4, seconds = 30, tier = 1, top = 120 },  -- paralyze
        [59] = { effect = 6, seconds = 30, tier = 1, top = 120 },  -- silence
        [60] = { effect = 100, seconds = 150, tier = 1 },  -- barfire
        [61] = { effect = 101, seconds = 150, tier = 1 },  -- barblizzard
        [62] = { effect = 102, seconds = 150, tier = 1 },  -- baraero
        [63] = { effect = 103, seconds = 150, tier = 1 },  -- barstone
        [64] = { effect = 104, seconds = 150, tier = 1 },  -- barthunder
        [65] = { effect = 105, seconds = 150, tier = 1 },  -- barwater
        [66] = { effect = 100, seconds = 150, tier = 2 },  -- barfira
        [67] = { effect = 101, seconds = 150, tier = 2 },  -- barblizzara
        [68] = { effect = 102, seconds = 150, tier = 2 },  -- baraera
        [69] = { effect = 103, seconds = 150, tier = 2 },  -- barstonra
        [70] = { effect = 104, seconds = 150, tier = 2 },  -- barthundra
        [71] = { effect = 105, seconds = 150, tier = 2 },  -- barwatera
        [72] = { effect = 106, seconds = 480, tier = 1 },  -- barsleep
        [73] = { effect = 107, seconds = 480, tier = 1 },  -- barpoison
        [74] = { effect = 108, seconds = 480, tier = 1 },  -- barparalyze
        [75] = { effect = 109, seconds = 480, tier = 1 },  -- barblind
        [76] = { effect = 110, seconds = 480, tier = 1 },  -- barsilence
        [77] = { effect = 111, seconds = 480, tier = 1 },  -- barpetrify
        [78] = { effect = 112, seconds = 480, tier = 1 },  -- barvirus
        [79] = { effect = 13, seconds = 180, tier = 7 },  -- slow_ii
        [80] = { effect = 4, seconds = 30, tier = 3, top = 120 },  -- paralyze_ii
        [86] = { effect = 106, seconds = 480, tier = 2 },  -- barsleepra
        [87] = { effect = 107, seconds = 480, tier = 2 },  -- barpoisonra
        [88] = { effect = 108, seconds = 480, tier = 2 },  -- barparalyzra
        [89] = { effect = 109, seconds = 480, tier = 2 },  -- barblindra
        [90] = { effect = 110, seconds = 480, tier = 2 },  -- barsilencera
        [91] = { effect = 111, seconds = 480, tier = 2 },  -- barpetra
        [92] = { effect = 112, seconds = 480, tier = 2 },  -- barvira
        [99] = { effect = 181, seconds = 180, tier = 1 },  -- sandstorm
        [100] = { effect = 94, seconds = 180, tier = 1 },  -- enfire
        [101] = { effect = 95, seconds = 180, tier = 1 },  -- enblizzard
        [102] = { effect = 96, seconds = 180, tier = 1 },  -- enaero
        [103] = { effect = 97, seconds = 180, tier = 1 },  -- enstone
        [104] = { effect = 98, seconds = 180, tier = 1 },  -- enthunder
        [105] = { effect = 99, seconds = 180, tier = 1 },  -- enwater
        [106] = { effect = 116, seconds = 180, tier = 1 },  -- phalanx
        [107] = { effect = 116, seconds = 120, tier = 2 },  -- phalanx_ii
        [108] = { effect = 42, seconds = 75, tier = 1 },  -- regen
        [109] = { effect = 43, seconds = 150, tier = 1 },  -- refresh
        [110] = { effect = 42, seconds = 60, tier = 2 },  -- regen_ii
        [111] = { effect = 42, seconds = 60, tier = 3 },  -- regen_iii
        [112] = { effect = 156, seconds = 12, tier = 1 },  -- flash
        [113] = { effect = 183, seconds = 180, tier = 1 },  -- rainstorm
        [114] = { effect = 180, seconds = 180, tier = 1 },  -- windstorm
        [115] = { effect = 178, seconds = 180, tier = 1 },  -- firestorm
        [116] = { effect = 179, seconds = 180, tier = 1 },  -- hailstorm
        [117] = { effect = 182, seconds = 180, tier = 1 },  -- thunderstorm
        [118] = { effect = 185, seconds = 180, tier = 1 },  -- voidstorm
        [119] = { effect = 184, seconds = 180, tier = 1 },  -- aurorastorm
        [125] = { effect = 40, seconds = 1800, tier = 1 },  -- protectra
        [126] = { effect = 40, seconds = 1800, tier = 2 },  -- protectra_ii
        [127] = { effect = 40, seconds = 1800, tier = 3 },  -- protectra_iii
        [128] = { effect = 40, seconds = 1800, tier = 4 },  -- protectra_iv
        [129] = { effect = 40, seconds = 1800, tier = 5 },  -- protectra_v
        [130] = { effect = 41, seconds = 1800, tier = 1 },  -- shellra
        [131] = { effect = 41, seconds = 1800, tier = 2 },  -- shellra_ii
        [132] = { effect = 41, seconds = 1800, tier = 3 },  -- shellra_iii
        [133] = { effect = 41, seconds = 1800, tier = 4 },  -- shellra_iv
        [134] = { effect = 41, seconds = 1800, tier = 5 },  -- shellra_v
        [135] = { effect = 113, seconds = 3600 },  -- reraise
        [136] = { effect = 69, seconds = 30, tier = 1, top = 300 },  -- invisible
        [137] = { effect = 71, seconds = 30, tier = 1, top = 300 },  -- sneak
        [138] = { effect = 70, seconds = 30, tier = 1, top = 300 },  -- deodorize
        [141] = { effect = 113, seconds = 3600 },  -- reraise_ii
        [142] = { effect = 113, seconds = 3600 },  -- reraise_iii
        [216] = { effect = 12, seconds = 120, tier = 1 },  -- gravity
        [220] = { effect = 3, seconds = 30, tier = 1 },  -- poison
        [221] = { effect = 3, seconds = 120, tier = 2 },  -- poison_ii
        [222] = { effect = 3, seconds = 150, tier = 3 },  -- poison_iii
        [225] = { effect = 3, seconds = 30, tier = 1 },  -- poisonga
        [226] = { effect = 3, seconds = 120, tier = 1 },  -- poisonga_ii
        [227] = { effect = 3, seconds = 150, tier = 1 },  -- poisonga_iii
        [230] = { effect = 135, tier = 2, seconds = 60 },  -- bio
        [231] = { effect = 135, tier = 4, seconds = 120 },  -- bio_ii
        [232] = { effect = 135, tier = 6, merit = 'bio_iii' },  -- bio_iii
        [233] = { effect = 135, seconds = 180 },  -- bio_iv
        [234] = { effect = 135, seconds = 180 },  -- bio_v
        [235] = { effect = 128, seconds = 90, tier = 1 },  -- burn
        [236] = { effect = 129, seconds = 90, tier = 1 },  -- frost
        [237] = { effect = 130, seconds = 90, tier = 1 },  -- choke
        [238] = { effect = 131, seconds = 90, tier = 1 },  -- rasp
        [239] = { effect = 132, seconds = 90, tier = 1 },  -- shock
        [240] = { effect = 133, seconds = 90, tier = 1 },  -- drown
        [249] = { effect = 34, seconds = 180, tier = 1 },  -- blaze_spikes
        [250] = { effect = 35, seconds = 180, tier = 1 },  -- ice_spikes
        [251] = { effect = 38, seconds = 180, tier = 1 },  -- shock_spikes
        [252] = { effect = 10, seconds = 2, tier = 1, top = 7 },  -- stun
        [253] = { effect = 2, seconds = 60, tier = 1 },  -- sleep
        [254] = { effect = 5, seconds = 80, tier = 1, top = 300 },  -- blind
        [256] = { effect = 31, seconds = 60, tier = 1 },  -- virus
        [257] = { effect = 9, seconds = 300, tier = 1 },  -- curse
        [258] = { effect = 11, seconds = 13, tier = 1, top = 60 },  -- bind
        [259] = { effect = 2, seconds = 90, tier = 2 },  -- sleep_ii
        [266] = { effect = 136, seconds = 90 },  -- absorb_str
        [267] = { effect = 137, seconds = 90 },  -- absorb_dex
        [268] = { effect = 138, seconds = 90 },  -- absorb_vit
        [269] = { effect = 139, seconds = 90 },  -- absorb_agi
        [270] = { effect = 140, seconds = 90 },  -- absorb_int
        [271] = { effect = 141, seconds = 90 },  -- absorb_mnd
        [272] = { effect = 142, seconds = 90 },  -- absorb_chr
        [273] = { effect = 2, seconds = 60, tier = 1 },  -- sleepga
        [274] = { effect = 2, seconds = 90, tier = 2 },  -- sleepga_ii
        [276] = { effect = 5, seconds = 80, tier = 3, top = 300 },  -- blind_ii
        [277] = { effect = 173, tier = 1, seconds = 60 },  -- dread_spikes
        [278] = { effect = 186, seconds = 30, tier = 1 },  -- geohelix
        [279] = { effect = 186, seconds = 30, tier = 1 },  -- hydrohelix
        [280] = { effect = 186, seconds = 30, tier = 1 },  -- anemohelix
        [281] = { effect = 186, seconds = 30, tier = 1 },  -- pyrohelix
        [282] = { effect = 186, seconds = 30, tier = 1 },  -- cryohelix
        [283] = { effect = 186, seconds = 30, tier = 1 },  -- ionohelix
        [284] = { effect = 186, seconds = 30, tier = 1 },  -- noctohelix
        [285] = { effect = 186, seconds = 30, tier = 1 },  -- luminohelix
        [341] = { effect = 4, seconds = 180, tier = 1 },  -- jubaku_ichi
        [342] = { effect = 4, seconds = 300, tier = 2 },  -- jubaku_ni
        [343] = { effect = 4, seconds = 420, tier = 3 },  -- jubaku_san
        [344] = { effect = 13, seconds = 180, tier = 3 },  -- hojo_ichi
        [345] = { effect = 13, seconds = 300, tier = 4 },  -- hojo_ni
        [346] = { effect = 13, seconds = 420, tier = 7 },  -- hojo_san
        [347] = { effect = 5, seconds = 180, tier = 1 },  -- kurayami_ichi
        [348] = { effect = 5, seconds = 300, tier = 2 },  -- kurayami_ni
        [349] = { effect = 5, seconds = 420, tier = 3 },  -- kurayami_san
        [350] = { effect = 3, seconds = 60, tier = 1 },  -- dokumori_ichi
        [351] = { effect = 3, seconds = 120, tier = 2 },  -- dokumori_ni
        [352] = { effect = 3, seconds = 360, tier = 3 },  -- dokumori_san
        [356] = { effect = 4, seconds = 120, tier = 2 },  -- paralyga
        [357] = { effect = 13, seconds = 180, tier = 8 },  -- slowga
        [358] = { effect = 33, seconds = 180, tier = 5 },  -- hastega
        [359] = { effect = 6, seconds = 120, tier = 2 },  -- silencega
        [361] = { effect = 5, seconds = 180, tier = 2 },  -- blindga
        [362] = { effect = 11, seconds = 60, tier = 1 },  -- bindga
        [366] = { effect = 12, seconds = 120, tier = 1 },  -- graviga
        [368] = { effect = 192, seconds = 64, tier = 1, song = 'requiem' },  -- foe_requiem
        [369] = { effect = 192, seconds = 80, tier = 2, song = 'requiem' },  -- foe_requiem_ii
        [370] = { effect = 192, seconds = 96, tier = 3, song = 'requiem' },  -- foe_requiem_iii
        [371] = { effect = 192, seconds = 112, tier = 4, song = 'requiem' },  -- foe_requiem_iv
        [372] = { effect = 192, seconds = 128, tier = 5, song = 'requiem' },  -- foe_requiem_v
        [373] = { effect = 192, seconds = 144, tier = 6, song = 'requiem' },  -- foe_requiem_vi
        [376] = { effect = 2, seconds = 30, tier = 1, song = 'lullaby' },  -- horde_lullaby
        [378] = { effect = 195, seconds = 120, tier = 1 },  -- armys_paeon
        [379] = { effect = 195, seconds = 120, tier = 2 },  -- armys_paeon_ii
        [380] = { effect = 195, seconds = 120, tier = 3 },  -- armys_paeon_iii
        [381] = { effect = 195, seconds = 120, tier = 4 },  -- armys_paeon_iv
        [382] = { effect = 195, seconds = 120, tier = 5 },  -- armys_paeon_v
        [386] = { effect = 196, seconds = 120, tier = 1 },  -- mages_ballad
        [387] = { effect = 196, seconds = 120, tier = 2 },  -- mages_ballad_ii
        [389] = { effect = 197, seconds = 120, tier = 1 },  -- knights_minne
        [390] = { effect = 197, seconds = 120, tier = 2 },  -- knights_minne_ii
        [391] = { effect = 197, seconds = 120, tier = 3 },  -- knights_minne_iii
        [392] = { effect = 197, seconds = 120, tier = 4 },  -- knights_minne_iv
        [394] = { effect = 198, seconds = 120, tier = 1 },  -- valor_minuet
        [395] = { effect = 198, seconds = 120, tier = 2 },  -- valor_minuet_ii
        [396] = { effect = 198, seconds = 120, tier = 3 },  -- valor_minuet_iii
        [397] = { effect = 198, seconds = 120, tier = 4 },  -- valor_minuet_iv
        [399] = { effect = 199, seconds = 120, tier = 1 },  -- sword_madrigal
        [400] = { effect = 199, seconds = 120, tier = 2 },  -- blade_madrigal
        [401] = { effect = 200, seconds = 120, tier = 1 },  -- hunters_prelude
        [402] = { effect = 200, seconds = 120, tier = 2 },  -- archers_prelude
        [403] = { effect = 201, seconds = 120, tier = 1 },  -- sheepfoe_mambo
        [404] = { effect = 201, seconds = 120, tier = 2 },  -- dragonfoe_mambo
        [405] = { effect = 202, seconds = 120, tier = 1 },  -- fowl_aubade
        [406] = { effect = 203, seconds = 120, tier = 1 },  -- herb_pastoral
        [408] = { effect = 205, seconds = 120, tier = 1 },  -- shining_fantasia
        [409] = { effect = 206, seconds = 120, tier = 1 },  -- scops_operetta
        [410] = { effect = 206, seconds = 120, tier = 2 },  -- puppets_operetta
        [412] = { effect = 207, seconds = 120, tier = 1 },  -- gold_capriccio
        [414] = { effect = 209, seconds = 120, tier = 1 },  -- warding_round
        [415] = { effect = 210, seconds = 120, tier = 1 },  -- goblin_gavotte
        [417] = { effect = 214, seconds = 120, tier = 3 },  -- moogle_rhapsody
        [419] = { effect = 214, seconds = 120, tier = 1 },  -- advancing_march
        [420] = { effect = 214, seconds = 120, tier = 2 },  -- victory_march
        [421] = { effect = 194, seconds = 120, tier = 1, song = 'elegy' },  -- battlefield_elegy
        [422] = { effect = 194, seconds = 180, tier = 1, song = 'elegy' },  -- carnage_elegy
        [423] = { effect = 194, seconds = 180, tier = 1, song = 'elegy' },  -- massacre_elegy
        [424] = { effect = 215, seconds = 120, tier = 1 },  -- sinewy_etude
        [425] = { effect = 215, seconds = 120, tier = 1 },  -- dextrous_etude
        [426] = { effect = 215, seconds = 120, tier = 1 },  -- vivacious_etude
        [427] = { effect = 215, seconds = 120, tier = 1 },  -- quick_etude
        [428] = { effect = 215, seconds = 120, tier = 1 },  -- learned_etude
        [429] = { effect = 215, seconds = 120, tier = 1 },  -- spirited_etude
        [430] = { effect = 215, seconds = 120, tier = 1 },  -- enchanting_etude
        [431] = { effect = 215, seconds = 120, tier = 2 },  -- herculean_etude
        [432] = { effect = 215, seconds = 120, tier = 2 },  -- uncanny_etude
        [433] = { effect = 215, seconds = 120, tier = 2 },  -- vital_etude
        [434] = { effect = 215, seconds = 120, tier = 2 },  -- swift_etude
        [435] = { effect = 215, seconds = 120, tier = 2 },  -- sage_etude
        [436] = { effect = 215, seconds = 120, tier = 2 },  -- logical_etude
        [437] = { effect = 215, seconds = 120, tier = 2 },  -- bewitching_etude
        [438] = { effect = 216, seconds = 120, tier = 1 },  -- fire_carol
        [439] = { effect = 216, seconds = 120, tier = 1 },  -- ice_carol
        [440] = { effect = 216, seconds = 120, tier = 1 },  -- wind_carol
        [441] = { effect = 216, seconds = 120, tier = 1 },  -- earth_carol
        [442] = { effect = 216, seconds = 120, tier = 1 },  -- lightning_carol
        [443] = { effect = 216, seconds = 120, tier = 1 },  -- water_carol
        [444] = { effect = 216, seconds = 120, tier = 1 },  -- light_carol
        [445] = { effect = 216, seconds = 120, tier = 1 },  -- dark_carol
        [454] = { effect = 217, seconds = 60, tier = 1, song = 'threnody' },  -- fire_threnody
        [455] = { effect = 217, seconds = 60, tier = 1, song = 'threnody' },  -- ice_threnody
        [456] = { effect = 217, seconds = 60, tier = 1, song = 'threnody' },  -- wind_threnody
        [457] = { effect = 217, seconds = 60, tier = 1, song = 'threnody' },  -- earth_threnody
        [458] = { effect = 217, seconds = 60, tier = 1, song = 'threnody' },  -- lightning_threnody
        [459] = { effect = 217, seconds = 60, tier = 1, song = 'threnody' },  -- water_threnody
        [460] = { effect = 217, seconds = 60, tier = 1, song = 'threnody' },  -- light_threnody
        [461] = { effect = 217, seconds = 60, tier = 1, song = 'threnody' },  -- dark_threnody
        [463] = { effect = 2, seconds = 30, tier = 1, song = 'lullaby' },  -- foe_lullaby
        [464] = { effect = 218, seconds = 120, tier = 1 },  -- goddesss_hymnus
        [465] = { effect = 219, seconds = 120, tier = 1 },  -- chocobo_mazurka
        [467] = { effect = 219, seconds = 120, tier = 1 },  -- raptor_mazurka
        [468] = { effect = 220, seconds = 120, tier = 1 },  -- foe_sirvente
        [469] = { effect = 221, seconds = 120, tier = 1 },  -- adventurers_dirge
        [513] = { effect = 3, seconds = 60 },  -- venom_shell
        [515] = { effect = 136, seconds = 60 },  -- maelstrom
        [517] = { effect = 37 },  -- metallic_body
        [524] = { effect = 146, seconds = 60 },  -- sandspin
        [530] = { effect = 33 },  -- refueling
        [531] = { effect = 11, seconds = 30 },  -- ice_break
        [532] = { effect = 10, seconds = 5 },  -- blitzstrahl
        [533] = { effect = 1, seconds = 300 },  -- self-destruct
        [534] = { effect = 12, seconds = 60 },  -- mysterious_light
        [536] = { effect = 3, seconds = 60 },  -- poison_breath
        [537] = { effect = 138, seconds = 60 },  -- stinking_gas
        [538] = { effect = 190 },  -- memento_mori
        [539] = { effect = 147, seconds = 60 },  -- terror_touch
        [547] = { effect = 93 },  -- cocoon
        [548] = { effect = 13, seconds = 90 },  -- filamented_hold
        [555] = { effect = 12, seconds = 60 },  -- magnetite_cloud
        [561] = { effect = 149, seconds = 180 },  -- frightful_roar
        [563] = { effect = 5, seconds = 60 },  -- hecatomb_wave
        [565] = { -- radiant_breath
            effect = 6,
            seconds = 60,
            by_effect = {
                [6] = { effect = 6, seconds = 60 },
                [13] = { effect = 13, seconds = 60 },
            },
        },
        [572] = { effect = 140, seconds = 30 },  -- sound_blast
        [574] = { effect = 92 },  -- feather_barrier
        [575] = { effect = 28, seconds = 5 },  -- jettatura
        [576] = { effect = 2, seconds = 90 },  -- yawn
        [582] = { effect = 6, seconds = 120 },  -- chaotic_eye
        [584] = { effect = 2, seconds = 60 },  -- sheep_song
        [588] = { effect = 31, seconds = 60 },  -- lowing
        [596] = { effect = 2 },  -- pinecone_bomb
        [597] = { effect = 13 },  -- sprout_smack
        [598] = { effect = 2, seconds = 90 },  -- soporific
        [599] = { effect = 3 },  -- queasyshroom
        [603] = { effect = 138 },  -- wild_oats
        [604] = { -- bad_breath
            effect = 3,
            seconds = 60,
            by_effect = {
                [3] = { effect = 3, seconds = 60 },
                [4] = { effect = 4, seconds = 60 },
                [5] = { effect = 5, seconds = 60 },
                [6] = { effect = 6, seconds = 60 },
                [11] = { effect = 11, seconds = 60 },
                [12] = { effect = 12, seconds = 60 },
                [13] = { effect = 13, seconds = 60 },
            },
        },
        [606] = { effect = 136, seconds = 30 },  -- awful_eye
        [608] = { effect = 4, seconds = 60 },  -- frost_breath
        [610] = { effect = 148, seconds = 60 },  -- infrasonics
        [611] = { effect = 3, seconds = 180 },  -- disseverment
        [612] = { effect = 156, seconds = 16 },  -- actinic_burst
        [613] = { effect = 35, by_effect = { [93] = { effect = 93 }, [35] = { effect = 35 } } },  -- reactor_cool
        [614] = { effect = 191 },  -- saline_coat
        [615] = { effect = 38 },  -- plasma_charge
        [616] = { effect = 10, seconds = 5 },  -- temporal_shift
        [618] = { effect = 11, seconds = 30 },  -- blastbomb
        [620] = { effect = 137 },  -- battle_dance
        [621] = { effect = 5, seconds = 120 },  -- sandspray
        [623] = { effect = 10, seconds = 8, top = 8 },  -- head_butt
        [628] = { effect = 10, seconds = 5 },  -- frypan
        [632] = { effect = 37 },  -- diamondhide
        [633] = { -- enervation
            effect = 149,
            seconds = 30,
            by_effect = {
                [149] = { effect = 149, seconds = 30 },
                [167] = { effect = 167, seconds = 30 },
            },
        },
        [634] = { -- light_of_penance
            effect = 5,
            seconds = 30,
            by_effect = {
                [5] = { effect = 5, seconds = 30 },
                [11] = { effect = 11, seconds = 30 },
            },
        },
        [636] = { effect = 90, by_effect = { [90] = { effect = 90 }, [92] = { effect = 92 } } },  -- warm-up
        [638] = { effect = 3 },  -- feather_storm
        [640] = { effect = 10, seconds = 5 },  -- tail_slap
        [642] = { -- amplification
            effect = 190,
            by_effect = {
                [190] = { effect = 190 },
                [191] = { effect = 191 },
            },
        },
        [644] = { effect = 4, seconds = 90 },  -- mind_blast
        [647] = { effect = 36 },  -- zephyr_mantle
        [648] = { effect = 11, seconds = 30 },  -- regurgitation
        [650] = { effect = 149, seconds = 120 },  -- seedspray
        [651] = { -- corrosive_ooze
            effect = 147,
            seconds = 90,
            by_effect = {
                [147] = { effect = 147, seconds = 90 },
                [149] = { effect = 149, seconds = 90 },
            },
        },
        [652] = { effect = 146, seconds = 60 },  -- spiral_spin
        [654] = { effect = 4, seconds = 180 },  -- sub-zero_smash
        [655] = { effect = 91 },  -- triumphant_roar
        [885] = { effect = 186, seconds = 30, tier = 2 },  -- geohelix_ii
        [886] = { effect = 186, seconds = 30, tier = 2 },  -- hydrohelix_ii
        [887] = { effect = 186, seconds = 30, tier = 2 },  -- anemohelix_ii
        [888] = { effect = 186, seconds = 30, tier = 2 },  -- pyrohelix_ii
        [889] = { effect = 186, seconds = 30, tier = 2 },  -- cryohelix_ii
        [890] = { effect = 186, seconds = 30, tier = 2 },  -- ionohelix_ii
        [891] = { effect = 186, seconds = 30, tier = 2 },  -- noctohelix_ii
        [892] = { effect = 186, seconds = 30, tier = 2 },  -- luminohelix_ii
    },
    -- Player ability IDs.
    abilities = {
        [16] = { effect = 44, seconds = 45 },  -- mighty_strikes
        [17] = { effect = 46 },  -- hundred_fists
        [19] = { effect = 47, seconds = 60 },  -- manafont
        [20] = { effect = 48, seconds = 60 },  -- chainspell
        [21] = { effect = 49 },  -- perfect_dodge
        [22] = { effect = 50, seconds = 30 },  -- invincible
        [23] = { effect = 51 },  -- blood_weapon
        [25] = { effect = 52, seconds = 180 },  -- soul_voice
        [27] = { effect = 54, seconds = 30 },  -- meikyo_shisui
        [29] = { effect = 126, seconds = 60 },  -- spirit_surge
        [30] = { effect = 55, seconds = 180 },  -- astral_flow
        [31] = { effect = 56 },  -- berserk
        [32] = { effect = 68 },  -- warcry
        [33] = { effect = 57 },  -- defender
        [34] = { effect = 58 },  -- aggressor
        [36] = { effect = 59, seconds = 120 },  -- focus
        [37] = { effect = 60, seconds = 120 },  -- dodge
        [38] = { effect = 42 },  -- chakra
        [39] = { effect = 45, seconds = 180 },  -- boost
        [40] = { effect = 61 },  -- counterstance
        [42] = { effect = 32 },  -- flee
        [43] = { effect = 76 },  -- hide
        [44] = { effect = 65, seconds = 60 },  -- sneak_attack
        [46] = { effect = 10, seconds = 8, top = 8 },  -- shield_bash
        [47] = { effect = 74 },  -- holy_circle
        [48] = { effect = 62 },  -- sentinel
        [49] = { effect = 63 },  -- souleater
        [50] = { effect = 75 },  -- arcane_circle
        [51] = { effect = 64, seconds = 30 },  -- last_resort
        [52] = { effect = 11, seconds = 5 },  -- charm
        [57] = { effect = 11, seconds = 30, gear = 'shadowbind' },  -- Shadowbind
        [58] = { effect = 77 },  -- camouflage
        [59] = { effect = 72, seconds = 60 },  -- sharpshot
        [60] = { effect = 73, seconds = 60 },  -- barrage
        [62] = { effect = 67, seconds = 30 },  -- third_eye
        [64] = { effect = 117 },  -- warding_circle
        [65] = { effect = 118 },  -- ancient_circle
        [66] = { -- jump
            effect = 149,
            seconds = 60,
        },
        [74] = { effect = 78, seconds = 60 },  -- divine_seal
        [75] = { effect = 79, seconds = 60 },  -- elemental_seal
        [76] = { effect = 87, seconds = 60 },  -- trick_attack
        [77] = { effect = 10, seconds = 8, top = 8 },  -- weapon_bash
        [78] = { effect = 42, seconds = 180 },  -- reward
        [79] = { effect = 114 },  -- cover
        [82] = { -- chi_blast
            effect = 168,
            merit = 'penance',
        },
        [92] = { effect = 623 },  -- rampart
        [93] = { effect = 163, seconds = 30 },  -- azure_lore
        [94] = { effect = 164, seconds = 30 },  -- chain_affinity
        [95] = { effect = 165, seconds = 30 },  -- burst_affinity
        [98] = { -- fighters_roll
            effect = 308,
            seconds = 45,
            by_effect = {
                [308] = { effect = 308, seconds = 45 },
                [309] = { effect = 309 },
            },
        },
        [99] = { -- monks_roll
            effect = 308,
            seconds = 45,
            by_effect = {
                [308] = { effect = 308, seconds = 45 },
                [309] = { effect = 309 },
            },
        },
        [100] = { -- healers_roll
            effect = 308,
            seconds = 45,
            by_effect = {
                [308] = { effect = 308, seconds = 45 },
                [309] = { effect = 309 },
            },
        },
        [101] = { -- wizards_roll
            effect = 308,
            seconds = 45,
            by_effect = {
                [308] = { effect = 308, seconds = 45 },
                [309] = { effect = 309 },
            },
        },
        [102] = { -- warlocks_roll
            effect = 308,
            seconds = 45,
            by_effect = {
                [308] = { effect = 308, seconds = 45 },
                [309] = { effect = 309 },
            },
        },
        [103] = { -- rogues_roll
            effect = 308,
            seconds = 45,
            by_effect = {
                [308] = { effect = 308, seconds = 45 },
                [309] = { effect = 309 },
            },
        },
        [104] = { -- gallants_roll
            effect = 308,
            seconds = 45,
            by_effect = {
                [308] = { effect = 308, seconds = 45 },
                [309] = { effect = 309 },
            },
        },
        [105] = { -- chaos_roll
            effect = 308,
            seconds = 45,
            by_effect = {
                [308] = { effect = 308, seconds = 45 },
                [309] = { effect = 309 },
            },
        },
        [106] = { -- beast_roll
            effect = 308,
            seconds = 45,
            by_effect = {
                [308] = { effect = 308, seconds = 45 },
                [309] = { effect = 309 },
            },
        },
        [107] = { -- choral_roll
            effect = 308,
            seconds = 45,
            by_effect = {
                [308] = { effect = 308, seconds = 45 },
                [309] = { effect = 309 },
            },
        },
        [108] = { -- hunters_roll
            effect = 308,
            seconds = 45,
            by_effect = {
                [308] = { effect = 308, seconds = 45 },
                [309] = { effect = 309 },
            },
        },
        [109] = { -- samurai_roll
            effect = 308,
            seconds = 45,
            by_effect = {
                [308] = { effect = 308, seconds = 45 },
                [309] = { effect = 309 },
            },
        },
        [110] = { -- ninja_roll
            effect = 308,
            seconds = 45,
            by_effect = {
                [308] = { effect = 308, seconds = 45 },
                [309] = { effect = 309 },
            },
        },
        [111] = { -- drachen_roll
            effect = 308,
            seconds = 45,
            by_effect = {
                [308] = { effect = 308, seconds = 45 },
                [309] = { effect = 309 },
            },
        },
        [112] = { -- evokers_roll
            effect = 308,
            seconds = 45,
            by_effect = {
                [308] = { effect = 308, seconds = 45 },
                [309] = { effect = 309 },
            },
        },
        [113] = { -- maguss_roll
            effect = 308,
            seconds = 45,
            by_effect = {
                [308] = { effect = 308, seconds = 45 },
                [309] = { effect = 309 },
            },
        },
        [114] = { -- corsairs_roll
            effect = 308,
            seconds = 45,
            by_effect = {
                [308] = { effect = 308, seconds = 45 },
                [309] = { effect = 309 },
            },
        },
        [115] = { -- puppet_roll
            effect = 308,
            seconds = 45,
            by_effect = {
                [308] = { effect = 308, seconds = 45 },
                [309] = { effect = 309 },
            },
        },
        [123] = { effect = 309 },  -- double-up
        [131] = { effect = 2, seconds = 90 },  -- Light Shot
        [135] = { effect = 166 },  -- overdrive
        [137] = { effect = 42 },  -- repair
        [149] = { effect = 340, seconds = 60 },  -- warriors_charge
        [151] = { effect = 88 },  -- mantra
        [152] = { effect = 341 },  -- formless_strikes
        [155] = { effect = 342, seconds = 60 },  -- assassins_charge
        [156] = { effect = 343, seconds = 60 },  -- feint
        [157] = { effect = 344 },  -- fealty
        [159] = { effect = 345, seconds = 60 },  -- dark_seal
        [160] = { effect = 346, seconds = 180 },  -- diabolic_eye
        [161] = { effect = 28, seconds = 10 },  -- feral_howl
        [162] = { effect = 349, seconds = 60 },  -- killer_instinct
        [163] = { effect = 347, seconds = 60 },  -- nightingale
        [164] = { effect = 348, seconds = 60 },  -- troubadour
        [168] = { -- blade_bash
            effect = 10,
            seconds = 6,
            by_effect = {
                [10] = { effect = 10, seconds = 6 },
                [31] = { effect = 31, seconds = 15 },
            },
        },
        [169] = { effect = 190, seconds = 180 },  -- deep_breathing
        [170] = { effect = 149, merit = 'angon' },  -- Angon
        [171] = { effect = 352, seconds = 60 },  -- sange
        [173] = { effect = 353, seconds = 300 },  -- hasso
        [174] = { effect = 354, seconds = 300 },  -- seigan
        [175] = { effect = 355, seconds = 60 },  -- convergence
        [176] = { effect = 356, seconds = 60 },  -- diffusion
        [177] = { effect = 357, seconds = 60 },  -- snake_eye
    },
    -- Monster skill IDs.
    skills = {
        [2] = { effect = 10, seconds = 10 },  -- shoulder_tackle
        [15] = { effect = 31, seconds = 30 },  -- shijin_spiral
        [16] = { effect = 3 },  -- wasp_sting
        [17] = { effect = 3 },  -- viper_bite
        [18] = { effect = 11 },  -- shadowstitch
        [28] = { effect = 12, seconds = 60 },  -- mordant_rime
        [29] = { effect = 148 },  -- pyrrhic_kleos
        [31] = { effect = 12, seconds = 60 },  -- rudras_storm
        [35] = { effect = 10, seconds = 4 },  -- flat_blade
        [44] = { effect = 404, seconds = 60 },  -- death_blossom
        [52] = { effect = 2, seconds = 300 },  -- shockwave
        [58] = { effect = 4, seconds = 300 },  -- herculean_slash
        [65] = { effect = 10, seconds = 4 },  -- smash_axe
        [66] = { effect = 130, seconds = 60 },  -- gale_axe
        [73] = { effect = 146, seconds = 60 },  -- onslaught
        [75] = { effect = 11, seconds = 20 },  -- bora_axe
        [80] = { effect = 148 },  -- shield_break
        [83] = { effect = 149 },  -- armor_break
        [85] = { effect = 147 },  -- weapon_break
        [87] = { -- full_break
            effect = 146,
            by_effect = {
                [146] = { effect = 146 },
                [147] = { effect = 147 },
                [148] = { effect = 148 },
                [149] = { effect = 149 },
            },
        },
        [89] = { effect = 149, seconds = 120 },  -- metatron_torment
        [92] = { effect = 13, seconds = 60 },  -- ukkos_fury
        [99] = { effect = 5 },  -- nightmare_scythe
        [102] = { effect = 6 },  -- guillotine
        [107] = { effect = 147 },  -- infernal_scythe
        [115] = { effect = 10, seconds = 4 },  -- leg_sweep
        [121] = { effect = 38 },  -- geirskogul
        [125] = { effect = 298, seconds = 60 },  -- stardiver
        [129] = { effect = 4, seconds = 210 },  -- blade_retsu
        [137] = { effect = 4, seconds = 60 },  -- blade_metsu
        [138] = { effect = 146 },  -- blade_kamu
        [139] = { effect = 3 },  -- blade_yu
        [145] = { effect = 10, seconds = 3 },  -- tachi_hobaku
        [150] = { effect = 5, seconds = 60 },  -- tachi_yukikaze
        [151] = { effect = 6, seconds = 45 },  -- tachi_gekko
        [152] = { effect = 4, seconds = 60 },  -- tachi_kasha
        [155] = { effect = 149 },  -- tachi_ageha
        [162] = { effect = 10, seconds = 3 },  -- brainshaker
        [165] = { effect = 140, seconds = 120 },  -- skullbreaker
        [170] = { effect = 148, seconds = 120 },  -- randgrith
        [172] = { effect = 156, seconds = 15 },  -- flash_nova
        [181] = { effect = 149 },  -- shell_crusher
        [185] = { effect = 147, seconds = 120 },  -- gate_of_tartarus
        [186] = { effect = 167 },  -- vidohunir
        [187] = { effect = 149 },  -- garland_of_bliss
        [188] = { effect = 175 },  -- omniscience
        [191] = { effect = 167, seconds = 120 },  -- shattersoul
        [194] = { effect = 140, seconds = 120 },  -- dulling_arrow
        [210] = { effect = 140, seconds = 140 },  -- sniper_shot
        [219] = { effect = 4, seconds = 300 },  -- numbing_shot
        [224] = { effect = 146 },  -- exenterator
        [238] = { effect = 156, seconds = 15 },  -- uriel_blade
        [239] = { effect = 10, seconds = 4 },  -- glory_slash
        [240] = { -- tartarus_torpor
            effect = 2,
            seconds = 300,
            by_effect = {
                [2] = { effect = 2, seconds = 300 },
                [167] = { effect = 167, seconds = 300 },
                [404] = { effect = 404, seconds = 300 },
            },
        },
        [241] = { effect = 11, seconds = 30 },  -- netherspikes
        [243] = { effect = 149, seconds = 120 },  -- aegis_schism
        [244] = { effect = 133, seconds = 60 },  -- dancing_chains
        [245] = { effect = 146, seconds = 180 },  -- barbed_crescent
        [247] = { effect = 10, seconds = 15 },  -- foxfire
        [249] = { effect = 11, seconds = 30 },  -- netherspikes
        [251] = { effect = 149, seconds = 120 },  -- aegis_schism
        [252] = { effect = 133, seconds = 60 },  -- dancing_chains
        [253] = { effect = 146, seconds = 180 },  -- barbed_crescent
        [254] = { effect = 149, seconds = 80 },  -- vulcan_shot
        [258] = { effect = 5, seconds = 120 },  -- dust_cloud
        [261] = { effect = 56, seconds = 120 },  -- rage
        [264] = { effect = 2, seconds = 45 },  -- sheep_song
        [265] = { effect = 56, seconds = 120 },  -- rage
        [267] = { effect = 148 },  -- rumble
        [268] = { effect = 144, seconds = 120 },  -- great_bleat
        [269] = { effect = 7, seconds = 120 },  -- petribreath
        [270] = { effect = 4, seconds = 120 },  -- roar
        [275] = { effect = 5, seconds = 90 },  -- sand_blast
        [276] = { effect = 11, seconds = 60 },  -- sand_pit
        [277] = { effect = 3 },  -- venom_spray
        [280] = { effect = 149, seconds = 180 },  -- sonic_wave
        [284] = { effect = 6, seconds = 70 },  -- cold_stare
        [285] = { effect = 83, seconds = 210 },  -- whistle
        [286] = { effect = 56, seconds = 120 },  -- berserk
        [289] = { effect = 4, seconds = 60 },  -- stone_throw
        [291] = { effect = 3, seconds = 60 },  -- claw_storm
        [294] = { effect = 5, seconds = 60 },  -- eye_scratch
        [299] = { effect = 11, seconds = 60 },  -- entangle_drain
        [301] = { effect = 2, seconds = 60 },  -- dream_flower
        [302] = { effect = 138, seconds = 120 },  -- wild_oats
        [304] = { effect = 42, seconds = 120 },  -- photosynthesis_mandragora
        [305] = { effect = 3, seconds = 180 },  -- leaf_dagger
        [306] = { effect = 141, seconds = 180 },  -- scream
        [309] = { effect = 4, seconds = 180 },  -- spore
        [310] = { effect = 3, seconds = 120 },  -- queasyshroom
        [311] = { effect = 4, seconds = 180 },  -- numbshroom
        [312] = { effect = 8, seconds = 720 },  -- shakeshroom
        [314] = { effect = 6, seconds = 60 },  -- silence_gas
        [315] = { effect = 5, seconds = 90 },  -- dark_spore
        [316] = { effect = 11, seconds = 15 },  -- impale_bind
        [319] = { -- bad_breath
            effect = 3,
            seconds = 60,
            by_effect = {
                [3] = { effect = 3, seconds = 60 },
                [4] = { effect = 4, seconds = 60 },
                [5] = { effect = 5, seconds = 60 },
                [6] = { effect = 6, seconds = 60 },
                [11] = { effect = 11, seconds = 60 },
                [12] = { effect = 12, seconds = 60 },
                [13] = { effect = 13, seconds = 60 },
            },
        },
        [320] = { effect = 2, seconds = 60 },  -- sweet_breath
        [324] = { effect = 42, seconds = 180 },  -- photosynthesis_sabotender
        [328] = { effect = 5, seconds = 45 },  -- drill_branch
        [329] = { effect = 2, seconds = 60 },  -- pinecone_bomb
        [332] = { effect = 11, seconds = 60 },  -- entangle
        [339] = { effect = 148, seconds = 180 },  -- hi-freq_field
        [341] = { effect = 92, seconds = 540 },  -- rhino_guard
        [343] = { effect = 136, seconds = 540 },  -- spoil
        [344] = { effect = 13, seconds = 540 },  -- sticky_thread
        [345] = { effect = 3, seconds = 300 },  -- poison_breath_crawler
        [346] = { effect = 93, seconds = 180 },  -- cocoon
        [348] = { effect = 4, seconds = 180 },  -- numbing_breath
        [349] = { effect = 11, seconds = 60 },  -- cold_breath
        [351] = { effect = 3, seconds = 60 },  -- poison_sting
        [354] = { effect = 3, seconds = 60 },  -- wild_rage
        [355] = { effect = 137, seconds = 180 },  -- earth_pounder
        [356] = { effect = 91, seconds = 540 },  -- sharp_strike
        [359] = { effect = 61, seconds = 60 },  -- bionic_boost
        [361] = { effect = 10, seconds = 4 },  -- earth_shock
        [364] = { effect = 13, seconds = 120 },  -- filamented_hold
        [366] = { effect = 10, seconds = 4 },  -- tail_blow
        [369] = { effect = 6, seconds = 30 },  -- brain_crush
        [370] = { effect = 7, seconds = 60 },  -- baleful_gaze_lizard
        [371] = { effect = 3, seconds = 120 },  -- plague_breath
        [372] = { effect = 148, seconds = 180 },  -- infrasonics
        [373] = { effect = 92, seconds = 60 },  -- secretion
        [376] = { effect = 8, seconds = 180 },  -- foul_breath
        [377] = { effect = 4, seconds = 180 },  -- frost_breath
        [378] = { effect = 10, seconds = 7 },  -- thunderbolt_raptor
        [379] = { effect = 13, seconds = 180 },  -- chomp_rush
        [380] = { effect = 10, seconds = 4 },  -- scythe_tail
        [384] = { effect = 93, seconds = 180 },  -- scutum
        [385] = { effect = 31, seconds = 60 },  -- bone_crunch
        [386] = { effect = 136, seconds = 180 },  -- awful_eye
        [387] = { effect = 10, seconds = 6 },  -- heavy_bellow
        [390] = { effect = 92, seconds = 180 },  -- mirage
        [391] = { effect = 93, seconds = 90 },  -- aura_of_persistence
        [392] = { effect = 148, seconds = 180 },  -- ultrasonics
        [393] = { effect = 147, seconds = 540 },  -- sonic_boom
        [399] = { effect = 5, seconds = 120 },  -- blind_vortex
        [401] = { effect = 10, seconds = 4 },  -- dread_dive
        [402] = { effect = 92, seconds = 1020 },  -- feather_barrier
        [407] = { effect = 3, seconds = 60 },  -- poison_pick
        [408] = { effect = 6, seconds = 120 },  -- sound_vacuum_cockatrice
        [410] = { effect = 140, seconds = 180 },  -- sound_blast
        [411] = { effect = 7, seconds = 120 },  -- baleful_gaze_cockatrice
        [414] = { effect = 10, seconds = 4 },  -- suction
        [415] = { effect = 147, seconds = 120 },  -- acid_mist
        [416] = { effect = 5, seconds = 120 },  -- sand_breath
        [418] = { effect = 42, seconds = 300 },  -- regeneration
        [423] = { effect = 140, seconds = 120 },  -- brain_drain
        [425] = { effect = 147, seconds = 180 },  -- gastric_bomb
        [426] = { effect = 146, seconds = 180 },  -- sandspin
        [427] = { effect = 137, seconds = 180 },  -- tremors
        [429] = { effect = 6, seconds = 90 },  -- sound_vacuum_worm
        [434] = { effect = 2, seconds = 30 },  -- soporific
        [435] = { effect = 4, seconds = 60 },  -- palsy_pollen
        [436] = { effect = 13, seconds = 180 },  -- gloeosuccus
        [438] = { effect = 4, seconds = 120 },  -- hex_eye
        [439] = { effect = 7, seconds = 25 },  -- petro_gaze
        [442] = { effect = 136, seconds = 180 },  -- bubble_shower
        [443] = { effect = 41, seconds = 180 },  -- bubble_curtain
        [445] = { effect = 93, seconds = 60 },  -- scissor_guard
        [448] = { effect = 37, seconds = 300 },  -- metallic_body
        [449] = { effect = 13, seconds = 120 },  -- intimidate
        [450] = { effect = 136, seconds = 180 },  -- aqua_ball
        [453] = { effect = 93, seconds = 90 },  -- water_wall
        [454] = { effect = 92, seconds = 90 },  -- water_shield
        [457] = { effect = 12, seconds = 120 },  -- gravity_wheel
        [458] = { effect = 5, seconds = 120 },  -- ink_jet
        [459] = { effect = 92, seconds = 540 },  -- hard_membrane
        [461] = { effect = 42, seconds = 300 },  -- regeneration
        [462] = { effect = 136, seconds = 180 },  -- maelstrom
        [463] = { effect = 138, seconds = 120 },  -- whirlwind
        [465] = { effect = 4, seconds = 60 },  -- howling
        [466] = { effect = 3, seconds = 300 },  -- poison_breath_hound
        [467] = { effect = 8, seconds = 360 },  -- rot_gas
        [469] = { effect = 5, seconds = 30 },  -- shadow_claw
        [471] = { effect = 152, seconds = 30 },  -- mind_wall
        [475] = { effect = 147, seconds = 90 },  -- terror_touch
        [476] = { effect = 9, seconds = 2280 },  -- curse
        [477] = { effect = 5, seconds = 300 },  -- dark_sphere
        [479] = { effect = 13, seconds = 300 },  -- horror_cloud
        [480] = { effect = 7, seconds = 60 },  -- petrifactive_breath
        [484] = { effect = 5, seconds = 480 },  -- black_cloud
        [486] = { effect = 10, seconds = 4 },  -- whip_tongue
        [487] = { effect = 150, seconds = 30 },  -- transmogrification
        [488] = { effect = 136, seconds = 180 },  -- acid_breath
        [489] = { effect = 138, seconds = 180 },  -- stinking_gas
        [490] = { effect = 8, seconds = 660 },  -- undead_mold
        [491] = { effect = 140, seconds = 120 },  -- call_of_the_grave
        [492] = { effect = 5, seconds = 120 },  -- abyss_blast
        [493] = { effect = 4, seconds = 120 },  -- rampant_gnaw
        [496] = { effect = 92, seconds = 60 },  -- rabid_dance
        [497] = { effect = 31, seconds = 60 },  -- lowing
        [498] = { effect = 137, seconds = 90 },  -- triclip
        [500] = { effect = 3, seconds = 30 },  -- mow
        [501] = { effect = 149, seconds = 180 },  -- frightful_roar
        [502] = { effect = 15, seconds = 45 },  -- mortal_ray
        [503] = { effect = 41, seconds = 180 },  -- unblessed_armor
        [504] = { effect = 3, seconds = 90 },  -- gas_shell
        [505] = { -- venom_shell
            effect = 3,
            seconds = 180,
            by_effect = {
                [3] = { effect = 3, seconds = 180 },
                [31] = { effect = 31, seconds = 45 },
            },
        },
        [506] = { effect = 4, seconds = 120 },  -- palsynyxis
        [508] = { effect = 11, seconds = 90 },  -- suctorial_tentacle
        [510] = { effect = 56, seconds = 120 },  -- berserk
        [512] = { effect = 128, seconds = 180 },  -- heat_wave
        [514] = { effect = 10, seconds = 10 },  -- whirl_of_rage
        [515] = { effect = 3, seconds = 180 },  -- toxic_spit
        [517] = { effect = 10, seconds = 10 },  -- numbing_noise
        [522] = { effect = 152, seconds = 60 },  -- spectral_barrier
        [523] = { effect = 12, seconds = 120 },  -- mysterious_light
        [524] = { effect = 141, seconds = 300 },  -- mind_drain
        [525] = { effect = 43, seconds = 198 },  -- battery_charge
        [526] = { effect = 56, seconds = 120 },  -- berserk
        [528] = { effect = 129, seconds = 180 },  -- cold_wave
        [530] = { effect = 190, seconds = 300 },  -- memento_mori
        [531] = { effect = 6, seconds = 60 },  -- silence_seal
        [532] = { effect = 9, seconds = 180 },  -- envoutement
        [533] = { effect = 14, seconds = 60 },  -- danse_macabre
        [534] = { effect = 2, seconds = 90 },  -- kartstrahl
        [535] = { effect = 10, seconds = 15 },  -- blitzstrahl
        [537] = { effect = 68, seconds = 120 },  -- berserk_doll
        [540] = { effect = 10, seconds = 3 },  -- tremorous_tread
        [541] = { effect = 13, seconds = 420 },  -- gravity_field
        [545] = { effect = 12, seconds = 180 },  -- somnolence
        [546] = { effect = 116, seconds = 120 },  -- noctoshield
        [548] = { effect = 5, seconds = 30 },  -- blindeye
        [550] = { effect = 2, seconds = 135 },  -- hypnosis
        [551] = { effect = 145, seconds = 10 },  -- mind_break
        [552] = { effect = 11, seconds = 90 },  -- binding_wave
        [553] = { effect = 151, seconds = 60 },  -- airy_shield
        [555] = { effect = 152, seconds = 60 },  -- magic_barrier
        [556] = { -- dream_shroud
            effect = 190,
            seconds = 180,
            by_effect = {
                [190] = { effect = 190, seconds = 180 },
                [191] = { effect = 191, seconds = 180 },
            },
        },
        [557] = { effect = 7, seconds = 105 },  -- level_5_petrify
        [558] = { -- nightmare
            effect = 2,
            seconds = 90,
            by_effect = {
                [2] = { effect = 2, seconds = 90 },
                [135] = { effect = 135, seconds = 90 },
            },
        },
        [560] = { effect = 5, seconds = 120 },  -- hecatomb_wave
        [562] = { effect = 38, seconds = 180 },  -- reactive_armor
        [563] = { effect = 13, seconds = 540 },  -- demonic_howl
        [569] = { effect = 33, seconds = 180 },  -- refueling
        [570] = { effect = 12, seconds = 120 },  -- circle_of_flames
        [577] = { effect = 28, seconds = 15 },  -- jettatura
        [579] = { -- choke_breath
            effect = 4,
            seconds = 30,
            by_effect = {
                [4] = { effect = 4, seconds = 30 },
                [6] = { effect = 6, seconds = 30 },
            },
        },
        [580] = { effect = 45, seconds = 180 },  -- fantod
        [581] = { effect = 10, seconds = 4 },  -- blow
        [582] = { effect = 9, seconds = 60 },  -- cacodemonia
        [583] = { effect = 11, seconds = 60 },  -- beatdown
        [586] = { effect = 4, seconds = 180 },  -- blank_gaze
        [587] = { effect = 6, seconds = 90 },  -- antiphase
        [588] = { -- death_trap
            effect = 3,
            seconds = 300,
            by_effect = {
                [3] = { effect = 3, seconds = 300 },
                [10] = { effect = 10, seconds = 15 },
            },
        },
        [589] = { effect = 15, seconds = 35 },  -- mortal_ray_minotaur
        [593] = { effect = 56, seconds = 180 },  -- berserk_bomb_big
        [595] = { effect = 128, seconds = 180 },  -- heat_wave
        [598] = { effect = 56, seconds = 120 },  -- berserk
        [600] = { effect = 129, seconds = 180 },  -- cold_wave
        [603] = { effect = 61, seconds = 300 },  -- counterstance_1
        [605] = { effect = 10, seconds = 10 },  -- aerial_wheel
        [607] = { effect = 11, seconds = 60 },  -- slam_dunk
        [608] = { effect = 93, seconds = 1020 },  -- arm_block
        [609] = { effect = 137, seconds = 180 },  -- battle_dance
        [612] = { effect = 10, seconds = 10 },  -- head_butt_quadav
        [613] = { effect = 10, seconds = 10 },  -- shell_bash
        [614] = { effect = 93, seconds = 1560 },  -- shell_guard
        [617] = { effect = 3, seconds = 45 },  -- feather_storm
        [618] = { effect = 10, seconds = 10 },  -- double_kick
        [619] = { effect = 93, seconds = 1440 },  -- parry
        [620] = { effect = 10, seconds = 10 },  -- sweep
        [629] = { effect = 10, seconds = 14 },  -- thunderbolt_behemoth
        [630] = { effect = 5, seconds = 120 },  -- kick_out
        [632] = { effect = 34, seconds = 180 },  -- flame_armor
        [633] = { effect = 68, seconds = 180 },  -- howl
        [638] = { effect = 11, seconds = 90 },  -- blastbomb
        [643] = { effect = 3, seconds = 180 },  -- poison_breath_dragon_1
        [646] = { effect = 4, seconds = 960 },  -- heavy_stomp
        [647] = { effect = 9, seconds = 420 },  -- chaos_blade
        [648] = { effect = 7, seconds = 420 },  -- petro_eyes
        [650] = { effect = 153, seconds = 30 },  -- thornsong
        [651] = { effect = 12, seconds = 30 },  -- lodesong
        [652] = { effect = 4, seconds = 60 },  -- blaster
        [653] = { effect = 6, seconds = 60 },  -- chaotic_eye
        [660] = { effect = 3, seconds = 60 },  -- venom
        [661] = { effect = 4, seconds = 120 },  -- snow_cloud
        [674] = { effect = 40, seconds = 300 },  -- crystal_shield
        [676] = { effect = 11, seconds = 240 },  -- ice_break
        [677] = { effect = 10, seconds = 20 },  -- thunder_break
        [686] = { effect = 2, seconds = 30 },  -- slumber_powder
        [687] = { effect = 13, seconds = 90 },  -- sprout_smack
        [688] = { effect = 44, seconds = 45 },  -- mighty_strikes
        [690] = { effect = 46, seconds = 45 },  -- hundred_fists
        [691] = { effect = 47, seconds = 60 },  -- manafont
        [692] = { effect = 48, seconds = 60 },  -- chainspell
        [693] = { effect = 49, seconds = 30 },  -- perfect_dodge
        [694] = { effect = 50, seconds = 30 },  -- invincible
        [695] = { effect = 51, seconds = 30 },  -- blood_weapon
        [696] = { effect = 52, seconds = 180 },  -- soul_voice
        [710] = { effect = 14 },  -- charm
        [717] = { effect = 3, seconds = 60 },  -- venom_breath
        [720] = { effect = 3, seconds = 30 },  -- venom_sting
        [721] = { effect = 4, seconds = 20 },  -- stasis
        [722] = { effect = 3, seconds = 60 },  -- venom_storm
        [723] = { effect = 10, seconds = 15 },  -- earthbreaker
        [724] = { effect = 92, seconds = 180 },  -- evasion
        [725] = { effect = 4, seconds = 120 },  -- impale
        [727] = { -- bad_breath
            effect = 3,
            seconds = 60,
            by_effect = {
                [3] = { effect = 3, seconds = 60 },
                [4] = { effect = 4, seconds = 60 },
                [5] = { effect = 5, seconds = 60 },
                [6] = { effect = 6, seconds = 60 },
                [11] = { effect = 11, seconds = 60 },
                [12] = { effect = 12, seconds = 60 },
                [13] = { effect = 13, seconds = 60 },
            },
        },
        [728] = { effect = 2, seconds = 60 },  -- sweet_breath
        [729] = { -- death_trap
            effect = 3,
            seconds = 300,
            by_effect = {
                [3] = { effect = 3, seconds = 300 },
                [10] = { effect = 10, seconds = 15 },
            },
        },
        [730] = { effect = 54, seconds = 30 },  -- meikyo_shisui
        [750] = { effect = 4, seconds = 90 },  -- stygian_flatus
        [752] = { effect = 93, seconds = 180 },  -- promyvion_barrier
        [753] = { effect = 93, seconds = 180 },  -- promyvion_barrier
        [762] = { effect = 68, seconds = 180 },  -- howl
        [764] = { effect = 68, seconds = 180 },  -- howl
        [766] = { effect = 68, seconds = 180 },  -- howl
        [771] = { effect = 136, seconds = 120 },  -- hydro_ball
        [774] = { effect = 41, seconds = 180 },  -- bubble_armor
        [780] = { effect = 10, seconds = 10 },  -- spinning_fin
        [783] = { effect = 9, seconds = 45 },  -- words_of_bane
        [784] = { effect = 92, seconds = 15 },  -- sigh
        [785] = { -- light_of_penance
            effect = 5,
            seconds = 60,
            by_effect = {
                [5] = { effect = 5, seconds = 60 },
                [11] = { effect = 11, seconds = 60 },
            },
        },
        [786] = { effect = 149, seconds = 30 },  -- lateral_slash
        [787] = { effect = 146, seconds = 30 },  -- vertical_slash
        [789] = { effect = 3, seconds = 60 },  -- spikeball
        [791] = { effect = 12, seconds = 60 },  -- magnetite_cloud
        [792] = { effect = 5, seconds = 90 },  -- sandstorm
        [793] = { effect = 92, seconds = 120 },  -- sand_veil
        [794] = { effect = 93, seconds = 90 },  -- sand_shield
        [795] = { effect = 7, seconds = 15 },  -- sand_trap
        [796] = { effect = 6, seconds = 120 },  -- jamming_wave
        [798] = { effect = 11, seconds = 60 },  -- tail_swing
        [799] = { effect = 11, seconds = 60 },  -- tail_smash
        [801] = { effect = 145, seconds = 60 },  -- riddle
        [802] = { effect = 5, seconds = 180 },  -- great_sandstorm
        [803] = { effect = 130, seconds = 90 },  -- great_whirlwind
        [805] = { effect = 146, seconds = 180 },  -- head_butt_turtle
        [806] = { effect = 149, seconds = 180 },  -- tortoise_stomp
        [807] = { effect = 93, seconds = 180 },  -- harden_shell
        [811] = { effect = 3, seconds = 60 },  -- acid_spray
        [812] = { effect = 13, seconds = 90 },  -- spider_web
        [815] = { effect = 92, seconds = 105 },  -- wind_wall
        [817] = { effect = 4, seconds = 60 },  -- dread_shriek
        [818] = { effect = 3 },  -- tail_crush
        [821] = { -- radiant_breath
            effect = 6,
            seconds = 120,
            by_effect = {
                [6] = { effect = 6, seconds = 120 },
                [13] = { effect = 13, seconds = 120 },
            },
        },
        [823] = { effect = 94, seconds = 1800 },  -- fire_blade
        [824] = { effect = 95, seconds = 1800 },  -- frost_blade
        [825] = { effect = 96, seconds = 1800 },  -- wind_blade_kam
        [826] = { effect = 97, seconds = 1800 },  -- earth_blade
        [827] = { effect = 98, seconds = 1800 },  -- lightning_blade
        [828] = { effect = 99, seconds = 1800 },  -- water_blade
        [831] = { effect = 5, seconds = 120 },  -- moonlit_charge
        [832] = { effect = 4, seconds = 90 },  -- crescent_fang
        [833] = { -- lunar_cry
            effect = 146,
            seconds = 180,
            by_effect = {
                [146] = { effect = 146, seconds = 180 },
                [148] = { effect = 148, seconds = 180 },
            },
        },
        [844] = { effect = 68, seconds = 180 },  -- crimson_howl
        [849] = { effect = 13, seconds = 120 },  -- rock_throw
        [852] = { effect = 13, seconds = 120 },  -- megalith_throw
        [853] = { effect = 37, seconds = 180 },  -- earthen_ward
        [855] = { effect = 11, seconds = 60 },  -- mountain_buster
        [856] = { effect = 10, seconds = 6 },  -- geocrush
        [860] = { effect = 12, seconds = 120 },  -- tail_whip
        [871] = { effect = 36, seconds = 180 },  -- aerial_armor
        [878] = { effect = 35, seconds = 180 },  -- frost_armor
        [879] = { effect = 2, seconds = 90 },  -- sleepga
        [885] = { effect = 10, seconds = 12 },  -- shock_strike
        [888] = { effect = 4, seconds = 60 },  -- thunderspark
        [889] = { effect = 38, seconds = 180 },  -- lightning_armor
        [891] = { effect = 10, seconds = 10 },  -- chaotic_strike
        [907] = { effect = 3, seconds = 60 },  -- poison_nails
        [922] = { effect = 5, seconds = 120 },  -- blind_vortex
        [924] = { effect = 10, seconds = 4 },  -- dread_dive
        [927] = { effect = 5, seconds = 45 },  -- drill_branch_nm
        [929] = { effect = 13, seconds = 120 },  -- leafstorm_dispel
        [930] = { -- entangle_poison
            effect = 3,
            seconds = 180,
            by_effect = {
                [3] = { effect = 3, seconds = 180 },
                [11] = { effect = 11, seconds = 60 },
            },
        },
        [931] = { effect = 10, seconds = 4 },  -- cross_reaver
        [932] = { effect = 2, seconds = 60 },  -- havoc_spiral
        [933] = { effect = 6, seconds = 60 },  -- dominion_slash
        [934] = { effect = 10, seconds = 6 },  -- shield_strike
        [935] = { -- amon_drive
            effect = 3,
            seconds = 60,
            by_effect = {
                [3] = { effect = 3, seconds = 60 },
                [4] = { effect = 4, seconds = 60 },
                [7] = { effect = 7 },
            },
        },
        [937] = { effect = 11, seconds = 30 },  -- dragonfall
        [945] = { effect = 6 },  -- guillotine
        [946] = { effect = 5, seconds = 60 },  -- tachi_yukikaze
        [947] = { effect = 6, seconds = 45 },  -- tachi_gekko
        [948] = { effect = 4, seconds = 60 },  -- tachi_kasha
        [951] = { effect = 5, seconds = 30 },  -- hurricane_wing
        [956] = { effect = 5, seconds = 30 },  -- hurricane_wing_flying
        [957] = { effect = 28 },  -- absolute_terror
        [960] = { effect = 3, seconds = 60 },  -- acid_spray
        [961] = { effect = 13, seconds = 90 },  -- spider_web
        [969] = { effect = 10, seconds = 4 },  -- flat_blade
        [971] = { effect = 10, seconds = 4 },  -- royal_bash
        [972] = { -- royal_savior
            effect = 37,
            seconds = 60,
            by_effect = {
                [37] = { effect = 37, seconds = 60 },
                [40] = { effect = 40, seconds = 300 },
                [93] = { effect = 93, seconds = 60 },
                [478] = { effect = 478, seconds = 60 },
            },
        },
        [976] = { effect = 68, seconds = 180 },  -- berserk_volker
        [983] = { effect = 10, seconds = 15 },  -- abyssal_strike
        [985] = { effect = 6, seconds = 30 },  -- stellar_burst
        [986] = { -- vortex
            effect = 11,
            seconds = 30,
            by_effect = {
                [11] = { effect = 11, seconds = 30 },
                [28] = { effect = 28, seconds = 9 },
            },
        },
        [987] = { effect = 2, seconds = 300 },  -- shockwave
        [991] = { effect = 11, seconds = 10 },  -- uranos_cascade_eta
        [995] = { effect = 11, seconds = 10 },  -- uranos_cascade_theta
        [997] = { effect = 10, seconds = 15 },  -- phase_shift_2
        [999] = { effect = 11, seconds = 10 },  -- uranos_cascade_lambda
        [1001] = { -- phase_shift_3
            effect = 10,
            seconds = 15,
            by_effect = {
                [10] = { effect = 10, seconds = 15 },
                [11] = { effect = 11, seconds = 30 },
            },
        },
        [1006] = { effect = 7, seconds = 45 },  -- omega_javelin
        [1008] = { effect = 44, seconds = 45 },  -- mighty_strikes
        [1009] = { effect = 46, seconds = 45 },  -- hundred_fists
        [1011] = { effect = 47, seconds = 60 },  -- manafont
        [1012] = { effect = 48, seconds = 60 },  -- chainspell
        [1013] = { effect = 49, seconds = 30 },  -- perfect_dodge
        [1014] = { effect = 50, seconds = 30 },  -- invincible
        [1015] = { effect = 51, seconds = 30 },  -- blood_weapon
        [1018] = { effect = 52, seconds = 180 },  -- soul_voice
        [1020] = { effect = 54, seconds = 30 },  -- meikyo_shisui
        [1026] = { effect = 12, seconds = 60 },  -- arbor_storm
        [1028] = { effect = 10, seconds = 4 },  -- tackle
        [1036] = { effect = 10, seconds = 4 },  -- maats_bash
        [1039] = { effect = 5, seconds = 30 },  -- hurricane_wing
        [1045] = { effect = 28 },  -- absolute_terror
        [1057] = { effect = 10, seconds = 10 },  -- aerial_wheel
        [1059] = { effect = 11, seconds = 60 },  -- slam_dunk
        [1060] = { effect = 93, seconds = 60 },  -- arm_block_dynamis
        [1061] = { effect = 137, seconds = 180 },  -- battle_dance
        [1062] = { effect = 68, seconds = 60 },  -- howl_dynamis
        [1066] = { effect = 14, seconds = 180 },  -- fanatic_dance
        [1067] = { effect = 15, seconds = 35 },  -- doom
        [1068] = { effect = 3, seconds = 45 },  -- feather_storm
        [1069] = { effect = 10, seconds = 10 },  -- double_kick
        [1070] = { effect = 93, seconds = 60 },  -- parry_dynamis
        [1071] = { effect = 10, seconds = 10 },  -- sweep
        [1072] = { effect = 68, seconds = 60 },  -- howl_dynamis
        [1073] = { effect = 15, seconds = 35 },  -- doom
        [1074] = { effect = 12, seconds = 60 },  -- the_wrath_of_gudha
        [1076] = { effect = 10, seconds = 10 },  -- head_butt_quadav
        [1077] = { effect = 10, seconds = 10 },  -- shell_bash
        [1078] = { effect = 93, seconds = 60 },  -- shell_guard_dynamis
        [1079] = { effect = 68, seconds = 60 },  -- howl_dynamis
        [1080] = { effect = 12, seconds = 60 },  -- the_wrath_of_gudha
        [1081] = { effect = 10, seconds = 4 },  -- frypan
        [1082] = { effect = 5, seconds = 120 },  -- smokebomb
        [1083] = { effect = 5, seconds = 120 },  -- smokebomb
        [1086] = { effect = 4, seconds = 120 },  -- paralysis_shower
        [1087] = { effect = 4, seconds = 120 },  -- paralysis_shower
        [1092] = { effect = 10, seconds = 4 },  -- frypan
        [1093] = { effect = 5, seconds = 120 },  -- smokebomb
        [1097] = { effect = 4, seconds = 120 },  -- paralysis_shower
        [1100] = { effect = 12, seconds = 90 },  -- dice_gravity
        [1102] = { effect = 10, seconds = 15 },  -- dice_stun
        [1103] = { effect = 3, seconds = 90 },  -- dice_poison
        [1104] = { effect = 8, seconds = 90 },  -- dice_disease
        [1105] = { effect = 2, seconds = 90 },  -- dice_sleep
        [1106] = { -- dice_slow
            effect = 13,
            seconds = 90,
            by_effect = {
                [6] = { effect = 6, seconds = 90 },
                [13] = { effect = 13, seconds = 90 },
            },
        },
        [1110] = { effect = 10, seconds = 10 },  -- seismostomp
        [1111] = { effect = 4, seconds = 180 },  -- numbing_glare
        [1112] = { effect = 10, seconds = 10 },  -- seismostomp
        [1113] = { effect = 9, seconds = 360 },  -- tormentful_glare
        [1114] = { effect = 10, seconds = 10 },  -- seismostomp
        [1115] = { effect = 2, seconds = 30 },  -- torpid_glare
        [1116] = { effect = 10, seconds = 10 },  -- seismostomp
        [1117] = { effect = 12, seconds = 300 },  -- lead_breath
        [1118] = { effect = 12, seconds = 300 },  -- lead_breath
        [1127] = { effect = 28, seconds = 30 },  -- dynamic_implosion
        [1131] = { effect = 136, seconds = 120 },  -- violent_rupture
        [1132] = { -- oblivion_smash
            effect = 5,
            seconds = 120,
            by_effect = {
                [5] = { effect = 5, seconds = 120 },
                [6] = { effect = 6, seconds = 120 },
                [11] = { effect = 11, seconds = 120 },
                [12] = { effect = 12, seconds = 120 },
            },
        },
        [1133] = { -- oblivion_smash_2
            effect = 5,
            seconds = 120,
            by_effect = {
                [5] = { effect = 5, seconds = 120 },
                [6] = { effect = 6, seconds = 120 },
                [11] = { effect = 11, seconds = 120 },
                [12] = { effect = 12, seconds = 120 },
            },
        },
        [1136] = { effect = 5, seconds = 30 },  -- blindeye
        [1138] = { effect = 2, seconds = 135 },  -- hypnosis
        [1139] = { effect = 145, seconds = 10 },  -- mind_break
        [1140] = { effect = 11, seconds = 90 },  -- binding_wave
        [1141] = { effect = 151, seconds = 60 },  -- airy_shield
        [1143] = { effect = 152, seconds = 60 },  -- magic_barrier
        [1144] = { effect = 7, seconds = 105 },  -- level_5_petrify
        [1146] = { effect = 5, seconds = 120 },  -- hecatomb_wave
        [1147] = { effect = 13, seconds = 540 },  -- demonic_howl
        [1148] = { effect = 10, seconds = 15 },  -- condemnation
        [1152] = { effect = 5, seconds = 120 },  -- hecatomb_wave_ra
        [1155] = { effect = 149, seconds = 180 },  -- subsonics
        [1157] = { effect = 146, seconds = 240 },  -- slipstream
        [1159] = { -- broadside_barrage
            effect = 136,
            seconds = 120,
            by_effect = {
                [136] = { effect = 136, seconds = 120 },
                [138] = { effect = 138, seconds = 120 },
            },
        },
        [1160] = { -- blind_side_barrage
            effect = 140,
            seconds = 120,
            by_effect = {
                [140] = { effect = 140, seconds = 120 },
                [141] = { effect = 141, seconds = 120 },
            },
        },
        [1161] = { effect = 10, seconds = 15 },  -- damnation_dive
        [1172] = { effect = 4, seconds = 960 },  -- heavy_stomp
        [1173] = { effect = 9, seconds = 420 },  -- chaos_blade
        [1174] = { effect = 7, seconds = 420 },  -- petro_eyes
        [1176] = { effect = 153, seconds = 30 },  -- thornsong_powerful
        [1179] = { effect = 3, seconds = 180 },  -- poison_breath_dragon_2
        [1192] = { effect = 146, seconds = 60 },  -- onslaught
        [1193] = { effect = 149, seconds = 120 },  -- metatron_torment
        [1195] = { effect = 38 },  -- geirskogul
        [1196] = { effect = 4, seconds = 60 },  -- blade_metsu
        [1198] = { effect = 148, seconds = 120 },  -- randgrith
        [1199] = { effect = 147, seconds = 120 },  -- gate_of_tartarus
        [1218] = { -- vacuous_osculation
            effect = 3,
            seconds = 60,
            by_effect = {
                [3] = { effect = 3, seconds = 60 },
                [31] = { effect = 31, seconds = 30 },
            },
        },
        [1219] = { effect = 93, seconds = 180 },  -- hexagon_belt
        [1220] = { -- auroral_drape
            effect = 5,
            seconds = 90,
            by_effect = {
                [5] = { effect = 5, seconds = 90 },
                [6] = { effect = 6, seconds = 60 },
            },
        },
        [1229] = { effect = 4, seconds = 90 },  -- brain_spike
        [1231] = { effect = 3, seconds = 180 },  -- promyvion_brume
        [1232] = { -- murk
            effect = 12,
            seconds = 120,
            by_effect = {
                [12] = { effect = 12, seconds = 120 },
                [13] = { effect = 13, seconds = 90 },
            },
        },
        [1233] = { effect = 92, seconds = 180 },  -- material_fend
        [1235] = { effect = 11, seconds = 15 },  -- pile_pitch
        [1237] = { -- hyper_pulse
            effect = 11,
            seconds = 15,
            by_effect = {
                [11] = { effect = 11, seconds = 15 },
                [12] = { effect = 12, seconds = 60 },
            },
        },
        [1239] = { -- discharger
            effect = 152,
            seconds = 60,
            by_effect = {
                [38] = { effect = 38, seconds = 90 },
                [152] = { effect = 152, seconds = 60 },
            },
        },
        [1240] = { effect = 4, seconds = 180 },  -- ion_efflux
        [1241] = { effect = 7, seconds = 30 },  -- rear_lasers
        [1243] = { effect = 13, seconds = 60 },  -- negative_whirl
        [1244] = { effect = 31, seconds = 120 },  -- stygian_vapor
        [1253] = { effect = 10, seconds = 4 },  -- vanity_strike
        [1255] = { effect = 66, seconds = 300 },  -- occultation
        [1258] = { effect = 134, seconds = 30 },  -- lamentation
        [1262] = { effect = 31, seconds = 120 },  -- flame_thrower
        [1263] = { effect = 4, seconds = 120 },  -- cryo_jet
        [1264] = { effect = 6, seconds = 30 },  -- turbofan
        [1265] = { effect = 7, seconds = 45 },  -- smoke_discharger
        [1266] = { effect = 10, seconds = 4 },  -- high-tension_discharger
        [1267] = { effect = 3, seconds = 120 },  -- hydro_cannon
        [1269] = { -- chemical_bomb
            effect = 13,
            seconds = 120,
            by_effect = {
                [13] = { effect = 13, seconds = 120 },
                [194] = { effect = 194, seconds = 120 },
            },
        },
        [1270] = { effect = 93, seconds = 300 },  -- particle_shield
        [1276] = { effect = 3, seconds = 180 },  -- promyvion_brume
        [1279] = { effect = 31, seconds = 120 },  -- tebbad_wing
        [1284] = { effect = 31, seconds = 120 },  -- tebbad_wing_air
        [1285] = { effect = 28 },  -- absolute_terror
        [1289] = { effect = 4, seconds = 120 },  -- gregale_wing
        [1294] = { effect = 4, seconds = 120 },  -- gregale_wing_air
        [1295] = { effect = 28 },  -- absolute_terror
        [1299] = { effect = 5, seconds = 30 },  -- typhoon_wing
        [1304] = { effect = 13, seconds = 120 },  -- bai_wing
        [1305] = { effect = 28 },  -- absolute_terror
        [1309] = { effect = 2, seconds = 60 },  -- cyclone_wing
        [1315] = { effect = 28 },  -- absolute_terror
        [1317] = { effect = 13, seconds = 90 },  -- mucus_spread
        [1319] = { effect = 11, seconds = 90 },  -- epoxy_spread
        [1322] = { effect = 10, seconds = 10 },  -- gerjis_grip
        [1326] = { effect = 10, seconds = 4 },  -- final_retribution
        [1328] = { effect = 5, seconds = 120 },  -- ink_jet_fee
        [1329] = { effect = 14, seconds = 60 },  -- gala_macabre
        [1335] = { -- toxic_pick
            effect = 3,
            seconds = 180,
            by_effect = {
                [3] = { effect = 3, seconds = 180 },
                [12] = { effect = 12, seconds = 120 },
                [31] = { effect = 31, seconds = 60 },
            },
        },
        [1336] = { effect = 91, seconds = 120 },  -- frenzied_rage
        [1337] = { effect = 14 },  -- charm
        [1338] = { effect = 31, seconds = 780 },  -- infernal_pestilence
        [1339] = { effect = 30, seconds = 600 },  -- bane
        [1341] = { -- knife_edge_circle
            effect = 3,
            seconds = 120,
            by_effect = {
                [3] = { effect = 3, seconds = 120 },
                [10] = { effect = 10, seconds = 15 },
            },
        },
        [1347] = { effect = 10, seconds = 4 },  -- dual_strike
        [1349] = { effect = 12, seconds = 45 },  -- mantle_pierce
        [1350] = { effect = 5, seconds = 60 },  -- ink_cloud
        [1351] = { effect = 93, seconds = 60 },  -- molluscous_mutation
        [1352] = { effect = 191, seconds = 60 },  -- saline_coat
        [1353] = { effect = 149, seconds = 75 },  -- aerial_collision
        [1355] = { effect = 31, seconds = 120 },  -- spine_lash
        [1356] = { effect = 6, seconds = 120 },  -- voiceless_storm
        [1357] = { -- tidal_dive
            effect = 11,
            seconds = 60,
            by_effect = {
                [11] = { effect = 11, seconds = 60 },
                [12] = { effect = 12, seconds = 120 },
            },
        },
        [1358] = { effect = 38, seconds = 60 },  -- plasma_charge
        [1359] = { effect = 15, seconds = 30 },  -- chthonian_ray
        [1360] = { effect = 15, seconds = 30 },  -- apocalyptic_ray
        [1361] = { -- viscid_secretion
            effect = 12,
            seconds = 120,
            by_effect = {
                [12] = { effect = 12, seconds = 120 },
                [13] = { effect = 13, seconds = 120 },
                [33] = { effect = 33, seconds = 90 },
            },
        },
        [1362] = { -- wild_ginseng
            effect = 36,
            seconds = 180,
            by_effect = {
                [33] = { effect = 33, seconds = 180 },
                [36] = { effect = 36, seconds = 180 },
                [40] = { effect = 40, seconds = 180 },
                [41] = { effect = 41, seconds = 180 },
                [42] = { effect = 42, seconds = 180 },
            },
        },
        [1365] = { effect = 4, seconds = 60 },  -- tail_thrust
        [1366] = { effect = 10, seconds = 10 },  -- temporal_shift
        [1368] = { effect = 42, seconds = 30 },  -- rapid_molt
        [1369] = { effect = 3, seconds = 120 },  -- ichor_stream
        [1370] = { effect = 3, seconds = 180 },  -- vitriolic_barrage
        [1371] = { effect = 11, seconds = 90 },  -- primal_drill
        [1372] = { effect = 12, seconds = 120 },  -- concussive_oscillation
        [1373] = { effect = 10, seconds = 5 },  -- ion_shower
        [1375] = { effect = 133, seconds = 60 },  -- asthenic_fog
        [1376] = { effect = 14, seconds = 25 },  -- luminous_drape
        [1377] = { effect = 45, seconds = 180 },  -- fluorescence
        [1378] = { effect = 13, seconds = 60 },  -- wing_thrust
        [1379] = { effect = 6, seconds = 120 },  -- auroral_wind
        [1380] = { -- impact_stream
            effect = 10,
            seconds = 10,
            by_effect = {
                [10] = { effect = 10, seconds = 10 },
                [149] = { effect = 149, seconds = 60 },
            },
        },
        [1382] = { -- crystaline_cocoon
            effect = 40,
            seconds = 120,
            by_effect = {
                [40] = { effect = 40, seconds = 120 },
                [41] = { effect = 41, seconds = 120 },
            },
        },
        [1383] = { effect = 4, seconds = 60 },  -- glacier_splitter
        [1384] = { effect = 3, seconds = 180 },  -- disseverment
        [1385] = { effect = 31, seconds = 60 },  -- biotic_boomerang
        [1386] = { effect = 7, seconds = 60 },  -- medusa_javelin
        [1392] = { effect = 5, seconds = 60 },  -- amatsu_yukiarashi
        [1393] = { effect = 6, seconds = 60 },  -- amatsu_tsukioboro
        [1394] = { effect = 4, seconds = 60 },  -- amatsu_hanaikusa
        [1406] = { effect = 5, seconds = 30 },  -- typhoon_wing
        [1411] = { effect = 13, seconds = 120 },  -- bai_wing
        [1412] = { effect = 28 },  -- absolute_terror
        [1417] = { effect = 91, seconds = 30 },  -- marionette_dice_4
        [1418] = { effect = 93, seconds = 30 },  -- marionette_dice_5
        [1422] = { effect = 91, seconds = 30 },  -- marionette_dice_9
        [1423] = { effect = 93, seconds = 30 },  -- marionette_dice_10
        [1428] = { effect = 68, seconds = 30 },  -- warcry
        [1429] = { effect = 61, seconds = 300 },  -- counterstance_4
        [1431] = { effect = 10, seconds = 7 },  -- shield_bash_1
        [1432] = { effect = 10, seconds = 7 },  -- weapon_bash
        [1434] = { effect = 73, seconds = 60 },  -- barrage
        [1441] = { effect = 156, seconds = 15 },  -- actinic_burst
        [1445] = { effect = 10, seconds = 15 },  -- damnation_dive
        [1448] = { -- efflorescent_foetor
            effect = 5,
            seconds = 30,
            by_effect = {
                [5] = { effect = 5, seconds = 30 },
                [6] = { effect = 6, seconds = 30 },
            },
        },
        [1449] = { effect = 2, seconds = 60 },  -- stupor_spores
        [1450] = { effect = 13, seconds = 120 },  -- viscid_nectar
        [1452] = { effect = 11, seconds = 60 },  -- axial_bloom
        [1463] = { -- reactor_cool
            effect = 35,
            seconds = 120,
            by_effect = {
                [35] = { effect = 35, seconds = 120 },
                [93] = { effect = 93, seconds = 120 },
            },
        },
        [1465] = { effect = 7, seconds = 60 },  -- optic_induration
        [1466] = { effect = 10, seconds = 4 },  -- static_filament
        [1467] = { effect = 3, seconds = 180 },  -- decayed_filament
        [1468] = { effect = 31, seconds = 60 },  -- reactor_overheat
        [1469] = { effect = 6, seconds = 60 },  -- reactor_overload
        [1485] = { effect = 46, seconds = 45 },  -- hundred_fists
        [1491] = { effect = 28, seconds = 30 },  -- chains_of_apathy
        [1492] = { effect = 28, seconds = 30 },  -- chains_of_arrogance
        [1493] = { effect = 28, seconds = 30 },  -- chains_of_cowardice
        [1494] = { effect = 28, seconds = 30 },  -- chains_of_rage
        [1495] = { effect = 28, seconds = 30 },  -- chains_of_envy
        [1496] = { effect = 9, seconds = 45 },  -- malevolent_blessing
        [1497] = { effect = 31, seconds = 120 },  -- pestilent_penance
        [1499] = { effect = 10, seconds = 10 },  -- infernal_deliverance
        [1500] = { effect = 9, seconds = 45 },  -- malevolent_blessing
        [1501] = { effect = 31, seconds = 120 },  -- pestilent_penance
        [1503] = { effect = 10, seconds = 10 },  -- infernal_deliverance
        [1504] = { effect = 150 },  -- wheel_of_impregnability
        [1505] = { effect = 152 },  -- bastion_of_twilight
        [1506] = { effect = 16, seconds = 75 },  -- winds_of_oblivion
        [1507] = { effect = 6, seconds = 75 },  -- seal_of_quiescence
        [1508] = { effect = 28, seconds = 30 },  -- luminous_lance
        [1521] = { effect = 12, seconds = 45 },  -- armor_buster
        [1522] = { effect = 150, seconds = 60 },  -- energy_screen
        [1523] = { effect = 152, seconds = 60 },  -- mana_screen
        [1524] = { effect = 28, seconds = 10 },  -- dissipation
        [1527] = { effect = 149, seconds = 90 },  -- laser_shower
        [1528] = { -- floodlight
            effect = 6,
            seconds = 90,
            by_effect = {
                [6] = { effect = 6, seconds = 90 },
                [156] = { effect = 156, seconds = 15 },
            },
        },
        [1529] = { -- hyper_pulse
            effect = 11,
            seconds = 15,
            by_effect = {
                [11] = { effect = 11, seconds = 15 },
                [12] = { effect = 12, seconds = 60 },
            },
        },
        [1530] = { effect = 4, seconds = 60 },  -- stun_cannon
        [1533] = { effect = 11, seconds = 15 },  -- pile_pitch
        [1535] = { -- hyper_pulse
            effect = 11,
            seconds = 15,
            by_effect = {
                [11] = { effect = 11, seconds = 15 },
                [12] = { effect = 12, seconds = 60 },
            },
        },
        [1537] = { -- discharger
            effect = 152,
            seconds = 60,
            by_effect = {
                [38] = { effect = 38, seconds = 90 },
                [152] = { effect = 152, seconds = 60 },
            },
        },
        [1538] = { effect = 4, seconds = 180 },  -- ion_efflux
        [1539] = { effect = 7, seconds = 30 },  -- rear_lasers
        [1542] = { effect = 11, seconds = 60 },  -- trample
        [1543] = { effect = 5, seconds = 60 },  -- tempest_wing
        [1547] = { -- impulsion
            effect = 5,
            seconds = 60,
            by_effect = {
                [5] = { effect = 5, seconds = 60 },
                [7] = { effect = 7, seconds = 15 },
            },
        },
        [1548] = { effect = 28 },  -- absolute_terror
        [1556] = { effect = 42, seconds = 20 },  -- regeneration_scolopendra
        [1561] = { effect = 149, seconds = 240 },  -- sonic_wave_dynamis
        [1562] = { effect = 10, seconds = 10 },  -- stomping_dynamis
        [1563] = { effect = 6, seconds = 90 },  -- cold_stare_dynamis
        [1564] = { effect = 92, seconds = 180 },  -- whistle_dynamis
        [1565] = { effect = 56, seconds = 180 },  -- berserk_dhalmel_dynamis
        [1568] = { effect = 5, seconds = 60 },  -- dust_cloud_dynamis
        [1571] = { -- gas_shell_dynamis
            effect = 3,
            seconds = 180,
            by_effect = {
                [3] = { effect = 3, seconds = 180 },
                [12] = { effect = 12, seconds = 45 },
            },
        },
        [1572] = { -- venom_shell_dynamis
            effect = 3,
            seconds = 180,
            by_effect = {
                [3] = { effect = 3, seconds = 180 },
                [31] = { effect = 31, seconds = 45 },
            },
        },
        [1573] = { effect = 4, seconds = 120 },  -- palsynyxis
        [1575] = { effect = 11, seconds = 90 },  -- suctorial_tentacle
        [1578] = { -- broadside_barrage_dynamis
            effect = 136,
            seconds = 90,
            by_effect = {
                [136] = { effect = 136, seconds = 90 },
                [138] = { effect = 138, seconds = 90 },
            },
        },
        [1579] = { -- blind_side_barrage_dynamis
            effect = 140,
            seconds = 90,
            by_effect = {
                [140] = { effect = 140, seconds = 90 },
                [141] = { effect = 141, seconds = 90 },
            },
        },
        [1580] = { effect = 10, seconds = 15 },  -- damnation_dive_nm
        [1581] = { effect = 13, seconds = 180 },  -- sticky_thread_dynamis
        [1583] = { effect = 93, seconds = 90 },  -- cocoon_dynamis
        [1585] = { effect = 2, seconds = 45 },  -- dream_flower_dynamis
        [1586] = { effect = 138, seconds = 120 },  -- wild_oats_dynamis
        [1587] = { effect = 3, seconds = 180 },  -- leaf_dagger
        [1588] = { -- scream_dynamis
            effect = 28,
            seconds = 5,
            by_effect = {
                [28] = { effect = 28, seconds = 5 },
                [141] = { effect = 141, seconds = 180 },
            },
        },
        [1589] = { effect = 136, seconds = 180 },  -- bubble_shower_dynamis
        [1590] = { effect = 191, seconds = 30 },  -- bubble_curtain_dynamis
        [1592] = { effect = 40, seconds = 30 },  -- scissor_guard_dynamis
        [1593] = { effect = 37, seconds = 300 },  -- metallic_body_dynamis
        [1594] = { effect = 3, seconds = 180 },  -- toxic_spit
        [1596] = { effect = 10, seconds = 10 },  -- numbing_noise
        [1604] = { effect = 3, seconds = 60 },  -- miasmic_breath
        [1605] = { effect = 3, seconds = 60 },  -- miasmic_breath
        [1606] = { effect = 14 },  -- fragrant_breath
        [1607] = { effect = 14 },  -- fragrant_breath
        [1613] = { effect = 13, seconds = 120 },  -- gloeosuccus_dynamis
        [1615] = { effect = 2, seconds = 45 },  -- soporific_dynamis
        [1616] = { effect = 4, seconds = 120 },  -- palsy_pollen_dynamis
        [1617] = { effect = 10, seconds = 4 },  -- blow
        [1619] = { effect = 14, seconds = 30 },  -- attractant
        [1620] = { effect = 3, seconds = 180 },  -- mephitic_spore
        [1623] = { effect = 3, seconds = 120 },  -- venom_dynamis
        [1629] = { effect = 145, seconds = 60 },  -- riddle
        [1630] = { effect = 5, seconds = 180 },  -- great_sandstorm
        [1631] = { effect = 130, seconds = 60 },  -- great_whirlwind_dynamis
        [1632] = { -- choke_breath
            effect = 4,
            seconds = 30,
            by_effect = {
                [4] = { effect = 4, seconds = 30 },
                [6] = { effect = 6, seconds = 30 },
            },
        },
        [1633] = { effect = 13, seconds = 180 },  -- sheep_bleat
        [1634] = { effect = 2, seconds = 30 },  -- sheep_song_dynamis
        [1638] = { effect = 10, seconds = 15 },  -- lightning_roar_dynamis
        [1639] = { effect = 12, seconds = 120 },  -- impact_roar_dynamis
        [1642] = { -- whirl_of_rage_dynamis
            effect = 6,
            seconds = 90,
            by_effect = {
                [6] = { effect = 6, seconds = 90 },
                [12] = { effect = 12, seconds = 30 },
            },
        },
        [1646] = { effect = 129, seconds = 30 },  -- cold_wave_dynamis
        [1647] = { effect = 56, seconds = 180 },  -- berserk_bomb_dynamis
        [1648] = { effect = 40, seconds = 120 },  -- crystal_shield_dynamis
        [1650] = { effect = 11, seconds = 240 },  -- ice_break
        [1651] = { effect = 10, seconds = 20 },  -- thunder_break
        [1653] = { effect = 31, seconds = 120 },  -- crystal_weapon_fire_dynamis
        [1654] = { effect = 7, seconds = 30 },  -- crystal_weapon_stone_dynamis
        [1655] = { effect = 3, seconds = 180 },  -- crystal_weapon_water_dynamis
        [1656] = { effect = 12, seconds = 90 },  -- crystal_weapon_wind_dynamis
        [1657] = { effect = 5, seconds = 90 },  -- blind_vortex_dynamis
        [1659] = { effect = 10, seconds = 4 },  -- dread_dive
        [1660] = { effect = 92, seconds = 1020 },  -- feather_barrier
        [1662] = { effect = 148, seconds = 180 },  -- ultrasonics_dynamis
        [1664] = { effect = 149, seconds = 90 },  -- subsonics_dynamis
        [1666] = { effect = 147, seconds = 90 },  -- sonic_boom_dynamis
        [1668] = { effect = 146, seconds = 90 },  -- slipstream_dynamis
        [1671] = { effect = 5, seconds = 120 },  -- ink_jet_dynamis
        [1672] = { effect = 92, seconds = 540 },  -- hard_membrane
        [1674] = { effect = 42, seconds = 180 },  -- regeneration_dynamis
        [1675] = { effect = 136, seconds = 180 },  -- maelstrom_dynamis
        [1676] = { effect = 138, seconds = 180 },  -- whirlwind_dynamis
        [1677] = { effect = 4, seconds = 90 },  -- roar_dynamis
        [1680] = { effect = 10, seconds = 8 },  -- predatory_glare_dynamis
        [1684] = { effect = 8, seconds = 180 },  -- foul_breath_dynamis
        [1685] = { effect = 4, seconds = 180 },  -- frost_breath_dynamis
        [1686] = { effect = 10, seconds = 15 },  -- thunderbolt_dynamis
        [1687] = { effect = 13, seconds = 180 },  -- chomp_rush
        [1688] = { effect = 10, seconds = 5 },  -- scythe_tail_dynamis
        [1691] = { effect = 13, seconds = 90 },  -- filamented_hold_dynamis
        [1694] = { -- vile_belch
            effect = 31,
            seconds = 75,
            by_effect = {
                [6] = { effect = 6, seconds = 90 },
                [31] = { effect = 31, seconds = 75 },
            },
        },
        [1695] = { effect = 2, seconds = 240 },  -- hypnic_lamp
        [1697] = { effect = 13, seconds = 60 },  -- seaspray
        [1702] = { effect = 14, seconds = 30 },  -- wisecrack
        [1703] = { -- barrier_tusk
            effect = 93,
            seconds = 90,
            by_effect = {
                [93] = { effect = 93, seconds = 90 },
                [191] = { effect = 191, seconds = 90 },
            },
        },
        [1709] = { effect = 16, seconds = 60 },  -- abrasive_tantara
        [1710] = { effect = 6, seconds = 30 },  -- deafening_tantara
        [1713] = { effect = 2, seconds = 120 },  -- yawn
        [1714] = { effect = 10, seconds = 4 },  -- wing_slap
        [1716] = { effect = 4, seconds = 120 },  -- frigid_shuffle
        [1721] = { effect = 156, seconds = 20 },  -- obfuscate
        [1722] = { effect = 36, seconds = 180 },  -- zephyr_mantle
        [1725] = { effect = 16, seconds = 60 },  -- kibosh
        [1727] = { effect = 5, seconds = 150 },  -- sandspray
        [1728] = { effect = 28, seconds = 10 },  -- faze
        [1730] = { -- deadeye
            effect = 149,
            seconds = 120,
            by_effect = {
                [149] = { effect = 149, seconds = 120 },
                [167] = { effect = 167, seconds = 120 },
            },
        },
        [1734] = { -- warm-up
            effect = 90,
            seconds = 60,
            by_effect = {
                [90] = { effect = 90, seconds = 60 },
                [92] = { effect = 92, seconds = 60 },
            },
        },
        [1743] = { effect = 7, seconds = 45 },  -- rock_smash
        [1744] = { effect = 37, seconds = 300 },  -- diamondhide
        [1745] = { -- enervation
            effect = 149,
            seconds = 30,
            by_effect = {
                [149] = { effect = 149, seconds = 30 },
                [167] = { effect = 167, seconds = 30 },
            },
        },
        [1746] = { effect = 45, seconds = 30 },  -- quake_stomp
        [1755] = { effect = 36, seconds = 120 },  -- dukkeripen_shadow
        [1756] = { effect = 4, seconds = 120 },  -- dukkeripen_para
        [1758] = { effect = 10, seconds = 4 },  -- tail_slap
        [1759] = { effect = 16, seconds = 90 },  -- hypnotic_sway
        [1762] = { effect = 14, seconds = 45 },  -- belly_dance
        [1768] = { effect = 36, seconds = 120 },  -- dukkeripen_shadow
        [1769] = { effect = 4, seconds = 120 },  -- dukkeripen_para
        [1771] = { effect = 10, seconds = 4 },  -- tail_slap
        [1780] = { effect = 10, seconds = 45 },  -- leaping_cleave
        [1782] = { effect = 33, seconds = 150 },  -- animating_wail
        [1783] = { effect = 40, seconds = 240 },  -- fortifying_wail
        [1788] = { effect = 4, seconds = 120 },  -- ululation
        [1789] = { -- magma_hoplon
            effect = 37,
            seconds = 300,
            by_effect = {
                [34] = { effect = 34, seconds = 180 },
                [37] = { effect = 37, seconds = 300 },
            },
        },
        [1790] = { effect = 128, seconds = 60 },  -- gates_of_hades
        [1800] = { -- miasma
            effect = 3,
            seconds = 60,
            by_effect = {
                [3] = { effect = 3, seconds = 60 },
                [13] = { effect = 13, seconds = 120 },
                [31] = { effect = 31, seconds = 60 },
            },
        },
        [1802] = { effect = 7, seconds = 60 },  -- sledgehammer
        [1804] = { effect = 16, seconds = 60 },  -- haymaker
        [1806] = { effect = 152, seconds = 300 },  -- arcane_stomp
        [1807] = { -- pleiades_ray
            effect = 3,
            seconds = 120,
            by_effect = {
                [3] = { effect = 3, seconds = 120 },
                [4] = { effect = 4, seconds = 120 },
                [5] = { effect = 5, seconds = 120 },
                [6] = { effect = 6, seconds = 120 },
                [11] = { effect = 11, seconds = 120 },
                [13] = { effect = 13, seconds = 120 },
                [31] = { effect = 31, seconds = 120 },
            },
        },
        [1808] = { effect = 7, seconds = 25 },  -- petrifaction
        [1810] = { effect = 10, seconds = 4 },  -- tail_slap
        [1812] = { effect = 11, seconds = 60 },  -- pinning_shot
        [1813] = { effect = 7, seconds = 120 },  -- calcifying_deluge
        [1814] = { effect = 7, seconds = 180 },  -- gorgon_dance
        [1815] = { effect = 93, seconds = 120 },  -- amber_scutum
        [1816] = { effect = 128, seconds = 60 },  -- vitriolic_spray
        [1817] = { effect = 5, seconds = 150 },  -- thermal_pulse
        [1819] = { -- heat_barrier
            effect = 34,
            seconds = 180,
            by_effect = {
                [34] = { effect = 34, seconds = 180 },
                [94] = { effect = 94, seconds = 300 },
            },
        },
        [1820] = { effect = 128, seconds = 60 },  -- vitriolic_shower
        [1821] = { -- amplification
            effect = 191,
            seconds = 120,
            by_effect = {
                [190] = { effect = 190, seconds = 120 },
                [191] = { effect = 191, seconds = 120 },
            },
        },
        [1822] = { effect = 167, seconds = 120 },  -- boiling_point
        [1828] = { effect = 31, seconds = 60 },  -- pyric_blast
        [1829] = { effect = 152, seconds = 45 },  -- pyric_bulwark
        [1830] = { effect = 4, seconds = 60 },  -- polar_blast
        [1831] = { effect = 150, seconds = 45 },  -- polar_bulwark
        [1832] = { effect = 12, seconds = 60 },  -- barofield
        [1836] = { -- nerve_gas
            effect = 3,
            seconds = 60,
            by_effect = {
                [3] = { effect = 3, seconds = 60 },
                [9] = { effect = 9, seconds = 420 },
            },
        },
        [1837] = { effect = 4, seconds = 90 },  -- feeble_bleat
        [1847] = { effect = 46, seconds = 20 },  -- frenzy_pollen
        [1856] = { effect = 7, seconds = 45 },  -- omega_javelin
        [1896] = { effect = 7, seconds = 45 },  -- rock_smash
        [1897] = { effect = 37, seconds = 300 },  -- diamondhide
        [1898] = { -- enervation
            effect = 149,
            seconds = 30,
            by_effect = {
                [149] = { effect = 149, seconds = 30 },
                [167] = { effect = 167, seconds = 30 },
            },
        },
        [1899] = { effect = 45, seconds = 30 },  -- quake_stomp
        [1904] = { effect = 12, seconds = 180 },  -- somnolence
        [1905] = { effect = 116, seconds = 120 },  -- noctoshield
        [1907] = { -- dream_shroud
            effect = 190,
            seconds = 180,
            by_effect = {
                [190] = { effect = 190, seconds = 180 },
                [191] = { effect = 191, seconds = 180 },
            },
        },
        [1908] = { -- nightmare
            effect = 2,
            seconds = 90,
            by_effect = {
                [2] = { effect = 2, seconds = 90 },
                [135] = { effect = 135, seconds = 90 },
            },
        },
        [1924] = { -- warm-up
            effect = 90,
            seconds = 60,
            by_effect = {
                [90] = { effect = 90, seconds = 60 },
                [92] = { effect = 92, seconds = 60 },
            },
        },
        [1933] = { effect = 163, seconds = 45 },  -- azure_lore
        [1936] = { effect = 10, seconds = 4 },  -- shibaraku
        [1944] = { effect = 10, seconds = 7 },  -- shield_bash
        [1947] = { effect = 156, seconds = 15 },  -- flashbulb
        [1952] = { effect = 33, seconds = 180 },  -- erratic_flutter
        [1954] = { effect = 134, seconds = 30 },  -- erosion_dust
        [1957] = { -- frog_song
            effect = 14,
            seconds = 60,
            by_effect = {
                [14] = { effect = 14, seconds = 60 },
                [127] = { effect = 127, seconds = 60 },
            },
        },
        [1959] = { effect = 6, seconds = 60 },  -- water_bomb
        [1960] = { -- frog_cheer
            effect = 190,
            seconds = 300,
            by_effect = {
                [79] = { effect = 79, seconds = 60 },
                [190] = { effect = 190, seconds = 300 },
            },
        },
        [1962] = { -- frog_chorus
            effect = 14,
            seconds = 60,
            by_effect = {
                [14] = { effect = 14, seconds = 60 },
                [127] = { effect = 127, seconds = 60 },
            },
        },
        [1963] = { effect = 4, seconds = 75 },  -- mind_blast
        [1967] = { -- tribulation
            effect = 5,
            seconds = 120,
            by_effect = {
                [5] = { effect = 5, seconds = 120 },
                [135] = { effect = 135, seconds = 120 },
            },
        },
        [1968] = { effect = 9, seconds = 300 },  -- immortal_anathema
        [1978] = { -- abominable_belch
            effect = 31,
            seconds = 75,
            by_effect = {
                [4] = { effect = 4, seconds = 90 },
                [6] = { effect = 6, seconds = 90 },
                [31] = { effect = 31, seconds = 75 },
            },
        },
        [1998] = { effect = 3, seconds = 45 },  -- hane_fubuki
        [1999] = { effect = 10, seconds = 4 },  -- hiden_sokyaku
        [2000] = { -- shiko_no_mitate
            effect = 93,
            seconds = 300,
            by_effect = {
                [37] = { effect = 37, seconds = 300 },
                [93] = { effect = 93, seconds = 300 },
                [484] = { effect = 484, seconds = 300 },
            },
        },
        [2001] = { effect = 10, seconds = 4 },  -- happobarai
        [2002] = { effect = 68, seconds = 180 },  -- rinpyotosha
        [2003] = { effect = 16, seconds = 60 },  -- grating_tantara
        [2004] = { effect = 6, seconds = 60 },  -- stifling_tantara
        [2006] = { effect = 163, seconds = 45 },  -- azure_lore
        [2015] = { effect = 2, seconds = 60 },  -- light_shot
        [2023] = { effect = 10, seconds = 10 },  -- thunderstrike
        [2024] = { effect = 149, seconds = 100 },  -- tourbillion
        [2025] = { effect = 28, seconds = 10 },  -- dreadstorm
        [2026] = { effect = 7, seconds = 60 },  -- fossilizing_breath
        [2027] = { -- plague_swipe
            effect = 31,
            seconds = 60,
            by_effect = {
                [31] = { effect = 31, seconds = 60 },
                [135] = { effect = 135, seconds = 60 },
            },
        },
        [2028] = { -- fulmination
            effect = 4,
            seconds = 60,
            by_effect = {
                [4] = { effect = 4, seconds = 60 },
                [10] = { effect = 10, seconds = 10 },
            },
        },
        [2031] = { effect = 38, seconds = 180 },  -- reactive_shield
        [2032] = { effect = 11, seconds = 30 },  -- roller_chain
        [2033] = { -- choke_chain
            effect = 16,
            seconds = 60,
            by_effect = {
                [6] = { effect = 6, seconds = 60 },
                [11] = { effect = 11, seconds = 60 },
                [16] = { effect = 16, seconds = 60 },
            },
        },
        [2038] = { effect = 12, seconds = 60 },  -- artificial_gravity
        [2043] = { effect = 12, seconds = 60 },  -- artificial_gravity_3
        [2046] = { effect = 12, seconds = 60 },  -- artificial_gravity_2
        [2049] = { effect = 12, seconds = 60 },  -- artificial_gravity_1
        [2053] = { -- heavy_armature
            effect = 36,
            seconds = 120,
            by_effect = {
                [33] = { effect = 33, seconds = 180 },
                [36] = { effect = 36, seconds = 120 },
                [40] = { effect = 40, seconds = 180 },
            },
        },
        [2055] = { effect = 11, seconds = 30 },  -- inertia_stream
        [2056] = { effect = 4, seconds = 180 },  -- discharge
        [2060] = { effect = 14, seconds = 60 },  -- brainjack
        [2066] = { effect = 10, seconds = 4 },  -- daze
        [2067] = { effect = 148, seconds = 30 },  -- knockout
        [2083] = { effect = 11, seconds = 60 },  -- drop_hammer
        [2097] = { effect = 93, seconds = 120 },  -- granite_skin
        [2101] = { effect = 147, seconds = 150 },  -- demoralizing_roar
        [2102] = { -- boiling_blood
            effect = 33,
            seconds = 180,
            by_effect = {
                [33] = { effect = 33, seconds = 180 },
                [56] = { effect = 56, seconds = 180 },
            },
        },
        [2103] = { effect = 93, seconds = 120 },  -- granite_skin
        [2104] = { effect = 4, seconds = 90 },  -- crippling_slam
        [2110] = { effect = 10, seconds = 4 },  -- wings_of_gehenna
        [2111] = { effect = 15, seconds = 30 },  -- eternal_damnation
        [2112] = { -- nocturnal_servitude
            effect = 14,
            seconds = 60,
            by_effect = {
                [14] = { effect = 14, seconds = 60 },
                [127] = { effect = 127, seconds = 60 },
            },
        },
        [2113] = { effect = 10 },  -- hellsnap
        [2114] = { effect = 12, seconds = 60 },  -- hellclap
        [2116] = { -- necrobane
            effect = 4,
            seconds = 60,
            by_effect = {
                [4] = { effect = 4, seconds = 60 },
                [9] = { effect = 9, seconds = 60 },
            },
        },
        [2117] = { effect = 9, seconds = 60 },  -- necropurge
        [2118] = { -- bilgestorm
            effect = 146,
            seconds = 60,
            by_effect = {
                [146] = { effect = 146, seconds = 60 },
                [147] = { effect = 147, seconds = 60 },
                [149] = { effect = 149, seconds = 60 },
            },
        },
        [2119] = { effect = 28, seconds = 15 },  -- thundris_shriek
        [2128] = { effect = 11, seconds = 240 },  -- ice_break_2128
        [2129] = { effect = 10, seconds = 4 },  -- thunder_break_2129
        [2141] = { effect = 167, seconds = 60 },  -- radiant_sacrament
        [2143] = { effect = 283, seconds = 10 },  -- perfect_defense
        [2146] = { effect = 28, seconds = 30 },  -- void_of_repentance
        [2153] = { effect = 11, seconds = 120 },  -- regurgitation
        [2154] = { effect = 31, seconds = 60 },  -- delta_thrust
        [2155] = { effect = 4, seconds = 120 },  -- torpefying_charge
        [2161] = { -- cimicine_discharge
            effect = 13,
            seconds = 180,
            by_effect = {
                [13] = { effect = 13, seconds = 180 },
                [33] = { effect = 33, seconds = 180 },
            },
        },
        [2163] = { effect = 149, seconds = 60 },  -- seedspray
        [2164] = { effect = 16, seconds = 60 },  -- viscid_emission
        [2165] = { -- rotten_stench
            effect = 146,
            seconds = 150,
            by_effect = {
                [146] = { effect = 146, seconds = 150 },
                [174] = { effect = 174, seconds = 150 },
            },
        },
        [2166] = { effect = 2, seconds = 30 },  -- floral_bouquet
        [2170] = { -- fevered_pitch
            effect = 10,
            seconds = 4,
            by_effect = {
                [10] = { effect = 10, seconds = 4 },
                [149] = { effect = 149, seconds = 120 },
            },
        },
        [2178] = { effect = 10, seconds = 4 },  -- sudden_lunge
        [2179] = { effect = 147, seconds = 120 },  -- noisome_powder
        [2180] = { effect = 16, seconds = 60 },  -- nepenthean_hum
        [2181] = { effect = 146, seconds = 60 },  -- spiral_spin
        [2183] = { -- fuscous_ooze
            effect = 12,
            seconds = 45,
            by_effect = {
                [12] = { effect = 12, seconds = 45 },
                [177] = { effect = 177, seconds = 45 },
            },
        },
        [2184] = { -- purulent_ooze
            effect = 135,
            seconds = 120,
            by_effect = {
                [135] = { effect = 135, seconds = 120 },
                [144] = { effect = 144, seconds = 120 },
            },
        },
        [2185] = { -- corrosive_ooze
            effect = 147,
            seconds = 120,
            by_effect = {
                [147] = { effect = 147, seconds = 120 },
                [149] = { effect = 149, seconds = 120 },
            },
        },
        [2188] = { -- slaverous_gale
            effect = 13,
            seconds = 120,
            by_effect = {
                [13] = { effect = 13, seconds = 120 },
                [31] = { effect = 31, seconds = 120 },
            },
        },
        [2189] = { -- aeolian_void
            effect = 5,
            seconds = 180,
            by_effect = {
                [5] = { effect = 5, seconds = 180 },
                [6] = { effect = 6, seconds = 180 },
            },
        },
        [2193] = { effect = 11, seconds = 120 },  -- zephyr_arrow
        [2194] = { -- lethe_arrows
            effect = 11,
            seconds = 120,
            by_effect = {
                [11] = { effect = 11, seconds = 120 },
                [16] = { effect = 16, seconds = 120 },
            },
        },
        [2195] = { effect = 2, seconds = 20 },  -- spring_breeze
        [2196] = { effect = 170, seconds = 60 },  -- summer_breeze
        [2198] = { effect = 10, seconds = 2 },  -- winter_breeze
        [2200] = { effect = 29, seconds = 60 },  -- cyclonic_torrent
        [2217] = { effect = 56, seconds = 120 },  -- berserk
        [2219] = { effect = 135, seconds = 60 },  -- dark_wave
        [2242] = { effect = 44, seconds = 45 },  -- mighty_strikes
        [2248] = { effect = 50, seconds = 30 },  -- invincible
        [2249] = { effect = 51, seconds = 30 },  -- blood_weapon
        [2257] = { effect = 163, seconds = 45 },  -- azure_lore
        [2329] = { effect = 11, seconds = 15 },  -- di_horn_attack
        [2330] = { effect = 12, seconds = 15 },  -- di_bite_attack
        [2334] = { effect = 6, seconds = 90 },  -- wrath_of_zeus
        [2335] = { effect = 16, seconds = 210 },  -- lightning_spear
        [2338] = { effect = 10, seconds = 5 },  -- rampant_stance
        [2351] = { -- tear_grenade
            effect = 6,
            seconds = 60,
            by_effect = {
                [5] = { effect = 5, seconds = 60 },
                [6] = { effect = 6, seconds = 60 },
            },
        },
        [2352] = { effect = 12, seconds = 60 },  -- sticky_grenade
        [2359] = { effect = 259, seconds = 60 },  -- strap_cutter
        [2360] = { effect = 12, seconds = 120 },  -- wind_shear_znm
        [2410] = { effect = 1, seconds = 90 },  -- demonic_flower
        [2411] = { effect = 11, seconds = 30 },  -- phantasmal_dance
        [2412] = { -- thunderous_yowl
            effect = 9,
            seconds = 60,
            by_effect = {
                [9] = { effect = 9, seconds = 60 },
                [31] = { effect = 31, seconds = 60 },
            },
        },
        [2413] = { -- feather_maelstrom
            effect = 16,
            seconds = 60,
            by_effect = {
                [16] = { effect = 16, seconds = 60 },
                [135] = { effect = 135, seconds = 60 },
            },
        },
        [2414] = { effect = 251, seconds = 1800 },  -- saucepan
        [2422] = { effect = 12, seconds = 60 },  -- dark_mist
        [2423] = { effect = 91, seconds = 90 },  -- triumphant_roar
        [2424] = { effect = 28, seconds = 30 },  -- terror_eye
        [2426] = { effect = 9, seconds = 300 },  -- shadow_burst
        [2427] = { effect = 16, seconds = 60 },  -- tail_lash
        [2430] = { -- warped_wail
            effect = 144,
            seconds = 300,
            by_effect = {
                [144] = { effect = 144, seconds = 300 },
                [145] = { effect = 145, seconds = 300 },
            },
        },
        [2432] = { effect = 6, seconds = 120 },  -- storm_wing
        [2435] = { effect = 149, seconds = 90 },  -- severing_fang
        [2436] = { effect = 4, seconds = 100 },  -- sub-zero_smash
        [2438] = { -- frozen_mist
            effect = 28,
            seconds = 30,
            by_effect = {
                [28] = { effect = 28, seconds = 30 },
                [37] = { effect = 37, seconds = 180 },
            },
        },
        [2439] = { effect = 37, seconds = 180 },  -- hydro_wave
        [2549] = { effect = 3 },  -- fluid_toss_claret
        [2562] = { effect = 167, seconds = 120 },  -- acrid_stream
        [2563] = { -- rime_spray
            effect = 129,
            seconds = 120,
            by_effect = {
                [129] = { effect = 129, seconds = 120 },
                [136] = { effect = 136, seconds = 60 },
                [137] = { effect = 137, seconds = 60 },
                [138] = { effect = 138, seconds = 60 },
                [139] = { effect = 139, seconds = 60 },
                [140] = { effect = 140, seconds = 60 },
                [141] = { effect = 141, seconds = 60 },
                [142] = { effect = 142, seconds = 60 },
            },
        },
        [2564] = { effect = 128, seconds = 120 },  -- blazing_bound
        [2578] = { effect = 20, seconds = 30 },  -- colossal_slam
        [2629] = { -- benthic_typhoon
            effect = 149,
            seconds = 60,
            by_effect = {
                [149] = { effect = 149, seconds = 60 },
                [167] = { effect = 167, seconds = 60 },
            },
        },
        [2770] = { -- booming_bombination
            effect = 167,
            seconds = 180,
            by_effect = {
                [31] = { effect = 31, seconds = 180 },
                [149] = { effect = 149, seconds = 180 },
                [167] = { effect = 167, seconds = 180 },
            },
        },
        [2828] = { effect = 28, seconds = 15 },  -- jettatura
        [2891] = { effect = 10, seconds = 10 },  -- grapeshot
        [2892] = { effect = 128, seconds = 20 },  -- pirate_pummel
        [2893] = { -- powder_keg
            effect = 149,
            seconds = 60,
            by_effect = {
                [149] = { effect = 149, seconds = 60 },
                [167] = { effect = 167, seconds = 60 },
            },
        },
        [2894] = { effect = 11, seconds = 20 },  -- walk_the_plank
        [2922] = { effect = 28, seconds = 30 },  -- soulshattering_roar
        [2923] = { effect = 7, seconds = 30 },  -- calcifying_claw
        [2924] = { -- divesting_stampede
            effect = 149,
            seconds = 60,
            by_effect = {
                [149] = { effect = 149, seconds = 60 },
                [167] = { effect = 167, seconds = 60 },
            },
        },
        [2925] = { -- bonebreaking_barrage
            effect = 12,
            seconds = 30,
            by_effect = {
                [12] = { effect = 12, seconds = 30 },
                [144] = { effect = 144, seconds = 60 },
            },
        },
        [2952] = { -- blackout
            effect = 5,
            seconds = 180,
            by_effect = {
                [4] = { effect = 4, seconds = 180 },
                [5] = { effect = 5, seconds = 180 },
                [6] = { effect = 6, seconds = 180 },
            },
        },
        [2953] = { effect = 128, seconds = 90 },  -- smouldering_swarm
        [3144] = { effect = 91, seconds = 60 },  -- jittering_jig
        [3189] = { effect = 10, seconds = 4 },  -- king_cobra_clamp
        [3193] = { effect = 10, seconds = 4 },  -- royal_bash
        [3194] = { -- royal_savior
            effect = 37,
            seconds = 60,
            by_effect = {
                [37] = { effect = 37, seconds = 60 },
                [40] = { effect = 40, seconds = 300 },
                [93] = { effect = 93, seconds = 60 },
                [478] = { effect = 478, seconds = 60 },
            },
        },
        [3196] = { effect = 10, seconds = 15 },  -- abyssal_strike
        [3198] = { effect = 10, seconds = 10 },  -- grapeshot
        [3199] = { effect = 128, seconds = 20 },  -- pirate_pummel
        [3200] = { -- powder_keg
            effect = 149,
            seconds = 60,
            by_effect = {
                [149] = { effect = 149, seconds = 60 },
                [167] = { effect = 167, seconds = 60 },
            },
        },
        [3201] = { effect = 11, seconds = 20 },  -- walk_the_plank
        [3202] = { effect = 156, seconds = 15 },  -- uriel_blade
        [3215] = { effect = 167, seconds = 60 },  -- peacebreaker
        [3243] = { effect = 10, seconds = 10 },  -- imperial_authority
        [3245] = { effect = 6, seconds = 15 },  -- shield_subverter
        [3256] = { effect = 3, seconds = 45 },  -- hane_fubuki
        [3257] = { effect = 10, seconds = 4 },  -- shibaraku
        [3258] = { -- shiko_no_mitate
            effect = 93,
            seconds = 300,
            by_effect = {
                [37] = { effect = 37, seconds = 300 },
                [93] = { effect = 93, seconds = 300 },
                [484] = { effect = 484, seconds = 300 },
            },
        },
        [3259] = { effect = 10, seconds = 4 },  -- happobarai
        [3260] = { effect = 68, seconds = 180 },  -- rinpyotosha
        [3351] = { effect = 138, seconds = 120 },  -- wild_oats
        [3355] = { effect = 10, seconds = 4 },  -- blow
        [3357] = { effect = 6, seconds = 90 },  -- antiphase
        [3358] = { effect = 4, seconds = 180 },  -- blank_gaze
        [3420] = { effect = 5, seconds = 60 },  -- amatsu_yukiarashi
        [3421] = { effect = 6, seconds = 60 },  -- amatsu_tsukioboro
        [3422] = { effect = 4, seconds = 60 },  -- amatsu_hanaikusa
        [3423] = { effect = 3 },  -- wasp_sting
        [3437] = { effect = 4, seconds = 60 },  -- tachi_kasha
        [3439] = { effect = 5, seconds = 30 },  -- hurricane_wing
        [3466] = { effect = 4, seconds = 60 },  -- paralyzing_microtube
        [3467] = { effect = 6, seconds = 60 },  -- silencing_microtube
        [3468] = { effect = 11, seconds = 60 },  -- binding_microtube
        [3472] = { -- vortex
            effect = 11,
            seconds = 30,
            by_effect = {
                [11] = { effect = 11, seconds = 30 },
                [28] = { effect = 28, seconds = 9 },
            },
        },
        [3473] = { effect = 6, seconds = 30 },  -- stellar_burst
        [3491] = { effect = 10, seconds = 10 },  -- grapeshot
        [3492] = { effect = 128, seconds = 20 },  -- pirate_pummel
        [3493] = { -- powder_keg
            effect = 149,
            seconds = 60,
            by_effect = {
                [149] = { effect = 149, seconds = 60 },
                [167] = { effect = 167, seconds = 60 },
            },
        },
        [3494] = { effect = 11, seconds = 20 },  -- walk_the_plank
        [3506] = { effect = 128, seconds = 60 },  -- hellfire_arrow
        [3507] = { effect = 136, seconds = 120 },  -- incensed_pummel
        [3511] = { effect = 29, seconds = 60 },  -- lunatic_voice
        [3513] = { effect = 14, seconds = 30 },  -- entice
        [3539] = { effect = 152, seconds = 10 },  -- hysteroanima
        [3540] = { effect = 150, seconds = 10 },  -- psychoanima
        [3541] = { -- salaheem_spirit
            effect = 80,
            by_effect = {
                [80] = { effect = 80 },
                [81] = { effect = 81 },
                [82] = { effect = 82 },
                [83] = { effect = 83 },
                [84] = { effect = 84 },
                [85] = { effect = 85 },
                [86] = { effect = 86 },
            },
        },
        [3547] = { effect = 92, seconds = 540 },  -- hard_membrane
        [3548] = { effect = 42, seconds = 300 },  -- regeneration
        [3621] = { effect = 28, seconds = 30 },  -- luminous_lance
        [3624] = { effect = 190, seconds = 300 },  -- memento_mori
        [3625] = { effect = 6, seconds = 60 },  -- silence_seal
        [3626] = { effect = 9, seconds = 180 },  -- envoutement
        [3653] = { effect = 16 },  -- tartaric_sigil
        [3655] = { effect = 156 },  -- alabaster_burst
        [3657] = { effect = 10 },  -- fulminous_fury
        [3706] = { effect = 10, seconds = 4 },  -- cross_reaver
        [3712] = { effect = 6, seconds = 60 },  -- dominion_slash
        [3714] = { effect = 10, seconds = 6 },  -- shield_strike
        [3717] = { effect = 2, seconds = 60 },  -- havoc_spiral
        [3720] = { -- amon_drive
            effect = 3,
            seconds = 60,
            by_effect = {
                [3] = { effect = 3, seconds = 60 },
                [4] = { effect = 4, seconds = 60 },
                [7] = { effect = 7 },
            },
        },
        [3721] = { effect = 6 },  -- guillotine
        [3722] = { effect = 5, seconds = 60 },  -- tachi_yukikaze
        [3723] = { effect = 6, seconds = 45 },  -- tachi_gekko
        [3724] = { effect = 11, seconds = 30 },  -- dragonfall
        [3725] = { effect = 4, seconds = 60 },  -- tachi_kasha
        [3841] = { effect = 5, seconds = 120 },  -- dust_cloud_jugpet
        [3844] = { effect = 2, seconds = 60 },  -- dream_flower_jugpet
        [3845] = { effect = 138, seconds = 120 },  -- wild_oats_jugpet
        [3846] = { effect = 3, seconds = 90 },  -- leaf_dagger_jugpet
        [3847] = { effect = 141, seconds = 180 },  -- scream_jugpet
        [3848] = { effect = 4, seconds = 120 },  -- roar_jugpet
        [3851] = { effect = 10, seconds = 4 },  -- tail_blow_jugpet
        [3854] = { effect = 6, seconds = 30 },  -- brain_crush_jugpet
        [3855] = { effect = 148, seconds = 180 },  -- infrasonics_jugpet
        [3856] = { effect = 92, seconds = 60 },  -- secretion_jugpet
        [3858] = { effect = 56, seconds = 120 },  -- rage_jugpet
        [3860] = { effect = 2, seconds = 45 },  -- sheep_song_jugpet
        [3861] = { effect = 136, seconds = 180 },  -- bubble_shower_jugpet
        [3862] = { effect = 41, seconds = 180 },  -- bubble_curtain_jugpet
        [3864] = { effect = 93, seconds = 60 },  -- scissor_guard_jugpet
        [3865] = { effect = 37, seconds = 300 },  -- metallic_body_jugpet
        [3869] = { effect = 4, seconds = 180 },  -- spore_jugpet
        [3870] = { effect = 3, seconds = 60 },  -- queasyshroom_jugpet
        [3871] = { effect = 4, seconds = 180 },  -- numbshroom_jugpet
        [3872] = { effect = 8, seconds = 720 },  -- shakeshroom_jugpet
        [3873] = { effect = 6, seconds = 60 },  -- silence_gas_jugpet
        [3874] = { effect = 5, seconds = 90 },  -- dark_spore_jugpet
        [3876] = { effect = 148, seconds = 180 },  -- hi-freq_field_jugpet
        [3878] = { effect = 92, seconds = 540 },  -- rhino_guard_jugpet
        [3879] = { effect = 136, seconds = 540 },  -- spoil_jugpet
        [3881] = { effect = 3, seconds = 60 },  -- venom_jugpet
        [3882] = { effect = 5, seconds = 90 },  -- sandblast_jugpet
        [3883] = { effect = 11, seconds = 60 },  -- sandpit_jugpet
        [3884] = { effect = 3, seconds = 120 },  -- venom_spray_jugpet
        [3886] = { effect = 2, seconds = 30 },  -- soporific_jugpet
        [3887] = { effect = 13, seconds = 180 },  -- gloeosuccus_jugpet
        [3888] = { effect = 4, seconds = 60 },  -- palsy_pollen_jugpet
        [3890] = { effect = 10, seconds = 10 },  -- numbing_noise_jugpet
        [3893] = { effect = 3, seconds = 180 },  -- toxic_spit_jugpet
        [3896] = { effect = 13, seconds = 120 },  -- filamented_hold_jugpet
        [3898] = { effect = 6, seconds = 60 },  -- chaotic_eye_jugpet
        [3899] = { effect = 4, seconds = 60 },  -- blaster_jugpet
        [3900] = { effect = 10, seconds = 4 },  -- suction_jugpet
        [3902] = { effect = 4, seconds = 120 },  -- snow_cloud_jugpet
        [3904] = { effect = 10, seconds = 4 },  -- sudden_lunge_jugpet
        [3905] = { effect = 146, seconds = 60 },  -- spiral_spin_jugpet
        [3906] = { effect = 147, seconds = 120 },  -- noisome_powder_jugpet
        [3907] = { effect = 147, seconds = 120 },  -- acid_mist_jugpet
        [3909] = { effect = 10, seconds = 4 },  -- scythe_tail_jugpet
        [3911] = { effect = 13, seconds = 180 },  -- chomp_rush_jugpet
        [3913] = { -- purulent_ooze_jugpet
            effect = 135,
            seconds = 120,
            by_effect = {
                [135] = { effect = 135, seconds = 120 },
                [144] = { effect = 144, seconds = 120 },
            },
        },
        [3914] = { -- corrosive_ooze_jugpet
            effect = 147,
            seconds = 120,
            by_effect = {
                [147] = { effect = 147, seconds = 120 },
                [149] = { effect = 149, seconds = 120 },
            },
        },
        [3916] = { effect = 28, seconds = 15 },  -- jettatura_jugpet
        [3917] = { -- choke_breath_jugpet
            effect = 4,
            seconds = 30,
            by_effect = {
                [4] = { effect = 4, seconds = 30 },
                [6] = { effect = 6, seconds = 30 },
            },
        },
        [3918] = { effect = 45, seconds = 180 },  -- fantod_jugpet
        [3919] = { effect = 149, seconds = 180 },  -- tortoise_stomp_jugpet
        [3920] = { effect = 93, seconds = 180 },  -- harden_shell_jugpet
        [3922] = { effect = 10, seconds = 4 },  -- wing_slap_jugpet
        [3924] = { effect = 13, seconds = 120 },  -- intimidate_jugpet
        [3926] = { effect = 93, seconds = 90 },  -- water_wall_jugpet
        [3943] = { effect = 3, seconds = 60 },  -- acid_spray_jugpet
        [3944] = { effect = 13, seconds = 90 },  -- spider_web_jugpet
        [3954] = { effect = 91, seconds = 120 },  -- frenzied_rage
        [3960] = { effect = 10, seconds = 8 },  -- predatory_glare_jugpet
        [3968] = { -- fire_meeble_warble
            effect = 31,
            seconds = 60,
            by_effect = {
                [31] = { effect = 31, seconds = 60 },
                [128] = { effect = 128, seconds = 60 },
            },
        },
        [3969] = { -- blizzard_meeble_warble
            effect = 4,
            seconds = 60,
            by_effect = {
                [4] = { effect = 4, seconds = 60 },
                [129] = { effect = 129, seconds = 60 },
            },
        },
        [3970] = { -- thunder_meeble_warble
            effect = 10,
            seconds = 15,
            by_effect = {
                [10] = { effect = 10, seconds = 15 },
                [132] = { effect = 132, seconds = 60 },
            },
        },
        [3971] = { -- stone_meeble_warble
            effect = 7,
            seconds = 60,
            by_effect = {
                [7] = { effect = 7, seconds = 60 },
                [131] = { effect = 131, seconds = 60 },
            },
        },
        [3972] = { -- water_meeble_warble
            effect = 3,
            seconds = 60,
            by_effect = {
                [3] = { effect = 3, seconds = 60 },
                [133] = { effect = 133, seconds = 60 },
            },
        },
        [3973] = { -- aero_meeble_warble
            effect = 6,
            seconds = 60,
            by_effect = {
                [6] = { effect = 6, seconds = 60 },
                [130] = { effect = 130, seconds = 60 },
            },
        },
        [3974] = { effect = 149, seconds = 60 },  -- thrashing_assault
        [3975] = { -- drill_claw
            effect = 144,
            seconds = 60,
            by_effect = {
                [144] = { effect = 144, seconds = 60 },
                [189] = { effect = 189, seconds = 60 },
            },
        },
        [4255] = { -- mix_guard_drink
            effect = 40,
            seconds = 300,
            by_effect = {
                [40] = { effect = 40, seconds = 300 },
                [41] = { effect = 41, seconds = 300 },
            },
        },
        [4256] = { effect = 626, seconds = 60 },  -- mix_insomniant
        [4257] = { effect = 42, seconds = 60 },  -- mix_life_water
        [4258] = { effect = 190, seconds = 60 },  -- mix_elemental_power
        [4259] = { effect = 191, seconds = 60 },  -- mix_dragon_shield
    },
    -- Pet skill IDs from the action packet.
    pacts = {
        [513] = { effect = 3, seconds = 90 },  -- poison_nails
        [514] = { effect = 154, seconds = 180 },  -- shining_ruby
        [522] = { effect = 2, seconds = 30 },  -- mewing_lullaby
        [523] = { -- eerie_eye
            effect = 6,
            seconds = 30,
            by_effect = {
                [6] = { effect = 6, seconds = 30 },
                [16] = { effect = 16, seconds = 15 },
            },
        },
        [526] = { effect = 113, seconds = 3600 },  -- reraise_ii
        [527] = { effect = 113 },  -- altana_s_favor
        [528] = { effect = 5, seconds = 60 },  -- moonlit_charge
        [529] = { effect = 4, seconds = 60 },  -- crescent_fang
        [530] = { -- lunar_cry
            effect = 146,
            by_effect = {
                [146] = { effect = 146 },
                [148] = { effect = 148 },
            },
        },
        [532] = { -- ecliptic_growl
            effect = 80,
            seconds = 180,
            by_effect = {
                [80] = { effect = 80, seconds = 180 },
                [81] = { effect = 81, seconds = 180 },
                [82] = { effect = 82, seconds = 180 },
                [83] = { effect = 83, seconds = 180 },
                [84] = { effect = 84, seconds = 180 },
                [85] = { effect = 85, seconds = 180 },
                [86] = { effect = 86, seconds = 180 },
            },
        },
        [533] = { -- ecliptic_howl
            effect = 90,
            seconds = 180,
            by_effect = {
                [90] = { effect = 90, seconds = 180 },
                [92] = { effect = 92, seconds = 180 },
            },
        },
        [548] = { effect = 68 },  -- crimson_howl
        [560] = { effect = 13, seconds = 120 },  -- rock_throw
        [562] = { effect = 11, seconds = 120 },  -- rock_buster
        [563] = { -- megalith_throw
            effect = 13,
            seconds = 120,
        },
        [564] = { effect = 37, seconds = 900 },  -- earthen_ward
        [567] = { effect = 10, seconds = 4 },  -- geocrush
        [578] = { effect = 12, seconds = 120 },  -- tail_whip
        [580] = { effect = 13 },  -- slowga
        [585] = { effect = 147 },  -- tidal_roar
        [586] = { effect = 586, seconds = 180 },  -- soothing_current
        [595] = { effect = 33 },  -- hastega
        [596] = { effect = 36, seconds = 900 },  -- aerial_armor
        [610] = { effect = 35 },  -- frost_armor
        [611] = { effect = 2, seconds = 90 },  -- sleepga
        [624] = { effect = 10, seconds = 12 },  -- shock_strike
        [626] = { effect = 98 },  -- rolling_thunder
        [627] = { -- thunderspark
            effect = 4,
            seconds = 60,
        },
        [628] = { effect = 38 },  -- lightning_armor
        [630] = { -- chaotic_strike
            effect = 10,
            seconds = 12,
        },
        [657] = { -- somnolence
            effect = 12,
            seconds = 120,
        },
        [658] = { effect = 2, seconds = 90, deep = true },  -- nightmare
        [660] = { effect = 116, seconds = 180 },  -- noctoshield
        [661] = { -- dream_shroud
            effect = 190,
            seconds = 180,
            by_effect = {
                [190] = { effect = 190, seconds = 180 },
                [191] = { effect = 191, seconds = 180 },
            },
        },
        [671] = { effect = 283 },  -- perfect_defense
        [673] = { -- dust_cloud
            effect = 5,
            seconds = 120,
        },
        [676] = { effect = 2, seconds = 60 },  -- dream_flower
        [677] = { effect = 138, seconds = 120 },  -- wild_oats
        [678] = { effect = 3, seconds = 90 },  -- leaf_dagger
        [679] = { effect = 141, seconds = 180 },  -- scream
        [680] = { effect = 4, seconds = 120 },  -- roar
        [683] = { effect = 10, seconds = 4 },  -- tail_blow
        [686] = { effect = 6, seconds = 30 },  -- brain_crush
        [687] = { effect = 148, seconds = 180 },  -- infrasonics
        [688] = { effect = 92, seconds = 60 },  -- secretion
        [690] = { effect = 56, seconds = 120 },  -- rage
        [692] = { effect = 2, seconds = 45 },  -- sheep_song
        [693] = { -- bubble_shower
            effect = 136,
            seconds = 180,
        },
        [694] = { effect = 41, seconds = 180 },  -- bubble_curtain
        [696] = { effect = 93, seconds = 60 },  -- scissor_guard
        [697] = { effect = 37, seconds = 300 },  -- metallic_body
        [701] = { effect = 4, seconds = 180 },  -- spore
        [702] = { effect = 3, seconds = 60 },  -- queasyshroom
        [703] = { effect = 4, seconds = 180 },  -- numbshroom
        [704] = { effect = 8, seconds = 720 },  -- shakeshroom
        [705] = { -- silence_gas
            effect = 6,
            seconds = 60,
        },
        [706] = { -- dark_spore
            effect = 5,
            seconds = 90,
        },
        [708] = { effect = 148, seconds = 180 },  -- hi-freq_field
        [710] = { effect = 92, seconds = 540 },  -- rhino_guard
        [711] = { effect = 136, seconds = 540 },  -- spoil
        [713] = { effect = 3, seconds = 60 },  -- venom
        [714] = { effect = 5, seconds = 90 },  -- sandblast
        [715] = { effect = 11, seconds = 60 },  -- sandpit
        [716] = { effect = 3, seconds = 120 },  -- venom_spray
        [718] = { effect = 2, seconds = 30 },  -- soporific
        [719] = { effect = 13, seconds = 180 },  -- gloeosuccus
        [720] = { effect = 4, seconds = 60 },  -- palsy_pollen
        [722] = { effect = 10, seconds = 10 },  -- numbing_noise
        [725] = { effect = 3, seconds = 180 },  -- toxic_spit
        [729] = { effect = 13, seconds = 120 },  -- filamented_hold
        [730] = { effect = 6, seconds = 60 },  -- chaotic_eye
        [731] = { effect = 4, seconds = 60 },  -- blaster
        [732] = { effect = 10, seconds = 4 },  -- suction
        [734] = { -- snow_cloud
            effect = 4,
            seconds = 120,
        },
        [736] = { effect = 10, seconds = 4 },  -- sudden_lunge
        [737] = { effect = 146, seconds = 60 },  -- spiral_spin
        [738] = { effect = 147, seconds = 120 },  -- noisome_powder
        [740] = { -- acid_mist
            effect = 147,
            seconds = 120,
        },
        [743] = { effect = 10, seconds = 4 },  -- scythe_tail
        [745] = { effect = 13, seconds = 180 },  -- chomp_rush
        [747] = { -- purulent_ooze
            effect = 135,
            seconds = 120,
            by_effect = {
                [135] = { effect = 135, seconds = 120 },
                [144] = { effect = 144, seconds = 120 },
            },
        },
        [748] = { -- corrosive_ooze
            effect = 147,
            seconds = 120,
            by_effect = {
                [147] = { effect = 147, seconds = 120 },
                [149] = { effect = 149, seconds = 120 },
            },
        },
        [750] = { effect = 28, seconds = 15 },  -- jettatura
        [751] = { -- choke_breath
            effect = 4,
            seconds = 30,
            by_effect = {
                [4] = { effect = 4, seconds = 30 },
                [6] = { effect = 6, seconds = 30 },
            },
        },
        [752] = { effect = 45, seconds = 180 },  -- fantod
        [753] = { -- tortoise_stomp
            effect = 149,
            seconds = 180,
        },
        [754] = { effect = 93, seconds = 180 },  -- harden_shell
        [756] = { effect = 10, seconds = 4 },  -- wing_slap
        [758] = { effect = 13, seconds = 120 },  -- intimidate
        [760] = { effect = 93, seconds = 90 },  -- water_wall
        [790] = { effect = 91, seconds = 120 },  -- frenzied_rage
        [796] = { effect = 10, seconds = 8 },  -- predatory_glare
        [960] = { -- clarsach_call
            effect = 91,
            seconds = 180,
            by_effect = {
                [91] = { effect = 91, seconds = 180 },
                [92] = { effect = 92, seconds = 180 },
                [93] = { effect = 93, seconds = 180 },
                [190] = { effect = 190, seconds = 180 },
                [191] = { effect = 191, seconds = 180 },
                [611] = { effect = 611, seconds = 180 },
            },
        },
    },
    -- Item IDs and their added-effect durations.
    procs = {
        [16387] = 30,
        [16403] = 30,
        [16404] = 30,
        [16410] = 30,
        [16417] = 30,
        [16418] = 30,
        [16425] = 30,
        [16429] = 30,
        [16430] = 60,
        [16431] = 5,
        [16432] = 5,
        [16438] = 30,
        [16439] = 30,
        [16454] = 30,
        [16458] = 30,
        [16459] = 60,
        [16471] = 30,
        [16472] = 30,
        [16478] = 30,
        [16479] = 60,
        [16489] = 30,
        [16490] = 30,
        [16493] = 30,
        [16494] = 60,
        [16495] = 30,
        [16496] = 30,
        [16497] = 25,
        [16499] = 30,
        [16501] = 60,
        [16502] = 30,
        [16503] = 5,
        [16504] = 180,
        [16505] = 30,
        [16506] = 5,
        [16507] = 30,
        [16508] = 30,
        [16510] = 30,
        [16525] = 30,
        [16533] = 30,
        [16692] = 30,
        [16693] = 30,
        [16700] = 30,
        [16741] = 30,
        [16742] = 30,
        [16743] = 30,
        [16761] = 30,
        [16762] = 30,
        [16773] = 60,
        [16863] = 60,
        [16897] = 20,
        [16905] = 30,
        [16906] = 30,
        [16907] = 30,
        [16908] = 60,
        [16909] = 30,
        [16910] = 3,
        [16925] = 30,
        [16926] = 30,
        [16927] = 30,
        [16974] = 30,
        [17069] = 12,
        [17083] = 30,
        [17106] = 30,
        [17116] = 30,
        [17117] = 25,
        [17325] = 60,
        [17329] = 30,
        [17464] = 5,
        [17483] = 30,
        [17484] = 5,
        [17486] = 5,
        [17487] = 60,
        [17492] = 30,
        [17600] = 5,
        [17605] = 60,
        [17606] = 60,
        [17607] = 60,
        [17608] = 60,
        [17614] = 5,
        [17627] = 30,
        [17650] = 60,
        [17695] = 60,
        [17768] = 60,
        [17770] = 3,
        [17797] = 60,
        [18008] = 30,
        [18010] = 60,
        [18011] = 60,
        [18012] = 60,
        [18013] = 60,
        [18032] = 60,
        [18033] = 60,
        [18110] = 30,
        [18111] = 30,
        [18118] = 30,
        [18119] = 30,
        [18123] = 30,
        [18124] = 30,
        [18148] = 60,
        [18149] = 25,
        [18150] = 30,
        [18152] = 30,
        [18157] = 30,
        [18158] = 25,
        [18159] = 60,
        [18160] = 5,
        [18270] = 30,
        [18288] = 60,
        [18294] = 60,
        [18300] = 60,
        [18306] = 30,
        [18312] = 30,
        [18318] = 60,
        [18355] = 30,
        [18357] = 60,
        [18410] = 60,
        [18708] = 30,
        [18709] = 30,
        [19019] = 5,
        [19020] = 5,
        [19163] = 10,
        [19796] = 30,
        [19797] = 30,
        [20640] = 180,
        [21314] = 60,
    },
    -- The status each added-effect item applies.
    proc_effects = {
        [16387] = 3,
        [16403] = 3,
        [16404] = 3,
        [16410] = 3,
        [16417] = 3,
        [16418] = 3,
        [16425] = 3,
        [16429] = 6,
        [16430] = 149,
        [16431] = 10,
        [16432] = 10,
        [16438] = 6,
        [16439] = 3,
        [16454] = 5,
        [16458] = 3,
        [16459] = 149,
        [16471] = 5,
        [16472] = 3,
        [16478] = 3,
        [16479] = 149,
        [16489] = 3,
        [16490] = 5,
        [16493] = 5,
        [16494] = 149,
        [16495] = 6,
        [16496] = 3,
        [16497] = 2,
        [16499] = 3,
        [16501] = 149,
        [16502] = 3,
        [16503] = 10,
        [16504] = 33,
        [16505] = 3,
        [16506] = 10,
        [16507] = 3,
        [16508] = 6,
        [16510] = 3,
        [16525] = 3,
        [16533] = 9,
        [16692] = 3,
        [16693] = 3,
        [16700] = 3,
        [16741] = 3,
        [16742] = 3,
        [16743] = 3,
        [16761] = 3,
        [16762] = 3,
        [16773] = 148,
        [16863] = 148,
        [16897] = 11,
        [16905] = 5,
        [16906] = 6,
        [16907] = 3,
        [16908] = 149,
        [16909] = 3,
        [16910] = 10,
        [16925] = 6,
        [16926] = 5,
        [16927] = 3,
        [16974] = 148,
        [17069] = 155,
        [17083] = 11,
        [17106] = 149,
        [17116] = 9,
        [17117] = 2,
        [17325] = 6,
        [17329] = 4,
        [17464] = 10,
        [17483] = 3,
        [17484] = 10,
        [17486] = 10,
        [17487] = 149,
        [17492] = 4,
        [17600] = 10,
        [17605] = 149,
        [17606] = 149,
        [17607] = 149,
        [17608] = 149,
        [17614] = 10,
        [17627] = 6,
        [17650] = 3,
        [17695] = 148,
        [17768] = 149,
        [17770] = 10,
        [17797] = 6,
        [18008] = 6,
        [18010] = 149,
        [18011] = 149,
        [18012] = 149,
        [18013] = 149,
        [18032] = 148,
        [18033] = 148,
        [18110] = 148,
        [18111] = 148,
        [18118] = 148,
        [18119] = 148,
        [18123] = 148,
        [18124] = 148,
        [18148] = 149,
        [18149] = 2,
        [18150] = 5,
        [18152] = 3,
        [18157] = 3,
        [18158] = 2,
        [18159] = 147,
        [18160] = 10,
        [18270] = 3,
        [18288] = 130,
        [18294] = 148,
        [18300] = 149,
        [18306] = 5,
        [18312] = 4,
        [18318] = 147,
        [18355] = 6,
        [18357] = 149,
        [18410] = 149,
        [18551] = 19,
        [18566] = 19,
        [18708] = 3,
        [18709] = 3,
        [19019] = 10,
        [19020] = 10,
        [19163] = 28,
        [19796] = 4,
        [19797] = 4,
        [20640] = 2,
        [21314] = 149,
    },
    -- Song bonuses and Shadowbind seconds by item ID.
    gear = {
        elegy = { [17352] = 1, [17371] = 2, [17856] = 3 },
        lullaby = {
            [17366] = 1,
            [17841] = 2,
            [17854] = 2,
            [18343] = 3,
            [21400] = 2,
            [21401] = 2,
            [21402] = 2,
            [21403] = 3,
            [23183] = 1,
            [23518] = 2,
            [27952] = 1,
            [27973] = 1,
        },
        requiem = { [17346] = 2, [17362] = 2, [17372] = 1, [17379] = 2, [17832] = 3, [17844] = 1, [17852] = 4 },
        shadowbind = { [13971] = 10, [14900] = 10, [23184] = 14, [23519] = 16, [27953] = 6, [27974] = 12 },
        songs = {
            [18342] = 2,
            [18572] = 4,
            [18577] = 2,
            [18578] = 2,
            [18579] = 3,
            [18580] = 3,
            [18840] = 4,
            [21400] = 1,
            [21401] = 2,
            [21405] = 2,
            [26031] = 1,
            [26032] = 2,
            [26033] = 3,
        },
        threnody = { [17347] = 1, [17368] = 2, [17842] = 3 },
    },
    -- Merit IDs, base seconds, seconds per rank and the enabled rank cap.
    merits = {
        angon = { id = 2882, base = 15, per_rank = 15, most = 3 },
        bio_iii = { id = 2312, base = 0, per_rank = 30, most = 3 },
        dia_iii = { id = 2304, base = 0, per_rank = 30, most = 3 },
        penance = { id = 2118, base = 0, per_rank = 20, most = 3 },
        tomahawk = { id = 2050, base = 15, per_rank = 15, most = 3 },
    },
    troubadour = 348,
}
