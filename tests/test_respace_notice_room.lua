-- The Size buttons and Put every display back leave the alert notices room at the size they draw at: Notice text size
-- when it is set, and Height times the size when that is set. What is placed after the notices keeps clear of them:
-- the timer panels that are off, the Pet display and the Phantom Roll display. With no spot that has room for them all,
-- the notices take the first spot with room for fewer while Height is Fit, and the whole room is kept for them there.
-- A Pet or Phantom Roll display with no spot whose start is under that room looks once more, past the spots kept for
-- panels that are off. When the player turns a panel on after either, the next Size press still moves the notices,
-- the panels and the display in the cases below, though not in every case. A display the player placed stays where
-- it is. So does one whose start isn't under the notices' room, when the player drags a panel onto it or turns one on.
local defaults, setup, store = require('ui.defaults'), require('ui.setup_defaults'), require('core.store');
local hud, customization, layout = require('ui.hud'), require('core.customization'), require('ui.layout');
local screen = { width = 1920, height = 1080 };
local function overlap(a, b)
    return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height;
end;
local function fresh()
    local s = defaults.tidy(defaults.make());
    setup.place_fresh(s, screen);
    return s;
end;
-- Where hud.draw_notices draws count notices of a line each, or its fixed height, from where they are now: each line
-- at the notices' text size, with 14 px of padding around each notice and 5 px after it.
local function notices(s, count)
    local alerts, scale = s.alerts, s.style.scale;
    local size = alerts.notice_text_size > 0 and alerts.notice_text_size or s.style.font_size;
    local width = math.min(alerts.notice_width * scale, screen.width);
    local height = math.min(alerts.notice_height > 0 and alerts.notice_height * scale or count * (size + 3 + 14 + 5) * scale, screen.height);
    return { x = math.min(alerts.notice_x, screen.width - width), y = math.max(0, math.min(alerts.notice_y, screen.height - height)),
        width = width, height = height };
