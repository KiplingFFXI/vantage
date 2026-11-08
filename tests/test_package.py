"""tools/package.py builds the addon archive, whose addons/vantage folder players copy into their game's addons
folder, and refuses private markers."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import package
import release_files

DOCUMENTS = {'LICENSE': 'License fixture\n', 'README.md': 'Read [the guide](docs/GUIDE.md).\n',
             'CHANGELOG.md': '# Changelog\n\n## 1.0.0\n', 'docs/GUIDE.md': 'Player guide\n',
             'docs/INSTALL.md': 'See [the guide](GUIDE.md).\n'}
# Made-up lines for tools/private_markers.txt, which stays on the author's machine.
OWN = ('Fennel_1234', 'someone@example.com')


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='vantage_package_')
        self.root = Path(self.work.name)
        self.addon = self.root / 'vantage'
        for name in package.REQUIRED:
            path = self.addon / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("addon.version = '1.0.0';\n" if name == 'vantage.lua' else 'return {};\n', encoding='ascii')
        for name, text in DOCUMENTS.items():
            (self.root / name).parent.mkdir(parents=True, exist_ok=True)
            (self.root / name).write_text(text, encoding='ascii')
        for name in ('tests/test_x.py', 'tools/x.py', 'docs/RELEASING.md'):
            (self.root / name).parent.mkdir(parents=True, exist_ok=True)
            (self.root / name).write_text('x\n', encoding='ascii')

    def tearDown(self):
        self.work.cleanup()

    def build(self, out='dist'):
        return package.build(self.root / out, self.root)

    def test_layout_and_reproducible(self):
        path, count, digest = self.build()
        self.assertEqual(path, self.root / 'dist/vantage-1.0.0-addon.zip')
        again, _, second = self.build('other')
        self.assertEqual(path.read_bytes(), again.read_bytes())
        self.assertEqual(digest, second)
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            self.assertIsNone(archive.testzip())
        self.assertEqual(count, len(package.REQUIRED) + 5)
        self.assertEqual(sorted(names), sorted(['addons/vantage/' + name for name in package.REQUIRED] + list(DOCUMENTS)))
        self.assertIn('addons/vantage/vantage.lua', names)
        self.assertFalse(any(name.startswith(('tests/', 'tools/', 'vantage/')) or name == 'docs/RELEASING.md'
                             for name in names))

    def test_caches_fonts_and_game_data_are_left_out(self):
        for name in ('__pycache__/x.pyc', 'core/cache.pyc', 'fonts/menu-v1-0000.ttf', 'ui/glyphs.ttf', 'data/ROM.DAT',
                     'config/addons/vantage/settings.json', 'tests/test_x.lua'):
            (self.addon / name).parent.mkdir(parents=True, exist_ok=True)
            (self.addon / name).write_bytes(b'x')
        path, count, _ = self.build()
        self.assertEqual(count, len(package.REQUIRED) + 5)
        with zipfile.ZipFile(path) as archive:
            self.assertFalse(any(name.endswith(('.pyc', '.ttf', '.DAT', '.json')) for name in archive.namelist()))

    def test_unexpected_runtime_file_refused(self):
        (self.addon / 'core/extra.lua').write_text('return {};\n', encoding='ascii')
        with self.assertRaisesRegex(RuntimeError, 'Unexpected or linked runtime file: core/extra.lua'):
            self.build()

    def test_missing_runtime_file_refused(self):
        (self.addon / 'core/store.lua').unlink()
        with self.assertRaisesRegex(RuntimeError, 'Missing runtime files: core/store.lua'):
            self.build()

    def test_loaded_module_left_out_refused(self):
        (self.addon / 'vantage.lua').write_text("addon.version = '1.0.0';\nlocal extra = require('core.extra');\n",
                                                encoding='ascii')
        (self.addon / 'core/extra.lua').write_text('return {};\n', encoding='ascii')
        with self.assertRaisesRegex(RuntimeError, 'leaves out: core/extra.lua'):
            release_files.addon_files(self.addon)

    def test_every_loaded_module_is_in_the_archive(self):
        loaded = package.required_modules(package.ADDON)
        self.assertIn('core/json.lua', loaded)
        self.assertIn('core/clock.lua', loaded)
        self.assertEqual(sorted(loaded - package.REQUIRED), [])

    def test_missing_document_refused(self):
        (self.root / 'docs/INSTALL.md').unlink()
        with self.assertRaisesRegex(RuntimeError, 'Missing or linked document: docs/INSTALL.md'):
            self.build()

    def test_broken_link_refused(self):
        (self.root / 'README.md').write_text('[Developer tests](tests/README.txt)\n', encoding='ascii')
        with self.assertRaisesRegex(RuntimeError, 'Broken archive document link'):
            self.build()

    def test_every_private_marker_refused_plain_and_utf16_in_any_case(self):
        with mock.patch.object(package, 'MARKERS', OWN + package.PATH_MARKERS):
            for marker in package.MARKERS:
                for data in (marker.encode('ascii'), marker.upper().encode('ascii'), marker.lower().encode('ascii'),
                             marker.encode('utf-16-le'), marker.upper().encode('utf-16-le')):
                    for name in ('docs/GUIDE.md', 'vantage/core/store.lua'):
                        with self.subTest(marker=marker, data=data, name=name):
                            (self.root / name).write_bytes(b'before ' + data + b' after\n')
                            with self.assertRaisesRegex(RuntimeError, 'Private marker'):
                                self.build()
                            (self.root / name).write_bytes(b'return {};\n')
        self.assertFalse((self.root / 'dist/vantage-1.0.0-addon.zip').exists())

    def test_the_paths_are_markers_on_any_machine(self):
        lowered = {marker.lower() for marker in package.MARKERS}
        for generic in ('appdata', 'c:/users', 'c:\\users'):
            self.assertIn(generic, lowered)

    def test_own_markers_are_read_from_a_file_git_ignores(self):
        path = self.root / 'private_markers.txt'
        self.assertEqual(package.own_markers(path), ())
        path.write_text('Fennel_1234\n\n  someone@example.com  \n', encoding='ascii')
        self.assertEqual(package.own_markers(path), OWN)
        self.assertEqual(package.OWN_MARKERS, ROOT / 'tools/private_markers.txt')
        self.assertIn('tools/private_markers.txt', (ROOT / '.gitignore').read_text(encoding='ascii').splitlines())

    def test_output_inside_the_addon_refused(self):
        with self.assertRaisesRegex(RuntimeError, 'outside'):
            package.build(self.addon / 'out', self.root)

    def test_this_project_builds_clean(self):
        with tempfile.TemporaryDirectory(prefix='vantage_package_real_') as out:
            path, count, _ = package.build(out)
            with zipfile.ZipFile(path) as archive:
                names = archive.namelist()
                for name in names:
                    self.assertIsNone(package.private_marker(archive.read(name)), name)
        self.assertEqual(path.name, 'vantage-1.0.0-addon.zip')
        self.assertEqual(count, len(package.REQUIRED) + 5)
        self.assertIn('docs/INSTALL.md', names)


if __name__ == '__main__':
    unittest.main()
