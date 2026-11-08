"""Compare real countdown pixels while retaining each font's ordinary frame text."""
from pathlib import Path
import os
import subprocess
import sys
import unittest

from PIL import Image

HERE = Path(__file__).resolve().parent
PREVIEW = HERE / 'preview'
INSTALL = Path(os.environ['ASHITA_LIBS']).resolve().parent.parent
CLIENT = INSTALL / 'SquareEnix' / 'FINAL FANTASY XI'
VIEW = INSTALL / 'polplugins' / 'DATs' / 'XiView-Standard'


class CountdownPreviewTests(unittest.TestCase):
    def render(self, native):
        output = HERE / 'out' / 'countdown-styles' / ('client-fonts.png' if native else 'ordinary-font.png')
        arguments = [sys.executable, str(PREVIEW / 'preview.py'), '--hud', '--frames', '4',
                     '--size', '1170', '750', '--no-crop', '--out', str(output),
                     '--exec', 'PREVIEW.countdown_native=' + ('true' if native else 'false'),
                     '--script', str(PREVIEW / 'countdown_gallery.lua')]
        if native:
            arguments += ['--client-assets', '--client-xiview-root', str(VIEW)]
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Countdown combinations and unchanged frame text rendered', result.stderr)
        with Image.open(output) as source:
            image = source.convert('RGBA')
        for column in range(3 if native else 1):
            x = 15 + column * 390
            controls, timers = [], []
            for index in range(8):
                y = 52 + index * 85
                controls.append(image.crop((x + 130, y + 7, x + 345, y + 38)).tobytes())
                timers.append(image.crop((x + 50, y + 7, x + 125, y + 40)).tobytes())
            self.assertEqual(len(set(controls)), 1, 'Countdown styling changed ordinary frame text pixels')
            self.assertNotEqual(timers[0], timers[1], 'Bold must visibly thicken the selected font')
            self.assertNotEqual(timers[0], timers[2], 'Shadow must be independently visible')
            self.assertNotEqual(timers[0], timers[4], 'Outline must be independently visible')
            self.assertNotEqual(timers[2], timers[4], 'Outline and shadow must remain distinct choices')
            self.assertNotEqual(timers[6], timers[7], 'Bold must still work with shadow and outline enabled')

    def test_ordinary_font_countdowns(self):
        self.render(False)

    @unittest.skipUnless((CLIENT / 'ROM/119/51.DAT').is_file() and (VIEW / 'ROM/119/51.DAT').is_file(),
                         'Original FFXI and local XI View artwork are unavailable')
    def test_original_and_xiview_countdowns(self):
        self.render(True)


if __name__ == '__main__':
    unittest.main()
