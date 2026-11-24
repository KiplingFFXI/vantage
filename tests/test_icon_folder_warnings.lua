-- The icons folder holds each set as a folder. A zip, 7z or rar file in it with no folder of its name beside it, a
-- picture put straight in it, or a folder with no pictures named by effect number but several folders inside that have some, gets a
-- line under Icons and Party buff icons in the problem color, and Reload icons and /vg report say so too. A set one
-- folder down, as a zip that held a folder extracts, is read from there.
local h = require('panel_fixture')();
local assets, icons, packs = require('ui.client_assets'), require('ui.icons'), require('ui.icon_packs');
local custom = require('core.customization');

local ROOT = 'C:/Sets';
local function file(name, size) return { name = name, folder = false, size = size or 100 }; end;
local function folder(name) return { name = name, folder = true, size = 0 }; end;
local tree, listed, read = {}, 0, {};
assets._set_platform_for_tests({
    list = function(path)
        listed = listed + 1;
        local entries = tree[path];
        if not entries then return nil, 'Fixture folder missing.'; end;
        local out = {};
        for index, entry in ipairs(entries) do out[index] = { name = entry.name, folder = entry.folder, size = entry.size }; end;
        return out;
    end,
    -- Every picture is a 32 px PNG, and the files read are kept in read.
    read = function(path)
        read[#read + 1] = path;
        return '\137PNG\r\n\26\n\0\0\0\13IHDR\0\0\0\32\0\0\0\32\8\6\0\0\0';
    end,
    upload_picture = function() return { id = 7, release = function() end }; end,
});
packs._set_folder_for_tests(ROOT);
-- The icons folder holds root, and each set folder what sets gives it. Reload icons reads it and says what it found.
local function holds(root, sets)
    tree = sets or {};
    tree[ROOT] = root;
    return icons.reload_sets();
end;
local SET = { [ROOT .. '/Alpha'] = { file('33.png') }, [ROOT .. '/Status-Pack'] = { file('33.png') } };
local EXTRACT = ' Vantage reads folders only, so extract it into a folder of its own in the icons folder, then press Reload icons. If you already'
    .. ' extracted it, delete it.';
local EACH = ' Vantage reads folders only, so extract each into a folder of its own, then press Reload icons. Delete any you'
    .. ' already extracted.';

do -- Section: what Reload icons and the line say.
    assert(holds({ folder('Alpha'), file('notes.txt'), file('pack.tar') }, SET) == 'One icon set read from config/addons/vantage/icons/.'
        and packs.warning() == nil and icons.folder_warning() == nil, 'A folder of sets and a file that isn\'t packed or a picture say nothing.');
    assert(holds({ file('status-pack.zip') }) == 'No icon sets are in config/addons/vantage/icons/ yet. status-pack.zip is a zip file.' .. EXTRACT,
        'A zip by itself is called a zip to extract: ' .. tostring(packs.warning()));
    assert(icons.folder_warning() == 'status-pack.zip is a zip file.' .. EXTRACT, 'The line under Icons says the same.');
    assert(holds({ file('status-pack.zip'), folder('Status-Pack') }, SET) == 'One icon set read from config/addons/vantage/icons/.'
        and packs.warning() == nil, 'A zip with a folder of its name beside it, in any case, has been extracted.');
    assert(holds({ file('a.b.zip'), folder('a.b'), file('Pack .zip'), file('Pack..rar'), folder('Pack'), file('Client.zip'), folder('Client'),
        file('README'), file('.zip') }, { [ROOT .. '/a.b'] = { file('33.png') }, [ROOT .. '/Pack'] = { file('33.png') } })
        == '2 icon sets read from config/addons/vantage/icons/.' and packs.warning() == nil,
        "A dot in the name, the spaces and dots Windows drops from the folder's name, a folder that isn't a set, and files with no kind: "
        .. tostring(packs.warning()));
    holds({ file('Bright.ZIP') });
    assert(packs.warning() == 'Bright.ZIP is a zip file.' .. EXTRACT, 'Its kind is found in any case: ' .. tostring(packs.warning()));
    holds({ file('Pack.7z') });
    assert(packs.warning() == 'Pack.7z is a 7z file.' .. EXTRACT, 'A 7z file is one too.');
    holds({ file('Pack.7Z') });
    assert(packs.warning() == 'Pack.7Z is a 7z file.' .. EXTRACT, 'In any case.');
    holds({ file('Pack.rar') });
    assert(packs.warning() == 'Pack.rar is a rar file.' .. EXTRACT, 'And a rar file.');
    holds({ file('A.zip'), file('B.zip'), folder('Alpha') }, SET);
    assert(packs.warning() == '2 zip files in the icons folder aren\'t read.' .. EACH, 'Several of one kind are counted: ' .. tostring(packs.warning()));
    holds({ file('A.zip'), file('B.7z'), file('C.rar') });
    assert(packs.warning() == '3 compressed files in the icons folder aren\'t read.' .. EACH, 'Several kinds are compressed files.');
    holds({ file('33.png') });
    assert(packs.warning() == '33.png is loose in the icons folder. Put it in a folder named for its set, then press Reload icons.',
        'A picture outside a set\'s folder is loose: ' .. tostring(packs.warning()));
    holds({ file('33.png'), file('40 Protect.JPG'), file('notes.txt'), folder('Alpha') }, SET);
    assert(packs.warning() == '2 pictures are loose in the icons folder. Put them in a folder named for their set, then press Reload icons.',
        'Several loose pictures are counted, and a text file isn\'t one.');
    holds({ file('A.zip'), file('33.png') });
    assert(packs.warning() == 'A.zip is a zip file.' .. EXTRACT .. ' 33.png is loose in the icons folder. Put it in a folder named for its set,'
        .. ' then press Reload icons.', 'A zip and a loose picture are both said.');
    local report = packs.report();
    assert(#report.archives == 1 and report.archives[1] == 'A.zip' and #report.loose == 1 and report.loose[1] == '33.png',
        '/vg report lists the zip and the loose picture.');
    -- Worked out once a read, as the line shows each frame.
    local before = listed;
    for _ = 1, 3 do packs.warning(); end;
    assert(listed == before, 'Asking again doesn\'t read the folder again.');
    holds({ file('A.zip'), folder('a') }, { [ROOT .. '/a'] = {} });
    report = packs.report();
    assert(packs.warning() == nil and #report.archives == 0 and #report.loose == 0, 'Once extracted, nothing is said or listed.');
    holds(nil);
    assert(packs.warning() == nil, 'A folder that can\'t be read says why elsewhere, not this.');
end; -- end of section

do -- Section: a set one folder down, as a zip that held a folder extracts.
    local function left(folder)
        for _, entry in ipairs(packs.report().left_out) do if entry.folder == folder then return entry.reason; end; end;
    end;
    -- Pack.zip extracted beside itself, holding a folder of its own: icons/Pack/Pack.
    assert(holds({ file('Pack.zip'), folder('Pack') }, { [ROOT .. '/Pack'] = { folder('Pack') },
        [ROOT .. '/Pack/Pack'] = { file('33.png'), file('40 Protect.png') } }) == 'One icon set read from config/addons/vantage/icons/.'
        and packs.warning() == nil, 'A set one folder down is read, and its zip counts as extracted: ' .. tostring(packs.warning()));
    local report = packs.report();
    assert(table.concat(packs.names(), ',') == 'Pack' and #report.sets == 1 and report.sets[1].name == 'Pack'
        and report.sets[1].inner_folder == 'Pack' and report.sets[1].pictures == 2 and #report.left_out == 0,
        'It is named for the outer folder, and /vg report names the folder inside it was read from.');
    assets.icon_frame();
    packs.frame();
    read = {};
    assert(packs.texture('Pack', 33) == 7 and read[1] == ROOT .. '/Pack/Pack/33.png', 'Its pictures are read from the folder inside.');
    -- A zip made on a Mac holds a __MACOSX folder too, with a ._ file for each picture, and a picture beside the folder.
    -- Only folders are looked in: the icons folder, Bright and the two inside it.
    local before = listed;
    holds({ folder('Bright') }, { [ROOT .. '/Bright'] = { folder('__MACOSX'), folder('status icons'), file('preview.png'), file('readme.txt') },
        [ROOT .. '/Bright/__MACOSX'] = { folder('status icons') }, [ROOT .. '/Bright/__MACOSX/status icons'] = { file('._33.png') },
        [ROOT .. '/Bright/status icons'] = { file('33.png'), file('Haste.png') } });
    report = packs.report();
    assert(#report.sets == 1 and report.sets[1].name == 'Bright' and report.sets[1].inner_folder == 'status icons'
        and packs.warning() == nil and listed == before + 4,
        'A __MACOSX folder and a picture beside the folder don\'t get in the way: ' .. (listed - before) .. ' folders listed.');
    assert(#report.sets[1].left_out == 1 and report.sets[1].left_out[1].file == 'Haste.png' and packs.found('bright')
        and icons.reason('Bright') == 'One picture in this set can\'t be used. /vg report says which and why.',
        'The folder inside is the set: its own pictures left out are said, not the one beside it, and it is found in any case.');
    -- A set's own pictures win, and no folder inside it is read then.
    before = listed;
    holds({ folder('Alpha') }, { [ROOT .. '/Alpha'] = { file('33.png'), folder('Old') }, [ROOT .. '/Alpha/Old'] = { file('40.png') } });
    report = packs.report();
    assert(listed == before + 2 and report.sets[1].inner_folder == nil and report.sets[1].pictures == 1,
        'A folder with pictures of its own is the set, as before.');
    -- So do its pictures too big to use: it isn't a set, and says why, and the folder inside isn't read in its place.
    before = listed;
    holds({ folder('Pack') }, { [ROOT .. '/Pack'] = { file('33.png', 2 * 1024 * 1024), folder('Pack') }, [ROOT .. '/Pack/Pack'] = { file('40.png') } });
    assert(#packs.names() == 0 and left('Pack') == 'Each of its pictures named by effect number is over 1 MB.' and listed == before + 2,
        'A folder whose pictures are each over 1 MB says so: ' .. tostring(left('Pack')));
    -- Several folders inside with pictures can't be told apart, so none is read, and the line says what to do.
    local SPLIT = 'Pack has no pictures named by effect number, but 2 folders inside it do. Move each into the icons folder as a set'
        .. ' of its own, then press Reload icons.';
    assert(holds({ folder('Pack') }, { [ROOT .. '/Pack'] = { folder('64px'), folder('32px'), folder('Notes'), folder('Gone') },
        [ROOT .. '/Pack/32px'] = { file('33.png') }, [ROOT .. '/Pack/64px'] = { file('33.png') }, [ROOT .. '/Pack/Notes'] = { file('Haste.png') } })
        == 'No icon sets are in config/addons/vantage/icons/ yet. ' .. SPLIT and icons.folder_warning() == SPLIT,
        'Two folders inside with pictures are said: ' .. tostring(packs.warning()));
    assert(left('Pack') == 'It has no pictures named by effect number, but 2 folders inside it do: 32px, 64px.',
        '/vg report names them, and not one with no numbered pictures or one that can\'t be read: ' .. tostring(left('Pack')));
    holds({ folder('A'), folder('B') }, { [ROOT .. '/A'] = { folder('1'), folder('2') }, [ROOT .. '/A/1'] = { file('33.png') },
        [ROOT .. '/A/2'] = { file('33.png') }, [ROOT .. '/B'] = { folder('1'), folder('2'), folder('3') }, [ROOT .. '/B/1'] = { file('33.png') },
        [ROOT .. '/B/2'] = { file('33.png') }, [ROOT .. '/B/3'] = { file('33.png') } });
    assert(packs.warning() == '2 folders in the icons folder have no pictures named by effect number, but several folders inside'
        .. ' each of them do. Move those into the icons folder as sets of their own, then press Reload icons.', 'Two such folders are counted.');
    holds({ file('C.zip'), folder('Pack'), file('33.png') }, { [ROOT .. '/Pack'] = { folder('a'), folder('b') },
        [ROOT .. '/Pack/a'] = { file('33.png') }, [ROOT .. '/Pack/b'] = { file('33.png') } });
    assert(packs.warning() == 'C.zip is a zip file.' .. EXTRACT .. ' ' .. SPLIT .. ' 33.png is loose in the icons folder. Put it in a'
        .. ' folder named for its set, then press Reload icons.', 'With a zip and a loose picture, it comes between them.');
    -- Two folders down isn't looked in.
    holds({ folder('Pack') }, { [ROOT .. '/Pack'] = { folder('Pack') }, [ROOT .. '/Pack/Pack'] = { folder('Pack') },
        [ROOT .. '/Pack/Pack/Pack'] = { file('33.png') } });
    assert(#packs.names() == 0 and left('Pack') == 'It has no pictures named by effect number.' and packs.warning() == nil,
        'A set two folders down isn\'t read: ' .. tostring(left('Pack')));
end; -- end of section

do -- Section: the line on the main page and on Party list's Look tab, in the problem color.
    local function line(text)
        for index, call in ipairs(MOCK.imgui_calls) do
            if call[1] == 'TextWrapped' and call[2] == text then return MOCK.imgui_calls[index - 1]; end;
        end;
    end;
    -- A % in a file's name is drawn as itself: vantage.lua doubles it for the game's printf.
    local warning = '50% Pack.zip is a zip file.' .. EXTRACT;
    warning = warning:gsub('%%', '%%%%');
    holds({ file('50% Pack.zip') });
    h.fresh(function(s) s.window.sections['Home/Artwork'] = true; end);
    h.draw();
    local look = require('ui.theme').window(h.s);
    local color = line(warning);
    assert(color and color[1] == 'PushStyleColor' and custom.equal(color[3], look.problem_messages), 'Artwork says it in the problem color.');
    assert(not custom.equal(look.problem_messages, look.notes), 'Fixture: that is not the color of a note.');
    -- Reload icons says it after what it read.
    h.draw('Reload icons##main_reload_icons');
    h.draw();
    assert(h.says('No icon sets are in config/addons/vantage/icons/ yet. ' .. warning), 'Reload icons says it too.');
    h.fresh(function(s) s.party_ui.enabled = true; end);
    h.on('party_ui', 'look');
    color = line(warning);
    assert(color and color[1] == 'PushStyleColor' and custom.equal(color[3], look.problem_messages), 'So does Party list\'s Look tab.');
    -- Extracted, neither has the line. (Reload icons' note from before may still be showing, so the line is looked for.)
    holds({ file('50% Pack.zip'), folder('50% Pack') }, { [ROOT .. '/50% Pack'] = { file('33.png') } });
    h.draw();
    assert(not line(warning) and h.called('Button', 'Reload icons##frame'), 'Party list has no line once it is extracted.');
    h.fresh(function(s) s.window.sections['Home/Artwork'] = true; end);
    h.draw();
    assert(not line(warning) and h.called('Button', 'Reload icons##main_reload_icons'), 'Nor does Artwork.');
end; -- end of section

assets._set_platform_for_tests(nil);
MOCK.fire('unload');
return 'A zip, loose pictures or sets that can\'t be told apart in the icons folder are said under Icons, by Reload icons and in'
    .. ' /vg report, and a set one folder down is read';
