-- settings.overhead: off by default, with every key of docs/OVERHEAD.md and its default; tidy clamps every value and
-- keeps keys it doesn't know; a save without overhead loads with the defaults and saves back with its other keys as
-- they were. Nothing in it is dragged, so it has no locks.
local defaults, store = require('ui.defaults'), require('core.store');
local overhead = require('ui.overhead_defaults');
local fresh = defaults.make().overhead;
assert(fresh.enabled == false, 'Overhead icons start off.');
assert(fresh.locked == nil, 'No lock: nothing is dragged.');
-- Who: on by default except other players, their pets and you.
for id, on in pairs({ target = true, subtarget = true, claimed = true, watched = true, debuffed = true, party = true, pet = true,
    alliance = true, other = false, other_pet = false, self = false }) do
    assert(fresh.units[id] == on, id .. ' starts ' .. tostring(on));
end
-- Each type: a single bar, the doc's limits for each layout, no offsets, countdowns on; the crowd control slot for mobs.
-- The name's middle sits half a yalm over a player's head and on a mob's or pet's.
local limits = { mob = { 8, 8, 4, 4, 6 }, party = { 8, 6, 8, 6, 6 }, self = { 8, 6, 8, 6, 6 }, alliance = { 6, 6, 4, 6, 6 },
    other = { 6, 6, 4, 6, 6 }, pet = { 6, 6, 4, 4, 4 }, other_pet = { 6, 6, 4, 4, 4 } };
for id, limit in pairs(limits) do
    local t = fresh.types[id];
    assert(t.layout == 'single' and t.limit == limit[1] and t.line_debuffs == limit[2] and t.line_buffs == limit[3]
        and t.split_buffs == limit[4] and t.split_debuffs == limit[5], id .. ' limits');
    assert(t.world_offset == 0 and t.screen_x == 0 and t.screen_y == 0 and t.size_scale == 1 and t.countdown == true
        and t.swap_lines == false and t.swap_sides == false and (t.cc_slot == true) == (id == 'mob'), id .. ' look');
    assert(t.name_lift == ((id == 'mob' or id == 'pet' or id == 'other_pet') and 0 or 0.5), id .. ' name_lift');
end
assert(fresh.max_units == 10 and fresh.distance_cap == 30 and fresh.fade_start == 20 and fresh.fade_alpha == 0.5
    and fresh.hide_in_cities == true and fresh.stack == nil and fresh.stack_steps == nil);
assert(fresh.camera.capture == 'scene' and fresh.camera.scene_index == 2 and fresh.camera.hold_ms == 250 and fresh.camera.max_distance == 60,
    'The camera is read at the 2nd BeginScene at first.');
local size = fresh.size;
assert(size.base == 22 and size.ref_depth == 10 and size.alpha == 0.5 and size.ref_hitbox == 1.5 and size.beta == 0.5
    and size.s_min == 0.85 and size.s_max == 1.6 and size.min_px == 14 and size.max_px == 40 and size.target_scale == 1.2);
local head = fresh.head;
assert(next(head.heights) == nil and next(head.offsets) == nil and next(head.sizes) == nil, 'The name lists ship empty.');
assert(table.concat(head.race_heights, ',') == '1.8,1.7,2.05,1.95,1,1,1.55,2.05' and head.default_height == 1.8);
assert(head.mounted_base == 1.35 and head.mounted_factor == 0.55 and head.sit_factor == 0.6 and head.chair_factor == 0.75);
assert(head.mob_height_base == 0.6 and head.mob_height_per_hitbox == 1 and head.mob_height_min == 1.2 and head.mob_height_max == 8
    and head.default_hitbox == 1.5);
local layout = fresh.layout;
assert(layout.placement == 'above_name' and layout.name_height == 0.33 and layout.name_cap == 24 and layout.target_height == 0.4
    and layout.target_cap == 16 and layout.gap == 3 and layout.line_gap == 2 and layout.icon_gap == 0 and layout.split_gap == 6
    and layout.cc_scale == 1.4);
assert(layout.name_clearance == nil and layout.target_clearance == nil, 'There is no pixel room for the name.');
assert(fresh.timer_format == nil and fresh.countdown_bold == false and fresh.countdown_shadow == true
    and fresh.countdown_outline == false and table.concat(fresh.countdown_outline_color, ',') == '0,0,0,1' and fresh.small_icon_inside_px == 18);
assert(store.equal(defaults.tidy(defaults.make()).overhead, fresh), 'Tidy leaves the defaults as they are.');

