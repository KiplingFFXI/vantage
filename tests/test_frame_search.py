"""The settings scenarios of tests/frame_harness.lua measure what they say.

A search_ scenario keeps its text in the settings search box, a player typing moves through the words and the pages, the
main page's rows have More look closed and open, a panel_ row draws its tab, and a settings scenario fails when the window
never loaded or stopped, which would otherwise pass as a fast window. Skipped without the client.
"""
from pathlib import Path
import os
import tempfile
import unittest

from lupa.luajit21 import LuaError

import benchmark_frame

GAME = Path(os.environ['ASHITA_LIBS']).resolve().parent.parent / 'SquareEnix/FINAL FANTASY XI'
BROKEN = "package.preload['ui.settings_window'] = function() error('this window does not compile') end"
STOPS = "package.preload['ui.settings_window'] = function() return { draw = function() error('this page failed') end } end"
SEEN = """
SEEN = {};
function H.note()
    local memo = require('ui.settings_window').search_memo;
    SEEN[(memo.query or '') .. '/' .. H.app.state.settings.window.tab] = true;
end;
"""
# Keeps what the box was last given.
BOX = """
local imgui = require('imgui');
local box = rawget(imgui, 'InputTextWithHint');
rawset(imgui, 'InputTextWithHint', function(label, hint, value)
    local changed = box(label, hint, value);
    if label == '##find_settings' then BOX = value[1]; end;
    return changed;
end);
"""
# Each pick and slider the window draws.
DRAWN = """
local imgui = require('imgui');
DRAWN = {};
for _, name in ipairs({ 'BeginCombo', 'SliderFloat' }) do
    local draw = imgui[name];
    rawset(imgui, name, function(label, ...) DRAWN[label] = true; return draw(label, ...); end);
end;
"""


