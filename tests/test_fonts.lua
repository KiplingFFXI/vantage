local imgui = require('imgui')
package.loaded['ui.client_assets'] = {
    prepare = function() end, raw = function() return nil end, texture = function() return nil end,
    retry_pending = function() return false end, generation = function() return 0 end,
    layout = function() return nil end, cached_texture = function() return nil end,
    status = function() return { available = false, reason = 'Missing client font fixture.' } end,
    step = function(stage, done, work) return { name = stage, run = function() if not done() then work() end end } end,
    report = function() return {} end,
}
local custom = require('core.identity').path('fonts/'):gsub('/', '\\')
local loads, pushed = {}, nil
local fallback = {}
-- The custom fonts on disk: whole font files, Broken.ttf whole but refused by ImGui, one cut short and one that isn't
-- a font at all. A font file here is a header and its one table, the least one can be and hold every table it lists.
local function font_file(tag)
    return (tag or '\0\1\0\0') .. '\0\1\0\16\0\0\0\0' .. 'head' .. '\0\0\0\0' .. '\0\0\0\28' .. '\0\0\0\4' .. 'abcd'
end
assert(ashita.fs.create_dir(custom))
for name, bytes in pairs({ ['Zulu.OTF'] = font_file('OTTO'), ['beta.ttf'] = font_file('true'), ['Arial.ttf'] = font_file(),
    ['Alpha.ttf'] = font_file(), ['Broken.ttf'] = font_file(), ['Short.ttf'] = font_file():sub(1, 30),
    ['Notes.ttf'] = 'Just some notes, not a font.' }) do
    local file = assert(io.open(custom .. name, 'wb')); file:write(bytes); file:close()
end
ashita.fs.exists = function(path) return not path:find('georgiab.ttf', 1, true) end
ashita.fs.get_directory = function() return { 'Zulu.OTF', 'beta.ttf', 'Arial.ttf', 'Alpha.ttf', 'Broken.ttf', 'Short.ttf',
    'Notes.ttf', '../escape.ttf', 'note.txt' } end
imgui.AddFontFromFileTTF = function(path)
    loads[#loads + 1] = path
    if path == custom .. 'Broken.ttf' then error('Unreadable font') end
    return { path = path }
end
imgui.GetFont = function() return fallback end
imgui.PushFont = function(face, size) pushed = { face = face, size = size } end
imgui.PopFont = function() end
local fonts = require('ui.fonts')
assert(#fonts.names() == 19)
assert(fonts.names()[18] == 'Original FFXI' and fonts.names()[19] == 'XI View')
local function prepare()
    fonts.load()
    for _, step in ipairs(fonts.warmup_steps()) do step.run() end
end
prepare()
assert(#fonts.names() == 23, 'Only valid custom fonts join the built-in list.')
assert(fonts.names()[20] == 'Alpha' and fonts.names()[21] == 'Arial.ttf (custom)' and fonts.names()[22] == 'beta' and fonts.names()[23] == 'Zulu',
    'Custom fonts sort without regard to case.')
for _, path in ipairs(loads) do
    assert(not path:find('Short.ttf', 1, true) and not path:find('Notes.ttf', 1, true), 'A file that fails the check never reaches ImGui.')
end
local left_out = {}
for _, entry in ipairs(fonts.report('Zulu').skipped) do left_out[entry.file] = entry.reason end
assert(left_out['Short.ttf'] == 'The font file is cut short or damaged.' and left_out['Notes.ttf'] == 'The file is not a TrueType or OpenType font.'
    and left_out['Broken.ttf'] == 'ImGui could not load this font file.' and left_out['Zulu.OTF'] == nil,
    'Each custom font file left out is listed for /vg report with why.')
assert(require('ui.client_menu_fonts').check(custom .. 'Missing.ttf') == nil
    and select(2, require('ui.client_menu_fonts').check(custom .. 'Missing.ttf')) == 'The font file could not be opened.')
assert(fonts.failed('Original FFXI') and fonts.failed('XI View') and fonts.reason('XI View') == 'Missing client font fixture.')
assert(fonts.is_bitmap('Original FFXI') and fonts.is_bitmap('XI View') and not fonts.is_bitmap('Agave'))
assert(fonts.measure('Original FFXI', 'Haste', 13) == nil and fonts.draw({}, 'XI View', 'Haste', 0, 0, 13, 0xffffffff) == false)
assert(fonts.failed('Georgia Bold'), 'An unavailable built-in must explain its fallback.')
assert(fonts.failed('Missing custom face'), 'A saved custom selection that disappeared must explain its fallback.')
assert(not fonts.failed('Agave') and not fonts.failed('Ashita'))
fonts.push('Segoe UI Semibold', 23)
assert(pushed.face.path:find('seguisb.ttf', 1, true) and pushed.size == 23)
fonts.push('Arial', 18)
assert(pushed.face.path ~= custom .. 'Arial.ttf', 'A custom filename must not replace a built-in face.')
fonts.push('Arial.ttf (custom)', 18)
assert(pushed.face.path == custom .. 'Arial.ttf')
fonts.push('Georgia Bold', 17)
assert(pushed.face == fallback and pushed.size == 17)
fonts.push('Agave', 16)
assert(pushed.face == fallback, 'Existing default-font settings must keep their face.')
imgui.GetFont = function() return { path = 'a separately selected configuration font' } end
fonts.push('Agave', 16)
assert(pushed.face == fallback, 'Agave inside a nested preview must keep Ashita\'s original face.')
fonts.push('Missing custom face', 16)
assert(pushed.face == fallback, 'Missing HUD fonts cannot inherit the configuration window face.')
fonts.push('Original FFXI', 13)
assert(pushed.face == fallback and pushed.size == 13, 'Unavailable bitmap fonts use the cached fallback inside a nested preview.')
local count = #loads
prepare()
fonts.names()
fonts.push('Zulu', 20)
assert(#loads == count, 'Picking fonts or loading again must never rebuild the atlas.')
assert(pushed.face.path == custom .. 'Zulu.OTF')
for _, path in ipairs(loads) do assert(not path:find('escape', 1, true) and not path:find('note.txt', 1, true)) end
local defaults = require('ui.defaults')
local saved = defaults.make()
saved.style.font = ('Custom'):rep(20)
saved.style.font_size = 21
defaults.tidy(saved)
assert(saved.style.font == ('Custom'):rep(20) and saved.style.font_size == 21)