-- Every value out of range or of the wrong kind comes back clamped or as its default.
local function tidied(change)
    local settings = defaults.make();
    change(settings.overhead);
    return defaults.tidy(settings).overhead;
end
local high = tidied(function(o)
    o.enabled, o.max_units, o.distance_cap, o.fade_start, o.fade_alpha = 'yes', 99, 80, 70, 4;
    o.camera.capture, o.camera.scene_index, o.camera.hold_ms, o.camera.max_distance = 'later', 30, 9000, 5000;
    for key in pairs(o.size) do o.size[key] = 1000; end
    for key, value in pairs(o.head) do if type(value) == 'number' then o.head[key] = 1000; end end
    for race = 1, 8 do o.head.race_heights[race] = 50; end
    for key, value in pairs(o.layout) do if type(value) == 'number' then o.layout[key] = 1000; end end
    o.layout.placement, o.small_icon_inside_px = 'sideways', 300;
    o.countdown_outline_color = { 5, -1, 'x', 2 };
    for _, t in pairs(o.types) do
        t.layout, t.limit, t.line_debuffs, t.line_buffs, t.split_buffs, t.split_debuffs = 'stack', 99, 0, 40, -3, 1.6;
        t.world_offset, t.screen_x, t.screen_y, t.size_scale, t.countdown, t.name_lift = 9, 900, -900, 7, 'on', 9;
    end
    o.units.target, o.units.other = 'no', 1;
end);
assert(high.enabled == false and high.max_units == 24 and high.distance_cap == 50 and high.fade_start == 50
    and high.fade_alpha == 1, 'The global numbers clamp.');
assert(high.camera.capture == 'scene' and high.camera.scene_index == 8 and high.camera.hold_ms == 2000 and high.camera.max_distance == 500,
    'A capture point it does not know is the default.');
assert(high.size.base == 48 and high.size.ref_depth == 30 and high.size.alpha == 1 and high.size.ref_hitbox == 5 and high.size.beta == 1
    and high.size.s_min == 1 and high.size.s_max == 2.5 and high.size.min_px == 64 and high.size.max_px == 64 and high.size.target_scale == 1.6);
assert(high.head.default_height == 4 and high.head.mounted_base == 4 and high.head.mounted_factor == 1.5 and high.head.sit_factor == 1
    and high.head.chair_factor == 1 and high.head.mob_height_base == 3 and high.head.mob_height_per_hitbox == 2.5
    and high.head.mob_height_min == 8 and high.head.mob_height_max == 12 and high.head.default_hitbox == 8);
for race = 1, 8 do assert(high.head.race_heights[race] == 4); end
assert(high.layout.placement == 'above_name' and high.layout.name_height == 1.5 and high.layout.name_cap == 80
    and high.layout.target_height == 1.5 and high.layout.target_cap == 60 and high.layout.gap == 20 and high.layout.line_gap == 16
    and high.layout.icon_gap == 16 and high.layout.split_gap == 40 and high.layout.cc_scale == 2);
assert(high.small_icon_inside_px == 64 and table.concat(high.countdown_outline_color, ',') == '1,0,0,1');
for id, t in pairs(high.types) do
    assert(t.layout == 'single' and t.limit == 32 and t.line_debuffs == 1 and t.line_buffs == 32 and t.split_buffs == 1
        and t.split_debuffs == 2 and t.world_offset == 5 and t.screen_x == 200 and t.screen_y == -200 and t.size_scale == 2
        and t.countdown == true and t.name_lift == 3, id .. ' clamps');
end
assert(high.units.target == true and high.units.other == false, 'A switch that isn\'t true or false is its default.');
local low = tidied(function(o)
    o.max_units, o.distance_cap, o.fade_alpha = 0, 1, -1;
    for key in pairs(o.size) do o.size[key] = -1000; end
    for key, value in pairs(o.head) do if type(value) == 'number' then o.head[key] = -1000; end end
    o.head.mob_height_max = 0.5;
    o.camera.hold_ms, o.camera.max_distance, o.camera.scene_index = -5, 0, 0;
    for key, value in pairs(o.layout) do if type(value) == 'number' then o.layout[key] = -1000; end end
    for _, t in pairs(o.types) do t.name_lift = -9; end
end);
assert(low.max_units == 1 and low.distance_cap == 5 and low.fade_start == 5 and low.fade_alpha == 0);
assert(low.size.base == 12 and low.size.ref_depth == 3 and low.size.alpha == 0 and low.size.min_px == 10 and low.size.max_px == 10
    and low.size.s_min == 0.5 and low.size.s_max == 1 and low.size.target_scale == 1 and low.size.ref_hitbox == 0.5 and low.size.beta == 0);
