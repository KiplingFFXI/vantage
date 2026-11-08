"""Reading an export takes time in step with its length, even with a long run of spaces inside it.

Text from the clipboard or from a file in the shared folder (vantage/core/share.lua) is read the frame Import from
clipboard or Import from a file is clicked. Trimming it with the pattern '^%s*(.-)%s*$' and finding its last } with '.*()}' took
time by the square of a run of spaces inside it: 11 to 35 s for 100,000 spaces, and over a minute at the 256 KB limit,
with the game stopped meanwhile. The Lua fixtures run on a stopped clock, so this one is timed here.
"""
import tempfile
import time
import unittest

import run

SPACES = 100000


class ShareReadTimeTests(unittest.TestCase):
    def test_a_long_run_of_spaces_reads_quickly(self):
        with tempfile.TemporaryDirectory(prefix='vantage_share_') as folder:
            lua = run.runtime(folder)
            read = lua.eval('function(text) local payload, why = require("core.share").read(text); '
                            'return type(payload) == "table" and payload.kind or why end')
            make = lua.eval("function(n) local body = '{\"kind\":\"profile\",\"data\":{\"panels\":{\"target\":{\"title\":\"a' "
                            ".. (' '):rep(n) .. 'b\"}}}}' return 'VG:1:' .. require('core.share').crc32(body) .. ':' .. body end")
            cases = (('a valid string with spaces inside', make(SPACES), 'profile'),
                     ('text with spaces inside', 'x' + ' ' * SPACES + 'y', 'That text is not a Vantage export.'),
                     ('a string in code marks with spaces after it', '```\n' + make(10) + ' ' * SPACES + 'x\n```', 'profile'))
            for name, text, expected in cases:
                with self.subTest(case=name):
                    started = time.perf_counter()
                    result = read(text)
                    took = time.perf_counter() - started
                    self.assertEqual(result, expected)
                    self.assertLess(took, 1.0, '%s took %.2f s to read' % (name, took))


if __name__ == '__main__':
    unittest.main()
