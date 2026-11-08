-- Real ImGui pointer input against simulated data; this never controls the game.
local app = assert(PREVIEW.addon);
local imgui, defaults, store = require('imgui'), require('ui.defaults'), require('core.store');
local hud, party, native = require('ui.hud'), require('ui.party_hud'), require('ui.native_party_hud');
local window = require('ui.settings_window');
local view = hud.sample(100);
view.notices = {{visual=true,test=true,ends=1000,message='Haste is ending soon.'}};
local roster, subjects = party.sample(6,100);
local kind, expected_label, start, original, last, verified = 'timer', nil, nil, nil, nil, 0;
local before, saves, finishes = 0, 0, 0;
local changed, save = app.callbacks.changed, app.callbacks.save;
app.callbacks.changed = function(stage,label,...)
    if stage == 'before' then before=before+1; end;
    return changed(stage,label,...);
end;
app.callbacks.save = function(...)
    saves=saves+1;
    return save(...);
end;
local button = imgui.InvisibleButton;
local begin = imgui.Begin;
imgui.Begin = function(name,open,flags,...)
    if name=='Vantage##settings' then PREVIEW.settings_open_arg,PREVIEW.settings_flags=open,flags; end;
    return begin(name,open,flags,...);
end;
imgui.InvisibleButton = function(label,size,...)
    if label == expected_label then
        local x,y=imgui.GetCursorScreenPos();
        last={x=x,y=y,width=size[1],height=size[2]};
        if not start then start=store.copy(last); end;
    end;
    return button(label,size,...);
end;
local geometry = {available=true,groups={[1]={x=800,y=200,width=116,height=240,rows={}}}};
for i,member in ipairs(roster.members) do
    geometry.groups[1].rows[member.slot]={x=800,y=200+(i-1)*40,width=116,height=40,slot=member.slot};
end;
local geometry_before = store.copy(geometry);
local function settings() return app.state.settings; end;
local function surface()
    local s=settings();
    if kind=='timer' then return s.panels.self_buffs;
    elseif kind=='recast' then return s.panels.recasts;
    elseif kind=='notice' then return s.alerts;
    elseif kind=='settings' then return s.window;
    else return s.party_ui; end;
end;
function PREVIEW.inset_reset(which)
    hud.cancel_gesture(); hud.cancel_notice_gesture();
    native.cancel_layout_gesture(); window.cancel_resize();
    app.state.settings=defaults.make();
    PREVIEW.settings=settings();
    local s=settings();
    kind=which;
    s.enabled,s.preview,s.style.scale=true,false,1;
    s.window.open, s.window.peek = false, false;
    s.window.x,s.window.y,s.window.width,s.window.height,s.window.tab=200,150,800,600,'Help';
    s.alerts.enabled,s.alerts.muted,s.alerts.notice_locked=which=='notice',false,false;
    s.alerts.notice_x,s.alerts.notice_y,s.alerts.notice_width,s.alerts.notice_height=200,150,320,240;
    for _,p in pairs(s.panels) do p.enabled=false; end;
    local p=s.panels[which=='recast' and 'recasts' or 'self_buffs'];
    p.enabled,p.locked,p.x,p.y,p.width,p.height_limit,p.auto_width,p.auto_height=true,false,200,150,320,240,false,false;
    s.recast_display='combined';
    local c=s.party_ui;
    c.enabled,c.preview,c.locked=true,false,false;
    c.native.snap,c.native.width,c.native.side,c.native.gap=false,320,'left',6;
    for _,g in ipairs(c.groups) do g.native_detached=false; end;
    c.groups[1].native_detached,c.groups[1].detached_x,c.groups[1].detached_y=true,200,150;
    c.groups[1].detached_width,c.groups[1].detached_height=320,240;
    if which=='native_attached' then c.groups[1].native_detached=false; end;
    if which=='settings' then s.window.open=true; end;
    expected_label=which=='timer' and '##move_self_buffs' or which=='recast' and '##move_recasts'
        or which=='notice' and '##notice_layout' or which=='settings' and '##settings_shift_layout'
        or '##native_move_1';
    start,last=nil,nil;
    defaults.tidy(s);
    original=store.copy(surface());
    app.state.history,app.state.redo,app.state.transaction,app.state.dirty={},{},nil,false;
    before,saves,finishes=0,0,0;
