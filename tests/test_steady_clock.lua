-- The waits that time a message, a cache or a retry count in seconds on the frame timings' counter, which keeps
-- counting after the game's os.clock stops at about 24.86 days. Without that counter they use os.clock, read at each
-- call.
local real_clock = os.clock
os.clock = function() return -0.001 end
local counter = 2500
package.loaded['core.performance'] = { now = function() return counter end }
package.loaded['core.steady'] = nil
local steady = require('core.steady')
assert(steady() == 2.5, 'Seconds from the counter\'s milliseconds.')
counter = 90000
assert(steady() == 90, 'It keeps counting while os.clock is stuck.')

package.loaded['core.performance'], package.loaded['core.steady'] = nil, nil
package.preload['core.performance'] = function() error('Timings are unavailable on this system.', 0) end
steady = require('core.steady')
local now = 12
os.clock = function() return now end
assert(steady() == 12, 'Without the counter it reads os.clock.')
now = 13
assert(steady() == 13, 'os.clock is read at each call, so a stand-in for it is seen.')
package.preload['core.performance'], package.loaded['core.steady'] = nil, nil
os.clock = real_clock
return 'The steady clock for waits'
