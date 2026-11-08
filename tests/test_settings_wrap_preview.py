"""Keep large-font button captions and their ImGui identities intact on resize."""
from pathlib import Path
import subprocess
import sys
import unittest


HERE = Path(__file__).resolve().parent


class SettingsWrapPreviewTests(unittest.TestCase):
    def test_button_wrap_and_identity(self):
        result = subprocess.run([
            sys.executable, str(HERE / 'preview/preview.py'),
            '--frames', '7', '--size', '1200', '1200',
            '--script', str(HERE / 'preview/settings_wrapped_buttons.lua'),
            '--out', str(HERE / 'out/full-review/settings-button-wrap.png'),
        ], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('OK window=', result.stdout)


if __name__ == '__main__':
    unittest.main()
