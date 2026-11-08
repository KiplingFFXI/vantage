-- A settings page that switches the shared scope, or presses Undo onto a step that rejoins sharing, reads the
-- shared file. When the page then fails, the rollback puts back the file this character last read too: a newer
-- layout another character saved is still loaded by the next poll and never written over, and a file nobody
-- changed is not loaded again.
local store=require('core.store');
local SNAP={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(SNAP);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
require('ui.party_hud').draw=function()return 0,{};end;
require('ui.native_party_hud').draw=function()return 0,{};end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end,suspend=function()return true;end};
local page;
package.loaded['ui.main_page']={labels={},draw=function(_,s,_,callbacks,ui)if page then page(s,callbacks,ui);end;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local function settings()return app.state.settings;end;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
local function frames(count)for _=1,count do MOCK.frame(.11);end;end;
-- A page that fails stops the window, which opens again for the next one.
local function fail(label,step)
    settings().window.open,settings().window.tab,app.state.settings_stopped=true,'Home',nil;
    local ran=false;
    page=function(s,callbacks,ui)ran,page=true,nil;step(s,callbacks,ui);error('Fixture settings page failure.');end;
    for _=1,3 do if not ran then MOCK.frame(.11); end; end;
    page=nil;
    assert(ran and app.state.settings_stopped,'Fixture: the page ran and failed: '..label);
end;
MOCK.fire('load');app.refresh(0);
app.state.dirty=true;assert(app.callbacks.save());
command('/vg set shared_layout true');
frames(30);
local root=app.state.path:gsub('Tester_1001/settings.json$','');
local layout_path=root..'shared_layout.json';
local function shared()return assert(store.read(layout_path));end;
local other=require('core.profiles').new(root);
command('/vg');frames(2);
assert(settings().window.open,'Fixture: the settings window is open.');

-- A newer layout from another character lands just after a poll; a failed page switches the scope.
local x=shared().self_debuffs.x;
local copy=store.copy(settings());copy.panels.self_debuffs.x=x+70;assert(other:save_layout(copy));
app.state.shared_at=MOCK.now;
fail('scope',function(_,callbacks)callbacks.sharing(true,'presentation');end);
assert(settings().shared_scope=='placement','Fixture: the page is rolled back.');
frames(40);
assert(settings().panels.self_debuffs.x==x+70,'The next poll loads the newer layout: '..settings().panels.self_debuffs.x);
command('/vg set panels.self_buffs.x 333');frames(30);
assert(shared().self_debuffs.x==x+70 and shared().self_buffs.x==333,'A later move here keeps the other character\'s move.');

-- The same through Undo onto a step that rejoins sharing in the other scope.
command('/vg set shared_scope presentation');frames(30);
command('/vg undo');frames(30);
assert(settings().shared_scope=='placement','Fixture: back to placement.');
x=shared().self_debuffs.x;
copy=store.copy(settings());copy.panels.self_debuffs.x=x+90;assert(other:save_layout(copy));
app.state.shared_at=MOCK.now;
fail('redo',function(_,callbacks)callbacks.redo();end);
assert(settings().shared_scope=='placement','Fixture: the Redo is rolled back.');
frames(40);
assert(settings().panels.self_debuffs.x==x+90,'After a failed Redo the next poll loads the newer layout too.');

-- Nobody changed the file: a failed page that read it doesn't make the next poll load it again.
frames(30);
app.state.shared_at=MOCK.now;
fail('unchanged',function(_,callbacks)callbacks.sharing(true,'presentation');end);
local value=app.state.shared_value;
frames(40);
assert(app.state.shared_value==value,'An unchanged shared file is not loaded again after a failed page.');
