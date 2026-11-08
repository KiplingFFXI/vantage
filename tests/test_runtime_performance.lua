local tracker = require('core.tracker').new();
local snapshot = { valid = true, id = 10, zone = 1, name = 'Self', self_known = true, self_revision = 1,
    self_effects = { { effect = 33, slot = 0, deadline = 10, raw_timer = 600 } }, party = {}, entities = {} };
tracker:reconcile(snapshot, 1);
tracker:observe({ { kind = 'apply', entity_id = 20, effect = 40, source = 10, duration = 9 } }, 1, snapshot);
local view = tracker:view(1, {}, snapshot);
tracker:drain_events();
local own, other;
for _, row in ipairs(view.rows) do if row.entity_id == 10 then own = row; else other = row; end end
local remapped = require('core.store').copy(own);
local version = tracker.version;
tracker:project(view, 1 + 1 / 60, { remapped });
assert(math.abs(own.remaining - (9 - 1 / 60)) < 0.000001 and own.remaining == remapped.remaining,
    'Countdowns advance on a rendered frame between full client samples');
assert(math.abs(other.elapsed - 1 / 60) < 0.000001);
assert(tracker.entities[10].entries[1].deadline == 10 and tracker.entities[10].entries[1].status == 'server');
assert(tracker.version == version and #tracker:drain_events() == 0, 'Projection does not mutate tracker evidence or emit observations');
tracker:project(view, 10, { remapped });
assert(own.remaining == 0 and own.status == 'server' and own.present and view.self_known);
assert(other.remaining == nil and other.status == 'unknown' and not other.present and #view.rows == 2,
    'An estimated deadline never confirms removal');
assert(remapped.remaining == 0 and remapped.status == 'server');
assert(tracker.entities[10].entries[1].deadline == 10 and tracker.entities[20].entries[1].status == 'estimated');
assert(#tracker:drain_events() == 0);
local kept_elapsed = other.elapsed;
tracker:project(view, 0 / 0); assert(other.elapsed == kept_elapsed, 'Invalid frame times leave projected data unchanged');

local store = require('core.store');
local live = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 1, level = 75,
    self_known = true, self_effects = { { effect = 33, slot = 0, deadline = 120, raw_timer = 7200 } }, party = {}, entities = {} };
local reads, roster_reads, projected_frames, stamp = 0, 0, 0, 500;
-- icons_moved is whether the next status packet changed your status icons.
local icons_moved = false;
package.loaded['core.client'] = {
    read = function() reads = reads + 1; return store.copy(live); end,
    load = function() end, capabilities = function() return {}; end,
    icons_changed = function() local moved = icons_moved; icons_moved = false; return moved; end,
};
package.loaded['core.observer'] = { read = function(event) return event.observations or {}; end };
package.loaded['core.roster'] = {
    read = function()
        roster_reads = roster_reads + 1;
        return { valid = live.valid, id = live.id, zone = live.zone,
            members = { { id = 1001, slot = 0, group = 1, active = true, stamp = stamp } } };
    end,
    target = function() error('Unexpected target command'); end,
};
package.loaded['ui.hud'] = {
    draw = function(v) projected_frames = projected_frames + 1; end,
    draw_notices = function() end, cancel_gesture = function() end,
};
package.loaded['ui.party_hud'] = { draw = function() return false, {}; end, cancel_layout_gesture = function() end };
package.loaded['ui.native_party_hud'] = { draw = function() return false, {}; end, cancel_layout_gesture = function() end };
-- The window opens Party list buffs for the Party & alliance page, as the real one does.
package.loaded['ui.panel_frame'] = { opened = function() return 'party_ui'; end };
package.loaded['ui.settings_window'] = { draw = function(s) if s.window.tab == 'Party & alliance' then s.window.tab = 'Display'; end; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
local function command(text) MOCK.fire('command', { command = text }); end
local function frame(dt) MOCK.frame(dt or 1 / 60); end
MOCK.now = 1; app.refresh(1);
assert(roster_reads == 0 and not app.state.roster_ready, 'A disabled party display does not read the roster');
local before = reads;
frame(); frame();
assert(reads == before and projected_frames == 2, 'Idle frames reuse the current snapshot');
assert(math.abs(app.state.view.rows[1].remaining - (120 - MOCK.now)) < 0.000001);
assert(app.state.party_subjects[1001].effects[1] == app.state.view.rows[1], 'Buff presentation shares an already copied display row');
command('/vg party show'); frame();
assert(reads == before + 1 and roster_reads == 1 and app.state.roster.members[1].stamp == 500,
    'Enabling the party display immediately validates the current roster');
for _, id in ipairs({ 0x063, 0x076, 0x0DD, 0x061, 0x0E1 }) do
    before = reads; stamp = stamp + 1;
    for _ = 1, 8 do MOCK.fire('packet_in', { id = id }); end
    frame();
    assert(reads == before + 1 and app.state.roster.members[1].stamp == stamp,
        'A burst of relevant packets coalesces into one read on the next frame: ' .. id);
end
-- Phoenix sends your 0x037 after any HP, MP or TP change too: one wakes a read only when your status icons changed.
before = reads; stamp = stamp + 1;
for _ = 1, 8 do MOCK.fire('packet_in', { id = 0x037 }); end
frame();
assert(reads == before, 'Status packets that change no icon wait for the next refresh.');
icons_moved = true;
for _ = 1, 8 do MOCK.fire('packet_in', { id = 0x037 }); end
frame();
assert(reads == before + 1 and app.state.roster.members[1].stamp == stamp, 'A burst with one icon change wakes one read.');
-- The party's HP updates, many a second in a fight, wait for the next refresh at its usual time.
before = reads;
for _ = 1, 8 do MOCK.fire('packet_in', { id = 0x0DF }); end
frame();
assert(reads == before, 'Party HP updates wait for the next refresh.');
frame(0.1);
assert(reads == before + 1, 'That refresh comes at its usual time.');
-- An entity leaving view wakes a read only when a display shows it or the Watch list holds it.
local function despawn(id) MOCK.fire('packet_in', { id = 0x00E, observations = { { kind = 'despawn', entity_id = id } } }); end;
local shown = app.state.view.subjects[1];
assert(shown, 'Fixture: a display shows someone.');
frame(0.1); before = reads;
despawn(0x1000999); frame();
assert(reads == before, 'An entity no display shows leaving view waits for the next refresh.');
frame(0.1); before = reads;
despawn(shown.id); frame();
assert(reads == before + 1, 'One a display shows wakes a read.');
frame(0.1); before = reads;
app.state.settings.watch_ids = { 0x1000999 };
despawn(0x1000999); frame();
assert(reads == before + 1, 'So does one the Watch list holds.');
app.state.settings.watch_ids = {};
-- Hits stop taking room once the queue is half full, so a wear-off behind them still fits.
frame(0.1);
local hits = {};
for i = 1, 200 do hits[i] = { kind = 'damage', entity_id = 0x1000999 }; end;
MOCK.fire('packet_in', { id = 0x028, observations = hits });
assert(#app.state.queue == 128, 'Hits fill half the queue at most: ' .. #app.state.queue);
MOCK.fire('packet_in', { id = 0x029, observations = { { kind = 'remove', entity_id = 0x1000999, effect = 2 } } });
assert(#app.state.queue == 129 and app.state.queue[129].kind == 'remove', 'A wear-off behind them still fits.');
frame(0.1);
assert(#app.state.queue == 0, 'The next refresh takes them all.');
before = reads;
MOCK.fire('packet_in', { id = 0x0DF, injected = true });
MOCK.fire('packet_in', { id = 0x0DD, blocked = true });
MOCK.fire('packet_in', { id = 0x017 });
frame(); assert(reads == before, 'Blocked, injected and unrelated packets do not force extra reads');
command('/vg party hide'); frame(0.11);
local hidden_reads = roster_reads;
frame(0.11); assert(roster_reads == hidden_reads);
-- The window appears on one frame, draws on the next and opens the panel, and the frame after reads the roster.
stamp = 900; command('/vg party config'); frame(); frame(); frame();
assert(roster_reads == hidden_reads + 1 and app.state.roster.members[1].stamp == 900, 'Party settings request fresh roster data');
app.state.settings.window.open = false; frame(0.11);
stamp = 950; hidden_reads = roster_reads;
assert(app.callbacks.export_report());
assert(roster_reads == hidden_reads + 1 and not app.state.roster_ready, 'An explicit report reads the roster without enabling background roster polling');
local report = assert(store.read(MOCK_INSTALL_PATH .. '/config/addons/vantage/reports/latest.json'));
assert(report.party_roster.members[1].stamp == 950);
stamp = 999; command('/vg party show'); frame();
assert(roster_reads == hidden_reads + 2 and app.state.roster.members[1].stamp == 999, 'A report cannot make later enable reuse an old roster');
live.zone = 103; MOCK.fire('packet_in', { id = 0x0DD }); frame();
assert(app.state.snapshot.zone == 103 and app.state.roster.zone == 103);
live.valid = false; icons_moved = true; MOCK.fire('packet_in', { id = 0x037 }); frame();
assert(not app.state.view.valid and #app.state.view.rows == 0 and not app.state.roster.valid);
local rule = require('ui.defaults').rule('color snapshot');
rule.chat, rule.sound, rule.flash = false, '', true;
rule.flash_color = { 1, 0.5, 0, 1 };
assert(app.callbacks.test_alert(rule));
local notice = app.alerts:view(MOCK.now)[1];
rule.flash_color[1] = 0;
assert(notice.flash_color[1] == 1, 'An existing notice retains its copied color while the editable rule changes');
assert(#MOCK.commands == 0, 'Polling and packet wakes never issue gameplay commands');
return 'Lightweight projection, guarded roster demand and packet-coalesced client refresh';
