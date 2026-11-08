"""Build dist/vantage-VERSION-addon.zip, whose addons/vantage folder players copy into their game's addons folder.

usage: python tools/package.py [--out FOLDER]

The archive holds addons/vantage/ (the addon's runtime files, as listed in tools/release_files.py) and
LICENSE, README.md, CHANGELOG.md, docs/GUIDE.md and docs/INSTALL.md. Caches, tests, tools, fonts made at run time
and game data are left out. It refuses to build when a file holds a private marker: a line of
tools/private_markers.txt, a temporary or scratch path or an absolute user path, in plain bytes or UTF-16LE, in any
case. The member order and times are fixed, so the same sources give the same archive.
"""
from pathlib import Path
import argparse
import hashlib
import os
import sys
import tempfile
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from release_files import ADDON, REQUIRED, ROOT, addon_version, check_archive_links, linked, required_modules

DOCUMENTS = ('LICENSE', 'README.md', 'CHANGELOG.md', 'docs/GUIDE.md', 'docs/INSTALL.md')
# Left out of the addon folder: caches, tests, tools, fonts Vantage makes at run time, game data and settings.
SKIP_FOLDERS = {'__pycache__', '.git', 'tests', 'tools', 'fonts', 'config'}
SKIP_SUFFIXES = {'.pyc', '.pyo', '.ttf', '.otf', '.dat', '.tmp', '.log', '.bak'}
# Your own private text, one per line: your Windows user name, email and character names. .gitignore keeps this file
# out of the repository, so a build without it still checks the paths.
OWN_MARKERS = Path(__file__).resolve().parent / 'private_markers.txt'
PATH_MARKERS = ('AppData', 'C:/Users', 'C:\\Users', 'C:\\\\Users')


def own_markers(path=OWN_MARKERS):
    """The lines of the local marker file, or none when there's no such file."""
    if not Path(path).is_file():
        return ()
    return tuple(line.strip() for line in Path(path).read_text(encoding='ascii').splitlines() if line.strip())


MARKERS = own_markers() + PATH_MARKERS


def private_marker(data):
    """The first marker data holds, plain or UTF-16LE, ignoring case, or None."""
    lowered = data.lower()
    for marker in MARKERS:
        text = marker.lower()
        if text.encode('ascii') in lowered or text.encode('utf-16-le') in lowered:
            return marker
    return None


def addon_contents(addon=ADDON):
    """[(path, archived name)] of the addon's runtime files, with caches, fonts and game data left out."""
    addon = Path(addon)
    if linked(addon):
        raise RuntimeError('The addon folder must not be linked.')
    found = {}
    for folder, subfolders, filenames in os.walk(addon):
        subfolders[:] = sorted(name for name in subfolders if name not in SKIP_FOLDERS)
        for name in subfolders:
            if linked(Path(folder) / name):
                raise RuntimeError('Linked runtime folder: ' + (Path(folder) / name).relative_to(addon).as_posix())
        for name in filenames:
            path = Path(folder) / name
            if path.suffix.lower() in SKIP_SUFFIXES:
                continue
            relative = path.relative_to(addon).as_posix()
            if linked(path) or relative not in REQUIRED:
                raise RuntimeError('Unexpected or linked runtime file: ' + relative)
            found[relative] = path
    missing = REQUIRED - set(found)
    if missing:
        raise RuntimeError('Missing runtime files: ' + ', '.join(sorted(missing)))
    left_out = required_modules(addon) - REQUIRED
    if left_out:
        raise RuntimeError('vantage.lua loads modules the archive leaves out: ' + ', '.join(sorted(left_out)))
    return [(found[name], 'addons/vantage/' + name) for name in sorted(found)]


def contents(root=ROOT, addon=None):
    """[(archived name, bytes)], checked: ASCII text, LF line ends, no private marker in a name or a file."""
    root = Path(root)
    sources = addon_contents(addon or root / 'vantage')
    for name in DOCUMENTS:
        path = root / name
        if not path.is_file() or linked(path):
            raise RuntimeError('Missing or linked document: ' + name)
        sources.append((path, name))
    result = []
    for path, name in sources:
        data = path.read_bytes()
        marker = private_marker(data) or private_marker(name.encode('ascii'))
        if marker:
            raise RuntimeError('Private marker in %s: %s' % (name, marker))
        try:
            data.decode('ascii')
        except UnicodeError:
            raise RuntimeError('Not ASCII text: ' + name)
        result.append((name, data.replace(b'\r\n', b'\n')))
    result.sort()
    check_archive_links(result)
    return result


def build(out=None, root=ROOT, addon=None):
    root = Path(root)
    addon = Path(addon or root / 'vantage')
    out = Path(out or root / 'dist')
    if out.resolve().is_relative_to(addon.resolve()):
        raise RuntimeError('Write the archive outside the addon folder.')
    files = contents(root, addon)
    out.mkdir(parents=True, exist_ok=True)
    destination = out / ('vantage-%s-addon.zip' % addon_version(addon))
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix='.vantage-', suffix='.zip', dir=out, delete=False) as handle:
            temporary = Path(handle.name)
        with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as archive:
            for name, data in files:
                entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                entry.create_system = 3
                entry.external_attr = 0o100644 << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(entry, data)
        with zipfile.ZipFile(temporary) as archive:
            if archive.testzip() or archive.namelist() != [name for name, _ in files]:
                raise RuntimeError('The archive failed verification.')
            if any(private_marker(archive.read(name)) for name in archive.namelist()):
                raise RuntimeError('The archive holds a private marker.')
        os.replace(temporary, destination)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()
    return destination, len(files), hashlib.sha256(destination.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--out', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    try:
        path, count, digest = build(args.out)
    except RuntimeError as error:
        print('Not built: %s' % error)
        return 1
    print('Wrote %s with %d files.' % (path, count))
    print('SHA-256 ' + digest)
    return 0


if __name__ == '__main__':
    sys.exit(main())
