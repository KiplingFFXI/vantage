-- Vantage never shows '?' or says unknown, unconfirmed or not confirmed about an effect. An effect with no countdown
-- keeps its normal look: its icon at full strength and a bar with its plain track and no marks. An estimate that ran
-- out with no wear-off stays like that for as long as its row lives, then leaves.
package.loaded['ui.icons'] = { status = function(effect) return tonumber(effect) and 5000 + effect or nil; end };
-- The strips ask for an icon at the size they draw it; this one has a single size.
package.loaded['ui.icons'].status_at = function(id, artwork) return package.loaded['ui.icons'].status(id, artwork), { 1, 1 }; end;
local hud, defaults = require('ui.hud'), require('ui.defaults');
local party_defaults, overlay, party_hud = require('ui.party_defaults'), require('ui.native_party_hud'), require('ui.party_hud');
local fonts, imgui, bit = require('ui.fonts'), require('imgui'), require('bit');
MOCK.screen = { 1600, 1000 };

local FORBIDDEN = { 'unknown', 'unconfirmed', 'not confirmed', 'not been confirmed' };
local function said(text)
    text = tostring(text or '');
    local lower = text:lower();
    for _, word in ipairs(FORBIDDEN) do if lower:find(word, 1, true) then return word; end; end;
    -- No display asks anything, so a question mark there can only be a status mark.
    if text:find('?', 1, true) then return '?'; end;
    -- A field with no value is left out, not shown as '--'.
    if text:find('--', 1, true) then return '--'; end;
end;
local function assert_honest_text(text, label)
    for line in (tostring(text) .. '\n'):gmatch('(.-)\n') do
        local word = said(line);
        assert(not word, label .. ' says ' .. tostring(word) .. ': ' .. line);
    end;
