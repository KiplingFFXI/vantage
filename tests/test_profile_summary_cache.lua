local app = dofile(ADDON_DIR .. '/vantage.lua');
local c, state = app.callbacks, app.state;
-- A read past the 2 second memo, by emptying it as an edit does.
local function reread() state.profile_summary_cache = nil; return c.profile_summary(); end;
local store, profiles, defaults = require('core.store'), require('core.profiles'), require('ui.defaults');
local peer = profiles.new(require('core.identity').root());
assert(c.profile_save('Support', false));
local reads, read = 0, store.read;
store.read = function(path, ...)
    if path == peer.path then reads = reads + 1; end;
    return read(path, ...);
end;
MOCK.now = 100;
local first = c.profile_summary();
assert(reads == 1 and first.status.source == 'Support' and first.status.exists and not first.status.modified);
assert(c.profile_summary() == first and reads == 1);
MOCK.now = 101.999;
assert(c.profile_summary() == first and reads == 1);
MOCK.now = 102;
assert(c.profile_summary() ~= first and reads == 2, 'Display refreshes at the 2 second boundary.');
MOCK.now = 99;
assert(c.profile_summary() and reads == 3, 'Clock rollback cannot retain stale results.');
c.profile_list(); c.profile_status('Support');
assert(reads == 5, 'Command and confirmation APIs bypass the display cache.');

local function refresh_after(action, message)
    reread();
    action();
    local before = reads;
    local value = c.profile_summary();
    assert(reads == before + 1, message);
    return value;
end;
assert(refresh_after(function() state.settings.active_profile = 'Missing'; end, 'Active-name changes refresh immediately').status.missing);
refresh_after(function() state.settings.active_profile = 'Support'; end, 'Returning to a source refreshes');
refresh_after(function() state.settings = store.copy(state.settings); end, 'Replacing settings refreshes');
refresh_after(function() state.identity = 'Another character'; end, 'Owner changes refresh');
refresh_after(function() c.save(); end, 'Saving refreshes');
local old_size = state.settings.style.font_size;
local changed = refresh_after(function()
    c.changed('before', 'Font size');
    state.settings.style.font_size = old_size + 1;
    c.changed('after');
end, 'Local edits refresh immediately');
assert(changed.status.modified);
assert(refresh_after(function() assert(c.undo()); end, 'Undo refreshes').status.modified == false);
assert(state.settings.style.font_size == old_size);
assert(refresh_after(function() assert(c.redo()); end, 'Redo refreshes').status.modified);
assert(state.settings.style.font_size == old_size + 1);
assert(not refresh_after(function() assert(c.profile_load('Support')); end, 'Loading refreshes').status.modified);

-- A cached display must never authorize overwriting another client's edit.
local cached = reread();
local external = defaults.make(); external.style.font_size = 29;
assert(peer:overwrite('Support', external, peer:source('Support').token));
assert(c.profile_summary() == cached, 'External changes wait only until the next display refresh.');
assert(c.profile_status('Support').token ~= cached.status.token, 'Confirmation sees the external edit immediately.');
assert(not c.profile_save('Support', true, cached.status.token));
local fresh = c.profile_summary();
assert(fresh ~= cached and fresh.status.token ~= cached.status.token and fresh.status.modified, 'Failed mutation clears the display cache.');
assert(not c.profile_delete('Support', cached.status.token));
assert(not c.profile_rename('Support', 'Stale', cached.status.token));
assert(peer:source('Support').token == fresh.status.token and not peer:source('Stale').exists);

local renamed = refresh_after(function()
    assert(c.profile_rename('Support', 'Renamed', c.profile_status('Support').token));
end, 'Renaming refreshes');
assert(renamed.status.source == 'Renamed' and renamed.status.recover_available and renamed.status.recover_kind == 'rename');
local recovered = refresh_after(function() assert(c.profile_recover()); end, 'Recovery refreshes');
assert(recovered.status.source == 'Support' and not recovered.status.recover_available);
assert(refresh_after(function() assert(c.profile_save('Second', false)); end, 'Saving a new profile refreshes').status.source == 'Second');
assert(refresh_after(function() assert(c.profile_delete('Second', c.profile_status('Second').token)); end,
    'Deleting refreshes').status.recover_kind == 'delete');

