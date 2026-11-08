-- A removal alert is dropped only when the same batch brings back the copy that left: the same row renewed,
-- a new copy of its tier or spell, or a new copy of an effect with no other copy left. Another copy renewed
-- or kept in that batch doesn't bring it back.
local alerts=require('core.alerts');
local SELF=1001;
local rules={{id='removed',enabled=true,event='removed',effect=0,scope='self',cooldown=0,duration=30,visual=true}};
local function row(key,effect,extra)
    local out={key=key,instance=1,effect=effect,entity_id=SELF,scope='self',name='Effect '..effect,kind='buff',present=true};
    for k,v in pairs(extra or {}) do out[k]=v;end;
    return out;
end;
local function event(kind,value) local out={};for k,v in pairs(value) do out[k]=v;end;out.kind=kind;return out;end;
local function fired(rows,events)
    local a=alerts.new();
    local view={valid=true,rows={},subjects={{id=SELF,known=true,scope='self'}},context={}};
    a:update(view,{},rules,1,{});
    view.rows=rows;
    a:update(view,events,rules,1.1,{});
    return #a:drain(1.1);
end;
local IV,III=row('a',198,{tier=4,spell=397,source=2002}),row('b',198,{tier=3,spell=396,source=2003});
-- Minuet IV ran out while Minuet III was resung.
assert(fired({III},{event('removed',IV),event('refresh',III)})==1,'Another copy renewed does not hide the removal of the one that left.');
-- A song caster at the cap: their Advancing March dropped while they renewed Victory March.
local AM,VM=row('c',214,{tier=1,spell=419,source=2002}),row('d',214,{tier=2,spell=420,source=SELF});
assert(fired({VM},{event('removed',AM),event('refresh',VM)})==1,'A renewed March does not hide the March that was dropped.');
-- Minuet IV ran out and a new Minuet III copy came while the old III stayed.
local new=row('e',198,{tier=3,spell=396,source=2004});
assert(fired({III,new},{event('removed',IV),event('gain',new)})==1,'A new copy of another tier beside a kept one does not hide it.');
-- The same copy back in the batch is no removal.
assert(fired({IV},{event('removed',IV),event('refresh',IV)})==0,'The same row renewed hides its removal.');
local again=row('f',198,{tier=4,spell=397,source=2002});
assert(fired({III,again},{event('removed',IV),event('gain',again)})==0,'A new copy of its tier hides its removal.');
-- Refresh worn off and recast in the same batch: one copy, back.
local old,recast=row('g',43,{spell=109,source=SELF}),row('h',43,{spell=110,source=SELF});
assert(fired({recast},{event('removed',old),event('gain',recast)})==0,'A single effect gained again hides its removal.');
