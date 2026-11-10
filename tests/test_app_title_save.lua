-- A change made at the title screen, before a character loads, has no file to go to, and the character's saved
-- settings replace it when it loads. Vantage says so and leaves it there: it doesn't try to save it again every frame,
-- which made the settings window and the displays work their looks out again each frame.
local store=require('core.store');
local SNAP={valid=false,id=1001,name='Tester',zone=102,job=1,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(SNAP);end};
package.loaded['core.observer']={read=function()return {};end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
local function frames(count)for _=1,count do MOCK.frame(1/60);end;end;
MOCK.fire('load');app.refresh(0);frames(10);
command('/vg');frames(5);
assert(not app.state.identity and app.state.settings_window_shown,'Fixture: the settings window is open at the title screen.');
for _,size in ipairs({15,17}) do
    command('/vg set style.font_size '..size);
    -- A save waits 0.6 s after a change.
    frames(60);
    local revision=app.state.settings_revision;
    frames(120);
    assert(app.state.settings_revision==revision,
        ('Two seconds at the title screen after a change move the settings revision by %d.'):format(app.state.settings_revision-revision));
    assert(not app.state.dirty and app.state.problem and app.state.problem:find('before a character loads',1,true),
        'The change is not waiting to be saved, and Vantage says it is replaced: '..tostring(app.state.problem));
end;
SNAP.valid=true;frames(5);
assert(app.state.identity and app.state.settings.style.font_size~=17 and app.state.problem==nil,
    'The character\'s saved settings replace the change when it loads, and the message ends.');
MOCK.fire('unload');
