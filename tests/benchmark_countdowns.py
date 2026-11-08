"""Measure real countdown glyph layout with cached mock textures; no GPU or live FPS.

The draw stand-in keeps its arguments reachable, as a C binding call needs them, so the glyph tables are
really built. Reports KB per frame and time with the collector running and stopped.
"""
from pathlib import Path
import argparse
import json
import statistics
import tempfile
import time

import run

SETUP = r'''
local path=...;
local file=assert(io.open(path,'rb'));local data=file:read('*a');file:close();
local original=require('ui.client_assets');
local raw=assert(original.parse(data,{'moji'})).textures['font    moji    '];
package.loaded['ui.client_assets']={prepare=function()end,retry_pending=function()return false;end,
    generation=function()return 1;end,raw=function()return raw;end,
    texture=function()return {id=1,width=raw.width,height=raw.height};end,
    status=function()return {available=true};end,
    derived_texture=function(_,_,_,width,height)return {id=2,width=width,height=height};end};
local client=require('ui.client_fonts');client.prepare();
local countdown=require('ui.countdown_text');
local quads=0;
local sink={};
local list={AddImageQuad=function(_,a,b,c,d,e,f,g,h,i,j)quads=quads+1;
    sink[1],sink[2],sink[3],sink[4],sink[5],sink[6],sink[7],sink[8],sink[9],sink[10]=a,b,c,d,e,f,g,h,i,j;end};
local labels={'4h','12m','59s','2h','3m','9s'};
function benchmark(frames,outline)
    local options={countdown_outline=outline};quads=0;
    for _=1,frames do
        for index=1,72 do
            local text=labels[(index-1)%#labels+1];
            countdown.measure('Original FFXI',text,12,options,true);
            countdown.draw(list,'Original FFXI',text,index*20,20,12,0xFFFFFFFF,options,true);
        end;
    end;
    return quads/frames;
end;
function allocated(frames,outline)
    collectgarbage('collect');collectgarbage('stop');local before=collectgarbage('count');
    benchmark(frames,outline);local kb=(collectgarbage('count')-before)/frames;
    collectgarbage('restart');collectgarbage('collect');return kb;
end;
function collector(on) collectgarbage('collect'); collectgarbage(on and 'restart' or 'stop'); end;
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--overlay', type=Path)
    parser.add_argument('--font-dat', type=Path,
        default=run.ASHITA_LIBS.parents[1] / 'SquareEnix/FINAL FANTASY XI/ROM/119/51.DAT')
    args = parser.parse_args()
    results = []
    with tempfile.TemporaryDirectory(prefix='vantage_countdown_benchmark_') as folder:
        lua = run.runtime(folder)
        if args.overlay:
            lua.execute('package.path=.....";"..package.path', args.overlay.resolve().as_posix() + '/?.lua')
        lua.execute(SETUP, args.font_dat.resolve().as_posix())
        g = lua.globals()
        benchmark = g.benchmark
        for outline in (False, True):
            benchmark(20, outline)
            quads = benchmark(1, outline)
            kb = statistics.median(g.allocated(100, outline) for _ in range(3))
            timed = {}
            for on in (True, False):
                timings = []
                for _ in range(7):
                    g.collector(on)
                    start = time.perf_counter()
                    benchmark(100, outline)
                    timings.append((time.perf_counter() - start) * 10)
                g.collector(True)
                timed[on] = round(statistics.median(timings), 3)
            results.append({'case': f'72_countdowns_outline_{outline}', 'glyph_quads': quads,
                            'median_ms_per_frame': timed[True], 'median_ms_per_frame_gc_stopped': timed[False],
                            'kb_per_frame': round(kb, 1)})
    print(json.dumps({'limits': 'Actual font glyphs; mocked cached textures and draw calls. Lua CPU only, not GPU or live client FPS.',
                      'results': results}, indent=2))


if __name__ == '__main__':
    main()
