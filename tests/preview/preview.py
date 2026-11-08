"""
Renders vantage's real settings window with real Dear ImGui (imgui_bundle 1.92.3) offscreen and saves
a PNG cropped to that window.

    python preview.py --addon <addon folder> --out <png> [--tab Panels] [--size W H] [--frames N]
                      [--set key.path=value ...] [--window-size W H] [--window NAME] [--margin PX]
                      [--full] [--exec LUA] [--font PATH]

The addon's Lua files are loaded unmodified into LuaJIT (lupa) with the tests' mock of Ashita
(../mock_ashita.lua), except that require('imgui') is Ashita's own libs/imgui.lua over a
bridge to imgui_bundle (imgui_bridge.lua / imgui_bridge.py). See README.txt.
"""
import argparse
import hashlib
import io
import os
import re
import shutil
import struct
import sys
import tempfile
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
HARNESS = os.path.dirname(HERE)
# The strict json.lua Vantage ships as core.json, as tests/run.py loads it; the game folder's copy is lenient.
JSON = os.path.join(os.path.dirname(HARNESS), 'vantage', 'core', 'json.lua').replace('\\', '/')
ADDON = os.path.join(os.path.dirname(HARNESS), 'vantage')
# Checked when a preview starts, so --help works without it.
ASHITA_LIBS = os.environ.get('ASHITA_LIBS', '').replace('\\', '/')
ASHITA_DLL = os.path.join(ASHITA_LIBS, '..', '..', 'Ashita.dll')
AGAVE = os.path.join(HERE, 'fonts', 'Agave_Regular.ttf')
FONT_AWESOME = [os.path.join(HERE, 'fonts', n) for n in
                ('Font_Awesome_7_Free_Solid.ttf', 'Font_Awesome_7_Free_Regular.ttf', 'Font_Awesome_7_Brands_Regular.ttf')]
BACKGROUND = (0.075, 0.085, 0.10, 1.0)   # dark blue-grey, like a night-time field behind the window
FREETYPE_NO_HINTING = 1   # ImGuiFreeTypeLoaderFlags_NoHinting (imgui_freetype.h); imgui_bundle doesn't name it

sys.path.insert(0, HERE)

import numpy as np                                   # noqa: E402
from PIL import Image                                # noqa: E402
from lupa import luajit21                            # noqa: E402
from imgui_bundle import imgui, hello_imgui, immapp  # noqa: E402

import imgui_bridge                                  # noqa: E402
import imgui_enums                                   # noqa: E402


def decode_item_picture(record, item_id):
    """Read the client item record's 32px DIB; no copyrighted pixels live in this fixture."""
    if len(record) not in (0xC00, 0x1400):
        raise ValueError('Unsupported item record length')
    decoded = record.translate(bytes(((value >> 5) | (value << 3)) & 255 for value in range(256)))
    if struct.unpack_from('<I', decoded)[0] != item_id:
        raise ValueError('Item record identity does not match the requested picture')
    image_size = struct.unpack_from('<I', decoded, 0x280)[0]
    if not 21 <= image_size <= 0x980 or 0x284 + image_size > len(decoded):
        raise ValueError('Item image size exceeds its record')
    start = 0x295
    header, width, height, planes, bits, compression = struct.unpack_from('<IiiHHI', decoded, start)
    if (header, width, height, planes, bits, compression) != (40, 32, 32, 1, 8, 0):
        raise ValueError('Unsupported item DIB layout')
    end = start + 40 + 1024 + 1024
    if end > 0x284 + image_size:
        raise ValueError('Item bitmap does not contain its palette and pixels')
    palette = np.frombuffer(decoded[start + 40:start + 40 + 1024], dtype=np.uint8).reshape(256, 4)
    indices = np.frombuffer(decoded[start + 40 + 1024:end], dtype=np.uint8).reshape(32, 32)[::-1]
    pixels = palette[indices][:, :, [2, 1, 0, 3]].copy()
    # D3DX loads this 8-bit DIB as opaque RGB and uses black as the color key.
    pixels[:, :, 3] = np.where(np.any(pixels[:, :, :3], axis=2), 255, 0)
    return Image.fromarray(pixels)


def read_item_picture(game_root, item_id):
    """Seek the two armor tables holding enchanted equipment."""
    from pathlib import Path
    root = Path(game_root)
    if isinstance(item_id, bool) or not isinstance(item_id, int) or not 1 <= item_id <= 65534:
        raise ValueError('Invalid item identity')
    for file_id in (0x004C, 0xD974):
        with (root / 'FTABLE.DAT').open('rb') as table:
            table.seek(file_id * 2)
            entry = table.read(2)
        if len(entry) != 2:
            raise ValueError('Incomplete client file table')
        file_number = int.from_bytes(entry, 'little')
        path = root / 'ROM' / str(file_number >> 7) / ('%d.DAT' % (file_number & 127))
        file_size = path.stat().st_size
        if file_size <= 0 or file_size > 128 * 1024 * 1024:
            raise ValueError('Invalid armor table size')
        with path.open('rb') as stream:
            first = stream.read(4)
            first_id = int.from_bytes(bytes(((value >> 5) | (value << 3)) & 255 for value in first), 'little')
            for record_size in (0x1400, 0xC00):
                index = item_id - first_id
                if file_size % record_size or not 0 <= index < file_size // record_size:
                    continue
                stream.seek(index * record_size)
                record = stream.read(record_size)
                identity = int.from_bytes(bytes(((value >> 5) | (value << 3)) & 255 for value in record[:4]), 'little')
                if identity == item_id:
                    return decode_item_picture(record, item_id), str(path)
    raise ValueError('The item was not found in the client armor tables')


