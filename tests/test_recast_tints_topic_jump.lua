-- The Recast tints topic goes to the tint fold on Recasts' Show, which shows only while a recast panel shows spells or
-- abilities (ui/recast_panel.lua). With none on, as a fresh install has it, the topic lands on Show with nothing to go to,
-- and nothing waits to open the fold on a later visit. A place a page doesn't draw is let go once the page has drawn.
-- Folds open only as SetNextItemOpen says, as in ImGui with ImGuiCond_Always.
local h = require('panel_fixture')();
local frame, window, imgui = h.panels, h.window, h.imgui;
local FOLD = "Tint recasts I can't use right now";
local TINT = FOLD .. '##Recast tints';
local TOPIC = 'Recast tints  /  Recasts';

local next_open, last_header;
local opened, scrolls = {}, {};
rawset(imgui, 'SetNextItemOpen', function(value) next_open = value; end);
rawset(imgui, 'CollapsingHeader', function(label)
    local open = next_open == true;
    next_open, last_header = nil, label;
    if open then opened[label] = true; end;
    return open;
end);
-- Each scroll is noted with the fold or heading drawn last before it.
rawset(imgui, 'SetScrollHereY', function() scrolls[#scrolls + 1] = last_header or '?'; end);
rawset(imgui, 'TextColored', function(_, text) last_header = text; end);
local function draw(click)
    opened, scrolls, last_header = {}, {}, nil;
    h.draw(click);
end;
local function jump()
    for index = 1, 255 do
        local name, value = debug.getupvalue(window.main_helpers.open_page, index);
        if not name then return nil; end;
        if name == 'jump_section' then return value; end;
    end;
end;
local function take_topic(text)
    h.typed['##find_settings'] = text;
    draw();
    assert(h.called('Selectable', TOPIC), 'Fixture: the topic is listed for ' .. text);
    draw(TOPIC);
end;

-- 1. Nothing shows spells or abilities: the topic lands on Show, and no jump waits.
h.fresh();
assert(not h.s.panels.spell_recasts.enabled and not h.s.panels.ability_recasts.enabled and h.s.recast_display == 'separate',
    'Fixture: a fresh install shows no spell or ability recasts.');
draw();
take_topic('tint');
draw();
local landed = ('landed on %s, search "%s", jump %s'):format(frame.context(), h.window.main_helpers.search[1], tostring(jump()));
assert(frame.context() == 'recasts/show' and jump() == nil, 'The topic left a jump waiting for a fold it can\'t show: ' .. landed);
assert(frame.route('Display', 'recasts', FOLD) == nil, 'The route gives a fold hidden now to go to.');

-- 2. Later, by the tab buttons and the header's On, with no search or link: the fold opens only as saved.
draw('Look##frame_tab'); draw();
draw('On##frame_display'); draw();
assert(h.s.panels.spell_recasts.enabled == true, 'Fixture: On turned Spell recasts on.');
draw('Show##frame_tab');
assert(not opened[TINT] and #scrolls == 0, ('Back on Show, the tint fold opened (%s) and the page scrolled %d time(s) to %s'):format(
    tostring(opened[TINT] == true), #scrolls, tostring(scrolls[1])));

-- 3. With Spell recasts on, the topic opens the fold and goes to it, once.
assert(frame.route('Display', 'recasts', FOLD) == TINT, 'The route gives the fold while it shows.');
h.typed['##find_settings'] = '';
draw();
take_topic('recast tints');
assert(opened[TINT] and scrolls[1] == TINT and jump() == nil, ('The topic opens the tint fold (%s) and goes to it (%s), and the jump is used (%s).')
    :format(tostring(opened[TINT] == true), tostring(scrolls[1]), tostring(jump())));
draw();
assert(#scrolls == 0, 'It goes there once.');

-- 4. Any place a page doesn't draw is let go after the page draws once, and a heading it draws is gone to.
window.main_helpers.open_page('Home', nil, 'A place not on this page');
draw();
assert(jump() == nil, 'A place the page didn\'t draw still waits: ' .. tostring(jump()));
window.main_helpers.open_page('Home', nil, 'Moving');
draw();
assert(scrolls[1] == 'Moving' and jump() == nil, 'A heading the page draws is gone to: ' .. tostring(scrolls[1]));
MOCK.fire('unload');
return 'The Recast tints topic leaves nothing waiting';
