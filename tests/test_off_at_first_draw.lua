-- The ready pulse, the recast tints, the party cooldown watch and the panels' buff light are off at first, and then
-- nothing of theirs draws. Through the real draws (ui/hud.lua with ui/ready_pulse.lua, and the party list strips in
-- ui/native_party_hud.lua), fresh settings with the combined recast panel, the Target and Watched enemies panels and
-- the strips shown draw no pulse, no tint or lock, no cooldown cell and no lit buff, though each has what it needs:
-- a long recast's ready and a pulse playing, rows marked Silenced and short of MP, a member's estimates, and a RDM
-- with Dispel facing a mob's Protect and Haste. Sample displays draw none of them either, and their hover and copied
-- details name no tint; the refresh doesn't look through your status list for the tints. Turned on, each draws, so
-- the scene can show it.
local defaults, hud, theme = require('ui.defaults'), require('ui.hud'), require('ui.theme');
local pulse, tints, cooldowns = require('core.ready_pulse'), require('core.recast_tints'), require('core.party_cooldowns');
local imgui = require('imgui');
require('ui.icons').status = function(effect) return 'icon:' .. tostring(effect); end;
local resources = { [57] = { ManaCost = 40 } };
AshitaCore.GetResourceManager = function() return { GetSpellById = function(_, id) return resources[id]; end }; end;
-- A RDM 75 with Dispel learned can take a mob's Protect and Haste off now (core/dispel.lua).
local player = AshitaCore:GetMemoryManager():GetPlayer();
MOCK.player.main_job, MOCK.player.main_level, MOCK.player.sub_job, MOCK.player.sub_level = 5, 75, 0, 0;
player.HasSpell = function(_, id) return id == 260; end;
local MOB, SELF = 0x1000123, 1001;
local now = 100;
local function fresh()
    local s = defaults.tidy(defaults.make());
    -- The displays that show them: none of the four.
    for _, panel in pairs(s.panels) do panel.enabled = false; end;
    s.panels.target.enabled, s.panels.watch.enabled = true, true;
    s.recast_display, s.panels.recasts.enabled, s.panels.recasts.mode = 'combined', true, 'bars';
    s.watch_ids = { MOB };
    return s;
end;
local function draw(view, s, callbacks)
    now = now + 1.5;
    MOCK.imgui_calls = {};
    hud.draw(view, s, now, callbacks or {});
end;

-- What each panel window drew: rects in a color, and whether the pulse window was begun.
local function rects(window, kind, color)
    local count, inside = 0, false;
    local wanted = theme.u32(color);
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Begin' then inside = call[2] == window;
        elseif call[1] == 'End' then inside = false;
        elseif inside and call[1] == kind and MOCK.drawn[call] and MOCK.drawn[call][4] == wanted then count = count + 1; end;
    end;
    return count;
end;
local function pulse_window()
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Begin' and call[2] == '##vantage_pulse' then return true; end; end;
    return false;
end;

-- The mob panels: Protect and Haste on the targeted, watched mob, and a Paralysis.
local function effect(id, kind, key)
    return { key = key, instance = 1, effect = id, name = 'Effect ' .. id, kind = kind, group = kind, scope = 'enemy',
        entity_id = MOB, entity_name = 'Goblin', status = 'estimated', deadline = now + 60, remaining = 60, total = 90,
        start = now - 30, observed_at = now - 30, first_seen = now - 30 };
end;
local function mob_view()
    return { valid = true, rows = { effect(40, 'buff', 'a'), effect(33, 'buff', 'b'), effect(4, 'debuff', 'c') },
        context = { valid = true, id = SELF, name = 'Tester', job = 5, target = { id = MOB, name = 'Goblin', kind = 'monster' },
            entities = { [MOB] = { id = MOB, name = 'Goblin', kind = 'monster' } } } };
end;
local function lit(s, key)
    local p = s.panels[key];
    local light = p.dispel_color;
    local glow = { light[1], light[2], light[3], light[4] * 0.35 };
    return rects('##vantage_' .. key, 'draw:AddRect', light), rects('##vantage_' .. key, 'draw:AddRectFilled', glow);
end;
local s = fresh();
draw(mob_view(), s);
for _, key in ipairs({ 'target', 'watch' }) do
    local edges, glows = lit(s, key);
    assert(edges == 0 and glows == 0, 'Fresh settings light no buff on ' .. key .. ': ' .. edges .. ' borders, ' .. glows .. ' glows.');
end;
s.panels.target.dispel_light, s.panels.watch.dispel_light = true, true;
draw(mob_view(), s);
for _, key in ipairs({ 'target', 'watch' }) do
    local edges, glows = lit(s, key);
    assert(edges == 2 and glows == 2, 'Turned on, ' .. key .. ' lights Protect and Haste: ' .. edges .. ', ' .. glows);
end;

