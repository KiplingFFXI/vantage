"""Mocked observer processing after action decode; no game process, packet decoder or rendering."""
import argparse
import json
from pathlib import Path
import statistics
import tempfile
import time

import run


SETUP = r'''
local client=require('core.client');local observer=require('core.observer');
local memory=AshitaCore:GetMemoryManager();local inventory={};
local equipment,samples=0,0;
inventory.GetEquippedItem=function() equipment=equipment+1;return {Index=0};end;
memory.GetInventory=function() return inventory;end;
AshitaCore.GetMemoryManager=function() return memory;end;
local sample=client.sample_modifiers;
client.sample_modifiers=function(...) samples=samples+1;return sample(...);end;
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=5,level=75,self_effects={},party={},entities={}};
for id=1001,1006 do snapshot.entities[id]={id=id,name='Member '..id,kind='player'};end;
local action={actor=1001,category=1,id=0,rows={{target=1002,message=1,param=40}}};
observer.decode=function() return action;end;
local event={id=0x028,data='',size=0};
BENCH=function(kind,iterations)
    if kind=='melee' then action.category,action.id,action.rows=1,0,{{target=1002,message=1,param=40}};
    elseif kind=='resisted' then action.category,action.id,action.rows=4,58,{{target=1002,message=85,param=4}};
    elseif kind=='removal' then action.category,action.id,action.rows=4,260,{{target=1002,message=341,param=13}};
    else action.category,action.id,action.rows=4,57,{};for id=1001,1006 do action.rows[#action.rows+1]={target=id,message=230,param=33};end;end;
    for _=1,100 do observer.read(event,100,snapshot);end;
    equipment,samples=0,0;collectgarbage('collect');local total=0;
    local start=BENCH_CLOCK();
    for i=1,iterations do total=total+#observer.read(event,100+i*0.1,snapshot);end;
    return (BENCH_CLOCK()-start)/iterations*1000000,equipment/iterations,samples/iterations,total/iterations;
end;
'''


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path)
    parser.add_argument('--count',type=int,default=3000)
    parser.add_argument('--repeats',type=int,default=3)
    parser.add_argument('--out',type=Path)
    args=parser.parse_args()
    if args.source: run.ADDON=args.source.resolve()
    result={'method':__doc__,'source':str(run.ADDON),'count':args.count,'scenarios':[]}
    for kind in ('melee','resisted','removal','six_target_buff'):
        timings=[]
        for _ in range(args.repeats):
            with tempfile.TemporaryDirectory(prefix='vantage_packet_bench_') as folder:
                lua=run.runtime(folder);lua.globals().BENCH_CLOCK=time.perf_counter;lua.execute(SETUP)
                values=lua.globals().BENCH(kind,args.count);timings.append(values[0])
        result['scenarios'].append(dict(name=kind,cpu_us=round(statistics.median(timings),3),
            equipment_reads=values[1],modifier_samples=values[2],observations=values[3]))
    output=json.dumps(result,indent=2)+'\n';print(output,end='')
    if args.out:
        args.out.parent.mkdir(parents=True,exist_ok=True);args.out.write_text(output,encoding='utf-8')


if __name__=='__main__':main()
