-- Every basic control can be changed in the real settings window, each pick as its own Undo step: on the main page, or
-- on the page that is its one home.
local store=require('core.store');
local SNAP={valid=true,id=1001,name='Tester',zone=102,job=3,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(SNAP);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,status=function()return {active=false};end};
local imgui=require('imgui');
local defaults,theme=require('ui.defaults'),require('ui.theme');
local copy=store.copy;
local app=dofile(ADDON_DIR..'/vantage.lua');
local window=require('ui.settings_window');
MOCK.fire('load');app.refresh(0);
local combo,slider,typed;
imgui.BeginCombo=function(label) return label==combo;end;
imgui.SliderFloat=function(label,value)
    if slider and slider[1]==label then value[1],slider=slider[2],nil;return true;end;
    return false;
end;
local input,input_with_hint=imgui.InputText,imgui.InputTextWithHint;
imgui.InputText=function(label,value,...)
    if typed and typed[1]==label then value[1],typed=typed[2],nil;return true;end;
    return input(label,value,...);
end;
imgui.InputTextWithHint=function(label,hint,value,...)
    if typed and typed[1]==label then value[1],typed=typed[2],nil;return true;end;
    return input_with_hint(label,hint,value,...);
end;
local view={rows={},context={valid=true,job=3}};
local function frame(step)
    step=step or {};
    combo,slider,typed=step.combo,step.slider,step.typed;
    MOCK.imgui_calls={};
    if step.click then MOCK.clicks[step.click]=true;end;
    window.draw(app.state.settings,view,app.callbacks);
    assert(not step.click or not MOCK.clicks[step.click],'The control is on its page: '..tostring(step.click));
    MOCK.clicks={};
    assert(#MOCK.font_stack==0);
end;
local function begin(row)
    local s=defaults.tidy(defaults.make());
    s.window.open,s.window.tab=true,row.page or 'Home';
    s.window.sections['Home/More look']=true;
    app.state.settings=s;
    if row[2] then row[2](s);end;
    if row.panel then require('ui.panel_frame').open(row.panel,row.tab or 'show');end;
    frame();
    app.state.history,app.state.redo,app.state.transaction={},{},nil;
    return copy(s);
end;
local function party_on(s) s.party_ui.enabled=true;end;
local function pick(id,label,value) return {{combo=id,click=label..'##'..value}};end;
local function click(label) return {{click=label}};end;
local function flipped(get) return function(s,b) return get(s)~=get(b);end;end;
local function profiles() local names=app.callbacks.profile_list();return names or {};end;
local function has(list,name) for _,entry in ipairs(list)do if entry==name then return true;end;end;return false;end;
-- The party list buffs wear the timer panels' look, so the party rows below read it there.
local function party_look(s) return require('ui.party_theme').party(s.party_ui,s.style);end;

local rows={
    {'Skin',nil,pick('##main_skin','Ember','Ember'),function(s) return s.style.theme=='Ember' and party_look(s).theme=='Ember';end,'Skin: Ember'},
    {'Skin, with this window',nil,pick('##main_skin','Lavender','Lavender'),function(s) return party_look(s).theme=='Lavender' and theme.window(s).theme=='Lavender';end,'Skin: Lavender'},
    -- A fresh install is at 1x, so the Size row picks another size.
    {'Size',nil,click('1.5x##main_size'),function(s) return s.style.scale==1.5;end,'Size 1.5x'},
    {'Hidden everywhere: Signet',nil,{{typed={'##frame_Find an effect','Signet'}},{click='Hide it everywhere##frame'}},function(s) local r=s.effect_filters.rules[1];return r and r.effect==253 and r.enabled;end,'Hide effect everywhere',page='Display',panel='hidden'},
    {'Hidden everywhere: Hide it everywhere',nil,{{typed={'##frame_Find an effect','Haste'}},{click='Hide it everywhere##frame'}},function(s) local r=s.effect_filters.rules[1];return r and r.effect==33 and r.enabled;end,'Hide effect everywhere',page='Display',panel='hidden'},
    {'Status timers: Status and recast icon size',nil,{{slider={'##main_icon_size',40}}},function(s) return s.style.icon_size==40;end,'Icon size'},
    -- Your own row is one pick over what were two ticks.
    {'Party: Show my own row',party_on,pick('##frame_Your own row','Never','never'),flipped(function(s) return s.party_ui.include_self;end),'Your own row',page='Display',panel='party_ui'},
    {'Party: Show when solo',party_on,pick('##frame_Your own row','Only in a party','party'),flipped(function(s) return s.party_ui.show_solo;end),'Your own row',page='Display',panel='party_ui'},
    {'Party: Buff side',function(s) party_on(s);s.party_ui.locked=false;end,pick('##frame_Buff side','Right','right'),function(s) return s.party_ui.native.side=='right';end,'Buff side',page='Display',panel='party_ui',tab='place'},
    {'Party: Your party',party_on,click('Your party##frame_strip'),flipped(function(s) return s.party_ui.strips.party;end),'Your party',page='Display',panel='party_ui'},
    {'Party: Alliance 1',party_on,click('Alliance 1##frame_strip'),flipped(function(s) return s.party_ui.strips.alliance1;end),'Alliance 1',page='Display',panel='party_ui'},
    {'Party: Alliance 2',party_on,click('Alliance 2##frame_strip'),flipped(function(s) return s.party_ui.strips.alliance2;end),'Alliance 2',page='Display',panel='party_ui'},
    {'Party: Party skin',nil,pick('##main_skin','Mint','Mint'),function(s) return party_look(s).theme=='Mint';end,'Skin: Mint'},
    {'Party: Party font',nil,pick('##main_font','Ashita (Agave)','Agave'),function(s) return party_look(s).font=='Agave';end,'Font'},
    -- The party list has no size of its own, so Text size is the one that changes it.
    {'Party: Party font size',nil,{{slider={'##main_text_size',30}}},function(s) return party_look(s).font_size==30;end,'Text size'},
    -- Show member effects is Party list buffs.
    {'Party: Show member effects',nil,click('Party list buffs##main_party_ui'),flipped(function(s) return s.party_ui.enabled;end),'Party list buffs'},
    -- The icon size is for a panel of its own, so the party is in one.
    {'Party: Buff and debuff icon size',function(s) party_on(s);s.party_ui.groups[1].native_detached=true;end,{{slider={'##frame_Icon size in a panel of its own',40}}},function(s) return s.party_ui.effects.icon_size==40;end,'Icon size in a panel of its own',page='Display',panel='party_ui',tab='place'},
    {'Party: Show effect countdowns',party_on,click('Countdowns##frame'),flipped(function(s) return s.party_ui.effects.timers;end),'Countdowns',page='Display',panel='party_ui'},
    {'Alerts: Sound volume',nil,{{slider={'##frame_Sound volume',35}}},function(s) return s.alerts.volume==35;end,'Sound volume',page='Display',panel='notices'},
    {'Alerts: Haste reminder / Sleep reminder / Silence notice',nil,click('Silence notice##frame'),function(s) return #s.alerts.rules==1 and s.alerts.rules[1].name=='Silenced';end,1,page='Display',panel='notices'},
    {'Themes & fonts: Panel font',nil,pick('##main_font','Segoe UI','Segoe UI'),function(s) return s.style.font=='Segoe UI';end,'Font'},
    {'Themes & fonts: Theme',nil,pick('##main_skin','Colorblind safe','Colorblind safe'),function(s) return s.style.theme=='Colorblind safe';end,'Skin: Colorblind safe'},
    {'Themes & fonts: Overall scale',nil,{{slider={'##main_scale',1.25}}},function(s) return s.style.scale==1.25;end,'Size'},
    {'Themes & fonts: Icon size',nil,{{slider={'##main_icon_size',20}}},function(s) return s.style.icon_size==20;end,'Icon size'},
    {'Themes & fonts: Settings text size',nil,{{slider={'##main_window_text',22}}},function(s) return s.window_style.font_size==22;end,'Settings text size'},
    {'Profiles: Save as new',nil,{{typed={'##profile_name','Healer'}},{click='Save as new'}},function(s) return s.active_profile=='Healer' and has(profiles(),'Healer');end,0,page='Profiles'},
    {'Profiles: Load profile',function(s)
        s.style.scale=2;app.callbacks.profile_save('Tank',false);s.style.scale=1;
    end,{{combo='##profiles',click='Tank'},{click='Load##profile_load'}},function(s) return s.style.scale==2 and s.active_profile=='Tank';end,1,page='Profiles'},
    {'Profiles: Job profile',nil,{{combo='##profiles',click='Healer'},{click='Link##profile_link'}},
        function(s) return (s.job_profiles[3] or s.job_profiles['3'])=='Healer';end,1,page='Profiles'},
};

local covered={};
for _,row in ipairs(rows)do
    local before=begin(row);
    for _,step in ipairs(row[3])do frame(step);end;
    local changed=row[4](app.state.settings,before);
    assert(changed,'It changes it: '..row[1]);
    local steps=type(row[5])=='number' and row[5] or 1;
    local undo=#app.state.history==steps and (type(row[5])~='string' or app.state.history[1].label==row[5]);
    assert(undo,'Each pick is its own Undo step: '..row[1]..' ('..#app.state.history..' '..tostring((app.state.history[1] or {}).label)..')');
    if changed and undo then covered[row[1]]=true;end;
end;
local count=0;
for _ in pairs(covered)do count=count+1;end;
assert(count==28,'All 28 rows of the list are covered: '..count);
assert(#MOCK.commands==0,'The controls send no game commands.');
return 'Every basic control has one home, and each pick there is one Undo step';
