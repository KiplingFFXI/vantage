-- Same-ID copies (songs) pair with the listed slots by one rule: as many pairs as can be, then the fewest
-- renewals, departing rows kept, order changes and raw timers that differ; of equal pairings the first in
-- slot order. The tracker must give what trying every pairing gives, and stay cheap: it runs on every
-- refresh, and trying every pairing of six copies took millions of steps.
local Tracker=require('core.tracker');
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(revision,effects,pending)
    return {valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_revision=revision,
        self_timers_pending=pending,self_effects=effects,party={},entities={}};
end;
-- Timers sit 60 apart and read 60 to a second, so a move of more than one step is a renewal.
local function renewed(row,slot) return math.abs(row.raw-slot.raw)>60; end;

-- The rule, tried every way. rows and slots are in slot order; returns the row index each slot takes.
local function reference(rows,slots)
    local best,best_cost,chosen,taken={},nil,{},{};
    local function visit(s)
        if s>#slots then
            local cost={0,0,0,0,0};
            for a=1,#slots do
                local r=chosen[a];
                if not r then cost[1]=cost[1]+1;
                else
                    if renewed(rows[r],slots[a]) then cost[2]=cost[2]+1; end;
                    if rows[r].departing then cost[3]=cost[3]+1; end;
                    for b=a+1,#slots do if chosen[b] and chosen[b]<r then cost[4]=cost[4]+1; end; end;
                    if rows[r].raw~=slots[a].raw then cost[5]=cost[5]+1; end;
                end;
            end;
            local k=1;
            while best_cost and k<5 and cost[k]==best_cost[k] do k=k+1; end;
            if not best_cost or cost[k]<best_cost[k] then
                best_cost=cost;
                for a=1,#slots do best[a]=chosen[a]; end;
            end;
            return;
        end;
        for r=1,#rows do
            if not taken[r] and not (rows[r].departing and renewed(rows[r],slots[s])) then
                taken[r],chosen[s]=true,r;
                visit(s+1);
                taken[r],chosen[s]=nil,nil;
            end;
        end;
        visit(s+1);
    end;
    visit(1);
    return best;
end;

-- Builds a tracker holding rows, then lists slots; returns the slot each row ended on (nil when dropped).
local function pair(rows,slots,pending)
    local tracker=Tracker.new();
    local listing={};
    for i,row in ipairs(rows) do listing[i]=status(198,i-1,row.raw/60,row.raw); end;
    tracker:reconcile(snapshot(1,listing),10);
    local entries=tracker.entities[1001].entries;
    local keys={};
    for i,entry in ipairs(entries) do
        keys[i]=entry.key;
        if rows[i].departing then entry.departing,entry.departing_at,entry.departing_revision=true,10,1; end;
    end;
    listing={};
    for i,slot in ipairs(slots) do
        listing[i]=status(198,i-1,not pending and slot.raw/60 or nil,not pending and slot.raw or nil);
    end;
    tracker:reconcile(snapshot(2,listing,pending),10.1);
    local result={};
    for _,entry in ipairs(tracker.entities[1001].entries) do
        for i,key in ipairs(keys) do if entry.key==key and entry.present then result[i]=entry.slot; end; end;
    end;
    return result,tracker;
end;

-- Seeded random listings: up to six copies, timers that stay, restamp, renew or reorder, some rows departing.
math.randomseed(20261016);
local disagree,tried=0,0;
for _=1,160 do
    local rows,slots={},{};
    for i=1,math.random(1,6) do rows[i]={raw=6000+60*math.random(0,12),departing=math.random()<0.2}; end;
    table.sort(rows,function(a,b) return a.raw<b.raw; end);
    for i=1,math.random(1,6) do
        local base=rows[math.random(#rows)].raw;
        slots[i]={raw=base+60*({0,0,-1,1,-2,2,40})[math.random(7)]};
    end;
    if math.random()<0.5 then table.sort(slots,function(a,b) return a.raw<b.raw; end); end;
    local expected=reference(rows,slots);
    local got=pair(rows,slots);
    local wanted={};
    for a,r in pairs(expected) do wanted[r]=a-1; end;
    for r=1,#rows do if got[r]~=wanted[r] then disagree=disagree+1; break; end; end;
    tried=tried+1;
end;
assert(tried==160 and disagree==0,'The pairing is the one trying every pairing gives.');

-- Six copies listed in reverse: no renewals means many order changes; the fewest wins over exact timers.
local six,reversed={},{};
for i=1,6 do six[i]={raw=60000+60*(i-1)}; end;
for i=1,6 do reversed[i]={raw=six[7-i].raw}; end;
local got=pair(six,reversed);
assert(got[1]==4 and got[2]==5 and got[3]==2 and got[4]==3 and got[5]==0 and got[6]==1,
    'Reversed copies pair with the fewest order changes, first in slot order.');

-- The work per refresh, counted in Lua steps so it doesn't depend on the machine. These listings are the
-- costly ones for six copies; trying every pairing took over two million steps for each. Now the whole
-- refresh takes under 30,000.
local function steps(slots,pending)
    local tracker=Tracker.new();
    local listing={};
    for i,row in ipairs(six) do listing[i]=status(198,i-1,row.raw/60,row.raw); end;
    tracker:reconcile(snapshot(1,listing),10);
    listing={};
    for i,slot in ipairs(slots) do
        listing[i]=status(198,i-1,not pending and slot.raw/60 or nil,not pending and slot.raw or nil);
    end;
    local snap=snapshot(2,listing,pending);
    local count=0;
    -- Compiled code skips the hook, so count with the compiler off and its traces dropped.
    jit.off();
    jit.flush();
    debug.sethook(function() count=count+1; end,'',10);
    tracker:reconcile(snap,10.1);
    debug.sethook();
    jit.on();
    return count*10;
end;
local function moved(by) local out={}; for i,row in ipairs(six) do out[i]={raw=row.raw+by}; end; return out; end;
local most=0;
for _,case in ipairs({{six},{moved(-60)},{moved(6000)},{reversed},{{six[1],six[2],six[3],six[4],six[5]}},{six,true}}) do
    most=math.max(most,steps(case[1],case[2]));
end;
assert(most>0 and most<40000,'Pairing six copies stays a small fixed cost: '..most..' steps.');
