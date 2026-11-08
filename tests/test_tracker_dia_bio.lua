-- Phoenix dia.lua and bio.lua send the damage message whatever happens to the effect. Dia goes on only over no
-- Bio of the same or a higher tier, and AddStatusEffect refuses it over Dia of the same or a higher tier; Bio the
-- same way over Dia, and over Bio of the same tier. One that goes on takes the other off. Tiers: Dia 1, Dia II 3,
-- Bio 2, Bio II 4. Real 0x028s through observer.read.
local observer=require('core.observer');
local SELF,BLM,MOB=1001,2002,0x1000123;
local function snapshot()
    return {valid=true,id=SELF,name='Tester',zone=102,job=3,level=75,self_known=true,self_revision=1,self_timer_revision=1,
        self_effects={},party={},
        entities={[SELF]={id=SELF,name='Tester',kind='player'},[BLM]={id=BLM,name='Blm',kind='player'},[MOB]={id=MOB,name='Goblin',kind='monster'}},
        target={id=MOB,name='Goblin',kind='monster'}};
end;
local function putbits(bytes, offset, length, value)
    for i = 0, length - 1 do
        local at = offset + i;
        if math.floor(value / 2 ^ i) % 2 == 1 then bytes[math.floor(at / 8)] = bytes[math.floor(at / 8)] + 2 ^ (at % 8); end
    end
end
local function action(actor, category, id, targets)
    local bytes, at = MOCK.bytes(2048), 150;
    putbits(bytes, 40, 32, actor); putbits(bytes, 72, 6, #targets); putbits(bytes, 82, 4, category); putbits(bytes, 86, 32, id);
    for _, target in ipairs(targets) do
        putbits(bytes, at, 32, target[1]); putbits(bytes, at + 32, 4, 1); at = at + 36;
        putbits(bytes, at + 27, 17, target[3]); putbits(bytes, at + 44, 10, target[2]); at = at + 87;
    end
    bytes.n = math.ceil(at / 8);
    return MOCK.packet(0x028, bytes);
end
local function wearoff(actor, target, icon)
    local bytes=MOCK.bytes(28);
    putbits(bytes,32,32,actor); putbits(bytes,64,32,target); putbits(bytes,96,32,icon); putbits(bytes,192,16,206);
    bytes.n=28;
    return MOCK.packet(0x029, bytes);
end
local tracker=require('core.tracker').new();
local function frame(now,packets)
    local snap=snapshot();
    local obs={};
    for _,p in ipairs(packets or {}) do for _,o in ipairs(observer.read(p,now,snap)) do obs[#obs+1]=o; end; end;
    tracker:observe(obs,now,snap); tracker:reconcile(snap,now);
    return tracker:view(now,{},snap),tracker:drain_events(),obs;
end;
local TIME=0;
local function rows()
    local out={};
    for _,r in ipairs(tracker:view(TIME,{},snapshot()).rows) do if r.entity_id==MOB then out[r.effect]=r; end; end;
    return out;
end;
local function step(now,packets)
    TIME=now;
    local _,events=frame(now,packets);
    local out={};
    for _,e in ipairs(events) do if e.entity_id==MOB then out[#out+1]=e.kind..':'..e.effect; end; end;
    return table.concat(out,','),rows();
end;
local function fresh() tracker=require('core.tracker').new(); frame(0); end;
local dia,dia2,bio=function(who) return action(who,4,23,{{MOB,2,8}}); end,function(who) return action(who,4,24,{{MOB,2,20}}); end,
    function(who) return action(who,4,230,{{MOB,2,12}}); end;

-- Control: the first Dia on a mob goes on.
fresh();
local events,held=step(1,{dia(SELF)});
assert(events=='gain:134' and held[134] and held[134].mine,'A Dia on a clean mob goes on: '..events);
-- (b) The same Dia 30 s later is refused: the countdown and the event stay as they were.
events,held=step(31,{dia(SELF)});
assert(events=='' and math.floor(held[134].remaining)==30,'A recast Dia Phoenix refuses changes nothing: '..events);

-- (a) A BLM's Bio, then the player's Dia: nothing changes.
fresh();
step(1,{bio(BLM)});
events,held=step(5,{dia(SELF)});
assert(events=='' and not held[134] and held[135] and held[135].source==BLM,'A Dia under a Bio of a higher tier is refused: '..events);
-- (c) Dia II over that Bio goes on and takes it off.
events,held=step(6,{dia2(SELF)});
assert(events=='removed:135,gain:134' and held[134] and held[134].spell==24 and not held[135],'Dia II over Bio replaces it: '..events);

-- (d) Another caster's Dia II, then the player's Bio: refused, and the Dia II stays.
fresh();
step(1,{dia2(BLM)});
events,held=step(5,{bio(SELF)});
assert(events=='' and held[134] and held[134].source==BLM and not held[135],'A Bio under a Dia of a higher tier changes nothing: '..events);

-- (e) Another player's Dia, then the player's: refused, so the credit stays theirs.
fresh();
step(1,{dia(BLM)});
events,held=step(5,{dia(SELF)});
assert(events=='' and held[134].source==BLM and not held[134].mine,'A second Dia of the same tier keeps the first caster: '..events);
-- The player's Bio over that Dia goes on and takes it off.
events,held=step(6,{bio(SELF)});
assert(events=='removed:134,gain:135' and held[135] and held[135].mine and not held[134],'Bio over a lower Dia replaces it: '..events);

-- A copy whose time ran out, its wear-off sent only to its caster, doesn't refuse a new one.
fresh();
step(1,{bio(BLM)});
events,held=step(62,{dia(SELF)});
assert(events:find('gain:134',1,true) and held[134] and held[134].mine,"A Bio past its time doesn't stop a Dia: "..events);
