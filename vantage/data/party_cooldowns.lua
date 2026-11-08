-- The abilities the party cooldown watch knows (core/party_cooldowns.lua): the two-hour abilities of the jobs in era
-- and a few key job abilities, with their Phoenix recasts at revision 730ac619c0 after the era SQL (modules/init.txt
-- :42-46). Each line gives the ability id, its job and its recast in seconds, and where the recast comes from:
-- sql/abilities.sql, then modules/era/sql/abyssea/revert_two_hours.sql :7-30 (every two-hour to 7200) and
-- modules/era/sql/abyssea/job_adjustments.sql. Two-hours share recast id 0 and take no merits. Trance and Tabula Rasa
-- are WotG jobs and are left out.
-- merits marks the ones merits can shorten: those with a meritModID that aren't merit abilities themselves
-- (src/map/entities/char_entity.cpp :1888), and Martyr, Devotion, Fealty and Chivalry, which the era Lua shortens
-- by their merits when RESTRICT_CONTENT is on (modules/era/lua/globals/job_utils/white_mage.lua :10-12, :28-30,
-- paladin.lua :92, :110). No gear in sql/item_mods.sql shortens any of them.
-- Eagle Eye Shot finishes as a weapon skill would (actionType 3, abilities.sql :46), so it is told from the weapon
-- skill with its id, Mercy Stroke, by its messages: 110 when it hits and 324 when it misses (era job_utils/ranger.lua
-- :40-44; scripts/enum/msg.lua :133, :244).
return {
    { id = 16, name = 'Mighty Strikes', job = 1, recast = 7200, special = true },   -- abilities.sql :36
    { id = 17, name = 'Hundred Fists', job = 2, recast = 7200, special = true },    -- :37
    { id = 18, name = 'Benediction', job = 3, recast = 7200, special = true },      -- :38
    { id = 19, name = 'Manafont', job = 4, recast = 7200, special = true },         -- :39
    { id = 20, name = 'Chainspell', job = 5, recast = 7200, special = true },       -- :40
    { id = 21, name = 'Perfect Dodge', job = 6, recast = 7200, special = true },    -- :41
    { id = 22, name = 'Invincible', job = 7, recast = 7200, special = true },       -- :42
    { id = 23, name = 'Blood Weapon', job = 8, recast = 7200, special = true },     -- :43
    { id = 24, name = 'Familiar', job = 9, recast = 7200, special = true },         -- :44
    { id = 25, name = 'Soul Voice', job = 10, recast = 7200, special = true },      -- :45
    { id = 26, name = 'Eagle Eye Shot', job = 11, recast = 7200, special = true, category = 3,
        messages = { [110] = true, [324] = true } },                                -- :46
    { id = 27, name = 'Meikyo Shisui', job = 12, recast = 7200, special = true },   -- :47
    { id = 28, name = 'Mijin Gakure', job = 13, recast = 7200, special = true },    -- :48
    { id = 29, name = 'Spirit Surge', job = 14, recast = 7200, special = true },    -- :49 (CoP)
    { id = 30, name = 'Astral Flow', job = 15, recast = 7200, special = true },     -- :50
    { id = 93, name = 'Azure Lore', job = 16, recast = 7200, special = true },      -- :113
    { id = 96, name = 'Wild Card', job = 17, recast = 7200, special = true },       -- :116
    { id = 135, name = 'Overdrive', job = 18, recast = 7200, special = true },      -- :154
    { id = 35, name = 'Provoke', job = 1, recast = 30 },                            -- abilities.sql :55
    { id = 31, name = 'Berserk', job = 1, recast = 300, merits = true },            -- :51
    { id = 32, name = 'Warcry', job = 1, recast = 300, merits = true },             -- :52
    { id = 74, name = 'Divine Seal', job = 3, recast = 600, merits = true },        -- :94
    { id = 153, name = 'Martyr', job = 3, recast = 1200, merits = true },           -- abyssea job_adjustments.sql :20
    { id = 154, name = 'Devotion', job = 3, recast = 1200, merits = true },         -- abyssea job_adjustments.sql :23
    { id = 75, name = 'Elemental Seal', job = 4, recast = 600, merits = true },     -- abilities.sql :95
    { id = 83, name = 'Convert', job = 5, recast = 600, merits = true },            -- :103
    { id = 48, name = 'Sentinel', job = 7, recast = 300, merits = true },           -- :68
    { id = 92, name = 'Rampart', job = 7, recast = 300, merits = true },            -- :112
    { id = 157, name = 'Fealty', job = 7, recast = 1200, merits = true },           -- abyssea job_adjustments.sql :65
    { id = 158, name = 'Chivalry', job = 7, recast = 1200, merits = true },         -- abyssea job_adjustments.sql :62
    { id = 85, name = 'Call Beast', job = 9, recast = 300, merits = true },         -- abilities.sql :105
    { id = 163, name = 'Nightingale', job = 10, recast = 600 },                     -- :182
    { id = 164, name = 'Troubadour', job = 10, recast = 600 },                      -- :183
    { id = 63, name = 'Meditate', job = 12, recast = 180, merits = true },          -- :83
    { id = 61, name = 'Call Wyvern', job = 14, recast = 1200 },                     -- :81
    { id = 133, name = 'Random Deal', job = 17, recast = 1200, merits = true },     -- :153
    { id = 136, name = 'Activate', job = 18, recast = 1200, merits = true },        -- :155
}
