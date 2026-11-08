local previous_install=AshitaCore.GetInstallPath;
local install=MOCK_INSTALL_PATH:gsub('[\\/]+$','');
AshitaCore.GetInstallPath=function() return install..'///'; end;
local current=install..'/config/addons/vantage/';
package.loaded['core.identity']=nil;
local identity=require('core.identity');
assert(identity.name=='vantage' and identity.title=='Vantage');
assert(identity.root()==current,'Settings are kept in the Vantage settings directory');
assert(identity.relative()=='config/addons/vantage/');
assert(identity.path('profiles.json')==current..'profiles.json');
assert(identity.path('sounds/')==current..'sounds/');
assert(identity.relative('fonts')=='config/addons/vantage/fonts');
install=install..'/other';
assert(identity.root()==current,'The selected root does not change while the addon is loaded');
for _,command in ipairs({'/vantage','/vg','/VANTAGE','/VG'}) do
    assert(identity.command(command),'The command alias is recognized: '..command);
end;
for _,command in ipairs({'vantage','/vantages','/vgx','/vg ',''}) do
    assert(not identity.command(command),'Unrelated commands are not intercepted: '..command);
end;
assert(not identity.command(nil) and not identity.command({}));
AshitaCore.GetInstallPath=previous_install;package.loaded['core.identity']=nil;
