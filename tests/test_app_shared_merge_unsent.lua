-- A publish takes what another character changed since this one last read shared_layout.json into these settings, and
-- then its write fails, as when another program holds the file. What it took stays taken, as after a publish that
-- works: the base moves past it, so only this character's own change is still owed, the Undo steps take it, and the
-- note in the character's own file carries that base over a reload. So neither the retry nor a later Undo puts the
-- other character's move back over a newer one.
local store=require('core.store');
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=3,self_known=true,self_effects={},party={},entities={}};
require('app_fixture')(snapshot);
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end,suspend=function()end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local function settings()return app.state.settings;end;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
local function frames(count)for _=1,count do MOCK.frame(.11);end;end;
MOCK.fire('load');app.refresh(0);
app.state.dirty=true;assert(app.callbacks.save(),'Fixture: the settings are on disk.');
command('/vg set shared_layout true');
frames(30);
local folder=app.state.path:gsub('Tester_1001/settings.json$','');
local layout_path,own_path=folder..'shared_layout.json',app.state.path;
local function shared()return assert(store.read(layout_path));end;
local other=require('core.profiles').new(folder);
local x,dx=shared().self_buffs.x,shared().self_debuffs.x;
-- While fails is above 0, a write of the shared file fails with no code, as when another program holds it, and counts
-- it down.
local real_write,fails=store.write,0;
store.write=function(path,...)
    if fails>0 and path==layout_path then
        fails=fails-1;
        return false,'The saved file could not be replaced. Your previous file was kept.';
    end;
    return real_write(path,...);
end;
-- The other character moves self_debuffs, and this one moves self_buffs before its next poll. Its publish takes the
-- other move and then fails to write.
local function both_move(their_x,own_x,failing)
    local theirs=store.copy(settings());theirs.panels.self_debuffs.x=their_x;
    assert(other:save_layout(theirs),'Fixture: the other character published its move.');
    app.state.shared_at=MOCK.now;frames(4);
    fails=failing;
    command('/vg set panels.self_buffs.x '..own_x);
    assert(app.state.publish_pending and settings().panels.self_debuffs.x==their_x,
        'Fixture: the publish took the other move into these settings, and then its write failed.');
    return theirs;
end;

both_move(dx+70,333,1);
local base=app.state.shared_value;
assert(base.self_debuffs.x==dx+70 and base.self_buffs.x==x,
    'The base takes the other move, and this character\'s own move is still owed: '..base.self_debuffs.x..', '..base.self_buffs.x);
local note=store.read(own_path).shared_unsent;
assert(type(note)=='table' and note.base.self_debuffs.x==dx+70 and note.base.self_buffs.x==x,
    'The character\'s file notes the change as still to be sent over that base.');
frames(60);
local file=shared();
assert(not app.state.publish_pending and file.self_buffs.x==333 and file.self_debuffs.x==dx+70,
    'Fixture: the retry shared both moves.');
command('/vg undo');frames(10);
file=shared();
assert(settings().panels.self_buffs.x==x and file.self_buffs.x==x,'Undo puts this character\'s move back.');
assert(settings().panels.self_debuffs.x==dx+70 and file.self_debuffs.x==dx+70,
    'Undo keeps the other move the failed publish took: '..settings().panels.self_debuffs.x..', '..file.self_debuffs.x);

-- The other character moves the same panel again before the retry. The retry takes that newer move.
frames(30);
local theirs=both_move(dx+80,334,1);
theirs.panels.self_debuffs.x=dx+90;
assert(other:save_layout(theirs),'Fixture: the other character moved self_debuffs again.');
frames(60);
file=shared();
assert(not app.state.publish_pending and file.self_buffs.x==334,'Fixture: the retry shared this character\'s move.');
assert(file.self_debuffs.x==dx+90 and settings().panels.self_debuffs.x==dx+90,
    'The retry takes the other character\'s newer move, not the one the failed publish took: '..file.self_debuffs.x);

-- The other character writes again between the publish's read and its write, so the publish reads the file once more,
-- and that read fails. Only the publish's own reads are counted: a write's checks pass a cache.
frames(30);
theirs=store.copy(settings());theirs.panels.self_debuffs.x=dx+120;
assert(other:save_layout(theirs),'Fixture: the other character published its move.');
app.state.shared_at=MOCK.now;frames(4);
local real_read,reads=store.read,0;
store.read=function(path,cache)
    if path~=layout_path or cache~=nil then return real_read(path,cache); end;
    reads=reads+1;
    if reads==2 then return nil,'shared_layout.json is in use.'; end;
    local value,why=real_read(path);
    if reads==1 then theirs.panels.self_debuffs.x=dx+130;assert(other:save_layout(theirs)); end;
    return value,why;
end;
command('/vg set panels.self_buffs.x 336');
store.read=real_read;
assert(reads==2 and app.state.publish_pending and settings().panels.self_debuffs.x==dx+120,
    'Fixture: the publish took the first move, then the other character wrote again and the read after that failed.');
frames(60);
file=shared();
assert(not app.state.publish_pending and file.self_buffs.x==336,'Fixture: the retry shared this character\'s move.');
assert(file.self_debuffs.x==dx+130 and settings().panels.self_debuffs.x==dx+130,
    'The retry takes the move written while the publish ran: '..file.self_debuffs.x);

-- The same over an unload and a load: the write keeps failing until Vantage unloads, and the other character moves
-- self_debuffs again meanwhile.
frames(30);
theirs=both_move(dx+140,337,1000);
MOCK.fire('unload');
fails=0;
assert(shared().self_buffs.x==336 and type(store.read(own_path).shared_unsent)=='table',
    'Fixture: the change is still owed, and the character\'s file notes it.');
theirs.panels.self_debuffs.x=dx+150;
assert(other:save_layout(theirs),'Fixture: the other character moved self_debuffs while this one was away.');
app=dofile(ADDON_DIR..'/vantage.lua');
MOCK.fire('load');app.refresh(MOCK.now);
frames(10);
file=shared();
assert(not app.state.publish_pending and file.self_buffs.x==337,'Fixture: the change is sent after the load.');
assert(file.self_debuffs.x==dx+150 and settings().panels.self_debuffs.x==dx+150,
    'After a reload the other character\'s newer move stays: '..file.self_debuffs.x);
store.write=real_write;
return 'A publish whose write fails after it took another character\'s change keeps it as taken';
