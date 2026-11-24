-- A refresh fills again the tables it hands on in place of new ones: what the recasts are read for, the queue of
-- observations, the roster that stands for no party list read, the alerts' options and their rules' names, and the
-- report's history while recording is off. Each still holds what this refresh gives it.
local store = require('core.store');
local snapshot = { valid = true, id = 1001, name = 'Aster', zone = 102, job = 1, self_known = true, self_effects = {}, party = {},
    entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
-- The first refresh reads the settings, which makes them new.
MOCK.now = 1; app.refresh(1);
local state, s = app.state, app.state.settings;
s.party_ui.enabled, s.party_cooldowns.enabled, s.window.open = false, false, false;
-- What the recast reader and the alerts were handed by the last refresh.
local recast_options, alert_options, names;
do
    local reader = require('core.recasts').new();
    local methods = getmetatable(reader).__index;
    local update = methods.update;
    methods.update = function(self, snap, now, options) recast_options = options; return update(self, snap, now, options); end;
end;
local update = app.alerts.update;
app.alerts.update = function(self, view, events, rules, now, options)
    alert_options, names = options, options.enrich_context;
    return update(self, view, events, rules, now, options);
end;
local now = 1;
local function refresh() now = now + 0.2; MOCK.now = now; app.refresh(now); end;
refresh();
local first = { recast = recast_options, queue = state.queue, roster = state.roster, alerts = alert_options, names = names,
    report = state.report };
refresh();
local second_queue = state.queue;
snapshot.chat_open = true;
refresh();
local failures = {};
local function check(ok, message) if not ok then failures[#failures + 1] = message; end; end;
check(recast_options == first.recast, 'The recasts are read for the same options table at each refresh.');
check(recast_options and recast_options.enabled == (recast_options.spells or recast_options.abilities or recast_options.items),
    'Those options are worked out again whole.');
check(second_queue ~= first.queue and state.queue == first.queue, 'The queue swaps between two tables.');
check(#state.queue == 0 and #second_queue == 0, 'The queue a refresh took is emptied for the next.');
check(state.roster == first.roster, 'With no party list read, the same roster stands in.');
check(state.roster.valid == false and #state.roster.members == 0 and state.roster.typing == true,
    'It says the chat line is open once it is.');
check(alert_options == first.alerts, 'The alerts get the same options table.');
check(alert_options.enabled == true and alert_options.watch_ids == s.watch_ids and alert_options.enrich ~= nil,
    'Those options hold this refresh\'s settings.');
check(names ~= nil and names == first.names, 'The rules\' names are kept in one table.');
check(state.report == first.report and #state.report == 0, 'The report history stays the same empty table while not recording.');
-- A rule's name comes and goes with the rule.
local rule = require('ui.defaults').rule('h');
rule.effect = 33;
s.alerts.rules = { rule };
refresh();
check(names == first.names and names[1] == 'Haste', 'A rule\'s effect name fills the kept table: ' .. tostring(names and names[1]));
s.alerts.rules = {};
refresh();
check(names == first.names and next(names) == nil, 'A rule taken away takes its name with it.');
-- A history left from recording goes once recording is off.
state.report[1] = { kind = 'gain' };
refresh();
check(#state.report == 0, 'Recording off empties the history.');
assert(#failures == 0, table.concat(failures, ' | '));
