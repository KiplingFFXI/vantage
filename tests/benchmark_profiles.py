"""Measure the mocked Profiles page with temporary real JSON and a 60Hz clock.

Includes Lua/Python filesystem bridge and mock ImGui costs, not live GPU/FPS.
Only temporary saved settings are written. --source may point to a runtime backup.
"""
import argparse
import json
from pathlib import Path
import statistics
import tempfile
import time

import run


SETUP = r'''
local count = ...;
local app = dofile(ADDON_DIR .. '/vantage.lua');
for i = 1, count do assert(app.callbacks.profile_save('Profile ' .. i, false)); end;
local settings = app.state.settings;
settings.window.open, settings.window.tab = true, 'Profiles';
local window, view = require('ui.settings_window'), require('ui.hud').sample(100);
local store, path = require('core.store'), require('core.identity').root() .. 'profiles.json';
local read, reads = store.read, 0;
store.read = function(file, ...)
    if file == path then reads = reads + 1; end;
    return read(file, ...);
end;
BENCH_PROFILE = function(frames, warm)
    app.state.profile_summary_cache = nil;
    MOCK.now = 100;
    local function draw(frame)
        MOCK.now = 100 + frame / 60;
        window.draw(settings, view, app.callbacks);
        MOCK.imgui_calls = {};
    end;
    for frame = 0, warm - 1 do draw(frame); end;
    reads = 0;
    local started = PROFILE_CLOCK();
    for frame = warm, warm + frames - 1 do draw(frame); end;
    return (PROFILE_CLOCK() - started) * 1000 / frames, reads;
end;
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=run.ADDON)
    parser.add_argument('--frames', type=int, default=120)
    parser.add_argument('--repeats', type=int, default=3)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    if args.frames < 1 or args.repeats < 1:
        parser.error('frames and repeats must be positive')
    run.ADDON = args.source.resolve()
    output = {'method': 'mocked Profiles page, real temporary JSON, deterministic 60Hz elapsed clock; not live FPS',
              'source': str(run.ADDON), 'frames': args.frames, 'warm_frames': 3, 'repeats': args.repeats, 'cases': []}
    for profiles in (0, 1, 10):
        times, reads = [], []
        for _ in range(args.repeats):
            with tempfile.TemporaryDirectory(prefix='vantage_profiles_bench_') as folder:
                lua = run.runtime(folder)
                lua.globals().PROFILE_CLOCK = time.perf_counter
                lua.execute(SETUP, profiles)
                elapsed, count = lua.globals().BENCH_PROFILE(args.frames, 3)
                times.append(elapsed)
                reads.append(count)
        output['cases'].append({'profiles': profiles, 'median_ms_per_frame': statistics.median(times),
                                'samples_ms_per_frame': times, 'profile_file_reads': reads,
                                'median_reads_per_frame': statistics.median(reads) / args.frames})
    text = json.dumps(output, indent=2)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + '\n', encoding='utf-8')
    print(text)


if __name__ == '__main__':
    main()
