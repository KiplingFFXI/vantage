local defaults, window = require('ui.defaults'), require('ui.settings_window');
local custom = require('core.customization');
local imgui, panels = require('imgui'), require('ui.panel_frame');
local s, edits, history = defaults.make(), 0, {};
s.window.open = true;
s.panels.self_buffs.mode, s.panels.spell_recasts.mode = 'icons', 'icons';
s.style.font = 'XI View';
-- Party countdowns start off; on here, so their controls show. The party list buffs' position and gap show while a
-- group is in a panel of its own, the only place that reads them.
s.party_ui.effects.timers = true;
s.party_ui.groups[1].native_detached = true;
local opened, combo, input = false, nil, {};
imgui.SetNextItemOpen = function(value) opened = value; end;
imgui.CollapsingHeader = function() return opened; end;
imgui.BeginCombo = function(label) return label == combo; end;
local slider = imgui.SliderFloat;
imgui.SliderFloat = function(label, value, ...)
    slider(label, value, ...);
    if input[label] ~= nil then value[1], input[label] = input[label], nil; return true; end;
    return false;
end;
local cb = { save=function() return true; end, changed=function(stage)
    if stage == 'before' then edits = edits + 1; history[#history + 1] = custom.history_value(s); end;
end };
local function draw(click, picker)
    combo, MOCK.imgui_calls = picker, {};
    if click then MOCK.clicks[click] = true; end;
    window.draw(s, require('ui.hud').sample(100), cb);
    if click then assert(not MOCK.clicks[click], 'Control is reachable: ' .. click); end;
    assert(#MOCK.font_stack == 0);
end;
local function called(kind, label)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == kind and call[2] == label then return true; end; end;
    return false;
end;
-- On a fresh save Self buffs shows icons, the recast panels bars, and the party list buffs no countdowns, so there the
-- search leads to what shows these.
for _, label in ipairs({ 'Icon countdown position', 'Icon countdown size', 'Icon countdown gap' }) do
    local found = {};
    for _, result in ipairs(window.search(label)) do found[result.tab .. '/' .. result.label] = true; end;
    for _, place in ipairs({ 'Display/' .. label, 'Display/Layout', 'Display/Countdowns' }) do
        assert(found[place], label .. ' finds ' .. place .. ' before the page is opened.');
    end;
end;
local function panel_case(id)
    return { page='Display', open=function() panels.open(id, 'place'); end, effect=s.panels[id], size='##frame_Size_countdown', gap='##frame_Gap_countdown',
        position='##frame_Position_countdown', position_label='Position', inside='Inside##inside', below='Below##below' };
end;
local cases = {
    panel_case('self_buffs'), panel_case('spell_recasts'),
    { page='Display', open=function() panels.open('party_ui', 'place'); end, effect=s.party_ui.effects, size='##frame_Countdown size',
        gap='##frame_Countdown gap', position='##frame_Countdown position', position_label='Countdown position', inside='Inside icon##inside', below='Below icon##below' },
};
for _, case in ipairs(cases) do
    s.window.tab = case.page;
    case.open();
    local before, count = custom.history_value(s), edits;
    draw();
    assert(custom.equal(before, custom.history_value(s)) and edits == count, 'Opening countdown settings never changes saved settings.');
    assert(called('SliderFloat', case.size) and called('SliderFloat', case.gap));
    input[case.size] = 18; draw();
    assert(case.effect.icon_countdown_size == 18 and history[#history].party_ui.locked, 'Manual countdown sizing is saved with an Undo snapshot.');
    input[case.gap] = 4; draw();
    assert(case.effect.icon_countdown_gap == 4);
    draw(case.inside, case.position);
    assert(case.effect.icon_countdown_position == 'inside' and not called('SliderFloat', case.gap));
    input[case.size] = 3; draw();
    assert(case.effect.icon_countdown_size == 6, 'The slider skips unsupported 1-5 pixel sizes.');
    input[case.size] = 0; draw();
    assert(case.effect.icon_countdown_size == 0);
    draw(case.below, case.position);
    assert(case.effect.icon_countdown_gap == 4 and called('SliderFloat', case.gap), 'Returning below restores the saved gap.');
end;
-- Beside the game's party list the time sits inside the icon, so with no group in a panel of its own Party list buffs
-- shows the countdown size and neither the position nor the gap. Their saved choices stay for a panel of its own.
s.party_ui.groups[1].native_detached = false;
s.party_ui.effects.icon_countdown_position, s.party_ui.effects.icon_countdown_gap = 'below', 4;
s.window.tab = 'Display';
panels.open('party_ui', 'place');
local kept = custom.history_value(s);
draw();
assert(called('SliderFloat', '##frame_Countdown size') and not called('TextUnformatted', 'Countdown position')
    and not called('SliderFloat', '##frame_Countdown gap'), 'Beside the game\'s list only the countdown size shows.');
assert(custom.equal(kept, custom.history_value(s)), 'Hiding them changes no saved choice.');
s.party_ui.groups[3].native_detached = true;
draw();
assert(called('TextUnformatted', 'Countdown position') and called('SliderFloat', '##frame_Countdown gap'),
    'A group in a panel of its own brings them back.');
s.party_ui.groups[3].native_detached = false;
-- Status timers and recasts always have room below the icon, so they always show both.
for _, case in ipairs({ cases[1], cases[2] }) do
    s.window.tab = case.page;
    case.open();
    draw();
    assert(called('TextUnformatted', case.position_label) and called('SliderFloat', case.gap), case.page .. ' shows the position and the gap.');
    -- They close the tab, so the rows that place the panel can't read as part of them.
    local back, size;
    for index, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Button' and tostring(call[2]):find('Put it back where it started', 1, true) then back = index; end;
        if call[1] == 'SliderFloat' and call[2] == case.size then size = index; end;
    end;
    assert(back and size and back < size, case.page .. ' has its countdown rows after the place rows.');
end;
assert(s.style.font == 'XI View');
assert(s.party_ui.locked and s.panels.self_buffs.locked);
assert(#MOCK.commands == 0);
