"""Measure unchanged effect-rule compilation in LuaJIT, without FFXI or rendering."""
import argparse
import json
from pathlib import Path
import statistics
import tempfile
import time

import run


PROGRAM = r'''
local filters = require('core.effect_filters');
local count, iterations = ...;
local settings = filters.make();
for i=1,count do
    settings.rules[i]={enabled=true,effect=i,kind='buff',name='Sample'..i,job=i%22+1,scope='party'};
end;
local compiled=filters.compile(settings);
for i=1,200 do assert(filters.compile(settings)==compiled); end;
collectgarbage('collect');
local start=BENCH_CLOCK();
for i=1,iterations do filters.compile(settings); end;
local elapsed=(BENCH_CLOCK()-start)*1000000/iterations;
collectgarbage('collect');
collectgarbage('stop');
local before=collectgarbage('count');
for i=1,500 do filters.compile(settings); end;
local allocated=(collectgarbage('count')-before)*1024/500;
collectgarbage('restart');
return elapsed,allocated;
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path)
    parser.add_argument('--iterations', type=int, default=5000)
    parser.add_argument('--repeats', type=int, default=5)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    if args.source:
        run.ADDON = args.source.resolve()
    report = {'method': 'Separate warmed LuaJIT runtimes; median CPU microseconds per unchanged compile; '
                        'heap growth over 500 calls with GC stopped; no FFXI, SDK or graphics driver',
              'source': str(run.ADDON), 'iterations': args.iterations, 'repeats': args.repeats, 'scenarios': []}
    for count in (0, 1, 16, 128):
        samples = []
        for _ in range(args.repeats):
            with tempfile.TemporaryDirectory(prefix='vantage_filters_') as folder:
                lua = run.runtime(folder)
                lua.globals().BENCH_CLOCK = time.perf_counter
                samples.append(lua.execute(PROGRAM, count, args.iterations))
        report['scenarios'].append({'rules': count,
                                    'compile_us': round(statistics.median(sample[0] for sample in samples), 6),
                                    'heap_bytes_per_compile': round(statistics.median(sample[1] for sample in samples), 3)})
    text = json.dumps(report, indent=2) + '\n'
    print(text, end='')
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding='utf-8')


if __name__ == '__main__':
    main()
