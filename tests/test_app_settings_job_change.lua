-- A report a settings page exports (Export report) refreshes only once the page has drawn, so a job change
-- or a character switch is never seen inside a draw that then fails. The job's linked profile still loads.
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
local app=dofile(ADDON_DIR..'/vantage.lua');
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

MOCK.fire('load');app.refresh(0);
app.state.dirty=true;assert(app.callbacks.save(),'Fixture: the settings are on disk.');
command('/vg');frame();frame();app.callbacks.editor_changed();app.callbacks.save();
assert(settings().window.open and disk().window.open==true,'Fixture: Home is drawn and saved open.');

-- Beta (font 30) is linked to job 2, and the font is 18 now. The page exports a report in the frame
-- the job changes, and then fails.
command('/vg set style.font_size 30');
assert(app.callbacks.profile_save('Beta',false) and app.callbacks.profile_link(2,'Beta'),'Fixture: Beta is saved and linked.');
command('/vg set style.font_size 18');
assert(settings().style.font_size==18,'Fixture: the font is 18.');
-- Another profile is the active one, so the job change loads Beta.
assert(app.callbacks.profile_save('Spare',false) and settings().active_profile=='Spare','Fixture: another profile is active.');
failure(function(_,callbacks)
    snapshot.job=2;
    local reports=printed('Report saved to');
    assert(callbacks.export_report(),'Fixture: the page exported a report.');
    assert(settings().style.font_size==18 and printed('Report saved to')==reports,'The report waits for the page, so no job change loads while it draws.');
end);
assert(printed('Report saved to')>0,'The report a failing page asked for is written after it.');
frame();frame();
assert(settings().style.font_size==30 and settings().active_profile=='Beta' and disk().style.font_size==30,
    'Job 2 runs with its linked profile Beta.');

-- A failing page that sees no job change leaves the job as it was, so nothing loads again, even with another
-- profile active, which a job change would load Beta over.
reopen();
command('/vg set style.font_size 20');
assert(app.callbacks.profile_save('Spare 2',false) and settings().active_profile=='Spare 2','Fixture: another profile is active.');
failure(function(_,callbacks)assert(callbacks.export_report(),'Fixture: the page exported a report.');end);
frame();frame();
assert(settings().style.font_size==20 and disk().style.font_size==20,'The job\'s profile does not load again on the same job.');

-- A character switch seen while a page draws keeps the new character's job, so a profile this
-- character links to that job never loads into the new character's file.
reopen();
assert(app.callbacks.profile_link(3,'Beta'),'Fixture: Beta is linked to job 3 too.');
local other,tester=nil,app.state.path;
failure(function(_,callbacks)
    snapshot.id,snapshot.name,snapshot.job=2002,'Other',3;
    assert(callbacks.export_report(),'Fixture: the page exported a report.');
    assert(app.state.path==tester,'No character switch happens while the page draws.');
end);
other=app.state.path;
assert(other and other:find('Other_2002',1,true),'The switch happens after the page.');
frame();frame();
assert(not exists(other) or disk(other).active_profile~='Beta','This character\'s link does not load into the other character\'s file.');
