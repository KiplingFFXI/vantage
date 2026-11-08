-- The editor of the pet display (settings.pet), as a display on the panel frame.
local conditions_ui = require('ui.condition_settings');
local frame = require('ui.panel_frame');
local pet = require('core.pet');
local rows = require('ui.panel_rows');
local status = require('ui.status_panel');
local page = {};
local fresh = pet.make();
local limit_help = 'What is past this, or past the display\'s room, is not shown.';

local function root(c) return c.p; end;
local function vitals_on(c) return c.p.show_vitals; end;
local function effects_on(c) return c.p.show_effects; end;
local function recasts_on(c) return c.p.show_recasts; end;

local header = {
    frame.line(nil, nil, {
        frame.tick('On', 'enabled', 'Your pet\'s HP, MP, TP, effects, maneuvers and command recasts while you have one. Turning it off ends its samples.', {
            tag = '_display', find = 'Show this display', alias = 'Show pet display Show this panel display',
            write = function(c, on)
                c.p.enabled = on;
                if not on then c.p.preview = false; end;
            end }),
        rows.samples('A sample pet of your job in the display, to arrange it with none out.', function(c) return c.p.enabled; end, { alias = 'Sample displays' }),
        frame.lock_row,
    }),
};

local show_rows = {
    frame.tick('Show HP, MP and TP', 'show_vitals', 'Bars for the pet\'s HP, MP and TP, as the client has them.'),
    frame.tick('Show charm and jug time', 'show_charm', 'For a charmed pet, its estimated time left, next to its name. Familiar adds at least 25 minutes once. With no /check before the charm it shows with no countdown. For a jug pet, the time until it leaves, counted from your Call Beast.', {
        alias = 'Show charm time' }),
    frame.radio('Effects', nil, { 'all', 'buff', 'debuff', 'none' }, { all = 'Buffs and debuffs', buff = 'Buffs only', debuff = 'Debuffs only', none = 'None' },
        'The pet\'s effects, debuffs first.', {
            alias = 'Show buffs and debuffs Effect types',
            read = function(c) return c.p.show_effects and c.p.kinds or 'none'; end,
            write = function(c, value)
                c.p.show_effects = value ~= 'none';
                if value ~= 'none' then c.p.kinds = value; end;
            end }),
    frame.radio('Show effects as', 'effects_as', pet.effect_styles, { icons = 'Icons', list = 'List with names' },
        'Icons wrap onto more rows. A list gives each effect a line with its name and time left.', { only = effects_on, shown_by = 'Effects' }),
    frame.tick('Show effect countdowns', 'show_countdowns', 'Effects with no known time show no countdown.', { only = effects_on, shown_by = 'Effects' }),
    frame.number('Most effects shown', 'max_effects', 1, 32, limit_help, { only = effects_on, shown_by = 'Effects' }),
    frame.tick('Show maneuvers and overload risk', 'show_maneuvers', 'As a PUP, main or support: a line for each element with a maneuver up, with the time until the next one ends and the overload risk your last maneuver reported.'),
    frame.tick('Show pet command recasts', 'show_recasts', 'Your recasts of pet commands and of abilities that call or heal a pet, soonest ready first.'),
    frame.number('Most recasts shown', 'max_recasts', 1, 16, limit_help, { only = recasts_on, shown_by = 'Show pet command recasts' }),
};

local function color_of(key) return function() return fresh[key]; end; end;

local look_rows = { frame.group({
    frame.color('HP bar', 'hp_color', nil, { fallback = color_of('hp_color'), alias = 'HP bar color' }),
    frame.color('MP bar', 'mp_color', nil, { fallback = color_of('mp_color'), alias = 'MP bar color' }),
    frame.color('TP bar', 'tp_color', nil, { fallback = color_of('tp_color'), alias = 'TP bar color' }),
}, { only = vitals_on, shown_by = 'Show HP, MP and TP' }) };

local filter_rows = {
    frame.tick('Use the Hidden everywhere list', 'shared_rules', 'The Hidden everywhere list applies here too. Its Pets group matches your pet.', { alias = 'Use shared hide rules' }),
    frame.button('Edit the list', 'Open the Hidden everywhere list.', function(c) c.open_page('Filters'); end, { alias = 'Shared effect filters' }),
    status.list_paused(),
};
for _, item in ipairs(rows.effect_lists({
    of = root, sorted = true, find = 'Find an effect', effect = 'Effect', show = 'Show only', hide = 'Hide here', clear = 'Clear this display\'s filters',
    listed = { include = 'Show only', exclude = 'Hidden here' },
    alias = { find = 'Find a pet effect', effect = 'Pet effect', show = 'Include on the pet display', hide = 'Hide on the pet display', clear = 'Clear pet filters Clear pet effect filters' },
})) do filter_rows[#filter_rows + 1] = item; end;

local place_rows = {
    frame.locked_line,
    frame.number('Width', 'width', 160, 1400, 'The display\'s width.', { locks = true, alias = 'Display width' }),
    frame.number('Tallest', 'height', 0, 16000, 'Fit follows what it shows. A fixed height is at least 60 pixels.', { locks = true, edge = 'y', special = { [0] = 'Fit' }, alias = 'Maximum display height Automatic',
        write = function(c, value) c.p.height = value == 0 and 0 or math.max(60, value); end }),
};
for _, item in ipairs(frame.place_rows()) do place_rows[#place_rows + 1] = item; end;
place_rows[#place_rows + 1] = frame.put_back;

frame.register({
    id = 'pet', name = 'Pet', fold_page = 'Pet',
    tabs = { show = show_rows, look = look_rows, filters = filter_rows, place = place_rows, when = conditions_ui.rows },
    tab_on = { look = vitals_on },
    header = header,
});

return page;
