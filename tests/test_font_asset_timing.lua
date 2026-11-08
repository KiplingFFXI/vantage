local stages = {}
local performance = {
    now = function() return MOCK.now end,
    record = function(stage, started)
        stages[#stages + 1] = { stage, started, MOCK.now - started }
    end,
}
package.loaded['core.performance'] = performance
local function upvalue(fn, wanted)
    for i = 1, 100 do
        local name, value = debug.getupvalue(fn, i)
        if name == wanted then return value end
        if not name then break end
    end
    error('Missing upvalue: ' .. wanted)
end
local function pack(...) return { count = select('#', ...), ... } end
local assets = require('ui.client_assets')
local native = upvalue(upvalue(assets.prepare_icons, 'art_roots'), 'native')
local measure = upvalue(native, 'measure_native')
local marker, returned = {}, {}
local calls = 0
local api = {
    read = function(...)
        assert(select('#', ...) == 3 and select(2, ...) == nil)
        calls = calls + 1
        MOCK.now = MOCK.now + 0.25
        return nil, 'Unavailable', nil, returned
    end,
    upload = function() MOCK.now = MOCK.now + 0.5; error(marker, 0) end,
}
assert(measure(api) == api)
local values = pack(api.read('source', nil, 4))
assert(values.count == 4 and values[1] == nil and values[2] == 'Unavailable'
    and values[3] == nil and values[4] == returned and calls == 1,
    'Asset timings preserve argument and result counts, nil holes and object identities.')
assert(stages[1][1] == 'assets.read' and stages[1][3] == 0.25)
local success, why = pcall(api.upload)
assert(not success and why == marker, 'Failed uploads rethrow the original error object.')
assert(stages[2][1] == 'assets.upload' and stages[2][3] == 0.5,
    'Failed resource work is measured before the caller handles it.')
local empty = measure({ read = function() end, upload = function() return nil end })
assert(pack(empty.read()).count == 0 and pack(empty.upload()).count == 1,
    'Zero results and one nil result stay distinct.')

-- An upload of 5 ms or more also gets a stage named for its texture; the total stage stays.
local named = measure({ upload = function(_, _, _, _, elapsed) MOCK.now = MOCK.now + elapsed; return returned end })
stages = {}
assert(named.upload('DDS ', 1024, 64, 'original_font.moji', 18.1) == returned)
assert(#stages == 2 and stages[1][1] == 'assets.upload' and stages[1][3] == 18.1
    and stages[2][1] == 'assets.upload.original_font.moji' and stages[2][3] == 18.1, 'A slow upload names its texture.')
stages = {}
named.upload('DDS ', 4, 4, 'window.newtex', 4.9)
named.upload('DDS ', 4, 4, nil, 9)
assert(#stages == 2 and stages[1][1] == 'assets.upload' and stages[2][1] == 'assets.upload',
    'A fast upload, or one with no name, keeps only the total stage.')
stages = {}
local slow = measure({ upload = function() MOCK.now = MOCK.now + 6; error(marker, 0) end })
success, why = pcall(slow.upload, 'DDS ', 4, 4, 'original_font.gauge')
assert(not success and why == marker and #stages == 2 and stages[2][1] == 'assets.upload.original_font.gauge',
    'A slow failed upload is named too, and its error is raised again.')
local direct = native()
local before = #stages
assert(direct.read('missing', 16) == nil)
package.loaded.d3d8 = { get_device = function() return nil end }
assert(direct.upload('DDS ', 1, 1) == nil)
assert(#stages == before + 2 and stages[before + 1][1] == 'assets.read'
    and stages[before + 2][1] == 'assets.upload', 'The real native API wraps both resource boundaries.')
assets.prepare()
before = #stages
for _ = 1, 10 do
    assets.cached_texture('original_font', 'moji')
    assets.texture('original_font', 'moji')
    assets.raw('original_font', 'moji')
    assets.generation()
end
assert(#stages == before, 'Cached texture access adds no resource timing calls.')
package.loaded['core.performance'] = {}
local unmeasured = { read = function() return 'bytes' end, upload = function() return returned end }
local original_read, original_upload = unmeasured.read, unmeasured.upload
assert(measure(unmeasured) == unmeasured and unmeasured.read == original_read
    and unmeasured.upload == original_upload, 'An unavailable optional timer leaves the original API intact.')

local order, fail_phase = {}, nil
local function phase(name, elapsed)
    return function()
        order[#order + 1] = name
        MOCK.now = MOCK.now + elapsed
        if fail_phase == name then error(marker, 0) end
    end
end
-- The load event makes the menu fonts and registers the Windows fonts. The rest are warmup steps: the stock art
-- (one fake kind here), then the bitmap face, then the frame font.
local made = {}
package.loaded['ui.client_fonts'] = {
    prepare = function()
        phase('bitmap', 1)()
        made.face = true
    end,
    available = function() return made.face == true end,
    current = function() return made.face == true end,
}
assets.warmup_steps = function()
    return { assets.step('assets.window', function() return made.window == true end,
        function() phase('stock', 4)(); made.window = true end) }
end
local imgui = require('imgui')
local registered
imgui.AddFontFromFileTTF = function(path, size) registered = { path, size }; return path end
package.loaded['ui.client_menu_fonts'] = {
    prepare = function(load)
        registered = nil
        assert(load('menu.ttf', 16) == 'menu.ttf' and registered[1] == 'menu.ttf' and registered[2] == 16,
            'The menu fonts are registered through ImGui\'s own call.')
        phase('menu', 3)()
    end,
    face = function() return nil end,
}
local original_fs = ashita.fs
ashita.fs = nil
package.loaded['core.performance'] = performance
package.loaded['ui.fonts'] = nil
stages = {}
local fonts = require('ui.fonts')
fonts.load()
for _, step in ipairs(fonts.warmup_steps()) do step.run() end
assert(table.concat(order, ',') == 'menu,stock,bitmap',
    'Load work first, then the stock art and the bitmap face.')
assert(#stages == 4 and stages[1][1] == 'fonts.menu' and stages[1][3] == 3
    and stages[2][1] == 'fonts.registration' and stages[3][1] == 'assets.window' and stages[3][3] == 4
    and stages[4][1] == 'fonts.face' and stages[4][3] == 1,
    'Every phase is measured, including an early exit.')
fonts.load()
for _, step in ipairs(fonts.warmup_steps()) do step.run() end
assert(#stages == 4 and #order == 3, 'Loading again and finished steps perform no repeated timing or work.')

-- The load part alone, then the steps in order.
package.loaded['ui.fonts'] = nil
stages, order, made = {}, {}, {}
fonts = require('ui.fonts')
fonts.load()
assert(table.concat(order, ',') == 'menu' and #stages == 2 and stages[2][1] == 'fonts.registration',
    'The load part makes the menu fonts and registers fonts, and nothing else.')
local names = {}
for _, step in ipairs(fonts.warmup_steps()) do names[#names + 1] = step.name; step.run() end
assert(table.concat(names, ',') == 'assets.window,fonts.face'
    and table.concat(order, ',') == 'menu,stock,bitmap', 'The steps run in their order.')

package.loaded['ui.fonts'] = nil
stages, order, made, fail_phase = {}, {}, {}, 'bitmap'
local failed = require('ui.fonts')
failed.load()
success, why = pcall(function() for _, step in ipairs(failed.warmup_steps()) do step.run() end end)
assert(not success and why == marker and #stages == 4 and stages[4][1] == 'fonts.face'
    and table.concat(order, ',') == 'menu,stock,bitmap', 'A failed phase is recorded and stops the steps.')

package.loaded['ui.fonts'] = nil
stages, order, made, fail_phase = {}, {}, {}, nil
ashita.fs = { exists = function() error(marker, 0) end }
success, why = pcall(require('ui.fonts').load)
assert(not success and why == marker and #stages == 2 and stages[2][1] == 'fonts.registration',
    'Registration errors retain their identity and timing.')
ashita.fs = original_fs
package.loaded['core.performance'] = {}
package.loaded['ui.fonts'] = nil
stages, order, made = {}, {}, {}
ashita.fs = nil
fonts = require('ui.fonts')
fonts.load()
for _, step in ipairs(fonts.warmup_steps()) do step.run() end
assert(#stages == 0 and #order == 3, 'The fonts load without the timing module.')
ashita.fs = original_fs
