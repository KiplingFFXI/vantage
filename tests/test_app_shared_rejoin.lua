-- Undo or Redo that turns sharing back on, or switches what it shares, joins it as the setting does: the
-- shared layout loads first. So another character's newer layout stays in the file, and this one takes it.
local store=require('core.store');
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=3,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(snapshot);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
require('ui.party_hud').draw=function()return 0,{};end;
require('ui.native_party_hud').draw=function()return 0,{};end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local function settings()return app.state.settings;end;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
local function frames(count)for _=1,count do MOCK.frame(.11);end;end;
MOCK.fire('load');app.refresh(0);
app.state.dirty=true;assert(app.callbacks.save(),'Fixture: the settings are on disk.');
local layout_path=app.state.path:gsub('Tester_1001/settings.json$','shared_layout.json');
local function shared()return assert(store.read(layout_path));end;
-- Another character saves through the same files.
local other=require('core.profiles').new(app.state.path:gsub('Tester_1001/settings.json$',''));
local function other_moves(x)
    local copy=store.copy(settings());copy.shared_layout,copy.panels.self_buffs.x=true,x;
    assert(other:save_layout(copy,'placement'),'Fixture: the other character saved its placement.');
end;
command('/vg set shared_layout true');
local x=shared().self_buffs.x;

-- Undo of a stop.
command('/vg set shared_layout false');
other_moves(x+100);frames(30);
assert(settings().panels.self_buffs.x==x,'Fixture: not sharing, this character keeps its own placement.');
command('/vg undo');frames(10);
assert(settings().shared_layout,'Fixture: undo turned sharing back on.');
assert(shared().self_buffs.x==x+100 and settings().panels.self_buffs.x==x+100,
    'Undo that rejoins sharing keeps the newer shared placement, and this character takes it.');
-- Redo of a join.
command('/vg undo');frames(5);
assert(not settings().shared_layout,'Fixture: a second undo left sharing.');
other_moves(x+200);frames(30);
command('/vg redo');frames(10);
assert(settings().shared_layout,'Fixture: redo joined sharing again.');
assert(shared().self_buffs.x==x+200 and settings().panels.self_buffs.x==x+200,
    'Redo that rejoins sharing keeps the newer shared placement, and this character takes it.');

-- Undo of a switch from full presentation to placement.
command('/vg set shared_scope presentation');frames(30);
local size=settings().style.font_size;
command('/vg set shared_scope placement');
local copy=store.copy(settings());copy.shared_scope,copy.style.font_size='presentation',size+5;
assert(other:save_layout(copy,'presentation'),'Fixture: the other character saved a new font size.');
frames(30);
command('/vg undo');frames(10);
assert(settings().shared_scope=='presentation','Fixture: undo went back to sharing the presentation.');
assert(shared().presentation.style.font_size==size+5 and settings().style.font_size==size+5,
    'Undo back to sharing the presentation keeps the newer one, and this character takes it.');

-- Redo of a switch from placement to full presentation, after another character saved a newer presentation.
-- Only the Redo's own rejoin can take it: the base it holds is a placement.
command('/vg set shared_scope placement');frames(30);
command('/vg set shared_scope presentation');frames(30);
size=settings().style.font_size;
command('/vg undo');frames(10);
assert(settings().shared_scope=='placement','Fixture: undo went back to sharing placement.');
copy=store.copy(settings());copy.shared_scope,copy.style.font_size='presentation',size+5;
assert(other:save_layout(copy,'presentation'),'Fixture: the other character saved a new font size.');
frames(30);
command('/vg redo');frames(10);
assert(settings().shared_scope=='presentation','Fixture: redo went back to sharing the presentation.');
assert(shared().presentation.style.font_size==size+5 and settings().style.font_size==size+5,
    'Redo back to sharing the presentation keeps the newer one, and this character takes it.');
