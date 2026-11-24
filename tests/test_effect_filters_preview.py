"""Exercise the shared status-filter editor with real ImGui pointer input."""
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
class EffectFilterInputTests(unittest.TestCase):
    def test_shared_filter_editor(self):
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

        def select(label, choice):
            click('##' + label)
            click(choice)

        def button(text):
            return text + '###' + text + '##frame'

        # Opens an effect list, types in the box at its top, and picks what it finds.
        def choose(text, choice, label='Effect'):
            nonlocal frame
            click('##' + label)
            click('##effect_search_' + label)
            actions.append({'frame': frame, 'text': text})
            frame += 3
            click(choice)

        click('Hide list', 'PREVIEW.check_route()')
        choose('Level Sync', 'Level Sync##effect_269')
        click(button('Hide it everywhere'), 'PREVIEW.check_sync()')
        click('Hide only for some players or jobs##Conditional hide rules')
        click(button('Add a rule'), 'PREVIEW.check_added()')
        choose('Haste', 'Haste##effect_33', 'Effect##_rule')
        actions.append({'frame': frame, 'lua': 'PREVIEW.check_rule_effect(33)'})
        frame += 2
        select('Effect##_rule', 'Any effect##all')
        select('frame_Buffs or debuffs', 'Debuffs##debuff')
        select('frame_Who', 'Alliance 2##alliance2')
        click('##frame_Player name')
        actions.append({'frame': frame, 'text': 'Fennel'})
        frame += 3
        select('frame_Main job_rule', 'WHM##3')
        actions.append({'frame': frame, 'lua': 'PREVIEW.check_conditions()'})
        frame += 2
        click('Use this rule##frame', 'PREVIEW.check_enabled()')
        click('Undo', 'PREVIEW.check_undo()')
        click('Redo', 'PREVIEW.check_enabled()')
        # Hiding what's already on the list adds nothing, and Remove takes it off in one step.
        choose('Signet', 'Signet##effect_253')
        click(button('Hide it everywhere'), 'PREVIEW.check_signet(1)')
        click(button('Hide it everywhere'), 'PREVIEW.check_signet(1)')
        click('Remove##effect', 'PREVIEW.check_signet(0)')
        select('frame_Rule', 'Any effect / Fennel / WHM / Alliance 2##2')
        actions.append({'frame': frame, 'mouse': [-100, -100]})
        output = HERE / 'out' / 'effect-filters' / 'shared-filter-editor.png'
        with tempfile.TemporaryDirectory(prefix='vantage_effect_filters_') as folder:
            inputs = Path(folder) / 'input.json'
            inputs.write_text(json.dumps(actions), encoding='utf-8')
            result = subprocess.run([
                sys.executable, str(PREVIEW / 'preview.py'), '--full', '--client-assets',
                '--frames', str(frame + 4), '--size', '1440', '1760', '--window-size', '1060', '1560',
                '--tab', 'Home', '--script', str(PREVIEW / 'effect_filters_interaction.lua'),
                '--input-script', str(inputs), '--out', str(output),
            ], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Hide list: top bar route, one rule for each effect, recipient rules and Undo/Redo passed.', result.stderr)
        self.assertTrue(output.is_file())


if __name__ == '__main__':
    unittest.main()
