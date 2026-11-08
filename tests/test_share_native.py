"""Read the Windows user name as exports leave it out (vantage/core/share.lua), with the real LuaJIT FFI.

Text typed in the settings window is UTF-8, while os.getenv gives the name in the ANSI code page, where an accented
letter is another byte. The Lua fixtures' ffi has no Windows calls, so this one runs here.
"""
from pathlib import Path
import os
import unittest

from lupa import luajit21

ROOT = Path(__file__).resolve().parents[1]
LIBS = Path(os.environ['ASHITA_LIBS'])
JSON = ROOT / 'vantage/core/json.lua'


@unittest.skipUnless(os.name == 'nt', 'The Windows user name.')
class NativeShareTests(unittest.TestCase):
    def setUp(self):
        self.user = os.environ.get('USERNAME')
        self.lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('package.path = ... .. package.path', ';'.join((
            (ROOT / 'vantage').as_posix() + '/?.lua', LIBS.as_posix() + '/?.lua', '')))
        self.lua.execute('local path = ...; package.preload.json = function() return dofile(path) end', JSON.as_posix())
        self.lua.execute('''
            VANTAGE_TEST_MODE = true;
            share = require('core.share');
            assert(require('ffi').os == 'Windows');
        ''')

    def tearDown(self):
        self.lua = None
        if self.user is None:
            os.environ.pop('USERNAME', None)
        else:
            os.environ['USERNAME'] = self.user

    def test_an_accented_name_reads_in_utf8(self):
        os.environ['USERNAME'] = 'Jos' + chr(0xe9)
        self.assertIs(self.lua.eval("share.windows_name() == 'Jos\\195\\169'"), True)
        # So a title that holds it is blanked in an export, and a file name leaves it out.
        self.assertEqual(self.lua.eval("share.file_name('Jos\\195\\169 raid', { share.windows_name() })"), 'raid')

    def test_a_plain_name(self):
        os.environ['USERNAME'] = 'Winuser'
        self.assertEqual(self.lua.eval('share.windows_name()'), 'Winuser')


if __name__ == '__main__':
    unittest.main()
