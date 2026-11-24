-- A 1.3.0 save could have Fit the width ticked and then Same width as the chat log, as 1.3.0 hid the first tick while
-- the second was on. Both keys stay true after the tidy, and the Width pick reads it as Same as the chat log. The
-- chat log's width wins, as it did in 1.3.0, even when the rows don't fit the height. Away from the chat log, or while
-- the chat log can't be read, Fits the rows still widens the panel for rows left out.
package.loaded['ui.icons'] = { status = function() return 123; end };
rawset(require('imgui'), 'CalcTextSize', function(text) return #tostring(text) * 8, 18; end);
local hud, defaults = require('ui.hud'), require('ui.defaults');
local elements = require('ui.elements');
MOCK.screen = { 1920, 1080 };
local CHAT = { x = 16, y = 821, width = 500, height = 223 };
local rows = {};
for index = 1, 20 do
    rows[index] = { key = 'r' .. index, effect = 40 + index, slot = index - 1, scope = 'party', entity_id = 1002, entity_name = 'Bob',
        kind = 'buff', status = 'estimated', name = 'Buff ' .. index, deadline = 1000 + 60 * index, start = 990, total = 600 };
end

-- The party panel's window width after a few frames, and the two keys after the tidy a load runs.
local function drawn_width(auto_width, match_chat, max_width, chat)
    local s = defaults.make();
    s.style.font, s.style.font_size, s.style.scale = 'Ashita', 14, 1;
    for id, panel in pairs(s.panels) do panel.enabled = id == 'party'; end
    local p = s.panels.party;
    p.mode, p.stack_direction, p.max_rows, p.height_limit = 'bars', 'vertical', 32, 300;
    p.min_width, p.max_width = 160, max_width;
    p.auto_width, p.dock_match_width = auto_width, match_chat;
    p.anchor.to, p.anchor.side = 'chat', 'above';
    s = defaults.tidy(s);
    p = s.panels.party;
    assert(p.auto_width == auto_width and p.dock_match_width == match_chat and p.anchor.to == 'chat', 'The tidy keeps both keys.');
    local width;
    for frame = 1, 3 do
        elements.frame();
        MOCK.imgui_calls = {};
        hud.draw({ valid = true, context = { id = 1001, valid = true, party = {}, chat = chat }, rows = rows }, s, 1000 + frame / 60, {});
        local last;
        for _, call in ipairs(MOCK.imgui_calls) do
            if call[1] == 'SetNextWindowSize' then last = call[2];
            elseif call[1] == 'Begin' and call[2] == '##vantage_party' then width = last and last[1]; end
        end
    end
    return width;
end

assert(drawn_width(false, true, 900, CHAT) == CHAT.width, 'Same as the chat log on its own is the chat log\'s width.');
local both = drawn_width(true, true, 900, CHAT);
assert(both == CHAT.width, ('Same as the chat log from a 1.3.0 save with Fit the width ticked is drawn %s wide, not the chat log\'s %d')
    :format(tostring(both), CHAT.width));
local wide = drawn_width(true, true, 1400, CHAT);
assert(wide == CHAT.width, ('With Widest at 1400 it is drawn %s wide, not the chat log\'s %d'):format(tostring(wide), CHAT.width));
-- Fits the rows on the chat log without its width still widens for the rows left out.
local fits = drawn_width(true, false, 1400, CHAT);
assert(fits and fits > CHAT.width, 'Fits the rows on the chat log still widens: ' .. tostring(fits));
-- While the chat log can't be read the 1.3.0 save falls back to Fits the rows, as 1.3.0 did.
local unread = drawn_width(true, true, 1400, nil);
assert(unread and unread > CHAT.width, 'With the chat log unread it fits the rows: ' .. tostring(unread));
return true;
