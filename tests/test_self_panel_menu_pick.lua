-- Replace the game's buff icons, as the app and the self panels run it. The game side (core/game_buffs.lua) is a
-- stand-in here, and test_game_buffs.lua covers the real one. Each Present asks for the replacement only while its
-- tick is on, both self panels are on, no samples show and the displays aren't hidden. What the game's + menu is on
-- gets a cursor on Vantage's own icon, or its name in a line when no self panel shows it. What the game side has to
-- say is said once, and an unload puts everything back.
local wants, releases = {}, 0;
local pick, notice, broken, unclean;
package.loaded['core.game_buffs'] = {
    update = function(want)
        wants[#wants + 1] = want;
        if broken then error(broken, 0); end
        local said = notice;
        notice = nil;
        return want and pick or nil, said;
    end,
    release = function()
        releases = releases + 1;
        if unclean then return false, unclean; end
        return true;
    end,
    status = function() return { on = wants[#wants] == true, moved = 0, returned = 0 }; end,
    problem = function() return nil; end,
};
local h = require('self_panel_fixture')();
local imgui = require('imgui');
rawset(imgui, 'GetForegroundDrawList', function() return imgui.GetWindowDrawList(); end);
local s = h.settings;
local function last() return MOCK.printed[#MOCK.printed]; end
local function command(text) local event = { command = text }; MOCK.fire('command', event); assert(event.blocked); end

-- Protect and Shell on Self buffs, Poison on Self debuffs.
h.both({ 40, 41, 3 });
local record = h.run(3);
assert(record.icons[40] == 1 and record.icons[41] == 1 and record.icons[3] == 1, 'Fixture: the three effects show: ' .. h.describe(record.icons));

-- It starts off, and off nothing asks for the replacement.
assert(s.replace_game_buffs == false and require('ui.defaults').make().replace_game_buffs == false, 'The tick starts off.');
for _, want in ipairs(wants) do assert(want == false, 'With the tick off the game draws its own icons.'); end
local function asked()
    h.frame();
    return wants[#wants];
end
s.replace_game_buffs = true;
assert(asked() == true, 'With the tick on and both self panels on, the game\'s icons are replaced.');
-- Each of these gives the game's icons back, and taking it away replaces them again.
for name, change in pairs({
    ['Self buffs off'] = { function() s.panels.self_buffs.enabled = false; end, function() s.panels.self_buffs.enabled = true; end },
    ['Self debuffs off'] = { function() s.panels.self_debuffs.enabled = false; end, function() s.panels.self_debuffs.enabled = true; end },
    ['the timer panels off'] = { function() s.enabled = false; end, function() s.enabled = true; end },
    ['samples'] = { function() s.preview = true; end, function() s.preview = false; end },
    ['/vg hide'] = { function() command('/vg hide'); end, function() command('/vg show'); end },
    ['the tick off'] = { function() s.replace_game_buffs = false; end, function() s.replace_game_buffs = true; end },
}) do
    change[1]();
    assert(asked() == false, name .. ' gives the game\'s icons back.');
    change[2]();
    assert(asked() == true, 'After ' .. name .. ' they are replaced again.');
end
-- Panels hidden by your own rules, as on the map, keep the game's icons hidden with them.
local client = require('core.client');
local read, visibility = client.read, client.visibility;
client.read = function(...)
    local snapshot = read(...);
    snapshot.map = true;
    return snapshot;
end;
client.visibility = function(snapshot)
    local out = visibility(snapshot);
    if out then out.map = true; end
    return out;
end;
h.app.refresh(MOCK.now);
record = h.frame();
assert(s.visibility.hide_map == true and h.count(record.icons) == 0, 'Fixture: on the map the panels are hidden.');
assert(wants[#wants] == true, 'Hidden on the map by your own rule, the game\'s icons stay hidden too.');
client.read, client.visibility = read, visibility;
h.app.refresh(MOCK.now);
record = h.frame();
assert(h.count(record.icons) == 3, 'Fixture: off the map the panels are back.');

-- The corners of a status icon's picture and of every box drawn in a frame.
local function drawn(record_calls, effect)
    local picture, boxes = nil, {};
    for _, call in ipairs(record_calls) do
        local copy = MOCK.drawn[call];
        if call[1] == 'draw:AddImage' and call[2] == 5000 + effect then picture = { copy[3][1], copy[3][2], copy[4][1], copy[4][2] }; end
        if call[1] == 'draw:AddRect' then boxes[#boxes + 1] = { copy[2][1], copy[2][2], copy[3][1], copy[3][2] }; end
    end
    return picture, boxes;
end
local function boxed(effect)
    local picture, boxes = drawn(MOCK.imgui_calls, effect);
    if not picture then return false; end
    for _, box in ipairs(boxes) do
        if box[1] == picture[1] and box[2] == picture[2] and box[3] == picture[3] and box[4] == picture[4] then return true; end
    end
    return false;
end
local function line(texts)
    for _, text in ipairs(texts) do if text:find('^%+ menu: ') then return text; end end
end

-- No + menu open: no cursor and no line.
record = h.frame();
assert(not boxed(40) and not boxed(41) and not boxed(3) and line(record.texts) == nil, 'With the + menu shut there is no cursor.');
-- The + menu on Shell: the cursor is on Vantage's Shell, and on nothing else.
pick = { effect = 41, can_cancel = true };
record = h.frame();
assert(boxed(41) and not boxed(40) and not boxed(3) and line(record.texts) == nil, 'The cursor is on Shell.');
-- On Poison, which sits on Self debuffs.
pick.effect, pick.can_cancel = 3, false;
record = h.frame();
assert(boxed(3) and not boxed(41) and not boxed(40) and line(record.texts) == nil, 'The cursor is on Poison, on Self debuffs.');
-- Shut again.
pick = nil;
h.frame();
assert(not boxed(3), 'With the + menu shut again the cursor is gone.');

-- An effect a self panel hides has no icon to take the cursor, so its name shows in a line.
s.panels.self_buffs.exclude[41] = true;
h.app.refresh(MOCK.now);
pick = { effect = 41, can_cancel = true };
record = h.frame();
assert(record.icons[41] == nil, 'Fixture: Shell is hidden on Self buffs.');
local name = require('core.catalog').get(41).name;
assert(line(record.texts) == '+ menu: ' .. name and not boxed(40) and not boxed(3), 'A hidden effect shows by name: ' .. tostring(line(record.texts)));
pick.effect = 40;
record = h.frame();
assert(boxed(40) and line(record.texts) == nil, 'On Protect the cursor is back on an icon and the line is gone.');
s.panels.self_buffs.exclude[41] = nil;
-- In list form the cursor boxes the whole row: one box more than the same frame draws with the + menu shut, and it
-- holds the row's icon.
local function box_count()
    local total = 0;
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'draw:AddRect' then total = total + 1; end end
    return total;
end
s.panels.self_buffs.mode = 'bars';
h.app.refresh(MOCK.now);
pick = nil;
h.run(2);
local plain = box_count();
pick = { effect = 40, can_cancel = true };
record = h.frame();
local picture, boxes = drawn(MOCK.imgui_calls, 40);
local around = false;
for _, box in ipairs(boxes) do
    if picture and box[1] <= picture[1] and box[2] <= picture[2] and box[3] > picture[3] and box[4] >= picture[4] then around = true; end
end
assert(picture and around and box_count() == plain + 1 and line(record.texts) == nil, 'In bars the cursor boxes Protect\'s row.');
s.panels.self_buffs.mode = 'icons';
h.app.refresh(MOCK.now);

-- Copy Image's shadows are one effect on Vantage's panels, so the + menu on a shadow icon is on it.
h.both({ 445 });
record = h.run(3);
pick = { effect = 445, can_cancel = true };
record = h.frame();
local shadow;
for effect in pairs(record.icons) do shadow = effect; end
assert(shadow and boxed(shadow) and line(record.texts) == nil, 'The cursor is on Copy Image: ' .. h.describe(record.icons));
pick = nil;

-- Samples aren't your effects, so they take no cursor.
h.both({ 40, 41, 3 });
h.run(3);
s.preview = true;
pick = { effect = 40, can_cancel = true };
record = h.frame();
assert(wants[#wants] == false and line(record.texts) == nil, 'Samples take no cursor.');
s.preview = false;
pick = nil;
h.frame();

-- What the game side says is said once, by the Present that heard it.
local count = #MOCK.printed;
local STOP = 'Vantage could not move the game\'s buff menu off screen, so the game draws its own buff icons again.';
notice = STOP;
h.frame();
assert(#MOCK.printed == count + 1 and last():find(STOP, 1, true), 'A stop is said: ' .. tostring(last()));
h.frame();
assert(#MOCK.printed == count + 1, 'and only once.');
-- A game side that raises an error is said once, and the frame goes on.
broken = 'boom';
count = #MOCK.printed;
record = h.frame();
h.frame();
assert(#MOCK.printed == count + 1 and last():find('The game\'s buff icons could not be replaced. boom', 1, true), 'An error is said once: ' .. tostring(last()));
assert(record.icons[40] == 1, 'and the panels still draw.');
broken = nil;

-- The tick is the character's own: no profile carries it, and no import changes it.
local profiles, share = require('core.profiles'), require('core.share');
assert(profiles.capture(s).replace_game_buffs == nil, 'A profile doesn\'t carry it.');
local text = assert(share.export(s, 'profile', nil, 'Tester'));
local payload = assert(share.read(text));
assert(payload.data.replace_game_buffs == nil, 'An export doesn\'t carry it.');
for _, mode in ipairs({ 'replace', 'add' }) do
    local candidate = assert(share.candidate(s, payload, mode));
    assert(candidate.replace_game_buffs == true, 'An import by ' .. mode .. ' keeps yours.');
end
-- Not even a string made by hand to carry it changes yours, on or off.
payload.data.replace_game_buffs = false;
assert(assert(share.candidate(s, payload, 'replace')).replace_game_buffs == true, 'A string that says off leaves yours on.');
payload.data.replace_game_buffs = true;
s.replace_game_buffs = false;
assert(assert(share.candidate(s, payload, 'add')).replace_game_buffs == false and assert(share.candidate(s, payload, 'replace')).replace_game_buffs == false,
    'A string that says on leaves yours off.');
s.replace_game_buffs = true;
payload.data.replace_game_buffs = nil;

-- The cursor only goes on the self panels. Poison on a party member, on Party members' timers, takes none, so the +
-- menu on your own Poison that no self panel shows still gets its line.
do
    local view = h.hud.sample(MOCK.now);
    local function shown(effect)
        MOCK.imgui_calls = {};
        h.hud.draw(view, s, MOCK.now, { menu_pick = effect and { effect = effect, can_cancel = false } or nil });
        local texts = {};
        for _, call in ipairs(MOCK.imgui_calls) do
            if call[1] == 'draw:AddText' and type(call[6]) == 'string' then texts[#texts + 1] = call[6]; end
        end
        return box_count(), line(texts);
    end
    s.panels.party.enabled = true;
    local boxes_shut = shown(nil);
    local boxes_poison, poison_line = shown(3);
    assert(poison_line == '+ menu: ' .. require('core.catalog').get(3).name and boxes_poison == boxes_shut + 1,
        'Another panel\'s Poison takes no cursor: ' .. tostring(poison_line));
    local boxes_own, own_line = shown(4);
    assert(own_line == nil and boxes_own == boxes_shut + 1, 'Your own Paralysis takes it on Self debuffs.');
    s.panels.party.enabled = false;
end
-- /vg set and /vg get reach it.
command('/vg set replace_game_buffs false');
assert(h.app.state.settings.replace_game_buffs == false, '/vg set turns it off.');
command('/vg set replace_game_buffs true');
assert(h.app.state.settings.replace_game_buffs == true, '/vg set turns it on.');
-- A value that is no true or false falls back to off.
local tidied = require('ui.defaults').tidy({ replace_game_buffs = 'yes' });
assert(tidied.replace_game_buffs == false, 'Only true or false is kept.');

-- An unload puts everything back, and says so when it couldn't.
unclean = 'Vantage could not put the game\'s buff drawing back. Restart the game to get its buff icons back.';
count = #MOCK.printed;
MOCK.fire('unload');
assert(releases == 1 and #MOCK.printed == count + 1 and last():find(unclean, 1, true), 'An unload that can\'t put it back says so: ' .. tostring(last()));
unclean = nil;
count = #MOCK.printed;
MOCK.fire('unload');
assert(releases == 2 and #MOCK.printed == count, 'A clean unload says nothing.');
return 'Replace the game\'s buff icons on the self panels';
