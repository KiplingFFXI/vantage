"""Mocked cooldown sampling/projection cost; no game process or graphics driver."""
from pathlib import Path
import argparse
import json
import tempfile
import time

import run
from run import runtime

LUA=r'''
local recasts=require('core.recasts');
local spell_count,ability_count,item_count,enabled,iterations=...;
local count,known_count,resource_count=0,0,0;
local function read(value) count=count+1;return value;end;
local function resource(value) resource_count=resource_count+1;return value;end;
local manager={
    GetSpellTimer=function(_,id) return read(id<spell_count and 60000 or 0);end,
    GetAbilityTimerId=function(_,slot) return read(slot<ability_count and slot or 0);end,
    GetAbilityTimer=function(_,slot) return read(slot<ability_count and 60000 or 0);end,
};
local inventory={
    GetEquippedItem=function(_,slot) return read({Index=slot<item_count and 2049+slot or 0});end,
    GetContainerItem=function(_,container,index) return read({Id=17000+index,Index=index,Extra=string.char(1)..string.rep('\0',11)});end,
};
local item_resource={Type=5,MaxCharges=10,CastDelay=30,RecastDelay=1800,Name={[1]='Test item'}};
local spell_resource={Name={[1]='Test spell'},ListIconNQ=2,ListIconHQ=143};
local action_resources={};
for timer=0,30 do for alias=0,1 do
    local id=528+timer*2+alias;
    action_resources[id]={Id=id,Name={[1]='Action '..id},Type=1,RecastTimerId=timer,ListIconId=360+alias,Element=41};
end end;
local resources={GetSpellById=function() return resource(spell_resource);end,
    GetAbilityById=function(_,id) return resource(action_resources[id]);end,
    GetItemById=function() return resource(item_resource);end};
local party={GetMemberServerId=function() return read(1001);end,GetMemberZone=function() return read(230);end};
local player={GetMainJob=function() return read(1);end,GetIsZoning=function() return read(false);end,
    GetSubJob=function() return read(2);end,GetMainJobLevel=function() return read(75);end,GetSubJobLevel=function() return read(37);end,
    HasAbilityData=function() return read(true);end,
    HasAbility=function(_,id) known_count=known_count+1;return read(id%2==0);end,
    HasPetCommand=function() known_count=known_count+1;return read(false);end};
local memory={GetRecast=function() return manager;end,GetInventory=function() return inventory;end,
    GetParty=function() return party;end,GetPlayer=function() return player;end};
AshitaCore.GetMemoryManager=function() return memory;end;
AshitaCore.GetResourceManager=function() return resources;end;
package.preload['ffxi.itemdata']=function() return {parse_timer_info=function() return read({use_delay=60,remaining_charges=10});end};end;
local model=recasts.new();local snapshot={valid=true,id=1001,zone=230,job=1};
model:update(snapshot,100,{enabled=enabled});model:view(100);count,known_count,resource_count=0,0,0;
collectgarbage('collect');
local start=BENCH_CLOCK();local view;
for i=1,iterations do model:update(snapshot,100+i*0.1,{enabled=enabled});view=model:view(100+i*0.1);end;
local sampling=(BENCH_CLOCK()-start)/iterations*1000;
local sample_reads=count/iterations;local known_reads=known_count/iterations;local resource_reads=resource_count/iterations;count=0;
start=BENCH_CLOCK();for i=1,iterations*10 do model:project(view,100+iterations*0.1+i/600);end;
return sampling,(BENCH_CLOCK()-start)/(iterations*10)*1000,sample_reads,count,#view.rows,known_reads,resource_reads;
'''


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path)
    parser.add_argument('--iterations',type=int,default=1000)
    parser.add_argument('--out',type=Path)
    args=parser.parse_args()
    if args.source: run.ADDON=args.source.resolve()
    result={'method':'LuaJIT mocked SDK, steady update plus view, separate projection, milliseconds per call',
            'source':str(run.ADDON),'iterations':args.iterations,'scenarios':[]}
    for name,spells,abilities,items,enabled in [
        ('disabled',0,0,0,False),('idle',0,0,0,True),
        ('active',16,8,2,True),('capacity',1024,31,16,True)]:
        with tempfile.TemporaryDirectory(prefix='vantage_recasts_') as folder:
            lua=runtime(folder)
            lua.globals().BENCH_CLOCK=time.perf_counter
            values=lua.execute(LUA,spells,abilities,items,enabled,args.iterations)
        result['scenarios'].append(dict(name=name,sample_ms=round(values[0],6),project_ms=round(values[1],6),
            sample_reads=values[2],project_reads=values[3],rows=values[4],
            known_ability_reads=values[5],resource_reads=values[6]))
    value=json.dumps(result,indent=2)+'\n'
    print(value,end='')
    if args.out:
        args.out.parent.mkdir(parents=True,exist_ok=True)
        args.out.write_text(value,encoding='utf-8')


if __name__=='__main__':
    main()
