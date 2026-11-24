-- /vg mute and /vg preview take on or off as /vg minimal does: off never turns them on, on never turns them off,
-- a choice already in place changes nothing and says so, and other words get the usage line. Lowering how many
-- history entries to keep trims the history to that many at the next recorded event.
local defaults = require('ui.defaults');
local SNAP = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 1, self_known = true, self_effects = {}, party = {}, entities = {} };
require('app_fixture')(SNAP);
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, update = function() end,
    status = function() return { active = false }; end, restore = function() return true; end, suspend = function() return true; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
local function command(text) local event = { command = text }; MOCK.fire('command', event); assert(event.blocked); end;
local function said(text)
    local count = #MOCK.printed;
    command(text);
    local out = {};
    for index = count + 1, #MOCK.printed do out[#out + 1] = MOCK.printed[index]; end
    return table.concat(out, ' | ');
end;
local function steps() return app.callbacks.history_status().undo; end;
MOCK.fire('load'); app.refresh(0);
for _ = 1, 3 do MOCK.frame(.11); end;
local s = app.state.settings;

-- Mute.
assert(not s.alerts.muted, 'Fixture: alerts start unmuted.');
local before = steps();
local reply = said('/vg mute off');
assert(not s.alerts.muted and steps() == before and reply:find('Alerts are unmuted.', 1, true),
    '/vg mute off while unmuted leaves them unmuted, adds no Undo step and says so: ' .. reply);
reply = said('/vg mute on');
assert(s.alerts.muted and steps() == before + 1 and reply:find('Alerts are muted.', 1, true), '/vg mute on mutes them: ' .. reply);
reply = said('/vg mute on');
assert(s.alerts.muted and steps() == before + 1, '/vg mute on again changes nothing: ' .. reply);
reply = said('/vg mute');
assert(not s.alerts.muted and steps() == before + 2, '/vg mute alone still toggles: ' .. reply);
reply = said('/vg mute please');
assert(not s.alerts.muted and reply:find('Usage: /vg mute [on|off]', 1, true), 'Other words get the usage line: ' .. reply);
reply = said('/vg mute on now');
assert(not s.alerts.muted and reply:find('Usage: /vg mute [on|off]', 1, true), 'So do extra words: ' .. reply);

-- Preview.
assert(not defaults.samples_showing(s), 'Fixture: no samples showing.');
before = steps();
reply = said('/vg preview off');
assert(not defaults.samples_showing(s) and steps() == before and reply:find('No samples are showing.', 1, true),
    '/vg preview off with none showing turns none on and says so: ' .. reply);
said('/vg preview on');
assert(defaults.samples_showing(s) and steps() == before + 1, '/vg preview on shows them.');
reply = said('/vg preview on');
assert(defaults.samples_showing(s) and steps() == before + 1 and reply:find('Samples are showing.', 1, true),
    '/vg preview on again changes nothing and says so: ' .. reply);
said('/vg preview off');
assert(not defaults.samples_showing(s) and steps() == before + 2, '/vg preview off ends them.');
said('/vg preview');
assert(defaults.samples_showing(s), '/vg preview alone still toggles.');
said('/vg preview');
reply = said('/vg preview maybe');
assert(not defaults.samples_showing(s) and reply:find('Usage: /vg preview [on|off]', 1, true), 'Other words get the usage line: ' .. reply);
-- With one panel showing its own samples, on shows them on every other display that is on too.
local panel;
for _, id in ipairs(defaults.panel_order) do if defaults.panel_enabled(s, id) then panel = id; break; end end
assert(panel, 'Fixture: a timer panel is on.');
s.overhead.enabled = true;
defaults.sample_panel(s, panel, true);
assert(defaults.samples_showing(s) and not s.preview and not s.overhead.preview, 'Fixture: one panel shows its own samples.');
before = steps();
reply = said('/vg preview on');
assert(s.preview and s.overhead.preview and steps() == before + 1,
    '/vg preview on with one panel showing its own shows them on every display that is on: ' .. reply);
reply = said('/vg preview on');
assert(steps() == before + 1 and reply:find('Samples are showing.', 1, true), 'Then on again changes nothing: ' .. reply);
said('/vg preview off');
assert(not defaults.samples_showing(s) and steps() == before + 2, 'and off ends them.');

-- The history keeps no more than it is set to keep, even after the setting is lowered.
s.diagnostics.record = true;
app.state.report = {};
for i = 1, 8 do app.state.report[i] = { kind = 'note', n = i }; end
s.diagnostics.max_entries = 3;
local tracker = app.tracker;
assert(tracker and tracker.drain_events, 'Fixture: the app hands on its tracker.');
local drain = tracker.drain_events;
tracker.drain_events = function(self, ...)
    local list = drain(self, ...);
    list[#list + 1] = { kind = 'apply', effect = 40 };
    return list;
end;
app.refresh(10);
tracker.drain_events = drain;
assert(#app.state.report == 3, 'The history is trimmed to 3 entries: ' .. #app.state.report);
assert(app.state.report[3].effect == 40, 'The newest entry is kept.');
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return true;
