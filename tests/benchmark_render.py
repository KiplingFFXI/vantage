"""Mocked Lua party list strip cost, allocation and call counts in the default look; no game, GPU, or live FPS measurement.

The strips beside the game's party list draw their icons in the fresh look, which they take from the timer panels:
the Original FFXI skin and bitmap font from the installed client art (read only; uploads only hand out ids), beside a
mocked game party list. The draw list keeps every argument
reachable, as a C binding call needs it.
"""
from pathlib import Path
import argparse
import importlib.util
import json
import statistics
import tempfile
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('fixture_runner', HERE / 'run.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
SETUP = r'''
local imgui=require('imgui');
COUNTS={};local counting=false;
local function hit(key)if counting then COUNTS[key]=(COUNTS[key] or 0)+1;end;end;
local clips,position,size,sink={}, {}, {}, {};
local list=setmetatable({}, {__index=function(self,key)
    local fn=function(_,a,b,c,d,e,f,g,h,i,j)hit('draw:'..key);sink[1],sink[2],sink[3],sink[4],sink[5],sink[6],sink[7],sink[8],sink[9],sink[10]=a,b,c,d,e,f,g,h,i,j;end;
    rawset(self,key,fn);return fn;end});
list.GetClipRectMin=function()local r=clips[#clips];return r[1],r[2];end;
list.GetClipRectMax=function()local r=clips[#clips];return r[3],r[4];end;
list.PushClipRect=function(_,a,b)local r=clips[#clips];clips[#clips+1]={math.max(a[1],r[1]),math.max(a[2],r[2]),math.min(b[1],r[3]),math.min(b[2],r[4])};end;
list.PopClipRect=function()clips[#clips]=nil;end;
imgui.SetNextWindowPos=function(v)position={v[1],v[2]};end;imgui.SetNextWindowSize=function(v)size={v[1],v[2]};end;
imgui.Begin=function()clips={{position[1],position[2],position[1]+size[1],position[2]+size[2]}};return true;end;
imgui.GetWindowDrawList=function()return list;end;
imgui.GetIO=function()return {DisplaySize={x=1920,y=1080}};end;
imgui.GetMousePos=function()return -1,-1;end;imgui.GetFont=function()return 1;end;
imgui.CalcTextSize=function(value)hit('measure');return #tostring(value)*7,14;end;
require('client_art_fixture')();
-- The bitmap fonts, as /load prepares them.
require('ui.client_fonts').prepare();
require('ui.icons').status=function()hit('status_texture');return 1;end;
local layout=require('ui.party_layout');
for _,key in ipairs({'effects','effect_cells','effect_height'})do
    local original=layout[key];layout[key]=function(...)hit(key);return original(...);end;
end;
local sort=table.sort;table.sort=function(...)hit('sort');return sort(...);end;
local hud,strips=require('ui.party_hud'),require('ui.native_party_hud');
function make_case(height,scroll)
    local config=require('ui.party_defaults').make();
    config.enabled=true;
    -- The strips wear the timer panels' look.
    local style=require('ui.defaults').make().style;
    assert(style.theme=='Original FFXI' and style.font=='Original FFXI','The fresh look is measured.');
    config.native.width=420;
    config.effects.max=32;
    -- A height of the screen is the three strips beside the game's party list; a shorter one is detached and scrolls.
    local detached=height<1080;
    for _,group in ipairs(config.groups)do
        group.native_detached,group.detached_width,group.detached_height=detached,420,height;
    end;
    local roster,subjects=hud.sample(18,100);
    local game={available=true,groups={}};
    for group=1,3 do
        local frame={x=1500,y=40+(group-1)*330,width=200,height=6*50,rows={}};
        for _,member in ipairs(roster.members)do if member.group==group then
            frame.rows[member.slot]={x=1500,y=frame.y+member.slot%6*50,width=200,height=50,slot=member.slot};
        end;end;
        game.groups[group]=frame;
    end;
    local callbacks={native_geometry=game,global_style=style};
    for _,member in ipairs(roster.members)do
        subjects[member.id].effects={};
        for index=1,32 do subjects[member.id].effects[index]={effect=index,name='Long example effect '..index,
            kind='buff',status='server',remaining=200,total=900,present=true,key=tostring(index)};end;
    end;
    imgui.GetScrollY=function()return scroll;end;
    return function(iterations,count_calls)
        COUNTS={};counting=count_calls;
        for index=1,iterations do strips.draw(roster,subjects,config,100,callbacks);MOCK.imgui_calls={};end;
        counting=false;return COUNTS;
    end;
end;
function bitmap_ready() return require('ui.fonts').is_bitmap('Original FFXI') and not require('ui.fonts').failed('Original FFXI'); end;
function allocated(run,iterations)
    collectgarbage('collect');collectgarbage('stop');local before=collectgarbage('count');
    run(iterations,false);local kb=(collectgarbage('count')-before)/iterations;
    collectgarbage('restart');collectgarbage('collect');return kb;
end;
function collector(on) collectgarbage('collect'); collectgarbage(on and 'restart' or 'stop'); end;
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--overlay', type=Path, help='Optional prior ui/ files used before current source modules')
    args = parser.parse_args()
    results = []
    with tempfile.TemporaryDirectory(prefix='vantage_render_benchmark_') as folder:
        lua = runner.runtime(folder)
        if args.overlay:
            lua.execute('package.path=.....";"..package.path', (args.overlay.resolve().as_posix() + '/?.lua'))
        lua.execute(SETUP)
        g = lua.globals()
        for height, scroll in [(1080, 0), (300, 500)]:
            run = g.make_case(height, scroll)
            run(20, False)
            if not g.bitmap_ready():
                raise SystemExit('The Original FFXI bitmap font did not load from the client art.')
            counts = dict(run(1, True))
            kb = statistics.median(g.allocated(run, 50) for _ in range(3))
            timed = {}
            for on in (True, False):
                samples = []
                for _ in range(5):
                    g.collector(on)
                    start = time.perf_counter()
                    run(50, False)
                    samples.append((time.perf_counter() - start) * 20)
                g.collector(True)
                timed[on] = round(statistics.median(samples), 3)
            place = 'attached' if height >= 1080 else 'detached_%dpx_scroll%d' % (height, scroll)
            results.append({'case': f'alliance_icons_{place}', 'median_ms_per_frame': timed[True],
                            'median_ms_per_frame_gc_stopped': timed[False], 'kb_per_frame': round(kb, 1),
                            'calls_per_frame': counts})
    print(json.dumps({'limits': 'Mocked Lua CPU only; synthetic 18-member, 32-effect strips in the fresh Original FFXI look with '
                      'installed client art, cached textures, no GPU or live client FPS.', 'results': results}, indent=2))


if __name__ == '__main__':
    main()
