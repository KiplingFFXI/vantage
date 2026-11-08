local A = require('core.alerts');
local function make()
    local a=A.new();
    local rule={id='warning',enabled=true,event='remaining',scope='target',effect=33,thresholds={10},
        cooldown=0,repeat_seconds=2,visual=true,sound='ding.wav',duration=30};
    local row={key='20:33',instance=1,entity_id=20,entity_name='Friend',scope='party',effect=33,name='Haste',
        status='estimated',remaining=20,total=180,present=true};
    local view={valid=true,rows={row},subjects={{id=20,name='Friend',scope='party',known=true}},context={target={id=20}}};
    a:update(view,{}, {rule},0,{}); row.remaining=9; a:update(view,{}, {rule},1,{});
    assert(#a:drain(1)==1 and #a:view(1)==1);
    return a,rule,row,view;
end
local a,r,row,v=make();
v.context.target={id=21}; a:update(v,{}, {r},2,{});
assert(#a:view(2)==0, 'Target-specific warnings must withdraw when the selected target changes.');
a,r,row,v=make(); row.status='unknown'; row.remaining=nil; a:update(v,{}, {r},2,{});
assert(#a:view(2)==0, 'A remaining-time notice cannot outlive the evidence for its countdown.');
a,r,row,v=make();
a:update(v,{}, {r},2,{muted=true}); a:update(v,{}, {r},3,{}); a:update(v,{}, {r},4,{});
assert(#a:drain(4)==0, 'Unmuting cannot replay an already-crossed repeated threshold.');
a,r,row,v=make(); r.scope='party'; r.event='missing'; r.effect=0;
v.rows={}; a=A.new();
a:update(v,{}, {r},0,{}); a:update(v,{}, {r},4,{});
assert(#a:drain(4)==0, 'A rule with no effect has no testable missing condition.');
a=A.new(); a:test(r,20); assert(a:drain(20)[1].sound=='ding.wav');
a:reset(); a:test(r,1);
assert(a:drain(1)[1].sound=='ding.wav', 'A backward clock reset must also reset the sound rate limiter.');
return true;
