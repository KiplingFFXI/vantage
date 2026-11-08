package.loaded['ui.icons']={status=function(id)return 1000+id;end};
local defaults,hud,tracker=require('ui.defaults'),require('ui.hud'),require('core.tracker');
local visible=require('visible_icons');
local window=require('ui.settings_window');
local panels=require('ui.panel_frame');
local store,custom,imgui=require('core.store'),require('core.customization'),require('imgui');
local copy,equal=store.copy,custom.equal;
local settings=defaults.make();
settings.style.font,settings.style.font_size,settings.style.scale='Ashita',14,1;
settings.window.open=true;
for id,p in pairs(settings.panels) do
    p.enabled=id=='self_buffs' or id=='self_debuffs' or id=='target';
    p.show_heading,p.width,p.max_rows=false,240,32;
end;
MOCK.screen,MOCK.content_width={1600,1000},1200;
local snapshot={valid=true,id=1001,name='Self',zone=102,self_known=true,party={},entities={},
    target={id=1001,kind='player',name='Self'},self_effects={
        {effect=33,slot=0,deadline=400},{effect=269,slot=1},
        {effect=13,slot=2,deadline=500},{effect=4,slot=3},
    }};
local tracked=tracker.new();
local view;
local function refresh()
    tracked:reconcile(snapshot,100);view=tracked:view(100,settings,snapshot);
    assert(#view.rows==4 and view.self_known, 'Self effects remain tracked independently of target visibility.');
    for _,row in ipairs(view.rows)do assert(row.scope=='self' and row.entity_id==1001 and row.present);end;
end;
refresh();
local begun,controls,body_started={},{},false;
local begin,checkbox,button=imgui.Begin,imgui.Checkbox,imgui.Button;
imgui.Begin=function(name,...)begun[name]=true;return begin(name,...);end;
imgui.Checkbox=function(label,...)
    local readable=label:gsub('^##','');
    controls[#controls+1]={label=readable,body=body_started};
    return checkbox(label,...);
end;
imgui.Button=function(label,...)
    if label=='Show##frame_tab' then body_started=true;end;
    return button(label,...);
end;
imgui.BeginCombo=function()return false;end;
local changes={};
local callbacks={editor_changed=function()end,save=function()return true;end,
    changed=function(phase,label)changes[#changes+1]={phase=phase,label=label,value=custom.history_value(settings)};end};
local function ui(page,label,selected_panel)
    settings.window.tab=page;controls,body_started,changes={},false,{};MOCK.clicks={};
    if selected_panel then panels.open(selected_panel,'show');end;
    if label then MOCK.clicks[label]=true;end;
    window.draw(settings,view,callbacks);
    assert(not label or not MOCK.clicks[label], 'The requested visibility control was displayed: '..tostring(label));
    assert(#MOCK.font_stack==0);
end;
local function only_change(expected,description)
    assert(equal(custom.history_value(settings),expected),description);
    local labels={};for _,change in ipairs(changes)do labels[#labels+1]=change.phase..':'..tostring(change.label);end;
    assert(#changes==2 and changes[1].phase=='before' and changes[2].phase=='after',
        'Each visibility switch remains one Undo transaction: '..table.concat(labels,','));
end;
-- Whether a self panel shows an effect's icon in full this frame.
local function shows(effect)
    for _,icon in ipairs(visible(function(texture)return texture==1000+effect;end))do
        if icon.window=='##vantage_self_buffs' or icon.window=='##vantage_self_debuffs' then return true;end;
    end;
    return false;
end;
local function render(buff,debuff,target_panel)
    begun={};local before=copy(view);
    MOCK.imgui_calls={};
    hud.draw(view,settings,100,{});
    assert(not not begun['##vantage_self_buffs']==buff, 'Self buff window visibility is independent.');
    assert(not not begun['##vantage_self_debuffs']==debuff, 'Self debuff window visibility is independent.');
    assert(not not begun['##vantage_target']==target_panel, 'Target timer panel follows only its own choice and selected entity.');
    assert(equal(view,before), 'Rendering and visibility filters never mutate shared tracker data.');
    -- A self panel that is on shows your own effects, with or without durations.
    for _,effect in ipairs({33,269})do assert(shows(effect)==buff, 'Known buff icons show even without durations.');end;
    for _,effect in ipairs({13,4})do assert(shows(effect)==debuff, 'Known debuff icons show even without durations.');end;
    assert(#MOCK.font_stack==0);
end;

for _,mode in ipairs({'bars','icons'}) do
    for _,id in ipairs({'self_buffs','self_debuffs','target'})do settings.panels[id].mode=mode;end;
    settings.enabled=true;settings.panels.target.enabled=true;
    snapshot.target={id=1001,kind='player',name='Self'};refresh();
    assert(#hud.filter_rows(view,settings.panels.self_buffs,'self_buffs',settings)==2);
    assert(#hud.filter_rows(view,settings.panels.self_debuffs,'self_debuffs',settings)==2);
    assert(#hud.filter_rows(view,settings.panels.target,'target',settings)==4, 'Self targeting can show the same effects in the independent target panel.');
    render(true,true,true);
    local expected=custom.history_value(settings);expected.panels.target.enabled=false;
    ui('Display','On##frame_display','target');
    only_change(expected, 'The Target panel header switch hides only the selected target panel.');
    local found,sample_index,visibility_index=0,nil,nil;
    for index,control in ipairs(controls)do
        if control.label=='On##frame_display' then found=found+1;visibility_index=index;assert(not control.body,'The scoped visibility control is in the header.');end;
        if control.label=='Show samples##frame' then sample_index=index;end;
    end;
    assert(found==1,'The selected-panel visibility switch appears once.');
    assert(sample_index and visibility_index<sample_index,'The scoped visibility switch comes before Show samples in the header.');
    refresh();render(true,true,false);
    snapshot.target={id=2002,name='Other player',kind='player'};refresh();
    render(true,true,false);
    settings.panels.target.enabled=true;
    render(true,true,false);
    snapshot.target={id=1001,name='Self',kind='player'};refresh();
    render(true,true,true);
    expected=custom.history_value(settings);expected.panels.target.enabled=false;
    ui('Home','Target timers##main_target');
    only_change(expected,'The main page\'s Target timers switch remains independent while self is selected.');
    render(true,true,false);
    expected=custom.history_value(settings);expected.panels.self_buffs.enabled=false;
    ui('Display','On##frame_display','self_buffs');
    only_change(expected,'Self buffs can be hidden without changing Self debuffs.');
    render(false,true,false);
    ui('Display','On##frame_display','self_buffs');render(true,true,false);
    expected=custom.history_value(settings);expected.panels.self_debuffs.enabled=false;
    ui('Display','On##frame_display','self_debuffs');
    only_change(expected,'Self debuffs can be hidden without changing Self buffs.');
    render(true,false,false);
    ui('Display','On##frame_display','self_debuffs');render(true,true,false);
end;

settings.panels.ability_recasts.enabled=true;
settings.panels.spell_recasts.enabled=false;
local choices=copy(settings.panels);
-- A pause comes from a save or /vg set, and the main page's paused line resumes it.
settings.enabled=false;
assert(equal(settings.panels,choices),'Global pause preserves every individual timer and recast choice.');
render(false,false,false);
local expected=custom.history_value(settings);expected.enabled=true;
ui('Home','Resume##main_resume');
only_change(expected,'Global resume restores the previously selected panels.');
assert(equal(settings.panels,choices));render(true,true,false);
settings.enabled=false;
expected=custom.history_value(settings);expected.enabled,expected.panels.target.enabled=true,true;
ui('Display','On##frame_display','target');
only_change(expected,'Enabling one panel still resumes timers without changing the other panel choices.');
render(true,true,true);
expected=custom.history_value(settings);expected.panels.target.enabled=false;
ui('Display','On##frame_display','target');
only_change(expected,'Disabling the resumed target panel never pauses self timers.');
render(true,true,false);

-- A recast panel has one switch of its own, in the header.
ui('Display',nil,'ability_recasts');
local count=0;
for _,control in ipairs(controls)do
    if control.label=='On##frame_display' then count=count+1;end;
end;
assert(count==1,'Recasts has one switch for the selected panel.');
expected=custom.history_value(settings);expected.panels.ability_recasts.enabled=false;
ui('Display','On##frame_display','ability_recasts');
only_change(expected,'The recast panel switch cannot pause status panels.');render(true,true,false);
local found=false;
for _,result in ipairs(window.search('Choose visible displays'))do
    found=found or result.tab=='Home' and result.label=='What to show';
end;
assert(found,'Choose visible displays finds What to show on the main page.');
assert(settings.panels.self_buffs.locked and settings.panels.self_debuffs.locked and settings.panels.target.locked,
    'Visibility changes do not bypass any saved lock.');
assert(#view.rows==4 and #MOCK.commands==0);
return 'Self-targeting keeps self timers independent from the target panel and explicit global pause.';
