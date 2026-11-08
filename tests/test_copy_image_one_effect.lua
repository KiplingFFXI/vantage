-- Copy Image is one effect, 66, wherever Vantage shows it or acts on it. Its icon is how many shadows are left: 446 for 4 or
-- more, 445 for 3, 444 for 2 and 66 for 1 (battleutils.cpp :3152-3170). The tracker hands each row and event out as Copy
-- Image with that icon beside it, so the pickers list it once, a hide rule or an alert on it covers every count, and what's
-- drawn is still the count's icon.
local icons = require('ui.icons');
local asked = {};
icons.status = function(id) asked[#asked + 1] = id; return 123; end;
local catalog = require('core.catalog');
local filters = require('core.effect_filters');
local SELF = 1001;

-- The pickers list it once, and none of its icons for 2, 3 and 4 or more shadows.
local listed = 0;
for _, entry in ipairs(catalog.list()) do
    assert(entry.id < 444 or entry.id > 446, 'The pickers leave out the icon ' .. entry.id .. '.');
    if entry.name:find('Copy Image', 1, true) then listed = listed + 1; end;
end;
assert(listed == 1, 'The pickers list Copy Image once: ' .. listed);

-- The player's three shadows, then its wear-off: the row and the removal read as Copy Image, with the icon.
local tracker, alerts = require('core.tracker').new(), require('core.alerts').new();
local rules = { { id = 'gone', enabled = true, event = 'removed', effect = 66, scope = 'self', cooldown = 0, duration = 30, visual = true } };
local function snapshot(revision, timers, effects)
    return { valid = true, id = SELF, name = 'Tester', zone = 102, job = 13, self_known = true, self_revision = revision,
        self_timer_revision = timers, self_effects = effects, party = {}, entities = {} };
end;
local three = { { effect = 445, slot = 0, deadline = 1900, raw_timer = 54000 } };
local notices = 0;
local function frame(snap, now, observations)
    tracker:observe(observations or {}, now, snap);
    tracker:reconcile(snap, now);
    local view, events = tracker:view(now, {}, snap), tracker:drain_events();
    alerts:update(view, events, rules, now, {});
    notices = notices + #alerts:drain(now);
    return view, events;
end;
local view = frame(snapshot(1, 1, three), 1000);
local row = view.rows[1];
assert(#view.rows == 1 and row.effect == 66 and row.icon == 445 and row.name == 'Copy Image' and row.kind == 'buff'
    and row.group == catalog.get(66).group, 'Three shadows read as Copy Image, with their icon.');
local _, worn = frame(snapshot(1, 1, three), 1010,
    { { kind = 'remove', entity_id = SELF, effect = 445, scope = 'self', reason = 'Observed wearoff', timer_revision = 1 } });
local _, after = frame(snapshot(3, 2, {}), 1010.4);
local gone;
for _, list in ipairs({ worn, after }) do
    for _, event in ipairs(list) do if event.kind == 'removed' then gone = event; end; end;
end;
assert(gone and gone.effect == 66 and gone.icon == 445, 'Its removal reads as Copy Image at its icon.');
assert(notices == 1, 'An alert on Copy Image going fires at any count: ' .. notices);

-- A Hidden everywhere rule on Copy Image hides it at every count, and nothing else.
local rule = filters.rule();
rule.effect = 66;
local hidden = { enabled = true, rules = { rule } };
local you = filters.context(nil, SELF, { name = 'Tester', job = 13, scope = 'self' });
local counts = require('core.tracker').new();
for at, icon in ipairs({ 446, 445, 444, 66 }) do
    local snap = snapshot(at, at, { { effect = icon, slot = 0, deadline = 1900, raw_timer = 54000 } });
    counts:observe({}, 1000 + at, snap);
    counts:reconcile(snap, 1000 + at);
    local shown = counts:view(1000 + at, {}, snap).rows[1];
    assert(shown and shown.effect == 66 and (shown.icon or shown.effect) == icon and filters.hide(hidden, shown, you),
        'Hiding Copy Image hides it at icon ' .. icon .. '.');
end;
assert(not filters.hide(hidden, { effect = 33, kind = 'buff', scope = 'self' }, you), 'And nothing else.');

-- What's drawn is the count's icon: the timer panel, as bars and as icons, and the party list.
local function drawn(paint)
    asked = {};
    paint();
    local seen = {};
    for _, id in ipairs(asked) do seen[id] = true; end;
    return seen;
end;
local hud, defaults = require('ui.hud'), require('ui.defaults');
MOCK.screen = { 1600, 1000 };
for _, mode in ipairs({ 'bars', 'icons' }) do
    local s = defaults.make();
    for id, panel in pairs(s.panels) do panel.enabled = id == 'self_buffs'; end;
    s.panels.self_buffs.mode = mode;
    local seen = drawn(function() hud.draw({ valid = true, context = { id = SELF, valid = true }, rows = { row } }, s, 1000, {}); end);
    assert(seen[445] and not seen[66], 'As ' .. mode .. ', the panel draws the icon of three shadows.');
end;
local party_hud, party_defaults = require('ui.party_hud'), require('ui.party_defaults');
local config = party_defaults.make();
local look = require('ui.party_theme').party(config, { font = 'XI View', font_size = 16 });
local list = setmetatable({}, { __index = function() return function() end; end });
local seen = drawn(function()
    party_hud.paint_effects(list, look, { known = true, effects = { row } }, config.effects, { x = 0, y = 0, width = 200, height = 200 },
        -1, -1, {}, 1000);
end);
assert(seen[445] and not seen[66], 'The party list draws the icon of three shadows.');
return 'Copy Image is one effect at every count, drawn by the icon of the shadows left';