assert(low.head.mob_height_min == 0.2 and low.head.mob_height_max == 1 and low.head.mob_height_base == -1 and low.head.sit_factor == 0.2);
assert(low.camera.hold_ms == 0 and low.camera.max_distance == 10 and low.camera.scene_index == 1);
assert(low.layout.name_height == 0.05 and low.layout.name_cap == 6 and low.layout.target_height == 0 and low.layout.target_cap == 0
    and low.layout.gap == 0 and low.layout.cc_scale == 1, 'The name and cursor sizes clamp.');
for id, t in pairs(low.types) do assert(t.name_lift == -2, id .. ' name height clamps'); end
-- min_px never above max_px, mob_height_max never under mob_height_min, fade_start never past the cap.
local crossed = tidied(function(o) o.size.min_px, o.size.max_px, o.head.mob_height_min, o.head.mob_height_max, o.distance_cap, o.fade_start = 30, 20, 5, 2, 10, 25; end);
assert(crossed.size.max_px == 30 and crossed.head.mob_height_max == 5 and crossed.fade_start == 10);
-- Name lists: a name is 1 to 40 characters with no control characters, a value is a finite number, clamped.
local named = tidied(function(o)
    o.head.heights = { ['Wild Rabbit'] = 0.9, Tiamat = 40, [''] = 2, ['Bad\nName'] = 2, [('x'):rep(41)] = 2, [7] = 2, Odd = 'tall', Nan = 0 / 0 };
    o.head.offsets = { Goblin = -9, Orc = 0.25 };
    o.head.sizes = { Fafnir = 3, Crab = 0.1 };
end);
assert(store.equal(named.head.heights, { ['Wild Rabbit'] = 0.9, Tiamat = 12 }), store.encode(named.head.heights));
assert(store.equal(named.head.offsets, { Goblin = -3, Orc = 0.25 }) and store.equal(named.head.sizes, { Fafnir = 2, Crab = 0.5 }));
local many = tidied(function(o) for i = 1, 300 do o.head.heights[('Mob %03d'):format(i)] = 2; end; end);
local count = 0;
for _ in pairs(many.head.heights) do count = count + 1; end
assert(count == 256 and many.head.heights['Mob 001'] and not many.head.heights['Mob 300'], 'At most 256 names, the first by name.');
-- Race heights saved as an object come back as a list of eight; a missing one is its default.
local races = overhead.tidy({ head = { race_heights = { ['1'] = 1.9, ['8'] = 2.2 } } });
assert(table.concat(races.head.race_heights, ',') == '1.9,1.7,2.05,1.95,1,1,1.55,2.2');
-- Keys tidy doesn't know are kept, as the rest of the settings keep them.
local later = tidied(function(o) o.enabled, o.preview = true, true; o.types.mob.filter = { mine_only = true }; end);
assert(later.preview == true and later.types.mob.filter.mine_only == true);
-- The samples show only while the icons are on.
assert(tidied(function(o) o.preview = true; end).preview == false, 'Samples saved with the icons off come back off.');
-- A garbage value for the whole table is the defaults.
assert(store.equal(defaults.tidy({ overhead = 'none', panels = {} }).overhead, fresh));

-- A settings file holding these overhead settings.
local saved_files = 0;
local function path_of(overhead_settings)
    local settings = defaults.make();
    settings.overhead = overhead_settings;
    saved_files = saved_files + 1;
    local file = MOCK_INSTALL_PATH .. '/config/addons/vantage/overhead_' .. saved_files .. '.json';
    assert(store.write(file, settings));
    return file;
