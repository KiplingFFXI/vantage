-- Profiles and sharing (ui/profiles_page.lua), through the real vantage.lua and settings window: the status line, any job
-- linked to the picked profile with Link, Unlink and Unlink all jobs, Undo the last profile change, and an export of
-- any kind read the same way with Import and add and Import and replace. test_profile_sharing.lua follows a whole profile.
local store, share, defaults = require('core.store'), require('core.share'), require('ui.defaults');
local imgui = require('imgui');
MOCK.screen = { 1920, 1080 };
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, level = 75, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window = require('ui.settings_window');
local clipboard, combo, previews = nil, nil, {};
rawset(imgui, 'GetClipboardText', function() return clipboard; end);
rawset(imgui, 'BeginCombo', function(label, preview) previews[label] = preview; return label == combo; end);
rawset(imgui, 'EndCombo', function() end);
local view = { rows = {}, context = { valid = true, job = 3, entities = {} } };
local function draw(click, opened)
    local s = app.state.settings;
    s.window.open, s.window.tab = true, 'Profiles';
    combo, MOCK.imgui_calls = opened, {};
    if click then MOCK.clicks[click] = true; end;
    window.draw(s, view, app.callbacks);
    assert(not click or not MOCK.clicks[click], 'The control is on the page: ' .. tostring(click));
    MOCK.clicks = {};
end;
local function said(text)
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'TextWrapped' or call[1] == 'Text' or call[1] == 'TextColored') and (call[2] == text or call[3] == text) then return true; end;
    end;
    return false;
end;
local function button(label)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Button' and call[2] == label then return true; end; end;
    return false;
end;
local function links() return app.state.settings.job_profiles; end;
local function pick(name) draw(name, '##profiles'); draw(); end;
local function job(name) draw(name, '##linked_job'); draw(); end;

-- The status line.
draw(); draw();
assert(said('No profile in use.'), 'With no profile it says so.');
assert(previews['##profiles'] == 'Choose a saved profile', 'Nothing is picked at first.');
assert(previews['##linked_job'] == 'WHM', 'The job list starts on the job you are on.');
assert(app.callbacks.profile_save('Raid', false), 'Fixture: Raid is saved.');
assert(app.callbacks.profile_save('Solo', false), 'Fixture: Solo is saved.');
app.state.settings.active_profile = 'Raid';
draw(); draw();
assert(said('Using profile "Raid".'), 'It names the profile in use.');
local function font(by)
    app.callbacks.changed('before', 'Font size');
    app.state.settings.style.font_size = app.state.settings.style.font_size + by;
    app.callbacks.changed('after');
end;
font(1);
draw(); draw();
assert(said('Using profile "Raid". Changed since it was saved.'), 'And says when it changed.');
font(-1);

-- Link needs a saved profile, and any job can be linked, not only the one you are on.
draw('Link##profile_link'); draw();
assert(next(links()) == nil and said('Choose a saved profile first.'), 'With none picked Link asks for one.');
assert(not button('Unlink##profile_unlink') and not button('Unlink all jobs'), 'With no link there is nothing to unlink.');
pick('Raid');
draw('Link##profile_link'); draw();
assert(links()['3'] == 'Raid' and said('Linked: WHM'), 'Link links the job in the list, here the one you are on.');
job('WAR');
assert(previews['##linked_job'] == 'WAR' and not button('Unlink##profile_unlink'), 'Another job has no link yet.');
draw('Link##profile_link'); draw();
assert(links()['1'] == 'Raid' and links()['3'] == 'Raid' and said('Linked: WAR, WHM'), 'Any job can be linked.');
-- A job linked to another profile says which, whatever is picked.
pick('Solo');
assert(said('WAR loads Raid.') and not said('Linked: WAR, WHM'), 'The line names the profile the job loads.');
job('PLD');
draw('Link##profile_link'); draw();
assert(links()['7'] == 'Solo' and said('Linked: PLD') and button('Unlink##profile_unlink'), 'Solo has its own job.');

