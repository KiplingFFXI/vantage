"""Measure mocked core CPU time and SDK reads; this is not a live FPS benchmark."""
import argparse
import json
from pathlib import Path
import statistics
import tempfile
import time

import run


SETUP = r'''
local reads, stage = {}, {};
BENCH = { reads = reads, stage = stage };
local function counted(name, fn)
    return function(...)
        reads[name] = (reads[name] or 0) + 1;
        return fn(...);
    end;
end;
local members, icons = {}, {};
for slot = 0, 17 do
    members[slot] = {id=1001+slot,index=0x400+slot,zone=102,name='Member'..slot};
end;
for slot = 0, 31 do icons[slot] = slot + 1; end;
local mm = AshitaCore:GetMemoryManager();
local party, player = mm:GetParty(), mm:GetPlayer();
MOCK.player.server_id, MOCK.player.index, MOCK.player.zone = 1001, 0x400, 102;
MOCK.player.name, MOCK.player.main_job, MOCK.player.main_level = 'Bench', 5, 75;
for name, key in pairs({GetMemberServerId='id',GetMemberTargetIndex='index',GetMemberZone='zone',GetMemberName='name'}) do
    party[name] = function(_, slot) return members[slot] and members[slot][key] or 0; end;
end;
for name, value in pairs({GetMemberHP=1234,GetMemberMP=567,GetMemberTP=2000,GetMemberHPPercent=90,
    GetMemberMPPercent=80,GetMemberMainJob=5,GetMemberMainJobLevel=75,GetMemberLastUpdatedTimestamp=1}) do
    party[name] = function() return value; end;
end;
party.GetMemberIsActive = function(_, slot) return members[slot] and 1 or 0; end;
party.GetStatusIconsServerId = function(_, entry) return members[entry + 1] and members[entry + 1].id or 0; end;
party.GetStatusIconsTargetIndex = function(_, entry) return 0x401 + entry; end;
party.GetStatusIcons = function() return icons; end;
party.GetStatusIconsBitMask = function() return 0; end;
player.GetStatusIcons = function() return icons; end;
player.GetStatusTimers = function() return nil; end;
-- The client's own buff array (0x037), which self effects are read from, lists the same effects.
local buffs = {};
for slot = 0, 31 do buffs[slot] = slot + 1; end;
-- What the list holds that the catalog leaves out: the client names them, and they show under those names.
for _, id in ipairs({ 17, 18, 19, 20, 21, 23, 24, 25, 26, 27 }) do
    require('data.catalog')[id] = { id = id, name = 'Status ' .. id, kind = 'other', group = 'Other', priority = 0 };
end;
player.GetBuffs = function() return buffs; end;
local entity = {
    GetServerId=function(_, index) return index==500 and 0x1001234 or index>=0x400 and index<=0x411 and 1001+index-0x400 or 0; end,
    GetName=function() return 'Target'; end,GetSpawnFlags=function() return 0x10; end,
    GetDistance=function() return 25; end,
};
local target = {GetTargetIndex=function() return BENCH.target and 500 or 0; end,GetIsSubTargetActive=function() return false; end};
mm.GetParty=function() return party; end;
mm.GetPlayer=function() return player; end;
mm.GetEntity=function() return entity; end;
mm.GetTarget=function() return target; end;
for kind, object in pairs({party=party,player=player,entity=entity,target=target,memory=mm}) do
    for name, fn in pairs(object) do if type(fn)=='function' then object[name]=counted(kind..'.'..name,fn); end end;
end;
AshitaCore.GetMemoryManager=counted('core.GetMemoryManager',function() return mm; end);
local get_player = GetPlayerEntity;
GetPlayerEntity=counted('core.GetPlayerEntity',get_player);
for _, name in ipairs({'read_uint8','read_uint32','find'}) do ashita.memory[name]=counted('native.'..name,ashita.memory[name]); end;
package.loaded['ui.hud']={draw=function() end,draw_notices=function() end,cancel_gesture=function() end};
package.loaded['ui.party_hud']={draw=function() return false,{}; end,cancel_layout_gesture=function() end};
package.loaded['ui.native_party_hud']={draw=function() return false,{}; end,cancel_layout_gesture=function() end};
package.loaded['ui.settings_window']={draw=function() end};
local client=require('core.client');
local client_read=client.read;
client.read=function(...) stage.client=(stage.client or 0)+1; return client_read(...); end;
local roster=require('core.roster');
local roster_read=roster.read;
roster.read=function(...) stage.roster=(stage.roster or 0)+1; return roster_read(...); end;
local recasts=require('core.recasts');
local new_recasts=recasts.new;
recasts.new=function(...)
    local instance=new_recasts(...); local project=instance.project;
    instance.project=function(self,view,...)
        stage.recast_projection=(stage.recast_projection or 0)+1;
        stage.recast_projection_rows=(stage.recast_projection_rows or 0)+#(view and view.rows or {});
        return project(self,view,...);
    end;
    return instance;
end;
local app=dofile(ADDON_DIR..'/vantage.lua');
BENCH.app=app;
BENCH.configure=function(scenario)
    BENCH.target=scenario~='disabled';
    if scenario=='disabled' or scenario=='self_target' then for slot=1,17 do members[slot]=nil; end; end;
    app.refresh(1);
    local settings=app.state.settings;
    settings.party_ui.enabled=scenario~='disabled' and scenario~='self_target';
    settings.alerts.enabled=scenario~='disabled';
    settings.diagnostics.record=false;
    for _,panel in pairs(settings.panels) do panel.enabled=scenario~='disabled'; end;
    local observations={};
    if BENCH.target then
        for effect=1,32 do observations[#observations+1]={kind='apply',entity_id=0x1001234,effect=effect,source=1001,duration=3600}; end;
    end;
    if settings.party_ui.enabled then
        for slot=6,17 do for effect=1,32 do
            observations[#observations+1]={kind='apply',entity_id=1001+slot,effect=effect,source=1001,duration=3600};
        end end;
    end;
    app.tracker:observe(observations,1,app.state.snapshot);
    app.refresh(1);
    local defaults=require('ui.defaults');
    if scenario~='disabled' then
        settings.alerts.rules={};
        for i=1,8 do local rule=defaults.rule('bench'..i);rule.scope='all';rule.effect=i;rule.event=i<=4 and 'missing' or 'remaining';
            rule.chat,rule.sound=false,'';settings.alerts.rules[#settings.alerts.rules+1]=rule; end;
    end;
    BENCH.rows=#app.state.view.rows;
end;
BENCH.clear=function()
    for key in pairs(reads) do reads[key]=nil; end;
    for key in pairs(stage) do stage[key]=nil; end;
end;
BENCH.run=function(count,mode)
    local first=10;
    for i=1,count do
        local t=first+i/60;
        MOCK.now=t;
        if mode=='refresh' then app.refresh(t);
        else
            if mode=='bursts' and i%6==0 then
                for n=1,8 do MOCK.fire('packet_in',{id=0x037,data=string.rep('\0',8),size=8}); end;
            end;
            MOCK.fire('d3d_present');
        end;
        MOCK.imgui_calls={};
    end;
end;
'''


