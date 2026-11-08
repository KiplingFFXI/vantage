"""Exercise persistence against the real Windows filesystem and LuaJIT FFI."""
from pathlib import Path
import ctypes
import os
import tempfile
import unittest

from lupa import luajit21

ROOT = Path(__file__).resolve().parents[1]
LIBS = Path(os.environ['ASHITA_LIBS'])
# The strict json.lua Vantage ships as core.json, as tests/run.py loads it; the game folder's copy is lenient.
JSON = ROOT / 'vantage/core/json.lua'


@unittest.skipUnless(os.name == 'nt', 'Windows replacement and sharing checks.')
class NativeStoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='vantage_native_')
        # resolve() gives the long form of a short temp path (RUNNER~1 on GitHub's runner), as mkdir's check below does.
        self.folder = Path(self.temp.name).resolve()
        self.path = self.folder / 'settings.json'
        self.lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('package.path = ... .. package.path', ';'.join((
            (ROOT / 'vantage').as_posix() + '/?.lua', LIBS.as_posix() + '/?.lua', '')))
        self.lua.execute('local path = ...; package.preload.json = function() return dofile(path) end', JSON.as_posix())
        self.lua.globals().FS_EXISTS = lambda path: Path(path).exists()

        def mkdir(path):
            target = Path(path).resolve()
            if not target.is_relative_to(self.folder):
                raise RuntimeError('Unexpected test directory.')
            target.mkdir(parents=True, exist_ok=True)
            return True

        self.lua.globals().FS_MKDIR = mkdir
        self.lua.execute('''
            T = function(value) return value end;
            ashita = { fs = { exists = FS_EXISTS, create_dir = FS_MKDIR } };
            VANTAGE_TEST_MODE = true;
            store = require('core.store');
            assert(require('ffi').os == 'Windows');
        ''')
        self.store = self.lua.globals().store

    def tearDown(self):
        self.lua = None
        self.temp.cleanup()

    def write(self, value):
        result = self.store.write(self.path.as_posix(), self.lua.table_from(value))
        return result if isinstance(result, tuple) else (result, None)

    def test_create_replace_and_read(self):
        self.assertEqual(self.write({'version': 1}), (True, None))
        self.assertEqual(self.write({'version': 2, 'theme': 'Phoenix'}), (True, None))
        loaded = self.store.read(self.path.as_posix())
        self.assertEqual(loaded['version'], 2)
        self.assertEqual(loaded['theme'], 'Phoenix')
        self.assertEqual(list(self.folder.glob('*.tmp')), [])

    def test_corrupt_document_is_untouched(self):
        # A trailing comma is refused in game, so the file it is in is never overwritten either.
        for previous in (b'{not valid json', b'{"version":1,}'):
            self.path.write_bytes(previous)
            ok, error = self.write({'version': 3})
            self.assertFalse(ok, previous)
            self.assertIn('kept unchanged', error)
            self.assertEqual(self.path.read_bytes(), previous)
            self.assertEqual(list(self.folder.glob('*.tmp')), [])

    def test_windows_read_lock_preserves_existing_file(self):
        self.path.write_bytes(b'{"version":1}')
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.CreateFileW.argtypes = (ctypes.c_wchar_p, ctypes.c_uint32,
                                      ctypes.c_uint32, ctypes.c_void_p,
                                      ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p)
        kernel.CreateFileW.restype = ctypes.c_void_p
        kernel.CloseHandle.argtypes = (ctypes.c_void_p,)
        handle = kernel.CreateFileW(str(self.path), 0x80000000, 0, None, 3, 0, None)
        self.assertNotEqual(handle, ctypes.c_void_p(-1).value)
        try:
            ok, error = self.write({'version': 2})
            self.assertFalse(ok)
            self.assertIn('kept unchanged', error)
        finally:
            kernel.CloseHandle(handle)
        self.assertEqual(self.path.read_bytes(), b'{"version":1}')
        self.assertEqual(list(self.folder.glob('*.tmp')), [])

    def test_flush_is_a_best_try(self):
        # A save flushes its temporary file to the disk before the move puts it in place. A file that isn't there or
        # that another program holds shut can't be flushed, which never makes one or stops anything.
        self.path.write_bytes(b'{"version":1}')
        self.assertIs(self.store.flush(self.path.as_posix()), True)
        missing = self.folder / 'missing.json'
        self.assertIs(self.store.flush(missing.as_posix()), False)
        self.assertFalse(missing.exists())
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.CreateFileW.argtypes = (ctypes.c_wchar_p, ctypes.c_uint32,
                                      ctypes.c_uint32, ctypes.c_void_p,
                                      ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p)
        kernel.CreateFileW.restype = ctypes.c_void_p
        kernel.CloseHandle.argtypes = (ctypes.c_void_p,)
        handle = kernel.CreateFileW(str(self.path), 0x80000000, 0, None, 3, 0, None)
        self.assertNotEqual(handle, ctypes.c_void_p(-1).value)
        try:
            self.assertIs(self.store.flush(self.path.as_posix()), False)
        finally:
            kernel.CloseHandle(handle)
        self.assertEqual(self.path.read_bytes(), b'{"version":1}')

    def test_create_new_file(self):
        # An export saved to the shared folder: a new file with the whole text, and one already there is never replaced.
        made = self.folder / 'shared' / 'Raid.txt'
        ok = self.store.create(made.as_posix(), 'VG:1:00000000:{}')
        self.assertIs(ok if not isinstance(ok, tuple) else ok[0], True)
        self.assertEqual(made.read_bytes(), b'VG:1:00000000:{}')
        ok, why, code = self.store.create(made.as_posix(), 'VG:1:00000000:{"kind":"other"}')
        self.assertFalse(ok)
        self.assertEqual(code, 'exists')
        self.assertEqual(made.read_bytes(), b'VG:1:00000000:{}')
        self.assertEqual(list(made.parent.glob('*.tmp')), [])


if __name__ == '__main__':
    unittest.main()
