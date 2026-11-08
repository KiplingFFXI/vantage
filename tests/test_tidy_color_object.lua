-- A color or the party groups given as a JSON object (a hand edit, or /vg set with a JSON object) load as plain
-- lists with the values the object gave, so saving never meets both numeric and string keys and keeps working
-- after the next load.
local store, defaults = require('core.store'), require('ui.defaults');
local s = defaults.make();
s.style.text_color = { ['1'] = 0.25, ['2'] = 0.5, ['3'] = 0.75, ['4'] = 1, r = 1 };
local groups = s.party_ui.groups;
s.party_ui.groups = { ['1'] = groups[1], ['2'] = groups[2], ['3'] = groups[3] };
groups[2].detached_x, groups[2].native_side = 777, 'left';
local function plain(color)
    local count = 0;
    for key in pairs(color) do if type(key) ~= 'number' then return false; end; count = count + 1; end;
    return count == 4;
end;
local tidy = defaults.tidy(store.copy(s));
assert(plain(tidy.style.text_color) and tidy.style.text_color[1] == 0.25 and tidy.style.text_color[3] == 0.75,
    'A timer color object loads as a list with its values.');
local count = 0;
for key in pairs(tidy.party_ui.groups) do assert(type(key) == 'number', 'The party groups load as a list.'); count = count + 1; end;
assert(count == 3 and tidy.party_ui.groups[2].detached_x == 777 and tidy.party_ui.groups[2].native_side == 'left',
    'The party groups keep what the object held.');
assert(pcall(store.encode, tidy), 'Settings tidied from objects can be saved.');
-- Saved and loaded again, they stay the same and can be saved again.
local saved, encoded = pcall(store.encode, tidy);
local again = defaults.tidy(saved and require('json').decode(encoded) or {});
assert(saved and pcall(store.encode, again) and store.equal(again.style.text_color, tidy.style.text_color)
    and again.party_ui.groups[2].detached_x == 777, 'A reload keeps them and saves.');

-- Through /vg set, then a reload: later changes still reach the saved file.
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
require('ui.native_party_hud').draw = function() return 0, {}; end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, status = function() return { active = false }; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
local function command(text) local event = { command = text }; MOCK.fire('command', event); end;
MOCK.fire('load'); app.refresh(0);
app.state.dirty = true; assert(app.callbacks.save(), 'Fixture: the settings are on disk.');
command('/vg set style.text_color {"r":1}');
command('/vg set party_ui.groups {"1":{"native_x":10},"2":{"native_x":20},"3":{"native_x":30}}');
snapshot.id, snapshot.name = 2002, 'Other'; app.refresh(1);
snapshot.id, snapshot.name = 1001, 'Tester'; app.refresh(2);
command('/vg set style.font_size 21');
for _ = 1, 20 do MOCK.frame(.11); end;
local disk = assert(store.read(app.state.path), 'Fixture: the file reads.');
assert(disk.style.font_size == 21 and not app.state.dirty, 'A change after the reload reaches the saved file.');
assert(disk.party_ui.groups[2].native_x == 20, 'The groups set as an object are kept.');
return true;
