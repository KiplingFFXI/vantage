-- Debuffs you can remove light up. data/cleansable.lua lists what a White Mage's spells take off, and core/dispel.lua
-- works out at most four times a second what you can take off now: WHM main or sub, the level met and the spell
-- learned. Erase reaches your party only. Over heads the light is on at first on Party, Alliance and You, it never
-- changes order, and Mobs, Other players and pets don't have it. The self debuffs and party panels and the party list
-- icons have it off at first. Samples light whatever your job, and each sample shows a debuff that lights.
local dispel = require('core.dispel');
local defaults, store = require('ui.defaults'), require('core.store');
local catalog, entries = require('core.catalog'), require('data.catalog');
local cleansable = require('data.cleansable');
local theme = require('ui.theme');
local share = require('core.share');
local imgui = require('imgui');
-- The mock keeps a record of each call, so colors are packed around it and a frame's memory counts only the addon's.
rawset(imgui, 'col32', function(a, r, g, b) return bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r); end);

-- The spells, by id, with their White Mage levels and the effects each takes off.
local LEVELS = { [14] = 6, [15] = 9, [16] = 14, [17] = 19, [20] = 29, [143] = 32, [19] = 34, [18] = 39 };
local EFFECTS = { [14] = { 3 }, [15] = { 4 }, [16] = { 5 }, [17] = { 6 }, [20] = { 9, 15, 30 }, [19] = { 8, 31 }, [18] = { 7 }, [143] = {} };
for _, range in ipairs({ { 10, 13 }, { 128, 142 }, { 144, 149 }, { 156, 156 }, { 167, 167 }, { 174, 175 }, { 192, 192 }, { 194, 194 } }) do
    for id = range[1], range[2] do table.insert(EFFECTS[143], id); end;
