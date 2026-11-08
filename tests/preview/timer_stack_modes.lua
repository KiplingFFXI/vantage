local defaults,hud,imgui,fonts=require('ui.defaults'),require('ui.hud'),require('imgui'),require('ui.fonts');
require('ui.icons').prepare();
local sets={};
for column,spec in ipairs({{'Original FFXI','horizontal'},{'Original FFXI','vertical'},
    {'XI View','horizontal'},{'XI View','vertical'}})do
    for row,mode in ipairs({'bars','expanded','icons'})do
        local settings=defaults.make();
        require('ui.theme').apply(settings,'Original FFXI');
        settings.style.theme,settings.style.font,settings.style.icon_art,settings.style.gauge_art='Original FFXI',spec[1],spec[1],spec[1];
        settings.style.font_size,settings.style.icon_size,settings.style.bar_height=16,32,36;
        settings.style.minimal,settings.style.opacity,settings.style.gap=false,1,4;
        settings.style.text_shadow=false;
        for key,p in pairs(settings.panels)do p.enabled=key=='self_buffs';end;
        local p=settings.panels.self_buffs;
        p.mode,p.stack_direction,p.item_width,p.sort=mode,spec[2],180,'fixed';
        p.x,p.y=20+(column-1)*410,76+(row-1)*280;
        p.width,p.height_limit=mode=='icons' and 140 or 390,mode=='icons' and 125 or 212;
        p.auto_height,p.auto_width,p.locked,p.wrap=false,false,true,true;
        p.bar_style,p.bar_thickness,p.title='rail',8,'Self buffs';
        p.show_name,p.show_time,p.show_total,p.show_elapsed=true,true,mode=='expanded',mode=='expanded';
        p.order={33,40,269,251};
        local view={valid=true,context={id=1001},rows={},notices={}};
        for index,item in ipairs({{33,'Haste',82,180},{40,'Protect',523,900},{269,'Level Sync'}, {251,'Food'}})do
            local left=item[3];
            view.rows[index]={key='effect'..item[1],effect=item[1],name=item[2],scope='self',entity_id=1001,
                kind=item[1]==269 and 'other' or 'buff',status=left and 'server' or 'unknown',present=true,
                deadline=left and 100+left or nil,total=item[4],start=left and 100-(item[4]-left) or nil};
        end;
        sets[#sets+1]={settings=settings,view=view,face=spec[1],direction=spec[2],mode=mode,column=column,row=row};
    end;
end;
local begin=imgui.Begin;
return function()
    for index,set in ipairs(sets)do
        assert(not fonts.failed(set.face),'The client font is available for the timer gallery');
        local p=set.settings.panels.self_buffs;
        imgui.SetNextWindowPos({p.x,p.y-54},ImGuiCond_Always);
        imgui.SetNextWindowSize({390,52},ImGuiCond_Always);
        imgui.Begin('##timer_stack_label'..index,true,ImGuiWindowFlags_NoDecoration+ImGuiWindowFlags_NoInputs+ImGuiWindowFlags_NoBackground);
        imgui.TextUnformatted(set.face..' / '..set.direction);
        imgui.TextUnformatted(({bars='Compact bars',expanded='Expanded bars',icons='Icons only'})[set.mode]);
        imgui.End();
        imgui.Begin=function(name,...)return begin(name..'_timer_stack_'..index,...);end;
        local ok,why=pcall(hud.draw,set.view,set.settings,100,{});
        imgui.Begin=begin;if not ok then error(why);end;
    end;
    PREVIEW.log('All three timer layouts with both stack directions and stock/XI View art; unknown effects retain only their icons.');
end;
