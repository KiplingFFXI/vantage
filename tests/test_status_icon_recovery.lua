local original_require = require
local now, clock_reads, attempts, resource_reads = 0, 0, 0, 0
local available = false
os.clock = function() clock_reads = clock_reads + 1; return now end
require = function(name)
    if name == 'd3d8' then
        attempts = attempts + 1
        if not available then error('Texture support is temporarily unavailable.') end
        return {get_device=function() return nil end}
    end
    return original_require(name)
end
AshitaCore.GetResourceManager = function()
    return {GetStatusIconByIndex=function() resource_reads = resource_reads + 1; return nil end}
end
local icons = require('ui.icons')
assert(icons.status(33) == nil and attempts == 1)
available = true
now = 29
assert(icons.status(34) == nil and attempts == 1, 'Library failures are not retried for every missing icon.')
now = 30
assert(icons.status(33) == nil and attempts == 2 and resource_reads == 1,
    'Status icons recover texture support after the same bounded retry as job and item icons.')
local loads, releases = 0, 0
icons._set_loader_for_tests(function()
    loads = loads + 1
    return 900, function() releases = releases + 1 end
end)
assert(icons.status(35) == 900 and loads == 1)
local clocks = clock_reads
for _ = 1, 120 do assert(icons.status(35) == 900) end
assert(clock_reads == clocks and loads == 1, 'Ready status icons do not read clocks or attempt uploads each frame.')
icons.clear()
assert(releases == 1)
icons._set_loader_for_tests(nil)
assert(icons.status(33) == nil and attempts == 3, 'Clearing textures also resets the library lifetime.')
