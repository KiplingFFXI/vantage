-- Commands that change nothing say why, and nothing a command can't keep is changed without a word: /vg font
-- with no name or a name no font has, /vg after a page error stopped the window, a change before a character loads,
-- and a profile whose name reads as a number linked with the no-job form.
local store=require('core.store');
local SNAP={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_effects={},party={},entities={}};
require('app_fixture')(SNAP);
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end,suspend=function()return true;end};
local page;
package.loaded['ui.main_page']={labels={},draw=function(_,s,_,callbacks,ui)if page then page(s,callbacks,ui);end;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local function settings()return app.state.settings;end;
local function disk()return store.read(app.state.path);end;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
local function frames(count)for _=1,count do MOCK.frame(.11);end;end;
local function printed_since(count)
    local out={};
    for index=count+1,#MOCK.printed do out[#out+1]=MOCK.printed[index]; end;
    return table.concat(out,' | ');
end;
-- Before a character loads.
SNAP.valid=false;
MOCK.fire('load');app.refresh(0);frames(3);
local count=#MOCK.printed;
command('/vg set style.font_size 30');frames(3);
local said=printed_since(count);
SNAP.valid=true;frames(5);
assert(app.state.identity,'Fixture: a character loaded.');
assert(said:find('before a character loads',1,true),'A change made before a character loads says it is replaced: '..said);
assert(settings().style.font_size~=30,'Fixture: the saved settings replace it.');
assert(app.state.problem==nil,'That message ends when the character loads.');

-- /vg font with no name.
app.state.dirty=true;assert(app.callbacks.save());
local font=settings().style.font;
count=#MOCK.printed;
command('/vg font');frames(10);
assert(settings().style.font==font and disk().style.font==font,'/vg font with no name keeps the font: '..string.format('%q',settings().style.font));
assert(printed_since(count):find('Usage',1,true),'And shows how to use it.');

-- /vg font finds a font without regard to case, by its name or by the name the main page's list shows for it, so it
-- never saves a name no font has. One that matches nothing keeps the font and lists the choices.
command('/vg font segoe ui');frames(2);
assert(settings().style.font=='Segoe UI' and disk().style.font=='Segoe UI' and app.state.history[#app.state.history].label=='Font',
    '/vg font segoe ui picks Segoe UI, as one Undo step: '..string.format('%q',settings().style.font));
for _,case in ipairs({{'"Ashita (Agave)"','Agave'},{'original ffxi','Original FFXI'},{'ashita','Agave'},{'xi VIEW','XI View'}})do
    command('/vg font '..case[1]);frames(2);
    assert(settings().style.font==case[2] and disk().style.font==case[2],
        '/vg font '..case[1]..' picks '..case[2]..': '..string.format('%q',settings().style.font));
end;
-- A custom font can have the name the list shows for another. The first match in the list still wins.
local names=require('ui.fonts').names();
names[#names+1]='Ashita (Agave)';
for _,typed in ipairs({'"Ashita (Agave)"','agave'})do
    command('/vg font Segoe UI');command('/vg font '..typed);frames(2);
    assert(settings().style.font=='Agave','/vg font '..typed..' still picks Agave: '..string.format('%q',settings().style.font));
end;
names[#names]=nil;
font,count=settings().style.font,#MOCK.printed;
local steps=#app.state.history;
command('/vg font Nope');frames(2);
local choices=printed_since(count);
assert(settings().style.font==font and disk().style.font==font and #app.state.history==steps,
    '/vg font with a name no font has keeps the font: '..string.format('%q',settings().style.font));
assert(choices:find('Choose Ashita (Agave), Segoe UI, Arial, ',1,true) and choices:find(', Original FFXI or XI View.',1,true),
    'And lists the choices as the main page shows them: '..choices);

-- /vg after a page error.
command('/vg');frames(2);
assert(settings().window.open and app.callbacks.settings_blocks_input(200,200,false,false),'Fixture: the window is drawn.');
page=function()page=nil;error('Fixture settings page failure.');end;
frames(2);
assert(not app.callbacks.settings_blocks_input(200,200,false,false),'Fixture: the window stopped.');
count=#MOCK.printed;
command('/vg');frames(2);
assert(not settings().window.open and printed_since(count):find('/vg opens it again',1,true),
    'The first /vg after a stop closes the window and says the next one opens it.');
command('/vg');frames(2);
assert(app.callbacks.settings_blocks_input(200,200,false,false),'The next /vg opens it.');

-- A profile named "5" linked to the current job, with job 5 linked elsewhere.
command('/vg profile save "Melee"');
command('/vg profile save "5"');
command('/vg profile link 5 "Melee"');
SNAP.job=3;frames(3);
assert(settings().job_profiles['5']=='Melee','Fixture: job 5 is linked to Melee.');
command('/vg profile link "5"');
assert(settings().job_profiles['3']=='5' and settings().job_profiles['5']=='Melee',
    'A quoted name links the current job: job 3 '..tostring(settings().job_profiles['3'])..', job 5 '..tostring(settings().job_profiles['5']));
command('/vg profile link 5');
assert(settings().job_profiles['5']==nil,'A job ID with no name still unlinks that job.');

-- /vg minimal names its switch the way Boxes does, in chat and in Undo.
assert(not settings().style.minimal,'Fixture: No boxes or headings starts off.');
count=#MOCK.printed;
command('/vg minimal on');frames(2);
assert(settings().style.minimal and printed_since(count):find('No boxes or headings is on.',1,true)
    and app.state.history[#app.state.history].label=='No boxes or headings',
    '/vg minimal says No boxes or headings, in chat and as its Undo step: '..printed_since(count));
