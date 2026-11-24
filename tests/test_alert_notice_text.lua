-- The text of an alert notice: Alerts has a text size and a text color of its own, and each rule can give its notice
-- a color. All three start as they were: the size is the shared Text size, the color the shared text color, and a rule
-- has no color of its own. A rule's color beats the Alerts color, which beats the shared one.
local defaults, hud, theme = require('ui.defaults'), require('ui.hud'), require('ui.theme');
local RED, GREEN = { 1, 0, 0, 1 }, { 0, 1, 0, 1 };

-- What a save holds.
do
    local fresh = defaults.make();
    assert(fresh.alerts.notice_text_size == 0, 'The notice text size starts as the shared Text size.');
    assert(type(fresh.alerts.notice_colors) == 'table' and next(fresh.alerts.notice_colors) == nil, 'Alerts starts with no text color of its own.');
    local rule = defaults.rule('r1');
    assert(type(rule.notice_colors) == 'table' and next(rule.notice_colors) == nil, 'A rule starts with no notice color of its own.');
    local function sized(value)
        local s = defaults.make();
        s.alerts.notice_text_size = value;
        return defaults.tidy(s).alerts.notice_text_size;
    end
    for _, case in ipairs({ { 0, 0 }, { 8, 8 }, { 20, 20 }, { 48, 48 }, { 5, 8 }, { 1, 8 }, { 60, 48 }, { 20.4, 20 }, { -3, 0 } }) do
        assert(sized(case[1]) == case[2], 'A saved size of ' .. case[1] .. ' reads as ' .. case[2] .. ': ' .. tostring(sized(case[1])));
    end
    assert(sized('big') == 0 and sized(nil) == 0 and sized(0 / 0) == 0, 'A size that is no number, or a save from before it, is the shared size.');
    local function colored(value)
        local s = defaults.make();
        s.alerts.notice_colors = value;
        return defaults.tidy(s).alerts.notice_colors;
    end
    local kept = colored({ text = { 1, 0.5, 0.25, 1 } });
    assert(kept.text[1] == 1 and kept.text[2] == 0.5 and kept.text[3] == 0.25 and kept.text[4] == 1, 'A saved color is kept.');
    kept = colored({ text = { 7, -2, 0.5, 1 } });
    assert(kept.text[1] == 1 and kept.text[2] == 0 and kept.text[3] == 0.5, 'Its parts stay between 0 and 1.');
    assert(next(colored(nil)) == nil and next(colored('red')) == nil and next(colored({ text = 'red' })) == nil and next(colored({ other = RED })) == nil,
        'Anything that is not a color leaves the shared one.');
    local function rule_color(value)
        local s = defaults.make();
        local made = defaults.rule('r1');
        made.notice_colors = value;
        s.alerts.rules = { made };
        return defaults.tidy(s).alerts.rules[1].notice_colors;
    end
    assert(rule_color({ text = GREEN }).text[2] == 1, 'A rule keeps its notice color.');
    assert(next(rule_color(nil)) == nil and next(rule_color({ text = 4 })) == nil, 'And has none when it was saved with none.');
    local old = defaults.make();
    old.alerts.rules = { { id = 'old', name = 'Old rule', effect = 2 } };
    assert(next(defaults.tidy(old).alerts.rules[1].notice_colors) == nil, 'A rule saved before this has no color of its own.');
end

-- A notice carries its rule's color from the moment it fires.
do
    local A = require('core.alerts');
    local function fired(colors)
        local rule = defaults.rule('r1');
        rule.effect, rule.effect_name, rule.event, rule.notice_colors = 2, 'Sleep', 'gain', colors;
        local a = A.new();
        a:test(rule, 10);
        return a:view(10.5)[1];
    end
    local notice = fired({ text = GREEN });
    assert(notice and notice.color and notice.color[2] == 1 and notice.color[1] == 0, 'The notice has its rule\'s color.');
    assert(fired({}).color == nil and fired(nil).color == nil, 'A rule with none gives its notice none.');
    local a = A.new();
    a:announce('pet', 'Your pet has 1000 TP', 10);
    assert(a:view(10.5)[1].color == nil, 'A notice with no rule behind it has no color of its own.');
end

