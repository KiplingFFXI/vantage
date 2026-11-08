"""Read-only checks against optional locally installed action artwork; no bundled assets."""
from pathlib import Path
import hashlib
import io
import os
import unittest

from lupa.luajit21 import LuaRuntime
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(os.environ['ASHITA_LIBS']).parent.parent / 'SquareEnix' / 'FINAL FANTASY XI'
VIEW = GAME.parents[1] / 'polplugins/DATs/XiView-Standard'


@unittest.skipUnless((GAME / 'ROM/280/15.DAT').is_file(), 'Local action artwork is unavailable')
class ClientActionArtworkTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
        self.lua.globals().VANTAGE_TEST_MODE = True
        self.lua.globals().addon_path = (str(ROOT / 'vantage').replace('\\', '/') + '/?.lua').encode()
        self.lua.execute(b'package.path=addon_path..";"..package.path')
        self.assets = self.lua.eval(b'require("ui.client_assets")')
        self.icons = self.lua.eval(b'require("ui.action_icons")')

    def parse(self, path, name):
        result = self.assets[b'parse'](path.read_bytes(), True, self.lua.table_from([name]))
        if isinstance(result, tuple):
            result, error = result
            self.assertIsNotNone(result, error)
        layout = result[b'layouts'][name]
        shapes = self.icons[b'parse'](layout)
        if isinstance(shapes, tuple):
            shapes, error = shapes
            self.assertIsNotNone(shapes, error)
        return result, shapes

    def test_all_installed_shape_bounds_and_dependencies(self):
        common, _ = self.parse(GAME / 'ROM/119/51.DAT', b'font    fontshp ')
        for path, layout, count in [
            (GAME / 'ROM/280/15.DAT', b'menu    magiconw', 677),
            (GAME / 'ROM/324/95.DAT', b'menu    magico2w', 89),
        ]:
            parsed, shapes = self.parse(path, layout)
            self.assertEqual(shapes[b'count'], count)
            for index in range(count):
                shape = shapes[b'shapes'][index]
                if shape[b'reason']:
                    self.assertEqual(len(shape[b'parts']), 0)
                    continue
                self.assertEqual(bool(shape[b'approximate_blend']), layout == b'menu    magiconw' and index == 31)
                for _, part in shape[b'parts'].items():
                    texture = parsed[b'textures'][part[b'name']] or common[b'textures'][part[b'name']]
                    self.assertIsNotNone(texture, (path, index, part[b'name']))
                    # Native drawing explicitly uses WRAP. Shape470 samples33 pixels
                    # from its32-pixel texture; runtime splits that wrapped sliver.
                    if part[b'u'] + part[b'source_width'] > texture[b'width']:
                        self.assertEqual((layout, index, part[b'name'], part[b'u'], part[b'source_width'], texture[b'width']),
                                         (b'menu    magiconw', 470, b'jobabi  jobab_97', 0, 33, 32))
                    self.assertLessEqual(part[b'u'] + part[b'source_width'], texture[b'width'] * 2)
                    self.assertLessEqual(part[b'v'] + part[b'source_height'], texture[b'height'])

    @unittest.skipUnless((VIEW / 'ROM/280/15.DAT').is_file(), 'Configured XI View artwork is unavailable')
    def test_xiview_uses_its_own_native_shapes_and_textures(self):
        stock, stock_shapes = self.parse(GAME / 'ROM/280/15.DAT', b'menu    magiconw')
        view, view_shapes = self.parse(VIEW / 'ROM/280/15.DAT', b'menu    magiconw')
        self.assertEqual(view_shapes[b'count'], stock_shapes[b'count'])
        different = [name for name, texture in view[b'textures'].items()
                     if hashlib.sha256(texture[b'dds']).digest() != hashlib.sha256(stock[b'textures'][name][b'dds']).digest()]
        self.assertIn(b'white   haste   ', different)
        self.assertFalse((VIEW / 'ROM/324/95.DAT').exists(), 'This installed XI View pack relies on stock secondary icons')

    def test_prepared_action_alpha_matches_native_modulate2x(self):
        for path, layout in [(GAME / 'ROM/280/15.DAT', b'menu    magiconw'),
                             (GAME / 'ROM/324/95.DAT', b'menu    magico2w')]:
            parsed, _ = self.parse(path, layout)
            for name, texture in parsed[b'textures'].items():
                original = Image.open(io.BytesIO(texture[b'dds'])).convert('RGBA')
                dds = self.assets[b'_action_dds_for_tests'](texture, 192)
                converted = Image.open(io.BytesIO(dds)).convert('RGBA')
                self.assertEqual(converted.size, original.size)
                for before, after in zip(original.getdata(), converted.getdata()):
                    self.assertEqual(after[:3], before[:3], name)
                    self.assertEqual(after[3], min(255, int(before[3] * 192 * 2 / 255 + .5)), name)


if __name__ == '__main__':
    unittest.main()
