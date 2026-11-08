-- The Pet display starts clear of the recast panels, on every screen with room for it, and Apply size or Apply setup
-- re-spaces it with the panels while it's still where it started. Loading never moves it, and one the player moved or
-- anchored stays. It goes last, so it never moves a panel.
local defaults, presets, setup = require('ui.defaults'), require('setup_fixture'), require('ui.setup_defaults');
local hud, layout, pet = require('ui.hud'), require('ui.layout'), require('core.pet');
local share, starters = require('core.share'), require('core.starters');
local copy = require('core.store').copy;

local function overlap(a, b)
    return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height;
end;
local function options(size, width, height)
    return { size = size, skin = 'keep', matching = false, window_type = 1, screen_width = width, screen_height = height };
end;
local function fresh_on(width, height)
    local s = defaults.tidy(defaults.make());
    setup.place_fresh(s, { width = width, height = height });
    return s;
end;
-- The display with its name, HP, MP and TP and two recasts.
local function box(s) return { x = s.pet.x, y = s.pet.y, width = s.pet.width, height = 150 * s.style.scale }; end;
local function panel(s, id, rows, width, height)
    local p = s.panels[id];
    return { x = p.x, y = p.y, width = p.width, height = hud.bounds(p, s.style, rows, width, height).height };
end;
local function spot(s) return s.pet.x .. ', ' .. s.pet.y; end;
-- Its starting spot is clear of the fresh spots of the recast panels, so Reset this position is too.
local start, panels = pet.make(), defaults.make().panels;
for _, id in ipairs({ 'spell_recasts', 'ability_recasts', 'recasts' }) do
    assert(start.x >= panels[id].x + panels[id].width, 'It starts to the right of ' .. id .. ', however long that gets.');
end;
local rolls = defaults.make().rolls;
assert(start.y >= rolls.y + 150, 'It starts under the Phantom Roll display.');

-- A fresh install on any screen with room: on screen, and clear of every panel, the alert notices, the game's windows
-- and the Phantom Roll display.
for _, screen in ipairs({ { 1280, 720 }, { 1280, 800 }, { 1366, 768 }, { 1600, 900 }, { 1680, 1050 }, { 1920, 1080 }, { 1920, 1200 },
    { 2560, 1080 }, { 2560, 1440 }, { 3440, 1440 }, { 3840, 2160 } }) do
    local width, height = screen[1], screen[2];
    local s = fresh_on(width, height);
    local where = ' on ' .. width .. ' x ' .. height .. ', at ' .. spot(s);
    local rect = box(s);
    assert(rect.x >= 0 and rect.y >= 0 and rect.x + rect.width <= width and rect.y + rect.height <= height, 'It is on screen' .. where);
    for _, id in ipairs(defaults.panel_order) do
        assert(not overlap(rect, panel(s, id, 3, width, height)), 'It is clear of ' .. id .. where);
    end;
    local chat, corner = layout.chat_area(width, height), layout.native_corner(width, height);
    assert(not overlap(rect, chat) and not overlap(rect, corner), 'It is clear of the game\'s windows' .. where);
    local notice = { x = s.alerts.notice_x, y = s.alerts.notice_y, width = s.alerts.notice_width, height = 170 };
    assert(not overlap(rect, notice), 'It is clear of the alert notices' .. where);
    assert(not overlap(rect, layout.clamp({ x = s.rolls.x, y = s.rolls.y, width = s.rolls.width, height = 150 }, width, height)),
        'It is clear of the Phantom Roll display' .. where);
    -- From here up the screen has room for it at its starting spot, right of the recast panels however long they get.
    if width >= 1600 then
        assert(s.pet.x == start.x and s.pet.y == start.y, 'It stays at its starting spot' .. where);
    end;
end;

-- A screen with no room leaves it at its starting spot, where drawing keeps it on the screen.
local tiny = fresh_on(800, 600);
assert(tiny.pet.x == start.x and tiny.pet.y == start.y, 'With no room it keeps its starting spot, at ' .. spot(tiny));

