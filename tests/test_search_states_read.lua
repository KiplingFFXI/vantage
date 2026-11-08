-- While the search box has text, the search reads a state that goes by the settings alone once each time they change,
-- and a live one each time it searches, so a search left in the box walks no settings on a quiet frame.
local h = require('panel_fixture')();
local index = require('ui.search_index');
-- The state that hides label on Home, with a count of its reads.
local function counted(label)
    local found;
    for _, state in ipairs(index.states) do
        for _, hidden in ipairs(state.hides.Home or {}) do if hidden == label then found = state; end; end;
    end;
    assert(found, 'Fixture: a state hides ' .. label .. '.');
    local on, count = found.on, { 0 };
    found.on = function(...) count[1] = count[1] + 1; return on(...); end;
    return count, found;
end;
local function finds(query, label)
    for _, result in ipairs(h.window.search(query)) do if result.tab == 'Home' and result.label == label then return true; end; end;
    return false;
end;

h.fresh();
h.draw();
local unmute, muting = counted('Unmute');
local ending, editing = counted('End edit mode');
assert(not muting.live and editing.live, 'Fixture: Unmute goes by the settings, End edit mode by more.');
h.window.search('alerts');
h.window.search('alerts');
h.window.search('mute');
assert(unmute[1] == 1, 'A state of the settings is read once while they stay the same: ' .. unmute[1]);
assert(ending[1] == 3, 'A live state is read each search: ' .. ending[1]);
h.bump();
h.window.search('mute');
assert(unmute[1] == 2 and ending[1] == 4, 'A change reads it again.');
-- Settings put in place of the others are read again, whatever their count says.
h.app.state.settings = require('ui.defaults').tidy(require('ui.defaults').make());
h.draw();
h.window.search('mute');
assert(unmute[1] == 3, 'New settings are read again.');

-- What it finds follows each change.
assert(not finds('unmute', 'Unmute'), 'Fixture: with alerts on, Unmute is not a result.');
h.s.alerts.muted = true;
h.bump();
assert(finds('unmute', 'Unmute'), 'Muted, Unmute is a result.');
h.s.alerts.muted = false;
h.bump();
assert(not finds('unmute', 'Unmute'), 'Unmuted, it goes.');
return 'The search reads each state when it can change';
