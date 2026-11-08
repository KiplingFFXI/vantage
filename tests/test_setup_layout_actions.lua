local defaults,presets=require('ui.defaults'),require('setup_fixture');
local copy,custom=require('core.store').copy,require('core.customization');
local appearance=require('ui.appearance');
-- The look the party list buffs draw with: the timer panels' look, with their own icons and opacity.
local party_look=require('ui.party_theme').party;
local imgui=require('imgui');
require('ui.fonts').measure=function(_,value,size)return #value*7*size/16;end;
MOCK.screen={4000,3000};
-- Each setup size and the timer scale it sets.
local sizes={{'minimal',1},{'minimal_1_5x',1.5},{'minimal_2x',2}};
-- A character with every display customized.
local function seed(face,locked)
    local s=defaults.make();assert(appearance.apply(s,face=='Agave' and 'Mint' or face));
    local p=s.party_ui;
    p.enabled,p.preview,p.locked=true,false,not locked;
    p.strips.alliance1=false;
    p.style.icon_art,p.style.opacity=face=='XI View' and 'Client' or 'XI View',.6;
    p.name_display,p.name_length='short',6;
    p.groups[2].order={5,4,3,2,1,0};
    p.groups[2].native_x,p.groups[2].native_side,p.groups[3].native_detached,p.groups[3].detached_x=-12,'right',true,333;
    p.effects.exclude,p.effects.sort={33},'name';
    p.effects.countdown_outline,p.effects.growth=false,'left';
    p.effects.icon_size=41;
    s.style.font_size,s.style.scale,s.style.icon_size,s.style.bar_height=29,3,47,61;
    s.window_style.font_size=31;
    for index,id in ipairs(defaults.panel_order)do
        local panel=s.panels[id];
        panel.x,panel.y,panel.locked,panel.enabled=100+index*13,200+index*17,index%2==0,index%3==0;
        panel.width,panel.height_limit,panel.mode,panel.auto_width,panel.auto_height=447,411,'expanded',true,false;
        panel.bar_style,panel.bar_thickness,panel.row_height,panel.wrap='full',11,49,true;
        panel.exclude,panel.include,panel.labels,panel.order={33},{40},{['40']='Custom protection'},{40};
        panel.filter,panel.mine_only,panel.known_only,panel.members='Protect',true,true,{[42]=true};
        panel.anchor.side,panel.anchor.gap,panel.anchor.align,panel.anchor.offset='above',9,'end',13;
        panel.colors={text={.2,.4,.6,1}};
    end;
    local rule=defaults.rule('kept-rule');rule.effect,rule.sound,rule.visual=33,'',true;
    s.alerts.rules,s.alerts.enabled,s.alerts.muted,s.alerts.volume={rule},false,true,31;
    s.alerts.notice_x,s.alerts.notice_y,s.alerts.notice_width,s.alerts.notice_height,s.alerts.notice_locked=117,228,777,123,false;
    s.alerts.max_notices=7;
    s.pet.x,s.pet.y=905,640;
    s.rolls.x,s.rolls.y=905,300;
    s.effect_filters.rules={{enabled=true,effect=253,kind='all',name='Sample',job=0,scope='self'}};
    s.job_profiles={['1']='Saved setup'};s.active_profile='Saved setup';
    return defaults.tidy(s);
end;
local function same_fields(a,b,keys,label)
    for _,key in ipairs(keys)do assert(custom.equal(a[key],b[key]),label..' preserves '..key);end;
end;
local panel_data={'enabled','x','y','locked','include','exclude','pinned','order','labels','groups','members','filter','mine_only','known_only',
    'anchor','dock_match_width'};
