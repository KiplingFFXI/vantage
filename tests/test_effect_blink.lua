local bit = require('bit');
local function fresh() return assert(loadfile(ADDON_DIR .. '/ui/effect_blink.lua'))(); end;
local blink = fresh();
local row = {effect=33,status='server',remaining=15,present=true};
local options = {blink_icons=true,blink_seconds=15};
for _,fps in ipairs({30}) do
    blink=fresh();
    local ticks=60/fps;
    local last=40/ticks;
    for frame=0,last+1 do
        local now=frame/fps;
        local phase=frame<=last and 40-frame*ticks or 40;
        local expected=(64+math.floor(math.min(phase,40-phase)*3.2))/128;
        assert(math.abs(blink.brightness(row,options,now)-expected)<0.00001,'Native triangle and inclusive endpoint at '..fps..' FPS, frame '..frame);
        assert(blink.brightness(row,options,now)==expected,'Every icon shares the same phase within a frame.');
    end;
end;
local live,interleaved=fresh(),fresh();
for frame=0,240 do
    local now=frame/60;
    local expected=live.brightness(row,options,now);
    interleaved.brightness(row,options,0);
    interleaved.brightness(row,options,now+1000);
    assert(interleaved.brightness(row,options,now)==expected,'Paused and offset previews cannot change live animation.');
end;
blink=fresh();
assert(blink.brightness(row,options,0)==0.5);
assert(blink.brightness(row,options,1/3)==1);
assert(blink.brightness(row,options,2/3)==0.5);
assert(blink.brightness(row,options,0.7)==0.5);
assert(blink.brightness(row,options,0.7+1/3)==1,'The time-driven cycle repeats independently of frame rate.');
blink=fresh();
for _,seconds in ipairs({15.00001,15.5,16,300}) do
    row.remaining=seconds;assert(blink.brightness(row,options,0)==1,'Ceiling seconds above threshold stay steady.');
end;
for _,seconds in ipairs({15,14.999,1,0.01}) do
    row.remaining=seconds;assert(blink.brightness(row,options,0)==0.5,'Finite positive timers within the threshold blink.');
end;
for _,seconds in ipairs({0,-1,math.huge,-math.huge,0/0}) do
    row.remaining=seconds;assert(blink.brightness(row,options,0)==1);
end;
row.remaining=10;
for _,status in ipairs({'unknown','stale','removed','ready'}) do row.status=status;assert(blink.brightness(row,options,0)==1);end;
row.status='estimated';assert(blink.brightness(row,options,0)==0.5,'Observed estimates can warn before their deadline.');
row.deadline=0;assert(blink.brightness(row,options,0)==1,'An expired deadline wins over stale remaining time.');
row.deadline=20;assert(blink.brightness(row,options,0)==1,'A refreshed deadline ends the warning immediately.');
row.deadline=15;assert(blink.brightness(row,options,0)==0.5);
row.deadline=math.huge;assert(blink.brightness(row,options,0)==1);
row.deadline=nil;
row.effect=269;assert(blink.brightness(row,options,0)==1,'Level Sync is never animated even if a stray duration exists.');
row.effect=33;row.present=false;assert(blink.brightness(row,options,0)==1);row.present=true;
row.domain='recast';assert(blink.brightness(row,options,0)==1);row.domain=nil;
assert(blink.brightness(row,{blink_icons=false},0)==1);
assert(blink.brightness(row,{blink_seconds=5},0)==1);
assert(blink.brightness(row,{},0)==0.5,'Missing options retain the native default.');
for _,now in ipairs({-1,math.huge,-math.huge,0/0})do assert(blink.brightness(row,options,now)==1);end;
assert(blink.brightness(row,options,nil)==1);
assert(blink.brightness(nil,options,0)==1);
local custom=0xA080C0FF;
assert(bit.tohex(blink.tint(row,options,0,custom))=='a040607f','RGB dims proportionally without changing alpha or hue.');
assert(blink.tint(row,{blink_icons=false},0,custom)==custom);
for frame=1,10 do blink.brightness(row,options,frame/30);end;
local held=blink.brightness(row,options,10/30);
assert(held==1 and blink.brightness(row,options,10/30)==held,'A clock that stands still does not advance the shared pulse.');
assert(blink.brightness(row,options,0)==0.5,'Resetting the clock safely restarts the pulse.');

package.loaded['ui.icons']={status=function(id)return 100+id;end};
local defaults,hud,store=require('ui.defaults'),require('ui.hud'),require('core.store');
local real_blink=require('ui.effect_blink');
local s=defaults.make();
s.style.font,s.style.font_size,s.style.scale='Ashita',14,1;
MOCK.screen={1600,1000};
for id,p in pairs(s.panels)do
    p.enabled=id=='self_buffs' or id=='self_debuffs';p.show_heading=false;p.width=240;
end;
local view={valid=true,context={id=1001,valid=true},rows={
    {key='buff',effect=33,slot=0,scope='self',kind='buff',status='server',present=true,deadline=10,total=20,name='Haste'},
    {key='debuff',effect=13,slot=1,scope='self',kind='debuff',status='unknown',present=true,name='Slow'},
}};
local function paint(now)
    view.rows[1].deadline=now+10;
    MOCK.imgui_calls={};hud.draw(view,s,now,{});
    local images,texts={},{ };
    for _,call in ipairs(MOCK.imgui_calls)do
        if call[1]=='draw:AddImage' and (call[2]==133 or call[2]==113)then images[call[2]]=store.copy(call);
        elseif call[1]=='draw:AddText'then texts[#texts+1]=store.copy(call);end;
    end;
    assert(images[133] and images[113],'The self panels draw both effects in every pulse phase.');
    assert(bit.tohex(images[133][7])==bit.tohex(real_blink.tint(view.rows[1],s.panels.self_buffs,now,0xFFFFFFFF)));
    assert(bit.tohex(images[113][7])=='ffffffff','Unknown-duration icons stay at full brightness.');
    return images,texts;
end;
local equal=require('core.customization').equal;
for _,mode in ipairs({'icons','bars','expanded'})do
    for _,art in ipairs({'Client','Original FFXI','XI View'})do
        for _,p in pairs(s.panels)do p.mode=mode;end;
        s.style.icon_art=art;
        local before=store.copy(s);
        local dark,text=paint(0);
        local bright,bright_text;
        for frame=1,10 do bright,bright_text=paint(frame/30);end;
        assert(bit.tohex(dark[133][7])=='ff7f7f7f' and bit.tohex(bright[133][7])=='ffffffff');
        for _,id in ipairs({133,113})do
            assert(equal(dark[id][3],bright[id][3]) and equal(dark[id][4],bright[id][4]),'Animation cannot change icon bounds.');
        end;
        assert(equal(text,bright_text),'Countdown text and names stay steady through blinking.');
        assert(equal(s,before),'Rendering never changes saved settings.');
    end;
end;