def parse_args(argv):
    p = argparse.ArgumentParser(description='Render vantage\'s settings window with real Dear ImGui.')
    p.add_argument('--addon', default=ADDON, help='addon folder (holds vantage.lua, ui/, core/), default ../../vantage')
    p.add_argument('--out', required=True, help='PNG to write')
    p.add_argument('--tab', help='tab to show, matched against the visible tab label (case-insensitive)')
    p.add_argument('--size', nargs=2, type=int, default=(1600, 1200), metavar=('W', 'H'),
                   help='game screen (ImGui display) size, default 1600 1200')
    p.add_argument('--frames', type=int, default=4, help='frames to draw before the screenshot (default 4)')
    p.add_argument('--set', action='append', default=[], metavar='key.path=value',
                   help='change a settings value before drawing: numbers, true/false, nil, #rrggbb[aa], '
                        'comma lists (1,0.5,0,1) or text. Repeatable.')
    p.add_argument('--window-size', nargs=2, type=float, metavar=('W', 'H'),
                   help='force the settings window to this size every frame (like a user resize)')
    p.add_argument('--window', help='substring of the window name to crop to (default: the largest window '
                                    'whose name does not start with ##)')
    p.add_argument('--margin', type=int, default=10, help='pixels kept around the window in the crop')
    p.add_argument('--hud', action='store_true', help='show the bar without the settings window')
    p.add_argument('--icon-fixture', action='store_true', help='use a grey test texture to check status icon layout; not game artwork')
    p.add_argument('--client-assets', action='store_true',
                   help='read local client DATs with the real Lua parser and upload decoded DDS textures to the preview renderer')
    p.add_argument('--client-game-root', help='FFXI install used by --client-assets (default: SquareEnix/FINAL FANTASY XI below Ashita)')
    p.add_argument('--client-xiview-root', help='optional XIView overlay root for --client-assets; otherwise find it from the overlay config')
    p.add_argument('--chat-fixture', action='store_true', help='draw the simulated chat rectangles behind the bar; not a game screenshot')
    p.add_argument('--input-script', help='JSON mouse input and Lua assertions to replay')
    p.add_argument('--full', action='store_true',
                   help='run the whole addon: dofile vantage.lua, fire load, "/vantage", then d3d_present '
                        'each frame (HUD timers included) instead of calling settings_window.draw directly')
    p.add_argument('--exec', action='append', default=[], metavar='LUA',
                   help='Lua run after settings load and --set, before the first frame (settings = the table)')
    p.add_argument('--script', metavar='LUA_FILE',
                   help='draw this Lua file instead of the settings window. The file returns a function that '
                        'is called once per frame; PREVIEW.log(text) and PREVIEW.frame / PREVIEW.last_frame '
                        'are available, and the last frame\'s log lines are printed on stderr as "log: ..."')
    p.add_argument('--font', default=None, help='TTF for the default ImGui font (default: Ashita\'s Agave)')
    p.add_argument('--font-size', type=float, default=18.0, help='default ImGui font size, Ashita uses 18')
    p.add_argument('--no-crop', action='store_true', help='save the whole screen instead of cropping to the window')
    args = p.parse_args(argv)
    return args


def parse_value(text):
    t = text.strip()
    if t in ('true', 'false'):
        return t == 'true'
    if t == 'nil':
        return None
    if re.fullmatch(r'#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?', t):
        vals = [int(t[i:i + 2], 16) / 255 for i in range(1, len(t), 2)]
        return vals + ([1.0] if len(vals) == 3 else [])
    try:
        return int(t)
    except ValueError:
        pass
    try:
        return float(t)
    except ValueError:
        pass
    if ',' in t:
        parts = [parse_value(x) for x in t.split(',')]
        if all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in parts):
            return parts
    if len(t) >= 2 and t[0] == t[-1] and t[0] in '\'"':
        return t[1:-1]
    return t


LUA_SETUP = r'''
local addon_dir, mode = ...
local function read_version()
    local f = io.open(addon_dir .. '/vantage.lua', 'r')
    if (f == nil) then return nil end
    local text = f:read('*a'); f:close()
    return text:match("addon%.version%s*=%s*'([^']+)'") or text:match('addon%.version%s*=%s*"([^"]+)"')
end
PREVIEW = { version = read_version() or '0.0.0' }
addon.name = 'vantage'
addon.version = PREVIEW.version
addon.path = addon_dir
-- Real file checks, so hud.load_fonts() finds Windows' fonts like it does in game.
local mock_exists = ashita.fs.exists
ashita.fs.exists = function (path) return mock_exists(path) or PREVIEW_PY.file_exists(path) end
'''

LUA_DIRECT = r'''
PREVIEW.settings = T(require('ui.defaults').make())
MOCK.settings.current = PREVIEW.settings
PREVIEW.hud = require('ui.hud')
if not PREVIEW.hud_only then PREVIEW.window = require('ui.settings_window') end
local fonts = require('ui.fonts')
fonts.load()
for _, step in ipairs(fonts.warmup_steps()) do step.run() end
PREVIEW.view = PREVIEW.hud.sample(100)
PREVIEW.settings.window.open = not PREVIEW.hud_only
PREVIEW.settings.preview = true
PREVIEW.services = {
    changed = function(phase) PREVIEW.changes=(PREVIEW.changes or 0)+1 end,
    save = function() PREVIEW.saves=(PREVIEW.saves or 0)+1; return true end,
    undo = function() return true end, reset = function() return true end,
    profile_list = function() return { 'Healer', 'Tank', 'Minimal' } end,
    profile_save = function() return true end, profile_load = function() return true end,
    profile_delete = function() return true end, profile_link = function() return true end,
    test_alert = function(rule) PREVIEW.tested_rule=rule return true end,
    sound_files = function() return { 'Warning.wav', 'Chime.mp3' } end,
    refresh_sounds = function() return { 'Warning.wav', 'Chime.mp3' } end,
    watch = function(id) table.insert(PREVIEW.settings.watch_ids,id) end,
    unwatch = function(id)
        for i=#PREVIEW.settings.watch_ids,1,-1 do
            if PREVIEW.settings.watch_ids[i]==id then table.remove(PREVIEW.settings.watch_ids,i) end
        end
    end,
}
function PREVIEW.draw()
    if PREVIEW.hud_only then
        PREVIEW.hud.draw(PREVIEW.view, PREVIEW.settings, 100, PREVIEW.services)
    else
        PREVIEW.window.draw(PREVIEW.settings, PREVIEW.view, PREVIEW.services)
    end
end
'''

