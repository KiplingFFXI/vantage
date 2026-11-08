-- Presentation scope: after this character saves, its next save and its next poll treat the shared file as its
-- own: no merge, no second settings write, no layout applied. The file keeps 14 significant digits (json.lua),
-- so colour components like 41/255 read back a little different from what was written.
local store=require('core.store');
local profiles=require('core.profiles');
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=3,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(snapshot);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
require('ui.party_hud').draw=function()return 0,{};end;
require('ui.native_party_hud').draw=function()return 0,{};end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end,suspend=function()return true;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local state=app.state;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
local function frames(count)for _=1,count do MOCK.frame(.11);end;end;
MOCK.fire('load');app.refresh(0);
state.dirty=true;assert(app.callbacks.save(),'Fixture: the settings are on disk.');
command('/vg set shared_scope presentation');
command('/vg set shared_layout true');
frames(30);
local applied,writes=0,0;
local apply=profiles.apply_layout;
profiles.apply_layout=function(...) applied=applied+1; return apply(...); end;
local write=store.write;
store.write=function(path,...) if path==state.path then writes=writes+1; end; return write(path,...); end;
-- Two saves 1 s apart, no poll between.
for index=1,2 do
    state.settings.panels.self_buffs.x=state.settings.panels.self_buffs.x+1;
    state.dirty,state.changed_at,state.retry_at,state.shared_at=true,-1e9,0,os.clock()+1e9;
    applied,writes=0,0;
    MOCK.frame(.11);
    assert(not state.dirty,'Fixture: saved.');
end;
assert(applied==0,'A save after this character\'s own save applies no layout: '..applied);
assert(writes==1,'A save after this character\'s own save writes the settings once: '..writes);
-- The poll after it.
state.shared_at,applied=-1e9,0;
MOCK.frame(.11);
assert(applied==0,'The poll after this character\'s own save applies no layout: '..applied);