-- The combined recast panel: Haste while Silenced, and Fire (24 MP) at 10 MP.
local function recast(id, key)
    return { key = key, instance = 1, effect = 10000 + id, recast_id = id, spell_id = id, name = 'Spell ' .. id, kind = 'spell',
        group = 'spell_recasts', domain = 'recast', scope = 'self', entity_id = SELF, entity_name = 'You', present = true,
        status = 'server', deadline = now + 30, remaining = 30, total = 60, start = now - 30, observed_at = now };
end;
local snapshot = { valid = true, id = SELF, zone = 102, mp = 10, self_effects = { { effect = 6, deadline = now + 40 } } };
-- The washes in the tints' colors, and the lock's ink, its color at full opacity.
local function washes(s)
    local config, window = s.recast_tints, '##vantage_recasts';
    return rects(window, 'draw:AddRectFilled', config.mp_color) + rects(window, 'draw:AddRectFilled', config.spell_lock_color),
        rects(window, 'draw:AddRectFilled', { 0.62, 0.62, 0.62, 1 });
end;
s = fresh();
local rows = { recast(57, 'haste'), recast(144, 'fire') };
-- Your own status list, counting each time the refresh looks at it.
local looked = 0;
local counted = setmetatable({ valid = true, id = SELF, zone = 102, mp = 10 }, { __index = function(_, key)
    if key == 'self_effects' then looked = looked + 1; return snapshot.self_effects; end;
end });
tints.mark(rows, counted, s);
assert(not rows[1].locked and not rows[1].tint_mp and not rows[2].locked and not rows[2].tint_mp, 'Fresh settings mark no recast row.');
assert(looked == 0, 'and the refresh doesn\'t look through your status list while the tints are off: ' .. looked);
draw({ valid = true, rows = rows, context = { valid = true, id = SELF } }, s);
local washed, locks = washes(s);
assert(washed == 0 and locks == 0, 'Fresh settings draw no tint and no lock: ' .. washed .. ', ' .. locks);
-- Rows marked as the samples mark theirs draw none either.
rows[1].locked, rows[1].lock_deadline, rows[2].tint_mp = true, now + 40, true;
draw({ valid = true, rows = rows, context = { valid = true, id = SELF } }, s);
washed, locks = washes(s);
assert(washed == 0 and locks == 0, 'Marked rows draw no tint and no lock while the tints are off: ' .. washed .. ', ' .. locks);
-- The timer samples, whose recast rows carry each tint, draw none.
s.preview = true;
draw({ valid = true, rows = {}, context = { valid = true, id = SELF } }, s);
washed, locks = washes(s);
assert(washed == 0 and locks == 0, 'The samples draw no tint and no lock: ' .. washed .. ', ' .. locks);
-- What the samples say of themselves, hovered down the panel and in Copy timer details.
local function told(s)
    local said, inside = {}, false;
    local p = s.panels.recasts;
    p.show_heading, p.locked, p.x, p.y, p.width = false, true, 100, 100, 320;
    for y = 102, 400, 4 do
        MOCK.mouse_x, MOCK.mouse_y = 120, y;
        -- Twice, as a hover shows its tooltip once it has held a moment.
        draw({ valid = true, rows = {}, context = { valid = true, id = SELF } }, s);
        draw({ valid = true, rows = {}, context = { valid = true, id = SELF } }, s);
        for _, call in ipairs(MOCK.imgui_calls) do
            if call[1] == 'BeginTooltip' then inside = true;
            elseif call[1] == 'EndTooltip' then inside = false;
            elseif inside and call[1] == 'TextUnformatted' and type(call[2]) == 'string' then said[#said + 1] = call[2]; end;
        end;
    end;
    MOCK.mouse_x, MOCK.mouse_y = nil, nil;
    said[#said + 1] = hud.copy_text({ valid = true, rows = {}, context = { valid = true, id = SELF } }, s, 'recasts', true, now);
    return table.concat(said, '\n');
end;
local text = told(s);
assert(text:find('Cure IV', 1, true) and not text:find('locked', 1, true) and not text:find('MP is below', 1, true),
    'Their hover and copied details name no tint while the tints are off.');
s.preview = false;
s.recast_tints.mp, s.recast_tints.spell_lock, s.recast_tints.ability_lock = true, true, true;
rows = { recast(57, 'haste'), recast(144, 'fire') };
looked = 0;
tints.mark(rows, counted, s);
assert(looked >= 1, 'Turned on, the refresh looks through your status list.');
draw({ valid = true, rows = rows, context = { valid = true, id = SELF } }, s);
washed, locks = washes(s);
assert(rows[1].locked and rows[2].tint_mp and washed >= 2 and locks >= 1, 'Turned on, the rows tint and lock: ' .. washed .. ', ' .. locks);
s.preview = true;
text = told(s);
assert(text:find('Spells are locked', 1, true) and text:find('Abilities are locked', 1, true) and text:find('Your MP is below its cost.', 1, true),
    'and the samples say so when hovered and copied.');
s.preview = false;

-- The ready pulse: a 180 s recast's ready starts none, a test pulse playing draws nothing, on its row or at the screen
-- spot, and holding Shift shows no spot to drag.
local function ready(row, at)
    local event = {};
    for key, value in pairs(row) do event[key] = value; end;
    event.category, event.kind, event.time, event.remaining = row.kind, 'ready', at, 0;
    return event;
end;
s = fresh();
local long = recast(57, 'long');
long.remaining, long.total = 170, 180;
local watch = pulse.new();
watch:update({ long }, {}, s, 10);
assert(#watch:update({}, { ready(long, 20) }, s, 20) == 0, 'Fresh settings start no pulse.');
local tested = watch:test(s, now);
for _, spot in ipairs({ 'row', 'screen' }) do
    -- Held mid-way through its length at the draw.
    tested.started, s.ready_pulse.spot = now + 1.2, spot;
    draw({ valid = true, rows = {}, context = { valid = true, id = SELF }, pulses = { tested } }, s);
    assert(not pulse_window(), 'A pulse handed to the draw shows nothing while the pulse is off: ' .. spot);
end;
s.ready_pulse.spot, s.ready_pulse.locked = 'screen', false;
MOCK.key_shift = true;
draw({ valid = true, rows = {}, context = { valid = true, id = SELF }, pulses = {} }, s, { shift = true });
MOCK.key_shift = false;
assert(not pulse_window(), 'Unlocked, with Shift held, the spot shows nothing to drag while the pulse is off.');
-- Turned on, at the screen spot, as no panel drew the row.
s.ready_pulse.enabled, s.ready_pulse.spot, s.ready_pulse.locked = true, 'screen', true;
watch = pulse.new();
watch:update({ long }, {}, s, 10);
local playing = watch:update({}, { ready(long, 20) }, s, 20);
assert(#playing == 1, 'Turned on, the ready starts a pulse.');
playing[1].started = now + 1.2;
draw({ valid = true, rows = {}, context = { valid = true, id = SELF }, pulses = playing }, s);
assert(pulse_window(), 'and it draws.');
tested.started, s.ready_pulse.spot = now + 1.2, 'row';
draw({ valid = true, rows = {}, context = { valid = true, id = SELF }, pulses = { tested } }, s);
assert(pulse_window(), 'A test pulse for rows, with no row drawn, plays at the screen spot.');

-- The strips beside the game's party list: a member's use, their estimates handed to the strip, and the samples.
local overlay, party_hud = require('ui.native_party_hud'), require('ui.party_hud');
local p = require('ui.party_defaults').make();
local r, subjects = party_hud.sample(6, 100);
local geometry = { available = true, groups = {} };
local frame = { x = 900, y = 40, width = 116, height = 132, rows = {} };
for _, member in ipairs(r.members) do
    frame.rows[member.slot] = { x = 900, y = 40 + member.slot * 22, width = 116, height = 22, slot = member.slot };
end;
geometry.groups[1] = frame;
p.enabled = true;
local function cells(s, kept)
    MOCK.imgui_calls = {};
    overlay.draw(r, subjects, p, now, { global_style = s.style, native_geometry = geometry, cooldowns = s.party_cooldowns });
    local count = 0;
    for _, item in ipairs(kept and overlay._kept.plans[1].rows or overlay.plan(r, subjects, p, geometry, 1280, 720)[1].rows) do
        if item.cooldown_area then count = count + 1; end;
    end;
    return count;
end;
s = fresh();
local counter = cooldowns.new();
counter:observe({ kind = 'cooldown', entity_id = 1002, ability = 18, entity_name = 'Bramble' }, now);
assert(#counter:refresh(now, s, { { id = 1002, name = 'Bramble' } }) == 0 and counter:of(1002) == nil and next(counter.members) == nil,
    'Fresh settings keep no estimate.');
subjects[1002].cooldowns = counter:of(1002);
assert(cells(s) == 0, 'and the strips draw no cooldown cell.');
local function estimate(ability, left)
    local info = cooldowns.WATCHED[ability];
    return { ability = ability, name = info.name, job = info.job, recast = info.recast, member = 1002, member_name = 'Bramble', deadline = now + left };
end;
subjects[1002].cooldowns = { estimate(18, 600), estimate(74, 900) };
assert(cells(s) == 0, 'Estimates handed to a strip draw no cell while the watch is off.');
p.preview = true;
assert(cells(s, true) == 0, 'The strips\' samples draw no cooldown cell while the watch is off.');
s.party_cooldowns.enabled = true;
assert(cells(s, true) == 5, 'Turned on, the samples draw them.');
p.preview = false;
assert(cells(s) >= 1, 'and so do the estimates handed to the strip.');
return 'Off at first, the pulse, the tints, the party cooldown cells and the panels\' light draw nothing';
