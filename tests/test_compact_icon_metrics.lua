local original_assets=require('ui.client_assets');
local function raw_font(top)
    local bytes={};for i=1,32768 do bytes[i]=0;end;
    for block=0,2047 do
        bytes[block*16+9],bytes[block*16+10]=255,255;
        for i=13,16 do bytes[block*16+i]=85;end;
    end;
    for code=33,126 do
        local index=code-32;local u,v=index%64*16,math.floor(index/64)*16;
        for y=(code==109 and 6 or top),13 do
            for x=1,(code==109 and 9 or 6) do
                local px,py=u+x,v+y;local block=math.floor(py/4)*256+math.floor(px/4);
                local at=py%4*4+px%4;local alpha=block*16+math.floor(at/2)+1;
                local factor=16^(at%2);bytes[alpha]=bytes[alpha]+(15-math.floor(bytes[alpha]/factor)%16)*factor;
                local color=block*16+math.floor(at/4)+13;factor=4^(at%4);
                bytes[color]=bytes[color]-math.floor(bytes[color]/factor)%4*factor;
            end;
        end;
    end;
    for i,value in ipairs(bytes) do bytes[i]=string.char(value);end;
    return {width=1024,height=2048,format='DXT3',dds='DDS '..string.rep('\0',80)..'DXT3'..string.rep('\0',40)
        ..table.concat(bytes)..string.rep('\0',1024*2048-#bytes)};
end;
local raws={original_font=raw_font(3),xiview_font=raw_font(2)};
local generation,reads,uploads=1,0,0;
package.loaded['ui.client_assets']={
    prepare=function()end,generation=function()return generation;end,
    raw=function(kind)reads=reads+1;return raws[kind];end,
    texture=function()return {id=100,width=1024,height=2048};end,
    status=function()return {};end,
    derived_texture=function(kind,_,_,width,height)
        uploads=uploads+1;return {id=kind=='original_font' and 101 or 102,width=width,height=height};
    end,
};
require('ui.client_fonts').prepare();
local countdown=require('ui.countdown_text');
local copy,equal=require('core.store').copy,require('core.customization').equal;
local imgui=require('imgui');
imgui.CalcTextSize=function(text)return #text*imgui.GetFontSize()/2,imgui.GetFontSize();end;
local calls={};
local physical={
    AddImage=function(_,...)calls[#calls+1]=MOCK.copy_arguments('image',...);end,
    AddText=function(_,...)calls[#calls+1]=MOCK.copy_arguments('text',...);end,
};
local function near(a,b)assert(math.abs(a-b)<0.000001);end;
local function check(name,scale,options,text,icon_size)
    text,icon_size=text or '12m',icon_size or 24;
    local before=copy(options);
    local metrics=countdown.icon_metrics(name,text,icon_size,options,scale);
    local x,y=20.3,41.7;
    calls={};countdown.draw(physical,name,text,x*scale,y*scale,metrics.size*scale,0xCCFFFFFF,options,true);
    local left,top,right,bottom;
    for _,call in ipairs(calls) do
        local first,last;
        if call[1]=='image' then
            first,last=call[3],call[4];
            assert(first[1]%1==0 and first[2]%1==0 and last[1]%1==0 and last[2]%1==0,
                'Scaled bitmap glyphs retain physical pixel alignment.');
        else
            first=call[4];last={first[1]+#call[6]*call[3]/2,first[2]+call[3]};
        end;
        left,top=math.min(left or first[1],first[1]),math.min(top or first[2],first[2]);
        right,bottom=math.max(right or last[1],last[1]),math.max(bottom or last[2],last[2]);
    end;
    if text=='' then
        assert(#calls==0 and metrics.width==0 and metrics.height==0,'Unknown durations have no text or reserved timer height.');
    else
        near(left,math.floor(x*scale+0.5));near(top,math.floor(y*scale+0.5));
        near(right-left,metrics.width*scale);near(bottom-top,metrics.height*scale);
        if options.countdown_bold then
            local per_pass=name=='Agave' and 1 or #text;
            local normal,bold=calls[#calls-2*per_pass+1],calls[#calls-per_pass+1];
            local a,b=normal[name=='Agave' and 4 or 3],bold[name=='Agave' and 4 or 3];
            near(b[1]-a[1],1);near(b[2]-a[2],0);
        end;
    end;
    assert(equal(options,before),'Measuring and drawing never modify saved countdown choices.');
    return metrics;
end;
local combinations={
    {},{countdown_shadow=true},{countdown_outline=true},{countdown_bold=true,countdown_shadow=true,countdown_outline=true},
};
for _,name in ipairs({'Original FFXI','XI View','Agave'}) do
    for _,scale in ipairs({.125,.6,.75,1,1.25,1.5,2,8}) do
        for _,options in ipairs(combinations) do
            local metrics=check(name,scale,options);
            near(metrics.size*scale,math.max(6,math.min(64,math.floor(24*scale/2+0.5))));
        end;
        for _,text in ipairs({'9m','59s',''}) do check(name,scale,{countdown_shadow=true},text);end;
        local metrics=check(name,scale,{icon_countdown_size=13.5,icon_countdown_gap=2,countdown_shadow=true});
        near(metrics.size,13.5);assert(metrics.gap==2,'Manual timer size and logical gap survive scaling.');
    end;
end;
local natural=countdown.icon_metrics('Original FFXI','12m',24,{},1);
for _,value in ipairs({0,-1,0/0,math.huge,-math.huge,false,'2'}) do
    assert(equal(countdown.icon_metrics('Original FFXI','12m',24,{},value),natural),'Invalid scales keep natural-size metrics.');
end;
local before_reads,before_uploads=reads,uploads;
check('Original FFXI',1.5,{countdown_bold=true,countdown_shadow=true,countdown_outline=true});
assert(reads==before_reads and uploads==before_uploads,'Scaled drawing performs no font reads or uploads.');

-- Optional real client glyph coverage uses the same production renderer.
-- Two folders up from addons/libs, whatever its case or slashes.
local game=ASHITA_LIBS:gsub('\\','/'):gsub('/+$',''):gsub('/[^/]+/[^/]+$','');
for _,entry in ipairs({
    {'Original FFXI','original_font',game..'/SquareEnix/FINAL FANTASY XI/ROM/119/51.DAT'},
    {'XI View','xiview_font',game..'/polplugins/DATs/XiView-Standard/ROM/119/51.DAT'},
}) do
    local file=io.open(entry[3],'rb');
    if file then
        local data=file:read('*a');file:close();
        raws[entry[2]]=assert(original_assets.parse(data,{'moji'})).textures['font    moji    '];
        generation=generation+1;
        for _,scale in ipairs({.75,1.5,2.125}) do
            for _,options in ipairs(combinations) do check(entry[1],scale,options);end;
        end;
    end;
end;
assert(#MOCK.font_stack==0,'Fallback font measurement leaves the stack balanced.');
return true;
