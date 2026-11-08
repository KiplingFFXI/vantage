-- A reload in the same game uses again each font the last load added while ImGui's atlas still holds it, so the atlas
-- doesn't gain the same files at every reload. A font whose file or size changed, one the atlas no longer holds as it
-- was, and one noted by another game are added again. The notes live in the process environment, never on disk.
local imgui = require('imgui')
package.loaded['ui.client_assets'] = {
    prepare = function() end, raw = function() return nil end, texture = function() return nil end,
    retry_pending = function() return false end, generation = function() return 0 end,
    layout = function() return nil end, cached_texture = function() return nil end,
    status = function() return { available = false, reason = 'Missing client font fixture.' } end,
    step = function(stage, done, work) return { name = stage, run = function() if not done() then work() end end } end,
    report = function() return {} end,
}
-- Two custom fonts on disk, each a header and its one table.
local custom = require('core.identity').path('fonts/'):gsub('/', '\\')
local function write(name, bytes)
    local file = assert(io.open(custom .. name, 'wb')); file:write(bytes); file:close()
end
local function font_file(extra)
    return '\0\1\0\0' .. '\0\1\0\16\0\0\0\0' .. 'head' .. '\0\0\0\0' .. '\0\0\0\28' .. ('\0\0\0' .. string.char(4 + #extra))
        .. 'abcd' .. extra
end
assert(ashita.fs.create_dir(custom))
write('Alpha.ttf', font_file(''))
write('Beta.ttf', font_file(''))
-- Only the custom folder is there: no Windows fonts.
ashita.fs.exists = function(path) return path:sub(1, #custom) == custom end
ashita.fs.get_directory = function() return { 'Alpha.ttf', 'Beta.ttf' } end

-- ImGui's atlas: each font it adds has an id, a size and a name, as the binding gives them.
local atlas, added, next_id = {}, {}, 0
local function atlas_font(size, name)
    next_id = next_id + 1
    local font = { FontId = next_id, LegacySize = size, name = name }
    function font:GetDebugName() return self.name end
    return font
end
imgui.GetIO = function() return { Fonts = { Fonts = atlas } } end
imgui.AddFontFromFileTTF = function(path, size)
    added[#added + 1] = path
    local font = atlas_font(size, path:match('[^\\/]+$'))
    atlas[#atlas + 1] = font
    return font
end
imgui.GetFont = function() return 'default' end
local pushed
imgui.PushFont = function(face) pushed = face end

-- A new addon session in the same game, with its notes in store.
local function session(store)
    package.loaded['ui.fonts'] = nil
    local fonts = require('ui.fonts')
    fonts._set_store(store)
    added = {}
    fonts.load()
    return fonts
end
local function face(fonts, name)
    fonts.push(name, 18)
    return pushed
end

local kept = MOCK.pattern_store(nil, 1234)
local fonts = session(kept)
local alpha, beta = face(fonts, 'Alpha'), face(fonts, 'Beta')
local atlas_report = fonts.report().atlas
assert(#added == 2 and #atlas == 2 and alpha ~= beta and atlas_report.fonts == 0 and atlas_report.kept == 0
    and atlas_report.added == 2, 'The first load adds each font.')
assert(kept.text and kept.text:match('^1;4d2;'), 'It notes them for the next load in this game: ' .. tostring(kept.text))

fonts = session(kept)
atlas_report = fonts.report().atlas
assert(#added == 0 and #atlas == 2 and face(fonts, 'Alpha') == alpha and face(fonts, 'Beta') == beta
    and atlas_report.fonts == 2 and atlas_report.kept == 2 and atlas_report.added == 0,
    'A reload uses the atlas\'s fonts again and adds nothing.')
for _ = 1, 10 do fonts = session(kept) end
assert(#atlas == 2 and fonts.report().atlas.kept == 2, 'However often it reloads.')

-- A file that changed is added again; the other is still used again.
write('Beta.ttf', font_file('efgh'))
fonts = session(kept)
assert(#added == 1 and added[1] == custom .. 'Beta.ttf' and face(fonts, 'Alpha') == alpha and face(fonts, 'Beta') ~= beta
    and fonts.report().atlas.kept == 1 and fonts.report().atlas.added == 1, 'A changed file is added again.')
beta = face(fonts, 'Beta')

-- A font the atlas no longer holds as it was: gone, renamed or a new size under its id.
assert(atlas[1] == alpha)
table.remove(atlas, 1)
fonts = session(kept)
assert(#added == 1 and added[1] == custom .. 'Alpha.ttf' and face(fonts, 'Alpha') ~= alpha, 'A font the atlas let go is added again.')
alpha = face(fonts, 'Alpha')
for _, change in ipairs({ function(font) font.name = 'Other.ttf' end, function(font) font.LegacySize = 20 end }) do
    for _, font in ipairs(atlas) do if font == alpha then change(font) end end
    fonts = session(kept)
    assert(#added == 1 and added[1] == custom .. 'Alpha.ttf' and face(fonts, 'Alpha') ~= alpha,
        'A font whose atlas entry changed is added again.')
    alpha = face(fonts, 'Alpha')
end

-- A note for another size, or from another game, is never used.
fonts = session(MOCK.pattern_store((kept.text:gsub(',18,', ',17,')), 1234))
assert(#added == 2, 'Fonts noted at another size are added again.')
fonts = session(MOCK.pattern_store(kept.text, 999))
assert(#added == 2, 'Notes from another game are not used.')
for _, junk in ipairs({ '', 'junk', '1;zz;', '1;4d2;notes' }) do
    fonts = session(MOCK.pattern_store(junk, 1234))
    assert(#added == 2, 'Notes that can\'t be read add every font: ' .. junk)
end

-- An atlas the binding can't list, or one with two fonts under one id, uses nothing again.
imgui.GetIO = function() return {} end
fonts = session(MOCK.pattern_store(kept.text, 1234))
assert(#added == 2 and fonts.report().atlas.fonts == nil, 'An atlas that can\'t be read adds every font.')
imgui.GetIO = function() return { Fonts = { Fonts = atlas } } end
local twin = atlas_font(18, 'Twin.ttf')
twin.FontId = atlas[1].FontId
atlas[#atlas + 1] = twin
fonts = session(MOCK.pattern_store(kept.text, 1234))
assert(#added == 2, 'Two fonts under one id can\'t be told apart, so every font is added.')
return 'Fonts used again on a reload while the atlas holds them'
