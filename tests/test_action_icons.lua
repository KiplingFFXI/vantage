local icons,assets=require('ui.action_icons'),require('ui.client_assets');
local function le16(v) v=v%65536;return string.char(v%256,math.floor(v/256));end;
local function le32(v)return le16(v%65536)..le16(math.floor(v/65536));end;
local function chunk(kind,payload)
    local n=math.ceil((16+#payload)/16)*16;
    return 'TEST'..le32(n/16*128+kind)..string.rep('\0',8)..payload..string.rep('\0',n-16-#payload);
end;
local function texture(name)
    return chunk(0x20,string.char(0xA1)..name..le32(40)..le32(32)..le32(32)..string.rep('\0',28)
        ..'3TXD'..le32(1024)..le32(0)..string.rep('\0',1024));
end;
local base,tier='white   cure    ','misc    numsx   ';
local function part(name,x,y,w,h,flags,flip)
    local values={x or 0,y or 0,(x or 0)+(w or 16),y or 0,x or 0,(y or 0)+(h or 16),(x or 0)+(w or 16),(y or 0)+(h or 16),32,32,0,0};
    local p={};for _,v in ipairs(values) do p[#p+1]=le16(v);end;
    return table.concat(p)..string.char(flip or 0)..string.rep(string.char(127,64,32,127),4)..(flags or '\1\0\1\1')..name;
end;
local function layout(name,shapes)
    local out={name,'\2',base,tier,le16(#shapes)};
    for _,shape in ipairs(shapes) do out[#out+1]=string.char(#shape);for _,p in ipairs(shape) do out[#out+1]=p;end;end;
    return table.concat(out);
end;
local function uv_size(value,width,height)
    return value:sub(1,16)..le16(width)..le16(height)..value:sub(21);
end;
local alpha_bytes={};for i=0,7 do alpha_bytes[#alpha_bytes+1]=string.char(i*2+(i*2+1)*16);end;
local decoded=assets._action_dds_for_tests({format='DXT3',width=4,height=4,
    dds=string.rep('\0',128)..table.concat(alpha_bytes)..le16(0xF800)..le16(0x07E0)..string.rep(string.char(0xE4),4)},192);
assert(#decoded==128+64 and decoded:sub(1,4)=='DDS ');
for pixel=0,15 do
    assert(decoded:byte(132+pixel*4)==math.min(255,math.floor(pixel*17*384/255+0.5)),
        'Every DXT3 alpha level matches native MODULATE2X before addon opacity.');
end;
assert(decoded:sub(129,131)==string.char(0,0,255) and decoded:sub(133,135)==string.char(0,255,0),
    'Native alpha preparation leaves texture color endpoints unchanged.');
local shape=layout('menu    magiconw',{{part(base)},{part(base),part(tier,7,10,9,6)},
    {part(base,0,0,16,16,'\1\0\2\2')},{},{part(base,0,0,16,16,'\1\2\0\1')},
    {part(base,0,0,16,16,nil,3)},{uv_size(part(base),33,32)},
    {uv_size(part(base,0,0,16,16,nil,3),33,33)},{uv_size(part(base),65,32)}});
local parsed=assert(icons.parse(shape));
assert(parsed.count==9 and #parsed.shapes[1].parts==2 and parsed.shapes[1].right==16 and parsed.shapes[1].bottom==16);
assert(parsed.shapes[3].reason and not parsed.shapes[4].reason and parsed.shapes[4].approximate_blend,
    'Empty native shapes stay explicit; subtractive shadows retain native art with an identified approximation.');
for _,bad in ipairs({false,{},'',string.rep('x',1024*1024+1)}) do assert(not icons.parse(bad));end;
for length=1,#shape-1 do assert(not icons.parse(shape:sub(1,length)),'Every truncated shape structure is rejected.');end;
assert(not icons.parse('menu    magiconw'..'\0'..le16(2049)));
assert(not icons.parse('menu    magiconw'..'\0'..le16(1)..string.char(17)..string.rep('\0',17*61)));
local malformed=part(base);malformed=malformed:sub(1,29)..'\0'..malformed:sub(31);
assert(icons.parse(layout('menu    magiconw',{{malformed}})).shapes[0].reason,'Unsupported per-vertex gradients are not misrepresented.');

local files,reads,uploads,releases={},0,0,0;
files['C:/Game/ROM/280/15.DAT']=texture(base)..texture(tier)..chunk(0x31,shape);
files['C:/Game/ROM/324/95.DAT']=texture(base)..chunk(0x31,layout('menu    magico2w',{{part(base)}}));
files['C:/Game/ROM/119/51.DAT']=texture('menu    acre    ');
local api={game_root=function()return 'C:/Game';end,ashita_root=function()return 'C:/Ashita';end,
    xiview_path=function()return 'C:/View/ROM/119/51.DAT';end,
    read=function(path,limit)reads=reads+1;assert(limit<=16*1024*1024);return files[path],'Unavailable fixture';end,
    upload=function(dds,w,h)
        assert(dds:sub(1,4)=='DDS ' and w==32 and h==32);uploads=uploads+1;
        return {id=100+uploads,release=function()releases=releases+1;end};
    end};
icons.clear();assets._set_platform_for_tests(api);
local parses,parse=0,icons.parse;
icons.parse=function(...) parses=parses+1;return parse(...);end;
local images,rects={},{};
-- The binding copies each vector when it is called, as ImGui's does, so a drawer may refill its own.
local function copied(...)local out={...};for i,v in ipairs(out) do if type(v)=='table' then out[i]={v[1],v[2]}; end end;return out;end;
local list={AddImage=function(_,...)images[#images+1]=copied(...);end,AddRectFilled=function(_,...)rects[#rects+1]=copied(...);end};
assert(not icons.draw(list,'Original FFXI',0,0,0,0,32,1) and reads==0,'Drawing never discovers or reads files.');
icons.prepare();local prepared_reads=reads;
assert(prepared_reads==4 and parses==2,'Preparing reads the overlay settings and the stock pack once, and parses its two layouts; XI View waits for its first draw.');
assert(uploads==0,'Preparing source data never eagerly uploads every icon.');
assert(icons.draw(list,'Original FFXI',1,0,10,20,32,1) and #images==2 and uploads==2,'Composite artwork draws each native layer.');
assert(images[1][2][1]==10 and images[1][2][2]==20 and images[1][3][1]==42 and images[1][3][2]==52);
assert(images[2][2][1]==24 and images[2][2][2]==40 and images[2][3][1]==42 and images[2][3][2]==52,'Tier mark geometry scales inside the original icon.');
assert(images[1][6]==255+130*256+66*65536+255*16777216,'Native RGB tint is retained; doubled texture alpha is prepared before upload.');
assert(icons.draw(list,'Original FFXI',65535,1,0,0,16,0.5));
assert(images[#images][6]==255+130*256+66*65536+128*16777216,'Addon opacity multiplies prepared native alpha.');
assert(icons.draw(list,'XI View',1,0,0,0,32,1) and uploads==2,'An absent XI View file shares stock textures.');
assert(reads==prepared_reads+3,'The first XI View draw looks for its three files once.');prepared_reads=reads;
assert(parses==2,'XI View without its own files shares the stock layouts, parsed once.');
icons.parse=parse;
assert(icons.status('XI View',1,0).using=='original');
assert(icons.draw(list,'Original FFXI',1000,0,0,0,32,1) and uploads==3,'Secondary icon indices use their own native layout.');
assert(icons.draw(list,'Original FFXI',2,0,0,0,32,1) and #rects==1,'Source-alpha/zero native layers have their black backing.');
local shadow_rects=#rects;
assert(icons.draw(list,'Original FFXI',4,0,0,0,32,1) and images[#images][6]==255*16777216
    and #rects==shadow_rects and icons.status('Original FFXI',4,0).approximate_blend,
    'Native subtractive shadow uses its own alpha texture, never an opaque rectangle or missing icon.');
assert(icons.draw(list,'Original FFXI',5,0,0,0,32,1));
local flipped=images[#images];assert(flipped[4][1]==1 and flipped[4][2]==1 and flipped[5][1]==0 and flipped[5][2]==0);
local before=#images;
assert(icons.draw(list,'Original FFXI',6,nil,0,0,33,1) and #images==before+2,'The native 33-pixel rectangle wraps across a 32-pixel texture.');
assert(images[before+1][3][1]==32 and images[before+2][2][1]==32 and images[before+2][3][1]==33);
assert(images[before+1][5][1]==1 and images[before+2][4][1]==0 and images[before+2][5][1]==1/32,'The wrapped sliver samples the start of the same native texture.');
before=#images;assert(icons.draw(list,'Original FFXI',7,nil,0,0,33,1) and #images==before+4);
assert(images[before+4][2][1]==0 and images[before+4][2][2]==0 and math.abs(images[before+4][3][1]-1)<0.00001
    and math.abs(images[before+4][3][2]-1)<0.00001,'Wrapped pieces retain both native flips.');
for _,id in ipairs({3,8,677,1089,65535,-1,1.5,math.huge,0/0}) do
    local n=#images;assert(not icons.draw(list,'Original FFXI',id,nil,0,0,32,1) and #images==n,'Missing art never draws an arbitrary status image.');
end;
for _,size in ipairs({0,-1,513,0/0,math.huge,'32'}) do assert(not icons.draw(list,'Original FFXI',0,0,0,0,size,1));end;
for _=1,200 do assert(icons.draw(list,'Original FFXI',1,0,0,0,32,1));icons.prepare();end;
assert(reads==prepared_reads and uploads==3,'Steady draws do not read files or recreate textures.');
icons.clear();icons.clear();assert(releases==3,'Every uploaded action texture is released exactly once.');

files['C:/View/ROM/280/15.DAT']=texture(base)..chunk(0x31,layout('menu    magiconw',{{part(base)}}));
icons.prepare();assert(icons.draw(list,'XI View',1,nil,0,0,32,1) and icons.status('XI View',1,nil).using=='original',
    'An older XI View layout falls back per missing native shape.');icons.clear();
files['C:/View/ROM/280/15.DAT']=texture(base)..chunk(0x31,layout('menu    magiconw',{{part(base,0,0,16,16,'\1\2\1\2')}}));
icons.prepare();assert(icons.draw(list,'XI View',0,nil,0,0,32,1) and icons.status('XI View',0,nil).using=='original',
    'An unsupported XI View shape uses the same stock action icon.');icons.clear();
files['C:/View/ROM/280/15.DAT']=texture(base)..chunk(0x31,layout('menu    magiconw',{{part('missing texture ')}}));
icons.prepare();before=#images;assert(icons.draw(list,'XI View',0,nil,0,0,32,1) and #images==before+1,
    'Missing custom shape dependencies fall back before drawing any partial icon.');icons.clear();
files['C:/View/ROM/280/15.DAT']=nil;

local original_clock=os.clock;local now=10;os.clock=function()return now;end;
local attempts=0;
api.upload=function()
    attempts=attempts+1;
    if attempts==1 then return {id=0,release=function()releases=releases+1;end},'Device unavailable';end;
    return {id=900+attempts,release=function()releases=releases+1;end};
end;
icons.prepare();local n=#images;
assert(not icons.draw(list,'Original FFXI',1,0,0,0,32,1) and #images==n,'A missing layer cannot leave a partial icon.');
for _=1,40 do assert(not icons.draw(list,'Original FFXI',1,0,0,0,32,1));end;
assert(attempts==1,'Failed uploads are bounded during a retry interval.');
now=41;assert(icons.draw(list,'Original FFXI',1,0,0,0,32,1) and attempts==3,'Recovery retries cached bytes, not files.');

-- New action textures are made within each Present's budget of new icon textures (client_assets.spend_upload): past
-- it an icon draws nothing yet, counts as drawn so nothing is put in its place, and is made in a later Present.
local failing,sent=false,{};
api.upload=function(dds)
    sent[#sent+1]=dds;
    if failing then return nil,'Device unavailable';end;
    uploads=uploads+1;
    return {id=3000+uploads,release=function()releases=releases+1;end};
end;
icons.clear();icons.prepare();uploads=0;
assets.icon_frame();
for alpha=1,8 do assert(assets.action_texture('original',false,base,alpha),'Up to eight new textures in a Present.');end;
local made,why,waiting=assets.action_texture('original',false,base,9);
assert(not made and why==nil and waiting==true and uploads==8,'The ninth waits for a later Present.');
local drawn=#images;
assert(icons.draw(list,'Original FFXI',1000,0,0,0,32,1) and #images==drawn and uploads==8,
    'An icon whose texture waits draws nothing yet and counts as drawn.');
assert(assets.action_texture('original',false,base,1) and uploads==8,'A texture made already costs nothing.');
assets.icon_frame();
assert(assets.action_texture('original',false,base,9) and uploads==9,'The next Present makes it.');
assert(icons.draw(list,'Original FFXI',1000,0,0,0,32,1) and #images==drawn+1 and uploads==10,'The icon draws once it is made.');

-- The converted pixels go once the upload is good, and stay while a retry waits.
local function upvalue(fn,wanted)
    for index=1,200 do
        local name,value=debug.getupvalue(fn,index);
        if name==wanted then return value;end;
        if not name then break;end;
    end;
end;
local raw=upvalue(assets.action_texture,'action_source')('original','main').data.textures[base];
assert(raw.action_dds[1]==nil and raw.action_dds[9]==nil,'The converted pixels go once the texture is made.');
failing=true;
assert(not assets.action_texture('original',false,base,10) and raw.action_dds[10],'A failed upload keeps its converted pixels.');
local kept=raw.action_dds[10];
failing,now=false,now+31;assets.icon_frame();
assert(assets.action_texture('original',false,base,10) and sent[#sent]==kept and raw.action_dds[10]==nil,
    'The retry uploads the kept pixels, then lets them go.');

-- Pixels that can't be converted never will be, so they aren't tried again and cost no later Present's budget.
files['C:/Game/ROM/280/15.DAT']=files['C:/Game/ROM/280/15.DAT']..chunk(0x20,string.char(0xA1)..'menu    flat    '
    ..le32(40)..le32(32)..le32(32)..string.rep('\0',28)..'1TXD'..le32(512)..le32(0)..string.rep('\0',512));
icons.clear();icons.prepare();assets.icon_frame();
local _,problem=assets.action_texture('original',false,'menu    flat    ',192);
assert(problem=='Unsupported native action pixel format.','A texture that can\'t be converted says why.');
now=now+1000;assets.icon_frame();uploads=0;
for _=1,20 do assert(select(2,assets.action_texture('original',false,'menu    flat    ',192))==problem);end;
for alpha=1,8 do assert(assets.action_texture('original',false,base,alpha));end;
assert(uploads==8,'Asking for it again converts nothing and spends none of the Present\'s budget.');
os.clock=original_clock;icons.clear();assets._set_platform_for_tests(nil);
return 'Native action icon shapes, selection, layers, tints, bounds, fallback, caching and cleanup';
