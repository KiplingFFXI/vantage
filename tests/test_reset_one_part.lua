-- Start over on Profiles: Reset one part puts one part of every display back, each asking first, each one Undo step. The
-- top bar's Mute alerts mutes on every page, and reads Unmute alerts while muted.
local h = require('panel_fixture')();
local customization = require('core.customization');
local defaults = require('ui.defaults');
local fresh = defaults.make();

-- Each part, what it changes first, and whether that came back.
local parts = {
    { 'appearance', 'Reset how everything looks', function(s) s.style.font_size = 20; end, function(s) return s.style.font_size == fresh.style.font_size; end },
    { 'conditions', 'Reset When to show on every display', function(s) s.panels.self_buffs.conditions.main_jobs[3] = true; end,
        function(s) return next(s.panels.self_buffs.conditions.main_jobs) == nil; end },
    -- A saved list is a set of ids.
    { 'effects', 'Reset the effect lists of every timer panel', function(s) s.panels.self_buffs.include = { [33] = true }; end,
        function(s) return next(s.panels.self_buffs.include) == nil; end },
    { 'moves_with', 'Reset Moves with on every display', function(s) s.panels.self_buffs.anchor.to = 'chat'; end,
        function(s) return s.panels.self_buffs.anchor.to == fresh.panels.self_buffs.anchor.to; end },
    { 'panels', 'Reset every timer panel\'s size and place', function(s) s.panels.self_buffs.width = 444; end,
        function(s) return s.panels.self_buffs.width == fresh.panels.self_buffs.width; end },
    { 'chat_colors', 'Reset chat line colors', function(s) s.chat_colors.replies = 50; end, function(s) return s.chat_colors.replies == 106; end },
};
for _, part in ipairs(parts) do
    local scope, label, change, back = part[1], part[2], part[3], part[4];
    h.fresh(change);
    h.s.window.tab, h.s.window.sections['Profiles/Reset one part'] = 'Profiles', true;
    h.draw();
    h.draw(label);
    assert(not back(h.s) and #h.app.state.history == 0, label .. ' asks first.');
    assert(h.says(label .. '? '), label .. ' asks under its button.');
    h.draw('Reset##look_profiles_reset_' .. scope);
    assert(back(h.s), label .. ' puts it back.');
    assert(#h.app.state.history == 1 and h.app.callbacks.history_status().undo_label == customization.reset_label(scope), label .. ' is one Undo step.');
    assert(h.app.callbacks.undo() and not back(h.app.state.settings), 'Undo takes ' .. label .. ' back.');
end;
-- Leave it as it is answers no.
h.fresh(parts[1][3]);
h.s.window.tab, h.s.window.sections['Profiles/Reset one part'] = 'Profiles', true;
h.draw();
h.draw(parts[1][2]);
h.draw('Cancel##look_profiles_reset_appearance');
h.draw();
assert(not parts[1][4](h.s) and #h.app.state.history == 0 and not h.says(parts[1][2] .. '? '), 'Cancel leaves it.');

-- Mute alerts, on the top bar of every page.
for _, tab in ipairs({ 'Home', 'Profiles', 'Help' }) do
    h.fresh();
    h.s.window.tab = tab;
    h.draw();
    assert(h.called('Button', 'Mute alerts##settings_mute'), 'Mute alerts is on the top bar of ' .. tab);
end;
h.draw('Mute alerts##settings_mute');
assert(h.s.alerts.muted == true and h.app.callbacks.history_status().undo_label == 'Mute alerts', 'It mutes in one Undo step.');
h.draw();
assert(h.called('Button', 'Unmute alerts##settings_mute'), 'Muted, it reads Unmute alerts.');
h.draw('Unmute alerts##settings_mute');
assert(h.s.alerts.muted == false and h.app.callbacks.history_status().undo_label == 'Unmute alerts', 'It unmutes in one Undo step.');

-- Reset the effect lists puts back every key a timer panel's Filters tab holds, on every timer panel.
local lists, keys = defaults.tidy(defaults.make()), require('ui.status_panel').filter_keys;
for _, id in ipairs(defaults.panel_order) do
    local panel = lists.panels[id];
    for _, key in ipairs(keys) do
        if type(panel[key]) == 'boolean' then panel[key] = not panel[key];
        elseif type(panel[key]) == 'string' then panel[key] = 'crab';
        elseif type(panel[key]) == 'table' then panel[key] = { [33] = true }; end;
    end;
end;
lists = customization.reset(lists, 'effects');
for _, id in ipairs(defaults.panel_order) do
    for _, key in ipairs(keys) do
        assert(customization.equal(lists.panels[id][key], fresh.panels[id][key]), 'Reset the effect lists puts back ' .. id .. '\'s ' .. key .. '.');
    end;
end;
MOCK.fire('unload');
return 'Reset one part asks first and is one Undo step, and Mute alerts is on the top bar';