-- Unlink takes one job, and Unlink all jobs every one as one Undo step.
local steps = #app.state.history;
draw('Unlink##profile_unlink'); draw();
assert(links()['7'] == nil and links()['1'] == 'Raid' and #app.state.history == steps + 1, 'Unlink takes this job only, as one Undo step.');
assert(not button('Unlink##profile_unlink') and button('Unlink all jobs'), 'Another job still has a link.');
steps = #app.state.history;
draw('Unlink all jobs'); draw();
assert(next(links()) == nil and not button('Unlink all jobs') and #app.state.history == steps + 1, 'Unlink all jobs is one Undo step.');
assert(app.callbacks.undo());
assert(links()['1'] == 'Raid' and links()['3'] == 'Raid', 'Undo puts the links back.');

-- The list ends at PUP, and a link to a missing profile says so.
app.state.settings.job_profiles['18'] = 'Gone';
draw(nil, '##linked_job');
local listed = {};
for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Selectable' then listed[call[2]] = true; end; end;
assert(listed.PUP and not listed.DNC, 'The list ends at PUP.');
job('PUP');
assert(said('This job refers to a missing profile: Gone'), 'A link to a missing profile says so.');
draw('Unlink##profile_unlink'); draw();
assert(links()['18'] == nil, 'and it can be undone.');

-- Overwrite and Delete wait for Confirm, and Undo the last profile change shows after one.
assert(not button('Undo the last profile change'), 'Nothing to undo yet.');
pick('Solo');
draw('Overwrite##profile_overwrite'); draw();
assert(said('This replaces the saved settings in Solo.') and button('Confirm overwrite') and button('Cancel profile change'), 'Overwrite asks first.');
draw('Confirm overwrite'); draw();
assert(button('Undo the last profile change') and not button('Confirm overwrite'), 'After it the way back shows.');
draw('Undo the last profile change'); draw();
assert(not button('Undo the last profile change'), 'and goes once used.');
draw('Delete##profile_delete'); draw();
assert(said('This deletes the saved profile Solo.'), 'Delete asks first.');
draw('Cancel profile change'); draw();
assert(not button('Confirm delete'), 'Cancel leaves it.');

-- Across characters: Share is what to share, in plain words, and it shows while sharing is on.
assert(previews['##Shared settings scope'] == nil, 'With sharing off there is nothing to pick.');
app.state.settings.shared_layout = true;
draw();
assert(previews['##Shared settings scope'] == 'Where the panels and party list buffs are', 'The scope is in plain words.');
app.state.settings.shared_scope = 'presentation';
draw();
assert(previews['##Shared settings scope'] == 'Where things are and how they look', 'Both of them.');
app.state.settings.shared_layout, app.state.settings.shared_scope = false, 'placement';

-- Each kind of string reads the same way, and says what it holds.
local fresh = defaults.tidy(defaults.make());
for _, case in ipairs({ { 'element', 'rolls', 'It holds: One display: Phantom Roll.' }, { 'layout', nil, 'It holds: Where everything is.' },
    { 'filters', nil, 'It holds: Hidden everywhere list.' }, { 'alerts', nil, 'It holds: Alert rules.' }, { 'profile', nil, 'It holds: Whole profile.' } }) do
    clipboard = assert(share.export(fresh, case[1], case[2], 'Tester'));
    local before = store.copy(app.state.settings);
    draw('Import from clipboard'); draw();
    assert(said(case[3]), case[3]);
    assert(button('Import and add##share_add') and button('Import and replace##share_replace') and button('Clear##share_clear'), case[1] .. ' can be imported either way.');
    assert(button('Save as a new profile') == (case[1] == 'profile'), 'Only a whole profile can be saved as a new profile: ' .. case[1]);
    assert(store.equal(before.panels, app.state.settings.panels) and store.equal(before.style, app.state.settings.style), 'Reading it changes nothing.');
    draw('Clear##share_clear'); draw();
    assert(not button('Import and add##share_add'), 'Clear forgets it.');
end;
-- Import and replace of a whole profile is one Undo step, keeps your locks and leaves the saved profiles alone.
local theirs = store.copy(fresh);
theirs.panels.target.width, theirs.panels.self_buffs.locked = 410, false;
clipboard = assert(share.export(defaults.tidy(theirs), 'profile', nil, 'Tester'));
local saved = #app.callbacks.profile_list();
steps = #app.state.history;
draw('Import from clipboard'); draw();
draw('Import and replace##share_replace'); draw();
assert(app.state.settings.panels.target.width == 410 and app.state.settings.panels.self_buffs.locked == true, 'It takes the settings and keeps your locks.');
assert(#app.state.history == steps + 1 and #app.callbacks.profile_list() == saved, 'One Undo step, and no new saved profile.');
assert(said('Replaced with the export. Undo takes it back.') and not button('Import and add##share_add'), 'It says so, and the string is done with.');

-- The word is Import, on every line of the page.
for _, call in ipairs(MOCK.imgui_calls) do
    for index = 2, 3 do
        local value = call[index];
        assert(type(value) ~= 'string' or not value:find('Paste', 1, true), 'The page says Paste: ' .. tostring(value));
    end;
end;

-- What importing would change is worked out again when the settings change, not as time goes by.
local preview, worked = app.callbacks.share_preview, 0;
app.callbacks.share_preview = function(...) worked = worked + 1; return preview(...); end;
clipboard = assert(share.export(fresh, 'layout', nil, 'Tester'));
draw('Import from clipboard'); draw();
assert(worked == #share.modes, 'Reading it works out each way to import it.');
for _ = 1, 3 do MOCK.now = MOCK.now + 1; draw(); end;
assert(worked == #share.modes, 'Time going by works out nothing again.');
font(1);
draw();
assert(worked == 2 * #share.modes, 'A change to the settings works them out again.');
font(-1);
draw('Clear##share_clear'); draw();
app.callbacks.share_preview = preview;

-- What is typed in the search box and the profile name box.
local typed, box = {}, imgui.InputTextWithHint;
rawset(imgui, 'InputTextWithHint', function(label, hint, value, ...)
    if typed[label] == nil then return box(label, hint, value, ...); end;
    value[1], typed[label] = typed[label], nil;
    return true;
end);
local function found(query, label)
    for _, result in ipairs(window.search(query)) do if result.tab == 'Profiles' and result.label == label then return true; end; end;
    return false;
end;
-- A Confirm is found by what it says while it waits, and not once it is done with.
pick('Solo');
typed['##find_settings'] = 'confirm';
draw(); draw();
draw('Delete##profile_delete'); draw();
assert(found('confirm', 'Confirm ') and found('confirm delete', 'Confirm '), 'While it waits the search finds it.');
draw('Cancel profile change'); draw();
assert(not found('confirm', 'Confirm ') and not found('confirm', 'Confirm delete'), 'Once cancelled the search leaves it out.');
typed['##find_settings'] = '';
draw(); draw();

-- Save as new and Rename pick the profile by the name it was saved under, without the spaces around what was typed.
typed['##profile_name'] = '  Nin ';
draw(); draw('Save as new'); draw();
assert(previews['##profiles'] == 'Nin', 'Save as new picks the name it was saved under.');
typed['##profile_name'] = ' Ninja ';
draw(); draw('Rename##profile_rename'); draw();
assert(previews['##profiles'] == 'Ninja' and app.callbacks.profile_status('Ninja').exists, 'Rename picks the new name.');
draw(nil, '##profiles');
local picked;
for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Selectable' and call[2] == 'Ninja' then picked = call[3]; end; end;
assert(picked == true, 'The list shows it picked.');
rawset(imgui, 'InputTextWithHint', nil);
rawset(imgui, 'GetClipboardText', nil);
rawset(imgui, 'BeginCombo', nil);
rawset(imgui, 'EndCombo', nil);
MOCK.fire('unload');
return 'Profiles and sharing links any job, and reads every kind of export one way';
