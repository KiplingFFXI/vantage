-- Undo and Redo of a personal change never publish an older placement over another character's newer
-- shared layout. Undoing this character's own move still publishes the placement it had before.
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
command('/vg set shared_layout true');
local layout_path=app.state.path:gsub('Tester_1001/settings.json$','shared_layout.json');
local function shared()return assert(store.read(layout_path));end;
-- Another character saves its own placement through the same files.
local other=require('core.profiles').new(app.state.path:gsub('Tester_1001/settings.json$',''));
local function other_moves(panel,x)
    local copy=store.copy(settings());copy.panels[panel].x=x;
    assert(other:save_layout(copy),'Fixture: the other character saved its placement.');
end;
local x,dx=shared().self_buffs.x,shared().self_debuffs.x;
assert(type(x)=='number' and type(dx)=='number','Fixture: the shared placement is on disk.');

-- Undo of a personal change after another character moved a panel.
command('/vg set style.font_size 25');
other_moves('self_buffs',x+100);frames(30);
assert(settings().panels.self_buffs.x==x+100,'Fixture: this character follows the newer shared placement.');
command('/vg undo');frames(10);
assert(settings().style.font_size~=25,'Fixture: undo put the font back.');
assert(settings().panels.self_buffs.x==x+100 and shared().self_buffs.x==x+100,
    'Undoing a personal change keeps the other character\'s newer placement, here and in the shared file.');
-- Redo of it after another move.
other_moves('self_buffs',x+200);frames(30);
assert(settings().panels.self_buffs.x==x+200,'Fixture: this character follows the newer shared placement again.');
command('/vg redo');frames(10);
assert(settings().style.font_size==25,'Fixture: redo put the font back.');
assert(settings().panels.self_buffs.x==x+200 and shared().self_buffs.x==x+200,
    'Redoing a personal change keeps the other character\'s newer placement too.');

-- Undo of this character's own move still publishes the earlier placement, and keeps the other
-- character's newer move of another panel.
command('/vg set panels.self_buffs.x 300');
assert(shared().self_buffs.x==300,'Fixture: this character\'s own move is published.');
other_moves('self_debuffs',dx+50);frames(30);
assert(settings().panels.self_debuffs.x==dx+50,'Fixture: this character follows the other character\'s move.');
command('/vg undo');frames(10);
local file=shared();
assert(settings().panels.self_buffs.x==x+200 and file.self_buffs.x==x+200,'Undoing an own move publishes the placement before it.');
assert(settings().panels.self_debuffs.x==dx+50 and file.self_debuffs.x==dx+50,
    'Undoing an own move keeps the other character\'s newer move of another panel.');
-- A change opened before another character's move and closed with nothing changed is no Undo step.
local steps=#app.state.history;
app.callbacks.changed('before','Timer panel layout');
other_moves('self_buffs',x+300);frames(30);
assert(settings().panels.self_buffs.x==x+300,'Fixture: this character follows the other character\'s move.');
app.callbacks.save();
assert(#app.state.history==steps,'An open change the other character\'s move came in during, closed unchanged, is no Undo step.');
