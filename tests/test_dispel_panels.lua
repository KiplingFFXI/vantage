-- The target and watched enemy panels light a mob's buff you can take off right now, as the overhead icons do, with
-- the same checks (core/dispel.lua) and the same list (data/dispelable.lua): a glow behind the icon when asked for and
-- a bright border, in the panel's own light color, in icon and bar layouts. Debuffs, players' buffs and the panels with
-- no light never light, a job that can't take it off lights nothing, and each panel's switch turns its light off. The
-- settings load at their defaults from a save without them and tidy keeps what was saved.
local defaults, hud, theme = require('ui.defaults'), require('ui.hud'), require('ui.theme');
local dispel = require('core.dispel');
require('ui.icons').status = function(effect) return 'icon:' .. tostring(effect); end;
local P = { main = 5, main_level = 75, spells = { [260] = true } };
local player = {
    GetMainJob = function() return P.main; end, GetMainJobLevel = function() return P.main_level; end,
    GetSubJob = function() return 0; end, GetSubJobLevel = function() return 0; end,
    HasSpell = function(_, id) return P.spells[id] == true; end,
};
AshitaCore.GetMemoryManager = function() return { GetPlayer = function() return player; end }; end;
local MOB, PLAYER, SELF = 0x1000123, 1003, 1001;
-- The light color a panel starts with, the overhead icons' own.
local LIGHT = { 1, 0.82, 0.25, 1 };
local now = 100;
local function row(effect, kind, entity, scope, key)
    return { key = key, instance = 1, effect = effect, name = 'Effect ' .. effect, kind = kind, group = kind, scope = scope,
        entity_id = entity, entity_name = entity == MOB and 'Goblin' or 'Someone', status = 'estimated', deadline = now + 60,
        remaining = 60, total = 90, start = now - 30, observed_at = now - 30, first_seen = now - 30 };
end;
-- On the mob: Protect and Haste (dispelable), Reraise (not), Paralysis (a debuff). On a player you target: Protect.
local function view(target)
    local rows = {
        row(40, 'buff', MOB, 'enemy', 'a'), row(33, 'buff', MOB, 'enemy', 'b'), row(113, 'buff', MOB, 'enemy', 'c'),
        row(4, 'debuff', MOB, 'enemy', 'd'), row(40, 'buff', PLAYER, 'other', 'e'), row(43, 'buff', SELF, 'self', 'f'),
    };
    return { valid = true, rows = rows, context = { valid = true, id = SELF, name = 'Tester', job = 5,
        target = { id = target or MOB, name = 'Goblin', kind = target == PLAYER and 'player' or 'monster' },
        entities = { [MOB] = { id = MOB, name = 'Goblin', kind = 'monster' } } } };
end;
local function settings()
    local s = defaults.tidy(defaults.make());
    s.panels.target.enabled, s.panels.watch.enabled, s.panels.self_buffs.enabled = true, true, true;
    -- The light is off at first, so the checks of what it lights turn it on.
    s.panels.target.dispel_light, s.panels.watch.dispel_light = true, true;
    s.watch_ids = { MOB };
    return s;
