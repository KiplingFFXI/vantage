"""With the settings window open, its draw makes nothing a frame once warm.

Each scene of tests/frame_harness.lua below runs with the JIT off, where the counts repeat from run to run. After a
warmup the window's draw is counted alone, with the collector stopped: its frame, look and skin, Undo and Redo, the
search box and the page with its controls. The main page has every section open, More look's art checks among them,
and every tab of the panel frame is drawn as a player has it. The tick, text and number controls are also counted
alone, on Timer durations with a page that draws one of each. A table made every tenth draw shows. Skipped without
the client.
"""
from pathlib import Path
import os
import tempfile
import unittest

import benchmark_frame

GAME = Path(os.environ['ASHITA_LIBS']).resolve().parent.parent / 'SquareEnix/FINAL FANTASY XI'
SCENES = ('settings', 'main_closed', 'main_grid', 'settings_help', 'settings_display', 'settings_filters', 'settings_party',
          'settings_durations', 'settings_profiles',
          'panel_show', 'panel_look', 'panel_look_open', 'panel_filters', 'panel_place', 'panel_when', 'panel_recasts',
          'panel_party', 'panel_party_look', 'panel_party_filters', 'panel_party_place', 'panel_party_when', 'panel_overhead',
          'panel_overhead_filters', 'panel_cooldowns', 'panel_rolls', 'panel_pet', 'panel_pet_filters', 'panel_alerts',
          'panel_alerts_rule', 'panel_hidden')

# Counts what the window's draw makes, and makes a table every tenth draw while leak is on.
COUNT = r"""
local window = package.loaded['ui.settings_window']
assert(type(window) == 'table', 'The settings window did not load.')
local draw = window.draw
WINDOW = { made = 0, calls = 0, leak = false }
window.draw = function(...)
    local counted = WINDOW
    local before = collectgarbage('count')
    draw(...)
    counted.calls = counted.calls + 1
    if counted.leak and counted.calls % 10 == 0 then counted.left = {} end
    counted.made = counted.made + (collectgarbage('count') - before)
end
function WINDOW.measure(count)
    collectgarbage('collect'); collectgarbage('collect')
    collectgarbage('stop')
    H.run(6)
    WINDOW.made, WINDOW.calls = 0, 0
    H.run(count)
    local each = WINDOW.made / math.max(1, WINDOW.calls)
    collectgarbage('restart')
    return each, WINDOW.calls
end
"""

# A Timer durations page that draws one tick, one text box and one number, as the real page does through the window.
CONTROLS = r"""
local object = { on = true, name = 'Tester', seconds = 30 }
require('ui.duration_settings').draw = function(_, _, _, _, c)
    c.check('A tick', object, 'on', 'A tick.')
    c.text('A name', object, 'name', 'A name.', 40)
    c.number('A time', object, 'seconds', 1, 60, 'A time.', true)
end
"""


def window_draw(scenario, setup=None, leak=False):
    """(KB the window's draw makes each frame, draws counted) after a warmup."""
    with tempfile.TemporaryDirectory(prefix='vantage_frame_') as folder:
        lua = benchmark_frame.runtime(folder)
        lua.execute('jit.off(); jit.flush()')
        lua.execute((benchmark_frame.HERE / 'frame_harness.lua').read_text(encoding='utf-8'), scenario)
        lua.execute('jit.off(); jit.flush()')
        if setup:
            lua.execute(setup)
        H = lua.globals().H
        H.run(240)
        lua.execute(COUNT)
        lua.globals().WINDOW.leak = leak
        each, calls = lua.eval('WINDOW.measure(60)')
        return float(each), int(calls)


class WindowFrameCostTests(unittest.TestCase):
    def setUp(self):
        if not (GAME / 'ROM/119/51.DAT').is_file():
            self.skipTest('No local client art')

    def test_open_window_makes_nothing(self):
        for scenario in SCENES:
            with self.subTest(scenario=scenario):
                each, calls = window_draw(scenario)
                self.assertEqual(calls, 60, 'fixture: the window draws each frame')
                self.assertLess(each, 0.002, '%s: the window makes %.4f KB a frame' % (scenario, each))

    def test_controls_make_nothing(self):
        each, calls = window_draw('settings_durations', CONTROLS)
        self.assertEqual(calls, 60, 'fixture: the window draws each frame')
        self.assertLess(each, 0.002, 'A tick, a text box and a number make %.4f KB a frame' % each)

    def test_a_table_shows(self):
        each, _ = window_draw('settings_display', leak=True)
        self.assertGreaterEqual(each, 0.002, 'A table made every tenth draw shows as %.4f KB' % each)


if __name__ == '__main__':
    unittest.main()
