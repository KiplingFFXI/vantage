-- What can happen during the warmup, through vantage.lua with what each slow call costs (warmup_fixture.lua): a step
-- that fails is said once in chat in plain words (its name and error go to /vg report), skipped, and the displays still
-- draw; a new graphics device lets the art go and makes
-- it again over the next Presents, the displays waiting for it as at load, without saying the failure again; a
-- Vantage command and /vg report run every step still to run first; an unload lets every texture go, the half-made
-- art too, and keeps its times for the next load.
local F = require('warmup_fixture');
local L, W = F.L, F.W;
local warmup = require('core.warmup');
local store = require('core.store');
W.unit(0x100, 0x1000100, 'mob', 0, -5, { name = 'Goblin Mugger', hitbox = 1.2 });
W.target = 0x100;
F.save('Original FFXI', function(settings) settings.party_ui.enabled, settings.overhead.enabled = true, true; end);
F.device = 0x1000;
AshitaCore.GetDirect3DDevice = function() return F.device; end;
-- The stock face can't be made: its step fails.
require('ui.client_fonts').prepare = function() error('The client font pixels are missing.', 0); end;
F.watch('ui.hud', 'draw', 'panels');
F.watch('ui.native_party_hud', 'draw', 'party strips');
F.watch('ui.settings_window', 'draw', 'settings window');
F.watch('ui.overhead_icons', 'draw', 'overhead icons');
local function said(text)
    local count = 0;
    for _, line in ipairs(MOCK.printed) do if line:find(text, 1, true) then count = count + 1; end end
    return count;
end
local function left() return warmup.pending('start') or warmup.pending('assets') or warmup.pending('party') or warmup.pending('names'); end
local failure = 'Part of Vantage could not load (the client art and fonts), so it goes on without it. /vg report has the reason.';
local function strings(value, out)
    out = out or {};
    if type(value) == 'string' then out[#out + 1] = value;
    elseif type(value) == 'table' then for key, child in pairs(value) do strings(key, out); strings(child, out); end end
    return out;
end

local app = F.load();
for _ = 1, 3 do F.present(); end
assert(warmup.pending('assets') and F.up() > 0, 'Fixture: part of the art is up and the rest still to make.');

-- A new device three Presents in: everything up is let go and the art is made again before anything draws.
local before, reads = {}, F.reads;
for id in pairs(F.live) do before[#before + 1] = id; end
F.device = 0x2000;
local ms, ran = F.present();
for _, id in ipairs(before) do assert(not F.live[id], 'A new device lets every texture made for the old one go.'); end
assert(F.names(ran)[1] == 'assets.window', 'The art is made again from its first step: ' .. tostring(F.names(ran)[1]));
assert(ms < warmup._BUDGET + 7.07, 'Within the budget.');
while left() do assert(F.presents < 100, 'Fixture: the warmup ends.'); F.present(); end
assert(#F.early == 0 and F.first['panels'], 'Nothing drew before the art was made again, then the displays drew.');
assert(F.reads == reads + 5, 'The art was read again: the window frame in use, the font, the status icons and the two action files.');
assert(said(failure) == 1 and said('fonts.face') == 0 and said('The client font pixels are missing.') == 0,
    'The failed step is said once in chat, in plain words.');
assert(warmup.report().failed[1].name == 'fonts.face' and warmup.report().failed[1].problem == 'The client font pixels are missing.'
    and warmup.ready(), 'It is skipped, the report keeps its name and why, and the displays draw.');

-- A new device once the displays draw: they stop until the art is made again, and the failure isn't said again.
local drawn = F.draws['panels'];
F.device = 0x3000;
F.present();
assert(app.state.ready == false and F.draws['panels'] == drawn and #F.early == 0, 'The displays wait for the new art.');
local waited, drew_in = 1, nil;
while not app.state.ready do assert(waited < 20, 'Fixture: the art is made.'); ms, drew_in = F.present(); waited = waited + 1; end
assert(F.draws['panels'] == drawn + 1 and #F.early == 0 and #drew_in == 0,
    'They draw again in the Present after the art is done, which runs no step.');
assert(said(failure) == 1, 'The failure is not said again.');
assert(#F.during == 0, 'Drawing reads, uploads and searches nothing: ' .. table.concat(F.during, ', '));

-- A command during the warmup runs what is left first; a command that isn't Vantage's leaves the warmup be. The reads
-- are slow from here, so making the art again takes more than one Present.
F.READ = 3;
F.device = 0x4000;
F.present();
assert(warmup.pending('assets'), 'Fixture: the art is being made again.');
local other = L.command('/echo hello');
assert(other.blocked == false and warmup.pending('assets') and app.state.ready == false, 'A command that isn\'t ours waits for nothing.');
local opened = L.command('/vg');
assert(opened.blocked == true and not left() and app.state.ready == true and app.state.settings.window.open,
    'A Vantage command runs every step left, and the displays draw from the next Present.');
F.present();
assert(F.draws['panels'] == drawn + 2 and #F.early == 0, 'They do.');

-- /vg report during the warmup: every step has run before the report is made, and its startup section says so plainly.
F.device = 0x5000;
F.present();
assert(warmup.pending('assets'), 'Fixture: the art is being made again.');
assert(L.command('/vg report').blocked == true and not left(), '/vg report runs every step left first.');
assert(F.stages['command.report'] and F.stages['command.report'].count == 1 and F.stages['warmup.drain'],
    'The command and the drain are timed.');
local report = store.read(MOCK_INSTALL_PATH .. '/config/addons/vantage/reports/latest.json');
local own = report and report.performance and report.performance.stages and report.performance.stages['command.report'];
assert(own and own.count == 1 and own.last > 0, 'The report holds the time of the /vg report that wrote it, its drain too.');
local startup = report and report.startup;
assert(startup and startup.spread and startup.ready and startup.drains == 2 and startup.restarts == 4,
    'The report has the startup section: drains and restarts.');
assert(#startup.steps > 50 and #startup.presents == math.min(F.presents, 32) and startup.failed[1].name == 'fonts.face',
    ('It lists the steps, the Presents and the failure: %d %d'):format(#startup.steps, #startup.presents));
for _, text in ipairs(strings(startup)) do
    assert(not text:find('?', 1, true) and not text:lower():find('unknown', 1, true), 'The startup section never guesses: ' .. text);
end
assert(report.capabilities.timers == true and report.capabilities.hidden == true, 'The report\'s flags are found ones.');

-- An unload during the warmup: no step runs after it, everything up is let go, the half-made art too, and its times
-- are kept for the next load in this game.
local kept = MOCK.pattern_store(nil, 1234);
warmup._set_store(kept);
F.device = 0x6000;
F.present();
assert(warmup.pending('assets') and F.up() > 0, 'Fixture: part of the new art is up.');
reads = F.reads;
MOCK.fire('unload');
assert(F.up() == 0, 'Every texture is let go: ' .. F.up());
assert(warmup.drain() and F.reads == reads and #warmup.report().later == 0, 'Nothing runs after the unload.');
assert(kept.text and kept.text:match('^1;4d2;%d+%.%d+;%d+%.%d+$'), 'The unload keeps its times: ' .. tostring(kept.text));
warmup._set_store(nil);
return 'Failures, new devices, commands and unloads during the warmup';