LUA_FULL = r'''
PREVIEW.addon = dofile(PREVIEW.addon_dir .. '/vantage.lua')
MOCK.fire('load')
PREVIEW.addon.refresh(0)
PREVIEW.settings = PREVIEW.addon.state.settings
PREVIEW.hud = require('ui.hud')
PREVIEW.window = require('ui.settings_window')
MOCK.fire('command', { command = '/vantage preview' })
if not PREVIEW.hud_only then MOCK.fire('command', { command = '/vantage' }) end
function PREVIEW.draw()
    MOCK.frame(1 / 60)
    PREVIEW.settings = PREVIEW.addon.state.settings
end
'''

LUA_SCRIPT = r'''
local path, last_frame = ...
PREVIEW.last_frame = last_frame
PREVIEW.frame = 0
PREVIEW.log = function (...)
    local parts = {}
    for i = 1, select('#', ...) do parts[i] = tostring((select(i, ...))) end
    PREVIEW_PY.log(table.concat(parts, ' '))
end
local draw = dofile(path)
if (type(draw) ~= 'function') then
    error(('--script %s must return a function (called once per frame), got %s'):format(path, type(draw)))
end
function PREVIEW.draw()
    PREVIEW.frame = PREVIEW.frame + 1
    draw()
end
'''

LUA_SET = r'''
local root, path, value = ...
local node = root
local keys = {}
for key in path:gmatch('[^%.]+') do keys[#keys + 1] = key end
if (keys[1] == 'settings') then table.remove(keys, 1) end
local created = {}
for i = 1, #keys - 1 do
    local k = tonumber(keys[i]) or keys[i]
    if (type(node[k]) ~= 'table') then
        if (node[k] ~= nil) then error(('--set %s: %s is not a table'):format(path, keys[i])) end
        node[k] = {}
        created[#created + 1] = keys[i]
    end
    node = node[k]
end
local last = tonumber(keys[#keys]) or keys[#keys]
local old = node[last]
if (type(value) == 'userdata' or type(value) == 'table') then
    local t = {}
    for i = 1, #value do t[i] = value[i] end
    value = t
end
node[last] = value
return type(old), table.concat(created, '.')
'''


def require_libs():
    if not ASHITA_LIBS:
        raise SystemExit('Set ASHITA_LIBS to the Ashita addons/libs folder (addons/libs in an Ashita install).')


