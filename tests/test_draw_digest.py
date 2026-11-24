"""Every draw call of the default look stays the same: positions, UVs, colors, clips and text over 120 frames.

tests/frame_harness.lua draws solo (fresh defaults), a 6-member party and an 18-member
alliance with the installed client art. A change meant to draw differently updates EXPECTED with the values this
test prints, and says why; a speed or cleanup change must leave them as they are. It also checks that the party
scenes list their members' effects by 0x076, as in play. Skipped without the client.
"""
from pathlib import Path
import os
import tempfile
import unittest

import benchmark_frame

GAME = Path(os.environ['ASHITA_LIBS']).resolve().parent.parent / 'SquareEnix/FINAL FANTASY XI'
# scenario: (draw calls, hash), recorded on the installed client.
EXPECTED = {
    'solo': (78000, 1232000184),
    'party6': (96240, 1836476962),
    'alliance18': (293640, 1232373777),
}


class DrawDigestTests(unittest.TestCase):
    def test_draw_calls_unchanged(self):
        if not (GAME / 'ROM/119/51.DAT').is_file():
            self.skipTest('No local client art')
        for scenario, expected in EXPECTED.items():
            with self.subTest(scenario=scenario):
                actual = benchmark_frame.digest(scenario)
                self.assertEqual(actual, expected, '%s draws %d calls, hash %d' % (scenario, *actual))

    def test_the_party_scenes_list_their_members_by_0x076(self):
        # In play the members' effects come by 0x076, and the game's party icons are read only until one comes. So once
        # the icons are emptied, a member still lists the effects its 0x076 gave, in each scene of a long session too.
        if not (GAME / 'ROM/119/51.DAT').is_file():
            self.skipTest('No local client art')
        listed = '''local id = ...; local found = 0;
            for _, member in ipairs(H.app.state.snapshot.party) do
                if member.id == id then found = #member.effects; end;
            end;
            return found;'''
        empty = '''local none = {}; for slot = 0, 31 do none[slot] = 255; end;
            AshitaCore:GetMemoryManager():GetParty().GetStatusIcons = function() return none; end;'''
        for scenario, scenes in (('party6', ()), ('alliance18', ()), ('party6', ('alliance18',)),
                                 ('alliance18', ('solo', 'party6'))):
            with self.subTest(scenario=scenario, scenes=scenes), \
                    tempfile.TemporaryDirectory(prefix='vantage_frame_') as folder:
                lua = benchmark_frame.harness(folder, scenario)
                H = lua.globals().H
                for scene in scenes:
                    H.scene(scene)
                H.run(60)
                each = 32 if (scenes or (scenario,))[-1] == 'alliance18' else 12
                count = lua.execute(listed, 1002)
                self.assertEqual(count, each, 'Fixture: member 1 lists %d effects' % count)
                lua.execute(empty)
                H.run(60)
                for member in range(1002, 1007):
                    count = lua.execute(listed, member)
                    self.assertEqual(count, each,
                                     'Member %d lists %d effects once the icons are empty' % (member, count))


if __name__ == '__main__':
    unittest.main()
