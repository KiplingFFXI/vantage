"""Check that a game client has every client pattern Vantage looks for, each exactly once.

usage: python tools/client_check.py <FFXiMain.dll or decoded image> [--addon FOLDER] [--libs ASHITA_LIBS]

Vantage finds a few things in the client by byte patterns, as Ashita's ashita.memory.find does:
  core/chat.lua            the chat windows and the menu scale, for chat docking and snapping
  core/client.lua          the event, interface and map focus flags its visibility options read
  core/native_party_ui.lua the game's party list, for the strips beside it, and the Treasure Pool window
  core/clock.lua           the game clock, for self timer countdowns
  core/name_anchor.lua     the game's name point, for overhead icons just above the name, and the client's
                           cameras, for the camera check in /vg report
  core/game_buffs.lua      the game's own buff icons and + menu, for Replace the game's buff icons: where
                           each routine starts, and each routine whole as it was written for
Item recasts load Ashita's ffxi.itemdata, which finds its own two patterns and the ones of the ffxi
libraries it loads (ffxi.time). Those are checked too while the addon loads ffxi.itemdata.

The patterns are read from those files, so this checks what the addon and libraries look for now. Each
is counted in the whole client image, the range ashita.memory.find searches, and printed with where it
was found. Exit codes: 0 every pattern found exactly once, 1 a pattern missing or found more than once,
2 the client or a pattern file cannot be read. The client is only read; a DLL is decoded in memory with
the research decoder in tests/out/native-solo-research. The libraries default to the addons/libs folder of
the Ashita install the client is in, or else ASHITA_LIBS.
"""
from pathlib import Path
import argparse
import contextlib
import hashlib
import io
import os
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT/'vantage'
RESEARCH = ROOT/'tests/out/native-solo-research'
# Matches past this many are counted as this many; one is all that may be found.
CAP = 9
HEX = r"'((?:[0-9A-F]{2}|\?\?)+)'"
REQUIRE = re.compile(r'''\brequire\s*(?:\(\s*|,\s*)?['"]([\w.]+)['"]''')


class Unreadable(Exception):
    pass


def sections(data):
    """name -> (rva, virtual size) from the PE headers."""
    if len(data) < 0x40 or data[:2] != b'MZ':
        raise Unreadable('not a PE file')
    pe = struct.unpack_from('<I', data, 0x3C)[0]
    if pe + 24 > len(data) or data[pe:pe + 4] != b'PE\0\0':
        raise Unreadable('not a PE file')
    count, optional = struct.unpack_from('<H', data, pe + 6)[0], struct.unpack_from('<H', data, pe + 20)[0]
    table, result = pe + 24 + optional, {}
    for index in range(count):
        at = table + index * 40
        name = data[at:at + 8].rstrip(b'\0').decode('ascii', 'replace')
        size, rva = struct.unpack_from('<II', data, at + 8)
        result.setdefault(name, (rva, size))
    return result


def image_base(data):
    pe = struct.unpack_from('<I', data, 0x3C)[0]
    return struct.unpack_from('<I', data, pe + 24 + 28)[0]


def read_client(path):
    """(decoded image bytes, input sha256, 'image' or 'dll')."""
    try:
        raw = Path(path).read_bytes()
    except OSError as error:
        raise Unreadable(str(error))
    found = sections(raw)
    if not found:
        raise Unreadable('no sections')
    if len(raw) >= max(rva for rva, _ in found.values()):
        return raw, hashlib.sha256(raw).hexdigest(), 'image'
    if 'POL1' not in found or '.text' not in found:
        raise Unreadable('not a decoded image and not an FFXiMain.dll')
    pe = struct.unpack_from('<I', raw, 0x3C)[0]
    table = pe + 24 + struct.unpack_from('<H', raw, pe + 20)[0]
    end = max(sum(struct.unpack_from('<II', raw, table + index * 40 + 16))
              for index in range(struct.unpack_from('<H', raw, pe + 6)[0]))
    if len(raw) < end:
        raise Unreadable('the DLL is truncated')
    sys.path[:0] = [str(RESEARCH), str(RESEARCH/'vendor')]
    try:
        from xi_core import load_and_decompress
        with contextlib.redirect_stdout(io.StringIO()):
            pe, text, section, base, _ = load_and_decompress(Path(path))
        image = bytearray(pe.get_memory_mapped_image())
        image[section.VirtualAddress:section.VirtualAddress + len(text)] = text
    except Exception as error:
        raise Unreadable('could not decode the DLL: %s' % error)
    if len(text) != found['.text'][1]:
        raise Unreadable('the DLL decoded to %d code bytes, not %d' % (len(text), found['.text'][1]))
    return bytes(image), hashlib.sha256(raw).hexdigest(), 'dll'


