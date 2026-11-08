local imgui=require('imgui');
local original_assets=require('ui.client_assets');
local function raw_font()
    local bytes={};for i=1,32768 do bytes[i]=0;end;
    for block=0,2047 do
        bytes[block*16+9],bytes[block*16+10]=255,255;
        for i=13,16 do bytes[block*16+i]=85;end;
    end;
    local function point(x,y,light)
        local block=math.floor(y/4)*256+math.floor(x/4);
        local index=y%4*4+x%4;
        local at=block*16+math.floor(index/2)+1;
        local factor=16^(index%2);
        bytes[at]=bytes[at]+(15-math.floor(bytes[at]/factor)%16)*factor;
        if light then
            at=block*16+math.floor(index/4)+13;factor=4^(index%4);
            bytes[at]=bytes[at]-math.floor(bytes[at]/factor)%4*factor;
        end;
    end;
    for code=33,126 do
        local at=code-32;local x,y=at%64*16,math.floor(at/64)*16;
        for row=2,12 do for col=0,7 do point(x+col,y+row,true);end;end;
        point(x+8,y+13,false);point(x+15,y+8,false);
    end;
    for i,value in ipairs(bytes) do bytes[i]=string.char(value);end;
    return {width=1024,height=2048,format='DXT3',dds='DDS '..string.rep('\0',80)..'DXT3'..string.rep('\0',40)
        ..table.concat(bytes)..string.rep('\0',1024*2048-#bytes)};
end;
local raw=raw_font();
local generation,available,derived_ok,uploads,reads,retries=1,true,true,{},0,0;
package.loaded['ui.client_assets']={
    prepare=function()end,retry=function()retries=retries+1;end,generation=function()return generation;end,
    raw=function()reads=reads+1;return available and raw or nil;end,
    texture=function()return available and {id=123,width=1024,height=2048} or nil;end,
    status=function()return {reason='Fixture unavailable'};end,
    derived_texture=function(kind,name,dds,width,height)
        assert(name=='countdown_foreground' and width==256 and height==128);
        if not derived_ok then return nil;end;
        uploads[kind]=uploads[kind] or {id=kind=='original_font' and 456 or 789,width=width,height=height,dds=dds};
        return uploads[kind];
    end,
};
local client=require('ui.client_fonts');
local parsed_faces,parse={},client.parse;
client.parse=function(...)
    local face,issue=parse(...);
    if face then parsed_faces[#parsed_faces+1]=face;end;
    return face,issue;
end;
client.prepare();
assert(#parsed_faces==1,'Preparing makes the stock face only.');
assert(client.available('Original FFXI') and client.available('XI View') and #parsed_faces==2,'The XI View face is made at its first use.');
local fonts=require('ui.fonts');
local countdown=require('ui.countdown_text');
imgui.CalcTextSize=function(text)return #text*imgui.GetFontSize()/2,imgui.GetFontSize();end;
for _,kind in ipairs({'original_font','xiview_font'}) do
    local atlas=uploads[kind];
    assert(atlas and #atlas.dds==128+256*128*4);
    local function pixel(code,x,y)
        local i=code-32;local offset=128+((math.floor(i/16)*16+y)*256+i%16*16+x)*4+1;
        return atlas.dds:sub(offset,offset+3);
    end;
    assert(pixel(49,0,2)=='\255\255\255\255','The selected family foreground remains intact.');
    assert(pixel(49,8,13)=='\0\0\0\0' and pixel(49,15,8)=='\0\0\0\0',
        'Embedded black shading and adjacent-cell bleed cannot survive a shadow-off countdown.');
end;
local calls={};
local list={AddImageQuad=function(_,...)calls[#calls+1]=MOCK.copy_arguments('image',...);end,
    AddText=function(_,...)calls[#calls+1]=MOCK.copy_arguments('text',...);end};
for _,name in ipairs({'Original FFXI','XI View','Agave'}) do
    for _,size in ipairs({8,16,32,48}) do
        for mask=0,7 do
            local bold,shadow,outline=mask%2==1,math.floor(mask/2)%2==1,math.floor(mask/4)%2==1;
            local options={countdown_bold=bold,countdown_shadow=shadow,countdown_outline=outline,countdown_outline_color={1,0,0,.5}};
            calls={};countdown.draw(list,name,'12',10.2,20.3,size,0x80402010,options);
            local passes=(1+(shadow and 1 or 0)+(outline and 8 or 0))*(bold and 2 or 1);
            assert(#calls==passes*(name=='Agave' and 1 or 2),'Each independent effect uses bounded passes.');
            local w,h=countdown.measure(name,'12',size,options);
            local l,t,r,b=countdown.padding(options);
            local base=name=='Agave' and size or client.measure(name,'12',size);
            assert(w==base+l+r and h==size+t+b,'Measurement reserves all selected effect extents.');
            for _,call in ipairs(calls) do
                local first,last,color;
                if call[1]=='image' then
                    assert(call[2]==(name=='Original FFXI' and 456 or 789));
                    first,last,color=call[3],call[5],call[11];
                else
                    assert(call[3]==size);first,last,color=call[4],{call[4][1]+base,call[4][2]+size},call[5];
                end;
                assert(first[1]%1==0 and first[2]%1==0 and first[1]>=10 and first[2]>=20);
                assert(last[1]<=10+w and last[2]<=20+h,'Every styled glyph stays inside the measured countdown box.');
                local alpha=math.floor(color/16777216)%256;
                assert(alpha==128 or outline and alpha==64,'Shadow and outline respect the foreground opacity.');
            end;
            local last=calls[#calls];assert(last[1]=='image' and last[11]==0x80402010 or last[1]=='text' and last[5]==0x80402010);
        end;
    end;
end;
local equal,copy=require('core.customization').equal,require('core.store').copy;
local function compact_box(name,text,size)
    local width,height=client.measure_countdown(name,text,size,true);
    calls={};assert(client.draw_countdown(list,name,text,10.2,20.3,size,0x80402010,true));
    local left,top,right,bottom;
    for _,call in ipairs(calls) do
        assert(call[1]=='image' and call[11]==0x80402010);
        local a,b=call[3],call[5];
        assert(a[1]%1==0 and a[2]%1==0 and b[1]%1==0 and b[2]%1==0,
            'Compact countdown edges remain aligned to whole pixels.');
        left,top=math.min(left or a[1],a[1]),math.min(top or a[2],a[2]);
        right,bottom=math.max(right or b[1],b[1]),math.max(bottom or b[2],b[2]);
    end;
    if #calls==0 then assert(width==0 and height==0,'Whitespace has no countdown ink.');
    else
        assert(left==10 and top==20,'The compact origin is the visible ink origin, not its old line box.');
        assert(right==10+width and bottom==20+height,'Compact measurement matches all drawn glyph bounds.');
    end;
    return width,height;
end;
for _,name in ipairs({'Original FFXI','XI View'}) do
    for _,size in ipairs({1,8,10,12,14.5,16,24,32,48}) do
        calls={};client.draw_countdown(list,name,'12m',10.2,20.3,size,0x80402010);
        local ordinary=copy(calls);
        local ordinary_width,ordinary_height=client.measure_countdown(name,'12m',size);
        for _,text in ipairs({'1h','4h','24h','12m','9m','59s','1:02','~12m','12m\n9s','1\r\n2m','',' \t\n'}) do
            compact_box(name,text,size);
        end;
        calls={};client.draw_countdown(list,name,'12m',10.2,20.3,size,0x80402010,false);
        assert(equal(calls,ordinary),'Compact drawing cannot alter ordinary countdown geometry or UVs.');
        local width,height=client.measure_countdown(name,'12m',size,false);
        assert(width==ordinary_width and height==ordinary_height,'Ordinary line-box measurement is unchanged.');
    end;
    local width,height=compact_box(name,'12m',16);
    assert(width==26 and height==11,'The fixture trims one trailing advance pixel and its transparent top/bottom rows.');
end;
calls={};client.draw(list,'Original FFXI','1',0,0,16,0xFFFFFFFF);
assert(calls[1][2]==123,'Normal client text still uses its untouched original glyph texture.');
local prior_reads,prior_uploads=reads,uploads.original_font;
for _=1,100 do countdown.measure('Original FFXI','1:23',16,{bold=true,shadow=true,outline=true});end;
assert(reads==prior_reads and uploads.original_font==prior_uploads,'Steady countdown rendering does not decode or upload glyphs again.');
local old_retries=retries;calls={};countdown.draw(list,'Original FFXI','12',0,0,16,0xFFFFFFFF,{bold=true,shadow=true,outline=true});
assert(retries==old_retries+1,'All outline/bold passes share one prepared font lookup.');
assert(countdown.measure('Agave','',16,{bold=true,shadow=true,outline=true})==0);
calls={};assert(countdown.draw(list,'Agave','',0,0,16,0xFFFFFFFF,{bold=true}) and #calls==0);
available=false;generation=generation+1;calls={};countdown.draw(list,'Original FFXI','12',0,0,16,0xFFFFFFFF,{});
assert(#calls==1 and calls[1][1]=='text' and countdown.measure('Original FFXI','12',16,{})==16,
    'Unavailable bitmap assets use the same ordinary fallback for measurement and drawing.');
available=true;derived_ok=false;generation=generation+1;calls={};countdown.draw(list,'XI View','12',0,0,16,0xFFFFFFFF,{});
assert(#calls==1 and calls[1][1]=='text','A failed derived upload falls back without retaining a stale GPU pointer.');
derived_ok=true;calls={};countdown.draw(list,'XI View','12',0,0,16,0xFFFFFFFF,{});
assert(#calls==2 and calls[1][2]==789,'Derived upload recovery restores the selected bitmap family.');
local calc=imgui.CalcTextSize;imgui.CalcTextSize=function()error('Measure fixture');end;
assert(not pcall(countdown.measure,'Agave','12',16,{}) and #MOCK.font_stack==0,'Fallback measure errors leave the font stack balanced.');
imgui.CalcTextSize=calc;
local width,height=countdown.measure('Agave','12',14.5,{});
calls={};countdown.draw(list,'Agave','12',0,0,14.5,0xFFFFFFFF,{});
assert(width==14.5 and height==14.5 and calls[1][3]==14.5,'Ordinary text retains the selected fractional font size.');
local first_width,first_height=client.measure_countdown('Original FFXI','12m',12,true);
for index=1,2200 do client.measure_countdown('Original FFXI',tostring(index)..'m',12,true);end;
local filled=false;
for _,face in ipairs(parsed_faces) do
    if face.compact_metrics then
        assert(face.compact_metrics:count()<=2048,'Each prepared font has bounded compact metrics');
        if face.compact_metrics:count()==2048 then filled=true;end;
    end;
end;
assert(filled,'The compact metric cache was exercised beyond its capacity');
local repeated_width,repeated_height=client.measure_countdown('Original FFXI','12m',12,true);
assert(first_width==repeated_width and first_height==repeated_height,'Eviction never changes native countdown bounds');

-- A countdown's glyphs are walked once and replayed for every pass. That draws exactly what one renderer
-- call per pass draws, in the same order: the shadow, the eight outline offsets, then the fill, each with
-- its bold copy.
local outline_ink=require('ui.theme').u32({1,0,0,.5});
outline_ink=outline_ink%16777216+math.floor(math.floor(outline_ink/16777216)%256*128/255+0.5)*16777216;
local around={{-1,-1},{0,-1},{1,-1},{-1,0},{1,0},{-1,1},{0,1},{1,1}};
for _,name in ipairs({'Original FFXI','XI View'}) do
    for _,size in ipairs({8,12,16,24}) do
        for _,compact in ipairs({false,true}) do
            for _,text in ipairs({'12','1:02','12m\n9s',' \t4h'}) do
                for mask=0,7 do
                    local bold,shadow,outline=mask%2==1,math.floor(mask/2)%2==1,math.floor(mask/4)%2==1;
                    local options={countdown_bold=bold,countdown_shadow=shadow,countdown_outline=outline,countdown_outline_color={1,0,0,.5}};
                    calls={};countdown.draw(list,name,text,10.4,20.6,size,0x80402010,options,compact);
                    local drawn=calls;
                    local l,t=countdown.padding(options);
                    local x,y=math.floor(10.4+0.5)+l,math.floor(20.6+0.5)+t;
                    local passes={};
                    local function pass(dx,dy,ink)
                        passes[#passes+1]={dx,dy,ink};
                        if bold then passes[#passes+1]={dx+1,dy,ink};end;
                    end;
                    if shadow then pass(1,1,128*16777216);end;
                    if outline then for _,offset in ipairs(around) do pass(offset[1],offset[2],outline_ink);end;end;
                    pass(0,0,0x80402010);
                    calls={};
                    for _,step in ipairs(passes) do client.draw_countdown(list,name,text,x+step[1],y+step[2],size,step[3],compact);end;
                    assert(#drawn>0 and equal(drawn,calls),'One glyph walk replayed for each pass draws what a renderer call per pass draws.');
                end;
            end;
        end;
    end;
end;
local current;
for index=#parsed_faces,1,-1 do
    local face=parsed_faces[index];
    if face.foreground.image and face.foreground.image.id==456 then current=face;break;end;
end;
local glyphs,looked=current.glyphs,0;
current.glyphs=setmetatable({},{__index=function(_,code)looked=looked+1;return glyphs[code];end});
calls={};countdown.draw(list,'Original FFXI','12',0,0,16,0xFFFFFFFF,{bold=true,shadow=true,outline=true});
current.glyphs=glyphs;
assert(#calls==40 and looked==2,'An outlined bold countdown walks its two glyphs once for all 20 passes.');

-- Check the real stock and configured XI View masks when their local DATs exist.
-- Two folders up from addons/libs, whatever its case or slashes.
local game=ASHITA_LIBS:gsub('\\','/'):gsub('/+$',''):gsub('/[^/]+/[^/]+$','');
for _,source in ipairs({
    {'Original FFXI',game..'/SquareEnix/FINAL FANTASY XI/ROM/119/51.DAT',24,11},
    {'XI View',game..'/polplugins/DATs/XiView-Standard/ROM/119/51.DAT',23,12},
}) do
    local file=io.open(source[2],'rb');
    if file then
        local data=file:read('*a');file:close();
        local parsed=assert(original_assets.parse(data,{'moji'}));
        raw=assert(parsed.textures['font    moji    ']);
        uploads={};generation=generation+1;
        local width,height=compact_box(source[1],'12m',16);
        assert(width==source[3] and height==source[4], 'Actual stock and XI View countdowns use their own foreground ink bounds.');
        for _,size in ipairs({8,10,12,16,24,32}) do
            for _,text in ipairs({'12m','9m','59s','1:02','12m\n9s'}) do compact_box(source[1],text,size);end;
        end;
        local old_reads,old_uploads=reads,uploads;
        for _=1,10 do compact_box(source[1],'12m',10);end;
        assert(reads==old_reads and uploads==old_uploads,'Compact metrics reuse parsed glyph bounds without new reads or uploads.');
    end;
end;