-- What is drawn. fonts.paint is where every piece of text goes, with its size and its color.
local fonts, imgui = require('ui.fonts'), require('imgui');
local paints, sizes, dimensions = {}, {}, {};
fonts.paint = function(_, _, _, value, _, y, size, color) paints[#paints + 1] = { text = value, size = size, color = color, y = y }; end;
imgui.SetNextWindowPos = function() end;
imgui.SetNextWindowSize = function(value) dimensions = value; end;
imgui.Begin = function(name) sizes[name] = { dimensions[1], dimensions[2] }; return true; end;
local function fresh()
    local s = defaults.tidy(defaults.make());
    s.style.scale, s.style.font, s.style.font_size, s.style.text_shadow, s.style.text_outline = 1, 'Ashita', 14, false, false;
    return s;
end
local LONG = 'Sleep is on Tester and it wears off in thirty seconds unless somebody takes it off before then';
local function draw(s, notices)
    paints, sizes = {}, {};
    hud.draw_notices({ notices = notices, context = {} }, s, 100, { shift = false });
    local box = sizes['##vantage_notices'];
    assert(box, 'Fixture: the notices drew.');
    return box[2], box[1];
end
-- The ink a line was drawn in, and its size, by the text it starts with.
local function drawn(start)
    local found;
    for _, paint in ipairs(paints) do
        if paint.text:sub(1, #start) == start then found = paint; end
    end
    return found;
end
local function lines_of(start)
    local count = 0;
    for _, paint in ipairs(paints) do count = count + 1; end
    return count;
end
local function notice(message, color) return { visual = true, ends = 104, message = message, color = color }; end

local s = fresh();
local plain_height = draw(s, { notice('Haste wore off') });
local plain = drawn('Haste');
assert(plain and plain.size == 14 and plain.color == theme.u32(s.style.text_color), 'As it starts, a notice has the shared size and color: ' .. tostring(plain and plain.size));
local plain_long = draw(s, { notice(LONG) });
local plain_lines = lines_of();

-- A bigger size: bigger text, a taller box, and more lines of a long message inside the same width.
s.alerts.notice_text_size = 28;
local big_height, big_width = draw(s, { notice('Haste wore off') });
local big = drawn('Haste');
assert(big.size == 28 and big.color == theme.u32(s.style.text_color), 'The notice text size sets the size of the text: ' .. big.size);
assert(big_height > plain_height + 10, 'The box grows with its text: ' .. plain_height .. ' to ' .. big_height);
assert(big_width == s.alerts.notice_width, 'And stays as wide as Width says: ' .. big_width);
local big_long = draw(s, { notice(LONG) });
assert(lines_of() > plain_lines and big_long > plain_long, 'A long message wraps onto more lines at a bigger size: ' .. plain_lines .. ' to ' .. lines_of());
for _, paint in ipairs(paints) do assert(paint.size == 28, 'Every line of it is that size.'); end
for index = 2, #paints do assert(paints[index].y - paints[index - 1].y == 31, 'Its lines are a line of that size apart: ' .. (paints[index].y - paints[index - 1].y)); end
-- The whole display follows Size, as before.
s.style.scale = 1.5;
draw(s, { notice('Haste wore off') });
assert(drawn('Haste').size == 42, 'Size on the main page scales it too: ' .. drawn('Haste').size);
s.style.scale = 1;
-- A smaller one than the shared size works the same way.
s.alerts.notice_text_size = 10;
local small_height = draw(s, { notice('Haste wore off') });
assert(drawn('Haste').size == 10 and small_height < plain_height, 'A smaller size makes a smaller notice.');
s.alerts.notice_text_size = 0;
draw(s, { notice('Haste wore off') });
assert(drawn('Haste').size == 14, 'Set back, it is the shared size again.');

-- The Alerts color, then a rule's own over it.
s.alerts.notice_colors.text = RED;
draw(s, { notice('Haste wore off'), notice('Sleep on Tester', GREEN) });
assert(drawn('Haste').color == theme.u32(RED), 'The Alerts text color colors a notice.');
assert(drawn('Sleep').color == theme.u32(GREEN), 'A rule\'s own color beats it.');
s.alerts.notice_colors.text = nil;
draw(s, { notice('Haste wore off'), notice('Sleep on Tester', GREEN) });
assert(drawn('Haste').color == theme.u32(s.style.text_color) and drawn('Sleep').color == theme.u32(GREEN),
    'With no Alerts color, a notice has the shared color and a rule\'s notice still has its own.');
-- Every line of a wrapped notice has its color, and the estimate tag with it.
draw(s, { { visual = true, ends = 104, message = LONG, color = GREEN, estimated = true } });
assert(#paints > 1 and drawn('[Estimated]'), 'Fixture: a wrapped notice with its tag.');
for _, paint in ipairs(paints) do assert(paint.color == theme.u32(GREEN), 'Every line of a notice has its color.'); end
return 'Notice text has a size and colors of its own';
