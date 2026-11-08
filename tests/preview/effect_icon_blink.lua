local imgui,defaults,hud=require('imgui'),require('ui.defaults'),require('ui.hud');
local party,strips=require('ui.party_hud'),require('ui.native_party_hud');
local pd=require('ui.party_defaults');
local icons,blink,bit=require('ui.icons'),require('ui.effect_blink'),require('bit');
local countdown=require('ui.countdown_text');
icons.prepare();
local specs={{33,'Haste','buff',10},{3,'Poison','debuff',10},{251,'Food','buff'},{269,'Level Sync','other'}};
local sets,active={},nil;
for column,spec in ipairs({{'Original FFXI',false},{'Original FFXI',true},{'XI View',false},{'XI View',true}})do
    for row,mode in ipairs({'icons','bars','strip'})do
        local x,y=20+(column-1)*340,80+(row-1)*220;
        if row>=3 then y=y+40;end;
        local effects={};
        for index,e in ipairs(specs)do effects[index]={key='e'..e[1],effect=e[1],name=e[2],kind=e[3],scope='self',entity_id=1001,
            present=true,status=e[4] and 'server' or 'unknown',remaining=e[4],total=e[4] and 180 or nil};end;
        local set={face=spec[1],full=spec[2],mode=mode,x=x,y=y,effects=effects,inks={},timers={},textures={}};
        for _,e in ipairs(effects)do set.textures[assert(icons.status(e.effect,spec[1]))]=e.effect;end;
        if mode=='strip' then
            -- A party strip left of a game party window at x + 186, 26 px from it. Its icons fill the 40 px row and
            -- touch, so the four take 160 px.
            set.p=pd.make();set.p.enabled,set.p.native.width=true,160;
            set.roster,set.subjects=party.sample(6,0);set.roster.members={set.roster.members[1]};
            set.subjects[1001].effects=effects;
            local member=set.roster.members[1];
            set.geometry={available=true,groups={{x=x+186,y=y,width=116,height=40,
                rows={[member.slot]={x=x+186,y=y,width=116,height=40,slot=member.slot}}}}};
        else
            set.s=defaults.make();require('ui.theme').apply(set.s,'Original FFXI');
            set.s.preview,set.s.watch_ids=false,{1001};
            for key,p in pairs(set.s.panels)do p.enabled=key=='watch';end;
            set.s.style.font,set.s.style.icon_art,set.s.style.gauge_art=spec[1],spec[1],spec[1];
            set.s.style.font_size,set.s.style.icon_size=16,32;
            set.p=set.s.panels.watch;set.p.mode,set.p.x,set.p.y,set.p.width,set.p.height_limit=mode,x,y,320,204;
            set.p.stack_direction,set.p.show_target,set.p.show_source,set.p.sort='vertical',false,false,'fixed';
            set.p.title,set.p.order,set.p.bar_style='Status timers',{33,3,251,269},'rail';
            set.view={valid=true,context={id=1001},rows=effects};
        end;
        if mode=='strip' then
            set.p.style.icon_art,set.p.style.opacity=spec[1],1;
            local e=set.p.effects;e.icon_size=32;
            e.sort,e.separate,e.fit_all,e.blink_icons,e.blink_seconds='id',false,true,true,15;
            -- Countdowns start off; on here, so the strip shows them as the panels do.
            e.timers=true;
        end;
        sets[#sets+1]=set;
    end;
end;
local get_list,begin,draw_timer=imgui.GetWindowDrawList,imgui.Begin,countdown.draw;
imgui.GetWindowDrawList=function()
    local list=get_list();local proxy={};
    proxy.AddImage=function(_,texture,a,b,uv1,uv2,ink)
        if active and active.textures[texture] then active.inks[active.textures[texture]]=ink or 0xFFFFFFFF;end;
        return list:AddImage(texture,a,b,uv1,uv2,ink);
    end;
    return setmetatable(proxy,{__index=function(self,key)
        local method=list[key];if type(method)~='function' then return method;end;
        local bound=function(_,...)return method(list,...);end;rawset(self,key,bound);return bound;
    end});
end;
countdown.draw=function(list,font,text,x,y,size,ink,...)
    if active then active.timers[#active.timers+1]={text=text,font=font,size=size,ink=ink};end;
    return draw_timer(list,font,text,x,y,size,ink,...);
end;
local held=100;
local held_ink=blink.tint({effect=33,status='server',remaining=10},{blink_icons=true},held,0xFFFFFFFF);
return function()
    -- Reset the shared clock before comparing each independently drawn sample.
    blink.brightness({effect=33,status='server',remaining=10},{},101);
    assert(blink.tint({effect=33,status='server',remaining=10},{},held,0xFFFFFFFF)==held_ink,
        'A draw at the same time keeps icon brightness stable');
    for _=1,4 do
        assert(blink.tint({effect=33,status='server',remaining=10},{},held,0xFFFFFFFF)==held_ink,
            'Repeated draws at the same time do not advance the blink phase');
    end;
    local pairs={};
    for index,set in ipairs(sets)do
        set.inks,set.timers={},{};
        local probe={effect=33,status='server',remaining=10};blink.brightness(probe,{},1);blink.brightness(probe,{},0);
        local now=set.full and 10/30 or 0;
        for _,e in ipairs(set.effects)do e.deadline=e.remaining and now+e.remaining or nil;end;
        imgui.SetNextWindowPos({set.x,set.y-55},ImGuiCond_Always);imgui.SetNextWindowSize({325,52},ImGuiCond_Always);
        imgui.Begin('##blink_caption'..index,true,ImGuiWindowFlags_NoDecoration+ImGuiWindowFlags_NoInputs+ImGuiWindowFlags_NoBackground);
        imgui.TextUnformatted(set.face..' / '..(set.full and 'full' or 'half')..' brightness');imgui.TextUnformatted(set.mode);imgui.End();
        active=set;imgui.Begin=function(name,...)return begin(name..'_blink_'..index,...);end;
        if set.mode=='strip' then strips.draw(set.roster,set.subjects,set.p,now,{native_geometry=set.geometry});
        else hud.draw(set.view,set.s,now,{shift=false});end;
        imgui.Begin,active=begin,nil;
        assert(#set.timers==2,'Both known countdowns stay visible; unknown and Level Sync have no countdown');
        for _,e in ipairs(specs)do
            local ink=assert(set.inks[e[1]],'Every known icon was actually drawn: '..set.mode..' '..e[1]);
            local eligible=e[1]==33 or e[1]==3;local rgb=eligible and not set.full and 127 or 255;
            assert(bit.band(bit.rshift(ink,24),255)==255,'Blinking never changes icon alpha');
            assert(bit.band(ink,255)==rgb and bit.band(bit.rshift(ink,8),255)==rgb and bit.band(bit.rshift(ink,16),255)==rgb,
                'Only eligible buff/debuff icon RGB dims; unknown and Level Sync stay steady');
        end;
        local key=set.face..set.mode;
        if not set.full then pairs[key]=set.timers;
        else assert(require('core.customization').equal(set.timers,pairs[key]),'Countdown text, size, font and tint remain unchanged');end;
    end;
    PREVIEW.log('12 actual HUD cases: half/full icon RGB, unchanged alpha/countdowns, unknown and Level Sync steady; repeated draws stable.');
end;
