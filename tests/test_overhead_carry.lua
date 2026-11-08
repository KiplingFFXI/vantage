-- settings.overhead travels as the other displays' settings do. A named profile keeps all of it but the samples and
-- loads it as one Undo step; a job-linked profile brings it on a job change; a profile without it leaves the
-- overhead icons as they are, and a profile's saved samples never come back on. A settings file without them, or
-- without their samples, loads them off with no samples. A skin and Apply setup keep their switches, layouts and
-- filters and give them the skin's look, and the question before them names Overhead icons when they have a look of
-- their own. Shared presentation gives another character all of them but their switch and samples.
local store=require('core.store');
local SNAP={valid=true,id=1001,name='Tester',zone=102,job=3,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(SNAP);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end,suspend=function()return true;end};
local imgui=require('imgui');
local defaults=require('ui.defaults');
local custom=require('core.customization');
local appearance,presets=require('ui.appearance'),require('setup_fixture');
local copy=store.copy;
local app=dofile(ADDON_DIR..'/vantage.lua');
local window=require('ui.settings_window');
MOCK.fire('load');app.refresh(0);
local function settings()return app.state.settings;end;
local function frames(count)for _=1,count do MOCK.frame(.11);end;end;
local function switch_back()
    SNAP.id,SNAP.name=2002,'Second';frames(10);
    assert(app.state.identity=='2002:Second','Fixture: switched.');
    SNAP.id,SNAP.name=1001,'Tester';frames(10);
    assert(app.state.identity=='1001:Tester','Fixture: back.');
end;
local profile_path=require('core.identity').root()..'profiles.json';

-- A settings file without overhead icons, or without their samples: off, with no samples.
local old=defaults.tidy({style={font_size=20}});
assert(old.overhead.enabled==false and old.overhead.preview==false and old.style.font_size==20,'Without them saved: off, with no samples.');
local partial=defaults.tidy({overhead={enabled=true,max_units=4}});
assert(partial.overhead.enabled and partial.overhead.preview==false and partial.overhead.max_units==4,'A save without the samples keeps the rest.');
app.state.dirty=true;assert(app.callbacks.save(),'Fixture: the settings are on disk.');
local file=store.read(app.state.path);
file.overhead=nil;file.style.font_size=21;
assert(store.write(app.state.path,file),'Fixture: a save without overhead icons.');
switch_back();
assert(settings().style.font_size==21 and not settings().overhead.enabled and settings().overhead.preview==false,
    'Logging in with a save without them: overhead icons off, no samples, the rest as saved.');

-- A named profile keeps them, but not the samples.
local o=settings().overhead;
o.enabled,o.preview,o.units.other,o.max_units,o.size.base=true,true,true,6,30;
o.types.mob.layout,o.types.mob.include,o.head.offsets=('split'),{2,4},{Fafnir=0.5};
assert(app.callbacks.profile_save('Overhead',false),'Fixture: Overhead saved.');
local kept=store.read(profile_path).Overhead.overhead;
assert(kept.enabled and kept.preview==false and kept.units.other and kept.max_units==6 and kept.size.base==30
    and kept.types.mob.layout=='split' and kept.types.mob.include[2]==4 and kept.head.offsets.Fafnir==0.5,
    'The profile keeps the overhead icons, without their samples.');
assert(settings().overhead.preview,'Saving leaves the samples on.');
assert(not app.callbacks.profile_status('Overhead').modified,'The samples don\'t mark the profile modified.');
-- Loading it brings them back as one Undo step, the samples off. The samples are on before it, so the icons are too.
o=settings().overhead;
assert(o.enabled and o.preview,'Fixture: the icons and their samples are on.');
o.types.mob.layout,o.max_units,o.head.offsets='single',10,{};
local count=#app.state.history;
assert(app.callbacks.profile_load('Overhead'),'Fixture: Overhead loaded.');
o=settings().overhead;
assert(o.enabled and o.types.mob.layout=='split' and o.max_units==6 and o.head.offsets.Fafnir==0.5 and o.preview==false,
    'Loading brings back the profile\'s overhead icons, with the samples off.');
