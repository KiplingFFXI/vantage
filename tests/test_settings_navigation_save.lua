-- Clicking through the settings window writes no file: a save stalls the frame it runs in. Which page and
-- sections are open is written with the next save, when the window closes, before another character
-- loads and on unload. An edit still saves at once.
local store=require('core.store');
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=3,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(snapshot);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
require('ui.party_hud').draw=function()return 0,{};end;
require('ui.native_party_hud').draw=function()return 0,{};end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end};
-- A section header is open when the fixture says so.
local headers,broken={},false;
local MORE='More look';
require('imgui').CollapsingHeader=function(label)
    return headers[label]==true;
end;
-- The page fails after its headers: the swatches come under Colors.
local swatch=require('imgui').ColorEdit4;
require('imgui').ColorEdit4=function(...)
    if broken then error('Fixture settings page failure.');end;
    return swatch(...);
end;
local app=dofile(ADDON_DIR..'/vantage.lua');
local writes,failing={},nil;
local write=store.write;
store.write=function(path,...)
    if path==failing then return false,'Fixture write failure.';end;
    writes[path]=(writes[path] or 0)+1;return write(path,...);
end;
local function settings()return app.state.settings;end;
local function disk(path)return store.read(path or app.state.path);end;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
local function frame(click)
    if click then MOCK.clicks[click]=true;end;
    MOCK.frame(.11);
    if click then assert(not MOCK.clicks[click],'Fixture: the window received its click: '..click);end;
end;
local function written()return writes[app.state.path] or 0;end;
-- The main page, however the window was left: open, closed or stopped.
local function open_main()settings().window.open,settings().window.tab,app.state.settings_stopped=true,'Home',nil;end;

MOCK.fire('load');app.refresh(0);
app.state.dirty=true;assert(app.callbacks.save(),'Fixture: the settings are on disk.');
local tester,before=app.state.path,written();
command('/vg');frame();frame();
assert(settings().window.open,'Fixture: the window is open.');
assert(written()==before and disk().window.open~=true,'Opening the window and drawing it write nothing.');

-- Page links and section headers.
frame('Help');
assert(settings().window.tab=='Help','Fixture: the link opened Help.');
frame('< Back##frame');
assert(settings().window.tab=='Home','Fixture: Back opened the main page.');
headers[MORE]=true;frame();
assert(settings().window.sections['Home/More look']==true,'Fixture: the More look header opened.');
for _=1,10 do frame();end;
assert(written()==before,'Navigation writes nothing, at the click or after the edit autosave delay.');
assert(not app.state.dirty and #app.state.history==0,'Navigation is no edit: no autosave waits and nothing goes into Undo.');
assert(disk().window.sections['Home/More look']~=true,'Fixture: the open section is not on disk yet.');

-- The next save writes it along with the edit, and the edit is saved at once.
command('/vg set style.font_size 25');
assert(written()==before+1,'An edit still saves at once.');
local file=disk();
assert(file.style.font_size==25 and file.window.open==true and file.window.sections['Home/More look']==true,
    'The next save writes which window, page and sections are open.');
for _=1,10 do frame();end;
assert(written()==before+1,'Nothing is left to write after that save.');

-- A page that fails puts back the navigation its draw changed, and leaves nothing waiting to be saved.
headers.Colors,broken=true,true;frame();broken=false;
assert(settings().window.sections['Home/Colors']~=true and not app.state.navigation_dirty,
    'A failed page leaves no navigation waiting.');
headers.Colors=false;open_main();frame();
assert(not app.state.navigation_dirty and written()==before+1,'Fixture: the window is back with nothing waiting.');

-- Closing the window saves at once, with the sections opened since.
headers.Colors=true;frame();
assert(settings().window.sections['Home/Colors']==true and written()==before+1,'Fixture: another header opened unsaved.');
frame('Title bar X');
file=disk();
assert(not settings().window.open and written()==before+2 and file.window.open==false
    and file.window.sections['Home/Colors']==true,'Closing the window saves it closed and what was open.');

-- Another character loading first saves this one's navigation to this one's file.
command('/vg');frame();headers.Colors=false;frame();
assert(settings().window.sections['Home/Colors']==false and disk().window.sections['Home/Colors']==true,
    'Fixture: a closed header is not saved yet.');
snapshot.id,snapshot.name=2002,'Other';frame();
assert(app.state.path~=tester,'Fixture: Other is loaded.');
file=disk(tester);
assert(file.window.open==true and file.window.sections['Home/Colors']==false,
    'A character switch first saves the previous character\'s open window and sections.');
assert(not app.state.navigation_dirty,'Other starts with nothing waiting.');

-- When that save fails, the next character still starts with nothing waiting.
local other=app.state.path;
headers={};open_main();frame();headers[MORE]=true;frame();
assert(settings().window.sections['Home/More look']==true and app.state.navigation_dirty,'Fixture: Other has unsaved navigation.');
-- The refresh loads Tester before any draw of Tester's window.
failing=other;snapshot.id,snapshot.name=1001,'Tester';app.refresh(MOCK.now);failing=nil;
local other_file=disk(other);
assert(app.state.path==tester and not (other_file.window and other_file.window.sections['Home/More look']),'Fixture: saving Other failed.');
assert(not app.state.navigation_dirty,'Tester starts with nothing waiting after saving Other failed.');

-- Unload saves it too.
headers={};open_main();frame();headers[MORE]=true;frame();
assert(settings().window.sections['Home/More look']==true and app.state.navigation_dirty,'Fixture: Tester has unsaved navigation.');
MOCK.fire('unload');
file=disk(tester);
assert(file.window.open==true and file.window.sections['Home/More look']==true,'Unload saves the open window and sections.');
return true;
