-- With more live notices than Notices shown at once, an automatic height still shows that many, the newest. The ones
-- past the cap or the height are left out with nothing in their place: no count, no "more alerts", no drag hint.
local hud, defaults = require('ui.hud'), require('ui.defaults');
local s = defaults.make();
local function draw(count)
    local view = { context = {}, notices = {} };
    for i = 1, count do view.notices[i] = { message = 'Warning ' .. i, visual = true, ends = 100 }; end;
    MOCK.imgui_calls = {};
    hud.draw_notices(view, s, 1, {});
    local seen, shown, footer, height, newest = {}, 0, nil, nil, false;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddText' then
            local value = call[#call];
            if value:match('^Warning %d$') then
                if not seen[value] then seen[value], shown = true, shown + 1; end;
                if value == 'Warning ' .. count then newest = true; end;
            else footer = value; end;
        elseif call[1] == 'SetNextWindowSize' then height = call[2][2]; end;
    end;
    return shown, footer, height, newest;
end;
assert(s.alerts.max_notices == 4 and s.alerts.notice_height == 0, 'Fixture: automatic height, four at once.');
local shown, footer, four = draw(4);
assert(shown == 4 and footer == nil, 'Fixture: four notices show with no other text.');
local five_height, newest;
shown, footer, five_height, newest = draw(5);
assert(shown == 4 and newest, 'Automatic height shows Notices shown at once (4), the newest, with five live (got ' .. shown .. ').');
assert(footer == nil, 'The one past the cap leaves no text behind: ' .. tostring(footer));
assert(five_height == four, 'The box keeps the height of the notices it shows.');
shown, footer = draw(6);
assert(shown == 4 and footer == nil, 'Six live: four shown and nothing said of the other two: ' .. tostring(footer));
-- A fixed height that fits the cap's four says nothing either.
s.alerts.notice_height = 400;
shown, footer = draw(6);
assert(shown == 4 and footer == nil, 'A tall fixed box shows four, the cap hiding two silently: ' .. tostring(footer));
-- A short fixed box: the height leaves out two of the cap's four, which dragging taller brings back.
s.alerts.notice_height = 80;
local short;
shown, footer, short, newest = draw(6);
assert(shown == 2 and newest and footer == nil and short == 80, 'A short box shows the newest two and no footer: ' .. tostring(footer));
shown, footer = draw(3);
assert(shown == 2 and footer == nil, 'Under the cap, the height cuts silently too: ' .. tostring(footer));
s.alerts.notice_height = 400;
shown, footer = draw(3);
assert(shown == 3 and footer == nil, 'Dragging taller brings back what the height left out.');
return true;
