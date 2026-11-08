-- The party list strips in named profiles and shared layouts. A profile keeps every strip choice; placement sharing
-- carries where the strips sit; presentation sharing carries their look and effects. Each character keeps its own
-- switches, lock and sample.
local profiles, store, defaults = require('core.profiles'), require('core.store'), require('ui.defaults');
local saved = profiles.new(MOCK_INSTALL_PATH .. '/config/addons/vantage');
local source, receiver = defaults.make(), defaults.make();
local party = source.party_ui;
party.enabled, party.preview, party.locked = true, true, true;
party.strips.alliance2 = false;
party.native.side, party.native.gap, party.native.width, party.native.snap = 'right', 14, 333, false;
party.include_self, party.show_solo, party.name_display, party.name_length = false, false, 'short', 5;
party.style.icon_art, party.style.opacity = 'XI View', 0.5;
party.effects.countdown_outline_color = { 0.2, 0.3, 0.4, 0.5 };
party.groups[2].native_x, party.groups[2].native_y, party.groups[2].native_side = -21, 17, 'left';
party.groups[3].native_detached, party.groups[3].detached_x, party.groups[3].detached_y = true, 801, 402;
party.groups[3].detached_width, party.groups[3].detached_height = 510, 333;
party.groups[2].order = { 5, 4, 3, 2, 1, 0 };
party.effects.include, party.effects.exclude = { 33, 40 }, { 2 };
party.effects.growth = 'left';
party.effects.icon_size = 128;

local captured = profiles.capture(source);
assert(captured.party_ui.preview == false and source.party_ui.preview == true, 'Saving never turns the active preview off.');
assert(captured.party_ui.enabled and captured.party_ui.locked and captured.party_ui.strips.alliance2 == false);
assert(captured.party_ui.groups[2].order[1] == 5);
captured.party_ui.effects.countdown_outline_color[1] = 0.9;
assert(source.party_ui.effects.countdown_outline_color[1] == 0.2, 'Captured nested colors cannot alias live settings.');
assert(saved:save_new('Alliance', source));
assert(store.read(saved.path).Alliance.party_ui.preview == false);
assert(not saved:source('Alliance', source).modified, 'Temporary party preview does not mark a named profile modified.');
assert(saved:load('Alliance', receiver));
local p = receiver.party_ui;
assert(p.enabled and p.locked and not p.preview and p.strips.party and p.strips.alliance1 and not p.strips.alliance2);
assert(p.native.side == 'right' and p.native.gap == 14 and p.native.width == 333 and not p.native.snap,
    'Named profiles retain where and how wide the strips are.');
assert(not p.include_self and not p.show_solo and p.name_display == 'short' and p.name_length == 5);
assert(p.style.icon_art == 'XI View' and p.style.opacity == 0.5, 'Named profiles retain the strip look.');
assert(p.groups[2].native_x == -21 and p.groups[2].native_y == 17 and p.groups[2].native_side == 'left'
    and p.groups[3].native_detached and p.groups[3].detached_x == 801 and p.groups[3].detached_width == 510);
assert(p.effects.icon_size == 128 and p.effects.growth == 'left', 'Named profiles retain large icons and the effect layout.');
assert(p.groups[2].order[1] == 5);
assert(p.effects.include[2] == 40 and p.effects.exclude[1] == 2);
assert(not saved:source('Alliance', receiver).modified, 'A loaded profile is not modified.');
p.effects.countdown_outline_color[1] = 0.7;
assert(saved:source('Alliance', receiver).modified and source.party_ui.effects.countdown_outline_color[1] == 0.2);

-- Loading a profile without party settings keeps the current strips, and a saved preview cannot turn on.
local database = assert(store.read(saved.path));
database.Plain = profiles.capture(defaults.make()); database.Plain.party_ui = nil;
database.Preview = profiles.capture(source); database.Preview.party_ui.preview = true;
assert(store.write(saved.path, database));
p.preview = true;
assert(saved:load('Plain', receiver));
p = receiver.party_ui;
assert(p.enabled and p.preview and p.native.width == 333);
assert(saved:load('Preview', receiver) and not receiver.party_ui.preview, 'Saved previews cannot become live profile mode.');
assert(saved:load('Alliance', receiver));

local placement = profiles.capture_layout(source, 'placement');
assert(placement.party_ui.native.side == 'right' and placement.party_ui.native.width == 333 and placement.party_ui.native.gap == 14);
assert(placement.party_ui.groups[2].native_x == -21 and placement.party_ui.groups[3].detached_x == 801
    and placement.party_ui.groups[3].native_detached and placement.party_ui.groups[2].order == nil);
assert(placement.party_ui.effects.growth == 'left');
for _, key in ipairs({ 'enabled', 'strips', 'preview', 'locked', 'style' }) do
    assert(placement.party_ui[key] == nil, 'Placement excludes ' .. key);
