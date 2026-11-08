local assets=require('ui.client_assets');
local function le32(n)
    return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256);
end;
local function chunk(kind,payload)
    local length=math.ceil((16+#payload)/16)*16;
    return 'TEST'..le32(length/16*128+kind)..string.rep('\0',8)..payload..string.rep('\0',length-16-#payload);
end;
local function texture(name)
    return chunk(0x20,'\161'..name..le32(40)..le32(4)..le32(4)..string.rep('\0',28)
        ..'3TXD'..le32(16)..le32(0)..string.rep('\0',16));
end;
local source=texture('font    moji    ')..texture('menu    gauge   ');
local function atlas(width,height)
    return 'DDS '..le32(124)..le32(0x100F)..le32(height)..le32(width)..le32(width*4)
        ..le32(0)..le32(1)..string.rep('\0',44)..le32(32)..le32(0x41)..le32(0)..le32(32)
        ..le32(0xFF0000)..le32(0xFF00)..le32(0xFF)..le32(0xFF000000)..le32(0x1000)..string.rep('\0',16)
        ..string.rep('\255',width*height*4);
end;
local dds=atlas(256,128);
local reads,uploads,released,created,fail_mode=0,0,{},0;
local api={game_root=function()return 'C:/Game';end,ashita_root=function()return 'C:/Ashita';end,
    read=function(path)
        reads=reads+1;
        if path:find('/config/pivot/pivot.ini',1,true) then return '[overlays]\n0=XI View\n';end;
        if path:find('/ROM/119/51.DAT',1,true) then return source;end;
        return nil,'Fixture does not need menu textures.';
    end,
    upload=function(bytes,width,height)
        uploads=uploads+1;
        assert(bytes:sub(1,4)=='DDS ');
        if fail_mode=='throw' then error('Device unavailable.');end;
        created=created+1;local id=created;
        local release=function()released[id]=(released[id] or 0)+1;assert(released[id]==1,'Each uploaded texture releases once.');end;
        if fail_mode=='partial' then return {id=0,release=release},'Partial upload failed.';end;
        return {id=id,release=release};
    end};
assets._set_platform_for_tests(api);
assert(not assets.derived_texture('original_font','countdown_foreground',dds,256,128) and reads==0 and uploads==0,
    'A derived font cannot initialize sources from a draw call.');
assets.prepare();
assert(assets.status('original_font').available and assets.status('xiview_font').available);
local before_reads,before_uploads,generation=reads,uploads,assets.generation();
local original=assets.raw('original_font','moji');local original_dds=original.dds;
local stock=assets.derived_texture('original_font','countdown_foreground',dds,256,128);
local view=assets.derived_texture('xiview_font','countdown_foreground',dds,256,128);
assert(stock and view and stock.id~=view.id and uploads==before_uploads+2);
assert(stock.width==256 and stock.height==128 and stock.format=='A8R8G8B8');
for _=1,100 do
    assert(assets.derived_texture('original_font','countdown_foreground',dds,256,128)==stock);
    assert(assets.derived_texture('xiview_font','countdown_foreground',dds,256,128)==view);
end;
assert(reads==before_reads and uploads==before_uploads+2 and assets.generation()==generation,
    'Ready derived textures need no reads, uploads, or source-generation churn.');
assert(original==assets.raw('original_font','moji') and original.dds==original_dds,
    'Removing countdown shadows never changes ordinary client glyphs.');
local stable=uploads;
for _,bad in ipairs({false,0,-1,257,1.5,math.huge,0/0,'256'}) do
    assert(not assets.derived_texture('original_font','countdown_foreground',dds,bad,128));
    assert(not assets.derived_texture('original_font','countdown_foreground',dds,256,bad));
end;
assert(not assets.derived_texture('window','countdown_foreground',dds,256,128));
assert(not assets.derived_texture('original_font','other',dds,256,128));
assert(not assets.derived_texture('original_font','countdown_foreground',false,256,128));
assert(not assets.derived_texture('original_font','countdown_foreground',dds:sub(1,-2),256,128));
for _,at in ipairs({1,5,13,17,21,77,81,85,89,93,97,101,105}) do
    local bad=dds:sub(1,at-1)..string.char((dds:byte(at)+1)%256)..dds:sub(at+1);
    assert(not assets.derived_texture('original_font','countdown_foreground',bad,256,128));
end;
assert(not assets.derived_texture('original_font','countdown_foreground',dds:sub(1,-2)..'\0',256,128),
    'Changing source pixels requires an explicit source lifetime refresh.');
assert(uploads==stable and reads==before_reads,'Invalid atlases cannot reach upload or source reads.');
assets.clear();
assert(released[stock.id]==1 and released[view.id]==1 and assets.generation()>generation);
local after_clear=created;
assets.clear();
for id=1,after_clear do assert(released[id]==1);end;
assert(not assets.derived_texture('original_font','countdown_foreground',dds,256,128));

MOCK.now=10;assets.prepare();
before_reads,before_uploads,generation=reads,uploads,assets.generation();
fail_mode='partial';
local missing,why=assets.derived_texture('original_font','countdown_foreground',dds,256,128);
assert(not missing and why=='Partial upload failed.' and released[created]==1,
    'A failed upload releases a partially returned texture immediately.');
for _=1,50 do assert(not assets.derived_texture('original_font','countdown_foreground',dds,256,128));end;
assert(uploads==before_uploads+1 and reads==before_reads);
MOCK.now=14.999;assert(not assets.derived_texture('original_font','countdown_foreground',dds,256,128));
assert(uploads==before_uploads+1);
MOCK.now=15;fail_mode='throw';assert(not assets.derived_texture('original_font','countdown_foreground',dds,256,128));
assert(uploads==before_uploads+2);
MOCK.now=19.999;fail_mode=nil;assert(not assets.derived_texture('original_font','countdown_foreground',dds,256,128));
MOCK.now=20;local recovered=assets.derived_texture('original_font','countdown_foreground',dds,256,128);
assert(recovered and uploads==before_uploads+3 and reads==before_reads and assets.generation()==generation,
    'Retry after five seconds recovers from cached bytes without reloading client files.');
assets.clear();assets.clear();
for id=1,created do assert(released[id]==1,'Unload releases every source and derived texture exactly once.');end;
