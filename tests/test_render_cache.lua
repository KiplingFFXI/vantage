local cache = require('ui.render_cache');
local bounded = cache.new(3);
for index=1,20 do bounded:put(index,{index}); end;
assert(bounded:count()==3 and bounded:get(17)==nil and bounded:get(18)[1]==18);
bounded:put(19,'updated');
assert(bounded:count()==3 and bounded:get(19)=='updated');
assert(cache.key('a','bc')~=cache.key('ab','c') and cache.key(1)~=cache.key('1'));
-- Argument lists a careless key would mix up stay apart, and the same list always gives the same key.
local lists={{n=2,'a','bc'},{n=2,'ab','c'},{n=1,1},{n=1,'1'},{n=1,true},{n=1,'true'},{n=1,nil},{n=1,'nil'},{n=2,1,2},
    {n=1,12},{n=2,'1',2},{n=1,0.1},{n=1,1e300},{n=1,0},{n=1,'n1;'},{n=1,'s1:a'},{n=1,''},{n=2,'',''},{n=1,'z'},{n=0},
    {n=2,nil,nil},{n=3,'a',nil,'b'},{n=2,'a','nil'},{n=1,false},{n=1,'f'},{n=1,'t'}};
local seen={};
for index,list in ipairs(lists) do
    local key=cache.key(unpack(list,1,list.n));
    assert(seen[key]==nil,'Argument lists '..tostring(seen[key])..' and '..index..' share a key.');
    seen[key]=index;
    assert(cache.key(unpack(list,1,list.n))==key);
end;
local revision=cache.revisions(4,{'sort','include'});
local config={sort='name',include={[33]=true}};
local first=revision(config);
assert(revision(config)==first);
config.include[34]=true;
assert(revision(config)~=first,'In-place nested filter edits invalidate immediately.');
first=revision(config);
assert(revision({sort=config.sort,include=config.include},config)==first,'Temporary effective options reuse their stable identity.');
assert(revision({sort='remaining',include=config.include},config)~=first,'Effective overrides retain their own semantics.');

