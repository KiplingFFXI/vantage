-- The Overhead icons panel and the main page's overhead switch, in the real settings window through vantage.lua. Each control
-- writes its own key in settings.overhead as one Undo step named for it, and nothing outside settings.overhead
-- changes; Undo puts it back and Redo does it again. Change the settings for picks the kind the controls write and
-- writes nothing. The effect filter editor keeps the kind's lists sorted and adds no pins or order. Search finds the
-- panel, its controls and the main page's switch before the panel is opened. Neither the panel nor search has a switch
-- that moves overlapping blocks up or its steps, and searching for stack lists nothing there. Every countdown has
-- one time format, so the panel offers no choice of it and search finds none there. Show these effects lists the same
-- seven switches on every kind in two columns, and goes while the kind shows debuffs only, when search leads to Show
-- instead. Mobs offer the light for buffs and Party, Alliance and You the one for debuffs, the others neither, and
-- the search leads to the picker while the kind picked lacks it.
local store=require('core.store');
local SNAP={valid=true,id=1001,name='Tester',zone=102,job=3,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(SNAP);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,status=function()return {active=false};end};
local imgui=require('imgui');
local defaults=require('ui.defaults');
local custom=require('core.customization');
local copy=store.copy;
local app=dofile(ADDON_DIR..'/vantage.lua');
local window=require('ui.settings_window');
local page=require('ui.overhead_settings');
MOCK.fire('load');app.refresh(0);

-- Search finds the panel and its controls before it is ever drawn. tab says it is a page, not the panel.
local function found(query,label,tab)
    for _,result in ipairs(window.search(query))do
        if result.label==label and (tab and result.tab==tab or not tab and result.panel=='overhead') then return true;end;
    end;
    return false;
end;
local KIND,SHOW_ROW='Change the settings for','Show buffs or debuffs';
assert(found('overhead','Buffs and debuffs above heads'),'Search names Overhead icons.');
for _,entry in ipairs({{'Crowd control slot','Layout'},{'Distance cap','Farthest away'},{'Light up buffs','Light up buffs you can remove'},
    {'Glow around lit icons','Glow around lit icons'},{'Glow around lit buffs','Glow around lit icons'},
    {'Light up debuffs',KIND},{'cursna',KIND},
    {'Head offsets by name','If icons sit too high or too low'},{'Unit type to edit',KIND},{'Overhead icon size','Icon size'},{'Show overhead icons','Show this display'},
    {'Include for this type','Find an effect'},{'Overhead icons','Overhead icons','Home'},{'Edit Overhead icons','Edit Overhead icons','Home'}})do
    assert(found(entry[1],entry[2],entry[3]),'Search finds '..entry[2]..' for '..entry[1]..' before it is drawn.');
