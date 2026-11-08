local defaults, party = require('ui.defaults'), require('ui.party_defaults');
local copy, equal = require('core.store').copy, require('core.customization').equal;
local keys = {'countdown_bold','countdown_shadow','countdown_outline','countdown_outline_color'};
for _, make in ipairs({party.make}) do
    local config = make();
    assert(config.effects.countdown_bold == false and config.effects.countdown_shadow == true and config.effects.countdown_outline == true);
    assert(equal(config.effects.countdown_outline_color, {0,0,0,1}));
    local changed = copy(config);
    changed.effects.countdown_bold, changed.effects.countdown_shadow, changed.effects.countdown_outline = true, false, false;
    changed.effects.countdown_outline_color = {.2,.3,.4,.5};
    local tidy = party.tidy;
    local saved = tidy(copy(changed));
    for _, key in ipairs(keys) do assert(equal(saved.effects[key],changed.effects[key]), 'Saved countdown choice survives validation: '..key); end;
    assert(equal(saved.style,config.style) and saved.locked==config.locked, 'Countdown validation preserves appearance and locks');
    saved.effects.countdown_outline = nil;
    assert(tidy(saved).effects.countdown_outline, 'A missing party outline choice uses the default.');
    changed.effects.countdown_bold, changed.effects.countdown_shadow, changed.effects.countdown_outline = 'yes', 1, {};
    changed.effects.countdown_outline_color = {0/0,.3,.4,1};
    saved = tidy(changed);
    assert(not saved.effects.countdown_bold and saved.effects.countdown_shadow and saved.effects.countdown_outline);
    assert(equal(saved.effects.countdown_outline_color,{0,0,0,1}));
end;
local settings = defaults.make();
settings.party_ui.effects.countdown_bold = true;
local profiles = require('core.profiles');
local captured = profiles.capture(settings);
assert(captured.party_ui.effects.countdown_bold);
local presentation = profiles.capture_layout(settings,'presentation').presentation;
assert(presentation.party_ui.effects.countdown_bold and presentation.target_ui == nil);
local placement = profiles.capture_layout(settings,'placement');
assert(not placement.party_ui.effects.countdown_bold and placement.target_ui == nil,
    'Placement-only sharing does not overwrite countdown appearance');

