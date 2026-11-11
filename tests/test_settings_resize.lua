local defaults, window, imgui = require('ui.defaults'), require('ui.settings_window'), require('imgui');
local s, view = defaults.make(), require('ui.hud').sample(100);
s.window.open, s.window.tab = true, 'Help';
local clicked, active, popup, saves, before, after, label, geometry = false, false, false, 0, 0, 0, nil, nil;
imgui.IsMouseClicked = function() return clicked; end;
imgui.IsAnyItemActive = function() return active; end;
imgui.IsPopupOpen = function() return popup; end;
-- A fold opens as it was told to, so drawing Help changes nothing.
local next_open = false;
imgui.SetNextItemOpen = function(open) next_open = open; end;
imgui.CollapsingHeader = function() return next_open; end;
local cb = {
    shift = false,
    save = function() saves = saves + 1; return true; end,
    changed = function(stage, value, _, window_geometry)
        if stage == 'before' then before, label, geometry = before + 1, value, window_geometry; else after = after + 1; end;
    end,
};
MOCK.hovered = true;
-- What the window tells the skin about its resize grip each frame: true when ImGui draws none.
local skin, no_grip = require('ui.client_skin'), nil;
local paint_menu = skin.menu;
skin.menu = function(gui, look, kind, fixed)
    if kind == 'window' then no_grip = fixed; end
    return paint_menu(gui, look, kind, fixed);
