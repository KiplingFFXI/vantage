-- Panels of their own in an alliance. Each group's own switch puts its buffs in a panel of its own, moved sideways away
-- from the game's list past the other groups' strips and panels, the strip gap clear, so no two cover each other.
-- Where the screen has no room sideways, a panel goes up past what it covers, and with no room there either the panels
-- beside the game's list share the screen's height, each still a line per member. Each switch is one Undo step, and the
-- lock stays as it is.
local defaults, store = require('ui.defaults'), require('core.store');
local elements, overlay = require('ui.elements'), require('ui.native_party_hud');
local hud = require('ui.party_hud');
local widget = require('ui.party_size_widget');
MOCK.screen = { 1920, 1080 };

-- The game's party list at the bottom right of a width-wide screen: the party's window, and each alliance window above
-- the one before, as the game stacks them. Rows are 14 px tall and 20 px apart, and each member has buffs effects.
-- shift moves the list across by part of a pixel, as a scaled game menu can.
local function alliance(count, buffs, width, shift)
    local roster, subjects = hud.sample(18, 100);
    for index = #roster.members, count + 1, -1 do table.remove(roster.members, index); end;
    local groups, last = {}, 1037;
    for group = 1, math.ceil(count / 6) do
        local first = last - 5 * 20;
        groups[group] = { x = width - 125 + (shift or 0), y = first, width = 106, height = 114, rows = {}, row_height = 14, pitch = 20,
            measured_by = 'rows' };
        last = first - 44;
    end;
    for _, member in ipairs(roster.members) do
        local frame = groups[member.group];
        frame.rows[member.slot] = { x = frame.x, y = frame.y + (member.slot % 6) * 20, width = 106, height = 14,
            slot = member.slot };
        local subject = subjects[member.id];
        subject.effects, subject.known = {}, true;
        for effect = 1, buffs do
            subject.effects[effect] = { effect = effect, name = 'Effect ' .. effect, kind = 'buff', remaining = 30, total = 60,
                status = 'estimated' };
        end;
    end;
    return roster, subjects, { available = true, groups = groups };
end;
local roster, subjects, game;
-- The timer panels' look, which the party list buffs wear, as fresh settings have it.
local style = defaults.make().style;
-- The strips and panels as the game draws them now, each recorded where it is drawn.
local function drawn(p)
    local plans = store.copy(overlay.plan(roster, subjects, p, game, MOCK.screen[1], MOCK.screen[2], nil, style));
    for _, plan in ipairs(plans) do elements.record('strip_' .. plan.group, plan); end;
    return plans;
end;
-- Every group's switch in turn, each placed against what is drawn by then.
local function in_turn(p)
    for group = 1, 3 do
        widget.place(p, group, overlay.rooms(p, game), style);
        drawn(p);
    end;
end;
local function overlap(a, b)
    return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height;
end;
-- Nothing drawn covers anything else drawn, and all of it is on the screen.
local function apart(plans, what)
    for index, plan in ipairs(plans) do
        assert(plan.x >= 0 and plan.y >= 0 and plan.x + plan.width <= MOCK.screen[1] and plan.y + plan.height <= MOCK.screen[2],
            what .. ': on the screen.');
        for other = index + 1, #plans do
            assert(not overlap(plan, plans[other]), what .. ': ' .. (plan.detached and 'the panel' or 'the strip') .. ' of group '
                .. plan.group .. ' clear of group ' .. plans[other].group .. '.');
        end;
    end;
end;
-- One line of 37 px icons for each of six members, with the countdown under each icon, in the timer panels' font,
-- which the party list buffs wear.
local sample = require('ui.party_defaults').make();
local look = require('ui.party_theme').party(sample, style);
local timer = math.ceil(require('ui.countdown_text').icon_metrics(look.font, '57', 37, sample.effects).height);
local least = 6 + 6 * (look.font_size + 2 + 3 + 37 + timer + 8);

-- The pages, in the real settings window.
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {},
    party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window, frame = require('ui.settings_window'), require('ui.panel_frame');
local status = app.callbacks.party_native_status;
app.callbacks.party_native_status = function()
    local value = status();
    value.geometry = game;
    return value;
end;
local view = { rows = {}, context = { valid = true, job = 3 } };
local function draw(page, tab, clicks)
    local s = app.state.settings;
    s.window.open, s.window.tab = true, page;
    if tab then frame.open('party_ui', tab); end;
    MOCK.imgui_calls = {};
    for label in pairs(clicks or {}) do MOCK.clicks[label] = true; end;
    window.draw(s, view, app.callbacks);
    assert(not next(MOCK.clicks), 'The control is on the page: ' .. tostring(next(MOCK.clicks)));
    MOCK.clicks = {};
