"""Grab twelve pixels inside real ImGui displays, rather than pixel-perfect borders."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
PREVIEW = HERE / 'preview'
GRIPS = {
    'left': ((0, .5), (12, 0)), 'right': ((1, .5), (-12, 0)),
    'top': ((.5, 0), (0, 12)), 'bottom': ((.5, 1), (0, -12)),
    'top_left': ((0, 0), (12, 12)), 'top_right': ((1, 0), (-12, 12)),
    'bottom_left': ((0, 1), (12, -12)), 'bottom_right': ((1, 1), (-12, -12)),
    'move': ((.5, .5), (0, 0)),
}


class InsetResizeInputTests(unittest.TestCase):
    def test_settings_normal_close_and_scroll_flags_after_shift(self):
        actions = [
            {'frame': 2, 'shift': True, 'mouse': [10, 10], 'lua': "PREVIEW.inset_reset('settings')"},
            {'frame': 3, 'lua': 'PREVIEW.settings_mode(true)'},
            {'frame': 4, 'shift': False, 'mouse': [988, 162]},
            {'frame': 6, 'lua': 'PREVIEW.settings_mode(false)', 'down': True},
            {'frame': 7, 'down': False},
            {'frame': 8, 'lua': "assert(not settings.window.open,'The native close button works after Shift is released')"},
            {'frame': 9, 'shift': True, 'lua': "PREVIEW.inset_reset('native')"},
        ]
        with tempfile.TemporaryDirectory(prefix='vantage_close_input_') as folder:
            inputs = Path(folder) / 'input.json'
            inputs.write_text(json.dumps(actions), encoding='utf-8')
            result = subprocess.run([
                sys.executable, str(PREVIEW / 'preview.py'), '--full', '--hud', '--icon-fixture',
                '--frames', '11', '--size', '1440', '1000', '--no-crop',
                '--script', str(PREVIEW / 'resize_inset_interaction.lua'),
                '--input-script', str(inputs), '--out', str(HERE / 'out' / 'resize-settings-normal-input.png'),
            ], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('OK window=', result.stdout)

    def test_inset_edges_and_centers_across_all_displays(self):
        actions, frame, count = [], 2, 0
        cases = [
            ('timer', '##move_self_buffs', GRIPS),
            ('recast', '##move_recasts', GRIPS),
            ('native', '##native_move_1', GRIPS),
            ('native_attached', '##native_move_1', GRIPS),
            ('notice', '##notice_layout', GRIPS),
            ('settings', '##settings_shift_layout', GRIPS),
        ]
        for kind, target, grips in cases:
            for edge, (point, offset) in grips.items():
                actions.extend([
                    {'frame': frame, 'shift': True, 'mouse': [10, 10],
                     'lua': f"PREVIEW.inset_reset('{kind}')"},
                    {'frame': frame + 1, 'target': target, 'point': point, 'delta': offset},
                    {'frame': frame + 2, 'down': True},
                    {'frame': frame + 3, 'delta': [20, 15]},
                    {'frame': frame + 4, 'down': False},
                    {'frame': frame + 5, 'lua': f"PREVIEW.inset_verify('{edge}')"},
                ])
                frame += 7
                count += 1
        output = HERE / 'out' / 'resize-inset-input.png'
        with tempfile.TemporaryDirectory(prefix='vantage_inset_input_') as folder:
            inputs = Path(folder) / 'input.json'
            inputs.write_text(json.dumps(actions), encoding='utf-8')
            result = subprocess.run([
                sys.executable, str(PREVIEW / 'preview.py'), '--full', '--hud', '--icon-fixture',
                '--frames', str(frame), '--size', '1440', '1000', '--no-crop',
                '--script', str(PREVIEW / 'resize_inset_interaction.lua'),
                '--input-script', str(inputs), '--out', str(output),
            ], capture_output=True, text=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f'Inset resize replay completed {count}', result.stderr)
        self.assertIn('OK window=', result.stdout)
        self.assertTrue(output.is_file())


if __name__ == '__main__':
    unittest.main()