-- A starter turns the recast panels and the Pet display on together, and they stay apart however long the lists get.
local s = assert(starters.apply(fresh_on(1920, 1080), 'pet'));
assert(s.pet.enabled and s.panels.spell_recasts.enabled and s.panels.ability_recasts.enabled, 'Fixture: the Pet starter turns all three on.');
for _, id in ipairs({ 'spell_recasts', 'ability_recasts' }) do
    assert(not overlap(box(s), panel(s, id, 12, 1920, 1080)), 'It is clear of a long ' .. id .. ' at ' .. spot(s));
end;

-- Loading keeps every saved spot.
local loaded = defaults.tidy({ pet = { x = 1240, y = 520 } });
assert(loaded.pet.x == 1240 and loaded.pet.y == 520, 'A save loads where it was.');

-- At a bigger size the panels are wider, and it keeps clear of the ones on screen.
for _, size in ipairs({ 'minimal_1_5x', 'minimal_2x' }) do
    local shown = fresh_on(1920, 1080);
    shown.panels.spell_recasts.enabled, shown.panels.ability_recasts.enabled = true, true;
    local built = presets.build(shown, options(size, 1920, 1080));
    assert(built.panels.spell_recasts.enabled and built.panels.ability_recasts.enabled, 'Fixture: the recast panels stay on.');
    for _, id in ipairs({ 'self_buffs', 'self_debuffs', 'target', 'spell_recasts', 'ability_recasts' }) do
        assert(not overlap(box(built), panel(built, id, 2, 1920, 1080)), 'At ' .. size .. ' it is clear of ' .. id .. ', at ' .. spot(built));
    end;
end;

-- Sizes up and back again end where a fresh install put it, and the same size twice moves nothing.
local first = fresh_on(1920, 1080);
local round = copy(first);
assert(presets.apply(round, options('minimal_1_5x', 1920, 1080)), 'Apply 1.5x.');
assert(round.pet.x ~= first.pet.x or round.pet.y ~= first.pet.y, 'Fixture: 1.5x moves it, to ' .. spot(round));
local at_1_5x = spot(round);
local again = presets.build(round, options('minimal_1_5x', 1920, 1080));
assert(spot(again) == at_1_5x, 'The same size again leaves it, not ' .. spot(again));
assert(presets.apply(round, options('minimal_2x', 1920, 1080)), 'Apply 2x.');
assert(presets.apply(round, options('minimal', 1920, 1080)), 'Apply 1x.');
assert(spot(round) == spot(first), 'Back at 1x it is where it started, not ' .. spot(round));

-- A spot a smaller screen gave it is Vantage's too, and it moves on or off.
for _, enabled in ipairs({ true, false }) do
    local moved_screen = fresh_on(1366, 768);
    moved_screen.pet.enabled = enabled;
    assert(moved_screen.pet.x ~= start.x, 'Fixture: 1366 x 768 places it somewhere else, at ' .. spot(moved_screen));
    assert(presets.apply(moved_screen, options('minimal', 1920, 1080)), 'Apply at 1920 x 1080.');
    assert(moved_screen.pet.x == start.x and moved_screen.pet.y == start.y, 'On the bigger screen it goes to its starting spot, not ' .. spot(moved_screen));
end;

-- One the player moved stays, and one on an anchor keeps its fallback spot.
local mine = fresh_on(1920, 1080);
mine.pet.x, mine.pet.y, mine.pet.enabled = 700, 700, true;
local after = presets.build(mine, options('minimal_1_5x', 1920, 1080));
assert(after.pet.x == 700 and after.pet.y == 700, 'One the player moved stays, not ' .. spot(after));
local anchored = fresh_on(1920, 1080);
anchored.pet.enabled, anchored.pet.anchor.to = true, 'screen';
after = presets.build(anchored, options('minimal_1_5x', 1920, 1080));
assert(after.pet.x == start.x and after.pet.y == start.y, 'One on an anchor stays, not ' .. spot(after));

