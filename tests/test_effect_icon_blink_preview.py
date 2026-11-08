"""Render expiry blinking with real ImGui and client artwork, asserting actual draw tints."""
from pathlib import Path
import os
import subprocess
import sys
import unittest

HERE=Path(__file__).resolve().parent
OUT=HERE/'out/effect-icon-blink'
INSTALL=Path(os.environ['ASHITA_LIBS']).resolve().parent.parent
CLIENT=INSTALL/'SquareEnix/FINAL FANTASY XI'
VIEW=INSTALL/'polplugins/DATs/XiView-Standard'

@unittest.skipUnless((CLIENT/'ROM/119/51.DAT').is_file() and (VIEW/'ROM/119/51.DAT').is_file(),
                     'Local client and XI View files are unavailable')
class EffectIconBlinkPreviewTests(unittest.TestCase):
    def test_real_stock_xiview_half_full_and_repeated_brightness(self):
        OUT.mkdir(parents=True,exist_ok=True)
        output=OUT/'blink-gallery.png'
        result=subprocess.run([sys.executable,str(HERE/'preview/preview.py'),'--hud','--no-crop',
            '--frames','4','--size','1380','930','--client-assets',
            '--client-xiview-root',str(VIEW),
            '--script',str(HERE/'preview/effect_icon_blink.lua'),'--out',str(output)],
            capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('OK window=',result.stdout)
        self.assertIn('repeated draws stable',result.stderr)
        self.assertTrue(output.is_file())

if __name__=='__main__':unittest.main()
