-- The Recasts display has its Show switch in the header of every tab, so no tab has to say a panel is hidden or how to show
-- it. The tabs edit the panels of the recast display in use: a panel of the other one can't be open here.
local defaults, window, hud = require('ui.defaults'), require('ui.settings_window'), require('ui.hud');
local panels = require('ui.panel_frame');
local s, view = defaults.make(), hud.sample(100);
s.window.open, s.window.tab = true, 'Display';
local edits = 0;
local cb = { changed = function(phase) if phase == 'after' then edits = edits + 1; end; end, editor_changed = function() end, save = function() return true; end };
local function frame(click)
    MOCK.imgui_calls = {};
    if click then MOCK.clicks[click] = true; end;
    window.draw(s, view, cb);
    if click then assert(not MOCK.clicks[click], 'Fixture: the control is on screen: ' .. click); end;
    MOCK.clicks = {};
end;
local function switch()
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Checkbox' and call[2] == 'On##frame_display' then return call[3][1]; end;
    end;
end;
local function hidden_line()
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'TextWrapped' and tostring(call[2]):find('Hidden: ', 1, true) then return call[2]; end;
    end;
end;
local tabs = { 'show', 'place', 'look', 'filters', 'when' };

-- Spell recasts starts off, and every tab has the switch and says nothing more.
for _, tab in ipairs(tabs) do
    panels.open('spell_recasts', tab);
    frame(); frame();
    assert(not s.panels.spell_recasts.enabled and switch() == false and hidden_line() == nil, 'The header shows the switch off, with no hidden line: ' .. tab);
end;
panels.open('spell_recasts', 'filters');
frame('On##frame_display'); frame();
assert(s.panels.spell_recasts.enabled == true and switch() == true and edits == 1, 'The switch shows the panel from any tab.');
s.enabled = false; frame();
assert(switch() == false, 'Paused timer panels read off.');
frame('On##frame_display'); frame();
assert(s.enabled == true and s.panels.spell_recasts.enabled == true and switch() == true, 'Its switch resumes them.');

-- While the display is combined the tabs edit the combined panel, and the switch is its own.
s.recast_display = 'combined'; frame();
assert(switch() == true, 'The combined panel starts on.');
s.panels.recasts.enabled = false; frame();
assert(switch() == false and s.panels.spell_recasts.enabled == true and hidden_line() == nil, 'The switch reads the combined panel.');
s.panels.recasts.enabled = true;
s.recast_display = 'separate';

-- Status timers has the same switch on every tab.
for _, tab in ipairs(tabs) do
    panels.open('self_buffs', tab);
    frame(); frame();
    assert(switch() == true and hidden_line() == nil, 'Fixture: Self buffs is on: ' .. tab);
end;
s.panels.self_buffs.enabled = false; frame();
assert(switch() == false and hidden_line() == nil, 'Status timers keeps its switch on every tab and says nothing more.');
assert(edits == 2, 'Only the switch changed anything.');
return 'Every tab of a timer or recast panel has its Show switch, and none has a hidden line';
