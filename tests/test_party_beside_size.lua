-- Icon size beside the game's list: Fill the row by default, a smaller size in the middle of each row, and a bigger one
-- in a stack of names and icons that ends where the game's last row does. Stacks pile up in the order of the game's
-- windows and shrink to fit the screen, or fill the rows when even the smallest stack wouldn't fit. The saved number
-- keeps its limits, and the line on Size and place says what the size does.
local overlay, defaults = require('ui.native_party_hud'), require('ui.party_defaults');
local hud, theme, widget = require('ui.party_hud'), require('ui.party_theme'), require('ui.party_size_widget');
local countdown = require('ui.countdown_text');

local p = defaults.make();
p.enabled = true;
local roster, subjects = hud.sample(18, 100);
local look = theme.party(p, nil);

-- The game's windows as they sit at 1920x1080: your party's at the bottom and the alliance's above it, with rows 14 px
-- tall and 20 px apart. bottoms are where each window's last row ends.
local function windows(bottoms, x, reversed)
    local geometry = { available = true, groups = {} };
    for group = 1, 3 do
        local frame = { x = x or 1795, y = bottoms[group] - 114, width = 116, height = 114, pitch = 20, rows = {} };
        for _, member in ipairs(roster.members) do if member.group == group then
            local place = reversed and 5 - member.slot % 6 or member.slot % 6;
            frame.rows[member.slot] = { x = frame.x, y = frame.y + place * 20, width = 116, height = 14, slot = member.slot };
        end end;
        geometry.groups[group] = frame;
    end;
    return geometry;
end;
local geometry = windows({ 1064, 914, 764 });
local function plans() return overlay.plan(roster, subjects, p, geometry, 1920, 1080); end;
-- One member's line in a stack at px, and a group's whole stack.
local function line(px) return look.font_size + 2 + 2 + px + 4; end;
local function reach(px) return 6 * line(px) - 4; end;

-- Fill the row is the default, and is as it always was.
local plan = plans()[1];
assert(p.native.icon_size == 0 and not plan.stacked and plan.rows[2].options.icon_size == 20 and plan.rows[2].area.y == 967
    and plan.rows[2].area.height == 20, 'Fill the row is the default: 20 px icons from 3 px above each row.');

-- Smaller than the step, the icons go in the middle of the 20 px room, and the distance stays by the row.
p.native.icon_size, p.distance = 16, true;
plan = plans()[1];
local row = plan.rows[2];
assert(not plan.stacked and row.options.icon_size == 16 and row.area.y == 969 and row.area.height == 16,
    'A 16 px size sits 2 px into the 20 px room, in the middle of the row.');
assert(row.distance_cell and row.distance_cell.y == 967 and row.distance_cell.height == 20, 'The distance stays by the row.');
p.distance = false;