class Preview:
    def __init__(self, args):
        require_libs()
        self.args = args
        self.errors = []
        self.warnings = []
        self.frame = 0
        self.last_windows = {}
        self.stack_before = None
        self.work = None                # this run's own folder for what the addon writes, see run()
        self.lua = None
        self.font_name = None
        self.style_done = False
        self.logs = []                  # PREVIEW.log lines of the frame being drawn (--script)
        self.drawn_text = []
        self.drawn_images = []
        self.drawn_runs = []
        self.drawn_rects = []
        self.icon_texture = None
        self.client_textures = {}
        self.client_reads = []
        self.sets = []
        self.inputs = []
        self.mouse_position = (-100, -100)
        if args.input_script:
            import json
            self.inputs = json.loads(open(args.input_script, encoding='utf-8').read())
        for item in args.set:
            key, sep, raw = item.partition('=')
            if not sep or not key.strip():
                raise SystemExit('--set expects key.path=value, got %r' % item)
            self.sets.append((key.strip(), parse_value(raw)))

    # -- Lua side ---------------------------------------------------------------------------------
    def warn(self, text):
        if text not in self.warnings:
            self.warnings.append(text)

    def make_lua(self):
        a = self.args
        addon = os.path.abspath(a.addon).replace('\\', '/')
        L = luajit21.LuaRuntime(unpack_returned_tuples=True)
        # Lua's garbage collector runs only between frames (see gui()). In the middle of one, it makes lupa
        # now and then give Lua the wrong imgui_bundle object, like an ImFont for GetIO(), or crash the run.
        # Keeping Python references to the objects handed to Lua doesn't stop that.
        L.execute("collectgarbage('stop')")
        self.collect_garbage = L.eval("function () collectgarbage('collect') collectgarbage('stop') end")
        L.execute("package.path = [[%s/?.lua;%s/?.lua;]] .. package.path" % (addon, HARNESS.replace('\\', '/')))
        L.execute("package.path = package.path .. [[;%s/?.lua]]" % ASHITA_LIBS)
        L.execute('local path = ...; package.preload.json = function() return dofile(path) end', JSON)
        install = self.work
        os.makedirs(os.path.join(install, 'config', 'addons', 'vantage'), exist_ok=True)
        L.globals().MOCK_INSTALL_PATH = install
        L.globals().ADDON_DIR = addon
        L.globals().ASHITA_LIBS = ASHITA_LIBS
        L.globals().VANTAGE_TEST_MODE = True
        def mkdir(path):
            from pathlib import Path
            target = Path(path).resolve()
            if not target.is_relative_to(Path(install).resolve()):
                raise RuntimeError('Preview writes must stay inside its temporary folder.')
            target.mkdir(parents=True, exist_ok=True)
            return True
        L.globals().MOCK_MKDIR = mkdir
        L.execute(open(os.path.join(HARNESS, 'mock_ashita.lua'), encoding='utf-8').read())

        self.bridge = imgui_bridge.Bridge(select_tab=a.tab, window_filter=a.window,
                                          forced_size=tuple(a.window_size) if a.window_size else None)
        enums = imgui_enums.bundle_enums()
        imgui_lua = os.path.join(ASHITA_LIBS, 'imgui.lua')
        if not os.path.exists(imgui_lua):
            self.warn('Ashita libs/imgui.lua not found; using imgui_bundle enum names only')
            imgui_lua = None
        draw_list = dict(imgui_bridge.DRAW_LIST_FUNCTIONS)
        draw_text = draw_list['AddText']
        draw_image = draw_list['AddImage']
        draw_image_quad = draw_list['AddImageQuad']
        draw_rect = draw_list['AddRectFilled']

        def record_text(dl, *args):
            text = str(args[4] if len(args) >= 5 else args[2])
            position = imgui_bridge.vec2(args[2] if len(args) >= 5 else args[0], 'text position')
            size = imgui.calc_text_size(text)
            self.drawn_text.append(text)
            self.drawn_runs.append({'kind': 'text', 'text': text, 'x': position.x, 'y': position.y,
                                    'width': size.x, 'height': size.y,
                                    'color': int(args[3] if len(args) >= 5 else args[1]) & 0xFFFFFFFF,
                                    'window': self.bridge.window_stack[0] if self.bridge.window_stack else ''})
            return draw_text(dl, *args)

        draw_list['AddText'] = record_text

        def record_image(dl, *args):
            self.drawn_images.append(args)
            start, end = imgui_bridge.vec2(args[1], 'image start'), imgui_bridge.vec2(args[2], 'image end')
            uv_min = imgui_bridge.vec2(args[3], 'uv_min') if len(args) > 3 and args[3] is not None else imgui.ImVec2(0, 0)
            uv_max = imgui_bridge.vec2(args[4], 'uv_max') if len(args) > 4 and args[4] is not None else imgui.ImVec2(1, 1)
            self.drawn_runs.append({'kind': 'image', 'text': '', 'x': start.x, 'y': start.y,
                                    'width': end.x - start.x, 'height': end.y - start.y,
                                    'texture': int(args[0]), 'native_window': str(imgui.internal.get_current_window().name),
                                    'u0': uv_min.x, 'v0': uv_min.y, 'u1': uv_max.x, 'v1': uv_max.y,
                                    'window': self.bridge.window_stack[0] if self.bridge.window_stack else ''})
            return draw_image(dl, *args)

        draw_list['AddImage'] = record_image

        def record_image_quad(dl, *args):
            self.drawn_images.append(args)
            points = [imgui_bridge.vec2(point) for point in args[1:5]]
            left, top = min(point.x for point in points), min(point.y for point in points)
            right, bottom = max(point.x for point in points), max(point.y for point in points)
            self.drawn_runs.append({'kind': 'image', 'text': '', 'x': left, 'y': top,
                                    'width': right - left, 'height': bottom - top,
                                    'window': self.bridge.window_stack[0] if self.bridge.window_stack else ''})
            return draw_image_quad(dl, *args)

        draw_list['AddImageQuad'] = record_image_quad

        def record_rect(dl, *args):
            start, end = imgui_bridge.vec2(args[0], 'rectangle start'), imgui_bridge.vec2(args[1], 'rectangle end')
            self.drawn_rects.append({'x': start.x, 'y': start.y, 'width': end.x - start.x, 'height': end.y - start.y,
                                     'color': int(args[2]) & 0xFFFFFFFF,
                                     'window': self.bridge.window_stack[0] if self.bridge.window_stack else ''})
            return draw_rect(dl, *args)

        draw_list['AddRectFilled'] = record_rect
        py = L.table_from({
            'functions': L.table_from(self.bridge.functions),
            'draw_list': L.table_from(draw_list),
            'get_attr': imgui_bridge.get_attr,
            'set_attr': imgui_bridge.set_attr,
            'call_attr': imgui_bridge.call_attr,
            'vec_get': imgui_bridge.vec_get,
            'vec_set': imgui_bridge.vec_set,
            'enums': L.table_from(enums),
            'imgui_lua': imgui_lua.replace('\\', '/') if imgui_lua else None,
            'warn': self.warn,
        })
        L.globals().PREVIEW_PY = L.table_from({'file_exists': imgui_bridge.file_exists, 'log': self.logs.append,
                                            'icon_fixture': self.load_icon_fixture,
                                            'image_count': lambda: len(self.drawn_images),
                                            'window_present': lambda name: name in self.last_windows,
                                            'window_width': lambda name: self.last_windows[name]['size'][0],
                                            'window_height': lambda name: self.last_windows[name]['size'][1],
                                            'window_x': lambda name: self.last_windows[name]['pos'][0],
                                            'window_y': lambda name: self.last_windows[name]['pos'][1],
                                            'drawn_text': lambda: ''.join(self.drawn_text)})
        L.globals().PREVIEW_PY.hud_runs = lambda: L.table_from([
            L.table_from(run) for run in self.drawn_runs if run['window'].startswith('##vantage_')])
        L.globals().PREVIEW_PY.all_runs = lambda: L.table_from([L.table_from(run) for run in self.drawn_runs])
        L.globals().PREVIEW_PY.item_bounds = lambda label: L.table_from(self.bridge.items.get(label, ()))
        L.globals().PREVIEW_PY.hud_rects = lambda: L.table_from([
            L.table_from(rect) for rect in self.drawn_rects if rect['window'].startswith('##vantage_')])
        bridge_src = open(os.path.join(HERE, 'imgui_bridge.lua'), encoding='utf-8').read()
        L.execute(bridge_src, py)
        L.execute(LUA_SETUP, addon, 'full' if a.full else 'direct')
        L.globals().PREVIEW.addon_dir = addon
        L.globals().PREVIEW.hud_only = a.hud
        self.lua = L
        if a.client_assets:
            self.install_client_assets_fixture()
        self.check_constants(addon)

    def install_client_assets_fixture(self):
        """Keep DAT parsing and rendering real; replace only discovery, bounded reads and GPU upload."""
        from pathlib import Path
        L = self.lua
        ashita_root = Path(ASHITA_LIBS).resolve().parent.parent
        game_root = Path(self.args.client_game_root).resolve() if self.args.client_game_root else ashita_root / 'SquareEnix' / 'FINAL FANTASY XI'
        if not game_root.is_dir():
            raise ValueError('--client-assets needs a local FFXI install; pass --client-game-root')
        xiview_root = str(Path(self.args.client_xiview_root).resolve() / 'ROM' / '119' / '51.DAT') if self.args.client_xiview_root else None
        L.globals().PREVIEW_PY.client_read = self.read_client_fixture
        L.globals().PREVIEW_PY.client_upload = self.upload_client_fixture
        L.globals().PREVIEW_PY.client_texture_count = lambda: len(self.client_textures)
        L.globals().PREVIEW_PY.item_texture = lambda item: self.upload_item_fixture(game_root, int(item))
        L.execute(r'''
            local game_root, ashita_root, xiview_root = ...
            local assets = require('ui.client_assets')
            assert(type(assets._set_platform_for_tests) == 'function', 'Client asset test boundary is missing')
            local platform = {
                game_root = function() return game_root end,
                ashita_root = function() return ashita_root end,
                read = function(path, maximum) return PREVIEW_PY.client_read(path, maximum) end,
                upload = function(dds, width, height)
                    -- Hex keeps binary DDS bytes intact across lupa's UTF-8 string boundary.
                    local hex = dds:gsub('.', function(byte) return ('%02x'):format(byte:byte()) end)
                    local id = PREVIEW_PY.client_upload(hex, width, height)
                    return { id = id, release = function() end }
                end,
            }
            if xiview_root then platform.xiview_path = function() return xiview_root end end
            assets._set_platform_for_tests(platform)
            local present, item_icons = pcall(require, 'ui.item_icons')
            if present then
                item_icons._set_loader_for_tests(function(item)
                    return PREVIEW_PY.item_texture(item), function() end
                end)
            end
        ''', str(game_root), str(ashita_root), xiview_root)

    def upload_item_fixture(self, game_root, item_id):
        key = 'client-item-%d' % item_id
        if key not in self.client_textures:
            picture, path = read_item_picture(game_root, item_id)
            self.client_reads.append(path)
            filename = key + '.png'
            picture.save(os.path.join(self.work, filename))
            hello_imgui.set_assets_folder(self.work.replace('\\', '/'))
            self.client_textures[key] = hello_imgui.im_texture_id_from_asset(filename)
        return self.client_textures[key]

    def read_client_fixture(self, path, maximum):
        """Python's Unicode filesystem path avoids ANSI conversion in this offline fixture."""
        from pathlib import Path
        limit = int(maximum or 16777216)
        if limit <= 0 or limit > 16777216:
            return None, 'Invalid fixture read bound'
        try:
            with Path(path).open('rb') as handle:
                data = handle.read(limit + 1)
            if len(data) > limit:
                return None, 'Fixture file exceeds read bound'
            self.client_reads.append(str(path))
            return data, None
        except OSError as ex:
            return None, str(ex)

    def upload_client_fixture(self, hex_data, width, height):
        dds = bytes.fromhex(hex_data)
        key = hashlib.sha256(dds).hexdigest()
        if key not in self.client_textures:
            with Image.open(io.BytesIO(dds)) as source:
                picture = source.convert('RGBA')
            if picture.size != (int(width), int(height)):
                raise ValueError('Parser texture dimensions differ from decoded DDS')
            filename = 'client-asset-%s.png' % key
            picture.save(os.path.join(self.work, filename))
            hello_imgui.set_assets_folder(self.work.replace('\\', '/'))
            self.client_textures[key] = hello_imgui.im_texture_id_from_asset(filename)
        return self.client_textures[key]

    def lua_files(self, addon):
        """(path, shown name) of every .lua file in the addon, plus the --script file."""
        for root, _, files in os.walk(addon):
            for f in files:
                if f.endswith('.lua'):
                    path = os.path.join(root, f)
                    yield path, os.path.relpath(path, addon)
        if self.args.script:
            yield os.path.abspath(self.args.script), os.path.basename(self.args.script)

    def check_constants(self, addon):
        """Every ImGui constant named in the addon's Lua (and --script) must be one Ashita's libs/imgui.lua defines."""
        rawget = self.lua.eval('function (k) return rawget(_G, k) end')
        self.constants_checked = 0
        for path, shown in self.lua_files(addon):
            text = open(path, encoding='utf-8', errors='replace').read()
            code = re.sub(r'--\[(=*)\[.*?\]\1\]|--[^\n]*', '', text, flags=re.S)
            for name in sorted(set(re.findall(r'\b(Im(?:Gui|Draw|Font|Texture)\w*?_\w+)\b', code))):
                self.constants_checked += 1
                if rawget(name) is None:
                    self.warn("%s (in %s) is not defined by Ashita's libs/imgui.lua, so it is nil in game" % (name, shown))

    def load_addon(self):
        """Runs inside hello_imgui's font-loading callback, so hud.load_fonts() may add fonts."""
        L = self.lua
        L.execute(LUA_FULL if self.args.full else LUA_DIRECT)
        if self.args.icon_fixture:
            L.execute("require('ui.icons').status = function() return PREVIEW_PY.icon_fixture() end")
        if self.args.tab:
            L.execute('PREVIEW.settings.window.tab = ...', self.args.tab)
            self.bridge.tab_applied = True
        set_fn = L.eval('function (...) ' + LUA_SET + ' end')
        for key, value in self.sets:
            if isinstance(value, list):
                value = L.table_from(value)
            old_type, created = set_fn(L.globals().PREVIEW.settings, key, value)
            if created:
                self.warn('--set %s created missing table(s) %s' % (key, created))
            elif old_type == 'nil':
                self.warn('--set %s: the key did not exist before' % key)
        for code in self.args.exec:
            L.execute('local settings = PREVIEW.settings\n' + code)
        if self.args.client_assets:
            required = ['window', 'original_font']
            if self.args.client_xiview_root:
                required.append('xiview_font')
            status_for = L.eval("require('ui.client_assets').status")
            for kind in required:
                status = status_for(kind)
                if not status.available:
                    raise ValueError('Client asset fixture %s failed: %s' % (kind, status.reason))
        if self.args.script:
            L.execute(LUA_SCRIPT, os.path.abspath(self.args.script).replace('\\', '/'), self.args.frames)

    def load_icon_fixture(self):
        if self.icon_texture is None:
            from PIL import ImageDraw
            path = os.path.join(self.work, 'job-layout-fixture.png')
            picture = Image.new('RGBA', (32, 32), (70, 74, 80, 255))
            draw = ImageDraw.Draw(picture)
            draw.rectangle((1, 1, 30, 30), outline=(190, 194, 200, 255), width=2)
            draw.line((5, 5, 26, 26), fill=(190, 194, 200, 255), width=2)
            draw.line((26, 5, 5, 26), fill=(190, 194, 200, 255), width=2)
            picture.save(path)
            hello_imgui.set_assets_folder(self.work.replace('\\', '/'))
            self.icon_texture = hello_imgui.im_texture_id_from_asset('job-layout-fixture.png')
        return self.icon_texture

    # -- hello_imgui callbacks --------------------------------------------------------------------
    def load_fonts(self):
        io = imgui.get_io()
        # The game's ImGui (Ashita's shared atlas) draws fonts with stb_truetype, which doesn't hint. imgui_bundle
        # uses FreeType, so hinting is turned off for every font added from here on, like the game.
        io.fonts.font_loader_flags |= FREETYPE_NO_HINTING
        path = self.args.font or AGAVE
        if not self.args.font and not os.path.exists(path) and os.path.exists(ASHITA_DLL):
            try:
                import subprocess
                subprocess.run([sys.executable, os.path.join(HERE, 'extract_ashita_fonts.py'), ASHITA_DLL,
                                os.path.join(HERE, 'fonts')], check=True, capture_output=True)
            except Exception as ex:
                self.warn('could not extract Agave from Ashita.dll: %s' % ex)
        if not os.path.exists(path):
            import imgui_bundle
            path = os.path.join(os.path.dirname(imgui_bundle.__file__), 'assets', 'fonts', 'Inconsolata-Medium.ttf')
            self.warn('Agave not found (run extract_ashita_fonts.py); using Inconsolata-Medium')
        font = io.fonts.add_font_from_file_ttf(path, self.args.font_size)
        self.font_name = os.path.basename(path)
        if not self.args.font:
            # Ashita merges Font Awesome into every font it loads.
            for fa in FONT_AWESOME:
                if os.path.exists(fa):
                    cfg = imgui.ImFontConfig()
                    cfg.merge_mode = True
                    io.fonts.add_font_from_file_ttf(fa, self.args.font_size, cfg)
        io.font_default = font
        try:
            self.load_addon()
        except Exception as ex:
            # Ending the app from inside this callback crashes hello_imgui, so gui() ends it on frame 1.
            self.errors.append('loading the addon failed: %s' % _short(ex))

    def setup_style(self):
        style = imgui.get_style()
        fresh = imgui.Style()
        for name in dir(fresh):
            if name.startswith('_'):
                continue
            value = getattr(fresh, name)
            if callable(value):
                continue
            try:
                setattr(style, name, value)
            except (AttributeError, TypeError):
                pass
        imgui.style_colors_dark(style)
        style.font_size_base = self.args.font_size
        style.font_scale_main = 1.0
        style.font_scale_dpi = 1.0
        io = imgui.get_io()
        io.set_ini_filename(None)
        io.config_dpi_scale_fonts = False
        io.config_error_recovery = True
        io.config_error_recovery_enable_assert = True
        io.config_error_recovery_enable_debug_log = False
        io.config_error_recovery_enable_tooltip = False
        io.config_debug_highlight_id_conflicts = False

    def pre_new_frame(self):
        # ImGui's default style (hello_imgui applies its own theme first), set before the first frame.
        if not self.style_done:
            self.setup_style()
            self.style_done = True
        io = imgui.get_io()
        actions = [action for action in self.inputs if action.get('frame') == self.frame + 1]
        if not self.inputs:
            io.add_mouse_pos_event(-imgui_bridge.FLT_MAX, -imgui_bridge.FLT_MAX)
        for action in actions:
            if 'target' in action:
                # Only an item the frame before drew: one drawn earlier may be gone or moved.
                rectangle = self.bridge.drawn_items.get(action['target'])
                if rectangle is None:
                    if action['target'] in self.bridge.items:
                        raise RuntimeError('Input target not drawn last frame: ' + action['target'])
                    raise RuntimeError('Input target missing: ' + action['target'])
                point = action.get('point', (0.5, 0.5))
                self.mouse_position = (rectangle[0] + (rectangle[2] - rectangle[0]) * point[0],
                                       rectangle[1] + (rectangle[3] - rectangle[1]) * point[1])
                io.add_mouse_pos_event(*self.mouse_position)
            if 'mouse' in action:
                self.mouse_position = tuple(action['mouse'])
                io.add_mouse_pos_event(*self.mouse_position)
            if 'delta' in action:
                self.mouse_position = (self.mouse_position[0] + action['delta'][0],
                                       self.mouse_position[1] + action['delta'][1])
                io.add_mouse_pos_event(*self.mouse_position)
            if 'down' in action:
                io.add_mouse_button_event(action.get('button', 0), action['down'])
            if 'shift' in action:
                io.add_key_event(imgui.Key.mod_shift, action['shift'])
                self.lua.globals().MOCK.key_shift = action['shift']
            if 'ctrl' in action:
                io.add_key_event(imgui.Key.mod_ctrl, action['ctrl'])
            if 'key' in action:
                io.add_key_event(getattr(imgui.Key, action['key']), action.get('key_down', True))
            if 'wheel' in action:
                io.add_mouse_wheel_event(0, action['wheel'])
            if 'escape' in action:
                io.add_key_event(imgui.Key.escape, action['escape'])
                self.lua.globals().MOCK.key_escape = action['escape']
            if 'text' in action:
                io.add_input_characters_utf8(action['text'])
            if 'lua' in action:
                self.lua.execute('local settings = PREVIEW.settings\n' + action['lua'])

    def gui(self):
        self.frame += 1
        params = hello_imgui.get_runner_params()
        if self.frame > self.args.frames or params.app_shall_exit or self.errors:
            params.app_shall_exit = True
            return
        self.bridge.begin_frame(self.frame)
        del self.logs[:]
        del self.drawn_text[:]
        del self.drawn_images[:]
        del self.drawn_runs[:]
        del self.drawn_rects[:]
        self.collect_garbage()
        before = imgui.internal.ErrorRecoveryState()
        imgui.internal.error_recovery_store_state(before)
        raised = False
        try:
            if self.args.chat_fixture:
                self.draw_chat_fixture()
            self.lua.globals().PREVIEW.draw()
        except Exception as ex:
            raised = True
            self.errors.append('frame %d: %s' % (self.frame, _short(ex)))
            params.app_shall_exit = True
        after = imgui.internal.ErrorRecoveryState()
        imgui.internal.error_recovery_store_state(after)
        diffs = [n[len('size_of_'):] + ' %+d' % (getattr(after, n) - getattr(before, n))
                 for n in dir(before) if n.startswith('size_of_') and getattr(after, n) != getattr(before, n)]
        if diffs:
            # A Lua error mid-window always leaves the stacks open, so only report them on their own.
            if not raised:
                self.errors.append('frame %d: unbalanced ImGui stacks after drawing: %s' % (self.frame, ', '.join(diffs)))
            # Unwind what the addon left open, so ImGui can finish the frame and exit cleanly.
            io = imgui.get_io()
            io.config_error_recovery_enable_assert = False
            try:
                imgui.internal.error_recovery_try_to_recover_state(before)
            except Exception as ex:
                self.errors.append('recovery failed: %s' % _short(ex))
            finally:
                io.config_error_recovery_enable_assert = True
            params.app_shall_exit = True
        if self.args.full:
            for line in self.lua.globals().MOCK.printed.values():
                if 'error' in str(line).lower() or 'could not' in str(line).lower():
                    self.errors.append('frame %d: Vantage reported an error: %s' % (self.frame, line))
                    params.app_shall_exit = True
            self.lua.execute('MOCK.printed = {}')
        self.last_windows = dict(self.bridge.windows)
        if self.frame >= self.args.frames:
            params.app_shall_exit = True

    def draw_chat_fixture(self):
        chat = self.lua.globals().MOCK.chat
        if chat is None:
            return
        areas, seen = [], set()
        for area in [chat] + list(chat.windows.values() if chat.windows is not None else []):
            bounds = (area.x, area.y, area.width, area.height)
            if bounds not in seen:
                areas.append(area)
                seen.add(bounds)
        draw = imgui.get_background_draw_list()
        for index, area in enumerate(areas, 1):
            start = imgui.ImVec2(area.x, area.y)
            end = imgui.ImVec2(area.x + area.width, area.y + area.height)
            draw.add_rect_filled(start, end, imgui.get_color_u32(imgui.ImVec4(0.11, 0.13, 0.18, 1)))
            draw.add_rect(start, end, imgui.get_color_u32(imgui.ImVec4(0.52, 0.6, 0.72, 1)))
            draw.add_text(imgui.ImVec2(area.x + 12, area.y + 12),
                          imgui.get_color_u32(imgui.ImVec4(0.72, 0.77, 0.84, 1)),
                          '%s %d' % (self.lua.globals().PREVIEW.chat_fixture_label or 'SIMULATED CHAT', index))

    # -- run --------------------------------------------------------------------------------------
    def run(self):
        a = self.args
        # The addon's files, like profiles.json, and ImGui's ini file go in a new folder in %TEMP%, so no
        # run sees another's. main() deletes it at the end.
        self.work = tempfile.mkdtemp(prefix='vantage_preview_')
        self.make_lua()
        rp = hello_imgui.RunnerParams()
        rp.app_window_params.window_title = 'vantage preview'
        rp.app_window_params.hidden = True
        rp.app_window_params.restore_previous_geometry = False
        rp.app_window_params.window_geometry.size = (int(a.size[0]), int(a.size[1]))
        rp.imgui_window_params.default_imgui_window_type = hello_imgui.DefaultImGuiWindowType.no_default_window
        rp.imgui_window_params.background_color = imgui.ImVec4(*BACKGROUND)
        rp.imgui_window_params.show_menu_bar = False
        rp.imgui_window_params.show_status_bar = False
        rp.imgui_window_params.remember_theme = False
        rp.fps_idling.enable_idling = False
        # Every run starts from ImGui's first-use state: no window positions or sizes carried over. Each
        # run gets its own file, so the fit gate's runs at once can't lock each other's.
        rp.ini_folder_type = hello_imgui.IniFolderType.absolute_path
        rp.ini_filename = os.path.join(self.work, 'hello_imgui_preview_%d.ini' % os.getpid())
        hello_imgui.delete_ini_settings(rp)
        rp.dpi_aware_params.dpi_window_size_factor = 1.0
        rp.callbacks.default_icon_font = hello_imgui.DefaultIconFont.no_icons
        rp.callbacks.load_additional_fonts = self.load_fonts
        rp.callbacks.setup_imgui_style = self.setup_style
        rp.callbacks.pre_new_frame = self.pre_new_frame
        rp.callbacks.show_gui = self.gui
        try:
            immapp.run(rp)
        except Exception as ex:
            self.errors.append('ImGui: %s' % _short(ex))
        try:
            hello_imgui.delete_ini_settings(rp)
        except Exception:
            pass

        shot = hello_imgui.final_app_window_screenshot()
        arr = np.asarray(shot) if shot is not None else None
        return arr

    def save(self, arr):
        a = self.args
        if a.tab and not self.bridge.tab_applied:
            self.errors.append('tab %r never opened (tabs seen: %s)' % (a.tab, sorted(set(self.bridge.tabs_seen)) or 'none'))
        if self.errors:
            return None, None   # no PNG for a failed run, so a stale or half-drawn image can't pass for a result
        if arr is None or arr.size == 0:
            self.errors.append('no screenshot was captured')
            return None, None
        h, w = arr.shape[0], arr.shape[1]
        target = self.pick_window()
        if target is None:
            self.errors.append('no settings window was drawn (windows seen: %s)' % (list(self.last_windows) or 'none'))
            return None, None
        info = self.last_windows[target]
        if info['content'][0] > info['size'][0]:
            self.errors.append('window content is wider than the visible window')
            return None, None
        if a.no_crop:
            box = (0, 0, w, h)
        else:
            info = self.last_windows[target]
            if info['hidden']:
                self.warn('window %r was still hidden on the last frame (auto-fit windows skip their first '
                          'frame); use --frames 2 or more' % target)
            x0, y0 = info['pos']
            x1, y1 = x0 + info['size'][0], y0 + info['size'][1]
            if x0 < 0 or y0 < 0 or x1 > w or y1 > h:
                self.warn('window %r runs off the %dx%d screen; the crop is clipped' % (target, w, h))
            m = a.margin
            box = (max(0, int(x0) - m), max(0, int(y0) - m), min(w, int(np.ceil(x1)) + m), min(h, int(np.ceil(y1)) + m))
        img = Image.fromarray(arr[:, :, :3] if arr.ndim == 3 else arr).crop(box)
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        img.save(a.out)
        return target, box

    def pick_window(self):
        if not self.last_windows:
            return None
        names = list(self.last_windows)
        if self.args.window:
            names = [n for n in names if self.args.window.lower() in n.lower()]
        else:
            named = [n for n in names if not n.startswith('##')]
            names = named or names
        if not names:
            return None
        return max(names, key=lambda n: self.last_windows[n]['size'][0] * self.last_windows[n]['size'][1])


