-- A command that takes no word after it changes nothing when it gets one and shows its usage line, as /vg party hide
-- extra and /vg mute on now do. So /vg hide party, typed for /vg party hide, hides nothing, and /vg reset party ui,
-- typed for /vg reset party_ui, resets nothing. The bare forms still act.
local SNAP = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 1, self_known = true, self_effects = {}, party = {}, entities = {} };
require('app_fixture')(SNAP);
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, update = function() end,
    status = function() return { active = false }; end, restore = function() return true; end, suspend = function() return true; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
local function said(text)
    local count = #MOCK.printed;
    local event = { command = text };
    MOCK.fire('command', event);
    assert(event.blocked, 'Fixture: ' .. text .. ' reaches Vantage.');
    local out = {};
    for index = count + 1, #MOCK.printed do out[#out + 1] = MOCK.printed[index]; end
    return (table.concat(out, ' | '):gsub('%c', ''));
end;
local function settings() return app.state.settings; end;
local function settle() for _ = 1, 8 do MOCK.frame(.11); end; end;
local function locked()
    local s = settings();
    return s.panels.self_buffs.locked and s.party_ui.locked and s.alerts.notice_locked and s.rolls.locked and s.pet.locked;
end;
local function unlocked()
    local s = settings();
    return not s.panels.self_buffs.locked and not s.party_ui.locked and not s.alerts.notice_locked and not s.rolls.locked
        and not s.pet.locked;
end;
local function any() return true; end;
MOCK.fire('load'); app.refresh(0);
settle();

-- Each one is tried, and every one that acted is told together.
local wrong = {};
local function refused(text, usage, unchanged)
    local status = app.callbacks.history_status();
    local undo, redo = status.undo, status.redo;
    local reply = said(text); settle();
    status = app.callbacks.history_status();
    if not reply:find(usage, 1, true) or status.undo ~= undo or status.redo ~= redo or not unchanged() then
        wrong[#wrong + 1] = ('%s -> said [%s], Undo steps %d->%d, Redo steps %d->%d'):format(text, reply, undo, status.undo, redo, status.redo);
    end
end;

said('/vg unlock'); said('/vg party show'); settle();
assert(unlocked() and settings().party_ui.enabled and not app.state.hidden, 'Fixture: everything unlocked and Party list on.');
refused('/vg hide party', 'Usage: /vg hide', function() return not app.state.hidden; end);
said('/vg hide'); settle();
refused('/vg show party', 'Usage: /vg show', function() return app.state.hidden; end);
said('/vg show'); said('/vg unlock'); settle();
refused('/vg lock party', 'Usage: /vg lock', unlocked);
said('/vg lock'); settle();
refused('/vg unlock all', 'Usage: /vg unlock', locked);
said('/vg unlock'); settle();
-- Undo and redo take one step each, so a count after them is a word too many.
assert(app.callbacks.history_status().undo >= 3, 'Fixture: three steps or more to undo.');
refused('/vg undo 3', 'Usage: /vg undo', any);
said('/vg undo'); settle();
assert(app.callbacks.history_status().redo >= 1, 'Fixture: a step to redo.');
refused('/vg redo 1', 'Usage: /vg redo', any);
said('/vg redo'); settle();
-- Reset takes one scope. party is the Party members' timers panel, so a second word must not leave it reset alone.
said('/vg set panels.party.filter "Protect"'); settle();
assert(settings().panels.party.filter == 'Protect', 'Fixture: the Party members\' timers panel has a name filter.');
refused('/vg reset party ui', 'Usage: /vg reset', function() return settings().panels.party.filter == 'Protect'; end);
-- The window, the chat sample and the report.
local open = settings().window.open;
refused('/vg settings extra', 'Usage: /vg settings', function() return settings().window.open == open; end);
refused('/vg filters extra', 'Usage: /vg filters', function() return settings().window.open == open; end);
refused('/vg chatsample extra', 'Usage: /vg chatsample', any);
refused('/vg report extra', 'Usage: /vg report', any);
assert(#wrong == 0, 'A word too many acted: ' .. table.concat(wrong, '; '));
for index = 1, #MOCK.printed do
    assert(not MOCK.printed[index]:find('This is how your Vantage messages will look.', 1, true)
        and not MOCK.printed[index]:find('Report saved to', 1, true), 'A word too many printed no sample line and saved no report.');
end
assert(not open, 'Fixture: the settings window is closed.');

-- The bare forms still act.
said('/vg hide'); settle();
assert(app.state.hidden, '/vg hide hides the displays.');
said('/vg show'); settle();
assert(not app.state.hidden, '/vg show shows them.');
said('/vg lock'); settle();
assert(locked(), '/vg lock locks every display.');
said('/vg unlock'); settle();
assert(unlocked(), '/vg unlock unlocks every display.');
local steps = app.callbacks.history_status().undo;
said('/vg undo'); settle();
assert(app.callbacks.history_status().undo == steps - 1 and locked(), '/vg undo takes one step back.');
said('/vg redo'); settle();
assert(app.callbacks.history_status().undo == steps and unlocked(), '/vg redo puts it back.');
said('/vg reset party'); settle();
assert(settings().panels.party.filter == '', '/vg reset with one scope resets it.');
local reply = said('/vg chatsample');
assert(reply:find('This is how your Vantage messages will look.', 1, true), '/vg chatsample prints the sample: ' .. reply);
reply = said('/vg report');
assert(reply:find('Report saved to', 1, true), '/vg report saves the report: ' .. reply);
said('/vg filters');
assert(settings().window.open and settings().window.tab == 'Filters', '/vg filters opens the Hide list.');
said('/vg settings');
assert(not settings().window.open, '/vg settings closes the open window.');
return 'A word too many gets the usage line';
