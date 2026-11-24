-- A saved settings window bigger than the screen (the game now runs at a smaller resolution) is fitted to the screen as
-- it opens. That fit is Vantage's, not the player's: it is no Undo step, and undoing back past the player's own changes
-- keeps their Redo. Drives the whole app frame, with the settings window's own Mute alerts, Undo and Redo buttons clicked.
local SNAP = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {}, party = {}, entities = {} };
require('app_fixture')(SNAP);
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, update = function() end,
    status = function() return { active = false }; end, restore = function() return true; end, suspend = function() return true; end };
local imgui = require('imgui');
rawset(imgui, 'IsMouseClicked', function() return false; end);
rawset(imgui, 'IsAnyItemActive', function() return false; end);
rawset(imgui, 'IsPopupOpen', function() return false; end);
-- A fold opens as it was told to, so drawing Help changes nothing.
local next_open = false;
rawset(imgui, 'SetNextItemOpen', function(open) next_open = open; end);
rawset(imgui, 'CollapsingHeader', function() return next_open; end);
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
for _ = 1, 3 do MOCK.frame(.11); end;
local cb = app.callbacks;
local function settings() return app.state.settings; end;
assert(cb.history_status().undo == 0 and cb.history_status().redo == 0, 'Fixture: no steps yet.');
-- MOCK's screen is 1600 x 900. The saved window is from a bigger screen.
local w = settings().window;
w.x, w.y, w.width, w.height, w.tab, w.open = 0, 0, 2000, 1000, 'Help', true;
local story = {};
local function status(what)
    local h, s = cb.history_status(), settings();
    story[#story + 1] = ('%s: window %dx%d, muted %s, Undo %d (%s), Redo %d (%s)'):format(what, s.window.width, s.window.height,
        tostring(s.alerts.muted == true), h.undo, tostring(h.undo_label), h.redo, tostring(h.redo_label));
    return { undo = h.undo, redo = h.redo, undo_label = h.undo_label, muted = s.alerts.muted == true, width = s.window.width };
end;
local function frames(n) for _ = 1, n or 1 do MOCK.imgui_calls = {}; MOCK.frame(1 / 60); end; end;
local function click(label)
    MOCK.clicks[label] = true; frames(1);
    assert(MOCK.clicks[label] == nil, 'Fixture: ' .. label .. ' was drawn and clicked.');
    frames(2);
end;
frames(3);
local opened = status('opened, saved 2000x1000 on a 1600x900 screen');
click('Mute alerts##settings_mute');
local muted = status('after Mute alerts');
click('Undo');
local one = status('after one Undo');
click('Undo');
local two = status('after a second Undo');
click('Redo');
local redone = status('after Redo');
for _ = 1, 3 do click('Undo'); end;
local more = status('after three more Undos');
local text = table.concat(story, '\n');
MOCK.fire('unload');
assert(opened.width == 1600, 'Fixture: the window was fitted to the screen and saved so.\n' .. text);
assert(muted.muted and one.redo == 1 and not one.muted, 'Fixture: Mute alerts and its Undo work.\n' .. text);
assert(opened.undo == 0, 'Opening the window makes no Undo step the player never made.\n' .. text);
assert(two.redo >= 1, 'Undoing past the fit keeps the Redo of Mute alerts.\n' .. text);
assert(redone.muted, 'Redo brings Mute alerts back.\n' .. text);
assert(more.undo == 0, 'Undo runs out.\n' .. text);
return 'Fitting the settings window to the screen is no Undo step';
