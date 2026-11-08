-- Party icons made at the size they draw (ui/client_assets.lua icon_texture_at, ui/icons.lua status_at): each status
-- icon is shrunk from its 32 px record once, at exactly the size it draws, into a texture of its own the next power of
-- two across with the rest transparent, and drawn 1:1 from that texture's top left corner. Up to 4 are made in a
-- Present, a new size waits 0.25 s, and each art keeps 4 sizes, letting go of the one asked for least recently at the
-- start of a later Present. Client art, 32 px and any failure draw the 32 px texture whole.
local assets, icons = require('ui.client_assets'), require('ui.icons');
local function le16(value) return string.char(value % 256, math.floor(value / 256) % 256); end;
local function le32(value) return le16(value % 65536) .. le16(math.floor(value / 65536)); end;
local function get32(s, at) local a, b, c, d = s:byte(at, at + 3); return a + b * 256 + c * 65536 + d * 16777216; end;

-- A status icon file of count 32 px records, 32 bits each, with transparent, part-transparent and solid pixels.
local function record(pixels)
    local data = string.rep('\0', 0x280) .. le32(57 + #pixels) .. '\145' .. string.rep(' ', 16)
        .. le32(40) .. le32(32) .. le32(32) .. le16(1) .. le16(32) .. string.rep('\0', 24) .. pixels;
    return data .. string.rep('\0', 0x1800 - #data);
end;
local function pack(seed, count)
    local records = {};
    for id = 0, count - 1 do
        local rows = {};
        for y = 0, 31 do
            local row = {};
            for x = 0, 31 do
                local alpha = (x + y + id) % 7 == 0 and 0 or (x * 3 + y * 5 + seed) % 4 == 0 and 255 or (x * 11 + y * 7 + id * 13 + seed) % 256;
                row[x + 1] = string.char((x * 7 + y * 13 + id + seed) % 256, (x * x + 3 * y + seed * 5) % 256, (5 * x * y + 11 + id) % 256, alpha);
            end;
            rows[y + 1] = table.concat(row);
        end;
        records[id + 1] = record(table.concat(rows));
    end;
    return table.concat(records);
end;

-- The stock art has ids 0 to 9, XI View's only 0 to 4.
local game, view = 'C:/Client Root', 'C:/View Root';
local files = { [game .. '/ROM/119/57.DAT'] = pack(0, 10), [view .. '/ROM/119/57.DAT'] = pack(91, 5) };
local stock, xiview = assert(assets.parse_icons(files[game .. '/ROM/119/57.DAT'])), assert(assets.parse_icons(files[view .. '/ROM/119/57.DAT']));
local uploads, released, failing, next_id = {}, {}, false, 500;
local api = {
    game_root = function() return game; end,
    ashita_root = function() return 'C:/Ashita Root'; end,
    xiview_path = function() return view .. '/ROM/119/51.DAT'; end,
    read = function(filename) return files[filename], 'Fixture file missing.'; end,
    upload = function(data, width, height, label)
        if failing then return nil, 'Fixture upload failed.'; end;
        next_id = next_id + 1;
        local id = next_id;
        uploads[#uploads + 1] = { id = id, data = data, width = width, height = height, label = label };
        return { id = id, release = function() released[id] = (released[id] or 0) + 1; end };
    end,
};
-- Client art comes from the game, here a loader that hands out ids.
local client_ids = 0;
icons._set_loader_for_tests(function() client_ids = client_ids + 1; return 9000 + client_ids, function() end; end);
-- Fresh art each time, its 32 px textures made already, so every upload after is one made at a size. A Present makes
-- up to 8 new 32 px textures, so they are made over as many as that takes.
local function fresh()
    icons.clear();
    assets._set_platform_for_tests(api);
    assets.prepare_icons();
    for id = 0, 9 do
        for _, artwork in ipairs({ 'Original FFXI', 'XI View', 'Client' }) do
            local waited = 0;
            while not icons.status(id, artwork) do
                assert(waited == 0, 'Fixture: a 32 px icon is made by the next Present.');
                assets.icon_frame();
                waited = waited + 1;
            end;
        end;
    end;
    uploads, released, failing = {}, {}, false;
end;
local function present(seconds) MOCK.now = MOCK.now + (seconds or 0); assets.icon_frame(); end;
local function whole(id, artwork) return icons.status(id, artwork); end;

-- The reference: on each axis a source texel spans size units and a pixel 32, so the overlap of the two, across times
-- down, weighs the texel. Alpha is that weighted area over the pixel's 1024, colour weighted by area and alpha, each
-- rounded to the nearest byte; outside size x size it is transparent, side px square.
local function reference(dds, size)
    local side = size <= 32 and 32 or size <= 64 and 64 or 128;
    local out = {};
    for y = 0, side - 1 do
        for x = 0, side - 1 do
            local b, g, r, a = 0, 0, 0, 0;
            if x < size and y < size then
                local sa, sb, sg, sr = 0, 0, 0, 0;
                for ty = 0, 31 do
                    local wy = math.min(size * ty + size, 32 * y + 32) - math.max(size * ty, 32 * y);
                    for tx = 0, 31 do
                        local wx = math.min(size * tx + size, 32 * x + 32) - math.max(size * tx, 32 * x);
                        if wx > 0 and wy > 0 then
                            local pb, pg, pr, pa = dds:byte(129 + (ty * 32 + tx) * 4, 132 + (ty * 32 + tx) * 4);
                            local weight = wx * wy * pa;
                            sa, sb, sg, sr = sa + weight, sb + weight * pb, sg + weight * pg, sr + weight * pr;
                        end;
                    end;
                end;
                if sa > 0 then
                    b, g, r = math.floor((2 * sb + sa) / (2 * sa)), math.floor((2 * sg + sa) / (2 * sa)), math.floor((2 * sr + sa) / (2 * sa));
                    a = math.floor((sa + 512) / 1024);
                end;
            end;
            out[#out + 1] = string.char(b, g, r, a);
        end;
    end;
    return table.concat(out);
end;

-- The four sizes the strips draw at most: 14, 18 and 20 px rows at 1920x1080, and 37 px in a panel of its own. Each is
-- made byte for byte as the reference, in a texture of its own with a side x side header and transparent padding.
fresh();
MOCK.now = 100;
present();
for _, size in ipairs({ 14, 18, 20, 37 }) do
    local side = size <= 32 and 32 or 64;
    local texture, corner = icons.status_at(3, 'Original FFXI', size);
    assert(texture == whole(3, 'Original FFXI') and corner[1] == 1 and corner[2] == 1 and #uploads == 0,
        'A new size draws the 32 px texture whole while it waits: ' .. size);
    present(0.25);
    texture, corner = icons.status_at(3, 'Original FFXI', size);
    local made = uploads[#uploads];
    assert(#uploads == 1 and texture == made.id and made.width == side and made.height == side and made.label == 'original.status',
        'Made once the size has waited 0.25 s: ' .. size);
    assert(corner[1] == size / side and corner[2] == size / side, 'Drawn from its top left corner: ' .. size);
    local raw = stock.records[3].dds;
    assert(#made.data == 128 + side * side * 4 and made.data:sub(1, 12) == raw:sub(1, 12) and get32(made.data, 13) == side
        and get32(made.data, 17) == side and get32(made.data, 21) == side * 4 and made.data:sub(25, 128) == raw:sub(25, 128),
        'The header says side x side, otherwise as the 32 px one: ' .. size);
    local pixels = made.data:sub(129);
    assert(pixels == reference(raw, size), 'Byte for byte the reference shrink: ' .. size);
    for y = 0, side - 1 do
        for x = 0, side - 1 do
            if x >= size or y >= size then
                assert(pixels:sub((y * side + x) * 4 + 1, (y * side + x) * 4 + 4) == '\0\0\0\0', 'The padding is transparent: ' .. size);
            end;
        end;
    end;
    -- Asked again, this Present and later ones, it is never made a second time.
    for _ = 1, 3 do
        assert(icons.status_at(3, 'Original FFXI', size) == made.id, 'The same texture: ' .. size);
        present();
    end;
    assert(icons.status_at(3, 'Original FFXI', size) == made.id and #uploads == 1, 'No second upload: ' .. size);
    uploads = {};
end;

-- Up to 4 are made in a Present: six buffs at a new size take two Presents once it has waited.
fresh();
present();
local ids = { 0, 1, 2, 4, 5, 6 };
for _, id in ipairs(ids) do assert(icons.status_at(id, 'Original FFXI', 20) == whole(id, 'Original FFXI')); end;
-- 0.125 s on, it still waits.
present(0.125);
for _, id in ipairs(ids) do assert(icons.status_at(id, 'Original FFXI', 20) == whole(id, 'Original FFXI')); end;
assert(#uploads == 0, 'A new size waits 0.25 s from when it is first asked for.');
present(0.125);
local first = {};
for index, id in ipairs(ids) do
    local texture, corner = icons.status_at(id, 'Original FFXI', 20);
    first[index] = texture ~= whole(id, 'Original FFXI') and corner[1] == 20 / 32;
end;
assert(#uploads == 4 and first[1] and first[2] and first[3] and first[4] and not first[5] and not first[6],
    'Four made in this Present, the other two draw the whole texture.');
present();
for _, id in ipairs(ids) do assert(icons.status_at(id, 'Original FFXI', 20) ~= whole(id, 'Original FFXI')); end;
assert(#uploads == 6, 'The other two the next Present.');
-- A new buff at a size already made needs no wait.
present();
assert(icons.status_at(7, 'Original FFXI', 20) ~= whole(7, 'Original FFXI') and #uploads == 7, 'A new icon at a kept size is made at once.');
-- A size not asked for in the Present before waits again for icons not made yet; the ones made draw at once.
present(); present();
assert(icons.status_at(8, 'Original FFXI', 20) == whole(8, 'Original FFXI') and icons.status_at(0, 'Original FFXI', 20) == uploads[1].id,
    'Back after a gap: made ones at once, a new one waits.');
present(0.25);
assert(icons.status_at(8, 'Original FFXI', 20) ~= whole(8, 'Original FFXI') and #uploads == 8);

-- Each art keeps 4 sizes. A fifth lets go of the one asked for least recently, never one asked for in this Present,
-- and its textures are released at the start of the next Present, after the frame that may still draw them.
fresh();
present();
local kept = {};
for _, size in ipairs({ 14, 18, 20, 37 }) do icons.status_at(2, 'Original FFXI', size); end;
present(0.25);
for index, size in ipairs({ 14, 18, 20, 37 }) do kept[size] = icons.status_at(2, 'Original FFXI', size); assert(kept[size] == uploads[index].id); end;
present();
-- This Present asks for 14, 18 and 20, then 22: 37 is let go of, but not released yet.
for _, size in ipairs({ 14, 18, 20 }) do assert(icons.status_at(2, 'Original FFXI', size) == kept[size]); end;
assert(icons.status_at(2, 'Original FFXI', 22) == whole(2, 'Original FFXI'), '22 px waits.');
assert(not released[kept[37]], 'Not released in the Present that let it go.');
-- 37 again in this Present: all four kept sizes were asked for now, so none is let go of and it draws the whole texture.
assert(icons.status_at(2, 'Original FFXI', 37) == whole(2, 'Original FFXI'), 'A fifth size draws whole when all four are in use.');
present();
assert(released[kept[37]] == 1 and not released[kept[14]] and not released[kept[18]] and not released[kept[20]],
    'Released at the start of the next Present, once.');
present(); present();
assert(released[kept[37]] == 1, 'Never released twice.');
local report = assets.icon_sizes_report();
local listed = {};
for _, entry in ipairs(report.sizes.original) do listed[#listed + 1] = entry.size .. ':' .. entry.icons; end;
assert(table.concat(listed, ' ') == '14:1 18:1 20:1 22:0', 'The report lists the sizes kept and the icons each holds: ' .. table.concat(listed, ' '));

-- clear_icons releases every texture made at a size, and the ones waiting for their release.
fresh();
present();
for _, size in ipairs({ 14, 18, 20, 37 }) do icons.status_at(5, 'Original FFXI', size); icons.status_at(6, 'Original FFXI', size); end;
present(0.25);
for _, size in ipairs({ 14, 18, 20, 37 }) do icons.status_at(5, 'Original FFXI', size); icons.status_at(6, 'Original FFXI', size); end;
present();
for _, size in ipairs({ 14, 18, 20, 37 }) do icons.status_at(5, 'Original FFXI', size); icons.status_at(6, 'Original FFXI', size); end;
assert(#uploads == 8, 'Fixture: eight made.');
present();
icons.status_at(5, 'Original FFXI', 24);
local pending = uploads[1].id;
assert(not released[pending], 'Fixture: 14 px let go of, waiting for its release.');
assets.clear_icons();
for _, made in ipairs(uploads) do assert(released[made.id] == 1, 'Every texture made at a size is released once by clear_icons.'); end;
present();
for _, made in ipairs(uploads) do assert(released[made.id] == 1, 'And not again at the next Present.'); end;
-- icons.clear, as unload and a new device call it, does the same.
fresh();
present();
icons.status_at(1, 'Original FFXI', 20);
present(0.25);
local one = icons.status_at(1, 'Original FFXI', 20);
assert(one == uploads[1].id);
icons.clear();
assert(released[one] == 1, 'icons.clear releases it too.');

-- A failed upload draws the 32 px texture whole and is tried again 5 s later, not before.
fresh();
present();
icons.status_at(4, 'Original FFXI', 20);
present(0.25);
failing = true;
local fallbacks = assets.icon_sizes_report().fallbacks;
local texture, corner = icons.status_at(4, 'Original FFXI', 20);
assert(texture == whole(4, 'Original FFXI') and corner[1] == 1 and corner[2] == 1 and assets.icon_sizes_report().fallbacks == fallbacks + 1,
    'A failed upload draws the whole texture and is counted.');
failing = false;
for _ = 1, 3 do
    present(1);
    assert(icons.status_at(4, 'Original FFXI', 20) == whole(4, 'Original FFXI') and #uploads == 0, 'Not tried again before 5 s.');
end;
present(2);
texture, corner = icons.status_at(4, 'Original FFXI', 20);
assert(texture == uploads[1].id and corner[1] == 20 / 32 and #uploads == 1, 'Tried again 5 s later.');

-- XI View art: its own icons made from its own records, and an id it lacks made from the stock one at that size.
fresh();
present();
icons.status_at(2, 'XI View', 20); icons.status_at(7, 'XI View', 20);
present(0.25);
local own, own_corner = icons.status_at(2, 'XI View', 20);
local lacking, lacking_corner = icons.status_at(7, 'XI View', 20);
assert(own == uploads[1].id and uploads[1].label == 'xiview.status' and uploads[1].data:sub(129) == reference(xiview.records[2].dds, 20)
    and own_corner[1] == 20 / 32, 'XI View\'s own icon at 20 px.');
assert(lacking == uploads[2].id and uploads[2].label == 'original.status' and uploads[2].data:sub(129) == reference(stock.records[7].dds, 20)
    and lacking_corner[1] == 20 / 32, 'An id XI View lacks is the stock one at 20 px.');

-- Client art and 32 px draw today's texture whole, and nothing is made; neither do sizes past 128 or between pixels.
fresh();
present();
for _, case in ipairs({ { 'Client', 20 }, { 'Original FFXI', 32 }, { 'XI View', 32 }, { 'Original FFXI', 129 }, { 'Original FFXI', 19.5 },
    { 'Original FFXI', 0 } }) do
    texture, corner = icons.status_at(6, case[1], case[2]);
    assert(texture == whole(6, case[1]) and corner[1] == 1 and corner[2] == 1, 'Today\'s texture whole: ' .. case[1] .. ' at ' .. case[2]);
end;
present(1);
for _, case in ipairs({ { 'Client', 20 }, { 'Original FFXI', 32 }, { 'XI View', 32 }, { 'Original FFXI', 129 }, { 'Original FFXI', 19.5 } }) do
    assert(icons.status_at(6, case[1], case[2]) == whole(6, case[1]), 'Still today\'s texture: ' .. case[1] .. ' at ' .. case[2]);
end;
assert(#uploads == 0, 'Nothing is made for them.');
-- An id the art doesn't have at all draws nothing new either.
assert(assets.icon_texture_at('original', 40, 20) == nil and assets.icon_texture_at('original', -1, 20) == nil);

-- The strips draw it: 20 px icons beside 14 px rows 20 px apart, 1:1 from the corner, the cells touching; in a panel of
-- its own at 32 px the 32 px texture whole.
local overlay, defaults, hud = require('ui.native_party_hud'), require('ui.party_defaults'), require('ui.party_hud');
MOCK.screen = { 1920, 1080 };
local roster, subjects = hud.sample(2, 100);
for index = #roster.members, 3, -1 do table.remove(roster.members, index); end;
local frame = { x = 1795, y = 1017, width = 106, height = 34, rows = {}, row_height = 14, pitch = 20, measured_by = 'rows' };
for _, member in ipairs(roster.members) do
    frame.rows[member.slot] = { x = 1795, y = 1017 + member.slot * 20, width = 106, height = 14, slot = member.slot };
    subjects[member.id].effects, subjects[member.id].known = {}, true;
    for effect = 1, 3 do
        subjects[member.id].effects[effect] = { effect = effect, name = 'Effect ' .. effect, kind = 'buff', remaining = 30, total = 60, status = 'estimated' };
    end;
end;
local geometry = { available = true, groups = { frame } };
local p = defaults.make();
p.enabled, p.effects.icon_size = true, 32;
assert(p.style.icon_art == 'Original FFXI', 'Fixture: fresh party buffs use the stock art.');
local function images()
    MOCK.imgui_calls = {};
    overlay.draw(roster, subjects, p, 100, { native_geometry = geometry });
    local out = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddImage' then out[#out + 1] = MOCK.drawn[call]; end;
    end;
    return out;
end;
fresh();
present();
local drawn = images();
assert(#drawn == 6, 'Fixture: two members with three buffs each.');
for _, image in ipairs(drawn) do
    local id = image[2] == whole(1, 'Original FFXI') and 1 or image[2] == whole(2, 'Original FFXI') and 2 or image[2] == whole(3, 'Original FFXI') and 3;
    assert(id and image[6][1] == 1 and image[6][2] == 1, 'While a new size waits, the 32 px texture whole.');
end;
present(0.25);
drawn = images();
assert(#drawn == 6 and #uploads == 3, 'Three icons, each made once at 20 px for both members.');
for index, image in ipairs(drawn) do
    assert(image[4][1] - image[3][1] == 20 and image[4][2] - image[3][2] == 20 and image[5][1] == 0 and image[5][2] == 0
        and image[6][1] == 20 / 32 and image[6][2] == 20 / 32, 'Drawn 20 px square from the corner, 1:1.');
    local next_image = drawn[index + 1];
    if next_image and next_image[3][2] == image[3][2] then assert(next_image[3][1] == image[4][1] or next_image[4][1] == image[3][1], 'Touching.'); end;
end;
p.groups[1].native_detached, p.groups[1].detached_x, p.groups[1].detached_y = true, 300, 300;
p.groups[1].detached_width, p.groups[1].detached_height = 300, 200;
present(1);
drawn = images();
assert(#drawn == 6, 'Fixture: the panel draws six icons.');
for _, image in ipairs(drawn) do
    assert(image[4][1] - image[3][1] == 32 and image[6][1] == 1 and image[6][2] == 1, 'In a panel at 32 px, the 32 px texture whole.');
end;
p.effects.icon_size = 37;
present(1);
images();
present(0.25);
drawn = images();
for _, image in ipairs(drawn) do
    assert(image[4][1] - image[3][1] == 37 and image[6][1] == 37 / 64, 'In a panel at 37 px, made at 37 px.');
end;
assert(#MOCK.font_stack == 0);
icons._set_loader_for_tests(nil);
icons.clear();
return 'Party icons are made at the size they draw, 1:1, at most 4 a Present and 4 sizes an art, and fall back to the 32 px texture';