-- Bigger than the step, each group's buffs are a stack: names over icons, in the game's order, ending at its last row.
p.native.icon_size = 32;
local all = plans();
plan = all[1];
assert(#all == 3 and plan.stacked and #plan.rows == 6, 'A size bigger than the rows makes a stack.');
for index, item in ipairs(plan.rows) do
    assert(item.member.slot == index - 1 and item.label_lines[1] == item.member.name, 'Each member\'s name is on their line, in the game\'s order.');
    assert(item.options.icon_size == 32 and item.area.height == 32 and item.area.y == item.label_y + look.font_size + 4,
        'The icons are 32 px, under the name.');
    assert(index == 1 or item.label_y - plan.rows[index - 1].label_y == line(32), 'One member\'s line follows the last.');
    assert(item.area.align_right and item.label_x + item.label_width == item.area.x + item.area.width,
        'Left of the game\'s list, the name sits over the icons nearest it.');
end;
local last = plan.rows[6];
assert(last.area.y + last.area.height == 1064 and plan.y == 1064 - reach(32) and plan.height == reach(32),
    'The last member\'s icons end where the game\'s last row does, and the stack grows up from there.');
assert(plan.x + plan.width == 1769, 'The stack keeps the 26 px gap from the game\'s list.');
-- A drag moves it as it moves a strip, kept on the screen.
assert(plan.offset_y_min == reach(32) - 1064 and plan.offset_y_max == 16, 'The stack moves from the top of the screen to its bottom.');
p.groups[1].native_y = -100;
assert(plans()[1].y == 1064 - reach(32) - 100, 'A saved offset moves the stack.');
p.groups[1].native_y = 0;

-- The alliance's stacks pile up over yours, 8 px apart, as the game's windows do.
local a1, a2 = all[2], all[3];
assert(a1.stacked and a2.stacked and a1.y + a1.height == plan.y - 8 and a2.y + a2.height == a1.y - 8,
    'Alliance 1 stacks over your party, and Alliance 2 over Alliance 1.');
assert(a1.rows[1].options.icon_size == 32 and a2.rows[1].options.icon_size == 32, 'At 32 px all three fit.');

-- When they don't fit, they all shrink to the biggest size that does.
p.native.icon_size = 64;
all = plans();
local px = all[1].rows[1].options.icon_size;
assert(px > 20 and px < 64 and all[2].rows[1].options.icon_size == px and all[3].rows[1].options.icon_size == px,
    'All three stacks shrink to one size: ' .. px);
assert(1064 - 3 * reach(px) - 16 >= 0 and 1064 - 3 * reach(px + 1) - 16 < 0, 'It is the biggest that fits.');
assert(p.native.icon_size == 64, 'Shrinking never changes the saved size.');

-- A stack that wouldn't fit even a pixel past the rows goes back to filling them.
p.native.icon_size = 32;
p.strips.alliance1, p.strips.alliance2 = false, false;
geometry = windows({ 150, 914, 764 });
plan = plans()[1];
assert(#plans() == 1 and not plan.stacked and plan.rows[1].options.icon_size == 20, 'No room above the list: the icons fill the rows.');
p.strips.alliance1, p.strips.alliance2 = true, true;

-- Right of the game's list, the names start where the icons do.
geometry = windows({ 1064, 914, 764 }, 1500);
p.native.side = 'right';
plan = plans()[1];
assert(plan.stacked and plan.x == 1642 and not plan.rows[1].area.align_right and plan.rows[1].label_x == plan.rows[1].area.x,
    'Right of the list, the stack starts 26 px past it with the names on the left.');
p.native.side = 'left';
geometry = windows({ 1064, 914, 764 });

-- A game list with its first slot at the bottom stacks in the order its rows are on the screen.
geometry = windows({ 1064, 914, 764 }, nil, true);
plan = plans()[1];
assert(plan.stacked and plan.rows[1].member.slot == 5 and plan.rows[6].member.slot == 0, 'The stack goes as the rows go.');
geometry = windows({ 1064, 914, 764 });

-- With no effects, the stack is as wide as its longest name.
local held_effects = {};
for slot = 0, 5 do held_effects[1001 + slot], subjects[1001 + slot].effects = subjects[1001 + slot].effects, {}; end;
plan = plans()[1];
local widest = 0;
for _, item in ipairs(plan.rows) do widest = math.max(widest, item.name_width); end;
assert(plan.stacked and widest > 32 and plan.width == widest, 'The names set the width when they are wider than the icons.');
for id, list in pairs(held_effects) do subjects[id].effects = list; end;

-- On rows that aren't on whole pixels, as with some game menu sizes, the stack starts on a whole pixel and its last
-- icons end within 1 px of the last row's bottom.
geometry = windows({ 1064.6, 914.6, 764.6 });
plan = plans()[1];
local ends = plan.rows[6].area.y + plan.rows[6].area.height;
assert(plan.stacked and plan.y == math.floor(plan.y) and ends <= 1064.6 and ends > 1063.6, 'Whole pixels, ending at ' .. ends);
geometry = windows({ 1064, 914, 764 });

-- With countdowns under the icons the line makes room for them, and inside the icons it doesn't.
p.effects.timers, p.effects.icon_countdown_position = true, 'below';
plan = plans()[1];
assert(not plan.stacked and plan.rows[1].options.icon_size == 20,
    'With countdowns 20 px tall under them, three stacks don\'t fit 1080 px even at 21 px, so they fill the rows.');
p.strips.alliance1, p.strips.alliance2 = false, false;
local _, _, tall, gap = countdown.icon_values(look.font, '57', 32, p.effects);
plan = plans()[1];
assert(plan.stacked and plan.rows[1].area.height == 32 + gap + math.ceil(tall), 'A countdown under the icons adds its height.');
p.effects.icon_countdown_position = 'inside';
assert(plans()[1].rows[1].area.height == 32, 'A countdown inside the icons adds nothing.');
p.effects.timers, p.strips.alliance1, p.strips.alliance2 = false, true, true;

-- The saved number: 0 fills the rows, anything else is 12 to 128.
for given, kept in pairs({ [5] = 12, [200] = 128, [-3] = 0, [0] = 0, [40] = 40 }) do
    local value = defaults.make();
    value.native.icon_size = given;
    assert(defaults.tidy(value).native.icon_size == kept, given .. ' keeps ' .. kept);
end;
local value = defaults.make();
value.native.icon_size = 'big';
assert(defaults.tidy(value).native.icon_size == 0, 'A size that isn\'t a number fills the rows.');
value.native.icon_size = nil;
assert(defaults.tidy(value).native.icon_size == 0, 'A save from before the size fills the rows.');

-- The line on Size and place, and whether a group stacks.
local rooms = { { group = 1, room = 20, pitch = 20, attached = true, members = 6 } };
p.native.icon_size = 0;
assert(widget.step(p, rooms) == "Beside the game's party list the icons fill the step from one row to the next (20 px here), with no space between them.");
assert(not widget.stacked(p, rooms), 'Fill the row never stacks.');
p.native.icon_size = 32;
assert(widget.step(p, rooms) == "The game's party list is 20 px from one row to the next here. Icons smaller than the step between its rows sit in the middle of each row, and bigger ones go in a stack with each member's name.");
assert(widget.stacked(p, rooms) and widget.stacked(p, {}), 'Bigger than the rows stacks, and so does any size before the list is read.');
p.native.icon_size = 16;
assert(not widget.stacked(p, rooms), 'Smaller than the rows doesn\'t stack.');
rooms[1].attached = false;
p.native.icon_size = 32;
assert(widget.stacked(p, rooms), 'A group in a panel of its own doesn\'t count as read.');

-- On the screen, a stack draws each member's name over their icons, and a strip that fills the rows draws none.
local fonts = require('ui.fonts');
local painted = {};
local plain_draw = fonts.draw;
fonts.draw = function(list, face, value, ...) painted[value] = true; return plain_draw(list, face, value, ...); end;
local function drawn(name)
    if painted[name] then return true; end;
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'draw:AddText' and call[6] == name then return true; end; end;
    return false;
end;
MOCK.screen = { 1920, 1080 };
local function draw()
    painted, MOCK.imgui_calls = {}, {};
    overlay.draw(roster, subjects, p, 100, { native_geometry = geometry });
end;
p.native.icon_size = 32;
draw();
for _, name in ipairs({ 'Aster', 'Fable', 'Gale', 'Reed' }) do assert(drawn(name), name .. ' is drawn over their icons.'); end;
p.native.icon_size = 0;
draw();
assert(not drawn('Aster') and not drawn('Gale'), 'Filling the rows draws no names.');
fonts.draw = plain_draw;

-- A new countdown size makes room for itself at once, though the height of each size is kept from frame to frame.
-- Here a countdown is as tall as its size, 16 px when it scales with the icon, and the plans keep what they measured.
p.native.icon_size, p.effects.timers, p.effects.icon_countdown_position = 32, true, 'below';
p.strips.alliance1, p.strips.alliance2 = false, false;
local real_values = countdown.icon_values;
countdown.icon_values = function(_, _, _, options)
    local size = (options.icon_countdown_size or 0) > 0 and options.icon_countdown_size or 16;
    return size, size, size, 0;
end;
local function kept() return overlay.plan(roster, subjects, p, geometry, 1920, 1080, nil, nil, overlay._kept)[1].rows[1].area.height; end;
p.effects.icon_countdown_size = 0;
assert(kept() == 48, 'A 16 px countdown under 32 px icons.');
p.effects.icon_countdown_size = 30;
assert(kept() == 62, 'A new countdown size is measured again at once.');
countdown.icon_values = real_values;
p.effects.icon_countdown_size, p.effects.timers, p.strips.alliance1, p.strips.alliance2 = 0, false, true, true;

-- The size goes where Longest row and the gap go, with shared placement.
local s = require('ui.defaults').make();
s.party_ui.native.icon_size = 40;
assert(require('core.profiles').capture_layout(s, 'placement').party_ui.native.icon_size == 40, 'Shared placement carries it.');

-- Search finds the size by its words, and while the names are hidden, it finds the size that brings them.
local window = require('ui.settings_window');
local function finds(query, label)
    for _, result in ipairs(window.search(query)) do if result.panel == 'party_ui' and result.label == label then return true; end; end;
    return false;
end;
assert(finds('Bigger party buffs', "Icon size beside the game's list"), 'Its search words find it.');
assert(finds('Member names', "Icon size beside the game's list") and finds('Member names', 'Your party in a panel of its own'),
    'Hidden names are found at the size and the switches that bring them.');

-- After a draw, the settings go by what it made of the size. Stacks that fell back to the rows show no name rows, and
-- the line says why.
local measured_rooms = { { group = 1, room = 20, pitch = 20, attached = true, members = 6 } };
p.native.icon_size, p.effects.timers, p.effects.icon_countdown_position = 32, true, 'below';
p.strips.alliance1, p.strips.alliance2 = true, true;
draw();
assert(not widget.stacked(p, measured_rooms), 'Stacks that fell back to the rows don\'t count as stacks.');
assert(widget.step(p, measured_rooms):find(" There's no room on the screen for the stacks now, so the icons fill the rows.", 1, true),
    'The line says the stacks had no room.');
p.effects.timers = false;
draw();
assert(widget.stacked(p, measured_rooms) and not widget.step(p, measured_rooms):find('no room', 1, true), 'Drawn stacks count.');
p.native.icon_size = 40;
assert(widget.stacked(p, measured_rooms), 'A size not drawn yet goes by the rows.');
