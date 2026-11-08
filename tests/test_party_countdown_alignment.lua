local imgui = require('imgui');
local hud = require('ui.party_hud');
local layout = require('ui.party_layout');
local countdown = require('ui.countdown_text');
local icons = require('ui.icons');
local defaults = require('ui.party_defaults');
local copy = require('core.store').copy;
local equal = require('core.customization').equal;
imgui.CalcTextSize = function(text) return #text * imgui.GetFontSize() / 2, imgui.GetFontSize(); end;

local effects = {
    {effect=40,name='Protect',kind='buff',remaining=16800,present=true},
    {effect=41,name='Shell',kind='buff',remaining=60,present=true},
    {effect=42,name='Unknown duration',kind='buff',present=true},
    {effect=43,name='Long duration',kind='buff',remaining=360000,present=true},
    {effect=269,name='Level Sync',kind='buff',present=true},
};
local original_icon, original_timer = icons.status, countdown.draw;
icons.status = function(effect) return effect; end;
local seen, current, clip, timers;
local list = {
    PushClipRect = function(_, first, last) clip={x=first[1],y=first[2],right=last[1],bottom=last[2]}; end,
    PopClipRect = function() end,
    AddImage = function(_, effect, first, last)
        current={effect=effect,x=first[1],y=first[2],width=last[1]-first[1],height=last[2]-first[2]};
        seen[#seen+1]=current;
    end,
};
local function near(a,b,why) assert(math.abs(a-b)<.001,why..': '..tostring(a)..' / '..tostring(b)); end;
countdown.draw = function(_,font,text,x,y,size,ink,options,compact)
    assert(current and compact);
    local width,height=countdown.measure(font,text,size,options,true);
    -- Icons land on whole pixels. A countdown inside one shares its center; one below stays centered in its column,
    -- so it is at most half a pixel from the icon's.
    if options.icon_countdown_position=='inside' then
        near(x+width/2,current.x+current.width/2,'Timer and icon share the same center');
    else
        assert(math.abs(x+width/2-(current.x+current.width/2))<=.501,
            'Timer and icon centers within half a pixel: '..tostring(x+width/2)..' / '..tostring(current.x+current.width/2));
    end;
    assert(x>=clip.x and x+width<=clip.right and y>=clip.y and y+height<=clip.bottom,
        'Styled countdown ink stays inside its reserved cell.');
    if options.icon_countdown_position~='inside' then
        assert(y>=current.y+current.height+(options.icon_countdown_gap or 0),'Below timers clear their icon.');
    end;
    assert(current.effect~=42 and current.effect~=269,'Unknown and Level Sync timers stay blank.');
    timers=timers+1;
end;
local cases,widened=0,0;
for _,font in ipairs({'Original FFXI','XI View'}) do
    for _,size in ipairs({16,24,32}) do
        for _,manual in ipairs({0,32}) do
            for _,growth in ipairs({'left','right'}) do
                for _,position in ipairs({'below','inside'}) do
                    for style=0,7 do
                        local options={timers=true,fit_all=true,wrap_text=true,
                            icon_size=size,countdown_font=font,icon_countdown_size=manual,icon_countdown_gap=0,
                            icon_countdown_position=position,growth=growth,font_size=16,blink_icons=false,
                            countdown_bold=style%2==1,countdown_shadow=math.floor(style/2)%2==1,countdown_outline=style>=4};
                        local before=copy(options);
                        local area={x=100,y=200,width=size*2+3,height=2000};
                        local cells,omitted=layout.effect_cells(effects,options,area);
                        assert(#cells==#effects and omitted==0 and cells[#cells].y>cells[1].y);
                        local look=require('ui.party_theme').resolve(defaults.make());look.font=font;
                        seen,current,clip,timers={},nil,nil,0;
                        hud.paint_effects(list,look,{effects=effects},options,area,-1,-1,{},100);
                        assert(#seen==#effects and timers>=3,'All icons and every known countdown remain visible.');
                        for index,icon in ipairs(seen) do
                            local cell=cells[index];
                            near(icon.width,size,'Manual icon sizes are preserved');
                            assert(icon.x==math.floor(icon.x) and icon.y==math.floor(icon.y),'Icons land on whole pixels.');
                            assert(math.abs(icon.x+size/2-(cell.x+cell.icon_column_width/2))<=.5,
                                'Icons center inside widened timer columns, to the nearest pixel.');
                            if cell.icon_column_width>size then widened=widened+1;end;
                        end;
                        assert(equal(options,before),'Rendering retains every manual sizing and appearance choice.');
                        cases=cases+1;
                    end;
                end;
            end;
        end;
    end;
end;
icons.status,countdown.draw=original_icon,original_timer;
assert(cases==384 and widened>0,'The regression covers widened columns, not only equal icon and timer widths.');
return 'Party and target icon/countdown centering: both client fonts, growth directions, wraps, manual sizes and all text styles';