def _short(ex):
    text = str(ex).strip()
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if len(lines) > 6:
        lines = lines[:6] + ['...']
    return ' | '.join(lines) if lines else repr(ex)


def main(argv=None):
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors='replace')
        except Exception:
            pass
    args = parse_args(argv if argv is not None else sys.argv[1:])
    require_libs()
    if not os.path.isdir(args.addon):
        print('FAIL addon folder not found: %s' % args.addon)
        return 2
    pv = Preview(args)
    try:
        arr = pv.run()
        target, box = pv.save(arr)
    except SystemExit:
        raise
    except Exception as ex:
        traceback.print_exc()
        pv.errors.append('preview crashed: %s' % _short(ex))
        target, box = None, None
    finally:
        if pv.work is not None:
            shutil.rmtree(pv.work, ignore_errors=True)

    b = pv.bridge if hasattr(pv, 'bridge') else None
    for line in pv.logs:
        print('log: ' + line, file=sys.stderr)
    for w in pv.warnings:
        print('warning: ' + w, file=sys.stderr)

    parts = ['OK' if not pv.errors else 'FAIL']
    if target is not None:
        info = pv.last_windows[target]
        parts.append('window=%r pos=(%g,%g) size=%gx%g content=%gx%g' % (
            target, info['pos'][0], info['pos'][1], info['size'][0], info['size'][1],
            info['content'][0], info['content'][1]))
        if info['scrollbar_y'] or info['scrollbar_x']:
            parts.append('scrollbar=%s%s' % ('x' if info['scrollbar_x'] else '', 'y' if info['scrollbar_y'] else ''))
    if b is not None:
        parts.append('tab=%s' % (','.join(b.tab_open) or '-'))
    parts.append('screen=%dx%d frames=%d font=%s' % (args.size[0], args.size[1], args.frames, pv.font_name))
    if args.client_assets:
        parts.append('client_textures=%d client_reads=%d' % (len(pv.client_textures), len(pv.client_reads)))
    if box is not None and not pv.errors:
        parts.append('crop=%s out=%s' % (box, args.out))
    if pv.warnings:
        parts.append('warnings=%d' % len(pv.warnings))
    if pv.errors:
        for e in pv.errors:
            print('error: ' + e, file=sys.stderr)
        parts.append('error: ' + pv.errors[0])
        if len(pv.errors) > 1:
            parts.append('(+%d follow-on, see stderr)' % (len(pv.errors) - 1))
    sys.stderr.flush()
    print(' '.join(parts))
    sys.stdout.flush()
    return 1 if pv.errors else 0


if __name__ == '__main__':
    code = main()
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(code)   # Skips interpreter teardown. hello_imgui and GL objects don't always unload cleanly.
