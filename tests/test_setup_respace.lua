-- Fresh displays start apart (alert notices start at the top right), and Apply size or Apply setup re-spaces the
-- timer panels and alert notices that are still where they started. Loading never moves anything, and anything the
-- player moved stays. The party list strips follow the game's party list, so they change nothing of it.
local defaults, presets, setup = require('ui.defaults'), require('setup_fixture'), require('ui.setup_defaults');
local hud = require('ui.hud');
local copy, equal = require('core.store').copy, require('core.customization').equal;

local fresh = defaults.make();
assert(fresh.alerts.notice_x == 985 and fresh.alerts.notice_y == 10, 'Fresh alert notices start at the top right.');

-- Loading keeps every saved value.
local saved = defaults.tidy({ alerts = { notice_x = 400, notice_y = 40 },
    panels = { party = { mode = 'icons' }, self_debuffs = { x = 355, y = 120 } } });
assert(saved.alerts.notice_x == 400 and saved.alerts.notice_y == 40 and saved.panels.party.mode == 'icons',
    'Saved positions and choices load as they are.');

-- The chat log is out of the way here, in the top left corner: test_fresh_chat_layout checks what it does.
local corner = { x = 0, y = 0, width = 1, height = 1, windows = {} };
local function options(size, width, height)
    return { size = size, skin = 'keep', matching = false, window_type = 1, screen_width = width, screen_height = height,
        chat = corner };
end;
local function applied(s, size, width, height)
    assert(presets.apply(s, options(size, width, height)), 'The setup applies: ' .. size);
    return s;
end;
local function positions(s)
    local out = { notice = { s.alerts.notice_x, s.alerts.notice_y } };
    for _, id in ipairs(defaults.panel_order) do out[id] = { s.panels[id].x, s.panels[id].y }; end;
    return out;
end;
local function overlap(a, b)
    return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height;
