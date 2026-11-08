"""Replay every combined-panel resize direction through actual ImGui input."""
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
class CombinedRecastInputTests(unittest.TestCase):
    def test_combined_recast_edges_modes_and_wrapping(self):
        actions, frame = [], 2
        grips = {
            'left': [.01, .5], 'right': [.99, .5], 'top': [.5, .01], 'bottom': [.5, .99],
            'top_left': [.01, .01], 'top_right': [.99, .01],
            'bottom_left': [.01, .99], 'bottom_right': [.99, .99],
        }
        for mode in ('bars', 'expanded', 'icons'):
            for edge, point in grips.items():
                for direction in (-1, 1):
                    dx = (-30 if 'left' in edge else 30) * direction
                    dy = (-20 if 'top' in edge else 20) * direction
                    actions.extend([
                        {'frame': frame, 'shift': True, 'mouse': [10, 10], 'lua': f"PREVIEW.reset('{mode}')"},
                        {'frame': frame + 1, 'target': '##move_recasts', 'point': point, 'down': True},
                        {'frame': frame + 2, 'delta': [dx, dy]},
                        {'frame': frame + 3, 'down': False},
                        {'frame': frame + 4, 'lua': f"PREVIEW.verify('{mode}','{edge}',{direction})"},
                    ])
                    frame += 6
        actions.extend([
            {'frame': frame, 'shift': True, 'mouse': [10, 10], 'lua': 'PREVIEW.wrap_setup()'},
            {'frame': frame + 1, 'target': '##move_recasts', 'point': [.99, .5], 'down': True},
            {'frame': frame + 2, 'delta': [-230, 0]},
            {'frame': frame + 3, 'down': False},
            {'frame': frame + 4, 'shift': False, 'lua': 'PREVIEW.verify_wrap()'},
        ])
        with tempfile.TemporaryDirectory(prefix='vantage_combined_recast_input_') as folder:
            inputs = Path(folder) / 'input.json'
            inputs.write_text(json.dumps(actions), encoding='utf-8')
            output = HERE / 'out' / 'vantage-combined-recast-input.png'
            result = subprocess.run([
                sys.executable, str(PREVIEW / 'preview.py'), '--full', '--hud', '--client-assets',
                '--frames', str(frame + 5), '--size', '1000', '750', '--no-crop',
                '--script', str(PREVIEW / 'combined_recasts.lua'),
                '--input-script', str(inputs), '--out', str(output),
            ], capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('OK window=', result.stdout)
            self.assertTrue(output.is_file())


if __name__ == '__main__':
    unittest.main()
