-- A Present after a status packet lays out and looks up icons exactly as a steady one does: each drawn icon is
-- looked up once. The real vantage.lua, client, observer, tracker and hud (self_panel_fixture.lua).
local fixture = require('self_panel_fixture')();
local hud = fixture.hud;
local layouts = 0;
local bounds = hud.bounds;
hud.bounds = function(...) layouts = layouts + 1; return bounds(...); end;
local s = fixture.settings;
local function frame()
    layouts = 0;
    local pictures = fixture.pictures;
    local record = fixture.frame();
    return {layouts=layouts, lookups=fixture.pictures - pictures, icons=fixture.count(record.icons)};
end;
for _, rows in ipairs({4, 3}) do
    s.panels.self_buffs.max_rows = rows;
    local list = {33, 40, 41, 43};
    fixture.both(list, {[33]=300, [40]=1800, [41]=1800, [43]=600});
    fixture.run(10);
    local steady = frame();
    assert(steady.layouts > 0 and steady.icons > 0 and steady.lookups == steady.icons,
        'Fixture: a steady frame lays out and looks up each drawn icon once (' .. rows .. ' rows).');
    for round = 1, 5 do
        fixture.both(list, {[33]=300 + round, [40]=1800, [41]=1800, [43]=600});
        local packet = frame();
        assert(packet.layouts == steady.layouts and packet.lookups == steady.lookups and packet.icons == steady.icons,
            'The Present after a status packet costs what a steady one does: ' .. packet.layouts .. ' layouts, '
            .. packet.lookups .. ' icon lookups against ' .. steady.layouts .. ' and ' .. steady.lookups .. '.');
    end;
end;
hud.bounds = bounds;
