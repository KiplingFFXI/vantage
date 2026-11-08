-- A settings page that fails leaves memory and every file as they were before its draw: the settings,
-- profile and shared layout files, Undo entries and the profile recovery list. An alert reset or a
-- display it showed is undone too. What it copied, printed or exported stays.
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
-- Home is the fixture's page: each step gives it what to do.
local page;
package.loaded['ui.main_page']={labels={},draw=function(_,s,_,callbacks,ui)if page then page(s,callbacks,ui);end;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local root=require('core.identity').root():gsub('[\\/]+$','')..'/';
local profiles_path,layout_path=root..'profiles.json',root..'shared_layout.json';
local function settings()return app.state.settings;end;
local function disk(path)return store.read(path or app.state.path);end;
local function exists(path)local file=io.open(path,'rb');if file then file:close();end;return file~=nil;end;
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
end;
local function reopen()
    -- Navigation waits for the next save, which writes the open window.
    settings().window.open,settings().window.tab,app.state.settings_stopped=true,'Home',nil;frame();frame();app.callbacks.editor_changed();app.callbacks.save();
    assert(settings().window.open and disk().window.open==true,'Fixture: the window is drawn again and saved open.');
end;
local function undo_entries(job)
    local list={job=job};
    for index,entry in ipairs(app.state.history)do
        list[index]={entry=entry,active=entry.settings.active_profile,link=entry.settings.job_profiles[job]};
    end;
    return list;
end;
local function same_entries(list,label)
    assert(#app.state.history==#list,label..': the Undo entries are all there.');
    for index,kept in ipairs(list)do
        local entry=app.state.history[index];
        assert(entry==kept.entry and entry.settings.active_profile==kept.active and entry.settings.job_profiles[list.job]==kept.link,
            label..': Undo entry '..index..' is as it was.');
    end;
end;

MOCK.fire('load');app.refresh(0);
app.state.dirty=true;assert(app.callbacks.save(),'Fixture: the settings are on disk.');
command('/vg');frame();frame();app.callbacks.editor_changed();app.callbacks.save();
assert(settings().window.open and disk().window.open==true,'Fixture: Home is drawn and saved open.');
local size=settings().style.font_size;

-- The page's first profile makes the profile file. Failing takes the file away again.
assert(not exists(profiles_path),'Fixture: there is no profile file yet.');
local settings_file=disk();
failure(function(_,callbacks)assert(callbacks.profile_save('First',false),'Fixture: the page saved a profile.');end);
assert(not exists(profiles_path),'A profile file made by a failing page is taken away.');
assert(store.equal(disk(),settings_file) and settings().active_profile=='','The settings file is as it was.');

-- Alpha is saved, active and loads on job 2, and Undo entries name it. A page renames it and changes a
-- setting, then fails.
reopen();
assert(app.callbacks.profile_save('Alpha',false) and app.callbacks.profile_link(2,'Alpha'),'Fixture: Alpha is saved and linked.');
command('/vg set style.font_size 21');
local entries=undo_entries('2');
assert(#entries>=2 and entries[#entries].active=='Alpha' and entries[#entries].link=='Alpha','Fixture: Undo entries name Alpha.');
local profile_file;
profile_file,settings_file=disk(profiles_path),disk();
failure(function(current,callbacks,ui)
    assert(callbacks.profile_rename('Alpha','Gamma',callbacks.profile_status('Alpha').token),'Fixture: the page renamed Alpha.');
    ui.changed(function()current.style.font_size=size+30;end,true,'Font size');
    assert(disk(profiles_path).Gamma and disk().job_profiles['2']=='Gamma','Fixture: the rename is on disk.');
end);
assert(store.equal(disk(profiles_path),profile_file) and not disk(profiles_path).Gamma,'A rename is undone in the profile file.');
assert(store.equal(disk(),settings_file),'The settings file is as it was.');
assert(settings().job_profiles['2']=='Alpha' and settings().active_profile=='Alpha','The settings still name Alpha.');
same_entries(entries,'After a failed rename');
assert(not app.callbacks.profile_status().recover_available,'The failed rename leaves nothing to recover.');
local missing=printed('That profile was not found.');
-- Another profile is the active one, so the job change loads Alpha.
assert(app.callbacks.profile_save('Other',false) and settings().active_profile=='Other','Fixture: another profile is active.');
snapshot.job=2;frame();
assert(printed('That profile was not found.')==missing and settings().active_profile=='Alpha' and settings().style.font_size==size,
    'The next job change loads Alpha.');

-- The same for a delete, of Omega, saved and linked to job 3 just before.
reopen();
assert(app.callbacks.profile_save('Omega',false) and app.callbacks.profile_link(3,'Omega'),'Fixture: Omega is saved and linked.');
command('/vg set style.font_size 22');
entries=undo_entries('3');
assert(entries[#entries].active=='Omega' and entries[#entries].link=='Omega','Fixture: Undo entries name Omega.');
profile_file,settings_file=disk(profiles_path),disk();
failure(function(_,callbacks)
    assert(callbacks.profile_delete('Omega',callbacks.profile_status('Omega').token),'Fixture: the page deleted Omega.');
end);
assert(store.equal(disk(profiles_path),profile_file) and store.equal(disk(),settings_file),'A delete is undone in both files.');
assert(settings().job_profiles['3']=='Omega' and settings().active_profile=='Omega' and not app.callbacks.profile_status().recover_available,
    'Omega is still active and linked, with nothing to recover.');
same_entries(entries,'After a failed delete');
assert(app.callbacks.profile_save('Spare',false) and settings().active_profile=='Spare','Fixture: another profile is active.');
snapshot.job=3;frame();
assert(printed('That profile was not found.')==missing and settings().style.font_size==size,'Job 3 still loads Omega.');

-- A recovery made by a failing page is undone, and can still be made after. Kappa is saved, linked to
-- job 4 and renamed Beta just before.
reopen();
assert(app.callbacks.profile_save('Kappa',false) and app.callbacks.profile_link(4,'Kappa'),'Fixture: Kappa is saved and linked.');
command('/vg set style.font_size 23');
assert(app.callbacks.profile_rename('Kappa','Beta',app.callbacks.profile_status('Kappa').token),'Fixture: Kappa is renamed Beta.');
local status=app.callbacks.profile_status();
assert(status.recover_available and status.recover_kind=='rename' and settings().job_profiles['4']=='Beta','Fixture: the rename can be recovered.');
entries=undo_entries('4');
assert(entries[#entries].active=='Beta','Fixture: Undo entries name Beta.');
profile_file,settings_file=disk(profiles_path),disk();
failure(function(_,callbacks)assert(callbacks.profile_recover(),'Fixture: the page recovered Kappa.');end);
assert(store.equal(disk(profiles_path),profile_file) and store.equal(disk(),settings_file),'A recovery is undone in both files.');
assert(settings().job_profiles['4']=='Beta' and settings().active_profile=='Beta','The settings still name Beta.');
same_entries(entries,'After a failed recovery');
status=app.callbacks.profile_status();
assert(status.recover_available and status.recover_kind=='rename','The rename can still be recovered.');
assert(app.callbacks.profile_recover() and disk(profiles_path).Kappa and settings().job_profiles['4']=='Kappa','Recovering it after works.');

-- An undo by a failing page leaves its Undo entry as it was, even after more changes in the same draw.
reopen();
local earlier=settings().style.font_size;
command('/vg set style.font_size 24');
local top=app.state.history[#app.state.history];
local watched,editor=store.copy(top.settings.watch_ids),store.copy(top.settings.window);
failure(function(_,callbacks)
    assert(callbacks.undo(),'Fixture: the page undid a change.');
    assert(callbacks.watch(4242),'Fixture: the page watched an entity.');
end);
assert(app.state.history[#app.state.history]==top and store.equal(top.settings.watch_ids,watched) and store.equal(top.settings.window,editor),
    'The Undo entry a failing page used is as it was.');

-- An alert reset and shown displays are put back. What the page copied, printed or exported stays.
reopen();
command('/vg hide');
local rule={id='fixture',name='Fixture alert',effect=0,domain='status',duration=30,thresholds={15}};
app.callbacks.test_alert(rule);
assert(app.state.hidden and #app.alerts:view(MOCK.now)==1,'Fixture: the displays are hidden and a notice shows.');
local reports=printed('Report saved to');
failure(function(_,callbacks)
    assert(callbacks.undo(),'Fixture: the page undid a change.');
    callbacks.show_displays();
    assert(callbacks.copy_text('Fixture copy'),'Fixture: the page copied.');
    callbacks.chat_sample();
    assert(callbacks.export_report(),'Fixture: the page exported a report.');
end);
assert(settings().style.font_size==24,'Fixture: the undo is put back.');
assert(#app.alerts:view(MOCK.now)==1,'An alert reset by a failing page is undone, so its notice still shows.');
assert(app.state.hidden,'Displays a failing page showed stay hidden.');
assert(MOCK.clipboard=='Fixture copy','What a failing page copied stays copied.');
assert(printed('This is how your Vantage messages will look.')==1,'What it printed stays printed.');
assert(exists(root..'reports/latest.json') and printed('Report saved to')==reports+1,'The report it exported stays.');
-- A page that ends keeps both: its undo resets the alerts once it's drawn, and the displays show.
reopen();
local undo=#app.state.history;
page=function(_,callbacks)
    assert(callbacks.undo(),'Fixture: the page undid a change.');
    callbacks.show_displays();
end;
frame();page=nil;
assert(#app.state.history==undo-1 and settings().style.font_size==earlier,'Fixture: the undo is kept.');
assert(#app.alerts:view(MOCK.now)==0,'A page that ends resets the alerts its undo changed.');
assert(not app.state.hidden,'A page that ends shows the displays.');

-- Sharing. Another character saved a newer layout that this one hasn't read yet.
reopen();
command('/vg set shared_layout true');
assert(settings().shared_layout and exists(layout_path),'Fixture: the layout is shared.');
local x=settings().panels.self_buffs.x;
local function layout(offset)
    local other=store.copy(settings());
    other.panels.self_buffs.x=x+offset;
    return require('core.profiles').capture_layout(other);
end;
local function polled()
    local at=app.state.shared_at;
    for _=1,30 do frame();if app.state.shared_at~=at then return true;end;end;
end;
assert(polled(),'Fixture: the shared layout was read.');
local theirs=layout(345);
assert(store.write(layout_path,theirs),'Fixture: another character saved a newer layout.');
local shared;
shared,settings_file=app.state.shared_value,disk();
failure(function(_,callbacks)assert(callbacks.sharing(false,'placement'),'Fixture: the page stopped sharing.');end);
assert(settings().shared_layout and app.state.shared_value==shared,'Sharing and the layout this character last read are put back.');
assert(store.equal(disk(layout_path),theirs),'The other character\'s layout is kept.');
assert(store.equal(disk(),settings_file),'The settings file is as it was.');
assert(polled() and settings().panels.self_buffs.x==x+345,'The next read takes the other character\'s layout.');
-- A page that writes its layout over the newer one puts the newer one back.
reopen();
assert(polled(),'Fixture: the shared layout was read.');
theirs=layout(500);
assert(store.write(layout_path,theirs),'Fixture: another character saved a newer layout.');
settings_file=disk();
failure(function(current,_,ui)
    ui.changed(function()current.panels.self_buffs.x=x+9;end,true,'Position');
    assert(disk(layout_path).self_buffs.x==x+9,'Fixture: the page wrote its layout over the shared file.');
end);
assert(store.equal(disk(layout_path),theirs) and store.equal(disk(),settings_file),'Both files the page wrote are put back.');
-- One another character saves after the page wrote is kept.
reopen();
assert(polled(),'Fixture: the shared layout was read.');
local third=layout(700);
failure(function(current,_,ui)
    ui.changed(function()current.panels.self_buffs.x=x+11;end,true,'Position');
    local file=assert(io.open(layout_path,'wb'));
    file:write(store.encode(third));file:close();
end);
assert(store.equal(disk(layout_path),third),'A layout another character saved after the page is kept.');
assert(polled() and store.equal(disk(layout_path),third) and settings().panels.self_buffs.x==x+700,
    'It stays, and the next read takes it.');
command('/vg set shared_layout false');

-- A settings file that can't be put back is saved again from the settings put back.
reopen();
local font;
font,settings_file=settings().style.font_size,disk();
failure(function(current,_,ui)
    ui.changed(function()current.style.font_size=size+20;end,true,'Font size');
    MOCK.file_replace_error=true;
end);
MOCK.file_replace_error=false;
assert(disk().style.font_size==size+20 and settings().style.font_size==font,'Fixture: the file could not be put back.');
assert(app.state.dirty,'Settings that could not be put back on disk wait to be saved.');
for _=1,6 do frame();end;
assert(store.equal(disk(),settings_file),'The next save puts them back.');
-- A profile file that can't be put back is reported.
reopen();
local reported=printed('The profiles a failed settings page changed could not be put back.');
failure(function(_,callbacks)
    assert(callbacks.profile_rename('Alpha','Delta',callbacks.profile_status('Alpha').token),'Fixture: the page renamed Alpha.');
    MOCK.file_replace_error=true;
end);
MOCK.file_replace_error=false;
assert(disk(profiles_path).Delta,'Fixture: the profile file could not be put back.');
assert(printed('The profiles a failed settings page changed could not be put back.')==reported+1,
    'A profile file that could not be put back is reported.');
