-- Saved profiles are a list of rows (ui/profiles_page.lua). Each row's buttons act on its own profile, whatever is
-- picked, an overwrite or delete asks under its own row, and a row's round button picks it for the job links.
local h = require('panel_fixture')();
local app, window = h.app, h.window;
local function leads(query, label)
    for _, result in ipairs(window.search(query)) do if result.tab == 'Profiles' and result.label == label then return true; end; end;
    return false;
end;
local function picked(name)
    for _, call in ipairs(h.calls('RadioButton', name .. '##profile_pick')) do return call[3] == true; end;
    return false;
end;
-- Where the first call of kind with label is among the frame's calls.
local function at(kind, label)
    for index, call in ipairs(MOCK.imgui_calls) do if call[1] == kind and call[2] == label then return index; end; end;
end;

-- With none saved the page says so, and the search leads to Save as new.
h.fresh();
h.s.window.tab = 'Profiles';
h.draw(); h.draw();
assert(h.says('No saved profiles yet. Save as new, below, saves your settings as one.'), 'With none saved, the page says so.');
assert(not h.called('RadioButton') and leads('load profile', 'Save as new'), 'With none saved, Load profile leads to Save as new.');

-- Two saved: each has its row, and nothing is picked.
h.s.style.scale = 2;
assert(app.callbacks.profile_save('Raid', false), 'Fixture: Raid is saved.');
h.s.style.scale = 1;
assert(app.callbacks.profile_save('Solo', false), 'Fixture: Solo is saved.');
h.draw(); h.draw();
for _, name in ipairs({ 'Raid', 'Solo' }) do
    assert(h.called('RadioButton', name .. '##profile_pick') and not picked(name), name .. ' has a row, not picked.');
    for _, label in ipairs({ 'Load##profile_load_', 'Overwrite##profile_overwrite_', 'Rename##profile_rename_', 'Delete##profile_delete_' }) do
        assert(h.called('Button', label .. name), name .. '\'s row has ' .. label);
    end;
    -- Exporting is in the Import and export block, not on the rows.
    for _, label in ipairs({ 'Export##profile_share_', 'Export to a file##profile_save_file_' }) do
        assert(not h.called('Button', label .. name), name .. '\'s row has no ' .. label);
    end;
end;
assert(at('RadioButton', 'Raid##profile_pick') < at('Button', 'Delete##profile_delete_Raid')
    and at('Button', 'Delete##profile_delete_Raid') < at('RadioButton', 'Solo##profile_pick'), 'Each row\'s buttons follow its name.');
assert(leads('load profile', 'Load profile'), 'With rows, the search finds Load.');

-- Load on Raid's row loads Raid with Solo picked, and picks Raid.
h.draw('Solo##profile_pick'); h.draw();
assert(picked('Solo'), 'Fixture: Solo is picked.');
h.draw('Load##profile_load_Raid'); h.draw();
assert(app.state.settings.style.scale == 2 and app.state.settings.active_profile == 'Raid', 'Load on its row loads Raid.');
assert(picked('Raid') and not picked('Solo'), 'The row acted on is picked.');

-- Delete asks under its own row, and Cancel leaves it.
h.draw('Delete##profile_delete_Solo'); h.draw();
local asked = at('TextWrapped', 'This deletes the saved profile Solo.');
assert(asked and asked > at('Button', 'Delete##profile_delete_Solo') and h.called('Button', 'Confirm delete'), 'Delete asks under Solo\'s row.');
h.draw('Cancel profile change'); h.draw();
assert(not h.called('Button', 'Confirm delete') and app.callbacks.profile_status('Solo').exists, 'Cancel leaves Solo.');
-- An overwrite asked for a profile deleted meanwhile has no row, so it goes.
h.draw('Overwrite##profile_overwrite_Solo'); h.draw();
assert(h.called('Button', 'Confirm overwrite'), 'Fixture: the overwrite waits.');
assert(app.callbacks.profile_delete('Solo', app.callbacks.profile_status('Solo').token), 'Fixture: Solo is deleted elsewhere.');
h.draw(); h.draw();
assert(not h.called('Button', 'Confirm overwrite') and not require('ui.profiles_page').confirming(), 'Its Confirm goes with it.');

-- Rename on a row gives it the name in the Name box.
h.draw('Raid##profile_pick'); h.draw();
h.type('##profile_name', 'Group');
h.draw('Rename##profile_rename_Raid'); h.draw();
assert(app.callbacks.profile_status('Group').exists and not app.callbacks.profile_status('Raid').exists and picked('Group'), 'Rename renames that row\'s profile.');
-- With the Name box empty it says what to type.
h.type('##profile_name', '');
h.draw('Rename##profile_rename_Group'); h.draw();
assert(h.says('Type its new name in the Name box below first.'), 'An empty Name box says what to do.');

-- Names that end in #: no round button's label has ###, which ImGui reads as one ID for all of them and which hides the
-- #, and each can be picked.
assert(app.callbacks.profile_save('Melee #', false) and app.callbacks.profile_save('Tank #', false), 'Fixture: two names ending in # are saved.');
h.draw(); h.draw();
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'RadioButton' then assert(not call[2]:find('###', 1, true), 'A round button\'s label has ###: ' .. call[2]); end;
end;
h.draw('Tank # ##profile_pick'); h.draw();
assert(picked('Tank # ') and not picked('Melee # '), 'A name that ends in # can be picked.');
MOCK.fire('unload');
return 'Each saved profile is a row whose buttons act on it';
