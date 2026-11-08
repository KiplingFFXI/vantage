"""Answer the Skin question on the main page through real Dear ImGui, at the default and a large menu font."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
CLIENT = Path(os.environ['ASHITA_LIBS']).resolve().parent.parent / 'SquareEnix' / 'FINAL FANTASY XI'


@unittest.skipUnless(CLIENT.is_dir(), 'Local client files are unavailable')
class LookConfirmPreviewTests(unittest.TestCase):
    def replay(self, width, height, font_size):
        # The page scrolled so Skin is on screen, as it is when a player reaches for it.
        actions = [{'frame': 4, 'mouse': [100 + width * 0.6, 300], 'wheel': -3 if font_size < 30 else -8}]
        for frame, target in ((7, '##main_skin'), (12, 'Mint##Mint'), (19, 'Cancel##look_main_skin'), (24, '##main_skin'), (29, 'Mint##Mint'),
                              (36, 'Apply##look_main_skin')):
            actions.extend([{'frame': frame, 'target': target, 'down': True}, {'frame': frame + 1, 'down': False}])
        actions.extend([
            {'frame': 6, 'lua': 'PREVIEW.capture()'},
            {'frame': 17, 'lua': 'PREVIEW.asked()'},
            {'frame': 22, 'lua': 'PREVIEW.cancelled()'},
            {'frame': 34, 'lua': 'PREVIEW.asked()'},
            {'frame': 39, 'lua': 'PREVIEW.applied()'},
            {'frame': 40, 'mouse': [-100, -100]},
        ])
        actions.sort(key=lambda action: action['frame'])
        with tempfile.TemporaryDirectory(prefix='vantage_look_confirm_') as folder:
            inputs = Path(folder) / 'input.json'
            inputs.write_text(json.dumps(actions), encoding='utf-8')
            result = subprocess.run([
                sys.executable, str(HERE / 'preview' / 'preview.py'), '--full', '--client-assets',
                '--frames', '42', '--size', '1400', str(height + 200), '--window-size', str(width), str(height),
                '--exec', f'PREVIEW.menu_font_size={font_size}',
                '--script', str(HERE / 'preview' / 'look_confirm.lua'),
                '--input-script', str(inputs), '--out', str(Path(folder) / 'look-confirm.png'),
            ], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Look question asked, cancelled and applied inside the window.', result.stderr)

    def test_default_font(self): self.replay(960, 680, 17)

    def test_narrow_large_font(self): self.replay(560, 1100, 36)


if __name__ == '__main__':
    unittest.main()
