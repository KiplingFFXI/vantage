"""With the settings window open, its draw makes nothing a frame once warm.

Each scene of tests/frame_harness.lua below runs with the JIT off, where the counts repeat from run to run. After a
warmup the window's draw is counted alone, with the collector stopped: its frame, look and skin, Undo and Redo, the
search box and the page with its controls. The main page has every section open, Artwork's art checks among them,
and every tab of the panel frame is drawn as a player has it. The tick, text and number controls are also counted
alone, on Timer durations with a page that draws one of each. Party list's Size and place is counted again with
Your party in a panel of its own and every fold open. So are a search held on each page, a Spell recasts Filters tab, a
recast and an effect list open, a button whose caption wraps, partly ticked boxes on the main page and a question waiting
for Apply or Cancel. A table made every tenth draw shows. Skipped without the client.
"""
from pathlib import Path
import os
import tempfile
import unittest

import benchmark_frame

GAME = Path(os.environ['ASHITA_LIBS']).resolve().parent.parent / 'SquareEnix/FINAL FANTASY XI'
SCENES = ('settings', 'main_closed', 'settings_help', 'settings_display', 'settings_filters', 'settings_party',
          'settings_durations', 'settings_profiles',
          'panel_show', 'panel_look', 'panel_look_open', 'panel_filters', 'panel_place', 'panel_when', 'panel_recasts',
          'panel_party', 'panel_party_look', 'panel_party_filters', 'panel_party_place', 'panel_party_when', 'panel_overhead',
          'panel_overhead_filters', 'panel_cooldowns', 'panel_cooldowns_filters', 'panel_rolls', 'panel_pet', 'panel_pet_filters', 'panel_alerts',
          'panel_alerts_rule', 'panel_hidden')
SEARCHES = ('search_home', 'search_display', 'search_party', 'search_filters', 'search_durations', 'search_profiles',
            'search_help')

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

# Your party in a panel of its own, with every fold open, so Size and place draws its panel and member order rows.
DETACHED = r"""
H.app.state.settings.party_ui.groups[1].native_detached = true
H.app.state.settings_revision = H.app.state.settings_revision + 1
rawset(require('imgui'), 'CollapsingHeader', function() return true end)
"""

# Spell recasts on its Filters tab, which lists your recasts each frame.
RECAST_FILTERS = r"""
require('ui.panel_frame').open('spell_recasts', 'filters')
H.app.state.settings.panels.spell_recasts.enabled = true
H.app.state.settings_revision = H.app.state.settings_revision + 1
"""

# An alert rule's Recast list, or its Effect list, held open.
RECAST_LIST = r"""
local s = H.app.state.settings
s.alerts.rules[1].domain, s.alerts.rules[1].effect = 'recast', 0
H.app.state.settings_revision = H.app.state.settings_revision + 1
rawset(require('imgui'), 'BeginCombo', function(label) return label == '##Recast' end)
"""
EFFECT_LIST = r"""
rawset(require('imgui'), 'BeginCombo', function(label) return label == '##Effect' end)
"""

# A Timer durations page that draws one button too long for the page, so its caption wraps.
WRAPPED = r"""
local caption = 'A button with a caption far too long for the page it sits on, ' .. string.rep('so it wraps onto more lines ', 8)
local function press() end
require('ui.duration_settings').draw = function(_, _, _, _, c)
    c.button(caption, press, 'A button.')
end
"""

# A main page with partly ticked boxes: Bold countdowns on one display only, the hide with the game keys split and the
# glow around lit icons on one display only. A partly ticked box is a square with sharp corners, so a frame draws three
# more of those than before.
MIXED = r"""
local s = H.app.state.settings
local list = require('imgui').GetWindowDrawList()
local fill, squares = list.AddRectFilled, 0
list.AddRectFilled = function(self, from, to, color, rounding, ...)
    if rounding == 0 then squares = squares + 1 end
    return fill(self, from, to, color, rounding, ...)
end
H.run(5)
squares = 0
H.run(1)
local plain = squares
s.panels.self_buffs.countdown_bold = not s.panels.self_buffs.countdown_bold
s.visibility.hide_map = not s.visibility.hide_events
s.overhead.dispel_glow = not s.overhead.dispel_glow
H.app.state.settings_revision = H.app.state.settings_revision + 1
H.run(5)
squares = 0
H.run(1)
list.AddRectFilled = fill
assert(squares - plain == 3, 'fixture: three ticks draw partly ticked, not ' .. (squares - plain))
"""

# A main page with a question up, as a skin pick or Reset all of this display asks one.
ASKED = r"""
local asked = false
local function yes() end
require('ui.main_page').draw = function(_, _, _, _, c)
    if not asked then asked = true; c.ask('bench_question', 'Change it?', yes) end
    c.confirm_line('bench_question')
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

    def test_party_panel_of_its_own_makes_nothing(self):
        each, calls = window_draw('panel_party_place', DETACHED)
        self.assertEqual(calls, 60, 'fixture: the window draws each frame')
        self.assertLess(each, 0.002, 'With a panel of its own, Size and place makes %.4f KB a frame' % each)

    def test_a_held_search_makes_nothing(self):
        for scenario in SEARCHES:
            with self.subTest(scenario=scenario):
                each, calls = window_draw(scenario)
                self.assertEqual(calls, 60, 'fixture: the window draws each frame')
                self.assertLess(each, 0.002, '%s: a held search makes %.4f KB a frame' % (scenario, each))

    def test_recast_and_effect_lists_make_nothing(self):
        for name, scenario, setup in (('Spell recasts Filters', 'panel_filters', RECAST_FILTERS),
                                      ('an open Recast list', 'panel_alerts_rule', RECAST_LIST),
                                      ('an open Effect list', 'panel_alerts_rule', EFFECT_LIST)):
            with self.subTest(name=name):
                each, calls = window_draw(scenario, setup)
                self.assertEqual(calls, 60, 'fixture: the window draws each frame')
                self.assertLess(each, 0.002, '%s makes %.4f KB a frame' % (name, each))

    def test_a_wrapped_caption_makes_nothing(self):
        each, calls = window_draw('settings_durations', WRAPPED)
        self.assertEqual(calls, 60, 'fixture: the window draws each frame')
        self.assertLess(each, 0.002, 'A button whose caption wraps makes %.4f KB a frame' % each)

    def test_partly_ticked_boxes_make_nothing(self):
        each, calls = window_draw('settings', MIXED)
        self.assertEqual(calls, 60, 'fixture: the window draws each frame')
        self.assertLess(each, 0.002, 'Three partly ticked boxes make %.4f KB a frame' % each)

    def test_a_question_makes_nothing(self):
        each, calls = window_draw('settings', ASKED)
        self.assertEqual(calls, 60, 'fixture: the window draws each frame')
        self.assertLess(each, 0.002, 'A question waiting for Apply or Cancel makes %.4f KB a frame' % each)

    def test_a_table_shows(self):
        each, _ = window_draw('settings_display', leak=True)
        self.assertGreaterEqual(each, 0.002, 'A table made every tenth draw shows as %.4f KB' % each)


if __name__ == '__main__':
    unittest.main()
