-- Icon sets you add (ui/icon_packs.lua): a folder for each set in the icons folder, with a picture per effect named by its
-- number. Each set is a choice beside Original FFXI and XI View, kept while its folder is away. A picture comes
-- first, an effect the set has no picture for draws as with Original FFXI, and Party list's icons are made at the size
-- they draw. Reload icons reads the folder again.
local assets, icons, packs = require('ui.client_assets'), require('ui.icons'), require('ui.icon_packs');
local defaults, share, json = require('ui.defaults'), require('core.share'), require('core.json');

-- The start of a picture file of each kind, as far as its size: what Vantage reads before D3DX makes the texture.
local function be16(value) return string.char(math.floor(value / 256) % 256, value % 256); end;
local function le16(value) return string.char(value % 256, math.floor(value / 256) % 256); end;
local function be32(value) return be16(math.floor(value / 65536)) .. be16(value % 65536); end;
local function le32(value) return le16(value % 65536) .. le16(math.floor(value / 65536)); end;
local function png(width, height) return '\137PNG\r\n\26\n' .. be32(13) .. 'IHDR' .. be32(width) .. be32(height) .. '\8\6\0\0\0'; end;
local function tga(width, height) return string.rep('\0', 12) .. le16(width) .. le16(height) .. '\32\8'; end;

