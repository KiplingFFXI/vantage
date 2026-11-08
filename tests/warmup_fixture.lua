-- The warmup as the game drives it: vantage.lua through live_fixture.lua's userdata events, on the decoded client
-- (name_anchor_fixture.lua) and a small client install, with what each slow call costs added to the clock the
-- timings read. A search costs 5.5 ms for each pass over the whole client, a first match only as far as it is found;
-- a DAT read 0.6 ms; a texture upload 0.23 ms, the moji texture's too, since only its 64 cropped rows go up; a Windows
-- font 22.7 ms for the 16. Nothing else the Lua does is counted. The fixture keeps every timing recorded, what each
-- display drew and when, and any file read, upload or search made while a display draws.
local F = { PASS = 5.5, READ = 0.6, UPLOAD = 0.23, FONT = 22.7 / 16, spent = 0, finds = 0, reads = 0, uploads = 0,
    live = {}, labels = {}, stages = {}, added = {}, draws = {}, first = {}, early = {}, during = {}, presents = 0 };
function F.cost(ms) F.spent = F.spent + ms; end
function F.now() return MOCK.now * 1000 + F.spent; end
-- Every stage kept as /vg report keeps it: count, last, longest and total.
local function keep(into, stage, ms)
    local sample = into[stage];
    if not sample then sample = { count = 0, last = 0, max = 0, total = 0 }; into[stage] = sample; end
    sample.count, sample.last, sample.total, sample.max = sample.count + 1, ms, sample.total + ms, math.max(sample.max, ms);
end
package.loaded['core.performance'] = {
    origin_ms = 0,
    now = F.now,
    record = function(stage, started)
        assert(type(started) == 'number' and started <= F.now(), 'A stage ends after it starts: ' .. tostring(stage));
        keep(F.stages, stage, F.now() - started);
        return true;
    end,
    add = function(stage, ms) keep(F.added, stage, ms); return true; end,
    zone_begin = function() return true; end, zone_ready = function() return true; end,
    snapshot = function() return { unit = 'ms', overlapping = true, retained = true, stages = F.stages }; end,
};

local L = require('live_fixture');
local N = require('name_anchor_fixture');
F.L, F.N, F.W = L, N, L.W;
local image = N.image;

