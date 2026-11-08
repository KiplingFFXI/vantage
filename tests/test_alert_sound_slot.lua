-- One alert sound plays a second. A notice whose volume is 0 (its rule's own volume, or the shared volume for a
-- rule on it) has no sound, so it neither takes that slot from an audible rule firing with it nor opens its file.
local A = require('core.alerts');
local function rule(id, effect, name, sound, volume)
    return { id = id, enabled = true, event = 'gain', effect = effect, effect_name = name, scope = 'self', cooldown = 0, visual = true,
        sound = sound, volume = volume, duration = 4 };
end;
local function fire(rules, at, shared)
    local view = { valid = true, rows = {}, subjects = { { id = 10, scope = 'self', known = true } }, context = { id = 10, zone = 1, job = 1 } };
    local a = A.new();
    a:update(view, {}, rules, at - 0.2, {}); a:update(view, {}, rules, at - 0.1, {});
    local events = {};
    for _, r in ipairs(rules) do
        events[#events + 1] = { kind = 'gain', key = '10:' .. r.effect, instance = 1, effect = r.effect, entity_id = 10, scope = 'self', name = r.effect_name };
        view.rows[#view.rows + 1] = { key = '10:' .. r.effect, instance = 1, effect = r.effect, name = r.effect_name, scope = 'self', entity_id = 10,
            status = 'server', remaining = 60, total = 60, present = true };
    end;
    a:update(view, events, rules, at, {});
    return a:drain(at, shared), a;
end;
local quiet, loud = rule('q', 6, 'Silence', 'soft.wav', 0), rule('l', 4, 'Paralysis', 'alarm.wav', 80);
local out = fire({ quiet, loud }, 1, 70);
assert(#out == 2 and out[1].sound == '' and out[2].sound == 'alarm.wav',
    'A rule muted with its own volume 0 leaves the sound to the audible rule firing with it.');
-- A rule on the shared volume (-1) with the shared volume at 0 is muted too.
local shared = rule('s', 6, 'Silence', 'soft.wav', -1);
out = fire({ shared, loud }, 1, 0);
assert(out[1].sound == '' and out[2].sound == 'alarm.wav', 'A rule on a shared volume of 0 leaves the sound to an audible rule.');
-- On a shared volume above 0 it is audible and keeps the slot.
out = fire({ shared, loud }, 1, 70);
assert(out[1].sound == 'soft.wav' and out[2].sound == '', 'A rule on an audible shared volume takes the one sound.');
-- A muted notice doesn't start the one-second gap either.
local a;
out, a = fire({ quiet }, 1, 70);
assert(out[1].sound == '' and a.last_sound == -math.huge, 'A muted notice leaves the sound gap as it was.');

-- The app passes the shared volume, so a rule on it opens no file while it is 0.
local store = require('core.store');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
require('ui.party_hud').draw = function() return 0, {}; end;
require('ui.native_party_hud').draw = function() return 0, {}; end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, update = function() end,
    status = function() return { active = false }; end, restore = function() return true; end, suspend = function() return true; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
ashita.fs.exists = function() return true; end;
MOCK.fire('load'); app.refresh(0);
app.state.settings.alerts.volume = 0;
MOCK.mci = {};
app.callbacks.test_alert(rule('t', 6, 'Silence', 'soft.wav', -1));
MOCK.frame(.11);
assert(#MOCK.mci == 0, 'A test alert on a shared volume of 0 opens no sound: ' .. table.concat(MOCK.mci, ' ; '));
app.state.settings.alerts.volume = 60;
MOCK.now = MOCK.now + 2;
app.callbacks.test_alert(rule('t', 6, 'Silence', 'soft.wav', -1));
MOCK.frame(.11);
assert(#MOCK.mci > 0 and table.concat(MOCK.mci, ' '):find('soft.wav', 1, true), 'Fixture: an audible shared volume plays the sound.');
return true;