end
-- What each type shows at first: mobs the debuffs from you and the party and their own buffs, the alliance its
-- debuffs, you everything, the rest every debuff and the buffs you cast; other players without the long buffs.
for id, t in pairs(fresh.types) do
    assert(t.mine_only == false and t.shared_rules == true and #t.include == 0, id .. ' filters');
    assert(t.kinds == (id == 'alliance' and 'debuff' or 'all'), id .. ' kinds');
    assert(t.buffs_mine_only == (id ~= 'mob' and id ~= 'alliance' and id ~= 'self'), id .. ' buffs you cast');
    assert(t.debuffs_party_only == (id == 'mob'), id .. ' debuffs from the party');
    local long = id == 'mob' or id == 'self';
    assert(#t.exclude == 0 and t.show_protect_shell == long and t.show_food == long and t.show_signet == long, id .. ' leaves out the usual long effects');
    assert(t.show_rolls and t.show_songs and t.show_barspells and t.show_stances, id .. ' shows the other groups');
end
assert(table.concat(fresh.countdown_color, ',') == '1,1,1,1' and fresh.blink_icons == true
    and fresh.blink_seconds == 15, 'The countdowns are white, and icons blink at the end.');
assert(fresh.dispel_light == true and fresh.dispel_glow == true and table.concat(fresh.dispel_color, ',') == '1,0.82,0.25,1',
    'Dispellable buffs light up with a glow.');
-- Their values clamp too: a kind it doesn't know, lists from a set or a list with repeats and junk, at most 256 ids.
local filtered = tidied(function(o)
    local mob, party = o.types.mob, o.types.party;
    mob.kinds, mob.mine_only, mob.shared_rules = 'mobs', 'yes', 0;
    mob.include = { 41, 40, 40, 'x', 2000, -1, 3.5 };
    mob.exclude = { ['33'] = true, [13] = true, [12] = false };
    party.exclude = nil;
    party.include = {};
    for i = 1, 300 do party.include[i] = i; end
    o.countdown_color, o.dispel_color = { 2, -1, 0.5 }, 'gold';
    o.blink_icons, o.dispel_light, o.dispel_glow, o.blink_seconds = 'on', nil, 1, 999;
end);
local mob = filtered.types.mob;
assert(mob.kinds == 'all' and mob.mine_only == false and mob.shared_rules == true, 'Bad switches and kinds are their defaults.');
assert(table.concat(mob.include, ',') == '40,41' and table.concat(mob.exclude, ',') == '13,33', 'Sorted lists of ids: '
    .. table.concat(mob.include, ',') .. ' / ' .. table.concat(mob.exclude, ','));
assert(#filtered.types.party.exclude == 0, 'A missing list is empty.');
-- A list of one is kept as it is: it isn't topped up from a default list as it loads.
local one = defaults.tidy(store.read(path_of(tidied(function(o) o.types.party.exclude = { 13 }; o.types.mob.show_food = 'x'; end))));
assert(table.concat(one.overhead.types.party.exclude, ',') == '13' and one.overhead.types.mob.show_food == true,
    'Saved and loaded, a list of one stays one: ' .. table.concat(one.overhead.types.party.exclude, ','));
assert(#filtered.types.party.include == 256 and filtered.types.party.include[256] == 256, 'At most 256 ids.');
assert(table.concat(filtered.countdown_color, ',') == '1,0,0.5,1'
    and table.concat(filtered.dispel_color, ',') == '1,0.82,0.25,1', 'Colors');
assert(filtered.blink_icons == true and filtered.dispel_light == true and filtered.dispel_glow == true and filtered.blink_seconds == 300);
-- They save as JSON can hold them.
assert(require('json').decode(require('json').encode(filtered)).types.mob.include[2] == 41, 'The lists are plain JSON arrays.');

-- A save without overhead loads with the defaults and saves back with every other key unchanged.
local file = defaults.tidy(defaults.make());
file.overhead, file.profile_job = nil, 1;
file.panels.target.x, file.style.font_size, file.party_ui.enabled = 777, 21, true;
local path = MOCK_INSTALL_PATH .. '/config/addons/vantage/Tester_1001/settings.json';
assert(store.write(path, file));
-- The file as saved, its numbers as JSON keeps them.
file = assert(store.read(path));
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(1);
assert(app.state.path == path, 'The fixture loads the saved file.');
assert(store.equal(app.state.settings.overhead, fresh), 'Overhead loads with its defaults.');
app.callbacks.changed('before', 'Overhead');
app.state.settings.overhead.max_units = 12;
app.callbacks.changed('after');
assert(app.callbacks.save());
local saved = assert(store.read(path));
assert(saved.overhead.max_units == 12 and saved.overhead.enabled == false, 'The overhead settings are saved.');
for key, value in pairs(file) do
    assert(store.equal(saved[key], value), key .. ' saves back unchanged');
end
for key in pairs(saved) do assert(key == 'overhead' or file[key] ~= nil, key .. ' is new'); end
-- And it loads again as saved.
local again = defaults.tidy(store.read(path));
assert(again.overhead.max_units == 12 and store.equal(again.panels, file.panels));