def compile_pattern(text):
    if len(text) % 2 or not re.fullmatch(r'(?:[0-9A-F]{2}|\?\?)+', text):
        raise ValueError('bad pattern %r' % text)
    return re.compile(b''.join(b'.' if text[k:k + 2] == '??' else re.escape(bytes([int(text[k:k + 2], 16)]))
                               for k in range(0, len(text), 2)), re.S)


def matches(data, text, cap=CAP):
    """Starts of matches anywhere in data, overlapping ones too, at most cap of them."""
    rx, found, pos = compile_pattern(text), [], 0
    while len(found) < cap:
        m = rx.search(data, pos)
        if not m:
            break
        found.append(m.start())
        pos = m.start() + 1
    return found


def source(path):
    try:
        return Path(path).read_text(encoding='utf-8')
    except (OSError, UnicodeError) as error:
        raise Unreadable('cannot read %s: %s' % (path, error))


def lua_string(expression, where):
    """The value of a Lua expression of quoted hex and string.rep('?', n), joined with .."""
    parts = []
    for piece in expression.split('..'):
        piece = piece.strip()
        quoted = re.fullmatch(r"'([0-9A-F?]*)'", piece)
        repeated = re.fullmatch(r"string\.rep\('\?',\s*(\d+)\)", piece)
        if quoted:
            parts.append(quoted.group(1))
        elif repeated:
            parts.append('?' * int(repeated.group(1)))
        else:
            raise Unreadable('cannot read the pattern in %s: %s' % (where, piece))
    return ''.join(parts)


def block(text, start, where):
    """The text of the Lua table that starts at the line start."""
    at = text.find(start)
    end = text.find('}', at)
    if at < 0 or end < 0:
        raise Unreadable('%s has no %s' % (where, start.strip()))
    return text[at + len(start):end]


def counted(found, expected, where):
    if len(found) != expected:
        raise Unreadable('%s has %d client patterns, this check reads %d' % (where, len(found), expected))
    return found


def addon_patterns(addon=ADDON):
    """[(file, name, pattern)] that the addon itself looks for."""
    addon, result = Path(addon), []
    where = 'core/chat.lua'
    text = source(addon/where)
    for name, pattern in counted(re.findall(r"^local (\w+)_PATTERN = %s;" % HEX, text, re.M), 2, where):
        result.append((where, {'CHAT': 'chat windows', 'SCALE': 'menu scale'}.get(name, name.lower()), pattern))
    where = 'core/client.lua'
    text = source(addon/where)
    labels = {'event_flag': 'event flag', 'interface': 'interface', 'focus_slot': 'map focus'}
    for name, pattern in counted(re.findall(r"^\s*(\w+) = pointer\(%s, \d+, \d+\);" % HEX, text, re.M), 3, where):
        result.append((where, labels.get(name, name), pattern))
    where = 'core/native_party_ui.lua'
    text = source(addon/where)
    party = counted(re.findall(HEX, block(text, '\nlocal patterns = {', where)), 2, where)
    for index, pattern in enumerate(party, 1):
        result.append((where, 'party list %d' % index, pattern))
    treasure = re.search(r'^local treasure_pattern = (.+?);', text, re.M | re.S)
    if not treasure:
        raise Unreadable('%s has no treasure_pattern' % where)
    result.append((where, 'treasure pool', lua_string(treasure.group(1), where)))
    where = 'core/clock.lua'
    text = source(addon/where)
    for name, pattern in counted(re.findall(r"(\w+) = %s" % HEX, block(text, '\nlocal patterns = {', where)), 1, where):
        result.append((where, name.replace('_', ' '), pattern))
    where = 'core/name_anchor.lua'
    text = source(addon/where)
    for start, count, label in (('\nlocal patterns = {', 16, 'name point'), ('\nlocal check_patterns = {', 7, 'camera check')):
        for name, pattern in counted(re.findall(r"(\w+) = %s" % HEX, block(text, start, where)), count, where):
            result.append((where, '%s %s' % (label, name.replace('_', ' ')), pattern))
    where = 'core/game_buffs.lua'
    text = source(addon/where)
    for start, count, label in (('\nlocal patterns = {', 7, 'game buffs'), ('\nlocal bodies = {', 6, 'game buffs whole')):
        for name, pattern in counted(re.findall(r"(\w+) = %s" % HEX, block(text, start, where)), count, where):
            result.append((where, '%s %s' % (label, name.replace('_', ' ')), pattern))
    return result


