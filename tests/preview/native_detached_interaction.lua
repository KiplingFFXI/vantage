-- Actual addon painting and ImGui input, with simulated roster/native anchors.
local overlay,defaults=require('ui.native_party_hud'),require('ui.party_defaults');
local hud,layout=require('ui.party_hud'),require('ui.party_layout');
local imgui=require('imgui');
local read_scroll=imgui.GetScrollY;
imgui.GetScrollY=function() local value=read_scroll(); PREVIEW.native_scroll=value; return value; end;
local config=PREVIEW.settings.party_ui;
config.enabled,config.locked,config.effects.max=true,false,32;
config.native.snap,config.native.width=false,280;
local roster,subjects=hud.sample(18,100);
local geometry={available=true,groups={}};
for group=1,3 do
    local saved=config.groups[group];
    saved.native_detached,saved.detached_x,saved.detached_y=true,20+(group-1)*350,50;
    saved.detached_width,saved.detached_height=300,530;
    saved.style={theme='Original FFXI',font=group==3 and 'XI View' or 'Original FFXI',font_size=14,
        icon_art=group==3 and 'XI View' or 'Original FFXI',window_type=group==2 and 7 or 1};
    local frame={x=1200,y=80+(group-1)*180,width=116,height=132,rows={}};
    for _,member in ipairs(roster.members) do if member.group==group then
        member.name=member.slot%6==0 and 'Longcharacterone' or member.name;
        frame.rows[member.slot]={x=frame.x,y=frame.y+member.slot%6*22,width=116,height=22,slot=member.slot};
        local effects=subjects[member.id].effects;
        for index=#effects+1,32 do effects[index]={effect=32+index,name='Sample '..index,remaining=index*5,total=180,status='estimated',kind='buff'}; end;
    end; end;
    geometry.groups[group]=frame;
end;
require('ui.icons').prepare();
PREVIEW.native_starts,PREVIEW.native_saves,PREVIEW.native_ends=0,0,0;
PREVIEW.native_plan=function() return overlay.plan(roster,subjects,config,geometry,1440,900)[1]; end;
PREVIEW.native_geometry=geometry;
PREVIEW.native_reset=function()
    overlay.cancel_layout_gesture();
    local saved=config.groups[1];
    saved.native_detached,saved.detached_x,saved.detached_y=true,200,150;
    saved.detached_width,saved.detached_height=300,240;
    config.native.snap=false;
    PREVIEW.native_starts,PREVIEW.native_saves,PREVIEW.native_ends=0,0,0;
end;
return function()
    local _,shown=overlay.draw(roster,subjects,config,100,{native_geometry=geometry,shift=MOCK.key_shift==true,
        begin_edit=function() PREVIEW.native_starts=PREVIEW.native_starts+1; end,
        end_edit=function() PREVIEW.native_ends=PREVIEW.native_ends+1; end,
        changed=function() PREVIEW.native_saves=PREVIEW.native_saves+1; end,
        target=function() error('A buff panel must never target'); end});
    assert(not next(shown),'Native game windows are never replaced by buff panels');
end;
