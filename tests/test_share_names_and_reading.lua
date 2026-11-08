-- Exports (core/share.lua): a whole profile also leaves out the names of every character with a settings folder
-- on this PC, and names are looked for in sound and font names too. Reading takes the string out of what Discord and
-- chat add around it (code marks, quote marks, line breaks and text), and the checksum still finds any change. A
-- string from a newer Vantage, another version or a key these settings lack, is refused in plain words. Pasting a
-- fresh profile into fresh settings shows no changes, and an import keeps your diagnostics settings and chat colors.
local share, defaults, json = require('core.share'), require('ui.defaults'), require('core.json');
local NAME, ALT, OTHER = 'Tester', 'Brightwing', 'Moonfall';
local root = require('core.identity').root();
MOCK.dirs = MOCK.dirs or {};
local function fresh() return defaults.tidy(defaults.make()); end;
local function data_of(text) return json.decode(text:match('^VG:1:%x+:(.+)$')).data; end;

do -- Section: the names of the other characters with settings on this PC are left out of a whole profile.
    MOCK.dirs[root] = { ALT .. '_2002', NAME .. '_1001', 'profiles.json', 'shared', 'sounds', 'cache', 'reports' };
    local names = share.local_names(root);
    table.sort(names);
    assert(#names == 2 and names[1] == ALT and names[2] == NAME, 'The character folders give their names: ' .. table.concat(names, ', '));
    local s = fresh();
    s.panels.self_buffs.title = ALT .. ' buffs';
    s.panels.target.labels = { [33] = 'Haste (' .. ALT .. ')' };
    s.overhead.head.offsets = { [ALT] = 0.4, Crab = 0.3 };
    local rule = defaults.rule('rule_1'); rule.name, rule.effect = 'Haste on ' .. ALT, 33;
    s.alerts.rules = { rule };
    s = defaults.tidy(s);
    local text = assert(share.export(s, 'profile', nil, NAME));
    assert(not text:lower():find(ALT:lower(), 1, true), 'A whole profile holds no name of a character on this PC.');
    local data = data_of(text);
    assert(data.overhead.head.offsets.Crab == 0.3 and #data.alerts.rules == 1 and data.alerts.rules[1].name == ''
        and data.panels.self_buffs.title == '', 'What names one is blanked or left out, and the rest stays.');
    -- Ashita may list only a folder's files: then the settings files in the folders below give the names.
    local listing = ashita.fs.get_directory;
    ashita.fs.get_directory = function(path, _, below)
        if path ~= root then return {}; end;
        return below and { OTHER .. '_3003\\settings.json', 'cache\\client-fonts\\x.bin', 'profiles.json' } or { 'profiles.json' };
    end;
    local from_files = share.local_names(root);
    s.panels.self_buffs.title = OTHER .. ' buffs';
    text = assert(share.export(s, 'profile', nil, NAME));
    ashita.fs.get_directory = listing;
    assert(#from_files == 1 and from_files[1] == OTHER and not text:find(OTHER, 1, true), 'and so are theirs.');
    MOCK.dirs[root] = nil;
end; -- end of section

do -- Section: whichever way Ashita's listing gives a folder's folders, their names are found.
    local listing = ashita.fs.get_directory;
    local forms = {
        -- The folders come only with the third argument true, and nothing below them.
        function(_, _, folders) return folders == true and { ALT .. '_2002', 'profiles.json' } or { 'profiles.json' }; end,
        -- Only the folder asked for alone lists its folders, each with a slash after it.
        function(...) return select('#', ...) == 1 and { ALT .. '_2002\\', 'profiles.json' } or { 'profiles.json' }; end,
        -- The third argument true lists the files in the folders below.
        function(_, _, below) return below == true and { ALT .. '_2002\\settings.json', 'cache\\x.bin' } or { 'profiles.json' }; end,
        -- Every listing has the folders.
        function() return { ALT .. '_2002', 'cache', 'reports' }; end,
    };
    for index, form in ipairs(forms) do
        ashita.fs.get_directory = function(path, ...) if path ~= root then return {}; end; return form(path, ...); end;
        local names = share.local_names(root);
        ashita.fs.get_directory = listing;
        assert(#names == 1 and names[1] == ALT, 'Listing ' .. index .. ' gives the name: ' .. table.concat(names, ', '));
    end;
    ashita.fs.get_directory = function() error('The folder could not be listed.'); end;
    local names = share.local_names(root);
    ashita.fs.get_directory = listing;
    assert(#names == 0, 'A listing that fails gives no names, and no error.');
end; -- end of section

do -- Section: names are looked for in sound and font names too.
    local s = fresh();
    local mine, theirs = defaults.rule('rule_1'), defaults.rule('rule_2');
    mine.sound, mine.effect, theirs.sound, theirs.effect = NAME .. '.wav', 33, 'Haste.mp3', 40;
    s.alerts.rules = { mine, theirs };
    s.style.font, s.rolls.font = NAME, NAME;
    s = defaults.tidy(s);
    assert(s.alerts.rules[1].sound == NAME .. '.wav', 'Fixture: the sound named after you is kept by tidy.');
    for _, kind in ipairs({ 'alerts', 'profile' }) do
        local text = assert(share.export(s, kind, nil, NAME));
        assert(not text:find(NAME, 1, true), kind .. ': a sound or font named after you is left out.');
        local rules = kind == 'alerts' and data_of(text).rules or data_of(text).alerts.rules;
        assert(rules[1].sound == '' and rules[2].sound == 'Haste.mp3', kind .. ': other sounds stay.');
    end;
end; -- end of section

do -- Section: a string wrapped by Discord or chat reads; any change inside it is still refused.
    local small = assert(share.export(fresh(), 'alerts', nil, NAME));
    local whole = assert(share.export(fresh(), 'profile', nil, NAME));
    for _, case in ipairs({
        { 'inline code', '`' .. small .. '`' }, { 'a code block', '```\n' .. small .. '\n```' },
        { 'a code block with a language', '```text\r\n' .. small .. '\r\n```\r\n' }, { 'a quote', '> ' .. small },
        { 'a quote in code', '> `' .. small .. '`' }, { 'a line before', 'Here is my profile:\n' .. small },
        { 'text after', small .. ' thanks!' }, { 'a whole profile in a code block', '```\n' .. whole .. '\n```' },
        { 'a line break after the checksum', small:gsub('^(VG:1:%x+:)', '%1\n> ') } }) do
        local payload, why = share.read(case[2]);
        assert(payload and payload.kind == (case[2]:find('"profile"', 1, true) and 'profile' or 'alerts'), case[1] .. ' reads: ' .. tostring(why));
    end;
    local damaged = small:sub(1, -3) .. (small:sub(-2, -2) == '1' and '2' or '1') .. small:sub(-1);
    for _, text in ipairs({ '`' .. damaged .. '`', '> ' .. damaged, 'Look: ' .. small:sub(1, -2) .. ' }' }) do
        local payload, why = share.read(text);
        assert(payload == nil and why:find('checksum', 1, true), 'A change inside the string is still refused: ' .. tostring(why));
    end;
    local payload, why = share.read('My VG: notes, and no string');
    assert(payload == nil and why == 'That text is not a Vantage export.', 'Text without a string is still not one: ' .. tostring(why));
end; -- end of section

do -- Section: a string from a newer Vantage is refused in plain words.
    local function string_of(payload)
        local body = require('core.store').encode(payload);
        return 'VG:1:' .. share.crc32(body) .. ':' .. body;
    end;
    local good = assert(share.export(fresh(), 'element', 'rolls', NAME));
    for _, case in ipairs({ { good:gsub('^VG:1:', 'VG:2:'), 'version 2' },
        { string_of({ kind = 'profile', data = { style = { font_size = 20, glow = 1 } } }), 'style.glow' },
        { string_of({ kind = 'element', element = 'rolls', data = { x = 5 }, later = true }), 'later' } }) do
        local payload, why, what = share.read(case[1]);
        assert(payload == nil and why == 'This was made with a newer Vantage. Update Vantage to read it.', 'Refused in plain words: ' .. tostring(why));
        assert(what == case[2], 'What it lacks is kept apart from the words: ' .. tostring(what));
    end;
end; -- end of section

do -- Section: pasting a fresh profile into fresh settings changes nothing.
    local s = fresh();
    local payload = assert(share.read(assert(share.export(s, 'profile', nil, NAME))));
    for _, mode in ipairs(share.modes) do
        local lines = share.changes(s, assert(share.candidate(s, payload, mode)));
        assert(#lines == 1 and lines[1] == 'Nothing changes.', mode .. ' of the same profile changes nothing: ' .. table.concat(lines, ' | '));
    end;
    local changed = fresh();
    changed.rolls.x = changed.rolls.x + 7;
    local lines = share.changes(s, assert(share.candidate(s, assert(share.read(assert(share.export(changed, 'profile', nil, NAME)))), 'replace')));
    assert(#lines == 1 and lines[1] == 'Phantom Roll: 1 setting change.', 'A real change is still counted: ' .. table.concat(lines, ' | '));
end; -- end of section

do -- Section: an import keeps your diagnostics settings and chat colors.
    local theirs = fresh();
    theirs.diagnostics.record, theirs.diagnostics.max_entries, theirs.chat_colors.tag_word = true, 1500, 100;
    theirs.panels.target.mode = 'bars';
    local payload = assert(share.read(assert(share.export(defaults.tidy(theirs), 'profile', nil, NAME))));
    local mine = fresh();
    mine.diagnostics.max_entries, mine.chat_colors.replies = 400, 9;
    mine = defaults.tidy(mine);
    for _, mode in ipairs(share.modes) do
        local candidate = assert(share.candidate(mine, payload, mode));
        assert(candidate.panels.target.mode == 'bars', mode .. ': fixture, the profile is taken.');
        assert(candidate.diagnostics.record == false and candidate.diagnostics.max_entries == 400 and candidate.chat_colors.tag_word == mine.chat_colors.tag_word
            and candidate.chat_colors.replies == 9, mode .. ': your diagnostics settings and chat colors stay.');
    end;
end; -- end of section

return 'Whole profiles leave out local names, strings read through chat, and newer ones are refused in plain words';
