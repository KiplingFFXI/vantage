"""Check the main page with actual ImGui pointer input at narrow and wide settings sizes."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
PREVIEW = HERE / 'preview'
CLIENT = Path(os.environ['ASHITA_LIBS']).resolve().parent.parent / 'SquareEnix' / 'FINAL FANTASY XI'


@unittest.skipUnless(CLIENT.is_dir(), 'Local client files are unavailable')
class MainPageInputTests(unittest.TestCase):
    def replay(self, width, font_size=16, height=960):
        actions = []
        frame = 5

        def click(label, check=None):
            nonlocal frame
            actions.extend([
                {'frame': frame, 'target': label, 'down': True},
                {'frame': frame + 1, 'down': False},
            ])
            if check:
                actions.append({'frame': frame + 3, 'lua': check})
            frame += 5

        actions.append({'frame': frame, 'lua': 'PREVIEW.capture()'})
        frame += 1
        click('Self buffs##main_self_buffs', 'PREVIEW.check_toggle()')
        click('Undo', 'PREVIEW.check_baseline()')
        click('Spells##main_recast_spell', 'PREVIEW.check_recast()')
        click('Undo', 'PREVIEW.check_baseline()')
        click('Party list buffs##main_party_ui', 'PREVIEW.check_party()')
        click('Edit##main_party_ui', "PREVIEW.check_page('Display'); PREVIEW.check_panel('party_ui/show')")
        click('Buffs only##frame_Show_kinds_buff', 'PREVIEW.check_kind()')
        click('Undo')
        click('Undo', 'PREVIEW.check_baseline()')
        click('< Back##frame', "PREVIEW.check_page('Home')")
        # Down to How it looks, which a large font pushes past the end of the window.
        actions.extend([
            {'frame': frame, 'mouse': [100 + width * 0.6, 500], 'wheel': -4},
            {'frame': frame + 3, 'lua': 'PREVIEW.check_look_rows()'},
        ])
        frame += 4
        click('More look', "PREVIEW.check_section('More look', true)")
        click('More look', "PREVIEW.check_section('More look', false)")
        click('1.5x##main_size', 'PREVIEW.check_size()')
        click('Undo', 'PREVIEW.check_baseline()')
        click('Redo', 'PREVIEW.check_size()')
        click('Undo', 'PREVIEW.check_baseline()')
        # A long page, scrolled, so the way back has something to leave behind. Help is long with its folds open.
        folds = "{'Reading a timer','What can be tracked','Alerts','Move and customize','Files and behavior'}"
        actions.extend([
            {'frame': frame, 'lua': "settings.window.tab='Help'; for _, name in ipairs(%s) do settings.window.sections['Help/'..name]=true; end" % folds},
            {'frame': frame + 2, 'mouse': [100 + width * 0.6, 500], 'wheel': -24},
            {'frame': frame + 4, 'lua': "assert(PREVIEW.page_scroll>50,'The page must actually scroll before testing navigation')"},
        ])
        frame += 5
        click('< Back##frame', 'PREVIEW.check_top()')
        actions.append({'frame': frame, 'mouse': [-100, -100]})
        suffix = '' if font_size == 16 else f'-font{font_size}'
        with tempfile.TemporaryDirectory(prefix='vantage_main_input_') as folder:
            output = Path(folder) / f'main-page-{width}{suffix}.png'
            inputs = Path(folder) / 'input.json'
            inputs.write_text(json.dumps(actions), encoding='utf-8')
            result = subprocess.run([
                sys.executable, str(PREVIEW / 'preview.py'), '--full', '--client-assets',
                '--frames', str(frame + 5), '--size', '1440', str(height + 160), '--window-size', str(width), str(height),
                '--exec', f'PREVIEW.expected_menu_font_size={font_size}',
                '--tab', 'Home', '--script', str(PREVIEW / 'main_page_navigation.lua'),
                '--input-script', str(inputs), '--out', str(output),
            ], capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('OK window=', result.stdout)
            self.assertIn('Main page switches, folds, Size and navigation passed.', result.stderr)
            self.assertTrue(output.is_file())

    def test_main_page_wide(self):
        self.replay(1220)

    def test_main_page_narrow(self):
        self.replay(660)

    def test_main_page_larger_font(self):
        self.replay(1220, font_size=36, height=1600)


if __name__ == '__main__':
    unittest.main()