end
for _, key in ipairs({ 'include', 'exclude', 'timers', 'icon_size' }) do
    assert(placement.party_ui.effects[key] == nil, 'Effect placement sharing excludes ' .. key);
end
receiver = defaults.make(); receiver.party_ui.preview, receiver.party_ui.locked = true, true;
assert(saved:save_layout(source, 'placement') and saved:load_layout(receiver, 'placement'));
p = receiver.party_ui;
assert(p.native.side == 'right' and p.native.width == 333 and p.native.gap == 14);
assert(p.groups[2].native_x == -21 and p.groups[3].native_detached and p.groups[3].detached_y == 402 and p.groups[3].detached_height == 333);
assert(p.groups[2].order[1] == 0, 'Placement sharing keeps the receiving member order.');
assert(p.style.icon_art ~= 'XI View' or p.style.opacity ~= 0.5, 'Fixture: the receiver has its own look.');
assert(p.effects.icon_size ~= 128, 'Placement sharing keeps the receiving character look and icons.');
assert(p.effects.growth == 'left');
assert(not p.enabled and p.preview and p.locked and p.strips.alliance2, 'Placement keeps the receiving switches, sample and lock.');

local presentation = profiles.capture_layout(source, 'presentation');
for _, key in ipairs({ 'enabled', 'strips', 'preview', 'locked' }) do
    assert(presentation.presentation.party_ui[key] == nil, 'Shared presentation excludes ' .. key);
end
assert(saved:save_layout(source, 'presentation'));
assert(saved:load_layout(receiver, 'presentation'));
p = receiver.party_ui;
assert(p.effects.icon_size == 128 and p.style.icon_art == 'XI View' and p.style.opacity == 0.5);
assert(not p.enabled and p.preview and p.locked and p.strips.alliance2, 'Presentation keeps the receiving switches, sample and lock.');
assert(p.groups[2].order[1] == 5 and p.effects.include[2] == 40);
assert(p.name_display == 'short' and not p.include_self, 'Full shared presentation includes the member labels and rows.');
-- Personal controls neither publish changes nor accept manually inserted flags.
local before = profiles.capture_layout(receiver, 'presentation');
p.enabled, p.preview, p.locked, p.strips.party = true, false, false, false;
local after = profiles.capture_layout(receiver, 'presentation');
for _, key in ipairs({ 'enabled', 'strips', 'preview', 'locked' }) do
    assert(before.presentation.party_ui[key] == after.presentation.party_ui[key]);
end
presentation.presentation.party_ui.enabled, presentation.presentation.party_ui.locked = false, true;
presentation.presentation.party_ui.strips = { party = true, alliance1 = true, alliance2 = true };
assert(store.write(saved.layout_path, presentation) and saved:load_layout(receiver, 'presentation'));
p = receiver.party_ui;
assert(p.enabled and not p.preview and not p.locked and not p.strips.party, 'Inserted switches and locks are not taken.');

-- A shared layout without party data, such as a partial document from a peer, leaves the strips alone, in both scopes.
local current = store.copy(p.native);
assert(store.write(saved.layout_path, { self_buffs = { x = 400 } }));
assert(saved:load_layout(receiver, 'placement') and store.equal(receiver.party_ui.native, current) and receiver.party_ui.enabled);
assert(store.write(saved.layout_path, { scope = 'presentation', presentation = { style = defaults.make().style } }));
assert(saved:load_layout(receiver, 'presentation') and receiver.party_ui.effects.icon_size == 128 and receiver.party_ui.style.icon_art == 'XI View');
-- Malformed placement data is bounded without changing what shows or the filters.
assert(store.write(saved.layout_path, { party_ui = { native = { side = 'up', gap = -8, width = 9000 }, enabled = false,
    groups = { ['2'] = { native_x = 9000, detached_width = 5, native_side = 'middle' } },
    effects = { growth = 'up', include = { 2 } } } }));
assert(saved:load_layout(receiver, 'placement'));
p = receiver.party_ui;
assert(p.native.side == 'left' and p.native.gap == 0 and p.native.width == 900, 'A malformed strip placement is bounded.');
assert(p.groups[2].native_x == 2000 and p.groups[2].detached_width == 40 and p.groups[2].native_side == 'default',
    'Group places out of range are bounded.');
assert(p.effects.growth == 'right' and p.enabled and p.effects.include[2] == 40,
    'Malformed placement data is bounded without changing effect visibility or filters.');
local file = assert(io.open(saved.layout_path, 'wb')); file:write('invalid JSON'); file:close();
local prior = receiver.party_ui.groups[2].native_x;
assert(not saved:load_layout(receiver, 'presentation') and receiver.party_ui.groups[2].native_x == prior and receiver.party_ui.enabled);
return true;
