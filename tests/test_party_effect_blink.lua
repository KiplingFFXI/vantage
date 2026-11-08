local bit,imgui=require('bit'),require('imgui');
local copy,equal=require('core.store').copy,require('core.customization').equal;
local expected_now,dim,calls=100,false,{};
local function tint(value,amount)
    local alpha=math.floor(value/16777216)%256;
    local red=math.floor(value)%256;
    local green=math.floor(value/256)%256;
    local blue=math.floor(value/65536)%256;
    return imgui.col32(alpha,math.floor(red*amount),math.floor(green*amount),math.floor(blue*amount));
end;
package.loaded['ui.effect_blink']={tint=function(effect,options,now,color)
    assert(now==expected_now,'Every frame renderer forwards its current draw time.');
    assert(options.blink_seconds==15,'Effect option copies retain the configured blink threshold.');
    calls[#calls+1]={effect=effect.effect,enabled=options.blink_icons,color=color};
    return tint(color,dim and options.blink_icons and effect.status~='unknown' and effect.effect~=269 and .5 or 1);
end};
local hud,party=require('ui.party_hud'),require('ui.party_defaults');
local native,theme=require('ui.native_party_hud'),require('ui.party_theme');
local fonts,countdown=require('ui.fonts'),require('ui.countdown_text');
require('ui.icons').status=function(id)return 100000+id;end;
fonts.measure=function(_,value,size)return #value*size*.5;end;
fonts.measure_countdown=function(_,value,size)return #value*size*.5,size;end;
fonts.failed=function()return false;end;
fonts.draw=function()return false;end;
countdown.draw=function(list,face,value,x,y,size,color)
    list:AddText(imgui.GetFont(),size,{x,y},color,value);
end;
imgui.GetMousePos=function()return -1,-1;end;
imgui.IsMouseDown=function()return false;end;
imgui.GetScrollY=function()return 0;end;
MOCK.screen,MOCK.content_width={2400,1600},900;
local function config()
    local p=party.make();
    p.enabled,p.locked,p.show_solo=true,true,true;
    p.style.opacity=.6;
    p.effects.icon_size=24;
    p.effects.blink_icons,p.effects.blink_seconds=true,15;
    return p;
end;
local subject={known=true,complete=true,effects={
    {effect=33,name='Haste',kind='buff',status='estimated',remaining=12,total=180,present=true},
    {effect=4,name='Paralysis',kind='debuff',status='unknown',present=true},
    {effect=269,name='Level Sync',kind='buff',status='unknown',present=true},
}};
local function reset()
    MOCK.imgui_calls,calls={},{};
end;
local function images()
    local result={};
    for _,call in ipairs(MOCK.imgui_calls)do
        if call[1]=='draw:AddImage' and type(call[2])=='number' and call[2]>=100000 then
            result[#result+1]={id=call[2]-100000,first=copy(call[3]),last=copy(call[4]),uv1=copy(call[5]),uv2=copy(call[6]),color=call[7]};
        end;
    end;
    return result;
end;
local function stable_draws()
    local result={};
    for _,call in ipairs(MOCK.imgui_calls)do
        if call[1]:sub(1,5)=='draw:' and call[1]~='draw:AddImage' then result[#result+1]=copy(call);end;
    end;
    return result;
end;
local function route(draw,owner,label)
    local before=copy(owner);
    dim,expected_now=false,100;reset();draw(expected_now);
    local bright,ordinary=images(),stable_draws();
    assert(#bright>0 and #calls==#bright,label..' uses the shared tint helper once per image.');
    for _,image in ipairs(bright)do
        assert(math.floor(image.color/16777216)%256==153,label..' keeps the selected opacity.');
    end;
    dim,expected_now=true,101;reset();draw(expected_now);
    local dark=images();
    assert(#dark==#bright and #calls==#dark,label..' never removes an icon during blinking.');
    for index,image in ipairs(dark)do
        local prior=bright[index];
        assert(image.id==prior.id and equal(image.first,prior.first) and equal(image.last,prior.last)
            and equal(image.uv1,prior.uv1) and equal(image.uv2,prior.uv2),label..' changes no icon geometry or artwork.');
        assert(math.floor(image.color/16777216)%256==math.floor(prior.color/16777216)%256,'Blinking preserves opacity.');
        assert(image.color==(image.id==33 and tint(prior.color,.5) or prior.color),label..' forwards the helper tint unchanged.');
    end;
    assert(equal(ordinary,stable_draws()),label..' leaves countdowns, names, borders, gauges, clipping and interaction unchanged.');
    assert(equal(owner,before),label..' preserves saved customization and locks.');
    assert(#MOCK.font_stack==0,'Frame drawing balances font scopes.');
end;

local p=config();
local look=theme.party(p,{font='Ashita',font_size=16});
local area={x=20,y=30,width=240,height=100};
route(function(now)hud.paint_effects(imgui.GetWindowDrawList(),look,subject,p.effects,area,nil,nil,{},now);end,p,'Direct effect painter');
local roster,subjects=hud.sample(18,100);
for _,member in ipairs(roster.members)do subjects[member.id]=copy(subject);end;

local member=roster.members[1];
local geometry={available=true,groups={[1]={x=1800,y=100,width=116,height=40,rows={
    [member.slot]={x=1800,y=100,width=116,height=40,slot=member.slot},
}}}};
for _,detached in ipairs({false,true})do
    p.groups[1].native_detached=detached;
    route(function(now)native.draw(roster,subjects,p,now,{native_geometry=geometry});end,p,
        detached and 'Detached native effect strip' or 'Attached native effect strip');
end;


for _,face in ipairs({'Original FFXI','XI View'})do
    look=theme.party(p,{font=face,font_size=16});
    route(function(now)hud.paint_effects(imgui.GetWindowDrawList(),look,subject,p.effects,area,nil,nil,{},now);end,
        p,face..' effect icons');
end;
p.effects.blink_icons=false;
dim,expected_now=true,120;reset();
hud.paint_effects(imgui.GetWindowDrawList(),look,subject,p.effects,area,nil,nil,{},expected_now);
assert(#calls==3);
for _,call in ipairs(calls)do assert(call.enabled==false,'The disabled choice reaches the tint helper.');end;
for _,image in ipairs(images())do assert(bit.band(image.color,0xFFFFFF)==0xFFFFFF,'Disabled blinking remains steady.');end;

p.effects.blink_icons=true;p.groups[1].native_detached=false;
for _,detached in ipairs({false,true})do
    p.groups[1].native_detached=detached;
    dim,expected_now=true,125;reset();
    p.preview=true;native.draw(roster,subjects,p,expected_now,{native_geometry=geometry});p.preview=false;
    assert(#calls>0,'The strip sample forwards draw time through the normal effect painter.');
    assert(#MOCK.font_stack==0);
end;
assert(#MOCK.commands==0,'Icon brightness never sends gameplay commands.');
return 'Effect blink tint and draw time reach the effect painter, the party list strips and their samples without changing text or geometry.';
