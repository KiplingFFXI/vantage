-- A profile name of several words goes in quotes. /vg profile save, overwrite, load and delete refuse any word past
-- the one name, and rename and link any word past the names they take. Each says its usage line with the name in
-- quotes and changes nothing, so a name typed without quotes never reaches the profile its first word names. The same
-- commands with the name in quotes act on the whole name.
local store=require('core.store');
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=3,self_known=true,self_effects={},party={},entities={}};
require('app_fixture')(snapshot);
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local function settings()return app.state.settings;end;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked,'Fixture: Vantage takes '..text);end;
MOCK.fire('load');app.refresh(0);
app.state.dirty=true;assert(app.callbacks.save(),'Fixture: the settings are on disk.');
local root=app.state.path:gsub('Tester_1001/settings.json$','');
local function profiles()return store.read(root..'profiles.json') or {};end;
local function font(name)return profiles()[name] and profiles()[name].style.font_size;end;

-- The game's parser, Ashita's sugar/string.lua, loaded apart so it changes nothing else here. The mock's splits the
-- same way: a word ends at each space, and only quotes keep a name whole.
local function game_args()
    local copy={};for key,value in pairs(string)do copy[key]=value;end;
    local env=setmetatable({string=copy,T=function(t)return t;end,debug={setmetatable=function()end}},{__index=_G});
    local string_mt=setfenv(assert(loadfile(ASHITA_LIBS..'/sugar/string.lua')),env)()();
    return string_mt.args;
end;
local game=game_args();
for _,text in ipairs({'/vg profile overwrite WHM Merits','/vg profile rename PLD Tank PLD Main','/vg profile link 6 WHM Merits',
    '/vg profile load "WHM Merits"'})do
    local theirs,ours=table.concat(game(text),'|'),table.concat(text:args(),'|');
    assert(theirs==ours,'Fixture: the mock splits '..text..' as the game does: '..theirs..' against '..ours);
end;
local words=('/vg profile overwrite WHM Merits'):args();
assert(words[4]=='WHM' and words[5]=='Merits','Fixture: an unquoted name is split at its space.');
assert(('/vg profile load "WHM Merits"'):args()[4]=='WHM Merits','Fixture: a quoted name stays whole.');

-- Each profile is saved with its own font size, so the file shows which profile a command reached.
local function profile(name,size)
    command('/vg set style.font_size '..size);
    local ok,why=app.callbacks.profile_save(name,false);
    assert(ok and font(name)==size,'Fixture: '..name..' is saved: '..tostring(why));
end;
profile('WHM',20);profile('WHM Merits',21);profile('PLD',22);profile('PLD Tank',23);
command('/vg set style.font_size 30');
assert(settings().active_profile=='PLD Tank' and settings().style.font_size==30,'Fixture: PLD Tank is active, with a change not saved to it.');
assert(settings().job_profiles['6']==nil and settings().job_profiles['3']==nil,'Fixture: jobs 3 and 6 have no profile linked.');

-- Typed without quotes, each says its usage line, alone, and changes no profile, setting or Undo step.
for _,case in ipairs({
    {'/vg profile save Main Tank','Usage: /vg profile save "Name"'},
    {'/vg profile overwrite WHM Merits','Usage: /vg profile overwrite "Name"'},
    {'/vg profile load WHM Merits','Usage: /vg profile load "Name"'},
    {'/vg profile delete WHM Merits','Usage: /vg profile delete "Name"'},
    {'/vg profile rename PLD Tank PLD Main','Usage: /vg profile rename "Old" "New"'},
    {'/vg profile rename WHM Merits "Merits Old"','Usage: /vg profile rename "Old" "New"'},
    {'/vg profile link 6 WHM Merits','Usage: /vg profile link [job] "Name"'},
    {'/vg profile link WHM Merits','Usage: /vg profile link [job] "Name"'},
})do
    local text,usage=case[1],case[2];
    local file,before,steps=profiles(),store.copy(settings()),#app.state.history;
    MOCK.printed={};command(text);
    assert(store.equal(profiles(),file),text..' changes no saved profile.');
    assert(store.equal(settings(),before) and #app.state.history==steps,text..' changes no setting and makes no Undo step.');
    assert(#MOCK.printed==1 and MOCK.printed[1]=='[Vantage] '..usage,text..' says '..usage..': '..table.concat(MOCK.printed,' | '));
end;
assert(font('WHM')==20 and font('WHM Merits')==21 and font('PLD')==22 and font('PLD Tank')==23
    and font('Main')==nil and font('Main Tank')==nil and font('Tank')==nil and font('Merits')==nil,
    'No profile was saved, replaced, renamed or deleted.');

-- With the names in quotes, each acts on the whole name and leaves the profile its first word names.
command('/vg profile load "WHM Merits"');
assert(settings().active_profile=='WHM Merits' and settings().style.font_size==21,'load "Name" loads the whole name.');
command('/vg set style.font_size 32');
command('/vg profile overwrite "WHM Merits"');
assert(font('WHM Merits')==32 and font('WHM')==20,'overwrite "Name" replaces the whole name.');
command('/vg profile rename "PLD Tank" "PLD Main"');
assert(font('PLD Main')==23 and font('PLD Tank')==nil and font('PLD')==22,'rename "Old" "New" renames the whole name.');
command('/vg profile link 6 "WHM Merits"');
assert(settings().job_profiles['6']=='WHM Merits','link <job> "Name" links the whole name.');
command('/vg profile link "PLD Main"');
assert(settings().job_profiles['3']=='PLD Main','link "Name" links the whole name to the current job.');
command('/vg profile delete "WHM Merits"');
assert(font('WHM Merits')==nil and font('WHM')==20,'delete "Name" deletes the whole name.');
command('/vg profile save "Main Tank"');
assert(font('Main Tank')==32 and font('Main')==nil,'save "Name" saves the whole name.');
