-- A settings page that saved and then failed while the file was locked again can't put the file back. The copy kept
-- to save again then has nothing sure to be checked against, so it saves after a character switch, as it did before
-- the check, and no line says another game saved the file.
local store=require('core.store');
local SNAP={valid=true,id=1001,name='First',zone=102,job=1,self_known=true,self_effects={},party={},entities={}};
require('app_fixture')(SNAP);
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end};
local page;
package.loaded['ui.main_page']={labels={},draw=function(_,s,_,callbacks,ui)if page then page(s,callbacks,ui);end;end};
local APP=dofile(ADDON_DIR..'/vantage.lua');
local function CMD(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
local function FRAMES(n)for _=1,n do MOCK.frame(.11);end;end;
local function dropped_lines()
    local count=0;
    for _,message in ipairs(MOCK.printed) do if message:find('another game saved',1,true) then count=count+1; end; end;
    return count;
end;
MOCK.fire('load');APP.refresh(0);
APP.state.dirty=true;assert(APP.callbacks.save());
local path=APP.state.path;
CMD('/vg');FRAMES(2);APP.callbacks.editor_changed();assert(APP.callbacks.save());
local size=store.read(path).style.font_size;
MOCK.file_replace_error=true;
CMD('/vg set style.font_size '..(size+7));
if not APP.state.unsaved[path] then APP.callbacks.save(); end;
assert(APP.state.unsaved[path],'Fixture: the change is kept to save again.');
local reached;
page=function()
    page=nil;
    MOCK.file_replace_error=nil;
    APP.state.dirty=true;assert(APP.callbacks.save(),'Fixture: the page saved.');
    MOCK.file_replace_error=true;
    reached=true;
    error('Fixture settings page failure.');
end;
FRAMES(1);
assert(reached and APP.state.settings_stopped,'Fixture: the page failed.');
local said=dropped_lines();
SNAP.id,SNAP.name=1002,'Other';
FRAMES(2);
assert(APP.state.path~=path,'Fixture: switched characters.');
MOCK.file_replace_error=nil;
FRAMES(50);
assert(dropped_lines()==said,'With one game, no line says another game saved the file: '..tostring(MOCK.printed[#MOCK.printed]));
assert(APP.state.unsaved[path]==nil and store.read(path).style.font_size==size+7,
    'The kept change saves after the switch, got '..tostring(store.read(path).style.font_size));
return 'A kept copy a failed page couldn\'t put back still saves';