class SearchScenarioTests(unittest.TestCase):
    def setUp(self):
        if not (GAME / 'ROM/119/51.DAT').is_file():
            self.skipTest('No local client art')

    def test_every_page_has_a_scenario_with_text_in_the_box(self):
        self.assertEqual(len(benchmark_frame.SEARCH), len(benchmark_frame.PAGES) + 2)
        for scenario in benchmark_frame.SEARCH:
            self.assertIn(scenario, benchmark_frame.FRAMES)
        for scenario, page in (('search_home', 'Home'), ('search_display', 'Display'), ('search_profiles', 'Profiles')):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory(prefix='vantage_frame_') as folder:
                lua = benchmark_frame.harness(folder, scenario)
                lua.globals().H.run(30)
                self.assertEqual(lua.eval("require('ui.settings_window').search_memo.query"), 'effects')
                self.assertEqual(lua.eval('H.app.state.settings.window.tab'), page)

    def test_main_page_rows_have_more_look_closed_and_open(self):
        for scenario, open_look in (('main_closed', False), ('main_open', True)):
            self.assertIn(scenario, benchmark_frame.FRAMES)
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory(prefix='vantage_frame_') as folder:
                lua = benchmark_frame.harness(folder, scenario, setup=[DRAWN])
                lua.globals().H.run(5)
                self.assertEqual(lua.eval('H.app.state.settings.window.tab'), 'Home')
                self.assertTrue(lua.eval("DRAWN['##main_skin'] == true"))
                self.assertEqual(lua.eval("DRAWN['##main_icon_size'] == true"), open_look)

    def test_main_grid_row_has_the_grid_fold_open(self):
        self.assertIn('main_grid', benchmark_frame.FRAMES)
        for scenario, grid in (('main_closed', False), ('main_grid', True)):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory(prefix='vantage_frame_') as folder:
                lua = benchmark_frame.harness(folder, scenario, setup=[DRAWN])
                lua.globals().H.run(5)
                self.assertEqual(lua.eval('H.app.state.settings.window.tab'), 'Home')
                self.assertEqual(lua.eval("DRAWN['##main_grid_size'] == true"), grid)

    def test_panel_rows_draw_their_tab(self):
        for scenario, context, drawn, folded in (('panel_show', 'watch/show', '##frame_Layout', None),
                                                 ('panel_place', 'watch/place', '##frame_Width', None),
                                                 ('panel_look', 'watch/look', '##frame_Box', '##frame_Line up rows'),
                                                 ('panel_look_open', 'watch/look', '##frame_Line up rows', None),
                                                 ('panel_filters', 'watch/filters', '##frame_Effect', None),
                                                 ('panel_place', 'watch/place', '##frame_Fills', None),
                                                 ('panel_when', 'watch/when', '##frame_From_min', None),
                                                 ('panel_recasts', 'recasts/show', '##frame_Editing', None),
                                                 ('panel_party', 'party_ui/show', '##frame_Your own row', None),
                                                 ('panel_party_place', 'party_ui/place', '##frame_Longest row', None),
                                                 ('panel_party_look', 'party_ui/look', '##frame_Opacity', None),
                                                 ('panel_party_filters', 'party_ui/filters', '##frame_Effect', None),
                                                 ('panel_party_place', 'party_ui/place', '##frame_Buff side', None),
                                                 ('panel_party_when', 'party_ui/when', '##frame_From_min', None),
                                                 ('panel_overhead', 'overhead/show', '##frame_Most units at once', None),
                                                 ('panel_overhead_filters', 'overhead/filters', '##frame_Effect', None),
                                                 ('panel_cooldowns', 'cooldown_list/show', '##frame_Most shown', None),
                                                 ('panel_rolls', 'rolls/show', '##frame_Most rolls shown', None),
                                                 ('panel_pet', 'pet/show', '##frame_Most effects shown', None),
                                                 ('panel_pet_filters', 'pet/filters', '##frame_Effect', None),
                                                 ('panel_alerts', 'notices/show', '##frame_Sound volume', '##frame_Trigger'),
                                                 ('panel_alerts_rule', 'notices/show', '##frame_Trigger', None),
                                                 ('panel_hidden', 'hidden/show', '##frame_Effect', None)):
            self.assertIn(scenario, benchmark_frame.FRAMES)
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory(prefix='vantage_frame_') as folder:
                lua = benchmark_frame.harness(folder, scenario, setup=[DRAWN])
                lua.globals().H.run(5)
                self.assertEqual(lua.eval('H.app.state.settings.window.tab'), 'Display')
                self.assertEqual(lua.eval("require('ui.panel_frame').context()"), context)
                self.assertTrue(lua.eval("DRAWN[%r] == true" % drawn), drawn)
                if folded:
                    self.assertFalse(lua.eval("DRAWN[%r] == true" % folded), folded)

    def test_typing_moves_through_words_and_pages(self):
        with tempfile.TemporaryDirectory(prefix='vantage_frame_') as folder:
            lua = benchmark_frame.harness(folder, 'search', setup=[SEEN])
            H = lua.globals().H
            for _ in range(70):
                H.run(25)
                H.note()
            seen = list(lua.globals().SEEN)
            self.assertGreaterEqual(len({key.split('/')[0] for key in seen}), 12, 'every word is typed')
            # Party & alliance and Filters open the Display page, so the seven tabs draw five pages.
            self.assertEqual(len({key.split('/', 1)[1] for key in seen}), 5, 'every page is drawn')

    def test_a_scene_leaves_the_box_empty(self):
        with tempfile.TemporaryDirectory(prefix='vantage_frame_') as folder:
            lua = benchmark_frame.harness(folder, 'solo')
            H = lua.globals().H
            H.run(5)
            H.scene('search')
            lua.execute(BOX)
            H.run(60)
            self.assertNotEqual(lua.globals().BOX, '')
            H.scene('filters')
            H.scene('settings')
            H.run(5)
            self.assertEqual(lua.globals().BOX, '')

    def test_a_window_that_never_loaded_fails(self):
        for setup, why in ((BROKEN, 'never compiled'), (STOPS, 'stopped')):
            with self.subTest(why=why), tempfile.TemporaryDirectory(prefix='vantage_frame_') as folder:
                lua = benchmark_frame.harness(folder, 'settings', setup=[setup])
                with self.assertRaises(LuaError):
                    lua.globals().H.run(120)

    def test_a_shut_window_needs_nothing(self):
        with tempfile.TemporaryDirectory(prefix='vantage_frame_') as folder:
            lua = benchmark_frame.harness(folder, 'solo', setup=[BROKEN])
            lua.globals().H.run(30)


if __name__ == '__main__':
    unittest.main()
