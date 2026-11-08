"""Drag the main page's Settings text size with actual ImGui pointer input while the page reflows under it."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
PREVIEW = HERE / 'preview'
CLIENT = Path(os.environ['ASHITA_LIBS']).resolve().parent.parent / 'SquareEnix' / 'FINAL FANTASY XI'


@unittest.skipUnless(CLIENT.is_dir(), 'Local client files are unavailable')
class MainPageDragTests(unittest.TestCase):
    def drag(self, width, height):
        # More look open and the page at its end, where the slider shows.
        actions = [{'frame': 1, 'lua': "settings.window.sections['Home/More look'] = true"},
                   {'frame': 3, 'mouse': [100 + width * 0.6, 80 + height * 0.6], 'wheel': -40},
                   {'frame': 6, 'target': '##main_window_text', 'point': [0.38, 0.5]}, {'frame': 7, 'down': True}]
        # Six pixels a frame to the right, as a player drags, for long enough to reach the largest size.
        actions += [{'frame': 8 + step, 'delta': [6, 0]} for step in range(90)]
        actions.append({'frame': 40, 'lua': "assert(require('imgui').IsAnyItemActive(), "
                                            "'The slider stays held while the page reflows: ' .. tostring(settings.window_style.font_size))"})
        actions.append({'frame': 98, 'down': False})
        actions.append({'frame': 100, 'lua': "assert(settings.window_style.font_size == 36, "
                                             "'The drag reaches the largest menu text size: ' .. tostring(settings.window_style.font_size))"})
        actions.append({'frame': 100, 'mouse': [-100, -100]})
        with tempfile.TemporaryDirectory(prefix='vantage_main_drag_') as folder:
            inputs = Path(folder) / 'input.json'
            inputs.write_text(json.dumps(actions), encoding='utf-8')
            result = subprocess.run([
                sys.executable, str(PREVIEW / 'preview.py'), '--client-assets', '--tab', 'Home',
                '--size', str(width + 200), str(height + 160), '--window-size', str(width), str(height), '--frames', '102',
                '--set', 'preview=false', '--input-script', str(inputs), '--out', str(Path(folder) / 'main-drag.png'),
            ], capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('OK window=', result.stdout)

    def test_default_window(self):
        self.drag(960, 680)

    def test_wide_window(self):
        self.drag(1220, 800)


if __name__ == '__main__':
    unittest.main()
