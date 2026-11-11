-- A client menu font is whole pixels on a 16 pixel grid. ImGui draws a font under 36 pixels at twice its width and
-- narrows it again, which spreads each pixel over two columns, so the font's own source asks for its own width
-- (OversampleH 1) before the font draws anything. A font an older load added never asked, and ImGui keeps the glyphs it
-- has drawn, so that one is added again once, then used again like any other. /vg report says which a font is.
local imgui = require('imgui')
package.loaded['ui.client_assets'] = {
    prepare = function() end, raw = function() return nil end, texture = function() return nil end,
    retry_pending = function() return false end, generation = function() return 0 end,
    layout = function() return nil end, cached_texture = function() return nil end,
    status = function() return { available = false, reason = 'Missing client font fixture.' } end,
    step = function(stage, done, work) return { name = stage, run = function() if not done() then work() end end } end,
    report = function() return {} end,
}
local folder = require('core.identity').path('cache/client-fonts')
assert(ashita.fs.create_dir(folder))
local menu_path = folder .. '/original_font-v2-0123456789abcdef.ttf'
local file = assert(io.open(menu_path, 'wb')); file:write('a menu font'); file:close()
-- No Windows or custom fonts here: the menu font is the only one.
ashita.fs.exists = function() return false end

-- ImGui's atlas. A font has its own source and the icon font Ashita merges into every font it adds, each with the
-- width it is drawn at: 0 lets ImGui choose, which is twice the width under 36 pixels.
local atlas, added, next_id, sources = {}, {}, 0, nil
local function plain_sources() return { { OversampleH = 0 }, { OversampleH = 0 } } end
imgui.GetIO = function() return { Fonts = { Fonts = atlas } } end
imgui.AddFontFromFileTTF = function(path, size)
    next_id = next_id + 1
    local font = { FontId = next_id, LegacySize = size, name = path:match('[^\\/]+$'), Sources = sources() }
    function font:GetDebugName() return self.name end
    added[#added + 1], atlas[#atlas + 1] = path, font
    return font
end
imgui.GetFont = function() return 'default' end

-- The menu fonts stand in: Original FFXI is the file above, added sharp as the real prepare adds it, or the way a
-- load from before this did when older is true.
local real = require('ui.client_menu_fonts')
local face, older, at_load
package.loaded['ui.client_menu_fonts'] = {
    check = real.check,
    prepare = function(load)
        if older then face = load(menu_path, 16) else face = load(menu_path, 16, true) end
        local source = face and type(face.Sources) == 'table' and face.Sources[1]
        at_load = source and source.OversampleH
    end,
    face = function(name) return name == 'Original FFXI' and face or nil end,
    report = function() return { ['Original FFXI'] = { loaded = face ~= nil }, ['XI View'] = { loaded = false } } end,
}
local function session(store)
    package.loaded['ui.fonts'] = nil
    local fonts = require('ui.fonts')
    fonts._set_store(store)
    added, face, at_load = {}, nil, nil
    fonts.load()
    return fonts
end
local function sharp(fonts) return fonts.report().menu['Original FFXI'].sharp end

sources = plain_sources
local kept = MOCK.pattern_store(nil, 1234)
local fonts = session(kept)
assert(#added == 1 and added[1] == menu_path, 'Fixture: the menu font is added from its file.')
assert(face.Sources[1].OversampleH == 1 and at_load == 1, 'The menu font asks for its own width as soon as it is added.')
assert(face.Sources[2].OversampleH == 0, 'The icon font merged into it is left as it was.')
assert(sharp(fonts) == true and fonts.report().menu['XI View'].sharp == nil,
    '/vg report says the font is drawn at its own width, and nothing for a font ImGui never took.')
local first = face

fonts = session(kept)
assert(#added == 0 and face == first and sharp(fonts) == true, 'A reload uses the sharp font again and adds nothing.')
for _ = 1, 10 do fonts = session(kept) end
assert(#atlas == 1 and face == first, 'However often it reloads.')

-- A font from a load before this: added without asking, so its glyphs were drawn smeared and ImGui keeps them.
atlas, next_id = {}, 0
local before = MOCK.pattern_store(nil, 1234)
older = true
session(before)
local smeared = face
assert(#added == 1 and smeared.Sources[1].OversampleH == 0, 'Fixture: an older load adds the font without asking.')
older = false
fonts = session(before)
assert(#added == 1 and face ~= smeared and face.Sources[1].OversampleH == 1 and sharp(fonts) == true,
    'The older font is not used again: the file is added once more, sharp.')
assert(smeared.Sources[1].OversampleH == 0, 'The older font is left alone.')
local second = face
fonts = session(before)
assert(#added == 0 and face == second and #atlas == 2, 'From then on the sharp font is used again.')
-- And back: an older load after this one looks under the plain path, so it never takes the sharp font for its own.
older = true
session(before)
assert(#added == 1 and face ~= second, 'A load from before this adds its own font.')
older = false

-- A binding that gives no sources, or one whose sources can't be written: the font is still added and drawn, the
-- report says what is known, and a reload adds nothing more.
for _, case in ipairs({
    { 'no sources', function() return nil end, nil },
    { 'an empty list', function() return {} end, nil },
    { 'a source that can\'t be written',
        function() return { setmetatable({}, { __index = { OversampleH = 0 }, __newindex = function() error('read only') end }) } end, false },
    { 'a source that keeps a width of 2',
        function() return { setmetatable({}, { __index = { OversampleH = 2 }, __newindex = function() end }) } end, false },
    { 'a source with no width', function() return { {} } end, true },
}) do
    atlas, next_id, sources = {}, 0, case[2]
    local store = MOCK.pattern_store(nil, 1234)
    local ok, loaded = pcall(session, store)
    assert(ok and #added == 1 and face ~= nil, 'With ' .. case[1] .. ' the menu font is still added: ' .. tostring(loaded))
    assert(sharp(loaded) == case[3], 'With ' .. case[1] .. ' the report says what ImGui says.')
    local only = face
    loaded = session(store)
    assert(#added == 0 and face == only and #atlas == 1, 'With ' .. case[1] .. ' a reload adds nothing.')
end
return 'Menu fonts ask ImGui for their own width, once, before they draw'
