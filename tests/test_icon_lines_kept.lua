-- An icon panel keeps its countdown lines from frame to frame, and each panel its working copy, so every change to how a
-- countdown looks has to reach the screen the frame it's made, and again when Undo takes it back.
local countdown = require('ui.countdown_text');
local seen = {};
countdown.draw = function(_, font, text, _, _, size, color, options)
    seen[#seen + 1] = { font = font, text = text, size = size, color = color, options = options };
    return true;
end;
local defaults, hud, theme = require('ui.defaults'), require('ui.hud'), require('ui.theme');
local s = defaults.make();
local p = s.panels.self_buffs;
p.mode = 'icons';
local view = hud.sample(100);
local function draw(now)
    seen = {};
    hud.draw(view, s, now or 100, {});
    assert(#seen > 0, 'Fixture: the panel drew its countdowns.');
    return seen[1];
end;

local first = draw();
assert(draw().options == first.options, 'Fixture: the next frame draws the line it kept.');
for _, field in ipairs({ 'countdown_bold', 'countdown_shadow', 'countdown_outline' }) do
    local before = p[field];
    p[field] = not before;
    assert(draw().options[field] == p[field], field .. ' reaches the screen.');
    p[field] = before;
    assert(draw().options[field] == before, field .. ' comes back with Undo.');
end;

-- A color can come back as a new table or be changed where it is.
local outline = p.countdown_outline_color;
p.countdown_outline_color = { 1, 0, 0, 1 };
assert(draw().options.countdown_outline_color == p.countdown_outline_color, 'A new outline color reaches the screen.');
p.countdown_outline_color[2] = .5;
assert(draw().options.countdown_outline_color[2] == .5, 'So does one changed where it is.');
p.countdown_outline_color = outline;
assert(draw().options.countdown_outline_color == outline, 'The outline color comes back with Undo.');
local colors = p.colors;
p.colors = { value = { 0, 1, 0, 1 } };
assert(draw().color == theme.u32({ 0, 1, 0, 1 }), 'A new countdown color reaches the screen.');
p.colors.value[1] = 1;
assert(draw().color == theme.u32({ 1, 1, 0, 1 }), 'So does one changed where it is.');
p.colors = colors;
assert(draw().color == first.color, 'The countdown color comes back with Undo.');
p.field_colors = { time = { 0, 1, 0, 1 } };
assert(draw().color == first.color, 'A row text color saved for the other layouts has no say here.');
p.field_colors = nil;

local size = first.size;
p.icon_countdown_size = size + 7;
assert(draw().size == size + 7, 'A new countdown size reaches the screen.');
p.icon_countdown_size = 0;
assert(draw().size == size, 'The size comes back with Undo.');
s.style.scale = 2;
assert(draw().size == size * 2, 'The scale reaches the screen.');
s.style.scale = 1;
assert(draw().size == size, 'The scale comes back with Undo.');

local later = draw(130);
assert(later.text ~= first.text, 'A countdown that ticks shows its new text: ' .. first.text .. ' to ' .. later.text);
assert(draw().text == first.text, 'And the kept text of an earlier second is still right.');

-- A working copy holds nothing the panel no longer has, and nothing Text only put in it.
p.countdown_outline_color = nil;
assert(draw().options.countdown_outline_color == nil, 'A key the panel lost leaves its working copy.');
p.countdown_outline_color = outline;
local icon, fill = p.show_icon, p.show_fill;
p.mode = 'text';
hud.draw(view, s, 100, {});
p.mode = 'bars';
local painted = {};
local drawn_with = hud.entries;
hud.entries = function(row, panel, ...) painted[#painted + 1] = panel; return drawn_with(row, panel, ...); end;
hud.draw(view, s, 100, {});
hud.entries = drawn_with;
assert(#painted > 0 and painted[1].show_icon == icon and painted[1].show_fill == fill, 'Text only leaves nothing behind for the next frame.');
return 'Kept icon lines follow every change';
