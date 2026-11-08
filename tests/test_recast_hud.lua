local hud,defaults=require('ui.hud'),require('ui.defaults');
local s,view=defaults.make(),hud.sample(100);
-- The sample rows carry recast tints, which have their own test (test_recast_tints.lua); here they are off.
s.recast_tints.mp,s.recast_tints.spell_lock,s.recast_tints.ability_lock=false,false,false;
local spells=hud.filter_rows(view,s.panels.spell_recasts,'spell_recasts',s);
local abilities=hud.filter_rows(view,s.panels.ability_recasts,'ability_recasts',s);
assert(#spells==2 and #abilities==1 and spells[1].domain=='recast');
assert(#hud.filter_rows(view,s.panels.item_recasts,'item_recasts',s)==1);
assert(#hud.filter_rows(view,s.panels.self_buffs,'self_buffs',s)==6,'Cooldowns never become self-buff rows.');
local p=s.panels.spell_recasts;
p.include={10057};assert(#hud.filter_rows(view,p,'spell_recasts',s)==1);
p.exclude={10057};assert(#hud.filter_rows(view,p,'spell_recasts',s)==0);
p.include,p.exclude={},{};p.filter='cure';assert(#hud.filter_rows(view,p,'spell_recasts',s)==1);
p.filter='';p.pinned={10057};p.sort='fixed';p.order={10004,10057};
assert(hud.filter_rows(view,p,'spell_recasts',s)[1].effect==10057,'Recasts use normal pin and order priorities.');
p.groups={spell_recasts=true};assert(#hud.filter_rows(view,p,'spell_recasts',s)==2);
p.labels[10057]='My Haste';p.show_total,p.wrap=true,true;
for _,panel in pairs(s.panels) do panel.enabled=false;end;p.enabled=true;
for _,mode in ipairs({'bars','expanded','icons'}) do
    p.mode=mode;MOCK.imgui_calls={};hud.draw(view,s,100,{});
    local badge,text,tile,outline=false,{},false,false;
    for _,call in ipairs(MOCK.imgui_calls) do
        if call[1]=='draw:AddText' then text[#text+1]=call[#call];if call[#call]:find('?',1,true) then badge=true;end;end;
        if call[1]=='draw:AddRect' or call[1]=='draw:AddRectFilled' then tile=true;end;
        if call[1]=='draw:AddRect' then outline=true;end;
    end;
    local shown=table.concat(text,'|');
    if mode=='icons' then
        assert(not badge and not tile,'Icons only does not invent a picture or tile when client artwork is unavailable.');
        assert(not shown:find('My Haste',1,true),'Icons only leaves stored effect labels off the display.');
        for _,row in ipairs(spells) do assert(shown:find(hud.timer_text(row,100),1,true),'Known recast countdowns remain visible without artwork.');end;
        local copied=hud.copy_text(view,s,'spell_recasts',false,100);
        assert(not copied:find('My Haste',1,true) and copied:find(hud.timer_text(spells[1],100),1,true),'Copy shown follows the icons-only countdown display.');
    else
        assert(outline and not badge,'Unavailable client artwork leaves an empty icon box, with no question mark and no borrowed status image.');
        assert(shown:find('My Haste',1,true));
    end;
    assert(#MOCK.font_stack==0);
end;
local detail=hud.details(spells[1],100,p);
assert(detail:find('cooldown',1,true) and detail:find('MP, TP',1,true));
p.mode='bars';hud.draw(view,s,100,{});
assert(hud.copy_text(view,s,'spell_recasts',false,100):find('My Haste',1,true));
local fonts=require('ui.fonts');local originals={fonts.draw,fonts.is_bitmap,fonts.failed};
local count=0;
fonts.draw=function(_,_,value) if value=='My Haste' then count=count+1;end;return true;end;
fonts.is_bitmap=function() return true;end;fonts.failed=function() return false;end;
p.mode='bars';s.style.text_shadow=true;s.style.text_outline=false;
hud.draw(view,s,100,{});assert(count==1,'Bitmap timer captions keep their baked shadow without an extra blurred copy.');
fonts.draw,fonts.is_bitmap,fonts.failed=unpack(originals);
