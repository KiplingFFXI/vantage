-- Overhead icons in its order, tab by tab: the units first in two columns, then what the kind picked has, and what a kind
-- has on each tab under one shared picker, with the offsets in a fold on Place that starts closed. The five sliders that
-- only changed the guess are off the panel while their keys, values and /vg set stay. The fold keeps its open state, and
-- a typed search opens it.
local store=require('core.store');
local SNAP={valid=true,id=1001,name='Tester',zone=102,job=3,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(SNAP);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,status=function()return {active=false};end};
local imgui=require('imgui');
local defaults=require('ui.defaults');
local app=dofile(ADDON_DIR..'/vantage.lua');
local window=require('ui.settings_window');
local page=require('ui.overhead_settings');
MOCK.fire('load');app.refresh(0);

-- A header opens as the window asks, as a real one does, and toggle is the player clicking it.
local FOLD='If icons sit too high or too low##Head offsets by name';
local next_open,toggle,query,slider=nil,{},nil,nil;
imgui.SetNextItemOpen=function(value) next_open=value;end;
imgui.CollapsingHeader=function(label)
    MOCK.imgui_calls[#MOCK.imgui_calls+1]={'CollapsingHeader',label};
    local value=next_open;
    if toggle[label]~=nil then value,toggle[label]=toggle[label],nil;end;
    return value;
end;
local input_with_hint=imgui.InputTextWithHint;
imgui.InputTextWithHint=function(label,hint,value,...)
    if label=='##find_settings' and query~=nil then value[1]=query;end;
    return input_with_hint(label,hint,value,...);
end;
imgui.SliderFloat=function(label,value)
    if slider and slider[1]==label then value[1],slider=slider[2],nil;return true;end;
    return false;
end;
local view={rows={},context={valid=true,job=3,target={id=0x1000100,name='Crab',kind='monster'},entities={}}};
local function frame()
    MOCK.imgui_calls={};
    window.draw(app.state.settings,view,app.callbacks);
end;
local panels=require('ui.panel_frame');
-- A fresh save on Overhead icons with Mobs picked, each fold as it starts unless opened says otherwise.
local function begin(opened,tab)
    local s=defaults.tidy(defaults.make());
    s.window.open,s.window.tab=true,'Display';
    panels.open('overhead',tab or 'show');
    for name,open in pairs(opened or {})do s.window.sections['Overhead/'..name]=open;end;
    page._selection.kind='mob';
    app.state.settings=s;
    query=nil;
    frame();
    return s;
end;
local ALL={['Lit icons']=true,['Head offsets by name']=true};
-- What the tab drew, top to bottom, after the row of tabs.
local function tab_labels()
    local out,started={},false;
    for _,call in ipairs(MOCK.imgui_calls)do
        local label;
        if call[1]=='TextColored' then label=call[3];
        elseif call[1]=='TextWrapped' or call[1]=='TextUnformatted' or call[1]=='CollapsingHeader' or call[1]=='Checkbox' or call[1]=='Button' or call[1]=='ColorEdit4' then
            label=call[2];
        end;
        if started and label then out[#out+1]=(label:gsub('##frame.*$',''));end;
        started=started or label=='When to show##frame_tab';
    end;
    return out;
end;
local function has(labels,wanted)
    for _,label in ipairs(labels)do if label==wanted then return true;end;end;
    return false;
end;
local function found(text,label)
    for _,result in ipairs(window.search(text))do if result.panel=='overhead' and result.label==label then return true;end;end;
    return false;
end;
local function joined(...)
    local out={};
    for _,list in ipairs({...})do for _,label in ipairs(list)do out[#out+1]=label;end;end;
    return out;
end;
local KIND='Change the settings for';
local WHO={'Show icons over','Your target','Your subtarget','Mobs your party claimed','Watched mobs','Mobs your party debuffed','Party members',
    'Alliance members','Other players','Your pet','Other players\' pets','You','No mobs are watched now.','Watch my target','Most units at once','Farthest away','Fade starts at',
    'Faded opacity','Only your target and party in towns'};
local function show_tab(light)
    local out=joined(WHO,{KIND,'Layout','Icons shown','Show countdowns','Show'});
    if light then out[#out+1]=light;end;
    return out;
end;
local PLACE={'Icons follow how big the unit is on screen: its distance from the camera, and its size from Phoenix hitboxes. Size on the main page scales them too.',
    'Icon size','Smallest','Largest','Bigger on your target','Shrink with distance','Bigger units get bigger icons',
    'Countdowns go inside icons under',KIND,'Icon size for this kind','Where the icons sit','Gap above the name','Space between icons',FOLD,
    'Head height offset','Across','Down',
    'For one unit, by its exact name. /vg overhead calibrate prints your target\'s head height and where it comes from.','Unit name',
    'Use my target\'s name','Add head offset','No head offsets yet.'};
local LOOK={'Countdown color','Lit icons','Glow around lit icons','Light color'};
local SWITCHES={'Show these effects:','Corsair rolls','Bard songs','Protect and Shell','Food','Barspells','Stances','Signet and similar'};
local ALWAYS={'Always show','Copy Image','Third Eye'};
-- A kind on Debuffs only has no switches, and no buffs to narrow. Always show stays, on the kinds that have it.
local function filter_tab(switches,always)
    return joined({KIND,'Use the Hidden everywhere list','Edit the list','Only effects I cast'},switches and {'Only buffs I cast'} or {},{'Only debuffs from my party'},
        switches and SWITCHES or {},always and ALWAYS or {},{'Find an effect','Effect','Show only','Hide here','Clear this kind\'s filters'});
end;
local function same_order(kind,tab,wanted)
    local got=tab_labels();
    wanted=joined(wanted,{'Reset this display'});
    assert(table.concat(got,'\n')==table.concat(wanted,'\n'),kind..' '..tab..' drew:\n'..table.concat(got,'\n'));
end;

-- Mobs light buffs, Party, Alliance and You light debuffs, the others have no light, and a kind on Debuffs only has no
-- switch list.
for _,entry in ipairs({{'mob','Light up buffs you can remove',true},{'party','Light up debuffs you can remove',true},{'alliance','Light up debuffs you can remove',false},
    {'self','Light up debuffs you can remove',true},{'other',nil,true},{'pet',nil,true},{'other_pet',nil,true}})do
    for tab,wanted in pairs({show=show_tab(entry[2]),look=LOOK,filters=filter_tab(entry[3],require('ui.overhead_defaults').always_for[entry[1]]),place=PLACE})do
        begin(ALL,tab);
        page._selection.kind=entry[1];
        frame();
        same_order(entry[1],tab,wanted);
    end;
end;

-- Rows wait for what they change: any kind on Two lines or Split, and mobs on Split with Crowd control icon on its own.
local function row_shown(tab,label,change)
    local s=begin(ALL,tab);
    if change then change(s.overhead);end;
    app.state.settings_revision=app.state.settings_revision+1;
    frame();
    return has(tab_labels(),label);
end;
assert(not row_shown('place','Space between lines'),'No kind on Two lines, and no Party cooldowns line, has no gap between lines.');
assert(row_shown('place','Space between lines',function(o) o.types.party.layout='lines';end),'Any kind on Two lines has one.');
assert(not row_shown('place','Space between the two sides'),'No kind on Split has no gap to set.');
assert(row_shown('place','Space between the two sides',function(o) o.types.party.layout='split';end),'Any kind on Split has one.');
assert(not row_shown('place','Crowd control icon size',function(o) o.types.mob.layout,o.types.mob.cc_slot='split',false;end),'Mobs on Split with no icon of its own has no size to set.');
assert(row_shown('place','Crowd control icon size',function(o) o.types.mob.layout,o.types.mob.cc_slot='split',true;end),'With its own icon it has.');

-- The 11 ticks in one table of two columns, 6 and 5, with no Trusts.
begin(ALL);
frame();
local in_table,columns,first,count=false,0,0,0;
local opened_at;
for _,call in ipairs(MOCK.imgui_calls)do
    if call[1]=='BeginTable' and call[2]=='##overhead_units' then in_table,opened_at=true,call[3];
    elseif in_table and call[1]=='EndTable' then in_table=false;
    elseif in_table and call[1]=='TableNextColumn' then columns=columns+1;
    elseif in_table and call[1]=='Checkbox' then
        count=count+1;
        if columns==1 then first=first+1;end;
    end;
end;
assert(opened_at==2 and columns==2 and count==11 and first==6,('Show icons over fills two columns: %s %d %d %d'):format(tostring(opened_at),columns,count,first));
assert(not has(tab_labels(),'Trusts'),'There is no Trusts tick.');

-- What isn't on the panel: an Editing line, a second line in the intro and the five sliders, on every kind, layout and tab.
local SLIDERS={'Name size in the world','Largest name','Target cursor size in the world','Largest target cursor','Name height above the head'};
for _,kind in ipairs(require('ui.overhead_defaults').types)do
    for _,layout in ipairs({'single','lines','split'})do
        for _,tab in ipairs(panels.tabs)do
            local s=begin(ALL,tab.key);
            s.overhead.types[kind].layout=layout;
            app.state.settings_revision=app.state.settings_revision+1;
            page._selection.kind=kind;
            frame();
            local labels=tab_labels();
            for _,label in ipairs(SLIDERS)do assert(not has(labels,label),label..' is off the panel.');end;
            for _,label in ipairs(labels)do
                assert(not label:find('^Editing:'),'The panel has no Editing line.');
                assert(not label:find('wear-off',1,true),'The panel has no wear-off line.');
            end;
        end;
    end;
end;

-- Their keys, values and /vg set stay, and only the guess reads them.
local function command(text) local event={command=text};MOCK.fire('command',event);assert(event.blocked,text);end;
local s=begin();
local fresh=defaults.make().overhead;
assert(s.overhead.layout.name_height==fresh.layout.name_height and s.overhead.layout.name_cap==24 and s.overhead.layout.target_height==0.4
    and s.overhead.layout.target_cap==16 and s.overhead.types.party.name_lift==0.5,'The keys hold their defaults.');
command('/vg set overhead.layout.name_height 0.5');
command('/vg set overhead.layout.name_cap 30');
command('/vg set overhead.layout.target_height 0.25');
command('/vg set overhead.layout.target_cap 20');
command('/vg set overhead.types.party.name_lift 1.25');
s=app.state.settings;
assert(s.overhead.layout.name_height==0.5 and s.overhead.layout.name_cap==30 and s.overhead.layout.target_height==0.25
    and s.overhead.layout.target_cap==20 and s.overhead.types.party.name_lift==1.25,'/vg set reaches each of them.');
frame();
local kept=defaults.tidy(store.copy(app.state.settings)).overhead;
assert(kept.layout.name_height==0.5 and kept.layout.name_cap==30 and kept.layout.target_height==0.25 and kept.layout.target_cap==20
    and kept.types.party.name_lift==1.25,'A value set that way stays through the page and a load.');

-- The fold is closed at first, with nothing in it drawn.
s=begin(nil,'place');
frame();
local labels=tab_labels();
assert(has(labels,FOLD),'The fold is on Size and place.');
for _,label in ipairs({'Head height offset','Across','Down','Unit name','Add head offset'})do
    assert(not has(labels,label),label..' waits in the closed fold.');
end;
assert(s.window.sections['Overhead/Head offsets by name']==nil,'Drawing it saves nothing.');
-- Opening it saves under the section's name, and no other key comes in.
toggle[FOLD]=true;
frame();
assert(app.state.settings.window.sections['Overhead/Head offsets by name']==true,'The fold saves under its section name.');
for key in pairs(app.state.settings.window.sections)do assert(not key:find('too high',1,true),'No key under its label: '..key);end;
-- A save that had Head offsets by name open or closed keeps that.
begin({['Head offsets by name']=true},'place');
frame();
assert(has(tab_labels(),'Head height offset'),'A fold saved open is open.');
begin({['Head offsets by name']=false},'place');
frame();
assert(not has(tab_labels(),'Head height offset'),'A fold saved closed is closed.');
-- A typed search opens it, as other sections do, and clearing it closes it again without a save.
s=begin(nil,'place');
query='head height';
frame();
frame();
labels=tab_labels();
assert(has(labels,'Head height offset') and has(labels,'Unit name'),'A search opens the fold.');
assert(s.window.sections['Overhead/Head offsets by name']==nil,'A search saves nothing.');
query='';
frame();
assert(not has(tab_labels(),'Head height offset'),'With the search cleared the fold is closed again.');

-- The offsets write the kind picked.
s=begin({['Head offsets by name']=true},'place');
page._selection.kind='party';
frame();
slider={'##frame_Head height offset',0.75};
frame();
assert(app.state.settings.overhead.types.party.world_offset==0.75 and app.state.settings.overhead.types.mob.world_offset==0,'The offset is for the kind picked.');
slider={'##frame_Across',-40};
frame();
slider={'##frame_Down',25};
frame();
local party=app.state.settings.overhead.types.party;
assert(party.screen_x==-40 and party.screen_y==25,'So are the pixels.');

-- Search leads each label to where it sits, and other words to its row.
begin();
for _,label in ipairs({'Only effects I cast','Head height offset','Across','Down',
    'If icons sit too high or too low','Unit name','Add head offset'})do
    assert(found(label,label),'Search finds '..label..'.');
end;
assert(found('Crowd control icon size','Layout'),'While it waits for Split, its name leads to the pick that shows it.');
assert(found('Filters for this type','Only effects I cast'),'Filters for this type finds the first filter row.');
assert(found('Head offsets by name','If icons sit too high or too low'),'The section name finds the fold.');
assert(not found('Head offsets by name','Head offsets by name'),'The section name is no result of its own.');
for _,label in ipairs(SLIDERS)do assert(not found(label,label),'Search does not find '..label..'.');end;

-- Lit icons starts closed like the fold on Place, a typed search opens it, and its two rows say the party list icons use
-- them.
begin(nil,'look');
frame();
local labels=tab_labels();
assert(has(labels,'Lit icons') and not has(labels,'Glow around lit icons') and not has(labels,'Light color'),'Lit icons starts closed.');
begin(nil,'look');
query='Light color';
frame();
frame();
assert(has(tab_labels(),'Light color'),'A typed search opens it.');
query='';
frame();
local hovered=imgui.IsItemHovered;
imgui.IsItemHovered=function() return true;end;
begin(ALL,'look');
imgui.IsItemHovered=hovered;
local told=0;
for _,label in ipairs(tab_labels())do if label=='The party list icons use this too.' then told=told+1;end;end;
assert(told==2,'Both rows say so: '..told);
assert(found('The party list icons use this too','Glow around lit icons'),'The search reads the help on the glow row.');
assert(not found('For every unit type, and the party list icons','Glow around lit icons'),'The search reads only the help the row has.');

-- Each section's open state stays when a save loads.
local saved=defaults.make();
saved.window.sections['Overhead/Head offsets by name']=true;
saved.window.sections['Overhead/Unit type']=false;
local loaded=defaults.tidy(saved);
assert(loaded.window.sections['Overhead/Head offsets by name']==true and loaded.window.sections['Overhead/Unit type']==false,'They stay.');
return 'Overhead icons is in its order, with the guess sliders off it and the offsets in a fold';
