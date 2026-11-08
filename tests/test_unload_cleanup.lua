local icons=require('ui.icons');
local recasts=require('ui.recast_icons');
local sound=require('core.sound');
local calls={};
sound.close=function() calls.sound=true; error('fixture restoration failure'); end;
icons.clear=function() calls.icons=true; end;
recasts.clear=function() calls.recasts=true; end;
dofile(ADDON_DIR..'/vantage.lua');
MOCK.fire('unload');
assert(calls.sound and calls.icons and calls.recasts,
    'One failed cleanup must not leave the other displays or resources open.');
local reported=false;
for _,message in ipairs(MOCK.printed) do
    if message:find('fixture restoration failure',1,true) then reported=true; end;
end;
assert(reported,'Cleanup failures remain visible.');
calls={};
local original_print=print;
print=function()error('fixture chat failure');end;
local closed=pcall(MOCK.fire,'unload');
print=original_print;
assert(closed and calls.sound and calls.icons and calls.recasts,
    'Unavailable chat output cannot interrupt the remaining unload cleanup.');
