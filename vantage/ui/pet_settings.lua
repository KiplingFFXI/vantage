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

local function color_of(key) return function() return fresh[key]; end; end;

-- What any pet shows comes first, then what each pet job adds. The bars' colors sit on one line under the tick that
-- shows them.
local show_rows = {
    frame.tick('Show HP, MP and TP', 'show_vitals', 'Bars for the pet\'s HP, MP and TP, as the client has them.'),
    frame.line(nil, nil, {
        frame.color('HP bar', 'hp_color', nil, { fallback = color_of('hp_color'), alias = 'HP bar color' }),
        frame.color('MP bar', 'mp_color', nil, { fallback = color_of('mp_color'), alias = 'MP bar color' }),
        frame.color('TP bar', 'tp_color', nil, { fallback = color_of('tp_color'), alias = 'TP bar color' }),
    }, { only = vitals_on, shown_by = 'Show HP, MP and TP' }),
    frame.radio('Effects', nil, { 'all', 'buff', 'debuff', 'none' }, { all = 'Buffs and debuffs', buff = 'Buffs only', debuff = 'Debuffs only', none = 'None' },
        'The pet\'s effects, debuffs first.', {
            alias = 'Show buffs and debuffs Effect types', resets = { 'show_effects', 'kinds' },
            read = function(c) return c.p.show_effects and c.p.kinds or 'none'; end,
            write = function(c, value)
                c.p.show_effects = value ~= 'none';
                if value ~= 'none' then c.p.kinds = value; end;
            end }),
    frame.radio('Show effects as', 'effects_as', pet.effect_styles, { icons = 'Icons', list = 'List with names' },
        'Icons wrap onto more rows. A list gives each effect a line with its name and time left.', { only = effects_on, shown_by = 'Effects' }),
    frame.tick('Show effect countdowns', 'show_countdowns', 'Effects with no known time show no countdown.', { only = effects_on, shown_by = 'Effects' }),
    frame.number('Most effects shown', 'max_effects', 1, 32, limit_help, { only = effects_on, shown_by = 'Effects' }),
    frame.tick('Show pet command recasts', 'show_recasts', 'Your recasts of pet commands and of abilities that call or heal a pet, soonest ready first.'),
    frame.number('Most recasts shown', 'max_recasts', 1, 16, limit_help, { only = recasts_on, shown_by = 'Show pet command recasts' }),
    frame.heading('More about any pet', 'Each of these adds a line to the display. They all start off.'),
    frame.tick('Show what my pet is fighting', 'show_target', 'The mob your pet is attacking and its HP. It\'s in the warning color when that isn\'t your target.', {
        alias = 'Pet target mob HP' }),
    frame.tick('Show what my pet is doing', 'show_action', 'The spell it\'s casting or the move it\'s readying, then the last one it used, with its damage.', {
        alias = 'Pet casting readies last move damage' }),
    frame.tick('Show the distance to my pet', 'show_distance', 'In yalms. It takes the warning color when your pet is too far for Fight on BST, Repair on PUP or Healing Breath on DRG.', {
        alias = 'Pet range yalms' }),
    frame.tick('Show how long my pet has been out', 'show_time_out', 'Counted from when Vantage first saw it in this zone.', { alias = 'Pet time out summoned' }),
    frame.heading('Automaton', 'For a PUP, main or support. Only the maneuvers start on.'),
    frame.tick('Show maneuvers and overload risk', 'show_maneuvers', 'As a PUP, main or support: a line for each element with a maneuver up, the time until the next ends, and the overload risk last reported.'),
    frame.tick('Show automaton HP as a number', 'exact_hp', 'As a PUP, main or support: your automaton\'s HP shows as HP and max HP, like 812/1040. Other pets, and the automaton until the server sends its status, show a percent.', {
        only = vitals_on, shown_by = 'Show HP, MP and TP' }),
    frame.tick('Show automaton MP as a number', 'exact_mp', 'Your automaton\'s MP bar shows its MP and max MP, like 168/420, instead of a percent. It comes from the same place as the HP number.', {
        only = vitals_on, shown_by = 'Show HP, MP and TP' }),
    frame.tick('Show attachment timers', 'show_attachments', 'A line for each attachment that fires on its own, such as Strobe and Flashbulb, with the time until it can fire again, or Ready, or the maneuver it needs.', {
        alias = 'Attachment recast cooldown Strobe Flashbulb Shock Absorber Replicator Eraser' }),
    frame.tick('Show the automaton\'s own cooldowns', 'show_cooldowns', 'About when it can next cast each kind of spell, shoot or Shield Bash, by its head and frame. These are estimates, as it acts on a tick of its own.', {
        alias = 'Automaton spell cooldown ranged attack Shield Bash' }),
    frame.tick('Show the automaton\'s build', 'show_build', 'Its head and frame, its skills with their caps, its stats and its attachments, as the server sends them to you.', {
        alias = 'Automaton head frame skills stats attachments' }),
    frame.heading('Charmed and jug pets', 'For a BST, main or support. Only the charm and jug time starts on.'),
    frame.tick('Show charm and jug time', 'show_charm', 'A charmed pet\'s estimated time left, next to its name, which needs a /check before the charm. For a jug pet, the time until it leaves, from your Call Beast.', {
        alias = 'Show charm time' }),
    frame.tick('Mark where Sic is ready', 'sic_mark', 'As a BST, main or support, with a jug pet or a charmed mob out: a mark on the TP bar at 1000 TP, where Sic makes your pet use a move.', {
        only = vitals_on, shown_by = 'Show HP, MP and TP', alias = 'Sic TP 1000' }),
    frame.tick('Show what Reward would heal', 'show_reward', 'As a BST, main or support, with a pet out: what Reward would heal with the pet food in your ammo slot, your MND and your gear.', {
        alias = 'Reward heal pet food' }),
    frame.heading('Avatar and wyvern', 'For a SMN and a DRG. They start off.'),
    frame.tick('Show what my avatar costs', 'show_upkeep', 'As a SMN: what your MP goes down by each 3 seconds with your avatar out, measured from your own MP, and how long your MP lasts at that rate.', {
        alias = 'Avatar perpetuation MP cost upkeep' }),
    frame.tick('Show when Healing Breath would fire', 'show_breath', 'As a DRG: whether a spell of yours would make your wyvern use Healing Breath now, and on whom, or the HP it waits for.', {
        alias = 'Wyvern Healing Breath' }),
    -- Your pet's alerts are on Alerts, with the rest (ui/alert_panel.lua).
    frame.line('Pet alerts', 'Low HP, 1000 TP and a charm or jug pet about to end are on Alerts, with your other alerts.', {
        frame.button('Open Alerts', 'Opens Alerts, where your pet\'s alerts are.', function(c) c.open_page('Display', 'notices'); end),
    }, { alias = 'Pet notices' }),
};

local filter_rows = {
    frame.tick('Use the Hide list', 'shared_rules', 'The Hide list applies here too. Its Pets group matches your pet.', { alias = 'Use shared hide rules' }),
    frame.button('Edit the list', 'Open the Hide list.', function(c) c.open_page('Filters'); end, { alias = 'Shared effect filters' }),
    status.list_paused(),
};
for _, item in ipairs(rows.effect_lists({
    of = root, sorted = true, show = 'Show only', hide = 'Hide here',
    listed = { include = 'Show only', exclude = 'Hidden here' },
    alias = { find = 'Find an effect Find a pet effect Pet effect', show = 'Include on the pet display', hide = 'Hide on the pet display' },
})) do filter_rows[#filter_rows + 1] = item; end;

local place_rows = rows.box_place(pet.MIN_WIDTH, 'display', 'what it shows');

frame.register({
    id = 'pet', name = 'Pet', fold_page = 'Pet',
    tabs = { show = show_rows, filters = filter_rows, place = place_rows, when = conditions_ui.rows },
    tab_reset = { filters = frame.reset_keys({ 'shared_rules', 'include', 'exclude' }) },
    header = header,
});

return page;
