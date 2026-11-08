-- Two characters share placement and move different panels within one poll of each other. Publishing this
-- character's move first takes what the other changed since it last read the file, so neither move undoes
-- the other, here, in the shared file or in this character's Undo.
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
local function disk()return store.read(app.state.path);end;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
local function frames(count)for _=1,count do MOCK.frame(.11);end;end;
MOCK.fire('load');app.refresh(0);
app.state.dirty=true;assert(app.callbacks.save(),'Fixture: the settings are on disk.');
command('/vg set shared_layout true');
frames(30);
local layout_path=app.state.path:gsub('Tester_1001/settings.json$','shared_layout.json');
local function shared()return assert(store.read(layout_path));end;
local other=require('core.profiles').new(app.state.path:gsub('Tester_1001/settings.json$',''));
local x,dx=shared().self_buffs.x,shared().self_debuffs.x;
-- The other character moves self_debuffs; this one moves self_buffs half a second later, before its next poll.
local theirs=store.copy(settings());theirs.panels.self_debuffs.x=dx+70;
assert(other:save_layout(theirs),'Fixture: the other character published its move.');
frames(4);
command('/vg set panels.self_buffs.x 333');
local file=shared();
assert(file.self_buffs.x==333 and file.self_debuffs.x==dx+70,
    'The shared file has both moves: '..tostring(file.self_buffs.x)..', '..tostring(file.self_debuffs.x));
assert(settings().panels.self_debuffs.x==dx+70 and disk().panels.self_debuffs.x==dx+70,
    'This character takes the other move as it publishes its own, and saves it.');
-- The other character's next poll keeps its own move.
local ok,_,found=other:load_layout(theirs);
assert(ok and found and theirs.panels.self_debuffs.x==dx+70 and theirs.panels.self_buffs.x==333,
    'The other character keeps its move and takes this one.');
-- Undoing this character's move publishes the placement before it and keeps the other move.
frames(30);
command('/vg undo');frames(10);
file=shared();
assert(settings().panels.self_buffs.x==x and file.self_buffs.x==x,'Undo puts this character\'s move back.');
assert(settings().panels.self_debuffs.x==dx+70 and file.self_debuffs.x==dx+70,'Undo keeps the other character\'s move.');
-- Both changing the same panel within one poll: the move published last stays. No poll comes between, so the
-- publish merges with the other move unread.
theirs=store.copy(settings());theirs.panels.self_buffs.x=x+40;
assert(other:save_layout(theirs),'Fixture: the other character moved self_buffs too.');
app.state.shared_at=MOCK.now;
frames(4);
assert(settings().panels.self_buffs.x~=x+40,'Fixture: the other move is unread here.');
command('/vg set panels.self_buffs.x 444');
assert(shared().self_buffs.x==444 and settings().panels.self_buffs.x==444,'This character\'s later move of the same panel stays.');
