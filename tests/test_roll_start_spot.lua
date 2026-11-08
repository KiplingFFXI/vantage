-- The Phantom Roll display starts clear of the recast panels with two rolls up, on every screen with room for it, and
-- Apply size or Apply setup re-spaces it with the panels while it's still where it started. Loading never moves it, and
-- one the player moved or anchored stays. It goes after the Pet display, so it moves neither a panel nor the Pet display.
local defaults, presets, setup = require('ui.defaults'), require('setup_fixture'), require('ui.setup_defaults');
local hud, layout, pet, rolls = require('ui.hud'), require('ui.layout'), require('core.pet'), require('core.rolls');
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
-- What ui/roll_display.lua draws for two rolls with every line on.
local function two_rolls(s)
    local style = s.style;
    local scale = style.scale;
    local font_size = style.font_size * scale;
    local first = math.max(math.floor(style.icon_size * 0.75 + 0.5) * scale, math.floor(font_size * 1.35 + 0.5) + 4 * scale);
    local heading = ((style.title_size > 0 and style.title_size or style.font_size) + 10) * scale;
    return heading + 4 * scale + 2 * (first + 3 * (font_size + 4 * scale) + 6 * scale);
end;
local function box(s) return { x = s.rolls.x, y = s.rolls.y, width = s.rolls.width, height = two_rolls(s) }; end;
local function panel(s, id, rows, width, height)
    local p = s.panels[id];
    return { x = p.x, y = p.y, width = p.width, height = hud.bounds(p, s.style, rows, width, height).height };
end;
local function spot(s) return s.rolls.x .. ', ' .. s.rolls.y; end;
-- Its starting spot is clear of the fresh spots of the recast panels, so Reset this position is too.
local start, panels = rolls.make(), defaults.make().panels;
for _, id in ipairs({ 'spell_recasts', 'ability_recasts', 'recasts' }) do
    assert(start.x >= panels[id].x + panels[id].width, 'It starts to the right of ' .. id .. ', however long that gets.');
end;
local fresh = defaults.tidy(defaults.make());
assert(start.y + two_rolls(fresh) <= pet.make().y, 'Two rolls end above the Pet display.');

-- A fresh install on any screen with room: on screen, and clear of every panel, the alert notices, the game's windows
-- and the Pet display.
for _, screen in ipairs({ { 1366, 768 }, { 1600, 900 }, { 1680, 1050 }, { 1920, 1080 }, { 1920, 1200 },
    { 2560, 1080 }, { 2560, 1440 }, { 3440, 1440 }, { 3840, 2160 } }) do
    local width, height = screen[1], screen[2];
    local s = fresh_on(width, height);
    local where = ' on ' .. width .. ' x ' .. height .. ', at ' .. spot(s);
    local rect = box(s);
    assert(rect.x >= 0 and rect.y >= 0 and rect.x + rect.width <= width and rect.y + rect.height <= height, 'It is on screen' .. where);
    -- With every display counted 1366 wide leaves room for the panels' second row, not their third.
    for _, id in ipairs(defaults.panel_order) do
        assert(not overlap(rect, panel(s, id, width < 1600 and 2 or 3, width, height)), 'It is clear of ' .. id .. where);
    end;
    local chat, corner = layout.chat_area(width, height), layout.native_corner(width, height);
    assert(not overlap(rect, chat) and not overlap(rect, corner), 'It is clear of the game\'s windows' .. where);
    local notice = { x = s.alerts.notice_x, y = s.alerts.notice_y, width = s.alerts.notice_width, height = 170 };
    assert(not overlap(rect, notice), 'It is clear of the alert notices' .. where);
    assert(not overlap(rect, layout.clamp({ x = s.pet.x, y = s.pet.y, width = s.pet.width, height = 150 }, width, height)),
        'It is clear of the Pet display' .. where);
    -- From here up the screen has room for it at its starting spot.
    if width >= 1620 then
        assert(s.rolls.x == start.x and s.rolls.y == start.y, 'It stays at its starting spot' .. where);
    end;
    -- The Pet display keeps its own spot on the screens that have room for that.
    if width >= 1600 then
        assert(s.pet.x == pet.make().x and s.pet.y == pet.make().y, 'The Pet display stays at its starting spot' .. where);
    end;
end;

-- A screen with no room leaves it at its starting spot, where drawing keeps it on the screen.
for _, screen in ipairs({ { 800, 600 }, { 1280, 720 }, { 1280, 800 } }) do
    local tiny = fresh_on(screen[1], screen[2]);
    assert(tiny.rolls.x == start.x and tiny.rolls.y == start.y, 'With no room it keeps its starting spot, at ' .. spot(tiny));
end;

-- The Support starter turns the recast panels and the display on together, and they stay apart however long the lists get.
local s = assert(starters.apply(fresh_on(1920, 1080), 'support'));
assert(s.rolls.enabled and s.panels.spell_recasts.enabled and s.panels.ability_recasts.enabled, 'Fixture: the Support starter turns all three on.');
for _, id in ipairs({ 'spell_recasts', 'ability_recasts' }) do
    assert(not overlap(box(s), panel(s, id, 12, 1920, 1080)), 'It is clear of a long ' .. id .. ' at ' .. spot(s));
end;

-- Loading keeps every saved spot.
local loaded = defaults.tidy({ rolls = { x = 1240, y = 300 } });
assert(loaded.rolls.x == 1240 and loaded.rolls.y == 300, 'A saved spot loads where it was.');

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
local at_1_5x = spot(round);
local again = presets.build(round, options('minimal_1_5x', 1920, 1080));
assert(spot(again) == at_1_5x, 'The same size again leaves it, not ' .. spot(again));
assert(presets.apply(round, options('minimal_2x', 1920, 1080)), 'Apply 2x.');
assert(presets.apply(round, options('minimal', 1920, 1080)), 'Apply 1x.');
assert(spot(round) == spot(first), 'Back at 1x it is where it started, not ' .. spot(round));

