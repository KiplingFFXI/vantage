"""Synthetic image records exercise the optional local-client preview adapter."""
from pathlib import Path
import importlib.util
import struct
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('vantage_preview_items', HERE / 'preview' / 'preview.py')
PREVIEW = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREVIEW)


def record(item=12511, size=0x1400):
    data = bytearray(size)
    struct.pack_into('<I', data, 0, item)
    struct.pack_into('<I', data, 0x280, 0x839)
    struct.pack_into('<IiiHHI', data, 0x295, 40, 32, 32, 1, 8, 0)
    palette = 0x295 + 40
    data[palette + 4:palette + 8] = bytes((30, 20, 10, 128))
    data[palette + 1024 + 31 * 32] = 1
    return data


def encode(data):
    return bytes(((value << 5) | (value >> 3)) & 255 for value in data)


class ItemPreviewTests(unittest.TestCase):
    def test_palette_orientation_and_black_color_key(self):
        for size in (0xC00, 0x1400):
            image = PREVIEW.decode_item_picture(encode(record(size=size)), 12511)
            self.assertEqual(image.size, (32, 32))
            self.assertEqual(image.getpixel((0, 0)), (10, 20, 30, 255))
            self.assertEqual(image.getpixel((0, 31)), (0, 0, 0, 0))

    def test_malformed_records_are_rejected(self):
        for offset, fmt, value in ((0, '<I', 1), (0x280, '<I', 0x981), (0x280, '<I', 40),
                                   (0x299, '<i', 64), (0x29D, '<i', -32), (0x2A3, '<H', 32)):
            bad = record()
            struct.pack_into(fmt, bad, offset, value)
            with self.assertRaises(ValueError):
                PREVIEW.decode_item_picture(encode(bad), 12511)
        with self.assertRaises(ValueError):
            PREVIEW.decode_item_picture(bytes(20), 12511)

    def test_bounded_record_seek_for_both_client_formats(self):
        for size in (0xC00, 0x1400):
            with tempfile.TemporaryDirectory(prefix='vantage_item_preview_') as folder:
                root = Path(folder)
                table = bytearray((0xD974 + 1) * 2)
                struct.pack_into('<H', table, 0x004C * 2, 1)
                struct.pack_into('<H', table, 0xD974 * 2, 2)
                (root / 'FTABLE.DAT').write_bytes(table)
                (root / 'ROM' / '0').mkdir(parents=True)
                source = root / 'ROM' / '0' / '1.DAT'
                source.write_bytes(encode(record(12510, size)) + encode(record(12511, size)))
                (root / 'ROM' / '0' / '2.DAT').write_bytes(encode(record(27786, size)))
                picture, path = PREVIEW.read_item_picture(root, 12511)
                self.assertEqual(picture.size, (32, 32))
                self.assertEqual(Path(path), source)
                self.assertEqual(PREVIEW.read_item_picture(root, 27786)[0].size, (32, 32))
                with self.assertRaises(ValueError):
                    PREVIEW.read_item_picture(root, 65535)
                with self.assertRaises(ValueError):
                    PREVIEW.read_item_picture(root, True)


if __name__ == '__main__':
    unittest.main()
