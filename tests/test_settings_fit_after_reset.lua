-- The default settings window on a small game window: 960 x 540, a quarter of a 1920 x 1080 screen. The default window
-- (960 x 680) is fitted to it as it opens. /vg reset puts the window's default size back, the next frame fits it again,
-- and the settings window's Undo then puts back what Reset all changed.
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
MOCK.screen = { 960, 540 };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
for _ = 1, 3 do MOCK.frame(.11); end;
local cb = app.callbacks;
local function settings() return app.state.settings; end;
local w = settings().window;
assert(w.width == 960 and w.height == 680, 'Fixture: the default window size.');
w.tab, w.open = 'Help', true;
local story = {};
local function status(what)
    local h, s = cb.history_status(), settings();
    story[#story + 1] = ('%s: window %dx%d, muted %s, Undo %d (%s), Redo %d'):format(what, s.window.width, s.window.height,
        tostring(s.alerts.muted == true), h.undo, tostring(h.undo_label), h.redo);
    return { undo = h.undo, muted = s.alerts.muted == true };
end;
local function frames(n) for _ = 1, n or 1 do MOCK.imgui_calls = {}; MOCK.frame(1 / 60); end; end;
local function click(label)
    MOCK.clicks[label] = true; frames(1);
    assert(MOCK.clicks[label] == nil, 'Fixture: ' .. label .. ' was drawn and clicked.');
    frames(2);
end;
frames(3);
local opened = status('opened the default 960x680 window on a 960x540 game');
click('Mute alerts##settings_mute');
status('after Mute alerts');
local event = { command = '/vg reset' }; MOCK.fire('command', event); assert(event.blocked, 'Fixture: /vg reset ran.');
frames(3);
local reset = status('after /vg reset and three frames');
click('Undo');
local one = status('after one Undo');
local text = table.concat(story, '\n');
MOCK.fire('unload');
MOCK.screen = nil;
assert(not reset.muted, 'Fixture: Reset all unmuted.\n' .. text);
assert(opened.undo == 0, 'Opening the default window on a 960x540 game makes no Undo step.\n' .. text);
assert(one.muted, 'One Undo puts back what Reset all changed.\n' .. text);
return 'Undo after Reset all on a small screen puts it back';
