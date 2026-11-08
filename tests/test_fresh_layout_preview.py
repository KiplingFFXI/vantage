"""Real ImGui: a fresh install's displays keep clear of each other, the chat log and the game's party list and target
window."""
from pathlib import Path
import os
import subprocess
import sys
import unittest

HERE = Path(__file__).resolve().parent
PREVIEW = HERE / 'preview'
CLIENT = Path(os.environ['ASHITA_LIBS']).resolve().parent.parent / 'SquareEnix' / 'FINAL FANTASY XI'


class FreshLayoutPreviewTests(unittest.TestCase):
    def run_script(self, script, size, frames, name, inputs=None):
        output = HERE / 'out' / 'fresh-layout' / (name + '.png')
        arguments = [sys.executable, str(PREVIEW / 'preview.py'), '--hud', '--frames', str(frames), '--no-crop',
                     '--size', str(size[0]), str(size[1]), '--script', str(PREVIEW / script), '--out', str(output)]
        if inputs:
            arguments += ['--input-script', str(PREVIEW / inputs)]
        if (CLIENT / 'ROM/119/51.DAT').is_file():
            arguments.append('--client-assets')
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def test_fresh_displays_keep_clear_on_each_screen(self):
        for size in ((1280, 720), (1600, 900), (1920, 1080)):
            with self.subTest(size=size):
                text = self.run_script('fresh_chat_layout.lua', size, 4, 'fresh-%dx%d' % size)
                self.assertIn('fresh layout ok %dx%d' % size, text)


if __name__ == '__main__':
    unittest.main()
