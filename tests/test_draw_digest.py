"""Every draw call of the default look stays the same: positions, UVs, colors, clips and text over 120 frames.

tests/frame_harness.lua draws solo (fresh defaults), a 6-member party and an 18-member
alliance with the installed client art. A change meant to draw differently updates EXPECTED with the values this
test prints, and says why; a speed or cleanup change must leave them as they are. Skipped without the client.
"""
from pathlib import Path
import os
import unittest

import benchmark_frame

GAME = Path(os.environ['ASHITA_LIBS']).resolve().parent.parent / 'SquareEnix/FINAL FANTASY XI'
# scenario: (draw calls, hash), recorded on the installed client.
EXPECTED = {
    'solo': (78000, 1232000184),
    'party6': (96240, 1836476962),
    'alliance18': (293640, 1232373777),
}


class DrawDigestTests(unittest.TestCase):
    def test_draw_calls_unchanged(self):
        if not (GAME / 'ROM/119/51.DAT').is_file():
            self.skipTest('No local client art')
        for scenario, expected in EXPECTED.items():
            with self.subTest(scenario=scenario):
                actual = benchmark_frame.digest(scenario)
                self.assertEqual(actual, expected, '%s draws %d calls, hash %d' % (scenario, *actual))


if __name__ == '__main__':
    unittest.main()
