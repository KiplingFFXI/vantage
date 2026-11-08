-- Countdown text has one home, More look on the main page. A search for it leads there, and a click on a result opens
-- the fold and changes nothing. Where a countdown sits on an icon stays with the panel, on its Size and place tab.
local defaults, window, hud = require('ui.defaults'), require('ui.settings_window'), require('ui.hud');
local custom = require('core.customization');
local panels, imgui = require('ui.panel_frame'), require('imgui');
local s, changes = defaults.make(), {};
s.window.open = true;
s.style.font = 'XI View';
local next_open, query = false, nil;
imgui.SetNextItemOpen = function(value) next_open = value; end;
imgui.CollapsingHeader = function() return next_open; end;
imgui.InputTextWithHint = function(label, _, value)
    if label == '##find_settings' and query ~= nil then value[1], query = query, nil; return true; end;
    return false;
end;
local cb = { editor_changed=function() end, save=function() return true; end,
    changed=function(stage, label)
        if stage == 'before' then changes[#changes + 1] = { label=label, state=custom.history_value(s) }; end;
    end };
local function draw(click)
    MOCK.imgui_calls = {};
    if click then MOCK.clicks[click] = true; end;
    window.draw(s, hud.sample(100), cb);
    if click then assert(not MOCK.clicks[click], 'Navigation is reachable: ' .. click); end;
    assert(#MOCK.font_stack == 0);
end;
local function calls(kind, label)
    local count = 0;
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == kind and (not label or call[2] == label) then count = count + 1; end; end;
    return count;
end;
local function searchable()
    for _, entry in ipairs({ { 'countdown text outline', 'Countdown outline' }, { 'bold countdowns', 'Bold countdowns' },
        { 'countdown shadow', 'Countdown shadow' } }) do
        local found = false;
        for _, result in ipairs(window.search(entry[1])) do found = found or result.tab == 'Home' and result.label == entry[2]; end;
        assert(found, 'The main page control is searchable before and after opening: ' .. entry[1]);
    end;
end;
searchable();

-- The fold starts closed, and a search opens it without a change.
s.window.tab = 'Display'; panels.open('self_buffs', 'look'); draw();
local before = custom.history_value(s);
query = 'countdown outline'; draw(); draw();
local result;
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'Selectable' and tostring(call[2]):find('Countdown outline  /', 1, true) then result = call[2]; end;
end;
assert(result, 'The control is on the list.');
draw(result); draw();
assert(s.window.tab == 'Home' and calls('BeginCombo', '##main_countdown_outline') == 1, 'A result opens the fold it sits in.');
assert(calls('SetScrollHereY') > 0, 'Navigation scrolls to the control.');
assert(custom.equal(before, custom.history_value(s)) and #changes == 0, 'Navigation changes no display settings and creates no Undo step.');
searchable();

-- A panel of icons keeps where its countdown sits, and no text effects.
draw('Clear search');
s.window.tab, s.panels.self_buffs.mode = 'Display', 'icons';
panels.open('self_buffs', 'place');
draw(); draw();
assert(calls('BeginCombo', '##frame_Position_countdown') == 1 and calls('Checkbox', 'Countdown text outline') == 0
    and calls('Checkbox', 'Bold countdowns') == 0, 'The panel sets where the countdown sits and not how its text looks.');
assert(s.style.font == 'XI View' and s.panels.self_buffs.locked and s.party_ui.locked);
assert(#MOCK.commands == 0);
