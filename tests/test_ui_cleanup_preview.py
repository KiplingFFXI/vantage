"""Use actual ImGui input to keep placement and sample controls reachable while scrolling."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE=Path(__file__).resolve().parent
PREVIEW=HERE/'preview'
# preview.py takes Agave from Ashita.dll the first time it needs it.
AGAVE=(PREVIEW/'fonts/Agave_Regular.ttf').is_file() or (Path(os.environ['ASHITA_LIBS']).resolve().parent.parent/'Ashita.dll').is_file()


class UiCleanupPreviewTests(unittest.TestCase):
    def replay(self,page,width,font,height=800):
        lock,samples='Locked##frame','Show samples##frame'
        actions=[
            {'frame':5,'lua':'PREVIEW.cleanup_capture()'},
            {'frame':7,'mouse':[40+width/2,height-40],'wheel':-25},
            {'frame':10,'lua':'PREVIEW.cleanup_scrolled()'},
            {'frame':11,'target':lock,'down':True},
            {'frame':12,'down':False},
            {'frame':14,'lua':'PREVIEW.cleanup_check(false,false,1)'},
            {'frame':15,'target':samples,'down':True},
            {'frame':16,'down':False},
            {'frame':18,'lua':'PREVIEW.cleanup_check(false,true,2)'},
            {'frame':19,'target':lock,'down':True},
            {'frame':20,'down':False},
            {'frame':22,'lua':'PREVIEW.cleanup_check(true,true,3)'},
            {'frame':23,'target':samples,'down':True},
            {'frame':24,'down':False},
            {'frame':26,'lua':'PREVIEW.cleanup_check(true,false,4)'},
            {'frame':27,'mouse':[40+width/2,height-40],'wheel':25},
            {'frame':30,'lua':'PREVIEW.cleanup_top()'},
            {'frame':31,'target':'##find_settings','down':True},
            {'frame':32,'down':False},
            {'frame':33,'text':'lock'},
            {'frame':35,'lua':"assert(PREVIEW.search_value=='lock','The fixed search input remains reachable')"},
            {'frame':36,'target':'Clear search','down':True},
            {'frame':37,'down':False},
            {'frame':39,'lua':"assert(PREVIEW.search_value=='','Search clears normally')",'mouse':[-100,-100]},
        ]
        slug=page.lower().replace(' & ','-').replace(' ','-')
        output=HERE/'out/ui-cleanup'/f'{slug}-{width}-font{font}.png'
        with tempfile.TemporaryDirectory(prefix='vantage_cleanup_') as folder:
            inputs=Path(folder)/'input.json'
            inputs.write_text(json.dumps(actions),encoding='utf-8')
            result=subprocess.run([
                sys.executable,str(PREVIEW/'preview.py'),'--full','--frames','42','--size','1200','1000',
                '--window-size',str(width),str(height),'--tab',page,
                '--exec',f"PREVIEW.cleanup_page={json.dumps(page)}; PREVIEW.cleanup_font={font}",
                '--script',str(PREVIEW/'ui_cleanup.lua'),'--input-script',str(inputs),'--out',str(output),
            ],capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('Fixed header lock, preview, search and scrolling passed',result.stderr)
        self.assertTrue(output.is_file())

    # Labels beside their controls make this page short enough to fit an 800 pixel window.
    def test_party_normal(self): self.replay('Party & alliance',920,16,460)
    # So does the Recasts panel's Size and place tab.
    def test_recasts_normal(self): self.replay('Recasts',920,16,400)
    def test_party_narrow_24(self): self.replay('Party & alliance',560,24)
    # Its long tick wraps in Agave and not in the preview's fallback font.
    @unittest.skipUnless(AGAVE,'Agave is unavailable')
    def test_recasts_narrow_24(self): self.replay('Recasts',560,24,640)
    def test_party_narrow_36(self): self.replay('Party & alliance',560,36)
    def test_recasts_narrow_36(self): self.replay('Recasts',560,36)

    def test_short_menu_large_font(self):
        actions = [
            {'frame':5, 'lua':'PREVIEW.compact_capture()'},
            # One notch (80 px) brings the page's first row fully into view, and the same back up reaches the lock control.
            {'frame':7, 'mouse':[300,380], 'wheel':-0.5},
            {'frame':10, 'lua':'PREVIEW.compact_visible(); PREVIEW.compact_check(true,0)'},
            {'frame':11, 'mouse':[300,380], 'wheel':0.5},
            {'frame':14, 'lua':'PREVIEW.compact_back()'},
            {'frame':15, 'target':'Locked##frame', 'down':True},
            {'frame':16, 'down':False},
            {'frame':18, 'lua':'PREVIEW.compact_check(false,1)'},
            {'frame':19, 'target':'Locked##frame', 'down':True},
            {'frame':20, 'down':False},
            {'frame':22, 'lua':'PREVIEW.compact_check(true,2)', 'mouse':[-100,-100]},
        ]
        output = HERE/'out/ui-cleanup/compact-large-font.png'
        with tempfile.TemporaryDirectory(prefix='vantage_compact_') as folder:
            inputs = Path(folder)/'input.json'
            inputs.write_text(json.dumps(actions), encoding='utf-8')
            result = subprocess.run([
                sys.executable, str(PREVIEW/'preview.py'), '--full', '--frames', '25',
                '--size', '1200', '900', '--window-size', '560', '400', '--tab', 'Recasts',
                '--script', str(PREVIEW/'compact_settings.lua'), '--input-script', str(inputs), '--out', str(output),
            ], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn('Compact settings scroll, lock and customization checks passed', result.stderr)


if __name__=='__main__': unittest.main()