end;
assert(#window.search('trusts')==0,'Search finds nothing for trusts.');
-- The effect switches, by label and by what a player would type.
local LIST={'Corsair rolls','Bard songs','Protect and Shell','Food','Barspells','Stances','Signet and similar'};
local words={{'rolls','Corsair rolls'},{'cor','Corsair rolls'},{'songs','Bard songs'},{'bard','Bard songs'},{'protect','Protect and Shell'},
    {'shell','Protect and Shell'},{'food','Food'},{'bar','Barspells'},{'hasso','Stances'},{'seigan','Stances'},{'stance','Stances'},
    {'signet','Signet and similar'},{'reraise','Signet and similar'},{'Leave out the usual long effects','Show these effects:'},
    {'Show these effects','Show these effects:'}};
local function search_finds_switches(when)
    for _,label in ipairs(LIST)do assert(found(label,label),'Search finds '..label..' '..when);end;
    for _,entry in ipairs(words)do assert(found(entry[1],entry[2]),'Search for '..entry[1]..' finds '..entry[2]..' '..when);end;
end;
search_finds_switches('before the panel is drawn.');

local combo,slider,typed,colored,color_labels;
imgui.BeginCombo=function(label) return label==combo;end;
imgui.SliderFloat=function(label,value)
    if slider and slider[1]==label then value[1],slider=slider[2],nil;return true;end;
    return false;
end;
imgui.ColorEdit4=function(label,value)
    if color_labels then color_labels[label]=true;end;
    if colored and colored[1]==label then for i=1,4 do value[i]=colored[2][i];end;colored=nil;return true;end;
    return false;
end;
local input,input_with_hint=imgui.InputText,imgui.InputTextWithHint;
local function typing(label,value,...)
    if typed and typed[1]==label then value[1],typed=typed[2],nil;return true;end;
    return false;
end;
imgui.InputText=function(label,value,...) if typing(label,value) then return true;end;return input(label,value,...);end;
imgui.InputTextWithHint=function(label,hint,value,...) if typing(label,value) then return true;end;return input_with_hint(label,hint,value,...);end;
local view={rows={},context={valid=true,job=3,target={id=0x1000100,name='Crab',kind='monster'},entities={}}};
local function frame(step)
    step=step or {};
    combo,slider,typed,colored=step.combo,step.slider,step.typed,step.color;
    if step.click then MOCK.clicks[step.click]=true;end;
    window.draw(app.state.settings,view,app.callbacks);
    assert(not step.click or not MOCK.clicks[step.click],'The control is on the page: '..tostring(step.click));
    assert(not slider and not typed and not colored,'The control is on the page: '..tostring(step.slider and step.slider[1] or step.typed and step.typed[1]
        or step.color and step.color[1]));
    MOCK.clicks={};
end;
local panels=require('ui.panel_frame');
local sections={'Lit icons','Head offsets by name'};
local function begin(tab,setup)
    local s=defaults.tidy(defaults.make());
    s.window.open,s.window.tab=true,tab=='Home' and 'Home' or 'Display';
    if tab~='Home' then panels.open('overhead',tab);end;
    for _,name in ipairs(sections)do s.window.sections['Overhead/'..name]=true;end;
    page._selection.kind='mob';
    app.state.settings=s;
    if setup then setup(s.overhead,s);end;
    app.state.settings_revision=app.state.settings_revision+1;
    frame();
    app.state.history,app.state.redo,app.state.transaction={},{},nil;
    return copy(s);
end;
local function click(label) return {{click=label}};end;
local function slide(label,value) return {{slider={'##frame_'..label,value}}};end;
local function pick(label,shown,value) return {{combo='##frame_'..label,click=shown..'##'..value}};end;
local function color(label,value) return {{color={label,value}}};end;
-- The kind picked first, then the control.
local function as(kind,shown,steps)
    local out={{combo='##frame_'..KIND,click=shown..'##'..kind}};
    for _,step in ipairs(steps)do out[#out+1]=step;end;
    return out;
end;
local function flipped(get) return function(o,b) return get(o)~=get(b);end;end;
local function same_list(list,values)
    if #list~=#values then return false;end;
    for i=1,#values do if list[i]~=values[i] then return false;end;end;
    return true;
end;
local function both_on(o) o.enabled,o.preview=true,true;end;

-- The panel has neither control, and the settings have neither key: a click on the switch and the slider for its
-- steps go unused, and nothing changes.
for _,tab in ipairs(panels.tabs)do
    begin(tab.key);
    MOCK.clicks['Move overlapping blocks up##frame']=true;
    slider={'##frame_Steps up',5};
    window.draw(app.state.settings,view,app.callbacks);
    assert(MOCK.clicks['Move overlapping blocks up##frame'] and slider and app.state.settings.overhead.stack==nil
        and app.state.settings.overhead.stack_steps==nil and #app.state.history==0,'The panel has no switch to move overlapping blocks up and no steps.');
    MOCK.clicks,slider={},nil;
end;
-- { name, setup, steps, check(overhead, overhead before), Undo label, tab or page }
local function on(o) o.enabled=true;end;
local function lines(o) o.types.mob.layout='lines';end;
local function split(o) o.types.mob.layout='split';end;
local rows={
    {'Show',nil,click('On##frame_display'),function(o) return o.enabled and not o.preview;end,'Show this display'},
    {'Show off ends the samples',both_on,click('On##frame_display'),function(o) return not o.enabled and not o.preview;end,'Show this display'},
    {'Show samples',on,click('Show samples##frame'),function(o) return o.preview and o.enabled;end,'Show samples'},
    {'Most units at once',nil,slide('Most units at once',16),function(o) return o.max_units==16;end,'Most units at once'},
    {'Farthest away',nil,slide('Farthest away',50),function(o) return o.distance_cap==50 and o.fade_start==20;end,'Farthest away'},
    {'Farthest away under the fade',nil,slide('Farthest away',12),function(o) return o.distance_cap==12 and o.fade_start==12;end,'Farthest away'},
    {'Fade starts at',nil,slide('Fade starts at',25),function(o) return o.fade_start==25;end,'Fade starts at'},
    {'Faded opacity',nil,slide('Faded opacity',0.25),function(o) return o.fade_alpha==0.25;end,'Faded opacity'},
    {'Only your target and party in towns',nil,click('Only your target and party in towns##frame'),function(o) return o.hide_in_cities==false;end,'Only your target and party in towns'},
    {'Layout of the kind picked',nil,as('party','Party',pick('Layout','Two lines','lines')),
        function(o) return o.types.party.layout=='lines' and o.types.mob.layout=='single';end,'Layout'},
    {'Icons shown',nil,slide('Icons shown',12),function(o) return o.types.mob.limit==12;end,'Icons shown'},
    {'Debuffs shown on two lines',function(o) o.types.alliance.layout='lines';end,as('alliance','Alliance',slide('Debuffs shown_lines',5)),
        function(o) return o.types.alliance.line_debuffs==5 and o.types.alliance.split_debuffs==6;end,'Debuffs shown'},
    {'Buffs shown on two lines',lines,slide('Buffs shown_lines',3),function(o) return o.types.mob.line_buffs==3;end,'Buffs shown'},
    {'Swap the lines',lines,click('Swap the lines##frame'),function(o) return o.types.mob.swap_lines;end,'Swap the lines'},
    {'Buffs shown in Split',split,slide('Buffs shown_split',2),
        function(o) return o.types.mob.split_buffs==2 and o.types.mob.line_buffs==4;end,'Buffs shown'},
    {'Debuffs shown in Split',split,slide('Debuffs shown_split',7),function(o) return o.types.mob.split_debuffs==7;end,'Debuffs shown'},
    {'Swap the sides',split,click('Swap the sides##frame'),function(o) return o.types.mob.swap_sides;end,'Swap the sides'},
    {'Crowd control icon on its own',split,click('Crowd control icon on its own##frame'),function(o) return o.types.mob.cc_slot==false;end,'Crowd control icon on its own'},
    {'Show countdowns',nil,as('other_pet','Other players\' pets',click('Show countdowns##frame')),function(o) return o.types.other_pet.countdown==false and o.types.mob.countdown;end,'Show countdowns'},
    {'Icon size for this kind',nil,slide('Icon size for this kind',1.5),function(o) return o.types.mob.size_scale==1.5;end,'Icon size for this kind','place'},
    {'Head height offset',nil,slide('Head height offset',0.75),function(o) return o.types.mob.world_offset==0.75;end,'Head height offset','place'},
    {'Across',nil,as('pet','Your pet',slide('Across',-40)),function(o) return o.types.pet.screen_x==-40;end,'Across','place'},
    {'Down',nil,slide('Down',25),function(o) return o.types.mob.screen_y==25;end,'Down','place'},
    {'Light up buffs you can remove',nil,click('Light up buffs you can remove##frame'),function(o) return o.dispel_light==false;end,'Light up buffs you can remove'},
    {'Light up debuffs you can remove',nil,as('party','Party',click('Light up debuffs you can remove##frame')),
        function(o) return o.types.party.cleanse_light==false and o.types.alliance.cleanse_light;end,'Light up debuffs you can remove'},
    {'Light up debuffs you can remove',nil,as('alliance','Alliance',click('Light up debuffs you can remove##frame')),
        function(o) return o.types.alliance.cleanse_light==false and o.types.self.cleanse_light;end,'Light up debuffs you can remove'},
    {'Light up debuffs you can remove',nil,as('self','You',click('Light up debuffs you can remove##frame')),
        function(o) return o.types.self.cleanse_light==false and o.types.party.cleanse_light;end,'Light up debuffs you can remove'},
    {'Glow around lit icons',nil,click('Glow around lit icons##frame'),function(o) return o.dispel_glow==false;end,'Glow around lit icons','look'},
    {'Light color',nil,color('Light color##frame',{0.2,0.9,1,1}),function(o) return o.dispel_color[2]==0.9 and o.dispel_color[3]==1;end,'Light color','look'},
    {'Show buffs or debuffs',nil,as('other','Other players',click('Debuffs only##frame_Show_kinds_debuff')),
        function(o) return o.types.other.kinds=='debuff' and o.types.mob.kinds=='all';end,'Show buffs or debuffs'},
    {'Only effects I cast',nil,click('Only effects I cast##frame'),function(o) return o.types.mob.mine_only;end,'Only effects I cast','filters'},
    {'Only buffs I cast',nil,click('Only buffs I cast##frame'),function(o) return o.types.mob.buffs_mine_only;end,'Only buffs I cast','filters'},
    {'Only debuffs from my party',nil,click('Only debuffs from my party##frame'),function(o) return o.types.mob.debuffs_party_only==false;end,'Only debuffs from my party','filters'},
    {'Corsair rolls',nil,click('Corsair rolls##frame'),function(o) return o.types.mob.show_rolls==false;end,'Corsair rolls','filters'},
    {'Bard songs',nil,click('Bard songs##frame'),function(o) return o.types.mob.show_songs==false;end,'Bard songs','filters'},
    {'Protect and Shell',nil,click('Protect and Shell##frame'),function(o) return o.types.mob.show_protect_shell==false;end,'Protect and Shell','filters'},
    {'Food',nil,as('party','Party',click('Food##frame')),function(o) return o.types.party.show_food and o.types.mob.show_food;end,'Food','filters'},
    {'Barspells',nil,click('Barspells##frame'),function(o) return o.types.mob.show_barspells==false;end,'Barspells','filters'},
    {'Stances',nil,click('Stances##frame'),function(o) return o.types.mob.show_stances==false;end,'Stances','filters'},
    {'Signet and similar',nil,as('other','Other players',click('Signet and similar##frame')),function(o) return o.types.other.show_signet and not o.types.party.show_signet;end,'Signet and similar','filters'},
    {'Copy Image',nil,as('party','Party',click('Copy Image##frame')),function(o) return o.types.party.show_copy_image and o.types.mob.show_copy_image;end,'Copy Image','filters'},
    {'Third Eye',nil,click('Third Eye##frame'),function(o) return o.types.mob.show_third_eye==false and o.types.self.show_third_eye;end,'Third Eye','filters'},
    {'Use the Hidden everywhere list',nil,as('self','You',click('Use the Hidden everywhere list##frame')),function(o) return o.types.self.shared_rules==false;end,'Use the Hidden everywhere list','filters'},
    {'Show only, kept sorted',function(o) o.types.mob.include={40};end,{{typed={'##frame_Find an effect','Paralysis'}},{click='Show only##frame'}},
        function(o) return same_list(o.types.mob.include,{4,40});end,'Show only','filters'},
    {'Hide here, kept sorted',function(o) o.types.party.exclude={253};end,as('party','Party',{{typed={'##frame_Find an effect','Haste'}},{click='Hide here##frame'}}),
        function(o) return same_list(o.types.party.exclude,{33,253});end,'Hide here','filters'},
    {'Clear this kind\'s filters',function(o) o.types.mob.include,o.types.mob.exclude={4},{33};end,click('Clear this kind\'s filters##frame'),
        function(o) local t=o.types.mob;return #t.include==0 and #t.exclude==0 and t.pinned==nil and t.order==nil;end,'Clear this kind\'s filters','filters'},
    {'Icon size',nil,slide('Icon size',30),function(o) return o.size.base==30;end,'Icon size','place'},
    {'Smallest raises the largest',nil,slide('Smallest',44),function(o) return o.size.min_px==44 and o.size.max_px==44;end,'Smallest','place'},
    {'Largest lowers the smallest',nil,slide('Largest',12),function(o) return o.size.max_px==12 and o.size.min_px==12;end,'Largest','place'},
    {'Bigger on your target',nil,slide('Bigger on your target',1.4),function(o) return o.size.target_scale==1.4;end,'Bigger on your target','place'},
    {'Shrink with distance',nil,slide('Shrink with distance',0.8),function(o) return o.size.alpha==0.8;end,'Shrink with distance','place'},
    {'Bigger units get bigger icons',nil,slide('Bigger units get bigger icons',0),function(o) return o.size.beta==0;end,'Bigger units get bigger icons','place'},
    {'Where the icons sit',nil,pick('Where the icons sit','Under the head','below_name'),function(o) return o.layout.placement=='below_name';end,'Where the icons sit','place'},
    {'Gap above the name',nil,slide('Gap above the name',6),function(o) return o.layout.gap==6;end,'Gap above the name','place'},
    {'Space between icons',nil,slide('Space between icons',3),function(o) return o.layout.icon_gap==3;end,'Space between icons','place'},
    {'Space between lines',lines,slide('Space between lines',4),function(o) return o.layout.line_gap==4;end,'Space between lines','place'},
    {'Space between the two sides',function(o) o.types.mob.layout='split';end,slide('Space between the two sides',12),function(o) return o.layout.split_gap==12;end,'Space between the two sides','place'},
    {'Crowd control icon size',function(o) o.types.mob.layout,o.types.mob.cc_slot='split',true;end,slide('Crowd control icon size',1.8),function(o) return o.layout.cc_scale==1.8;end,'Crowd control icon size','place'},
    {'Countdowns go inside icons under',nil,slide('Countdowns go inside icons under',22),function(o) return o.small_icon_inside_px==22;end,'Countdowns go inside icons under','place'},
    {'Countdown color',nil,color('Countdown color##frame',{1,0.5,0.5,1}),function(o) return o.countdown_color[2]==0.5;end,'Countdown color','look'},
    {'Add head offset',nil,{{typed={'##frame_Unit name','  Fafnir  '}},{click='Add head offset##frame'}},function(o) return o.head.offsets.Fafnir==0;end,'Add head offset','place'},
    {'Add head offset for the target',nil,{{click='Use my target\'s name##frame'},{click='Add head offset##frame'}},function(o) return o.head.offsets.Crab==0;end,'Add head offset','place'},
    {'Offset in yalms',function(o) o.head.offsets={Fafnir=0};end,slide('Offset in yalms',1.25),function(o) return o.head.offsets.Fafnir==1.25;end,'Offset in yalms','place'},
    {'Remove head offset',function(o) o.head.offsets={Fafnir=0.5};end,click('Remove head offset##frame'),function(o) return o.head.offsets.Fafnir==nil;end,'Remove head offset','place'},
    {'Reset this display',function(o) o.max_units,o.types.mob.layout,o.head.offsets=3,'split',{Fafnir=1};end,
        {{click='Reset this display##frame'},{click='Reset##look_frame_reset_overhead'}},
        function(o) return custom.equal(o,defaults.make().overhead);end,'Reset Overhead icons'},
    -- The main page.
    {'Main page: Overhead icons',nil,click('Overhead icons##main_overhead'),function(o) return o.enabled and not o.preview;end,'Overhead icons','Home'},
    {'Main page: Overhead icons off ends the samples',both_on,click('Overhead icons##main_overhead'),function(o) return not o.enabled and not o.preview;end,'Overhead icons','Home'},
    {'Main page: End samples',both_on,click('End samples##main'),function(o) return o.enabled and not o.preview;end,'End samples','Home'},
};
-- Everything but settings.overhead, the window's navigation and the job a save notes.
local function outside(s)
    local value=copy(s);
    value.overhead,value.window,value.profile_job=nil,nil,nil;
    return value;
end;
for _,row in ipairs(rows)do
    local before=begin(row[6] or 'show',row[2]);
    local o_before=copy(app.state.settings.overhead);
    for _,step in ipairs(row[3])do frame(step);end;
    local s=app.state.settings;
    assert(row[4](s.overhead,o_before),'The control writes its key: '..row[1]);
    assert(#app.state.history==1 and app.state.history[1].label==row[5],
        'One Undo step named '..row[5]..': '..row[1]..' ('..#app.state.history..', '..tostring(app.state.history[1] and app.state.history[1].label)..')');
    assert(custom.equal(outside(s),outside(before)),'Nothing outside overhead icons changes: '..row[1]);
    local after=copy(s.overhead);
    assert(app.callbacks.undo());
    assert(custom.equal(app.state.settings.overhead,o_before),'Undo puts it back: '..row[1]);
    assert(app.callbacks.redo());
    assert(custom.equal(app.state.settings.overhead,after),'Redo does it again: '..row[1]);
end;

-- Each switch of who gets a block.
for _,entry in ipairs({{'Your target','target'},{'Your subtarget','subtarget'},{'Mobs your party claimed','claimed'},{'Watched mobs','watched'},
    {'Mobs your party debuffed','debuffed'},{'Party members','party'},{'Alliance members','alliance'},{'Other players','other'},
    {'Your pet','pet'},{'Other players\' pets','other_pet'},{'You','self'}})do
    local before=begin('show');
    frame({click=entry[1]..'##frame'});
    local units=app.state.settings.overhead.units;
    assert(units[entry[2]]==not before.overhead.units[entry[2]] and #app.state.history==1 and app.state.history[1].label==entry[1],
        'The switch turns its units on or off in one step: '..entry[1]);
    for id,on in pairs(units)do assert(id==entry[2] or on==before.overhead.units[id],'Only its own units: '..entry[1]);end;
end;

-- No time format to pick, on any tab.
local begun={};
imgui.BeginCombo=function(label) begun[label]=true;return label==combo;end;
for _,tab in ipairs(panels.tabs)do begin(tab.key);end;
assert(begun['##frame_'..KIND] and not begun['##frame_Time format'],'The panel offers no time format.');
imgui.BeginCombo=function(label) return label==combo;end;
-- The picker writes nothing; the crowd control icon is for mobs in Split only.
begin('show',function(o) o.types.party.layout='split';end);
frame({combo='##frame_'..KIND,click='Party##party'});
assert(page._selection.kind=='party' and #app.state.history==0,'Picking a kind writes nothing.');
MOCK.imgui_calls={};
frame();
local offered={};
for _,call in ipairs(MOCK.imgui_calls)do if call[1]=='Checkbox' then offered[call[2]]=true;end;end;
assert(offered['Swap the sides##frame'] and not offered['Crowd control icon on its own##frame'] and not offered['Light up buffs you can remove##frame'],
    'Party in Split has no crowd control icon or light for buffs.');
-- The light each kind offers on Show, the shared glow and color on Look, and where the search leads.
local function ticks()
    color_labels={};
    MOCK.imgui_calls={};
    frame();
    local out,colors={},color_labels;
    color_labels=nil;
    for _,call in ipairs(MOCK.imgui_calls)do
        if call[1]=='Checkbox' then out[(call[2]:gsub('##frame.*$',''))]=call[3][1];end;
    end;
    return out,colors;
end;
local function pick_kind(kind)
    page._selection.kind=kind;
    app.state.settings_revision=app.state.settings_revision+1;
end;
local BUFFS,DEBUFFS,GLOW,COLOR='Light up buffs you can remove','Light up debuffs you can remove','Glow around lit icons','Light color';
for _,entry in ipairs({{'mob',BUFFS},{'party',DEBUFFS},{'alliance',DEBUFFS},{'self',DEBUFFS},{'other'},{'pet'},{'other_pet'}})do
    local kind,light=entry[1],entry[2];
    begin('show');
    pick_kind(kind);
    local shown=ticks();
    assert(shown[BUFFS]==(light==BUFFS or nil) and shown[DEBUFFS]==(light==DEBUFFS or nil),kind..' offers its own light, on at first.');
    panels.open('overhead','look');
    local look,colors=ticks();
    assert(look[GLOW]==true and colors['Light color##frame']==true,kind..' shows the glow and color, with a light or without one.');
    for _,label in ipairs({BUFFS,DEBUFFS})do
        assert(found(label,label)==(label==light),kind..': '..label..' is a result only where it is offered.');
        assert(label==light or found(label,KIND),kind..': the picker leads to '..label..' where it is not.');
    end;
    assert(light~=DEBUFFS or not found(DEBUFFS,KIND),kind..': with the light offered the picker doesn\'t answer for it.');
    assert(found(GLOW,GLOW) and found('Glow around lit buffs',GLOW) and found(COLOR,COLOR),kind..': the glow and color are results, the glow by both names.');
    assert(found('cursna',DEBUFFS)==(light==DEBUFFS) and found('cursna',KIND)==(light~=DEBUFFS),kind..': the spell names lead there too.');
    assert(not found(GLOW,KIND) and not found(COLOR,KIND),kind..': the picker has no part in them.');
    if light then
        panels.open('overhead','show');
        frame();
        frame({click=light..'##frame'});
        shown=ticks();
        assert(shown[light]==false,kind..': the light goes off.');
        panels.open('overhead','look');
        look,colors=ticks();
        assert(look[GLOW]==true and colors['Light color##frame']==true,kind..': with the light off the glow and color stay.');
        assert(found(GLOW,GLOW) and found(COLOR,COLOR) and not found(GLOW,light) and not found(COLOR,light),
            kind..': and the search goes straight to them.');
    end;
end;
page._selection.kind='mob';
-- Show these effects: the line, then the seven ticks, the first four in the first column, on every kind that shows buffs.
local function switch_list()
    local names,lead,inside,columns,first={},false,false,0,0;
    for _,call in ipairs(MOCK.imgui_calls)do
        if call[1]=='BeginTable' and call[2]=='##overhead_switches' then inside=call[3]==2;assert(inside and not names[1] and lead,'Two columns, after the line.');
        elseif inside and call[1]=='EndTable' then inside=false;
        elseif inside and call[1]=='TableNextColumn' then columns=columns+1;
        elseif inside and call[1]=='Checkbox' then
            names[#names+1]=call[2]:gsub('##frame.*$','');
            if columns==1 then first=first+1;end;
        elseif call[2]=='Show these effects:' then lead=true;end;
    end;
    return table.concat(names,'|'),lead,columns,first;
end;
for _,kind in ipairs({'mob','party','other','pet','other_pet','self'})do
    begin('filters');
    pick_kind(kind);
    MOCK.imgui_calls={};
    frame();
    local names,lead,columns,first=switch_list();
    assert(names==table.concat(LIST,'|') and lead and columns==2 and first==4,'The same list on '..kind..': '..names..' '..columns..' '..first);
    search_finds_switches('with '..kind..' picked.');
end;
-- The alliance shows debuffs only at first: no list, its keys keep their values, and the search leads to the Show choice
-- on this panel and nowhere else, so no result opens onto a list that isn't there.
begin('filters');
frame({combo='##frame_'..KIND,click='Alliance##alliance'});
MOCK.imgui_calls={};
frame();
local names,lead=switch_list();
assert(names=='' and not lead,'Debuffs only lists no switches.');
local alliance=app.state.settings.overhead.types.alliance;
assert(alliance.show_food==false and alliance.show_rolls==true,'The keys keep their values while the list is hidden.');
local function elsewhere(query,label)
    for _,result in ipairs(window.search(query))do if result.panel~='overhead' and result.label==label then return true;end;end;
    return false;
end;
for _,label in ipairs(LIST)do
    assert(not found(label,label) and found(label,SHOW_ROW),'While hidden, '..label..' leads to the Show choice.');
    assert(not elsewhere(label,SHOW_ROW) and not elsewhere(label,'Effect types'),'Only on Overhead icons: '..label);
end;
for _,entry in ipairs(words)do
    assert(found(entry[1],SHOW_ROW) and not found(entry[1],entry[2]),'While hidden, '..entry[1]..' leads to the Show choice.');
end;
-- Buffs and debuffs brings the list back, as the player left it.
panels.open('overhead','show');
frame();
frame({click='Buffs and debuffs##frame_Show_kinds_all'});
panels.open('overhead','filters');
MOCK.imgui_calls={};
frame();
assert(switch_list()==table.concat(LIST,'|'),'The list is back.');
for _,call in ipairs(MOCK.imgui_calls)do
    if call[1]=='Checkbox' and call[2]=='Food##frame' then assert(call[3][1]==false,'Food shows as it was left.');end;
    if call[1]=='Checkbox' and call[2]=='Corsair rolls##frame' then assert(call[3][1]==true,'Corsair rolls shows as it was left.');end;
end;
search_finds_switches('with the alliance showing buffs too.');
assert(not found('Corsair rolls',SHOW_ROW),'With the list shown, the search goes to the switch.');
-- Always show: other players have no line, so what names it finds the kind choice, and the alliance and Mobs have it.
local always_words={{'Always show','Always show'},{'Copy Image','Copy Image'},{'Third Eye','Third Eye'},{'utsusemi','Copy Image'},{'shadows','Copy Image'},{'samurai','Third Eye'}};
pick_kind('other');
frame();
for _,entry in ipairs(always_words)do
    assert(found(entry[1],KIND) and not found(entry[1],entry[2]),'On other players, '..entry[1]..' leads to the kind choice.');
end;
for _,kind in ipairs({'alliance','mob'})do
    pick_kind(kind);
    frame();
    for _,entry in ipairs(always_words)do assert(found(entry[1],entry[2]),'On '..kind..', search for '..entry[1]..' finds '..entry[2]);end;
end;
-- A name the head offsets can't keep is refused, with a note, and nothing changes.
begin('place');
frame({typed={'##frame_Unit name','   '}});
frame({click='Add head offset##frame'});
assert(next(app.state.settings.overhead.head.offsets)==nil and #app.state.history==0,'An empty name adds nothing.');
begin('place',function(o) o.head.offsets={Fafnir=0.5};end);
frame({typed={'##frame_Unit name','Fafnir'}});
frame({click='Add head offset##frame'});
assert(app.state.settings.overhead.head.offsets.Fafnir==0.5 and #app.state.history==0,'A name already there keeps its offset.');
-- Bold on the main page reaches the overhead icons with every other display.
begin('Home');
frame({click='Bold##main_countdown_bold'});
local s=app.state.settings;
assert(s.overhead.countdown_bold and s.panels.self_buffs.countdown_bold,'Every countdown includes the overhead icons.');
-- The main page's Edit opens the panel.
begin('Home',function(o) o.enabled=true;end);
MOCK.imgui_calls={};
frame({click='Edit##main_overhead'});
assert(app.state.settings.window.tab=='Display' and panels.opened()=='overhead' and #app.state.history==0,'Edit opens Overhead icons.');
assert(#MOCK.commands==0,'The panel sends no game commands.');
return 'Every Overhead icons control writes its key as one Undo step, and search finds them';
