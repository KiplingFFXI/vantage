-- Overhead icons, sampled: while Show samples is on for them, one block of invented effects drawn as a block of
-- the unit type picked on the Overhead icons page would be, above your own head, or a third of the way down the
-- middle of the screen when you aren't on it (overhead.sample in core/overhead.lua). It goes through that type's
-- filters, limits, layout, countdowns and size, so a change shows at once, and what can be removed lights whenever
-- the light is on; a party or alliance sample has sample party cooldowns while the watch is on and they go over
-- heads. It draws over the settings window. Nothing here is tracked or alerts. Every table is made once,
-- so a frame makes nothing.
local preview = {};
local overhead = require('core.overhead');
local draw = require('ui.overhead_icons');
local cooldowns = require('core.party_cooldowns');

-- Each sample: its effect id, debuff or buff, whether you cast it, the seconds its countdown runs down from before it
-- starts again (0 for no known time), and its catalog priority. A mob carries more than a single bar holds, so the
-- limit shows.
local MOB = {
    { 2, 'debuff', false, 60, 80 },     -- Sleep I, crowd control
    { 134, 'debuff', true, 120 },      -- Dia
    { 13, 'debuff', true, 180 },       -- Slow
    { 4, 'debuff', false, 120 },       -- Paralysis
    { 5, 'debuff', false, 0 },         -- Blindness
    { 194, 'debuff', false, 180 },     -- Elegy
    { 3, 'debuff', true, 60 },         -- Poison
    { 40, 'buff', false, 0 },          -- Protect, dispellable
    { 33, 'buff', false, 180 },        -- Haste, dispellable
    { 37, 'buff', false, 0 },          -- Stoneskin, dispellable
    { 34, 'buff', false, 90 },         -- Blaze Spikes, dispellable
};
-- Players and pets: the debuffs, then one of yours for each effect switch on the Overhead icons page, in its order, so
-- a switch moves the sample whatever Only buffs I cast is on. The two Always show effects are someone else's, as they are
-- on a party member, and go ahead of the switches' while ticked. Past them Haste and Refresh fill the limit, and Regen is
-- the buff someone else cast. With all seven on and those two unticked, the last is past a limit of 8.
local PLAYER = {
    { 3, 'debuff', false, 60 },        -- Poison
    { 13, 'debuff', false, 180 },      -- Slow
    { 310, 'buff', true, 300 },        -- Fighter's Roll
    { 214, 'buff', true, 240 },        -- March
    { 40, 'buff', true, 0 },           -- Protect
    { 251, 'buff', true, 0 },          -- Food
    { 100, 'buff', true, 150 },        -- Barfire
    { 353, 'buff', true, 0 },          -- Hasso
    { 253, 'buff', true, 0 },          -- Signet
    { 66, 'buff', false, 0 },          -- Copy Image
    { 67, 'buff', false, 0 },          -- Third Eye
    { 33, 'buff', true, 180 },         -- Haste
    { 43, 'buff', true, 150 },         -- Refresh
    { 42, 'buff', false, 75 },         -- Regen
};

local function rows(list)
    local out = {};
    for index, spec in ipairs(list) do
        out[index] = { effect = spec[1], kind = spec[2], mine = spec[3], cycle = spec[4], priority = spec[5] or 0,
            phase = index * 7, domain = 'status', status = 'server', present = true, name = 'Sample',
            first_seen = index, first_sequence = index };
    end
    return out;
end
local mob, players = rows(MOB), rows(PLAYER);

local unit = { id = 0, index = 0, kind = 'mob', target = true, subtarget = false, player = false, name = '', race = 0, hitbox = 0,
    size = 0, alpha = 1, x = 0, y = 0, anchor_x = 0, anchor_y = 0, depth = 0, distance = 0, ppy = 0, name_px = 0, arrow_px = 0 };
local plan = { valid = true, count = 1, units = { unit }, order = { 1 }, ui = 1, above = true };
local subject = { effects = mob };
local subjects = { [0] = subject };
-- The unit type the sample is laid out as.
local shown = 'mob';

-- The Overhead icons page names the unit type it edits. A new type shows its own size at once.
function preview.show(kind)
    if kind ~= shown then unit.size = 0; end
    shown = kind;
end

-- Draws the sample block when overhead icons and their Show samples are both on, after overhead.update. compiled
-- and recipients are the frame's shared hide rules and who they apply to. Returns how many icons it drew.
function preview.draw(settings, snapshot, now, compiled, recipients)
    local config = settings.overhead;
    if not config.enabled or not config.preview or not config.types[shown] then return 0; end
    if not overhead.sample(unit, settings, snapshot, shown) then return 0; end
    local effects = shown == 'mob' and mob or players;
    for index = 1, #effects do
        local effect = effects[index];
        if effect.cycle > 0 then effect.remaining = effect.cycle - (now + effect.phase) % effect.cycle; end
    end
    subject.effects = effects;
    -- A party or alliance sample shows the party cooldown samples in its line, when the watch is on and they go over
    -- heads.
    local watch = settings.party_cooldowns;
    subject.cooldowns = (shown == 'party' or shown == 'alliance') and type(watch) == 'table' and watch.enabled and watch.overhead
        and cooldowns.samples(now) or nil;
    plan.ui, plan.above = overhead.plan.ui, overhead.plan.above;
    return draw.draw(plan, subjects, settings, now, compiled, recipients, true);
end

if VANTAGE_TEST_MODE then
    preview._unit, preview._plan = unit, plan;
end

return preview;