-- What a draw does that it should not: a read, an upload or a search, with the display drawing then.
local function during(what, detail) if F.drawing then F.during[#F.during + 1] = what .. ' ' .. tostring(detail) .. ' in ' .. F.drawing; end end

-- Searches, charged by how much of the client they scan: to the match, or all of it without one.
local scan = ashita.memory.find;
ashita.memory.find = function(where, size, pattern, offset, usage)
    local found = scan(where, size, pattern, offset, usage);
    local start, length = image.base, #image.data;
    if type(where) == 'number' and where ~= 0 then start, length = where, size; end
    local scanned = found ~= 0 and found - (offset or 0) - start or length;
    F.finds = F.finds + 1;
    F.cost(F.PASS * scanned / #image.data);
    during('search', pattern);
    return found;
end;
local ffi = package.loaded.ffi;
ffi.typeof = function(name) if not ffi.declared then error('not declared'); end; return name; end;
ffi.cdef = function(source) ffi.declared = source; end;
ffi.cast = function() return function() return 1000; end; end;
package.preload['core.chat'], package.loaded['core.chat'] = nil, nil;
local patterns = require('core.patterns');
patterns._set_store(MOCK.pattern_store());
patterns._set_pages(N.valid);
require('core.chat')._set_backend({
    range = function() return image.base, #image.data; end,
    find = function(pattern, usage) return ashita.memory.find('FFXiMain.dll', 0, pattern, 0, usage); end,
    read = function(at, size) return image:bytes(at, size); end,
});
require('core.native_party_ui')._set_platform({
    valid = N.valid,
    find = function(pattern, usage) return ashita.memory.find(':ffximain', 0, pattern, 0, usage); end,
    read32 = ashita.memory.read_uint32, read8 = ashita.memory.read_uint8,
});

-- The install: the font file, the eight window frames, the status icons and the two action files.
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
    .. texture('menu    gauge   ', 4, 4) .. texture('menu    colorbal', 4, 4) .. texture('anc     anc     ', 4, 4)
    .. chunk(0x31, glyphs)
local function record(pixels)
    local data = string.rep('\0', 0x280) .. u32(57 + #pixels) .. '\145' .. string.rep(' ', 16)
        .. u32(40) .. u32(32) .. u32(32) .. u16(1) .. u16(32) .. string.rep('\0', 24) .. pixels
    return data .. string.rep('\0', 0x1800 - #data)
end
local icon = record(string.rep('\0\0\255\128', 32 * 32))
local base, tier = 'white   cure    ', 'misc    numsx   '
local function part(name)
    local values = { 0, 0, 16, 0, 0, 16, 16, 16, 32, 32, 0, 0 }
    local out = {}
    for _, value in ipairs(values) do out[#out + 1] = u16(value) end
    return table.concat(out) .. '\0' .. string.rep(string.char(127, 64, 32, 127), 4) .. '\1\0\1\1' .. name
end
local function layout(name, count)
    local out = { name, '\2', base, tier, u16(count) }
    for _ = 1, count do out[#out + 1] = '\1' .. part(base) end
    return table.concat(out)
end
local stock_root, view_root = 'C:/Fixture', 'C:/FixtureView'
F.stock_root, F.view_root = stock_root, view_root
local view_font = view_root .. '/ROM/119/51.DAT'
F.files = {
    [stock_root .. '/ROM/119/51.DAT'] = font_dat .. texture('menu    menu2fon', 128, 128) .. texture('menu    keytop  ', 4, 4),
    [view_font] = font_dat,
    [stock_root .. '/ROM/119/57.DAT'] = string.rep(icon, 8),
    [view_root .. '/ROM/119/57.DAT'] = string.rep(icon, 8),
    [stock_root .. '/ROM/280/15.DAT'] = texture(base, 32, 32) .. texture(tier, 32, 32) .. chunk(0x31, layout('menu    magiconw', 4)),
    [stock_root .. '/ROM/324/95.DAT'] = texture(base, 32, 32) .. chunk(0x31, layout('menu    magico2w', 2)),
}
-- Each frame's pieces at the sizes the client draws them at.
for window = 14, 21 do
    F.files[stock_root .. ('/ROM/0/%d.DAT'):format(window)] = texture('menu    newtex  ', 128, 128) .. texture('menu    hfr1    ', 32, 32)
        .. texture('menu    corner  ', 32, 32) .. texture('menu    vfr1    ', 32, 32)
end
F.next_id = 900;
require('ui.client_assets')._set_platform_for_tests({
    game_root = function() return stock_root end,
    ashita_root = function() return 'C:/FixtureAshita' end,
    xiview_path = function() return view_font end,
    read = function(filename)
        local data = F.files[filename]
        if data then F.reads = F.reads + 1; F.cost(F.READ) end
        during('read', filename)
        return data, 'No fixture asset.'
    end,
    upload = function(_, _, _, label)
        F.uploads, F.next_id = F.uploads + 1, F.next_id + 1
        F.cost(F.UPLOAD)
        during('upload', label)
        local id = F.next_id
        F.live[id], F.labels[#F.labels + 1] = label or 'texture', label
        return { id = id, release = function() F.live[id] = nil end }
    end,
})
local function loader(id) return 7000 + id, function() end end
require('ui.item_icons')._set_loader_for_tests(loader)
-- The Windows fonts are there, and each costs its share.
local exists = ashita.fs.exists;
ashita.fs.exists = function(path)
    if type(path) == 'string' and path:find('\\Fonts\\', 1, true) then return true; end
    return exists(path);
end;
rawset(require('imgui'), 'AddFontFromFileTTF', function(path) F.cost(F.FONT); return path; end);

-- How many textures are up now.
function F.up()
    local count = 0;
    for _ in pairs(F.live) do count = count + 1; end
    return count;
end

-- A display's draw, watched: when it first drew, whether the warmup let it, and what it did while drawing.
-- check(name) runs before its first draw.
function F.watch(module, name, label, check)
    local owner = require(module);
    local original = owner[name];
    owner[name] = function(...)
        F.draws[label] = (F.draws[label] or 0) + 1;
        if F.app and F.app.state.ready == false then F.early[#F.early + 1] = label; end
        if not F.first[label] then
            F.first[label] = F.presents;
            if check then check(label); end
        end
        local outer = F.drawing;
        F.drawing = label;
        local results = { pcall(original, ...) };
        F.drawing = outer;
        if not results[1] then error(results[2], 0); end
        return unpack(results, 2);
    end;
end

-- Settings saved for Tester (1001) before the load: look is applied, and edit(settings) changes the rest.
function F.save(look, edit)
    local store, defaults, appearance = require('core.store'), require('ui.defaults'), require('ui.appearance');
    local settings = defaults.make();
    assert(appearance.apply(settings, look, { matching = true }), 'Fixture: the look ' .. look);
    if edit then edit(settings); end
    assert(store.write(MOCK_INSTALL_PATH .. '/config/addons/vantage/Tester_1001/settings.json', settings));
end

-- vantage.lua loaded, and its load event, with what it cost.
function F.load()
    F.app = dofile(ADDON_DIR .. '/vantage.lua');
    L.app = F.app;
    local before = F.spent;
    MOCK.events.load.vantage_load();
    F.load_ms = F.spent - before;
    return F.app;
end

-- One Present 1/60 s after the last: its cost, and the steps it ran.
function F.present()
    local before, steps = F.spent, #require('core.warmup').report().steps;
    F.presents = F.presents + 1;
    L.frame(1 / 60);
    local ran = {};
    local report = require('core.warmup').report();
    for index = steps + 1, #report.steps do ran[#ran + 1] = report.steps[index]; end
    return F.spent - before, ran;
end

-- The names of steps, in order.
function F.names(steps)
    local out = {};
    for index, step in ipairs(steps) do out[index] = step.name; end
    return out;
end

return F;
