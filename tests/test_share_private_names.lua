-- Exports and their file names (core/share.lua) leave out your names as whole words, whatever the case: a name with no
-- letter right before or after it. A digit next to it doesn't make it part of another word, as FFXI names have none,
-- and a byte past 127, part of an accented letter in UTF-8, counts as a letter, so a name that ends in one is found
-- and one inside a longer word isn't. The Windows user name is read in UTF-8, as text typed in the settings window
-- is; the tests' ffi has no Windows calls, so there it is os.getenv's.
local share, defaults, json = require('core.share'), require('ui.defaults'), require('core.json');
local NAME = 'Tester';
local JOSE = 'Jos\195\169';
local getenv = os.getenv;
local function as_user(name)
    os.getenv = function(key) if key == 'USERNAME' then return name; end; return getenv(key); end;
end;
-- The title of Self buffs as an export of that one display has it.
local function exported(title, character)
    local settings = defaults.tidy(defaults.make());
    settings.panels.self_buffs.title = title;
    local text, why = share.export(settings, 'element', 'self_buffs', character);
    assert(text, 'Fixture: Self buffs exports: ' .. tostring(why));
    return json.decode(text:match('^VG:1:%x+:(.+)$')).data.title;
end;

do -- Section: your character's name in an export.
    as_user('Winuser');
    for _, case in ipairs({ { 'Tester buffs', '' }, { 'TESTER buffs', '' }, { 'Tester2 buffs', '' }, { 'My buffs, Tester', '' },
        { 'Testers buffs', 'Testers buffs' }, { 'Tester\195\169 buffs', 'Tester\195\169 buffs' }, { 'Main buffs', 'Main buffs' } }) do
        local title = exported(case[1], NAME);
        assert(title == case[2], 'A title of ' .. case[1] .. ' exports as "' .. case[2] .. '": "' .. tostring(title) .. '"');
    end;
    assert(exported('Raid buffs', 'Rai') == 'Raid buffs', 'A name that only starts a word is no match.');
    os.getenv = getenv;
end; -- end of section

do -- Section: a Windows user name that ends in an accented letter.
    as_user(JOSE);
    assert(share.windows_name() == JOSE, 'The tests read the Windows user name from os.getenv.');
    for _, case in ipairs({ { JOSE .. ' raid', '' }, { 'JOS\195\169 raid', '' }, { 'Party of ' .. JOSE, '' }, { JOSE .. '2 raid', '' },
        { JOSE .. 'phine raid', JOSE .. 'phine raid' }, { 'Main buffs', 'Main buffs' } }) do
        local title = exported(case[1], NAME);
        assert(title == case[2], 'A title of ' .. case[1] .. ' exports as "' .. case[2] .. '": "' .. tostring(title) .. '"');
    end;
    os.getenv = getenv;
end; -- end of section

do -- Section: a Windows user name of digits only.
    -- An id is a number, never a name, so a list of effects by id exports though the user name is those digits.
    as_user('1234');
    local settings = defaults.tidy(defaults.make());
    settings.panels.self_buffs.include = { [1234] = true };
    local text, why = share.export(settings, 'element', 'self_buffs', NAME);
    assert(text and json.decode(text:match('^VG:1:%x+:(.+)$')).data.include['1234'], 'A user name of digits leaves the ids alone: ' .. tostring(why));
    os.getenv = getenv;
end; -- end of section

do -- Section: the file name.
    for _, case in ipairs({ { 'Tester raid', { NAME }, 'raid' }, { 'TESTER raid', { NAME }, 'raid' }, { 'Tester2 raid', { NAME }, '2 raid' },
        { 'raid Tester Tester', { NAME }, 'raid' }, { 'TesterTester', { NAME }, 'TesterTester' }, { 'Raid', { 'Rai' }, 'Raid' },
        { JOSE .. ' raid', { JOSE }, 'raid' }, { JOSE .. 'phine', { JOSE }, 'Josphine' }, { JOSE, { JOSE }, 'profile' } }) do
        local made = share.file_name(case[1], case[2]);
        assert(made == case[3], 'The file name of ' .. case[1] .. ' is ' .. case[3] .. ': ' .. made);
    end;
end; -- end of section

do -- Section: no Windows user name at all.
    for _, none in ipairs({ false, '' }) do
        as_user(none or nil);
        assert(share.windows_name() == nil, 'With no user name there is none to leave out.');
        assert(exported('Main buffs', NAME) == 'Main buffs', 'and an export is still made.');
    end;
    os.getenv = getenv;
end; -- end of section