-- A drag reports a change every frame while the mouse is down. The status keeps its 2 second refresh
-- then, and a change with the mouse up refreshes it at once again.
state.settings.window.open = false;
MOCK.mouse_down = true; MOCK.frame(0);
assert(c.profile_load('Support'));
local dragging = reread();
assert(dragging.status.source == 'Support' and not dragging.status.modified, 'Fixture: the drag starts on a saved profile.');
local drag_reads = reads;
for _ = 1, 5 do
    c.changed('before', 'Timer scale');
    state.settings.style.scale = state.settings.style.scale + 0.01;
    c.changed('after');
    MOCK.frame(0);
    assert(c.profile_summary() == dragging, 'A drag frame keeps the cached profile status.');
end;
assert(reads == drag_reads, 'A drag reads the profile file only at the display refresh.');
MOCK.now = MOCK.now + 2;
local refreshed = c.profile_summary();
assert(refreshed ~= dragging and reads == drag_reads + 1 and refreshed.status.modified, 'The 2 second refresh still runs during a drag.');
MOCK.mouse_down = false; MOCK.frame(0);
local released = c.profile_summary();
c.changed('before', 'Timer scale'); state.settings.style.scale = state.settings.style.scale + 0.01; c.changed('after');
assert(c.profile_summary() ~= released, 'With the mouse up an edit refreshes the status at once.');

-- The display decodes the profile file again only when its text changed. Confirmations read it fresh.
local json = require('core.json');
local decode, decodes = json.decode, 0;
json.decode = function(...) decodes = decodes + 1; return decode(...); end;
reread();
local seen, read_before = decodes, reads;
reread(); reread();
assert(reads == read_before + 2 and decodes == seen, 'The unchanged file is read but not decoded again.');
c.profile_status('Support');
assert(decodes == seen + 1, 'A confirmation decodes the file itself.');
local edited = defaults.make(); edited.style.font_size = 31;
assert(peer:overwrite('Support', edited, peer:source('Support').token));
local after_edit = decodes;
local changed_file = reread();
assert(decodes > after_edit and changed_file.status.token == c.profile_status('Support').token,
    'A changed file is decoded again and the display shows it.');
json.decode = decode;

local file = assert(io.open(peer.path, 'wb')); file:write('malformed JSON'); file:close();
local broken = reread();
assert(#broken.names == 0 and broken.problem and broken.status.problem == broken.problem);
assert(broken.status.recover_available, 'File problems retain the available recovery action.');
assert(not c.profile_recover());
assert(c.profile_summary() ~= broken, 'Failed recovery also refreshes the problem display.');
file = assert(io.open(peer.path, 'rb')); assert(file:read('*a') == 'malformed JSON'); file:close();
file = assert(io.open(peer.path, 'wb')); file:write(store.encode({Repaired=profiles.capture(defaults.make())})); file:close();
local repaired = reread();
assert(not repaired.problem and #repaired.names == 1 and repaired.names[1] == 'Repaired');

-- No timer or background poll exists for the display cache.
local settings_window = require('ui.settings_window');
state.settings.window.open = false;
local before = reads;
for i = 1, 30 do
    MOCK.now = 200 + i;
    settings_window.draw(state.settings, state.view, c);
end;
assert(reads == before, 'Closed settings never poll profiles.');
state.settings.window.open, state.settings.window.tab = true, 'Display';
for i = 1, 3 do settings_window.draw(state.settings, state.view, c); end;
assert(reads == before, 'Other settings pages do not poll profiles.');
return true;