local imgui=require('imgui');
-- Party list buffs says whether countdowns show. How their text looks is on the main page, so the panel sets none of it.
local h=require('panel_fixture')();
settings=h.fresh(function(saved)
    saved.party_ui.style.icon_art='XI View';
    -- Countdowns start off; on here, so what goes with them shows.
    saved.party_ui.effects.timers=true;
end);
local custom=require('core.customization');
local before=custom.history_value(settings);
local controls=h.every_tab('party_ui');
assert(equal(custom.history_value(h.s),before) and #h.app.state.history==0, 'Viewing the panel has no side effects');
assert(controls.Countdowns, 'Fixture: the panel drew its switch.');
for _, label in ipairs({'Bold effect countdowns','Effect countdown shadow','Effect countdown outline','Effect countdown outline color','Use for every countdown'}) do
    assert(not controls[label], 'The panel has no '..label);
end;

local hud, layout, theme = require('ui.party_hud'), require('ui.party_layout'), require('ui.party_theme');
local fonts, countdown = require('ui.fonts'), require('ui.countdown_text');
local ordinary, timer_calls, images, outlines, clips = {}, {}, 0, 0, {};
local function record_timer(face,value,x,y,size,ink)
    timer_calls[#timer_calls+1]={face=face,value=value,x=x,y=y,size=size,ink=ink};
end;
fonts.failed=function()return false;end;
fonts.measure=function(_,value,size)return #value*size*.5;end;
fonts.measure_countdown=function(_,value,size)return #value*size*.5,size;end;
fonts.countdown_renderer=function(face)return function(_,value,x,y,size,ink)record_timer(face,value,x,y,size,ink);end;end;
fonts.face=function(face)return face;end;
fonts.draw=function(_,face,value,x,y,size,ink)ordinary[#ordinary+1]={face=face,value=value,x=x,y=y,size=size,ink=ink};return true;end;
imgui.CalcTextSize=function(value)local size=imgui.GetFontSize();return #value*size*.5,size;end;
require('ui.icons').status=function()return 123;end;
local list={};
function list:PushClipRect(a,b)clips[#clips+1]={a,b};end;
function list:PopClipRect()clips[#clips]=nil;end;
function list:AddText(face,size,pos,ink,value)record_timer(face,value,pos[1],pos[2],size,ink);end;
function list:AddImage()images=images+1;end;
function list:AddRect()outlines=outlines+1;end;
function list:AddRectFilled()end;
function list:AddRectFilledMultiColor()end;
local function reset()ordinary,timer_calls,images,outlines,clips={},{},0,0,{};end;
local effect={effect=33,name='Haste',kind='buff',status='estimated',remaining=80,total=180,present=true};
local subject={known=true,effects={effect}};
local area={x=10,y=20,width=180,height=1000};
-- Countdowns start off, so each one below turns them on. The strips draw the icon alone, with no effect name.
for _, face in ipairs({'Agave','Original FFXI','XI View'}) do
    for mask=0,7 do
        local config=party.make();
        local look=theme.party(config,{font=face,font_size=16});look.bitmap_ready=fonts.is_bitmap(face);
        local options=config.effects;
        options.timers=true;
        options.countdown_bold=mask%2==1;options.countdown_shadow=math.floor(mask/2)%2==1;options.countdown_outline=mask>=4;
        options.countdown_outline_color={.2,.3,.4,.5};
        local before=copy(config);reset();
        hud.paint_effects(list,look,subject,options,area,nil,nil,{});
        local expected=(options.countdown_bold and 2 or 1)*(1+(options.countdown_shadow and 1 or 0)+(options.countdown_outline and 8 or 0));
        assert(#timer_calls==expected, 'Only selected countdown passes are drawn: '..face..':'..mask);
        local cells=layout.effect_cells({effect},options,area);local cell=cells[1];
        for _, call in ipairs(timer_calls) do
            assert(call.face==face and call.value=='1m' and call.size==16, 'Countdown styling keeps the selected font and size');
            assert(call.x>=cell.x and call.y>=cell.y and call.x+#call.value*8<=cell.x+cell.width and call.y+16<=cell.y+cell.height,
                'All countdown foreground, shadow and outline passes fit the effect cell');
        end;
        assert(images==1 and #ordinary==0, 'The icon alone, with no effect name.');
        assert(outlines==0, 'Real buff icons acquire no rectangle outline');
        assert(equal(config,before) and #clips==0 and #MOCK.font_stack==0);
    end;
end;

local options=party.make().effects;
options.timers=true;
options.countdown_bold,options.countdown_shadow,options.countdown_outline=true,false,true;
effect.remaining=36000;
for _, face in ipairs({'Original FFXI','XI View'}) do
    for skin=1,8 do
        local config=party.make();
        local look=theme.party(config,{font=face,font_size=48,theme='Original FFXI',window_type=skin});look.bitmap_ready=true;
        local e=copy(options);e.icon_size,e.auto_rows=16,true;
        e.icon_countdown_size,e.countdown_font=48,face;
        local rect={x=10,y=20,width=60,height=1000};reset();
        hud.paint_effects(list,look,subject,e,rect,nil,nil,{});
        local cells=layout.effect_cells({effect},e,rect);local cell=cells[1];
        assert(cell.countdown and cell.countdown.below and #cell.countdown.lines>1 and images==1,
            'A manually enlarged countdown wraps below the fixed-size icon without changing the member font.');
        for _, call in ipairs(timer_calls) do
            assert(call.face==face and call.size==48);
            assert(call.x>=cell.x and call.x+#call.value*24<=cell.x+cell.width and call.y>=cell.y and call.y+48<=cell.y+cell.height);
        end;
        assert(outlines==0 and #clips==0);
    end;
end;

effect.name,effect.remaining,effect.status='Unknown',nil,'unknown';
options.timers=true;
local look=theme.resolve(party.make());reset();
hud.paint_effects(list,look,subject,options,area,nil,nil,{});
assert(images==1 and #timer_calls==0, 'Known effect icons remain without an unknown countdown');
options.timers=false;reset();hud.paint_effects(list,look,subject,options,area,nil,nil,{});
assert(images==1 and #timer_calls==0, 'Disabling countdowns removes every countdown styling pass');

-- Attached strips have a fixed native slot height; even a large selected font must stay within it.
options.timers,options.icon_size=true,12;
look.font,look.font_size='XI View',48;reset();
hud.paint_effects(list,look,subject,options,{x=10,y=20,width=120,height=12},nil,nil,{});
assert(images==1 and #timer_calls==0);
for _,call in ipairs(timer_calls)do
    assert(call.face=='XI View' and call.value=='?');
    assert(call.x>=10 and call.x+#call.value*call.size*.5<=22 and call.y>=20 and call.y+call.size<=32,
        'Fixed native icon countdowns fit both axes, including their outline');
end;

-- Strips beside the game's party list and detached ones send the independent effect style through the shared painter.
local observed, draw_countdown = {}, countdown.draw;
countdown.draw=function(list,face,value,x,y,size,ink,style)
    observed[#observed+1]={face=face,bold=style.countdown_bold,shadow=style.countdown_shadow,outline=style.countdown_outline,color=copy(style.countdown_outline_color)};
    return draw_countdown(list,face,value,x,y,size,ink,style);
end;
imgui.GetWindowDrawList=function()return list;end;
imgui.GetScrollY=function()return 0;end;
imgui.GetMousePos=function()return -1,-1;end;
imgui.IsMouseDown=function()return false;end;
local roster,subjects=hud.sample(1,100);
local p=party.make();p.enabled,p.locked=true,true;
-- Countdowns start off; on here, so the strips draw them. They take the timer panels' font.
p.effects.timers=true;
local style=defaults.make().style;
style.font,style.font_size='XI View',16;
p.effects.countdown_bold,p.effects.countdown_shadow,p.effects.countdown_outline=true,false,true;
p.effects.countdown_outline_color={.3,.6,.8,.5};
local function assert_route(before,config)
    assert(#observed>0);
    for _,call in ipairs(observed)do
        assert(call.face=='XI View' and call.bold and not call.shadow and call.outline);
        assert(equal(call.color,{.3,.6,.8,.5}));
    end;
    assert(equal(before,config), 'Painting never changes the selected font, controls or locked placement');
    observed={};
end;
MOCK.screen={1600,1200};
local before;
local member=roster.members[1];
local geometry={available=true,groups={[1]={x=1000,y=100,width=116,height=40,rows={
    [member.slot]={x=1000,y=100,width=116,height=40,slot=member.slot},
}}}};
local overlay=require('ui.native_party_hud');
for _,detached in ipairs({false,true})do
    p.groups[1].native_detached=detached;
    before=copy(p);reset();overlay.draw(roster,subjects,p,100,{native_geometry=geometry,global_style=style});assert_route(before,p);
end;
countdown.draw=draw_countdown;

-- Native row height is fixed even when a countdown adds all three effects.
p.groups[1].native_detached=false;
p.native.width=240;
p.effects.max=1;
local observed_subjects={[member.id]={known=true,effects={{effect=33,name='Haste',kind='buff',status='estimated',remaining=80,total=180}}}};
for _,face in ipairs({'Agave','Original FFXI','XI View'})do
    style.font,style.font_size=face,14;
    for _,height in ipairs({12,14})do
        geometry.groups[1].height=height;geometry.groups[1].rows[member.slot].height=height;
        p.effects.countdown_bold,p.effects.countdown_shadow,p.effects.countdown_outline=true,true,true;
        before=copy(p);reset();overlay.draw(roster,observed_subjects,p,100,{native_geometry=geometry,global_style=style});
        local plan=overlay.plan(roster,observed_subjects,p,geometry,1600,1200,nil,style)[1];
        local row=plan.rows[1];
        local cells=layout.effect_cells(observed_subjects[member.id].effects,row.options,row.area);local cell=cells[1];
        assert(row.options.fixed_countdown_slot and cell and cell.height<=height);
        assert(#timer_calls>0 and equal(before,p), 'The fixed-slot fit is temporary and leaves native/user geometry unchanged');
        for _,call in ipairs(timer_calls)do
            assert(call.face==face and call.x>=cell.x and call.y>=cell.y);
            assert(call.x+#call.value*call.size*.5<=cell.x+cell.width and call.y+call.size<=cell.y+cell.height,
                'Every timer pass fits the '..height..'px native slot');
        end;
        assert(#ordinary==0, 'No effect name beside the game\'s rows either.');
    end;
end;

-- Integer glyph rounding can widen a proportional fit; use the final measured size.
local original_measure_countdown=fonts.measure_countdown;
fonts.measure_countdown=function(_,value,size)return #value*math.floor(size*.5+.5),size;end;
local original_renderer=fonts.countdown_renderer;
fonts.countdown_renderer=function(face)return function(_,value,x,y,size,ink)
    timer_calls[#timer_calls+1]={face=face,value=value,x=x,y=y,size=size,ink=ink,width=#value*math.floor(size*.5+.5)};
end;end;
effect.remaining,effect.status=359999,'estimated';
options.icon_size=12;
options.countdown_bold,options.countdown_shadow,options.countdown_outline=true,true,true;
options.fixed_countdown_slot,options.countdown_font=true,'XI View';
look.font,look.font_size='XI View',48;
reset();hud.paint_effects(list,look,subject,options,{x=10,y=20,width=120,height=12},nil,nil,{});
assert(#timer_calls>0);
for _,call in ipairs(timer_calls)do assert(call.x+call.width<=22 and call.y+call.size<=32, 'Final integer-glyph measure fits the fixed native icon');end;
fonts.measure_countdown,fonts.countdown_renderer=original_measure_countdown,original_renderer;
