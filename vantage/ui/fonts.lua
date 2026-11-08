local fonts = {}
local client_fonts = require('ui.client_fonts')
local menu_fonts = require('ui.client_menu_fonts')
local faces = {}
local choices = { 'Agave' }
local loaded = false
local default_face
-- For /vg report: the custom font files left out at load, each with why, and how many fonts ImGui's atlas held at
-- load and how many of them this load used again or added.
local skipped, atlas_counts = {}, { kept = 0, added = 0 }
local files = {
    { 'Segoe UI', 'segoeui.ttf' },
    { 'Arial', 'arial.ttf' },
    { 'Tahoma', 'tahoma.ttf' },
    { 'Verdana', 'verdana.ttf' },
    { 'Calibri', 'calibri.ttf' },
    { 'Consolas', 'consola.ttf' },
    { 'Segoe UI Semibold', 'seguisb.ttf' },
    { 'Tahoma Bold', 'tahomabd.ttf' },
    { 'Segoe UI Bold', 'segoeuib.ttf' },
    { 'Verdana Bold', 'verdanab.ttf' },
    { 'Arial Bold', 'arialbd.ttf' },
    { 'Calibri Bold', 'calibrib.ttf' },
    { 'Trebuchet MS Bold', 'trebucbd.ttf' },
    { 'Bahnschrift', 'bahnschrift.ttf' },
    { 'Consolas Bold', 'consolab.ttf' },
    { 'Georgia Bold', 'georgiab.ttf' },
}
local used_names = { agave = true, ashita = true, ['original ffxi'] = true, ['xi view'] = true }
for _, entry in ipairs(files) do
    choices[#choices + 1] = entry[1]
    used_names[entry[1]:lower()] = true
end
choices[#choices + 1], choices[#choices + 2] = 'Original FFXI', 'XI View'
fonts.labels = { Agave = 'Ashita (Agave)', Ashita = 'Ashita (Agave)' }

function fonts.names()
    return choices
end

fonts.is_bitmap = client_fonts.is_bitmap
fonts.measure = client_fonts.measure
fonts.draw = client_fonts.draw
fonts.measure_countdown = client_fonts.measure_countdown
fonts.countdown_renderer = client_fonts.countdown_renderer

-- Text in a look's font: the bitmap font, else ImGui's at one kept point, which ImGui copies.
-- outline draws the text that many pixels left, right, up and down first, black at the text's alpha.
local bit = require('bit')
local point = { 0, 0 }
local function paint(imgui, list, look, value, x, y, size, ink)
    if not fonts.draw(list, look.font, value, x, y, size, ink) then
        point[1], point[2] = x, y
        list:AddText(imgui.GetFont(), size, point, ink, value)
    end
end
function fonts.paint(imgui, list, look, value, x, y, size, ink, outline)
    if outline then
        local edge = bit.lshift(bit.rshift(ink, 24), 24)
        paint(imgui, list, look, value, x - outline, y, size, edge); paint(imgui, list, look, value, x + outline, y, size, edge)
        paint(imgui, list, look, value, x, y - outline, size, edge); paint(imgui, list, look, value, x, y + outline, size, edge)
    end
    paint(imgui, list, look, value, x, y, size, ink)
end

-- A font an addon adds can stay in ImGui's atlas after the addon unloads, and nothing here takes one out, as that
-- isn't known to be safe. So a reload doesn't add the same files again: each font this load adds or uses again is
-- noted in a process environment variable (VANTAGE_FONTS, through core/patterns.lua's kernel32 store) with its file,
-- the file's size and the atlas's id, size and name for it. The next load in the same game uses a noted font again only
-- while the atlas still holds a font with that id, size and name, and adds the file otherwise. Nothing is written to
-- disk, and nothing is kept when the game closes.
local FONTS = 'VANTAGE_FONTS'
local store
local function environment()
    if store == nil then
        local ok, finder = pcall(require, 'core.patterns')
        store = ok and type(finder) == 'table' and type(finder.environment) == 'function' and finder.environment(FONTS) or false
    end
    return store or nil
end

local function hex(text) return (text:gsub('.', function(c) return ('%02x'):format(c:byte()) end)) end
local function unhex(text) return (text:gsub('%x%x', function(pair) return string.char(tonumber(pair, 16)) end)) end

local function file_size(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local ok, size = pcall(file.seek, file, 'end')
    pcall(file.close, file)
    return ok and size or nil
end

local function describe(font)
    return font.FontId, font.LegacySize, font:GetDebugName()
end

-- The atlas's fonts by id, with their sizes and names, and how many it holds; nil when it can't be read, or when two
-- fonts share an id, as ids then can't tell one font from another.
local function atlas_fonts(imgui)
    local list, out = imgui.GetIO().Fonts.Fonts, {}
    local count = #list
    for index = 1, count do
        local font = list[index]
        local ok, id, size, name = pcall(describe, font)
        if ok and type(id) == 'number' and type(size) == 'number' and type(name) == 'string' then
            if out[id] then return nil end
            out[id] = { font = font, size = ('%.2f'):format(size), name = name }
        end
    end
    return out, count
end

-- The fonts the last load in this game noted, by lower-case path.
local function noted_fonts(source)
    local list = {}
    local ok, process = pcall(source.process)
    local read, text = pcall(source.read)
    if not ok or type(process) ~= 'number' or not read or type(text) ~= 'string' then return list end
    local pid, rest = text:match('^1;(%x+)(.*)$')
    if not pid or tonumber(pid, 16) ~= process then return list end
    for path, size, id, legacy, name, bytes in rest:gmatch(';(%x+),(%d+),(%d+),([%d%.]+),(%x*),(%d+)') do
        list[unhex(path):lower()] = { size = tonumber(size), id = tonumber(id), legacy = legacy, name = unhex(name),
            bytes = tonumber(bytes) }
    end
    return list
end

-- add(path, size) gives the face for the font file at path: the last load's while the atlas still holds it, else one
-- added now. save() notes them all for the next load.
local function font_adder(imgui)
    local source = environment()
    local previous = source and noted_fonts(source) or {}
    local listed, held, count = pcall(atlas_fonts, imgui)
    held = listed and held or {}
    atlas_counts.fonts = listed and count or nil
    local notes = {}
    local function note(path, size, face, bytes)
        local ok, id, legacy, name = pcall(describe, face)
        if ok and type(id) == 'number' and type(legacy) == 'number' and type(name) == 'string' and bytes then
            notes[#notes + 1] = (';%s,%d,%d,%.2f,%s,%d'):format(hex(path), size, id, legacy, hex(name), bytes)
        end
    end
    local function add(path, size)
        local bytes = file_size(path)
        local last = previous[path:lower()]
        local kept = last and last.size == size and last.bytes == bytes and held[last.id]
        if kept and kept.size == last.legacy and kept.name == last.name then
            atlas_counts.kept = atlas_counts.kept + 1
            note(path, size, kept.font, bytes)
            return kept.font
        end
        local ok, face = pcall(imgui.AddFontFromFileTTF, path, size)
        if not ok or not face then return nil end
        atlas_counts.added = atlas_counts.added + 1
        note(path, size, face, bytes)
        return face
    end
    local function save()
        if not source then return end
        local ok, process = pcall(source.process)
        if ok and type(process) == 'number' then pcall(source.write, ('1;%x'):format(process) .. table.concat(notes)) end
    end
    return add, save
end

local function register_fonts(add)
    if not ashita or not ashita.fs then return end
    local function load(name, path)
        if not ashita.fs.exists(path) then return false end
        local face = add(path, 18)
        if not face then return false end
        faces[name] = face
        return true
    end
    local folder = (os.getenv('WINDIR') or 'C:\\Windows') .. '\\Fonts\\'
    for _, entry in ipairs(files) do load(entry[1], folder .. entry[2]) end
    if not AshitaCore or not ashita.fs.get_directory then return end
    folder = require('core.identity').path('fonts/'):gsub('/', '\\')
    if not ashita.fs.exists(folder) then return end
    local ok, custom = pcall(ashita.fs.get_directory, folder, '.*\\.[tToO][tT][fF]$', false)
    if not ok or type(custom) ~= 'table' then return end
    local sorted = {}
    for _, file in ipairs(custom) do
        if type(file) == 'string' and #file <= 1024 and not file:find('[\\/:%c]') and not file:find('##', 1, true)
            and (file:lower():match('%.ttf$') or file:lower():match('%.otf$')) then
            sorted[#sorted + 1] = file
        end
    end
    table.sort(sorted, function(a, b) return a:lower() < b:lower() end)
    for _, file in ipairs(sorted) do
        local name = file:sub(1, -5)
        if used_names[name:lower()] then name = file .. ' (custom)' end
        if name ~= '' and not used_names[name:lower()] then
            -- ImGui reads a font file as its table directory says, so a file cut short or damaged is left out.
            local whole, why = menu_fonts.check(folder .. file)
            if not whole then skipped[#skipped + 1] = { file = file, reason = why }
            elseif not load(name, folder .. file) then
                skipped[#skipped + 1] = { file = file, reason = 'ImGui could not load this font file.' }
            else
                choices[#choices + 1] = name
                used_names[name:lower()] = true
            end
        end
    end
end

local function timed(stage, callback, ...)
    local ok, performance = pcall(require, 'core.performance')
    if not ok or type(performance) ~= 'table' or type(performance.now) ~= 'function'
        or type(performance.record) ~= 'function' then return callback(...) end
    local started = performance.now()
    local success, why = pcall(callback, ...)
    performance.record(stage, started)
    if not success then error(why, 0) end
end

-- What must happen in the load event, since ImGui takes new fonts only then: the menu fonts, from their cache
-- when it is whole so no client file is read, and the Windows and custom fonts, each the last load's when the atlas
-- still holds it. Changing the selection never rebuilds the atlas.
function fonts.load()
    if loaded then return end
    loaded = true
    local imgui = require('imgui')
    default_face = imgui.GetFont()
    local add, save = font_adder(imgui)
    local ok, why = pcall(function()
        timed('fonts.menu', menu_fonts.prepare, add)
        timed('fonts.registration', register_fonts, add)
    end)
    save()
    if not ok then error(why, 0) end
end

-- The rest as warmup steps, in order: the stock client art (the window frame in use, then the font), then the bitmap
-- face. Each does nothing once its work is done for the textures uploaded now.
function fonts.warmup_steps()
    local assets = require('ui.client_assets')
    local steps = assets.warmup_steps and assets.warmup_steps() or {}
    steps[#steps + 1] = assets.step('fonts.face', function() return client_fonts.current('Original FFXI') end, function()
        client_fonts.prepare()
        client_fonts.available('Original FFXI')
    end)
    return steps
end

function fonts.push(name, size)
    local imgui = require('imgui')
    imgui.PushFont(faces[name] or default_face or imgui.GetFont(), size or 16)
end

function fonts.face(name)
    return faces[name] or default_face or require('imgui').GetFont()
end

function fonts.pop()
    require('imgui').PopFont()
end

-- A client menu font is drawn at the multiple of 16 nearest size, as its glyphs are made on a 16 pixel grid and any
-- other size blurs them: 17, the default, draws at 16. The saved size isn't changed, and another font draws at it.
function fonts.push_window(name, size)
    local imgui = require('imgui')
    local menu = menu_fonts.face(name)
    size = size or 16
    if menu then size = math.max(16, math.floor((size + 8) / 16) * 16) end
    imgui.PushFont(menu or faces[name] or default_face or imgui.GetFont(), size)
end

function fonts.window_failed(name)
    if client_fonts.is_bitmap(name) then return menu_fonts.face(name) == nil end
    return fonts.failed(name)
end

function fonts.failed(name)
    if client_fonts.is_bitmap(name) then return not client_fonts.available(name) end
    return name ~= 'Agave' and name ~= 'Ashita' and faces[name] == nil
end

function fonts.reason(name)
    if client_fonts.is_bitmap(name) then return client_fonts.reason(name) end
    if fonts.failed(name) then return 'The selected font file is unavailable. The Ashita font is being used.' end
end

-- The fonts and the client art for /vg report, as plain values: the chosen font and why it isn't drawn as chosen, the
-- menu fonts, the custom font files left out, how many fonts ImGui's atlas held at load and how many this load used
-- again or added, the client art (client_assets.report) and why the last action icon wasn't drawn.
function fonts.report(name)
    local actions_ok, actions = pcall(require, 'ui.action_icons')
    local out = { font = type(name) == 'string' and name or nil, menu = menu_fonts.report(), skipped = skipped,
        atlas = { fonts = atlas_counts.fonts, kept = atlas_counts.kept, added = atlas_counts.added },
        client = require('ui.client_assets').report(), action_icon = actions_ok and actions.reason() or nil }
    if out.font then out.reason = fonts.reason(out.font) end
    return out
end

if VANTAGE_TEST_MODE then
    -- The font store in place of the environment: { read, write, process }, or nil for none.
    function fonts._set_store(value) store = value or false end
end

return fonts
