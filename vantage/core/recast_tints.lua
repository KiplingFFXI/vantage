-- Recast tints (settings.recast_tints). A spell recast row tints when your MP is below the spell's cost. A spell row
-- shows a grey lock, with the lock's time left, while you are Silenced or Muted, and an ability row while Amnesia is
-- on you. Salvage's Omerta and Impairment lock spells and abilities the same way. The rows are marked at each refresh
-- from your own status list, whose timers the client gives; ui/hud.lua draws the tints, and never over a countdown.
-- Display only: nothing here casts or tells you what to do. Each tint is off at first, like the overhead icons.
--
-- Phoenix at revision 730ac619c0:
-- - A spell can't be cast under Silence (6) or Mute (29) (src/map/ai/states/magic_state.cpp :379), nor under
--   Omerta (262) when its power has the spell's group bit (:385-388). A job ability can't be used under Amnesia (16),
--   nor under Impairment (261) of power 1 or 3 (src/map/ai/states/ability_state.cpp :263-264).
-- - Salvage puts Omerta 63 (every group) and Impairment 3 on at entry (scripts/globals/salvage.lua :62-63,
--   zones/Arrapago_Remnants and Bhaflau_Remnants instances :14-15 and :123-124). Nyzul Isle's Omerta stops only the
--   groups of spells its power holds and its Impairment abilities, weapon skills or both, a gear mob's penalty adding
--   its group to one already on (scripts/globals/nyzul/pathos.lua :20-27, :111-120), and the client isn't told
--   which, so those lock nothing.
-- - A spell needs MP at least its cost (src/map/utils/battleutils.cpp CanAffordSpell :5734, :5761). Songs and
--   ninjutsu cost none (src/map/spell.cpp :172-175). Manafont (47) skips the check (battleutils.cpp :5742). Gear that
--   lowers the cost isn't seen.
local tints = {};
local numbers = require('ui.numbers');
local finite = numbers.finite;

local SILENCE, MUTE, AMNESIA, MANAFONT, IMPAIRMENT, OMERTA = 6, 29, 16, 47, 261, 262;
-- Zhayolm, Arrapago, Bhaflau and Silver Sea Remnants (Phoenix docs/ZoneIDs.txt :79-82).
local SALVAGE = { [73] = true, [74] = true, [75] = true, [76] = true };

-- The spell costs era SQL changes, which the client's spell data doesn't know: the elemental nukes
-- (modules/era/sql/soa/spell_adjustments.sql :13-76) and Raise II and III and Reraise II and III
-- (modules/era/sql/wotg/spell_adjustments.sql :23-35). The others are the client's ManaCost.
tints.era_costs = {
    [13] = 200, [140] = 250, [141] = 175, [142] = 200,
    [144] = 24, [145] = 68, [146] = 113, [147] = 157, [149] = 30, [150] = 77, [151] = 120, [152] = 164,
    [154] = 18, [155] = 59, [156] = 106, [157] = 150, [159] = 9, [160] = 43, [161] = 92, [162] = 138,
    [164] = 37, [165] = 86, [166] = 128, [167] = 171, [169] = 13, [170] = 51, [171] = 98, [172] = 144,
    [174] = 71, [175] = 158, [176] = 277, [179] = 82, [180] = 175, [181] = 299, [184] = 57, [185] = 138, [186] = 252,
    [189] = 37, [190] = 109, [191] = 211, [194] = 95, [195] = 193, [196] = 322, [199] = 47, [200] = 123, [201] = 231,
    [204] = 383, [205] = 287, [206] = 307, [207] = 287, [208] = 322, [209] = 287, [210] = 337, [211] = 287,
    [212] = 352, [213] = 287, [214] = 368, [215] = 287,
};

-- A grey that reads on any icon, and a blue for MP.
function tints.make()
    return { mp = false, mp_color = { 0.25, 0.45, 1, 0.45 }, spell_lock = false, spell_lock_color = { 0.62, 0.62, 0.62, 0.6 },
        ability_lock = false, ability_lock_color = { 0.62, 0.62, 0.62, 0.6 } };
end

local function rgba(value, fallback)
    local result = {};
    for index = 1, 4 do
        local part = type(value) == 'table' and value[index] or nil;
        result[index] = numbers.clamp(part, 0, 1, fallback[index]);
    end
    return result;
end

-- Keys this doesn't know are kept, as the rest of the settings keep them.
function tints.tidy(value)
    value = type(value) == 'table' and value or {};
    local fresh = tints.make();
    for _, key in ipairs({ 'mp', 'spell_lock', 'ability_lock' }) do
        if type(value[key]) ~= 'boolean' then value[key] = fresh[key]; end
        value[key .. '_color'] = rgba(value[key .. '_color'], fresh[key .. '_color']);
    end
    return value;
end

-- A spell's MP cost: the era one, else the client's, kept once read. Nil while the client's data can't be read.
local costs = {};
local function index_of(object, key) return object[key]; end
function tints.cost(id)
    if not finite(id) then return nil; end
    local era = tints.era_costs[id];
    if era then return era; end
    local saved = costs[id];
    if saved ~= nil then return saved or nil; end
    local ok, resources = pcall(function() return AshitaCore:GetResourceManager(); end);
    if not ok or not resources then return nil; end
    local found, spell = pcall(resources.GetSpellById, resources, id);
    if not found or spell == nil then return nil; end
    local read, cost = pcall(index_of, spell, 'ManaCost');
    cost = read and finite(cost) and cost >= 0 and cost or false;
    costs[id] = cost;
    return cost or nil;
end

-- The latest end of the locks that are on: false when one of them has no known end.
local function later(held, deadline)
    if held == false then return false; end
    if not finite(deadline) then return false; end
    return held and math.max(held, deadline) or deadline;
end

-- Marks each recast row: tint_mp when the spell costs more MP than you have, locked and lock_deadline (nil when the
-- lock's end isn't known) while you can't cast spells or use abilities.
function tints.mark(rows, snapshot, settings)
    local config = type(settings) == 'table' and settings.recast_tints;
    if type(rows) ~= 'table' then return; end
    local spells, abilities, manafont;
    -- With every tint off the status list isn't looked at; the rows below are still cleared.
    local on = type(config) == 'table' and (config.mp or config.spell_lock or config.ability_lock);
    if on and type(snapshot) == 'table' and snapshot.valid then
        local salvage = SALVAGE[snapshot.zone] == true;
        for _, effect in ipairs(snapshot.self_effects or {}) do
            local id = effect.effect;
            if id == SILENCE or id == MUTE or id == OMERTA and salvage then spells = later(spells, effect.deadline);
            elseif id == AMNESIA or id == IMPAIRMENT and salvage then abilities = later(abilities, effect.deadline);
            elseif id == MANAFONT then manafont = true; end
        end
    end
    local mp = type(snapshot) == 'table' and snapshot.mp;
    for _, row in ipairs(rows) do
        row.tint_mp, row.locked, row.lock_deadline = nil, nil, nil;
        if row.domain == 'recast' and type(config) == 'table' then
            if row.kind == 'spell' then
                if config.spell_lock and spells ~= nil then row.locked, row.lock_deadline = true, spells or nil; end
                if config.mp and not manafont and finite(mp) then
                    local cost = tints.cost(row.recast_id);
                    if cost and cost > mp then row.tint_mp = true; end
                end
            elseif row.kind == 'ability' and config.ability_lock and abilities ~= nil then
                row.locked, row.lock_deadline = true, abilities or nil;
            end
        end
    end
end

if VANTAGE_TEST_MODE then
    function tints._forget() costs = {}; end
end

return tints;