end;
-- What is placed after the notices, each as tall as the placing counts it: one row of a panel that is off, and the
-- Pet and Phantom Roll displays with five and seven lines. A panel turned off that found no room keeps its fresh spot
-- and is left out, as nothing draws it.
local function after_notices(s)
    local out, start, scale = {}, defaults.make().panels, s.style.scale;
    for _, id in ipairs(defaults.panel_order) do
        local p = s.panels[id];
        if not defaults.panel_enabled(s, id) and not (p.x == start[id].x and p.y == start[id].y) then
            out[#out + 1] = { id = id, x = p.x, y = p.y, width = p.width, height = hud.bounds(p, s.style, 1, screen.width, screen.height).height };
        end;
    end;
    for id, lines in pairs({ pet = 5, rolls = 7 }) do
        out[#out + 1] = { id = id, x = s[id].x, y = s[id].y, width = s[id].width,
            height = (s.style.title_size + 16 + lines * (s.style.font_size + 8)) * scale };
    end;
    return out;
end;
local function clear_of(s, box, when)
    for _, rect in ipairs(after_notices(s)) do
        assert(not overlap(rect, box), ('%s: %s at %s, %s keeps clear of the notices, %s px tall from %s, %s'):format(
            when, rect.id, rect.x, rect.y, box.height, box.x, box.y));
    end;
end;
-- The timer panels that are on, with a row each, keep clear of the notices too.
local function shown_clear_of(s, box, when)
    for _, id in ipairs(defaults.panel_order) do
        local p = s.panels[id];
        if defaults.panel_enabled(s, id) then
            local rect = { x = p.x, y = p.y, width = p.width, height = hud.bounds(p, s.style, 1, screen.width, screen.height).height };
            assert(not overlap(rect, box), ('%s: %s at %s, %s keeps clear of the notices, %s px tall from %s, %s'):format(
                when, id, p.x, p.y, box.height, box.x, box.y));
        end;
    end;
end;

-- Notice text size 48, then Size 2x: the room for four notices fits nowhere clear of the chat log, but the room for
-- three fits where they start, so they stay there and the whole room is kept for them. Four notices draw 560 px tall.
-- That room leaves no spot for the Phantom Roll display, so it looks once more past the spots kept for panels that are
-- off.
local s = fresh();
s.alerts.notice_text_size = 48;
local old = store.copy(s);
s.style.scale = 2;
setup.respace(old, s, screen);
assert(s.alerts.notice_x == 985 and s.alerts.notice_y == 10, 'The notices stay where they start at 2x.');
clear_of(s, notices(s, 4), 'Size 2x with Notice text size 48');

-- Put every display back with Notice text size 48 and six notices shown at once: they draw 420 px tall at 1x.
s = fresh();
s.alerts.notice_text_size, s.alerts.max_notices = 48, 6;
s = customization.reset(s, 'displays');
setup.place_fresh(s, screen);
clear_of(s, notices(s, 6), 'Put every display back with Notice text size 48');

-- A fixed Height of 300 is 450 px at 1.5x, however few notices are up.
s = fresh();
s.alerts.notice_height = 300;
old = store.copy(s);
s.style.scale = 1.5;
setup.respace(old, s, screen);
clear_of(s, notices(s, 1), 'Size 1.5x with Height 300');

-- Notice text size 48, then Size 1.5x: the room for four notices fits where they start, so they stay there. It leaves
-- no spot for the Phantom Roll display, whose start is under it, so it looks once more past the spots kept for panels
-- that are off.
s = fresh();
s.alerts.notice_text_size = 48;
old = store.copy(s);
s.style.scale = 1.5;
setup.respace(old, s, screen);
assert(s.alerts.notice_x == 985 and s.alerts.notice_y == 10, 'The notices stay where they start at 1.5x.');
shown_clear_of(s, notices(s, 4), 'Size 1.5x with Notice text size 48');
clear_of(s, notices(s, 4), 'Size 1.5x with Notice text size 48');

-- On 1600 x 900, Notice text size 40, then Size 1.5x: the room for four notices fits nowhere, so they take the first
-- spot with room for fewer. Four notices of a line each cover no timer panel there, nor the Pet or Phantom Roll
-- display.
screen = { width = 1600, height = 900 };
s = fresh();
s.alerts.notice_text_size = 40;
old = store.copy(s);
s.style.scale = 1.5;
setup.respace(old, s, screen);
shown_clear_of(s, notices(s, 4), 'Size 1.5x with Notice text size 40 on 1600 x 900');
clear_of(s, notices(s, 4), 'Size 1.5x with Notice text size 40 on 1600 x 900');

-- The Pet display with five lines and the Phantom Roll display with seven, held on the screen as they are drawn.
local function display(s, id)
    local c, lines = s[id], id == 'rolls' and 7 or 5;
    return layout.clamp({ x = c.x, y = c.y, width = c.width,
        height = (s.style.title_size + 16 + lines * (s.style.font_size + 8)) * s.style.scale }, screen.width, screen.height);
end;
local function panel_box(s, id)
    local p = s.panels[id];
    return { x = p.x, y = p.y, width = p.width, height = hud.bounds(p, s.style, 1, screen.width, screen.height).height };
end;
-- Neither display covers a timer panel that is on.
local function displays_clear(s, when)
    for _, id in ipairs({ 'pet', 'rolls' }) do
        for _, panel in ipairs(defaults.panel_order) do
            if defaults.panel_enabled(s, panel) then
                assert(not overlap(display(s, id), panel_box(s, panel)), ('%s: the %s display at %s, %s covers %s at %s, %s'):format(
                    when, id == 'pet' and 'Pet' or 'Phantom Roll', s[id].x, s[id].y, defaults.panel_names[panel],
                    s.panels[panel].x, s.panels[panel].y));
            end;
        end;
    end;
end;
local function press(s, scale)
    local before = store.copy(s);
    s.style.scale = scale;
    setup.respace(before, s, screen);
end;

-- Size 2x leaves the Phantom Roll display no spot under the notices' room, so it takes the one kept for Party members'
-- timers and Watched enemy timers, which are off. With one or both turned on, the next Size press moves it clear.
screen = { width = 1920, height = 1080 };
for _, turned_on in ipairs({ { 'party' }, { 'party', 'watch' } }) do
    s = fresh();
    press(s, 2);
    local names = {};
    for _, id in ipairs(turned_on) do
        names[#names + 1] = defaults.panel_names[id];
        assert(overlap(display(s, 'rolls'), panel_box(s, id)), 'At 2x the Phantom Roll display is on the spot kept for ' .. names[#names] .. '.');
        s.panels[id].enabled = true;
    end;
    press(s, 1.5);
    displays_clear(s, ('Size 2x, then %s on, then Size 1.5x'):format(table.concat(names, ' and ')));
end;

-- On 1600 x 900 with Notice text size 40, Size 1.5x puts the Pet display on the spot kept for Item recasts. Turning on
-- Ability recasts, which isn't under either display, changes where the next press would put them, and it still moves
-- them clear.
screen = { width = 1600, height = 900 };
for _, scale in ipairs({ 1, 2 }) do
    s = fresh();
    s.alerts.notice_text_size = 40;
    press(s, 1.5);
    assert(overlap(display(s, 'pet'), panel_box(s, 'item_recasts')), 'At 1.5x the Pet display is on the spot kept for Item recasts.');
    s.panels.ability_recasts.enabled = true;
    press(s, scale);
    displays_clear(s, ('Size 1.5x with Notice text size 40 on 1600 x 900, then Ability recasts on, then Size %sx'):format(scale));
end;

-- The same with Spell recasts turned on too. Ability recasts had no spot at 1.5x and is still at its fresh spot, so only
-- Spell recasts shows as turned on since. The next Size press still moves the Pet display clear.
for _, scale in ipairs({ 1, 2 }) do
    s = fresh();
    s.alerts.notice_text_size = 40;
    press(s, 1.5);
    assert(overlap(display(s, 'pet'), panel_box(s, 'item_recasts')), 'At 1.5x the Pet display is on the spot kept for Item recasts.');
    s.panels.spell_recasts.enabled, s.panels.ability_recasts.enabled = true, true;
    press(s, scale);
    displays_clear(s, ('Size 1.5x with Notice text size 40 on 1600 x 900, then Spell recasts and Ability recasts on, then Size %sx'):format(scale));
end;

-- With every timer panel off, Size 2x puts the Phantom Roll display on the spots kept for Self buffs, Self debuffs and
-- Item recasts. With just those three turned on, no other panel is on to turn off with them, and the next Size press
-- still moves it clear.
screen = { width = 1920, height = 1080 };
s = fresh();
for _, id in ipairs(defaults.panel_order) do s.panels[id].enabled = false; end;
press(s, 2);
for _, id in ipairs({ 'self_buffs', 'self_debuffs', 'item_recasts' }) do
    assert(overlap(display(s, 'rolls'), panel_box(s, id)), 'At 2x the Phantom Roll display is on the spot kept for ' .. defaults.panel_names[id] .. '.');
    s.panels[id].enabled = true;
end;
press(s, 1);
displays_clear(s, 'Every timer panel off, Size 2x, then Self buffs, Self debuffs and Item recasts on, then Size 1x');

-- On 1280 x 720, Size 2x has no spot with room for every notice, so they take the first spot with room for fewer. That
-- keeps the spot for Item recasts, which is off, under the Phantom Roll display's start. With Item recasts turned on,
-- the next Size press still knows the notices and Item recasts as Vantage's and moves them, and neither display covers
-- a panel that is on.
screen = { width = 1280, height = 720 };
s = fresh();
press(s, 2);
assert(s.alerts.notice_x == 40 and s.alerts.notice_y == 229, 'On 1280 x 720 at 2x the notices take the spot with room for fewer.');
assert(overlap(display(s, 'rolls'), panel_box(s, 'item_recasts')), 'At 2x the spot kept for Item recasts is under the Phantom Roll display.');
s.panels.item_recasts.enabled = true;
press(s, 1.5);
displays_clear(s, 'On 1280 x 720, Size 2x, then Item recasts on, then Size 1.5x');

-- On 1680 x 1050 with Notice text size 40, Size 2x does the same and keeps the spot for Watched enemy timers under the
-- Phantom Roll display's start. With that panel turned on, the next Size press still moves it.
screen = { width = 1680, height = 1050 };
s = fresh();
s.alerts.notice_text_size = 40;
press(s, 2);
assert(s.alerts.notice_x == 40 and s.alerts.notice_y == 315, 'On 1680 x 1050 at 2x the notices take the spot with room for fewer.');
assert(overlap(display(s, 'rolls'), panel_box(s, 'watch')), 'At 2x the spot kept for Watched enemy timers is under the Phantom Roll display.');
s.panels.watch.enabled = true;
press(s, 1.5);
displays_clear(s, 'On 1680 x 1050 with Notice text size 40, Size 2x, then Watched enemy timers on, then Size 1.5x');

-- On 1920 x 1080 with Notice text size 48, the player drags the Pet display across after Size 2x, to a spot with no
-- timer panel under it. The next Size press leaves it where the player put it.
screen = { width = 1920, height = 1080 };
s = fresh();
s.alerts.notice_text_size = 48;
press(s, 2);
assert(s.pet.x == 670 and s.pet.y == 229, 'At 2x with Notice text size 48 the Pet display is at 670, 229.');
s.pet.x = 1565;
press(s, 1);
assert(s.pet.x == 1565 and s.pet.y == 229, ('The Pet display the player put at 1565, 229 stays there after Size 1x, not at %s, %s.'):format(s.pet.x, s.pet.y));

-- On 1920 x 1080, Size 1.5x has room for every notice and puts the Phantom Roll display at 1300, 761. The player drags
-- Target timers or Self buffs onto it. The room fits and its start isn't under it, so the next Size press leaves it
-- where it is.
for _, dragged in ipairs({ 'target', 'self_buffs' }) do
    s = fresh();
    press(s, 1.5);
    assert(s.rolls.x == 1300 and s.rolls.y == 761, 'At 1.5x the Phantom Roll display is at 1300, 761.');
    s.panels[dragged].x, s.panels[dragged].y = 1300, 761;
    press(s, 1.5);
    assert(s.rolls.x == 1300 and s.rolls.y == 761, ('With %s dragged onto it, the Phantom Roll display stays at 1300, 761 after Size 1.5x, not at %s, %s.'):format(
        defaults.panel_names[dragged], s.rolls.x, s.rolls.y));
end;

-- The same with no drag: Size 1.5x puts the Pet display at 1615, 520, and the player turns Item recasts on. The room
-- fits and the Pet display's start isn't under it, so Size 1x leaves the Pet display there.
s = fresh();
press(s, 1.5);
assert(s.pet.x == 1615 and s.pet.y == 520, 'At 1.5x the Pet display is at 1615, 520.');
s.panels.item_recasts.enabled = true;
press(s, 1);
assert(s.pet.x == 1615 and s.pet.y == 520, ('With Item recasts turned on, the Pet display stays at 1615, 520 after Size 1x, not at %s, %s.'):format(s.pet.x, s.pet.y));
