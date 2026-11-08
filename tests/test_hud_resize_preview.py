"""Exercise timer and alert edges through real pointer input and addon history."""
from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
PREVIEW = HERE / 'preview'


class HudResizeInputTests(unittest.TestCase):
    def test_timer_and_notice_edges_with_undo(self):
        actions, frame = [], 2
        grips = {
            'left': [0.01, 0.5], 'right': [0.99, 0.5],
            'top': [0.5, 0.01], 'bottom': [0.5, 0.99],
            'top_left': [0.01, 0.01], 'top_right': [0.99, 0.01],
            'bottom_left': [0.01, 0.99], 'bottom_right': [0.99, 0.99],
        }
        for kind in ('timer', 'notice'):
            for edge, point in grips.items():
                actions.extend([
                    {'frame': frame, 'shift': True, 'mouse': [10, 10],
                     'lua': "PREVIEW.reset('%s')" % kind},
                    {'frame': frame + 1, 'target': '##move_self_buffs' if kind == 'timer' else '##notice_layout',
                     'point': point, 'down': True},
                    {'frame': frame + 2, 'delta': [20, 15]},
                    {'frame': frame + 3, 'down': False},
                    {'frame': frame + 4, 'lua': "PREVIEW.verify('%s','%s')" % (kind, edge)},
                ])
                frame += 6
        with tempfile.TemporaryDirectory(prefix='vantage_resize_input_') as folder:
            inputs = Path(folder) / 'input.json'
            inputs.write_text(json.dumps(actions), encoding='utf-8')
            output = HERE / 'out' / 'hud-all-edges-input.png'
            result = subprocess.run([sys.executable, str(PREVIEW / 'preview.py'), '--full', '--hud',
                                     '--frames', str(frame), '--size', '1280', '800', '--no-crop',
                                     '--script', str(PREVIEW / 'hud_resize_interaction.lua'),
                                     '--input-script', str(inputs), '--out', str(output)],
                                    capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('OK window=', result.stdout)
            self.assertTrue(output.is_file())


if __name__ == '__main__':
    unittest.main()

