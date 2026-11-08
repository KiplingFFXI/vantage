"""The addon keeps its compiled traces in x86 LuaJIT through the heaviest frame scenarios and through a long session.

When LuaJIT's trace cache fills it throws every compiled trace away and starts over (lj_trace.c, trace_findfree), and
Vantage's party list strips, timer panels and settings window need more traces than the default 1,000. A session keeps the traces of
everything it has drawn, so one that has drawn all of them needs far more than any one scenario. vantage.lua raises the
limit itself when it loads (its jit.opt.start call). This runs tests/frame_harness.lua in a plain x86 luajit.exe
(tests/luajit-x86/luajit.exe, or --exe; through tests/x86_runtime.lua, which sets no options of its own) for the
alliance18, settings, search, filters, overhead, cooldowns, rolls, pet and edit scenarios and fails on any trace flush after the warmup, then runs one mixed session in one runtime (solo, party6, alliance18,
settings, filters, overhead, cooldowns, rolls, pet and edit, one after another, --cycles times, through H.scene) and fails on any flush from the app's load to
the session's end, when the session leaves fewer than FREE traces of vantage.lua's maxtrace free, or when a full cache
of traces like the session's would need more machine code than vantage.lua's maxmcode (LuaJIT flushes when that fills
too). H.scene adds each scenario's target and alliance effects to what the tracker holds and removes none, so after the
first alliance18 every scene also draws alliance18's 32 target effects (they last 187 to 404 s, and alliance18 applies
them again each cycle). It counts traces and bytes, never milliseconds: frame times are too noisy here to assert.

usage: jit_flush_guard.py [--exe LUAJIT_EXE] [--addon FOLDER] [--frames N] [--cycles N]
"""
from pathlib import Path
import argparse
import os
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / 'tests'
LUAJIT = TESTS / 'luajit-x86/luajit.exe'
SCENARIOS = ('alliance18', 'settings', 'search', 'filters', 'overhead', 'cooldowns', 'rolls', 'pet', 'edit')
# Search stays out of the session: it goes round every page, which nothing else here does, and with it in, twelve
# cycles held 6,397 to 10,304 traces.
MIXED = ('solo', 'party6', 'alliance18', 'settings', 'filters', 'overhead', 'cooldowns', 'rolls', 'pet', 'edit')
WARMUP = 600
# The traces this mixed session holds spread from run to run (about 5,700 to 7,650 after twelve cycles), 80 minutes
# of such a session at 60 frames a second was still adding some, and a player's session runs code this one doesn't,
# so a limit that only just fits here would still flush in play.
FREE = 2500
DRIVER = r'''
assert(loadfile(TESTS_DIR .. '/frame_harness.lua'))(os.getenv('VANTAGE_FRAME_SCENARIO'));
local flushes = H.flushes(tonumber(os.getenv('VANTAGE_FRAME_WARMUP')), tonumber(os.getenv('VANTAGE_FRAME_COUNT')));
io.stdout:write('FLUSHES ' .. tostring(flushes) .. '\n');
'''
# Every flush counts, from before the app loads to the end of the session, H.scene's commands and refreshes included:
# the cache starts empty, so any flush means it filled. The counter is the driver's own. The harness attaches one only
# in H.flushes and H.measure, which this doesn't call, and LuaJIT keeps one handler for each event, so one jit.flush()
# after the count checks that this one was still counting (CHECK 1).
MIXED_DRIVER = r'''
local flushes;
if jit and jit.attach then
    flushes = 0;
    jit.attach(function(what) if what == 'flush' then flushes = flushes + 1; end; end, 'trace');
end;
assert(loadfile(TESTS_DIR .. '/frame_harness.lua'))('solo');
if flushes == nil then io.stdout:write('FLUSHES nil\n'); return; end;
local frames = tonumber(os.getenv('VANTAGE_FRAME_COUNT'));
for _ = 1, tonumber(os.getenv('VANTAGE_FRAME_CYCLES')) do
    for name in os.getenv('VANTAGE_FRAME_SCENES'):gmatch('%S+') do
        H.scene(name);
        H.run(frames);
    end;
end;
local util, held, bytes = require('jit.util'), 0, 0;
for trace = 1, 65535 do
    if util.traceinfo(trace) then
        held = held + 1;
        local code = util.tracemc(trace);
        if code then bytes = bytes + #code; end;
    end;
end;
local counted = flushes;
jit.flush();
io.stdout:write('FLUSHES ' .. counted .. ' HELD ' .. held .. ' MCODE ' .. bytes .. ' CHECK ' .. (flushes - counted)
    .. '\n');
'''


