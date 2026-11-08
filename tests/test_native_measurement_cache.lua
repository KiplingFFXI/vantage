local overlay,defaults=require('ui.native_party_hud'),require('ui.party_defaults');
local hud,fonts,layout=require('ui.party_hud'),require('ui.fonts'),require('ui.party_layout');
local config=defaults.make();
config.groups[1].native_detached=true;
config.groups[1].detached_width=190;
config.effects.max=32;
local roster,subjects=hud.sample(6,100);
for _,member in ipairs(roster.members) do
    member.name='LongMemberName';
    subjects[member.id]={known=true,effects={}};
    for id=1,32 do subjects[member.id].effects[id]={effect=id,name='Repeated effect description '..id,
        remaining=30,total=60,status='estimated',kind='buff'};end;
end;
local calls={};
fonts.measure=function(_,value,size) calls[value]=(calls[value] or 0)+1;return #value*size/2;end;
-- The party list buffs wear the timer panels' font.
local style=require('ui.defaults').make().style;
local function plan()
    return overlay.plan(roster,subjects,config,{available=false},1600,900,nil,style)[1];
end;
local first=plan();
for value,count in pairs(calls) do assert(count==1,'Each exact caption/prefix is measured once per detached plan: '..value);end;
for _,row in ipairs(first.rows) do
    layout.effect_cells(layout.effects(subjects[row.member.id],row.options),row.options,row.area);
end;
for _,count in pairs(calls) do assert(count==1,'Height measurement and painting share only the current plan measurement cache.');end;
local count=0;for _ in pairs(calls) do count=count+1;end;
print('Detached32-effect caption measurements per plan: '..count);
calls={};style.font_size=30;
local second=plan();
assert(second.content_height>first.content_height,'Changing font size recalculates wrapping in a fresh plan.');
for _,count2 in pairs(calls) do assert(count2==1);end;
assert(#MOCK.font_stack==0);
return 'Detached effect layout shares per-plan caption measurements without retaining font-dependent results';
