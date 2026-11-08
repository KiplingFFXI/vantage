-- Profile sharing on Profiles and sharing, through the real vantage.lua and settings window. Export to clipboard copies the picked
-- saved profile as a whole profile export without loading it, the same string loading it and copying it gives,
-- and changes neither the settings nor Undo. Export to a file writes that string to a new file in the shared folder,
-- named from the profile's letters, digits, spaces, - and _ only, without a name of a character on this PC or of the
-- Windows user, never over a file, not even one made while it writes, and never outside that folder.
-- Import from clipboard reads one, and Import from a file reads a .txt file there (at most an export's length). A whole
-- profile can then be saved as a new profile under a name you pick: at first "Imported" from the clipboard and the
-- file's name from a file, kept to what a profile name can have, with " 2" and so on when that is saved already. A name
-- in use asks for another, and Clear takes that line away with the string. It is not loaded, is picked so Load uses it,
-- and has your own locks, job links, members, watched enemies, diagnostics and chat colors. When it was placed on
-- another screen size the page says so, and Keep my own display positions is ticked. Any other kind of string reads the
-- same way, for Import and add or Import and replace, and one from a newer Vantage says so in plain words.
local defaults, store, share, json = require('ui.defaults'), require('core.store'), require('core.share'), require('core.json');
local equal = require('core.customization').equal;
local imgui = require('imgui');
local NAME, FRIEND, MEMBER = 'Tester', 'Brightwing', 3987654321;
MOCK.screen = { 1920, 1080 };
MOCK.dirs = MOCK.dirs or {};
local snapshot = { valid = true, id = 1001, name = NAME, zone = 102, job = 17, level = 75, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window = require('ui.settings_window');
local root = require('core.identity').root();
local shared = root .. 'shared/';
local clipboard, combo, previews = nil, nil, {};
rawset(imgui, 'GetClipboardText', function() return clipboard; end);
rawset(imgui, 'BeginCombo', function(label, preview) previews[label] = preview; return label == combo; end);
rawset(imgui, 'EndCombo', function() end);
local function draw(click, opened)
    local s = app.state.settings;
    s.window.open, s.window.tab = true, 'Profiles';
    combo, MOCK.imgui_calls = opened, {};
    if click then MOCK.clicks[click] = true; end;
    window.draw(s, { rows = {}, context = { valid = true, entities = {} } }, app.callbacks);
    assert(not click or not MOCK.clicks[click], 'The control is on the Profiles page: ' .. tostring(click));
    MOCK.clicks = {};
end;
-- Whether the last frame drew text holding words, and the call that drew a control.
local function shown(words)
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'TextWrapped' or call[1] == 'Text') and type(call[2]) == 'string' and call[2]:find(words, 1, true) then return true; end;
    end;
    return false;
end;
local function drawn(name, label)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == name and call[2] == label then return call; end; end;
end;
-- The calls between the label Save it as and the name box, by name; nil without the label.
local function before_box()
    local from;
    for index, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'TextUnformatted' or call[1] == 'TextWrapped') and call[2] == 'Save it as' then from = index; end;
        if from and call[1] == 'InputTextWithHint' and call[2] == '##import_name' then
            local names = {};
            for at = from + 1, index - 1 do names[#names + 1] = MOCK.imgui_calls[at][1]; end;
            return table.concat(names, ' ');
        end;
    end;
    return nil;
end;
-- The settings but the window's own state, and the saved profiles as the file holds them.
local function live() local value = store.copy(app.state.settings); value.window = nil; return value; end;
local function saved() return store.read(root .. 'profiles.json'); end;
local function read_file(path) local file = io.open(path, 'rb'); if not file then return nil; end; local text = file:read('*a'); file:close(); return text; end;
local function data_of(text) return json.decode(text:match('^VG:1:%x+:(.+)$')).data; end;
local function pick(name) draw(name, '##profiles'); draw(); assert(previews['##profiles'] == name, 'Fixture: ' .. name .. ' is picked.'); end;

-- Your own settings: locks on, a job link, a member, a watched enemy, diagnostics and chat colors of your own.
local s = app.state.settings;
s.panels.target.width, s.rolls.x, s.panels.self_buffs.x, s.panels.self_buffs.y = 333, 222, 150, 160;
s.placement_screen = { width = 1920, height = 1080 };
assert(app.callbacks.profile_save('Raid', false), 'Fixture: Raid is saved.');
s = app.state.settings;
s.panels.target.width = 250;
s.panels.party.members = { [MEMBER] = true };
s.watch_ids = { MEMBER };
s.job_profiles['17'] = 'Raid';
s.diagnostics.record, s.diagnostics.max_entries = false, 300;
s.chat_colors.tag_word, s.chat_colors.replies = 7, 8;
assert(app.callbacks.profile_save('Solo', false), 'Fixture: Solo is saved.');
s = app.state.settings;
s.active_profile = 'Raid';
app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
draw(); draw();

do -- Section: Share copies the picked saved profile without loading it.
    pick('Raid');
    local before, undo = live(), #app.state.history;
    MOCK.clipboard = nil;
    draw('Export to clipboard##profile_share'); draw();
    assert(type(MOCK.clipboard) == 'string' and MOCK.clipboard:find('^VG:1:'), 'Share puts an export on the clipboard.');
    assert(data_of(MOCK.clipboard).panels.target.width == 333, 'It is the saved profile, not the settings on screen.');
    assert(equal(before, live()) and app.state.settings.panels.target.width == 250 and app.state.settings.active_profile == 'Raid',
        'The settings on screen don\'t change.');
    assert(#app.state.history == undo and #app.state.redo == 0 and app.state.transaction == nil, 'Nothing is added to Undo.');
    assert(shown('Copied "Raid". Send it in a message, or use Export to a file to keep it as a file.'), 'The status line says it was copied, and where it can go.');
    assert(not MOCK.clipboard:find(NAME, 1, true) and not MOCK.clipboard:find(tostring(MEMBER), 1, true), 'It holds no name or id.');
    -- The same string Load, then Copy of a whole profile, give.
    local copied = MOCK.clipboard;
    draw('Load##profile_load'); draw();
    assert(app.state.settings.panels.target.width == 333, 'Fixture: Raid is loaded.');
    -- The same data: JSON keeps the order the tables give their keys in, which can differ between two tables.
    assert(app.callbacks.share_copy('profile') and equal(data_of(MOCK.clipboard), data_of(copied)), 'Share gives what loading it and copying it gives.');
    MOCK.fire('command', { command = '/vg undo' });
    assert(app.state.settings.panels.target.width == 250, 'Fixture: Undo takes the load back.');
end; -- end of section

do -- Section: Export to a file writes it to a new file in the shared folder, never over one.
    pick('Raid');
    local before, undo = live(), #app.state.history;
    draw('Export to a file##profile_save_file'); draw();
    local first = read_file(shared .. 'Raid.txt');
    assert(first and first:find('^VG:1:') and data_of(first).panels.target.width == 333, 'The file holds the export of Raid.');
    assert(shown('Saved "Raid" as config/addons/vantage/shared/Raid.txt. A friend puts it in their own shared folder and uses Import from a file.'),
        'The status line names the file.');
    draw('Export to a file##profile_save_file'); draw();
    assert(read_file(shared .. 'Raid 2.txt') == first and read_file(shared .. 'Raid.txt') == first, 'A second save is Raid 2.txt; Raid.txt stays.');
    assert(equal(before, live()) and #app.state.history == undo, 'The settings and Undo don\'t change.');
end; -- end of section

-- A friend's whole profile, placed on a 2560 x 1440 screen, with their own locks, diagnostics and chat colors.
local friend = defaults.tidy(defaults.make());
friend.panels.target.width, friend.panels.target.mode, friend.panels.self_buffs.x, friend.panels.self_buffs.y = 410, 'bars', 2000, 1200;
friend.panels.self_buffs.locked, friend.rolls.locked = false, false;
friend.placement_screen = { width = 2560, height = 1440 };
friend.diagnostics.record, friend.chat_colors.tag_word = true, 100;
local rule = defaults.rule('rule_1'); rule.name, rule.effect = 'Haste reminder', 33;
friend.alerts.rules = { rule };
friend = defaults.tidy(friend);
local from_friend = assert(share.export(friend, 'profile', nil, FRIEND));

do -- Section: Save as a new profile saves the clipboard's whole profile, not loaded.
    clipboard = from_friend;
    local before, undo, redo, names = live(), #app.state.history, #app.state.redo, #app.callbacks.profile_list();
    draw('Import from clipboard'); draw();
    assert(not shown('A whole profile. Saving it adds it to your saved profiles.'), 'The page doesn\'t say again what saving it does.');
    -- Save it as names the box, on the box's line, and above it in a narrow window.
    assert(before_box() == 'SameLine IsItemHovered SetNextItemWidth', 'Save it as is before the name box: ' .. tostring(before_box()));
    MOCK.content_width = 240; draw(); MOCK.content_width = nil;
    assert(before_box() == 'IsItemHovered SetNextItemWidth', 'In a narrow window Save it as is above the box: ' .. tostring(before_box()));
    draw();
    assert(shown('Its displays were placed on a 2560 x 1440 screen, and yours is 1920 x 1080.'), 'It says the screen sizes differ.');
    local keep = drawn('Checkbox', 'Keep my own display positions');
    assert(keep and keep[3][1] == true, 'Keep my own display positions is ticked.');
    local name = drawn('InputTextWithHint', '##import_name');
    assert(name and name[4][1] == 'Imported', 'The name is Imported.');
    assert(equal(before, live()) and #app.callbacks.profile_list() == names, 'Reading it saves and changes nothing.');
    draw('Save as a new profile'); draw();
    local list = app.callbacks.profile_list();
    assert(#list == names + 1 and saved().Imported, 'It is saved as a new profile, Imported.');
    assert(equal(before, live()) and app.state.settings.active_profile == 'Raid', 'It is not loaded: the settings on screen don\'t change.');
    assert(#app.state.history == undo and #app.state.redo == redo and app.state.transaction == nil, 'Nothing is added to Undo.');
    assert(previews['##profiles'] == 'Imported', 'It is picked, so Load uses it.');
    assert(shown('Saved "Imported" as a new profile. It is not loaded: click Load to use it.'), 'The status line says so.');
    assert(not drawn('InputTextWithHint', '##import_name'), 'The name box goes once it is saved.');
    local imported = saved().Imported;
    assert(imported.panels.target.mode == 'bars' and #imported.alerts.rules == 1, 'It holds the friend\'s settings.');
    assert(imported.panels.self_buffs.locked == true and imported.rolls.locked == true, 'It keeps your locks.');
    assert(imported.diagnostics.record == false and imported.diagnostics.max_entries == 300 and imported.chat_colors.tag_word == 7
        and imported.chat_colors.replies == 8, 'It keeps your diagnostics settings and chat colors.');
    assert(imported.panels.self_buffs.x == 150 and imported.panels.self_buffs.y == 160 and imported.panels.target.width == 250
        and imported.placement_screen.width == 1920, 'Keep my own display positions keeps where your displays are, their sizes and your screen.');
    -- Load, one click.
    draw('Load##profile_load'); draw();
    local now = app.state.settings;
    assert(now.panels.target.mode == 'bars' and now.active_profile == 'Imported', 'Load loads it.');
    assert(now.job_profiles['17'] == 'Raid' and now.panels.party.members[MEMBER] and now.watch_ids[1] == MEMBER,
        'Your job links, members and watched enemies stay.');
    assert(now.panels.self_buffs.locked and now.rolls.locked and not now.diagnostics.record and now.chat_colors.tag_word == 7,
        'Your locks, diagnostics and chat colors stay.');
    MOCK.fire('command', { command = '/vg undo' });
    assert(app.state.settings.panels.target.mode ~= 'bars' and app.state.settings.active_profile == 'Raid', 'Fixture: Undo takes the load back.');
end; -- end of section

do -- Section: the name is the first free one, and a name in use asks for another.
    clipboard = from_friend;
    draw('Import from clipboard'); draw();
    local name = drawn('InputTextWithHint', '##import_name');
    assert(name and name[4][1] == 'Imported 2', 'With Imported saved, the name is Imported 2.');
    local names = #app.callbacks.profile_list();
    name[4][1] = 'raid';
    draw('Save as a new profile'); draw();
    assert(shown('A profile with that name is already saved. Type another name.') and not shown('Overwrite')
        and #app.callbacks.profile_list() == names, 'A name in use, in any case, asks for another and says nothing of Overwrite.');
    assert(drawn('InputTextWithHint', '##import_name'), 'The profile read waits for another name.');
    -- Clear's tooltip, with the mouse over Clear only.
    rawset(imgui, 'IsItemHovered', function()
        local last = MOCK.imgui_calls[#MOCK.imgui_calls];
        return last ~= nil and last[1] == 'Button' and last[2] == 'Clear##share_clear';
    end);
    draw();
    rawset(imgui, 'IsItemHovered', nil);
    local clear;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Button' and call[2] == 'Clear##share_clear' then clear = false;
        elseif clear == false and call[1] == 'TextUnformatted' then clear = call[2]; end;
    end;
    assert(clear == 'Forgets the export read. Nothing changes.', 'Clear says what it does: ' .. tostring(clear));
    draw('Clear##share_clear'); draw();
    assert(not drawn('InputTextWithHint', '##import_name') and #app.callbacks.profile_list() == names, 'Clear forgets it and saves nothing.');
    assert(not shown('A profile with that name is already saved.'), 'Clear takes away the line asking for another name.');
    -- A line about something else stays.
    draw('Import from clipboard'); draw();
    draw('Export to clipboard##profile_share'); draw();
    assert(shown('Copied "'), 'Fixture: Share says what it copied.');
    draw('Clear##share_clear'); draw();
    assert(shown('Copied "') and not drawn('InputTextWithHint', '##import_name'), 'Clear leaves a line about something else.');
    -- Save as new has Overwrite beside it, so its own message stays.
    drawn('InputTextWithHint', '##profile_name')[4][1] = 'raid';
    draw('Save as new'); draw();
    assert(shown('That profile already exists. Choose a new name or use Overwrite.') and #app.callbacks.profile_list() == names,
        'Save as new keeps its message for a name in use.');
end; -- end of section

do -- Section: untick Keep my own display positions to take the profile's; the same screen size asks nothing.
    clipboard = from_friend;
    draw('Import from clipboard'); draw();
    draw('Keep my own display positions'); draw();
    assert(drawn('Checkbox', 'Keep my own display positions')[3][1] == false, 'It unticks.');
    drawn('InputTextWithHint', '##import_name')[4][1] = 'Theirs';
    draw('Save as a new profile'); draw();
    local theirs = saved().Theirs;
    assert(theirs and theirs.panels.self_buffs.x == 2000 and theirs.panels.self_buffs.y == 1200 and theirs.panels.target.width == 410
        and theirs.placement_screen.width == 2560, 'Unticked, the profile keeps its own positions, sizes and screen.');
    local same = store.copy(friend);
    same.placement_screen = { width = 1920, height = 1080 };
    clipboard = assert(share.export(same, 'profile', nil, FRIEND));
    draw('Import from clipboard'); draw();
    assert(drawn('InputTextWithHint', '##import_name') and not drawn('Checkbox', 'Keep my own display positions')
        and not shown('Its displays were placed on'), 'Placed on your screen size, it says nothing of positions.');
    drawn('InputTextWithHint', '##import_name')[4][1] = 'Same screen';
    draw('Save as a new profile'); draw();
    assert(saved()['Same screen'].panels.self_buffs.x == 2000, 'and takes the profile\'s positions.');
end; -- end of section

do -- Section: another kind of string reads the same way, with no name to save; one from a newer Vantage says so.
    local names = #app.callbacks.profile_list();
    clipboard = assert(share.export(friend, 'element', 'rolls', FRIEND));
    draw('Import from clipboard'); draw();
    assert(shown('It holds: One display: Phantom Roll.') and drawn('Button', 'Import and add##share_add') and drawn('Button', 'Import and replace##share_replace')
        and not drawn('InputTextWithHint', '##import_name') and not drawn('Button', 'Save as a new profile'),
        'Another kind reads for Import and add or Import and replace, with nothing to save it as.');
    local body = from_friend:match('^VG:1:%x+:(.+)$'):gsub('^{', '{"later":1,');
    clipboard = 'VG:1:' .. share.crc32(body) .. ':' .. body;
    draw('Import from clipboard'); draw();
    assert(shown('This was made with a newer Vantage. Update Vantage to read it.') and not shown('which the settings do not have'),
        'A newer string says so in plain words.');
    clipboard = from_friend:gsub('^VG:1:', 'VG:2:');
    draw('Import from clipboard'); draw();
    assert(shown('This was made with a newer Vantage. Update Vantage to read it.'), 'and so does a newer version.');
    assert(#app.callbacks.profile_list() == names, 'Nothing is saved.');
    -- A whole profile read next doesn't show that line over it.
    clipboard = from_friend;
    draw('Import from clipboard'); draw();
    assert(drawn('InputTextWithHint', '##import_name') and not shown('newer Vantage'), 'A read that works takes the last line away.');
    draw('Clear##share_clear'); draw();
    assert(#app.callbacks.profile_list() == names, 'and Clear saves nothing.');
end; -- end of section

do -- Section: Import from a file lists the .txt files in the shared folder and reads the one picked, named after it.
    MOCK.dirs[shared] = { 'Raid.txt', 'notes.md', 'Raid 2.txt', 'sub\\evil.txt', 'Raid.txt.1.2.tmp' };
    draw('Import from a file##profile_open_file'); draw(nil, '##profile_file');
    assert(drawn('Selectable', 'Raid.txt##profile_file_Raid.txt') and drawn('Selectable', 'Raid 2.txt##profile_file_Raid 2.txt'), 'The .txt files are listed.');
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Selectable' then assert(not call[2]:find('notes.md', 1, true) and not call[2]:find('evil', 1, true)
            and not call[2]:find('.tmp', 1, true), 'Only .txt files of the shared folder are listed: ' .. call[2]); end;
    end;
    local before, names = live(), #app.callbacks.profile_list();
    draw('Raid.txt##profile_file_Raid.txt', '##profile_file'); draw();
    local name = drawn('InputTextWithHint', '##import_name');
    assert(name and name[4][1] == 'Raid 2', 'The name is the file\'s without .txt, Raid 2 with Raid saved: ' .. tostring(name and name[4][1]));
    draw('Save as a new profile'); draw();
    assert(#app.callbacks.profile_list() == names + 1 and saved()['Raid 2'].panels.target.width == 333 and equal(before, live()),
        'It is saved as a new profile, not loaded.');
    -- .txt in any case and the spaces around the name go; with nothing left it is Imported; a long name is cut to the
    -- 40 characters a profile name can have, its number kept. Letters a profile name can't have and ## are left out, so
    -- the name always saves and is never cut in the middle of a letter.
    local long = ('Long name '):rep(6);
    for _, case in ipairs({ { ' Night raid .TXT', 'Night raid' }, { '.txt', 'Imported 2' }, { long .. '.txt', long:sub(1, 39) },
        { long .. '.txt', long:sub(1, 38) .. ' 2' }, { 'Caf\195\169 raid.txt', 'Caf raid' }, { 'Raid##night.txt', 'Raidnight' },
        { ('a'):rep(39) .. '\195\169b.txt', ('a'):rep(39) .. 'b' } }) do
        local file = assert(io.open(shared .. case[1], 'wb'));
        file:write(from_friend);
        file:close();
        MOCK.dirs[shared] = { case[1] };
        draw('Import from a file##profile_open_file'); draw(case[1] .. '##profile_file_' .. case[1], '##profile_file'); draw();
        name = drawn('InputTextWithHint', '##import_name');
        assert(name and name[4][1] == case[2], 'The name for ' .. case[1] .. ' is ' .. case[2] .. ': ' .. tostring(name and name[4][1]));
        draw('Save as a new profile'); draw();
        assert(saved()[case[2]] and not drawn('InputTextWithHint', '##import_name'), case[2] .. ' is saved.');
    end;
    -- A name with nothing a profile name can have left, or None, which is kept for turning off a job profile, is
    -- Imported too.
    for _, case in ipairs({ '\195\169\195\168 .txt', 'None.txt' }) do
        local file = assert(io.open(shared .. case, 'wb'));
        file:write(from_friend);
        file:close();
        MOCK.dirs[shared] = { case };
        draw('Import from a file##profile_open_file'); draw(case .. '##profile_file_' .. case, '##profile_file'); draw();
        assert(drawn('InputTextWithHint', '##import_name')[4][1] == 'Imported 3', 'The name for ' .. case .. ' is Imported 3.');
        draw('Clear##share_clear'); draw();
    end;
    -- From the clipboard it is still Imported, with the next free number.
    clipboard = from_friend;
    draw('Import from clipboard'); draw();
    assert(drawn('InputTextWithHint', '##import_name')[4][1] == 'Imported 3', 'The clipboard\'s is Imported 3.');
    draw('Clear##share_clear'); draw();
    MOCK.dirs[shared] = {};
    draw('Import from a file##profile_open_file'); draw();
    assert(shown('There are no .txt files in config/addons/vantage/shared/ yet. Put a file there, then click Import from a file again.'),
        'An empty folder says where the files go.');
end; -- end of section

do -- Section: a file longer than an export is read no further and refused.
    local path = shared .. 'Huge.txt';
    local file = assert(io.open(path, 'wb'));
    file:write(from_friend, (' '):rep(share.MOST));
    file:close();
    local open, asked = io.open, {};
    io.open = function(target, mode)
        local handle, why = open(target, mode);
        if target ~= path or not handle then return handle, why; end;
        return { read = function(_, size) asked[#asked + 1] = size; return handle:read(size); end, close = function() return handle:close(); end };
    end;
    MOCK.dirs[shared] = { 'Huge.txt' };
    draw('Import from a file##profile_open_file'); draw('Huge.txt##profile_file_Huge.txt', '##profile_file'); draw();
    io.open = open;
    assert(#asked == 1 and asked[1] == share.MOST + 1, 'It reads at most an export\'s length and one more byte: ' .. tostring(asked[1]));
    assert(shown('That text is too long to be an export.') and not drawn('InputTextWithHint', '##import_name'), 'and refuses it.');
end; -- end of section

do -- Section: file names keep letters, digits, spaces, - and _ only; nothing is written outside the shared folder.
    for _, case in ipairs({ { 'Raid/WHM', 'RaidWHM' }, { '..\\..\\evil', 'evil' }, { 'CON', 'CON profile' }, { 'What?', 'What' },
        { 'a:b', 'ab' }, { 'x*y', 'xy' }, { '', 'profile' }, { ' . ', 'profile' }, { 'nul', 'nul profile' }, { 'LPT1', 'LPT1 profile' },
        { 'My raid_2-b', 'My raid_2-b' } }) do
        assert(share.file_name(case[1]) == case[2], 'The file name of ' .. case[1] .. ' is ' .. case[2] .. ': ' .. share.file_name(case[1]));
    end;
    local cases = { { 'Raid/WHM', 'RaidWHM' }, { '..\\..\\evil', 'evil' }, { 'CON', 'CON profile' }, { 'What?', 'What' },
        { 'a:b', 'ab' }, { 'x*y', 'xy' } };
    for _, case in ipairs(cases) do assert(app.callbacks.profile_save(case[1], false), 'Fixture: a profile named ' .. case[1] .. ' is saved.'); end;
    local open, create_dir, writes = io.open, ashita.fs.create_dir, {};
    for _, case in ipairs(cases) do
        pick(case[1]);
        -- Every file opened to write and folder made while Export to a file is clicked.
        io.open = function(target, mode)
            if mode and mode:find('[wa+]') then writes[#writes + 1] = target; end;
            return open(target, mode);
        end;
        ashita.fs.create_dir = function(target) writes[#writes + 1] = target .. '/'; return create_dir(target); end;
        draw('Export to a file##profile_save_file');
        io.open, ashita.fs.create_dir = open, create_dir;
        draw();
        assert(read_file(shared .. case[2] .. '.txt'), case[1] .. ' is saved as ' .. case[2] .. '.txt in the shared folder.');
    end;
    for _, target in ipairs(writes) do
        assert(target == shared or target:sub(1, #shared) == shared and not target:sub(#shared + 1):find('[\\/]'),
            'Written only in the shared folder: ' .. target);
    end;
    assert(#writes > 0 and not read_file(root .. '../../evil.txt') and not read_file(root .. 'evil.txt'), 'Nothing lands outside it.');
    assert(share.save_file(shared, '', 'VG:1:0:{}') == 'profile.txt' and read_file(shared .. 'profile.txt') == 'VG:1:0:{}', 'An empty name is profile.txt.');
end; -- end of section

do -- Section: the file name leaves out your name, the Windows user's and the other characters' on this PC.
    for _, case in ipairs({ { 'Brightwing raid', 'raid' }, { 'Raid brightwing WHM', 'Raid WHM' }, { 'Brightwing', 'profile' },
        { 'Brightwings', 'Brightwings' }, { 'WHM (Brightwing)', 'WHM' } }) do
        local made = share.file_name(case[1], { FRIEND });
        assert(made == case[2], 'The file name of ' .. case[1] .. ' is ' .. case[2] .. ': ' .. made);
    end;
    local getenv = os.getenv;
    os.getenv = function(key) if key == 'USERNAME' then return 'Winuser'; end; return getenv(key); end;
    MOCK.dirs[root] = { FRIEND .. '_2002', NAME .. '_1001', 'profiles.json', 'shared' };
    for _, case in ipairs({ { FRIEND .. ' trial', 'trial' }, { NAME .. ' WHM', 'WHM' }, { 'winuser setup', 'setup' } }) do
        assert(app.callbacks.profile_save(case[1], false), 'Fixture: a profile named ' .. case[1] .. ' is saved.');
        pick(case[1]);
        draw('Export to a file##profile_save_file'); draw();
        assert(read_file(shared .. case[2] .. '.txt') and shown('Saved "' .. case[1] .. '" as config/addons/vantage/shared/' .. case[2] .. '.txt.'),
            case[1] .. ' is saved as ' .. case[2] .. '.txt, and the status line names that file.');
        assert(not read_file(shared .. case[1] .. '.txt'), 'No file is named ' .. case[1] .. '.');
    end;
    os.getenv, MOCK.dirs[root] = getenv, nil;
end; -- end of section

do -- Section: a file there is never replaced.
    assert(store.create(shared .. 'Keep.txt', 'mine'), 'Fixture: a file of yours.');
    local ok, why, code = store.create(shared .. 'Keep.txt', 'theirs');
    assert(not ok and code == 'exists' and why:find('already exists', 1, true) and read_file(shared .. 'Keep.txt') == 'mine',
        'Writing a file that is there writes nothing.');
    assert(share.save_file(shared, 'Keep', 'theirs') == 'Keep 2.txt' and read_file(shared .. 'Keep.txt') == 'mine'
        and read_file(shared .. 'Keep 2.txt') == 'theirs', 'Export to a file takes the next free name.');
    -- A file made after the look for one and before the move stays as well, and the temporary file goes.
    assert(store.create(shared .. 'Race.txt', 'mine'), 'Fixture: Race.txt is made.');
    local exists, open, asked, temps = ashita.fs.exists, io.open, 0, {};
    ashita.fs.exists = function(path)
        if path == shared .. 'Race.txt' then asked = asked + 1; if asked == 1 then return false; end; end;
        return exists(path);
    end;
    io.open = function(target, mode)
        if mode and mode:find('w', 1, true) and target:match('%.tmp$') then temps[#temps + 1] = target; end;
        return open(target, mode);
    end;
    local saved_as = share.save_file(shared, 'Race', 'theirs');
    ashita.fs.exists, io.open = exists, open;
    assert(saved_as == 'Race 2.txt' and read_file(shared .. 'Race.txt') == 'mine' and read_file(shared .. 'Race 2.txt') == 'theirs',
        'A file made meanwhile is not replaced: ' .. tostring(saved_as));
    assert(#temps == 2 and not read_file(temps[1]) and not read_file(temps[2]), 'No temporary file is left.');
end; -- end of section

rawset(imgui, 'GetClipboardText', nil);
rawset(imgui, 'BeginCombo', nil);
rawset(imgui, 'EndCombo', nil);
MOCK.fire('unload');
return 'Profiles share, save to a file, import and open a file';
