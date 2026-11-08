-- The shared layout poll every 2 s: a file this character already has costs no layout work, and one another
-- character changed costs about the same with a full Undo history as with none.
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
    status=function()return {active=false};end,restore=function()return true;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local state=app.state;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
local function frames(count)for _=1,count do MOCK.frame(.11);end;end;
MOCK.fire('load');app.refresh(0);
state.dirty=true;assert(app.callbacks.save(),'Fixture: the settings are on disk.');
local other=profiles.new(state.path:gsub('Tester_1001/settings.json$',''));
local applied=0;
local apply=profiles.apply_layout;
profiles.apply_layout=function(...) applied=applied+1; return apply(...); end;
local moves=0;
-- One Present with the poll due: its VM steps and its layout applies.
local function poll(steps,change)
    state.history,state.redo,state.transaction={},{},nil;
    for index=1,steps do state.history[index]={settings=store.copy(state.settings),label='Step '..index,epoch=state.zone_epoch}; end;
    if change then
        moves=moves+1;
        local copy=store.copy(state.settings);copy.panels.self_buffs.x=copy.panels.self_buffs.x+moves;
        assert(other:save_layout(copy),'Fixture: the other character moved a panel.');
    end;
    state.shared_at,state.dirty,applied=-1e9,false,0;
    local count=0;
    -- Compiled code skips the hook, so count with the compiler off and its traces dropped.
    jit.off();jit.flush();
    debug.sethook(function() count=count+1; end,'',10);
    MOCK.frame(.11);
    debug.sethook();jit.on();
    return count*10,applied;
end;
for _,scope in ipairs({'placement','presentation'}) do
    command('/vg set shared_scope '..scope);
    command('/vg set shared_layout true');
    frames(30);
    local _,calls=poll(20,false);
    assert(calls==0,'An unchanged shared file costs no layout work: '..scope);
    local none=poll(0,true);
    local full=poll(20,true);
    assert(full<1.5*none,('A changed shared file costs about the same with 20 Undo steps: %d against %d (%s).'):format(full,none,scope));
    local x=state.settings.panels.self_buffs.x;
    command('/vg undo');
    assert(state.settings.panels.self_buffs.x==x,'Fixture: the step undone follows the other character too: '..scope);
    command('/vg set shared_layout false');
end;
