local defaults,custom=require('ui.defaults'),require('core.customization');
local presets,hud=require('setup_fixture'),require('ui.hud');
local copy=require('core.store').copy;
local status={'self_buffs','self_debuffs','target','party','watch'};
local fresh=defaults.make();
for _,value in ipairs({{}, {mode='invalid'}, {mode=false}})do
    local s=defaults.tidy({panels={self_buffs=copy(value)}});
    assert(s.panels.self_buffs.mode=='icons' and s.panels.self_buffs.stack_direction=='horizontal','Missing or invalid layout values use the current defaults.');
end;
-- Party timers and Watched enemies start as bars, which name whose effect each row is.
for _,id in ipairs({'party','watch'})do
    local p=fresh.panels[id];
    assert(p.mode=='bars' and p.stack_direction=='vertical' and p.show_target,id..' starts as vertical bars that name the target.');
end;
for _,id in ipairs(status)do
    local p=fresh.panels[id];
    local icons=id~='party' and id~='watch';
    assert(not icons or p.mode=='icons' and p.stack_direction=='horizontal',id..' starts with horizontal icons.');
    local r=icons and hud.bounds(p,fresh.style,12,1920,1080);
    assert(not icons or not r.vertical and r.columns>1 and r.shown==12,'Default icons fill a row before wrapping.');
    assert(p.countdown_outline and p.sort=='longest' and p.locked,'Countdown, sorting and lock defaults are retained.');
end;
for id in pairs(defaults.recast_panels)do
    assert(fresh.panels[id].mode=='bars' and fresh.panels[id].stack_direction=='vertical','Recast presentation is independent.');
end;
local saved=defaults.make();
for _,id in ipairs(status)do
    local p=saved.panels[id];
    p.mode,p.stack_direction,p.width,p.locked='expanded','vertical',431,false;
    p.include,p.exclude,p.labels,p.order={33},{40},{['33']='Sample speed'},{33};
end;
saved=defaults.tidy(saved);
local before=copy(saved);
assert(custom.equal(defaults.tidy(copy(saved)),before),'Loading existing explicit presentation choices never replaces them.');
for _,size in ipairs({'minimal','minimal_1_5x','minimal_2x'})do
    local s=copy(saved);assert(presets.apply(s,{skin='keep',size=size,label='full'}));
    for _,id in ipairs(status)do
        local p=s.panels[id];
        -- Party timers and Watched enemies keep the layout the player set: their bars default is for a fresh
        -- install only. The other status panels take their icons default.
        local icons=id~='party' and id~='watch';
        assert(icons and p.mode=='icons' and p.stack_direction=='horizontal' or not icons and p.mode=='expanded' and p.stack_direction=='vertical',
            'A complete setup uses the icons default and keeps the party and watch layouts.');
        assert(p.x==before.panels[id].x and p.y==before.panels[id].y and not p.locked);
        for _,key in ipairs({'include','exclude','labels','order'})do assert(custom.equal(p[key],before.panels[id][key]));end;
        local r=icons and hud.bounds(p,s.style,12,4000,3000);
        assert(not icons or not r.vertical and r.columns>1 and r.shown==12,'Each setup scale remains horizontal without dropping effects.');
    end;
end;
-- Party timers and Watched enemies set to icons stay icons, and a fresh install's stay bars.
for _,case in ipairs({{mode='icons',stack='horizontal'},{mode='bars',stack='vertical'}})do
    local s=defaults.tidy(defaults.make());
    if case.mode=='icons' then for _,id in ipairs({'party','watch'})do s.panels[id].mode,s.panels[id].stack_direction='icons','horizontal';end;end;
    assert(presets.apply(s,{skin='keep',size='minimal',label='full'}));
    for _,id in ipairs({'party','watch'})do
        assert(s.panels[id].mode==case.mode and s.panels[id].stack_direction==case.stack,id..' keeps its '..case.mode..' layout through Apply.');
    end;
end;
assert(#MOCK.commands==0,'Defaults and setup changes do not issue game commands.');
