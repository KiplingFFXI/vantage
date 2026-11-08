-- With 20 Undo steps, each shared change another character makes is held by every step and applied when the step
-- holds too many. The 17th change applies the held changes of each step at once, one layout per step, so it
-- costs about what one change costs per step, and Undo of a step holding 16 applies one.
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
local other=profiles.new(state.path:gsub('Tester_1001/settings.json$',''));
command('/vg set shared_layout true');
frames(30);
for index=1,20 do command('/vg set style.font_size '..(10+index)); end;
frames(10);
local applied=0;
local apply=profiles.apply_layout;
profiles.apply_layout=function(...) applied=applied+1; return apply(...); end;
local most,first=0;
for move=1,20 do
    local copy=store.copy(state.settings);copy.panels.self_buffs.x=copy.panels.self_buffs.x+move;
    assert(other:save_layout(copy),'Fixture: the other character moved a panel.');
    state.shared_at,state.dirty,applied=-1e9,false,0;
    MOCK.frame(.11);
    first=first or applied;
    most=math.max(most,applied);
end;
assert(most<=first+21,('No poll applies many more layouts than the first: %d against %d.'):format(most,first));
-- Undo of a step holding 16 changes.
profiles.apply_layout=apply;
for size=11,30 do command('/vg set style.font_size '..size); end;
frames(10);
for move=21,36 do
    local copy=store.copy(state.settings);copy.panels.self_buffs.x=copy.panels.self_buffs.x+move;
    assert(other:save_layout(copy),'Fixture: the other character moved a panel.');
    state.shared_at,state.dirty=-1e9,false;
    MOCK.frame(.11);
end;
profiles.apply_layout=function(...) applied=applied+1; return apply(...); end;
applied=0;
command('/vg undo');
assert(applied<=2,'Undo of a step holding 16 changes applies them at once: '..applied);
