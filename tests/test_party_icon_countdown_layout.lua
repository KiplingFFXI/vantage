local imgui = require('imgui');
local layout = require('ui.party_layout');
local countdown = require('ui.countdown_text');
local hud = require('ui.party_hud');
local overlay = require('ui.native_party_hud');
local defaults = require('ui.party_defaults');
local copy = require('core.store').copy;
imgui.CalcTextSize = function(text) return #text * imgui.GetFontSize() / 2, imgui.GetFontSize(); end;

local effects = {
    {effect=40,name='Protect',kind='buff',remaining=720,present=true},
    {effect=41,name='Shell',kind='buff',remaining=59,present=true},
    {effect=42,name='Unknown duration',kind='buff',present=true},
    {effect=269,name='Zone Level Sync',kind='buff',present=true},
};
local options = {icon_size=24,timers=true,fit_all=true,wrap_text=true,sort='name',
    countdown_font='Agave',font_size=48,measure_key='compact-fixture',
    text_measure=function(value) return #value * 24; end};
local area = {x=10,y=20,width=180,height=600};
local function cells(value, rect) return layout.effect_cells(effects, value or options, rect or area); end;
local function near(a,b) assert(math.abs(a-b)<.001, tostring(a)..' differs from '..tostring(b)); end;
local current, omitted = cells();
assert(#current==4 and omitted==0);
assert(current[1].countdown.below and current[1].countdown.size==12,
    'Icon timers follow their glyph size, independently of a large member font.');
assert(current[1].countdown.gap==0 and current[1].height==36);
assert(current[1].countdown.lines[1].text=='12m' and current[2].countdown.lines[1].text=='59s');
assert(current[3].countdown==nil and current[4].countdown==nil, 'Unknown and Level Sync durations remain blank.');
for _, size in ipairs({16,24,32,64}) do
    local setting=copy(options);setting.icon_size=size;
    local result=cells(setting);
    assert(result[1].icon_size==size and result[1].countdown.size==size/2);
    assert(result[1].height==size+result[1].countdown.height);
end;

local inside=copy(options);inside.icon_countdown_position='inside';
local inside_cells=cells(inside);
assert(not inside_cells[1].countdown.below and inside_cells[1].height==24);
local manual=copy(options);manual.icon_countdown_size,manual.icon_countdown_gap=20,3;
local manual_cells=cells(manual,{x=0,y=0,width=24,height=1000});
assert(manual_cells[1].countdown.size==20 and #manual_cells[1].countdown.lines==2);
assert(manual_cells[1].height==67 and manual_cells[2].y==70,
    'A narrow strip wraps chosen timer text without reducing its size or overlapping the next icon.');
assert(manual_cells[1].icon_size==24 and manual.icon_countdown_size==20);
manual.icon_countdown_gap=7;
assert(cells(manual, {x=0,y=0,width=24,height=1000})[1].height==71, 'Gap edits invalidate the cell cache.');
manual.icon_countdown_size=8;
assert(cells(manual)[1].countdown.size==8, 'Manual font edits invalidate the cell cache.');
manual.icon_countdown_position='inside';
assert(not cells(manual)[1].countdown.below, 'Placement edits invalidate the cell cache.');
manual.countdown_font='Original FFXI';
assert(cells(manual)[1].countdown.size==8, 'Changing the font family does not restore an old size.');

for _, scale in ipairs({.5,1,1.5,2,4,8}) do
    local setting=copy(options);setting.icon_size,setting.pixel_scale=24/scale,scale;
    local result=cells(setting,{x=0,y=0,width=180/scale,height=600/scale});
    near(result[1].icon_size*scale,24);
    near(result[1].countdown.size*scale,12);
    near(result[1].countdown.height*scale,12);
    near(result[1].height*scale,36);
end;
for _, growth in ipairs({'left','right'}) do
    local setting=copy(options);setting.growth=growth;
    local result, hidden=cells(setting,{x=100,y=200,width=51,height=1000});
    assert(#result==4 and hidden==0 and result[3].y>result[1].y);
    for _, cell in ipairs(result) do assert(cell.x>=100 and cell.x+cell.width<=151); end;
    assert((result[1].x<result[2].x)==(growth=='right'));
end;

local saved_draw, calls = countdown.draw, {};
countdown.draw=function(_,font,value,x,y,size,ink,style,tight)
    calls[#calls+1]={font=font,text=value,x=x,y=y,size=size,tight=tight};
end;
local icon_module=require('ui.icons');local original_status=icon_module.status;
icon_module.status=function() return 10001; end;
local look=require('ui.party_theme').resolve(defaults.make());
look.font,look.font_size='Agave',48;
local hovered=hud.paint_effects(imgui.GetWindowDrawList(),look,{effects=effects},options,area,15,50,{},100);
assert(hovered and hovered.effect==40, 'The timer area remains part of its icon hover target.');
assert(#calls==2 and calls[1].text=='12m' and calls[2].text=='59s');
near(calls[1].y,44);near(calls[1].size,12);
assert(calls[1].tight==true and calls[1].font=='Agave');
countdown.draw,icon_module.status=saved_draw,original_status;

local config=defaults.make();config.enabled=true;
config.effects.icon_size=22;config.effects.timers=true;config.effects.icon_countdown_position='below';
local roster,subjects=hud.sample(1,100);
subjects[roster.members[1].id]={effects=effects};
local native={available=true,groups={{x=500,y=100,width=116,height=22,rows={
    [0]={x=500,y=100,width=116,height=22,slot=0}}}}};
local attached=overlay.plan(roster,subjects,config,native,1280,720)[1].rows[1];
local native_cells=layout.effect_cells(effects,attached.options,attached.area);
assert(#native_cells==4 and native_cells[1].icon_size==22);
assert(not native_cells[1].countdown.below and native_cells[1].countdown.fallback,
    'An attached native strip uses fitted Inside when Below cannot fit the fixed client row.');
assert(native_cells[1].countdown.height<=22 and native_cells[1].height<=22);
assert(config.effects.icon_size==22 and config.effects.icon_countdown_position=='below');
local roomy=copy(attached.options);roomy.icon_size=12;
assert(layout.effect_cells(effects,roomy,{x=0,y=0,width=120,height=22})[1].countdown.below,
    'Attached rows honor Below when icon and timer both fit.');
config.groups[1].native_detached=true;
local detached=overlay.plan(roster,subjects,config,native,1280,720)[1].rows[1];
local detached_cells=layout.effect_cells(effects,detached.options,detached.area);
assert(detached_cells[1].countdown.below and not detached_cells[1].countdown.fallback);
assert(detached_cells[1].icon_size==22 and config.effects.icon_size==22);
-- At 14 px rows 20 px apart the icons fill the step: 20 px icons from 3 px above the row, their countdowns inside,
-- half the icon's height, because below would need the icon, the gap and the text.
native.groups[1]={x=500,y=100,width=116,height=14,pitch=20,rows={
    [0]={x=500,y=100,width=116,height=14,slot=0}}};
config.groups[1].native_detached=false;
local touched=overlay.plan(roster,subjects,config,native,1280,720)[1].rows[1];
local touched_cells=layout.effect_cells(effects,touched.options,touched.area);
assert(touched_cells[1].icon_size==20 and touched_cells[1].y==97 and touched_cells[1].height<=20,'20 px icons.');
assert(not touched_cells[1].countdown.below and touched_cells[1].countdown.fallback and touched_cells[1].countdown.size==10
    and touched_cells[1].countdown.height<=20,'A 20 px room keeps 10 px countdowns inside the icon.');
return 'Compact below-icon countdown layout, wrapping, linked scaling, caching, painter and native row fallback';
