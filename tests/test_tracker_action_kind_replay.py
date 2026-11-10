"""What put an effect on (action_kind) stays with the cast it came with, wherever the tracker moves a cast.

Only effects from job abilities goes by it (core/catalog.lua from_ability), so a copy that kept another cast's kind, or
lost its own, would show or hide wrongly. This plays every tracker fixture again with each cast marked by its caster
and action, and checks at each view that a row with a caster or an action has the kind its cast came with, and a row
with neither has none. Weakness and Reraise from a raise take their caster from the raise and no kind. The list in
data/ability_effects.lua has neither, so they hide with the tick on either way.
"""
import tempfile
import unittest
from pathlib import Path

import run

HERE = Path(__file__).resolve().parent
WEAKNESS, RERAISE = 1, 113

# Wraps each tracker the fixture makes, once it requires core.tracker itself, so one that sets up core.catalog first
# still gets its own.
HOOK = r'''
local kinds, problems = {}, {};
local function mark(source, spell) return tostring(source) .. ':' .. tostring(spell); end
local function wrap(module)
    local new = module.new;
    module.new = function(...)
        local tracker = new(...);
        local observe, view = tracker.observe, tracker.view;
        tracker.observe = function(self, observations, ...)
            for _, o in ipairs(type(observations) == 'table' and observations or {}) do
                if type(o) == 'table' and (o.source ~= nil or o.spell ~= nil) then
                    if o.action_kind == nil then o.action_kind = mark(o.source, o.spell); end
                    kinds[mark(o.source, o.spell)] = o.action_kind;
                end
            end
            return observe(self, observations, ...);
        end;
        tracker.view = function(self, ...)
            local result = view(self, ...);
            for _, row in ipairs(type(result) == 'table' and result.rows or {}) do
                local wanted = (row.source ~= nil or row.spell ~= nil) and kinds[mark(row.source, row.spell)] or nil;
                local raised = (row.effect == %d or row.effect == %d) and row.action_kind == nil;
                if row.domain ~= 'recast' and row.action_kind ~= wanted and not raised then
                    if #problems < 5 then
                        problems[#problems + 1] = 'effect ' .. tostring(row.effect) .. ' from ' .. mark(row.source, row.spell)
                            .. ' has ' .. tostring(row.action_kind) .. ', not ' .. tostring(wanted);
                    end
                end
            end
            return result;
        end;
        return tracker;
    end;
end
local original = require;
require = function(name)
    local fresh = package.loaded[name] == nil;
    local value = original(name);
    if fresh and name == 'core.tracker' then wrap(value); end
    return value;
end;
return problems;
''' % (WEAKNESS, RERAISE)


class ActionKindReplayTests(unittest.TestCase):
    def test_every_tracker_fixture_keeps_the_kind_with_its_cast(self):
        names = sorted(path.name for path in HERE.glob('test_tracker_*.lua'))
        self.assertGreater(len(names), 40, 'The tracker fixtures are where they were.')
        for name in names:
            with self.subTest(fixture=name), tempfile.TemporaryDirectory(prefix='vantage_kind_') as folder:
                lua = run.runtime(folder)
                problems = lua.execute(HOOK)
                lua.execute('dofile(...)', (HERE / name).as_posix())
                self.assertEqual(list(problems.values()), [])


if __name__ == '__main__':
    unittest.main()
