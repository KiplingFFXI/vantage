-- Settings keep the screen size a fresh install's first frame or an apply placed the displays for. Apply size on
-- another screen then knows that screen's spots as Vantage's own and re-spaces them, so a layout made for a bigger
-- screen doesn't leave panels on top of each other. A save with no such size loads as it is.
local defaults, presets, setup = require('ui.defaults'), require('setup_fixture'), require('ui.setup_defaults');
local hud, layout, store = require('ui.hud'), require('ui.layout'), require('core.store');
local profiles = require('core.profiles');
local copy, equal = store.copy, require('core.customization').equal;

-- Loading: none stays none, nothing is written for it, a good size is kept and a bad one is dropped.
local saved = defaults.tidy(defaults.make());
saved.placement_screen = nil;
local text = store.encode(saved);
local loaded = defaults.tidy(require('json').decode(text));
assert(loaded.placement_screen == nil and not store.encode(loaded):find('placement_screen', 1, true),
    'A save without a placement screen loads without one.');
assert(equal(defaults.tidy({ placement_screen = { width = 1920, height = 1080 } }).placement_screen, { width = 1920, height = 1080 }),
    'A saved placement screen is kept.');
for _, bad in ipairs({ { width = 'x', height = 1080 }, { width = 0, height = 1080 }, { width = 1920 }, 1920, 'big' }) do
    assert(defaults.tidy({ placement_screen = bad }).placement_screen == nil, 'A damaged placement screen is dropped.');
end;

-- A fresh install's first frame and an apply with a screen keep the size they placed for.
local s = defaults.tidy(defaults.make());
setup.place_fresh(s, { width = 1920, height = 1080 });
assert(equal(s.placement_screen, { width = 1920, height = 1080 }), 'The first frame keeps its screen.');
local options = function(size, width, height)
    return { size = size, skin = 'keep', matching = true, window_type = 1, screen_width = width, screen_height = height };
end;
assert(presets.apply(s, options('minimal', 1600, 900)));
assert(equal(s.placement_screen, { width = 1600, height = 900 }), 'An apply keeps the screen it placed for.');
local without = copy(s);
assert(presets.apply(without, { size = 'minimal', skin = 'keep', matching = true, window_type = 1 }));
assert(equal(without.placement_screen, s.placement_screen), 'An apply without a screen leaves the size as it was.');