end;
-- Every text a frame drew, through the fonts, straight to the draw list or in a tooltip, with its ink.
local painted = {};
local plain_draw = fonts.draw;
fonts.draw = function(list, face, value, x, y, size, ink, ...)
    painted[#painted + 1] = { text = value, ink = ink };
    return plain_draw(list, face, value, x, y, size, ink, ...);
end;
local function begin() painted, MOCK.imgui_calls = {}, {}; end;
local function texts()
    local out = {};
    for _, entry in ipairs(painted) do out[#out + 1] = entry; end;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddText' and type(call[6]) == 'string' then out[#out + 1] = { text = call[6], ink = call[5] }; end;
        if (call[1] == 'TextUnformatted' or call[1] == 'Text' or call[1] == 'TextWrapped') and type(call[2]) == 'string' then
            out[#out + 1] = { text = call[2], tooltip = true };
        end;
    end;
    return out;
end;
local function assert_honest(label)
    local count = 0;
    for _, entry in ipairs(texts()) do
        local word = said(entry.text);
        assert(not word, label .. (entry.tooltip and ' tooltip' or '') .. ' says ' .. tostring(word) .. ': ' .. entry.text);
        count = count + 1;
    end;
    return count;
end;
local function calls(name)
    local out = {};
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == name then out[#out + 1] = call; end; end;
    return out;
end;

-- An estimate on the target that runs out with no wear-off.
local s = defaults.make();
s.style.font, s.style.font_size, s.style.scale, s.style.hover = 'Ashita', 14, 1, true;
local live = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 5, self_known = true, self_revision = 1,
    self_effects = {}, party = {}, entities = {}, target = { id = 500, name = 'Training Crab', kind = 'enemy' } };
local tracked = require('core.tracker').new();
tracked:reconcile(live, 100);
tracked:observe({ { kind = 'apply', entity_id = 500, entity_name = 'Training Crab', effect = 2, source = 1001,
    source_name = 'Tester', duration = 10 } }, 101, live);
local function find(view, effect)
    for _, row in ipairs(view.rows) do if row.effect == effect then return row; end; end;
end;
local running = find(tracked:view(105, s, live), 2);
assert(running and running.status == 'estimated' and running.remaining, 'Fixture: Sleep is estimated while it runs.');
local view = tracked:view(112, s, live);
local ended = find(view, 2);
assert(ended and ended.status == 'unknown' and ended.deadline == nil and ended.remaining == nil and ended.kind == 'debuff',
    'Fixture: the estimate ran out with no wear-off and has no countdown.');
assert(not said(ended.reason), 'Its reason says nothing unknown: ' .. tostring(ended.reason));
assert(find(tracked:view(290, s, live), 2), 'It keeps showing for as long as its row lives.');
assert(not find(tracked:view(292, s, live), 2), 'Then it leaves as it always did.');

for id, panel in pairs(s.panels) do panel.enabled = id == 'target'; end;
local p = s.panels.target;
p.show_heading, p.locked, p.x, p.y, p.width = false, true, 100, 100, 320;
-- Icons only: the icon at full strength and no countdown.
p.mode = 'icons';
begin();
hud.draw(view, s, 112, {});
local icons_drawn = calls('draw:AddImage');
assert(#icons_drawn == 1 and icons_drawn[1][2] == 5002 and bit.band(icons_drawn[1][7], 0xFFFFFFFF) == bit.band(0xFFFFFFFF, 0xFFFFFFFF),
    'The ended estimate draws its icon at full strength.');
assert(#calls('draw:AddText') == 0 and #painted == 0, 'It draws no countdown and no mark.');
-- Bars: the plain track with no hatching, no dotted estimate line and no fill.
p.mode, p.show_fill, p.show_icon, p.warning_mark = 'bars', true, true, false;
p.show_time = true;
begin();
hud.draw(view, s, 112, {});
assert(#calls('draw:AddLine') == 0, 'A bar with no countdown has no marks on its track.');
assert(assert_honest('The ended estimate\'s bar') > 0, 'Fixture: the bar draws its name.');
local filled = 0;
for _, call in ipairs(calls('draw:AddRectFilled')) do filled = filled + 1; end;
assert(filled >= 1, 'Its track is drawn.');
-- Hover it: the tooltip names the effect and its source, and says nothing unknown.
local window = MOCK.positions['##vantage_target'];
MOCK.mouse_x, MOCK.mouse_y = window[1] + 20, window[2] + 12;
hud.draw(view, s, 112, {});
begin();
hud.draw(view, s, 112.5, {});
assert(#calls('BeginTooltip') == 1, 'Fixture: the bar shows its tooltip.');
assert_honest('The ended estimate');
MOCK.mouse_x, MOCK.mouse_y = nil, nil;

-- On the party list strips the ended estimate is its icon, as any effect is.
local config = party_defaults.make();
config.enabled, config.locked, config.include_self = true, true, true;
config.effects.timers = true;
local roster = { valid = true, id = 1001, zone = 230, members = { { id = 1001, index = 1024, slot = 0, group = 1, name = 'Aster',
    zone = 230, active = true, job = 5, level = 75, known = true, available = true } } };
local subjects = { [1001] = { known = true, complete = true, effects = { ended } } };
local game = { available = true, groups = { { x = 1300, y = 300, width = 200, height = 30,
    rows = { [0] = { x = 1300, y = 300, width = 200, height = 30, slot = 0 } } } } };
begin();
overlay.draw(roster, subjects, config, 112, { native_geometry = game, global_style = s.style });
assert_honest('The strip');
assert(#calls('draw:AddImage') > 0, 'Fixture: the strip draws the effect.');
-- Its tooltip on the strip says nothing unknown either, also for a member whose list may not be whole.
subjects[1001].complete = false;
imgui.BeginTooltip = function() MOCK.imgui_calls[#MOCK.imgui_calls + 1] = { 'BeginTooltip' }; return true; end;
begin();
party_hud.effect_tooltip(imgui, ended, roster.members[1], subjects[1001]);
assert(#calls('TextUnformatted') >= 2, 'Fixture: the strip tooltip has lines.');
assert_honest('The strip');
subjects[1001].complete = true;

-- Every panel in every layout, with every field on, and each row's tooltip.
local sample = hud.sample(100);
for _, key in ipairs(defaults.panel_order) do
    for _, mode in ipairs({ 'icons', 'bars', 'expanded', 'text' }) do
        local settings = defaults.make();
        settings.style.font, settings.style.font_size, settings.style.scale, settings.style.hover = 'Ashita', 14, 1, true;
        -- The recast tints are off at first; on, the sample recast rows draw their locks' times, which are checked too.
        settings.recast_tints.mp, settings.recast_tints.spell_lock, settings.recast_tints.ability_lock = true, true, true;
        for id, panel in pairs(settings.panels) do panel.enabled = id == key; end;
        local panel = settings.panels[key];
        panel.mode, panel.locked, panel.max_rows, panel.x, panel.y = mode, true, 6, 100, 100;
        for _, id in ipairs(defaults.field_ids) do panel['show_' .. id] = true; end;
        panel.show_icon, panel.show_fill = true, true;
        local rows = hud.filter_rows(sample, panel, key, settings);
        begin();
        hud.draw(sample, settings, 100, {});
        assert_honest(key .. ' ' .. mode);
        for _, row in ipairs(rows) do assert_honest_text(hud.details(row, 100, panel), key .. ' tooltip'); end;
        local copied = hud.copy_text(sample, settings, key, true, 100);
        assert_honest_text(copied, key .. ' copied details');
        assert_honest_text(hud.copy_text(sample, settings, key, false, 100), key .. ' copied rows');
    end;
end;

-- With every field on, a row with no start, no full duration, no target or caster name and no countdown shows its
-- name alone: no field stands in for a value it does not have.
local untimed = { effect = 13, name = 'Slow', kind = 'debuff', status = 'unknown', key = 'untimed', domain = 'status' };
local field_panel = defaults.make().panels.target;
field_panel.mode = 'bars';
field_panel.show_icon = true;
for _, id in ipairs(defaults.field_ids) do field_panel['show_' .. id] = true; end;
local entries = hud.entries(untimed, field_panel, s.style, 100);
assert(#entries == 1 and entries[1].id == 'name' and entries[1].text == 'Slow',
    'An untimed row shows only its name: ' .. require('ui.fields').text(entries));
assert(#hud.field_lines(untimed, field_panel, 100) == 1, 'The plain field lines leave the missing values out too.');

-- A recast with no client art keeps an empty icon box, with no question mark in it.
package.loaded['ui.icons'].status = function() return nil; end;
local recast_icons = require('ui.recast_icons');
local saved_recast_draw = recast_icons.draw;
recast_icons.draw = function() return false; end;
local recast = defaults.make();
recast.style.font = 'Ashita';
-- The recast tints are off at first; on, the sample rows draw their locks' times, which are checked too.
recast.recast_tints.mp, recast.recast_tints.spell_lock, recast.recast_tints.ability_lock = true, true, true;
for id, panel in pairs(recast.panels) do panel.enabled = id == 'spell_recasts'; end;
recast.panels.spell_recasts.mode, recast.panels.spell_recasts.show_icon = 'bars', true;
begin();
hud.draw(hud.sample(100), recast, 100, {});
assert(#calls('draw:AddRect') > 0, 'Fixture: the recast draws its empty icon box.');
assert_honest('A recast with no art');
recast_icons.draw = saved_recast_draw;
fonts.draw = plain_draw;

-- A remaining-time alert fires on the running estimate and never on the row once it has no countdown.
local alerts = require('core.alerts').new();
local rule = { id = 'sleep', enabled = true, event = 'remaining', effect = 2, scope = 'self', thresholds = { 15 }, unit = 'seconds',
    cooldown = 0, visual = true, duration = 4 };
local function as_own(row, instance)
    local copy = defaults.copy(row);
    copy.key, copy.instance, copy.scope, copy.entity_id = '10:2', instance, 'self', 10;
    return copy;
end;
local own = { valid = true, subjects = { { id = 10, scope = 'self', known = true } }, context = { id = 10, zone = 1, job = 1 } };
own.rows = { as_own(running, 1) };
own.rows[1].remaining = 40;
alerts:update(own, {}, { rule }, 0, {});
own.rows[1].remaining = 5;
alerts:update(own, {}, { rule }, 1, {});
assert(#alerts:drain(1) == 1, 'Fixture: the running estimate crosses its threshold and fires.');
own.rows = { as_own(ended, 2) };
alerts:update(own, {}, { rule }, 2, {});
alerts:update(own, {}, { rule }, 3, {});
assert(#alerts:drain(3) == 0, 'A row with no countdown never fires a remaining-time alert.');

-- A unit the game hasn't named yet has no name: no Entity and its number, no number alone and no gap, on its row, in
-- its hover, in a field or in an alert. Sorting by target takes it, and the name fills in when the game gives it.
local tracker = require('core.tracker').new();
local here = { valid = true, id = 10, name = 'Tester', zone = 1, job = 1, self_known = true, self_effects = {}, party = {}, entities = {} };
local MOB = 0x1000123;
tracker:observe({ { kind = 'apply', entity_id = MOB, effect = 13, scope = 'enemy', duration = 60 },
    { kind = 'apply', entity_id = MOB + 1, effect = 13, scope = 'enemy', entity_name = '', duration = 60 } }, 1, here);
local seen = tracker:view(2, {}, here);
assert(#seen.rows == 2 and #seen.subjects == 2, 'Fixture: two units, each with a row.');
local function nameless(text, label)
    text = tostring(text);
    assert(not text:find('Entity', 1, true), label .. ' says Entity: ' .. text);
    assert(not text:find('%d%d%d%d%d'), label .. ' prints the number: ' .. text);
end;
for index, row in ipairs(seen.rows) do
    assert(row.entity_name == nil and seen.subjects[index].name == nil, 'It has no name.');
    local hover = hud.details(row, 2, field_panel);
    nameless(hover, 'Its hover');
    assert(not hover:find('On ', 1, true), 'Its hover leaves out who it is on: ' .. hover);
    for _, entry in ipairs(hud.entries(row, field_panel, s.style, 2)) do
        assert(entry.id ~= 'target', 'No target field.');
        nameless(entry.text, 'A field');
    end;
    for _, line in ipairs(hud.field_lines(row, field_panel, 2)) do nameless(line, 'A line'); end;
end;
local by_target = defaults.make().panels.watch;
by_target.group_by = 'target';
local rows = { seen.rows[1], { effect = 14, name = 'Paralysis', key = 'named', entity_id = 5, entity_name = 'Crab', domain = 'status', kind = 'debuff', scope = 'enemy' } };
local sorted = hud.filter_rows({ rows = rows, context = { watch_ids = { MOB, 5 } } }, by_target, 'watch', defaults.make());
assert(type(sorted) == 'table', 'Sorting by target takes a row with no name.');
local nameless_row = defaults.copy(seen.rows[1]);
nameless_row.remaining = 40;
local warn = { id = 'slow', enabled = true, event = 'remaining', effect = 13, scope = 'all', thresholds = { 15 }, unit = 'seconds',
    cooldown = 0, visual = true, duration = 4 };
local watching = { valid = true, rows = { nameless_row }, subjects = { { id = MOB, scope = 'enemy', known = true } }, context = { id = 10, zone = 1, job = 1 } };
local warnings = require('core.alerts').new();
warnings:update(watching, {}, { warn }, 0, {});
nameless_row.remaining = 5;
warnings:update(watching, {}, { warn }, 1, {});
local warned = warnings:drain(1);
assert(#warned == 1 and warned[1].message == 'Slow on the target may wear off soon.', 'An alert names no one: ' .. tostring(warned[1] and warned[1].message));
tracker:observe({ { kind = 'apply', entity_id = MOB, effect = 13, scope = 'enemy', entity_name = 'Goblin Mugger', duration = 60 } }, 3, here);
seen = tracker:view(3, {}, here);
local named = false;
for _, row in ipairs(seen.rows) do named = named or row.entity_id == MOB and row.entity_name == 'Goblin Mugger'; end;
assert(named, 'The name fills in when the game gives it.');
return 'No display says unknown or shows a question mark, and untimed effects keep their normal look';