end;
-- What one panel's window drew: its images, and the rects in its light color, filled (glow) and outlined (border).
local function drawn(s, v, key)
    now = now + 1.5;
    MOCK.imgui_calls = {};
    hud.draw(v, s, now, {});
    local p = s.panels[key];
    local color = p.dispel_color or LIGHT;
    local edge = theme.u32(color);
    local glow = theme.u32({ color[1], color[2], color[3], color[4] * 0.35 });
    local out, inside = { images = {}, glows = {}, edges = {} }, false;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Begin' then inside = call[2] == '##vantage_' .. key;
        elseif call[1] == 'End' then inside = false;
        elseif inside then
            local copy = MOCK.drawn[call];
            if call[1] == 'draw:AddImage' then out.images[#out.images + 1] = copy;
            elseif call[1] == 'draw:AddRectFilled' and copy[4] == glow then out.glows[#out.glows + 1] = copy;
            elseif call[1] == 'draw:AddRect' and copy[4] == edge then out.edges[#out.edges + 1] = copy; end;
        end;
    end;
    return out;
end;
-- An icon's corners: AddImage(texture, min, max, ...).
local function image(out, effect)
    for _, copy in ipairs(out.images) do if copy[2] == 'icon:' .. effect then return { copy[3], copy[4] }; end end;
end;

-- A RDM 75 with Dispel: the target panel, in icons, lights Protect and Haste, and nothing else.
local s = settings();
assert(s.panels.target.mode == 'icons' and s.panels.watch.mode == 'bars', 'Fixture: the target panel starts as icons, watch as bars.');
local out = drawn(s, view(), 'target');
assert(#out.glows == 2 and #out.edges == 2, 'Two lit buffs, each with a glow and a border: ' .. #out.glows .. ', ' .. #out.edges);
local protect, haste = image(out, 40), image(out, 33);
assert(protect and haste and image(out, 113) and image(out, 4), 'Fixture: the panel draws every effect.');
local lit = { [40] = false, [33] = false };
for effect in pairs(lit) do
    local picture = image(out, effect);
    for index = 1, 2 do
        local glow, edge = out.glows[index], out.edges[index];
        if glow[2][1] < picture[1][1] and glow[3][1] > picture[2][1] and edge[2][1] <= picture[1][1] and edge[3][1] >= picture[2][1]
            and glow[2][2] < picture[1][2] and edge[2][2] <= picture[1][2] then lit[effect] = true; end;
    end;
end;
assert(lit[40] and lit[33], 'The glow and the border sit around the lit icons.');
-- The glow goes behind the icon, the border over it.
local order = {};
for index, call in ipairs(MOCK.imgui_calls) do
    local copy = MOCK.drawn[call];
    if copy and copy[2] == 'icon:40' then order.image = index; end;
    if copy and call[1] == 'draw:AddRectFilled' and copy[2][1] < protect[1][1] and copy[3][1] > protect[2][1] and copy[2][2] < protect[1][2] then order.glow = order.glow or index; end;
end;
assert(order.glow and order.image and order.glow < order.image, 'The glow is drawn before the icon.');

-- The watch panel, as bars with icons, lights its icons; with no icons, its bars.
out = drawn(s, view(), 'watch');
assert(#out.glows == 2 and #out.edges == 2, 'Watched enemies in bars light two buffs: ' .. #out.glows .. ', ' .. #out.edges);
s.panels.watch.show_icon = false;
out = drawn(s, view(), 'watch');
assert(#out.glows == 0 and #out.edges == 2 and #out.images == 0, 'With no icons the bar gets the border.');
assert(out.edges[1][3][1] - out.edges[1][2][1] > 100, 'The border spans the bar.');
s.panels.watch.show_icon = true;

-- No glow when the panel asks for none, its own color, and its switch.
s.panels.target.dispel_glow = false;
out = drawn(s, view(), 'target');
assert(#out.glows == 0 and #out.edges == 2, 'Glow off leaves the borders.');
s.panels.target.dispel_color = { 0.2, 0.9, 1, 1 };
out = drawn(s, view(), 'target');
assert(#out.edges == 2, 'The border takes the panel\'s own light color.');
assert(#drawn(s, view(), 'watch').edges == 2, 'The other panel keeps its own color.');
s.panels.target.dispel_light = false;
out = drawn(s, view(), 'target');
assert(#out.glows == 0 and #out.edges == 0, 'The switch turns the target panel\'s light off.');
assert(#drawn(s, view(), 'watch').edges == 2, 'The watch panel has its own switch.');

-- A player you target: their buffs never light. Nor do your own buffs on the self panel.
s = settings();
out = drawn(s, view(PLAYER), 'target');
assert(#out.edges == 0 and image(out, 40), 'A player\'s Protect does not light.');
local own = drawn(s, view(), 'self_buffs');
assert(#own.edges == 0 and #own.glows == 0, 'The self buffs panel never lights.');

-- A job that can't take it off lights nothing: a WAR, a RDM without Dispel, a RDM under 32, a /RDM sub under 32.
for _, case in ipairs({ { 1, 75, { [260] = true } }, { 5, 75, {} }, { 5, 31, { [260] = true } } }) do
    P.main, P.main_level, P.spells = case[1], case[2], case[3];
    assert(#drawn(s, view(), 'target').edges == 0, 'Nothing lights for job ' .. case[1] .. ' at ' .. case[2] .. '.');
end;
P.main, P.main_level, P.spells = 5, 75, { [260] = true };
assert(#drawn(s, view(), 'target').edges == 2, 'Back to a RDM with Dispel.');

-- Settings: fresh defaults off with the glow on, a save without the light loads with it off, tidy keeps a saved
-- choice and turns a bad color back to its default; only the target, watch, self debuffs and party panels have it.
local fresh = defaults.make();
for _, key in ipairs({ 'target', 'watch', 'self_debuffs', 'party' }) do
    assert(fresh.panels[key].dispel_light == false and fresh.panels[key].dispel_glow == true, key .. ' starts with the light off and its glow on.');
    assert(fresh.panels[key].dispel_color[1] == 1 and fresh.panels[key].dispel_color[2] == 0.82, key .. ' starts with the overhead light color.');
end;
assert(fresh.panels.self_buffs.dispel_light == nil and fresh.panels.spell_recasts.dispel_light == nil, 'The other panels have no light.');
local old = defaults.make();
old.panels.target.dispel_light, old.panels.target.dispel_glow, old.panels.target.dispel_color = nil, nil, nil;
local loaded = defaults.tidy(old);
assert(loaded.panels.target.dispel_light == false and loaded.panels.target.dispel_color[3] == 0.25, 'A save without the light gets its defaults.');
local saved = defaults.make();
saved.panels.watch.dispel_light, saved.panels.watch.dispel_glow = false, false;
saved.panels.watch.dispel_color = { 2, 'x', -1, 0.5 };
-- Off is the default, so a light saved on shows a saved choice staying too.
saved.panels.target.dispel_light = true;
loaded = defaults.tidy(saved);
assert(loaded.panels.watch.dispel_light == false and loaded.panels.watch.dispel_glow == false, 'A saved choice stays.');
assert(loaded.panels.target.dispel_light == true, 'A light saved on stays on.');
local c = loaded.panels.watch.dispel_color;
assert(c[1] == 1 and c[2] == 0.82 and c[3] == 0 and c[4] == 0.5, 'A color is clamped, a bad part takes the default.');
assert(dispel.buffs[40] and dispel.buffs[33] and not dispel.buffs[113], 'Fixture: the shared list.');
return 'The target and watched enemy panels light the mob buffs you can take off now, as overhead';
