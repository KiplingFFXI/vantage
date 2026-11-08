local assets=require('ui.client_assets');
local function le32(n)
    return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256);
end;
local function texture(name,size)
    size=size or 4;
    local bytes=size*size;
    local payload='\161'..name..le32(40)..le32(size)..le32(size)..string.rep('\0',28)
        ..'3TXD'..le32(bytes)..le32(0)..string.rep('\0',bytes);
    local length=math.ceil((16+#payload)/16)*16;
    return 'TEST'..le32(length/16*128+0x20)..string.rep('\0',8)..payload..string.rep('\0',length-16-#payload);
end;
-- A window frame's pieces at the sizes the client draws them at.
local window=texture('menu    newtex  ',128)..texture('menu    hfr1    ',32)..texture('menu    corner  ',32)..texture('menu    vfr1    ',32);
local font=texture('font    moji    ')..texture('menu    gauge   ');
local reads,uploads,releases,clocks,fail,fail_at=0,0,0,0,false,nil;
local clock=os.clock;
os.clock=function() clocks=clocks+1;return clock();end;
local api={game_root=function()return 'C:/Game';end,ashita_root=function()return 'C:/Ashita';end,
    xiview_path=function()return 'C:/XIView/ROM/119/51.DAT';end,
    read=function(path)
        reads=reads+1;
        return path:find('/ROM/119/51.DAT',1,true) and font or window;
    end,
    upload=function()
        uploads=uploads+1;
        if fail or uploads==fail_at then return nil,'Device not ready.';end;
        return {id=uploads,release=function()releases=releases+1;end};
    end};
assets._set_platform_for_tests(api);
assert(not assets.retry_pending() and not assets.retry() and reads==0);
assert(assets.prepare() and not assets.retry_pending());
local before_reads,before_uploads,before_clocks=reads,uploads,clocks;
for _=1,1000 do
    assert(assets.retry() and assets.texture('window','newtex'));
    assert(assets.status('original_font').available);
end;
assert(reads==before_reads and uploads==before_uploads and clocks==before_clocks,
    'Ready cached assets need no retry deadline checks, uploads or file reads.');
assets.clear();
assert(releases==before_uploads and not assets.retry_pending());
MOCK.now,fail=0,true;
assert(not assets.prepare() and assets.retry_pending());
local failed_uploads=uploads;before_reads=reads;
for tick=1,4 do MOCK.now=tick;assert(not assets.retry());end;
assert(uploads==failed_uploads and reads==before_reads,'Pending recovery keeps the five-second deadline.');
MOCK.now=5;fail=false;
assert(assets.retry() and not assets.retry_pending());
assert(uploads>failed_uploads and reads==before_reads,'Recovery uses cached bytes at its original deadline.');
local generation=assets.generation();before_clocks=clocks;
for _=1,1000 do assert(assets.prepare());end;
assert(clocks==before_clocks and assets.generation()==generation,'Ready recovery returns to the no-clock fast path.');
assets.clear();

-- The window frame in use and the two base font textures upload at load. XI View uploads at its first use.
MOCK.now,fail_at=10,uploads+4+2+1;
assert(assets.prepare() and not assets.retry_pending() and uploads==fail_at-1,'XI View waits for its first use.');
local original=assets.texture('original_font','moji');
assert(original and assets.status('original_font').available and not assets.status('xiview_font').available
    and assets.retry_pending(),'A failed XI View upload does not hide the loaded Original FFXI font.');
before_reads,before_uploads=reads,uploads;
generation=assets.generation();
MOCK.now=14.99;
assert(assets.retry() and assets.retry_pending());
assert(reads==before_reads and uploads==before_uploads,'A partly loaded set keeps the pending upload deadline.');
MOCK.now=15;
assert(assets.retry() and not assets.retry_pending() and assets.status('xiview_font').available);
assert(assets.texture('original_font','moji')==original and assets.generation()>generation,
    'XI View recovery updates the font generation without replacing successful textures.');
assert(reads==before_reads,'Partial recovery uploads cached bytes without reading files again.');
assets.clear();

local retries=0;
package.loaded['ui.client_assets']={
    prepare=function()end,retry=function()retries=retries+1;end,
    retry_pending=function()return false;end,generation=function()return 0;end,
    raw=function()end,texture=function()end,status=function()return {};end,
};
package.loaded['ui.client_fonts']=nil;
local fonts=require('ui.client_fonts');fonts.prepare();
for _,name in ipairs({'Agave','Original FFXI','XI View'}) do
    for _=1,1000 do
        fonts.measure(name,'Timer',16);fonts.draw({},name,'Timer',0,0,16,0xffffffff);
        fonts.reason(name);fonts.available(name);fonts.measure_countdown(name,'10',16);
    end;
end;
assert(retries==0,'Font lookups and fallback rendering never request recovery when assets have no pending uploads.');
package.loaded['ui.client_assets'].retry_pending=function()return true;end;
fonts.measure('Agave','Timer',16);fonts.draw({},'Agave','Timer',0,0,16,0xffffffff);
assert(retries==0,'Nonbitmap fonts bypass bitmap recovery even when an upload is pending.');
fonts.measure('Original FFXI','Timer',16);
assert(retries==1,'A pending native upload remains eligible for recovery.');
os.clock=clock;
