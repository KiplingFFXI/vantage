-- Phoenix item scripts put an effect back by taking it off with a message, adding it again and sending the gain
-- message (reraise_earring.lua onItemUse: delStatusEffect, addStatusEffect, messageBasic 205). The player gets
-- the 0x029 206 and then the 0x029 205, both from themselves, ahead of the tick's status packets, and those list
-- the deleted copy beside the new one until the next tick drops it with no message (status_effect_container.cpp).
-- A datagram can end between any two of them. However they come, that is one renewal of the row: it keeps its
-- key, is the player's, starts over, and nothing is gained, removed or missing. A removal with no 205 or second
-- copy behind it is still a removal, a 205 with no removal before it a gain, and Refresh reads as it did. Other
-- items, a spell and a job ability that take an effect off with a message and put it back in the player's tick
-- are one renewal too, and a copy a 205 replaced with no message leaves quietly. Real parsers throughout.
local raw_time=1000;
package.preload['core.clock']=function() return {available=function() return true; end,get_game_time_raw=function() return raw_time; end}; end;
local client=require('core.client');
local observer=require('core.observer');
local stats=AshitaCore:GetMemoryManager():GetPlayer();
local buffs,icons,timers={},{},{};
stats.GetBuffs=function() return buffs; end;
stats.GetStatusIcons=function() return icons; end;
stats.GetStatusTimers=function() return timers; end;
local function list(ids,raws) for slot=0,31 do buffs[slot]=ids[slot+1] or 65535; icons[slot]=ids[slot+1] or 255; timers[slot]=raws[slot+1] or 0; end; end;
local SELF=MOCK.player.server_id;
local RERAISE,REFRESH,HASTE,MAGIC_SHIELD,INVISIBLE,REGEN,PROTECT=113,43,33,152,69,42,40;
local s=require('ui.defaults').make();
local rules={};
for _,effect in ipairs({RERAISE,REFRESH,HASTE,MAGIC_SHIELD,INVISIBLE,REGEN,PROTECT}) do
    for _,event in ipairs({'gain','removed','missing'}) do
        rules[#rules+1]={id=event..effect,enabled=true,event=event,effect=effect,scope='self',cooldown=0,duration=30,visual=true};
    end;
end;
local tracker,alerts,snap,queue;
local function putbits(bytes, offset, length, value)
    for i = 0, length - 1 do
        local at = offset + i;
        if math.floor(value / 2 ^ i) % 2 == 1 then bytes[math.floor(at / 8)] = bytes[math.floor(at / 8)] + 2 ^ (at % 8); end
    end
end
local function feed(packet,t) for _,o in ipairs(observer.read(packet,t,snap)) do queue[#queue+1]=o; end; end;
local function status_packets(t) feed(MOCK.packet(0x037,MOCK.bytes(0x50)),t); local b=MOCK.bytes(200); MOCK.put(b,4,2,9); feed(MOCK.packet(0x063,b),t); end;
local function message(id,effect,t)
    local b=MOCK.bytes(28);
    MOCK.put(b,4,4,SELF); MOCK.put(b,8,4,SELF); MOCK.put(b,12,4,effect); MOCK.put(b,24,2,id);
    feed(MOCK.packet(0x029,b),t);
end;
-- The 0x028 of an action on the player, by themselves unless another actor is given: an item (category 5, no
-- message) or a spell.
local function action(category,id,message_id,param,t,actor)
    local bytes, at = MOCK.bytes(512), 150;
    putbits(bytes, 40, 32, actor or SELF); putbits(bytes, 72, 6, 1);
    putbits(bytes, 82, 4, category); putbits(bytes, 86, 32, id);
    putbits(bytes, at, 32, SELF); putbits(bytes, at + 32, 4, 1); at = at + 36;
    putbits(bytes, at + 27, 17, param); putbits(bytes, at + 44, 10, message_id); at = at + 87;
    bytes.n = math.ceil(at / 8);
    feed(MOCK.packet(0x028, bytes),t);
end;
local function raw(seconds) return raw_time*60+seconds*60; end;
-- One refresh of the addon: the queue, the listing, the alerts. Returns the rows of the effect by slot, the
-- kinds of its events, and its alerts.
local function present(t,effect)
    local current=client.read(t,s);
    tracker:observe(queue,t,current); queue={};
    tracker:reconcile(current,t);
    snap=current;
    local view=tracker:view(t,s,current);
    local events=tracker:drain_events();
    alerts:update(view,events,rules,t,{enabled=true});
    local kinds,fired,rows={},{},{};
    for _,event in ipairs(events) do if event.effect==effect then kinds[#kinds+1]=event.kind; end; end;
    for _,notice in ipairs(alerts:drain(t)) do if notice.effect==effect then fired[#fired+1]=notice.rule_id; end; end;
    for _,row in ipairs(view.rows) do if row.effect==effect then rows[#rows+1]=row; end; end;
    table.sort(rows,function(a,b) return a.slot<b.slot; end);
    return rows,table.concat(kinds,','),table.concat(fired,',');
end;
local function wait(from,to,effect)
    local kinds,fired={},{};
    for t=from,to do
        raw_time=1000+t;
        local _,k,f=present(t,effect);
        if k~='' then kinds[#kinds+1]=k; end;
        if f~='' then fired[#fired+1]=f; end;
    end;
    return table.concat(kinds,','),table.concat(fired,',');
end;
-- The Reraise Earring used once at t=1 with no Reraise up: the delete finds nothing, so the client gets the 205,
-- the item's 0x028 and the status packets: a gain, the player's own.
local function start()
    tracker,alerts,queue=require('core.tracker').new(),require('core.alerts').new(),{};
    raw_time=1000; list({},{});
    snap=client.read(0,s); present(0,RERAISE); present(0.5,RERAISE);
    raw_time=1001;
    message(205,RERAISE,1); action(5,14790,0,0,1);
    list({RERAISE},{raw(7200)}); status_packets(1);
    local rows,kinds,fired=present(1.05,RERAISE);
    assert(kinds=='gain' and fired=='gain113' and #rows==1 and rows[1].source==SELF and rows[1].mine==true,
        'Fixture: the first use is a gain of the player: events '..kinds..', alerts '..fired);
    wait(2,59,RERAISE);
    raw_time=1060;
    return rows;
end;
local function reuse_checks(rows,kinds,fired,key,label)
    local row=rows[2];
    assert(kinds=='refresh' and fired=='','['..label..'] Using it again is one refresh, with no alert: events '..kinds..', alerts '..fired);
    assert(#rows==2 and rows[1].departing and rows[1].key~=key and not row.departing and row.key==key,
        '['..label..'] The row moves to the new copy and the old one shows leaving: '..#rows..' rows');
    assert(row.instance==2 and row.source==SELF and row.mine==true and row.spell==nil and row.start>=60 and row.start<60.3
        and math.abs(row.total-7200)<1 and math.abs(row.remaining-7200)<1,
        '['..label..'] It is the player\'s renewal, started over: instance '..tostring(row.instance)..' start '..tostring(row.start)
        ..' total '..tostring(row.total));
end;
local function drop_checks()
    list({RERAISE},{raw(7200)}); status_packets(60.4);
    local rows,kinds,fired=present(60.45,RERAISE);
    return rows,kinds,fired;
end;

local rows=start();
local key,kinds,fired,later,later_fired=rows[1].key;

-- A: the 206, the 205, the item's 0x028 and the status packets in one datagram.
message(206,RERAISE,60); message(205,RERAISE,60); action(5,14790,0,0,60);
list({RERAISE,RERAISE},{raw(7141),raw(7200)}); status_packets(60);
rows,kinds,fired=present(60.05,RERAISE);
reuse_checks(rows,kinds,fired,key,'one datagram');
rows,kinds,fired=drop_checks();
assert(kinds=='' and fired=='' and #rows==1 and rows[1].key==key and rows[1].instance==2 and rows[1].mine==true,
    'The next tick drops the old copy quietly: events '..kinds..', alerts '..fired);
-- Both ticks in one reply: the listing read after them has the new copy alone.
rows=start(); key=rows[1].key;
message(206,RERAISE,60); message(205,RERAISE,60); action(5,14790,0,0,60);
list({RERAISE,RERAISE},{raw(7141),raw(7200)}); status_packets(60);
list({RERAISE},{raw(7200)}); status_packets(60);
rows,kinds,fired=present(60.05,RERAISE);
assert(kinds=='refresh' and fired=='' and #rows==1 and rows[1].key==key and rows[1].instance==2 and rows[1].mine==true
    and math.abs(rows[1].remaining-7200)<1,'Read past its two-copy tick, it is the same renewal: events '..kinds..', alerts '..fired);

-- B: the datagram ends after the 206; the 205 and the status packets come in the next one.
rows=start(); key=rows[1].key;
message(206,RERAISE,60);
rows,kinds,fired=present(60.02,RERAISE);
assert(kinds=='' and fired=='' and #rows==1 and rows[1].key==key and rows[1].present and rows[1].departing,
    'The 206 alone is held, the row still drawn, with no removed or missing alert: events '..kinds..', alerts '..fired);
message(205,RERAISE,60.2); action(5,14790,0,0,60.2);
list({RERAISE,RERAISE},{raw(7141),raw(7200)}); status_packets(60.2);
rows,kinds,fired=present(60.22,RERAISE);
reuse_checks(rows,kinds,fired,key,'206 split from the 205');
rows,kinds,fired=drop_checks();
assert(kinds=='' and fired=='' and #rows==1 and rows[1].key==key,'The old copy leaves quietly: events '..kinds..', alerts '..fired);

-- C: the datagram ends after the 205; the status packets come in the next one.
rows=start(); key=rows[1].key;
message(206,RERAISE,60); message(205,RERAISE,60); action(5,14790,0,0,60);
rows,kinds,fired=present(60.02,RERAISE);
assert(kinds=='' and fired=='' and #rows==1 and rows[1].key==key,'The two messages wait for the listing: events '..kinds..', alerts '..fired);
list({RERAISE,RERAISE},{raw(7141),raw(7200)}); status_packets(60.2);
rows,kinds,fired=present(60.22,RERAISE);
reuse_checks(rows,kinds,fired,key,'status packets split from the messages');
rows,kinds,fired=drop_checks();
assert(kinds=='' and fired=='' and #rows==1 and rows[1].key==key,'The old copy leaves quietly: events '..kinds..', alerts '..fired);

-- D: the 0x037 before its 0x063: the buff list has both copies, the icons and timers not yet.
rows=start(); key=rows[1].key;
message(206,RERAISE,60); message(205,RERAISE,60); action(5,14790,0,0,60);
buffs[1]=RERAISE; feed(MOCK.packet(0x037,MOCK.bytes(0x50)),60);
rows,kinds,fired=present(60.02,RERAISE);
assert(snap.self_timers_pending==true,'Fixture: the 0x037 came without its 0x063.');
assert(kinds=='' and fired=='','The 0x037 alone gains nothing: events '..kinds..', alerts '..fired);
list({RERAISE,RERAISE},{raw(7141),raw(7200)});
local b=MOCK.bytes(200); MOCK.put(b,4,2,9); feed(MOCK.packet(0x063,b),60.1);
rows,kinds,fired=present(60.12,RERAISE);
reuse_checks(rows,kinds,fired,key,'0x037 before its 0x063');

-- E: the earring's removal split from its status packets with no 205 behind it is a removal, once the 0x063
-- comes without one.
rows=start(); key=rows[1].key;
message(206,RERAISE,60);
rows,kinds,fired=present(60.02,RERAISE);
assert(kinds=='' and fired=='','It waits: events '..kinds..', alerts '..fired);
list({},{}); status_packets(60.2);
rows,kinds,fired=present(60.22,RERAISE);
assert(kinds=='removed' and fired=='removed113,missing113' and #rows==0,'Then it is a removal: events '..kinds..', alerts '..fired);
-- So is one whose 0x063 still lists the copy alone, as one taken off in the player's own tick: then, not a tick later.
rows=start(); key=rows[1].key;
message(206,RERAISE,60);
present(60.02,RERAISE);
status_packets(60.2);
rows,kinds,fired=present(60.22,RERAISE);
assert(kinds=='removed' and fired=='removed113,missing113' and #rows==1 and rows[1].departing,
    'A 0x063 still listing it says it went: events '..kinds..', alerts '..fired);
list({},{}); status_packets(60.6);
rows,kinds,fired=present(60.62,RERAISE);
assert(kinds=='' and fired=='' and #rows==0,'And its slot clears quietly: events '..kinds..', alerts '..fired);

-- F: Hi-Reraiser takes Reraise off and puts it back with no 205 (hi-reraiser.lua). Its 206 and the listing of
-- both copies are the renewal too, whose caster nothing names.
for _,split in ipairs({false,true}) do
    local label=split and 'split' or 'one datagram';
    rows=start(); key=rows[1].key;
    message(206,RERAISE,60); action(5,4173,0,0,60);
    if split then
        rows,kinds,fired=present(60.02,RERAISE);
        assert(kinds=='' and fired=='','['..label..'] The 206 waits: events '..kinds..', alerts '..fired);
    end;
    list({RERAISE,RERAISE},{raw(7141),raw(5400)}); status_packets(60.2);
    rows,kinds,fired=present(60.22,RERAISE);
    assert(kinds=='refresh' and fired=='' and #rows==2 and rows[1].departing and rows[2].key==key and rows[2].instance==2
        and rows[2].source==nil and rows[2].start==nil and math.abs(rows[2].remaining-5400)<1,
        '['..label..'] One renewal, by nobody named: events '..kinds..', alerts '..fired);
    list({RERAISE},{raw(5400)}); status_packets(60.6);
    rows,kinds,fired=present(60.62,RERAISE);
    assert(kinds=='' and fired=='' and #rows==1 and rows[1].key==key,'['..label..'] The old copy leaves quietly: events '..kinds..', alerts '..fired);
end;

-- G: Refresh, unchanged. The player's own recast (206 and the 0x028, Always_Overwrite) is one refresh; a wear-off
-- split from its status packets still alerts at once.
tracker,alerts,queue=require('core.tracker').new(),require('core.alerts').new(),{};
raw_time=1000; list({},{});
snap=client.read(0,s); present(0,REFRESH); present(0.5,REFRESH);
raw_time=1001; action(4,109,230,REFRESH,1); list({REFRESH},{raw(150)}); status_packets(1);
rows=present(1.05,REFRESH); key=rows[1].key;
wait(2,59,REFRESH); raw_time=1060;
message(206,REFRESH,60); action(4,109,230,REFRESH,60);
list({REFRESH,REFRESH},{raw(91),raw(150)}); status_packets(60);
rows,kinds,fired=present(60.05,REFRESH);
assert(kinds=='refresh' and fired=='' and #rows==2 and rows[2].key==key and rows[2].spell==109 and rows[2].mine==true
    and rows[1].departing,'The Refresh recast is one refresh: events '..kinds..', alerts '..fired);
list({REFRESH},{raw(150)}); status_packets(60.4);
rows,kinds,fired=present(60.45,REFRESH);
assert(kinds=='' and fired=='' and #rows==1 and rows[1].key==key,'Its old copy leaves quietly: events '..kinds..', alerts '..fired);
wait(61,209,REFRESH); raw_time=1210;
message(206,REFRESH,210);
rows,kinds,fired=present(210.02,REFRESH);
assert(kinds=='removed' and fired=='removed43,missing43','A Refresh wear-off alone alerts at once: events '..kinds..', alerts '..fired);

-- H: a 205 with no removal before it stays a gain, even beside a listed copy of its icon: the Haste Belt's
-- enchantment wears the Haste icon (haste_belt.lua) next to the player's Haste spell, and both stay.
tracker,alerts,queue=require('core.tracker').new(),require('core.alerts').new(),{};
raw_time=1000; list({},{});
snap=client.read(0,s); present(0,HASTE); present(0.5,HASTE);
raw_time=1001; action(4,57,230,HASTE,1); list({HASTE},{raw(180)}); status_packets(1);
rows=present(1.05,HASTE); key=rows[1].key;
wait(2,29,HASTE); raw_time=1030;
message(205,HASTE,30); action(5,15290,0,0,30);
list({HASTE,HASTE},{raw(151),raw(180)}); status_packets(30);
rows,kinds,fired=present(30.05,HASTE);
assert(kinds=='gain' and fired=='gain33' and #rows==2 and rows[1].key==key and rows[1].instance==1 and rows[1].spell==57
    and not rows[1].departing and rows[2].key~=key and rows[2].source==SELF,
    'The copy from the belt is a gain and the row of the spell is untouched: events '..kinds..', alerts '..fired);
later,later_fired=wait(31,40,HASTE);
rows=present(40.5,HASTE);
assert(later=='' and later_fired=='' and #rows==2 and rows[1].key==key and rows[1].spell==57,
    'Both stay, with nothing more: '..later..' / '..later_fired);
-- So the spell's copy leaving later is a removal, beside the belt's copy of the icon: when a mob's Slow takes it
-- with no message (OverwriteStatusEffect drops Haste, Slow's negative), when it wears off a moment after the belt,
-- and when Slow takes it a moment after a listing that still had it.
local MOB=0x01000ABC;
local function belt(left)
    tracker,alerts,queue=require('core.tracker').new(),require('core.alerts').new(),{};
    raw_time=1000; list({},{});
    snap=client.read(0,s); present(0,HASTE); present(0.5,HASTE);
    raw_time=1001; action(4,57,230,HASTE,1); list({HASTE},{raw(left+29)}); status_packets(1);
    local rows=present(1.05,HASTE);
    wait(2,29,HASTE); raw_time=1030;
    message(205,HASTE,30); action(5,15290,0,0,30); list({HASTE,HASTE},{raw(left),raw(180)}); status_packets(30);
    present(30.05,HASTE);
    return rows[1].key;
end;
key=belt(150);
wait(31,59,HASTE); raw_time=1060;
action(4,56,236,13,60,MOB); list({HASTE,13},{raw(150),raw(180)}); status_packets(60);
rows,kinds,fired=present(60.05,HASTE);
assert(kinds=='removed' and fired=='removed33' and #rows==1 and rows[1].key~=key,
    'Slow taking the spell\'s copy later is a removal: events '..kinds..', alerts '..fired);
key=belt(2); raw_time=1032;
message(206,HASTE,32); list({HASTE},{raw(178)}); status_packets(32);
rows,kinds,fired=present(32.05,HASTE);
assert(kinds=='removed' and fired=='removed33' and #rows==1 and rows[1].key~=key,
    'The spell\'s copy wearing off just after is a removal: events '..kinds..', alerts '..fired);
key=belt(150); raw_time=1031;
action(4,43,230,PROTECT,31); list({HASTE,HASTE,PROTECT},{raw(149),raw(179),raw(1800)}); status_packets(31);
present(31.05,HASTE); raw_time=1032;
action(4,56,236,13,32,MOB); list({HASTE,PROTECT,13},{raw(178),raw(1799),raw(180)}); status_packets(32);
rows,kinds,fired=present(32.05,HASTE);
assert(kinds=='removed' and fired=='removed33' and #rows==1 and rows[1].key~=key,
    'Slow taking it after a listing that still had it is a removal: events '..kinds..', alerts '..fired);

-- I: a party member's Fool's Powder over the player's Magic Shield (pinch_of_fools_powder.lua, addItemShield on
-- each member): the 206 and the 205 come to the player, from the player, in the user's tick, so the player's own
-- next tick lists the new copy alone. The 205 can't name who used it; the renewal is still one.
for _,split in ipairs({false,true}) do
    local label=split and 'split' or 'one datagram';
    tracker,alerts,queue=require('core.tracker').new(),require('core.alerts').new(),{};
    raw_time=1000; list({},{});
    snap=client.read(0,s); present(0,MAGIC_SHIELD); present(0.5,MAGIC_SHIELD);
    raw_time=1001; message(205,MAGIC_SHIELD,1); list({MAGIC_SHIELD},{raw(60)}); status_packets(1);
    rows=present(1.05,MAGIC_SHIELD); key=rows[1].key;
    wait(2,29,MAGIC_SHIELD); raw_time=1030;
    message(206,MAGIC_SHIELD,30);
    if split then
        rows,kinds,fired=present(30.02,MAGIC_SHIELD);
        assert(kinds=='' and fired=='','['..label..'] The 206 waits: events '..kinds..', alerts '..fired);
    end;
    message(205,MAGIC_SHIELD,30.05);
    rows,kinds,fired=present(30.1,MAGIC_SHIELD);
    if not split then
        assert(kinds=='' and fired=='','['..label..'] The messages wait for the listing: events '..kinds..', alerts '..fired);
    end;
    list({MAGIC_SHIELD},{raw(60)}); status_packets(30.4);
    rows,kinds,fired=present(30.45,MAGIC_SHIELD);
    assert(kinds=='refresh' and fired=='' and #rows==1 and rows[1].key==key and rows[1].instance==2
        and not rows[1].departing and math.abs(rows[1].remaining-60)<1,
        '['..label..'] One renewal: events '..kinds..', alerts '..fired);
end;

-- An effect gained at t=1 from nothing waiting: an item (category 5) or a job ability (category 6) whose 0x028
-- names no effect, or a spell.
local function begin(effect,category,id,message_id,param,seconds)
    tracker,alerts,queue=require('core.tracker').new(),require('core.alerts').new(),{};
    raw_time=1000; list({},{});
    snap=client.read(0,s); present(0,effect); present(0.5,effect);
    raw_time=1001; action(category,id,message_id,param,1); list({effect},{raw(seconds)}); status_packets(1);
    local rows,kinds,fired=present(1.05,effect);
    assert(kinds=='gain' and fired=='gain'..effect and #rows==1,'Fixture: the first use is a gain: events '..kinds..', alerts '..fired);
    wait(2,29,effect); raw_time=1030;
    return rows;
end;

-- J: Prism Powder takes Invisible off with a message and puts it back with no 205 (pinch_of_prism_powder.lua), as
-- do Rainbow Powder, Sneaking Boots, Blaze Hose and the Max HP and MP drinks. In one datagram or with the 206 in
-- its own, one renewal by nobody named.
for _,split in ipairs({false,true}) do
    local label=split and 'split' or 'one datagram';
    rows=begin(INVISIBLE,5,4164,0,0,300); key=rows[1].key;
    message(206,INVISIBLE,30);
    if split then
        rows,kinds,fired=present(30.02,INVISIBLE);
        assert(kinds=='' and fired=='' and #rows==1 and rows[1].key==key,'['..label..'] The 206 waits: events '..kinds..', alerts '..fired);
    end;
    action(5,4164,0,0,30.1); list({INVISIBLE,INVISIBLE},{raw(271),raw(300)}); status_packets(30.1);
    rows,kinds,fired=present(30.15,INVISIBLE);
    assert(kinds=='refresh' and fired=='' and #rows==2 and rows[1].departing and rows[2].key==key and rows[2].instance==2
        and rows[2].source==nil and math.abs(rows[2].remaining-300)<1,
        '['..label..'] Prism Powder again is one renewal: events '..kinds..', alerts '..fired);
    list({INVISIBLE},{raw(300)}); status_packets(30.5);
    rows,kinds,fired=present(30.55,INVISIBLE);
    assert(kinds=='' and fired=='' and #rows==1 and rows[1].key==key,'['..label..'] The old copy leaves quietly: events '..kinds..', alerts '..fired);
end;

-- K: the player's Invisible over their Invisible. Casting takes it off with a message (battle_entity.cpp
-- OnCastFinished), then the spell puts it back: one refresh, the spell's.
for _,split in ipairs({false,true}) do
    local label=split and 'split' or 'one datagram';
    rows=begin(INVISIBLE,4,136,230,INVISIBLE,420); key=rows[1].key;
    message(206,INVISIBLE,30);
    if split then
        rows,kinds,fired=present(30.02,INVISIBLE);
        assert(kinds=='' and fired=='','['..label..'] The 206 waits: events '..kinds..', alerts '..fired);
    end;
    action(4,136,230,INVISIBLE,30.1); list({INVISIBLE,INVISIBLE},{raw(391),raw(420)}); status_packets(30.1);
    rows,kinds,fired=present(30.15,INVISIBLE);
    assert(kinds=='refresh' and fired=='' and #rows==2 and rows[1].departing and rows[2].key==key and rows[2].instance==2
        and rows[2].spell==136 and rows[2].mine==true,'['..label..'] The recast is one refresh: events '..kinds..', alerts '..fired);
    list({INVISIBLE},{raw(420)}); status_packets(30.5);
    rows,kinds,fired=present(30.55,INVISIBLE);
    assert(kinds=='' and fired=='' and #rows==1 and rows[1].key==key,'['..label..'] The old copy leaves quietly: events '..kinds..', alerts '..fired);
end;

-- L: Chakra with Invigorate (Phoenix era monk.lua useChakra) takes Regen off with a message and puts it back, and
-- its 0x028 names no effect. The listing of both copies says it was put back in the player's tick.
rows=begin(REGEN,6,15,102,40,60); key=rows[1].key;
message(206,REGEN,30); action(6,15,102,40,30); list({REGEN,REGEN},{raw(31),raw(60)}); status_packets(30);
rows,kinds,fired=present(30.05,REGEN);
assert(kinds=='refresh' and fired=='' and #rows==2 and rows[1].departing and rows[2].key==key and rows[2].instance==2
    and math.abs(rows[2].remaining-60)<1,'Chakra again is one renewal: events '..kinds..', alerts '..fired);
list({REGEN},{raw(60)}); status_packets(30.4);
rows,kinds,fired=present(30.45,REGEN);
assert(kinds=='' and fired=='' and #rows==1 and rows[1].key==key,'Its old copy leaves quietly: events '..kinds..', alerts '..fired);

-- M: the Protect Earring over the player's Protect replaces it with no message (protect_earring.lua,
-- OverwriteStatusEffect), then sends the 205. The gain stays; the copy the next tick drops left quietly.
rows=begin(PROTECT,4,43,230,PROTECT,1800); key=rows[1].key;
message(205,PROTECT,30); action(5,15838,0,0,30); list({PROTECT,PROTECT},{raw(1771),raw(1800)}); status_packets(30);
rows,kinds,fired=present(30.05,PROTECT);
assert(kinds=='gain' and fired=='gain40' and #rows==2 and rows[1].key==key and rows[2].key~=key and rows[2].source==SELF,
    'The earring\'s copy is a gain: events '..kinds..', alerts '..fired);
local gained=rows[2].key;
present(30.2,PROTECT);
list({PROTECT},{raw(1800)}); status_packets(30.4);
rows,kinds,fired=present(30.45,PROTECT);
assert(kinds=='' and fired=='' and #rows==1 and rows[1].key==gained,'The copy it replaced leaves quietly: events '..kinds..', alerts '..fired);
