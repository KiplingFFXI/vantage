"""Exercise settings resizing through the real ImGui renderer and addon entrypoint."""
from pathlib import Path
import subprocess
import sys
import unittest


HERE = Path(__file__).resolve().parent


class SettingsResizePreviewTests(unittest.TestCase):
    def test_settings_edges_peek_ordinary_resize_typing_and_undo(self):
        result = subprocess.run([
            sys.executable, str(HERE / 'preview' / 'preview.py'), '--full',
            '--frames', '145', '--out', str(HERE / 'out' / 'settings-resize-input.png'),
            '--script', str(HERE / 'preview' / 'settings_resize_interaction.lua'),
            '--input-script', str(HERE / 'preview' / 'settings_resize_input.json'),
        ], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('OK window=', result.stdout)
        self.assertIn('All settings edges', result.stderr)


if __name__ == '__main__':
    unittest.main()
