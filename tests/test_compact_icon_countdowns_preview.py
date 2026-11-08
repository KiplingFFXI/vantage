"""Exercise the production icon HUD with real client glyphs and ImGui draw calls."""
from pathlib import Path
import os
import subprocess
import sys
import unittest

HERE = Path(__file__).resolve().parent
INSTALL = Path(os.environ['ASHITA_LIBS']).resolve().parent.parent
CLIENT = INSTALL / 'SquareEnix/FINAL FANTASY XI'
VIEW = INSTALL / 'polplugins/DATs/XiView-Standard'


@unittest.skipUnless((CLIENT / 'ROM/119/51.DAT').is_file() and (VIEW / 'ROM/119/51.DAT').is_file(),
                     'Original FFXI and local XI View artwork are unavailable')
class CompactIconCountdownPreviewTests(unittest.TestCase):
    def test_production_status_and_recast_countdowns(self):
        output = HERE / 'out/compact-icon-countdowns/compact-production-gallery.png'
        result = subprocess.run([
            sys.executable, str(HERE / 'preview/preview.py'), '--hud', '--no-crop', '--frames', '4',
            '--size', '1180', '560', '--client-assets', '--client-xiview-root', str(VIEW),
            '--script', str(HERE / 'preview/compact_icon_countdowns.lua'), '--out', str(output),
        ], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('OK window=', result.stdout)
        self.assertIn('exact ink gap, manual controls and unknown icons preserved', result.stderr)
        self.assertTrue(output.is_file())


if __name__ == '__main__':
    unittest.main()
