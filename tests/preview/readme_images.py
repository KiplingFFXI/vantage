"""
Remakes the example pictures the README shows, in docs/images/:

    python tests/preview/readme_images.py [--only NAME]

preview.py draws each one with the addon's own Lua: a scene from readme/, or for the settings pages and edit mode the
whole addon, set up by readme/pages.lua. --only remakes just the picture named, as in --only skins. ASHITA_LIBS must
name the addons/libs folder of an Ashita install, as for preview.py. The pictures hold client art read from that
install's game files, so they stay in docs/ and are never packed in the addon zip.
"""
from pathlib import Path
import argparse
import json
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageChops

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
IMAGES = ROOT / 'docs' / 'images'
SCENES = HERE / 'readme'
# The space left around what a picture shows, and how far a pixel must be from the screen's color to count as drawn.
MARGIN = 16
INK = 30

# How each picture is drawn. A scene is cut to what it drew. A page runs the whole addon and is cut to its settings
# window, drawn at that window size, unless hud leaves the window shut; then crop is the part of the screen kept.
# size is the game screen (1280 by 1000 unless given), frames how many are drawn (10 unless given), and input the
# mouse and keys preview.py plays.
PICTURES = {
    'vantage-example': {'scene': 'example.lua', 'size': (1000, 450)},
    'timer-layouts': {'scene': 'timer_layouts.lua', 'size': (980, 420)},
    'target-dispel': {'scene': 'target_dispel.lua', 'size': (620, 300)},
    'cleanse-light': {'scene': 'cleanse_light.lua', 'size': (660, 360)},
    'party-members': {'scene': 'party_members.lua', 'size': (360, 360)},
    'party-list-buffs': {'scene': 'party_list_buffs.lua', 'size': (560, 270)},
    'overhead-icons': {'scene': 'overhead_icons.lua', 'size': (1920, 1080)},
    'recasts': {'scene': 'recasts.lua', 'size': (840, 400)},
    'party-cooldowns': {'scene': 'party_cooldowns.lua', 'size': (380, 240)},
    'phantom-roll': {'scene': 'phantom_roll.lua', 'size': (400, 300)},
    'pet': {'scene': 'pet.lua', 'size': (640, 330)},
    'skins': {'scene': 'skins.lua', 'size': (760, 600)},
    'countdown-styles': {'scene': 'countdown_styles.lua', 'size': (820, 140)},
    'main-page': {'page': 'main', 'window': (960, 680)},
    'display-editor': {'page': 'editor', 'window': (960, 510)},
    'hidden-everywhere': {'page': 'hidden', 'window': (960, 700)},
    'alerts': {'page': 'alerts', 'size': (1280, 1050), 'window': (960, 910)},
    # A Shift drag of Target timers, which shows the grid.
    'edit-mode': {'page': 'edit', 'hud': True, 'size': (1080, 600), 'frames': 12, 'crop': (0, 0, 1080, 540), 'input': [
        {'frame': 4, 'mouse': [420, 318], 'shift': True, 'down': True},
        {'frame': 5, 'delta': [6, 4]},
        {'frame': 6, 'delta': [10, 6]}]},
    # The starter profile list open, pointing at Crowd control near its left end so its tooltip stays in the window.
    'starter-profiles': {'page': 'starters', 'window': (960, 680), 'frames': 40, 'input': [
        {'frame': 3, 'target': '##main_starter', 'down': True},
        {'frame': 4, 'down': False},
        {'frame': 6, 'target': 'Crowd control##crowd control', 'point': [0.08, 0.5]},
        {'frame': 7, 'delta': [1, 0]}]},
}


def command(spec, out, folder):
    size = spec.get('size', (1280, 1000))
    args = [sys.executable, str(HERE / 'preview.py'), '--client-assets', '--out', str(out),
            '--size', str(size[0]), str(size[1]), '--frames', str(spec.get('frames', 10))]
    if 'scene' in spec:
        args += ['--script', str(SCENES / spec['scene']), '--no-crop']
    else:
        args += ['--full', '--exec', "require('preview.readme.pages').%s(settings)" % spec['page']]
        if spec.get('hud'):
            args += ['--hud', '--no-crop']
        else:
            args += ['--window-size', str(spec['window'][0]), str(spec['window'][1]), '--margin', str(MARGIN)]
    if 'input' in spec:
        actions = folder / 'input.json'
        actions.write_text(json.dumps(spec['input']), encoding='ascii')
        args += ['--input-script', str(actions)]
    return args


def trim(picture):
    """Cuts a scene to what was drawn on it, with MARGIN around it."""
    background = Image.new('RGB', picture.size, picture.getpixel((0, 0)))
    red, green, blue = ImageChops.difference(picture, background).split()
    drawn = ImageChops.lighter(ImageChops.lighter(red, green), blue).point(lambda value: 255 if value > INK else 0)
    box = drawn.getbbox()
    if box is None:
        raise RuntimeError('nothing was drawn')
    left, top, right, bottom = box
    return picture.crop((max(0, left - MARGIN), max(0, top - MARGIN),
                         min(picture.width, right + MARGIN), min(picture.height, bottom + MARGIN)))


def make(name, spec):
    with tempfile.TemporaryDirectory() as folder:
        folder = Path(folder)
        out = folder / 'picture.png'
        result = subprocess.run(command(spec, out, folder), cwd=ROOT, capture_output=True, text=True, errors='replace')
        if result.returncode != 0 or not out.is_file():
            raise RuntimeError('preview.py failed for %s:\n%s%s' % (name, result.stdout, result.stderr))
        for line in result.stderr.splitlines():
            if line.startswith('warning:'):
                print('%s: %s' % (name, line))
        with Image.open(out) as image:
            picture = image.convert('RGB')
    if 'scene' in spec:
        picture = trim(picture)
    elif 'crop' in spec:
        picture = picture.crop(spec['crop'])
    target = IMAGES / (name + '.png')
    picture.save(target, optimize=True)
    print('%s.png %dx%d %d KB' % (name, picture.width, picture.height, (target.stat().st_size + 1023) // 1024))


def main():
    parser = argparse.ArgumentParser(description='Remake the README pictures in docs/images/.')
    parser.add_argument('--only', metavar='NAME', help='remake just this picture: ' + ', '.join(PICTURES))
    args = parser.parse_args()
    if not os.environ.get('ASHITA_LIBS'):
        raise SystemExit('Set ASHITA_LIBS to the Ashita addons/libs folder (addons/libs in an Ashita install).')
    names = list(PICTURES)
    if args.only:
        name = args.only[:-4] if args.only.endswith('.png') else args.only
        if name not in PICTURES:
            raise SystemExit('No picture named %s. The pictures are: %s' % (args.only, ', '.join(PICTURES)))
        names = [name]
    IMAGES.mkdir(parents=True, exist_ok=True)
    for name in names:
        try:
            make(name, PICTURES[name])
        except RuntimeError as error:
            raise SystemExit(str(error))


if __name__ == '__main__':
    main()