# Self holds 32 effects, the target 32, and each of 17 members 32 (docs/PERFORMANCE.md).
EXPECTED_ROWS = {'disabled': 32, 'self_target': 64, 'alliance': 608}


def benchmark(count, repeats):
    results = []
    for scenario, mode in [('disabled', 'refresh'), ('self_target', 'refresh'),
                           ('alliance', 'refresh'), ('alliance', 'idle'), ('alliance', 'bursts')]:
        timings, row = [], None
        for _ in range(repeats):
            with tempfile.TemporaryDirectory(prefix='vantage_benchmark_') as folder:
                lua = run.runtime(folder)
                lua.execute(SETUP)
                bench = lua.globals().BENCH
                bench.configure(scenario)
                bench.run(120, mode)
                bench.clear()
                start = time.process_time_ns()
                bench.run(count, mode)
                timings.append((time.process_time_ns() - start) / count / 1000)
                row = {'scenario': scenario, 'mode': mode, 'iterations': count, 'rows': bench.rows,
                       'stage_calls': dict(bench.stage), 'sdk_calls': dict(bench.reads)}
                assert bench.rows == EXPECTED_ROWS[scenario], f'{scenario}: {bench.rows} effect rows, expected {EXPECTED_ROWS[scenario]}'
        row['cpu_us_per_iteration_median'] = round(statistics.median(timings), 3)
        row['cpu_us_samples'] = [round(value, 3) for value in timings]
        row['sdk_calls_total'] = sum(row['sdk_calls'].values())
        results.append(row)
    return {'limits': 'Mocked SDK calls and no GPU/UI rendering. CPU timings are host measurements, not FPS or live client costs.',
            'source': str(run.ADDON), 'results': results}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--count', type=int, default=1800)
    parser.add_argument('--repeats', type=int, default=3)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--source', '--addon', dest='source', type=Path)
    args = parser.parse_args()
    if args.source:
        run.ADDON = args.source.resolve()
    result = benchmark(args.count, args.repeats)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(result, indent=2), encoding='utf-8')
    for row in result['results']:
        print(f"{row['scenario']:12s} {row['mode']:8s}: {row['cpu_us_per_iteration_median']:8.3f} us/iteration; "
              f"{row['sdk_calls_total']} SDK calls; {row['rows']} effect rows; {row['stage_calls']}")
