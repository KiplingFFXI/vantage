-- The debuffs a White Mage's spells take off at Phoenix revision ed41f351f6 (phoenix/live), each with the id of the
-- spell that does it. The -na spells and Cursna name theirs (scripts/actions/spells/white). Erase takes any effect that
-- data/status_effects.yaml flags erasable (src/map/status_effect_container.cpp:885): 38 of them, less the 7 that can't
-- exist on Phoenix (tools/export_catalog.py), which leaves 31. Built from those files; the name after each id is its
-- name there.
return {
    [3] = 14, -- poison, Poisona
    [4] = 15, -- paralysis, Paralyna
    [5] = 16, -- blindness, Blindna
    [6] = 17, -- silence, Silena
    [7] = 18, -- petrification, Stona
    [8] = 19, -- disease, Viruna
    [9] = 20, -- curse, Cursna
    [10] = 143, -- stun, Erase
    [11] = 143, -- bind, Erase
    [12] = 143, -- weight, Erase
    [13] = 143, -- slow, Erase
    [15] = 20, -- doom, Cursna
    [30] = 20, -- bane, Cursna
    [31] = 19, -- plague, Viruna
    [128] = 143, -- burn, Erase
    [129] = 143, -- frost, Erase
    [130] = 143, -- choke, Erase
    [131] = 143, -- rasp, Erase
    [132] = 143, -- shock, Erase
    [133] = 143, -- drown, Erase
    [134] = 143, -- dia, Erase
    [135] = 143, -- bio, Erase
    [136] = 143, -- str_down, Erase
    [137] = 143, -- dex_down, Erase
    [138] = 143, -- vit_down, Erase
    [139] = 143, -- agi_down, Erase
    [140] = 143, -- int_down, Erase
    [141] = 143, -- mnd_down, Erase
    [142] = 143, -- chr_down, Erase
    [144] = 143, -- max_hp_down, Erase
    [145] = 143, -- max_mp_down, Erase
    [146] = 143, -- accuracy_down, Erase
    [147] = 143, -- attack_down, Erase
    [148] = 143, -- evasion_down, Erase
    [149] = 143, -- defense_down, Erase
    [156] = 143, -- flash, Erase
    [167] = 143, -- magic_def_down, Erase
    [174] = 143, -- magic_acc_down, Erase
    [175] = 143, -- magic_atk_down, Erase
    [192] = 143, -- requiem, Erase
    [194] = 143, -- elegy, Erase
};
