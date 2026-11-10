-- /vg report says whether the trace limits took, LuaJIT's own state, whether self timers have the game clock,
-- whether item recasts can be read, and the timings or why there are none.
local store=require('core.store');
local path=MOCK_INSTALL_PATH..'/config/addons/vantage/reports/latest.json';
local app=dofile(ADDON_DIR..'/vantage.lua');
MOCK.fire('load');app.refresh(1);
MOCK.fire('command',{command='/vg report'});
local report=assert(store.read(path));
assert(report.version=='1.1.0');
assert(report.jit.applied==true and report.jit.problem==nil and report.jit.maxtrace==12000 and report.jit.maxmcode==16384,
    'The trace limits take in this LuaJIT.');
assert(type(report.jit.enabled)=='boolean' and type(report.jit.flags)=='table','LuaJIT\'s own state is reported.');
assert(report.clock.available==false and report.clock.reason:find('without a countdown',1,true),
    'A client without the game clock says self timers show without a countdown.');
assert(report.item_recasts and report.item_recasts.reason,'Item recasts have a status line.');
-- Each Present starts the party icons' builds at their drawn size, and /vg report says what was made: the sizes kept
-- for each art, the textures made, the builds tried, the ones that drew the 32 px texture instead and the slowest build.
local sized=report.party_icon_sizes;
assert(type(sized)=='table' and type(sized.sizes)=='table' and sized.made==0 and sized.builds==0 and sized.fallbacks==0
    and sized.slowest_ms==0,'The report has the party icon sizes.');
local assets=require('ui.client_assets');
local icon_frame,frames=assets.icon_frame,0;
assets.icon_frame=function() frames=frames+1;return icon_frame();end;
for _=1,3 do MOCK.frame();end;
assets.icon_frame=icon_frame;
assert(frames==3,'Each Present starts the party icon builds.');
assert(report.performance.available==false and report.performance.reason:find('Timings are unavailable',1,true));
for _,key in ipairs({'native_target','native_status','native_target_effects','native_spell_info','native_loading','loading','target_frame','spell_information'}) do
    assert(report[key]==nil,key..' is not reported: Vantage replaces no game window.');
end;

-- A LuaJIT that refuses the limits says so, and Vantage runs as before.
local start=jit.opt.start;
jit.opt.start=function() error('Fixture refuses trace limits.'); end;
app=dofile(ADDON_DIR..'/vantage.lua');
jit.opt.start=start;
MOCK.fire('load');app.refresh(2);MOCK.frame();
MOCK.fire('command',{command='/vg report'});
report=assert(store.read(path));
assert(report.jit.applied==false and report.jit.problem:find('Fixture refuses trace limits.',1,true),
    'A refused limit is reported with its reason.');
assert(app.state.problem==nil,'Vantage draws on without the limits.');

-- An old report that is no longer JSON is replaced, as any old report is.
local old=assert(io.open(path,'wb'),'Fixture: the report opens.');
old:write('{"version":');old:close();
assert(store.read(path)==nil,'Fixture: the old report is not JSON.');
local said=#MOCK.printed;
MOCK.fire('command',{command='/vg report'});
report=store.read(path);
local message=MOCK.printed[said+1] or '';
assert(report and report.version=='1.1.0' and message:find('Report saved to',1,true),'A broken old report is replaced: '..message);
