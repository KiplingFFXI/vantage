"""Paint the cooldown panels with real ImGui and installed client artwork."""
from pathlib import Path
import os
import subprocess
import sys
import unittest

HERE = Path(__file__).resolve().parent
CLIENT = Path(os.environ['ASHITA_LIBS']).resolve().parent.parent / 'SquareEnix' / 'FINAL FANTASY XI'


@unittest.skipUnless(CLIENT.is_dir(), 'Local client files are unavailable')
class RecastPreviewTests(unittest.TestCase):
    def test_three_categories_and_layouts(self):
        result = subprocess.run([
            sys.executable, str(HERE / 'preview/preview.py'), '--client-assets',
            '--hud', '--frames', '3', '--size', '1060', '810', '--no-crop',
            '--script', str(HERE / 'preview/recast_gallery.lua'),
            '--out', str(HERE / 'out/recast-gallery.png')],
            capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('OK window=', result.stdout)


if __name__ == '__main__':
    unittest.main()
