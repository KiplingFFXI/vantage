"""Exercise subpage isolation and navigation with real Dear ImGui mouse input."""
from pathlib import Path
import subprocess
import sys
import unittest


HERE = Path(__file__).resolve().parent


class DisplayEditorPreviewTests(unittest.TestCase):
    def test_display_tabs_normal_narrow_and_large_font(self):
        for width, font_size in ((1000, 18), (560, 18), (560, 36)):
            with self.subTest(width=width, font_size=font_size):
                result = subprocess.run([
                    sys.executable, str(HERE / 'preview/preview.py'),
                    '--frames', '29', '--size', '1400', '1400',
                    '--set', f'window.width={width}', '--set', 'window.height=1200',
                    '--set', 'window.x=20', '--set', 'window.y=20',
                    '--set', f'window_style.font_size={font_size}',
                    '--script', str(HERE / 'preview/display_editor_navigation.lua'),
                    '--input-script', str(HERE / 'preview/display_editor_navigation_input.json'),
                    '--out', str(HERE / f'out/ui-consolidation/editor-{width}-{font_size}.png'),
                ], capture_output=True, text=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('OK window=', result.stdout)
                self.assertIn('Actual subpage clicks', result.stderr)


if __name__ == '__main__':
    unittest.main()
