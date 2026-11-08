local layout, overlay, hud = require('ui.party_layout'), require('ui.native_party_hud'), require('ui.party_hud')
local defaults, copy, equal = require('ui.party_defaults'), require('core.store').copy, require('core.customization').equal
local imgui, fonts, icons = require('imgui'), require('ui.fonts'), require('ui.icons')
local drawn, pictures = {}, 0
fonts.measure = function(_,text,size)return #text*size*.5 end
fonts.draw = function(_,_,value)drawn[#drawn+1]=value;return true end
fonts.is_bitmap = function()return false end
icons.status = function()pictures=pictures+1;return 1 end
imgui.GetScrollY = function()return 0 end
local mx,my = -1,-1
imgui.GetMousePos = function()return mx,my end
local config=defaults.make()
config.enabled,config.locked=true,true
config.effects.timers=true
local roster,subjects=hud.sample(18,100)
local geometry={available=true,groups={}}
for group=1,3 do
    local frame={x=1000,y=40+(group-1)*250,width=116,height=132,rows={}}
    for _,member in ipairs(roster.members)do if member.group==group then
        frame.rows[member.slot]={x=frame.x,y=frame.y+(member.slot%6)*22,width=116,height=22,slot=member.slot}
    end end
    geometry.groups[group]=frame
    config.groups[group].detached_x=30+(group-1)*310
    config.groups[group].detached_y,config.groups[group].detached_width,config.groups[group].detached_height=40,300,400
end
MOCK.screen={1600,1000}
local function populate(kind)
    for _,member in ipairs(roster.members)do
        if kind=='missing' then
            subjects[member.id]=nil
        else
            subjects[member.id]={known=kind=='clear',complete=kind=='clear',effects={}}
        end
    end
end
local function reset_draw()
    drawn,pictures,MOCK.imgui_calls={},0,{}
end
local function no_marker()
    for _,value in ipairs(drawn)do assert(value~='?' and not value:find('Effects unknown',1,true), 'Unavailable lists have no persistent marker.')end
    for _,call in ipairs(MOCK.imgui_calls)do assert(call[1]~='BeginTooltip','Availability remains hover-only.')end
end
for _,detached in ipairs({false,true})do
    for group=1,3 do config.groups[group].native_detached=detached end
    populate('clear');local cleared=overlay.plan(roster,subjects,config,geometry,1600,1000)
    for _,kind in ipairs({'missing','unavailable'})do
        populate(kind);local before=copy(subjects)
        local plans=overlay.plan(roster,subjects,config,geometry,1600,1000)
        assert(#plans==3 and #plans[3].rows==6,'All native party and alliance anchors remain available when empty.')
        for index,plan in ipairs(plans)do
            assert(plan.width==cleared[index].width and plan.height==cleared[index].height)
            assert(plan.content_height==cleared[index].content_height, 'Unavailable lists add no extra vertical space.')
            if detached then for _,row in ipairs(plan.rows)do assert(row.area.height==0 and not row.unknown)end end
        end
        reset_draw();overlay.draw(roster,subjects,config,100,{native_geometry=geometry})
        no_marker();assert(pictures==0 and equal(before,subjects),'Empty display never changes unknown state to clear.')
        local item=plans[1].rows[1]
        mx,my=item.area.x+3,detached and item.label_y+2 or item.area.y+2
        reset_draw();overlay.draw(roster,subjects,config,100,{native_geometry=geometry})
        local explanation=false
        for _,call in ipairs(MOCK.imgui_calls)do
            if call[1]=='TextUnformatted' and type(call[2])=='string' and call[2]:find('does not confirm',1,true)then explanation=true end
        end
        assert(explanation,'Member hover explains unavailable effects: '..tostring(detached))
        reset_draw();overlay.draw(roster,subjects,config,100,{native_geometry=geometry,shift=true})
        for _,call in ipairs(MOCK.imgui_calls)do
            assert(call[1]~='BeginTooltip','Shift suppresses availability hover even when the native panel is locked.')
        end
        mx,my=-1,-1
    end
end

-- A detached strip gives an unavailable list no height.
local options=copy(config.effects);options.wrap_text,options.font_size=true,48
options.text_measure=function(value)return #value*24 end
assert(layout.kept_effect_height({},nil,{},options,30)==0)
assert(layout.kept_effect_height({},{known=false,effects={}},{},options,30)==0)

-- A supplied icon with an unknown duration is still useful information.
populate('unavailable')
subjects[roster.members[1].id].effects={{effect=4,name='Paralysis',kind='debuff',status='unknown',present=true,key='paralysis'}}
local before=copy(subjects)
for _,detached in ipairs({false,true})do
    for group=1,3 do config.groups[group].native_detached=detached end
    reset_draw();overlay.draw(roster,subjects,config,100,{native_geometry=geometry})
    assert(pictures==1,'Observed icons remain visible even when the whole effect list is unavailable.')
    local unknown_time=false;for _,value in ipairs(drawn)do if value=='?' then unknown_time=true end end
    for _,call in ipairs(MOCK.imgui_calls)do if call[1]=='draw:AddText' and call[6]=='?' then unknown_time=true end end
    assert(not unknown_time,'A known icon remains visible without a duration placeholder.')
    assert(equal(subjects,before),'Rendering never upgrades incomplete observations.')
end
