-- The client art owners hand out warmup steps: named, in load order, each doing one small piece and timing it, and
-- doing nothing once its piece is done. Of the window frames only the one in use is a step, and XI View's steps make
-- only the parts the look draws with. Running every step gives what the old one-shot loads gave, and the old one-shot
-- functions still work by running them. Art half made between steps is safe to ask for.
local function u16(value) return string.char(value % 256, math.floor(value / 256) % 256) end
local function u32(value) return u16(value % 65536) .. u16(math.floor(value / 65536)) end
local function chunk(kind, payload)
    local length = math.ceil((16 + #payload) / 16) * 16
    return 'TEST' .. u32(length / 16 * 128 + kind) .. string.rep('\0', 8) .. payload .. string.rep('\0', length - 16 - #payload)
end
local function texture(name, width, height)
    local data = string.rep(string.rep('\255', 8) .. '\255\255\0\0\0\0\0\0', math.ceil(width / 4) * math.ceil(height / 4))
    return chunk(0x20, string.char(0xA1) .. name .. u32(40) .. u32(width) .. u32(height)
        .. string.rep('\0', 28) .. '3TXD' .. u32(#data) .. u32(0) .. data)
end
local parts = {}
for code = 32, 126 do
    local width = code == 32 and 4 or 9
    local out = {}
    for _, value in ipairs({ 0, 0, width, 0, 0, 11, width, 11 }) do out[#out + 1] = u16(value) end
    out[#out + 1] = u16(width * 2 + 1) .. u16(23) .. u16(0) .. u16(0) .. '\0'
        .. string.rep(string.char(127), 16) .. string.char(1, 0, 1, 1) .. 'font    font    '
    parts[#parts + 1] = '\1' .. table.concat(out)
end
local glyphs = 'font    fontshp ' .. '\1' .. 'font    font    ' .. u16(95) .. table.concat(parts)
local font_dat = texture('font    moji    ', 1024, 2048) .. texture('font    font    ', 256, 256)
    .. texture('menu    gauge   ', 4, 4) .. texture('menu    colorbal', 4, 4) .. texture('menu    anc     ', 4, 4)
    .. chunk(0x31, glyphs)
local stock_root, view_root = 'C:/Fixture', 'C:/FixtureView'
local stock_font, view_font = stock_root .. '/ROM/119/51.DAT', view_root .. '/ROM/119/51.DAT'
local files = { [stock_font] = font_dat .. texture('menu    menu2fon', 128, 128) .. texture('menu    keytop  ', 4, 4),
    [view_font] = font_dat }
-- Each frame's pieces at the sizes the client draws them at.
for window = 14, 21 do
    files[stock_root .. ('/ROM/0/%d.DAT'):format(window)] = texture('menu    newtex  ', 128, 128) .. texture('menu    hfr1    ', 32, 32)
        .. texture('menu    corner  ', 32, 32) .. texture('menu    vfr1    ', 32, 32)
end
-- A look that draws every part with XI View, one that draws none, and one that draws only its status icons.
local function look(font, icon_art, recast_icon_art)
    return { style = { font = font, gauge_art = font, icon_art = icon_art, recast_icon_art = recast_icon_art } }
end
local all_view, no_view = look('XI View', 'XI View', 'XI View'), look('Original FFXI', 'Original FFXI', 'Original FFXI')
local view_icons = look('Original FFXI', 'XI View', 'Original FFXI')
local reads, uploads, labels = {}, 0, {}
local platform = {
    game_root = function() return stock_root end,
    ashita_root = function() return 'C:/FixtureAshita' end,
    xiview_path = function() return view_font end,
    read = function(filename)
        reads[filename] = (reads[filename] or 0) + 1
        return files[filename], 'No fixture asset.'
    end,
    upload = function(_, _, _, label)
        uploads = uploads + 1
        labels[#labels + 1] = label
        return { id = 900 + uploads, release = function() end }
    end,
}
local stages = {}
package.loaded['core.performance'] = {
    now = function() return MOCK.now end,
    record = function(stage) stages[#stages + 1] = stage end,
}
local function total()
    local count = 0
    for filename, value in pairs(reads) do if filename:match('%.DAT$') then count = count + value end end
    return count
end
local function upvalue(fn, wanted)
    for index = 1, 200 do
        local name, value = debug.getupvalue(fn, index)
        if name == wanted then return value end
        if not name then break end
    end
end
local owners = { 'ui.client_assets', 'ui.client_fonts', 'ui.client_menu_fonts', 'ui.fonts',
    'ui.icons', 'ui.item_icons', 'ui.recast_icons', 'ui.action_icons', 'ui.appearance' }
-- A new addon session: every owner starts over.
local function session()
    for _, name in ipairs(owners) do package.loaded[name] = nil end
    local assets = require('ui.client_assets')
    assets._set_platform_for_tests(platform)
    local function loader() return 77, function() end end
    require('ui.icons')._set_loader_for_tests(loader)
    require('ui.item_icons')._set_loader_for_tests(loader)
    reads, uploads, labels, stages = {}, 0, {}, {}
    return assets
end
local function names(steps)
    local out = {}
    for _, step in ipairs(steps) do out[#out + 1] = step.name end
    return table.concat(out, ',')
end
local function counted(list)
    local out = {}
    for _, value in ipairs(list) do out[value] = (out[value] or 0) + 1 end
    return out
end
local function same(a, b)
    for key, value in pairs(a) do if b[key] ~= value then return false end end
    for key, value in pairs(b) do if a[key] ~= value then return false end end
    return true
end

local assets = session()
local fonts, icons, recasts = require('ui.fonts'), require('ui.icons'), require('ui.recast_icons')
local appearance, client_fonts = require('ui.appearance'), require('ui.client_fonts')
local font_steps, icon_steps = fonts.warmup_steps(), icons.warmup_steps()
local recast_steps, view_steps = recasts.warmup_steps(), appearance.warmup_steps()
assert(names(font_steps) == 'assets.window,assets.original_font,fonts.face',
    'The font steps: the window frame in use, the stock font, then the face.')
assert(names(icon_steps) == 'icons.pack'
    and names(recast_steps) == 'recasts.items,actions.original.main,actions.original.secondary,actions.original.common',
    'The icon, job and recast steps.')
assert(names(view_steps) == 'assets.xiview_font,fonts.face.xiview,'
    .. 'icons.pack.xiview,actions.xiview.main,actions.xiview.secondary,actions.xiview.common',
    'The XI View steps.')
assert(total() == 0 and uploads == 0 and #stages == 0, 'Handing out steps does no work.')

-- The load part, then the stock steps one at a time: each reads at most one file and uploads only its own kind.
fonts.load()
local after_load = total()
assert(reads[stock_font] == 1 and reads[view_font] == 1 and uploads == 0,
    'The menu fonts read each font file once and upload nothing (no cache here: no file times).')
font_steps[1].run()
assert(total() == after_load + 1 and reads[stock_root .. '/ROM/0/14.DAT'] == 1 and uploads == 4
    and stages[#stages] == 'assets.window', 'The window step reads the frame in use, uploads its four textures and times itself.')
-- Half made: art not loaded yet is simply missing, and asking for it reads nothing.
local before = total()
assert(assets.cached_texture('window', 'newtex', 1) and not assets.cached_texture('window', 'newtex', 5)
    and not assets.cached_texture('original_font', 'gauge') and total() == before,
    'Art not loaded yet is missing, and asking for it reads nothing.')
assert(not assets.retry_pending() and assets.retry() == true and total() == before,
    'Recovery between steps retries nothing and reads nothing.')
assert(not client_fonts.available('Original FFXI') and total() == before,
    'Fonts asked for before their steps are missing and read nothing.')
font_steps[2].run()
assert(total() == before and reads[stock_font] == 1, 'The stock font kind uses the read the menu font made.')
assert(upvalue(upvalue(assets.prepare, 'load_stock'), 'stock_reader') == nil, 'That read is let go once the font is loaded.')
local state = upvalue(assets.clear, 'state')
assert(state.window2 == nil and state.window5 == nil and state.xiview_font.deferred,
    'The other frames wait for their first draw, and XI View for its first use.')
local moji = state.original_font.data.textures['font    moji    ']
assert(moji.dds, 'The stock font keeps its pixels until its face is made.')
font_steps[3].run()
assert(client_fonts.current('Original FFXI') and client_fonts.available('Original FFXI') and not moji.dds and total() == before,
    'The face step makes the stock face and lets the font pixels go.')
local after_fonts, sent, timed = total(), uploads, #stages
for _, step in ipairs(font_steps) do step.run() end
assert(total() == after_fonts and uploads == sent and #stages == timed, 'Finished font steps do nothing.')

for _, list in ipairs({ icon_steps, recast_steps }) do
    for _, step in ipairs(list) do
        local count = #stages
        step.run()
        assert(#stages == count + 1 and stages[#stages] == step.name, 'Each step times itself under its own name.')
    end
end
assert(reads[stock_root .. '/ROM/119/57.DAT'] == 1 and reads[stock_root .. '/ROM/280/15.DAT'] == 1
    and reads[stock_root .. '/ROM/324/95.DAT'] == 1 and reads[stock_font] == 1,
    'The status icons and each action file are read once; the file the actions share with the font isn\'t read again.')
assert(reads['C:/FixtureAshita/config/pivot/pivot.ini'] == 1,
    'Where the art is comes from one read of the overlay settings, for the art, the status icons and the action icons.')
assert(assets.icons_prepared() and assets.action_loaded('original', 'main') and assets.action_loaded('original', 'secondary')
    and assets.action_loaded('original', 'common') and not assets.action_loaded('xiview', 'main'),
    'The stock icon and action packs are loaded; XI View\'s are not.')
local stock_reads, stock_uploads, stock_stages = total(), uploads, #stages
for _, list in ipairs({ icon_steps, recast_steps }) do for _, step in ipairs(list) do step.run() end end
assert(total() == stock_reads and uploads == stock_uploads and #stages == stock_stages, 'Finished steps do nothing.')

-- XI View's steps make nothing for a look that doesn't draw with it.
appearance.uses_xiview(no_view)
for _, step in ipairs(view_steps) do step.run() end
assert(total() == stock_reads and uploads == stock_uploads and #stages == stock_stages and state.xiview_font.deferred
    and not client_fonts.current('XI View') and not assets.icons_loaded('xiview') and not assets.action_loaded('xiview', 'main'),
    'A look without XI View runs none of its steps.')

-- XI View, one piece at a time, for a look that draws every part with it.
appearance.uses_xiview(all_view)
for _, step in ipairs(view_steps) do step.run() end
assert(not state.xiview_font.deferred and client_fonts.available('XI View')
    and assets.icons_loaded('xiview') and assets.action_loaded('xiview', 'common'),
    'The XI View steps load its art, faces, icons and actions.')
assert(reads[view_font] == 2,
    'XI View\'s art and the texture its actions share with it come from one read; its menu font made its own at load.')
local view_reads, view_uploads, view_stages = total(), uploads, #stages
appearance.preload_xiview()
for _, step in ipairs(view_steps) do step.run() end
assert(total() == view_reads and uploads == view_uploads and #stages == view_stages,
    'The preload and finished XI View steps do nothing more.')
local stepped = { reads = {}, labels = counted(labels) }
for filename, count in pairs(reads) do stepped.reads[filename] = count end
assert(stepped.labels['original_font.moji'] == 1 and stepped.labels['xiview_font.moji'] == 1
    and stepped.labels['window.newtex'] == 1 and stepped.labels['window.vfr1'] == 1
    and stepped.labels['original_font.countdown'] == 1,
    'Every upload names its texture.')
for window = 15, 21 do
    assert(reads[stock_root .. ('/ROM/0/%d.DAT'):format(window)] == nil, 'A frame not in use is never read.')
end

-- A device change clears the art; the same steps then make it again.
assets.clear(); icons.clear(); recasts.clear()
local cleared = total()
for _, list in ipairs({ font_steps, icon_steps, recast_steps }) do for _, step in ipairs(list) do step.run() end end
-- The frame in use and the font file; the status icons and their fallback file; the two action files of their own.
assert(total() == cleared + 6 and client_fonts.available('Original FFXI')
    and assets.icons_prepared(), 'After a device change the steps read and make the stock art again.')

-- One-shot loads give the same reads and uploads as the steps.
assets = session()
local one_shot = require('ui.fonts')
one_shot.load()
for _, step in ipairs(one_shot.warmup_steps()) do step.run() end
require('ui.icons').prepare()
require('ui.recast_icons').prepare()
require('ui.appearance').uses_xiview(all_view)
require('ui.appearance').preload_xiview()
assert(same(reads, stepped.reads) and same(counted(labels), stepped.labels),
    'Running every step reads and uploads exactly what the one-shot loads do.')
assert(require('ui.client_fonts').available('Original FFXI') and require('ui.client_fonts').available('XI View'),
    'The one-shot loads make both faces.')

-- XI View asked for before any stock step loads only XI View.
assets = session()
require('ui.fonts').load()
assert(assets.cached_texture('xiview_font', 'moji') and not upvalue(assets.clear, 'state').window,
    'A first XI View use reads and uploads XI View and leaves the stock art to its steps.')

-- A look that draws only its status icons with XI View runs only their step; the rest of XI View waits for a first use.
assets = session()
require('ui.fonts').load()
appearance = require('ui.appearance')
appearance.uses_xiview(view_icons)
local timed_view = #stages
for _, step in ipairs(appearance.warmup_steps()) do step.run() end
assert(#stages == timed_view + 1 and stages[#stages] == 'icons.pack.xiview' and assets.icons_loaded('xiview')
    and upvalue(assets.clear, 'state').xiview_font.deferred and not require('ui.client_fonts').current('XI View')
    and not assets.action_loaded('xiview', 'main') and reads[view_font] == 1,
    'Only the status icons are made, and XI View\'s font file is read for nothing else.')

-- A failing step times itself and raises its error; a step runs without the timer too.
local step = assets.step('broken', function() return false end, function() error('broken step', 0) end)
local ok, why = pcall(step.run)
assert(not ok and why == 'broken step' and stages[#stages] == 'broken', 'A failing step is timed and raises.')
package.loaded['core.performance'] = nil
package.preload['core.performance'] = function() error('No counter here.') end
local runs = 0
step = assets.step('plain', function() return runs > 0 end, function() runs = runs + 1 end)
step.run(); step.run()
assert(runs == 1, 'A step works without the timer, and only once.')
package.preload['core.performance'] = nil
assets.clear()
return true
