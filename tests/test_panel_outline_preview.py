"""In real ImGui, a plain theme's panel outline shows on its window's edge.

preview/panel_outline.lua draws Self buffs (compact bars) and Spell recasts (Text only) over one flat color, and logs
each window's rect. A panel's edge pixel is the field color where nothing is drawn there: the window border size
clips a box's outermost pixel, which is how a panel without an outline has always looked. ImGui puts a window on
whole pixels, cutting its position and size toward zero, so the window's pixels are read the same way; at the Scale
slider's 1.5 the expanded panel is a fractional size.
"""
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from PIL import Image

HERE = Path(__file__).resolve().parent
PREVIEW = HERE / 'preview'
PANELS = ('##vantage_self_buffs', '##vantage_spell_recasts')


def render(cfg, windows=PANELS):
    with tempfile.TemporaryDirectory(prefix='vantage_outline_') as folder:
        out = Path(folder) / 'outline.png'
        result = subprocess.run([
            sys.executable, str(PREVIEW / 'preview.py'), '--hud', '--no-crop', '--frames', '4', '--size', '1000', '600',
            '--exec', 'PREVIEW.cfg=' + cfg, '--script', str(PREVIEW / 'panel_outline.lua'), '--out', str(out),
        ], capture_output=True, text=True, timeout=60)
        field, rects, given = None, {}, {}
        for line in result.stderr.splitlines():
            parts = line.split()
            if line.startswith('log: field '):
                field = tuple(int(value) for value in parts[2:5])
            elif line.startswith('log: rect '):
                given[parts[2]] = tuple(float(value) for value in parts[3:7])
                rects[parts[2]] = tuple(math.trunc(value) for value in given[parts[2]])
        if result.returncode != 0 or 'OK window=' not in result.stdout or field is None or set(rects) != set(windows):
            raise AssertionError('The preview drew every window: ' + result.stdout + result.stderr)
        render.given = given
        image = Image.open(out).convert('RGB')
        image.load()
    return image, field, rects


def along(rect, side, depth):
    """Three pixels `depth` px inside the window's edge on that side, a quarter, half and three quarters along it,
    clear of the rounded corners."""
    x, y, w, h = rect
    if side in ('left', 'right'):
        column = x + depth if side == 'left' else x + w - 1 - depth
        return [(column, y + h * part // 4) for part in (1, 2, 3)]
    row = y + depth if side == 'top' else y + h - 1 - depth
    return [(x + w * part // 4, row) for part in (1, 2, 3)]


def edges(image, rect):
    """The pixel at the middle of each edge, and one just inside the left edge."""
    x, y, w, h = rect
    mx, my = x + w // 2, y + h // 2
    return [image.getpixel(point) for point in ((x, my), (x + w - 1, my), (mx, y), (mx, y + h - 1))], image.getpixel((x + 1, my))


class PanelOutlinePreviewTests(unittest.TestCase):
    def assert_outline(self, image, field, rect, name):
        sides, inside = edges(image, rect)
        for side in sides:
            self.assertNotEqual(side, field, name + ': the outline shows on every edge')
            self.assertNotEqual(side, inside, name + ': the edge is the outline, not the backdrop')

    def assert_no_outline(self, image, field, rect, name):
        sides, inside = edges(image, rect)
        self.assertEqual(sides, [field] * 4, name + ': nothing is drawn on the window edge')
        self.assertNotEqual(inside, field, name + ': the backdrop is drawn inside it')

    def assert_whole_outline(self, image, field, rect, name):
        color = image.getpixel((rect[0] + rect[2] // 2, rect[1]))
        self.assertNotEqual(color, field, name + ': the top edge is the outline')
        for side in ('left', 'right', 'top', 'bottom'):
            for edge, inside in zip(along(rect, side, 0), along(rect, side, 1)):
                self.assertEqual(image.getpixel(edge), color, '%s: the %s outline is at full strength at %s' % (name, side, edge))
                self.assertNotEqual(image.getpixel(inside), color, '%s: the %s outline is one pixel wide at %s' % (name, side, inside))

    def test_shared_with_panel_borders_on_shows_the_outline(self):
        for look in ('Phoenix', 'Ember'):
            image, field, rects = render('{look="%s",border=true}' % look)
            for name in PANELS:
                self.assert_outline(image, field, rects[name], look + ' ' + name)

    def test_shared_with_panel_borders_off_draws_no_outline(self):
        image, field, rects = render('{border=false}')
        for name in PANELS:
            self.assert_no_outline(image, field, rects[name], name)

    def test_own_picks(self):
        image, field, rects = render('{border=false,box="border"}')
        for name in PANELS:
            self.assert_outline(image, field, rects[name], 'Border only ' + name)
        image, field, rects = render('{border=true,box="background"}')
        for name in PANELS:
            self.assert_no_outline(image, field, rects[name], 'Background only ' + name)

    def test_frameless_timer_panels_draw_no_box(self):
        image, field, rects = render('{border=true,minimal=true}')
        for name in PANELS:
            sides, inside = edges(image, rects[name])
            self.assertEqual(sides + [inside], [field] * 5, name + ': Frameless timer panels draw no box')

    def test_outline_whole_at_fractional_sizes(self):
        # At 1.5 the panels' heights are fractional.
        windows = PANELS + ('##vantage_self_debuffs',)
        for look in ('Phoenix', 'High contrast'):
            image, field, rects = render('{look="%s",border=true,scale=1.5,expanded=true}' % look, windows)
            fractions = [name for name, value in render.given.items() if any(part != math.trunc(part) for part in value)]
            self.assertTrue('##vantage_self_debuffs' in fractions, 'Fixture: fractional sizes: ' + repr(render.given))
            for name in windows:
                self.assert_whole_outline(image, field, rects[name], look + ' ' + name)
        image, field, rects = render('{border=true,scale=1.5,expanded=true,minimal=true}', windows)
        for name in windows:
            sides, inside = edges(image, rects[name])
            self.assertEqual(sides + [inside], [field] * 5, name + ': Frameless timer panels draw no box at 1.5 either')


if __name__ == '__main__':
    if not os.environ.get('ASHITA_LIBS'):
        raise SystemExit('Set ASHITA_LIBS to the Ashita addons/libs folder.')
    unittest.main()
