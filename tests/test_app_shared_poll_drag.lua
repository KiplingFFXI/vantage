-- Party list strip drags released while the shared layout poll is due keep their place, beside the game's party
-- list and detached. Real vantage.lua, ui/native_party_hud.lua and core/profiles.lua; only the client readers, the
-- game party list, the timer panels and the settings window are fixtures.
local store=require('core.store');
local copy,equal=store.copy,store.equal;
local profiles=require('core.profiles');
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_effects={},party={},entities={}};
-- The game's party window for your own party, with your row in it.
local game={available=true,groups={{x=1300,y=600,width=200,height=40,rows={[0]={x=1300,y=600,width=200,height=40,slot=0}}}}};
package.loaded['core.client']={load=function()end,read=function()return copy(snapshot);end,visibility=function()return copy(snapshot);end};
package.loaded['core.observer']={read=function()return {};end};
package.loaded['core.native_party_ui']={status=function()return {available=true};end,treasure_open=function()return false;end,
    geometry=function()return game;end};
package.loaded['ui.hud']={draw=function()return nil;end,draw_notices=function()end,cancel_gesture=function()end};
package.loaded['ui.settings_window']={blocks_input=function()return false;end,draw=function()end};

-- The mouse and the strips' move buttons.
local imgui=require('imgui');
local mx,my,down,pressed,item,active,cursor=-1,-1,false,false,nil,nil,{};
local buttons={};
imgui.GetMousePos=function()return mx,my;end;
imgui.IsMouseDown=function()return down;end;
imgui.SetCursorScreenPos=function(value)cursor=value;end;
imgui.InvisibleButton=function(id,size)
    item=id;buttons[id]={x=cursor[1],y=cursor[2],width=size[1],height=size[2]};
    if pressed and mx>=cursor[1] and mx<cursor[1]+size[1] and my>=cursor[2] and my<cursor[2]+size[2] then active=id;end;
    return false;
end;
imgui.IsItemActivated=function()return pressed and item==active;end;
imgui.IsItemActive=function()return down and item==active;end;
imgui.Begin=function()return true;end;
imgui.GetScrollY=function()return 0;end;
MOCK.screen={1600,900};
MOCK.key_shift=true;

local app=dofile(ADDON_DIR..'/vantage.lua');
MOCK.now=1;app.refresh(1);
local settings=app.state.settings;
local party=settings.party_ui;
party.enabled,party.preview,party.locked=true,true,false;
local strip=party.groups[1];
strip.detached_x,strip.detached_y,strip.detached_width,strip.detached_height=400,150,300,240;
settings.shared_layout,settings.shared_scope=true,'placement';
local shared=profiles.new(MOCK_INSTALL_PATH..'/config/addons/vantage');
local function present(seconds)MOCK.frame(seconds or .016);MOCK.fire('d3d_beginscene',true);end;
local function layout()return copy(profiles.capture_layout(settings));end;
-- Everything saved, the shared layout holds the starting place and was just polled.
local function settle()
    present();app.callbacks.save();app.state.dirty=false;
    assert(shared:save_layout(settings),'Fixture: the shared layout saves.');app.state.shared_at=MOCK.now;
end;

-- The poll waits while the mouse is down and on the frame it comes up.
settle();
mx,my,down,pressed,active=5,5,true,true,nil;present();pressed=false;
local due=MOCK.now-3;
app.state.shared_at=due;present();
assert(app.state.shared_at==due,'No shared layout poll while the mouse is down.');
down=false;present();
assert(app.state.shared_at==due,'No shared layout poll on the frame the mouse is released.');
present();
assert(math.abs(app.state.shared_at-MOCK.now)<1e-6,'The next frame with the mouse up polls the shared layout.');

local panels={
    {name='party strip',detached=false},
    {name='detached party strip',detached=true},
};
for _,panel in ipairs(panels)do
    strip.native_detached=panel.detached;
    buttons={};settle();
    local box;
    for id,value in pairs(buttons)do if id=='##native_move_1' then box=value;end;end;
    assert(box,'Fixture: the '..panel.name..' draws its move button.');
    local start=layout();
    -- Press in the middle, then drag for 2.5 s, so the poll is due when the mouse comes up.
    mx,my,down,pressed,active=box.x+box.width/2,box.y+box.height/2,true,true,nil;present();pressed=false;
    for _=1,5 do mx,my=mx+7,my+3;present(.5);end;
    local dragged=layout();
    assert(not equal(dragged.party_ui,start.party_ui),'Fixture: the '..panel.name..' follows the drag.');
    assert(app.state.shared_at<MOCK.now-2,'Fixture: the shared layout poll is due at release.');
    down=false;present();present();present();
    assert(equal(layout().party_ui,dragged.party_ui),'A released '..panel.name..' drag keeps its place.');
    assert(app.state.dirty,'The released '..panel.name..' drag is an unsaved change.');
    for _=1,60 do present(.05);end;
    assert(not app.state.dirty and app.state.shared_at>MOCK.now-2,'Fixture: saved, then polled again.');
    assert(equal(layout().party_ui,dragged.party_ui),'The '..panel.name..' keeps its place after the next poll.');
    local saved=store.read(app.state.path);
    assert(saved and equal(profiles.capture_layout(saved).party_ui,dragged.party_ui),'The released '..panel.name..' drag is saved.');
    local other=copy(saved);
    assert(shared:load_layout(other),'Fixture: the shared layout reads.');
    assert(equal(profiles.capture_layout(other).party_ui,dragged.party_ui),'The shared layout holds the released '..panel.name..' drag.');
end;
