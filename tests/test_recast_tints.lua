-- Recast tints (core/recast_tints.lua, drawn by ui/hud.lua). A spell row tints while your MP is below its cost, the
-- era cost for the spells era SQL changed, unless Manafont is on. Spell rows lock while you are Silenced or Muted,
-- ability rows while Amnesia is on you, and in Salvage under Omerta and Impairment, never in Nyzul Isle. A lock shows
-- its time left when the client gives one and none when it doesn't. Every recast layout draws them under its
-- countdown, a row with no icon keeps its text clear of the lock, each tint has its own switch and color, Sample
-- displays show each one, and saves without them get them at their defaults.
local tints, defaults, hud, theme = require('core.recast_tints'), require('ui.defaults'), require('ui.hud'), require('ui.theme');
local resources = { [57] = { ManaCost = 40 }, [144] = { ManaCost = 7 }, [413] = { ManaCost = 0 } };
AshitaCore.GetResourceManager = function() return { GetSpellById = function(_, id) return resources[id]; end }; end;
local now = 200;

local function row(kind, id, key)
    local effect = (kind == 'spell' and 10000 or kind == 'ability' and 20000 or 30000) + id;
    return { key = key or (kind .. id), instance = 1, effect = effect, recast_id = id, spell_id = kind == 'spell' and id or nil, name = kind .. ' ' .. id,
        kind = kind, group = kind .. '_recasts', domain = 'recast', scope = 'self', entity_id = 1001, entity_name = 'You', present = true,
        status = 'server', deadline = now + 30, remaining = 30, total = 60, start = now - 30, observed_at = now };
end;
local function snapshot(mp, effects, zone)
    return { valid = true, id = 1001, zone = zone or 102, mp = mp, self_effects = effects or {} };
end;
-- The tints are off at first, so these checks of what they mark and draw turn them on.
local function fresh()
    local s = defaults.tidy(defaults.make());
    s.recast_tints.mp, s.recast_tints.spell_lock, s.recast_tints.ability_lock = true, true, true;
    return s;
end;
local function marks(rows, snap, s)
    tints.mark(rows, snap, s or fresh());
    return rows;
end;

-- Costs: the era SQL ones, then the client's ManaCost, kept once read.
tints._forget();
assert(tints.cost(144) == 24 and tints.cost(13) == 200 and tints.cost(215) == 287, 'Era SQL costs: Fire 24, Raise II 200, Flood II 287.');
assert(tints.cost(57) == 40 and tints.cost(413) == 0, 'Other spells cost what the client says.');
resources[57] = nil;
assert(tints.cost(57) == 40, 'A cost once read is kept.');
resources[57] = { ManaCost = 40 };
assert(tints.cost(999) == nil, 'A spell the client has no data for has no cost.');
local count = 0;
for _ in pairs(tints.era_costs) do count = count + 1; end;
assert(count == 58, 'The 54 elemental nukes and four Raise and Reraise spells: ' .. count);

-- MP: Haste (40) tints at 30 MP, era Fire (24, the client says 7) doesn't, nor does a song, an ability or an item.
local function spells_and_more() return { row('spell', 57), row('spell', 144), row('spell', 413), row('ability', 11), row('item', 15840) }; end;
local rows = marks(spells_and_more(), snapshot(30));
assert(rows[1].tint_mp and not rows[2].tint_mp and not rows[3].tint_mp and not rows[4].tint_mp and not rows[5].tint_mp,
    'Only the spell whose cost is above your MP tints.');
rows = marks(spells_and_more(), snapshot(20));
assert(rows[1].tint_mp and rows[2].tint_mp, 'At 20 MP, era Fire (24) tints too, though the client says it costs 7.');
rows = marks(spells_and_more(), snapshot(40));
assert(not rows[1].tint_mp, 'MP equal to the cost is enough.');
rows = marks(spells_and_more(), snapshot(10, { { effect = 47, deadline = now + 60 } }));
assert(not rows[1].tint_mp and not rows[2].tint_mp, 'Manafont stops the MP tint.');
rows = marks(spells_and_more(), snapshot(nil));
assert(not rows[1].tint_mp, 'With no MP read, nothing tints.');

-- Locks, with the lock's time left from your own status timers.
rows = marks(spells_and_more(), snapshot(500, { { effect = 6, deadline = now + 12 } }));
assert(rows[1].locked and rows[1].lock_deadline == now + 12 and rows[2].locked and rows[3].locked,
    'Silence locks every spell row, with its end.');
assert(not rows[4].locked and not rows[5].locked, 'Silence locks no ability or item row.');
rows = marks(spells_and_more(), snapshot(500, { { effect = 29, deadline = now + 40 }, { effect = 6, deadline = now + 12 } }));
assert(rows[1].locked and rows[1].lock_deadline == now + 40, 'Silence and Mute lock until the later one ends.');
rows = marks(spells_and_more(), snapshot(500, { { effect = 29 }, { effect = 6, deadline = now + 12 } }));
assert(rows[1].locked and rows[1].lock_deadline == nil, 'A lock whose end isn\'t known has no time.');
rows = marks(spells_and_more(), snapshot(500, { { effect = 16, deadline = now + 9 } }));
assert(rows[4].locked and rows[4].lock_deadline == now + 9 and not rows[1].locked and not rows[5].locked,
    'Amnesia locks ability rows only.');
