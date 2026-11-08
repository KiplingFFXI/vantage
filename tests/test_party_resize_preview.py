"""Replay Shift-drags from a native buff strip's edges and corners through real ImGui input: each only moves the strip."""
from pathlib import Path
import subprocess
import sys
import unittest

HERE = Path(__file__).resolve().parent
PREVIEW = HERE / 'preview'


class PartyResizeInputTests(unittest.TestCase):
    def render(self, name, frames, size, script=None, extra=()):
        output = HERE / 'out' / 'resize-zone' / (name + '.png')
        result = subprocess.run([
            sys.executable, str(PREVIEW / 'preview.py'), '--frames', str(frames),
            '--size', *map(str, size), '--no-crop', '--hud', '--icon-fixture', *extra,
            '--script', str(PREVIEW / ((script or name) + '_interaction.lua')),
            '--input-script', str(PREVIEW / (name + '_input.json')), '--out', str(output),
        ], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('OK window=', result.stdout)
        self.assertTrue(output.is_file())

    def test_native_strip_horizontal_edges_on_both_sides(self):
        self.render('native_resize', 58, (1920, 1080))


if __name__ == '__main__':
    unittest.main()
