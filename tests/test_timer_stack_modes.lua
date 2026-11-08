local defaults, hud = require('ui.defaults'), require('ui.hud');
local store, custom = require('core.store'), require('core.customization');
local imgui, countdown, fonts = require('imgui'), require('ui.countdown_text'), require('ui.fonts');
local timer_calls = {};
require('ui.icons').status = function(id) return 100000 + id; end;
require('ui.recast_icons').draw = function(list, row, _, x, y, size)
    list:AddImage(100000 + row.effect, {x,y}, {x+size,y+size}); return true;
end;
fonts.measure = function(_, text, size) return #text * size * 0.5; end;
fonts.draw = function() return false; end;
countdown.draw = function(_, font, text, x, y, size)
    timer_calls[#timer_calls+1] = {font=font,text=text,x=x,y=y,size=size};
end;
MOCK.screen = { 1600, 1000 };

local function setup(mode, direction, key, face)
    local settings = defaults.make();
    settings.recast_display = 'combined';
    settings.window.open = false;
    settings.style.font, settings.style.icon_size, settings.style.font_size = face, 24, 12;
    settings.style.scale, settings.style.gap, settings.style.bar_height = 1, 4, 36;
    settings.style.minimal, settings.style.background, settings.style.border = false, true, true;
    for id, panel in pairs(settings.panels) do panel.enabled = id == key; end;
    local p = settings.panels[key];
    p.mode, p.stack_direction, p.item_width, p.sort = mode, direction, 180, 'fixed';
    p.x, p.y, p.width = 100, 100, mode == 'icons' and 160 or 640;
    p.auto_width, p.auto_height, p.height_limit, p.max_rows = false, false, mode == 'icons' and 100 or 180, 32;
    p.wrap, p.locked, p.show_source, p.show_target = true, true, false, false;
    local view = { valid=true, context={id=1001}, rows={} };
    for index = 1, 6 do
        local id = index == 3 and 269 or 39 + index;
        if key == 'recasts' then id = 10000 + index; end;
        local row = { key='row'..index, effect=id, name='Effect '..index, entity_id=1001, present=true,
            scope='self', kind=key=='self_debuffs' and 'debuff' or 'buff' };
        row.status = (index==3 or index==4) and 'unknown' or 'server';
        if index ~= 3 and index ~= 4 then row.deadline, row.total = 200 + index, 300; end;
        if key == 'recasts' then row.domain, row.scope, row.kind = 'recast', 'recast', 'spell'; end;
        view.rows[index], p.order[index] = row, id;
    end;
    return settings, p, view;
end;

local function draw(settings, view, cb)
    MOCK.imgui_calls, timer_calls = {}, {};
    hud.draw(view, settings, 100, cb or {});
    local pictures, texts, decoration = {}, {}, 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddImage' and type(call[2]) == 'number' and call[2] >= 100000 then
            local values = MOCK.drawn[call];
            pictures[#pictures+1] = { id=call[2]-100000, x=values[3][1], y=values[3][2],
                width=values[4][1]-values[3][1], height=values[4][2]-values[3][2] };
        elseif call[1] == 'draw:AddText' then texts[#texts+1] = call[6];
        elseif call[1] == 'draw:AddRect' or call[1] == 'draw:AddRectFilled' or call[1] == 'draw:AddRectFilledMultiColor'
            or call[1] == 'draw:AddLine' then decoration = decoration + 1; end;
    end;
    return pictures, texts, decoration;
end;

for _, mode in ipairs({'bars','expanded','icons'}) do
    for _, direction in ipairs({'horizontal','vertical'}) do
        for _, key in ipairs({'self_buffs','self_debuffs','recasts'}) do
            for _, face in ipairs({'Original FFXI','XI View'}) do
                local settings, p, view = setup(mode,direction,key,face);
                local before = store.copy(settings);
                local pictures = draw(settings, view);
                assert(#pictures == 6, mode..' '..direction..' fits all six effects/cooldowns');
                assert(custom.equal(settings,before), 'Layout measurement never changes stored settings or locks');
                for _, picture in ipairs(pictures) do
                    assert(picture.width == 24 and picture.height == 24, 'Wrapping preserves the selected icon size');
                    assert(picture.x >= p.x and picture.x+picture.width <= p.x+p.width
                        and picture.y >= p.y and picture.y+picture.height <= p.y+p.height_limit,
                        'Every shown icon stays inside the requested panel');
                end;
                if direction == 'horizontal' then
                    assert(pictures[2].x > pictures[1].x and pictures[2].y == pictures[1].y,
                        mode .. ' ' .. key .. ' ' .. face .. ': horizontal stacking fills across before wrapping down');
                    assert(pictures[#pictures].y > pictures[1].y, 'Horizontal stacking wraps into another row');
                else
                    assert(pictures[2].x == pictures[1].x and pictures[2].y > pictures[1].y,
                        mode .. ' ' .. key .. ' ' .. face .. ': vertical stacking fills downward before wrapping across');
                    assert(pictures[#pictures].x > pictures[1].x, 'Vertical stacking wraps into another column');
                end;
                p.max_rows = 2;
                assert(#draw(settings,view) == 2, 'An explicit effect limit remains respected');
            end;
        end;
    end;
end;

for _, key in ipairs({'self_buffs','self_debuffs','recasts'}) do
    for _, face in ipairs({'Original FFXI','XI View'}) do
        local settings,p,view = setup('icons','horizontal',key,face);
        p.show_icon,p.show_time,p.show_text = false,false,false;
        p.show_name,p.show_target,p.show_source,p.show_elapsed,p.show_total = true,true,true,true,true;
        p.show_fill,p.show_heading,p.gradient,p.warning_mark = true,true,true,true;
        local before = store.copy(p);
        local pictures,texts,decoration = draw(settings,view);
        assert(#pictures == 6, 'Icons-only always shows known pictures, including effects with no duration');
        assert(decoration == 0 and #texts == 0, 'Icons-only has no panel, tile, gauge, heading, name, or unknown placeholder');
        assert(#timer_calls == 4, 'Only known durations receive countdown text');
        for _, call in ipairs(timer_calls) do
            assert(call.font == face and call.size == 12 and not call.text:find('?',1,true),
                'Countdowns retain the selected stock or XI View font without unknown symbols');
        end;
        assert(custom.equal(p,before), 'Icons-only preserves all bar fields and decorations for switching back');
        p.mode,p.show_icon,p.show_time,p.show_text = 'bars',true,true,true;
        local _,bar_text,bar_decoration = draw(settings,view);
        assert(#bar_text > 0 and bar_decoration > 0, 'Returning to bars restores names and configured decoration');
    end;
end;

local clicked = false;
imgui.IsItemHovered = function() return true; end;
imgui.IsMouseClicked = function() local result=clicked; clicked=false; return result; end;
for _, mode in ipairs({'bars','expanded','icons'}) do
    for _, direction in ipairs({'horizontal','vertical'}) do
        for _, locked in ipairs({true,false}) do
            hud.cancel_gesture();
            local settings,p,view = setup(mode,direction,'self_buffs','XI View');
            p.locked = locked;
            local original = store.copy(p);
            local saves = 0;
            local callbacks = {shift=true,changed=function()end,save=function()saves=saves+1;end};
            MOCK.mouse_x,MOCK.mouse_y,MOCK.mouse_down,clicked = p.x+p.width-1,p.y+p.height_limit-1,true,true;
            draw(settings,view,callbacks);
            MOCK.mouse_x,MOCK.mouse_y = MOCK.mouse_x+80,MOCK.mouse_y+70;
            draw(settings,view,callbacks);
            MOCK.mouse_down = false;
            draw(settings,view,callbacks);
            if locked then assert(custom.equal(p,original) and saves==0, 'Shift never bypasses a saved timer-panel lock');
            else
                assert(p.width==original.width+80 and p.height_limit==original.height_limit+70 and saves==1,
                    'Unlocked Shift corner resize changes both dimensions and saves once');
                assert(p.stack_direction==direction and settings.style.icon_size==24 and p.wrap,
                    'Resizing retains stacking direction, selected icon size, and text wrapping');
            end;
        end;
    end;
end;
MOCK.mouse_down,MOCK.mouse_x,MOCK.mouse_y = false,-1,-1;
imgui.IsItemHovered = function() return false; end;
imgui.IsMouseClicked = function() return false; end;

local saved = defaults.make();
saved.panels.self_buffs.mode, saved.panels.self_buffs.stack_direction = 'icons', nil;
saved.panels.spell_recasts.mode, saved.panels.spell_recasts.stack_direction = 'icons', 'vertical';
local loaded = defaults.tidy(saved);
assert(loaded.panels.self_buffs.mode == 'icons' and loaded.panels.self_buffs.stack_direction == 'horizontal',
    'Icon tiles keep their saved mode key and horizontal ordering');
assert(loaded.panels.spell_recasts.stack_direction == 'vertical', 'An explicit icon stack direction survives normalization');
assert(custom.equal(defaults.tidy(store.copy(loaded)),loaded), 'A timer layout is stable across reloads');
local profiles = require('core.profiles').new(MOCK_INSTALL_PATH .. '/config/addons/vantage/timer-stack');
loaded.panels.self_buffs.item_width = 193;
assert(profiles:save_new('Stack layout',loaded));
local receiver = defaults.make();
assert(profiles:load('Stack layout',receiver));
assert(receiver.panels.self_buffs.mode == 'icons' and receiver.panels.self_buffs.stack_direction == 'horizontal'
    and receiver.panels.self_buffs.item_width == 193, 'Named profiles preserve direction and preferred bar width');
assert(profiles:save_layout(loaded,'placement'));
receiver = defaults.make();
receiver.panels.self_buffs.mode = 'bars';
assert(profiles:load_layout(receiver,'placement'));
assert(receiver.panels.self_buffs.stack_direction == 'horizontal' and receiver.panels.self_buffs.item_width == 193
    and receiver.panels.self_buffs.mode == 'bars', 'Shared placement carries stacking geometry without changing the selected display mode');
custom.reset(receiver,'layouts');
assert(receiver.panels.self_buffs.stack_direction == 'horizontal' and receiver.panels.self_buffs.item_width == 280,
    'Reset layout restores the stacking defaults');

local window = require('ui.settings_window');
local panels = require('ui.panel_frame');
local editor = defaults.make();
editor.window.open, editor.window.tab, editor.recast_display = true,'Display','combined';
local active_combo, choices = nil, {};
local selectable = imgui.Selectable;
imgui.BeginCombo = function(label) return not active_combo or label == '##frame_' .. active_combo; end;
imgui.Selectable = function(label, ...) choices[label] = true; return selectable(label,...); end;
local callbacks = {changed=function()end,save=function()return true;end,now=function()return 100;end};
for _, id in ipairs({'self_buffs','recasts'}) do
    local found = false;
    for _, result in ipairs(window.search('Stack direction')) do
        if result.tab == 'Display' and result.label == 'Fills' and result.panel == id then found = true; end;
    end;
    assert(found,'Stack direction is searchable before opening '..id);
    local p = editor.panels[id];
    p.show_name,p.show_time,p.show_fill,p.show_heading = false,false,false,false;
    p.field_labels.name,p.colors.track,p.bar_style = 'Effect:',{.1,.2,.3,.4},'rail';
    local fields = store.copy(p);
    for _, spec in ipairs({{'Layout','show','Icons##icons','mode','icons'},
        {'Fills','place','To the right, then down##right_down','stack_direction','horizontal'},
        {'Fills','place','Down, then to the right##down_right','stack_direction','vertical'},
        {'Layout','show','Bars##bars','mode','bars'}}) do
        panels.open(id,spec[2]);
        active_combo,choices = spec[1],{};
        MOCK.clicks[spec[3]] = true;
        window.draw(editor,hud.sample(100),callbacks);
        fields[spec[4]] = spec[5];
        assert(p[spec[4]] == spec[5] and custom.equal(p,fields), 'The selected layout control preserves all other bar choices');
        if spec[1]=='Layout' then
            assert(choices['Icons##icons'] and not choices['Icon tiles##icons'], 'Layout offers Icons under the preserved icons key');
        end;
        assert(#MOCK.font_stack == 0);
    end;
end;
return 'Timer modes wrap in either direction with icons-only countdowns and locked placement';