rows = marks(spells_and_more(), snapshot(500, { { effect = 262, deadline = now + 5000 }, { effect = 261, deadline = now + 5000 } }, 73));
assert(rows[1].locked and rows[4].locked, 'In Salvage, Omerta locks spells and Impairment abilities.');
rows = marks(spells_and_more(), snapshot(500, { { effect = 262, deadline = now + 5000 }, { effect = 261, deadline = now + 5000 } }, 77));
assert(not rows[1].locked and not rows[4].locked, 'In Nyzul Isle, where the client isn\'t told what they stop, they lock nothing.');

-- Each tint has its own switch.
local s = fresh();
s.recast_tints.mp, s.recast_tints.spell_lock, s.recast_tints.ability_lock = false, false, false;
rows = marks(spells_and_more(), snapshot(1, { { effect = 6, deadline = now + 9 }, { effect = 16, deadline = now + 9 } }), s);
for _, value in ipairs(rows) do assert(not value.tint_mp and not value.locked, 'A tint turned off marks nothing.'); end;
s.recast_tints.ability_lock = true;
rows = marks(spells_and_more(), snapshot(1, { { effect = 6, deadline = now + 9 }, { effect = 16, deadline = now + 9 } }), s);
assert(rows[4].locked and not rows[1].locked and not rows[1].tint_mp, 'Each switch works alone.');

-- Settings: a save without them gets the tints at their defaults; colors are kept within range and saved keys stay.
local old = defaults.tidy({ style = {}, panels = {} });
assert(old.recast_tints.mp == false and old.recast_tints.spell_lock == false and old.recast_tints.ability_lock == false,
    'A save without them gets every tint off, as a fresh one does.');
local saved = tints.tidy({ mp = false, mp_color = { 2, -1, 0.5 }, extra = 3 });
assert(saved.mp == false and saved.mp_color[1] == 1 and saved.mp_color[2] == 0 and saved.mp_color[3] == 0.5 and saved.mp_color[4] == 0.45
    and saved.extra == 3, 'Tidy keeps choices, clamps colors and keeps keys it doesn\'t know.');

