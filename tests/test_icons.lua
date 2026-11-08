local requests,now=0,100
local original_clock=os.clock
os.clock=function() return now end
package.preload.d3d8=function() return {get_device=function() return nil end} end
local resources={GetStatusIconByIndex=function() requests=requests+1;return nil end}
AshitaCore.GetResourceManager=function() return resources end
local icons=require('ui.icons')
for _,id in ipairs({-1,1024,1.5,math.huge,0/0}) do assert(icons.status(id)==nil) end
assert(requests==0,'Malformed icon IDs never reach the native resource lookup.')
assert(icons.status(33)==nil and requests==1)
assert(icons.status(33)==nil and requests==1,'A missing icon is not queried every frame.')
now=129;assert(icons.status(33)==nil and requests==1)
now=130;assert(icons.status(33)==nil and requests==2,'A transient missing resource is retried after its cooldown.')
icons.clear();assert(icons.status(33)==nil and requests==3)
local releases, loads = 0, 0
icons._set_loader_for_tests(function(id)
    loads = loads + 1
    return id == 89 and 0 or 788, function() releases = releases + 1 end
end)
assert(icons.status(88) == 788 and icons.status(88) == 788 and loads == 1)
assert(icons.status(89) == nil and releases == 1, 'An invalid uploaded client image releases its returned texture.')
icons.clear(); assert(releases == 2, 'The existing Client artwork also releases its cached GPU texture at unload.')
icons.clear(); assert(releases == 2, 'Repeated cleanup cannot release a client image twice.')
-- From the first Present on, up to 8 new icon textures are made in each (client_assets.spend_upload). A Client icon
-- past them draws nothing in this Present, is not counted as missing, and is made in the next.
local real_assets = require('ui.client_assets')
real_assets.icon_frame()
loads = 0
for id = 100, 107 do assert(icons.status(id) == 788) end
assert(icons.status(108) == nil and loads == 8, 'The ninth new icon waits for the next Present.')
assert(icons.status(100) == 788 and loads == 8, 'Icons made already draw while others wait.')
real_assets.icon_frame()
assert(icons.status(108) == 788 and loads == 9, 'It is made in the next Present, with no retry delay.')
icons.clear()
local icon_requests, pack_reason, recovered = 0, nil, false
package.loaded['ui.client_assets'] = {
    prepare_icons = function() error('Settings must not trigger file reads.') end,
    clear_icons = function() end,
    spend_upload = function() return true end,
    icon_texture = function(kind, id)
        icon_requests = icon_requests + 1
        if recovered and kind == 'xiview' then return { id = 991 } end
        return nil, 'This status index is not present in the selected artwork.'
    end,
    icon_status = function() return { available = true, count = 640, reason = pack_reason } end,
}
assert(icons.reason('XI View') == nil, 'An available pack does not claim a fallback before one is observed.')
assert(icons.status(640, 'XI View') == 788)
local observed = icons.artwork_status('XI View')
assert(observed.available and observed.using == 'XI View' and observed.fallbacks == 1,
    'A missing record does not mark the entire artwork pack unavailable.')
assert(observed.reason:find('Some effects use other artwork', 1, true) and not observed.reason:find('640', 1, true) and observed.reason:find('not present', 1, true)
    and observed.reason:find('Using Client artwork', 1, true), 'Settings explain an observed missing-image fallback.')
local previous_requests, previous_loads = icon_requests, loads
for _ = 1, 10 do assert(icons.reason('XI View') == observed.reason) end
assert(icon_requests == previous_requests and loads == previous_loads,
    'Pack-level fallback notices inspect only bounded cached results.')
pack_reason = 'Device unavailable. Some status images are using fallback artwork.'
local combined = icons.reason('XI View')
assert(combined:find('Device unavailable', 1, true) and combined:find('Some effects use other artwork', 1, true),
    'Observed missing records do not replace the existing GPU upload failure summary.')
pack_reason, recovered = nil, true
assert(icons.status(640, 'XI View') == 991 and icons.reason('XI View') == nil,
    'A successful retry removes the recovered image from the fallback summary.')
recovered = false; icons.status(641, 'XI View')
assert(icons.reason('XI View'))
icons.clear(); assert(icons.reason('XI View') == nil, 'Unload clears observed fallback notices.')
os.clock=original_clock