def loads_itemdata(addon=ADDON):
    for path in sorted(Path(addon).rglob('*.lua')):
        if 'ffxi.itemdata' in REQUIRE.findall(source(path)):
            return True
    return False


def library_patterns(libs):
    """[(file, name, pattern)] that ffxi.itemdata and the ffxi libraries it loads look for."""
    libs, result, pending, seen = Path(libs), [], ['ffxi.itemdata'], set()
    while pending:
        module = pending.pop(0)
        if module in seen:
            continue
        seen.add(module)
        where = module.replace('.', '/') + '.lua'
        text = source(libs/where)
        found = re.findall(r"([\w.]+)\s*=\s*ashita\.memory\.find\(\s*0\s*,\s*0\s*,\s*%s\s*,\s*-?\d+\s*,\s*\d+\s*\)" % HEX, text)
        calls = len(re.findall(r'^[^-\n]*ashita\.memory\.find\(', text, re.M))
        if calls != len(found) or module == 'ffxi.itemdata' and not found:
            raise Unreadable('%s has %d client pattern searches, this check reads %d' % (where, calls, len(found)))
        result += [('libs/' + where, name.split('.')[-1].replace('_', ' '), pattern) for name, pattern in found]
        pending += [name for name in REQUIRE.findall(text) if name.startswith('ffxi.')]
    return result


def default_libs(client):
    """The libraries of the Ashita install the client is in (<Ashita>/SquareEnix/FINAL FANTASY XI), or else
    ASHITA_LIBS."""
    parents = Path(client).resolve().parents
    # A client less than three folders deep isn't in an Ashita install.
    if len(parents) > 2 and (parents[2]/'addons/libs/ffxi').is_dir():
        return parents[2]/'addons/libs'
    if os.environ.get('ASHITA_LIBS'):
        return Path(os.environ['ASHITA_LIBS'])
    raise Unreadable("the addon loads ffxi.itemdata; pass --libs with Ashita's addons/libs folder")


def check(data, patterns):
    """[(file, name, pattern, [match RVAs])], each pattern's matches in the image, at most CAP."""
    return [(where, name, pattern, matches(data, pattern)) for where, name, pattern in patterns]


def main(argv=None):
    parser = argparse.ArgumentParser(description='Check that a client has every pattern Vantage looks for, once.')
    parser.add_argument('client', type=Path, help='FFXiMain.dll or a decoded client image')
    parser.add_argument('--addon', type=Path, default=ADDON, help='the vantage addon folder')
    parser.add_argument('--libs', type=Path, help="Ashita's addons/libs folder, for ffxi.itemdata")
    args = parser.parse_args(argv)
    try:
        patterns = addon_patterns(args.addon)
        if loads_itemdata(args.addon):
            patterns += library_patterns(args.libs or default_libs(args.client))
        data, input_sha256, kind = read_client(args.client)
        base = image_base(data)
        results = check(data, patterns)
    except (Unreadable, ValueError, struct.error) as error:
        print('Cannot check the client: %s' % error)
        return 2
    print('Client %s (%s, SHA-256 %s)' % (args.client, kind, input_sha256))
    bad, width = 0, max([20] + [len(name) for _, name, _, _ in results])
    for where, name, pattern, found in results:
        if len(found) == 1:
            result = 'once at 0x%08X' % (base + found[0])
        else:
            bad += 1
            result = 'NOT FOUND' if not found else 'FOUND %s%d TIMES' % ('AT LEAST ' if len(found) >= CAP else '', len(found))
        print('  %-30s %-*s %-17s %s' % (where, width, name, result, pattern))
    if bad:
        print('%d of %d patterns are not found exactly once.' % (bad, len(results)))
        return 1
    print('All %d patterns found exactly once.' % len(results))
    return 0


if __name__ == '__main__':
    sys.exit(main())
