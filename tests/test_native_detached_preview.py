"""Exercise detached native buff panels using actual Dear ImGui mouse input."""
import json
from pathlib import Path
import subprocess
import sys
import unittest

HERE = Path(__file__).resolve().parent


class NativeDetachedInputTests(unittest.TestCase):
    def test_edges_detach_and_snap(self):
        actions = []
        frame = 1
        for edge, point, delta in [
            ('left', [0.002, 0.5], [-30, 0]), ('right', [0.998, 0.5], [30, 0]),
            ('top', [0.5, 0.002], [0, -20]), ('bottom', [0.5, 0.998], [0, 20]),
            ('top_left', [0.002, 0.002], [-30, -20]), ('top_right', [0.998, 0.002], [30, -20]),
            ('bottom_left', [0.002, 0.998], [-30, 20]), ('bottom_right', [0.998, 0.998], [30, 20]),
        ]:
            width = 330 if delta[0] else 300
            height = 260 if delta[1] else 240
            actions.extend([
                {'frame': frame, 'shift': True, 'lua': "PREVIEW.native_reset(); settings.party_ui.strips.alliance1=false; settings.party_ui.strips.alliance2=false"},
                {'frame': frame+1, 'target': '##native_move_1', 'point': point, 'down': True},
                {'frame': frame+2, 'delta': delta}, {'frame': frame+4, 'down': False},
                {'frame': frame+5, 'lua': f"local p=PREVIEW.native_plan(); assert(p.width=={width} and p.height=={height},'{edge} dimensions'); assert(PREVIEW.native_starts==1 and PREVIEW.native_ends==1 and PREVIEW.native_saves==1,'one edit {edge}')"},
            ])
            frame += 7
        actions.extend([
            {'frame': frame, 'lua': "PREVIEW.native_reset(); local g=settings.party_ui.groups[1]; g.native_detached=false; g.native_x=0; g.native_y=0; PREVIEW.native_before=PREVIEW.native_plan()"},
            {'frame': frame+1, 'target': '##native_move_1', 'point': [0.5, 0.998], 'down': True},
            {'frame': frame+2, 'delta': [0, 40]}, {'frame': frame+4, 'down': False},
            {'frame': frame+5, 'lua': "local g=settings.party_ui.groups[1]; local p=PREVIEW.native_plan(); assert(not g.native_detached and g.native_y==40 and p.height==PREVIEW.native_before.height and p.y==PREVIEW.native_before.y+40,'an attached edge only moves')"},
            {'frame': frame+7, 'lua': "PREVIEW.native_reset(); local g=settings.party_ui.groups[1]; g.detached_x=PREVIEW.native_geometry.groups[1].x-settings.party_ui.native.gap-g.detached_width-30; g.detached_y=PREVIEW.native_geometry.groups[1].y; settings.party_ui.native.snap=true"},
            {'frame': frame+8, 'target': '##native_move_1', 'point': [0.5, 0.5], 'down': True},
            {'frame': frame+9, 'delta': [30, 0]}, {'frame': frame+11, 'down': False},
            {'frame': frame+12, 'lua': "local g=settings.party_ui.groups[1]; assert(not g.native_detached and g.native_side=='left' and g.native_x==0 and g.native_y==0,'release snaps to own game window'); assert(PREVIEW.native_saves==1,'snapping shares the drag edit')"},
            {'frame': frame+14, 'shift': False, 'mouse': [250, 200], 'lua': 'PREVIEW.native_reset()'},
            {'frame': frame+16, 'wheel': -3},
            {'frame': frame+19, 'lua': "assert(PREVIEW.native_scroll>0,'ordinary mouse wheel scrolls detached content'); assert(PREVIEW.native_saves==0,'scroll is not a layout edit')"},
        ])
        output = HERE / 'out' / 'native-detached'
        output.mkdir(parents=True, exist_ok=True)
        events = output / 'input.json'
        events.write_text(json.dumps(actions), encoding='utf-8')
        result = subprocess.run([
            sys.executable, str(HERE/'preview/preview.py'), '--hud', '--no-crop', '--icon-fixture',
            '--size', '1440', '900', '--frames', str(frame+22),
            '--script', str(HERE/'preview/native_detached_interaction.lua'),
            '--input-script', str(events), '--out', str(output/'input.png'),
        ], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn('OK window=', result.stdout)


if __name__ == '__main__':
    unittest.main()