local fonts,imgui=require('ui.fonts'),require('imgui');
local generation,reads,wraps=1,0,0;
local assets=require('ui.client_assets');
assets.generation=function()return generation;end;
fonts.measure=function(_,value,size)reads=reads+1;return #value*size/2;end;
local metrics=require('ui.text_metrics');
local width=metrics.width('Original FFXI','Haste',16);
assert(width==40 and metrics.width('Original FFXI','Haste',16)==width and reads==1);
generation=generation+1;
assert(metrics.width('Original FFXI','Haste',16)==width and reads==2,'Recovered native artwork invalidates text metrics.');
fonts.measure=function(_,value,size)reads=reads+1;return #value*size;end;
assert(metrics.width('Original FFXI','Haste',16)==80 and reads==3,'Changed measurement sources cannot inherit old widths.');
assert(metrics.width('XI View','Haste',16)==80 and reads==4,'Font families have distinct entries.');
local wrap=require('ui.text_wrap');
local original_lines=wrap.lines;
wrap.lines=function(...)wraps=wraps+1;return original_lines(...);end;
local token=metrics.token('XI View',16);
local measure=function(value)return #value*8;end;
local a=metrics.lines('Haste Protect',48,measure,token);
assert(#a>1 and metrics.lines('Haste Protect',48,measure,token)==a and wraps==1);
assert(metrics.lines('Haste Protect',160,measure,token)~=a and wraps==2);
metrics.lines('Haste Protect',48,measure,nil);
assert(wraps==3,'Unknown measurement callbacks bypass cached wrapping.');

local layout=require('ui.party_layout');
local defaults=require('ui.party_defaults');
local options=defaults.make().effects;
options.max,options.sort,options.separate,options.fit_all=2,'remaining',false,false;
local one={effect=33,name='Haste',kind='buff',remaining=5,total=60,status='server',present=true,key='one'};
local two={effect=40,name='Protect',kind='buff',remaining=10,total=90,status='server',present=true,key='two'};
local three={effect=41,name='Shell',kind='buff',remaining=20,total=90,status='server',present=true,key='three'};
local subject={effects={one,two,three}};
local original_sort,sorts=table.sort,0;
table.sort=function(...)sorts=sorts+1;return original_sort(...);end;
local selected,hidden=layout.effects(subject,options,{});
assert(selected[1]==one and selected[2]==two and hidden==1);
local before=sorts;
one.remaining,two.remaining,three.remaining=4,9,19;
selected=layout.effects(subject,options,{});
assert(selected[1]==one and sorts==before,'Continuously ticking remaining values do not force a fresh sort.');
three.remaining=1;
selected=layout.effects(subject,options,{});
assert(selected[1]==three and sorts==before+1,'An overflow effect that moves ahead is included immediately.');
one.remaining=nil;
selected=layout.effects(subject,options,{});
assert(selected[2]==two,'An unknown duration moves after known timers.');
options.pinned[33]=true;
selected=layout.effects(subject,options,{});
assert(selected[1]==one,'In-place pin edits override remaining order immediately.');
options.exclude[33]=true;
selected,hidden=layout.effects(subject,options,{});
assert(selected[1]==three and selected[2]==two and hidden==0);
local replacement=require('core.store').copy(subject);
selected=layout.effects(replacement,options,{});
assert(selected[1]==replacement.effects[3] and selected[1]~=three,'Selection never retains stale effect objects.');
table.sort=original_sort;

-- The strips draw icons only: each cell is an icon with its countdown under it.
options=defaults.make().effects;
options.timers=true;
options.wrap,options.auto_rows=true,true;
options.measure_key=metrics.token('XI View',16);
options.icon_size=24;
one.remaining=33;
local rect={x=10,y=20,width=250,height=400};
local cells,omitted,height=layout.effect_cells({one,two},options,rect);
before=wraps;
local next_one=require('core.store').copy(one);next_one.remaining=32.5;next_one.total=120;
local again=layout.effect_cells({next_one,two},options,{x=40,y=70,width=250,height=400});
assert(wraps==before and again[1].x==cells[1].x+30 and again[1].y==cells[1].y+50);
assert(again[1].effect==next_one and again[1].effect.total==120,'Cached cell geometry uses this frame\'s timer/fill state.');
table.remove(again);
assert(#layout.effect_cells({one,two},options,rect)==#cells,'Changing the returned cells cannot damage a retained plan.');
local current=layout.effect_cells({one,two},options,rect);
options.growth='left';
local reversed=layout.effect_cells({one,two},options,rect);
assert(reversed[1].x==rect.x+rect.width-(current[1].x-rect.x)-current[1].width);
options.icon_countdown_position='inside';
local inside=layout.effect_cells({one,two},options,rect);
assert(inside[1].height<current[1].height,'Option changes reflow cached cells immediately.');
options.icon_countdown_position='below';
local cached=layout.effect_cells({one,two},options,rect);
options.measure_key=nil;
local uncached=layout.effect_cells({one,two},options,rect);
assert(require('core.customization').equal(cached,uncached),'Cached geometry exactly matches the independent uncached builder.');
assert(one.name=='Haste' and one.remaining==33,'Rendering caches do not modify source effects.');

-- Sizing wants only the omitted count and the height, so no cells are copied. With a draw's cache the
-- same effects, options and area size are worked out once in that draw.
options.measure_key=token;
local listed={one,two};
local full_cells,full_omitted,full_height=layout.effect_cells(listed,options,rect);
local sized_cells,sized_omitted,sized_height=layout.effect_cells(listed,options,rect,true);
assert(#full_cells>0 and sized_cells==nil and sized_omitted==full_omitted and sized_height==full_height,
    'Sizing gives the same omitted count and height without copying cells.');
-- Each effect's countdown text is part of the key a sizing works out.
local captions,caption=0,layout.effect_time;
layout.effect_time=function(...)captions=captions+1;return caption(...);end;
local draw={};
local _,first_omitted,first_height=layout.effect_cells(listed,options,rect,true,draw);
local asked=captions;
local _,again_omitted,again_height=layout.effect_cells(listed,options,{x=0,y=0,width=rect.width,height=rect.height},true,draw);
assert(asked>0 and captions==asked and again_omitted==first_omitted and again_height==first_height,
    'One draw sizes the same effects, options and area once.');
layout.effect_cells(listed,options,{x=0,y=0,width=rect.width-60,height=rect.height},true,draw);
assert(captions>asked,'Another width is sized again.');
asked=captions;
layout.effect_cells(listed,options,{x=0,y=0,width=rect.width,height=rect.height-60},true,draw);
assert(captions>asked,'Another height is sized again.');
asked=captions;
layout.effect_cells(listed,options,{x=0,y=0,width=rect.width,height=rect.height,align_right=true},true,draw);
assert(captions>asked,'Another alignment is sized again.');
asked=captions;
local other={};for key,value in pairs(options) do other[key]=value;end;
layout.effect_cells(listed,other,rect,true,draw);
assert(captions>asked,'Other options are sized again.');
asked=captions;
layout.effect_cells(listed,options,rect,true);layout.effect_cells(listed,options,rect,true);
assert(captions==asked+2*#listed,'Without a draw cache each sizing works its key out.');
local sized_subject,draw_heights={effects={one,two}},{};
local function effect_height()
    local _,_,height=layout.effect_cells(layout.effects(sized_subject,options,draw_heights),options,
        {x=0,y=0,width=rect.width,height=2048},true,draw_heights);
    return height;
end;
local first_height=effect_height();
asked=captions;
assert(effect_height()==first_height and captions==asked,'Effect heights in one draw share their sizing.');
layout.effect_time=caption;

wrap.lines=original_lines;
return 'Bounded render caches, current rows, immediate option/art changes and exact wrapped geometry';
