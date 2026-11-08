-- The character's settings file can't be read when the character loads: another program holds it for a moment,
-- or it has invalid JSON the user then repairs. Vantage runs on defaults and says the file was kept unchanged.
-- It must stay unchanged: no change saved, retried or saved at unload replaces it with defaults. Once the file
-- reads, it is loaded.
local store=require('core.store');
local defaults=require('ui.defaults');
local root=require('core.identity').root():gsub('[/'..string.char(92)..']+$','')..'/';
local path=root..'Tester_1001/settings.json';
local saved=defaults.make();
saved.panels.self_buffs.x,saved.panels.self_buffs.locked=777,false;
saved.alerts.rules={defaults.rule('rule_1')};
assert(store.write(path,saved),'Fixture: saved settings.');
local handle=assert(io.open(path,'rb'));local good=handle:read('*a');handle:close();
local held;
local open=io.open;
io.open=function(name,mode,...)
    if held and name==held and (mode=='rb' or mode=='r') then held=nil;return nil,'Permission denied',13;end;
    return open(name,mode,...);
end;
local SNAP={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(SNAP);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
require('ui.party_hud').draw=function()return 0,{};end;
require('ui.native_party_hud').draw=function()return 0,{};end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end,suspend=function()return true;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local function settings()return app.state.settings;end;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
local function frames(count)for _=1,count do MOCK.frame(.11);end;end;
local function intact(label)
    local file=store.read(path);
    assert(file and file.panels.self_buffs.x==777 and file.panels.self_buffs.locked==false and #file.alerts.rules==1,
        label..': the file is unchanged (x '..tostring(file and file.panels.self_buffs.x)..').');
end;
local function said(text)
    for _,message in ipairs(MOCK.printed)do if message:find(text,1,true)then return true;end;end;
    return false;
end;

-- 1. Held for a moment at load.
held=path;
MOCK.fire('load');app.refresh(0);
assert(held==nil and said('kept unchanged'),'Fixture: the first read was refused and reported.');
assert(settings().panels.self_buffs.x~=777,'Fixture: the session runs on defaults.');
frames(5);
command('/vg set style.font_size 20');frames(20);
intact('A change saved after a refused read');
-- Read again a few seconds later, it loads.
frames(50);
assert(settings().panels.self_buffs.x==777 and settings().panels.self_buffs.locked==false and settings().style.font_size~=20,
    'Once the file reads, it replaces the defaults.');
intact('After it loads');
command('/vg set style.font_size 21');frames(10);
assert(store.read(path).style.font_size==21 and store.read(path).panels.self_buffs.x==777,'Later changes save onto it.');

-- 2. Invalid JSON at load, a change made while it is invalid, then the file repaired with the game running:
-- the queued save doesn't land on the repaired file, and nor does the unload save.
MOCK.fire('unload');
assert(store.write(path,saved),'Fixture: saved settings again.');
handle=assert(open(path,'rb'));good=handle:read('*a');handle:close();
local file=assert(open(path,'wb'));file:write(good:sub(1,#good-5));file:close();
SNAP.id,SNAP.name=1001,'Tester';
app=dofile(ADDON_DIR..'/vantage.lua');
MOCK.fire('load');app.refresh(MOCK.now);
assert(settings().panels.self_buffs.x~=777,'Fixture: the invalid file leaves defaults.');
command('/vg set style.font_size 20');frames(3);
file=assert(open(path,'wb'));file:write(good);file:close();
command('/vg lock');frames(2);
MOCK.fire('unload');
intact('A repaired file');