end;
assert(#EFFECTS[143] == 31, 'Fixture: Erase takes 31 effects.');

-- The list: every effect with its spell, and nothing else, each a debuff the catalog lists.
local expected, count = {}, 0;
for spell, ids in pairs(EFFECTS) do for _, id in ipairs(ids) do expected[id] = spell; end; end;
for id, spell in pairs(cleansable) do
    count = count + 1;
    assert(expected[id] == spell, 'Effect ' .. id .. ' goes with spell ' .. tostring(expected[id]) .. ', not ' .. tostring(spell));
    assert(entries[id] and catalog.get(id).kind == 'debuff', 'A debuff the catalog lists: ' .. id);
end;
assert(count == 41, 'Ten effects for the other spells and 31 for Erase: ' .. count);

-- The player. All eight spells are learned unless a test says otherwise, whatever the job.
local P = { main = 3, main_level = 75, sub = 0, sub_level = 0, spells = {}, reads = 0, asked = 0 };
local function learn_all() for spell in pairs(LEVELS) do P.spells[spell] = true; end; end;
learn_all();
local player = {
    GetMainJob = function() P.reads = P.reads + 1; return P.main; end, GetMainJobLevel = function() return P.main_level; end,
    GetSubJob = function() return P.sub; end, GetSubJobLevel = function() return P.sub_level; end,
    HasSpell = function(_, id) P.asked = P.asked + 1; return P.spells[id] == true; end,
};
local manager = { GetPlayer = function() return player; end };
AshitaCore.GetMemoryManager = function() return manager; end;
local now = 100;
local function job(main, main_level, sub, sub_level)
    P.main, P.main_level, P.sub, P.sub_level = main, main_level, sub or 0, sub_level or 0;
end;
-- The sets, past the quarter second it keeps them.
local function sets()
    now = now + 1;
    return dispel.cleansable(now);
end;
local function lit_spells(set)
    local out = {};
    for spell, ids in pairs(EFFECTS) do
        local on = 0;
        for _, id in ipairs(ids) do if set[id] then on = on + 1; end; end;
        assert(on == 0 or on == #ids, 'A spell lights all it takes off or none: ' .. spell);
        if on > 0 then out[#out + 1] = spell; end;
    end;
    table.sort(out);
    return table.concat(out, ' ');
end;

-- A White Mage at each spell's level has it, and a level under doesn't.
for spell, level in pairs(LEVELS) do
    job(3, level);
    local near = sets();
    assert(near[EFFECTS[spell][1]], 'WHM ' .. level .. ' can use spell ' .. spell);
    job(3, level - 1);
    near = sets();
    assert(not near[EFFECTS[spell][1]], 'WHM ' .. (level - 1) .. ' can\'t use spell ' .. spell);
end;
job(3, 75);
local near, far = sets();
assert(lit_spells(near) == '14 15 16 17 18 19 20 143', 'WHM 75 reaches everything on the party: ' .. lit_spells(near));
-- Erase reaches your party only.
assert(lit_spells(far) == '14 15 16 17 18 19 20', 'WHM 75 reaches everything but Erase on the alliance: ' .. lit_spells(far));
-- From the sub job, by the sub level, which stops at 37: no Stona.
job(1, 75, 3, 37);
near, far = sets();
assert(lit_spells(near) == '14 15 16 17 19 20 143' and lit_spells(far) == '14 15 16 17 19 20', '/WHM 37 has all but Stona: ' .. lit_spells(near));
job(1, 40, 3, 20);
assert(lit_spells((sets())) == '14 15 16 17', '/WHM 20 has the first four.');
-- Level Sync: the levels are the ones the client shows.
job(3, 25, 5, 12);
assert(lit_spells((sets())) == '14 15 16 17', 'A WHM synced to 25 is a WHM 25.');
-- Learned, or it doesn't light.
job(3, 75);
P.spells = {};
assert(lit_spells((sets())) == '', 'A WHM who learned none lights nothing.');
P.spells[20] = true;
assert(lit_spells((sets())) == '20', 'Only what is learned.');
learn_all();
-- Any other job lights nothing, spells or no spells, and asks about no spell.
for main = 1, 22 do
    if main ~= 3 then
        job(main, 75, main == 1 and 2 or 1, 37);
        P.asked = 0;
        near, far = sets();
        assert(lit_spells(near) == '' and lit_spells(far) == '' and P.asked == 0, 'Job ' .. main .. ' lights nothing.');
    end;
end;
-- With no player to read, nothing lights and nothing breaks.
local saved_player = manager.GetPlayer;
manager.GetPlayer = function() return nil; end;
assert(lit_spells((sets())) == '', 'No player, no light.');
manager.GetPlayer = saved_player;

-- At most four times a second, into the same tables, and asking the game once per spell, whatever a draw looks up.
job(3, 75);
local kept_near, kept_far = sets();
P.reads, P.asked = 0, 0;
job(1, 75);
local later_near, later_far = dispel.cleansable(now + 0.2);
assert(P.reads == 0 and P.asked == 0 and later_near == kept_near and later_far == kept_far and later_near[3], 'Within a quarter second the answer stands.');
later_near = dispel.cleansable(now + 0.25);
assert(P.reads == 1 and later_near == kept_near and not later_near[3], 'After it the client is read again, into the same table.');
now = now + 0.25;
job(3, 75);
P.reads, P.asked = 0, 0;
for at = 1, 100 do dispel.cleansable(now + 1 + at / 1000); end;
assert(P.reads == 1 and P.asked == 8, 'A hundred frames in a quarter second read the client once and ask about each spell once: ' .. P.asked);
assert(dispel.cleansable(now - 50)[3] and P.reads == 2, 'A clock that goes back reads again.');
now = now + 2;
-- KB each call of step makes, with the JIT off as its traces count as memory.
local function made_by(count, step)
    jit.off(); jit.flush();
    for _ = 1, 60 do step(); end;
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    local before = collectgarbage('count');
    for _ = 1, count do step(); end;
    local each = (collectgarbage('count') - before) / count;
    collectgarbage('restart');
    jit.on();
    return each;
end;
-- Refilling the sets makes nothing, and nor does a look at them.
local each = made_by(600, function() now = now + 1; dispel.cleansable(now); end);
assert(each < 0.002, ('Refilling the sets makes %.4f KB a time'):format(each));
each = made_by(600, function() dispel.cleansable(now, true); end);
assert(each < 0.002, ('The sample sets make %.4f KB a time'):format(each));

-- Samples light whatever your job, with the same reach.
job(1, 75);
near, far = dispel.cleansable(now, true);
assert(lit_spells(near) == '14 15 16 17 18 19 20 143' and lit_spells(far) == '14 15 16 17 18 19 20', 'Samples light for a WAR.');
local real = sets();
assert(lit_spells(real) == '', 'And a sample leaves the real sets alone.');
-- _reset clears what was worked out, so the next call reads the client.
job(3, 75);
real = sets();
dispel._reset();
assert(lit_spells(real) == '', 'The sets are empty after a reset.');
P.reads = 0;
dispel.cleansable(now);
assert(P.reads == 1 and lit_spells(real) ~= '', 'And the next call reads the client, at the same moment.');

-- Over heads, with a plan of one unit of each kind. Each carries Poison (Poisona), Slow (Erase only), a buff and an
-- effect with no removal.
local draw = require('ui.overhead_icons');
local calls = {};
local list = setmetatable({}, { __index = function(_, name)
    return function(_, ...) calls[#calls + 1] = MOCK.copy_arguments(name, ...); end;
end });
rawset(imgui, 'GetBackgroundDrawList', function() return list; end);
rawset(imgui, 'GetForegroundDrawList', function() return list; end);
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);
local KINDS = { 'mob', 'party', 'alliance', 'other', 'pet', 'other_pet', 'self' };
local units, order, subjects = {}, {}, {};
local function row(id, kind, at, mine)
    return { effect = id, kind = kind, name = 'Effect ' .. id, present = true, status = 'server', priority = 0, remaining = 300,
        first_seen = at, first_sequence = at, key = 'k' .. at, mine = mine, domain = 'status' };
end;
for index, kind in ipairs(KINDS) do
    units[index] = { id = index, index = index, kind = kind, target = false, subtarget = false, player = kind ~= 'mob', name = 'Unit' .. index,
        race = 0, hitbox = 0, size = 24, alpha = 1, x = 0, y = 0, anchor_x = index * 200, anchor_y = 300, depth = 10, distance = 10, ppy = 0, name_px = 0, arrow_px = 0 };
    order[index] = index;
    subjects[index] = { effects = { row(33, 'buff', 1, true), row(3, 'debuff', 2), row(13, 'debuff', 3), row(4, 'debuff', 4), row(99, 'debuff', 5), row(42, 'buff', 6) } };
end;
local plan = { valid = true, count = #units, units = units, order = order, ui = 1, above = true };
local function settings()
    local s = defaults.tidy(defaults.make());
    s.overhead.enabled = true;
    for _, kind in ipairs(KINDS) do
        local t = s.overhead.types[kind];
        t.kinds, t.buffs_mine_only, t.debuffs_party_only, t.layout, t.limit = 'all', false, false, 'single', 32;
    end;
    return s;
end;
local function overhead_draw(s, sample)
    calls = {};
    now = now + 1;
    return draw.draw(plan, subjects, s, now, nil, nil, sample);
end;
-- What one unit shows, in order, and which of those are lit.
local function shown(index)
    local slot = draw._slots[index];
    local ids, lit = {}, {};
    for n = 1, slot.count do
        ids[n] = slot.effect[n].effect;
        if slot.lit[n] then lit[#lit + 1] = slot.effect[n].effect; end;
    end;
    table.sort(lit);
    return table.concat(ids, ' '), table.concat(lit, ' ');
end;
local function index_of(kind) for index, name in ipairs(KINDS) do if name == kind then return index; end; end; end;
local s = settings();
for _, kind in ipairs({ 'party', 'alliance', 'self' }) do assert(s.overhead.types[kind].cleanse_light == true, kind .. ' lights at first.'); end;
for _, kind in ipairs({ 'mob', 'other', 'pet', 'other_pet' }) do assert(s.overhead.types[kind].cleanse_light == nil, kind .. ' has no key.'); end;

-- A White Mage: Poison, Slow and Paralysis on you and the party, Poison and Paralysis on the alliance, and nothing on
-- mobs, other players or pets. The buffs and the debuff no spell takes off never light.
job(3, 75);
overhead_draw(s);
local order_lit = {};
for _, kind in ipairs(KINDS) do local ids = shown(index_of(kind)); order_lit[kind] = ids; end;
for kind, want in pairs({ party = '3 4 13', self = '3 4 13', alliance = '3 4', mob = '', other = '', pet = '', other_pet = '' }) do
    local _, lit = shown(index_of(kind));
    assert(lit == want, kind .. ' lights ' .. want .. ', not ' .. lit);
end;
-- It draws in the shared glow and color: a border and a glow for each lit icon.
local function count_of(name, ink)
    local out = 0;
    for _, call in ipairs(calls) do if call[1] == name and call[4] == ink then out = out + 1; end; end;
    return out;
end;
local color = s.overhead.dispel_color;
local edge, glow = theme.u32(color, 1), theme.u32({ color[1], color[2], color[3], color[4] * 0.35 }, 1);
assert(count_of('AddRect', edge) == 8 and count_of('AddRectFilled', glow) == 8, 'Eight lit icons, each with a border and a glow.');
s.overhead.dispel_glow = false;
overhead_draw(s);
assert(count_of('AddRect', edge) == 8 and count_of('AddRectFilled', glow) == 0, 'The shared glow switch goes for debuffs too, and the border stays.');
s.overhead.dispel_glow = true;
s.overhead.dispel_color = { 0.2, 0.9, 1, 1 };
overhead_draw(s);
assert(count_of('AddRect', theme.u32({ 0.2, 0.9, 1, 1 }, 1)) == 8, 'The shared color goes for debuffs too.');
s = settings();
-- Saved dispel_light stays Mobs only: off, the debuffs still light.
s.overhead.dispel_light = false;
overhead_draw(s);
local _, lit_party = shown(index_of('party'));
assert(lit_party == '3 4 13', 'The mobs\' switch leaves the debuffs lit.');
s = settings();
-- A /WHM can't reach Stona, and a level 1 WHM reaches nothing.
subjects[index_of('party')].effects[#subjects[index_of('party')].effects + 1] = row(7, 'debuff', 7);
job(1, 75, 3, 37);
overhead_draw(s);
_, lit_party = shown(index_of('party'));
assert(lit_party == '3 4 13', 'A /WHM doesn\'t light Petrification.');
job(3, 75);
overhead_draw(s);
_, lit_party = shown(index_of('party'));
assert(lit_party == '3 4 7 13', 'A WHM does.');
table.remove(subjects[index_of('party')].effects);
job(1, 75);
overhead_draw(s);
for _, kind in ipairs(KINDS) do local _, lit = shown(index_of(kind)); assert(lit == '', 'A WAR lights nothing on ' .. kind); end;
-- The light never changes the order, or what a limit leaves out.
job(3, 75);
for _, layout in ipairs({ 'single', 'lines', 'split' }) do
    for _, limit in ipairs({ 32, 2 }) do
        for _, kind in ipairs({ 'party', 'alliance', 'self' }) do
            local t = s.overhead.types[kind];
            t.layout, t.limit, t.line_debuffs, t.line_buffs, t.split_debuffs, t.split_buffs = layout, limit, limit, limit, limit, limit;
            t.cleanse_light = true;
            overhead_draw(s);
            local lit_ids = shown(index_of(kind));
            t.cleanse_light = false;
            overhead_draw(s);
            local plain, none = shown(index_of(kind));
            assert(lit_ids == plain and none == '', kind .. ' in ' .. layout .. ' keeps its order: ' .. lit_ids .. ' and ' .. plain);
        end;
    end;
end;
-- Each type's switch is its own.
s = settings();
s.overhead.types.party.cleanse_light = false;
overhead_draw(s);
local _, lit_self = shown(index_of('self'));
_, lit_party = shown(index_of('party'));
assert(lit_party == '' and lit_self == '3 4 13', 'Party off, You on.');
-- Mobs: a debuff never lights, and for a RDM with Dispel the buffs do.
s = settings();
job(5, 75);
P.spells[260] = true;
dispel._reset();
overhead_draw(s);
local _, lit_mob = shown(index_of('mob'));
assert(lit_mob == '33 42', 'On a mob only the buffs light: ' .. lit_mob);
P.spells[260] = nil;
-- Lit icons make no more in a frame than the same icons unlit.
local quiet = setmetatable({}, { __index = function(owner, name)
    local nothing = function() end;
    rawset(owner, name, nothing);
    return nothing;
end });
rawset(imgui, 'GetBackgroundDrawList', function() return quiet; end);
job(3, 75);
local function overhead_frame() now = now + 0.02; MOCK.imgui_calls = {}; draw.draw(plan, subjects, s, now, nil, nil); end;
local lit_frame = made_by(300, overhead_frame);
for _, kind in ipairs({ 'party', 'alliance', 'self' }) do s.overhead.types[kind].cleanse_light = false; end;
local plain_frame = made_by(300, overhead_frame);
for _, kind in ipairs({ 'party', 'alliance', 'self' }) do s.overhead.types[kind].cleanse_light = true; end;
assert(lit_frame - plain_frame < 0.002, ('The light adds %.4f KB to a frame'):format(lit_frame - plain_frame));
rawset(imgui, 'GetBackgroundDrawList', function() return list; end);
-- A sample lights whatever your job, by the same reach.
job(1, 75);
overhead_draw(s, true);
local _, sample_party = shown(index_of('party'));
local _, sample_alliance = shown(index_of('alliance'));
assert(sample_party == '3 4 13' and sample_alliance == '3 4', 'A sample lights for a WAR: ' .. sample_party .. ' and ' .. sample_alliance);

-- Each overhead sample that can show a light has a debuff that lights, and the alliance's isn't one only Erase takes.
local preview = require('ui.overhead_preview');
local overhead = require('core.overhead');
local sample_at = overhead.sample;
overhead.sample = function(unit, _, _, shown_kind)
    unit.kind, unit.size = shown_kind, 24;
    return true;
end;
local one = draw._slots[1];
for kind, want in pairs({ party = '3 13', self = '3 13', alliance = '3' }) do
    s = settings();
    s.overhead.preview = true;
    preview.show(kind);
    assert(preview.draw(s, {}, now) > 0, 'Fixture: the sample draws on ' .. kind);
    local got = {};
    for n = 1, one.count do if one.lit[n] then got[#got + 1] = one.effect[n].effect; end; end;
    table.sort(got);
    assert(table.concat(got, ' ') == want, kind .. '\'s sample lights ' .. want .. ', not ' .. table.concat(got, ' '));
end;
overhead.sample = sample_at;
preview.show('mob');

-- The panels: self debuffs and party, off at first, in icons and bars.
local hud = require('ui.hud');
local SELF, ALLY = 1001, 1002;
local function panel_row(effect, kind, entity, scope, key)
    return { key = key, instance = 1, effect = effect, name = 'Effect ' .. effect, kind = kind, group = kind, scope = scope, entity_id = entity,
        entity_name = 'Someone', status = 'estimated', deadline = now + 60, remaining = 60, total = 90, start = now - 30, observed_at = now - 30,
        first_seen = now - 30, present = true };
end;
local function panel_view()
    return { valid = true, context = { valid = true, id = SELF, name = 'Tester', job = 3,
        party = { { id = ALLY, name = 'Ally', scope = 'party', slot = 1, group = 1, valid = true } }, entities = {} }, rows = {
        panel_row(3, 'debuff', SELF, 'self', 'a'), panel_row(13, 'debuff', SELF, 'self', 'b'), panel_row(99, 'debuff', SELF, 'self', 'c'),
        panel_row(33, 'buff', SELF, 'self', 'd'),
        panel_row(4, 'debuff', ALLY, 'party', 'e'), panel_row(13, 'debuff', ALLY, 'party', 'f'), panel_row(99, 'debuff', ALLY, 'party', 'g'),
        panel_row(33, 'buff', ALLY, 'party', 'h'),
    } };
end;
local function panel_settings(on)
    local out = defaults.tidy(defaults.make());
    for _, key in ipairs({ 'self_debuffs', 'party', 'self_buffs' }) do
        out.panels[key].enabled = true;
        if out.panels[key].dispel_light ~= nil then out.panels[key].dispel_light = on; end;
    end;
    return out;
end;
require('ui.icons').status = function(effect) return 'icon:' .. tostring(effect); end;
local function panel_drawn(out, key, view)
    now = now + 1.5;
    MOCK.imgui_calls = {};
    hud.draw(view or panel_view(), out, now, {});
    local p = out.panels[key];
    local ink, soft = theme.u32(p.dispel_color or defaults.dispel_color), theme.u32({ 1, 0.82, 0.25, 0.35 });
    local found, inside = { edges = 0, glows = 0 }, false;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Begin' then inside = call[2] == '##vantage_' .. key;
        elseif call[1] == 'End' then inside = false;
        elseif inside then
            local copy = MOCK.drawn[call];
            if call[1] == 'draw:AddRect' and copy[4] == ink then found.edges = found.edges + 1;
            elseif call[1] == 'draw:AddRectFilled' and copy[4] == soft then found.glows = found.glows + 1; end;
        end;
    end;
    return found;
end;
job(3, 75);
local fresh = defaults.make();
assert(fresh.panels.self_debuffs.dispel_light == false and fresh.panels.party.dispel_light == false, 'The panels start with the light off.');
for _, mode in ipairs({ 'icons', 'bars' }) do
    local out = panel_settings(true);
    out.panels.self_debuffs.mode, out.panels.party.mode = mode, mode;
    -- Poison and Slow on you. Paralysis and Slow on a party row: Erase reaches it. The buff and the rest never light.
    local found = panel_drawn(out, 'self_debuffs');
    assert(found.edges == 2 and found.glows == 2, 'Self debuffs in ' .. mode .. ' lights two rows: ' .. found.edges .. ', ' .. found.glows);
    found = panel_drawn(out, 'party');
    assert(found.edges == 2 and found.glows == 2, 'Party in ' .. mode .. ' lights two rows: ' .. found.edges .. ', ' .. found.glows);
    assert(panel_drawn(out, 'self_buffs').edges == 0, 'Self buffs has no light.');
    out.panels.party.dispel_glow = false;
    found = panel_drawn(out, 'party');
    assert(found.edges == 2 and found.glows == 0, 'The panel\'s glow switch goes for its debuffs.');
    out.panels.party.dispel_color = { 0.2, 0.9, 1, 1 };
    assert(panel_drawn(out, 'party').edges == 2, 'And the panel\'s own color.');
    out = panel_settings(false);
    out.panels.self_debuffs.mode, out.panels.party.mode = mode, mode;
    assert(panel_drawn(out, 'self_debuffs').edges == 0 and panel_drawn(out, 'party').edges == 0, 'Off, nothing lights in ' .. mode);
end;
-- Whoever a row is, a job that can't remove it lights nothing, and a recast row never lights.
local out = panel_settings(true);
job(1, 75);
assert(panel_drawn(out, 'self_debuffs').edges == 0 and panel_drawn(out, 'party').edges == 0, 'A WAR lights nothing on the panels.');
job(1, 75, 3, 37);
local stone = panel_view();
stone.rows[#stone.rows + 1] = panel_row(7, 'debuff', SELF, 'self', 'i');
assert(panel_drawn(out, 'self_debuffs', stone).edges == 2, 'A /WHM doesn\'t light Petrification.');
job(3, 75);
assert(panel_drawn(out, 'self_debuffs', stone).edges == 3, 'A WHM does.');
-- A party panel holds no alliance members, so a row on it can always be reached.
local alliance_view = panel_view();
for _, entry in ipairs(alliance_view.rows) do if entry.scope == 'party' then entry.scope = 'alliance'; end; end;
assert(panel_drawn(out, 'party', alliance_view).edges == 0, 'Alliance rows aren\'t on the party panel.');
-- A sample lights whatever your job, and each panel's sample has a debuff that lights.
job(1, 75);
out = panel_settings(true);
out.preview = true;
local sample_view = hud.sample(now);
for _, key in ipairs({ 'self_debuffs', 'party' }) do
    assert(panel_drawn(out, key, sample_view).edges >= 1, key .. '\'s sample lights for a WAR.');
end;
local spots = {};
for _, entry in ipairs(sample_view.rows) do if entry.kind == 'debuff' and cleansable[entry.effect] then spots[entry.scope] = true; end; end;
assert(spots.self and spots.party, 'The panel samples hold a debuff that lights.');

-- The party list icons: off at first, in the overhead icons' glow and color, and Erase doesn't reach the alliance.
local overlay = require('ui.native_party_hud');
local strip = settings();
assert(strip.party_ui.effects.cleanse_light == false, 'The party list icons start with the light off.');
strip.party_ui.enabled, strip.party_ui.locked, strip.party_ui.include_self = true, true, true;
local roster = { valid = true, id = 1001, zone = 230, members = {} };
local game = { available = true, groups = {} };
local strip_subjects = {};
for i = 1, 12 do
    local group = math.floor((i - 1) / 6) + 1;
    local member = { id = 1000 + i, index = 1023 + i, slot = i - 1, group = group, name = 'Member' .. i, zone = 230, active = true, job = 5, level = 75,
        known = true, available = true };
    roster.members[i] = member;
    strip_subjects[member.id] = { known = true, complete = true, effects = {
        { effect = 3, name = 'Poison', kind = 'debuff', status = 'server', remaining = 60, total = 120, present = true, key = 'p' .. i },
        { effect = 13, name = 'Slow', kind = 'debuff', status = 'server', remaining = 50, total = 120, present = true, key = 's' .. i },
        { effect = 33, name = 'Haste', kind = 'buff', status = 'server', remaining = 40, total = 120, present = true, key = 'h' .. i },
    } };
    game.groups[group] = game.groups[group] or { x = 1300, y = 100 + (group - 1) * 240, width = 200, height = 180, rows = {} };
    game.groups[group].rows[member.slot] = { x = 1300, y = game.groups[group].y + member.slot % 6 * 30, width = 200, height = 30, slot = member.slot };
end;
imgui.GetWindowDrawList = function() return list; end;
local function strips(config_now)
    calls = {};
    now = now + 1;
    overlay.draw(roster, strip_subjects, strip.party_ui, config_now or now, { native_geometry = game, global_style = strip.style, settings = strip });
    local look = strip.overhead.dispel_color;
    local opacity = strip.party_ui.style.opacity;
    local ink = require('ui.party_theme').u32(look, opacity);
    local soft = require('ui.party_theme').u32({ look[1], look[2], look[3], look[4] * 0.35 }, opacity);
    return count_of('AddRect', ink), count_of('AddRectFilled', soft);
end;
job(3, 75);
local edges, glows = strips();
assert(edges == 0 and glows == 0, 'Off, nothing lights.');
strip.party_ui.effects.cleanse_light = true;
edges, glows = strips();
-- The party's six members light Poison and Slow, and the alliance's six only Poison.
assert(edges == 18 and glows == 18, 'Twelve on the party strip and six on the alliance strip: ' .. edges .. ', ' .. glows);
strip.overhead.dispel_glow = false;
edges, glows = strips();
assert(edges == 18 and glows == 0, 'The Overhead page\'s glow switch goes here too.');
strip.overhead.dispel_glow = true;
strip.overhead.dispel_color = { 0.2, 0.9, 1, 1 };
edges, glows = strips();
assert(edges == 18 and glows == 18, 'And its color.');
strip.party_ui.style.opacity = 0.5;
edges = strips();
assert(edges == 18, 'At the party opacity.');
strip.party_ui.style.opacity = 1;
job(1, 75);
edges = strips();
assert(edges == 0, 'A WAR lights nothing.');
job(1, 75, 3, 37);
strip_subjects[1001].effects[1].effect = 7;
edges = strips();
assert(edges == 17, 'A /WHM doesn\'t light Petrification.');
strip_subjects[1001].effects[1].effect = 3;
-- Samples light for any job, and every sample member, alliance ones too, has a debuff that lights there.
job(1, 75);
strip.party_ui.preview = true;
edges = strips();
assert(edges == 12, 'Each of the twelve sample members lights its Paralysis: ' .. edges);
strip.party_ui.preview = false;
local _, samples = require('ui.party_hud').sample(18, now);
for id, subject in pairs(samples) do
    local any = false;
    for _, effect in ipairs(subject.effects) do any = any or cleansable[effect.effect] == 15; end;
    assert(any, 'The sample of member ' .. id .. ' holds a debuff the alliance reach lights.');
end;
-- While off, the strips don't ask what you can remove.
strip.party_ui.effects.cleanse_light = false;
local asked_at = dispel.cleansable;
dispel.cleansable = function() error('The light is off.'); end;
strips();
dispel.cleansable = asked_at;
-- Lit strips make no more in a frame than strips with it off.
imgui.GetWindowDrawList = function() return quiet; end;
job(3, 75);
local function strip_frame()
    now = now + 0.02;
    MOCK.imgui_calls = {};
    overlay.draw(roster, strip_subjects, strip.party_ui, now, { native_geometry = game, global_style = strip.style, settings = strip });
end;
plain_frame = made_by(200, strip_frame);
strip.party_ui.effects.cleanse_light = true;
lit_frame = made_by(200, strip_frame);
strip.party_ui.effects.cleanse_light = false;
assert(lit_frame - plain_frame < 0.002, ('The light adds %.4f KB to a frame of strips'):format(lit_frame - plain_frame));
imgui.GetWindowDrawList = function() return list; end;
-- And the light adds no cell: what fits, fits the same.
local function images()
    local out = {};
    for _, call in ipairs(calls) do if call[1] == 'AddImage' then out[#out + 1] = call[2]; end; end;
    return table.concat(out, ' ');
end;
job(3, 75);
strips();
local plain = images();
strip.party_ui.effects.cleanse_light = true;
strips();
assert(images() == plain, 'The icons are the same with the light on.');

-- Saved data: a key that isn't there comes in at its default, a saved choice stays, a bad value goes back to the default,
-- and a string or profile without the keys still loads.
local partial = defaults.make();
for _, kind in ipairs({ 'party', 'alliance', 'self' }) do partial.overhead.types[kind].cleanse_light = nil; end;
for _, key in ipairs({ 'self_debuffs', 'party' }) do
    partial.panels[key].dispel_light, partial.panels[key].dispel_glow, partial.panels[key].dispel_color = nil, nil, nil;
end;
partial.party_ui.effects.cleanse_light = nil;
local loaded = defaults.tidy(store.copy(partial));
for _, kind in ipairs({ 'party', 'alliance', 'self' }) do assert(loaded.overhead.types[kind].cleanse_light == true, 'A save without the key lights ' .. kind .. ' at first.'); end;
for _, key in ipairs({ 'self_debuffs', 'party' }) do
    local p = loaded.panels[key];
    assert(p.dispel_light == false and p.dispel_glow == true and p.dispel_color[2] == 0.82, key .. ' gets its light at the defaults.');
end;
assert(loaded.party_ui.effects.cleanse_light == false, 'The party list icons get theirs.');
local saved = defaults.make();
saved.overhead.types.party.cleanse_light, saved.overhead.types.self.cleanse_light = false, 'x';
saved.overhead.types.mob.cleanse_light = true;
saved.panels.party.dispel_light, saved.panels.party.dispel_color = true, { 2, 'x', -1, 0.5 };
saved.party_ui.effects.cleanse_light = true;
loaded = defaults.tidy(saved);
assert(loaded.overhead.types.party.cleanse_light == false and loaded.overhead.types.self.cleanse_light == true, 'A saved choice stays, and a bad value is the default.');
assert(loaded.overhead.types.mob.cleanse_light == nil, 'A type with no light keeps no key.');
assert(loaded.panels.party.dispel_light == true and loaded.party_ui.effects.cleanse_light == true, 'Saved on stays on.');
local c = loaded.panels.party.dispel_color;
assert(c[1] == 1 and c[2] == 0.82 and c[3] == 0 and c[4] == 0.5, 'A bad color is kept in range.');
-- An export without the keys reads, and applying it leaves them at the defaults.
local base = defaults.tidy(defaults.make());
local payload = assert(share.read(assert(share.export(base, 'profile', nil, 'Tester'))));
for _, kind in ipairs({ 'party', 'alliance', 'self' }) do payload.data.overhead.types[kind].cleanse_light = nil; end;
for _, key in ipairs({ 'self_debuffs', 'party' }) do
    local p = payload.data.panels[key];
    p.dispel_light, p.dispel_glow, p.dispel_color = nil, nil, nil;
end;
payload.data.party_ui.effects.cleanse_light = nil;
local body = store.encode(payload);
local read = assert(share.read('VG:1:' .. share.crc32(body) .. ':' .. body), 'A string without the lights reads.');
local applied = assert(share.candidate(base, read, 'replace'));
assert(applied.overhead.types.party.cleanse_light == true and applied.panels.party.dispel_light == false and applied.party_ui.effects.cleanse_light == false,
    'And it lands with the lights at their defaults.');
-- A string that holds them carries them.
local mine = defaults.tidy(defaults.make());
mine.overhead.types.party.cleanse_light, mine.panels.party.dispel_light, mine.party_ui.effects.cleanse_light = false, true, true;
applied = assert(share.candidate(base, assert(share.read(assert(share.export(mine, 'profile', nil, 'Tester')))), 'replace'));
assert(applied.overhead.types.party.cleanse_light == false and applied.panels.party.dispel_light == true and applied.party_ui.effects.cleanse_light == true,
    'A string carries the lights.');
