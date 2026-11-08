-- Each Present compares the game's Direct3D device with the one it saw last. A new device clears and makes
-- again every texture Vantage owns; the first Present and an unchanged device clear nothing.
local icons=require('ui.icons');
local recasts=require('ui.recast_icons');
local assets=require('ui.client_assets');
local calls={};
for name,module in pairs({icons=icons,recasts=recasts,assets=assets}) do
    module.clear=function() calls[name]=(calls[name] or 0)+1; end;
    if module.prepare and name~='assets' then
        module.prepare=function() calls[name..'_prepare']=(calls[name..'_prepare'] or 0)+1; end;
    end;
end;
local device,reads=0x1000000,0;
AshitaCore.GetDirect3DDevice=function() reads=reads+1; return device; end;
local app=dofile(ADDON_DIR..'/vantage.lua');
MOCK.frame();MOCK.frame();
assert(reads==2 and next(calls)==nil,'The first device and an unchanged one clear no texture.');
local saved=require('core.store').copy(app.state.settings);
device=0x2000000;MOCK.frame();
assert(calls.icons==1 and calls.recasts==1 and calls.assets==1,
    'A new device clears every owned GPU texture cache.');
assert(calls.icons_prepare==1 and calls.recasts_prepare==1,
    'Icon loaders can acquire the new device.');
MOCK.frame();
assert(calls.icons==1 and calls.assets==1,'The new device is kept, so the next Present clears nothing.');
-- A device that can't be read is not taken for a new one.
device=nil;MOCK.frame();device=0;MOCK.frame();
AshitaCore.GetDirect3DDevice=function() error('Fixture device failure'); end;MOCK.frame();
assert(calls.icons==1 and calls.assets==1,'An unreadable device clears nothing.');
AshitaCore.GetDirect3DDevice=function() return 0x2000000; end;MOCK.frame();
assert(calls.icons==1,'The same device read again after a failure is not new.');
assert(require('core.customization').equal(saved,app.state.settings),
    'A graphics device change must not alter saved customization or frame locks.');
-- A rebuild that fails on a new device is reported once. The displays go on drawing, and the next frames don't
-- try the rebuild again.
icons.prepare=function() calls.icons_prepare=calls.icons_prepare+1; error('Fixture texture failure'); end;
local printed=#MOCK.printed;
AshitaCore.GetDirect3DDevice=function() return device; end;
device=0x3000000;MOCK.frame(0.2);
assert(calls.icons==2 and calls.icons_prepare==2,'The new device starts a rebuild.');
assert(#MOCK.printed==printed+1 and MOCK.printed[#MOCK.printed]:find('Fixture texture failure',1,true),
    'A failed rebuild is reported in one line.');
local sampled=app.state.sampled;
MOCK.frame(0.2);MOCK.frame(0.2);
assert(calls.icons==2 and calls.icons_prepare==2,'The rebuild is not tried again every frame.');
assert(app.state.sampled>sampled,'The displays keep updating after a failed rebuild.');
assert(#MOCK.printed==printed+1,'The failure is not repeated.');
