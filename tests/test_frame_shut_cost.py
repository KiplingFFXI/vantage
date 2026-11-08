"""With the settings window shut, a frame makes no more than it did when the window loaded with the addon.

The window loads the first time it opens (vantage/ui/settings_stub.lua). Each window-shut scenario of
tests/frame_harness.lua runs with the JIT off, where the counts repeat from run to run: once as it is, where the
window must stay unloaded, and once with the window required first, as vantage.lua did before. A frame may make at
most 0.5 KB more than that. Skipped without the client.
"""
from pathlib import Path
import os
import tempfile
import unittest

import benchmark_frame

GAME = Path(os.environ['ASHITA_LIBS']).resolve().parent.parent / 'SquareEnix/FINAL FANTASY XI'
SHUT = ('solo', 'party6', 'alliance18', 'filters', 'overhead', 'cooldowns', 'rolls', 'pet', 'edit')
FRAMES = {'alliance18': 30}


def shut_frame(scenario, loaded):
    """(KB per frame with the collector stopped, whether the window module is loaded) after a warmup."""
    with tempfile.TemporaryDirectory(prefix='vantage_frame_') as folder:
        lua = benchmark_frame.runtime(folder)
        lua.execute('jit.off(); jit.flush()')
        lua.execute((benchmark_frame.HERE / 'frame_harness.lua').read_text(encoding='utf-8'), scenario)
        lua.execute('jit.off(); jit.flush()')
        if loaded:
            lua.execute("require('ui.settings_window')")
        H = lua.globals().H
        H.run(120)
        count = FRAMES.get(scenario, 60)
        values = sorted(float(H.alloc(count)) for _ in range(3))
        return values[1], lua.eval("type(package.loaded['ui.settings_window']) == 'table'")


class ShutFrameCostTests(unittest.TestCase):
    def test_shut_window_costs_nothing_more(self):
        if not (GAME / 'ROM/119/51.DAT').is_file():
            self.skipTest('No local client art')
        for scenario in SHUT:
            with self.subTest(scenario=scenario):
                now, loaded = shut_frame(scenario, False)
                self.assertFalse(loaded, '%s loaded the settings window with it shut' % scenario)
                before, loaded = shut_frame(scenario, True)
                self.assertTrue(loaded, 'fixture: the window is loaded')
                self.assertLessEqual(now, before + 0.5, '%s makes %.2f KB a frame, %.2f with the window loaded'
                                     % (scenario, now, before))


if __name__ == '__main__':
    unittest.main()
