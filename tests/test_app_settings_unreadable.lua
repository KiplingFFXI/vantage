-- A file a failing settings page wrote, which can't be read for a moment when the page's changes are
-- put back (another program holds it), counts as not put back. The settings and the shared layout are
-- saved again from what was put back. A profile file, reported, and a shared layout no longer shared
-- are put back once they can be read. Only a file that reads as something else was written by someone
-- else and is kept.
local store=require('core.store');
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(snapshot);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
require('ui.party_hud').draw=function()return 0,{};end;
require('ui.native_party_hud').draw=function()return 0,{};end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end};
local page;
package.loaded['ui.main_page']={labels={},draw=function(_,s,_,callbacks,ui)if page then page(s,callbacks,ui);end;end};
-- One read of the held path fails, as when another program has the file open.
local held;
local open=io.open;
io.open=function(path,mode,...)
    if held and path==held and (mode=='rb' or mode=='r') then held=nil;return nil,'Permission denied',13;end;
    return open(path,mode,...);
end;
local app=dofile(ADDON_DIR..'/vantage.lua');
local root=require('core.identity').root():gsub('[\\/]+$','')..'/';
local profiles_path,layout_path=root..'profiles.json',root..'shared_layout.json';
local function settings()return app.state.settings;end;
local function disk(path)return store.read(path or app.state.path);end;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
local function frame(click)
    if click then MOCK.clicks[click]=true;end;
    MOCK.frame(.11);
    if click then assert(not MOCK.clicks[click],'Fixture: the window received its click: '..click);end;
end;
local function printed(text)
    local count=0;
    for _,message in ipairs(MOCK.printed)do if message:find(text,1,true)then count=count+1;end;end;
    return count;
end;
local function failure(step)
    local count=printed('Fixture settings page failure.');
    page=function(s,callbacks,ui)step(s,callbacks,ui);error('Fixture settings page failure.');end;
    frame();page=nil;
    assert(printed('Fixture settings page failure.')==count+1,'Fixture: the page failed.');
    assert(held==nil,'Fixture: putting the page\'s changes back met the held file.');
end;
local function reopen()
    -- Navigation waits for the next save, which writes the open window.
    settings().window.open,settings().window.tab,app.state.settings_stopped=true,'Home',nil;frame();frame();app.callbacks.editor_changed();app.callbacks.save();
    assert(settings().window.open and disk().window.open==true,'Fixture: the window is drawn again and saved open.');
end;

MOCK.fire('load');app.refresh(0);
app.state.dirty=true;assert(app.callbacks.save(),'Fixture: the settings are on disk.');
command('/vg');frame();frame();app.callbacks.editor_changed();app.callbacks.save();
assert(settings().window.open and disk().window.open==true,'Fixture: Home is drawn and saved open.');

-- The settings file.
local size,settings_file=settings().style.font_size,disk();
failure(function(current,_,ui)
    ui.changed(function()current.style.font_size=size+20;end,true,'Font size');
    assert(disk().style.font_size==size+20,'Fixture: the page saved its font size.');
    held=app.state.path;
end);
assert(settings().style.font_size==size,'Fixture: the font size is put back in memory.');
assert(app.state.dirty,'Settings whose file could not be read back wait to be saved.');
for _=1,6 do frame();end;
assert(store.equal(disk(),settings_file) and not app.state.dirty,'Once the file can be read, it holds the settings put back.');

-- The shared layout file.
reopen();
command('/vg set shared_layout true');
local at=app.state.shared_at;
for _=1,30 do frame();if app.state.shared_at~=at then break;end;end;
assert(app.state.shared_at~=at,'Fixture: the shared layout was read.');
local x,layout_file=settings().panels.self_buffs.x,disk(layout_path);
assert(layout_file.self_buffs and layout_file.self_buffs.x==x,'Fixture: the shared file holds this layout.');
settings_file=disk();
failure(function(current,_,ui)
    ui.changed(function()current.panels.self_buffs.x=x+9;end,true,'Position');
    assert(disk(layout_path).self_buffs.x==x+9,'Fixture: the page wrote its layout to the shared file.');
    held=layout_path;
end);
assert(store.equal(disk(),settings_file),'Fixture: the settings file is put back.');
assert(app.state.dirty,'A shared layout that could not be read back waits to be saved.');
for _=1,30 do frame();end;
assert(store.equal(disk(layout_path),layout_file),'Once it can be read, the shared file holds the layout put back.');
assert(settings().panels.self_buffs.x==x,'The failed page\'s layout never comes back from the shared file.');
command('/vg set shared_layout false');

-- A shared layout the page started sharing, when the settings put back don't share it.
reopen();
local unshared=disk(layout_path);
failure(function(_,callbacks,ui)
    assert(callbacks.sharing(true,'placement'),'Fixture: the page turned sharing on.');
    ui.changed(function()settings().panels.self_buffs.x=x+7;end,true,'Position');
    assert(disk(layout_path).self_buffs.x==x+7,'Fixture: the page wrote its layout to the shared file.');
    held=layout_path;
end);
assert(not settings().shared_layout and disk(layout_path).self_buffs.x==x+7,'Fixture: the shared file could not be put back.');
for _=1,12 do frame();end;
assert(store.equal(disk(layout_path),unshared),'Once it can be read, a shared file this character no longer shares is put back too.');

-- The profile file.
reopen();
command('/vg set style.font_size 31');
assert(app.callbacks.profile_save('Alpha',false) and app.callbacks.profile_link(2,'Alpha'),'Fixture: Alpha is saved and linked to job 2.');
command('/vg set style.font_size 18');
local reported=printed('The profiles a failed settings page changed could not be put back.');
failure(function(_,callbacks)
    assert(callbacks.profile_rename('Alpha','Delta',callbacks.profile_status('Alpha').token),'Fixture: the page renamed Alpha.');
    held=profiles_path;
end);
assert(disk(profiles_path).Delta and settings().active_profile=='Alpha','Fixture: the profile file could not be put back.');
assert(printed('The profiles a failed settings page changed could not be put back.')==reported+1,
    'A profile file that could not be read back is reported.');
for _=1,12 do frame();end;
assert(disk(profiles_path).Alpha and not disk(profiles_path).Delta,'Once it can be read, the profile file is put back.');
-- Another profile is the active one, so the job change loads Alpha.
assert(app.callbacks.profile_save('Spare',false) and settings().active_profile=='Spare','Fixture: another profile is active.');
snapshot.job=2;frame();frame();
assert(settings().style.font_size==31 and settings().active_profile=='Alpha','Job 2 still loads its linked profile.');