-- It keeps clear of the Phantom Roll display and the party cooldown list, wherever the player put them.
for _, name in ipairs({ 'rolls', 'list' }) do
    local placed = fresh_on(1920, 1080);
    local display = name == 'rolls' and placed.rolls or placed.party_cooldowns.list;
    display.x, display.y = start.x, start.y - 20;
    after = presets.build(placed, options('minimal', 1920, 1080));
    local rect = { x = display.x, y = display.y, width = display.width, height = 150 };
    assert(not overlap(box(after), rect), 'It is clear of ' .. name .. ', at ' .. spot(after));
end;

-- A height the player set is the room it needs.
local tall = fresh_on(1920, 1080);
tall.rolls.x, tall.rolls.y = start.x, 800;
after = presets.build(tall, options('minimal', 1920, 1080));
assert(after.pet.x == start.x and after.pet.y == start.y, 'Fixture: its usual height fits above the Phantom Roll display, at ' .. spot(after));
tall.pet.height = 400;
after = presets.build(tall, options('minimal', 1920, 1080));
assert(after.pet.x ~= start.x or after.pet.y ~= start.y, '400 tall it does not, at ' .. spot(after));

-- Its automatic height grows with the size. The panels are out of the way here, turned off where the player put them.
local doubled = fresh_on(1920, 1080);
for _, id in ipairs(defaults.panel_order) do
    local p = doubled.panels[id];
    p.x, p.y, p.enabled = 0, 0, false;
end;
doubled.rolls.x, doubled.rolls.y = start.x, 720;
after = presets.build(doubled, options('minimal', 1920, 1080));
assert(after.pet.x == start.x and after.pet.y == start.y, 'Fixture: at 1x it fits above the Phantom Roll display, at ' .. spot(after));
after = presets.build(doubled, options('minimal_2x', 1920, 1080));
assert(not overlap(box(after), { x = start.x, y = 720, width = doubled.rolls.width, height = 150 }), 'At 2x it needs twice the room, at ' .. spot(after));

-- With no room an apply puts it at its starting spot too.
local cramped = fresh_on(1366, 768);
after = presets.build(cramped, options('minimal', 800, 600));
assert(after.pet.x == start.x and after.pet.y == start.y, 'With no room an apply goes to its starting spot, not ' .. spot(after));

-- An export's Add takes its spot whole over the starting spot, by every road, and leaves one the player chose.
local friend = fresh_on(1920, 1080);
friend.pet.x, friend.pet.y = 700, 640;
for _, road in ipairs({ { 'layout' }, { 'element', 'pet' }, { 'profile' } }) do
    local payload = assert(share.read(assert(share.export(friend, road[1], road[2], 'Tester'))));
    local got = assert(share.candidate(fresh_on(1920, 1080), payload, 'add'));
    assert(got.pet.x == 700 and got.pet.y == 640, road[1] .. ' Add takes the string\'s spot over the starting one, not ' .. spot(got));
    local chosen = fresh_on(1920, 1080);
    chosen.pet.x, chosen.pet.y = 900, 300;
    got = assert(share.candidate(chosen, payload, 'add'));
    assert(got.pet.x == 900 and got.pet.y == 300, road[1] .. ' Add keeps a spot the player chose, not ' .. spot(got));
end;

-- Where it goes, or whether it goes, moves no panel.
local function panel_spots(from)
    local out = {};
    for _, id in ipairs(defaults.panel_order) do out[#out + 1] = id .. ' ' .. from.panels[id].x .. ' ' .. from.panels[id].y; end;
    out[#out + 1] = 'notice ' .. from.alerts.notice_x .. ' ' .. from.alerts.notice_y;
    return table.concat(out, '; ');
end;
for _, size in ipairs({ 'minimal', 'minimal_1_5x', 'minimal_2x' }) do
    local flowing = presets.build(fresh_on(1920, 1080), options(size, 1920, 1080));
    local staying = fresh_on(1920, 1080);
    staying.pet.x, staying.pet.y = 700, 700;
    assert(panel_spots(flowing) == panel_spots(presets.build(staying, options(size, 1920, 1080))), 'No panel moves for it at ' .. size .. '.');
end;

return 'The Pet display starts clear of the recast panels';
