-- The window art sends only the pieces that show. A frame edge whose art is the same all along its length, read from
-- the texture's own pixels as it loads (DXT1, DXT3 or DXT5), is one stretched piece instead of tiles. The settings
-- window, painted in two clipped parts around its resize grip, sends each part only the pieces inside its clip.
local assets = require('ui.client_assets')
local function le16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
local function le32(n) return le16(n % 65536) .. le16(math.floor(n / 65536)) end
local function chunk(kind, payload)
    local length = math.ceil((16 + #payload) / 16) * 16
    return 'TEST' .. le32(length / 16 * 128 + kind) .. string.rep('\0', 8) .. payload .. string.rep('\0', length - 16 - #payload)
end
local names = { newtex = 'menu    newtex  ', hfr1 = 'menu    hfr1    ', corner = 'menu    corner  ', vfr1 = 'menu    vfr1    ' }
local function texture(name, format, data, size)
    return chunk(0x20, string.char(0xA1) .. names[name] .. le32(40) .. le32(size) .. le32(size) .. string.rep('\0', 28)
        .. format:reverse() .. le32(#data) .. le32(0) .. data)
end
-- A row of four 2-bit color indices, and a DXT1 color block from two 565 end colors and four rows.
local function row(a, b, c, d) return a + b * 4 + c * 16 + d * 64 end
local function colors(c0, c1, r1, r2, r3, r4) return le16(c0) .. le16(c1) .. string.char(r1, r2, r3, r4) end
-- DXT3's alpha: four rows of four 4-bit alphas. DXT5's: two end alphas and sixteen 3-bit indices.
local function nibbles(a, b, c, d) return le16(a + b * 16 + c * 256 + d * 4096) end
local function alpha5(a0, a1, index)
    local halves = {}
    for half = 0, 1 do
        local bits = 0
        for texel = 7, 0, -1 do bits = bits * 8 + index(half * 8 + texel) end
        halves[#halves + 1] = string.char(bits % 256, math.floor(bits / 256) % 256, math.floor(bits / 65536))
    end
    return string.char(a0, a1) .. table.concat(halves)
end
local RED, BLUE, GREEN = 0xF800, 0x001F, 0x07E0
local by_row = colors(RED, BLUE, row(0, 0, 0, 0), row(1, 1, 1, 1), row(2, 2, 2, 2), row(3, 3, 3, 3))
local by_column = colors(RED, BLUE, row(0, 1, 2, 3), row(0, 1, 2, 3), row(0, 1, 2, 3), row(0, 1, 2, 3))
-- Equal end colors: DXT1's first three indices are the one color and its fourth is see-through, while DXT3 and DXT5
-- always have four colors.
local one_color = colors(GREEN, GREEN, row(0, 1, 2, 1), row(2, 1, 0, 0), row(1, 1, 2, 0), row(0, 2, 2, 1))
local one_with_fourth = colors(GREEN, GREEN, row(0, 1, 2, 1), row(2, 3, 0, 0), row(1, 1, 2, 0), row(0, 2, 2, 1))
local solid = nibbles(15, 15, 15, 15):rep(4)
local cases = {
    { 'DXT1', by_row:rep(64), 'DXT1', by_column:rep(64), true, false, false, true, 'Rows and columns of DXT1' },
    { 'DXT1', one_color:rep(64), 'DXT1', one_with_fourth:rep(64), true, true, false, false,
        'Equal end colors are one color, but not with DXT1\'s see-through fourth index' },
    { 'DXT3', (nibbles(0, 0, 0, 0) .. nibbles(5, 5, 5, 5) .. nibbles(9, 9, 9, 9) .. nibbles(15, 15, 15, 15) .. one_color):rep(64),
        'DXT3', (solid .. one_with_fourth):rep(64), true, false, true, true, 'DXT3\'s alpha by row, and its four colors' },
    { 'DXT5', (alpha5(255, 0, function(texel) return texel % 4; end) .. one_color):rep(64),
        'DXT5', (alpha5(10, 200, function(texel) return texel < 8 and 6 or 7; end) .. one_color):rep(64),
        false, true, true, false, 'DXT5\'s alpha by column, and its six-alpha blocks' },
    { 'DXT1', colors(RED, RED, 0, 0, 0, 0) .. colors(BLUE, BLUE, 0, 0, 0, 0):rep(63), 'DXT1', by_row:rep(64),
        false, false, true, false, 'One block of another color' },
}
local game, files, uploads = 'C:/Client Root', {}, 0
for window_type, case in ipairs(cases) do
    files[game .. ('/ROM/0/%d.DAT'):format(13 + window_type)] = texture('newtex', 'DXT1', string.rep('\0', 8192), 128)
        .. texture('hfr1', case[1], case[2], 32) .. texture('corner', 'DXT1', string.rep('\0', 512), 32)
        .. texture('vfr1', case[3], case[4], 32)
end
assets._set_platform_for_tests({
    game_root = function() return game; end,
    ashita_root = function() return 'C:/Ashita Root'; end,
    read = function(filename) return files[filename], 'Fixture file missing.'; end,
    upload = function() uploads = uploads + 1; return { id = uploads, release = function() end }; end,
});
for window_type, case in ipairs(cases) do
    local horizontal, vertical = assets.texture('window', 'hfr1', window_type), assets.texture('window', 'vfr1', window_type)
    assert(horizontal and vertical, 'Fixture: window type ' .. window_type .. ' loads.')
    assert(horizontal.across == case[5] and horizontal.down == case[6] and vertical.across == case[7] and vertical.down == case[8],
        ('%s: across %s and down %s, then across %s and down %s'):format(case[9], tostring(horizontal.across),
        tostring(horizontal.down), tostring(vertical.across), tostring(vertical.down)))
    assert(assets.texture('window', 'newtex', window_type).across == nil, 'Only the edges are read for this.')
end

-- A panel: each of window type 1's edges is one piece. Type 2's top and bottom are, its sides tiled, and type 4's
-- edges are all tiled.
local skin = require('ui.client_skin')
local sent, active = {}, nil
local list = {
    GetClipRectMin = function() return 0, 0; end, GetClipRectMax = function() return 1920, 1080; end,
    PushClipRect = function(_, first, last, intersect)
        assert(intersect == true and active == nil, 'Fixture: one clip at a time.')
        active = { first[1], first[2], last[1], last[2] };
    end,
    PopClipRect = function() active = nil; end,
    AddImage = function(_, id, first, last, uv1, uv2)
        sent[#sent + 1] = { id, first[1], first[2], last[1], last[2], uv1[1], uv1[2], uv2[1], uv2[2], clip = active };
    end,
    AddTriangleFilled = function() end, AddRectFilled = function() end,
};
local function style(window_type)
    return { theme = 'Original FFXI', window_type = window_type, scale = 1, opacity = 1, background = true, border = true,
        background_color = { 1, 1, 1, 1 }, border_color = { 1, 1, 1, 1 } };
end
local function pieces(id)
    local found = {};
    for _, piece in ipairs(sent) do if piece[1] == id then found[#found + 1] = piece; end end
    return found;
end
local rect = { x = 40, y = 60, width = 300, height = 200 };
sent = {};
assert(skin.panel(list, rect, style(1), {}));
-- The 16 px corners leave the top and bottom 56 to 324 across, and the sides 76 to 244 down.
local across, down = pieces(assets.texture('window', 'hfr1', 1).id), pieces(assets.texture('window', 'vfr1', 1).id);
assert(#across == 2 and #down == 2, ('Each even edge is one piece, not %d across and %d down.'):format(#across, #down));
for index, y in ipairs({ 60, 244 }) do
    local piece, v = across[index], (index - 1) / 2;
    assert(piece[2] == 56 and piece[3] == y and piece[4] == 324 and piece[5] == y + 16 and piece[6] == 0 and piece[7] == v
        and piece[8] == 1 and piece[9] == v + 0.5,
        'A stretched edge covers what its tiles did, with the whole length of its art: ' .. table.concat(piece, ', ', 2, 9));
end
for index, x in ipairs({ 40, 324 }) do
    local piece, u = down[index], (index - 1) / 2;
    assert(piece[2] == x and piece[3] == 76 and piece[4] == x + 16 and piece[5] == 244 and piece[6] == u and piece[7] == 0
        and piece[8] == u + 0.5 and piece[9] == 1, 'A stretched side: ' .. table.concat(piece, ', ', 2, 9));
end
sent = {};
assert(skin.panel(list, rect, style(2), {}));
assert(#pieces(assets.texture('window', 'hfr1', 2).id) == 2 and #pieces(assets.texture('window', 'vfr1', 2).id) > 2,
    'Window type 2\'s top and bottom are one piece each, and its sides stay tiled.');
sent = {};
assert(skin.panel(list, rect, style(4), {}));
assert(#pieces(assets.texture('window', 'hfr1', 4).id) > 2 and #pieces(assets.texture('window', 'vfr1', 4).id) > 2,
    'Edges that change along their length stay tiled.');

-- The settings window at 960 by 680 under a 20 px title, its grip 30 px: the part above the grip and the strip beside
-- it each get the pieces of the whole panel that reach into their clip, the same pieces, and no others.
local gui = {
    GetWindowDrawList = function() return list; end,
    GetWindowPos = function() return 100, 50; end, GetWindowSize = function() return 960, 680; end,
    GetFrameHeight = function() return 20; end, GetFontSize = function() return 16; end, GetStyle = function() return { WindowRounding = 0 }; end,
};
local function key(piece)
    local parts = {};
    for i = 1, 9 do parts[i] = ('%.3f'):format(piece[i]); end
    return table.concat(parts, ' ');
end
local function inside(piece, clip)
    return piece[2] < clip[3] and piece[3] < clip[4] and piece[4] > clip[1] and piece[5] > clip[2];
end
for _, window_type in ipairs({ 1, 4 }) do
    local look = { theme = 'Original FFXI', window_type = window_type, background = { 1, 1, 1, 1 }, dropdowns = { 1, 1, 1, 1 },
        border = { 1, 1, 1, 1 } };
    sent = {};
    assert(skin.panel(list, { x = 100, y = 70, width = 960, height = 660 }, style(window_type), {}));
    local whole = sent;
    sent = {};
    assert(skin.menu(gui, look, 'window') and active == nil);
    local clips, by_clip = {}, {};
    for _, piece in ipairs(sent) do
        assert(piece.clip, 'Every piece is drawn inside a clip.');
        if not by_clip[piece.clip] then clips[#clips + 1], by_clip[piece.clip] = piece.clip, {}; end
        by_clip[piece.clip][key(piece)] = (by_clip[piece.clip][key(piece)] or 0) + 1;
    end
    assert(#clips == 2, 'Fixture: two parts around the grip.');
    for _, clip in ipairs(clips) do
        local want = {};
        for _, piece in ipairs(whole) do if inside(piece, clip) then want[key(piece)] = (want[key(piece)] or 0) + 1; end end
        for name, count in pairs(want) do
            assert(by_clip[clip][name] == count, ('Type %d: the piece %s reaches into the clip and is sent.'):format(window_type, name));
        end
        for name, count in pairs(by_clip[clip]) do
            assert(want[name] == count, ('Type %d: the piece %s is outside the clip or sent twice.'):format(window_type, name));
        end
    end
    if window_type == 1 then
        assert(#sent <= 70, 'With even edges the settings window sends ' .. #sent .. ' pieces, not 300.');
    end
end
