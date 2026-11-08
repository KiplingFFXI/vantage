-- Two edges of saving and showing settings: a change whose save failed on a character since switched away
-- from reaches that character's file once it can be written; /vg while the user's own rules hide the panels
-- says when the window shows instead of opening it invisibly.
local store=require('core.store');
local SNAP={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(SNAP);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
require('ui.party_hud').draw=function()return 0,{};end;
require('ui.native_party_hud').draw=function()return 0,{};end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end};
local APP=dofile(ADDON_DIR..'/vantage.lua');
local function S()return APP.state.settings;end;
local function CMD(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
local function FRAMES(n)for _=1,n do MOCK.frame(.11);end;end;
MOCK.fire('load');APP.refresh(0);
APP.state.dirty=true;assert(APP.callbacks.save());
local a_path=APP.state.path;
-- A change on A whose save fails (the file is busy) until after the switch to B.
MOCK.file_replace_error=true;
CMD('/vg set style.font_size 23');
assert(S().style.font_size==23 and APP.state.dirty,'Fixture: the change is pending, its save failed.');
SNAP.id,SNAP.name=1002,'Other';
FRAMES(2);
assert(APP.state.path~=a_path and APP.state.unsaved[a_path],'Fixture: switched to B with A\'s copy parked.');
local saved=assert(store.read(a_path));
assert(saved.style.font_size==16,'Fixture: A\'s file still holds the old value while it cannot be written.');
MOCK.file_replace_error=nil;
FRAMES(50);
saved=assert(store.read(a_path));
assert(saved.style.font_size==23 and APP.state.unsaved[a_path]==nil,'A\'s pending change reaches A\'s file from B once the file can be written: '..tostring(saved.style.font_size));
FRAMES(3);
assert(S().style.font_size==16 and not APP.state.dirty,'B\'s own settings are untouched.');
-- /vg during an event with Hide during events on: the window opens when the event ends, and says so now.
assert(S().visibility.hide_events,'Fixture: hide during events is the default.');
SNAP.in_event=true;FRAMES(3);
local printed=#MOCK.printed;
local drawn=false;
local window=require('ui.settings_window');local draw=window.draw;
window.draw=function(...) drawn=true;return draw(...);end;
CMD('/vg');FRAMES(3);
assert(S().window.open and not drawn,'Fixture: the window is open but hidden by the rule.');
assert(#MOCK.printed==printed+1 and MOCK.printed[#MOCK.printed]:find('settings window shows when',1,true),
    '/vg during an event says when the window shows: '..tostring(MOCK.printed[#MOCK.printed]));
SNAP.in_event=false;FRAMES(3);
assert(drawn,'The window shows when the event ends.');
printed=#MOCK.printed;
CMD('/vg');FRAMES(1);
assert(not S().window.open and #MOCK.printed==printed,'A /vg with the window shown closes it with no message.');
window.draw=draw;
