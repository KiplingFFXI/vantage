-- /vg report's art and fonts section (fonts.report), from the real modules: plain values that encode, with the chosen
-- font and why it isn't drawn as chosen, each menu font, the custom font files left out, the atlas counts, the client
-- art and why the last action icon wasn't drawn. Making it reads and uploads nothing, and the shipped addon has the
-- action icons' reason too.
local reads, uploads = 0, 0
local assets = require('ui.client_assets')
assets._set_platform_for_tests({
    game_root = function() return 'C:/Game' end,
    ashita_root = function() return 'C:/Ashita' end,
    read = function() reads = reads + 1; return nil, 'No fixture asset.' end,
    upload = function() uploads = uploads + 1; return nil end,
})
-- No Windows or custom font files here.
ashita.fs.exists = function() return false end
local fonts, actions = require('ui.fonts'), require('ui.action_icons')
fonts.load()
for _, step in ipairs(fonts.warmup_steps()) do pcall(step.run) end
require('ui.icons').prepare()
require('ui.recast_icons').prepare()
local list = { AddImage = function() end, AddRectFilled = function() end }
assert(not actions.draw(list, 'Original FFXI', 1, 0, 0, 0, 32, 1) and type(actions.reason()) == 'string',
    'Fixture: an action icon that can\'t be drawn.')

local function plain(value)
    if type(value) ~= 'table' then return type(value) == 'string' or type(value) == 'number' or type(value) == 'boolean' end
    for key, child in pairs(value) do if not plain(key) or not plain(child) then return false end end
    return true
end
local function strings(value, out)
    out = out or {}
    if type(value) == 'string' then out[#out + 1] = value
    elseif type(value) == 'table' then for key, child in pairs(value) do strings(key, out); strings(child, out) end end
    return out
end

local read_before, sent_before = reads, uploads
local report = fonts.report('Original FFXI')
assert(plain(report) and pcall(require('core.store').encode, report), 'The section is plain values that encode.')
assert(reads == read_before and uploads == sent_before, 'Making it reads and uploads nothing.')
assert(report.font == 'Original FFXI' and type(report.reason) == 'string' and report.reason == fonts.reason('Original FFXI'),
    'It names the chosen font and why it isn\'t drawn as chosen.')
assert(report.menu['Original FFXI'].loaded == false and type(report.menu['Original FFXI'].reason) == 'string'
    and report.menu['XI View'].loaded == false and type(report.menu['XI View'].reason) == 'string',
    'Each menu font says whether ImGui took it, and why not.')
assert(report.client.window == 'window' and report.client.kinds.window.available == false
    and report.client.kinds.window.reason == 'No fixture asset.' and report.client.kinds.original_font.reason == 'No fixture asset.'
    and report.client.kinds.xiview_font.reason == 'Not needed yet.',
    'The client art says what each kind loaded from, or why it didn\'t.')
assert(report.action_icon == actions.reason(), 'It has why the last action icon wasn\'t drawn.')
assert(type(report.skipped) == 'table' and #report.skipped == 0 and report.atlas.kept == 0 and report.atlas.added == 0,
    'With no font files, nothing is left out, used again or added.')
for _, text in ipairs(strings(report)) do
    assert(not text:find('?', 1, true) and not text:lower():find('unknown', 1, true), 'The section never guesses: ' .. text)
end
assert(fonts.report('Agave').reason == nil and fonts.report().font == nil, 'A font drawn as chosen has no reason.')

-- The shipped addon has the action icons' reason, not only the fixtures.
VANTAGE_TEST_MODE = false
local ok, shipped = pcall(function() return assert(loadfile(ADDON_DIR .. '/ui/action_icons.lua'))() end)
VANTAGE_TEST_MODE = true
assert(ok and type(shipped.reason) == 'function', 'The shipped action icons give their last reason.')

-- The whole report goes through without_folders: a path under the game's, Ashita's or your user folder starts from its
-- mark, matched with either slash in any case and in keys too. A folder only matches whole, other text is kept, and
-- the tables given are left as they are.
local getenv = os.getenv
os.getenv = function(name) if name == 'USERPROFILE' then return 'D:\\Profiles\\Someone' end return getenv(name) end
local given = { 'C:\\GAME\\ROM\\1\\2.dat', ['c:/ashita/addons/x'] = 'C:/Games/other', 3,
    nested = { 'Error at C:/Ashita/addons/vantage/vantage.lua:12: no', 'C:/Gamer/x', 'd:/profiles/someone/Documents/a' } }
local marked = assets.without_folders(given)
assert(marked[1] == '<game>\\ROM\\1\\2.dat' and marked['<Ashita>/addons/x'] == 'C:/Games/other' and marked[2] == 3,
    'A path starts from its folder\'s mark, in keys too.')
assert(marked.nested[1] == 'Error at <Ashita>/addons/vantage/vantage.lua:12: no' and marked.nested[2] == 'C:/Gamer/x'
    and marked.nested[3] == '<user folder>/Documents/a', 'A folder matches whole, inside other text.')
assert(given[1] == 'C:\\GAME\\ROM\\1\\2.dat' and given['c:/ashita/addons/x'] and given.nested[3]:find('someone', 1, true),
    'The tables given are left as they are.')
-- A game inside Ashita's folder is named from the game's, and a folder too short to be a path is never matched.
assets._set_platform_for_tests({ game_root = function() return 'C:/Play/Game/' end, ashita_root = function() return '.' end })
marked = assets.without_folders({ 'C:/Play/Game/ROM/1.dat', 'a.b ./x' })
assert(marked[1] == '<game>/ROM/1.dat' and marked[2] == 'a.b ./x', 'The longest folder is matched first.')
assets._set_platform_for_tests({ game_root = function() return 'C:/Play/Game' end, ashita_root = function() return 'C:/Play' end })
marked = assets.without_folders({ 'C:/Play/Game/ROM/1.dat', 'C:/Play/addons' })
assert(marked[1] == '<game>/ROM/1.dat' and marked[2] == '<Ashita>/addons', 'A game inside Ashita\'s folder starts from the game\'s.')
-- LuaJIT shortens a long file name in an error to ... and its last 56 characters, which can start inside a folder.
-- That tail starts from the mark too, in a traceback line as well, and other dots are kept.
local ashita = 'C:\\Players\\Bob\\Documents\\PhoenixXI\\Ashita'
assets._set_platform_for_tests({ game_root = function() return 'C:/Play/Game' end, ashita_root = function() return ashita end })
local chunk = assert(loadstring('local t; return t.x', '@' .. ashita .. '\\addons\\vantage\\ui\\hud.lua'))
local _, why = pcall(chunk)
assert(why:sub(1, 3) == '...' and why:find('Bob', 1, true), 'Fixture: the error shortens the name inside the folders: ' .. why)
marked = assets.without_folders({ why, 'stack traceback:\n\t' .. why, 'Loading... done', '(...ashita/addons/a.lua)' })
assert(marked[1]:find('^<Ashita>\\addons\\vantage\\ui\\hud%.lua:1:') and not marked[1]:find('Bob', 1, true)
    and marked[2]:find('\n\t<Ashita>\\addons', 1, true) and not marked[2]:find('Bob', 1, true),
    'A shortened file name starts from its folder\'s mark: ' .. marked[1])
assert(marked[3] == 'Loading... done' and marked[4] == '(<Ashita>/addons/a.lua)', 'Other dots are kept: ' .. marked[3])
os.getenv = getenv
assets.clear()
return 'The art and fonts section of /vg report'
