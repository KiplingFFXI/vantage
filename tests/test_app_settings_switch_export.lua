-- A report a settings page exports in the frame the character changes, in a draw that then fails, never
-- leaves the new character running on, or saving, the old character's settings.
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
    command('/vg');frame();frame();app.callbacks.editor_changed();app.callbacks.save();
    assert(settings().window.open and disk().window.open==true,'Fixture: the window is drawn again and saved open.');
end;

MOCK.fire('load');app.refresh(0);
app.state.dirty=true;assert(app.callbacks.save(),'Fixture: the settings are on disk.');
command('/vg');frame();frame();app.callbacks.editor_changed();app.callbacks.save();
assert(settings().window.open and disk().window.open==true,'Fixture: Home is drawn and saved open.');

-- Other already has its own settings: font 14, its buff panel unlocked at x 777.
local tester=app.state.path;
local other=tester:gsub('Tester_1001','Other_2002');
local own=require('ui.defaults').make();own.style.font_size=14;own.panels.self_buffs.x=777;own.panels.self_buffs.locked=false;
assert(store.write(other,own),'Fixture: Other has a settings file.');
local function bytes(path)local file=assert(io.open(path,'rb'));local text=file:read('*a');file:close();return text;end;
local before=bytes(other);
command('/vg set style.font_size 27');
assert(app.callbacks.profile_save('Beta',false) and app.callbacks.profile_link(3,'Beta'),'Fixture: Beta is saved and linked to job 3.');
assert(app.callbacks.watch(4242),'Fixture: Tester watches an entity.');
-- One edit is still waiting for its autosave when the page draws.
settings().panels.self_buffs.x=4321;app.callbacks.changed('after');
assert(app.state.dirty and disk(tester).panels.self_buffs.x~=4321,'Fixture: an edit waits for its autosave.');
failure(function(_,callbacks)
    snapshot.id,snapshot.name,snapshot.job=2002,'Other',3;
    assert(callbacks.export_report(),'Fixture: the page exported a report.');
end);
assert(app.state.path==other and app.state.identity=='2002:Other','The character switch is seen after the failed page.');
assert(settings().style.font_size==14 and settings().panels.self_buffs.x==777 and settings().panels.self_buffs.locked==false,
    'Other runs with its own settings.');
assert(settings().active_profile~='Beta' and settings().job_profiles['3']==nil and #settings().watch_ids==0,
    'Other runs with none of Tester\'s profile choices or watched entities.');
local file=disk(tester);
assert(file.style.font_size==27 and file.panels.self_buffs.x==4321,'Tester\'s waiting edit is saved to Tester\'s file.');
for _=1,8 do frame();end;
assert(bytes(other)==before,'Other\'s saved settings and lock are unchanged with no action from the user.');
snapshot.zone=103;for _=1,8 do frame();end;
assert(bytes(other)==before,'A zone change on Other leaves its saved settings unchanged.');
command('/vg set style.icon_size 30');
file=disk(other);
assert(file.style.font_size==14 and file.panels.self_buffs.x==777 and file.panels.self_buffs.locked==false
    and file.active_profile~='Beta' and (file.job_profiles or {})['3']==nil,
    'A later change on Other saves Other\'s own settings.');
