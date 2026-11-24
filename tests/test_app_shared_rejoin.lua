-- Undo or Redo that turns sharing back on, or switches what it shares, joins it as the setting does: the
-- shared layout loads first. So another character's newer layout stays in the file, and this one takes it. The other
-- Undo and Redo steps take it too, so going on past the step that rejoined doesn't publish the older layout they held.
local store=require('core.store');
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=3,self_known=true,self_effects={},party={},entities={}};
require('app_fixture')(snapshot);
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

-- Undo past a step that rejoined sharing, to a personal change from before this character stopped sharing. That step
-- takes the placement another character shared meanwhile, as a step the poll moved does (test_app_shared_undo.lua).
command('/vg set shared_scope placement');frames(30);
local at,font=settings().panels.self_buffs.x,settings().style.font_size;
command('/vg set style.font_size '..(font+1));
command('/vg set shared_layout false');
other_moves(at+100);frames(30);
command('/vg undo');frames(10);
assert(settings().shared_layout and settings().panels.self_buffs.x==at+100,'Fixture: undo rejoined sharing and took the newer placement.');
command('/vg undo');frames(10);
assert(settings().style.font_size==font,'Fixture: the second undo put the font back.');
assert(settings().panels.self_buffs.x==at+100 and shared().self_buffs.x==at+100,
    'Undo past a step that rejoined sharing keeps the other character\'s newer placement, here and in the shared file.');

-- Redo past a step that rejoined sharing.
command('/vg set shared_layout false');frames(5);
at=settings().panels.self_buffs.x;
command('/vg set shared_layout true');frames(10);
command('/vg set style.font_size '..(font+2));
command('/vg undo');frames(5);
command('/vg undo');frames(5);
assert(not settings().shared_layout,'Fixture: two undos left sharing.');
other_moves(at+100);frames(30);
command('/vg redo');frames(10);
assert(settings().shared_layout and settings().panels.self_buffs.x==at+100,'Fixture: redo rejoined sharing and took the newer placement.');
command('/vg redo');frames(10);
assert(settings().style.font_size==font+2,'Fixture: the second redo put the font back.');
assert(settings().panels.self_buffs.x==at+100 and shared().self_buffs.x==at+100,
    'Redo past a step that rejoined sharing keeps the other character\'s newer placement too.');

-- Undo past a step that went back to sharing the presentation, to this character's own move from before it shared
-- placement only. The move is put back, and the newer presentation another character shared meanwhile stays.
command('/vg set shared_scope presentation');frames(30);
local dx=settings().panels.self_debuffs.x;
size=settings().style.font_size;
command('/vg set panels.self_debuffs.x '..(dx+30));
command('/vg set shared_scope placement');
copy=store.copy(settings());copy.shared_scope,copy.style.font_size='presentation',size+5;
assert(other:save_layout(copy,'presentation'),'Fixture: the other character saved a new font size.');
frames(30);
command('/vg undo');frames(10);
assert(settings().shared_scope=='presentation' and settings().style.font_size==size+5,
    'Fixture: undo went back to sharing the presentation and took the newer one.');
command('/vg undo');frames(10);
local file=shared();
assert(settings().panels.self_debuffs.x==dx and file.presentation.panels.self_debuffs.x==dx,
    'Fixture: the second undo put this character\'s own move back.');
assert(settings().style.font_size==size+5 and file.presentation.style.font_size==size+5,
    'Undo past a step that went back to sharing the presentation keeps the other character\'s newer one, here and in the shared file.');
