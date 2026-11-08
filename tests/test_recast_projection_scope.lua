local store = require('core.store');
local live = {valid=true,id=1001,name='Tester',zone=102,job=1,level=75,self_known=true,
    self_effects={{effect=33,slot=0,deadline=120,raw_timer=7200}},party={},entities={}};
local client_reads, timer_reads, raw = 0, 0, 600;
package.loaded['core.client'] = {read=function()
    client_reads=client_reads+1; return store.copy(live);
end,load=function() end,capabilities=function() return {}; end};
package.loaded['core.observer'] = {read=function() return {}; end};
package.loaded['ui.hud'] = {draw=function() end,draw_notices=function() end,cancel_gesture=function() end};
package.loaded['ui.party_hud'] = {draw=function() return false,{}; end,cancel_layout_gesture=function() end};
package.loaded['ui.native_party_hud'] = {draw=function() return false,{}; end,cancel_layout_gesture=function() end};
package.loaded['ui.settings_window'] = {draw=function() end};
local memory = AshitaCore:GetMemoryManager();
memory.GetRecast=function() return {GetSpellTimer=function(_,id)
    timer_reads=timer_reads+1; return id==2 and raw or 0;
end}; end;
AshitaCore.GetMemoryManager=function() return memory; end;
-- The client names spell 2, so its timer is the one read.
local resources = {GetSpellById=function(_,id) return id==2 and {Name={'Cure'}} or nil; end};
AshitaCore.GetResourceManager=function() return resources; end;
local source, projected, model = require('core.recasts');
local new = source.new;
source.new=function()
    model=new(); local project=model.project;
    model.project=function(self,view,...)
        projected=view;
        for _,row in ipairs(view and view.rows or {}) do
            assert(row.domain=='recast','Recast projection only visits cooldown rows');
        end;
        return project(self,view,...);
    end;
    return model;
end;
local app = dofile(ADDON_DIR..'/vantage.lua');
MOCK.now=1; app.refresh(1);
app.state.settings.recast_display='combined'; app.refresh(1);
local function row(kind)
    for _,value in ipairs(app.state.view.rows) do
        if (value.domain=='recast')==(kind=='recast') then return value; end;
    end;
end;
local function same_rows()
    assert(#app.state.recasts.rows==1 and row('recast')==app.state.recasts.rows[1],
        'The combined render view retains the recast view row itself');
end;
same_rows();
local own, cooldown = row('status'), row('recast');
assert(own and cooldown and cooldown.remaining==10);
local reads, spells = client_reads, timer_reads;
MOCK.frame(1/60);
assert(projected==app.state.recasts,'Idle frames project the existing recast-only view');
assert(client_reads==reads and timer_reads==spells,'Projection adds no client or timer reads');
assert(math.abs(cooldown.remaining-(11-MOCK.now))<0.000001);
assert(math.abs(own.remaining-(120-MOCK.now))<0.000001,'Status projection still advances each frame');
assert(app.state.party_subjects[1001].effects[1]==own,'Party status aliases remain unchanged');
assert(#model:drain_events()==0,'Projection never emits readiness');

-- A packet wakes status sampling but does not force another cooldown scan before 100 ms.
MOCK.fire('packet_in',{id=0x063}); MOCK.frame(1/60);
assert(client_reads==reads+1 and timer_reads==spells);
same_rows();
MOCK.frame(0.08);
assert(client_reads==reads+1 and timer_reads==spells,'The intervening frame remains projection-only');
MOCK.frame(0.04);
assert(client_reads==reads+2 and timer_reads==spells+1,'The ordinary 100 ms sample reads the timer of the spell the client names');
same_rows();

-- Expiry remains unknown until the native clock explicitly reads zero.
raw=3; MOCK.now=2; app.refresh(2); same_rows();
cooldown=row('recast'); reads,spells=client_reads,timer_reads;
MOCK.frame(0.06);
assert(projected==app.state.recasts and cooldown.remaining==nil and cooldown.status=='unknown' and cooldown.present);
assert(client_reads==reads and timer_reads==spells and #model:drain_events()==0);
raw=0; MOCK.frame(0.06);
assert(not row('recast') and #app.state.recasts.rows==0 and row('status'));
reads,spells=client_reads,timer_reads; MOCK.frame(1/60);
assert(projected==app.state.recasts and #projected.rows==0,'No cooldowns means no status rows scanned by cooldown projection');
assert(client_reads==reads and timer_reads==spells);

-- Hidden display state must not interrupt clocks used by alerts or later rendering.
raw=600; MOCK.now=3; app.refresh(3); app.state.hidden=true;
cooldown=row('recast'); reads,spells=client_reads,timer_reads; MOCK.frame(1/60);
assert(projected==app.state.recasts and math.abs(cooldown.remaining-(13-MOCK.now))<0.000001);
assert(client_reads==reads and timer_reads==spells and #MOCK.commands==0);
assert(app.state.problem==nil,'Projection finishes without a guarded render error');
