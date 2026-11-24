-- A change whose save failed on a character since switched away from is kept to save again. When another game saves
-- that character's file before the retry gets through, or before the character logs back in here, the newer file
-- stays and one line says the change was dropped.
local store=require('core.store');
local SNAP={valid=true,id=1001,name='First',zone=102,job=1,self_known=true,self_effects={},party={},entities={}};
require('app_fixture')(SNAP);
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end};
local APP=dofile(ADDON_DIR..'/vantage.lua');
local function CMD(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
local function FRAMES(n)for _=1,n do MOCK.frame(.11);end;end;
MOCK.fire('load');APP.refresh(0);
APP.state.dirty=true;assert(APP.callbacks.save());
local a_path=APP.state.path;
local x0=assert(store.read(a_path)).panels.self_buffs.x;
-- A change on First whose save fails (the file is busy), then a switch to Other keeps the copy to save again.
MOCK.file_replace_error=true;
CMD('/vg set style.font_size 23');
SNAP.id,SNAP.name=1002,'Other';
FRAMES(2);
assert(APP.state.path~=a_path and APP.state.unsaved[a_path],'Fixture: First\'s copy is kept to save again.');
-- Another game logs First in, reads the file without the change kept here, and saves a move of its own.
MOCK.file_replace_error=nil;
local other_game=assert(store.read(a_path));
assert(other_game.style.font_size==16,'Fixture: the other game reads the file without the change kept here.');
other_game.panels.self_buffs.x=x0+250;
assert(store.write(a_path,other_game),'Fixture: the other game saved First.');
local printed=#MOCK.printed;
FRAMES(50);
local file=assert(store.read(a_path));
local lines=#MOCK.printed-printed;
assert(file.panels.self_buffs.x==x0+250 and file.style.font_size==16,
    'The other game\'s newer save of First is kept: self_buffs.x '..tostring(file.panels.self_buffs.x)..' (it saved '..(x0+250)
    ..'), font_size '..tostring(file.style.font_size)..', '..lines..' lines said');
assert(APP.state.unsaved[a_path]==nil,'The copy kept here is dropped.');
assert(lines==1 and MOCK.printed[#MOCK.printed]:find('another game saved',1,true),
    'One line says the change was dropped: '..tostring(MOCK.printed[#MOCK.printed]));
FRAMES(50);
assert(#MOCK.printed==printed+1 and store.read(a_path).panels.self_buffs.x==x0+250,'Nothing is tried or said again.');
-- Other's own settings are untouched.
assert(APP.state.settings.style.font_size==16 and not APP.state.dirty,'Other\'s settings are untouched.');
local function dropped_lines()
    local count=0;
    for _,message in ipairs(MOCK.printed) do if message:find('another game saved',1,true) then count=count+1; end; end;
    return count;
end;
-- The same when First logs back in here while the retries still fail: the newer file loads, not the copy.
SNAP.id,SNAP.name=1001,'First';
FRAMES(2);
assert(APP.state.path==a_path and APP.state.settings.panels.self_buffs.x==x0+250,'Fixture: First loads the other game\'s save.');
MOCK.file_replace_error=true;
CMD('/vg set style.font_size 24');
SNAP.id,SNAP.name=1002,'Other';
FRAMES(2);
assert(APP.state.path~=a_path and APP.state.unsaved[a_path],'Fixture: First\'s new copy is kept to save again.');
-- The other game gets its save of First through while this game's retries keep failing.
MOCK.file_replace_error=nil;
other_game=assert(store.read(a_path));
other_game.panels.self_buffs.x=x0+300;
assert(store.write(a_path,other_game),'Fixture: the other game saved First again.');
MOCK.file_replace_error=true;
local said=dropped_lines();
SNAP.id,SNAP.name=1001,'First';
FRAMES(2);
assert(APP.state.path==a_path,'Fixture: First is back here.');
local loaded=APP.state.settings;
assert(loaded.panels.self_buffs.x==x0+300 and loaded.style.font_size==16,'The other game\'s newer save is what loads: self_buffs.x '
    ..tostring(loaded.panels.self_buffs.x)..' (it saved '..(x0+300)..'), font_size '..tostring(loaded.style.font_size));
assert(APP.state.unsaved[a_path]==nil and not APP.state.dirty,'The copy kept here is dropped and nothing waits to be saved.');
assert(dropped_lines()==said+1,'One line says the change was dropped.');
MOCK.file_replace_error=nil;
FRAMES(50);
file=assert(store.read(a_path));
assert(file.panels.self_buffs.x==x0+300 and file.style.font_size==16 and dropped_lines()==said+1,
    'Nothing is saved over the newer file or said again.');
return true;
