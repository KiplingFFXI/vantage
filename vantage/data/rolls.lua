-- The Phantom Rolls in era (content tag TOAU, sql/abilities.sql :118-135) as Phoenix 730ac619c0 plays them, by ability
-- id: the power at each total from 1 to 11 (scripts/globals/job_utils/corsair.lua rollData :16-357, where the era tables
-- of modules/era/lua/globals/job_utils/corsair.lua :25-96 replace them), the job whose main job in the party adds the
-- bonus, the power of a bust, and the lucky and unlucky numbers, where the table spikes and dips. Phoenix has no code
-- for lucky and unlucky numbers; they are only what the table says. Evoker's Roll's table ties at 1 and 3, so its
-- numbers are the script header's (scripts/actions/abilities/evokers_roll.lua :5-6). gives is what the roll's effect
-- adds at its power (scripts/effects/<name>_roll.lua :8-9; the era Healer's, Gallant's, Drachen and Puppet Roll
-- effects are in the era corsair.lua :235-297), and busts what a bust takes from the Corsair (scripts/effects/bust.lua
-- :7-23, which also lowers ranged accuracy with accuracy and ranged attack with attack). Drachen, Beast and Puppet Roll
-- bust with no penalty (bustMod NONE). The era tables and effects are Lua overrides, which Phoenix applies only with
-- RESTRICT_CONTENT on (modules/module_utils.lua :79-95); with it off it plays the base tables, and Dancer's and
-- Scholar's Roll too.
return {
    [114] = { name = "Corsair's Roll", job = 17, powers = { 10, 11, 11, 12, 20, 13, 15, 16, 8, 17, 24 }, bonus = 0, bust = 6,
        lucky = 5, unlucky = 9, gives = 'Experience +%d%%', busts = 'Experience -%d%%' },                              -- :18
    [110] = { name = 'Ninja Roll', job = 13, powers = { 4, 6, 8, 25, 10, 12, 14, 2, 17, 20, 30 }, bonus = 10, bust = 15,
        lucky = 4, unlucky = 8, gives = 'Evasion +%d', busts = 'Evasion -%d' },                                         -- era :27-31
    [108] = { name = "Hunter's Roll", job = 11, powers = { 10, 13, 15, 40, 18, 20, 25, 5, 28, 30, 50 }, bonus = 15, bust = 15,
        lucky = 4, unlucky = 8, gives = 'Accuracy and ranged accuracy +%d', busts = 'Accuracy and ranged accuracy -%d' }, -- :40
    [105] = { name = 'Chaos Roll', job = 8, powers = { 6, 8, 9, 25, 11, 13, 16, 3, 17, 19, 31 }, bonus = 10, bust = 10,
        lucky = 4, unlucky = 8, gives = 'Attack and ranged attack +%d%%', busts = 'Attack and ranged attack -%d%%' },   -- :51
    [113] = { name = "Magus's Roll", job = 16, powers = { 5, 20, 6, 8, 9, 3, 10, 13, 14, 15, 25 }, bonus = 8, bust = 8,
        lucky = 2, unlucky = 6, gives = 'Magic defense +%d', busts = 'Magic defense -%d' },                             -- :62
    [100] = { name = "Healer's Roll", job = 3, powers = { 2, 3, 10, 4, 4, 5, 1, 6, 7, 7, 12 }, bonus = 3, bust = 4,
        lucky = 3, unlucky = 7, gives = 'MP recovered while healing +%d', busts = 'Cure potency received -%d%%' },     -- era :74-78
    [111] = { name = 'Drachen Roll', job = 14, powers = { 4, 5, 18, 7, 9, 10, 2, 11, 13, 15, 22 }, bonus = 8, bust = 15,
        lucky = 3, unlucky = 7, gives = 'Pet magic attack and magic accuracy +%d' },                                    -- era :86-90
    [107] = { name = 'Choral Roll', job = 10, powers = { 4, 17, 5, 6, 7, 2, 8, 10, 11, 12, 21 }, bonus = 8, bust = 25,
        lucky = 2, unlucky = 6, gives = 'Spell interruption rate -%d%%', busts = 'Spell interruption rate +%d%%' },     -- era :62-66
    [99] = { name = "Monk's Roll", job = 2, powers = { 8, 10, 32, 12, 14, 16, 4, 20, 22, 24, 40 }, bonus = 10, bust = 11,
        lucky = 3, unlucky = 7, gives = 'Subtle Blow +%d', busts = 'Subtle Blow -%d' },                                 -- :106
    [106] = { name = 'Beast Roll', job = 9, powers = { 5, 6, 7, 19, 8, 9, 12, 2, 13, 14, 23 }, bonus = 8, bust = 7,
        lucky = 4, unlucky = 8, gives = 'Pet attack +%d%%' },                                                           -- era :56-60, :10-21
    [109] = { name = 'Samurai Roll', job = 12, powers = { 8, 32, 10, 12, 14, 4, 16, 20, 22, 24, 40 }, bonus = 10, bust = 10,
        lucky = 2, unlucky = 6, gives = 'Store TP +%d', busts = 'Store TP -%d' },                                       -- :128
    [112] = { name = "Evoker's Roll", job = 15, powers = { 1, 1, 1, 1, 3, 2, 2, 2, 1, 3, 4 }, bonus = 1, bust = 1,
        lucky = 5, unlucky = 9, gives = 'Refresh +%d MP', busts = 'Refresh -%d MP' },                                   -- :139
    [103] = { name = "Rogue's Roll", job = 6, powers = { 2, 2, 3, 4, 12, 5, 6, 6, 1, 8, 19 }, bonus = 6, bust = 6,
        lucky = 5, unlucky = 9, gives = 'Critical hit rate +%d%%', busts = 'Critical hit rate -%d%%' },                 -- :150
    [102] = { name = "Warlock's Roll", job = 5, powers = { 2, 3, 4, 10, 4, 5, 6, 1, 7, 7, 12 }, bonus = 4, bust = 15,
        lucky = 4, unlucky = 8, gives = 'Magic accuracy +%d', busts = 'Magic accuracy -%d' },                           -- era :50-54
    [98] = { name = "Fighter's Roll", job = 1, powers = { 2, 2, 3, 4, 12, 5, 6, 7, 1, 9, 18 }, bonus = 6, bust = 6,
        lucky = 5, unlucky = 9, gives = 'Double Attack +%d%%', busts = 'Double Attack -%d%%' },                         -- :172
    [115] = { name = 'Puppet Roll', job = 18, powers = { 10, 13, 15, 40, 18, 20, 25, 5, 28, 30, 50 }, bonus = 15, bust = 8,
        lucky = 4, unlucky = 8, gives = 'Pet accuracy and ranged accuracy +%d' },                                       -- era :92-96
    [104] = { name = "Gallant's Roll", job = 7, powers = { 4, 5, 15, 6, 7, 8, 3, 9, 10, 12, 20 }, bonus = 10, bust = 11,
        lucky = 3, unlucky = 7, gives = 'Returns %d%% of physical damage taken', busts = 'Defense -%d%%' },             -- era :80-84
    [101] = { name = "Wizard's Roll", job = 4, powers = { 2, 3, 4, 4, 10, 5, 6, 7, 1, 7, 12 }, bonus = 4, bust = 10,
        lucky = 5, unlucky = 9, gives = 'Magic attack +%d', busts = 'Magic attack -%d' },                               -- era :33-37
}
