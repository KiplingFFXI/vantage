-- The editor of the Phantom Roll display (settings.rolls), as a display on the panel frame.
local conditions_ui = require('ui.condition_settings');
local frame = require('ui.panel_frame');
local rolls = require('core.rolls');
local rows = require('ui.panel_rows');
local page = {};
local fresh = rolls.make();

local function members_shown(c) return c.p.show_members; end;

local header = {
    frame.line(nil, nil, {
        frame.tick('On', 'enabled', 'Shows the display while you or a party member rolls. Turning it off ends its samples.', {
            tag = '_display', find = 'Show this display', alias = 'Show Phantom Roll display Show this panel display',
            write = function(c, on)
                c.p.enabled = on;
                if not on then c.p.preview = false; end;
            end }),
        rows.samples('Sample rolls in the display, to arrange it with nothing happening.', function(c) return c.p.enabled; end, { alias = 'Sample displays' }),
        frame.lock_row,
    }),
};

local function color_of(key) return function() return fresh[key]; end; end;

-- The heading switch and the colors close the tab.
local show_rows = {
    frame.tick('Show what it gives', 'show_effect', 'What the roll gives you at its total, or what a bust takes from the Corsair.'),
    frame.tick('Show lucky and unlucky numbers', 'show_numbers', 'A line with each roll\'s lucky and unlucky numbers. The total takes the lucky and unlucky colors either way.'),
    frame.tick('Show the bust chance', 'show_odds', 'The chance that one more Double-Up busts, from the total. With Snake Eye on the Corsair it adds 1.'),
    frame.tick('Show who got it', 'show_members', 'Your party, in party order. Those it didn\'t reach, or that already have the roll from another Corsair, are dimmed.'),
    frame.number('Most rolls shown', 'max_rolls', 1, 8, 'A Corsair can hold two rolls, and each new roll moves the Double-Up chance to it. Rolls past this, or past the display\'s height, are not shown.'),
    rows.heading('Show the display\'s title.'),
    frame.color('Lucky number color', 'lucky_color', nil, { fallback = color_of('lucky_color') }),
    frame.color('Unlucky number color', 'unlucky_color', nil, { fallback = color_of('unlucky_color') }),
    frame.color('Not reached color', 'missed_color', nil, { fallback = color_of('missed_color'), only = members_shown, shown_by = 'Show who got it' }),
};

local place_rows = rows.box_place(rolls.MIN_WIDTH, 'display', 'what it shows');

frame.register({
    id = 'rolls', name = 'Phantom Roll', fold_page = 'Rolls',
    tabs = { show = show_rows, place = place_rows, when = conditions_ui.rows },
    header = header,
});

return page;
