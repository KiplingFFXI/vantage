-- /vg lock and /vg unlock change nothing on screen, so each says what it did.
local store = require('core.store');
local SNAP = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 1, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(SNAP); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
require('ui.party_hud').draw = function() return 0, {}; end;
require('ui.native_party_hud').draw = function() return 0, {}; end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, update = function() end,
    status = function() return { active = false }; end, restore = function() return true; end, suspend = function() return true; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
local function command(text) local event = { command = text }; MOCK.fire('command', event); assert(event.blocked); end;
MOCK.fire('load'); app.refresh(0);
for _ = 1, 3 do MOCK.frame(.11); end;
for text, wanted in pairs({ ['/vg unlock'] = 'Every display is unlocked. Hold Shift and drag one to move it.',
    ['/vg lock'] = 'Every display is locked.' }) do
    local count = #MOCK.printed;
    command(text);
    assert(#MOCK.printed == count + 1 and MOCK.printed[#MOCK.printed]:find(wanted, 1, true), text .. ' says what it did: ' .. tostring(MOCK.printed[#MOCK.printed]));
    assert(app.state.settings.rolls.locked == (text == '/vg lock'), 'Fixture: ' .. text .. ' did it.');
end;
return 'The lock commands say what they did';
