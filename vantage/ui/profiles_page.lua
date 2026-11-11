-- The Profiles and sharing page. Profiles: which one is in use, the saved ones, and the jobs that load one. Across
-- characters. Import and export (core/share.lua): copy part of your settings as text, or read an export from the clipboard
-- or the shared folder, see what adding it or replacing with it would change, and do one of them as one Undo step. A
-- whole profile can be saved as a new profile instead, which doesn't load it. Start over puts things back. It draws
-- with the settings window's helpers (c), and what is picked here lasts the session.
local share = require('core.share');
local elements = require('ui.elements');
local skin = require('ui.client_skin');
local page = { seen = {} };

-- The saved profile picked and the name box, the job picked here, and the overwrite or delete waiting for its Confirm.
local selected, name_box, picked_job, confirm = '', { '' }, nil, nil;
-- What to export.
local pick = { kind = 'profile', id = 'self_buffs' };
local ids, labels = {}, {};
for _, element in ipairs(elements.list) do ids[#ids + 1], labels[element.id] = element.id, element.label; end
-- The string read and what importing it would change, worked out again when the settings change, so an edit made since
-- shows. A whole profile also has the line that says it was placed on another screen, the name and whether to keep your
-- own display positions, and the line a save that failed left.
local pending, previews, previewed, previewed_revision, other_screen, save_problem;
local import_name, import_keep = { '' }, { keep = false };
-- The files Import from a file listed.
local files;
-- What the buttons and lists act on, set as each draw starts, so a draw makes no function for them.
local now = {};

-- Saved profile names, any problem reading them, and where the current settings came from.
function page.choices(callbacks)
    local summary = callbacks.profile_summary and callbacks.profile_summary();
    -- The search goes by this, so it never reads the file while the box holds text.
    page.seen = summary and summary.status or {};
    if summary then return summary.names or {}, summary.problem, summary.status or {}; end
    local names, problem = {}, nil;
    if callbacks.profile_list then names, problem = callbacks.profile_list(); end
    return names or {}, problem, callbacks.profile_status and callbacks.profile_status() or {};
end

-- base, or base with " 2", " 3" and so on after it: the first that no saved profile in names has. Each is cut to the 40
-- characters a profile name can have (core/profiles.lua), the number kept.
function page.free_name(names, base)
    local taken = {};
    for _, name in ipairs(names or {}) do taken[name:lower()] = true; end
    for count = 1, 999 do
        local number = count > 1 and ' ' .. count or '';
        local name = base:sub(1, 40 - #number):match('^(.-)%s*$') .. number;
        if not taken[name:lower()] then return name; end
    end
    return base;
end

-- Makes name the saved profile picked, for Load and the job link.
function page.pick(name) selected, name_box[1] = name, name; end

-- Picks a profile just saved under typed, by the name the store gave it: it takes off the spaces around a name.
local function pick_saved(callbacks, typed)
    local state = callbacks.profile_status and callbacks.profile_status(typed) or {};
    page.pick(state.exists and state.name or typed);
end

-- Drops an overwrite or delete waiting for its Confirm. Returns whether there was one.
function page.cancel()
    local waiting = confirm ~= nil;
    confirm = nil;
    return waiting;
end

function page.clear() pending, previews, previewed, previewed_revision, other_screen, save_problem = nil, nil, nil, nil, nil, nil; end

-- What the search goes by: whether Confirm shows, whether a string read or a whole profile waits, whether its line about
-- another screen shows, whether Import from a file listed any, and whether the display to export shows.
function page.confirming() return confirm ~= nil; end
function page.reading() return pending ~= nil; end
function page.reading_profile() return pending ~= nil and pending.kind == 'profile'; end
function page.other_screen() return other_screen ~= nil; end
function page.listing() return files ~= nil and #files > 0; end
function page.copying_display() return pick.kind == 'element'; end

local function link_of(settings, job) return settings.job_profiles[job] or settings.job_profiles[tostring(job)] or ''; end

local jobs = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP' };

-- The job the list shows: the one picked here, or the one you are on until you pick one.
local function job_shown(view)
    local current = view and view.context and view.context.job;
    return picked_job or jobs[current] and current or 1;
end

-- What Unlink and Unlink all jobs go by.
function page.job_linked(settings, view) return link_of(settings, job_shown(view)) ~= ''; end
function page.any_link(settings) return next(settings.job_profiles) ~= nil; end

-- The help of the export and import buttons, which name the shared folder, made once.
local helps;
local function help_lines()
    if helps then return helps; end
    local folder = require('core.identity').relative('shared/');
    helps = { folder = folder,
        share = 'Copies the picked saved profile to the clipboard, without loading it. Send it to a friend to import. Your screen does not change.',
        save_file = 'Saves the picked saved profile to a new file in ' .. folder .. ', without loading it. A file already there is never replaced.',
        read = 'Reads the export you copied. Nothing changes until you choose how to import it. An export that is damaged, too long, from another version or holds a setting Vantage doesn\'t have is refused. The entries of a list in it, such as the effects a panel shows, are cleaned as a saved setting\'s are.',
        open_file = 'Lists the .txt files in ' .. folder .. ', to read one of them. Put a file a friend sent you there first.',
        file = 'The .txt files in ' .. folder .. '. Choosing one reads it as Import from clipboard does.',
        keep = 'Keeps where each of your displays sits and its size. Untick to take the places from the profile.',
        name = 'The name the profile is saved under. It can\'t be the name of a profile you already have.',
        save = 'Saves it as a new profile. It is not loaded, and it is picked above, so Load uses it.' };
    return helps;
end

local function status_line(settings, status)
    local source = status.source or settings.active_profile or '';
    if source == '' then return 'No profile in use.'; end
    return 'Using profile "' .. source .. '".' .. (status.modified and ' Changed since it was saved.' or '')
        .. (status.missing and ' Its saved copy is missing.' or '');
end

-- A list down the page, its label on the left. leaves names a button drawn beside it, and it stops short to leave that room.
local function list(imgui, c, label, search, help, id, shown, draw_entries, leaves)
    c.row_label(label, help);
    imgui.SetNextItemWidth(leaves and -(imgui.CalcTextSize(leaves) + 28) or -1);
    skin.prepare_menu(imgui, c.look);
    if imgui.BeginCombo(id, shown) then
        skin.menu(imgui, c.look, 'popup');
        draw_entries();
        imgui.EndCombo();
    end
    c.mark(search, help);
    c.tip(help);
end

local function profile_entries()
    for _, name in ipairs(now.names) do if now.imgui.Selectable(name, selected == name) then page.pick(name); end end
end

-- Overwrite and Delete wait for their Confirm.
local function ask(kind)
    local c, callbacks = now.c, now.callbacks;
    if selected == '' then c.note('Choose a saved profile first.'); return; end
    local state = callbacks.profile_status and callbacks.profile_status(selected) or {};
    confirm = { kind = kind, name = selected, token = state.token };
end

local function load_profile()
    local c = now.c;
    if selected == '' then c.note('Choose a saved profile first.'); return; end
    if c.call('profile_load', selected) ~= false then c.note('Profile loaded.'); end
end

local function overwrite_profile() ask('overwrite'); end

local function rename_profile()
    local c, callbacks = now.c, now.callbacks;
    if selected == '' or name_box[1] == '' then c.note('Choose a saved profile and enter its new name.'); return; end
    local state = callbacks.profile_status and callbacks.profile_status(selected) or {};
    if c.call('profile_rename', selected, name_box[1], state.token) ~= false then pick_saved(callbacks, name_box[1]); c.note('Profile renamed.'); end
end

local function delete_profile() ask('delete'); end

local function confirm_change()
    local c, request = now.c, confirm;
    local ok;
    if request.kind == 'overwrite' then ok = c.call('profile_save', request.name, true, request.token);
    else ok = c.call('profile_delete', request.name, request.token); end
    if ok ~= false then
        c.note('Profile ' .. (request.kind == 'overwrite' and 'updated.' or 'deleted.'));
        if request.kind == 'delete' then selected = ''; end
    end
    confirm = nil;
end

local function cancel_change() confirm = nil; end

local function share_profile(to_file)
    local c, callbacks = now.c, now.callbacks;
    if selected == '' then c.note('Choose a saved profile first.'); return; end
    if not callbacks.profile_share then c.note('That action is not available right now.'); return; end
    local ok, why, left, file = callbacks.profile_share(selected, to_file);
    if not ok then c.note(why or 'That profile could not be exported.', 'problem_messages'); return; end
    c.note((to_file and 'Saved "' .. selected .. '" as ' .. file .. '. A friend puts it in their own shared folder and uses Import from a file.'
        or 'Copied "' .. selected .. '". Send it in a message, or use Export to a file to keep it as a file.') .. (left and ' ' .. left or ''), 'done_messages');
end

local function export_to_clipboard() share_profile(false); end
local function export_to_file() share_profile(true); end

local function save_new()
    local c = now.c;
    if name_box[1] == '' then c.note('Give this profile a name first.'); return; end
    if c.call('profile_save', name_box[1], false) ~= false then pick_saved(now.callbacks, name_box[1]); c.note('Profile saved.', 'done_messages'); end
end

local function saved_profiles(imgui, settings, callbacks, c, names, problem, status)
    c.heading('Profiles', 'Save your panels, appearance and alert rules together. Current effects and timer deadlines are never part of a profile.');
    if problem then imgui.TextWrapped(problem); end
    imgui.TextWrapped(status_line(settings, status));
    -- With nothing to pick, the list is greyed out and says why.
    local none = #names == 0;
    if none and imgui.BeginDisabled then imgui.BeginDisabled(true); end
    list(imgui, c, 'Saved profiles', 'Saved profiles', 'Picking one changes nothing until you use a button below.', '##profiles',
        none and (problem and 'No profiles could be read' or 'No saved profiles yet') or selected ~= '' and selected or 'Choose a saved profile',
        profile_entries);
    if none and imgui.EndDisabled then imgui.EndDisabled(); end
    c.button('Load##profile_load', load_profile, 'Puts the picked saved profile in place of your settings. Undo puts them back.', nil, 'Load profile');
    imgui.SameLine();
    c.button('Overwrite##profile_overwrite', overwrite_profile,
        'Replaces the picked saved profile after you confirm. Undo the last profile change can put it back.', nil, 'Overwrite profile');
    imgui.SameLine();
    c.button('Rename##profile_rename', rename_profile, 'Gives the picked saved profile the name below.', nil, 'Rename profile');
    imgui.SameLine();
    c.button('Delete##profile_delete', delete_profile, 'Deletes the picked saved profile after you confirm.', nil, 'Delete profile');
    if confirm then
        imgui.TextWrapped((confirm.kind == 'overwrite' and 'This replaces the saved settings in ' or 'This deletes the saved profile ') .. confirm.name .. '.');
        -- The search knows both kinds by the words they begin with, which it finds only while a Confirm waits.
        c.button('Confirm ' .. confirm.kind, confirm_change, nil, nil, 'Confirm ');
        imgui.SameLine();
        c.button('Cancel profile change', cancel_change);
    end
    -- Export to clipboard and Export to a file sit here, as they act on the profile picked just above.
    local text = help_lines();
    c.button('Export to clipboard##profile_share', export_to_clipboard, text.share, nil, 'Export a saved profile');
    imgui.SameLine();
    c.button('Export to a file##profile_save_file', export_to_file, text.save_file, nil, 'Export a saved profile to a file');
    c.row_label('Name', 'What Save as new calls it, and the new name for Rename.');
    imgui.SetNextItemWidth(-(imgui.CalcTextSize('Save as new') + 28));
    imgui.InputTextWithHint('##profile_name', 'Profile name', name_box, 81);
    c.mark('Profile name', 'What Save as new calls it, and the new name for Rename.');
    c.tip('What Save as new calls it, and the new name for Rename.');
    imgui.SameLine();
    c.button('Save as new', save_new, 'Saves your settings as a new profile under this name.');
end

local function job_entries()
    local imgui, job = now.imgui, now.job;
    for id = 1, #jobs do
        if imgui.Selectable(jobs[id], job == id) then picked_job = id; end
    end
end

local function link_job()
    local c = now.c;
    if selected == '' then c.note('Choose a saved profile first.'); return; end
    c.call('profile_link', now.job, selected);
end

local function unlink_job() now.c.call('profile_link', now.job, ''); end
local function unlink_all() now.c.call('reset', 'job_profiles'); end
local function recover_change() now.c.call('profile_recover'); confirm = nil; end

-- Whether names has name.
local function has_name(names, name)
    for _, each in ipairs(names) do if each == name then return true; end end
    return false;
end

-- The jobs the picked profile loads on, a table kept from draw to draw.
local linked = {};

-- Any job can be linked, not only the one you are on.
local function job_links(imgui, settings, view, c, names, status)
    local job = job_shown(view);
    now.job = job;
    list(imgui, c, 'Load this profile when I change to', 'Load this profile when I change to',
        'Pick a job, then Link. Changing to that job loads the saved profile picked above.', '##linked_job', jobs[job], job_entries, 'Link');
    imgui.SameLine();
    c.button('Link##profile_link', link_job, 'Changing to this job loads the saved profile picked above.', nil, 'Link this job');
    local link = link_of(settings, job);
    if link ~= '' then
        c.button('Unlink##profile_unlink', unlink_job, 'Changing to this job loads no profile.', nil, 'Unlink this job');
        imgui.SameLine();
    end
    if page.any_link(settings) then
        c.button('Unlink all jobs', unlink_all, 'No job loads a profile any more. Undo puts the links back.');
    end
    if link ~= '' and not has_name(names, link) then imgui.TextColored(settings.style.warning_color, 'This job refers to a missing profile: ' .. link);
    elseif link ~= '' and link ~= selected then imgui.TextWrapped(jobs[job] .. ' loads ' .. link .. '.'); end
    if selected ~= '' then
        for index = #linked, 1, -1 do linked[index] = nil; end
        for id = 1, #jobs do if link_of(settings, id) == selected then linked[#linked + 1] = jobs[id]; end end
        if #linked > 0 then imgui.TextWrapped('Linked: ' .. table.concat(linked, ', ')); end
    end
    if status.recover_available then
        c.button('Undo the last profile change', recover_change,
            'Puts back the last saved profile ' .. (status.recover_kind or 'change') .. ' if those files have not changed since.');
    end
end

local scopes = { placement = 'Where the panels and party list buffs are', presentation = 'Where things are and how they look' };
local scope_order = { 'placement', 'presentation' };

local function share_toggled(value) now.c.call('sharing', value, now.settings.shared_scope); end

local function scope_entries()
    local imgui, settings, c = now.imgui, now.settings, now.c;
    for _, scope in ipairs(scope_order) do
        if imgui.Selectable(scopes[scope] .. '##' .. scope, settings.shared_scope == scope) then c.call('sharing', settings.shared_layout, scope); end
    end
end

local function across_characters(imgui, settings, c)
    c.heading('Across characters');
    c.check('Share settings across my characters', settings, 'shared_layout', 'Loads existing shared settings before joining. Your later changes to what you share reach your other characters.',
        share_toggled);
    if not settings.shared_layout then return; end
    list(imgui, c, 'What to share', 'What to share across characters',
        'How they look shares panels, appearance, groups, visibility, overhead icons, recast marks, the ready pulse, party cooldowns and the Phantom Roll and pet displays. Job links, alert rules and member names stay with each character.',
        '##Shared settings scope', scopes[settings.shared_scope], scope_entries);
end

-- A string read from the clipboard or a file. base is the name a whole profile starts with, before a number is added
-- for a name already saved.
local function read_string(imgui, c, names, payload, why, base)
    page.clear();
    if not payload then c.note(why or 'That is not a Vantage export.', 'problem_messages'); return; end
    pending = payload;
    -- A line from a read that failed before doesn't stay over this one.
    files = nil;
    c.forget_note();
    if payload.kind ~= 'profile' then return; end
    local placed, screen = payload.data.placement_screen, imgui.GetIO().DisplaySize;
    local width, height = type(placed) == 'table' and tonumber(placed.width) or 0, type(placed) == 'table' and tonumber(placed.height) or 0;
    local mine_width, mine_height = math.floor((screen.x or 0) + 0.5), math.floor((screen.y or 0) + 0.5);
    local differs = width > 0 and height > 0 and mine_width > 0 and mine_height > 0 and (width ~= mine_width or height ~= mine_height);
    other_screen = differs and ('Its displays were placed on a ' .. width .. ' x ' .. height .. ' screen, and yours is ' .. mine_width .. ' x ' .. mine_height .. '.') or nil;
    import_keep.keep = differs;
    import_name[1] = page.free_name(names, base or 'Imported');
end

local function file_entries()
    local imgui = now.imgui;
    for _, file in ipairs(files) do if imgui.Selectable(file .. '##profile_file_' .. file, false) then now.opened = file; end end
end

local function read_file(imgui, callbacks, c, names, text)
    now.opened = nil;
    list(imgui, c, 'File to open', 'File to open', text.file, '##profile_file', 'Choose a file to open', file_entries);
    local opened = now.opened;
    if not opened or not callbacks.shared_read then return; end
    -- The name starts as the file's name without .txt, keeping only what a profile name can have (core/profiles.lua):
    -- plain characters, no ##. It is Imported when nothing is left of it, or when what is left is None.
    local base = opened:gsub('%.[tT][xX][tT]$', ''):gsub('[^\32-\126]', ''):gsub('##', ''):match('^%s*(.-)%s*$');
    local reserved = base:lower() == 'none' or base:lower() == '(none)';
    local payload, why = callbacks.shared_read(opened);
    read_string(imgui, c, names, payload, why, base ~= '' and not reserved and base or 'Imported');
end

local function keep_toggled(value) import_keep.keep = value; end

local function save_import()
    local c, callbacks = now.c, now.callbacks;
    if not callbacks.profile_import then return; end
    local ok, why, saved = callbacks.profile_import(pending, import_name[1], other_screen ~= nil and import_keep.keep);
    if not ok then
        save_problem = why or 'That profile could not be saved.';
        c.note(save_problem, 'problem_messages');
        return;
    end
    page.pick(saved);
    page.clear();
    c.note('Saved "' .. saved .. '" as a new profile. It is not loaded: click Load to use it.', 'done_messages');
end

-- A whole profile can stay out of your settings: saved under a name, not loaded.
local function save_read_profile(imgui, callbacks, c, text)
    imgui.TextWrapped('Or save it as a new profile. It is not loaded, and your screen does not change.');
    if other_screen then
        imgui.TextWrapped(other_screen);
        c.check('Keep my own display positions', import_keep, 'keep', text.keep, keep_toggled);
    end
    c.row_label('Save it as', text.name);
    imgui.SetNextItemWidth(-1);
    imgui.InputTextWithHint('##import_name', 'Profile name', import_name, 81);
    c.mark('Save it as', text.name);
    c.tip(text.name);
    c.button('Save as a new profile', save_import, text.save);
end

-- Import and add, and Import and replace, one for each way an export can go in.
local import_with = {};
for _, mode in ipairs(share.modes) do
    import_with[mode] = function()
        local c = now.c;
        local ok, why = now.callbacks.share_import(pending, mode);
        if ok ~= false then
            c.note((mode == 'add' and 'Added from the export.' or 'Replaced with the export.') .. ' Undo takes it back.', 'done_messages');
            page.clear();
        else c.note(why or 'That export could not be used.', 'problem_messages'); end
    end;
end

-- This also takes away the line a save that failed left, which asks for a name in a box that is gone.
local function clear_import()
    if save_problem then now.c.forget_note(save_problem); end
    page.clear();
end

local function read_result(imgui, settings, callbacks, c, text)
    -- Without a revision to go by, each draw works them out.
    local revision = callbacks.settings_revision and callbacks.settings_revision();
    if (previewed ~= settings or revision == nil or previewed_revision ~= revision) and callbacks.share_preview then
        previews = {};
        for _, mode in ipairs(share.modes) do previews[mode] = callbacks.share_preview(pending, mode) or { 'It could not be read.' }; end
        previewed, previewed_revision = settings, revision;
    end
    imgui.TextWrapped('It holds: ' .. share.describe(pending));
    imgui.TextWrapped('Import and add keeps every setting you changed and takes the rest from it, or adds its rules after yours. It changes:');
    for _, line in ipairs(previews and previews.add or {}) do imgui.BulletText(line); end
    imgui.TextWrapped('Import and replace puts what it holds in place of yours. It changes:');
    for _, line in ipairs(previews and previews.replace or {}) do imgui.BulletText(line); end
    imgui.TextWrapped('Either keeps your own locks and samples. Undo takes it back.');
    for _, mode in ipairs(share.modes) do
        if mode ~= share.modes[1] then imgui.SameLine(); end
        local name = mode == 'add' and 'Import and add' or 'Import and replace';
        c.button(name .. '##share_' .. mode, import_with[mode],
            mode == 'add' and 'Keeps what you changed and takes the rest. One Undo step.' or 'Puts what it holds in place of yours. One Undo step.', nil, name);
    end
    imgui.SameLine();
    c.button('Clear##share_clear', clear_import, 'Forgets the export read. Nothing changes.', nil, 'Clear the import');
    if pending and pending.kind == 'profile' then save_read_profile(imgui, callbacks, c, text); end
end

local function copy_export()
    local c, callbacks = now.c, now.callbacks;
    if not callbacks.share_copy then return; end
    local ok, why, left = callbacks.share_copy(pick.kind, pick.id);
    if ok then c.note('Copied an export of ' .. (pick.kind == 'element' and labels[pick.id] or share.kind_names[pick.kind]:lower()) .. '.'
        .. (left and ' ' .. left or ''), 'done_messages');
    else c.note(why or 'That export could not be made.', 'problem_messages'); end
end

local function import_clipboard()
    local callbacks = now.callbacks;
    if callbacks.share_read then read_string(now.imgui, now.c, now.names, callbacks.share_read()); end
end

local function open_files()
    local c, callbacks = now.c, now.callbacks;
    if not callbacks.shared_files then return; end
    local found, why = callbacks.shared_files();
    files = found;
    if why then c.note(why, 'problem_messages');
    elseif #found == 0 then c.note('There are no .txt files in ' .. help_lines().folder .. ' yet. Put a file there, then click Import from a file again.'); end
end

local function import_export(imgui, settings, callbacks, c, names)
    c.heading('Import and export', 'An export is text that holds part of your settings, for a friend to import into their Vantage. It holds settings only: never your character\'s name, ids or file paths. It goes through the clipboard or a file, so nothing is sent anywhere.');
    -- Copy sits beside the last of the two lists.
    local one_display = pick.kind == 'element';
    c.choice('Export', pick, 'kind', share.kinds, share.kind_names,
        'One display holds everything about it but its switch and lock. Where everything is holds where every display sits. Whole profile holds every setting.', nil, not one_display and 'Copy' or nil);
    if one_display then c.choice('Display to export', pick, 'id', ids, labels, nil, nil, 'Copy'); end
    imgui.SameLine();
    c.button('Copy##share_copy', copy_export, 'Copies it to the clipboard. Nothing is sent anywhere.', nil, 'Copy the export');
    local text = help_lines();
    c.button('Import from clipboard', import_clipboard, text.read);
    imgui.SameLine();
    c.button('Import from a file##profile_open_file', open_files, text.open_file, nil, 'Import from a file');
    if files and #files > 0 then read_file(imgui, callbacks, c, names, text); end
    if pending then read_result(imgui, settings, callbacks, c, text); end
end

local PUT_BACK = 'Every display goes back to its first spot, locked. Looks and choices are kept.';
local RESET_ALL = 'Every display goes back to a fresh install: locked, in its first spot. Profiles, job links, watched enemies and learned times are kept.';

local function shaded(imgui, c, value)
    imgui.PushStyleColor(ImGuiCol_Text, c.look.notes);
    imgui.TextWrapped(value);
    imgui.PopStyleColor();
end

local function put_back() now.c.call('reset', 'displays'); end
local function reset_all() now.c.call('reset', 'all'); end

local function start_over(imgui, c)
    c.heading('Start over');
    c.button('Put every display back where it started', put_back, PUT_BACK .. ' Undo takes it back.');
    shaded(imgui, c, PUT_BACK);
    c.button('Reset all settings', reset_all, RESET_ALL .. ' Undo takes it back.');
    shaded(imgui, c, RESET_ALL);
end

function page.draw(imgui, settings, view, callbacks, c)
    local names, problem, status = page.choices(callbacks);
    now.imgui, now.settings, now.callbacks, now.c, now.names = imgui, settings, callbacks, c, names;
    saved_profiles(imgui, settings, callbacks, c, names, problem, status);
    job_links(imgui, settings, view, c, names, status);
    across_characters(imgui, settings, c);
    import_export(imgui, settings, callbacks, c, names);
    start_over(imgui, c);
end

return page;
