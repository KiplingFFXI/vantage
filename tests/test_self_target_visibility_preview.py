"""Exercise local timer visibility through real ImGui pointer input while targeting self."""
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest

HERE = Path(__file__).resolve().parent
PREVIEW = HERE / 'preview'
OUT = HERE / 'out/self-target-visibility'
CLIENT = Path(os.environ['ASHITA_LIBS']).resolve().parent.parent / 'SquareEnix/FINAL FANTASY XI'


class SelfTargetVisibilityInputTests(unittest.TestCase):
    def replay(self, page, actions, frames):
        OUT.mkdir(parents=True, exist_ok=True)
        inputs = OUT / (page.lower() + '-input.json')
        output = OUT / (page.lower() + '.png')
        inputs.write_text(json.dumps(actions), encoding='utf-8')
        command = [sys.executable, str(PREVIEW / 'preview.py'), '--full', '--hud', '--no-crop',
                   '--size', '1320', '850', '--frames', str(frames),
                   '--exec', "PREVIEW.visibility_page='" + page + "'",
                   '--script', str(PREVIEW / 'self_target_visibility.lua'),
                   '--input-script', str(inputs), '--out', str(output)]
        command.append('--client-assets' if (CLIENT / 'ROM/0/14.DAT').is_file() else '--icon-fixture')
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('OK window=', result.stdout)
        self.assertIn('Self-target local visibility: ' + page, result.stderr)
        self.assertTrue(output.is_file())

    def test_target_panel_toggle_undo_redo_keeps_self_status_visible(self):
        actions = [
            {'frame': 10, 'lua': "PREVIEW.visibility_capture(); PREVIEW.visibility_verify('target',true,true)"},
            {'frame': 11, 'target': 'On##frame_display', 'down': True},
            {'frame': 12, 'down': False},
            {'frame': 14, 'lua': "PREVIEW.visibility_verify('target',false)"},
            {'frame': 15, 'target': 'Undo', 'down': True},
            {'frame': 16, 'down': False},
            {'frame': 18, 'lua': "PREVIEW.visibility_verify('target',true,true)"},
            {'frame': 19, 'target': 'Redo', 'down': True},
            {'frame': 20, 'down': False},
            {'frame': 22, 'lua': "PREVIEW.visibility_verify('target',false)"},
            {'frame': 23, 'target': 'On##frame_display', 'down': True},
            {'frame': 24, 'down': False},
            {'frame': 26, 'lua': "PREVIEW.visibility_verify('target',true,true)"},
            {'frame': 27, 'mouse': [-100, -100]},
        ]
        self.replay('Display', actions, 29)

    def test_combined_recast_local_toggle_keeps_other_panels_visible(self):
        actions = [
            {'frame': 4, 'lua': "PREVIEW.visibility_capture(); PREVIEW.visibility_verify('recasts',true,true)"},
            {'frame': 5, 'target': 'On##frame_display', 'down': True},
            {'frame': 6, 'down': False},
            {'frame': 8, 'lua': "PREVIEW.visibility_verify('recasts',false)"},
            {'frame': 9, 'target': 'On##frame_display', 'down': True},
            {'frame': 10, 'down': False},
            {'frame': 12, 'lua': "PREVIEW.visibility_verify('recasts',true,true)"},
            {'frame': 13, 'mouse': [-100, -100]},
        ]
        self.replay('Recasts', actions, 15)


if __name__ == '__main__':
    unittest.main()
