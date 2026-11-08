"""Per-frame Lua time and allocation of the default look with real client art; no game, GPU or live FPS.

Runs tests/frame_harness.lua (solo, party6, alliance18, settings, filters, overhead, cooldowns, rolls, pet and edit, the
main page with More look closed and open, the settings window on each other page, and the settings window with text in
its search box, held on each page and being typed) in the test runtime or, with --runtime
x86, in a plain x86 luajit.exe (tests/luajit-x86/luajit.exe, or --exe) through tests/x86_runtime.lua, where vantage.lua
sets LuaJIT's limits itself as it does in the game. Each run prints KB allocated per frame with the collector stopped, ms per frame with
the collector running and stopped, the mean, p95, p99 and max of single frames with the collector running, and how
many times LuaJIT flushed its compiled traces after the warmup.
"""
from pathlib import Path
import argparse
import os
import subprocess
import sys
import tempfile

from lupa import luajit21

HERE = Path(__file__).resolve().parent
ADDON = HERE.parent / 'vantage'
LUAJIT = HERE / 'luajit-x86/luajit.exe'
# Frames per batch. A batch with the collector stopped holds all its garbage (about 7 MB a frame in an alliance
# before batch 1), so the counts stay well inside the 32-bit runtime's memory.
FRAMES = {'solo': 600, 'party6': 300, 'alliance18': 60, 'settings': 300, 'filters': 300, 'overhead': 300, 'cooldowns': 300, 'rolls': 300,
          'pet': 300, 'edit': 300, 'main_closed': 300, 'main_open': 300, 'main_grid': 300, 'panel_show': 300, 'panel_look': 300,
          'panel_look_open': 300, 'panel_filters': 300, 'panel_place': 300, 'panel_when': 300, 'panel_recasts': 300,
          'panel_party': 300, 'panel_party_look': 300, 'panel_party_filters': 300,
          'panel_party_place': 300, 'panel_party_when': 300, 'panel_overhead': 300, 'panel_overhead_filters': 300,
          'panel_cooldowns': 300, 'panel_rolls': 300, 'panel_pet': 300, 'panel_pet_filters': 300, 'panel_alerts': 300,
          'panel_alerts_rule': 300, 'panel_hidden': 300}
# The settings scenario open on each other page; the settings row is the main page with every fold open.
PAGES = ['settings_filters', 'settings_display', 'settings_party', 'settings_durations', 'settings_profiles', 'settings_help']
FRAMES.update((page, 300) for page in PAGES)
# The settings window with text in its search box: held on each page, and search itself, being typed across them.
SEARCH = ['search', 'search_home'] + ['search_' + page[len('settings_'):] for page in PAGES]
FRAMES.update((page, 300) for page in SEARCH)
DRIVER = r'''
assert(loadfile(TESTS_DIR .. '/frame_harness.lua'))(os.getenv('VANTAGE_FRAME_SCENARIO'));
io.stdout:write('x86 ' .. H.measure(tonumber(os.getenv('VANTAGE_FRAME_COUNT')), tonumber(os.getenv('VANTAGE_FRAME_REPEATS'))) .. '\n');
'''


def libs():
    return Path(os.environ['ASHITA_LIBS']).resolve()


def runtime(install, addon=ADDON):
    """A test runtime like tests/run.py, with the addon folder chosen."""
    install, addon = Path(install).resolve(), Path(addon).resolve()
    lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
    lua.execute('package.path = ... .. package.path', ';'.join((
        addon.as_posix() + '/?.lua', HERE.as_posix() + '/?.lua', libs().as_posix() + '/?.lua', '')))
    g = lua.globals()
    g.MOCK_INSTALL_PATH, g.ADDON_DIR, g.ASHITA_LIBS = install.as_posix(), addon.as_posix(), libs().as_posix()
    g.VANTAGE_TEST_MODE = True

    def mkdir(path):
        target = Path(path).resolve()
        if not target.is_relative_to(install):
            raise RuntimeError('The harness may create folders only inside its temporary install.')
        target.mkdir(parents=True, exist_ok=True)
        return True

    g.MOCK_MKDIR = mkdir
    mkdir(install / 'config/addons/vantage')
    lua.execute((HERE / 'mock_ashita.lua').read_text(encoding='utf-8'))
    g.MOCK.fs[(install / 'config/addons/vantage').as_posix() + '/'] = True
    return lua


def harness(install, scenario, addon=ADDON, setup=()):
    lua = runtime(install, addon)
    lua.execute((HERE / 'frame_harness.lua').read_text(encoding='utf-8'), scenario)
    for code in setup:
        lua.execute(code)
    return lua


def digest(scenario, addon=ADDON, frames=120, setup=()):
    """(draw calls, hash) over the frames after a 60-frame warmup."""
    with tempfile.TemporaryDirectory(prefix='vantage_frame_') as folder:
        lua = harness(folder, scenario, addon, setup)
        H = lua.globals().H
        H.run(60)
        rows, members, problem = H.info()
        if problem != 'nil':
            raise AssertionError('%s reported a problem: %s' % (scenario, problem))
        count, value = H.draw_digest(frames)
        return int(count), int(value)


def host(scenario, addon, repeats):
    with tempfile.TemporaryDirectory(prefix='vantage_frame_') as folder:
        lua = harness(folder, scenario, addon)
        return 'host ' + lua.globals().H.measure(FRAMES[scenario], repeats)


def x86(scenario, addon, repeats, exe):
    with tempfile.TemporaryDirectory(prefix='vantage_frame_') as folder:
        driver = Path(folder) / 'driver.lua'
        driver.write_text(DRIVER, encoding='utf-8')
        install = Path(folder) / 'install'
        install.mkdir()
        env = dict(os.environ, VANTAGE_FRAME_SCENARIO=scenario, VANTAGE_FRAME_COUNT=str(FRAMES[scenario]),
                   VANTAGE_FRAME_REPEATS=str(repeats))
        result = subprocess.run([str(exe), (HERE / 'x86_runtime.lua').as_posix(), driver.as_posix(), install.as_posix(),
                                 Path(addon).resolve().as_posix(), libs().as_posix(), HERE.as_posix()], env=env,
                                capture_output=True, text=True)
        lines = [line for line in result.stdout.splitlines() if line.startswith('x86 ')]
        if result.returncode or not lines:
            raise RuntimeError('x86 runtime failed: %s %s' % (result.stdout[-2000:], result.stderr[-2000:]))
        return lines[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--runtime', choices=['host', 'x86'], default='host')
    parser.add_argument('--exe', type=Path, default=LUAJIT, help='a plain x86 luajit.exe (LuaJIT 2.1) for --runtime x86')
    parser.add_argument('--addon', type=Path, default=ADDON, help='folder holding vantage.lua, core and ui')
    parser.add_argument('--scenario', action='append', choices=list(FRAMES), help='repeatable; default every scene, panel tab, page and search')
    parser.add_argument('--runs', type=int, default=3, help='separate runtimes per scenario')
    parser.add_argument('--repeats', type=int, default=5, help='timed batches per collector setting in each run')
    args = parser.parse_args()
    if args.runtime == 'x86' and not (args.exe and args.exe.is_file()):
        parser.error('--runtime x86 needs a plain x86 luajit.exe: put one in tests/luajit-x86 or pass --exe')
    for scenario in args.scenario or list(FRAMES):
        for run in range(args.runs):
            line = x86(scenario, args.addon, args.repeats, args.exe) if args.runtime == 'x86' else host(scenario, args.addon, args.repeats)
            print('run %d %s' % (run + 1, line), flush=True)


if __name__ == '__main__':
    sys.exit(main())
