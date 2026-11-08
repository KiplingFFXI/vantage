-- Phoenix sends 0x119 (every ability recast) each time a job ability is used, with each running timer rounded up to
-- whole seconds (0x119_abil_recast.cpp), and the client rebuilds its live timers from those seconds. So a running
-- ability timer can rise by up to a second when another ability is used. That is not a new use: the row keeps its
-- instance, total and bar, and no rule fires again. Played through core.recasts and core.alerts as vantage.lua wires
-- them.
local abilities = {};
local manager = {
    GetSpellTimer = function() return 0; end,
    GetAbilityTimerId = function(_, slot) return abilities[slot] and abilities[slot].id or 0; end,
    GetAbilityTimer = function(_, slot) return abilities[slot] and abilities[slot].timer or 0; end,
};
local ability_resources = { [547] = { Id = 547, Name = { [1] = 'Provoke' }, RecastTimerId = 5, Type = 1 },
    [548] = { Id = 548, Name = { [1] = 'Berserk' }, RecastTimerId = 1, Type = 1 },
    [549] = { Id = 549, Name = { [1] = 'Fight' }, RecastTimerId = 100, Type = 1 } };
local resources = {
    GetSpellById = function() return nil; end,
    GetAbilityById = function(_, id) return ability_resources[id]; end,
    GetAbilityByTimerId = function() return nil; end,
    GetItemById = function() return nil; end,
};
local memory = { GetRecast = function() return manager; end, GetInventory = function() return nil; end };
AshitaCore.GetMemoryManager = function() return memory; end;
AshitaCore.GetResourceManager = function() return resources; end;
local recasts = require('core.recasts');
local alerts = require('core.alerts');
local hud = require('ui.hud');
local snapshot = { valid = true, id = 1001, zone = 230, job = 1, name = 'Aster' };
local model, notifier, now = recasts.new(), alerts.new(), 100;
local function get(view, id) for _, row in ipairs(view.rows) do if row.recast_id == id then return row; end; end; end;
-- One 0.1 s sample: the client counts its live timers down in 1/60 s ticks.
local function step(rules)
    now = now + 0.1;
    for _, slot in pairs(abilities) do slot.timer = math.max(0, slot.timer - 6); end;
    model:update(snapshot, now, { spells = true, abilities = true, items = false });
    local view = model:view(now);
    notifier:update({ valid = true, context = { id = 1001, job = 1 }, rows = view.rows, subjects = {} }, model:drain_events(),
        rules or {}, now, {});
    return view, notifier:drain(now);
end;
-- The server's 0x119: every running ability timer rounded up to whole seconds.
local function resync()
    for _, slot in pairs(abilities) do slot.timer = math.ceil(slot.timer / 60) * 60; end;
end;
local started = { id = 'started', name = 'On cooldown', domain = 'recast', enabled = true, effect = 0,
    scope = 'self', event = 'started', thresholds = { 10 }, cooldown = 10, duration = 4, visual = true, chat = true };

abilities[0], abilities[1], abilities[2] = { id = 0, timer = 0 }, { id = 5, timer = 0 }, { id = 1, timer = 0 };
step({ started }); step({ started });
abilities[1].timer = 30 * 60;
local view, notices = step({ started });
local first = get(view, 5);
assert(first.total > 29 and #notices == 1 and notices[1].message:find('Provoke', 1, true), 'Fixture: Provoke is used once.');
for _ = 1, 123 do step({ started }); end;
local before = get(model:view(now), 5);
-- Berserk is used 12.4 s later: Phoenix sends Berserk at 300 s and Provoke rounded up.
abilities[2].timer = 300 * 60;
resync();
view, notices = step({ started });
local after = get(view, 5);
assert(after.instance == first.instance and after.total == first.total and after.start == first.start,
    'A resync keeps the running row: instance ' .. first.instance .. ' -> ' .. after.instance .. ', total ' .. tostring(after.total));
assert(#notices == 1 and notices[1].message:find('Berserk', 1, true), 'Only Berserk goes on cooldown: ' .. #notices .. ' notices');
local panel = { horizon = 300, direction = 'drain' };
assert(hud.fraction(after, panel, after.observed_at) < hud.fraction(before, panel, before.observed_at) + 0.05,
    'The bar keeps draining through a resync.');

-- Every phase of the rounding: none of them is a new use.
for tenth = 0, 9 do
    model, notifier = recasts.new(), alerts.new();
    abilities[1].timer, abilities[2].timer = 0, 0;
    step(); step();
    abilities[1].timer = 30 * 60; step();
    local used = get(model:view(now), 5);
    for _ = 1, 50 + tenth do step(); end;
    resync(); step();
    local row = get(model:view(now), 5);
    assert(row.instance == used.instance and row.total == used.total, 'A resync ' .. (5 + tenth / 10) .. ' s later is not a new use.');
end;

-- A percent rule on a 300 s recast fires once per use, a resync after its threshold or not.
local half = { id = 'half', name = 'Half', domain = 'recast', enabled = true, effect = 20001, scope = 'self',
    event = 'remaining', unit = 'percent', thresholds = { 50 }, cooldown = 0, duration = 4, visual = true, chat = true };
model, notifier = recasts.new(), alerts.new();
abilities[1], abilities[2] = { id = 5, timer = 0 }, { id = 1, timer = 0 };
step({ half }); step({ half });
abilities[2].timer = 300 * 60; step({ half });
local fired = 0;
while get(model:view(now), 1).remaining > 140.65 do local _, list = step({ half }); fired = fired + #list; end;
abilities[1].timer = 30 * 60;
resync();
while get(model:view(now), 1) and get(model:view(now), 1).remaining > 60 do local _, list = step({ half }); fired = fired + #list; end;
assert(fired == 1, 'A 50% recast rule fires once per use: ' .. fired);

-- A real reuse still starts a new row: one that reached zero, or a short command used again within one sample of
-- reaching zero, which rises about 4.9 s.
model, notifier = recasts.new(), alerts.new();
abilities[1], abilities[2] = { id = 5, timer = 0 }, { id = 100, timer = 0 };
step(); step();
abilities[2].timer = 5 * 60; step();
local command = get(model:view(now), 100);
for _ = 1, 48 do step(); end;
assert(abilities[2].timer == 6, 'Fixture: the command is one tick from ready.');
abilities[2].timer = 5 * 60;
view = step();
local again = get(view, 100);
assert(again.instance ~= command.instance and again.total > 4.8, 'A command used again just before zero is a new use.');

-- A row running at load has no known total; a resync doesn't make one up from the time left.
model, notifier = recasts.new(), alerts.new();
abilities[1] = { id = 5, timer = 17 * 60 + 25 };
step(); step();
resync(); view = step();
assert(get(view, 5).total == nil and get(view, 5).start == nil, 'A resync of a row seen at load leaves its total unknown.');