end;
function PREVIEW.inset_verify(edge)
    assert(start and last,kind..' resize surface must be visible');
    local left, right=edge:find('left',1,true),edge:find('right',1,true);
    local top, bottom=edge:find('top',1,true),edge:find('bottom',1,true);
    -- A strip beside the game's rows only moves, from its edges and corners too.
    local moving=edge=='move' or kind=='native_attached';
    local x=start.x+((left or moving) and 20 or 0);
    local y=start.y+((top or moving) and 15 or 0);
    local width=start.width+(moving and 0 or left and -20 or right and 20 or 0);
    local height=start.height+(moving and 0 or top and -15 or bottom and 15 or 0);
    for key,wanted in pairs({x=x,y=y,width=width,height=height}) do
        assert(math.abs(last[key]-wanted)<1.1,kind..' '..edge..' '..key..': '..last[key]..' wanted '..wanted);
    end;
    assert(before==1 and saves==1,kind..' '..edge..' one edit and save: '..before..'/'..saves);
    assert(#app.state.history==1 and not app.state.transaction,kind..' '..edge..' completed Undo entry');
    if kind=='native' or kind=='native_attached' then
        assert(finishes==1,kind..' ends once');
    end;
    if kind=='native_attached' then
        assert(not settings().party_ui.groups[1].native_detached,'A Shift-drag never puts a strip in a panel of its own');
    end;
    assert(require('core.customization').equal(geometry,geometry_before),'Never modify native game geometry');
    local final=store.copy(surface());
    assert(app.callbacks.undo(),kind..' Undo');
    assert(require('core.customization').equal(surface(),original),kind..' Undo restores saved settings');
    assert(app.callbacks.redo(),kind..' Redo');
    assert(require('core.customization').equal(surface(),final),kind..' Redo restores changed settings');
    PREVIEW.settings=settings();
    verified=verified+1;
    PREVIEW.log('Inset grab passed',kind,edge);
end;
function PREVIEW.settings_mode(shift)
    local bit=require('bit');
    assert((PREVIEW.settings_open_arg==nil)==shift,'Only Shift layout mode suppresses the native close button');
    for _,flag in ipairs({ImGuiWindowFlags_NoScrollbar,ImGuiWindowFlags_NoScrollWithMouse}) do
        assert((bit.band(PREVIEW.settings_flags,flag)~=0)==shift,'Normal scrolling returns after Shift');
    end;
end;
PREVIEW.inset_reset('timer');
return function()
    PREVIEW.settings=settings();
    local s=settings();
    local shift=imgui.GetIO().KeyShift==true;
    app.callbacks.shift=shift;
    local callbacks={global_style=s.style,shift=shift,native_geometry=geometry,
        begin_edit=function() app.callbacks.changed('before','Inset layout'); end,
        end_edit=function() finishes=finishes+1; end,
        changed=function() app.callbacks.changed('after'); app.callbacks.save(); end,
        target=function() error('Shift resizing must not target'); end};
    if kind=='timer' or kind=='recast' or kind=='notice' then
        if kind=='notice' then s.panels.self_buffs.enabled=false; end;
        hud.draw(view,s,100,app.callbacks);
    elseif kind=='settings' then window.draw(s,view,app.callbacks);
    else
        local _,shown=native.draw(roster,subjects,s.party_ui,100,callbacks);
        assert(not next(shown),'Native strips do not replace client windows');
    end;
    if PREVIEW.frame==PREVIEW.last_frame then
        assert(#MOCK.commands==0,'Gestures never issue game commands');
        PREVIEW.log('Inset resize replay completed',verified);
    end;
end;