-- Drawing: the combined recast panel in every layout, a locked Haste and a short-of-MP Fire.
require('ui.icons').status = function() return nil; end;
local view = { valid = true, rows = { row('spell', 57, 'a'), row('spell', 144, 'b') }, context = { valid = true, id = 1001 } };
view.rows[1].locked, view.rows[1].lock_deadline = true, now + 12;
view.rows[2].tint_mp, view.rows[2].deadline, view.rows[2].remaining = true, now + 45, 45;
local function draw(mode, settings)
    settings = settings or fresh();
    for _, panel in pairs(settings.panels) do panel.enabled = false; end;
    local p = settings.panels.recasts;
    settings.recast_display, p.enabled, p.mode = 'combined', true, mode;
    MOCK.imgui_calls = {};
    hud.draw(view, settings, now, {});
    local out = { washes = {}, texts = {}, lock = nil, countdowns = {} };
    local lock_ink = theme.u32({ 0.62, 0.62, 0.62, 1 });
    for index, call in ipairs(MOCK.imgui_calls) do
        local copy = MOCK.drawn[call];
        if copy and copy[1] == 'draw:AddRectFilled' then
            if copy[4] == theme.u32(settings.recast_tints.spell_lock_color) then out.washes[#out.washes + 1] = { 'lock', index, copy };
            elseif copy[4] == theme.u32(settings.recast_tints.mp_color) then out.washes[#out.washes + 1] = { 'mp', index, copy };
            elseif copy[4] == lock_ink and not out.lock then out.lock = { index, copy }; end;
        elseif copy and copy[1] == 'draw:AddText' then out.texts[#out.texts + 1] = { index, copy[#copy], copy[4] }; end;
    end;
    return out;
end;
local function first_text(out, value)
    for _, entry in ipairs(out.texts) do if entry[2] == value then return entry; end end;
end;
for _, mode in ipairs({ 'bars', 'expanded', 'icons', 'text' }) do
    local out = draw(mode);
    local locked, short = 0, 0;
    for _, wash in ipairs(out.washes) do if wash[1] == 'lock' then locked = locked + 1; else short = short + 1; end; end;
    assert(locked >= 1 and short >= 1, mode .. ': the locked row washes grey and the short one blue: ' .. locked .. ', ' .. short);
    assert(out.lock, mode .. ': the locked row draws its lock.');
    local lock_time = first_text(out, '12s');
    assert(lock_time, mode .. ': the lock shows its time left.');
    local clock = hud.timer_text(view.rows[1], now, 'auto');
    local countdown, later = first_text(out, clock), first_text(out, hud.timer_text(view.rows[2], now, 'auto'));
    assert(countdown and later, mode .. ': the countdowns are still drawn: ' .. clock);
    for _, wash in ipairs(out.washes) do
        assert(wash[2] < (wash[1] == 'lock' and countdown or later)[1], mode .. ': each wash goes under the countdown of its row.');
    end;
    if mode == 'text' then
        assert(lock_time[3][1] < countdown[3][1], 'Text only: the lock goes beside the countdown, before it.');
    end;
end;
-- A tint turned off draws nothing, and its color is its own.
local s = fresh();
s.recast_tints.spell_lock, s.recast_tints.mp_color = false, { 1, 0, 0, 0.5 };
local out = draw('bars', s);
local locked, short = 0, 0;
for _, wash in ipairs(out.washes) do if wash[1] == 'lock' then locked = locked + 1; else short = short + 1; end; end;
assert(locked == 0 and short >= 1 and not first_text(out, '12s'), 'With the spell lock off only the MP tint draws, in its own color.');
-- With no icon the lock goes just before the countdown, and the text before it stops short of the lock, however long
-- the spell's name: text only, and compact bars with the icon off.
view.rows[1].name = 'A spell name long enough to run on under the lock';
for _, case in ipairs({ { 'text' }, { 'bars', false } }) do
    local s = fresh();
    if case[2] == false then s.panels.recasts.show_icon = false; end;
    out = draw(case[1], s);
    assert(out.lock, case[1] .. ': the locked row draws its lock.');
    local lock_x, clip, named = out.lock[2][2][1], nil, false;
    for _, call in ipairs(MOCK.imgui_calls) do
        local copy = MOCK.drawn[call];
        if copy and copy[1] == 'draw:PushClipRect' then clip = copy[3][1];
        elseif copy and copy[1] == 'draw:AddText' and tostring(copy[#copy]):find('^A spell name') then
            named = true;
            assert(clip and clip <= lock_x + 0.5, case[1] .. ': the name stops short of the lock: ' .. tostring(clip) .. ' past ' .. lock_x);
        end;
    end;
    assert(named, case[1] .. ': the name is drawn.');
    assert(first_text(out, '12s') and first_text(out, hud.timer_text(view.rows[1], now, 'auto')), case[1] .. ': the lock time and countdown still show.');
end;
view.rows[1].name = 'spell 57';
-- A lock with no known end shows no time.
view.rows[1].lock_deadline = nil;
out = draw('icons');
assert(out.lock and not first_text(out, '12s'), 'A lock with no known end draws no time.');
-- The tooltip says what the tint stands for, never what to do.
view.rows[1].lock_deadline = now + 12;
assert(hud.details(view.rows[1], now, fresh().panels.recasts):find('Spells are locked for 12s.', 1, true), 'The tooltip names the lock and its time.');
assert(hud.details(view.rows[2], now, fresh().panels.recasts):find('Your MP is below its cost.', 1, true), 'The tooltip names the MP tint.');
-- Sample displays show each tint, so its color can be seen: a sample spell you can't afford, and a locked spell and
-- ability with their lock's time left. The item row stays as it is.
local samples = {};
for _, sample in ipairs(hud.sample(now).rows) do if sample.domain == 'recast' then samples[sample.kind .. ' ' .. sample.name] = sample; end end;
assert(samples['spell Cure IV'].tint_mp and not samples['spell Cure IV'].locked, 'The Cure IV sample is short of MP.');
assert(samples['spell Haste'].locked and samples['spell Haste'].lock_deadline > now, 'The Haste sample is locked, with a time.');
assert(samples['ability Provoke'].locked and samples['ability Provoke'].lock_deadline > now, 'The Provoke sample is locked, with a time.');
assert(not samples['item Empress Band'].locked and not samples['item Empress Band'].tint_mp, 'The item sample has no tint.');
local sampling = fresh();
sampling.preview = true;
for _, mode in ipairs({ 'bars', 'icons', 'text' }) do
    out = draw(mode, sampling);
    locked, short = 0, 0;
    for _, wash in ipairs(out.washes) do if wash[1] == 'lock' then locked = locked + 1; else short = short + 1; end; end;
    assert(locked >= 2 and short >= 1 and out.lock, mode .. ': the samples draw the locks and the MP tint: ' .. locked .. ', ' .. short);
end;
sampling.recast_tints.mp, sampling.recast_tints.spell_lock, sampling.recast_tints.ability_lock = false, false, false;
out = draw('bars', sampling);
assert(#out.washes == 0 and not out.lock, 'With the tints off, the samples show none.');

-- The app reads your MP for the snapshot and marks the recast rows at each refresh.
local client = require('core.client');
local party = AshitaCore:GetMemoryManager():GetParty();
party.GetMemberMP = function(_, slot) return slot == 0 and 123 or 0; end;
MOCK.player.server_id, MOCK.player.index, MOCK.player.zone, MOCK.player.name, MOCK.player.main_job = 1001, 0x400, 102, 'Tester', 5;
local read = client.read(now, fresh());
assert(read.valid and read.mp == 123, 'The snapshot carries your MP: ' .. tostring(read.mp));
return 'Recast tints mark and draw as their switches say';
