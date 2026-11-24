-- Opening a sound file takes tens of milliseconds, and playing one that is open takes one or two (core/sound.lua).
-- So the sounds the alert rules can play are opened ahead of time, as warmup steps after a load and again when the
-- rules' sounds change, and the frame an alert fires in only plays. A rule that can't be heard opens nothing.
local sound = require('core.sound');
-- Every sound file is there but one named missing. Other files are as the disk has them.
local on_disk = ashita.fs.exists;
ashita.fs.exists = function(path)
    if path:find(sound.FOLDER, 1, true) then return not path:find('missing', 1, true); end
    return on_disk(path);
end;
local function sent(pattern)
    local count = 0;
    for _, command in ipairs(MOCK.mci or {}) do if command:find(pattern, 1, true) then count = count + 1; end end
    return count;
end

-- The module: a sound made ready is opened once, and what plays next is unchanged.
MOCK.mci = {};
assert(sound.use('first.wav') and sent('open') == 1, 'Fixture: a sound in use is open.');
assert(sound.prepare('second.wav') == true and sent('open') == 2 and sound.is_open('second.wav'), 'A sound made ready is opened.');
assert(sound.prepare('second.wav') == true and sent('open') == 2, 'One that is open is not opened again.');
MOCK.mci = {};
assert(sound.play(70) and sent('play vantage_alert1') == 1 and sent('vantage_alert2') == 0, 'The sound in use still plays, not the one made ready.');
MOCK.mci = {};
assert(sound.use('second.wav') and sound.play(70) and sent('open') == 0 and sent('play vantage_alert2') == 1,
    'Used later, the ready sound plays with no open.');
-- One that can't be opened is marked, as a play of it would mark it, and what is in use stays in use.
MOCK.mci = {};
assert(sound.prepare('missing.wav') == false and sound.problem('missing.wav') ~= nil, 'A file that isn\'t there can\'t be made ready.');
assert(sound.prepare('missing.wav') == false and sent('open') == 0, 'And it isn\'t tried again.');
assert(sound.prepare('') == false and sound.prepare('bad/name.wav') == false and sent('open') == 0, 'No name and a bad name open nothing.');
-- A file that is there but won't open is tried once, so its stall isn't paid again each time the steps run.
MOCK.mci_code = function(command) return command:find('broken', 1, true) and 1 or 0; end;
assert(sound.prepare('broken.wav') == false and sent('open') == 1, 'A file that won\'t open is tried once.');
assert(sound.prepare('broken.wav') == false and sent('open') == 1, 'And not again.');
MOCK.mci_code = nil;
MOCK.mci = {};
assert(sound.play(70) and sent('play vantage_alert2') == 1, 'The sound in use is still the one that plays.');
-- All eight places taken. keep names the sounds the rules play now: none of those is closed to make room, and
-- neither is the sound in use. A place held by any other sound is given up, the one played longest ago first.
for index = 3, 8 do assert(sound.prepare('s' .. index .. '.wav'), 'Fixture: place ' .. index .. ' is taken.'); end
local keep = { ['first.wav'] = true, ['second.wav'] = true };
for index = 3, 8 do keep['s' .. index .. '.wav'] = true; end
MOCK.mci = {};
assert(sound.prepare('ninth.wav', keep) == false and sent('open') == 0 and sent('close') == 0 and not sound.is_open('ninth.wav'),
    'With every place taken by a sound the rules play, nothing is closed.');
assert(sound.is_open('first.wav') and sound.is_open('s8.wav'), 'The open ones stay open.');
keep['first.wav'] = nil;
assert(sound.prepare('ninth.wav', keep) == true and sent('close vantage_alert1') == 1 and sent('open') == 1,
    'A place held by a sound no rule plays is given to one a rule does: ' .. table.concat(MOCK.mci, ' ; '));
assert(sound.is_open('ninth.wav') and not sound.is_open('first.wav') and sound.is_open('second.wav'), 'Only that one was closed.');
-- With nothing kept, the one played longest ago goes, but never the sound in use, though it is the oldest.
MOCK.mci = {};
assert(sound.prepare('tenth.wav', {}) == true and sent('close vantage_alert3') == 1 and sound.is_open('second.wav') and not sound.is_open('s3.wav'),
    'The sound in use keeps its place, and the oldest other one goes: ' .. table.concat(MOCK.mci, ' ; '));
MOCK.mci = {};
assert(sound.play(70) and sent('play vantage_alert2') == 1, 'And it is still the one that plays.');
sound.close();

-- The addon: a saved rule with a sound has it open before any alert, and the alert's frame only plays.
local warmup = require('core.warmup');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {}, party = {}, entities = {} };
require('app_fixture')(snapshot);
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, update = function() end,
    status = function() return { active = false }; end, restore = function() return true; end, suspend = function() return true; end };
local function rule(id, effect, name, file, volume, enabled)
    return { id = id, enabled = enabled ~= false, event = 'gain', effect = effect, effect_name = name, scope = 'self', cooldown = 0, visual = true,
        sound = file, volume = volume or -1, duration = 4 };
