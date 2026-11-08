-- A settings, profiles or shared layout file saved as UTF-8 with a byte order mark loads, and the next save
-- writes it back without one. A file that still can't be read is kept, and the messages name it and say it must
-- be JSON saved as UTF-8.
local store = require('core.store');
local folder = MOCK_INSTALL_PATH .. '/config/addons/vantage/Bom_1';
MOCK_MKDIR(folder);
local path = folder .. '/settings.json';
local function put(text) local file = assert(io.open(path, 'wb'), 'Fixture: the file opens.'); file:write(text); file:close(); end;
local function text() local file = assert(io.open(path, 'rb'), 'Fixture: the file opens.'); local value = file:read('*a'); file:close(); return value; end;
put('\239\187\191{"style":{"font_size":21},"list":[1,2]}');
local value, why = store.read(path);
assert(value and value.style.font_size == 21 and value.list[2] == 2, 'A file with a UTF-8 byte order mark loads: ' .. tostring(why));
local cache = {};
local first = store.read(path, cache);
assert(store.read(path, cache) == first and (cache.text or ''):sub(1, 1) == '{', 'The cache keeps the text after the mark.');
assert(store.write(path, { style = { font_size = 22 } }), 'A file with a mark can be saved over.');
assert(text():sub(1, 1) == '{' and (store.read(path) or { style = {} }).style.font_size == 22, 'The save writes it back without the mark.');
-- An empty file holds no settings, as a missing one does: it loads as none, and the next save writes over it.
put('');
value, why = store.read(path);
assert(type(value) == 'table' and next(value) == nil, 'An empty file loads as no settings: ' .. tostring(why));
assert(store.write(path, { style = { font_size = 24 } }) and (store.read(path) or { style = {} }).style.font_size == 24,
    'An empty file is saved over.');
-- UTF-16, as PowerShell 5.1's Out-File writes, still doesn't load, and is never saved over.
put('\255\254{\0}\0');
value, why = store.read(path);
assert(value == nil and why:find('config/addons/vantage/Bom_1/settings.json', 1, true) and why:find('UTF-8', 1, true)
    and why:find('kept unchanged', 1, true), 'An unreadable file is named and kept: ' .. tostring(why));
local ok, written = store.write(path, { style = { font_size = 23 } });
assert(not ok and written == why and text() == '\255\254{\0}\0', 'An unreadable file is never saved over.');

-- The app on such a file: it runs on defaults, and refusing to save over it names the file.
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
require('ui.party_hud').draw = function() return 0, {}; end;
require('ui.native_party_hud').draw = function() return 0, {}; end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, update = function() end,
    status = function() return { active = false }; end, restore = function() return true; end, suspend = function() return true; end };
local own = MOCK_INSTALL_PATH .. '/config/addons/vantage/Tester_1001';
MOCK_MKDIR(own);
local saved = assert(io.open(own .. '/settings.json', 'wb'), 'Fixture: the file opens.');
saved:write('\255\254{\0}\0'); saved:close();
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
assert(app.state.unread == app.state.path, 'Fixture: the file could not be read.');
app.state.dirty = true;
local refused, reason = app.callbacks.save();
assert(not refused and tostring(reason):find('config/addons/vantage/Tester_1001/settings.json', 1, true) and reason:find('UTF-8', 1, true),
    'Refusing to save names the file: ' .. tostring(reason));
-- Saved again as UTF-8 with a mark, it loads at the next try.
saved = assert(io.open(own .. '/settings.json', 'wb'), 'Fixture: the file opens.');
saved:write('\239\187\191{"style":{"font_size":27}}'); saved:close();
for _ = 1, 60 do MOCK.frame(.11); end;
assert(app.state.unread == nil and app.state.settings.style.font_size == 27, 'The file with a mark is loaded once it is saved.');
return true;
