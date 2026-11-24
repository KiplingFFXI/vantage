-- A Required effect missing alert tells an effect once each time it goes missing (GUIDE.md, Alerts). A mute, an Undo,
-- /vg set, a reset of another part, a profile load or an import doesn't tell one still missing again, from the window
-- or by a command. Found and lost again, or a zone change, still tells it again. The window's controls run inside its
-- draw, as the real window's do, and each second goes through Present, so the notice and the chat line are the ones
-- the player gets.
package.loaded['core.performance'] = { now=function() return MOCK.now*1000; end, record=function() return true; end,
    add=function() return true; end, zone_begin=function() return true; end, zone_ready=function() return true; end,
    snapshot=function() return {}; end, origin_ms=0 };
local store = require('core.store');
local defaults = require('ui.defaults');
-- You, with no effects on, so Protect is missing the whole time.
local snapshot = { valid=true,id=1001,name='Tester',zone=102,job=1,job_name='WAR',self_known=true,
    self_effects={},party={},entities={} };
package.loaded['core.client'] = { read=function() return store.copy(snapshot); end, load=function() end };
package.loaded['core.observer'] = { read=function(e) return e.observations or {}; end };
package.loaded['ui.hud'] = { draw=function() end, draw_notices=function() end };
-- A control clicked on a frame runs inside that frame's draw, with the callbacks the app gives the window.
local click;
package.loaded['ui.settings_window'] = { draw=function(_, _, callbacks)
    if click then local run = click; click = nil; run(callbacks); end
end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
local function command(text) local e = {command=text}; MOCK.fire('command',e); return e; end

local seen, told, chats, scanned = {}, {}, {}, 0;
local function frame_to(t)
    while MOCK.now < t - 1e-9 do
        MOCK.frame(1);
        for _, notice in ipairs(app.state.view.notices) do
            if not seen[notice] and notice.event == 'missing' then seen[notice] = true; told[#told + 1] = MOCK.now; end
        end
        for index = scanned + 1, #MOCK.printed do
            if MOCK.printed[index]:find('Protect is missing on you.', 1, true) then chats[#chats + 1] = MOCK.now; end
        end
        scanned = #MOCK.printed;
    end
end
local function list(times) local out = {}; for i, t in ipairs(times) do out[i] = string.format('%g', t); end; return '[' .. table.concat(out, ',') .. ']'; end
local function click_on_next_frame(run) click = run; frame_to(MOCK.now + 1); assert(click == nil, 'Fixture: the window drew.'); end

MOCK.now = 0;
MOCK.fire('load'); app.refresh(0); command('/vg');
assert(app.state.settings.window.open, 'Fixture: the window is open.');
-- An alert as New alert makes it, set to Required effect missing for Protect on you, with a chat line. Its minimum time
-- between repeats stays at 10 s and Repeat every stays off.
local rule = defaults.rule('missing'); rule.name = 'Protect missing'; rule.event = 'missing'; rule.effect = 40;
rule.effect_name = 'Protect'; rule.chat = true;
assert(rule.cooldown == 10 and rule.repeat_seconds == 0, 'Fixture: the usual alert.');
app.state.settings.alerts.rules = { rule };
frame_to(10);
assert(#told == 1 and #chats == 1, 'Fixture: told once when first missing: ' .. list(told) .. ' ' .. list(chats));

local results, wrong = {}, {};
-- Runs one step and counts what it told in the seconds after it.
local function stage(name, act, length, wanted)
    local before_told, before_chat = #told, #chats;
    local at = MOCK.now;
    act();
    frame_to(at + (length or 10));
    local times = {};
    for index = before_told + 1, #told do times[#times + 1] = told[index]; end
    results[#results + 1] = ('%s at %g: told %s, chat lines %d'):format(name, at, list(times), #chats - before_chat);
    if #times ~= (wanted or 0) or #chats - before_chat ~= (wanted or 0) then wrong[#wrong + 1] = name; end
end

-- The window's Mute alerts and Unmute alerts, as its top bar does them.
stage('window Mute alerts', function() click_on_next_frame(function(cb)
    cb.changed('before', 'Mute alerts'); app.state.settings.alerts.muted = true; cb.changed('after'); cb.save(); end); end);
stage('window Unmute alerts', function() click_on_next_frame(function(cb)
    cb.changed('before', 'Unmute alerts'); app.state.settings.alerts.muted = false; cb.changed('after'); cb.save(); end); end);
stage('/vg mute on', function() command('/vg mute on'); end);
assert(app.state.settings.alerts.muted == true, 'Fixture: /vg mute on muted.');
stage('/vg mute off', function() command('/vg mute off'); end);
assert(app.state.settings.alerts.muted == false, 'Fixture: /vg mute off unmuted.');
-- A change made in the window, then the window's Undo, whose alert reset waits for the end of the draw.
stage('window Text size then Undo', function()
    click_on_next_frame(function(cb) cb.changed('before', 'Text size'); app.state.settings.style.font_size = 18; cb.changed('after'); cb.save(); end);
    click_on_next_frame(function(cb) assert(cb.undo()); end);
    assert(app.state.settings.style.font_size ~= 18, 'Fixture: the window Undo took the text size back.');
end, 12);
stage('/vg unlock then /vg undo', function() command('/vg unlock'); command('/vg undo'); end);
assert(app.state.settings.panels.self_buffs.locked, 'Fixture: /vg undo took the unlock back.');
stage('/vg set style.font_size 20', function() command('/vg set style.font_size 20'); end);
assert(app.state.settings.style.font_size == 20, 'Fixture: /vg set set it.');
stage('/vg reset rolls', function() command('/vg reset rolls'); end);
-- A profile saved and loaded again, with the same alert in it.
stage('/vg profile save then load', function()
    command('/vg profile save "Spare"'); command('/vg profile load "Spare"');
    assert(app.state.settings.active_profile == 'Spare', 'Fixture: the profile loaded.');
end);
-- The Hide list's export imported back over it. The mock has no clipboard to read, so its text is read here.
stage('Hide list export imported back', function()
    assert(app.callbacks.share_copy('filters'), 'Fixture: the export copied.');
    local payload = assert(require('core.share').read(MOCK.clipboard));
    assert(app.callbacks.share_import(payload, 'replace'), 'Fixture: the import ran.');
end);
assert(#app.state.settings.alerts.rules == 1 and app.state.settings.alerts.rules[1].effect == 40, 'Fixture: the alert is still there.');
-- These do tell it again: Protect found and then gone again, and a zone change.
stage('Protect on for 4 s, then gone', function()
    snapshot.self_effects = { { effect=40, slot=0, deadline=MOCK.now + 1800, raw_timer=1800 * 60 } };
    frame_to(MOCK.now + 4);
    snapshot.self_effects = {};
end, 10, 1);
stage('zone change', function() snapshot.zone = 103; end, 10, 1);
stage('/vg mute on, then the window Unmute alerts 5 s later', function()
    command('/vg mute on'); frame_to(MOCK.now + 5);
    click_on_next_frame(function(cb) cb.changed('before', 'Unmute alerts'); app.state.settings.alerts.muted = false; cb.changed('after'); cb.save(); end);
end);

for index = 1, #MOCK.printed do
    assert(not MOCK.printed[index]:find('could not', 1, true), 'Fixture: something failed: ' .. MOCK.printed[index]);
end
assert(#wrong == 0, 'Told a missing effect a wrong number of times: ' .. table.concat(wrong, ', ') .. ' || ' .. table.concat(results, '; '));
return true;