end
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local function frames(count) for _ = 1, count do MOCK.frame(.11); end end
frames(3);
MOCK.mci = {};
frames(5);
assert(sent('open') == 0, 'With no rule that has a sound, nothing is opened.');

-- Rules saved with sounds: one audible, one off, one with its own volume 0, one that repeats the first.
local function change(edit)
    app.callbacks.changed('before', 'Fixture rules');
    edit(app.state.settings);
    app.callbacks.changed('after');
end
change(function(s)
    s.alerts.rules = { rule('a', 4, 'Paralysis', 'alarm.wav'), rule('b', 6, 'Silence', 'off.wav', -1, false),
        rule('c', 3, 'Poison', 'quiet.wav', 0), rule('d', 5, 'Blindness', 'alarm.wav'), rule('e', 2, 'Sleep', 'chime.wav', 40) };
end);
frames(3);
assert(sent('alarm.wav') == 1 and sent('chime.wav') == 1 and sent('open') == 2, 'Each sound an audible rule plays is opened once: ' .. table.concat(MOCK.mci, ' ; '));
assert(sent('off.wav') == 0 and sent('quiet.wav') == 0, 'A rule that is off or has its volume at 0 opens nothing.');
-- The alert's own frame opens nothing more.
MOCK.mci = {};
app.callbacks.test_alert(app.state.settings.alerts.rules[1]);
frames(1);
assert(sent('open') == 0 and sent('play') == 1, 'The frame the alert fires in only plays: ' .. table.concat(MOCK.mci, ' ; '));
-- A change that leaves the sounds as they are opens nothing.
MOCK.mci = {};
change(function(s) s.alerts.rules[1].cooldown = 5; end);
frames(3);
assert(#MOCK.mci == 0, 'A change to something else opens nothing: ' .. table.concat(MOCK.mci, ' ; '));
-- A new sound on a rule is opened when it is chosen.
change(function(s) s.alerts.rules[1].sound = 'bell.wav'; end);
frames(3);
assert(sent('bell.wav') == 1, 'A sound chosen for a rule is opened then.');
-- The sounds' steps ran again for it, but /vg report's startup.restarts counts only what the displays wait for, which a
-- new graphics device makes again.
assert(warmup.report().restarts == 0, 'A new sound is not counted as a restart: ' .. warmup.report().restarts);
-- Muted, or with Alerts off, nothing new is opened.
MOCK.mci = {};
change(function(s) s.alerts.muted = true; s.alerts.rules[5].sound = 'horn.wav'; end);
frames(3);
assert(sent('open') == 0, 'While muted no sound is opened.');
change(function(s) s.alerts.muted = false; end);
frames(3);
assert(sent('horn.wav') == 1, 'Unmuted, the new sound is opened.');
MOCK.mci = {};
change(function(s) s.alerts.volume = 0; s.alerts.rules[1].sound = 'gong.wav'; end);
frames(3);
assert(sent('gong.wav') == 0, 'A rule on a shared volume of 0 opens nothing.');
change(function(s) s.alerts.volume = 70; end);
frames(3);
assert(sent('gong.wav') == 1, 'With the shared volume back up it is opened.');

-- More sounds tried on a rule than can be open at once: the newest is still opened ahead, in the place of one no
-- rule plays any more, and the sounds the other rules play stay open.
MOCK.mci = {};
for index = 1, 6 do
    change(function(s) s.alerts.rules[1].sound = 'try' .. index .. '.wav'; end);
    frames(3);
end
assert(sent('open') == 6 and sent('alarm.wav') == 0 and sent('horn.wav') == 0,
    'Each new sound is one open, and no sound a rule plays is closed and opened again: ' .. table.concat(MOCK.mci, ' ; '));
assert(sound.is_open('try6.wav') and sound.is_open('alarm.wav') and sound.is_open('horn.wav'),
    'Past eight open sounds, a newly chosen one is still opened and the rules\' other sounds stay.');
MOCK.mci = {};
app.callbacks.test_alert(app.state.settings.alerts.rules[1]);
frames(1);
assert(sent('open') == 0 and sent('play') == 1, 'Its alert only plays: ' .. table.concat(MOCK.mci, ' ; '));
MOCK.now = MOCK.now + 2;
change(function(s) s.alerts.rules[1].sound = 'gong.wav'; end);
frames(3);
assert(warmup.report().restarts == 0, 'Nor is an unmute or any other change to the sounds: ' .. warmup.report().restarts);

-- After a reload the saved rules' sounds are opened by the load's warmup, before anything fires.
assert(app.callbacks.save(), 'Fixture: the rules are saved.');
MOCK.fire('unload');
MOCK.mci = {};
app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(MOCK.now);
frames(5);
assert(sent('gong.wav') == 1 and sent('alarm.wav') == 1 and sent('horn.wav') == 1 and sent('open') == 3,
    'A load opens each sound the saved rules play, once: ' .. table.concat(MOCK.mci, ' ; '));
MOCK.mci = {};
app.callbacks.test_alert(app.state.settings.alerts.rules[1]);
frames(1);
assert(sent('open') == 0 and sent('play') == 1, 'And the first alert after a load only plays.');
return 'Alert sounds are open before their first alert';
