local countdown=require('ui.countdown_text');
local layout=require('ui.party_layout');
local fields=require('ui.fields');
local copy,equal=require('core.store').copy,require('core.customization').equal;
local sync={effect=269,name='Level Sync',status='unknown',present=true,kind='buff'};
assert(require('data.catalog')[269].name=='Level Sync');
-- No display draws an infinity sign for it.
local infinity=string.char(226,136,158);
assert(countdown.indefinite(sync) and layout.effect_time(sync)=='');
local stale=copy(sync);stale.present=nil;assert(not countdown.indefinite(stale) and layout.effect_time(stale)=='');
for _,change in ipairs({{effect=33},{domain='recast'},{present=false},{remaining=0},{remaining=30},{deadline=0},{deadline=140}})do
    local row=copy(sync);for key,value in pairs(change)do row[key]=value;end;
    assert(not countdown.indefinite(row),'Only present status Level Sync without a finite supplied countdown is indefinite');
end;
for _,value in ipairs({-1,math.huge,-math.huge,0/0,'30'})do
    local row=copy(sync);row.remaining=value;
    assert(countdown.indefinite(row));
end;
local grace=copy(sync);grace.status,grace.remaining,grace.deadline='server',30,130;
assert(layout.effect_time(grace)=='');
local unknown=copy(sync);unknown.effect=4;
assert(layout.effect_time(unknown)=='');
local panel={show_name=true,show_time=true,field_order={'name','time'},field_labels={time='Remaining'},
    countdown_bold=true,countdown_shadow=true,countdown_outline=true};
local style={font_size=16,text_color={1,1,1,1}};
local function build(row)
    return fields.build(row,panel,style,100,function(value)return value and tostring(value) or '?'end,'Time unknown',row.name,{1,1,1,1});
end;
local original=copy(sync);
local rows=build(sync);local caption=fields.text(rows);
assert(caption=='Level Sync' and not caption:find('Unknown',1,true));
for _,row in ipairs(rows)do assert(not row.countdown);end;
assert(equal(sync,original),'Display semantics do not change timer confidence or invent a deadline');
local untimed=fields.text(build(unknown));
assert(untimed~='' and not untimed:find('Unknown',1,true) and not untimed:find('?',1,true),
    'Other effects without a duration say nothing unknown either: '..untimed);
panel.show_time=false;assert(not fields.text(build(sync)):find(infinity,1,true));
panel.show_time=true;

local imgui,fonts=require('imgui'),require('ui.fonts');
local calls,unsupported={},0;
fonts.measure_countdown=function(_,text,size)
    assert(not text:find(infinity,1,true),'Bitmap atlas never receives an unsupported infinity codepoint');
    return #text*size*.5,size;
