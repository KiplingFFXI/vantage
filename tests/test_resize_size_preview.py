"""Check live size badges against real ImGui bounds while resizing with the mouse."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
OUT = HERE / 'out/resize-size-labels'
INSTALL = Path(os.environ['ASHITA_LIBS']).resolve().parent.parent
CLIENT = INSTALL / 'SquareEnix' / 'FINAL FANTASY XI'
VIEW = INSTALL / 'polplugins' / 'DATs' / 'XiView-Standard'


@unittest.skipUnless((CLIENT / 'ROM/119/51.DAT').is_file() and (VIEW / 'ROM/119/51.DAT').is_file(),
                     'Local client and XI View files are unavailable')
class ResizeSizePreviewTests(unittest.TestCase):
    def test_live_dimensions_with_both_client_fonts(self):
        actions = [
            {'frame': 2, 'shift': True, 'mouse': [518, 358]},
            {'frame': 3, 'down': True},
            {'frame': 4, 'delta': [60, 40]},
            {'frame': 5, 'down': False},
            {'frame': 6, 'lua': 'PREVIEW.verify_locked()'},
            {'frame': 7, 'mouse': [10, 10]},
            {'frame': 8, 'target': '##move_self_buffs', 'point': [.99, .99], 'down': True},
            {'frame': 9, 'delta': [40, 30]},
            {'frame': 10, 'lua': 'PREVIEW.verify_size(360,210,true)'},
            {'frame': 11, 'delta': [40, 30]},
            {'frame': 12, 'lua': 'PREVIEW.verify_size(400,240,true)'},
            {'frame': 13, 'down': False},
            {'frame': 14, 'lua': 'PREVIEW.verify_size(400,240,false)'},
            {'frame': 15, 'shift': False, 'mouse': [10, 10]},
            {'frame': 16, 'lua': 'PREVIEW.verify_hidden()'},
            {'frame': 17, 'shift': True},
        ]
        OUT.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='vantage_size_badges_') as folder:
            inputs = Path(folder) / 'input.json'
            inputs.write_text(json.dumps(actions), encoding='utf-8')
            for face, slug in [('Original FFXI', 'original-ffxi'), ('XI View', 'xi-view')]:
                with self.subTest(font=face):
                    output = OUT / f'live-size-{slug}.png'
                    result = subprocess.run([
                        sys.executable, str(HERE / 'preview/preview.py'), '--full', '--hud',
                        '--frames', '20', '--size', '900', '600', '--no-crop', '--client-assets',
                        '--client-xiview-root', str(VIEW),
                        '--exec', f"PREVIEW.test_font='{face}'",
                        '--script', str(HERE / 'preview/resize_size_labels.lua'),
                        '--input-script', str(inputs), '--out', str(output),
                    ], capture_output=True, text=True, timeout=60)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn('Live size badges passed: ' + face, result.stderr)
                    self.assertTrue(output.is_file())


if __name__ == '__main__':
    unittest.main()
