local countdown = require('ui.countdown_text');
local hud = require('ui.hud');
local layout = require('ui.party_layout');
local cases = {
    {0, '0s'}, {0.01, '1s'}, {1, '1s'}, {59, '59s'}, {59.9, '60s'},
    {60, '1m'}, {60.1, '1m'}, {119.99, '1m'}, {120, '2m'},
    {3360, '56m'}, {3599, '59m'}, {3599.9, '59m'}, {3600, '1h'}, {3600.1, '1h'},
    {7199.99, '1h'}, {7200, '2h'}, {16800, '4h'}, {86399.9, '23h'}, {86400, '24h'},
};
for _, case in ipairs(cases) do
    local seconds, expected = case[1], case[2];
    assert(countdown.time(seconds) == expected);
    assert(countdown.time(seconds, 'auto') == expected);
    assert(countdown.time(seconds, 'compact') == expected);
    for _, status in ipairs({'server', 'estimated'}) do
        local effect = {effect=33,remaining=seconds,status=status};
        assert(layout.effect_time(effect) == expected);
        local row = {effect=33,deadline=100+seconds,status=status};
        assert(hud.timer_text(row,100,'auto') == expected);
        assert(hud.timer_text(row,100,'compact') == expected);
    end;
end;
for _, bad in ipairs({-1,0/0,math.huge,'60'}) do
    assert(countdown.time(bad)=='');
    assert(layout.effect_time({effect=33,remaining=bad})=='');
end;
assert(layout.effect_time({effect=33,status='unknown'})=='');
assert(hud.timer_text({effect=33,status='unknown'},100)=='');
assert(layout.effect_time({effect=269,remaining=300,status='server'})=='');
assert(hud.timer_text({effect=269,deadline=400,status='server'},100)=='');
-- Every countdown has the one time format, recasts too, and a format a caller names changes nothing.
assert(hud.timer_text({domain='recast',deadline=3460,status='server'},100)=='56m');
assert(hud.timer_text({domain='recast',deadline=16900,status='server'},100)=='4h');
for _, format in ipairs({'auto','compact','clock','seconds','minutes'}) do
    assert(hud.timer_text({domain='recast',deadline=16900,status='server'},100,format)=='4h');
    assert(hud.timer_text({deadline=3461,status='server'},100,format)=='56m');
    assert(hud.time(65,format)=='1m' and hud.time(nil,format)=='--');
    assert(layout.effect_time({remaining=65,status='estimated'},format)=='1m');
end;
local ranged={effect=33,status='estimated',start=0,duration_min=120,total=180,deadline=180};
assert(hud.timer_text(ranged,0,'auto')=='2m - 3m');
ranged.duration_min,ranged.total,ranged.deadline=3600,7200,7200;
assert(hud.timer_text(ranged,0,'auto')=='1h - 2h');