end;
fonts.countdown_renderer=function(face)return function(_,text,x,y,size,color)
    assert(not text:find(infinity,1,true));calls[#calls+1]={kind='text',x=x,y=y,width=#text*size*.5,height=size,color=color};
end;end;
fonts.face=function(face)return face;end;
fonts.failed=function()return false;end;
fonts.measure=function(_,text,size)return #text*size*.5;end;
fonts.draw=function()return true;end;
imgui.CalcTextSize=function(text)
    assert(not text:find(infinity,1,true));local size=imgui.GetFontSize();return #text*size*.5,size;
end;
local list={};
function list:AddLine(a,b,color,stroke) calls[#calls+1]={kind='line',a=a,b=b,color=color,stroke=stroke};end;
function list:AddText(_,size,position,color,text)
    assert(not text:find(infinity,1,true));calls[#calls+1]={kind='text',x=position[1],y=position[2],width=#text*size*.5,height=size,color=color};
end;
for _,method in ipairs({'PushClipRect','PopClipRect','AddRectFilled','AddRectFilledMultiColor','AddImage','AddRect'})do list[method]=function()end;end;

local party,hud,theme=require('ui.party_defaults'),require('ui.party_hud'),require('ui.party_theme');
require('ui.icons').status=function()return 123;end;
local subject={known=true,effects={sync}};
for _,face in ipairs({'Original FFXI','XI View','Agave'})do
    for _,wrapped in ipairs({false,true})do
        local config=party.make();
        local look=theme.party(config,{font=face,font_size=16});look.bitmap_ready=fonts.is_bitmap(face);
        local options=config.effects;
        options.wrap_text,options.font_size,options.text_measure=wrapped,16,function(value)return #value*8;end;
        options.countdown_bold,options.countdown_shadow,options.countdown_outline=true,true,true;
        local area={x=10,y=20,width=110,height=300};
        calls={};hud.paint_effects(list,look,subject,options,area,nil,nil,{});
        assert(#calls==0,'Level Sync has no countdown overlay');
    end;
end;
-- Fixed native slots keep the icon without a countdown overlay.
for _,height in ipairs({12,14,16})do
    local config=party.make();
    local look=theme.party(config,{font='XI View',font_size=48});look.bitmap_ready=true;
    local options=config.effects;
    options.icon_size,options.fixed_countdown_slot=height,true;
    options.countdown_bold,options.countdown_shadow,options.countdown_outline=true,true,true;
    local area={x=10,y=20,width=110,height=height};
    calls={};hud.paint_effects(list,look,subject,options,area,nil,nil,{});
    assert(#calls==0,'Attached Level Sync icon has no countdown overlay');
end;
assert(equal(sync,original),'Rendering preserves unknown certainty and the original Level Sync observation');

local timer_hud=require('ui.hud');
local defaults=require('ui.defaults');
local settings=defaults.make();
local timer_panel=settings.panels.self_buffs;
timer_panel.show_time=true;
assert(timer_hud.timer_text(sync,100)=='' and timer_hud.timer_text(stale,100)=='');
assert(timer_hud.timer_text(grace,100)=='');
assert(not fields.text(timer_hud.entries(sync,timer_panel,settings.style,100)):find('Unknown',1,true));
assert(not table.concat(timer_hud.field_lines(sync,timer_panel,100),' '):find('Unknown',1,true));
assert(timer_hud.details(sync,100,timer_panel):find('without a fixed countdown',1,true));
assert(timer_hud.fraction(sync,timer_panel,100)==nil,'Icon-only presentation never fabricates a countdown bar fraction');
local tooltip_text={};local old_text=imgui.TextUnformatted;
imgui.TextUnformatted=function(text)tooltip_text[#tooltip_text+1]=text;end;
local with_reason=copy(sync);with_reason.reason='Its duration is unknown.';
assert(not timer_hud.details(with_reason,100,timer_panel):lower():find('unknown',1,true));
hud.effect_tooltip(imgui,with_reason,{name='Player'},subject);
imgui.TextUnformatted=old_text;
assert(table.concat(tooltip_text,' '):find('without a fixed countdown',1,true));
assert(not table.concat(tooltip_text,' '):lower():find('unknown',1,true));

local seen={};local original_draw=countdown.draw;
countdown.draw=function(list,face,text,...)
    seen[#seen+1]=text;
    return original_draw(list,face,text,...);
end;
imgui.GetWindowDrawList=function()return list;end;
imgui.GetScrollY=function()return 0;end;
imgui.GetMousePos=function()return -1,-1;end;
imgui.IsMouseDown=function()return false;end;
MOCK.screen={1600,1200};
local function route(fn)
    seen={};fn();assert(#seen==0,'Level Sync remains icon-only across every display');
end;
local config=party.make();config.enabled,config.locked=true,true;
local roster=hud.sample(1,100);
local member=roster.members[1];local subjects={[member.id]=subject};
local native=require('ui.native_party_hud');
local geometry={available=true,groups={[1]={x=1000,y=100,width=116,height=32,rows={
    [member.slot]={x=1000,y=100,width=116,height=32,slot=member.slot},
}}}};
for _,detached in ipairs({false,true})do
    config.groups[1].native_detached=detached;
    route(function()native.draw(roster,subjects,config,100,{native_geometry=geometry})end);
end;
for key,p in pairs(settings.panels)do p.enabled=key=='self_buffs';end;
settings.style.font='XI View';timer_panel.show_icon=true;
local row=copy(sync);row.scope,row.key='self','sync';
route(function()timer_hud.draw({valid=true,rows={row},events={}},settings,100,{})end);
countdown.draw=original_draw;