end;
local function history() app.callbacks.save(); return app.callbacks.history_status(); end;
local function fresh()
    local s = defaults.tidy(defaults.make());
    s.party_ui.enabled, s.party_ui.effects.icon_size = true, 37;
    -- Countdowns start off; on here, so each icon has its countdown under it, as the sizes below count.
    s.party_ui.locked, s.party_ui.effects.timers = true, true;
    app.state.settings, app.state.history, app.state.redo, app.state.transaction = s, {}, {}, nil;
    return s;
end;

-- Icons fill the step beside the rows: six touching 20 px icons make a 120 px strip, 26 px from the game's list.
roster, subjects, game = alliance(18, 6, 1920);
local s = fresh();
local p = s.party_ui;
local strips = drawn(p);
assert(#strips == 3 and strips[1].x == 1649 and strips[1].width == 120 and not strips[2].detached,
    'Fixture: three strips of six touching 20 px icons beside the rows.');
-- An alliance of 18 at 1920x1080 with six buffs each, every switch in turn: the party's panel past the alliance strips,
-- and each one after it beside the panel before it, away from the game's list.
in_turn(p);
local panels = drawn(p);
assert(#panels == 3 and panels[1].detached and panels[2].detached and panels[3].detached, 'Every group is in a panel of its own.');
apart(panels, '18 members, one switch at a time');
assert(panels[1].x + panels[1].width + 26 == strips[2].x and panels[1].width == 420 and panels[1].y + panels[1].height == 1080,
    'The party\'s panel is past the alliance strips.');
for group = 2, 3 do
    local panel, inner = panels[group], panels[group - 1];
    assert(panel.width == 420 and panel.x + panel.width + 26 == inner.x and panel.y == inner.y,
        'Alliance ' .. (group - 1) .. ': beside the panel before it, away from the game\'s list.');
    assert(panel.content_height <= panel.height and p.groups[group].detached_x == panel.x, 'Every member\'s buffs show at its saved place.');
end;
local steps;

-- The party on its own, with both alliance strips beside the rows: its panel moves past them, clear of both.
s = fresh();
p = s.party_ui;
strips = drawn(p);
draw('Display', 'place', { ['Your party in a panel of its own##frame'] = true });
steps = history();
panels = drawn(p);
assert(#panels == 3 and panels[1].detached and not panels[2].detached and not panels[3].detached, 'Fixture: only the party moved.');
apart(panels, 'The party alone');
assert(panels[1].x + panels[1].width + 26 == strips[2].x and panels[1].y + panels[1].height == 1080 and panels[1].width == 420,
    'The party\'s panel moved by an alliance strip\'s width and the gap.');
assert(steps.undo == 1 and steps.undo_label == 'Your party in a panel of its own' and p.locked == true, 'One Undo step, still locked.');
-- Then Alliance 1 on its own: clear of the party's panel and the Alliance 2 strip.
draw('Display', 'place', { ['Alliance 1 in a panel of its own##frame'] = true });
panels = drawn(p);
assert(#panels == 3 and panels[1].detached and panels[2].detached and not panels[3].detached, 'Fixture: Alliance 1 moved too.');
apart(panels, 'Alliance 1 after the party');
assert(panels[2].x + panels[2].width + 26 == panels[1].x and history().undo == 2 and p.locked == true,
    'Alliance 1 is beside the party\'s panel, as one more Undo step.');

-- A narrower screen with no room for a third panel sideways: Alliance 2 goes back beside the game's list, above the
-- party's panel. Here both still fit whole.
MOCK.screen = { 1280, 1080 };
roster, subjects, game = alliance(18, 6, 1280);
p = fresh().party_ui;
strips = drawn(p);
in_turn(p);
panels = drawn(p);
apart(panels, '1280 px wide');
assert(panels[2].x + panels[2].width + 26 == panels[1].x and panels[3].x + panels[3].width == strips[3].x + strips[3].width,
    'Alliance 2 is back beside the list.');
assert(panels[1].y + panels[1].height == 1080 and panels[3].y + panels[3].height + 26 <= panels[1].y, 'Alliance 2 is above the party.');
for _, panel in ipairs(panels) do assert(panel.content_height <= panel.height, 'Nothing scrolls while both fit.'); end;
-- Twelve buffs each need two lines, so with the party's panel dragged beside the list there is no room above either:
-- the party and Alliance 2 take half the screen each, the party lowest, at least a line per member, and scroll.
roster, subjects, game = alliance(18, 12, 1280);
p = fresh().party_ui;
drawn(p);
widget.place(p, 1, overlay.rooms(p, game), style);
p.groups[1].detached_x = 709;
drawn(p);
widget.place(p, 2, overlay.rooms(p, game), style);
drawn(p);
widget.place(p, 3, overlay.rooms(p, game), style);
panels = drawn(p);
apart(panels, '1280 px wide, twelve buffs');
local share = math.floor((1080 - 26) / 2);
assert(panels[1].height == share and panels[3].height == share and panels[1].y == 1080 - share and panels[3].y == 1080 - 2 * share - 26,
    'Each takes half the screen.');
assert(share >= least and panels[1].content_height > share and panels[2].height == panels[2].content_height,
    'Still a line per member; only the two sharing scroll.');

-- Every group in a panel, then the party's switch off, then Alliance 2's off and on again while Locked. With Alliance 1's
-- panel moved to the middle there's no room sideways, so Alliance 2's panel goes up past the party's strip, at its full
-- height, and covers nothing.
roster, subjects, game = alliance(18, 6, 1280);
s = fresh();
p = s.party_ui;
drawn(p);
in_turn(p);
p.groups[1].native_detached, p.groups[3].native_detached, p.groups[2].detached_x = false, false, 263;
strips = drawn(p);
assert(not strips[1].detached and strips[2].detached and not strips[3].detached, 'Fixture: the party and Alliance 2 beside the rows.');
draw('Display', 'place', { ['Alliance 2 in a panel of its own##frame'] = true });
panels = drawn(p);
apart(panels, 'Alliance 2 on again');
assert(panels[3].detached and panels[3].x + panels[3].width == strips[1].x + strips[1].width and panels[3].height == least
    and panels[3].y + panels[3].height + 26 == strips[1].y, 'Alliance 2 is just above the party\'s strip, at its full height.');
assert(history().undo == 1 and p.locked == true, 'One Undo step, still locked.');

-- A panel placed by hand beside the list, smaller than a line per member: another group's switch with no room
-- sideways or above moves it to make room, and keeps its height.
s = fresh();
p = s.party_ui;
local mine, theirs = p.groups[1], p.groups[2];
mine.native_detached, mine.detached_x, mine.detached_y, mine.detached_width, mine.detached_height = true, 709, 300, 420, 300;
theirs.native_detached, theirs.detached_x, theirs.detached_y, theirs.detached_width, theirs.detached_height = true, 263, 570, 420, 510;
drawn(p);
draw('Display', 'place', { ['Alliance 2 in a panel of its own##frame'] = true });
panels = drawn(p);
apart(panels, 'A panel placed by hand');
assert(panels[1].x == 709 and panels[1].width == 420 and panels[1].height == 300 and panels[1].y + 300 == 1080,
    'The panel placed by hand keeps its size, at the bottom.');
assert(panels[2].x == 263 and panels[2].y == 570 and panels[3].x == 709 and panels[3].height == least
    and panels[3].y + panels[3].height + 26 == panels[1].y, 'Alliance 2 is above it, and Alliance 1 stays where it was.');
assert(history().undo == 1 and p.locked == true, 'One Undo step, still locked.');

-- A party alone with no alliance keeps the place it always got.
MOCK.screen = { 1920, 1080 };
roster, subjects, game = alliance(6, 6, 1920);
p = fresh().party_ui;
drawn(p);
widget.place(p, 1, overlay.rooms(p, game), style);
panels = drawn(p);
assert(#panels == 1 and panels[1].x == 1349 and panels[1].width == 420 and panels[1].height == least
    and panels[1].y == 1080 - least, 'Six members: 420 px wide at the strip\'s edge, moved up only to stay on the screen.');

-- The game's list a quarter pixel across: the strips beside it draw on whole pixels, and the party's panel, moved past
-- the alliance strips, is saved at a whole pixel.
roster, subjects, game = alliance(18, 6, 1920, 0.25);
p = fresh().party_ui;
strips = drawn(p);
assert(game.groups[2].x ~= math.floor(game.groups[2].x) and strips[2].x == math.floor(strips[2].x),
    'Fixture: the game\'s list is part of a pixel across, and the strips are on whole pixels.');
widget.place(p, 1, overlay.rooms(p, game), style);
panels = drawn(p);
apart(panels, 'A scaled menu');
assert(p.groups[1].detached_x == math.floor(p.groups[1].detached_x) and panels[1].x + panels[1].width + 26 <= strips[2].x,
    'The panel is at a whole pixel, still the gap clear of the strips.');

MOCK.fire('unload');
return 'Panels of their own in an alliance keep clear of each other and of the other groups\' strips';
