"""The decoded client image a driver runs on.

Drivers take --image: a decoded image (.bin) or an FFXiMain.dll to decode. The default is the image
every test was verified on, so no driver reads the installed client unless it is passed explicitly.
A DLL is decoded in memory; its image is written only to --image-dir, or else to a temporary folder
outside the project that is removed at exit. No driver writes the two images in tests/fixtures/clients.
"""
from pathlib import Path
import argparse
import atexit
import hashlib
import shutil
import struct
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OLD_IMAGE = ROOT/'tests/fixtures/clients/client-image-f2245d1c.bin'
NEW_IMAGE = ROOT/'tests/fixtures/clients/client-image-04288488.bin'
RESEARCH = ROOT/'tests/out/native-solo-research'
# Decoded images and the FFXiMain.dll each was decoded from.
KNOWN = {'45908788c486ae171d40c1b19c745dfcb187123dbb46d0d1a74e6583b934d929':
         'f2245d1c9d06e02c36624942483913f5120c0d40777fc1bb8703c6f4bda823e4',
         '1dfee620131f9630751fbee8708de68dc9801881c34ea5aac63b2f738986edb7':
         '042884888eea4fadac183e520f2ae9f8c4fa267860e685048e1880efd358e872'}
BASE = 0x10000000


def digest(data):
    return hashlib.sha256(data).hexdigest()


def sections(data):
    """(name, rva, virtual size, raw offset, raw size) from the PE headers."""
    if len(data) < 0x40 or data[:2] != b'MZ':
        raise ValueError('not a PE file')
    pe = struct.unpack_from('<I', data, 0x3C)[0]
    if data[pe:pe + 4] != b'PE\0\0':
        raise ValueError('not a PE file')
    count, optional = struct.unpack_from('<H', data, pe + 6)[0], struct.unpack_from('<H', data, pe + 20)[0]
    table, result = pe + 24 + optional, []
    for index in range(count):
        at = table + index * 40
        name = data[at:at + 8].rstrip(b'\0').decode('ascii', 'replace')
        size, rva, raw_size, raw = struct.unpack_from('<IIII', data, at + 8)
        result.append((name, rva, size, raw, raw_size))
    return result


def image_base(data):
    pe = struct.unpack_from('<I', data, 0x3C)[0]
    return struct.unpack_from('<I', data, pe + 24 + 28)[0]


def is_mapped(data):
    """A decoded image is laid out by virtual address; a DLL on disk by file offset."""
    found = sections(data)
    return bool(found) and len(data) >= max(rva for _, rva, _, _, _ in found)


def decode(path):
    """Decode FFXiMain.dll in memory with the research decoder (read only)."""
    sys.path[:0] = [str(RESEARCH), str(RESEARCH/'vendor')]
    from xi_core import load_and_decompress
    pe, text, section, base, _ = load_and_decompress(Path(path))
    if base != BASE:
        raise ValueError('unexpected client image base ' + hex(base))
    image = bytearray(pe.get_memory_mapped_image())
    image[section.VirtualAddress:section.VirtualAddress + len(text)] = text
    return bytes(image)


class ClientImage:
    def __init__(self, given, path, data, source):
        self.given = Path(given)           # the --image argument
        self.path = Path(path)             # a decoded image file a test process can read
        self.data = data
        self.source = source               # 'image' or 'dll'
        self.image_sha256 = digest(data)
        self.input_sha256 = digest(self.given.read_bytes()) if source == 'dll' else self.image_sha256
        # The DLL the image came from when it is known; otherwise the image itself.
        self.source_sha256 = self.input_sha256 if source == 'dll' else KNOWN.get(self.image_sha256, self.image_sha256)


_temporary = []


def _cleanup():
    for folder in _temporary:
        shutil.rmtree(folder, ignore_errors=True)


def _writable(folder):
    folder = Path(folder).resolve()
    if folder.as_posix().lower().startswith('c:/games'):
        raise ValueError('refusing to write a client image under C:/Games')
    return folder


def load(given, image_dir=None):
    given = Path(given)
    data = given.read_bytes()
    if is_mapped(data):
        if image_base(data) != BASE:
            raise ValueError('unexpected client image base ' + hex(image_base(data)))
        return ClientImage(given, given, data, 'image')
    image = decode(given)
    if image_dir is None:
        folder = Path(tempfile.mkdtemp(prefix='vantage-client-image-'))
        if not _temporary:
            atexit.register(_cleanup)
        _temporary.append(folder)
    else:
        folder = _writable(image_dir)
        folder.mkdir(parents=True, exist_ok=True)
    path = folder/('client-image-%s.bin' % digest(data)[:8])
    if path.resolve() in (OLD_IMAGE.resolve(), NEW_IMAGE.resolve()):
        raise ValueError('refusing to overwrite a verified client image')
    path.write_bytes(image)
    return ClientImage(given, path, image, 'dll')


def add_arguments(parser):
    parser.add_argument('--image', type=Path, default=OLD_IMAGE,
                        help='decoded client image or FFXiMain.dll (default: the verified f2245d1c image)')
    parser.add_argument('--image-dir', type=Path,
                        help='folder for the image decoded from a DLL (default: a temporary folder)')


def from_arguments(args):
    return load(args.image, args.image_dir)


def from_argv(argv=None):
    """For drivers that run inside another driver (runpy) and so share its command line."""
    parser = argparse.ArgumentParser(add_help=False)
    add_arguments(parser)
    args, _ = parser.parse_known_args(sys.argv[1:] if argv is None else argv)
    return from_arguments(args)


def inspect_namespace(image):
    """The read-only helpers the target drivers used from the research inspector."""
    sys.path.insert(0, str(RESEARCH/'vendor'))
    import re
    from capstone import Cs, CS_ARCH_X86, CS_MODE_32
    data, base = image.data, image_base(image.data)
    md = Cs(CS_ARCH_X86, CS_MODE_32)
    md.detail = True

    def va(off):
        return base + off

    def raw(addr):
        return addr - base

    def dis(addr, n=256):
        for i in md.disasm(data[raw(addr):raw(addr) + n], addr):
            print(f'{i.address:08X} {i.bytes.hex():24} {i.mnemonic:8} {i.op_str}')

    def xrefs(addr):
        pattern = struct.pack('<I', addr)
        return [va(m.start()) for m in re.finditer(re.escape(pattern), data)]

    return {'data': data, 'base': base, 'source_hash': image.source_sha256, 'md': md, 'va': va, 'raw': raw,
            'dis': dis, 'xrefs': xrefs}