local function data_preserved(after,before)
    same_fields(after,before,{'effect_filters','groups','tracking','watch_ids','job_profiles','active_profile','shared_layout','shared_scope',
        'enabled','preview','recast_display'},'Full setup');
    same_fields(after.party_ui,before.party_ui,{'enabled','preview','locked','strips','name_display','name_length'},'Party list strips');
    for index,group in ipairs(after.party_ui.groups)do
        same_fields(group,before.party_ui.groups[index],{'order','native_x','native_y','native_side','native_detached','detached_x','detached_y'},'Party group');
    end;
    for _,id in ipairs(defaults.panel_order)do same_fields(after.panels[id],before.panels[id],panel_data,id);end;
    same_fields(after.party_ui.effects,before.party_ui.effects,{'include','exclude','pinned','icon_size'},
        'party_ui effects');
    same_fields(after.alerts,before.alerts,{'rules','enabled','muted','volume','notice_x','notice_y','notice_locked'},'Alerts');
end;
for _,spec in ipairs(sizes)do for _,face in ipairs({'Original FFXI','XI View','Agave'})do
    for _,locked in ipairs({false,true})do
        local s=seed(face,locked);local before=copy(s);
        local options={skin='keep',size=spec[1]};
        local preview=presets.build(s,options);assert(preview and custom.equal(s,before),'Building the setup changes no saved setting.');
        assert(presets.apply(s,options) and custom.equal(s,preview),'Build and Apply share the complete all-display recipe.');
        local p=s.party_ui;
        local basis=face=='Agave' and 'Mint' or face;
        local canonical=defaults.make();assert(appearance.apply(canonical,basis));
        assert(s.style.font_size==16 and s.style.scale==spec[2] and s.style.icon_size==canonical.style.icon_size,
            'Global font and icon bases reset once; selected size scales their physical rendering once.');
        assert(s.style.font==canonical.style.font and p.style.icon_art==canonical.party_ui.style.icon_art,'Current skin supplies clean defaults across every display and the menu.');
        assert(s.window_style.font_size==before.window_style.font_size,'Menu text size stays as set.');
        assert(p.style.opacity==canonical.party_ui.style.opacity,'Stale local visual overrides are cleared by the full setup.');
        for _,id in ipairs(defaults.panel_order)do
            local panel,fresh=s.panels[id],canonical.panels[id];
            -- Party timers and Watched enemies keep the layout the player set; bars are their fresh-install default only.
            local mode=(id=='party' or id=='watch') and before.panels[id].mode or fresh.mode;
            assert(panel.width==300*spec[2] and panel.mode==mode and panel.auto_height==fresh.auto_height
                and panel.auto_width==fresh.auto_width and panel.bar_style==fresh.bar_style and panel.row_height==fresh.row_height,
                'Every status and recast display receives canonical defaults: '..id);
            assert(panel.item_width==fresh.item_width,'Horizontal cell width keeps its base units and scales once: '..id);
            assert(next(panel.colors)==nil,'Old panel colors cannot survive a full default setup: '..id);
        end;
        assert(s.alerts.notice_width==before.alerts.notice_width and s.alerts.notice_height==before.alerts.notice_height
            and s.alerts.max_notices==before.alerts.max_notices,'Alert notice width, height and count stay as set.');
        data_preserved(s,before);
        local applied=seed(face,locked);
        assert(presets.apply(applied,{skin='Mint',size=spec[1],matching=true}),'The chosen skin and size apply.');
        -- The party list buffs wear the timer panels' look.
        assert(applied.style.theme=='Mint' and party_look(applied.party_ui,applied.style).theme=='Mint' and applied.style.scale==spec[2],
            'Explicit staged choices apply to the complete setup.');
    end;
end;end;
for _,invalid in ipairs({'extended','extended_1_5x','extended_2x','unknown',''})do
    local s=seed('Original FFXI',true);local before=copy(s);
    assert(not presets.apply(s,{skin='keep',size=invalid}) and custom.equal(s,before));
    assert(not presets.apply(s,{skin='Mint',size=invalid}) and custom.equal(s,before),
        'An invalid size changes no settings.');
