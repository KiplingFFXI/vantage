"""Check public sources, document links, and runtime release boundaries."""
from collections import Counter
import os
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit

from release_files import PRIVATE, ROOT, addon_files, addon_version, checked_bytes, linked

SKIP = {'.git', '.ci', '.venv', '__pycache__', 'dist'}
TEXT = {'.lua', '.py', '.md', '.txt', '.yml', '.yaml', '.json', '.bat', '.ps1', '.asm', '.cpp', '.hpp', '.def'}
# Output folders, the decoded client images the client check reads and the x86 LuaJIT the frame benchmark and
# trace check run in; .gitignore keeps them out of commits.
SKIP_FOLDERS = {'tests/out', 'tests/preview/fonts', 'tests/fixtures/clients', 'tests/luajit-x86'}


def public_files(root):
    for folder, subfolders, files in os.walk(root):
        base = Path(folder)
        subfolders[:] = sorted(name for name in subfolders if name not in SKIP
                               and (base / name).relative_to(root).as_posix() not in SKIP_FOLDERS)
        for name in sorted(files):
            yield base / name


def anchors(text):
    result, seen = set(), Counter()
    for title in re.findall(r'^#{1,6}\s+(.+?)\s*#*$', text, re.M):
        slug = re.sub(r'[^\w\- ]', '', title.lower()).replace(' ', '-')
        result.add(slug if not seen[slug] else '%s-%d' % (slug, seen[slug]))
        seen[slug] += 1
    return result


def check(root=ROOT):
    root = Path(root).resolve()
    problems, documents = [], {}
    for path in public_files(root):
        relative = path.relative_to(root).as_posix()
        if linked(path):
            problems.append(relative + ': linked source file')
        if path.suffix.lower() not in TEXT and path.name not in {'LICENSE', '.gitignore', '.gitattributes', '.clang-format'}:
            if not (path.suffix.lower() == '.png' and relative.startswith('docs/images/')):
                problems.append(relative + ': unexpected public file type')
            continue
        try:
            text = path.read_text(encoding='ascii')
        except UnicodeError:
            problems.append(relative + ': expected ASCII text')
            continue
        if PRIVATE.search(text):
            problems.append(relative + ': private path or credential marker')
        if path.suffix == '.md':
            documents[path.resolve()] = text
    for name in ('README.md', 'CHANGELOG.md', 'LICENSE', 'docs/GUIDE.md', 'docs/INSTALL.md', 'docs/RELEASING.md',
                 'tests/README.txt', 'tools/README.txt'):
        if not (root / name).is_file():
            problems.append(name + ': missing release document')
    try:
        version = addon_version(root / 'vantage')
        headings = re.findall(r'^## (.+)$', documents.get((root / 'CHANGELOG.md').resolve(), ''), re.M)
        if not headings or headings[0] != version:
            problems.append('CHANGELOG.md: newest heading must match addon.version')
        for path, name in addon_files(root / 'vantage'):
            checked_bytes(path, name)
    except (RuntimeError, OSError, UnicodeError) as exc:
        problems.append(str(exc))
    links = 0
    for path, text in documents.items():
        for target in re.findall(r'\[[^\]\n]*\]\(([^)\n]+)\)', text):
            target = target.strip('<>')
            split = urlsplit(target)
            if split.scheme or split.netloc:
                continue
            destination = (path.parent / unquote(split.path)).resolve() if split.path else path
            links += 1
            if not destination.is_relative_to(root) or not destination.exists():
                problems.append(path.relative_to(root).as_posix() + ': missing local link ' + target)
            elif split.fragment and destination in documents and unquote(split.fragment) not in anchors(documents[destination]):
                problems.append(path.relative_to(root).as_posix() + ': missing heading ' + target)
    return problems, links


if __name__ == '__main__':
    problems, links = check()
    for problem in problems:
        print('FAIL ' + problem)
    if problems:
        raise SystemExit(1)
    print('Public sources and release files checked; %d local document links verified.' % links)
