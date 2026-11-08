-- Nothing on the pages looks on while it does nothing: what can't work says why and offers the way out, or goes until it
-- can, and one thing has one name wherever it shows. Each section here is one way a tick could sit on saying nothing.
local h = require('panel_fixture')();
local defaults, imgui = require('ui.defaults'), h.imgui;
imgui.CollapsingHeader = function(label) MOCK.imgui_calls[#MOCK.imgui_calls + 1] = { 'CollapsingHeader', label }; return true; end;

local function page(id, tab, change) h.fresh(change); h.on(id, tab); end;
local function home(change) h.fresh(change); h.draw(); h.draw(); end;
local function steps() return #h.app.state.history; end;
local function has(name) return h.drawn()[name] == true; end;
local function tabs()
    local out = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        local name = type(call[2]) == 'string' and call[2]:match('^(.-)##frame_tab$');
        if name then out[name] = true; end;
    end;
    return out;
end;

-- A ready pulse with no recast panel on says so on Recasts and the main page, and one click gives it a spot of its own.
local function pulsing(s) s.ready_pulse.enabled = true; end;
local NO_ROW = 'No recast panel is on, so the pulse has no row to play on.';
page('spell_recasts', 'show', pulsing);
assert(h.says(NO_ROW), 'Recasts says the pulse has no row.');
h.draw('Use a spot of its own##frame'); h.draw();
assert(h.s.ready_pulse.spot == 'screen' and steps() == 1 and not h.says(NO_ROW), 'One Undo step gives it a spot, and the line goes.');
home(pulsing);
assert(h.says('No recast panel is on, so the ready pulse has no row to play on.'), 'The main page says so too.');
h.draw('Use a spot of its own##main_pulse'); h.draw();
assert(h.s.ready_pulse.spot == 'screen' and steps() == 1, 'and its button does the same.');
page('spell_recasts', 'show', function(s) pulsing(s); s.panels.spell_recasts.enabled = true; end);
assert(not h.says(NO_ROW), 'A panel on has rows to play on.');
page('spell_recasts', 'show');
assert(not h.says(NO_ROW), 'A pulse that is off says nothing.');

-- An empty watch list says so where it would show, with the way to fill it there.
local NOBODY, NO_MOBS = 'Nobody is watched now, so this panel stays empty.', 'No mobs are watched now.';
page('watch', 'show');
assert(h.says(NOBODY), 'The panel says nobody is watched.');
page('watch', 'show', function(s) s.watch_ids = { 42 }; end);
assert(not h.says(NOBODY), 'With someone watched it says nothing.');
page('watch', 'show', function(s) s.panels.watch.list_debuffed = true; end);
assert(not h.says(NOBODY), 'Nor while the panel lists what you debuff.');
page('overhead', 'show');
assert(h.says(NO_MOBS) and h.called('Button', 'Watch my target##frame'), 'Overhead icons says so under Watched mobs, with the button.');
page('overhead', 'show', function(s) s.overhead.units.watched = false; end);
assert(not h.says(NO_MOBS) and not h.called('Button', 'Watch my target##frame'), 'With Watched mobs unticked it says nothing.');

-- A group the Which groups show ticks leave out has no panel to put it in.
local PARTY, ALLIANCE = 'Your party in a panel of its own', 'Alliance 1 in a panel of its own';
page('party_ui', 'place', function(s) s.party_ui.enabled = true; end);
assert(has(PARTY) and has(ALLIANCE), 'A group that shows has its tick.');
page('party_ui', 'place', function(s) s.party_ui.enabled, s.party_ui.strips.alliance1 = true, false; end);
assert(has(PARTY) and not has(ALLIANCE), 'One that doesn\'t has none.');

-- Timer panels on Icons skip most of the look: the main page says which rows reach them.
local ICONS = 'Your timer panels are all on Icons, so of these only Icon size and Space between rows change them.';
local ALL_ICONS = 'Your timer panels are all on Icons, which don\'t use this. They go by Icon size, under More look.';
home();
assert(h.says(ICONS) and h.says(ALL_ICONS), 'A fresh save is all Icons, and the main page says so.');
home(function(s) s.panels.target.mode = 'bars'; end);
assert(not h.says(ICONS) and not h.says(ALL_ICONS), 'One panel on bars is reached by them all.');

-- A paused Hidden everywhere list says so on every page that leans on it, with the way back.
local PAUSED = 'The Hidden everywhere list is paused, so it hides nothing now.';
for _, id in ipairs({ 'self_buffs', 'overhead', 'pet', 'party_ui' }) do
    page(id, 'filters', function(s) s.effect_filters.enabled = false; end);
    assert(h.says(PAUSED) and not h.says('Effects on the Hidden everywhere list are hidden here too.'), id .. ' says the list is paused.');
    h.draw('Use it again##frame'); h.draw();
    assert(h.s.effect_filters.enabled and steps() == 1 and not h.says(PAUSED), id .. ': one Undo step puts it back.');
end;

-- Party cooldowns on with nowhere to show says so on the main page, and the button turns on the list.
local NOWHERE = 'Party cooldowns has nowhere to show.';
local function nowhere(s)
    local watch = s.party_cooldowns;
    watch.enabled, watch.list.enabled, watch.strips, watch.overhead = true, false, false, false;
end;
home(nowhere);
assert(h.says(NOWHERE), 'The main page says so.');
h.draw('Show them in a list##main_cooldowns'); h.draw();
assert(h.s.party_cooldowns.list.enabled and steps() == 1 and not h.says(NOWHERE), 'One Undo step turns on the list.');

-- Muted alerts say so on their page, with the way back.
local MUTED = 'Alerts are muted, so none of them fires.';
page('notices', 'show', function(s) s.alerts.muted = true; end);
assert(h.says(MUTED), 'The page says they are muted.');
h.draw('Unmute##frame'); h.draw();
assert(not h.s.alerts.muted and steps() == 1 and not h.says(MUTED), 'One Undo step unmutes them.');

-- Buff side moves a group a drag has put on a side of its own too.
page('party_ui', 'place', function(s) s.party_ui.enabled, s.party_ui.groups[1].native_side = true, 'left'; end);
h.pick('##frame_Buff side', 'Right##right');
assert(h.s.party_ui.native.side == 'right' and h.s.party_ui.groups[1].native_side == 'default', 'The pick reaches every group.');

-- Copying with nothing to copy says so, and leaves what is on the clipboard.
do
    local set = imgui.SetClipboardText;
    local copied = 0;
    imgui.SetClipboardText = function() copied = copied + 1; end;
    h.fresh();
    local ok, why = h.app.callbacks.copy_shown('self_buffs', false);
    assert(ok == false and why == 'No timers are showing, so nothing was copied.' and copied == 0, 'Nothing to copy leaves the clipboard: ' .. tostring(why));
    imgui.SetClipboardText = set;
end;

-- The cooldown list's samples follow its picks, and ticks that leave none show all of them rather than an empty list.
do
    local cooldowns = require('core.party_cooldowns');
    local config = defaults.make().party_cooldowns;
    local all = #cooldowns.list_samples(config, 100);
    config.list.jobs[3] = true;
    local some = cooldowns.list_samples(config, 100);
    assert(#some > 0 and #some < all, 'A job ticked narrows the samples: ' .. #some .. ' of ' .. all);
    for _, use in ipairs(some) do assert(use.job == 3, 'Only that job shows.'); end;
    config.list.jobs[3], config.list.jobs[17] = nil, true;
    assert(#cooldowns.list_samples(config, 100) > 0, 'Ticks that match no sample still show some.');
end;

-- Samples show whatever a panel's picks are: an empty watch list, a kind ticked or a member ticked.
do
    local hud, catalog = require('ui.hud'), require('core.catalog');
    local view = hud.sample(100);
    local s = defaults.tidy(defaults.make());
    s.preview, s.panels.watch.enabled = true, true;
    assert(#hud.filter_rows(view, s.panels.watch, 'watch', s) > 0, 'With nobody watched the panel still has samples.');
    local p = s.panels.self_buffs;
    p.groups[catalog.get(33).group] = true;
    assert(#hud.filter_rows(view, p, 'self_buffs', s) > 0, 'A kind ticked keeps the samples of that kind.');
end;

-- What can't do anything goes. { display, tab, row, change where it can't, change where it can }
local function layout(name) return function(s) s.overhead.types.mob.layout = name; end; end;
local function kinds(name) return function(s) s.overhead.types.mob.kinds = name; end; end;
local function panel(change) return function(s) change(s.panels.self_buffs); end; end;
local function with_mode(mode, change) return panel(function(p) p.mode = mode; if change then change(p); end; end); end;
local overhead_page = require('ui.overhead_settings');
for _, row in ipairs({
    { 'overhead', 'filters', 'Only buffs I cast', kinds('debuff'), kinds('all') },
    { 'overhead', 'filters', 'Only debuffs from my party', kinds('buff'), kinds('all') },
    { 'overhead', 'show', 'Light up buffs you can remove', nil, kinds('all') },
    -- A ticked Always show effect is a buff the light can reach, even under Debuffs only.
    { 'overhead', 'show', 'Light up buffs you can remove', function(s)
        kinds('debuff')(s);
        s.overhead.types.mob.show_copy_image, s.overhead.types.mob.show_third_eye = false, false;
    end, kinds('debuff') },
    { 'overhead', 'show', 'Show countdowns', function(s) s.overhead.size.max_px = 13; end, function(s) s.overhead.size.max_px = 14; end },
    { 'overhead', 'place', 'Countdowns go inside icons under', function(s) s.overhead.size.max_px = 13; end, function(s) s.overhead.size.max_px = 14; end },
    { 'overhead', 'show', 'Faded opacity', function(s) s.overhead.fade_start = s.overhead.distance_cap; end, nil },
    { 'rolls', 'look', 'Not reached color', function(s) s.rolls.show_members = false; end, function(s) s.rolls.show_members = true; end },
    { 'rolls', 'look', 'Show its heading', function(s) s.style.minimal = true; end, nil },
    { 'cooldown_list', 'show', 'Locked', nil, function(s) s.party_cooldowns.enabled, s.party_cooldowns.list.enabled = true, true; end },
    { 'self_buffs', 'look', 'Between parts', with_mode('bars'), with_mode('bars', function(p) p.wrap = true; end) },
    { 'self_buffs', 'look', 'Divider before it', with_mode('bars'), with_mode('bars', function(p) p.wrap = true; end) },
    { 'self_buffs', 'look', 'When space is short, keep the higher-priority parts', with_mode('bars', function(p) p.wrap = true; end), with_mode('bars') },
    { 'self_buffs', 'look', 'Label position', with_mode('bars'), with_mode('bars', function(p) p.show_elapsed = true; end) },
    { 'self_buffs', 'look', 'Between label and value', with_mode('bars', function(p) p.show_elapsed, p.label_position = true, 'hidden'; end),
        with_mode('bars', function(p) p.show_elapsed = true; end) },
    { 'self_buffs', 'place', 'Across', panel(function(p) p.anchor.to = 'screen'; end), panel(function(p) p.anchor.to = 'chat'; end) },
    { 'self_buffs', 'place', 'Width', panel(function(p) p.mode, p.auto_width, p.dock_match_width, p.anchor.to = 'bars', false, true, 'chat'; end),
        panel(function(p) p.mode, p.auto_width = 'bars', false; end) },
    { 'spell_recasts', 'when', 'When the pulse plays', nil, pulsing },
}) do
    local name = row[1] .. ' / ' .. row[2] .. ' / ' .. row[3];
    overhead_page._selection.kind = 'mob';
    page(row[1], row[2], row[4]);
    if row[4] then assert(not has(row[3]), name .. ' goes while it can\'t do anything.'); end;
    page(row[1], row[2], row[5]);
    assert(has(row[3]), name .. ' shows while it can.');
end;

-- A tab with nothing that can work goes, and a display left on it comes back to Show.
page('cooldown_list', 'show');
assert(not tabs()['Size and place'] and not tabs()['Filters'] and not tabs()['When to show'], 'Party cooldowns has only Show with the list off: ' .. table.concat((function()
    local out = {}; for name in pairs(tabs()) do out[#out + 1] = name; end; return out;
end)(), ', '));
local function list_on(s) s.party_cooldowns.enabled, s.party_cooldowns.list.enabled = true, true; end;
page('cooldown_list', 'place', list_on);
assert(tabs()['Size and place'] and tabs()['Filters'] and tabs()['When to show'] and has('Moves with'), 'With the list on the three tabs are back.');
h.s.party_cooldowns.list.enabled = false;
h.bump(); h.draw(); h.draw();
assert(not has('Moves with') and has('In a list'), 'Turning the list off leaves the tab it opened.');
page('pet', 'look', function(s) s.pet.show_vitals = false; end);
assert(not tabs()['Look'] and has('Show HP, MP and TP'), 'Pet has no Look tab with no bars to color.');

-- With the list off its lock doesn't count, so the page has no Unlocked line for it.
page('cooldown_list', 'show', function(s) s.party_cooldowns.list.locked = false; end);
assert(not h.says('Unlocked'), 'No list, no line.');
page('cooldown_list', 'show', function(s) list_on(s); s.party_cooldowns.list.locked = false; end);
assert(h.says('Unlocked'), 'With the list on it counts.');

-- No boxes or headings takes every heading, and the page says why in the tick's place.
local NO_HEADING = 'No boxes or headings is on, so this display has no heading.';
page('rolls', 'look', function(s) s.style.minimal = true; end);
assert(h.says(NO_HEADING), 'Phantom Roll says why.');
page('rolls', 'look');
assert(not h.says(NO_HEADING), 'Without it there is nothing to say.');

-- Beside the party list and Over heads read off with the watch off, and ticking one turns the watch on.
page('cooldown_list', 'show');
h.draw('Over heads##frame'); h.draw();
assert(h.s.party_cooldowns.enabled and h.s.party_cooldowns.overhead and steps() == 1, 'Over heads turns the watch on with it, in one step.');

-- A blank part label or divider keeps the blank's meaning: it goes back to the normal wording.
page('self_buffs', 'look', function(s) local p = s.panels.self_buffs; p.mode, p.wrap, p.show_source, p.field_labels.source = 'bars', true, true, 'From'; end);
h.draw('Who cast it'); h.draw();
h.type('##frame_Label_part', '');
assert(h.s.panels.self_buffs.field_labels.source == nil, 'A blank label is no label kept: ' .. tostring(h.s.panels.self_buffs.field_labels.source));

-- Widest never goes under Narrowest, and Narrowest takes Widest up with it.
page('self_buffs', 'place', function(s) local p = s.panels.self_buffs; p.mode, p.auto_width, p.locked, p.min_width, p.max_width = 'bars', true, false, 200, 300; end);
h.slide('##frame_Narrowest', 500);
assert(h.s.panels.self_buffs.min_width == 500 and h.s.panels.self_buffs.max_width == 500, 'Narrowest lifts Widest.');
h.slide('##frame_Widest', 240);
assert(h.s.panels.self_buffs.max_width == 240 and h.s.panels.self_buffs.min_width == 240, 'Widest lowers Narrowest.');

-- A rule about enemies or pets has no player's name or job to go by, so moving it there clears them.
do
    local filters = require('core.effect_filters');
    local rule = filters.rule();
    rule.effect, rule.scope, rule.name, rule.job = 253, 'party', 'Aerith', 3;
    page('hidden', 'show', function(s) s.effect_filters.rules = { rule }; end);
    assert(has('Player name'), 'A rule about players has them.');
    h.pick('##frame_Who', 'Enemies##enemy');
    local kept = h.s.effect_filters.rules[1];
    assert(kept.scope == 'enemy' and kept.name == '' and kept.job == 0 and not has('Player name'), 'A rule about enemies has neither.');
end;

-- A starter with alert rules turns Alerts on. One with none leaves it.
do
    local starters = require('core.starters');
    for _, entry in ipairs(starters.list) do
        local s = defaults.tidy(defaults.make());
        s.alerts.enabled = false;
        local made = starters.apply(s, entry.id);
        assert(made.alerts.enabled == (#entry.rules > 0), entry.name .. ' turns Alerts on only with rules of its own.');
    end;
end;

-- With no saved profile picked the buttons say what's missing.
for _, label in ipairs({ 'Load##profile_load', 'Overwrite##profile_overwrite', 'Delete##profile_delete' }) do
    h.fresh();
    h.s.window.tab = 'Profiles';
    h.draw();
    h.draw(label); h.draw();
    assert(h.says('Choose a saved profile first.'), label .. ' says to pick one.');
end;

-- Lines that only hold in some states say nothing in the others.
local CURSOR = 'While the cursor is out, "my target" means the unit under it';
page('target', 'show', function(s) s.tracking.follow_subtarget = true; end);
assert(h.says(CURSOR), 'With the tick on it says what the tick does.');
page('target', 'show', function(s) s.tracking.follow_subtarget = false; end);
assert(not h.says(CURSOR), 'With it off it says nothing.');
page('self_buffs', 'show', function(s) s.style.hover = true; end);
assert(h.says('Point at one for the rest.'), 'With details on, pointing shows the rest.');
page('self_buffs', 'show', function(s) s.style.hover = false; end);
assert(not h.says('Point at one'), 'With them off it says nothing of pointing.');

-- The commands use the page's words.
do
    local function command(text) local event = { command = text }; MOCK.fire('command', event); assert(event.blocked, text); end;
    h.fresh();
    command('/vg skin Mint');
    assert(h.app.state.settings.style.skin == 'Mint' or require('ui.theme').window(h.app.state.settings).theme == 'Mint', '/vg skin picks a skin.');
    h.fresh();
    command('/vg skin Frameless');
    assert(h.app.state.settings.style.minimal == true, 'Frameless is a skin like any other.');
    h.fresh();
    command('/vg skin mint');
    assert(h.app.state.settings.style.skin == 'Mint' or require('ui.theme').window(h.app.state.settings).theme == 'Mint',
        "A skin's name matches without regard to case.");
    h.fresh();
    command('/vg skin frameless');
    assert(h.app.state.settings.style.minimal == true, 'So does Frameless.');
    local before = #MOCK.printed;
    command('/vg theme Mint');
    local help = MOCK.printed[before + 1] or '';
    assert(help:find(' skin,', 1, true) and not help:find('theme', 1, true), 'The help line names skin, the command there is: ' .. help);
    local count = #MOCK.printed;
    h.fresh(function(s) s.alerts.muted = true; end);
    command('/vg mute');
    assert(MOCK.printed[count + 1] and MOCK.printed[count + 1]:find('Alerts are unmuted.', 1, true), '/vg mute says what it did: ' .. tostring(MOCK.printed[count + 1]));
end;

-- My order with nothing on it says what it does instead, on timers and on recasts.
do
    local line = 'Nothing is on My order yet, so rows go by name.';
    h.fresh(function(s) s.panels.self_buffs.enabled, s.panels.self_buffs.sort, s.panels.self_buffs.order = true, 'fixed', {}; end);
    h.on('self_buffs', 'show');
    h.draw();
    assert(h.says(line), 'An empty My order says rows go by name.');
    h.fresh(function(s) s.panels.self_buffs.enabled, s.panels.self_buffs.sort, s.panels.self_buffs.order = true, 'fixed', { 40 }; end);
    h.on('self_buffs', 'show');
    h.draw();
    assert(not h.says(line), 'My order with something on it needs no line.');
    h.fresh(function(s) s.panels.spell_recasts.enabled, s.panels.spell_recasts.sort, s.panels.spell_recasts.order = true, 'fixed', {}; end);
    h.on('spell_recasts', 'show');
    h.draw();
    assert(h.says(line), 'Recasts say it too.');
end;

-- A row names things the way the page does.
do
    local hud = require('ui.hud');
    local lines = hud.details({ domain = 'recast', kind = 'spell', effect = 10001, name = 'Cure', timing = 'server', remaining = 10, duration = 20, recast_id = 1 }, 1,
        { labels = { ['10001'] = 'Big heal' } });
    assert(type(lines) == 'table' and lines[1] == 'Big heal' or tostring(lines):find('Big heal', 1, true), 'Pointing at a renamed recast uses the new name.');
end;
return 'What can\'t work says why or goes, and each thing has one name';
