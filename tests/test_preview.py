"""Replay actual ImGui mouse input in a hidden renderer, without the game."""
from pathlib import Path
import os
import subprocess
import sys
import unittest

HERE = Path(__file__).resolve().parent
PREVIEW = HERE / 'preview'
OUTPUT = HERE / 'out'
CLIENT_ROOT = Path(os.environ['ASHITA_LIBS']).resolve().parent.parent / 'SquareEnix' / 'FINAL FANTASY XI'


class PreviewInputTests(unittest.TestCase):
    def render(self, name, *arguments):
        output = OUTPUT / (name + '.png')
        result = subprocess.run([sys.executable, str(PREVIEW / 'preview.py'),
                                 '--out', str(output), *arguments],
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('OK window=', result.stdout)
        self.assertTrue(output.is_file())

    def test_alert_creation_and_test_action(self):
        self.render('alert-editor', '--tab', 'Display', '--frames', '13',
                    '--exec', "require('ui.panel_frame').open('notices', 'show')",
                    '--input-script', str(PREVIEW / 'alert_input.json'))

    def test_locked_drag_typing_guard_and_resize(self):
        self.render('panel-gestures', '--hud', '--frames', '18', '--no-crop', '--set', 'panels.self_buffs.mode=bars',
                    '--input-script', str(PREVIEW / 'drag_input.json'))

    def test_full_entrypoint_render(self):
        self.render('settings-full', '--full')

    def test_replay_targets_only_what_the_last_frame_drew(self):
        output = OUTPUT / 'stale-target.png'
        result = subprocess.run([sys.executable, str(PREVIEW / 'preview.py'), '--out', str(output), '--hud', '--frames', '8',
                                 '--script', str(PREVIEW / 'stale_target_interaction.lua'),
                                 '--input-script', str(PREVIEW / 'stale_target_input.json')],
                                capture_output=True, text=True, timeout=60)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Input target not drawn last frame: ##gone', result.stdout + result.stderr)

    def test_settings_files_decode_as_vantage_reads_them(self):
        # Vantage's own json.lua (core.json) refuses what the game folder's copy lets through, like a trailing comma.
        self.render('strict-json', '--frames', '1',
                    '--exec', "local json = require('json'); assert(not pcall(json.decode, '{\"version\":1,}') "
                    "and not pcall(json.decode, '[1,2,]') and json.decode('[1,2]')[2] == 2, 'The preview decodes JSON "
                    "with the strict json.lua')")

    def test_native_party_strip_drag_and_passive_clicks(self):
        self.render('native-party-gestures', '--hud', '--icon-fixture', '--size', '1280', '800', '--frames', '25',
                    '--script', str(PREVIEW / 'native_party_interaction.lua'),
                    '--input-script', str(PREVIEW / 'native_party_input.json'))

    @unittest.skipUnless((CLIENT_ROOT / 'ROM/0/14.DAT').is_file() and
                         (CLIENT_ROOT / 'ROM/119/51.DAT').is_file(), 'Local FFXI client artwork is unavailable')
    def test_native_appearance_button_preserves_layout_and_undo(self):
        self.render('native-appearance-input', '--full', '--client-assets', '--tab', 'Home',
                    '--window-size', '700', '850', '--frames', '20',
                    '--exec', "settings.style.minimal=true; settings.style.font='Agave'; "
                    "settings.panels.self_buffs.x=321; settings.panels.self_buffs.y=222; "
                    "settings.panels.self_buffs.filter='Haste'; settings.panels.self_buffs.include[33]=true; "
                    "settings.panels.self_buffs.exclude[40]=true; settings.panels.self_buffs.gradient=true; "
                    "settings.panels.self_buffs.colors.label={0.2,0.4,0.6,1}; "
                    "settings.panels.future_panel={zz_newer=1}; "
                    "PREVIEW.original_style=require('core.store').copy(settings.style)",
                    '--input-script', str(PREVIEW / 'client_appearance_input.json'))

    @unittest.skipUnless((CLIENT_ROOT / 'ROM/0/21.DAT').is_file() and
                         (CLIENT_ROOT / 'ROM/119/51.DAT').is_file(), 'Local FFXI client artwork is unavailable')
    def test_native_menu_fonts_skin_popup_typing_and_undo(self):
        self.render('native-menu-input', '--full', '--client-assets', '--tab', 'Help',
                    '--window-size', '700', '1000', '--frames', '48',
                    '--exec', "settings.panels.self_buffs.mode='bars'",
                    '--input-script', str(PREVIEW / 'client_menu_input.json'))


if __name__ == '__main__':
    unittest.main()
