-- The shape every display's editor has. A header with the way back, the display's name, On, samples and Locked. The same
-- tabs in the same order, leaving out one a display has nothing for. Reset this display at the foot of every tab. No two
-- controls on a tab share an id, or a click would land on both.
local h = require('panel_fixture')();
local defaults, custom = require('ui.defaults'), require('core.customization');
local panels, imgui = h.panels, h.imgui;
local tab_buttons = { 'Show##frame_tab', 'Size and place##frame_tab', 'Look##frame_tab', 'Filters##frame_tab', 'When to show##frame_tab' };
local tab_keys = { 'show', 'place', 'look', 'filters', 'when' };
local status_ids = { 'self_buffs', 'self_debuffs', 'target', 'party', 'watch' };
local names = { self_buffs = 'Self buffs', self_debuffs = 'Self debuffs', target = 'Target timers', party = "Party members' timers", watch = 'Watched enemy timers' };

-- The header and the tabs, on each display, on every tab.
h.fresh();
for _, id in ipairs({ 'self_buffs', 'self_debuffs', 'target', 'party', 'watch', 'recasts' }) do
    for _, tab in ipairs(tab_keys) do
        h.on(id, tab);
        assert(h.called('Button', '< Back##frame'), 'The way back is on ' .. id);
        assert(h.says(names[id] or 'Recasts'), 'It says which display this is: ' .. id);
        assert(h.called('Checkbox', 'On##frame_display') and h.called('Checkbox', 'Show samples##frame')
            and h.called('Checkbox', 'Locked##frame'), 'On, samples and Locked are in the header of ' .. id);
        local order = {};
        for _, call in ipairs(MOCK.imgui_calls) do
            if call[1] == 'Button' and tostring(call[2]):find('##frame_tab', 1, true) then order[#order + 1] = call[2]; end;
        end;
        assert(table.concat(order, '|') == table.concat(tab_buttons, '|'), 'Always the same tabs, in order: ' .. table.concat(order, '|'));
        assert(h.called('Button', 'Reset this display##frame'), 'Reset this display is at the foot of ' .. id .. ' ' .. tab);
    end;
end;

-- The tabs go where they say, each display keeps its own, and the way back is the main page.
h.on('self_buffs', 'look');
assert(panels.context() == 'self_buffs/look');
h.draw('Size and place##frame_tab');
h.draw();
assert(panels.context() == 'self_buffs/place' and h.called('SliderFloat', '##frame_Across'));
panels.open('target', 'look');
panels.open('self_buffs');
assert(panels.context() == 'self_buffs/place', 'A display opens on the tab it was last on.');
panels.open('target');
assert(panels.context() == 'target/look', 'Each display has its own.');
local before = custom.history_value(h.s);
h.draw('< Back##frame');
h.draw();
assert(h.s.window.tab == 'Home' and custom.equal(before, custom.history_value(h.s)), 'Back goes to the main page and changes no setting.');
panels.open('self_buffs', 'no such tab');
assert(panels.context() == 'self_buffs/show', 'A tab no display has opens Show.');

-- A display with nothing for a tab has no button for it.
panels.register({ id = 'test_display', name = 'Test display', fold_page = 'Panels', header = {},
    tabs = { show = { panels.note('On show.') }, place = {} },
    fill = function(ctx) ctx.id = 'self_buffs'; end });
h.s.window.tab = 'Display';
panels.open('test_display', 'show');
h.draw(); h.draw();
assert(not h.called('Button', 'Filters##frame_tab') and not h.called('Button', 'Look##frame_tab') and not h.called('Button', 'When to show##frame_tab'), 'A tab with nothing is left out.');
assert(h.called('Button', 'Show##frame_tab') and h.called('Button', 'Size and place##frame_tab'), 'A tab with rows is not.');
panels.open('self_buffs');

-- Reset this display: asks first, puts it back locked in its first spot, and Undo brings the settings back.
h.fresh(function(s)
    local p = s.panels.self_debuffs;
    p.x, p.y, p.locked, p.mode, p.sort, p.title = 411, 233, false, 'bars', 'name', 'Mine';
end);
h.on('self_debuffs', 'look');
h.draw('Reset this display##frame');
assert(h.s.panels.self_debuffs.x == 411, 'The first click only asks.');
h.draw();
assert(h.says('Reset Self debuffs? It goes back to how it started: locked, in its first spot.'), 'The line says what it does: ');
assert(h.called('Button', 'Reset##look_frame_reset_self_debuffs') and h.called('Button', 'Cancel##look_frame_reset_self_debuffs'), 'And offers both ways out.');
h.draw('Cancel##look_frame_reset_self_debuffs');
h.draw();
assert(h.s.panels.self_debuffs.x == 411 and not h.says('Reset Self debuffs?'), 'Cancel leaves it.');
h.draw('Reset this display##frame');
h.draw();
h.draw('Reset##look_frame_reset_self_debuffs');
h.draw();
local p, first = h.s.panels.self_debuffs, defaults.make().panels.self_debuffs;
assert(p.x == first.x and p.y == first.y and p.locked == true and p.mode == first.mode and p.sort == first.sort and p.title == first.title,
    'It goes back to how it started: locked, in its first spot.');
h.draw('Undo');
h.draw();
p = h.s.panels.self_debuffs;
assert(p.x == 411 and p.y == 233 and p.locked == false and p.title == 'Mine', 'Undo brings the settings back.');

-- No two controls on a tab share an id, in any state of a display.
local kinds = { Checkbox = true, Button = true, SliderFloat = true, BeginCombo = true, InputText = true, ColorEdit4 = true, RadioButton = true, CollapsingHeader = true };
local function one_id_each(when)
    local seen, stack = {}, {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'PushID' then stack[#stack + 1] = tostring(call[2]);
        elseif call[1] == 'PopID' then stack[#stack] = nil;
        elseif kinds[call[1]] then
            local id = table.concat(stack, '/') .. '/' .. tostring(call[2]);
            assert(not seen[id], when .. ': two controls share ' .. id);
            seen[id] = true;
        end;
    end;
end;
for _, mode in ipairs({ 'icons', 'bars', 'expanded', 'text' }) do
    h.fresh(function(s)
        for _, id in ipairs(defaults.panel_order) do
            local panel = s.panels[id];
            panel.mode, panel.dispel_light, panel.gradient, panel.bar_style = mode, true, true, 'rail';
            panel.anchor.to = 'chat';
        end;
        s.ready_pulse.enabled, s.ready_pulse.spot = true, 'screen';
    end);
    for _, id in ipairs({ 'self_buffs', 'self_debuffs', 'target', 'party', 'watch', 'spell_recasts' }) do
        for _, tab in ipairs(tab_keys) do
            h.on(id, tab);
            one_id_each(mode .. ' ' .. id .. '/' .. tab);
        end;
    end;
end;

-- A display's name on its tabs is what ui/elements.lua calls it, and its id is what it always was.
local elements = require('ui.elements');
for id, name in pairs(names) do assert(elements.label(id) == name and elements.by_id[id], 'Its name and id: ' .. id); end;
assert(#MOCK.commands == 0, 'The editors send no game commands.');
MOCK.fire('unload');
return 'Every display has the same header, six tabs and Reset, greyed where it has nothing, with one id for each control';
