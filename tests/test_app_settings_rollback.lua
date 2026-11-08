-- A settings page that fails changes nothing. What it wrote is put back in memory and on disk, so
-- closing the stopped window by /vg or by its Close button saves only real settings.
local store,custom=require('core.store'),require('core.customization');
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(snapshot);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
require('ui.party_hud').draw=function()return 0,{};end;
require('ui.native_party_hud').draw=function()return 0,{};end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end};
-- Home is the fixture's page: each step gives it what to do.
local page;
package.loaded['ui.main_page']={labels={},draw=function(_,s,_,callbacks,ui)if page then page(s,callbacks,ui);end;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local function settings()return app.state.settings;end;
local function disk()return store.read(app.state.path);end;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
local function frame(click)
    if click then MOCK.clicks[click]=true;end;
    MOCK.frame(.11);
    if click then assert(not MOCK.clicks[click],'Fixture: the window received its click: '..click);end;
end;
local function reports()
    local count=0;
    for _,message in ipairs(MOCK.printed)do if message:find('Fixture settings page failure.',1,true)then count=count+1;end;end;
    return count;
end;
local function failure(step)
    local count=reports();
    page=function(s,callbacks,ui)step(s,callbacks,ui);error('Fixture settings page failure.');end;
    frame();page=nil;
    assert(reports()==count+1 and not app.callbacks.settings_blocks_input(200,200,false,false),'Fixture: the page failed and stopped.');
end;
-- The main page's own button saves the open window, so a close has to be saved to reach disk.
local function reopen()
    -- Navigation waits for the next save, which writes the open window.
    settings().window.open,settings().window.tab,app.state.settings_stopped=true,'Home',nil;frame();frame();app.callbacks.editor_changed();app.callbacks.save();
    assert(settings().window.open and disk().window.open==true and app.callbacks.settings_blocks_input(200,200,false,false),
        'Fixture: the window is drawn again and saved open.');
end;

MOCK.fire('load');app.refresh(0);
local file_path=app.state.path;
app.state.dirty=true;assert(app.callbacks.save(),'Fixture: the settings are on disk.');
command('/vg');frame();frame();app.callbacks.editor_changed();app.callbacks.save();
assert(settings().window.open and settings().window.tab=='Home' and disk().window.open==true,'Fixture: Home is drawn and saved open.');
local size=settings().style.font_size;

-- A page that writes without reporting it and then fails leaves nothing behind for /vg to save.
failure(function(s)s.style.font_size=size+15;end);
assert(settings().style.font_size==size,'What a failing page wrote is put back at once.');
command('/vg');
assert(not settings().window.open,'Fixture: /vg closes the stopped window.');
local file=disk();
assert(file.window.open==false and file.style.font_size==size,'/vg saves the close and nothing the failed page wrote.');

-- The same for the X on the window's title bar, after a command brought it back.
reopen();
failure(function(s)s.style.font_size=size+16;end);
assert(settings().style.font_size==size,'The second failure is put back too.');
reopen();
frame('Title bar X');
assert(not settings().window.open,'Fixture: the X closes the window.');
file=disk();
assert(file.window.open==false and file.style.font_size==size,'The X saves the close and nothing the failed page wrote.');

-- A held slider's edit isn't saved yet. A page that then fails, after saving its own edit and replacing
-- a table, gives back exactly the held edit, in the same tables and still unsaved. The file is put back
-- as it was, and the held edit is saved as one Undo step once it's let go.
reopen();
local s=settings();
local panels,buffs=s.panels,s.panels.self_buffs;
local width,x=buffs.width,buffs.x;
MOCK.mouse_down=true;
page=function(current,_,ui)ui.changed(function()current.panels.self_buffs.width=width+40;end,false,'Width');end;
frame();page=nil;
assert(app.state.dirty and buffs.width==width+40 and disk().panels.self_buffs.width==width,
    'Fixture: the held edit is in memory and not on disk.');
local history=#app.state.history;
local midway;
failure(function(current,_,ui)
    current.style.font_size=size+17;
    ui.changed(function()current.panels.self_buffs.x=x+9;current.panels.self_buffs={};end,true,'Position');
    midway=disk();
end);
MOCK.mouse_down=false;
assert(midway and midway.style.font_size==size+17 and next(midway.panels.self_buffs)==nil,'Fixture: the failing page saved its edit.');
assert(settings()==s and s.panels==panels and s.panels.self_buffs==buffs,'The settings are put back in the same tables.');
assert(buffs.width==width+40,'The held edit stays.');
assert(buffs.x==x and s.style.font_size==size,'Everything the failing page wrote is put back.');
file=disk();
assert(file.panels.self_buffs.width==width and file.panels.self_buffs.x==x and file.style.font_size==size,
    'Its save is undone on disk, which holds what it held before the page.');
assert(app.state.dirty and app.state.transaction and #app.state.history==history,'The held edit still waits to be saved.');
for _=1,6 do frame(); end;
file=disk();
assert(file.panels.self_buffs.width==width+40 and file.panels.self_buffs.x==x and file.style.font_size==size,
    'Once let go, the held edit is saved.');
assert(#app.state.history==history+1 and app.callbacks.history_status().undo_label=='Width','The held edit is one Undo step.');
command('/vg undo');
assert(settings().panels.self_buffs.width==width and settings().panels.self_buffs.x==x and settings().style.font_size==size,
    'Undo restores the settings from before the held edit, without the failed page.');

-- A failing page that saved an edit loses no change to redo.
reopen();
command('/vg set style.font_size 25');
command('/vg undo');
assert(settings().style.font_size==size and app.callbacks.history_status().redo==1,'Fixture: one change to redo.');
local redo,undo=app.state.redo[1],#app.state.history;
failure(function(current,_,ui)ui.changed(function()current.panels.self_buffs.width=width+77;end,true,'Width again');end);
assert(app.state.redo[1]==redo and #app.state.redo==1 and #app.state.history==undo,'The failed save takes no Undo step and clears no redo.');
assert(settings().panels.self_buffs.width==width and disk().panels.self_buffs.width==width,'Its edit is put back in memory and on disk.');
command('/vg redo');
assert(settings().style.font_size==25,'The change to redo still redoes.');

-- A page that undoes and then fails leaves the settings, Undo and the file as they were.
reopen();
s=settings();
undo,redo=#app.state.history,#app.state.redo;
failure(function(_,callbacks)callbacks.undo();end);
assert(settings()==s and s.style.font_size==25,'An undo by a failing page is put back.');
assert(#app.state.history==undo and #app.state.redo==redo,'Undo and redo are as they were.');
assert(disk().style.font_size==25,'The file is as it was.');

-- What the failing page read back about its own change isn't kept either.
reopen();
assert(app.callbacks.profile_save('Beta',false) and not app.callbacks.profile_summary().status.modified,
    'Fixture: the settings match the Beta profile.');
failure(function(current,callbacks)current.style.font_size=size+19;app.state.profile_summary_cache=nil;callbacks.profile_summary();end);
assert(not app.callbacks.profile_summary().status.modified,'The profile summary shows no change from the failed page.');

-- A page whose save failed leaves nothing to save or retry, even after a character switch.
reopen();
MOCK.file_replace_error=true;
failure(function(current,_,ui)ui.changed(function()current.style.font_size=size+18;end,true,'Font size');end);
MOCK.file_replace_error=false;
assert(settings().style.font_size==25 and not app.state.dirty,'A failing page whose save failed leaves nothing to save.');
snapshot.id,snapshot.name=1002,'Other';
frame();
snapshot.id,snapshot.name=1001,'Tester';
frame();
assert(app.state.path==file_path and settings().style.font_size==25,'Switching characters and back brings none of it back.');

-- Keeping settings that didn't change walks them and copies nothing.
local kept=custom.keep(nil,s);
local node=kept.panels.self_buffs;
assert(custom.keep(kept,s)==kept and kept.panels.self_buffs==node,'Unchanged settings keep the same copy.');
s.panels.self_buffs.width=width+5;
assert(custom.keep(kept,s)==kept and kept.panels.self_buffs==node and node.width==width+5,'A changed value is copied in place.');
-- Putting them back gives the tables and keys they had when kept.
local sections,visibility=s.window.sections,{};
for key,value in pairs(s.visibility)do visibility[key]=value;end;
sections.Gone,s.visibility=true,visibility;
custom.keep(kept,s);
sections.Gone=nil;
custom.keep(kept,s);
sections.Gone,sections.Added,s.visibility=true,true,{};
assert(custom.restore(kept)==s and s.window.sections==sections and s.visibility==visibility,'The kept tables are put back.');
assert(sections.Gone==nil and sections.Added==nil and visibility.hide_map~=nil,'Keys added since are taken out and kept values put back.');