-- A spot an earlier apply gave it is Vantage's too, so the next apply still spaces it.
local applied = fresh_on(1920, 1080);
applied.party_cooldowns.list.x, applied.party_cooldowns.list.y = start.x, start.y - 20;
assert(presets.apply(applied, options('minimal', 1920, 1080)), 'Apply 1x.');
local given = spot(applied);
assert(given ~= start.x .. ', ' .. start.y, 'Fixture: the list moves it, to ' .. given);
assert(presets.apply(applied, options('minimal_1_5x', 1920, 1080)), 'Apply 1.5x.');
assert(spot(applied) ~= given, 'At 1.5x it is spaced again, not left at ' .. given);
assert(presets.apply(applied, options('minimal', 1920, 1080)), 'Apply 1x.');
assert(spot(applied) == given, 'Back at 1x it is where the first apply put it, not ' .. spot(applied));

-- A spot a smaller screen gave it is Vantage's too.
local moved_screen = fresh_on(1366, 768);
assert(moved_screen.rolls.x ~= start.x, 'Fixture: 1366 x 768 places it somewhere else, at ' .. spot(moved_screen));
assert(presets.apply(moved_screen, options('minimal', 1920, 1080)), 'Apply at 1920 x 1080.');
assert(moved_screen.rolls.x == start.x and moved_screen.rolls.y == start.y, 'On the bigger screen it goes to its starting spot, not ' .. spot(moved_screen));

-- One the player moved stays, and one on an anchor keeps its fallback spot.
local mine = fresh_on(1920, 1080);
mine.rolls.x, mine.rolls.y, mine.rolls.enabled = 700, 700, true;
local after = presets.build(mine, options('minimal_1_5x', 1920, 1080));
assert(after.rolls.x == 700 and after.rolls.y == 700, 'One the player moved stays, not ' .. spot(after));
local anchored = fresh_on(1366, 768);
local held_x, held_y = anchored.rolls.x, anchored.rolls.y;
anchored.rolls.enabled, anchored.rolls.anchor.to = true, 'screen';
after = presets.build(anchored, options('minimal_1_5x', 1920, 1080));
assert(after.rolls.x == held_x and after.rolls.y == held_y, 'One on an anchor stays, not ' .. spot(after));

-- It keeps clear of the Pet display and the party cooldown list, wherever the player put them.
for _, name in ipairs({ 'pet', 'list' }) do
    local placed = fresh_on(1920, 1080);
    local display = name == 'pet' and placed.pet or placed.party_cooldowns.list;
    display.x, display.y = start.x, start.y - 20;
    after = presets.build(placed, options('minimal', 1920, 1080));
    local rect = { x = display.x, y = display.y, width = display.width, height = 150 };
    assert(not overlap(box(after), rect), 'It is clear of ' .. name .. ', at ' .. spot(after));
end;

-- A height the player set is the room it needs.
local tall = fresh_on(1920, 1080);
tall.rolls.height = 400;
after = presets.build(tall, options('minimal', 1920, 1080));
assert(after.rolls.x ~= start.x or after.rolls.y ~= start.y, '400 tall it does not fit above the Pet display, at ' .. spot(after));

-- With no room an apply puts it at its starting spot too.
local cramped = fresh_on(1366, 768);
after = presets.build(cramped, options('minimal', 800, 600));
assert(after.rolls.x == start.x and after.rolls.y == start.y, 'With no room an apply goes to its starting spot, not ' .. spot(after));

-- An export's Add takes its spot whole over the starting spot, by every road, and leaves one the player chose.
local friend = fresh_on(1920, 1080);
friend.rolls.x, friend.rolls.y = 700, 640;
for _, road in ipairs({ { 'layout' }, { 'element', 'rolls' }, { 'profile' } }) do
    local payload = assert(share.read(assert(share.export(friend, road[1], road[2], 'Tester'))));
    local got = assert(share.candidate(fresh_on(1920, 1080), payload, 'add'));
    assert(got.rolls.x == 700 and got.rolls.y == 640, road[1] .. ' Add takes the string\'s spot over the starting one, not ' .. spot(got));
    local chosen = fresh_on(1920, 1080);
    chosen.rolls.x, chosen.rolls.y = 900, 400;
    got = assert(share.candidate(chosen, payload, 'add'));
    assert(got.rolls.x == 900 and got.rolls.y == 400, road[1] .. ' Add keeps a spot the player chose, not ' .. spot(got));
end;

-- Where it goes, or whether it goes, moves no panel and not the Pet display.
local function other_spots(from)
    local out = {};
    for _, id in ipairs(defaults.panel_order) do out[#out + 1] = id .. ' ' .. from.panels[id].x .. ' ' .. from.panels[id].y; end;
    out[#out + 1] = 'notice ' .. from.alerts.notice_x .. ' ' .. from.alerts.notice_y;
    out[#out + 1] = 'pet ' .. from.pet.x .. ' ' .. from.pet.y;
    return table.concat(out, '; ');
end;
for _, size in ipairs({ 'minimal', 'minimal_1_5x', 'minimal_2x' }) do
    local flowing = presets.build(fresh_on(1920, 1080), options(size, 1920, 1080));
    local staying = fresh_on(1920, 1080);
    staying.rolls.x, staying.rolls.y = 700, 700;
    assert(other_spots(flowing) == other_spots(presets.build(staying, options(size, 1920, 1080))), 'Nothing else moves for it at ' .. size .. '.');
end;

return 'The Phantom Roll display starts clear of the recast panels';
