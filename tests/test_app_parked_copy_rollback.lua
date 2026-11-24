-- A settings page that fails puts back the copy kept to save again with the file it was kept against. So a page that
-- saved and then failed doesn't make that copy look older than the file, and it still saves after a character switch.
local store=require('core.store');
local SNAP={valid=true,id=1001,name='First',zone=102,job=1,self_known=true,self_effects={},party={},entities={}};
require('app_fixture')(SNAP);
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end};
-- Home is the fixture's page: page gives it what to do.
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
assert(APP.state.settings.window.open and store.read(path).window.open==true,'Fixture: the window is drawn and saved open.');
local size=store.read(path).style.font_size;
-- A change whose save fails (the file is busy) is kept to save again.
MOCK.file_replace_error=true;
CMD('/vg set style.font_size '..(size+7));
if not APP.state.unsaved[path] then APP.callbacks.save(); end;
local kept=APP.state.unsaved[path];
assert(kept and kept.style.font_size==size+7,'Fixture: the change is kept to save again.');
-- The page saves once the file is free, makes a change whose save fails again, and then fails itself.
local reached;
page=function(current)
    page=nil;
    MOCK.file_replace_error=nil;
    APP.state.dirty=true;assert(APP.callbacks.save(),'Fixture: the page saved.');
    MOCK.file_replace_error=true;
    current.style.font_size=size+8;APP.state.dirty=true;
    assert(not APP.callbacks.save(),'Fixture: the page\'s second save failed.');
    MOCK.file_replace_error=nil;
    reached=true;
    error('Fixture settings page failure.');
end;
FRAMES(1);
assert(reached and APP.state.settings_stopped,'Fixture: the page failed and stopped.');
assert(APP.state.unsaved[path]==kept and APP.state.settings.style.font_size==size+7,'Fixture: the copy kept before the page is back.');
assert(store.read(path).style.font_size==size,'Fixture: the file is put back as it was before the page.');
-- The file is still busy when the player switches characters, and is free later.
local said=dropped_lines();
MOCK.file_replace_error=true;
SNAP.id,SNAP.name=1002,'Other';
FRAMES(2);
assert(APP.state.path~=path,'Fixture: switched to Other.');
MOCK.file_replace_error=nil;
FRAMES(50);
local file=assert(store.read(path));
assert(file.style.font_size==size+7 and APP.state.unsaved[path]==nil and dropped_lines()==said,
    'The copy saves once the file is free, and nothing says another game saved it: font_size '..tostring(file.style.font_size)
    ..' (the copy has '..(size+7)..'), '..(dropped_lines()-said)..' such lines');
return true;
