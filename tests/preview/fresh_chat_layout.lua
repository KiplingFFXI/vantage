-- A fresh install's first frame in real ImGui: with the timer panels and four notices, no two displays overlap and
-- none reaches into the game's chat log or its own party list and target window (where they usually sit, scaled to
-- the screen).
local imgui = require('imgui');
local defaults, setup, layout = require('ui.defaults'), require('ui.setup_defaults'), require('ui.layout');
local hud = require('ui.hud');
-- The scene is built on the first frame, once the screen has its size.
local width, height, chat, corner, settings, view;
local now, passed = 100, nil;
local function build()
    local screen = imgui.GetIO().DisplaySize;
    width, height = math.floor(screen.x), math.floor(screen.y);
    chat, corner = layout.chat_area(width, height), layout.native_corner(width, height);
    settings = defaults.make();
    setup.place_fresh(settings, { width = width, height = height });
    view = hud.sample(now);
    view.notices = {};
    for index = 1, 4 do view.notices[index] = { visual = true, ends = now + 3, message = 'Notice ' .. index .. ' wears off in 10 seconds' }; end;
end;

local next_pos, next_size, windows = nil, nil, {};
local set_pos, set_size, begin = imgui.SetNextWindowPos, imgui.SetNextWindowSize, imgui.Begin;
imgui.SetNextWindowPos = function(position, ...) next_pos = position; return set_pos(position, ...); end;
imgui.SetNextWindowSize = function(size, ...) next_size = size; return set_size(size, ...); end;
imgui.Begin = function(name, ...)
    if next_pos and next_size then windows[#windows + 1] = { name = name, x = next_pos[1], y = next_pos[2], width = next_size[1], height = next_size[2] }; end;
    next_pos, next_size = nil, nil;
    return begin(name, ...);
end;
local function overlap(a, b)
    return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height;
end;

return function()
    if not settings then build(); end;
    for index = #windows, 1, -1 do windows[index] = nil; end;
    hud.draw(view, settings, now, { shift = false });
    if PREVIEW.frame == 3 then
        local all = { { name = 'chat log', x = chat.x, y = chat.y, width = chat.width, height = chat.height },
            { name = 'game party list and target window', x = corner.x, y = corner.y, width = corner.width, height = corner.height } };
        local names = {};
        for _, window in ipairs(windows) do all[#all + 1] = window; names[window.name] = true; end;
        assert(names['##vantage_notices'] and names['##vantage_self_buffs'], 'The notices and the timer panels are drawn.');
        -- The chat log and the game's windows are not checked against each other.
        for i = 1, #all do
            for j = math.max(i + 1, 3), #all do
                local a, b = all[i], all[j];
                assert(not overlap(a, b),
                    string.format('%s and %s overlap on a %d x %d screen', a.name, b.name, width, height));
            end;
        end;
        passed = string.format('fresh layout ok %dx%d: %d windows clear of each other, the chat log and the game windows', width, height,
            #windows);
    end;
    -- The preview prints the last frame's log lines only.
    if PREVIEW.frame == PREVIEW.last_frame and passed then PREVIEW.log(passed); end;
end;
