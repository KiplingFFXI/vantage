local defaults,hud,imgui,fonts=require('ui.defaults'),require('ui.hud'),require('imgui'),require('ui.fonts');
local custom=require('core.customization');
require('ui.icons').prepare();require('ui.recast_icons').prepare();
local modes=PREVIEW_TIMER_GROWTH_ICONS and {'icons'} or {'bars','expanded'};
local sets={};
for column,spec in ipairs({{'Original FFXI','right'},{'Original FFXI','left'},{'XI View','right'},{'XI View','left'}})do
    for mode_index,mode in ipairs(modes)do
        for stack_index,stack in ipairs({'horizontal','vertical'})do
            local row=(mode_index-1)*2+stack_index;
            local s=defaults.make();require('ui.theme').apply(s,'Original FFXI');
            s.window.open,s.recast_display=false,'combined';
            s.style.font,s.style.icon_art,s.style.gauge_art,s.style.recast_icon_art=spec[1],spec[1],spec[1],spec[1];
            s.style.font_size,s.style.icon_size,s.style.bar_height=16,32,36;
            s.style.opacity,s.style.gap,s.style.text_shadow=1,4,false;
            local key=mode=='icons' and stack=='vertical' and 'recasts' or 'self_buffs';
            for id,p in pairs(s.panels)do p.enabled=id==key;end;
            local p=s.panels[key];
            p.mode,p.stack_direction,p.growth,p.item_width,p.sort=mode,stack,spec[2],180,'fixed';
            p.x,p.y=20+(column-1)*410,76+(row-1)*310;
            p.width,p.height_limit=mode=='icons' and 140 or 390,mode=='expanded' and 242 or mode=='icons' and 142 or 174;
            p.auto_height,p.auto_width,p.locked,p.wrap=false,false,true,true;
            p.bar_style,p.bar_thickness,p.title='rail',8,defaults.panel_names[key];
            local view={valid=true,context={id=1001},rows={},notices={}};
            if key=='recasts' then
                for _,timer in ipairs(hud.sample(100).rows)do
                    if timer.domain=='recast' then
                        if timer.effect==10004 then timer.spell_id,timer.list_icon_hq,timer.list_icon_nq=4,89,6;
                        elseif timer.effect==10057 then timer.spell_id,timer.list_icon_hq,timer.list_icon_nq=57,143,2;
                        elseif timer.kind=='ability' then timer.ability_id,timer.list_icon_id,timer.ability_element=547,360,41;
                        elseif timer.kind=='item' then timer.item_id,timer.recast_id=15762,15762;end;
                        view.rows[#view.rows+1]=timer;p.order[#p.order+1]=timer.effect;
                    end;
                end;
            else
                for index,item in ipairs({{33,'Haste',82,180},{40,'Protect',523,900},{269,'Level Sync'},
                    {251,'Food'},{41,'Refresh',90,150}})do
                    local left=item[3];p.order[index]=item[1];
                    view.rows[index]={key='effect'..item[1],effect=item[1],name=item[2],scope='self',entity_id=1001,
                        kind=item[1]==269 and 'other' or 'buff',status=left and 'server' or 'unknown',present=true,
                        deadline=left and 100+left or nil,total=item[4],start=left and 100-(item[4]-left) or nil};
                end;
            end;
            sets[#sets+1]={settings=s,view=view,panel=p,face=spec[1],growth=spec[2],stack=stack,mode=mode};
        end;
    end;
end;
local begin=imgui.Begin;
return function()
    for index,set in ipairs(sets)do
        assert(not fonts.failed(set.face),'The selected client font is available');
        local p=set.panel;
        imgui.SetNextWindowPos({p.x,p.y-54},ImGuiCond_Always);
        imgui.SetNextWindowSize({390,52},ImGuiCond_Always);
        imgui.Begin('##timer_growth_label'..index,true,ImGuiWindowFlags_NoDecoration+ImGuiWindowFlags_NoInputs+ImGuiWindowFlags_NoBackground);
        imgui.TextUnformatted(set.face..' / '..(set.growth=='left' and 'Right to left' or 'Left to right'));
        imgui.TextUnformatted(({bars='Compact bars',expanded='Expanded bars',icons='Icons only'})[set.mode]..' / '..set.stack);
        imgui.End();
        local before=defaults.copy(set.settings);
        imgui.Begin=function(name,...)return begin(name..'_timer_growth_'..index,...);end;
        local ok,why=pcall(hud.draw,set.view,set.settings,100,{shift=false});
        imgui.Begin=begin;if not ok then error(why);end;
        assert(custom.equal(before,set.settings),'Growth rendering preserves every saved option and lock');
    end;
    PREVIEW.log(#sets..' layouts: both stack directions, both growth directions, Original FFXI/XI View. Unknown status icons remain visible without a countdown.');
end;