assert(#app.state.history==count+1,'Loading is one Undo step.');
assert(app.callbacks.undo() and settings().overhead.types.mob.layout=='single' and settings().overhead.preview,'Undo puts back what was there.');
assert(app.callbacks.redo() and settings().overhead.types.mob.layout=='split','Redo loads it again.');

-- A profile without overhead icons leaves them as they are; a profile's saved samples never come back on.
local database=store.read(profile_path);
database.Bare=copy(database.Overhead);database.Bare.overhead=nil;database.Bare.style.font_size=23;
database.Samples=copy(database.Overhead);database.Samples.overhead.preview=true;database.Samples.overhead.max_units=7;
assert(store.write(profile_path,database),'Fixture: the two profiles.');
settings().overhead.preview,settings().overhead.max_units=true,9;
assert(app.callbacks.profile_load('Bare'));
assert(settings().style.font_size==23 and settings().overhead.max_units==9 and settings().overhead.preview,
    'A profile without them leaves the overhead icons and their samples as they are.');
assert(app.callbacks.profile_load('Samples'));
assert(settings().overhead.max_units==7 and settings().overhead.preview==false,'A profile\'s saved samples stay off.');

-- A job-linked profile brings them on a job change.
assert(app.callbacks.profile_link(5,'Overhead'),'Fixture: Overhead linked to RDM.');
o=settings().overhead;
o.enabled,o.types.mob.layout,o.preview=false,'lines',true;
app.state.dirty=true;app.callbacks.save();
SNAP.job=5;frames(10);
o=settings().overhead;
assert(settings().active_profile=='Overhead' and o.enabled and o.types.mob.layout=='split' and o.max_units==6 and o.preview==false,
    'Changing to RDM loads the linked profile\'s overhead icons, with the samples off.');

-- A skin keeps the switches, layouts and filters and gives them its look; the question names them first.
local function fresh()
    local s=defaults.tidy(defaults.make());
    local v=s.overhead;
    v.enabled,v.preview,v.units.other,v.types.mob.layout,v.types.party.include,v.max_units=true,true,true,'split',{33},5;
    v.size.base,v.head.offsets=31,{Fafnir=0.5};
    return s;
end;
local function behavior(v)
    local value=copy(v);
    value.countdown_color,value.dispel_color=nil,nil;
    return value;
end;
local s=fresh();
assert(#appearance.replaced(s)==0,'Their default look is the skin\'s.');
s.overhead.countdown_color,s.overhead.dispel_color={1,0,0,1},{0,1,0,1};
local named;
for _,entry in ipairs(appearance.replaced(s))do if entry.label=='Overhead icons' then named=entry;end;end;
assert(named and named.page=='Display' and named.panel=='overhead','Their own look is named, with their panel.');
local skinned=copy(s);
assert(appearance.apply(skinned,'Mint',{matching=true}));
assert(skinned.overhead.countdown_color[2]==1 and skinned.overhead.dispel_color[1]==1
    and custom.equal(behavior(skinned.overhead),behavior(s.overhead)),'A skin with its fonts gives them its look and keeps the rest.');
local kept_font=copy(s);
assert(appearance.apply(kept_font,'Mint',{matching=false}));
assert(kept_font.overhead.countdown_color[2]==1,'A skin without its fonts gives them its look too.');
named=nil;
for _,entry in ipairs(appearance.replaced(s,skinned))do if entry.label=='Overhead icons' then named=entry;end;end;
assert(named,'A skin pick names them.');

-- The main page's skin pick asks first, naming them, then applies in one step.
local combo;
imgui.BeginCombo=function(label) return label==combo;end;
local function frame(click,opened)
    combo=opened;
    MOCK.imgui_calls={};
    if click then MOCK.clicks[click]=true;end;
    window.draw(app.state.settings,{rows={},context={valid=false}},app.callbacks);
    if click then assert(not MOCK.clicks[click],'The control is on screen: '..click);end;
end;
local function said(text)
    for _,call in ipairs(MOCK.imgui_calls)do if call[1]=='TextWrapped' and tostring(call[2]):find(text,1,true) then return call[2];end;end;
end;
s=fresh();
s.overhead.countdown_color={1,0,0,1};
s.window.open,s.window.tab=true,'Home';
app.state.settings=s;
frame();
app.state.history,app.state.redo,app.state.transaction={},{},nil;
local before=copy(s.overhead);
frame('Mint##Mint','##main_skin');
frame();
assert(said('Overhead icons') and custom.equal(s.overhead,before),'The skin pick names Overhead icons and waits.');
frame('Apply##look_main_skin');
s=app.state.settings;
assert(s.overhead.countdown_color[2]==1 and custom.equal(behavior(s.overhead),behavior(before)),'Apply gives them the skin\'s look and keeps the rest.');
assert(#app.state.history==1 and app.state.history[1].label=='Skin: Mint','In one Undo step.');
assert(app.callbacks.undo() and app.state.settings.overhead.countdown_color[2]==0,'Undo puts their colors back.');

-- Apply setup (a size and a skin) keeps their switches, layouts and filters, scales them through Timer scale and
-- gives them the skin's look; Apply size starts their colors again.
s=fresh();
s.overhead.dispel_color={0,0,1,1};
local setup=copy(s);
assert(presets.apply(setup,{skin='XI View',size='minimal_2x',matching=true,window_type=1}));
assert(setup.style.scale==2 and setup.overhead.dispel_color[3]==0.25
    and custom.equal(behavior(setup.overhead),behavior(s.overhead)),'Apply setup restyles them and keeps the rest.');
local sized=copy(s);
assert(presets.apply(sized,{skin='keep',size='minimal',matching=false,window_type=1}));
assert(sized.overhead.dispel_color[3]==0.25 and custom.equal(behavior(sized.overhead),behavior(s.overhead)),
    'Apply size starts their colors again.');
named=nil;
for _,entry in ipairs(appearance.replaced(s,setup))do if entry.label=='Overhead icons' then named=entry;end;end;
assert(named,'Apply setup names them before it replaces their look.');

-- Shared presentation gives another character their settings but not their switch or samples, as the strips keep
-- theirs; placement sharing and a shared file without them leave them as they are.
local profiles=require('core.profiles');
local shared=profiles.new(MOCK_INSTALL_PATH..'/config/addons/vantage');
local from,to=fresh(),defaults.tidy(defaults.make());
from.overhead.countdown_color={1,0,0,1};
local layout=profiles.capture_layout(from,'presentation');
local carried=layout.presentation.overhead;
assert(carried and carried.enabled==nil and carried.preview==nil and carried.types.mob.layout=='split',
    'Shared presentation carries them without their switch or samples.');
assert(shared:save_layout(from,'presentation'),'Fixture: the shared file.');
local placed=copy(to);
assert(shared:load_layout(placed,'placement') and custom.equal(placed.overhead,to.overhead),'Placement sharing leaves them.');
assert(shared:load_layout(to,'presentation'),'Fixture: presentation loaded.');
local v=to.overhead;
assert(v.types.mob.layout=='split' and v.max_units==5 and v.units.other and v.size.base==31 and v.head.offsets.Fafnir==0.5
    and v.types.party.include[1]==33 and v.countdown_color[2]==0,'Shared presentation brings their layouts, filters, sizes and look.');
assert(not v.enabled and not v.preview,'Their switch and samples stay this character\'s.');
-- The switch and samples aren't shared, and ones written into the file aren't taken.
local before=profiles.capture_layout(to,'presentation');
v.enabled,v.preview=true,false;
assert(custom.equal(profiles.capture_layout(to,'presentation'),before),'Turning them on changes nothing shared.');
carried.enabled,carried.preview=false,true;
assert(store.write(shared.layout_path,layout)and shared:load_layout(to,'presentation'),'Fixture: switches written into the file.');
assert(to.overhead.enabled and not to.overhead.preview,'Switches written into the file aren\'t taken.');
to.overhead.max_units=3;
assert(store.write(shared.layout_path,{scope='presentation',presentation={style=defaults.make().style}})
    and shared:load_layout(to,'presentation'),'Fixture: a shared file without them.');
assert(to.overhead.max_units==3 and to.overhead.types.mob.layout=='split' and to.overhead.enabled,'A shared file without them leaves them.');
return 'Profiles, job links, skins, Apply setup and shared presentation carry the overhead icons';