end;
-- The explicit font/artwork opt-out survives even a complete default setup.
for _,spec in ipairs(sizes)do for _,skin in ipairs(appearance.names)do
    local source=seed('XI View',true);
    source.style.font,source.style.icon_art='Tahoma Bold','Client';
    local before=copy(source);
    assert(presets.apply(source,{size=spec[1],skin=skin,matching=false}));
    for _,key in ipairs({'font','gauge_art','icon_art','recast_icon_art'})do
        assert(source.style[key]==before.style[key],'Unmatched full setup preserves the selected global family: '..key);
    end;
    same_fields(source.party_ui.style,before.party_ui.style,{'icon_art'},'Unmatched party_ui');
    -- The party list buffs keep their own icons, at the setup's font size.
    assert(party_look(source.party_ui,source.style).icon_art==before.party_ui.style.icon_art,'Unmatched party list buffs keep their icons');
    assert(source.style.scale==spec[2] and source.style.font_size==16 and party_look(source.party_ui,source.style).font_size==16);
    data_preserved(source,before);
end;end;
local profiles=require('core.profiles').new(MOCK_INSTALL_PATH..'/config/addons/vantage/setup-layout-profiles');
for _,spec in ipairs(sizes)do
    local saved=seed('XI View',true);assert(presets.apply(saved,{skin='keep',size=spec[1]}));
    assert(profiles:save_new('Setup '..spec[1],saved));
    local receiver=defaults.make();assert(profiles:load('Setup '..spec[1],receiver));
    assert(receiver.style.scale==spec[2] and party_look(receiver.party_ui,receiver.style).font=='XI View'
        and receiver.party_ui.locked==saved.party_ui.locked,
        'Named profiles preserve explicit setup scaling, font family and locks.');
    assert(profiles:save_layout(saved,'presentation'));
    receiver=defaults.make();receiver.party_ui.locked=not saved.party_ui.locked;
    assert(profiles:load_layout(receiver,'presentation'));
    assert(receiver.style.scale==spec[2] and receiver.party_ui.locked~=saved.party_ui.locked,
        'Shared presentation preserves the setup size without changing the receiving lock.');
end;
local app=dofile(ADDON_DIR..'/vantage.lua');
local window=require('ui.settings_window');
local current;
-- Manual controls remain usable after a setup and keep the chosen size. Party opacity is with the party list buffs'
-- own icons; the party list has no font size of its own.
local sliders=imgui.SliderFloat;
for _,entry in ipairs({{'look','Opacity',0.5,function(p) return p.style.opacity==0.5; end},
    {'place','Longest row',300,function(p) return p.native.width==300; end}})do
    app.state.settings=seed('XI View',true);current=app.state.settings;
    assert(presets.apply(current,{skin='keep',size='minimal_2x'}));
    current.window.open,current.window.tab,current.party_ui.locked=true,'Display',false;
    require('ui.panel_frame').open('party_ui',entry[1]);
    local pending=entry[3];
    imgui.BeginCombo=function()return false;end;
    imgui.SliderFloat=function(label,value,...)
        if label=='##frame_'..entry[2] and pending then value[1],pending=pending,nil;return true;end;
        return sliders(label,value,...);
    end;
    local before=custom.history_value(current);app.state.history,app.state.redo,app.state.transaction={},{},nil;
    window.draw(current,{rows={},context={}},app.callbacks);
    assert(pending==nil and #app.state.history==1,'The real manual control remains available after setup: '..entry[2]);
    assert(entry[4](app.state.settings.party_ui) and app.state.settings.style.scale==2,'The manual edit keeps the setup size: '..entry[2]);
    assert(app.callbacks.undo() and custom.equal(custom.history_value(app.state.settings),before),
        'One Undo restores the selected preset and every unrelated choice after a manual edit.');
end;
imgui.SliderFloat=sliders;
assert(#MOCK.commands==0 and #MOCK.font_stack==0);
return 'All-display setup defaults, preserved functional data, manual controls and atomic editor Undo/Redo';
