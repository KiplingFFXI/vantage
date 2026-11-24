"""The rows of tests/benchmark_runtime.py measure what docs/PERFORMANCE.md says they do.

The measured batch goes on from where the warm-up left the clock, so the idle and bursts rows refresh on the 0.1 s
gate from their first frame. Each burst's 0x037s are long enough for the client to read their status icons, and the first of
each burst changes them, so it wakes a refresh. A short batch still reads a time above zero.
"""
import tempfile
import unittest

import benchmark_runtime
import run

COUNT = 60

# Counts the 0x037s whose status icons changed, which is what wakes a refresh.
WOKEN = r'''
local client = require('core.client');
local changed = client.icons_changed;
client.icons_changed = function(...)
    local value = changed(...);
    if value then BENCH.stage.woken = (BENCH.stage.woken or 0) + 1; end
    return value;
end;
'''


class RuntimeBenchmarkTests(unittest.TestCase):
    def test_the_rows_measure_what_the_notes_say(self):
        problems = []
        result = benchmark_runtime.benchmark(COUNT, 1)
        for row in result['results']:
            if row['cpu_us_per_iteration_median'] <= 0:
                problems.append('%s %s reads %.3f us an iteration' % (row['scenario'], row['mode'],
                                                                       row['cpu_us_per_iteration_median']))
            if row['mode'] in ('idle', 'bursts') and row['stage_calls'].get('client', 0) < COUNT // 7:
                problems.append('%s %s refreshed %d times in %d frames' % (row['scenario'], row['mode'],
                                                                         row['stage_calls'].get('client', 0), COUNT))
        with tempfile.TemporaryDirectory(prefix='vantage_benchmark_') as folder:
            lua = run.runtime(folder)
            lua.execute(benchmark_runtime.SETUP)
            lua.execute(WOKEN)
            bench = lua.globals().BENCH
            bench.configure('alliance')
            bench.run(120, 'bursts')
            bench.clear()
            bench.run(COUNT, 'bursts')
            woken = bench.stage.woken or 0
            if woken != COUNT // 6:
                problems.append('%d bursts woke %d refreshes' % (COUNT // 6, woken))
        self.assertEqual(problems, [])


if __name__ == '__main__':
    unittest.main()