end;
-- One row of every panel at the size applied. A panel turned off that found no room keeps its fresh spot; those
-- are left out, as nothing draws them.
local function boxes(s, width, height)
    local out, start = {}, defaults.make().panels;
    for _, id in ipairs(defaults.panel_order) do
        local p = s.panels[id];
        local stuck = not defaults.panel_enabled(s, id) and p.x == start[id].x and p.y == start[id].y;
        if id ~= 'recasts' and not stuck then
            local r = hud.bounds(p, s.style, 1, width, height);
            out[#out + 1] = { id = id, x = p.x, y = p.y, width = p.width, height = r.height };
        end;
    end;
    return out;
end;

-- At its own size a fresh layout is already apart, so Apply size 1x leaves what shows where it is. The panels
-- that are off take the spots a fresh install's first frame gives them: Apply size lands where it lands from that
-- first frame. Item recasts, also off, moves: room for four notices reaches over its fresh spot.
local s = applied(defaults.tidy(defaults.make()), 'minimal', 1920, 1080);
local first = defaults.make();
setup.place_fresh(first, { width = 1920, height = 1080, chat = corner });
local kept_spots, fresh_spots = positions(s), positions(defaults.make());
local item = kept_spots.item_recasts;
assert(equal(kept_spots, positions(applied(first, 'minimal', 1920, 1080))), "1x puts the panels where it puts a fresh install's.");
for _, id in ipairs({ 'self_buffs', 'self_debuffs', 'target', 'notice' }) do
    assert(equal(kept_spots[id], fresh_spots[id]), '1x keeps the fresh spot: ' .. id);
end;
local four = { x = s.alerts.notice_x, y = s.alerts.notice_y, width = 440, height = 9 * 19 };
assert(not overlap({ x = item[1], y = item[2], width = 300, height = 47 }, four), 'Item recasts moves clear of four notices.');

-- At 2x the fresh 315 px pitch would overlap 600 px panels: they flow onto a wider grid and wrap at the edge.
for _, screen in ipairs({ { 1920, 1080 }, { 1600, 900 } }) do
    local spots = {};
    for _, party_on in ipairs({ false, true }) do
        s = defaults.tidy(defaults.make());
        s.party_ui.enabled = party_on;
        -- The re-spacing keeps room for as many notices as can show at once; these checks are for two.
        s.alerts.max_notices = 2;
        local before = copy(s);
        applied(s, 'minimal_2x', screen[1], screen[2]);
        local list = boxes(s, screen[1], screen[2]);
        spots[party_on] = positions(s);
        if party_on then
            assert(equal(spots[false], spots[true]), 'With the party list strips off, the panels and notices go where they go with them on, on '
                .. screen[1] .. ' x ' .. screen[2]);
        end;
        for i = 1, #list do
            local a = list[i];
            assert(a.x >= 0 and a.y >= 0 and a.x + a.width <= screen[1], a.id .. ' stays on screen.');
            for j = i + 1, #list do
                local b = list[j];
                local shared = (a.id == 'spell_recasts' and b.id == 'recasts') or (b.id == 'spell_recasts' and a.id == 'recasts');
                assert(shared or not overlap(a, b), a.id .. ' and ' .. b.id .. ' keep apart at 2x on ' .. screen[1] .. ' x ' .. screen[2]);
            end;
        end;
        assert(s.panels.recasts.x == s.panels.spell_recasts.x and s.panels.recasts.y == s.panels.spell_recasts.y,
            'The combined and spell recast panels share their spot.');
        local notice = { x = math.min(s.alerts.notice_x, screen[1] - 880), y = s.alerts.notice_y, width = 880, height = 190 };
        for _, box in ipairs(list) do
            if s.panels[box.id].enabled then assert(not overlap(notice, box), 'The notices keep clear of ' .. box.id); end;
        end;
        for _, id in ipairs(defaults.panel_order) do
            assert(s.panels[id].locked == before.panels[id].locked and s.panels[id].enabled == before.panels[id].enabled,
                'Apply leaves locks and switches alone: ' .. id);
        end;
    end;
end;

-- A spot an earlier apply gave is a starting spot too: 1.5x then 2x lands where 2x does at once, and 1x brings the
-- fresh grid back.
local direct = positions(applied(defaults.tidy(defaults.make()), 'minimal_2x', 1600, 900));
s = applied(applied(defaults.tidy(defaults.make()), 'minimal_1_5x', 1600, 900), 'minimal_2x', 1600, 900);
assert(equal(positions(s), direct), 'Panels an earlier apply placed move on with the next one.');
assert(equal(positions(applied(s, 'minimal', 1600, 900)), positions(applied(defaults.tidy(defaults.make()), 'minimal', 1600, 900))),
    'Back at 1x they return to the grid 1x gives a fresh layout.');

-- What the player moved stays, and the others keep clear of it.
s = defaults.tidy(defaults.make());
s.panels.self_debuffs.x, s.panels.self_debuffs.y = 700, 600;
s.alerts.notice_x, s.alerts.notice_y = 117, 228;
applied(s, 'minimal_2x', 1920, 1080);
assert(s.panels.self_debuffs.x == 700 and s.panels.self_debuffs.y == 600, 'A moved panel stays where it was put.');
assert(s.alerts.notice_x == 117 and s.alerts.notice_y == 228, 'Moved notices stay where they were put.');
local moved_box = { x = 700, y = 600, width = 600, height = hud.bounds(s.panels.self_debuffs, s.style, 1, 1920, 1080).height };
for _, box in ipairs(boxes(s, 1920, 1080)) do
    if box.id ~= 'self_debuffs' then assert(not overlap(moved_box, box), box.id .. ' keeps clear of the moved panel.'); end;
end;

-- With a panel moved before both applies, 1.5x then 2x still lands where 2x does at once: the earlier apply's
-- spots are worked out with the moved panel in the way, as it was then.
for _, moved in ipairs({ 'self_buffs', 'self_debuffs' }) do
    for _, screen in ipairs({ { 1920, 1080 }, { 1600, 900 } }) do
        local function start()
            local value = defaults.tidy(defaults.make());
            value.panels[moved].x, value.panels[moved].y = 1200, 600;
            return value;
        end;
        local once = positions(applied(start(), 'minimal_2x', screen[1], screen[2]));
        s = applied(applied(start(), 'minimal_1_5x', screen[1], screen[2]), 'minimal_2x', screen[1], screen[2]);
        assert(equal(positions(s), once), 'With ' .. moved .. ' moved, two applies land where one does.');
        local shown = boxes(s, screen[1], screen[2]);
        for i = 1, #shown do
            for j = i + 1, #shown do
                assert(not overlap(shown[i], shown[j]), shown[i].id .. ' and ' .. shown[j].id .. ' keep apart after two applies.');
            end;
        end;
    end;
end;
-- A panel moving with another was never flowed, so an earlier apply's spots are worked out without it.
local function attached_start()
    local value = defaults.tidy(defaults.make());
    value.panels.self_debuffs.anchor.to, value.panels.self_debuffs.anchor.element = 'element', 'self_buffs';
    return value;
end;
local once = positions(applied(attached_start(), 'minimal_2x', 1920, 1080));
s = applied(applied(attached_start(), 'minimal_1_5x', 1920, 1080), 'minimal_2x', 1920, 1080);
assert(equal(positions(s), once), 'With a panel attached, two applies land where one does.');
assert(s.panels.self_debuffs.anchor.element == 'self_buffs' and s.panels.self_debuffs.x == fresh.panels.self_debuffs.x
    and s.panels.self_debuffs.y == fresh.panels.self_debuffs.y, 'An attached panel keeps its saved spot through both applies.');
-- A panel moving with the chat log isn't flowed either: it keeps its saved spot and what it moves with.
s = defaults.tidy(defaults.make());
s.panels.self_debuffs.anchor.to = 'chat';
applied(s, 'minimal_2x', 1920, 1080);
assert(s.panels.self_debuffs.anchor.to == 'chat' and s.panels.self_debuffs.x == fresh.panels.self_debuffs.x
    and s.panels.self_debuffs.y == fresh.panels.self_debuffs.y, 'A docked panel keeps its saved spot through Apply size.');

-- Without a screen size there is nothing to fit to, so positions stay as they were.
s = defaults.tidy(defaults.make());
local kept = positions(s);
assert(presets.apply(s, { size = 'minimal_2x', skin = 'keep', matching = false, window_type = 1 }));
assert(equal(positions(s), kept), 'An apply without a screen size moves nothing.');
return 'Fresh displays start apart, and Apply size re-spaces the panels and notices still where they started';
