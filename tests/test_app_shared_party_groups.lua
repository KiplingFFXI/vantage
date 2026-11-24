-- Two characters share where the party list strips sit. Each party group, and each field of one, merges and moves
-- the Undo steps on its own, as a panel does. So one character moving Your party while the other puts Alliance 1, or
-- Your party itself, in a panel of its own keeps both changes, and Undo puts back only this character's own move. With
-- the presentation shared, a group's member order stays one value.
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
command('/vg set shared_layout true');
frames(30);
local folder=app.state.path:gsub('Tester_1001/settings.json$','');
local layout_path=folder..'shared_layout.json';
local other=require('core.profiles').new(folder);
-- The party groups in the shared file, in either scope's form.
local function shared()local file=assert(store.read(layout_path));return (file.presentation or file).party_ui.groups;end;
local function mine()return settings().party_ui.groups;end;
local function order(list)return table.concat(list,',');end;
-- This character changes a party group, as a drag of its strip does, and saves.
local function move(group,field,value)
    app.callbacks.changed('before','Party layout');
    mine()[group][field]=value;
    app.callbacks.changed('after');
    assert(app.callbacks.save(),'Fixture: the change is saved.');
end;
-- The other character publishes a copy of these settings with a change made to its groups. The poll here doesn't read
-- it yet.
local function other_changes(change)
    local theirs=store.copy(settings());
    change(theirs.party_ui.groups);
    assert(other:save_layout(theirs),'Fixture: the other character published its change.');
    app.state.shared_at=MOCK.now;
    return theirs;
end;
local start=shared();
assert(start[1].native_x==0 and start[1].native_detached==false and start[2].native_detached==false and start[3].native_x==0,
    'Fixture: the party groups are shared where they start.');

-- The other character puts Alliance 1 in a panel of its own, and this one moves Your party within one poll of it.
local theirs=other_changes(function(groups)groups[2].native_detached,groups[2].detached_x=true,600;end);
frames(4);
assert(mine()[2].native_detached==false,'Fixture: the other change is unread here.');
move(1,'native_x',-30);
local file=shared();
assert(file[1].native_x==-30 and file[2].native_detached==true and file[2].detached_x==600,
    'The shared file has both characters\' group changes: '..tostring(file[1].native_x)..', '..tostring(file[2].native_detached)
    ..', '..tostring(file[2].detached_x));
assert(mine()[1].native_x==-30 and mine()[2].native_detached==true and mine()[2].detached_x==600,
    'This character takes the other group change as it publishes its own.');
local ok,_,found=other:load_layout(theirs);
assert(ok and found and theirs.party_ui.groups[2].native_detached==true and theirs.party_ui.groups[1].native_x==-30,
    'The other character keeps its change and takes this one.');

-- Two fields of one group: the other character puts Your party in a panel of its own while this one drags it.
frames(30);
other_changes(function(groups)groups[1].native_detached,groups[1].detached_x=true,700;end);
frames(4);
move(1,'native_y',25);
file=shared()[1];
assert(file.native_y==25 and file.native_x==-30 and file.native_detached==true and file.detached_x==700,
    'Each character\'s change to a field of the same group stays: '..tostring(file.native_y)..', '..tostring(file.native_detached)
    ..', '..tostring(file.detached_x));

-- Undo of this character's own group move after the other character changed another group.
frames(30);
move(3,'native_x',40);
assert(shared()[3].native_x==40,'Fixture: this character\'s move is shared.');
other_changes(function(groups)groups[2].detached_y=300;end);
frames(30);
assert(mine()[2].detached_y==300,'Fixture: this character follows the other character\'s change.');
command('/vg undo');frames(10);
file=shared();
assert(mine()[3].native_x==0 and file[3].native_x==0,
    'Undo puts this character\'s own group move back, here and in the shared file: '..mine()[3].native_x..', '..file[3].native_x);
assert(mine()[2].detached_y==300 and file[2].detached_y==300 and mine()[1].native_y==25,
    'Undo keeps the other character\'s change to another group, and this character\'s earlier move.');

-- The same with the presentation shared, where each group also has its member order.
command('/vg set shared_scope presentation');frames(30);
assert(other:save_layout(store.copy(settings())),'Fixture: the shared file is in presentation form.');
frames(30);
assert(order(shared()[1].order)=='0,1,2,3,4,5','Fixture: the presentation is shared, with each group\'s member order.');
other_changes(function(groups)groups[1].order,groups[2].order={5,4,3,2,1,0},{5,4,3,2,1,0};end);
frames(4);
move(1,'order',{1,0,2,3,4,5});
file=shared();
assert(order(file[2].order)=='5,4,3,2,1,0' and order(mine()[2].order)=='5,4,3,2,1,0',
    'With the presentation shared, a group this character left alone takes the other character\'s change: '..order(file[2].order));
assert(order(file[1].order)=='1,0,2,3,4,5' and order(mine()[1].order)=='1,0,2,3,4,5',
    'A member order both characters changed is one value, and this character\'s later one stays whole: '..order(file[1].order));
frames(30);
other_changes(function(groups)groups[3].order={2,1,0,3,4,5};end);
frames(30);
assert(order(mine()[3].order)=='2,1,0,3,4,5','Fixture: this character follows the other character\'s change.');
command('/vg undo');frames(10);
file=shared();
assert(order(mine()[1].order)=='0,1,2,3,4,5' and order(file[1].order)=='0,1,2,3,4,5',
    'With the presentation shared, Undo puts this character\'s own member order back: '..order(mine()[1].order));
assert(order(mine()[3].order)=='2,1,0,3,4,5' and order(file[3].order)=='2,1,0,3,4,5' and order(file[2].order)=='5,4,3,2,1,0',
    'And keeps the other character\'s changes to the other groups.');
return 'Two characters\' changes to different party groups, or different fields of one, both stay, and Undo puts back only this character\'s';
