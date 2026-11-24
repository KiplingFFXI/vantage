-- A display showing samples over the open settings window draws on the foreground draw list, under a clip of its own
-- (resize.sample_list). When its paint fails partway, the error still goes on, but what the foreground list draws
-- after it in the frame isn't cut to that display or to a text box it was drawing. Timer panels with their size labels
-- and SAMPLE tags, the party cooldown list, the Phantom Roll display and the pet display.
local imgui = require('imgui');
local defaults, hud, fonts = require('ui.defaults'), require('ui.hud'), require('ui.fonts');
local elements, resize = require('ui.elements'), require('ui.resize');
MOCK.screen = { 1920, 1080 };
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);

-- The foreground list keeps its clips as ImDrawList does, starting each frame at the whole screen. Other calls draw
-- nothing here.
local SCREEN = { 0, 0, 1920, 1080 };
local foreground = { stack = {}, depth = 0 };
local function top() return foreground.depth > 0 and foreground.stack[foreground.depth] or SCREEN; end
function foreground:PushClipRect(min, max, intersect)
    local x1, y1, x2, y2 = min[1], min[2], max[1], max[2];
    if intersect then
        local t = top();
        x1, y1, x2, y2 = math.max(x1, t[1]), math.max(y1, t[2]), math.min(x2, t[3]), math.min(y2, t[4]);
    end
    self.depth = self.depth + 1;
    self.stack[self.depth] = { x1, y1, x2, y2 };
end
function foreground:PopClipRect()
    assert(self.depth > 0, 'Nothing pops a clip it did not push.');
    self.stack[self.depth], self.depth = nil, self.depth - 1;
end
setmetatable(foreground, { __index = function() return function() end; end });
-- The windows' own list clips 1 px inside the window, as a window with a border does.
local window_name, next_pos, next_size, clip = nil, { 0, 0 }, { 0, 0 }, { 0, 0, 0, 0 };
local window_list = setmetatable({
    GetClipRectMin = function() return clip[1], clip[2]; end,
    GetClipRectMax = function() return clip[3], clip[4]; end,
}, { __index = function() return function() end; end });
for name, fn in pairs({
    GetWindowDrawList = function() return window_list; end,
    GetForegroundDrawList = function() return foreground; end,
    SetNextWindowPos = function(pos) next_pos[1], next_pos[2] = pos[1], pos[2]; end,
    SetNextWindowSize = function(size) next_size[1], next_size[2] = size[1], size[2]; end,
    Begin = function(name)
        window_name = name;
        clip[1], clip[2], clip[3], clip[4] = next_pos[1] + 1, next_pos[2] + 1, next_pos[1] + next_size[1] - 1, next_pos[2] + next_size[2] - 1;
        return true;
    end,
    End = function() window_name = nil; end,
}) do rawset(imgui, name, fn); end

-- A text drawn on the foreground list in the window named fail_window throws, as any error partway through a paint
-- would. fail_text, when set, picks the text.
local plain_draw, fail_window, fail_text, thrown = fonts.draw, nil, nil, false;
fonts.draw = function(list, face, value, ...)
    if fail_window and list == foreground and window_name == fail_window and type(value) == 'string' and value ~= ''
        and (not fail_text or value:find(fail_text, 1, true)) then
        thrown = true;
        error('paint probe', 0);
    end
    return plain_draw(list, face, value, ...);
end;

local s = defaults.tidy(defaults.make());
for _, panel in pairs(s.panels) do panel.enabled = false; end
s.window.open, s.window.x, s.window.y, s.window.width, s.window.height = true, 543, 101, 960, 680;
local view = hud.sample(100);
MOCK.mouse_x, MOCK.mouse_y = -1, -1;
-- held says Shift is held.
local held;
local function frame()
    foreground.stack, foreground.depth, thrown = {}, 0, false;
    resize.frame(); elements.frame();
    return pcall(hud.draw, view, s, 100, { shift = held });
end

local function clip_text(t) return ('[%d,%d..%d,%d]'):format(t[1], t[2], t[3], t[4]); end
-- A good frame, then one whose paint fails in window at the text named, then a good one again.
local function check(label, window, text)
    fail_window, fail_text = nil, nil;
    local ok, why = frame();
    assert(ok, label .. ': a good frame draws: ' .. tostring(why));
    assert(foreground.depth == 0, label .. ': a good frame leaves no clip open.');
    fail_window, fail_text = window, text;
    ok, why = frame();
    fail_window, fail_text = nil, nil;
    assert(thrown and not ok and why == 'paint probe', label .. ': the paint failed and its error went on: ' .. tostring(why));
    local left = top();
    assert(left[1] <= 0 and left[2] <= 0 and left[3] >= 1920 and left[4] >= 1080,
        label .. ': what the foreground list draws after a failed paint is cut to ' .. clip_text(left));
    ok = frame();
    assert(ok and foreground.depth == 0, label .. ': the next frame draws as before.');
end

-- A timer panel, failing in its heading and in a row.
s.panels.self_buffs.enabled, s.panels.self_buffs.mode, s.panels.self_buffs.show_heading = true, 'bars', true;
s.preview = true;
check('Self buffs heading', '##vantage_self_buffs', 'Self buffs');
check('Self buffs row', '##vantage_self_buffs', 'Protect');
-- Shift held on an unlocked panel shows its size label, on the foreground list too with the pointer off the panel and
-- off the settings window. The label has a text box of its own.
s.panels.self_buffs.locked, held = false, true;
check('Self buffs size label', '##vantage_self_buffs', ' px');
s.panels.self_buffs.locked, held = true, nil;
-- An icon panel's SAMPLE tag, failing before it draws.
s.panels.self_buffs.mode = 'icons';
local metrics = require('ui.text_metrics');
local plain_width = metrics.width;
metrics.width = function(face, value, ...)
    if fail_window and window_name == fail_window and value == fail_text then
        thrown = true;
        error('paint probe', 0);
    end
    return plain_width(face, value, ...);
end;
check('Self buffs SAMPLE tag', '##vantage_self_buffs', 'SAMPLE');
metrics.width = plain_width;
s.panels.self_buffs.enabled, s.preview = false, false;

s.party_cooldowns.enabled, s.party_cooldowns.list.enabled, s.party_cooldowns.preview = true, true, true;
s.party_cooldowns.list.x, s.party_cooldowns.list.y = 600, 400;
check('Party cooldowns', '##vantage_cooldowns', 'Party cooldowns');
s.party_cooldowns.enabled, s.party_cooldowns.preview = false, false;

s.rolls.enabled, s.rolls.preview = true, true;
check('Phantom Roll', '##vantage_rolls', 'Double-Up');
s.rolls.enabled, s.rolls.preview = false, false;

s.pet.enabled, s.pet.preview = true, true;
check('Pet', '##vantage_pet', nil);
s.pet.enabled, s.pet.preview = false, false;

fonts.draw = plain_draw;
return true;