local ROOT = 'C:/Sets';
local function file(name, size) return { name = name, folder = false, size = size or 100 }; end;
local function folder(name) return { name = name, folder = true, size = 0 }; end;
local tree = {
    [ROOT] = { folder('Beta'), folder('Alpha'), folder('client'), folder('xi view'), folder('Empty'), file('notes.txt') },
    [ROOT .. '/Alpha'] = { file('40 Protect.png'), file('33.png'), file('33_old.png'), file('Haste.png'), file('readme.txt'),
        file('41.png', 2 * 1024 * 1024), file('43.png'), folder('More') },
    [ROOT .. '/Beta'] = { file('012.TGA'), file('7.png'), file('8.png', 300 * 1024) },
    [ROOT .. '/client'] = { file('33.png') },
    [ROOT .. '/xi view'] = { file('33.png') },
    [ROOT .. '/Empty'] = { file('readme.txt') },
};
local pictures = {
    [ROOT .. '/Alpha/33.png'] = png(128, 128), [ROOT .. '/Alpha/40 Protect.png'] = png(20, 24), [ROOT .. '/Alpha/43.png'] = 'broken',
    [ROOT .. '/Beta/012.TGA'] = tga(32, 32), [ROOT .. '/Beta/7.png'] = png(16, 16), [ROOT .. '/Beta/8.png'] = png(64, 64),
};
local uploads, released, next_id = {}, {}, 100;
local api = {
    list = function(path)
        local entries = tree[path];
        if not entries then return nil, 'Fixture folder missing.'; end;
        local out = {};
        for index, entry in ipairs(entries) do out[index] = { name = entry.name, folder = entry.folder, size = entry.size }; end;
        return out;
    end,
    read = function(path) return pictures[path], 'Fixture file missing.'; end,
    upload_picture = function(bytes, side, levels, name)
        next_id = next_id + 1;
        local id = next_id;
        uploads[#uploads + 1] = { id = id, bytes = bytes, side = side, levels = levels, name = name };
        return { id = id, release = function() released[id] = (released[id] or 0) + 1; end };
    end,
};
-- The game's own icons, for what a set has no picture for: no stock art files here, so they come from the client.
local client_ids = 0;
icons._set_loader_for_tests(function() client_ids = client_ids + 1; return 9000 + client_ids, function() end; end);
assets._set_platform_for_tests(api);
packs._set_folder_for_tests(ROOT);
local function last() return uploads[#uploads]; end;
-- A new Present: the budget of new icon textures and the cap on set pictures start again.
local function next_present() assets.icon_frame(); packs.frame(); end;

do -- Section: a picture's size, from its file's header.
    local size = packs.picture_size;
    local function is(bytes, kind, width, height, message)
        local w, h = size(bytes, kind);
        assert(w == width and h == height, message .. ': ' .. tostring(w) .. 'x' .. tostring(h));
    end;
    is(png(48, 40), 'png', 48, 40, 'PNG');
    is('BM' .. string.rep('\0', 12) .. le32(40) .. le32(36) .. le32(30) .. string.rep('\0', 4), 'bmp', 36, 30, 'BMP');
    is('BM' .. string.rep('\0', 12) .. le32(40) .. le32(36) .. le32(4294967296 - 30) .. string.rep('\0', 4), 'bmp', 36, 30, 'A BMP stored top row first');
    is('BM' .. string.rep('\0', 12) .. le32(12) .. le16(20) .. le16(22) .. string.rep('\0', 6), 'bmp', 20, 22, 'An old BMP header');
    is('DDS ' .. le32(124) .. le32(0) .. le32(24) .. le32(28), 'dds', 28, 24, 'DDS');
    is(tga(16, 18), 'tga', 16, 18, 'TGA');
    local app0 = '\255\224' .. be16(16) .. string.rep('\0', 14);
    is('\255\216' .. app0 .. '\255\192' .. be16(17) .. '\8' .. be16(50) .. be16(60) .. '\3', 'jpg', 60, 50, 'A JPG after its APP0');
    is('\255\216' .. app0 .. '\255\196' .. be16(4) .. '\0\0' .. '\255\194' .. be16(17) .. '\8' .. be16(10) .. be16(12) .. '\3', 'jpeg',
        12, 10, 'A progressive JPG, past its Huffman table');
    is(png(48, 40), 'bmp', nil, nil, 'A picture of another kind than its name says');
    is('broken', 'png', nil, nil, 'A file that isn\'t a picture');
    is(png(0, 40), 'png', nil, nil, 'A picture with no width');
end; -- end of section

do -- Section: the sets found and the files left out.
    local names = packs.names();
    assert(table.concat(names, ',') == 'Alpha,Beta', 'The sets, in name order: ' .. table.concat(names, ','));
    local report = packs.report();
    local left = {};
    for _, entry in ipairs(report.left_out) do left[entry.folder] = entry.reason; end;
    assert(left['xi view'] and left['xi view']:find('built-in', 1, true), 'A folder with a built-in choice\'s name isn\'t a set.');
    assert(left.client and left.client:find('old Client icons', 1, true), 'Nor is one named Client, which was a choice.');
    assert(left.Empty and left.Empty:find('no pictures', 1, true), 'A folder with no numbered pictures isn\'t a set.');
    local alpha = report.sets[1];
    assert(alpha.name == 'Alpha' and alpha.pictures == 3, 'Alpha has 33, 40 and 43: ' .. alpha.pictures);
    local why = {};
    for _, entry in ipairs(alpha.left_out) do why[entry.file] = entry.reason; end;
    assert(why['33_old.png'] and why['33_old.png']:find('already', 1, true), 'A second picture for an effect is left out.');
    assert(why['Haste.png'] and why['Haste.png']:find('effect number', 1, true), 'A picture with no number is left out.');
    assert(why['41.png'] and why['41.png']:find('1 MB', 1, true), 'A picture over 1 MB is left out.');
    assert(why['readme.txt'] == nil, 'A file that isn\'t a picture isn\'t called a problem.');
    assert(icons.reason('Alpha') == '3 pictures in this set can\'t be used. /vg report says which and why.',
        'The set says some pictures can\'t be used: ' .. icons.reason('Alpha'));
    assert(icons.reason('Beta') == nil, 'A set with every picture usable says nothing.');
end; -- end of section

do -- Section: the choices.
    local list, names = icons.choices('Original FFXI');
    assert(table.concat(list, ',') == 'Original FFXI,XI View,Alpha,Beta', 'Sets come after the built-in choices.');
    assert(names.Alpha == 'Alpha' and names['XI View'] == 'XI View');
    assert(icons.choices('Original FFXI') == list, 'The same list each frame.');
    assert(not packs.valid_name('Mine#') and packs.valid_name('#1 set'), 'A # at the end would join the ## of its label.');
    -- Windows finds a folder whatever the case of its name, so a saved name in another case is the same set.
    local cased, cased_names = icons.choices('alpha');
    assert(#cased == 4 and cased_names.alpha == 'Alpha', 'A saved name in another case shows as the folder\'s name, not as missing.');
    assert(packs.found('ALPHA') and icons.reason('alpha') == icons.reason('Alpha'), 'And it is that set.');
    local away, away_names = icons.choices('Gone');
    assert(#away == 5 and away[5] == 'Gone' and away_names.Gone:find('not in the icons folder', 1, true), 'A saved set that isn\'t there stays a choice.');
    assert(icons.reason('Gone'):find('isn\'t in the icons folder', 1, true), 'A set that isn\'t there says so.');
    assert(icons.reason('Gone') == icons.reason('Gone'), 'The same line each frame.');
    -- Sets keep their names through a save, and a name a folder can't have goes back to the default.
    local settings = defaults.make();
    settings.style.icon_art, settings.party_ui.style.icon_art = 'Alpha', 'Gone';
    settings = defaults.tidy(settings);
    assert(settings.style.icon_art == 'Alpha' and settings.party_ui.style.icon_art == 'Gone', 'A set\'s name is saved, there or not.');
end; -- end of section

do -- Section: a set's pictures, and what it has none for.
    local texture = icons.status(33, 'Alpha');
    assert(texture == last().id and last().side == 64 and last().levels == 0 and last().bytes == png(128, 128),
        'A large picture is made at 64 px with every mip level.');
    local count = #uploads;
    assert(icons.status(33, 'Alpha') == texture and #uploads == count, 'It is made once.');
    icons.status(40, 'Alpha');
    assert(last().side == 24, 'A small picture is made at its own size, the longer side.');
    count = #uploads;
    local waiting = icons.status(12, 'Beta');
    assert(waiting == nil and #uploads == count, 'A third set picture waits for the next Present.');
    next_present();
    assert(icons.status(12, 'Beta') == last().id and last().side == 32, 'A number with a leading zero, in capitals, is read.');
    count = #uploads;
    local before = client_ids;
    local fallback = icons.status(42, 'Alpha');
    assert(fallback and fallback > 9000 and client_ids == before + 1 and #uploads == count, 'An effect with no picture uses the game\'s icon.');
    assert(icons.status(41, 'Alpha') > 9000, 'A picture left out uses the game\'s icon.');
    next_present();
    assert(icons.status(43, 'Alpha') > 9000, 'A picture that can\'t be read uses the game\'s icon.');
    assert(icons.reason('Alpha'):find('4 pictures', 1, true), 'One that can\'t be read counts as well: ' .. icons.reason('Alpha'));
    local found = false;
    for _, entry in ipairs(packs.report().sets[1].left_out) do
        if entry.file == '43.png' and entry.reason:find('PNG, DDS', 1, true) then found = true; end;
    end;
    assert(found, '/vg report says why the picture can\'t be read.');
    -- It is tried again after 5 s, as a picture still being saved may be whole by then. The game's icon draws meanwhile.
    MOCK.now = 50;
    next_present();
    assert(icons.status(43, 'Alpha') > 9000, 'It isn\'t tried again at once.');
    pictures[ROOT .. '/Alpha/43.png'] = png(32, 32);
    MOCK.now = 56;
    for _ = 1, 8 do assets.spend_upload(); end;
    assert(icons.status(43, 'Alpha') > 9000, 'A retry that must wait for the budget draws the game\'s icon, not nothing.');
    next_present();
    assert(icons.status(43, 'Alpha') == last().id and last().side == 32, 'After 5 s it is tried again, and made.');
    assert(icons.reason('Alpha'):find('^3 pictures'), 'It no longer counts: ' .. icons.reason('Alpha'));
    assert(icons.status(33, 'Gone') > 9000, 'A set that isn\'t there uses the game\'s icons.');
    assert(icons.status(33, 'Original FFXI') > 9000 and icons.status(33, 'Alpha') == texture, 'Switching back and forth keeps each texture.');
end; -- end of section

do -- Section: a set's picture waits for a later Present, with nothing in its place meanwhile.
    assets.icon_frame();
    for _ = 1, 8 do assets.spend_upload(); end;
    local before = client_ids;
    local texture, waiting = icons.status(7, 'Beta');
    assert(texture == nil and client_ids == before, 'While the budget is spent, nothing is drawn, not the game\'s icon.');
    assets.icon_frame();
    packs.frame();
    assert(icons.status(7, 'Beta') == last().id and last().side == 16, 'It is made in the next Present.');
    local count = #uploads;
    assert(icons.status(8, 'Beta') == nil and #uploads == count, 'A picture over 256 KB waits for a Present of its own.');
    next_present();
    assert(icons.status(8, 'Beta') == last().id and #uploads == count + 1, 'It is made first in the next one.');
end; -- end of section

do -- Section: Party list's icons are made at the size they draw.
    MOCK.now = 100;
    local usual = icons.status(33, 'Alpha');
    local function present(seconds) MOCK.now = MOCK.now + (seconds or 0); assets.icon_frame(); packs.frame(); end;
    present();
    local texture, corner = icons.status_at(33, 'Alpha', 40);
    assert(texture == usual and corner[1] == 1 and corner[2] == 1, 'Until a size is made, the usual texture draws whole.');
    present(0.3);
    texture, corner = icons.status_at(33, 'Alpha', 40);
    local forty = last();
    assert(texture == forty.id and forty.side == 40 and forty.levels == 1 and corner[1] == 1, 'After 0.25 s it is made at 40 px, from the picture.');
    assert(icons.status_at(33, 'Alpha', 64) == usual, 'The usual texture\'s own size uses it.');
    assert(icons.status_at(42, 'Alpha', 40) > 9000, 'An effect with no picture draws as Original FFXI would.');
    -- A set keeps 4 sizes. A fifth lets go of the one asked for least recently, released at the next Present.
    for _, size in ipairs({ 20, 24, 28 }) do
        present(); icons.status_at(33, 'Alpha', size);
        present(0.3); icons.status_at(33, 'Alpha', size);
    end;
    present(); icons.status_at(33, 'Alpha', 30);
    assert(not released[forty.id], 'A size let go of isn\'t released while this frame may draw it.');
    present();
    assert(released[forty.id] == 1, 'It is released at the next Present.');
    -- A size that can't be made draws the usual texture scaled, and /vg report says so.
    local upload = api.upload_picture;
    api.upload_picture = function(bytes, side, levels, name)
        if side == 36 then return nil, 'No room.'; end;
        return upload(bytes, side, levels, name);
    end;
    present(); icons.status_at(33, 'Alpha', 36);
    present(0.3);
    local drawn = icons.status_at(33, 'Alpha', 36);
    api.upload_picture = upload;
    local failed = packs.report().sets[1].sizes_failed[1];
    assert(drawn == usual and failed and failed.file == '33.png' and failed.size == 36 and failed.reason == 'No room.',
        'A size that can\'t be made is in the report.');
    present(1);
    assert(icons.status_at(33, 'Alpha', 36) == usual, 'It isn\'t tried again at once.');
    present(5);
    local thirty_six = icons.status_at(33, 'Alpha', 36);
    assert(thirty_six ~= usual and thirty_six == last().id and last().side == 36, 'After 5 s it is tried again, and made.');
    assert(#packs.report().sets[1].sizes_failed == 0, 'Then the report no longer lists it.');
end; -- end of section

do -- Section: Reload icons reads the folder again, and a new graphics device makes the textures again.
    next_present();
    local made = icons.status(33, 'Alpha');
    icons.clear();
    assert(released[made] == 1, 'A new graphics device lets go of every texture.');
    assets._set_platform_for_tests(api);
    assert(table.concat(packs.names(), ',') == 'Alpha,Beta', 'The sets stay as they were read.');
    next_present();
    made = icons.status(33, 'Alpha');
    local list = icons.choices('Alpha');
    tree[ROOT][#tree[ROOT] + 1] = folder('Gamma');
    tree[ROOT .. '/Gamma'] = { file('33.png') };
    pictures[ROOT .. '/Gamma/33.png'] = png(32, 32);
    local note = icons.reload_sets();
    assert(note:find('3 icon sets', 1, true) and note:find('config/addons/vantage/icons/', 1, true), 'Reload icons says what it read: ' .. note);
    assert(released[made] == 1, 'What the last read made is let go of.');
    local again = icons.choices('Alpha');
    assert(again ~= list and again[5] == 'Gamma', 'A new set is a choice at once.');
    next_present();
    assert(icons.status(33, 'Gamma') == last().id, 'And it draws.');
end; -- end of section

do -- Section: an export blanks a set's name with yours in it, and never a built-in choice.
    local function exported(art, character)
        local settings = defaults.tidy(defaults.make());
        settings.style.icon_art = art;
        local text = assert(share.export(settings, 'profile', nil, character));
        local data = json.decode(text:match('^VG:1:%x+:(.+)$')).data;
        return data.style and data.style.icon_art or data.settings and data.settings.style.icon_art;
    end;
    assert(exported('Tester icons', 'Tester') == '', 'A set named for you is blanked.');
    assert(exported('Crisp icons', 'Tester') == 'Crisp icons', 'Another set\'s name is shared.');
    assert(exported('XI View', 'View') == 'XI View', 'A built-in choice is shared, whatever your name.');
end; -- end of section
