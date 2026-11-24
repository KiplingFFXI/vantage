-- The player drags the settings window's ImGui resize grip to the screen's right edge. ImGui keeps the grip under the
-- mouse at the offset it was taken at, so the window ends a few pixels past the edge, and on the release frame Vantage
-- moves it back on screen. That resize is still the player's own: one Undo step, which Undo puts back.
local SNAP = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {}, party = {}, entities = {} };
require('app_fixture')(SNAP);
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, update = function() end,
    status = function() return { active = false }; end, restore = function() return true; end, suspend = function() return true; end };
local imgui = require('imgui');
rawset(imgui, 'IsMouseClicked', function() return false; end);
rawset(imgui, 'IsAnyItemActive', function() return false; end);
rawset(imgui, 'IsPopupOpen', function() return false; end);
local next_open = false;
rawset(imgui, 'SetNextItemOpen', function(open) next_open = open; end);
rawset(imgui, 'CollapsingHeader', function() return next_open; end);
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
for _ = 1, 3 do MOCK.frame(.11); end;
local cb = app.callbacks;
local function settings() return app.state.settings; end;
local function frames(n) for _ = 1, n or 1 do MOCK.imgui_calls = {}; MOCK.frame(1 / 60); end; end;
local w = settings().window;
w.tab, w.open = 'Help', true;
frames(3);
local function where(s) return ('%d,%d %dx%d'):format(s.window.x, s.window.y, s.window.width, s.window.height); end;
local start = where(settings());
assert(start == '100,80 960x680' and cb.history_status().undo == 0, 'Fixture: the default window, no steps: ' .. start);
-- The drag: the corner taken 10 px inside it and pulled to the screen's edge, so ImGui reports 1510 wide at x 100.
MOCK.mouse_down, MOCK.window_size = true, { 1510, 700 };
frames(1);
assert(where(settings()) == start, 'Fixture: nothing is saved while the mouse is held.');
MOCK.mouse_down, MOCK.window_size = false, nil;
frames(2);
local h = cb.history_status();
local after = ('after the drag: window %s, Undo %d (%s)'):format(where(settings()), h.undo, tostring(h.undo_label));
assert(where(settings()) == '90,80 1510x700', 'The window was moved back on screen and saved: ' .. after);
assert(h.undo == 1 and h.undo_label == 'Settings window size', 'The player\'s resize is an Undo step: ' .. after);
MOCK.clicks['Undo'] = true; frames(3);
assert(where(settings()) == start, 'Undo put the window back: ' .. where(settings()));
MOCK.fire('unload');
return 'A resize let go past the screen edge is an Undo step';
