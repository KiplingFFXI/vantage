-- Samples over the settings window (resize.sample_list). While the settings window is open and a display shows
-- samples, it draws on the foreground draw list, clipped as its own window clips, so the window can't hide it. The one
-- the mouse is over stays on its own window's list, every frame the mouse is on it, so the settings under it and its
-- tooltip show; so does one whose SAMPLE tag the mouse is on, and one under a tooltip or list of the settings window.
-- With the window closed, for real content and in edit mode, each display draws in its own window. That drawing
-- samples over the window makes nothing per frame is in test_element_draw_allocation.lua.
local imgui = require('imgui');
local defaults, hud, fonts = require('ui.defaults'), require('ui.hud'), require('ui.fonts');
local elements, resize = require('ui.elements'), require('ui.resize');
local rolls = require('core.rolls');
MOCK.screen = { 1920, 1080 };
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);

-- The windows' list, each call tagged with the window it went into, and the foreground's; a call keeps a copy of the
-- tables it was given, which the callers refill. A window clips 1 px inside its edges, as a window with a border does;
-- clips holds each window's.
local window_name, next_pos, next_size, clip, clips = nil, { 0, 0 }, { 0, 0 }, { 0, 0, 0, 0 }, {};
local function recorder()
    return setmetatable({ calls = {} }, { __index = function(_, method)
        return function(self, ...)
            local call = MOCK.copy_arguments(...);
            call.method, call.window = method, window_name;
            self.calls[#self.calls + 1] = call;
        end;
    end });
end;
local window_list, foreground = recorder(), recorder();
window_list.GetClipRectMin = function() return clip[1], clip[2]; end;
window_list.GetClipRectMax = function() return clip[3], clip[4]; end;
for name, fn in pairs({
    GetWindowDrawList = function() return window_list; end,
    GetForegroundDrawList = function() return foreground; end,
    SetNextWindowPos = function(pos) next_pos[1], next_pos[2] = pos[1], pos[2]; end,
    SetNextWindowSize = function(size) next_size[1], next_size[2] = size[1], size[2]; end,
    Begin = function(name)
        window_name = name;
        clip[1], clip[2], clip[3], clip[4] = next_pos[1] + 1, next_pos[2] + 1, next_pos[1] + next_size[1] - 1, next_pos[2] + next_size[2] - 1;
        clips[name] = { clip[1], clip[2], clip[3], clip[4] };
        return true;
    end,
    End = function() window_name = nil; end,
}) do rawset(imgui, name, fn); end
-- Every text drawn, with the list and window it went to, through the fonts or straight to a list.
local painted = {};
local plain_draw = fonts.draw;
fonts.draw = function(list, face, value, ...)
    painted[#painted + 1] = { list = list, window = window_name, text = value };
    return plain_draw(list, face, value, ...);
end;
local function texts(list, window)
    local out = {};
    for _, call in ipairs(list.calls) do
        if call.method == 'AddText' and call.window == window and type(call[5]) == 'string' then out[#out + 1] = call[5]; end;
    end;
    for _, entry in ipairs(painted) do
        if entry.list == list and entry.window == window then out[#out + 1] = entry.text; end;
    end;
    return '|' .. table.concat(out, '|') .. '|';
end;
-- How many draw calls a list took for a window, clip pushes and pops left out.
local function draws(list, window)
    local count = 0;
    for _, call in ipairs(list.calls) do
        if call.window == window and call.method ~= 'PushClipRect' and call.method ~= 'PopClipRect' then count = count + 1; end;
    end;
    return count;
end;
-- A window's draws on the foreground start with its own clip, pushed without the screen's, and every clip pushed for
-- it is popped.
local function mirrored(window)
    local pushes, pops, first = 0, 0, nil;
    for _, call in ipairs(foreground.calls) do
        if call.window == window then
            first = first or call;
            if call.method == 'PushClipRect' then pushes = pushes + 1; elseif call.method == 'PopClipRect' then pops = pops + 1; end;
        end;
    end;
    local own = clips[window];
    assert(first and first.method == 'PushClipRect' and first[3] == false and first[1][1] == own[1] and first[1][2] == own[2]
        and first[2][1] == own[3] and first[2][2] == own[4], window .. ' is clipped on the foreground as its window clips.');
    return pushes == pops;
end;
local function tooltip()
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'BeginTooltip' then return true; end; end;
    return false;
end;

local s = defaults.tidy(defaults.make());
for _, panel in pairs(s.panels) do panel.enabled = false; end;
s.window.open, s.window.x, s.window.y, s.window.width, s.window.height = true, 543, 101, 960, 680;
local view = hud.sample(100);
view.context = view.context or {};
local callbacks = {};
local function frame()
    window_list.calls, foreground.calls, painted, MOCK.imgui_calls = {}, {}, {}, {};
    resize.frame(); elements.frame();
    hud.draw(view, s, 100, callbacks);
end;
local function mouse(x, y) MOCK.mouse_x, MOCK.mouse_y = x, y; end;

-- The Phantom Roll display at its fresh spot, which the settings window at 543, 101 mostly covers.
s.rolls.enabled, s.rolls.preview = true, true;
mouse(-1, -1);
frame();
local roll = elements.drawn('rolls');
assert(roll and roll.x == 1300 and roll.y == 300, 'Fixture: the roll display at its fresh spot.');
local over = texts(foreground, '##vantage_rolls');
assert(over:find('|Chaos Roll|', 1, true) and over:find('Sample', 1, true) and over:find('|SAMPLE|', 1, true),
    'With the window open the roll samples and their tag go over it: ' .. over);
assert(draws(window_list, '##vantage_rolls') == 0, 'Nothing of the roll samples stays behind the window.');
assert(mirrored('##vantage_rolls'), 'The foreground clip is the roll window\'s, pushed and popped once.');

-- The mouse on the sample, inside the settings window: the sample steps back so the settings under it show and take
-- the click, and stays back every frame the mouse is on it.
mouse(1300, 330);
for _ = 1, 3 do
    frame();
    assert(draws(foreground, '##vantage_rolls') == 0 and texts(window_list, '##vantage_rolls'):find('|Chaos Roll|', 1, true),
        'The sample under the mouse draws in its own window, every frame.');
    assert(not tooltip(), 'Over the settings window no tooltip opens.');
end;
-- The mouse on the part the window leaves bare: the tooltip opens over the sample, which is in its own window, under
-- every tooltip.
mouse(1530, 330);
for _ = 1, 3 do
    frame();
    assert(draws(foreground, '##vantage_rolls') == 0 and texts(window_list, '##vantage_rolls'):find('|Chaos Roll|', 1, true),
        'The sample under the mouse stays in its own window.');
    assert(tooltip(), 'Its tooltip opens.');
end;
-- The mouse moves off: back over the window.
mouse(1000, 900);
frame();
assert(texts(foreground, '##vantage_rolls'):find('|Chaos Roll|', 1, true) and draws(window_list, '##vantage_rolls') == 0,
    'Off the sample, it goes back over the window.');

-- A tooltip or list of the settings window, drawn before the displays as the host draws it, over the sample: the
-- sample steps back for each Present the window draws one there, so the help of a control beside it reads in full.
-- At 1200, 436 the mouse is on the What it shows heading, left of the sample; its tooltip opens over the sample.
local skin = require('ui.client_skin');
local function settings_draws(kind, x, y, width, height)
    rawset(imgui, 'GetWindowPos', function() return x, y; end);
    rawset(imgui, 'GetWindowSize', function() return width, height; end);
    skin.menu(imgui, nil, kind);
    rawset(imgui, 'GetWindowPos', nil);
    rawset(imgui, 'GetWindowSize', nil);
end;
local function rolls_back() return draws(foreground, '##vantage_rolls') == 0 and texts(window_list, '##vantage_rolls'):find('|Chaos Roll|', 1, true); end;
local function rolls_over() return draws(window_list, '##vantage_rolls') == 0 and texts(foreground, '##vantage_rolls'):find('|Chaos Roll|', 1, true); end;
mouse(1200, 436);
for _ = 1, 3 do
    settings_draws('tooltip', 1226, 447, 364, 66);
    frame();
    assert(rolls_back(), 'Under a settings tooltip the sample stays in its own window, every frame.');
end;
settings_draws('tooltip', 600, 200, 300, 60);
frame();
assert(rolls_over(), 'A tooltip away from the sample leaves it over the window.');
frame();
assert(rolls_over(), 'The Present the window draws no tooltip, the sample is back over the window.');
settings_draws('popup', 1100, 420, 220, 200);
frame();
assert(rolls_back(), 'Under an open list of the settings window the sample steps back.');
rawset(imgui, 'IsPopupOpen', function() return true; end);
settings_draws('popup', 600, 420, 220, 200);
frame();
assert(rolls_over(), 'An open list away from the sample leaves it over the window.');
frame();
assert(rolls_back(), 'A list the settings window opened that is not known here, such as a color picker, steps every sample back.');
rawset(imgui, 'IsPopupOpen', nil);
frame();
assert(rolls_over(), 'With no list open the sample is over the window again.');
mouse(1000, 900);

-- The window closed: in its own window.
s.window.open = false;
frame();
assert(texts(window_list, '##vantage_rolls'):find('|Chaos Roll|', 1, true) and #foreground.calls == 0, 'Window closed: its own window.');
s.window.open = true;
-- Edit mode keeps every display under its outlines and bar.
callbacks.editing = true;
frame();
assert(texts(window_list, '##vantage_rolls'):find('|Chaos Roll|', 1, true) and draws(foreground, '##vantage_rolls') == 0,
    'Edit mode: its own window.');
callbacks.editing = nil;
-- A real roll is never drawn over the window.
s.rolls.preview = false;
local self_id, ally = 1001, 1002;
local snapshot = { valid = true, id = self_id, zone = 102, name = 'Tester', level = 75, job = 17,
    party = { { id = ally, name = 'Ally', scope = 'party', zone = 102, slot = 1 } },
    entities = { [self_id] = { id = self_id, index = 0x400, name = 'Tester', kind = 'player' } } };
local watch = rolls.new();
watch:observe({ kind = 'roll', entity_id = self_id, ability = 105, total = 4, targets = { self_id, ally }, results = { 'got', 'none' } }, 99);
view.rolls = watch:refresh(100, s, snapshot, {});
frame();
assert(texts(window_list, '##vantage_rolls'):find('|Chaos Roll|', 1, true) and not texts(window_list, '##vantage_rolls'):find('Sample', 1, true)
    and draws(foreground, '##vantage_rolls') == 0, 'A real roll draws in its own window: ' .. texts(window_list, '##vantage_rolls'));
view.rolls = nil;
s.rolls.enabled = false;

-- The pet display and the party cooldown list, the same way.
s.pet.enabled, s.pet.preview = true, true;
s.party_cooldowns.enabled, s.party_cooldowns.list.enabled, s.party_cooldowns.preview = true, true, true;
s.party_cooldowns.list.x, s.party_cooldowns.list.y = 600, 400;
mouse(-1, -1);
frame();
assert(texts(foreground, '##vantage_pet'):find('Sample pet', 1, true) and draws(window_list, '##vantage_pet') == 0 and mirrored('##vantage_pet'),
    'Pet samples go over the window: ' .. texts(foreground, '##vantage_pet'));
assert(texts(foreground, '##vantage_cooldowns'):find('Party cooldowns  /  Sample', 1, true) and draws(window_list, '##vantage_cooldowns') == 0
    and mirrored('##vantage_cooldowns'), 'Party cooldown samples go over the window: ' .. texts(foreground, '##vantage_cooldowns'));
local list_rect = elements.drawn('cooldown_list');
mouse(list_rect.x + 10, list_rect.y + 10);
frame();
assert(draws(foreground, '##vantage_cooldowns') == 0 and texts(window_list, '##vantage_cooldowns'):find('Party cooldowns', 1, true),
    'The cooldown list under the mouse steps back.');
assert(texts(foreground, '##vantage_pet'):find('Sample pet', 1, true), 'The pet samples, not under the mouse, stay over the window.');
local pet_rect = elements.drawn('pet');
mouse(pet_rect.x + 10, pet_rect.y + 10);
frame();
assert(draws(foreground, '##vantage_pet') == 0 and texts(window_list, '##vantage_pet'):find('Sample pet', 1, true), 'The pet under the mouse steps back.');
s.pet.preview, s.party_cooldowns.preview = false, false;
mouse(-1, -1);
frame();
assert(#foreground.calls == 0, 'With their samples off nothing goes over the window.');
s.pet.enabled, s.party_cooldowns.enabled = false, false;

-- Timer and recast panels with samples on: each panel goes over the window but the one under the mouse.
for _, key in ipairs({ 'self_buffs', 'target' }) do
    local p = s.panels[key];
    p.enabled, p.mode, p.show_heading = true, 'bars', true;
end;
s.preview = true;
frame();
local buffs = texts(foreground, '##vantage_self_buffs') .. texts(foreground, '##vantage_target');
assert(buffs:find('Self buffs  /  Sample', 1, true) and buffs:find('Target timers  /  Sample', 1, true), 'Sample panels go over the window: ' .. buffs);
assert(draws(window_list, '##vantage_self_buffs') == 0 and draws(window_list, '##vantage_target') == 0
    and mirrored('##vantage_self_buffs') and mirrored('##vantage_target'), 'Nothing of them stays behind.');
local panel = elements.drawn('self_buffs');
mouse(panel.x + 10, panel.y + 10);
frame();
assert(draws(foreground, '##vantage_self_buffs') == 0 and texts(window_list, '##vantage_self_buffs'):find('Self buffs  /  Sample', 1, true),
    'The panel under the mouse steps back.');
assert(texts(foreground, '##vantage_target'):find('Target timers  /  Sample', 1, true), 'The other stays over the window.');
mouse(-1, -1);
-- An icon panel's SAMPLE tag goes with it.
s.panels.self_buffs.mode = 'icons';
frame();
assert(texts(foreground, '##vantage_self_buffs'):find('|SAMPLE|', 1, true) and draws(window_list, '##vantage_self_buffs') == 0,
    'An icon panel and its tag go over the window.');
-- The tag sits just above the panel, outside its rect: the mouse on it steps the panel back, so the tag doesn't cover
-- the settings under it.
panel = elements.drawn('self_buffs');
mouse(panel.x + panel.width - 10, panel.y - 8);
frame();
assert(draws(foreground, '##vantage_self_buffs') == 0 and texts(window_list, '##vantage_self_buffs'):find('|SAMPLE|', 1, true),
    'The mouse on the SAMPLE tag steps the panel back.');
mouse(panel.x + panel.width - 10, panel.y - 30);
frame();
assert(texts(foreground, '##vantage_self_buffs'):find('|SAMPLE|', 1, true), 'Above the tag the panel is over the window again.');
mouse(-1, -1);
s.panels.self_buffs.mode = 'bars';
-- Live panels show real content: in their own windows.
s.preview = false;
frame();
assert(#foreground.calls == 0 and draws(window_list, '##vantage_self_buffs') > 0, 'Live panels draw in their own windows.');
s.preview = true;
s.window.open = false;
frame();
assert(#foreground.calls == 0 and draws(window_list, '##vantage_self_buffs') > 0, 'Window closed: their own windows.');
s.window.open = true;
callbacks.editing = true;
frame();
assert(#foreground.calls == 0 and draws(window_list, '##vantage_self_buffs') > 0, 'Edit mode: their own windows.');
callbacks.editing = nil;

s.panels.self_buffs.enabled, s.panels.target.enabled, s.preview = false, false, false;

-- The party list strips: their samples go over the window when the host says the window is open outside edit mode.
local party_defaults, overlay = require('ui.party_defaults'), require('ui.native_party_hud');
local config = party_defaults.make();
config.enabled, config.locked, config.include_self, config.preview = true, true, true, true;
local roster = { valid = true, id = 1001, zone = 230, members = {} };
local game = { available = true, groups = { { x = 1300, y = 300, width = 200, height = 6 * 30, rows = {} } } };
for i, name in ipairs({ 'Aster', 'Bramble', 'Cinder', 'Dawn', 'Elm', 'Fable' }) do
    local member = { id = 1000 + i, index = 1023 + i, slot = i - 1, group = 1, name = name, zone = 230, active = true,
        job = 5, level = 75, known = true, available = true };
    roster.members[i] = member;
    game.groups[1].rows[member.slot] = { x = 1300, y = 300 + member.slot * 30, width = 200, height = 30, slot = member.slot };
end;
local strip_callbacks = { native_geometry = game, global_style = s.style, samples_over = true };
local function strips()
    window_list.calls, foreground.calls, painted, MOCK.imgui_calls = {}, {}, {}, {};
    resize.frame(); elements.frame();
    overlay.draw(roster, {}, config, 100, strip_callbacks);
end;
strips();
assert(draws(foreground, '##vantage_native_1') > 0 and draws(window_list, '##vantage_native_1') == 0 and mirrored('##vantage_native_1'),
    'Party list samples go over the window.');
local strip = elements.drawn('strip_1');
mouse(strip.x + 2, strip.y + 2);
strips();
assert(draws(foreground, '##vantage_native_1') == 0 and draws(window_list, '##vantage_native_1') > 0, 'The strip under the mouse steps back.');
mouse(-1, -1);
strip_callbacks.samples_over = nil;
strips();
assert(draws(foreground, '##vantage_native_1') == 0 and draws(window_list, '##vantage_native_1') > 0, 'Window closed or edit mode: its own window.');
strip_callbacks.samples_over, config.preview = true, false;
strips();
assert(draws(foreground, '##vantage_native_1') == 0, 'Real party effects are never drawn over the window.');

fonts.draw = plain_draw;
return 'Samples go over the open settings window, but the one under the mouse';