def run(exe, addon, driver_text, env):
    with tempfile.TemporaryDirectory(prefix='vantage_flush_') as folder:
        driver = Path(folder) / 'driver.lua'
        driver.write_text(driver_text, encoding='utf-8')
        install = Path(folder) / 'install'
        install.mkdir()
        result = subprocess.run([str(exe), (TESTS / 'x86_runtime.lua').as_posix(), driver.as_posix(), install.as_posix(),
                                 Path(addon).resolve().as_posix(), Path(os.environ['ASHITA_LIBS']).resolve().as_posix(),
                                 TESTS.as_posix()],
                                env=dict(os.environ, **env), capture_output=True, text=True, timeout=1800)
        lines = [line for line in result.stdout.splitlines() if line.startswith('FLUSHES ')]
        if result.returncode or not lines:
            raise RuntimeError('x86 runtime failed: %s %s' % (result.stdout[-2000:], result.stderr[-2000:]))
        words = lines[0].split()
        if words[1] == 'nil':
            raise RuntimeError('the x86 runtime has no jit module to count flushes with')
        return [int(word) for word in words[1::2]]


def flushes(exe, scenario, addon, frames):
    return run(exe, addon, DRIVER, {'VANTAGE_FRAME_SCENARIO': scenario, 'VANTAGE_FRAME_WARMUP': str(WARMUP),
                                    'VANTAGE_FRAME_COUNT': str(frames)})[0]


def mixed(exe, addon, frames, cycles):
    """Trace flushes in the whole mixed session, the traces the cache holds at its end and their machine code, and the
    flushes the counter saw of the one jit.flush() after it."""
    return run(exe, addon, MIXED_DRIVER, {'VANTAGE_FRAME_SCENES': ' '.join(MIXED), 'VANTAGE_FRAME_COUNT': str(frames),
                                          'VANTAGE_FRAME_CYCLES': str(cycles)})


def limit(addon, name='maxtrace'):
    """The maxtrace (or maxmcode, in KB) vantage.lua sets with jit.opt.start."""
    source = Path(addon) / 'vantage.lua'
    found = re.findall(r"'%s=(\d+)'" % name, source.read_text(encoding='utf-8'))
    if len(found) != 1:
        raise RuntimeError('%s should set %s once, found %d' % (source, name, len(found)))
    return int(found[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--exe', type=Path, default=LUAJIT, help='a plain x86 luajit.exe (LuaJIT 2.1)')
    parser.add_argument('--addon', type=Path, default=ROOT / 'vantage')
    parser.add_argument('--frames', type=int, default=600, help='frames counted in each scenario after the warmup')
    parser.add_argument('--cycles', type=int, default=12, help='times the mixed session draws every scenario')
    args = parser.parse_args()
    if not os.environ.get('ASHITA_LIBS'):
        parser.error('set ASHITA_LIBS')
    if not args.exe.is_file():
        parser.error('needs a plain x86 luajit.exe: put one in tests/luajit-x86 or pass --exe')
    failed = []
    for scenario in SCENARIOS:
        count = flushes(args.exe, scenario, args.addon, args.frames)
        print('%s: %d trace flushes in %d frames after %d warmup frames' % (scenario, count, args.frames, WARMUP), flush=True)
        if count:
            failed.append(scenario)
    maxtrace, maxmcode = limit(args.addon), limit(args.addon, 'maxmcode')
    count, held, bytes, check = mixed(args.exe, args.addon, args.frames, args.cycles)
    if check != 1:
        raise RuntimeError('the mixed session\'s flush counter saw %d of one jit.flush() after it, so it may have '
                           'missed flushes in it' % check)
    if not held:
        raise RuntimeError('the mixed session left no compiled trace to measure')
    print('mixed: %d trace flushes in one session of %s, %d frames each, %d times over (%d frames); %d of %d traces '
          'held at the end' % (count, ', '.join(MIXED), args.frames, args.cycles, args.frames * len(MIXED) * args.cycles,
                               held, maxtrace), flush=True)
    if count:
        failed.append('the mixed session')
    if failed:
        print('FAIL: LuaJIT flushed its trace cache in ' + ', '.join(failed))
        return 1
    if held > maxtrace - FREE:
        print('FAIL: the mixed session left %d traces free of maxtrace=%d, fewer than %d' % (maxtrace - held, maxtrace,
                                                                                            FREE))
        return 1
    need = bytes * maxtrace // held // 1024
    print('machine code: %d KB for those %d traces, so %d such traces need about %d KB of maxmcode=%d'
          % (bytes // 1024, held, maxtrace, need, maxmcode), flush=True)
    if need > maxmcode:
        print('FAIL: a full trace cache would run out of machine code first (maxmcode=%d KB)' % maxmcode)
        return 1
    print('No trace flushes in ' + ', '.join(SCENARIOS) + ' or the mixed session, and %d traces free after it.'
          % (maxtrace - held))
    return 0


if __name__ == '__main__':
    sys.exit(main())
