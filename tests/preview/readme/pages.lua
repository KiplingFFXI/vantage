-- How the settings pages and edit mode in the README pictures are set up, run through the preview's --exec with the
-- whole addon loaded: require('preview.readme.pages').<page>(settings). The pages start with the samples off, as a
-- fresh install has them; edit mode keeps them on, so its displays have something in them.
local defaults = require('ui.defaults');
local M = {};

-- A level 75 Red Mage with White Mage support, as in the other pictures.
local function red_mage()
    MOCK.player.main_job, MOCK.player.main_level, MOCK.player.sub_job, MOCK.player.sub_level = 5, 75, 3, 37;
end

local function fresh(settings)
    defaults.samples_off(settings);
    red_mage();
end

-- The main page.
function M.main(settings)
    fresh(settings);
    settings.window.tab = 'Home';
end

-- Self buffs' editor on its Look tab, as bars.
function M.editor(settings)
    fresh(settings);
    settings.panels.self_buffs.mode, settings.panels.self_buffs.stack_direction = 'bars', 'vertical';
    settings.window.tab = 'Display';
    require('ui.panel_frame').open('self_buffs', 'look');
end

-- Hidden everywhere with four effects on its list, one of them only on party members.
function M.hidden(settings)
    fresh(settings);
    local filters = require('core.effect_filters');
    local rules = settings.effect_filters.rules;
    for _, spec in ipairs({ { 253, 'all' }, { 256, 'all' }, { 113, 'all' }, { 251, 'party' } }) do
        local rule = filters.rule();
        rule.effect, rule.scope = spec[1], spec[2];
        rules[#rules + 1] = rule;
    end;
    settings.window.tab = 'Display';
    settings.window.sections['Filters/Conditional hide rules'] = true;
    require('ui.panel_frame').open('hidden');
end

-- Alerts with its three common reminders added and the first open in the editor.
function M.alerts(settings)
    fresh(settings);
    local templates = { { name = 'Haste ending', effect = 33, thresholds = { 30, 10 }, scope = 'self' },
        { name = 'Sleep ending', effect = 2, thresholds = { 10 }, scope = 'target' }, require('core.starters').silenced };
    for index, template in ipairs(templates) do
        local rule = defaults.rule('rule_' .. index);
        for key, value in pairs(template) do rule[key] = value; end;
        settings.alerts.rules[index] = rule;
    end;
    settings.window.tab = 'Display';
    require('ui.panel_frame').open('notices');
    require('ui.alert_panel').edit('rule_1');
end

-- The main page, where a Red Mage's starter profile is Crowd control.
function M.starters(settings)
    fresh(settings);
    settings.window.tab = 'Home';
end

-- Edit mode on a 1080 by 600 screen with the samples on, Grid mode on for Target timers and Target timers unlocked, so
-- a Shift drag of it shows the grid. Every display is bars, so each has the heading its name sits under.
function M.edit(settings)
    red_mage();
    settings.window.open = false;
    -- The sample recasts' pictures.
    require('preview.readme.common').resources();
    local places = { self_buffs = { 24, 140 }, self_debuffs = { 340, 140 }, target = { 340, 300 }, spell_recasts = { 660, 140 },
        ability_recasts = { 660, 300 } };
    for key, place in pairs(places) do
        local p = settings.panels[key];
        p.enabled, p.x, p.y, p.mode, p.stack_direction = true, place[1], place[2], 'bars', 'vertical';
    end;
    settings.panels.target.locked = false;
    settings.alerts.notice_x, settings.alerts.notice_y = 340, 480;
    settings.edit_mode.grid_mode = true;
    require('ui.snap').tick(settings, 'target', true);
    -- The preview's ImGui has no keyboard capture call for edit mode's arrow keys; nothing in the picture needs one.
    rawset(require('imgui'), 'SetNextFrameWantCaptureKeyboard', function() end);
    MOCK.fire('command', { command = '/vg edit' });
end

return M;