end;
local function frame()
    MOCK.imgui_calls = {};
    no_grip = nil;
    window.draw(s, view, cb);
    clicked = false;
    assert(#MOCK.font_stack == 0);
end;
local function flags()
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Begin' and call[2] == 'Vantage##settings' then return call[4]; end; end;
    error('Settings window was not drawn.');
end;
local function press(x, y)
    cb.shift, MOCK.mouse_down, clicked, MOCK.mouse_x, MOCK.mouse_y = true, true, true, x, y;
    frame();
end;
local function release()
    MOCK.mouse_down = false;
    frame();
end;
frame();
assert(saves == 0);
assert(require('bit').band(flags(), ImGuiWindowFlags_NoResize) == 0 and no_grip == false,
    'Without Shift ImGui draws its resize grip, and the skin is told to leave room for it.');
press(1059, 759);
assert(require('bit').band(flags(), ImGuiWindowFlags_NoResize) ~= 0, 'Shift resizing suppresses the competing ordinary grip.');
assert(no_grip == true, 'With no grip drawn, the skin is told to paint the whole body, so no corner is left bare.');
MOCK.mouse_x, MOCK.mouse_y = 1159, 819;
frame();
assert(s.window.width == 960 and s.window.height == 680 and saves == 0, 'Shift resizing stays transient while held.');
assert(MOCK.next_size[1] == 1060 and MOCK.next_size[2] == 740, 'The window follows both resize axes.');
release();
assert(s.window.width == 1060 and s.window.height == 740);
assert(saves == 1 and before == 1 and after == 1 and label == 'Settings window layout', 'One completed drag produces one labeled Undo transaction and save.');
assert(geometry == true, 'The drag is marked as window geometry, so Undo puts the window back.');
frame(); assert(saves == 1, 'Idle frames do not repeat the save.');

press(100, 400);
MOCK.mouse_x = 50;
frame(); release();
assert(s.window.x == 50 and s.window.width == 1110 and s.window.y == 80 and s.window.height == 740, 'The left edge anchors the opposite edge without changing height.');
local saved = saves;
press(50, 400); release();
assert(saves == saved, 'Clicking a grip without moving does not add Undo or save.');

s.window.peek = true;
MOCK.mouse_x, MOCK.mouse_y = 50, 80;
frame();
assert(require('bit').band(flags(), ImGuiWindowFlags_NoInputs) == 0, 'The settings edge remains visible with Shift peek enabled.');
MOCK.mouse_x, MOCK.mouse_y = 400, 400;
frame();
assert(require('bit').band(flags(), ImGuiWindowFlags_NoInputs) ~= 0, 'Shift peek still works away from the edges.');
active = true; frame();
assert(require('bit').band(flags(), ImGuiWindowFlags_NoInputs) == 0, 'Editing a control suppresses peeking.');
active, s.window.peek = false, false;

view.context.chat_open = true;
press(1159, 819);
MOCK.mouse_x = 1259; frame(); release();
assert(s.window.width == 1110 and saves == saved, 'Typing in game blocks Shift resizing.');
view.context.chat_open, popup = false, true;
press(1159, 819);
MOCK.mouse_x = 1259; frame(); release();
assert(s.window.width == 1110 and saves == saved, 'A popup blocks starting a settings resize.');
popup = false;

cb.shift, MOCK.window_size, MOCK.mouse_down = false, { 1180, 760 }, true;
frame(); assert(s.window.width == 1110 and saves == saved, 'Ordinary resizing still defers persistence while the mouse is held.');
release();
assert(s.window.width == 1180 and s.window.height == 760 and saves == saved + 1 and label == 'Settings window size' and geometry == true);
MOCK.window_size = nil;
-- A move through ImGui saves the position as a change whose Undo leaves the window where it is.
local x0 = s.window.x;
saved, MOCK.mouse_down, MOCK.window_pos['Vantage##settings'] = saves, true, { x0 + 30, s.window.y };
frame(); release();
assert(s.window.x == x0 + 30 and saves == saved + 1 and label == 'Settings window position' and not geometry,
    'An ImGui move is a position change, not window geometry.');
MOCK.mouse_down, MOCK.window_pos['Vantage##settings'] = true, { x0, s.window.y };
frame(); release();
assert(s.window.x == x0);
MOCK.window_pos['Vantage##settings'] = nil;

press(1229, 839);
MOCK.mouse_x, MOCK.mouse_y = 5000, 5000;
frame(); release();
assert(s.window.x + s.window.width == 1600 and s.window.y + s.window.height == 900, 'Growth stops at the viewport edges.');
press(1599, 899);
MOCK.mouse_x, MOCK.mouse_y = 60, 90;
frame(); release();
assert(s.window.width == 560 and s.window.height == 400, 'Shrinking respects the settings minimum size.');

press(609, 479);
MOCK.mouse_x, MOCK.mouse_y = 709, 529;
frame();
saved = saves;
window.cancel_resize();
assert(saves == saved + 1 and s.window.width == 660 and s.window.height == 450, 'Lifecycle cancellation commits the last visible size once.');
window.cancel_resize(); assert(saves == saved + 1);
release();

s.window.width, s.window.height, s.window.x, s.window.y = 800, 500, 10, 20;
frame();
assert(MOCK.next_size[1] == 800 and MOCK.next_size[2] == 500 and MOCK.positions['Vantage##settings'][1] == 10,
    'Restored geometry applies to an already-open settings window.');
local replacement = defaults.make();
replacement.window.open, replacement.window.tab = true, 'Help';
press(809, 519);
MOCK.mouse_x = 900; frame();
saved = saves;
s = replacement; release();
assert(s.window.width == 960 and saves == saved, 'Changing settings owners discards a stale resize.');

s.window.peek = false;
saved = saves;
press(400, 400);
MOCK.mouse_x, MOCK.mouse_y = 470, 440;
frame();
assert(s.window.x == 100 and s.window.y == 80 and saves == saved, 'Shift movement stays transient while held.');
assert(MOCK.positions['Vantage##settings'][1] == 170 and MOCK.positions['Vantage##settings'][2] == 120);
release();
assert(s.window.x == 170 and s.window.y == 120 and s.window.width == 960 and s.window.height == 680);
assert(saves == saved + 1 and label == 'Settings window layout' and geometry == true, 'Shift movement saves one layout transaction.');
assert(window.blocks_input(s, 400, 400, true, false), 'A visible settings interior blocks underlying HUD input.');
s.window.peek = true;
assert(not window.blocks_input(s, 400, 400, true, false), 'A peeked interior allows HUD input.');
assert(window.blocks_input(s, 400, 135, true, false), 'A peek-enabled title bar blocks underlying HUD input.');
assert(window.blocks_input(s, 170, 400, true, false), 'A peek-enabled resize edge blocks underlying HUD input.');
press(400, 140);
MOCK.mouse_x, MOCK.mouse_y = 420, 150;
frame(); release();
assert(s.window.x == 190 and s.window.y == 130, 'The title bar Shift-moves while peek remains enabled.');
saved = saves;
press(400, 400); MOCK.mouse_x = 460; frame(); release();
assert(s.window.x == 190 and s.window.y == 130 and saves == saved, 'The peeked interior does not move the settings window.');
s.window.peek = false;
press(400, 400); release();
assert(saves == saved, 'Clicking the settings interior without movement does not create Undo.');
assert(not window.blocks_input(s, 1, 1, true, false), 'Settings input blocking is bounded to the window.');

cb.focused = false;
press(400, 400); MOCK.mouse_x = 500; frame(); release();
assert(s.window.x == 190 and s.window.y == 130 and saves == saved, 'An unfocused client cannot start a settings drag even if Shift remains reported.');
assert(require('bit').band(flags(), ImGuiWindowFlags_NoInputs) ~= 0);
cb.focused = true;
press(400, 400); MOCK.mouse_x = 420; frame();
cb.focused, MOCK.mouse_x = false, 700;
frame(); release();
assert(s.window.x == 210 and s.window.y == 130 and saves == saved + 1,
    'Losing focus saves the last foreground position once and ignores later mouse movement.');
s.window.peek, MOCK.mouse_x, MOCK.mouse_y = true, 400, 400;
frame();
assert(require('bit').band(flags(), ImGuiWindowFlags_NoBackground) == 0, 'Background Shift never peeks through settings.');
cb.focused = true;

MOCK.screen, cb.shift = { 480, 320 }, false;
frame();
assert(s.window.width == 480 and s.window.height == 320, 'A smaller viewport takes precedence over the ordinary minimum.');
assert(#MOCK.commands == 0);
