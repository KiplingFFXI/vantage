-- Level Sync and unknown timers stay icon-only in each native font family.
local imgui,fonts=require('imgui'),require('ui.fonts');
local countdown,icons=require('ui.countdown_text'),require('ui.icons');
local party,hud,theme=require('ui.party_defaults'),require('ui.party_hud'),require('ui.party_theme');
icons.prepare();
local faces={'Original FFXI','XI View','Agave'};
local sync={effect=269,name='Level Sync',kind='buff',status='unknown',present=true};
-- No countdown draws an infinity sign or a question mark.
local infinity=string.char(226,136,158);
local seen=0;local draw=countdown.draw;
countdown.draw=function(list,face,text,...)
    assert(not text:find(infinity,1,true) and not text:find('?',1,true));
    if text~='' then seen=seen+1;end;
    return draw(list,face,text,...);
end;
local function plain(list,face,text,x,y)
    if not fonts.draw(list,face,text,x,y,16,0xffffffff)then list:AddText({x,y},0xffffffff,text);end;
end;
return function()
    seen=0;
    imgui.SetNextWindowPos({0,0},ImGuiCond_Always);
    imgui.SetNextWindowSize({810,460},ImGuiCond_Always);
    imgui.Begin('##level_sync_infinity',true,ImGuiWindowFlags_NoDecoration+ImGuiWindowFlags_NoInputs);
    local list=imgui.GetWindowDrawList();
    for column,face in ipairs(faces)do
        local x=12+(column-1)*270;
        if face~='Agave'then assert(not fonts.failed(face));end;
        fonts.push(face,16);plain(list,face,face,x,14);
        local config=party.make();
        config.style.icon_art=face=='Agave' and 'Original FFXI' or face;
        local look=theme.party(config,{font=face,font_size=16});
        local options=config.effects;
        options.icon_size,options.max=16,1;
        for mask=0,7 do
            local y=47+mask*41;
            options.countdown_bold,options.countdown_shadow,options.countdown_outline=mask%2==1,math.floor(mask/2)%2==1,mask>=4;
            list:AddRectFilled({x,y},{x+248,y+35},0xff332a20);
            hud.paint_effects(list,look,{known=true,effects={sync}},options,{x=x+8,y=y+9,width=16,height=16},nil,nil,{});
            plain(list,face,'Icon only',x+36,y+8);
            list:AddText({x+179,y+12},0xffb8b8b8,('B%d S%d O%d'):format(mask%2,math.floor(mask/2)%2,math.floor(mask/4)%2));
        end;
        options.countdown_bold,options.countdown_shadow,options.countdown_outline=false,true,false;
        plain(list,face,'Other unknown',x,386);
        hud.paint_effects(list,look,{known=true,effects={{effect=33,name='Haste',status='unknown',present=true}}},options,{x=x+220,y=386,width=16,height=16},nil,nil,{});
        plain(list,face,'Known timer',x,418);countdown.draw(list,face,'30s',x+194,418,16,0xffffffff,options);
        fonts.pop();
    end;
    imgui.End();
    assert(seen==3,'Only the three known timers draw countdown text');
    PREVIEW.log('Level Sync and unknown timers remain icon-only with native fonts');
end;
