-- After a save publishes the shared layout, the base kept for the next save is this character's own layout,
-- as load and poll keep it, whatever form the file is in. A base in the file's full presentation form never
-- matches again, so every later save would write the shared file and could put back another character's move.
local store=require('core.store');
local profiles=require('core.profiles');
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=3,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(snapshot);end};
package.loaded['core.observer']={read=function()return {};end};
local app=dofile(ADDON_DIR..'/vantage.lua');
MOCK.fire('load');app.refresh(0);
local state,callbacks=app.state,app.callbacks;
state.dirty=true;assert(callbacks.save(),'Fixture: the settings are on disk.');
local folder=state.path:gsub('Tester_1001/settings.json$','');
local layout_path=folder..'shared_layout.json';
local layout_writes=0;
local write=store.write;
store.write=function(path,...)if path==layout_path then layout_writes=layout_writes+1;end;return write(path,...);end;
local function move(id,dx)
    callbacks.changed('before','Move');
    state.settings.panels[id].x=state.settings.panels[id].x+dx;
    callbacks.changed('after',nil,'status');
    assert(callbacks.save(),'Fixture: the move is saved.');
end;
local function navigate(count)
    for _=1,count do
        state.settings.window.sections['Home/Recasts']=not state.settings.window.sections['Home/Recasts'];
        callbacks.editor_changed();
        assert(callbacks.save(),'Fixture: the navigation is saved.');
    end;
end;
local function panels(file)return file.scope=='presentation' and file.presentation.panels or file;end;

-- This character shared full presentation, then switched to placement: the file keeps its presentation form.
assert(callbacks.sharing(true,'presentation') and callbacks.sharing(true,'placement'),'Fixture: sharing switched to placement.');
assert(store.read(layout_path).scope=='presentation','Fixture: the shared file is in presentation form.');
move('self_buffs',5);
assert(state.shared_value and state.shared_value.scope==nil and store.equal(state.shared_value,profiles.capture_layout(state.settings)),
    'After publishing, the base is this character\'s own placement layout.');
layout_writes=0;
navigate(10);
assert(layout_writes==0,'Saves that change nothing shared never write the shared file again.');

-- Another character moves a different panel and publishes. This character's next save, before its poll
-- reads that, keeps the other character's move in the file.
local before=state.settings.panels.self_debuffs.x;
local other=profiles.new(folder);
local theirs=store.copy(state.settings);
theirs.shared_scope='presentation';
assert(other:load_layout(theirs),'Fixture: the other character read the file.');
local base=profiles.capture_layout(theirs);
theirs.panels.self_debuffs.x=777;
assert(other:publish_layout(theirs,base),'Fixture: the other character published its move.');
assert(panels(store.read(layout_path)).self_debuffs.x==777,'Fixture: the file holds the other character\'s move.');
navigate(1);
assert(panels(store.read(layout_path)).self_debuffs.x==777,'A navigation save never puts back another character\'s move.');
assert(state.settings.panels.self_debuffs.x==before,'Fixture: this character has not polled the move yet.');
return true;
