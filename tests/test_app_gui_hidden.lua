-- With Ashita's drawing hidden (/hideui) no Vantage panel reaches the screen, so from the second hidden Present
-- none is drawn. A one-Present hide changes nothing.
local store=require('core.store');
local copy=store.copy;
local world={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_effects={{effect=33,slot=0}},party={},entities={},
    hidden=false,map=false,in_event=false,chat_open=false,combat=true};
local drawn={};
local function count(name) drawn[name]=(drawn[name] or 0)+1; end;
package.loaded['core.client']={load=function()end,read=function()return copy(world);end,
    visibility=function()return {valid=true,id=world.id,zone=world.zone,hidden=world.hidden,map=world.map,
        in_event=world.in_event,chat_open=world.chat_open};end};
package.loaded['core.observer']={read=function()return {};end};
package.loaded['core.native_party_ui']={status=function()return {available=true};end,treasure_open=function()return false;end};
package.loaded['ui.native_party_hud']={cancel_layout_gesture=function()end,draw=function()count('party');return false,{},{};end};
package.loaded['ui.hud']={cancel_gesture=function()end,
    draw_notices=function()count('notices');end,
    draw=function()count('panels');end};
package.loaded['ui.settings_window']={draw=function()end,blocks_input=function()return false;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
MOCK.now=1;app.refresh(1);
local settings=app.state.settings;
settings.enabled=true;
settings.party_ui.enabled,settings.party_ui.preview=true,false;
local saved=copy(settings);
local function present()drawn={};MOCK.frame(.11);end;
local function everything()return drawn.panels==1 and drawn.party==1;end;
present();
assert(everything(),'Fixture: an ordinary Present draws every display.');

-- A hide that shows again in its own Present is one hidden Present, which is drawn normally.
MOCK.gui_visible=false;present();
assert(everything() and not app.state.gui_off,'One hidden Present still draws every display.');
MOCK.gui_visible=true;present();assert(everything());

-- /hideui stays hidden. From the second hidden Present no display is drawn.
MOCK.gui_visible=false;present();assert(everything());
for _=1,5 do
    present();
    assert(app.state.gui_off and not drawn.panels and not drawn.party,
        'No display is drawn while drawing stays hidden.');
    assert(drawn.notices==1,'Alert notices still keep their place.');
end;

-- Drawing shown again: the next Present draws every display.
MOCK.gui_visible=true;present();
assert(everything() and not app.state.gui_off,'Showing drawing again draws every display from the next Present.');
assert(require('core.customization').equal(saved,app.state.settings) and #MOCK.commands==0,
    'Hidden drawing changes no setting and sends nothing.');
