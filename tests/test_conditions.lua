-- Show conditions (core/conditions.lua): each display shows only where its conditions hold: main and sub job, a level
-- range, Level Sync, the kinds of zone, solo or party or alliance, engaged and a pet out. Every condition set must hold;
-- one with several picks holds for any of them; a display with none always shows. The zone kinds follow Phoenix's zone
-- data, with the Battlefield status for battlefields and the zone-in packet for a Mog House. They hide only the display:
-- samples and edit mode show it anyway. They read as plain words.
local conditions, zones, elements, defaults = require('core.conditions'), require('data.zones'), require('ui.elements'), require('ui.defaults');
local store = require('core.store');

-- Zone kinds from Phoenix's zone data (data/zones/*/zone.yaml at 730ac619c0), with the corrections to the research.
local kind = conditions.kind_of;
for _, id in ipairs({ 172, 173, 174, 176, 177, 178, 9, 140, 190, 198, 213 }) do assert(kind[id] == 'dungeon', 'Zone ' .. id .. ' is a dungeon.'); end;
assert(kind[175] == nil, 'The Eldieme Necropolis [S] (175) is later content, not an era dungeon.');
assert(kind[220] == nil and kind[221] == nil, 'The ferries to Selbina and Mhaura have no type, so they read as other zones.');
for id = 223, 228 do assert(kind[id] == 'field', 'Airships and pirate ferries (' .. id .. ') are outdoors.'); end;
for _, id in ipairs({ 26, 32, 48, 50, 70, 71, 230, 245, 252 }) do assert(kind[id] == 'town', 'Zone ' .. id .. ' is a town.'); end;
assert(kind[53] == 'field', 'Nashmau is typed outdoors.');
for _, id in ipairs({ 39, 40, 41, 42, 134, 135, 185, 186, 187, 188 }) do assert(kind[id] == 'dynamis', 'Zone ' .. id .. ' is Dynamis.'); end;
assert(kind[37] == 'limbus' and kind[38] == 'limbus', 'Temenos and Apollyon are Limbus.');
for _, id in ipairs({ 55, 56, 63, 66, 69 }) do assert(kind[id] == 'assault', 'Zone ' .. id .. ' is Assault.'); end;
for id = 73, 76 do assert(kind[id] == 'salvage', 'Zone ' .. id .. ' is Salvage.'); end;
assert(kind[77] == 'nyzul' and kind[60] == 'ashu_talif', 'Nyzul Isle and The Ashu Talif have kinds of their own.');
for _, id in ipairs({ 139, 144, 146, 165, 168, 201, 78, 0, 256, 80 }) do assert(kind[id] == nil, 'Zone ' .. id .. ' has no era kind.'); end;
local counted = 0;
for _, list in pairs(zones) do counted = counted + #list; end;
assert(counted == #zones.town + #zones.field + #zones.dungeon + 10 + 2 + 5 + 4 + 1 + 1, 'Fixture: every list counted.');
local seen = {};
for name, list in pairs(zones) do for _, id in ipairs(list) do assert(not seen[id], 'Zone ' .. id .. ' has one kind only.'); seen[id] = name; end; end;

-- Tidy.
local fresh = conditions.make();
assert(not conditions.any(fresh) and conditions.describe(fresh)[1] == 'always shows.', 'With none set it always shows.');
local tidied = conditions.tidy({ main_jobs = { 3, '5', 40 }, sub_jobs = { ['13'] = true, nope = true }, level_min = 80, level_max = 30,
    level_sync = 'maybe', zones = { 'town', 'moon', field = true }, group = { 'solo', alliance = 'yes' }, engaged = 'yes', pet = 7 });
assert(tidied.main_jobs[3] and not tidied.main_jobs[5] and not tidied.main_jobs[40], 'Job lists keep known job ids.');
assert(tidied.sub_jobs[13] and next(tidied.sub_jobs, next(tidied.sub_jobs)) == nil, 'Job maps keep their ids.');
assert(tidied.level_min == 30 and tidied.level_max == 80, 'A level range given the wrong way round is turned round.');
assert(tidied.level_sync == 'any' and tidied.pet == 'any' and tidied.engaged == 'yes', 'Unknown choices are Either way.');
assert(tidied.zones.town and tidied.zones.field and not tidied.zones.moon and tidied.group.solo and not tidied.group.alliance,
    'Zone and party picks keep only known names.');

-- Where you are, from a snapshot and the client, and whether conditions hold there.
MOCK.player.sub_job = 13;
local pet_index;
local entity = { GetPetTargetIndex = function() return pet_index or 0; end, GetServerId = function(_, index) return index == 0x700 and 0x1000700 or 0; end,
    GetStatus = function() return 0; end };
local manager = AshitaCore.GetMemoryManager;
local memory = manager();
memory.GetEntity = function() return entity; end;
AshitaCore.GetMemoryManager = function() return memory; end;
local function snap(fields)
    local out = { valid = true, id = 1001, zone = 102, job = 3, level = 75, self_effects = {}, party = {}, combat = false,
        entities = { [1001] = { id = 1001, index = 0x400 } } };
    for key, value in pairs(fields or {}) do out[key] = value; end;
    return out;
end;
local function holds(value, fields) conditions.read(snap(fields)); return conditions.holds(conditions.tidy(value)); end;
assert(holds({}) and holds({ main_jobs = { 3 } }) and not holds({ main_jobs = { 4 } }), 'Main job.');
assert(holds({ main_jobs = { 4, 3 } }), 'Any of the picked jobs.');
assert(holds({ sub_jobs = { 13 } }) and not holds({ sub_jobs = { 5 } }), 'Sub job, from the client.');
assert(holds({ level_min = 70, level_max = 75 }) and not holds({ level_min = 76 }) and not holds({ level_max = 60 }), 'Level range.');
assert(holds({ level_min = 30, level_max = 40 }, { level = 35 }), 'The level the game shows, lowered under Level Sync.');
assert(holds({ level_sync = 'yes' }, { self_effects = { { effect = 269 } } }) and not holds({ level_sync = 'yes' }), 'Level Sync on.');
assert(holds({ level_sync = 'no' }) and not holds({ level_sync = 'no' }, { self_effects = { { effect = 269 } } }), 'Level Sync off.');
assert(holds({ zones = { 'field' } }) and not holds({ zones = { 'town' } }), 'La Theine Plateau (102) is a field.');
assert(holds({ zones = { 'town', 'dungeon' } }, { zone = 245 }) and holds({ zones = { 'dungeon' } }, { zone = 172 }), 'Any of the picked zones.');
assert(holds({ zones = { 'other' } }, { zone = 220 }) and not holds({ zones = { 'field' } }, { zone = 220 }), 'A ferry ride is another zone.');
assert(holds({ zones = { 'battlefield' } }, { zone = 140, self_effects = { { effect = 254 } } }), 'The Battlefield status is a battlefield.');
assert(holds({ zones = { 'dungeon' } }, { zone = 140, self_effects = { { effect = 254 } } }), 'and Ghelsba Outpost stays a dungeon.');
assert(not holds({ zones = { 'battlefield' } }, { zone = 140 }), 'Without the status there is no battlefield.');
assert(holds({ zones = { 'limbus' } }, { zone = 37 }) and holds({ zones = { 'dynamis' } }, { zone = 186 }) and holds({ zones = { 'assault' } }, { zone = 69 }),
    'Limbus, Dynamis and Assault.');
-- A zone-in packet with login state 1 (0x80) brings you into a Mog House, until the next zone-in.
local function zone_in(state)
    local bytes = MOCK.bytes(0x100);
    MOCK.put(bytes, 0x80, 4, state);
    conditions.packet(MOCK.packet(0x00A, bytes));
end;
zone_in(1);
assert(holds({ zones = { 'mog_house' } }, { zone = 245 }) and not holds({ zones = { 'town' } }, { zone = 245 }), 'A Mog House is not the town around it.');
zone_in(2);
assert(holds({ zones = { 'town' } }, { zone = 245 }) and not holds({ zones = { 'mog_house' } }, { zone = 245 }), 'Leaving it, the town is a town again.');
local short = MOCK.bytes(0x40); MOCK.put(short, 0x30, 4, 1);
conditions.packet(MOCK.packet(0x00A, short));
assert(holds({ zones = { 'town' } }, { zone = 245 }), 'A packet too short to hold the login state changes nothing.');
assert(holds({ group = { 'solo' } }) and not holds({ group = { 'party' } }), 'Solo.');
local party = { { id = 1002, scope = 'party' } };
assert(holds({ group = { 'party' } }, { party = party }) and not holds({ group = { 'solo', 'alliance' } }, { party = party }), 'In a party.');
assert(holds({ group = { 'alliance' } }, { party = { { id = 1002, scope = 'party' }, { id = 1008, scope = 'alliance' } } }), 'In an alliance.');
assert(holds({ engaged = 'yes' }, { combat = true }) and not holds({ engaged = 'yes' }) and holds({ engaged = 'no' }), 'Engaged.');
assert(not holds({ pet = 'yes' }) and holds({ pet = 'no' }), 'No pet out.');
assert(holds({ pet = 'yes' }, { pet = { index = 0x700 } }) and not holds({ pet = 'no' }, { pet = { index = 0x700 } }), 'A pet out.');
assert(holds({ pet = 'yes' }, { pet = { index = 0x700, away = true } }), 'One out of view is still out.');
assert(holds({ main_jobs = { 3 }, level_min = 70, zones = { 'field' }, engaged = 'no' }) and not holds({ main_jobs = { 3 }, engaged = 'yes' }),
    'Every condition set must hold.');
-- While zoning the snapshot lists no one: the last place stays.
conditions.read(snap({ zone = 245 }));
conditions.read({ valid = false });
assert(conditions.place.kind == 'town' and conditions.place.valid, 'A snapshot of no one keeps the last place.');

-- Plain words.
local words = table.concat(conditions.describe(conditions.tidy({ main_jobs = { 3, 5 }, sub_jobs = { 13 }, level_min = 60, level_max = 75,
    level_sync = 'no', zones = { 'town', 'dungeon' }, group = { 'party', 'alliance' }, engaged = 'yes', pet = 'yes' })), ' ');
assert(words == 'Main job WHM or RDM. Support job NIN. Level 60 to 75. While not Level Synced. In Towns or Dungeons. While in a party or in an alliance. While engaged. With a pet out.',
    'Plain words: ' .. words);
assert(not words:find('?', 1, true) and not words:lower():find('unknown'), 'No question marks or unknown.');
conditions.read(snap());
assert(conditions.where():find('WHM 75 / NIN', 1, true) and not conditions.where():find('?', 1, true), 'Where you are: ' .. conditions.where());

-- The party cooldown list, the pet display, the ready pulse and the alert notices their conditions hide aren't drawn,
-- with something to show in each; samples and edit mode show them anyway.
local hud = require('ui.hud');
local gate = defaults.tidy(defaults.make());
for _, panel in pairs(gate.panels) do panel.enabled = false; end;
gate.party_cooldowns.enabled, gate.party_cooldowns.list.enabled, gate.pet.enabled = true, true, true;
gate.ready_pulse.enabled, gate.ready_pulse.spot, gate.alerts.enabled, gate.alerts.muted = true, 'screen', true, false;
local pulses = require('core.ready_pulse').new();
pulses:test(gate, 500).test = false;
local live = { valid = true, rows = {}, context = { valid = true, id = 1001 }, cooldowns = store.copy(require('core.party_cooldowns').samples(500)),
    pet = store.copy(require('core.pet').samples(500)), pulses = pulses.active, notices = { { visual = true, test = true, ends = 510, message = 'Haste wore off' } } };
local gated = { cooldown_list = '##vantage_cooldowns', pet = '##vantage_pet', pulse = '##vantage_pulse', notices = '##vantage_notices' };
local function drawn_windows(callbacks)
    elements.frame();
    MOCK.imgui_calls = {};
    hud.draw(live, gate, 500.2, callbacks or {});
    local seen = {};
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Begin' then seen[call[2]] = true; end; end;
    return seen;
end;
conditions.update(gate, snap());
local open = drawn_windows();
for id, window in pairs(gated) do assert(open[window], 'Fixture: with no conditions it is drawn: ' .. id); end;
local engaged = conditions.tidy({ engaged = 'yes' });
gate.party_cooldowns.list.conditions, gate.pet.conditions = store.copy(engaged), store.copy(engaged);
gate.ready_pulse.conditions, gate.alerts.notice_conditions = store.copy(engaged), store.copy(engaged);
conditions.update(gate, snap());
open = drawn_windows();
for id, window in pairs(gated) do
    assert(not conditions.shown(id) and not open[window], 'Its conditions hide it: ' .. id);
end;
open = drawn_windows({ editing = true });
for id, window in pairs(gated) do assert(open[window], 'Edit mode shows it so it can be placed: ' .. id); end;
gate.party_cooldowns.preview, gate.pet.preview, gate.preview = true, true, true;
open = drawn_windows();
for _, id in ipairs({ 'cooldown_list', 'pet', 'notices' }) do assert(open[gated[id]], 'Samples show it anyway: ' .. id); end;
gate.party_cooldowns.preview, gate.pet.preview, gate.preview = false, false, false;
conditions.update(gate, snap({ combat = true }));
open = drawn_windows();
for id, window in pairs(gated) do assert(open[window], 'Where its conditions hold it is drawn: ' .. id); end;

-- Through the app: a display whose conditions fail isn't drawn, unless samples or edit mode show it.
local snapshot = snap({ name = 'Tester', self_known = true });
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
local overhead_hidden, overhead_conditions;
local real_overhead = require('core.overhead');
local stub = setmetatable({ update = function(_, _, _, _, hidden, conditioned)
    overhead_hidden, overhead_conditions = hidden, conditioned;
    return nil;
end }, { __index = real_overhead });
package.loaded['core.overhead'] = stub;
local strips = 0;
local native = require('ui.native_party_hud');
local real_draw = native.draw;
native.draw = function(...) strips = strips + 1; return real_draw(...); end;
local imgui = require('imgui');
rawset(imgui, 'GetBackgroundDrawList', function() return imgui.GetWindowDrawList(); end);
rawset(imgui, 'GetForegroundDrawList', function() return imgui.GetWindowDrawList(); end);
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(1);
local s = app.state.settings;
s.rolls.enabled, s.party_ui.enabled = true, true;
s.panels.self_buffs.empty, s.panels.self_debuffs.empty = 'show', 'show';
-- Your own roll, in its Double-Up window.
app.rolls:observe({ kind = 'roll', entity_id = 1001, ability = 105, total = 4, targets = { 1001 }, results = { 'got' } }, MOCK.now);
s.rolls.conditions = conditions.tidy({ main_jobs = { 17 } });
s.party_ui.conditions = conditions.tidy({ group = { 'alliance' } });
s.overhead.enabled, s.overhead.conditions = true, conditions.tidy({ engaged = 'yes' });
s.panels.self_buffs.conditions = conditions.tidy({ zones = { 'town' } });
s.alerts.notice_conditions = conditions.tidy({ pet = 'yes' });
app.refresh(2);
for _, id in ipairs({ 'rolls', 'party_ui', 'overhead', 'self_buffs', 'notices' }) do assert(not conditions.shown(id), id .. ' is hidden here.'); end;
assert(conditions.shown('self_debuffs') and conditions.shown('pet'), 'Displays with no conditions show.');
local function windows()
    MOCK.imgui_calls = {};
    strips = 0;
    MOCK.frame(0.2);
    local seen = {};
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Begin' then seen[call[2]] = true; end; end;
    return seen;
end;
s.rolls.preview, s.preview = false, true;
local open = windows();
assert(not open['##vantage_rolls'], 'The Phantom Roll display its conditions hide isn\'t drawn.');
assert(open['##vantage_self_buffs'], 'Samples show a panel its conditions hide.');
s.preview = false;
open = windows();
assert(not open['##vantage_self_buffs'] and open['##vantage_self_debuffs'], 'The panel its conditions hide isn\'t drawn; the others are.');
assert(strips == 0 and overhead_conditions == true and not overhead_hidden, 'The strips and overhead icons their conditions hide aren\'t drawn.');
s.rolls.preview = true;
assert(windows()['##vantage_rolls'], 'Samples show the Phantom Roll display anyway.');
s.rolls.preview = false;
app.callbacks.edit_mode(true);
open = windows();
assert(open['##vantage_rolls'] and open['##vantage_self_buffs'], 'Edit mode shows them so they can be placed.');
app.callbacks.edit_mode(false);
-- Change where you are and they show.
snapshot.job, snapshot.party, snapshot.combat, snapshot.zone = 17, { { id = 1002, scope = 'party' }, { id = 1008, scope = 'alliance' } }, true, 245;
snapshot.pet = { index = 0x700 };
app.refresh(3);
for _, id in ipairs({ 'rolls', 'party_ui', 'overhead', 'self_buffs', 'notices' }) do assert(conditions.shown(id), id .. ' shows there.'); end;
-- The zone change ended the roll; a new one in the new zone.
app.rolls:observe({ kind = 'roll', entity_id = 1001, ability = 105, total = 4, targets = { 1001 }, results = { 'got' } }, MOCK.now);
app.refresh(4);
open = windows();
assert(open['##vantage_self_buffs'] and open['##vantage_rolls'] and overhead_hidden == false and overhead_conditions == false
    and strips > 0, 'They draw again.');
AshitaCore.GetMemoryManager = manager;
rawset(imgui, 'GetBackgroundDrawList', nil); rawset(imgui, 'GetForegroundDrawList', nil);
MOCK.fire('unload');
return true;
