-- Another character sharing the presentation removes a shared hide rule, or unchecks an effect a panel
-- includes. This character takes it at the poll, then undoes a personal change. The undone step must keep the
-- removal and publish nothing older: a list is one value, as the merge reads it, and a field the newer layout
-- dropped is dropped from the step too.
local store=require('core.store');
local profiles=require('core.profiles');
local SNAP={valid=true,id=1001,name='Tester',zone=102,job=3,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(SNAP);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
require('ui.party_hud').draw=function()return 0,{};end;
require('ui.native_party_hud').draw=function()return 0,{};end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end,suspend=function()return true;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local function settings()return app.state.settings;end;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
local function frames(count)for _=1,count do MOCK.frame(.11);end;end;
local function effects(list)local out={};for i,rule in ipairs(list)do out[i]=tostring(rule.effect);end;return table.concat(out,',');end;
MOCK.fire('load');
-- Each case is a character of its own, so its Undo history starts empty; they share one layout file.
local function start(id)
    SNAP.id,SNAP.name=id,'Tester'..id;
    app.refresh(MOCK.now);
    app.state.dirty=true;assert(app.callbacks.save());
    command('/vg set shared_layout true');frames(30);
    command('/vg set shared_scope presentation');frames(30);
    local root=app.state.path:gsub('Tester'..id..'_'..id..'/settings.json$','');
    return root..'shared_layout.json',profiles.new(root);
end;
local function rules_case(id,case)
    local layout_path,other=start(id);
    local filters=store.copy(settings().effect_filters);
    local first,second=require('core.effect_filters').rule(),require('core.effect_filters').rule();
    first.effect,second.effect=10,20;
    filters.rules={first,second};
    command('/vg set effect_filters '..store.encode(filters));frames(30);
    assert(effects(settings().effect_filters.rules)=='10,20','Fixture: two shared hide rules.');
    command('/vg set alerts.volume 40');frames(30);
    local theirs=store.copy(settings());
    local base=profiles.capture_layout(theirs);
    if case=='tail' then table.remove(theirs.effect_filters.rules,2);
    elseif case=='head' then table.remove(theirs.effect_filters.rules,1);
    else theirs.effect_filters.rules[2].effect=30; end;
    assert(other:publish_layout(theirs,base),'Fixture: the other character publishes.');
    frames(40);
    local want=case=='tail' and '10' or case=='head' and '20' or '10,30';
    assert(effects(settings().effect_filters.rules)==want,'Fixture: the poll took it: '..effects(settings().effect_filters.rules));
    command('/vg undo');frames(30);
    assert(settings().alerts.volume~=40,'Fixture: the undo restored the volume.');
    assert(effects(settings().effect_filters.rules)==want,
        ('Undo keeps the other character\'s %s rules here: %s, want %s.'):format(case,effects(settings().effect_filters.rules),want));
    assert(effects(store.read(layout_path).presentation.effect_filters.rules)==want,'And publishes them, not the older list.');
end;
rules_case(1001,'tail');
rules_case(1002,'head');
rules_case(1003,'edit');

-- One of two included effects unchecked by the other character, then Undo of a personal change here.
local layout_path,other=start(1004);
command('/vg set panels.self_buffs.include {"33":true,"40":true}');frames(30);
assert(settings().panels.self_buffs.include[33] and settings().panels.self_buffs.include[40],'Fixture: two included effects.');
command('/vg set tracking.stale_seconds 300');frames(30);
local theirs=store.copy(settings());
local base=profiles.capture_layout(theirs);
theirs.panels.self_buffs.include[33]=nil;
assert(other:publish_layout(theirs,base),'Fixture: the other character publishes.');
frames(40);
assert(settings().panels.self_buffs.include[33]==nil,'Fixture: the poll took the removal.');
command('/vg undo');frames(30);
assert(settings().tracking.stale_seconds~=300,'Fixture: the undo restored the stale time.');
local file=assert(store.read(layout_path));
assert(settings().panels.self_buffs.include[33]==nil and settings().panels.self_buffs.include[40],'Undo keeps the removal here.');
assert(file.presentation.panels.self_buffs.include['33']==nil,'And does not publish the removed effect again.');
