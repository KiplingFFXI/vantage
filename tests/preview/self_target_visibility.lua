local app=assert(PREVIEW.addon);
local hud,window,imgui=require('ui.hud'),require('ui.settings_window'),require('imgui');
local custom=require('core.customization');
local s=app.state.settings;
local page=PREVIEW.visibility_page or 'Display';
if page=='Display' then require('ui.panel_frame').open('target','show');end;
s.window.tab,s.window.open,s.window.x,s.window.y=page,true,20,20;
s.window.width, s.window.height = 860, 800;
s.style.font,s.window_style.font_size='Agave',16;
s.enabled,s.preview,s.recast_display=true,false,'combined';
s.party_ui.enabled,s.party_ui.preview=false,false;
s.style.icon_size,s.style.font_size,s.style.font=32,16,'Agave';
s.style.icon_art='Original FFXI';
local order={self_buffs=1,self_debuffs=2,target=3,recasts=4};
for id,p in pairs(s.panels)do
    p.enabled=order[id]~=nil;
    p.locked,p.mode,p.empty=true,'bars','hide';
    p.x,p.y,p.width=930,80+((order[id] or 1)-1)*160,350;
    p.auto_width,p.auto_height,p.height_limit,p.show_target=false,true,140,false;
end;
require('ui.icons').prepare();require('ui.recast_icons').prepare();
local view={valid=true,self_known=true,context={id=1001,name='Fennel',target={id=1001,name='Fennel'}},rows={
    {key='self_haste',effect=33,slot=0,name='Haste',scope='self',kind='buff',entity_id=1001,entity_name='Fennel',
        present=true,status='server',deadline=182,total=180},
    {key='self_poison',effect=3,slot=1,name='Poison',scope='self',kind='debuff',entity_id=1001,entity_name='Fennel',
        present=true,status='server',deadline=131,total=90},
    {key='cure_recast',effect=10004,name='Cure IV',scope='recast',domain='recast',kind='spell',entity_id=1001,
        spell_id=4,list_icon_hq=89,list_icon_nq=6,present=true,status='server',deadline=118,total=30},
}};
local begin,finish=imgui.Begin,imgui.End;
local current;
imgui.Begin=function(name,...)
    local visible=begin(name,...);
    current=visible and name or nil;
    for id in pairs(order)do
        if name=='##vantage_'..id and visible then PREVIEW.visibility_drawn[id]=true;end;
    end;
    return visible;
end;
imgui.End=function(...)current=nil;return finish(...);end;
-- The effects whose icons the self panels draw.
local icons=require('ui.icons');
local status=icons.status;
icons.status=function(id,...)
    if current=='##vantage_self_buffs' or current=='##vantage_self_debuffs' then PREVIEW.visibility_icons[id]=true;end;
    return status(id,...);
end;
local baseline;
-- Every panel has On beside its samples, in the header that stays put.
function PREVIEW.visibility_capture()
    local toggle=PREVIEW_PY.item_bounds('On##frame_display');
    local sample=PREVIEW_PY.item_bounds('Show samples##frame');
    assert(#toggle==4 and #sample==4 and toggle[1]<sample[1] and toggle[2]<sample[4] and sample[2]<toggle[4],
        'The tested On checkbox is in the fixed header beside the samples, not in the page body');
    baseline=custom.history_value(app.state.settings);
    app.state.history,app.state.redo,app.state.transaction={},{},nil;
end;
function PREVIEW.visibility_verify(id,shown,restored)
    local current=app.state.settings;
    assert(view.context.target.id==view.context.id,'The observed target remains the player');
    assert(current.enabled and not current.preview,'Local visibility leaves the global display enabled and samples off');
    for key in pairs(order)do
        local wanted=key~=id or shown;
        assert(current.panels[key].enabled==wanted,'Only the selected panel visibility changes: '..key);
        assert((PREVIEW.visibility_drawn[key]==true)==wanted,'Actual HUD rendering follows only that panel: '..key);
    end;
    assert(PREVIEW.visibility_icons[33] and PREVIEW.visibility_icons[3],
        'The real HUD still draws both self buff and self debuff icons while targeting self');
    if restored then assert(custom.equal(custom.history_value(current),baseline),'Restoring visibility preserves every original option');end;
    assert(#MOCK.commands==0,'Settings interaction never queues gameplay commands');
    PREVIEW.visibility_checks=(PREVIEW.visibility_checks or 0)+1;
end;
return function()
    PREVIEW.settings=app.state.settings;
    PREVIEW.visibility_drawn,PREVIEW.visibility_icons={},{};
    app.callbacks.shift=false;
    hud.draw(view,PREVIEW.settings,100,app.callbacks);
    window.draw(PREVIEW.settings,view,app.callbacks);
    if PREVIEW.frame==PREVIEW.last_frame then
        assert((PREVIEW.visibility_checks or 0)>0,'The real pointer sequence completed its assertions');
        PREVIEW.log('Self-target local visibility: '..page..' toolbar toggles only its selected panel; self buffs/debuffs stay drawn and global display stays enabled.');
    end;
end;