-- What a layout made for one screen looks like on another: each shown panel clamped on screen, and whether any
-- two of them overlap or any reaches past the edge.
local function problems(settings, width, height)
    local rects, found = {}, {};
    for _, id in ipairs(defaults.panel_order) do
        local p = settings.panels[id];
        if defaults.panel_enabled(settings, id) then
            local r = layout.clamp({ x = p.x, y = p.y, width = p.width, height = hud.bounds(p, settings.style, 1, width, height).height }, width, height);
            rects[#rects + 1] = { id = id, x = r.x, y = r.y, w = r.width, h = r.height };
            if p.x + p.width > width then found[#found + 1] = id .. ' past the edge'; end;
        end;
    end;
    for i = 1, #rects do
        for j = i + 1, #rects do
            local a, b = rects[i], rects[j];
            if a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h then found[#found + 1] = a.id .. '/' .. b.id; end;
        end;
    end;
    return found;
end;
local recasts = { 'spell_recasts', 'ability_recasts', 'item_recasts' };
for _, pair in ipairs({ { { 1920, 1080 }, { 1600, 900 } }, { { 1920, 1080 }, { 1280, 720 } }, { { 1600, 900 }, { 1280, 720 } } }) do
    local from, to = pair[1], pair[2];
    local tag = from[1] .. ' x ' .. from[2] .. ' shown at ' .. to[1] .. ' x ' .. to[2];
    -- The first frame's spots and an apply's flow spots on the first screen.
    for _, earlier in ipairs({ false, 'minimal_1_5x' }) do
        s = defaults.tidy(defaults.make());
        setup.place_fresh(s, { width = from[1], height = from[2] });
        for _, id in ipairs(recasts) do s.panels[id].enabled = true; end;
        if earlier then assert(presets.apply(s, options(earlier, from[1], from[2]))); end;
        assert(#problems(s, to[1], to[2]) > 0, 'Fixture: ' .. tag .. ' overlaps or reaches past the edge.');
        assert(presets.apply(s, options('minimal', to[1], to[2])));
        local left = problems(s, to[1], to[2]);
        assert(#left == 0, tag .. (earlier and ' after ' .. earlier or '') .. ': Apply size there re-spaces them: ' .. table.concat(left, ', '));
    end;
end;

-- A panel the player moved stays where it was put, and the others keep clear of it.
s = defaults.tidy(defaults.make());
setup.place_fresh(s, { width = 1920, height = 1080 });
for _, id in ipairs(recasts) do s.panels[id].enabled = true; end;
s.panels.self_debuffs.x, s.panels.self_debuffs.y = 700, 600;
assert(presets.apply(s, options('minimal', 1600, 900)));
assert(s.panels.self_debuffs.x == 700 and s.panels.self_debuffs.y == 600, 'A moved panel stays where it was put.');
assert(#problems(s, 1600, 900) == 0, 'The others keep clear of it: ' .. table.concat(problems(s, 1600, 900), ', '));

-- With no placement screen saved, only this screen's own spots are known.
s = defaults.tidy(defaults.make());
setup.place_fresh(s, { width = 1920, height = 1080 });
for _, id in ipairs(recasts) do s.panels[id].enabled = true; end;
s.placement_screen = nil;
-- Item recasts is one the first frame on 1920 x 1080 moved from its start.
local kept, start = { x = s.panels.item_recasts.x, y = s.panels.item_recasts.y }, defaults.make().panels.item_recasts;
assert(kept.x ~= start.x or kept.y ~= start.y, 'Fixture: the first frame moved Item recasts.');
assert(presets.apply(s, options('minimal', 1600, 900)));
assert(s.panels.item_recasts.x == kept.x and s.panels.item_recasts.y == kept.y, 'Without one, spots for another screen stay.');

-- Profiles and the shared layout carry the size with the positions it describes.
local placed = defaults.tidy(defaults.make());
setup.place_fresh(placed, { width = 1920, height = 1080 });
local layout_file = profiles.capture_layout(placed, 'placement');
assert(equal(layout_file.placement_screen, { width = 1920, height = 1080 }), 'A shared placement carries the screen.');
local other = defaults.tidy(defaults.make());
setup.place_fresh(other, { width = 1600, height = 900 });
assert(profiles.apply_layout(other, layout_file, 'placement'));
assert(equal(other.placement_screen, { width = 1920, height = 1080 }), 'Loading a shared placement takes its screen.');
local presentation = profiles.capture_layout(placed, 'presentation');
assert(equal(presentation.presentation.placement_screen, { width = 1920, height = 1080 }), 'A shared presentation carries it too.');
other = defaults.tidy(defaults.make());
setup.place_fresh(other, { width = 1600, height = 900 });
assert(profiles.apply_layout(other, presentation, 'presentation'));
assert(equal(other.placement_screen, { width = 1920, height = 1080 }), 'Loading a shared presentation takes its screen.');
layout_file.placement_screen = nil;
other = defaults.tidy(defaults.make());
setup.place_fresh(other, { width = 1600, height = 900 });
assert(profiles.apply_layout(other, layout_file, 'placement'));
assert(equal(other.placement_screen, { width = 1600, height = 900 }), 'A shared file without one keeps the character\'s own.');

local saved_profiles = profiles.new(require('core.identity').root());
assert(saved_profiles:save_new('Big screen', placed));
local unplaced = copy(placed);
unplaced.placement_screen = nil;
assert(saved_profiles:save_new('No screen', unplaced));
local current = defaults.tidy(defaults.make());
setup.place_fresh(current, { width = 1600, height = 900 });
assert(saved_profiles:load('Big screen', current));
assert(equal(current.placement_screen, { width = 1920, height = 1080 }), 'A profile brings the screen its positions were placed for.');
assert(saved_profiles:load('No screen', current));
assert(current.placement_screen == nil, 'A profile saved without one brings none.');
