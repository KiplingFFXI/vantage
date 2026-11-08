-- What can fail on every frame or packet says so once, however many fail together. A client whose patterns came up
-- short says so once, when the displays can draw. /vg reset says what it did, and a bad observation goes with its frame.
local store = require('core.store');
local SNAP = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 1, self_known = true, self_effects = {}, party = {}, entities = {} };
local found = { timers = true, map = true, hidden = true, event = true };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(SNAP); end,
    capabilities = function() return found; end };
package.loaded['core.observer'] = { read = function() return {}; end };
local hud, overhead = require('ui.hud'), require('core.overhead');
local draw, update, packet = function() end, overhead.update, overhead.packet;
hud.draw, hud.draw_notices = function(...) return draw(...); end, function() end;
require('ui.party_hud').draw = function() return 0, {}; end;
require('ui.native_party_hud').draw = function() return 0, {}; end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, update = function() end,
    status = function() return { active = false }; end, restore = function() return true; end, suspend = function() return true; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
local function said(text)
    local count = 0;
    for _, line in ipairs(MOCK.printed) do if line:find(text, 1, true) then count = count + 1; end; end;
    return count;
end;
local function command(text) local event = { command = text }; MOCK.fire('command', event); assert(event.blocked); end;
local function frames(count) for _ = 1, count do MOCK.frame(.1); end; end;
local MISSING = 'Part of this game client was not found';

MOCK.fire('load'); app.refresh(0); frames(3);
assert(app.state.ready, 'Fixture: the displays can draw.');
assert(said(MISSING) == 0, 'A client with everything found says nothing.');

-- Found short: once, and no more after that.
found.map, app.state.client_checked = false, nil;
frames(3);
assert(said(MISSING) == 1 and said('/vg report says which part.') == 1, 'A part not found is said, with where to look.');
frames(30);
assert(said(MISSING) == 1, 'It is said once.');
found.map = true;

-- Two parts failing on every frame: one line each, not one each per frame.
draw = function() error('Panel failed', 0); end;
overhead.update = function() error('Icons failed', 0); end;
frames(120);
assert(said('The display could not update. Panel failed') == 1, 'The display says so once.');
assert(said('Overhead icons could not be drawn. Icons failed') == 1, 'The overhead icons say so once.');

-- A reason that keeps changing is said at most every 5 seconds.
local count = 0;
draw = function() count = count + 1; error('Panel failed ' .. count, 0); end;
local before = said('The display could not update.');
frames(100);
local lines = said('The display could not update.') - before;
assert(lines >= 1 and lines <= 3, 'Ten seconds of new reasons take a few lines, not ' .. lines);
draw, overhead.update = function() end, update;

-- Two readers failing on every packet, the same way.
overhead.packet = function() error('Bad entity', 0); end;
require('core.dispel').packet = function() error('Bad magic', 0); end;
for _ = 1, 200 do MOCK.fire('packet_in', { id = 0x00D }); end;
assert(said('An entity update could not be read. Bad entity') == 1, 'The entity reader says so once.');
assert(said('The blue magic you have set could not be read. Bad magic') == 1, 'The blue magic reader says so once.');
overhead.packet = packet;
require('core.dispel').packet = function() end;

-- /vg reset says what it did, and Undo does step back over it.
command('/vg set style.font_size 20'); frames(1);
assert(app.state.settings.style.font_size == 20, 'Fixture: a change to reset.');
command('/vg reset');
assert(said('Reset all settings. /vg undo steps back one change.') == 1, 'A full reset is said.');
assert(app.state.settings.style.font_size ~= 20, 'Fixture: the reset took it.');
command('/vg undo');
assert(app.state.settings.style.font_size == 20, 'And Undo takes it back.');
app.state.settings.alerts.volume = 0.25;
command('/vg reset alerts');
assert(said('Reset alerts. /vg undo steps back one change.') == 1, 'A section reset is said.');
command('/vg reset alerts');
assert(said('Reset alerts.') == 2 and said('Reset alerts. /vg undo steps back one change.') == 1, 'One that changed nothing has no step to undo, so it says none.');
local lines = #MOCK.printed;
command('/vg reset typo');
assert(#MOCK.printed == lines + 1 and said('Reset typo') == 0, 'A section that does not exist says why, not that it was done.');

-- An observation that can't be read goes with its frame, so the refreshes after it work.
local durations, prepare = require('core.durations'), require('core.durations').prepare;
durations.prepare = function() error('Bad observation', 0); end;
app.state.queue = { { kind = 'apply', entity_id = 1001, effect = 33 } };
assert(not pcall(app.refresh, 100, true), 'Fixture: the refresh fails.');
durations.prepare = prepare;
assert(#app.state.queue == 0, 'What failed is not tried again.');
assert(pcall(app.refresh, 101, true), 'The next refresh works.');
return true;
