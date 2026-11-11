"""tools/client_check.py finds every client pattern the addon and ffxi.itemdata look for, each exactly once."""
from contextlib import redirect_stdout
import io
import os
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import client_check

CLIENTS = ROOT / 'tests/fixtures/clients'
SOURCES = ('core/chat.lua', 'core/client.lua', 'core/native_party_ui.lua', 'core/clock.lua', 'core/name_anchor.lua',
           'core/game_buffs.lua')
LIBRARY = {
    'ffxi/itemdata.lua': "local time = require 'ffxi.time';\n"
                         "itemdata.ptrs.parse_augments = ashita.memory.find(0, 0, '8B5424040F', 0, 0);\n",
    'ffxi/time.lua': "local jit = require 'jit';\n"
                     "        local_time  = ashita.memory.find(0, 0, '8B442404??8BC8', 0, 0), -- sqLocalTime\n",
}


def image(patterns, twice=()):
    """A decoded-image-shaped PE: one section holding each pattern once, wildcards as zero, twice two times. A pattern
    that starts a longer one is planted with it: core/game_buffs.lua's starts are the first bytes of its routines."""
    body = bytearray(0x40)
    for pattern in patterns:
        if any(other != pattern and other.startswith(pattern) for other in patterns):
            continue
        planted = bytes.fromhex(pattern.replace('??', '00')) + bytes(0x40)
        body += planted * (2 if pattern in twice else 1)
    data = bytearray(0x1000) + body
    data[:2] = b'MZ'
    struct.pack_into('<I', data, 0x3C, 0x80)
    data[0x80:0x84] = b'PE\0\0'
    struct.pack_into('<HH', data, 0x84, 0x14C, 1)
    struct.pack_into('<H', data, 0x94, 0xE0)
    struct.pack_into('<H', data, 0x98, 0x10B)
    struct.pack_into('<I', data, 0x98 + 28, 0x10000000)
    data[0x178:0x17D] = b'.text'
    struct.pack_into('<II', data, 0x180, len(body), 0x1000)
    return bytes(data)


class ClientCheckTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='vantage_client_check_')
        self.root = Path(self.work.name)
        self.addon, self.libs = self.root / 'vantage', self.root / 'libs'
        for name in SOURCES:
            (self.addon / name).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / 'vantage' / name, self.addon / name)
        (self.addon / 'core/recasts.lua').write_text("local ok,value=pcall(require,'ffxi.itemdata');\n", encoding='ascii')
        for name, text in LIBRARY.items():
            (self.libs / name).parent.mkdir(parents=True, exist_ok=True)
            (self.libs / name).write_text(text, encoding='ascii')

    def tearDown(self):
        self.work.cleanup()

    def patterns(self):
        found = client_check.addon_patterns(self.addon) + client_check.library_patterns(self.libs)
        return list(dict.fromkeys(pattern for _, _, pattern in found))

    def run_check(self, data, *extra):
        client = self.root / 'client.bin'
        client.write_bytes(data)
        out = io.StringIO()
        with redirect_stdout(out):
            code = client_check.main([str(client), '--addon', str(self.addon), '--libs', str(self.libs), *extra])
        return code, out.getvalue()

    def test_reads_every_addon_pattern(self):
        found = client_check.addon_patterns(ROOT / 'vantage')
        self.assertEqual([(where, name) for where, name, _ in found], [
            ('core/chat.lua', 'chat windows'), ('core/chat.lua', 'menu scale'),
            ('core/client.lua', 'event flag'), ('core/client.lua', 'interface'), ('core/client.lua', 'map focus'),
            ('core/native_party_ui.lua', 'party list 1'), ('core/native_party_ui.lua', 'party list 2'),
            ('core/native_party_ui.lua', 'treasure pool'), ('core/clock.lua', 'game time')]
            + [('core/name_anchor.lua', 'name point ' + name) for name in (
                'lift', 'name index', 'arrow index', 'root', 'skeleton', 'scale', 'node', 'handle', 'generator offset',
                'bones', 'generators', 'entity', 'model pick', 'gate mount', 'gate chocobo', 'gate chair')]
            + [('core/name_anchor.lua', 'camera check ' + name) for name in (
                'app view', 'app projection', 'wrapper transforms', 'wrapper', 'wrapper again', 'viewport', 'sizes')]
            + [('core/game_buffs.lua', 'game buffs ' + name) for name in (
                'icon paint', 'timer paint', 'icon draw', 'timer draw', 'menu move', 'rebuild', 'registry')]
            + [('core/game_buffs.lua', 'game buffs whole ' + name) for name in (
                'icon paint', 'timer paint', 'icon draw', 'timer draw', 'menu move', 'rebuild')])
        # Each routine's start is the first 32 bytes of the routine whole.
        by_name = dict(((where, name), pattern) for where, name, pattern in found)
        for name in ('icon paint', 'timer paint', 'icon draw', 'timer draw', 'menu move', 'rebuild'):
            start = by_name['core/game_buffs.lua', 'game buffs ' + name]
            self.assertEqual(len(start), 64)
            self.assertTrue(by_name['core/game_buffs.lua', 'game buffs whole ' + name].startswith(start), name)
        treasure = dict(((where, name), pattern) for where, name, pattern in found)['core/native_party_ui.lua', 'treasure pool']
        # Three menu names, 16 bytes each, with 28 bytes of window pointers between them.
        self.assertEqual(len(treasure), 2 * (16 * 3 + 28 * 2))
        self.assertEqual(treasure.count('??'), 56)
        self.assertTrue(client_check.loads_itemdata(ROOT / 'vantage'))

    @unittest.skipUnless(os.environ.get('ASHITA_LIBS'), 'needs ASHITA_LIBS')
    def test_reads_the_item_data_library(self):
        found = client_check.library_patterns(os.environ['ASHITA_LIBS'])
        names = [(where, name) for where, name, _ in found]
        self.assertEqual(names[:2], [('libs/ffxi/itemdata.lua', 'parse augments'),
                                     ('libs/ffxi/itemdata.lua', 'parse synthesis rate')])
        self.assertIn(('libs/ffxi/time.lua', 'game time'), names)
        self.assertEqual(len([where for where, _ in names if where == 'libs/ffxi/time.lua']), 13)

    def test_every_pattern_once_passes(self):
        code, out = self.run_check(image(self.patterns()))
        self.assertEqual(code, 0, out)
        self.assertIn('All 47 patterns found exactly once.', out)
        self.assertRegex(out, r'core/clock\.lua\s+game time\s+once at 0x1000')
        self.assertRegex(out, r'libs/ffxi/time\.lua\s+local time\s+once at 0x1000')

    def test_a_pattern_found_twice_fails(self):
        patterns = self.patterns()
        code, out = self.run_check(image(patterns, twice={patterns[0]}))
        self.assertEqual(code, 1, out)
        self.assertRegex(out, r'core/chat\.lua\s+chat windows\s+FOUND 2 TIMES')
        self.assertIn('1 of 47 patterns are not found exactly once.', out)

    def test_a_missing_pattern_fails(self):
        clock = [p for where, _, p in client_check.addon_patterns(self.addon) if where == 'core/clock.lua']
        code, out = self.run_check(image([p for p in self.patterns() if p != clock[0]]))
        self.assertEqual(code, 1, out)
        self.assertRegex(out, r'core/clock\.lua\s+game time\s+NOT FOUND')

    def test_library_patterns_only_while_the_addon_loads_item_data(self):
        (self.addon / 'core/recasts.lua').write_text('return {};\n', encoding='ascii')
        shutil.rmtree(self.libs)
        code, out = self.run_check(image(self.patterns_without_libs()))
        self.assertEqual(code, 0, out)
        self.assertIn('All 45 patterns found exactly once.', out)
        self.assertNotIn('libs/', out)

    def patterns_without_libs(self):
        return list(dict.fromkeys(pattern for _, _, pattern in client_check.addon_patterns(self.addon)))

    def test_a_pattern_file_it_cannot_read_stops_the_check(self):
        client, chat = image(self.patterns()), self.addon / 'core/chat.lua'
        chat.write_text(chat.read_text(encoding='utf-8').replace("local SCALE_PATTERN", "local SCALE"), encoding='utf-8')
        code, out = self.run_check(client)
        self.assertEqual(code, 2, out)
        self.assertIn('core/chat.lua has 1 client patterns, this check reads 2', out)

    def test_a_library_search_it_cannot_read_stops_the_check(self):
        client, time = image(self.patterns()), self.libs / 'ffxi/time.lua'
        time.write_text(time.read_text(encoding='ascii') + "x = ashita.memory.find(0, 0, pattern, 0, 0);\n", encoding='ascii')
        code, out = self.run_check(client)
        self.assertEqual(code, 2, out)
        self.assertIn('ffxi/time.lua has 2 client pattern searches, this check reads 1', out)

    def test_not_a_client_stops_the_check(self):
        code, out = self.run_check(b'not a client at all')
        self.assertEqual(code, 2, out)
        self.assertIn('Cannot check the client: not a PE file', out)

    def test_a_client_near_the_drive_root_falls_back_to_ashita_libs(self):
        # Fewer than three folders above the client: no Ashita install around it to take the libraries from.
        for client in (Path(self.root.anchor) / 'FFXiMain.dll', Path(self.root.anchor) / 'x/FFXiMain.dll'):
            with self.subTest(client=client), mock.patch.dict(os.environ, {'ASHITA_LIBS': str(self.libs)}):
                self.assertEqual(client_check.default_libs(client), self.libs)
                os.environ.pop('ASHITA_LIBS')
                out = io.StringIO()
                with redirect_stdout(out):
                    code = client_check.main([str(client), '--addon', str(self.addon)])
                self.assertEqual(code, 2, out.getvalue())
                self.assertIn('pass --libs', out.getvalue())

    @unittest.skipUnless(os.environ.get('ASHITA_LIBS') and (CLIENTS / 'client-image-04288488.bin').is_file(),
                         'needs ASHITA_LIBS and the decoded client images')
    def test_known_clients(self):
        for name in ('client-image-f2245d1c.bin', 'client-image-04288488.bin'):
            out = io.StringIO()
            with redirect_stdout(out):
                code = client_check.main([str(CLIENTS / name), '--libs', os.environ['ASHITA_LIBS']])
            self.assertEqual(code, 0, out.getvalue())
            self.assertIn('All 60 patterns found exactly once.', out.getvalue())


if __name__ == '__main__':
    unittest.main()
