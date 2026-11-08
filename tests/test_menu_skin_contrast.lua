local defaults,theme,appearance=require('ui.defaults'),require('ui.theme'),require('ui.appearance');
local copy,equal=require('core.store').copy,require('core.customization').equal;
local imgui=require('imgui');
local backgrounds={'boxes','boxes_hovered','boxes_clicked','buttons','buttons_hovered','buttons_pressed',
    'dropdowns','row_picked','row_hovered','row_clicked'};
local painted,stack={},{};
for _,entry in ipairs(theme.WINDOW_COLORS)do
    if entry.paints then _G['ImGuiCol_'..entry.paints]=entry.paints;end;
    if entry.also then _G['ImGuiCol_'..entry.also]=entry.also;end;
end;
imgui.PushStyleColor=function(key,value)
    stack[#stack+1]=key;painted[key]=copy(value);
end;
imgui.PopStyleColor=function(count)for _=1,count do table.remove(stack);end;end;
local function luminance(value)
    local channels={};
    for i=1,3 do channels[i]=value[i]<=.04045 and value[i]/12.92 or ((value[i]+.055)/1.055)^2.4;end;
    return .2126*channels[1]+.7152*channels[2]+.0722*channels[3];
end;
local function contrast(ink,fill)
    local a,b=luminance(ink),luminance(fill);
    return (math.max(a,b)+.05)/(math.min(a,b)+.05);
end;
local function inspect(settings,label)
    local saved=copy(settings);local look=theme.window(settings);
    painted={};local count=theme.push(settings,look);
    assert(count==#stack and count>30,'Every skin applies all available menu states, including selected and hovered rows.');
    for _,entry in ipairs(theme.WINDOW_COLORS)do
        if entry.paints then assert(equal(painted[entry.paints],theme.window_paint(look,entry.key)),
            'Actual ImGui style uses the resolved '..label..' '..entry.key..' color.');end;
    end;
    for _,key in ipairs(backgrounds)do
        assert(contrast(look.text,theme.window_paint(look,key))>=4.5,
            label..' '..key..' keeps readable text when selected, focused, hovered or pressed.');
    end;
    assert(contrast(look.on_chip_text,look.on_chips)>=4.5,'Enabled-chip text retains its dedicated contrasting ink.');
    theme.pop(count);assert(#stack==0,'Every skin balances its menu color stack.');
    assert(equal(settings,saved),'Resolving and painting a menu never writes any saved setting.');
    return look;
end;

MENU_CONTRAST_CASES=0;
for _,skin in ipairs(appearance.names)do
    local settings=defaults.make();assert(appearance.apply(settings,skin));
    inspect(settings,skin);MENU_CONTRAST_CASES=MENU_CONTRAST_CASES+1;
    assert(theme.window(settings).theme==(skin=='XI View' and 'Original FFXI' or skin));
end;
for kind=1,8 do
    local settings=defaults.make();assert(appearance.apply(settings,'Original FFXI',{window_type=kind}));
    local look=inspect(settings,'Original FFXI '..kind);
    local original=theme.window_defaults({style={theme='Original FFXI',window_type=kind}});
    for _,entry in ipairs(theme.WINDOW_COLORS)do assert(equal(look[entry.key],original[entry.key]),
        'All eight native menu palettes keep every original color.');end;
    MENU_CONTRAST_CASES=MENU_CONTRAST_CASES+1;
end;

-- Custom source colors stay literal.
local custom={.94,.81,.23,.71};
for _,skin in ipairs({'Mint','High contrast','Ember'})do
    local settings=defaults.make();assert(appearance.apply(settings,skin));
    settings.style.estimate_color=copy(custom);
    local saved=copy(settings);local look=theme.window(settings);
    assert(equal(look.buttons_pressed,custom) and equal(settings,saved),
        'A custom pressed-state source remains exactly as chosen.');
    settings.style.border_color=copy(custom);look=theme.window(settings);
    assert(equal(look.boxes_hovered,custom) and equal(look.row_clicked,custom) and equal(look.buttons_hovered,custom),
        'Custom border colors remain literal for every derived state.');
end;
for _,skin in ipairs({'Mint','High contrast','Ember'})do
    local settings=defaults.make();assert(appearance.apply(settings,skin));
    settings.style.estimate_color[1]=settings.style.estimate_color[1]+.001;
    local saved=copy(settings);local look=theme.window(settings);
    assert(equal(look.buttons_pressed,settings.style.estimate_color) and equal(settings,saved),
        'A color only .001 from stock remains an explicit literal override.');
end;

assert(MENU_CONTRAST_CASES==18 and #MOCK.commands==0);
